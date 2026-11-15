class_name SwordState
extends RefCounted
## One equipped spirit sword (game/main.py `Sword`). Combat owns its logical
## pose (`position`, `angle`), its action phase and every timing and reach
## value; a visual scene only follows `phase`/`angle` and never feeds anything
## back (ADR 0003).
##
## Fang (a homing dash, the Viper Flurry ultimate) and Warden (an alternating
## sweeping arc, the Maelstrom ultimate) are ported: idle/recover orbit, windup,
## strike, recovery and the ultimates. Pike and Colossus attacks, Converge and
## their ultimates land in later slices, so `SwordDefs.is_supported` rejects
## other types.
##
## Ultimates are per-slot sword state: each sword carries its own recharge and,
## while it lasts, the ULTIMATE phase. `begin_ultimate`, `_update_ultimate` and
## the windup/strike phases dispatch on the sword type; the other types add a
## branch each. Warden's sweep geometry (`sweep_*`) and Maelstrom's reach are
## gameplay state the presentation reads, never the other way round (ADR 0003).

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

## Warden's sweep (prototype `pivot`, `a0`, `a1`, `side`, `dur`, `hit`). `side` flips at the
## start of every attack, so successive sweeps swing in opposite directions. The pivot and
## the arc's end angles follow the target through the windup and freeze at the strike.
var side: int = 1
var sweep_pivot: Vector2 = Vector2.ZERO
var sweep_from: float = 0.0
var sweep_to: float = 0.0
var sweep_duration: float = SwordDefs.WARDEN_SWEEP_TIME
## Enemies the current attack has already hit: each is struck at most once per attack.
var sweep_hits: Dictionary[EnemyState, bool] = {}

## Ultimate recharge: the full time (base times the rarity's cooldown factor) and
## what is left. The recharge starts the moment the ultimate does and runs on
## gameplay time in every phase, so it covers the ultimate itself and the recovery.
var ultimate_cooldown: float = 0.0
var ultimate_cooldown_left: float = 0.0
## The (range-clamped) world point the current ultimate was aimed at.
var ultimate_point: Vector2 = Vector2.ZERO
## Maelstrom: the angle of the sword around the centre, and gameplay seconds left in
## `ultimate_time_left` / until the next beat in `ultimate_beat` (shared with Viper Flurry).
var ultimate_spin: float = 0.0
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
## The rarity's size factor (it scales the blade and Maelstrom's radius), and the type's
## knockback, windup, hitstop and shake for a normal blow.
var size_scale: float = 1.0
var knock: float = 0.0
var windup: float = 0.0
var hit_stop: float = 0.0
var hit_shake: float = 0.0


static func equip(spec_value: SwordSpec, at: Vector2, start_cooldown: float) -> SwordState:
	assert(SwordDefs.is_supported(spec_value.type_id), "sword type not ported yet: %s" % spec_value.type_id)
	var sword: SwordState = SwordState.new()
	sword.spec = spec_value
	var rarity: int = spec_value.rarity
	var type_id: StringName = spec_value.type_id
	sword.damage = SwordDefs.base_damage(type_id) * SwordDefs.RARITY_DAMAGE[rarity]
	sword.cooldown = SwordDefs.base_cooldown(type_id) * SwordDefs.RARITY_COOLDOWN[rarity]
	sword.attack_range = SwordDefs.base_range(type_id) * SwordDefs.RARITY_RANGE[rarity]
	sword.length = SwordDefs.base_length(type_id) * SwordDefs.RARITY_SIZE[rarity]
	sword.size_scale = SwordDefs.RARITY_SIZE[rarity]
	sword.knock = SwordDefs.base_knock(type_id)
	sword.windup = SwordDefs.base_windup(type_id)
	sword.hit_stop = SwordDefs.base_hitstop(type_id)
	sword.hit_shake = SwordDefs.base_shake(type_id)
	sword.ultimate_cooldown = SwordDefs.ultimate_cooldown(spec_value.type_id) * SwordDefs.RARITY_COOLDOWN[rarity]
	sword.position = at
	sword.cooldown_left = start_cooldown
	return sword


func _spring(goal: Vector2, k: float, c: float, dt: float) -> void:
	velocity += ((goal - position) * k - velocity * c) * dt
	position += velocity * dt


## True while `enemy` can still be targeted: alive and still in the run. The
## prototype checks only `dead`, because an enemy only leaves the run once dead;
## a reference kept across ticks (the attack target, the flurry's victim) is also
## dropped if its enemy was removed while alive, so a stale enemy can never be
## hit, killed or rewarded (docs/reference/viper-flurry.md, exception 10).
static func _in_play(run: GameRun, enemy: EnemyState) -> bool:
	return enemy != null and not enemy.dead and run.enemies.has(enemy)


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


## Maelstrom geometry (prototype `R` and `reach` in `update_ult`): the circle the sword whirls
## on, the reach of its blades from the centre, how far out enemies are dragged in, and the
## reach of the finishing burst (an enemy's own radius adds to each).
func maelstrom_radius() -> float:
	return SwordDefs.WARDEN_ULT_RADIUS * size_scale


func maelstrom_reach() -> float:
	return maelstrom_radius() + length * SwordDefs.WARDEN_ULT_REACH_TAIL


func maelstrom_pull_range() -> float:
	return maelstrom_reach() + SwordDefs.WARDEN_ULT_PULL_EXTRA


func maelstrom_burst_reach() -> float:
	return maelstrom_reach() + SwordDefs.WARDEN_ULT_BURST_MARGIN


## The radius of the area this sword's running ultimate acts in, for the HUD and effects.
func ultimate_area_radius() -> float:
	return maelstrom_reach() if spec.type_id == SwordDefs.WARDEN else SwordDefs.FANG_ULT_RADIUS


## Starts this sword's ultimate aimed at `point` (already clamped to its range
## by the run), interrupting whatever it was doing and starting the recharge.
func begin_ultimate(point: Vector2) -> void:
	phase = Phase.ULTIMATE
	ultimate_cooldown_left = ultimate_cooldown
	boost = 1.0
	target = null
	ultimate_victim = null
	ultimate_point = point
	sweep_hits.clear()
	match spec.type_id:
		SwordDefs.FANG:
			# Blink straight onto the target area.
			position = point
			ultimate_goal = point
			ultimate_time_left = SwordDefs.FANG_ULT_DURATION
			ultimate_beat = 0.0
		SwordDefs.WARDEN:
			# No blink: the sword starts whirling from where it hangs, at its bearing from the centre.
			ultimate_time_left = SwordDefs.WARDEN_ULT_DURATION
			ultimate_beat = SwordDefs.WARDEN_ULT_FIRST_BEAT
			ultimate_spin = atan2(position.y - point.y, position.x - point.x)


func begin(new_target: EnemyState, new_aim: Vector2, new_boost: float = 1.0) -> void:
	target = new_target
	aim = new_aim
	boost = new_boost
	phase = Phase.WINDUP
	timer = windup
	sweep_hits.clear()
	side = -side


## One fixed step of this sword's state machine (prototype `Sword.update`).
## `index`/`count` place the sword on its orbit around the player.
func update(run: GameRun, dt: float, index: int, count: int) -> void:
	cooldown_left -= dt
	ultimate_cooldown_left = maxf(0.0, ultimate_cooldown_left - dt)
	if target != null:
		if not _in_play(run, target):
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
			match spec.type_id:
				SwordDefs.WARDEN:
					_update_sweep_windup(dt, to_aim)
				_:
					var d: Vector2 = SimMath.norm(aim - position, run.rng, to_aim, true)
					_spring(run.position + (position - run.position) * 0.98 - d * 18.0, 160.0, 22.0, dt)
					angle = SimMath.ang_lerp(angle, atan2(d.y, d.x), minf(1.0, dt * 25.0))
			if timer <= 0.0:
				_start_strike(run)
		Phase.STRIKE:
			match spec.type_id:
				SwordDefs.WARDEN:
					_update_sweep(run, dt)
				_:
					_update_strike(run, dt)
		Phase.ULTIMATE:
			_update_ultimate(run, dt)


func _start_strike(run: GameRun) -> void:
	phase = Phase.STRIKE
	cooldown_left = cooldown
	match spec.type_id:
		SwordDefs.WARDEN:
			# The sweep follows the pivot and arc the last windup tick set; the heading is for cues.
			timer = SwordDefs.WARDEN_SWEEP_TIME
			sweep_duration = timer
			dir = SimMath.polar((sweep_from + sweep_to) * 0.5)
		_:
			dir = SimMath.norm(aim - position, run.rng)
			timer = SwordDefs.FANG_STRIKE_TIME
	run.add_cue(SimCue.make(SimCue.Kind.SWORD_STRIKE, position, dir))


## Warden's windup (prototype `Sword.update`, blade branch): the pivot sits 0.55 blade lengths
## behind the aim point on the player's line to it, the arc runs from `amid - side * 1.9` to
## `amid + side * 1.45`, and the sword springs onto its start and turns toward it. Everything is
## recomputed every tick, so the pivot and arc follow a moving target until the strike.
func _update_sweep_windup(dt: float, to_aim: Vector2) -> void:
	sweep_pivot = aim - to_aim * (length * SwordDefs.WARDEN_PIVOT_BACK)
	var amid: float = atan2(to_aim.y, to_aim.x)
	sweep_from = amid - float(side) * SwordDefs.WARDEN_SWEEP_START
	sweep_to = amid + float(side) * SwordDefs.WARDEN_SWEEP_END
	_spring(sweep_pivot + SimMath.polar(sweep_from, length * SwordDefs.WARDEN_POSE_RADIUS), SwordDefs.WARDEN_WINDUP_SPRING_K, SwordDefs.WARDEN_WINDUP_SPRING_C, dt)
	angle = SimMath.ang_lerp(angle, sweep_from, minf(1.0, dt * SwordDefs.WARDEN_WINDUP_TURN_RATE))


## Warden's sweep (prototype `Sword.update`, blade strike): the sword rides the arc, eased out
## over WARDEN_SWEEP_TIME, and every tick its cutting segment is tested at two angles, halfway
## from last tick's heading and at the new one. Each enemy within its radius + 8 of either is
## struck once per attack (in enemy order), then every orb within reach of either is parried,
## hit or no hit. Recovery follows the last tick of the sweep.
func _update_sweep(run: GameRun, dt: float) -> void:
	timer -= dt
	var progress: float = 1.0 - maxf(0.0, timer) / sweep_duration
	var previous_angle: float = angle
	var swung: float = lerpf(sweep_from, sweep_to, SimMath.ease_out(progress))
	var next: Vector2 = sweep_pivot + SimMath.polar(swung, length * SwordDefs.WARDEN_POSE_RADIUS)
	velocity = (next - position) / maxf(dt, 1e-4)
	position = next
	angle = swung
	for sample: float in [lerpf(previous_angle, swung, 0.5), swung]:
		var guard: Vector2 = sweep_pivot + SimMath.polar(sample, length * SwordDefs.WARDEN_GUARD)
		var tip: Vector2 = sweep_pivot + SimMath.polar(sample, length * SwordDefs.WARDEN_TIP)
		for enemy: EnemyState in run.enemies:
			if sweep_hits.has(enemy):
				continue
			if SimMath.seg_dist(enemy.position, guard, tip) < enemy.radius + SwordDefs.WARDEN_HIT_PAD:
				sweep_hits[enemy] = true
				var tangent: Vector2 = SimMath.polar(sample + float(side) * PI * 0.5)
				var away: Vector2 = SimMath.norm(enemy.position - run.position, run.rng)
				run.hit_enemy(enemy, damage * boost, tangent * SwordDefs.WARDEN_TANGENT_WEIGHT + away, knock, self)
		run.parry_projectiles(guard, tip, SwordDefs.WARDEN_PARRY_PAD)
	if timer <= 0.0:
		phase = Phase.RECOVER
		timer = SwordDefs.WARDEN_RECOVER_TIME
		velocity = SimMath.polar(swung + float(side) * PI * 0.5, SwordDefs.WARDEN_RECOVER_SPEED)


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
		SwordDefs.WARDEN:
			_update_maelstrom(run, dt)


## Viper Flurry: the sword darts between the enemies inside the area, striking
## one every FANG_ULT_CADENCE seconds, then recovers. The victim is chosen one
## beat ahead and struck at the next one, so an enemy that died (or left the
## run, even alive) in between is simply skipped and replaced. A struck victim is not
## chosen again while another enemy is in the area. Nothing in the flurry
## parries projectiles (the prototype's does not either).
func _update_viper_flurry(run: GameRun, dt: float) -> void:
	var radius: float = SwordDefs.FANG_ULT_RADIUS
	ultimate_time_left -= dt
	ultimate_beat -= dt
	if ultimate_beat <= 0.0:
		ultimate_beat = SwordDefs.FANG_ULT_CADENCE
		var struck: EnemyState = ultimate_victim
		if struck != null and _in_play(run, struck):
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


## Maelstrom: the sword whirls on a circle around the centre, every enemy inside the pull range
## is dragged toward the centre, a beat every WARDEN_ULT_BEAT seconds strikes everything inside
## the blades' reach (heavy blows, one dose of the element each), and when the time is up a
## finishing burst strikes a little farther out for more (two doses), then the sword recovers.
## Enemies are taken in the run's order and the dead are not skipped, exactly as in the
## prototype: a corpse (killed earlier this tick, removed at the end of the update) is still
## pulled, which changes the crowd's collisions, and a corpse inside the reach still counts for
## the beat's sound and shake (`hit_enemy` itself ignores the dead). Nothing in the whirl
## parries projectiles (the prototype's does not either).
func _update_maelstrom(run: GameRun, dt: float) -> void:
	var centre: Vector2 = ultimate_point
	ultimate_time_left -= dt
	ultimate_spin += dt * SwordDefs.WARDEN_ULT_SPIN_RATE
	var reach: float = maelstrom_reach()
	var previous: Vector2 = position
	position = position.lerp(centre + SimMath.polar(ultimate_spin, maelstrom_radius()), minf(1.0, dt * SwordDefs.WARDEN_ULT_APPROACH_RATE))
	velocity = (position - previous) / maxf(dt, 1e-4)
	angle = ultimate_spin
	for enemy: EnemyState in run.enemies:
		var to_centre: Vector2 = centre - enemy.position
		var dist: float = to_centre.length()
		if SwordDefs.WARDEN_ULT_PULL_MIN < dist and dist < maelstrom_pull_range():
			enemy.position += to_centre / dist * SwordDefs.WARDEN_ULT_PULL_SPEED * enemy.knock_mult * dt
	ultimate_beat -= dt
	if ultimate_beat <= 0.0:
		ultimate_beat = SwordDefs.WARDEN_ULT_BEAT
		var struck: int = 0
		for enemy: EnemyState in run.enemies:
			var off: Vector2 = enemy.position - centre
			if off.length() < reach + enemy.radius:
				run.hit_enemy(enemy, damage * SwordDefs.WARDEN_ULT_TICK_FACTOR, Vector2(-off.y, off.x), SwordDefs.WARDEN_ULT_TICK_KNOCK, self, true)
				struck += 1
		if struck > 0:
			run.add_shake(SwordDefs.WARDEN_ULT_TICK_SHAKE)
		_add_maelstrom_cue(run, SimCue.Kind.MAELSTROM_BEAT, reach, struck)
	if ultimate_time_left <= 0.0:
		var caught: int = 0
		var burst_reach: float = maelstrom_burst_reach()
		for enemy: EnemyState in run.enemies:
			var off: Vector2 = enemy.position - centre
			if off.length() < burst_reach + enemy.radius:
				run.hit_enemy(enemy, damage * SwordDefs.WARDEN_ULT_BURST_FACTOR, off, SwordDefs.WARDEN_ULT_BURST_KNOCK, self, true, SwordDefs.WARDEN_ULT_BURST_STACKS)
				caught += 1
		_add_maelstrom_cue(run, SimCue.Kind.MAELSTROM_BURST, burst_reach, caught)
		run.add_shake(SwordDefs.WARDEN_ULT_BURST_SHAKE)
		run.hitstop = maxf(run.hitstop, SwordDefs.WARDEN_ULT_BURST_HITSTOP)
		phase = Phase.RECOVER
		timer = SwordDefs.WARDEN_ULT_RECOVER_TIME
		velocity = SimMath.polar(ultimate_spin + PI * 0.5, SwordDefs.WARDEN_ULT_RECOVER_SPEED)


func _add_maelstrom_cue(run: GameRun, kind: SimCue.Kind, reach: float, struck: int) -> void:
	var cue: SimCue = SimCue.make(kind, ultimate_point, Vector2.ZERO, struck)
	cue.radius = reach
	cue.element = spec.element
	run.add_cue(cue)
