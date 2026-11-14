class_name EnemyState
extends RefCounted
## One enemy in a run (game/main.py `Enemy`). Husks, runners and brutes differ
## only in the `EnemyDefs` numbers and the runner's weave; the spitter adds a
## distance-keeping AI and a charged shot. Holds per-instance state only; the
## type's constants live in `EnemyDefs`.

const HUSK: StringName = EnemyDefs.HUSK
const HUSK_RADIUS: float = EnemyDefs.HUSK_RADIUS
## The runner's weave: sideways pull `sin(t * 5) * 0.5` (prototype `Enemy.update`).
const RUNNER_WEAVE_RATE: float = 5.0
const RUNNER_WEAVE_AMPLITUDE: float = 0.5

var kind: StringName = HUSK
var serial: int = 0
var position: Vector2 = Vector2.ZERO
var velocity: Vector2 = Vector2.ZERO
var radius: float = EnemyDefs.HUSK_RADIUS
var max_hp: float = EnemyDefs.HUSK_HP
var hp: float = EnemyDefs.HUSK_HP
var speed: float = EnemyDefs.HUSK_SPEED
var damage: int = EnemyDefs.HUSK_DAMAGE
## Multiplies the knockback force of every blow (brute resists, runner flies).
var knock_mult: float = EnemyDefs.HUSK_KNOCK
var facing: Vector2 = Vector2.RIGHT
## Seconds of reduced control after a hit (knockback stun).
var stun: float = 0.0
## Cosmetic timers the presentation reads (hit flash and squash).
var flash: float = 0.0
var squash: float = 0.0
var dead: bool = false
## The enemy's own clock (prototype `Enemy.t`): starts at a random phase and
## runs while it lives. Drives the runner's weave and the post-death drift.
var age: float = 0.0
## Spitter only: seconds until it may wind up its next shot (it keeps counting
## down while out of range, so it can fire the moment the player comes close),
## and how long it has been charging the current one.
var shoot_cooldown: float = 0.0
var charge: float = 0.0


static func husk(at: Vector2, wave: int, speed_factor: float, serial_value: int) -> EnemyState:
	return make(EnemyDefs.HUSK, at, wave, speed_factor, serial_value)


## A freshly spawned enemy of any ported type. `speed_factor` is the prototype's
## uniform(0.9, 1.12) draw (times any scenario scale); `phase` its `t` draw.
## `shoot_cooldown_value` is the spitter's starting cooldown (prototype
## uniform(1.5, 3.0)); other types ignore it.
static func make(kind_value: StringName, at: Vector2, wave: int, speed_factor: float, serial_value: int, phase: float = 0.0, shoot_cooldown_value: float = 0.0) -> EnemyState:
	var def: EnemyDefs = EnemyDefs.of(kind_value)
	var enemy: EnemyState = EnemyState.new()
	enemy.kind = kind_value
	enemy.serial = serial_value
	enemy.position = at
	enemy.radius = def.radius
	enemy.max_hp = def.hp * (1.0 + EnemyDefs.HP_PER_WAVE * float(wave - 1))
	enemy.hp = enemy.max_hp
	enemy.speed = def.speed * speed_factor
	enemy.damage = def.damage
	enemy.knock_mult = def.knock
	enemy.age = phase
	enemy.shoot_cooldown = shoot_cooldown_value
	return enemy


## 0..1 progress of a spitter's shot telegraph (0 when it is not winding up).
## Presentation reads it to show the glow; gameplay owns the timing.
func telegraph() -> float:
	if kind != EnemyDefs.SPITTER:
		return 0.0
	return clampf(charge / EnemyDefs.SPITTER_CHARGE_TIME, 0.0, 1.0)


## Applies a blow's knockback (prototype `hit_enemy`): the old velocity keeps
## 30 %, the new impulse adds, and the enemy is stunned for longer the harder it
## was hit. `force` already includes the type's resistance and any crit bonus.
func launch(direction: Vector2, force: float) -> void:
	velocity = velocity * 0.3 + direction * force
	stun = maxf(stun, 0.08 + force / 1500.0)


## Prototype `Enemy.update`: chase the player (a runner weaves across the line
## of approach, a spitter keeps its distance and shoots); a stunned enemy only
## decays its knockback velocity, and a stun cancels a spitter's charge. Once the
## player is dead every enemy wanders slowly and nothing shoots. Walls clamp the enemy; hitting one
## while stunned and fast is a wall slam.
func update(run: GameRun, dt: float) -> void:
	age += dt
	flash = maxf(0.0, flash - dt)
	squash = maxf(0.0, squash - dt * 5.0)
	var to_player: Vector2 = run.position - position
	var dist: float = maxf(1.0, to_player.length())
	var toward: Vector2 = to_player / dist
	facing = toward
	if stun > 0.0:
		stun -= dt
		velocity *= exp(-dt * 5.0)
		charge = 0.0
	else:
		var want: Vector2 = toward * speed
		if run.dead:
			want = SimMath.polar(age * 0.3 + float(serial % 7), speed * 0.3)
		elif kind == EnemyDefs.SPITTER:
			want = _spitter_want(run, dt, dist, toward, want)
		elif kind == EnemyDefs.RUNNER:
			var side: Vector2 = Vector2(-toward.y, toward.x)
			want = (toward + side * sin(age * RUNNER_WEAVE_RATE) * RUNNER_WEAVE_AMPLITUDE) * speed
		velocity += (want - velocity) * minf(1.0, dt * 6.0)
	var speed_before: float = velocity.length()
	position += velocity * dt
	var slammed: bool = false
	var inner: Rect2 = GameRun.WORLD.grow(-radius)
	if position.x < inner.position.x or position.x > inner.end.x:
		position.x = clampf(position.x, inner.position.x, inner.end.x)
		velocity.x *= -0.35
		slammed = true
	if position.y < inner.position.y or position.y > inner.end.y:
		position.y = clampf(position.y, inner.position.y, inner.end.y)
		velocity.y *= -0.35
		slammed = true
	if slammed and stun > 0.0 and speed_before > GameRun.WALL_SLAM_MIN_SPEED:
		run.wall_slam(self, speed_before)


## The spitter's decision for one tick: back away when too close, circle at a
## middling distance, otherwise approach; once its cooldown is spent and the
## player is in range it slows to a crawl for CHARGE_TIME and then fires an orb
## straight at the player (prototype `Enemy.update`, kind == "spitter"). Returns
## the velocity it wants. A stun resets the charge but does not advance the
## cooldown (the caller only gets here while it is in control).
func _spitter_want(run: GameRun, dt: float, dist: float, toward: Vector2, approach: Vector2) -> Vector2:
	var want: Vector2 = approach
	if dist < EnemyDefs.SPITTER_RETREAT_RANGE:
		want = -toward * speed
	elif dist < EnemyDefs.SPITTER_ORBIT_RANGE:
		want = Vector2(-toward.y, toward.x) * speed * EnemyDefs.SPITTER_ORBIT_SPEED
	shoot_cooldown -= dt
	if shoot_cooldown <= 0.0 and dist < EnemyDefs.SPITTER_FIRE_RANGE:
		charge += dt
		want *= EnemyDefs.SPITTER_CHARGE_SLOW
		if charge >= EnemyDefs.SPITTER_CHARGE_TIME:
			run.spawn_projectile(position + toward * radius, toward * EnemyDefs.SPITTER_SHOT_SPEED)
			charge = 0.0
			shoot_cooldown = run.rng.randf_range(EnemyDefs.SPITTER_COOLDOWN_MIN, EnemyDefs.SPITTER_COOLDOWN_MAX)
	return want
