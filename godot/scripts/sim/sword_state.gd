class_name SwordState
extends RefCounted
## One equipped spirit sword (game/main.py `Sword`). Combat owns its logical
## pose (`position`, `angle`), its action phase and every timing and reach
## value; a visual scene only follows `phase`/`angle` and never feeds anything
## back (ADR 0003).
##
## Only the Fang sword type is ported here: idle/recover orbit, windup, strike
## and recovery. Warden, Pike and Colossus attacks, Converge and ultimates land
## in later slices, so `SwordDefs.is_supported` rejects other types.

enum Phase { IDLE, WINDUP, STRIKE, RECOVER }

var spec: SwordSpec
var phase: Phase = Phase.IDLE
var position: Vector2 = Vector2.ZERO
var velocity: Vector2 = Vector2.ZERO
## Logical facing of the blade, radians. Upright (-PI/2) while idle.
var angle: float = -PI / 2.0
## Seconds left in the current windup/strike/recover phase.
var timer: float = 0.0
## Time until this sword may acquire its next target.
var cooldown_left: float = 0.0
var target: EnemyState = null
var aim: Vector2 = Vector2.ZERO
var dir: Vector2 = Vector2.RIGHT
## Damage multiplier of the current attack (1 for automatic attacks).
var boost: float = 1.0

var damage: float = 0.0
var cooldown: float = 0.0
var attack_range: float = 0.0
var length: float = 0.0


static func equip(spec_value: SwordSpec, at: Vector2, start_cooldown: float) -> SwordState:
	assert(SwordDefs.is_supported(spec_value.type_id), "sword type not ported yet: %s" % spec_value.type_id)
	var sword: SwordState = SwordState.new()
	sword.spec = spec_value
	var rarity: int = spec_value.rarity
	sword.damage = SwordDefs.FANG_DAMAGE * SwordDefs.RARITY_DAMAGE[rarity]
	sword.cooldown = SwordDefs.FANG_COOLDOWN * SwordDefs.RARITY_COOLDOWN[rarity]
	sword.attack_range = SwordDefs.FANG_RANGE * SwordDefs.RARITY_RANGE[rarity]
	sword.length = SwordDefs.FANG_LENGTH * SwordDefs.RARITY_SIZE[rarity]
	sword.position = at
	sword.cooldown_left = start_cooldown
	return sword


func _spring(goal: Vector2, k: float, c: float, dt: float) -> void:
	velocity += ((goal - position) * k - velocity * c) * dt
	position += velocity * dt


## Nearest enemy within range of the player, or null (prototype `acquire`).
func acquire(run: GameRun) -> EnemyState:
	var best: EnemyState = null
	var best_dist: float = INF
	for enemy: EnemyState in run.enemies:
		var dist: float = (enemy.position - run.position).length()
		if dist < attack_range + enemy.radius and dist < best_dist:
			best = enemy
			best_dist = dist
	return best


func begin(new_target: EnemyState, new_aim: Vector2, new_boost: float = 1.0) -> void:
	target = new_target
	aim = new_aim
	boost = new_boost
	phase = Phase.WINDUP
	timer = SwordDefs.FANG_WINDUP


## One fixed step of this sword's state machine (prototype `Sword.update`).
## `index`/`count` place the sword on its orbit around the player.
func update(run: GameRun, dt: float, index: int, count: int) -> void:
	cooldown_left -= dt
	if target != null:
		if target.dead:
			target = null
		else:
			aim = target.position

	if run.dead:
		velocity *= exp(-dt * 3.0)
		position += velocity * dt
		angle = SimMath.ang_lerp(angle, float(index) * 1.3 + 0.4, minf(1.0, dt * 4.0))
		phase = Phase.IDLE
		return

	var start_phase: Phase = phase
	match start_phase:
		Phase.IDLE, Phase.RECOVER:
			var orbit: float = run.gameplay_time * 0.9 + float(index) * TAU / float(count)
			var radius: float = 46.0 + length * 0.22
			var slot: Vector2 = run.position + Vector2(cos(orbit) * radius, sin(orbit) * radius * 0.55 - 6.0)
			if start_phase == Phase.RECOVER:
				_spring(slot, 90.0, 13.0, dt)
				timer -= dt
				if timer <= 0.0:
					phase = Phase.IDLE
			else:
				_spring(slot, 55.0, 10.0, dt)
			var lean: float = clampf(velocity.x / 600.0, -0.8, 0.8)
			angle = SimMath.ang_lerp(angle, -PI / 2.0 + lean + sin(run.gameplay_time * 1.7 + float(index)) * 0.12, minf(1.0, dt * 7.0))
			if start_phase == Phase.IDLE and cooldown_left <= 0.0:
				var found: EnemyState = acquire(run)
				if found != null:
					begin(found, found.position)
		Phase.WINDUP:
			timer -= dt
			var to_aim: Vector2 = SimMath.norm(aim - run.position, run.rng, Vector2.RIGHT, true)
			var d: Vector2 = SimMath.norm(aim - position, run.rng, to_aim, true)
			_spring(run.position + (position - run.position) * 0.98 - d * 18.0, 160.0, 22.0, dt)
			angle = SimMath.ang_lerp(angle, atan2(d.y, d.x), minf(1.0, dt * 25.0))
			if timer <= 0.0:
				_start_strike(run)
		Phase.STRIKE:
			_update_strike(run, dt)


func _start_strike(run: GameRun) -> void:
	phase = Phase.STRIKE
	cooldown_left = cooldown
	dir = SimMath.norm(aim - position, run.rng)
	timer = SwordDefs.FANG_STRIKE_TIME
	run.add_cue(SimCue.make(SimCue.Kind.SWORD_STRIKE, position, dir))


## The strike dashes the sword along a homing line; the first enemy touched by
## the swept segment takes the hit and ends the strike.
func _update_strike(run: GameRun, dt: float) -> void:
	timer -= dt
	var previous: Vector2 = position
	var d: Vector2 = SimMath.norm(aim - position, run.rng, dir, true)
	dir = SimMath.norm(dir.lerp(d, minf(1.0, dt * 14.0)), run.rng, d, true)
	velocity = dir * SwordDefs.FANG_SPEED
	position += velocity * dt
	angle = atan2(dir.y, dir.x)
	var tip: Vector2 = position + dir * length * SwordDefs.FANG_TIP_FRACTION
	for enemy: EnemyState in run.enemies:
		if SimMath.seg_dist(enemy.position, previous, tip) < enemy.radius + SwordDefs.FANG_HIT_PAD:
			run.hit_enemy(enemy, damage * boost, dir, SwordDefs.FANG_KNOCK, self)
			phase = Phase.RECOVER
			timer = SwordDefs.FANG_RECOVER_AFTER_HIT
			velocity = -dir * 380.0 + SimMath.polar(run.rng.randf_range(0.0, TAU), 160.0)
			return
	if timer <= 0.0 or (target == null and (aim - position).length() < 12.0):
		phase = Phase.RECOVER
		timer = SwordDefs.FANG_RECOVER_AFTER_MISS
