class_name SwordState
extends RefCounted
## One equipped spirit sword (game/main.py `Sword`). Combat owns its logical
## pose (`position`, `angle`), its action phase and every timing and reach
## value; a visual scene only follows `phase`/`angle` and never feeds anything
## back (ADR 0003).
##
## Only the Fang sword type is ported here: idle/recover orbit, windup, strike,
## recovery and the Viper Flurry ultimate. Warden, Pike and Colossus attacks,
## Converge and their ultimates land in later slices, so
## `SwordDefs.is_supported` rejects other types.
##
## Ultimates are per-slot sword state: each sword carries its own recharge and,
## while it lasts, the ULTIMATE phase. `begin_ultimate` and `_update_ultimate`
## dispatch on the sword type; the other types' ultimates add a branch each.

## ULTIMATE is last so the earlier phases keep their numeric values.
enum Phase { IDLE, WINDUP, STRIKE, RECOVER, ULTIMATE }

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

## Ultimate recharge: the full time (base times the rarity's cooldown factor) and
## what is left. The recharge starts the moment the ultimate does and runs on
## gameplay time in every phase, so it covers the ultimate itself and the recovery.
var ultimate_cooldown: float = 0.0
var ultimate_cooldown_left: float = 0.0
## The (range-clamped) world point the current ultimate was aimed at.
var ultimate_point: Vector2 = Vector2.ZERO
## Viper Flurry: where the sword is darting to, who it will strike next, gameplay
## seconds left, and the seconds until the next dart.
var ultimate_goal: Vector2 = Vector2.ZERO
var ultimate_victim: EnemyState = null
var ultimate_time_left: float = 0.0
var ultimate_beat: float = 0.0

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
	sword.ultimate_cooldown = SwordDefs.ultimate_cooldown(spec_value.type_id) * SwordDefs.RARITY_COOLDOWN[rarity]
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


## True when the slot's ultimate may be triggered: recharged and not running.
func ultimate_ready() -> bool:
	return ultimate_cooldown_left <= 0.0 and phase != Phase.ULTIMATE


## 0..1 progress of the recharge (1 = recharged), for the HUD.
func ultimate_charge() -> float:
	if ultimate_cooldown <= 0.0:
		return 1.0
	return 1.0 - clampf(ultimate_cooldown_left / ultimate_cooldown, 0.0, 1.0)


## Starts this sword's ultimate aimed at `point` (already clamped to its range
## by the run), interrupting whatever it was doing and starting the recharge.
func begin_ultimate(point: Vector2) -> void:
	phase = Phase.ULTIMATE
	ultimate_cooldown_left = ultimate_cooldown
	boost = 1.0
	target = null
	ultimate_victim = null
	ultimate_point = point
	match spec.type_id:
		SwordDefs.FANG:
			# Blink straight onto the target area.
			position = point
			ultimate_goal = point
			ultimate_time_left = SwordDefs.FANG_ULT_DURATION
			ultimate_beat = 0.0


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
	ultimate_cooldown_left = maxf(0.0, ultimate_cooldown_left - dt)
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
		ultimate_victim = null
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
		Phase.ULTIMATE:
			_update_ultimate(run, dt)


func _start_strike(run: GameRun) -> void:
	phase = Phase.STRIKE
	cooldown_left = cooldown
	dir = SimMath.norm(aim - position, run.rng)
	timer = SwordDefs.FANG_STRIKE_TIME
	run.add_cue(SimCue.make(SimCue.Kind.SWORD_STRIKE, position, dir))


## The strike dashes the sword along a homing line; the first enemy touched by
## the swept segment takes the hit and ends the strike. A sweep that touches no
## enemy parries every projectile within reach of its swept segment instead (a
## tick that hits is not a parrying tick), then the strike runs on or ends.
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
	run.parry_projectiles(previous, tip, SwordDefs.FANG_PARRY_PAD)
	if timer <= 0.0 or (target == null and (aim - position).length() < 12.0):
		phase = Phase.RECOVER
		timer = SwordDefs.FANG_RECOVER_AFTER_MISS


## One tick of the running ultimate (prototype `Sword.update_ult`).
func _update_ultimate(run: GameRun, dt: float) -> void:
	match spec.type_id:
		SwordDefs.FANG:
			_update_viper_flurry(run, dt)


## Viper Flurry: the sword darts between the enemies inside the area, striking
## one every FANG_ULT_CADENCE seconds, then recovers. The victim is chosen one
## beat ahead and struck at the next one, so an enemy that died (or left the
## run) in between is simply skipped and replaced. A struck victim is not
## chosen again while another enemy is in the area. Nothing in the flurry
## parries projectiles (the prototype's does not either).
func _update_viper_flurry(run: GameRun, dt: float) -> void:
	var radius: float = SwordDefs.FANG_ULT_RADIUS
	ultimate_time_left -= dt
	ultimate_beat -= dt
	if ultimate_beat <= 0.0:
		ultimate_beat = SwordDefs.FANG_ULT_CADENCE
		var struck: EnemyState = ultimate_victim
		if struck != null and not struck.dead:
			var heading: Vector2 = SimMath.norm(struck.position - ultimate_point, run.rng, dir, true)
			run.hit_enemy(struck, damage * SwordDefs.FANG_ULT_DAMAGE_FACTOR, heading, SwordDefs.FANG_ULT_KNOCK, self, true)
			run.add_shake(SwordDefs.FANG_ULT_SHAKE)
		var nearby: Array[EnemyState] = []
		var fresh: Array[EnemyState] = []
		for enemy: EnemyState in run.enemies:
			if not enemy.dead and (enemy.position - ultimate_point).length() < radius + enemy.radius:
				nearby.append(enemy)
				if enemy != struck:
					fresh.append(enemy)
		var pool: Array[EnemyState] = fresh if not fresh.is_empty() else nearby
		if not pool.is_empty():
			ultimate_victim = pool[run.rng.randi_range(0, pool.size() - 1)]
			var away: Vector2 = SimMath.norm(ultimate_victim.position - position, run.rng)
			ultimate_goal = ultimate_victim.position + away * (ultimate_victim.radius + SwordDefs.FANG_ULT_STANDOFF)
		else:
			ultimate_victim = null
			ultimate_goal = ultimate_point + SimMath.polar(run.rng.randf_range(0.0, TAU), run.rng.randf_range(SwordDefs.FANG_ULT_WANDER_MIN, radius * SwordDefs.FANG_ULT_WANDER_FRACTION))
	var previous: Vector2 = position
	position = position.lerp(ultimate_goal, minf(1.0, dt * SwordDefs.FANG_ULT_APPROACH_RATE))
	velocity = (position - previous) / maxf(dt, 1e-4)
	if velocity.length_squared() > 400.0:
		dir = SimMath.norm(velocity, run.rng)
		angle = atan2(dir.y, dir.x)
	if ultimate_time_left <= 0.0:
		phase = Phase.RECOVER
		timer = SwordDefs.FANG_ULT_RECOVER_TIME
		velocity = SimMath.polar(run.rng.randf_range(0.0, TAU), SwordDefs.FANG_ULT_RECOVER_SPEED)
		ultimate_victim = null
