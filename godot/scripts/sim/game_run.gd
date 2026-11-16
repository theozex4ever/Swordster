class_name GameRun
extends RefCounted
## The simulation of one run. Owns every run-owned entity and counter (player,
## equipped spirit swords, enemies, motes, wave schedule, time scales) and knows
## nothing about nodes, rendering, audio or input devices.
##
## Ported from game/main.py (`Game.update`, `Player`, `hit_enemy`, `kill`,
## `hurt_player`, `separate`, `parry_projectiles`, `afflict`, `update_conditions`) and stepped at a fixed 60 Hz; the prototype uses a
## variable step capped at 1/30. The update order inside `step()` is the
## prototype's, explicitly: player, then each sword slot in order (a running ultimate
## strikes during its sword's update), then enemies, separation, elemental conditions
## (damage over time, expiry), contacts, removal of
## the dead, projectiles, motes, counters and the wave director. Elemental fields (issue #15) tick right
## after the conditions (the prototype's `update_fields` follows `update_conditions`) and call the same `afflict`;
## a Colossus slam is `slam`. An armed enemy's death leaves its sword lying as a `PickupState` (issue #17); the pickups
## age after the motes, and `try_swap` (keys 1 / 2 / 3) claims the nearest one within reach. See docs/reference/fang-survival-loop.md,
## docs/reference/runners-brutes-crowd.md, docs/reference/spitters-projectiles-parries.md,
## docs/reference/viper-flurry.md, docs/reference/elemental-conditions.md and docs/reference/drops-swaps.md
## for the captured reference values and tolerances. Crowd and wall rules (separation, bowling, wall slams) are
## explicit circle geometry on the enemies' own positions and velocities, never
## rigid bodies. Enemy projectiles are run-owned `ProjectileState`s moved by
## `_update_projectiles`; any sword's swept attack parries them through the one
## `parry_projectiles(from, to, pad)` rule.
##
## Three clocks, as in the prototype:
##   * real time (`real_time`, `tick`): advances every unpaused tick, including
##     hitstop and slow motion. Shake decay and the hitstop/slow-motion timers run on it.
##   * gameplay time (`gameplay_time`): scaled time. Frozen during hitstop,
##     slowed during slow motion. Everything gameplay-related advances by it.
##   * paused: nothing advances.

const TICK_RATE: int = 60
const TICK_DT: float = 1.0 / 60.0
const WORLD: Rect2 = Rect2(0.0, 0.0, 2600.0, 1800.0)
## Reference view used by the camera clamp (prototype W x H).
const VIEW: Vector2 = Vector2(1280.0, 720.0)

const PLAYER_RADIUS: float = 14.0
const PLAYER_SPEED: float = 285.0
const ACCELERATION: float = 14.0
const PLAYER_MAX_HP: float = 100.0

const DASH_SPEED: float = 1000.0
const DASH_TIME: float = 0.14
const DASH_COOLDOWN: float = 0.65
const DASH_IFRAMES: float = 0.24

const HURT_IFRAMES: float = 0.8
const HURT_KNOCKBACK: float = 420.0
const HURT_HITSTOP: float = 0.07
const HURT_SHAKE: float = 0.45
const CONTACT_KNOCKBACK: float = 200.0
const CONTACT_STUN: float = 0.2

const DEATH_SLOWMO: float = 1.4
const DEATH_SLOWMO_SCALE: float = 0.25
## Gameplay seconds after death before the R key restarts (prototype `death_t > 0.8`).
const RESTART_DELAY: float = 0.8

const CRIT_MULTIPLIER: float = 2.0
const CRIT_KNOCK_BONUS: float = 1.3
const CRIT_HITSTOP_FACTOR: float = 1.5
const CRIT_SHAKE_BONUS: float = 0.1
const COMBO_WINDOW: float = 2.6
## The help overlay a new run starts with stays this long (prototype `help_t = 14`); H hides it, or shows it until hidden.
const HELP_SECONDS: float = 14.0
const HELP_FOREVER: float = 9999.0
## Crowd and wall rules (prototype `Game.separate` and `Game.wall_slam`).
## A launched enemy (stunned, faster than BOWL_MIN_SPEED, moving toward its
## neighbour) knocks into that neighbour; a stunned enemy hitting an arena wall
## faster than WALL_SLAM_MIN_SPEED takes damage.
const BOWL_MIN_SPEED: float = 340.0
const BOWL_IMPULSE: float = 0.55
const BOWL_DAMAGE: float = 3.0
const BOWL_SELF_DRAG: float = 0.6
const BOWL_STUN: float = 0.25
const BOWL_FLASH: float = 0.08
const BOWL_SHAKE: float = 0.06
const WALL_SLAM_MIN_SPEED: float = 380.0
const WALL_SLAM_BASE_DAMAGE: float = 6.0
const WALL_SLAM_DAMAGE_PER_SPEED: float = 0.04
const WALL_SLAM_STUN_CAP: float = 0.15
const WALL_SLAM_HITSTOP: float = 0.04
const WALL_SLAM_SHAKE: float = 0.18
## DEVELOPMENT FIXTURE: the dev shove imparts a Colossus-sized knock (SWORD_TYPES
## "colossus" knock 650) to every enemy within this radius of the player.
const DEV_SHOVE_KNOCK: float = 650.0
const DEV_SHOVE_RADIUS: float = 320.0
const DEV_SHOVE_SHAKE: float = 0.35
## A parried projectile freezes gameplay briefly (prototype `parry_projectiles`).
const PARRY_HITSTOP: float = 0.025
const MAX_QUEUED_CUES: int = 256

## Touch aiming with no enemy: this far ahead of the player (prototype `auto_aim`).
const AUTO_AIM_AHEAD: float = 300.0

const CAMERA_LOOKAHEAD: float = 0.12
const CAMERA_RATE: float = 7.0
const CAMERA_OVERSCAN: float = 140.0

enum Outcome { RUNNING, SURVIVED, LOST }

## What became of a Converge command (`try_converge`).
enum ConvergeResult {
	COMMANDED,
	## Paused or dead: no sword may be commanded.
	UNAVAILABLE,
	## The shared cooldown is still running.
	COOLING_DOWN,
}

## What became of a swap command (`try_swap`).
enum SwapResult {
	SWAPPED,
	## Paused or dead: nothing may be swapped.
	UNAVAILABLE,
	## No pickup is within reach (also produces a visible refusal cue).
	NO_PICKUP,
	## The slot holds no sword.
	NO_SWORD,
}

## What became of an ultimate command (`try_ultimate`).
enum UltimateResult {
	STARTED,
	## Paused or dead: no ultimate may start.
	UNAVAILABLE,
	## The slot holds no sword.
	NO_SWORD,
	## That slot's ultimate is already running.
	ACTIVE,
	## That slot's ultimate is still recharging.
	RECHARGING,
}

var scenario: RunScenario
## Gameplay randomness (crits, spawn points, knock directions). Cosmetic
## randomness never draws from it.
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

# --- clocks
## Fixed ticks that advanced real time (never advances while paused).
var tick: int = 0
## Real seconds the run has been unpaused (`tick * TICK_DT`).
var real_time: float = 0.0
## Scaled gameplay seconds: frozen during hitstop, slowed during slow motion.
var gameplay_time: float = 0.0
var paused: bool = false
## Real seconds of hitstop still to wait out; all gameplay is frozen meanwhile.
var hitstop: float = 0.0
## Real seconds of slow motion left, and the gameplay-time scale while it lasts.
var slowmo: float = 0.0
var slowmo_scale: float = 1.0
## Screen-shake intensity (decays in real time) and its directional kick.
var trauma: float = 0.0
var kick: Vector2 = Vector2.ZERO
## How many times this run was restarted; presenters use it to drop stale visuals.
var restarts: int = 0
## Whether the attack ranges are shown (Tab or G). Like the prototype's flag it belongs to the
## session, not the run: a restart keeps it.
var show_ranges: bool = false
## Seconds the help overlay has left (gameplay time, so it holds still while paused and in hitstop): it starts at HELP_SECONDS and
## fades over its last second; H toggles it. Display state only: nothing in the run reads it.
var help_left: float = HELP_SECONDS

# --- player
var position: Vector2 = Vector2.ZERO
var velocity: Vector2 = Vector2.ZERO
var facing: Vector2 = Vector2.RIGHT
var hp: float = PLAYER_MAX_HP
var max_hp: float = PLAYER_MAX_HP
var dead: bool = false
## Remaining invulnerability seconds (dash and damage both grant it).
var iframes: float = 0.0
var dash_left: float = 0.0
var dash_cooldown_left: float = 0.0
## Gameplay seconds until Converge may be commanded again (prototype `converge_cd`).
var converge_cooldown_left: float = 0.0
## Gameplay seconds since the player died.
var death_time: float = 0.0

# --- run-owned entities
var swords: Array[SwordState] = []
var enemies: Array[EnemyState] = []
var projectiles: Array[ProjectileState] = []
var motes: Array[Mote] = []
## The elemental ground Cataclysm leaves (run-owned: cleared on restart, frozen by pause and hitstop).
var fields: Array[FieldState] = []
## The spirit swords lying in the arena (run-owned: dropped by armed enemies, or put back by a swap; cleared on restart,
## frozen by pause and hitstop, slowed by slow motion like everything on gameplay time).
var pickups: Array[PickupState] = []
var director: WaveDirector

# --- counters
var kills: int = 0
## How many enemy orbs Colossus slams have destroyed this run (they are removed silently, so this is how it is observed).
var projectiles_cleared: int = 0
var combo: int = 0
var best_combo: int = 0
var combo_left: float = 0.0
var banner_title: String = ""
## The line under the banner's title (empty: none).
var banner_sub: String = ""
var banner_left: float = 0.0

## Camera centre (player plus velocity look-ahead, eased and clamped).
var camera: Vector2 = Vector2.ZERO

var _move_input: Vector2 = Vector2.ZERO
var _cues: Array[SimCue] = []
## How many cues of each kind this run produced, whether or not presentation
## drained them. Lets checks count events (kills, slams, bowls) exactly.
var _cue_counts: Dictionary[int, int] = {}
var _next_serial: int = 0
## Pickups number themselves apart from enemies, so a drop never shifts the serial an enemy spawns with.
var _next_pickup_serial: int = 0
## The scenarios `TOGGLE_ENCOUNTER` cycles through, in `RunScenario.ENCOUNTER_CYCLE`
## order (normal, crowd, spitters, conditions, warden, pike, colossus, drops): the one the run was made with keeps its own
## slot (a custom scenario is the "normal" slot, the wall encounter the crowd's).
var _encounter_scenarios: Array[RunScenario] = []


## The members `state_digest()` leaves out, each with the reason. Every other script variable of the run, and of every
## object it reaches, is in the digest by reflection (see StateDigest), so a member added anywhere is covered the day
## it is declared. Extending this list is a reviewed decision: `render_rate_checks.gd` pins its exact content.
const STATE_DIGEST_EXCLUDED: Dictionary[String, String] = {
	"scenario": "the run's static input (a restart may replace it); its effect is in the state it produced",
	"_encounter_scenarios": "static inputs the encounter toggle cycles through",
	"_cues": "the queue presentation drains; `_cue_counts` counts every cue whether or not it was drained",
	"show_ranges": "a session toggle of the presentation (Tab / G), not run state",
}


func _init(scenario_value: RunScenario = null) -> void:
	scenario = scenario_value if scenario_value != null else RunScenario.normal_run()
	_encounter_scenarios = [
		scenario if scenario.encounter == RunScenario.ENCOUNTER_NORMAL else RunScenario.normal_run(),
		scenario if scenario.encounter == RunScenario.ENCOUNTER_CROWD else RunScenario.crowd_encounter(),
		scenario if scenario.encounter == RunScenario.ENCOUNTER_SPITTERS else RunScenario.spitter_encounter(),
		scenario if scenario.encounter == RunScenario.ENCOUNTER_CONDITIONS else RunScenario.conditions_encounter(),
		scenario if scenario.encounter == RunScenario.ENCOUNTER_WARDEN else RunScenario.warden_encounter(),
		scenario if scenario.encounter == RunScenario.ENCOUNTER_PIKE else RunScenario.pike_encounter(),
		scenario if scenario.encounter == RunScenario.ENCOUNTER_COLOSSUS else RunScenario.colossus_encounter(),
		scenario if scenario.encounter == RunScenario.ENCOUNTER_DROPS else RunScenario.drops_encounter(),
	]
	if scenario.seed < 0:
		rng.randomize()
	_reset_state()


# ----------------------------------------------------------------- commands
## Applies a command. Movement while paused is remembered but has no effect
## until the run resumes; every other action has its own eligibility rule.
func apply(command: GameCommand) -> void:
	match command.kind:
		GameCommand.Kind.MOVE:
			_move_input = command.axis.limit_length(1.0)
		GameCommand.Kind.PAUSE:
			paused = true
		GameCommand.Kind.RESUME:
			paused = false
		GameCommand.Kind.TOGGLE_PAUSE:
			paused = not paused
		GameCommand.Kind.DASH:
			_try_dash()
		GameCommand.Kind.RESTART:
			restarts += 1
			_reset_state()
		GameCommand.Kind.ULTIMATE:
			try_ultimate(command.slot, auto_aim() if command.at_nearest else command.point)
		GameCommand.Kind.RESTART_FROM_KEY:
			if dead and death_time > RESTART_DELAY:
				restarts += 1
				_reset_state()
		GameCommand.Kind.SWAP:
			try_swap(command.slot)
		GameCommand.Kind.DEV_SHOVE:
			_dev_shove()
		GameCommand.Kind.CONVERGE:
			try_converge(auto_aim() if command.at_nearest else command.point)
		GameCommand.Kind.TOGGLE_RANGES:
			if not paused and not dead:
				show_ranges = not show_ranges
		GameCommand.Kind.TOGGLE_HELP:
			if not paused and not dead:
				help_left = 0.0 if help_left > 0.0 else HELP_FOREVER
		GameCommand.Kind.TOGGLE_ENCOUNTER:
			restart_with(_encounter_scenarios[RunScenario.ENCOUNTER_CYCLE.find(RunScenario.next_encounter(scenario.encounter))])


## Replaces the starting conditions and restarts the run from them. Like the
## Restart button it un-pauses.
func restart_with(new_scenario: RunScenario) -> void:
	scenario = new_scenario
	restarts += 1
	_reset_state()


## Triggers the ultimate of sword slot `slot` at a world point (prototype
## `Game.ultimate`). Refused while paused or dead, when the slot has no sword,
## while its ultimate is running (even if its recharge were zero) and while it
## recharges (that one also produces a visible refusal cue). A point beyond the
## type's range is pulled back onto it, measured from the player. The recharge
## starts at once and the sword blinks/launches the same tick, even during
## hitstop.
func try_ultimate(slot: int, point: Vector2) -> UltimateResult:
	if paused or dead:
		return UltimateResult.UNAVAILABLE
	if slot < 0 or slot >= swords.size():
		return UltimateResult.NO_SWORD
	var sword: SwordState = swords[slot]
	if sword.phase == SwordState.Phase.ULTIMATE:
		return UltimateResult.ACTIVE
	if sword.ultimate_cooldown_left > 0.0:
		add_cue(SimCue.make(SimCue.Kind.ULTIMATE_REFUSED, position, Vector2.ZERO, SimMath.py_round(sword.ultimate_cooldown_left)))
		return UltimateResult.RECHARGING
	var type_id: StringName = sword.spec.type_id
	var target: Vector2 = point
	var to_point: Vector2 = point - position
	if not SwordDefs.ultimate_is_shot(type_id) and to_point.length() > SwordDefs.ultimate_range(type_id):
		target = position + to_point.normalized() * SwordDefs.ultimate_range(type_id)
	var origin: Vector2 = sword.position
	sword.begin_ultimate(self, target)
	var cue: SimCue = SimCue.make(SimCue.Kind.ULTIMATE_STARTED, sword.position, SimMath.norm(sword.position - origin, rng, Vector2.RIGHT, true), slot)
	cue.origin = origin
	cue.spec = sword.spec
	add_cue(cue)
	return UltimateResult.STARTED


## Swaps the nearest pickup within LootDefs.PICKUP_REACH of the player (strictly closer; the first in the arena's
## order wins a tie) into sword slot `slot` (prototype `Game.swap`). The slot gets a new sword of exactly the pickup's type,
## element and rarity, which starts where the pickup lay and keeps the slot's ultimate recharge by FRACTION (see
## `SwordState.swapped_in`); the pickup is gone and the sword it replaces comes back as a pickup just below it, a
## uniform draw up to RETURN_SPREAD to either side. Refused while paused or dead and when the slot holds no
## sword; refused with a visible cue when no pickup is within reach. A refusal changes nothing.
func try_swap(slot: int) -> SwapResult:
	if paused or dead:
		return SwapResult.UNAVAILABLE
	var claimed: PickupState = nearest_pickup()
	if claimed == null:
		add_cue(SimCue.make(SimCue.Kind.SWAP_REFUSED, position))
		return SwapResult.NO_PICKUP
	if slot < 0 or slot >= swords.size():
		return SwapResult.NO_SWORD
	var replaced: SwordState = swords[slot]
	swords[slot] = SwordState.swapped_in(claimed.spec, claimed.position, replaced)
	pickups.erase(claimed)
	var returned_at: Vector2 = claimed.position + Vector2(rng.randf_range(-LootDefs.RETURN_SPREAD, LootDefs.RETURN_SPREAD), LootDefs.RETURN_DROP)
	pickups.append(PickupState.make(replaced.spec, returned_at, _next_pickup_serial))
	_next_pickup_serial += 1
	var cue: SimCue = SimCue.make(SimCue.Kind.SWORD_SWAPPED, claimed.position, Vector2.ZERO, slot)
	cue.spec = claimed.spec
	cue.origin = returned_at
	add_cue(cue)
	return SwapResult.SWAPPED


## The pickup the swap key would claim: the nearest one strictly within reach of the player (the first in the arena's
## order among equals), or null. The HUD uses it to show the card of what is up for grabs.
func nearest_pickup() -> PickupState:
	var nearest: PickupState = null
	var nearest_distance: float = INF
	for pickup: PickupState in pickups:
		var distance: float = (pickup.position - position).length()
		if distance < LootDefs.PICKUP_REACH and distance < nearest_distance:
			nearest = pickup
			nearest_distance = distance
	return nearest


## Converge (prototype `Game.converge`): every equipped sword is commanded to strike `point`. Refused
## while paused or dead and while the shared cooldown runs (silently, as in the prototype). A point
## beyond CONVERGE_RANGE is pulled back onto it, measured from the player. Each sword in the run's
## slot order takes the command or ignores it by its own state (`SwordState.command`); the cooldown
## starts at once whether or not any sword took it. Works during hitstop, like every command.
func try_converge(point: Vector2) -> ConvergeResult:
	if paused or dead:
		return ConvergeResult.UNAVAILABLE
	if converge_cooldown_left > 0.0:
		return ConvergeResult.COOLING_DOWN
	var target: Vector2 = point
	var to_point: Vector2 = point - position
	if to_point.length() > SwordDefs.CONVERGE_RANGE:
		target = position + to_point.normalized() * SwordDefs.CONVERGE_RANGE
	var taken: int = 0
	for sword: SwordState in swords:
		if sword.command(self, target):
			taken += 1
	converge_cooldown_left = SwordDefs.CONVERGE_COOLDOWN
	add_cue(SimCue.make(SimCue.Kind.CONVERGE, target, Vector2.ZERO, taken))
	return ConvergeResult.COMMANDED


## The touch aim point (prototype `Game.auto_aim`): the nearest living enemy, or
## 300 px ahead of the player.
func auto_aim() -> Vector2:
	var nearest: EnemyState = null
	var nearest_sq: float = INF
	for enemy: EnemyState in enemies:
		var dist_sq: float = (enemy.position - position).length_squared()
		if not enemy.dead and dist_sq < nearest_sq:
			nearest = enemy
			nearest_sq = dist_sq
	if nearest != null:
		return nearest.position
	return position + facing * AUTO_AIM_AHEAD


func _try_dash() -> void:
	if paused or dead or dash_cooldown_left > 0.0:
		return
	var heading: Vector2 = _move_input if _move_input.length_squared() > 0.0 else facing
	velocity = heading.normalized() * DASH_SPEED
	dash_left = DASH_TIME
	dash_cooldown_left = DASH_COOLDOWN
	iframes = maxf(iframes, DASH_IFRAMES)
	add_cue(SimCue.make(SimCue.Kind.DASH, position, heading.normalized()))


## DEVELOPMENT FIXTURE (scenario `dev_shove`): launches every living enemy
## within reach of the player away from it, with the knockback of a heavy
## Colossus blow and no damage, through the same impulse a sword hit uses.
func _dev_shove() -> void:
	if not scenario.dev_shove or paused or dead:
		return
	for enemy: EnemyState in enemies:
		var offset: Vector2 = enemy.position - position
		if enemy.dead or offset.length() > DEV_SHOVE_RADIUS:
			continue
		enemy.launch(SimMath.norm(offset, rng), DEV_SHOVE_KNOCK * enemy.knock_mult)
	add_shake(DEV_SHOVE_SHAKE)
	add_cue(SimCue.make(SimCue.Kind.SHOVE, position))


# --------------------------------------------------------------------- step
## Advances exactly one fixed tick. Does nothing while paused.
func step() -> void:
	if paused:
		return
	tick += 1
	real_time += TICK_DT
	trauma = maxf(0.0, trauma - TICK_DT * 1.6)
	kick *= exp(-TICK_DT * 12.0)
	if hitstop > 0.0:
		hitstop -= TICK_DT
		return
	var dt: float = TICK_DT
	if slowmo > 0.0:
		slowmo -= dt
		dt *= slowmo_scale
	gameplay_time += dt
	help_left -= dt
	if dead:
		death_time += dt

	_update_player(dt)
	var sword_count: int = swords.size()
	for i: int in sword_count:
		swords[i].update(self, dt, i, sword_count)
	for enemy: EnemyState in enemies:
		enemy.update(self, dt)
	_separate()
	_update_conditions(dt)
	_update_fields(dt)
	_resolve_contacts()
	var alive: Array[EnemyState] = []
	for enemy: EnemyState in enemies:
		if not enemy.dead:
			alive.append(enemy)
	enemies = alive
	_update_projectiles(dt)
	_update_motes(dt)
	_update_pickups(dt)

	combo_left -= dt
	if combo_left <= 0.0:
		combo = 0
	converge_cooldown_left = maxf(0.0, converge_cooldown_left - dt)
	if banner_left > 0.0:
		banner_left -= dt
		if banner_left <= 0.0:
			banner_title = ""
			banner_sub = ""
	director.update(self, dt)
	_update_camera(dt)


func _update_player(dt: float) -> void:
	var move: Vector2 = Vector2.ZERO if dead else _move_input
	if move.length_squared() > 0.0:
		facing = move.normalized()
	iframes = maxf(0.0, iframes - dt)
	dash_cooldown_left = maxf(0.0, dash_cooldown_left - dt)
	if dash_left > 0.0:
		dash_left -= dt
	else:
		velocity += (move * PLAYER_SPEED - velocity) * minf(1.0, dt * ACCELERATION)
	position += velocity * dt
	var inner: Rect2 = WORLD.grow(-PLAYER_RADIUS)
	position = position.clamp(inner.position, inner.end)


func _update_camera(dt: float) -> void:
	var goal: Vector2 = position + velocity * CAMERA_LOOKAHEAD
	camera += (goal - camera) * (1.0 - exp(-dt * CAMERA_RATE))
	var half: Vector2 = VIEW * 0.5 - Vector2(CAMERA_OVERSCAN, CAMERA_OVERSCAN)
	camera = camera.clamp(WORLD.position + half, WORLD.end - half)


## Enemies touching the player hurt it (unless invulnerable) and are knocked
## back regardless. A frozen enemy does neither: it neither hurts nor is pushed. Prototype order: after
## enemy movement, separation and the conditions' damage over time.
func _resolve_contacts() -> void:
	for enemy: EnemyState in enemies:
		if not enemy.dead and not enemy.conditions.is_frozen() and (enemy.position - position).length() < enemy.radius + PLAYER_RADIUS:
			hurt_player(enemy.damage, enemy.position)
			enemy.velocity = SimMath.norm(enemy.position - position, rng) * CONTACT_KNOCKBACK
			enemy.stun = CONTACT_STUN


## Fires an orb (a spitter's shot). The new projectile flies on the same tick,
## as in the prototype where the projectile loop follows the enemy updates.
func spawn_projectile(at: Vector2, velocity_value: Vector2) -> ProjectileState:
	var projectile: ProjectileState = ProjectileState.make(at, velocity_value)
	projectiles.append(projectile)
	add_cue(SimCue.make(SimCue.Kind.PROJECTILE_FIRED, at, velocity_value.normalized()))
	return projectile


## Prototype order: every projectile moves, then ends by expiry or by leaving the
## arena, or else hurts the player. An invulnerable or dead player is passed
## through (the projectile flies on). A projectile that was already parried or
## cleared this tick is not moved or counted again: it resolves exactly once.
func _update_projectiles(dt: float) -> void:
	for projectile: ProjectileState in projectiles:
		if projectile.is_resolved():
			continue
		projectile.position += projectile.velocity * dt
		projectile.life -= dt
		if projectile.life <= 0.0:
			projectile.resolve(ProjectileState.Fate.EXPIRED)
		elif not WORLD.has_point(projectile.position):
			projectile.resolve(ProjectileState.Fate.LEFT_ARENA)
		elif iframes <= 0.0 and not dead and (projectile.position - position).length() < projectile.radius + PLAYER_RADIUS:
			projectile.resolve(ProjectileState.Fate.HIT_PLAYER)
			hurt_player(ProjectileState.DAMAGE, projectile.position)
	var flying: Array[ProjectileState] = []
	for projectile: ProjectileState in projectiles:
		if not projectile.is_resolved():
			flying.append(projectile)
	projectiles = flying


## The shared parry rule (prototype `parry_projectiles`): every projectile whose
## centre is within its radius plus `pad` of the segment `from`-`to` is destroyed
## with a spark cue, and gameplay freezes briefly. Swords pass the segment their
## attack swept this tick (Fang: previous position to tip; Warden: each sub-arc;
## Pike: tail to tip, for the thrust and again for the Skewer). Returns how many were parried. It does not check what the
## sword hit this tick: the caller decides whether this tick parries.
func parry_projectiles(from: Vector2, to: Vector2, pad: float) -> int:
	var parried: int = 0
	for projectile: ProjectileState in projectiles:
		if projectile.is_resolved():
			continue
		if SimMath.seg_dist(projectile.position, from, to) < projectile.radius + pad:
			projectile.resolve(ProjectileState.Fate.PARRIED)
			parried += 1
			add_cue(SimCue.make(SimCue.Kind.PROJECTILE_PARRIED, projectile.position, SimMath.norm(-projectile.velocity, rng, Vector2.LEFT, true)))
			hitstop = maxf(hitstop, PARRY_HITSTOP)
	return parried


## A Colossus slam (prototype `Game.slam`) at `point`: every enemy within `radius` plus its own is struck
## by a heavy blow of `damage x boost x power x fall` with `knock x fall`, where `fall` is 1 minus
## SLAM_FALLOFF x how far out (0..1 of `radius`) it stands, and takes `stacks` doses of the element; every orb
## within `radius` is cleared. As in the prototype the enemies are taken in the run's order and the dead are
## not skipped (`hit_enemy` ignores them, but a corpse still counts as something in the area, which sets
## the hitstop and shake). Hitstop and shake are the sword type's if anything was in the area, else a short one.
## `cataclysm` only tells the cue which kind of slam it was. Returns how many enemies were in the area.
func slam(sword: SwordState, point: Vector2, radius: float, power: float, stacks: int, cataclysm: bool) -> int:
	var in_area: int = 0
	for enemy: EnemyState in enemies:
		var offset: Vector2 = enemy.position - point
		var dist: float = offset.length()
		if dist < radius + enemy.radius:
			var fall: float = 1.0 - SwordDefs.COLOSSUS_SLAM_FALLOFF * clampf(dist / radius, 0.0, 1.0)
			hit_enemy(enemy, sword.damage * sword.boost * power * fall, offset, sword.knock * fall, sword, true, stacks)
			in_area += 1
	clear_projectiles_in_circle(point, radius)
	hitstop = maxf(hitstop, sword.hit_stop if in_area > 0 else SwordDefs.COLOSSUS_SLAM_EMPTY_HITSTOP)
	add_shake(sword.hit_shake if in_area > 0 else SwordDefs.COLOSSUS_SLAM_EMPTY_SHAKE, Vector2.DOWN, true)
	var cue: SimCue = SimCue.make(SimCue.Kind.COLOSSUS_SLAM, point, Vector2.DOWN, in_area, cataclysm)
	cue.radius = radius
	cue.element = sword.spec.element
	add_cue(cue)
	return in_area


## Adds an elemental ground field to the run (Cataclysm's), announcing it.
func add_field(field: FieldState) -> void:
	fields.append(field)
	var cue: SimCue = SimCue.make(SimCue.Kind.FIELD_CREATED, field.position)
	cue.radius = field.radius
	cue.element = field.element
	add_cue(cue)


## Elemental fields (prototype `update_fields`), right after the conditions: every field loses life and its
## dose clock; when the clock runs out (the very tick a field is made, since it starts at zero) it is
## set back to FIELD_PERIOD and every LIVING enemy whose centre is within the field's radius plus its own gets one
## dose of its element through `afflict`, in the run's order (a corpse of this tick is skipped). A field that
## has run out of life still pulses on its last tick, and is removed after the loop.
func _update_fields(dt: float) -> void:
	for field: FieldState in fields:
		field.life -= dt
		field.tick_left -= dt
		if field.tick_left <= 0.0:
			field.tick_left = SwordDefs.COLOSSUS_FIELD_PERIOD
			var dosed: int = 0
			for enemy: EnemyState in enemies:
				if not enemy.dead and field.reaches(enemy):
					afflict(enemy, field.element, field.power)
					dosed += 1
			var cue: SimCue = SimCue.make(SimCue.Kind.FIELD_PULSED, field.position, Vector2.ZERO, dosed)
			cue.radius = field.radius
			cue.element = field.element
			add_cue(cue)
	var remaining: Array[FieldState] = []
	for field: FieldState in fields:
		if field.life > 0.0:
			remaining.append(field)
	fields = remaining


## Destroys every projectile whose centre is inside the circle, silently (the
## prototype's Colossus slam: `pr.dead = True` within the blast, no parry
## feedback of its own). Returns how many were cleared.
func clear_projectiles_in_circle(center: Vector2, radius: float) -> int:
	var cleared: int = 0
	for projectile: ProjectileState in projectiles:
		if not projectile.is_resolved() and (projectile.position - center).length() < radius:
			projectile.resolve(ProjectileState.Fate.CLEARED)
			cleared += 1
	projectiles_cleared += cleared
	return cleared


func _update_motes(dt: float) -> void:
	for mote: Mote in motes:
		mote.age += dt
		var to_player: Vector2 = position - mote.position
		var dist: float = to_player.length()
		if mote.age > Mote.HOMING_DELAY:
			mote.velocity += SimMath.norm(to_player, rng) * 2400.0 * dt
			mote.velocity *= exp(-dt * 2.5)
		else:
			mote.velocity *= exp(-dt * 5.0)
		mote.position += mote.velocity * dt
		if dist < Mote.COLLECT_RADIUS and mote.age > Mote.HOMING_DELAY:
			mote.collected = true
			if not dead:
				hp = minf(max_hp, hp + Mote.HEAL)
				add_cue(SimCue.make(SimCue.Kind.MOTE_COLLECTED, mote.position))
	var remaining: Array[Mote] = []
	for mote: Mote in motes:
		if not mote.collected:
			remaining.append(mote)
	motes = remaining


## Every pickup ages and counts down its life; the expired are removed (prototype update: `t += dt`, `life -= dt`, then
## only `life > 0` stays), on gameplay time, so hitstop and pause freeze them and slow motion slows them.
func _update_pickups(dt: float) -> void:
	var lying: Array[PickupState] = []
	for pickup: PickupState in pickups:
		pickup.age += dt
		pickup.life -= dt
		if pickup.life > 0.0:
			lying.append(pickup)
	pickups = lying


## Pairwise enemy push-apart (heavier = r*r moves less) with the prototype's
## "bowling" transfer from launched enemies.
func _separate() -> void:
	var count: int = enemies.size()
	for i: int in count:
		var a: EnemyState = enemies[i]
		for j: int in range(i + 1, count):
			var b: EnemyState = enemies[j]
			var d: Vector2 = b.position - a.position
			var reach: float = a.radius + b.radius
			if absf(d.x) > reach or absf(d.y) > reach:
				continue
			var dist: float = d.length()
			if dist >= reach or dist == 0.0:
				continue
			var normal: Vector2 = d / dist
			var overlap: float = reach - dist
			var mass_a: float = a.radius * a.radius
			var mass_b: float = b.radius * b.radius
			a.position -= normal * overlap * mass_b / (mass_a + mass_b)
			b.position += normal * overlap * mass_a / (mass_a + mass_b)
			_bowl(a, b, normal, 1.0)
			_bowl(b, a, normal, -1.0)


## One direction of a crowd collision: `launched` is a stunned, fast enemy moving
## toward `hit` (`sign_value` orients the shared normal). It hands over momentum
## scaled by relative size, stuns and damages `hit`, and slows itself. Bowling
## damage can kill `hit` here; `kill` keeps that to exactly once.
func _bowl(launched: EnemyState, hit: EnemyState, normal: Vector2, sign_value: float) -> void:
	if launched.stun > 0.0 and launched.velocity.length() > BOWL_MIN_SPEED and launched.velocity.dot(normal * sign_value) > 0.0:
		hit.velocity += launched.velocity * BOWL_IMPULSE * launched.radius / hit.radius * 0.6
		hit.stun = maxf(hit.stun, BOWL_STUN)
		hit.flash = BOWL_FLASH
		hit.hp -= BOWL_DAMAGE
		launched.velocity *= BOWL_SELF_DRAG
		add_shake(BOWL_SHAKE)
		add_cue(SimCue.make(SimCue.Kind.BOWLED, (launched.position + hit.position) * 0.5, SimMath.norm(launched.velocity, rng, Vector2.RIGHT, true), int(BOWL_DAMAGE)))
		if hit.hp <= 0.0 and not hit.dead:
			kill(hit, SimMath.norm(launched.velocity, rng), true)


# ------------------------------------------------------------------- combat
## A sword hits an enemy (prototype `hit_enemy`): critical roll, the frozen bonus, rounding
## (Python round-half-even), knockback, stun, hitstop and shake; a blow that leaves the
## enemy alive then applies the sword's element (`stacks` doses of it). A dead enemy
## ignores further hits so its death and rewards resolve exactly once.
## A `heavy` blow (a Fang flurry dart, a Maelstrom beat or burst) flashes the enemy longer and,
## unlike a normal hit, causes no hitstop and no hit shake of its own (the caller adds its own).
## A normal hit's hitstop and shake are the sword type's own (Fang 0.02 / 0.07, Warden 0.05 / 0.16).
func hit_enemy(enemy: EnemyState, raw_damage: float, direction: Vector2, knock: float, sword: SwordState, heavy: bool = false, stacks: int = 1) -> void:
	if enemy.dead:
		return
	var crit: bool = rng.randf() < scenario.crit_chance
	var dmg: float = raw_damage
	if crit:
		dmg *= CRIT_MULTIPLIER
	var shattered: bool = enemy.conditions.is_frozen()
	if shattered:
		dmg *= ConditionDefs.SHATTER
	var dealt: int = maxi(1, SimMath.py_round(dmg))
	enemy.hp -= float(dealt)
	enemy.flash = SwordDefs.HEAVY_HIT_FLASH if heavy else SwordDefs.NORMAL_HIT_FLASH
	enemy.squash = 1.0
	var d: Vector2 = SimMath.norm(direction, rng)
	var force: float = knock * enemy.knock_mult * (CRIT_KNOCK_BONUS if crit else 1.0)
	enemy.launch(d, force)
	# A normal blow's feedback is the sword type's own (prototype `sword.t["hitstop"]` / `["shake"]`).
	if not heavy:
		var stop: float = (sword.hit_stop if sword != null else SwordDefs.FANG_HITSTOP) * (CRIT_HITSTOP_FACTOR if crit else 1.0)
		hitstop = maxf(hitstop, stop)
		add_shake((sword.hit_shake if sword != null else SwordDefs.FANG_SHAKE) + (CRIT_SHAKE_BONUS if crit else 0.0), d, true)
	var hit_cue: SimCue = SimCue.make(SimCue.Kind.ENEMY_HIT, enemy.position, d, dealt, crit)
	hit_cue.heavy = heavy
	hit_cue.spec = sword.spec if sword != null else null
	hit_cue.radius = enemy.radius
	if shattered:
		hit_cue.element = ConditionDefs.ICE
	add_cue(hit_cue)
	if enemy.hp <= 0.0:
		kill(enemy, d, heavy or crit)
	elif sword != null:
		afflict(enemy, sword.spec.element, sword.damage, stacks)


## Applies `stacks` doses of an element to a living enemy (prototype `afflict`); `power`
## is the source's base damage (a sword's type damage times its rarity). Sword hits and
## elemental fields both come through here. Does nothing when the scenario is a
## condition-free fixture. Freezing is announced with a cue and slows the enemy at once.
func afflict(enemy: EnemyState, element: StringName, power: float, stacks: int = 1) -> void:
	if not scenario.conditions_enabled or enemy.dead:
		return
	if enemy.conditions.apply(element, power, stacks):
		enemy.velocity *= ConditionDefs.FREEZE_VELOCITY_KEEP
		var cue: SimCue = SimCue.make(SimCue.Kind.ENEMY_FROZEN, enemy.position)
		cue.element = ConditionDefs.ICE
		add_cue(cue)


## Burn and poison damage over time, chill and freeze expiry (prototype
## `update_conditions`). Damage here is neither critical nor frozen-boosted. An enemy it
## kills dies through `kill` like any other, spreading its fire if it burned.
func _update_conditions(dt: float) -> void:
	for enemy: EnemyState in enemies:
		if enemy.dead:
			continue
		var dealt: int = enemy.conditions.tick(dt)
		if dealt < 1:
			continue
		enemy.hp -= float(dealt)
		var cue: SimCue = SimCue.make(SimCue.Kind.CONDITION_DAMAGE, enemy.position, Vector2.ZERO, dealt)
		cue.element = enemy.conditions.dominant_element()
		add_cue(cue)
		if enemy.hp <= 0.0:
			kill(enemy, Vector2.UP)


## Resolves an enemy's death exactly once: counters, combo and healing motes, and the
## fire a burning enemy leaves behind. Every cause of death (a blow, bowling, a wall slam,
## damage over time) comes through here.
func kill(enemy: EnemyState, direction: Vector2, big: bool = false) -> void:
	if enemy.dead:
		return
	enemy.dead = true
	kills += 1
	combo += 1
	combo_left = COMBO_WINDOW
	best_combo = maxi(best_combo, combo)
	if WaveDefs.CHAIN_MILESTONES.has(combo):
		add_cue(SimCue.make(SimCue.Kind.CHAIN_MILESTONE, position, Vector2.ZERO, combo))
	for i: int in 3:
		motes.append(Mote.scatter(enemy.position, rng))
	var killed: SimCue = SimCue.make(SimCue.Kind.ENEMY_KILLED, enemy.position, direction, 0, big)
	killed.enemy_kind = enemy.kind
	killed.radius = enemy.radius
	add_cue(killed)
	if enemy.conditions.is_burning():
		_spread_fire(enemy)
	if enemy.conditions.is_frozen():
		add_cue(SimCue.make(SimCue.Kind.ENEMY_SHATTERED, enemy.position))
	if enemy.armed != null:
		# The sword it carried lies where it fell. `kill` runs once per enemy, so it drops exactly once.
		pickups.append(PickupState.make(enemy.armed, enemy.position, _next_pickup_serial))
		_next_pickup_serial += 1
		var drop: SimCue = SimCue.make(SimCue.Kind.SWORD_DROPPED, enemy.position)
		drop.spec = enemy.armed
		add_cue(drop)


## A burning enemy's death ignites the living enemies beside it (prototype `kill`). It
## only sets burns; an ignited enemy dies, and spreads in turn, by its own damage over
## time, so a chain advances one death at a time.
func _spread_fire(source: EnemyState) -> void:
	for other: EnemyState in enemies:
		if other != source and not other.dead and (other.position - source.position).length() < source.radius + other.radius + ConditionDefs.SPREAD_REACH:
			other.conditions.ignite_from_spread(source.conditions.burn_dps)
	var cue: SimCue = SimCue.make(SimCue.Kind.FIRE_SPREAD, source.position)
	cue.element = ConditionDefs.FIRE
	add_cue(cue)


## An enemy launched into the arena wall (prototype `wall_slam`). `speed` is
## its speed on arrival; damage grows with how far it exceeds the threshold.
func wall_slam(enemy: EnemyState, speed: float) -> void:
	enemy.stun = minf(enemy.stun, WALL_SLAM_STUN_CAP)
	var dealt: int = SimMath.py_round(WALL_SLAM_BASE_DAMAGE + (speed - WALL_SLAM_MIN_SPEED) * WALL_SLAM_DAMAGE_PER_SPEED)
	enemy.hp -= float(dealt)
	enemy.flash = 0.12
	add_shake(WALL_SLAM_SHAKE)
	hitstop = maxf(hitstop, WALL_SLAM_HITSTOP)
	add_cue(SimCue.make(SimCue.Kind.WALL_SLAM, enemy.position, Vector2.ZERO, dealt))
	if enemy.hp <= 0.0 and not enemy.dead:
		kill(enemy, SimMath.norm(-enemy.velocity, rng), true)


## Damage to the player (prototype `hurt_player`): ignored while invulnerable
## or dead; grants invulnerability, knockback, hitstop and shake; dying starts
## the slow-motion death.
func hurt_player(amount: int, source: Vector2) -> void:
	if iframes > 0.0 or dead:
		return
	hp -= float(amount)
	iframes = HURT_IFRAMES
	var d: Vector2 = SimMath.norm(position - source, rng)
	velocity = d * HURT_KNOCKBACK
	add_shake(HURT_SHAKE, d, true)
	hitstop = maxf(hitstop, HURT_HITSTOP)
	add_cue(SimCue.make(SimCue.Kind.PLAYER_HURT, position, d, amount))
	if hp <= 0.0:
		hp = 0.0
		dead = true
		slowmo = DEATH_SLOWMO
		slowmo_scale = DEATH_SLOWMO_SCALE
		death_time = 0.0
		add_cue(SimCue.make(SimCue.Kind.PLAYER_DIED, position))


func add_shake(amount: float, direction: Vector2 = Vector2.ZERO, with_kick: bool = false) -> void:
	trauma = minf(1.0, trauma + amount)
	if with_kick:
		kick += SimMath.norm(direction, rng) * amount * 16.0


func set_banner(title: String, seconds: float, sub: String = "") -> void:
	banner_title = title
	banner_sub = sub
	banner_left = seconds


func next_serial() -> int:
	_next_serial += 1
	return _next_serial


func add_cue(cue: SimCue) -> void:
	_cue_counts[cue.kind] = _cue_counts.get(cue.kind, 0) + 1
	if _cues.size() < MAX_QUEUED_CUES:
		_cues.append(cue)


## Total cues of `kind` produced since the run (re)started, drained or not.
func cue_count(kind: SimCue.Kind) -> int:
	return _cue_counts.get(kind, 0)


## Drains the cues produced since the last call (presentation/audio only).
func take_cues() -> Array[SimCue]:
	var taken: Array[SimCue] = _cues
	_cues = []
	return taken


func outcome() -> Outcome:
	if dead:
		return Outcome.LOST
	if director.survived:
		return Outcome.SURVIVED
	return Outcome.RUNNING


## Whether the R key would restart right now.
func can_restart_from_key() -> bool:
	return dead and death_time > RESTART_DELAY


## Everything that decides how the run goes on, as plain values (reflection over every member, see StateDigest and
## STATE_DIGEST_EXCLUDED): the player with its dash, cooldowns and iframes, every sword's full state, every enemy with its
## conditions, projectiles, fields, pickups, motes, the wave director (queue, markers, timers), Converge's cooldown, the
## counters, the clocks, and the gameplay random generator's seed and state.
func state_digest() -> Dictionary:
	return StateDigest.of(self, STATE_DIGEST_EXCLUDED)


## A 64-bit fingerprint of exactly the state `state_digest()` describes, cheap enough to take on every tick (see
## StateDigest.fingerprint).
func state_fingerprint() -> int:
	return StateDigest.fingerprint(self, STATE_DIGEST_EXCLUDED)


## Observation adapter for checks: plain values only.
func snapshot() -> Dictionary:
	var sword_positions: Array[Vector2] = []
	var sword_phases: Array[int] = []
	var ultimate_cooldowns: Array[float] = []
	for sword: SwordState in swords:
		sword_positions.append(sword.position)
		sword_phases.append(sword.phase)
		ultimate_cooldowns.append(sword.ultimate_cooldown_left)
	var enemy_positions: Array[Vector2] = []
	var enemy_hp: Array[float] = []
	for enemy: EnemyState in enemies:
		enemy_positions.append(enemy.position)
		enemy_hp.append(enemy.hp)
	var projectile_positions: Array[Vector2] = []
	for projectile: ProjectileState in projectiles:
		projectile_positions.append(projectile.position)
	return {
		"tick": tick,
		"real_time": real_time,
		"gameplay_time": gameplay_time,
		"paused": paused,
		"restarts": restarts,
		"position": position,
		"velocity": velocity,
		"facing": facing,
		"move_input": _move_input,
		"hp": hp,
		"dead": dead,
		"iframes": iframes,
		"dash_left": dash_left,
		"dash_cooldown_left": dash_cooldown_left,
		"converge_cooldown_left": converge_cooldown_left,
		"hitstop": hitstop,
		"slowmo": slowmo,
		"camera": camera,
		"kills": kills,
		"combo": combo,
		"best_combo": best_combo,
		"wave": director.wave,
		"outcome": outcome(),
		"enemy_positions": enemy_positions,
		"enemy_hp": enemy_hp,
		"projectile_positions": projectile_positions,
		"mote_count": motes.size(),
		"pickup_count": pickups.size(),
		"field_count": fields.size(),
		"field_lives": fields.map(func(field: FieldState) -> float: return field.life),
		"sword_positions": sword_positions,
		"sword_phases": sword_phases,
		"ultimate_cooldowns": ultimate_cooldowns,
	}


func _reset_state() -> void:
	if scenario.seed >= 0:
		rng.seed = scenario.seed
	tick = 0
	real_time = 0.0
	gameplay_time = 0.0
	paused = false
	hitstop = 0.0
	slowmo = 0.0
	slowmo_scale = 1.0
	trauma = 0.0
	kick = Vector2.ZERO
	position = scenario.start_position
	velocity = Vector2.ZERO
	facing = Vector2.RIGHT
	max_hp = PLAYER_MAX_HP
	hp = max_hp if scenario.start_health < 0.0 else minf(max_hp, scenario.start_health)
	dead = false
	iframes = 0.0
	dash_left = 0.0
	dash_cooldown_left = 0.0
	converge_cooldown_left = 0.0
	death_time = 0.0
	help_left = HELP_SECONDS
	kills = 0
	projectiles_cleared = 0
	combo = 0
	best_combo = 0
	combo_left = 0.0
	banner_title = ""
	banner_sub = ""
	banner_left = 0.0
	camera = position
	_move_input = Vector2.ZERO
	_cues = []
	_cue_counts = {}
	_next_serial = 0
	_next_pickup_serial = 0
	pickups = []
	swords = []
	for i: int in scenario.loadout.size():
		var start_cd: float = scenario.sword_start_cooldowns[i] if i < scenario.sword_start_cooldowns.size() else rng.randf_range(0.2, 0.6)
		swords.append(SwordState.equip(scenario.loadout[i], position, start_cd))
	enemies = []
	projectiles = []
	for at: Vector2 in scenario.initial_husks:
		enemies.append(EnemyState.husk(at, 1, scenario.enemy_speed_scale, next_serial()))
	for placement: EnemyPlacement in scenario.initial_enemies:
		var cooldown: float = placement.shoot_cooldown
		if cooldown < 0.0 and placement.kind == EnemyDefs.SPITTER:
			cooldown = rng.randf_range(EnemyDefs.SPITTER_FIRST_COOLDOWN_MIN, EnemyDefs.SPITTER_FIRST_COOLDOWN_MAX)
		var enemy: EnemyState = EnemyState.make(placement.kind, placement.position, placement.wave, placement.speed_scale * scenario.enemy_speed_scale, next_serial(), placement.phase, maxf(cooldown, 0.0), placement.armed)
		enemy.charge = placement.charge
		enemy.velocity = placement.velocity
		enemy.stun = placement.stun
		if placement.hp >= 0.0:
			enemy.hp = placement.hp
		enemies.append(enemy)
	fields = []
	motes = []
	for at: Vector2 in scenario.initial_motes:
		motes.append(Mote.scatter(at, rng))
	director = WaveDirector.new(scenario)
