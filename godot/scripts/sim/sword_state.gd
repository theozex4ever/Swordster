class_name SwordState
extends RefCounted
## One equipped spirit sword (game/main.py `Sword`). Combat owns its logical
## pose (`position`, `angle`), its action phase and every timing and reach
## value; a visual scene only follows `phase`/`angle` and never feeds anything
## back (ADR 0003).
##
## Fang (a homing dash, the Viper Flurry ultimate), Warden (an alternating
## sweeping arc, the Maelstrom ultimate), Pike (a long piercing thrust, the Skewer
## ultimate) and Colossus (a crushing slam, the Cataclysm ultimate) are ported: idle/recover orbit,
## windup, strike, recovery and the ultimates, and the player's Converge command (`command`).
##
## Ultimates are per-slot sword state: each sword carries its own recharge and,
## while it lasts, the ULTIMATE phase. `begin_ultimate`, `_update_ultimate` and
## the windup/strike phases dispatch on the sword type; the other types add a
## branch each. Warden's sweep geometry (`sweep_*`) and Maelstrom's reach are
## gameplay state the presentation reads, never the other way round (ADR 0003). Pike's
## thrust and Skewer sweep a segment each tick (tail to tip), so nothing can tunnel at any
## speed or render rate; the Skewer's carried enemies are `skewer_carried`. Colossus
## rises, falls and lands on the point it chose; how long the fall takes is decided by its altitude and
## fall speed (`altitude`, `fall_speed`), which are gameplay state here because the prototype's height
## `z` decides when the slam lands. The visual draws them and never feeds anything back (ADR 0003).

## ULTIMATE and STUCK come last so the earlier phases keep their numeric values. STUCK is
## Colossus's pause with its blade buried in the floor after a slam (the prototype's "stuck").
enum Phase { IDLE, WINDUP, STRIKE, RECOVER, ULTIMATE, STUCK }

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
## Damage multiplier of the current attack (1 for automatic attacks, Converge's 1.5 for a commanded one).
var boost: float = 1.0
## How long the current windup lasts in total: the type's windup, or Converge's shorter one. The
## windup's progress (the telegraphs) is measured against it, never against the type's own.
var windup_span: float = 0.0

## Warden's sweep (prototype `pivot`, `a0`, `a1`, `side`, `dur`, `hit`). `side` flips at the
## start of every attack, so successive sweeps swing in opposite directions. The pivot and
## the arc's end angles follow the target through the windup and freeze at the strike.
var side: int = 1
var sweep_pivot: Vector2 = Vector2.ZERO
var sweep_from: float = 0.0
var sweep_to: float = 0.0
var sweep_duration: float = SwordDefs.WARDEN_SWEEP_TIME
## Enemies the current attack has already hit: each is struck at most once per attack
## (Warden's sweep, Pike's thrust and Skewer all use it; the prototype's `hit` set).
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
## Skewer: false while the sword aims (SwordDefs.PIKE_ULT_AIM_TIME), true once it has launched
## and flies along `dir`, and the enemies it has impaled and carries along (prototype `phase` and
## `carried`). A carried enemy stays in the list until it dies, is removed from the run, or the
## sword lets go of it.
var skewer_flying: bool = false
var skewer_carried: Array[EnemyState] = []
## Colossus (prototype `z`, `vz`, `impact` and, for Cataclysm, `phase == "fall"`): the height above the
## ground in px and the speed it falls at (while the slam falls, positive is downward), the ground
## point a slam lands on (fixed when the strike starts) and whether Cataclysm has stopped rising and
## is falling. The slam lands on the first tick the altitude reaches zero, so these decide its timing.
var altitude: float = 0.0
var fall_speed: float = 0.0
var impact: Vector2 = Vector2.ZERO
var cataclysm_falling: bool = false

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
	sword.windup_span = sword.windup
	sword.hit_stop = SwordDefs.base_hitstop(type_id)
	sword.hit_shake = SwordDefs.base_shake(type_id)
	sword.ultimate_cooldown = SwordDefs.ultimate_cooldown(spec_value.type_id) * SwordDefs.RARITY_COOLDOWN[rarity]
	sword.position = at
	sword.cooldown_left = start_cooldown
	if type_id == SwordDefs.COLOSSUS:
		sword.altitude = SwordDefs.COLOSSUS_START_ALTITUDE
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


## Nearest enemy within range of the player, or null (prototype `acquire`). A Pike
## prefers a long thrust: while any candidate is farther than PIKE_FAR_MIN from the player,
## only those are considered.
func acquire(run: GameRun) -> EnemyState:
	if spec.type_id == SwordDefs.COLOSSUS:
		return _acquire_cluster(run)
	var prefer_far: bool = false
	if spec.type_id == SwordDefs.PIKE:
		for enemy: EnemyState in run.enemies:
			var far: float = (enemy.position - run.position).length()
			if far < attack_range + enemy.radius and far > SwordDefs.PIKE_FAR_MIN:
				prefer_far = true
				break
	var best: EnemyState = null
	var best_dist: float = INF
	for enemy: EnemyState in run.enemies:
		var dist: float = (enemy.position - run.position).length()
		if prefer_far and dist <= SwordDefs.PIKE_FAR_MIN:
			continue
		if dist < attack_range + enemy.radius and dist < best_dist:
			best = enemy
			best_dist = dist
	return best


## Colossus's target (prototype `acquire`, colossus branch): among the enemies within range of the player,
## the one with the most enemies (itself, the dead of this tick and every other included) within
## COLOSSUS_AOE of it, a nearer one winning when the counts are equal (each enemy scores
## `count x 1000 - distance to the player`; the first of equal scores wins). The count uses the type's radius,
## not the rarity-scaled one the slam itself uses, as in the prototype.
func _acquire_cluster(run: GameRun) -> EnemyState:
	var best: EnemyState = null
	var best_score: float = 0.0
	for enemy: EnemyState in run.enemies:
		var dist: float = (enemy.position - run.position).length()
		if dist < attack_range + enemy.radius:
			var crowd: int = 0
			for other: EnemyState in run.enemies:
				if (other.position - enemy.position).length() < SwordDefs.COLOSSUS_AOE:
					crowd += 1
			var score: float = float(crowd) * 1000.0 - dist
			if best == null or score > best_score:
				best = enemy
				best_score = score
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
	match spec.type_id:
		SwordDefs.WARDEN:
			return maelstrom_reach()
		SwordDefs.PIKE:
			return 0.0
		SwordDefs.COLOSSUS:
			return cataclysm_radius()
		_:
			return SwordDefs.FANG_ULT_RADIUS


## The radius of this sword's automatic slam, and of a Cataclysm (prototype `t.aoe x scale`, and `ult_aoe`:
## `t.aoe x ult.aoe x scale`, multiplied in that order). The slam's own area uses the rarity's size factor.
func slam_radius() -> float:
	return SwordDefs.COLOSSUS_AOE * size_scale


func cataclysm_radius() -> float:
	return SwordDefs.COLOSSUS_AOE * SwordDefs.COLOSSUS_ULT_AOE_FACTOR * size_scale


## 0..1 progress of a Cataclysm's rise (1 once it is falling), for the telegraph.
func cataclysm_rise_progress() -> float:
	if phase != Phase.ULTIMATE or spec.type_id != SwordDefs.COLOSSUS:
		return 0.0
	if cataclysm_falling:
		return 1.0
	return 1.0 - clampf(ultimate_time_left / SwordDefs.COLOSSUS_ULT_RISE_TIME, 0.0, 1.0)


## 0..1 progress of the thrust's windup (Pike), for the presentation's telegraph; 0 outside it.
func windup_progress() -> float:
	if phase != Phase.WINDUP or windup_span <= 0.0:
		return 0.0
	return 1.0 - clampf(timer / windup_span, 0.0, 1.0)


## 0..1 progress of the Skewer's aim phase (1 once it has launched), for the telegraph.
func skewer_aim_progress() -> float:
	if phase != Phase.ULTIMATE or spec.type_id != SwordDefs.PIKE:
		return 0.0
	if skewer_flying:
		return 1.0
	return 1.0 - clampf(ultimate_time_left / SwordDefs.PIKE_ULT_AIM_TIME, 0.0, 1.0)


## Starts this sword's ultimate aimed at `point` (already clamped to its range
## by the run, except for a skill shot, which only takes its heading from it),
## interrupting whatever it was doing and starting the recharge.
func begin_ultimate(run: GameRun, point: Vector2) -> void:
	phase = Phase.ULTIMATE
	ultimate_cooldown_left = ultimate_cooldown
	boost = 1.0
	target = null
	ultimate_victim = null
	ultimate_point = point
	sweep_hits.clear()
	skewer_carried.clear()
	skewer_flying = false
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
		SwordDefs.COLOSSUS:
			# No move: the sword rises where it hangs, onto the point, and then falls on it.
			cataclysm_falling = false
			ultimate_time_left = SwordDefs.COLOSSUS_ULT_RISE_TIME
		SwordDefs.PIKE:
			# A skill shot: the heading is the player-to-point line (the player's facing if
			# they coincide), fixed for the whole shot.
			dir = SimMath.norm(point - run.position, run.rng, run.facing, true)
			ultimate_time_left = SwordDefs.PIKE_ULT_AIM_TIME


func begin(new_target: EnemyState, new_aim: Vector2, new_boost: float = 1.0, fast: bool = false) -> void:
	target = new_target
	aim = new_aim
	boost = new_boost
	phase = Phase.WINDUP
	timer = windup * (SwordDefs.CONVERGE_WINDUP_FACTOR if fast else 1.0)
	windup_span = timer
	sweep_hits.clear()
	side = -side


## Converge (prototype `Sword.command`): this sword strikes `point` at once with a shorter windup and
## CONVERGE_BOOST times its damage, aimed at the enemy nearest the point if one stands within
## CONVERGE_TARGET_RADIUS of it (it then follows that enemy through the windup), else at the point
## itself. The sword's own type decides what the attack is (a dash, a sweep, a thrust or a slam), as
## for an automatic attack. A sword in the middle of a strike, buried after a slam or in its
## ultimate ignores the command; one that is idle, winding up (the windup starts again) or
## recovering takes it, whatever its attack cooldown says. Enemies are taken in the run's order
## and the first nearest wins, a corpse included, exactly as in the prototype. Returns whether
## the sword took the command.
func command(run: GameRun, point: Vector2) -> bool:
	if phase == Phase.STRIKE or phase == Phase.STUCK or phase == Phase.ULTIMATE:
		return false
	var nearest: EnemyState = null
	var nearest_dist: float = SwordDefs.CONVERGE_TARGET_RADIUS
	for enemy: EnemyState in run.enemies:
		var dist: float = (enemy.position - point).length()
		if dist < nearest_dist:
			nearest = enemy
			nearest_dist = dist
	begin(nearest, point, SwordDefs.CONVERGE_BOOST, true)
	return true


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
		if spec.type_id == SwordDefs.COLOSSUS:
			altitude = maxf(0.0, altitude - dt * SwordDefs.COLOSSUS_SINK_RATE)
		phase = Phase.IDLE
		ultimate_victim = null
		skewer_carried.clear()
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
			if spec.type_id == SwordDefs.COLOSSUS:
				var rest: float = SwordDefs.COLOSSUS_REST_BASE + length * SwordDefs.COLOSSUS_REST_LENGTH + sin(run.gameplay_time * SwordDefs.COLOSSUS_REST_BOB_RATE + float(index) * SwordDefs.COLOSSUS_REST_BOB_SLOT) * SwordDefs.COLOSSUS_REST_BOB
				altitude = lerpf(altitude, rest, minf(1.0, dt * SwordDefs.COLOSSUS_REST_RATE))
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
				SwordDefs.PIKE:
					_update_thrust_windup(dt, to_aim)
				SwordDefs.COLOSSUS:
					_update_slam_windup(run, dt)
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
				SwordDefs.PIKE:
					_update_thrust(run, dt)
				SwordDefs.COLOSSUS:
					_update_slam_fall(run, dt)
				_:
					_update_strike(run, dt)
		Phase.ULTIMATE:
			_update_ultimate(run, dt)
		Phase.STUCK:
			_update_stuck(dt)


func _start_strike(run: GameRun) -> void:
	phase = Phase.STRIKE
	cooldown_left = cooldown
	match spec.type_id:
		SwordDefs.WARDEN:
			# The sweep follows the pivot and arc the last windup tick set; the heading is for cues.
			timer = SwordDefs.WARDEN_SWEEP_TIME
			sweep_duration = timer
			dir = SimMath.polar((sweep_from + sweep_to) * 0.5)
		SwordDefs.COLOSSUS:
			# The ground point is fixed now; the sword falls straight onto it.
			impact = aim
			fall_speed = SwordDefs.COLOSSUS_STRIKE_FALL_SPEED
			dir = Vector2.DOWN
		SwordDefs.PIKE:
			# A fixed line from where the sword hangs toward the aim point, run a little past it.
			dir = SimMath.norm(aim - position, run.rng)
			timer = ((aim - position).length() + SwordDefs.PIKE_STRIKE_OVERSHOOT) / SwordDefs.PIKE_SPEED
			angle = atan2(dir.y, dir.x)
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


## Pike's windup (prototype `Sword.update`, lance branch): the sword springs to a point 0.5
## lengths + 120 px short of the aim point on the player's line to it and turns to face along
## that line. Recomputed every tick, so it follows a moving target until the strike.
func _update_thrust_windup(dt: float, to_aim: Vector2) -> void:
	_spring(aim - to_aim * (length * SwordDefs.PIKE_WINDUP_STANDOFF_LENGTH + SwordDefs.PIKE_WINDUP_STANDOFF_EXTRA), SwordDefs.PIKE_WINDUP_SPRING_K, SwordDefs.PIKE_WINDUP_SPRING_C, dt)
	angle = SimMath.ang_lerp(angle, atan2(to_aim.y, to_aim.x), minf(1.0, dt * SwordDefs.PIKE_WINDUP_TURN_RATE))


## Pike's thrust (prototype `Sword.update`, lance strike): the sword flies straight along `dir`
## at PIKE_SPEED and every tick its swept segment, from 0.3 lengths behind where it was to 0.65
## ahead of where it is, strikes each enemy within radius + 7 once per attack (in enemy order,
## the dead included: `hit_enemy` ignores them), then parries every orb within 8 of it, hit or
## no hit. The sword does not stop on a hit; it recovers once the thrust's time is up.
func _update_thrust(run: GameRun, dt: float) -> void:
	timer -= dt
	var previous: Vector2 = position
	position += dir * SwordDefs.PIKE_SPEED * dt
	var tail: Vector2 = previous - dir * length * SwordDefs.PIKE_TAIL_FRACTION
	var tip: Vector2 = position + dir * length * SwordDefs.PIKE_TIP_FRACTION
	for enemy: EnemyState in run.enemies:
		if sweep_hits.has(enemy):
			continue
		if SimMath.seg_dist(enemy.position, tail, tip) < enemy.radius + SwordDefs.PIKE_HIT_PAD:
			sweep_hits[enemy] = true
			run.hit_enemy(enemy, damage * boost, dir, knock, self)
	run.parry_projectiles(tail, tip, SwordDefs.PIKE_PARRY_PAD)
	if timer <= 0.0:
		phase = Phase.RECOVER
		timer = SwordDefs.PIKE_RECOVER_TIME
		velocity = dir * SwordDefs.PIKE_RECOVER_SPEED


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
		SwordDefs.PIKE:
			_update_skewer(run, dt)
		SwordDefs.COLOSSUS:
			_update_cataclysm(run, dt)


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


## Skewer: the sword hangs back and faces the heading for PIKE_ULT_AIM_TIME, then launches from
## just ahead of the player and flies PIKE_ULT_RANGE along it at PIKE_ULT_SPEED. Each tick of the
## flight, in this order (the prototype's): every enemy the swept segment (0.3 lengths behind to
## 0.65 ahead) touches within radius + 18 and that is not yet in this Skewer's hit set takes a
## heavy blow of 2.2 x damage with no knockback and two doses of the element, shaking the screen;
## if it survives it is impaled. Enemies are taken in the run's order and the dead are not
## skipped (a corpse killed earlier this tick joins the hit set, `hit_enemy` ignores it and it is
## not impaled). Then the impaled that have died or left the run are let go, the rest are moved
## by the sword's whole step with their velocity zeroed and at least 0.5 s of stun (they are
## carried even into and past a wall: the enemy's own movement clamps them), and every orb the
## segment touches within 14 is parried. The flight ends when the range is spent or the tip leaves
## the arena shrunk by 20 px in each dimension (10 per side): whatever is still impaled is flung along the heading (1100 px/s at a
## wall, where the stunned enemy slams, 750 at the range limit) with at least 0.6 s of stun, and the
## sword recovers (kicked back from a wall, carried on at the range limit).
func _update_skewer(run: GameRun, dt: float) -> void:
	ultimate_time_left -= dt
	if not skewer_flying:
		_spring(run.position - dir * SwordDefs.PIKE_ULT_AIM_STANDOFF, SwordDefs.PIKE_ULT_AIM_SPRING_K, SwordDefs.PIKE_ULT_AIM_SPRING_C, dt)
		angle = atan2(dir.y, dir.x)
		if ultimate_time_left <= 0.0:
			skewer_flying = true
			position = run.position + dir * SwordDefs.PIKE_ULT_LAUNCH_AHEAD
			ultimate_time_left = SwordDefs.PIKE_ULT_RANGE / SwordDefs.PIKE_ULT_SPEED
			run.add_shake(SwordDefs.PIKE_ULT_LAUNCH_SHAKE, dir, true)
			run.add_cue(SimCue.make(SimCue.Kind.SKEWER_LAUNCHED, position, dir))
		return
	var step: Vector2 = dir * SwordDefs.PIKE_ULT_SPEED * dt
	var previous: Vector2 = position
	position += step
	velocity = dir * SwordDefs.PIKE_ULT_SPEED
	var tail: Vector2 = previous - dir * length * SwordDefs.PIKE_ULT_TAIL_FRACTION
	var tip: Vector2 = position + dir * length * SwordDefs.PIKE_ULT_TIP_FRACTION
	for enemy: EnemyState in run.enemies:
		if sweep_hits.has(enemy):
			continue
		if SimMath.seg_dist(enemy.position, tail, tip) < enemy.radius + SwordDefs.PIKE_ULT_HIT_PAD:
			sweep_hits[enemy] = true
			run.hit_enemy(enemy, damage * SwordDefs.PIKE_ULT_DAMAGE_FACTOR, dir, 0.0, self, true, SwordDefs.PIKE_ULT_STACKS)
			run.add_shake(SwordDefs.PIKE_ULT_HIT_SHAKE, dir, true)
			if not enemy.dead:
				skewer_carried.append(enemy)
	var still_carried: Array[EnemyState] = []
	for enemy: EnemyState in skewer_carried:
		if _in_play(run, enemy):
			still_carried.append(enemy)
	skewer_carried = still_carried
	for enemy: EnemyState in skewer_carried:
		enemy.position += step
		enemy.velocity = Vector2.ZERO
		enemy.stun = maxf(enemy.stun, SwordDefs.PIKE_ULT_CARRY_STUN)
	run.parry_projectiles(tail, tip, SwordDefs.PIKE_ULT_PARRY_PAD)
	var at_wall: bool = not _inside_skewer_arena(tip)
	if ultimate_time_left <= 0.0 or at_wall:
		var released: int = skewer_carried.size()
		for enemy: EnemyState in skewer_carried:
			enemy.velocity = dir * (SwordDefs.PIKE_ULT_RELEASE_SPEED_WALL if at_wall else SwordDefs.PIKE_ULT_RELEASE_SPEED_RANGE)
			enemy.stun = maxf(enemy.stun, SwordDefs.PIKE_ULT_RELEASE_STUN)
		skewer_carried.clear()
		phase = Phase.RECOVER
		timer = SwordDefs.PIKE_ULT_RECOVER_TIME
		velocity = -dir * SwordDefs.PIKE_ULT_RECOVER_SPEED_WALL if at_wall else dir * SwordDefs.PIKE_ULT_RECOVER_SPEED_RANGE
		run.add_cue(SimCue.make(SimCue.Kind.SKEWER_RELEASED, tip, dir, released, at_wall))


## Colossus's windup (prototype `Sword.update`, colossus branch): the sword springs onto the aim point,
## which follows its target until the strike, climbs toward its windup altitude and turns upright with a
## small tremble.
func _update_slam_windup(run: GameRun, dt: float) -> void:
	_spring(aim, SwordDefs.COLOSSUS_WINDUP_SPRING_K, SwordDefs.COLOSSUS_WINDUP_SPRING_C, dt)
	altitude = lerpf(altitude, SwordDefs.COLOSSUS_WINDUP_ALTITUDE, minf(1.0, dt * SwordDefs.COLOSSUS_WINDUP_RATE))
	angle = SimMath.ang_lerp(angle, PI / 2.0 + sin(run.gameplay_time * SwordDefs.COLOSSUS_WINDUP_TREMBLE_RATE) * SwordDefs.COLOSSUS_WINDUP_TREMBLE, minf(1.0, dt * SwordDefs.COLOSSUS_WINDUP_TURN_RATE))


## Colossus's fall (prototype `Sword.update`, colossus strike): the sword glides onto the impact point
## while it falls faster and faster; on the first tick its altitude reaches zero it lands exactly on the point,
## slams (`GameRun.slam`) and sticks in the ground. How long the fall takes depends only on the altitude
## it began from, never on a visual.
func _update_slam_fall(run: GameRun, dt: float) -> void:
	position = position.lerp(impact, minf(1.0, dt * SwordDefs.COLOSSUS_GLIDE_RATE))
	fall_speed += SwordDefs.COLOSSUS_STRIKE_GRAVITY * dt
	altitude -= fall_speed * dt
	if altitude <= 0.0:
		altitude = 0.0
		position = impact
		run.slam(self, impact, slam_radius(), 1.0, 1, false)
		phase = Phase.STUCK
		timer = SwordDefs.COLOSSUS_STUCK_TIME


## Colossus buried in the floor after a slam, trembling for a moment before it recovers.
func _update_stuck(dt: float) -> void:
	timer -= dt
	angle = PI / 2.0 + sin(timer * SwordDefs.COLOSSUS_STUCK_TREMBLE_RATE) * SwordDefs.COLOSSUS_STUCK_TREMBLE * timer
	if timer <= 0.0:
		phase = Phase.RECOVER
		timer = SwordDefs.COLOSSUS_RECOVER_TIME
		velocity = SwordDefs.COLOSSUS_RECOVER_VELOCITY


## Cataclysm: the sword rises onto the point for COLOSSUS_ULT_RISE_TIME (springing, climbing toward its
## rise altitude, trembling), then falls on it faster than an automatic slam. On the first tick the altitude
## reaches zero it lands: a slam of 2.2 x damage with three doses of the element (its area is 1.8 x the
## automatic one), then the elemental field it leaves, an extra shake and the sword sticks in the ground.
## The first tick of the fall is the tick after the rise ends, as in the prototype.
func _update_cataclysm(run: GameRun, dt: float) -> void:
	ultimate_time_left -= dt
	if not cataclysm_falling:
		_spring(ultimate_point, SwordDefs.COLOSSUS_WINDUP_SPRING_K, SwordDefs.COLOSSUS_WINDUP_SPRING_C, dt)
		altitude = lerpf(altitude, SwordDefs.COLOSSUS_ULT_RISE_ALTITUDE, minf(1.0, dt * SwordDefs.COLOSSUS_ULT_RISE_RATE))
		angle = SimMath.ang_lerp(angle, PI / 2.0 + sin(run.gameplay_time * SwordDefs.COLOSSUS_ULT_TREMBLE_RATE) * SwordDefs.COLOSSUS_ULT_TREMBLE, minf(1.0, dt * SwordDefs.COLOSSUS_WINDUP_TURN_RATE))
		if ultimate_time_left <= 0.0:
			cataclysm_falling = true
			fall_speed = SwordDefs.COLOSSUS_ULT_FALL_SPEED
		return
	position = position.lerp(ultimate_point, minf(1.0, dt * SwordDefs.COLOSSUS_GLIDE_RATE))
	fall_speed += SwordDefs.COLOSSUS_ULT_FALL_GRAVITY * dt
	altitude -= fall_speed * dt
	if altitude <= 0.0:
		altitude = 0.0
		position = ultimate_point
		var area: float = cataclysm_radius()
		run.slam(self, ultimate_point, area, SwordDefs.COLOSSUS_ULT_DAMAGE_FACTOR, SwordDefs.COLOSSUS_ULT_STACKS, true)
		run.add_field(FieldState.make(ultimate_point, area * SwordDefs.COLOSSUS_FIELD_RADIUS_FACTOR, spec.element, damage, SwordDefs.COLOSSUS_FIELD_LIFE))
		run.add_shake(SwordDefs.COLOSSUS_ULT_SHAKE)
		phase = Phase.STUCK
		timer = SwordDefs.COLOSSUS_ULT_STUCK_TIME


## The prototype's `WORLD.inflate(-20, -20).collidepoint(tip)`: the rectangle loses 20 px of width and
## of height (10 px per side), and pygame's rectangle contains its left and top edges and not its right
## and bottom ones, as Godot's `Rect2.has_point` does.
func _inside_skewer_arena(point: Vector2) -> bool:
	var margin: float = SwordDefs.PIKE_ULT_WALL_MARGIN
	return point.x >= GameRun.WORLD.position.x + margin and point.x < GameRun.WORLD.end.x - margin \
		and point.y >= GameRun.WORLD.position.y + margin and point.y < GameRun.WORLD.end.y - margin


func _add_maelstrom_cue(run: GameRun, kind: SimCue.Kind, reach: float, struck: int) -> void:
	var cue: SimCue = SimCue.make(kind, ultimate_point, Vector2.ZERO, struck)
	cue.radius = reach
	cue.element = spec.element
	run.add_cue(cue)
