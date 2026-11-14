class_name EnemyState
extends RefCounted
## One enemy in a run. Only the husk exists in this slice (game/main.py
## `ENEMY_TYPES["husk"]`, `Enemy.update`); runners, spitters and brutes land
## later. Holds per-instance state only; constants are the husk's definition.

const HUSK: StringName = &"husk"
const HUSK_RADIUS: float = 16.0
const HUSK_HP: float = 30.0
const HUSK_SPEED: float = 92.0
const HUSK_DAMAGE: int = 10
const HUSK_KNOCK: float = 1.0
## Health grows by this fraction per wave after the first.
const HP_PER_WAVE: float = 0.1

var kind: StringName = HUSK
var serial: int = 0
var position: Vector2 = Vector2.ZERO
var velocity: Vector2 = Vector2.ZERO
var radius: float = HUSK_RADIUS
var max_hp: float = HUSK_HP
var hp: float = HUSK_HP
var speed: float = HUSK_SPEED
var damage: int = HUSK_DAMAGE
var knock_mult: float = HUSK_KNOCK
var facing: Vector2 = Vector2.RIGHT
## Seconds of reduced control after a hit (knockback stun).
var stun: float = 0.0
## Cosmetic timers the presentation reads (hit flash and squash).
var flash: float = 0.0
var squash: float = 0.0
var dead: bool = false
var age: float = 0.0


static func husk(at: Vector2, wave: int, speed_factor: float, serial_value: int) -> EnemyState:
	var enemy: EnemyState = EnemyState.new()
	enemy.serial = serial_value
	enemy.position = at
	enemy.max_hp = HUSK_HP * (1.0 + HP_PER_WAVE * float(wave - 1))
	enemy.hp = enemy.max_hp
	enemy.speed = HUSK_SPEED * speed_factor
	return enemy


## Prototype `Enemy.update` for a husk: chase the player; a stunned husk only
## decays its knockback velocity. `player_dead` makes husks wander slowly.
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
	else:
		var want: Vector2 = toward * speed
		if run.dead:
			want = SimMath.polar(age * 0.3 + float(serial % 7), speed * 0.3)
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
	if slammed and stun > 0.0 and speed_before > 380.0:
		run.wall_slam(self, speed_before)
