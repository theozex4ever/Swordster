class_name SpitterAndParryChecks
extends RefCounted
## Game-run behavioural checks for spitters, projectiles and parries (issue #10).
## Like the earlier slices' checks, every check drives the real `GameRun` through
## `GameCommand`s (or the real Main scene), advances fixed ticks and observes
## outcomes. Comparison values come from the Python prototype's captured
## reference (res://tests/reference/spitters_and_parries.json, recorded by
## tools/reference/capture_spitters_and_parries.py), which also carries each
## case's fixture (`setup`), so no starting number is copied into this file.
## Tolerances and deliberate exceptions: docs/reference/spitters-projectiles-parries.md.

const REFERENCE_PATH: String = "res://tests/reference/spitters_and_parries.json"
const PROBE_SCRIPT: String = "res://tests/frame_rate_probe.gd"

## Same-algorithm comparisons at the prototype's 60 FPS step.
const POSITION_TOL: float = 0.05  # px
const VELOCITY_TOL: float = 0.05  # px/s
const SCALAR_TOL: float = 0.002  # health, timers, shake, stun, charge
const TICK_TOL: int = 1
const PROBE_FRAME_RATES: Array[int] = [5, 20, 60, 240]
## Where the strike fixtures park the sword (far from the player, like the capture).
const CENTER: Vector2 = Vector2(1300.0, 900.0)

var _check: Callable
var _tree: SceneTree
var _ref: Dictionary = {}


func _init(check_function: Callable, tree: SceneTree) -> void:
	_check = check_function
	_tree = tree


func run_all() -> void:
	var file: FileAccess = FileAccess.open(REFERENCE_PATH, FileAccess.READ)
	if file == null:
		_ok("spitter reference file loads", false, REFERENCE_PATH)
		return
	_ref = JSON.parse_string(file.get_as_text())
	_ok("spitter reference file parses", not _ref.is_empty())
	_check_reference_scope()
	_check_definitions()
	_check_movement()
	_check_shooting()
	_check_charge_rules()
	_check_projectile_flight()
	_check_player_hit()
	_check_spitter_as_enemy()
	_check_fang_parry_geometry()
	_check_fang_parry_in_flight()
	_check_hit_versus_parry()
	_check_fang_auto()
	_check_exactly_once()
	_check_paused_and_dead()
	_check_shared_parry_rule()
	_check_encounter_and_cycle()
	_check_normal_run_unchanged()
	await _check_main_scene()
	await _check_visual_independence()
	await _check_render_rates()


# --------------------------------------------------------------- helpers
func _ok(label: String, condition: bool, detail: String = "") -> void:
	_check.call(label, condition, detail)


func _near(a: float, b: float, tolerance: float) -> bool:
	return absf(a - b) <= tolerance


func _steps(run: GameRun, count: int) -> void:
	for i: int in count:
		run.step()


func _placement(setup: Dictionary) -> EnemyPlacement:
	var placement: EnemyPlacement = EnemyPlacement.make(StringName(setup["kind"]), Vector2(float(setup["x"]), float(setup["y"])))
	placement.velocity = Vector2(float(setup["vx"]), float(setup["vy"]))
	placement.stun = float(setup["stun"])
	placement.phase = float(setup["t"])
	placement.wave = int(setup["wave"])
	placement.speed_scale = float(setup["speed_scale"])
	placement.hp = float(setup["hp"])
	placement.shoot_cooldown = float(setup["shoot_cd"])
	placement.charge = float(setup["charge"])
	return placement


## No waves and no swords: only what the case itself puts in the arena.
func _arena(setups: Array, swords: Array[SwordSpec] = []) -> RunScenario:
	var scenario: RunScenario = RunScenario.new()
	scenario.seed = 31
	scenario.waves_enabled = false
	scenario.crit_chance = 0.0
	scenario.loadout = swords
	var placements: Array[EnemyPlacement] = []
	for setup: Variant in setups:
		placements.append(_placement(setup as Dictionary))
	scenario.initial_enemies = placements
	return scenario


## Sets a projectile from a reference `setup` ({x, y, vx, vy, life}).
func _shoot(run: GameRun, setup: Dictionary) -> ProjectileState:
	var projectile: ProjectileState = run.spawn_projectile(Vector2(float(setup["x"]), float(setup["y"])), Vector2(float(setup["vx"]), float(setup["vy"])))
	projectile.life = float(setup["life"])
	return projectile


func _gone(run: GameRun, projectile: ProjectileState) -> bool:
	return not run.projectiles.has(projectile)


## A run holding exactly one Fang in mid-strike (reference `sword` setup), as the
## capture builds it. The strike then runs through the real `SwordState` update.
func _strike_run(sword_setup: Dictionary, enemies: Array = []) -> GameRun:
	var specs: Array[SwordSpec] = [SwordSpec.make(&"fang", int(sword_setup["rarity"]), &"fire")]
	var scenario: RunScenario = _arena(enemies, specs)
	scenario.sword_start_cooldowns = [5.0]
	var run: GameRun = GameRun.new(scenario)
	var sword: SwordState = run.swords[0]
	sword.position = Vector2(float(sword_setup["x"]), float(sword_setup["y"]))
	sword.phase = SwordState.Phase.STRIKE
	sword.timer = float(sword_setup["timer"])
	sword.dir = Vector2(float(sword_setup["dx"]), float(sword_setup["dy"]))
	sword.velocity = sword.dir * SwordDefs.FANG_SPEED
	sword.aim = Vector2(float(sword_setup["aimx"]), float(sword_setup["aimy"]))
	sword.target = null
	sword.cooldown_left = 5.0
	return run


func _ticks_close(actual: int, expected: int) -> bool:
	return absi(actual - expected) <= TICK_TOL


func _phase_name(sword: SwordState) -> String:
	return SwordState.Phase.keys()[sword.phase]


## Steps until `done` is true or `limit` ticks passed; returns the tick it became
## true (0 when it never did). Cues are drained so none pile up.
func _until(run: GameRun, limit: int, done: Callable) -> int:
	for tick_index: int in range(1, limit + 1):
		run.step()
		run.take_cues()
		if done.call():
			return tick_index
	return 0


# ------------------------------------------------------ scope of the capture
func _check_reference_scope() -> void:
	print("spitters: the reference was captured with out-of-scope mechanics disabled")
	var scope: Dictionary = _ref["fixture_scope"]
	_ok("the capture ran with elemental conditions (afflict) disabled", bool(scope["afflict_disabled"]))
	_ok("no enemy in the capture was armed (arming and drops are issue #17)", int(scope["armed_enemies"]) == 0)
	_ok("the capture fielded only husks and spitters", _same_names(scope["kinds"], ["husk", "spitter"]))
	_ok("only Fang swords took part and no ultimate or Converge was used", _same_names(scope["swords_used"], ["fang"]) and not bool(scope["ultimates_and_converge_used"]))
	_ok("the capture ran no waves (spitters first appear in wave 3: issue #18)", not bool(scope["waves_enabled"]))


func _same_names(actual: Array, expected: Array[String]) -> bool:
	if actual.size() != expected.size():
		return false
	for i: int in actual.size():
		if String(actual[i]) != expected[i]:
			return false
	return true


# ------------------------------------------------------------- definitions
func _check_definitions() -> void:
	print("spitters: stats and projectile constants against the prototype")
	var table: Dictionary = _ref["table"]
	var expected: Dictionary = table["spitter"]
	var def: EnemyDefs = EnemyDefs.of(EnemyDefs.SPITTER)
	_ok("spitter: radius, health, speed, contact damage and knockback multiplier match ENEMY_TYPES",
		def.radius == float(expected["r"]) and def.hp == float(expected["hp"]) and def.speed == float(expected["speed"]) and def.damage == int(expected["dmg"]) and _near(def.knock, float(expected["knock"]), 0.0001),
		"%s" % [expected])
	var wave_health: Dictionary = table["wave_health"]
	var scaled_ok: bool = true
	for wave: String in wave_health:
		scaled_ok = scaled_ok and _near(EnemyState.make(EnemyDefs.SPITTER, Vector2.ZERO, int(wave), 1.0, 1).max_hp, float(wave_health[wave]), SCALAR_TOL)
	_ok("spitter health scales by wave: %s" % [wave_health], scaled_ok)
	var projectile: Dictionary = table["projectile"]
	_ok("a projectile has radius 7, lives 4 s and flies at 270 px/s", ProjectileState.RADIUS == float(projectile["r"]) and ProjectileState.LIFETIME == float(projectile["life"]) and EnemyDefs.SPITTER_SHOT_SPEED == float(table["shot_speed"]))
	_ok("the first cooldown range is 1.5-3.0 s and the cooldown after a shot 2.0-2.9 s", [EnemyDefs.SPITTER_FIRST_COOLDOWN_MIN, EnemyDefs.SPITTER_FIRST_COOLDOWN_MAX] == [1.5, 3.0] and [EnemyDefs.SPITTER_COOLDOWN_MIN, EnemyDefs.SPITTER_COOLDOWN_MAX] == [2.0, 2.9])
	_ok("the shot hurts for a flat 8", ProjectileState.DAMAGE == 8)
	var ranges: Array[float] = [EnemyDefs.SPITTER_RETREAT_RANGE, EnemyDefs.SPITTER_ORBIT_RANGE, EnemyDefs.SPITTER_FIRE_RANGE, EnemyDefs.SPITTER_CHARGE_TIME, EnemyDefs.SPITTER_CHARGE_SLOW, EnemyDefs.SPITTER_ORBIT_SPEED]
	_ok("the AI bands are retreat < 260, orbit < 380, fire < 620, charge 0.5 s at 15%% speed, orbit at 60%%", ranges == [260.0, 380.0, 620.0, 0.5, 0.15, 0.6])
	var spawned: EnemyState = EnemyState.make(EnemyDefs.SPITTER, Vector2.ZERO, 1, 1.0, 1, 0.0, 2.0)
	_ok("a spitter starts with the cooldown it is given and no charge", spawned.shoot_cooldown == 2.0 and spawned.charge == 0.0)


# ---------------------------------------------------------------- movement
func _check_movement() -> void:
	print("spitters: retreat, orbit and approach")
	var movement: Dictionary = _ref["movement"]
	for label: String in ["retreat_150", "orbit_300", "approach_450", "far_800"]:
		var case: Dictionary = movement[label]
		var run: GameRun = GameRun.new(_arena(case["setup"]))
		var enemy: EnemyState = run.enemies[0]
		var trace: Dictionary = case["trace"]
		var marks: Dictionary = {15: "0.25", 30: "0.5", 60: "1.0", 120: "2.0"}
		var problem: String = ""
		for tick_index: int in range(1, 121):
			run.step()
			if marks.has(tick_index):
				var expected: Dictionary = trace[marks[tick_index]]
				var offset: Vector2 = enemy.position - CENTER
				if not (_near(offset.x, float(expected["x"]), POSITION_TOL) and _near(offset.y, float(expected["y"]), POSITION_TOL) and _near(enemy.velocity.x, float(expected["vx"]), VELOCITY_TOL) and _near(enemy.velocity.y, float(expected["vy"]), VELOCITY_TOL) and _near(enemy.facing.x, float(expected["fx"]), 0.001) and _near(enemy.facing.y, float(expected["fy"]), 0.001)):
					problem += " %ss: %s vel %s vs %s" % [marks[tick_index], offset, enemy.velocity, expected]
		_ok("%s: position, velocity and facing match the prototype at 0.25, 0.5, 1 and 2 s%s" % [label, problem], problem.is_empty())
		_ok("%s: nothing is fired while its cooldown is long" % label, run.projectiles.is_empty())
	var retreat: Dictionary = movement["retreat_150"]["trace"]
	var orbit: Dictionary = movement["orbit_300"]["trace"]
	_ok("inside 260 px it backs off (away from the player), at 300 px it circles sideways, at 450 px it closes in",
		float(retreat["0.25"]["vx"]) < -50.0 and absf(float(orbit["1.0"]["vy"])) > absf(float(orbit["1.0"]["vx"])) * 2.0 and float(movement["approach_450"]["trace"]["0.25"]["vx"]) > 50.0)
	var edges: Dictionary = movement["band_edges"]
	var edge_problem: String = ""
	for distance: String in edges:
		var case: Dictionary = edges[distance]
		var run: GameRun = GameRun.new(_arena([case["setup"]]))
		run.step()
		var enemy: EnemyState = run.enemies[0]
		if not (_near(enemy.velocity.x, float(case["vx"]), VELOCITY_TOL) and _near(enemy.velocity.y, float(case["vy"]), VELOCITY_TOL)):
			edge_problem += " %s px: %s vs (%s, %s)" % [distance, enemy.velocity, case["vx"], case["vy"]]
	_ok("the band edges at 260 and 380 px switch behaviour on the prototype's side of the line%s" % edge_problem, edge_problem.is_empty())
	var east: Dictionary = movement["orbit_from_east"]
	var east_run: GameRun = GameRun.new(_arena(east["setup"]))
	_steps(east_run, 10)
	var east_enemy: EnemyState = east_run.enemies[0]
	_ok("the orbit direction is fixed: from the east of the player it circles toward +y (%.3f, %.3f)" % [east_enemy.velocity.x, east_enemy.velocity.y],
		_near(east_enemy.velocity.x, float(east["vx"]), VELOCITY_TOL) and _near(east_enemy.velocity.y, float(east["vy"]), VELOCITY_TOL))


# ---------------------------------------------------------------- shooting
func _check_shooting() -> void:
	print("spitters: the charged shot")
	var shooting: Dictionary = _ref["shooting"]
	var first: Dictionary = shooting["first_shot"]
	var run: GameRun = GameRun.new(_arena(first["setup"]))
	var enemy: EnemyState = run.enemies[0]
	var trace: Dictionary = first["charge_trace"]
	var fired_tick: int = 0
	var trace_problem: String = ""
	var fired_at: Vector2 = Vector2.ZERO
	var fired_velocity: Vector2 = Vector2.ZERO
	var cooldown_after: float = -1.0
	for tick_index: int in range(1, 241):
		run.step()
		run.take_cues()
		if trace.has(str(tick_index)) and fired_tick == 0:
			var expected: Dictionary = trace[str(tick_index)]
			var comparable: bool = _near(enemy.charge, float(expected["charge"]), SCALAR_TOL) and _near(enemy.velocity.x, float(expected["vx"]), VELOCITY_TOL) and _near(enemy.velocity.y, float(expected["vy"]), VELOCITY_TOL)
			if tick_index < 90:
				comparable = comparable and _near(enemy.shoot_cooldown, float(expected["shoot_cd"]), SCALAR_TOL)
			if not comparable:
				trace_problem += " tick %d: charge %.3f cd %.3f vel %s vs %s" % [tick_index, enemy.charge, enemy.shoot_cooldown, enemy.velocity, expected]
		if not run.projectiles.is_empty() and fired_tick == 0:
			fired_tick = tick_index
			fired_at = run.projectiles[0].position - enemy.position
			fired_velocity = run.projectiles[0].velocity
			cooldown_after = enemy.shoot_cooldown
			break
	_ok("the first shot leaves on the prototype's tick %d (%d here)" % [int(first["tick"]), fired_tick], _ticks_close(fired_tick, int(first["tick"])))
	_ok("the charge, cooldown and slowed speed match the prototype tick by tick up to the shot%s" % trace_problem, trace_problem.is_empty())
	_ok("the orb leaves the muzzle (one radius toward the player) heading at the player at 270 px/s",
		_near(fired_at.x, float(first["x"]), POSITION_TOL) and _near(fired_at.y, float(first["y"]), POSITION_TOL) and _near(fired_velocity.x, float(first["vx"]), VELOCITY_TOL) and _near(fired_velocity.y, float(first["vy"]), VELOCITY_TOL) and _near(fired_velocity.length(), 270.0, 0.001),
		"%s %s" % [fired_at, fired_velocity])
	_ok("the shot resets the charge and draws a new cooldown within 2.0-2.9 s (%.3f)" % cooldown_after, enemy.charge == 0.0 and cooldown_after >= 2.0 and cooldown_after <= 2.9)
	_ok("firing is reported as one cue at the muzzle", run.cue_count(SimCue.Kind.PROJECTILE_FIRED) == 1)

	var intervals: Dictionary = shooting["shot_intervals"]
	var long_scenario: RunScenario = _arena(intervals["setup"])
	var long_run: GameRun = GameRun.new(long_scenario)
	long_run.iframes = 1.0e9
	var fire_ticks: Array[int] = []
	for tick_index: int in range(1, 60 * 30 + 1):
		long_run.step()
		for cue: SimCue in long_run.take_cues():
			if cue.kind == SimCue.Kind.PROJECTILE_FIRED:
				fire_ticks.append(tick_index)
	var gaps: Array[int] = []
	for i: int in range(1, fire_ticks.size()):
		gaps.append(fire_ticks[i] - fire_ticks[i - 1])
	var reference_ticks: Array = intervals["fire_ticks"]
	var in_band: bool = not gaps.is_empty()
	var distinct: Dictionary = {}
	for gap: int in gaps:
		in_band = in_band and gap >= 149 and gap <= 205
		distinct[gap] = true
	_ok("the first of thirty seconds of shooting is on the prototype's tick %d (%d here) and there are at least 8 shots (%d)" % [int(reference_ticks[0]), fire_ticks[0] if not fire_ticks.is_empty() else -1, fire_ticks.size()], not fire_ticks.is_empty() and _ticks_close(fire_ticks[0], int(reference_ticks[0])) and fire_ticks.size() >= 8)
	_ok("shots follow each other 2.5-3.4 s apart (the 2.0-2.9 s cooldown plus the 0.5 s charge): %s" % [gaps], in_band)
	var reference_gaps: Array = intervals["intervals_ticks"]
	var reference_in_band: bool = true
	for gap: Variant in reference_gaps:
		reference_in_band = reference_in_band and int(gap) >= 149 and int(gap) <= 205
	_ok("the prototype's own intervals fall in that same band", reference_in_band)
	_ok("the cooldown after a shot is a random draw, not a constant (%d distinct gaps)" % distinct.size(), distinct.size() >= 3)

	var cooldowns: Array[float] = []
	for seed_value: int in 12:
		var spawn_scenario: RunScenario = _arena([])
		spawn_scenario.seed = seed_value
		var shooters: Array[EnemyPlacement] = []
		for i: int in 4:
			var shooter: EnemyPlacement = EnemyPlacement.make(EnemyDefs.SPITTER, Vector2(300.0 + 100.0 * float(i), 300.0))
			shooters.append(shooter)
		spawn_scenario.initial_enemies = shooters
		var spawn_run: GameRun = GameRun.new(spawn_scenario)
		for spitter: EnemyState in spawn_run.enemies:
			cooldowns.append(spitter.shoot_cooldown)
	var lowest: float = cooldowns.min()
	var highest: float = cooldowns.max()
	_ok("a spitter without a pinned cooldown starts with a draw from 1.5-3.0 s (%.2f..%.2f over %d spitters)" % [lowest, highest, cooldowns.size()], lowest >= 1.5 and highest <= 3.0 and highest - lowest > 0.5)


func _check_charge_rules() -> void:
	print("spitters: range, charge slowing, stun, death")
	var shooting: Dictionary = _ref["shooting"]
	var far: Dictionary = shooting["out_of_range"]
	var far_run: GameRun = GameRun.new(_arena(far["setup"]))
	_steps(far_run, 120)
	var far_enemy: EnemyState = far_run.enemies[0]
	_ok("beyond 620 px it never charges, keeps the charge it had and its cooldown runs on (%.3f, %.2f)" % [far_enemy.charge, far_enemy.shoot_cooldown],
		far_run.projectiles.is_empty() and _near(far_enemy.charge, float(far["charge"]), SCALAR_TOL) and _near(far_enemy.shoot_cooldown, float(far["shoot_cd"]), SCALAR_TOL))
	var inside: Dictionary = shooting["just_in_range"]
	var inside_run: GameRun = GameRun.new(_arena(inside["setup"]))
	_steps(inside_run, 10)
	var outside: Dictionary = shooting["just_out_of_range"]
	var outside_run: GameRun = GameRun.new(_arena(outside["setup"]))
	_steps(outside_run, 10)
	_ok("at 619 px it charges (%.3f after 10 ticks); at 621 px it does not" % inside_run.enemies[0].charge, _near(inside_run.enemies[0].charge, float(inside["charge"]), SCALAR_TOL) and outside_run.enemies[0].charge == float(outside["charge"]))
	var slow: Dictionary = shooting["charge_slows_first_tick"]
	var slow_run: GameRun = GameRun.new(_arena(slow["setup"]))
	slow_run.step()
	var slowed: EnemyState = slow_run.enemies[0]
	var first_ok: bool = _near(slowed.velocity.x, float(slow["vx"]), VELOCITY_TOL) and _near(slowed.charge, float(slow["charge"]), SCALAR_TOL)
	_steps(slow_run, 9)
	var tenth: Dictionary = shooting["charge_slows_tick_10"]
	_ok("charging cuts the wanted speed to 15%% (first tick %.3f, tick 10 %.3f px/s)" % [slow["vx"], tenth["vx"]], first_ok and _near(slowed.velocity.x, float(tenth["vx"]), VELOCITY_TOL) and _near(slowed.charge, float(tenth["charge"]), SCALAR_TOL))
	var stun: Dictionary = shooting["stun_cancels_charge"]
	var stun_scenario: RunScenario = _arena(stun["setup"])
	var stun_run: GameRun = GameRun.new(stun_scenario)
	stun_run.enemies[0].stun = 0.5
	_steps(stun_run, 6)
	var stunned: EnemyState = stun_run.enemies[0]
	_ok("a stun cancels the charge and spends no cooldown, so no shot comes out of it", stun_run.projectiles.is_empty() and _near(stunned.charge, float(stun["charge"]), SCALAR_TOL) and _near(stunned.shoot_cooldown, float(stun["shoot_cd"]), SCALAR_TOL) and _near(stunned.stun, float(stun["stun"]), SCALAR_TOL))
	var frozen: Dictionary = shooting["stun_freezes_cooldown"]
	var frozen_run: GameRun = GameRun.new(_arena(frozen["setup"]))
	_steps(frozen_run, 12)
	_ok("a stunned spitter's cooldown stands still (%.3f)" % frozen_run.enemies[0].shoot_cooldown, _near(frozen_run.enemies[0].shoot_cooldown, float(frozen["shoot_cd"]), SCALAR_TOL))
	var dead: Dictionary = shooting["player_dead_no_shot"]
	var dead_run: GameRun = GameRun.new(_arena(dead["setup"]))
	dead_run.dead = true
	_steps(dead_run, 90)
	_ok("once the player is dead spitters wander and never charge or shoot", dead_run.projectiles.is_empty() and dead_run.enemies[0].charge == float(dead["charge"]) and dead_run.cue_count(SimCue.Kind.PROJECTILE_FIRED) == 0)
	var telegraphing: EnemyState = EnemyState.make(EnemyDefs.SPITTER, Vector2.ZERO, 1, 1.0, 1)
	telegraphing.charge = 0.25
	var husk: EnemyState = EnemyState.husk(Vector2.ZERO, 1, 1.0, 2)
	husk.charge = 0.25
	_ok("the visible wind-up is the charge as a 0..1 fraction (spitter only)", _near(telegraphing.telegraph(), 0.5, 0.0001) and husk.telegraph() == 0.0 and EnemyState.make(EnemyDefs.SPITTER, Vector2.ZERO, 1, 1.0, 3).telegraph() == 0.0)
	var paused_run: GameRun = GameRun.new(_arena([_ref["shooting"]["charge_slows_first_tick"]["setup"][0]]))
	paused_run.apply(GameCommand.pause())
	_steps(paused_run, 60)
	_ok("a paused run advances no charge and fires nothing", paused_run.enemies[0].charge == 0.0 and paused_run.projectiles.is_empty())


# ------------------------------------------------------ projectile flight
func _check_projectile_flight() -> void:
	print("projectiles: flight, expiry and leaving the arena")
	var flight: Dictionary = _ref["projectile_flight"]
	var open: Dictionary = flight["expiry_in_the_open"]
	var run: GameRun = GameRun.new(_arena([]))
	var projectile: ProjectileState = _shoot(run, open["setup"])
	var trace: Dictionary = open["trace"]
	var trace_problem: String = ""
	var removed: int = 0
	for tick_index: int in range(1, 301):
		run.step()
		if trace.has(str(tick_index)):
			var expected: Dictionary = trace[str(tick_index)]
			if not (_near(projectile.position.x, float(expected["x"]), POSITION_TOL) and _near(projectile.position.y, float(expected["y"]), POSITION_TOL) and _near(projectile.life, float(expected["life"]), SCALAR_TOL)):
				trace_problem += " tick %d: %s life %.3f" % [tick_index, projectile.position, projectile.life]
		if _gone(run, projectile):
			removed = tick_index
			break
	_ok("a projectile flies straight at 270 px/s and its life runs down%s" % trace_problem, trace_problem.is_empty())
	_ok("it expires after 4 s, on the prototype's tick %d (%d here), in the open arena" % [int(open["removed_tick"]), removed], _ticks_close(removed, int(open["removed_tick"])) and projectile.fate == ProjectileState.Fate.EXPIRED and _near(projectile.position.x, float(open["final_x"]), POSITION_TOL))
	for label: String in ["east", "west", "south", "north", "diagonal"]:
		var case: Dictionary = flight["leaves_%s" % label]
		var leaving_run: GameRun = GameRun.new(_arena([]))
		var leaving: ProjectileState = _shoot(leaving_run, case["setup"])
		var gone_at: int = _until(leaving_run, 240, func() -> bool: return _gone(leaving_run, leaving))
		_ok("leaving through the %s wall: removed on tick %d (%d here) at the prototype's position" % [label, int(case["removed_tick"]), gone_at],
			_ticks_close(gone_at, int(case["removed_tick"])) and leaving.fate == ProjectileState.Fate.LEFT_ARENA and _near(leaving.position.x, float(case["x"]), POSITION_TOL) and _near(leaving.position.y, float(case["y"]), POSITION_TOL) and _near(leaving.life, float(case["life"]), SCALAR_TOL))
	var wall: Dictionary = flight["already_at_the_wall"]
	var wall_run: GameRun = GameRun.new(_arena([]))
	var at_wall: ProjectileState = _shoot(wall_run, wall["setup"])
	wall_run.step()
	_ok("a projectile on the arena edge is removed on its first tick", bool(wall["removed"]) and _gone(wall_run, at_wall) and at_wall.fate == ProjectileState.Fate.LEFT_ARENA)
	var short: Dictionary = flight["short_life"]
	var short_run: GameRun = GameRun.new(_arena([]))
	var brief: ProjectileState = _shoot(short_run, short["setup"])
	var short_at: int = _until(short_run, 12, func() -> bool: return _gone(short_run, brief))
	_ok("a nearly spent projectile expires on the prototype's tick %d (%d here)" % [int(short["removed_tick"]), short_at], _ticks_close(short_at, int(short["removed_tick"])) and brief.fate == ProjectileState.Fate.EXPIRED)
	var slow: Dictionary = flight["slow_motion"]
	var slow_run: GameRun = GameRun.new(_arena([]))
	var slow_projectile: ProjectileState = _shoot(slow_run, slow["setup"])
	slow_run.slowmo = 10.0
	slow_run.slowmo_scale = 0.25
	_steps(slow_run, 60)
	_ok("slow motion slows a projectile's flight and life with the rest of the simulation (x %.1f, life %.2f)" % [slow["x"], slow["life"]], _near(slow_projectile.position.x, float(slow["x"]), POSITION_TOL) and _near(slow_projectile.life, float(slow["life"]), SCALAR_TOL))
	var stop: Dictionary = flight["hitstop_freezes"]
	var stop_run: GameRun = GameRun.new(_arena([]))
	var stopped: ProjectileState = _shoot(stop_run, stop["setup"])
	stop_run.hitstop = 5.0 / 60.0 + 0.0001
	_steps(stop_run, 3)
	_ok("hitstop freezes a projectile in the air", _near(stopped.position.x, float(stop["x_after_3_ticks"]), POSITION_TOL) and _near(stopped.life, ProjectileState.LIFETIME, SCALAR_TOL))
	var pause: Dictionary = flight["pause_freezes"]
	var pause_run: GameRun = GameRun.new(_arena([]))
	var paused: ProjectileState = _shoot(pause_run, pause["setup"])
	pause_run.apply(GameCommand.pause())
	_steps(pause_run, 30)
	_ok("a paused run freezes projectiles and their life", _near(paused.position.x, float(pause["x"]), POSITION_TOL) and _near(paused.life, float(pause["life"]), SCALAR_TOL))
	pause_run.apply(GameCommand.resume())
	_steps(pause_run, 30)
	_ok("they fly on again after resuming", paused.position.x > float(pause["x"]) + 100.0)


# ------------------------------------------------------- hits on the player
func _check_player_hit() -> void:
	print("projectiles: damage to the player and invulnerability")
	var hit: Dictionary = _ref["player_hit"]
	var head: Dictionary = hit["head_on"]
	var run: GameRun = GameRun.new(_arena([]))
	var projectile: ProjectileState = _shoot(run, head["setup"])
	var hit_at: int = _until(run, 60, func() -> bool: return run.hp < 100.0)
	_ok("a projectile hurts for 8 on the prototype's tick %d (%d here), is consumed, and grants 0.8 s invulnerability" % [int(head["tick"]), hit_at],
		_ticks_close(hit_at, int(head["tick"])) and _near(run.hp, float(head["hp"]), SCALAR_TOL) and _near(run.iframes, float(head["iframes"]), SCALAR_TOL) and _gone(run, projectile) and projectile.fate == ProjectileState.Fate.HIT_PLAYER and _near(projectile.position.x, float(head["projectile_x"]), POSITION_TOL))
	_ok("the player is knocked back along the shot (420 px/s), with hitstop 0.07 and shake 0.45",
		_near(run.velocity.x, float(head["player_vx"]), VELOCITY_TOL) and _near(run.velocity.y, float(head["player_vy"]), VELOCITY_TOL) and _near(run.hitstop, float(head["hitstop"]), SCALAR_TOL) and _near(run.trauma, float(head["trauma"]), SCALAR_TOL))
	_ok("the hit is one PLAYER_HURT cue of 8 and the orb is not reported as parried", run.cue_count(SimCue.Kind.PLAYER_HURT) == 1 and run.cue_count(SimCue.Kind.PROJECTILE_PARRIED) == 0)
	var diagonal: Dictionary = hit["diagonal"]
	var diagonal_run: GameRun = GameRun.new(_arena([]))
	_shoot(diagonal_run, diagonal["setup"])
	var diagonal_at: int = _until(diagonal_run, 60, func() -> bool: return diagonal_run.hp < 100.0)
	_ok("a diagonal shot hits on tick %d (%d here) and knocks the player along its own heading" % [int(diagonal["tick"]), diagonal_at],
		_ticks_close(diagonal_at, int(diagonal["tick"])) and _near(diagonal_run.velocity.x, float(diagonal["player_vx"]), VELOCITY_TOL) and _near(diagonal_run.velocity.y, float(diagonal["player_vy"]), VELOCITY_TOL))
	for offset: String in ["20", "22"]:
		var graze: Dictionary = hit["graze_%s" % offset]
		var graze_run: GameRun = GameRun.new(_arena([]))
		var grazing: ProjectileState = _shoot(graze_run, graze["setup"])
		_steps(graze_run, 60)
		_ok("a parallel shot %s px off the player's centre %s (radii 7 + 14 = 21)" % [offset, "hits" if float(graze["hp"]) < 100.0 else "misses"], _near(graze_run.hp, float(graze["hp"]), SCALAR_TOL) and graze_run.projectiles.has(grazing) == bool(graze["alive"]))
	var damage: Dictionary = hit["damage_is_eight"]
	var damage_run: GameRun = GameRun.new(_arena([]))
	_shoot(damage_run, damage["setup"])
	_steps(damage_run, 40)
	_ok("the damage is the projectile's flat 8", _near(damage_run.hp, float(damage["hp"]), SCALAR_TOL))

	var through: Dictionary = hit["passes_through_iframes"]
	var through_run: GameRun = GameRun.new(_arena([]))
	through_run.iframes = float(through["iframes_start"])
	var passing: ProjectileState = _shoot(through_run, through["setup"])
	_steps(through_run, 50)
	_ok("an invulnerable player is passed through: no damage, and the projectile flies on (x %.1f)" % passing.position.x,
		_near(through_run.hp, float(through["hp"]), SCALAR_TOL) and through_run.projectiles.has(passing) == bool(through["alive"]) and _near(passing.position.x, float(through["x"]), POSITION_TOL) and _near(passing.life, float(through["life"]), SCALAR_TOL) and not passing.is_resolved())
	var late: Dictionary = hit["hits_when_iframes_end"]
	var late_run: GameRun = GameRun.new(_arena([]))
	late_run.iframes = float(late["iframes_start"])
	_shoot(late_run, late["setup"])
	var late_at: int = _until(late_run, 120, func() -> bool: return late_run.hp < 100.0)
	_ok("a slow shot still overlapping the player when invulnerability ends hurts then, on tick %d (%d here)" % [int(late["tick"]), late_at], _ticks_close(late_at, int(late["tick"])) and _near(late_run.hp, float(late["hp"]), SCALAR_TOL))
	var dash: Dictionary = hit["dash_dodges"]
	var dash_run: GameRun = GameRun.new(_arena([]))
	dash_run.facing = Vector2(0.0, 1.0)
	dash_run.apply(GameCommand.dash())
	_ok("a dash grants 0.24 s of invulnerability", _near(dash_run.iframes, float(dash["iframes_after_dash"]), SCALAR_TOL))
	var dashed: ProjectileState = _shoot(dash_run, dash["setup"])
	_steps(dash_run, 20)
	_ok("a shot that crosses the player during the dash does nothing", _near(dash_run.hp, float(dash["hp"]), SCALAR_TOL) and dash_run.projectiles.has(dashed) == bool(dash["alive"]))
	var second: Dictionary = hit["second_shot_inside_iframes"]
	var pair_run: GameRun = GameRun.new(_arena([]))
	var first_shot: ProjectileState = _shoot(pair_run, second["setup"][0])
	var second_shot: ProjectileState = _shoot(pair_run, second["setup"][1])
	var hit_ticks: Array[int] = []
	var last_hp: float = pair_run.hp
	for tick_index: int in range(1, 90):
		pair_run.step()
		if pair_run.hp < last_hp:
			hit_ticks.append(tick_index)
			last_hp = pair_run.hp
	_ok("two orbs inside one invulnerability window hurt once: hits on ticks %s, health %.0f, the second flew on to x %.1f" % [hit_ticks, pair_run.hp, second_shot.position.x],
		hit_ticks.size() == 1 and _ticks_close(hit_ticks[0], int((second["hit_ticks"] as Array)[0])) and _near(pair_run.hp, float(second["hp"]), SCALAR_TOL) and pair_run.projectiles.has(second_shot) == bool(second["second_alive"]) and _near(second_shot.position.x, float(second["second_x"]), POSITION_TOL) and first_shot.fate == ProjectileState.Fate.HIT_PLAYER)
	var corpse: Dictionary = hit["dead_player_not_hit"]
	var corpse_run: GameRun = GameRun.new(_arena([]))
	corpse_run.dead = true
	var lifeless: ProjectileState = _shoot(corpse_run, corpse["setup"])
	_steps(corpse_run, 50)
	_ok("a dead player is not hit: the projectile flies through (x %.1f)" % lifeless.position.x, _near(corpse_run.hp, float(corpse["hp"]), SCALAR_TOL) and corpse_run.projectiles.has(lifeless) == bool(corpse["alive"]) and _near(lifeless.position.x, float(corpse["x"]), POSITION_TOL))
	var lethal: Dictionary = hit["lethal"]
	var lethal_scenario: RunScenario = _arena([])
	lethal_scenario.start_health = float(lethal["start_health"])
	var lethal_run: GameRun = GameRun.new(lethal_scenario)
	_shoot(lethal_run, lethal["setup"])
	var lethal_at: int = _until(lethal_run, 40, func() -> bool: return lethal_run.dead)
	_ok("a shot on 8 health kills the player on the prototype's tick %d (%d here): health 0, slow motion 1.4 s" % [int(lethal["tick"]), lethal_at],
		_ticks_close(lethal_at, int(lethal["tick"])) and lethal_run.hp == float(lethal["hp"]) and _near(lethal_run.slowmo, float(lethal["slowmo"]), SCALAR_TOL) and _near(lethal_run.slowmo_scale, float(lethal["slowmo_scale"]), SCALAR_TOL))
	var expiring: Dictionary = hit["expiry_beats_hit"]
	var expiry_run: GameRun = GameRun.new(_arena([]))
	var spent: ProjectileState = _shoot(expiry_run, expiring["setup"])
	expiry_run.step()
	_ok("a projectile whose life ends on the tick it would hit expires instead (no damage)", _near(expiry_run.hp, float(expiring["hp"]), SCALAR_TOL) and spent.fate == ProjectileState.Fate.EXPIRED and bool(expiring["dead"]))


func _check_spitter_as_enemy() -> void:
	print("spitters: the same contact and blow rules as any enemy")
	var case: Dictionary = _ref["spitter_as_enemy"]
	var contact: Dictionary = case["contact"]
	var run: GameRun = GameRun.new(_arena(contact["setup"]))
	run.step()
	var enemy: EnemyState = run.enemies[0]
	_ok("contact hurts for 8 and shoves the spitter away, stunned 0.2 s",
		_near(run.hp, float(contact["hp"]), SCALAR_TOL) and _near(run.iframes, float(contact["iframes"]), SCALAR_TOL) and _near(enemy.velocity.x, float(contact["enemy_vx"]), VELOCITY_TOL) and _near(enemy.stun, float(contact["enemy_stun"]), SCALAR_TOL))
	for label: String in ["fang_hit", "fang_crit"]:
		var blow: Dictionary = case[label]
		var scenario: RunScenario = _arena(blow["setup"])
		scenario.crit_chance = 1.0 if label == "fang_crit" else 0.0
		var blow_run: GameRun = GameRun.new(scenario)
		var target: EnemyState = blow_run.enemies[0]
		var full: float = target.hp
		blow_run.hit_enemy(target, 7.0, Vector2.RIGHT, SwordDefs.FANG_KNOCK, null)
		_ok("%s: damage %d, knockback x1.1 (%.1f px/s), stun and hitstop match" % [label, int(blow["dealt"]), float(blow["vx"])],
			_near(full - target.hp, float(blow["dealt"]), SCALAR_TOL) and _near(target.velocity.x, float(blow["vx"]), VELOCITY_TOL) and _near(target.stun, float(blow["stun"]), 0.001) and _near(blow_run.hitstop, float(blow["hitstop"]), SCALAR_TOL))
	var killed: GameRun = GameRun.new(_arena([_ref["spitter_as_enemy"]["fang_hit"]["setup"][0]]))
	var doomed: EnemyState = killed.enemies[0]
	killed.hit_enemy(doomed, 30.0, Vector2.RIGHT, SwordDefs.FANG_KNOCK, null)
	killed.hit_enemy(doomed, 30.0, Vector2.RIGHT, SwordDefs.FANG_KNOCK, null)
	_ok("a spitter's death resolves once: one kill, three motes", killed.kills == 1 and killed.motes.size() == 3 and killed.cue_count(SimCue.Kind.ENEMY_KILLED) == 1)


# ------------------------------------------------------------ Fang parries
func _check_fang_parry_geometry() -> void:
	print("parry: what a Fang's swept strike reaches")
	var parry: Dictionary = _ref["fang_parry"]
	var reach: Dictionary = parry["perpendicular_reach"]
	for label: String in reach:
		var case: Dictionary = reach[label]
		var run: GameRun = _strike_run(case["setup"]["sword"])
		var projectile: ProjectileState = _shoot(run, case["setup"]["projectile"])
		run.step()
		var parried: bool = projectile.fate == ProjectileState.Fate.PARRIED
		_ok("%s px off the strike line the orb is %s (reach 7 + 8 = 15), hitstop %.3f" % [label.trim_prefix("off_"), "parried" if bool(case["parried"]) else "not parried", float(case["hitstop"])],
			parried == bool(case["parried"]) and _near(run.hitstop, float(case["hitstop"]), SCALAR_TOL) and run.projectiles.has(projectile) != bool(case["parried"]))
	var along: Dictionary = parry["along_the_sweep"]
	for label: String in along:
		var case: Dictionary = along[label]
		var run: GameRun = _strike_run(case["setup"]["sword"])
		var projectile: ProjectileState = _shoot(run, case["setup"]["projectile"])
		run.step()
		_ok("along the sweep, %s: %s" % [label, "parried" if bool(case["parried"]) else "not parried"], (projectile.fate == ProjectileState.Fate.PARRIED) == bool(case["parried"]))
	var mythic: Dictionary = parry["mythic_reach"]
	var mythic_run: GameRun = _strike_run(mythic["setup"]["sword"])
	var far_orb: ProjectileState = _shoot(mythic_run, mythic["setup"]["projectile"])
	mythic_run.step()
	_ok("a Mythic Fang's longer blade reaches an orb a Common one would miss", (far_orb.fate == ProjectileState.Fate.PARRIED) == bool(mythic["parried"]))
	var common_run: GameRun = _strike_run(mythic["setup"]["sword"])
	common_run.swords[0].length = SwordDefs.FANG_LENGTH
	var common_orb: ProjectileState = _shoot(common_run, mythic["setup"]["projectile"])
	common_run.step()
	_ok("...and the same orb is out of a Common Fang's reach", common_orb.fate == ProjectileState.Fate.FLYING)
	var last: Dictionary = parry["final_strike_tick_parries"]
	var last_run: GameRun = _strike_run(last["setup"]["sword"])
	var last_orb: ProjectileState = _shoot(last_run, last["setup"]["projectile"])
	last_run.step()
	_ok("the strike's final tick still parries before the sword recovers", (last_orb.fate == ProjectileState.Fate.PARRIED) == bool(last["parried"]) and _phase_name(last_run.swords[0]) == "RECOVER")


func _check_fang_parry_in_flight() -> void:
	print("parry: moving projectiles and what the parry leaves alone")
	var parry: Dictionary = _ref["fang_parry"]
	var moving: Dictionary = parry["moving_projectile"]
	for label: String in moving:
		var case: Dictionary = moving[label]
		var run: GameRun = _strike_run(case["setup"]["sword"])
		var projectile: ProjectileState = _shoot(run, case["setup"]["projectile"])
		var parried_at: int = 0
		var hitstop_then: float = -1.0
		for tick_index: int in range(1, 31):
			run.step()
			if projectile.fate == ProjectileState.Fate.PARRIED and parried_at == 0:
				parried_at = tick_index
				hitstop_then = run.hitstop
		_ok("%s: the sweep parries it on the prototype's tick %d (%d here), hitstop %.3f" % [label, int(case["parried_tick"]), parried_at, float(case["hitstop_at_parry"])],
			parried_at != 0 and _ticks_close(parried_at, int(case["parried_tick"])) and _near(hitstop_then, float(case["hitstop_at_parry"]), SCALAR_TOL))
	var carry: Dictionary = parry["parry_does_not_end_the_strike"]
	var run: GameRun = _strike_run(carry["setup"]["sword"])
	var projectile: ProjectileState = _shoot(run, carry["setup"]["projectile"])
	run.step()
	var after_parry: float = run.hitstop
	var trauma_after_parry: float = run.trauma
	_steps(run, 2)
	_ok("a parry does not end the strike, shake the screen or score anything: the sword is still striking after 3 ticks, hitstop %.3f, shake %.2f, no kill or combo" % [after_parry, trauma_after_parry],
		projectile.fate == ProjectileState.Fate.PARRIED and _phase_name(run.swords[0]) == String(carry["sword_state_after_3"]).to_upper() and _near(after_parry, float((carry["hitstop_trace"] as Array)[0]), SCALAR_TOL) and _near(trauma_after_parry, float(carry["trauma"]), SCALAR_TOL) and run.kills == 0 and run.combo == 0)
	var pair: Dictionary = parry["two_in_one_sweep"]
	var pair_run: GameRun = _strike_run(pair["setup"]["sword"])
	var a: ProjectileState = _shoot(pair_run, pair["setup"]["projectiles"][0])
	var b: ProjectileState = _shoot(pair_run, pair["setup"]["projectiles"][1])
	pair_run.step()
	_ok("two orbs in one sweep are both parried on that tick, hitstop is the larger of the two, not the sum (%.3f)" % pair_run.hitstop,
		a.fate == ProjectileState.Fate.PARRIED and b.fate == ProjectileState.Fate.PARRIED and _near(pair_run.hitstop, float(pair["hitstop"]), SCALAR_TOL) and pair_run.projectiles.size() == int(pair["projectiles_left"]) and pair_run.cue_count(SimCue.Kind.PROJECTILE_PARRIED) == 2)
	var idle: Dictionary = parry["idle_sword_does_not_parry"]
	var specs: Array[SwordSpec] = [SwordSpec.make(&"fang", 0, &"fire")]
	var idle_scenario: RunScenario = _arena([], specs)
	idle_scenario.sword_start_cooldowns = [99.0]
	var idle_run: GameRun = GameRun.new(idle_scenario)
	idle_run.swords[0].position = Vector2(float(idle["setup"]["sword_x"]), float(idle["setup"]["sword_y"]))
	var sitting: ProjectileState = _shoot(idle_run, idle["setup"]["projectile"])
	_steps(idle_run, 30)
	_ok("an idle sword parries nothing, even with the orb on top of it", sitting.fate == ProjectileState.Fate.FLYING and not bool(idle["parried"]) and _phase_name(idle_run.swords[0]) == "IDLE")
	var windup_scenario: RunScenario = _arena([], specs)
	windup_scenario.sword_start_cooldowns = [0.0]
	var windup_run: GameRun = GameRun.new(windup_scenario)
	var husk_target: EnemyPlacement = EnemyPlacement.make(EnemyDefs.HUSK, CENTER + Vector2(120.0, 0.0))
	husk_target.speed_scale = 0.0
	husk_target.hp = 900.0
	windup_run.enemies.append(EnemyState.make(EnemyDefs.HUSK, husk_target.position, 1, 0.0, 99))
	windup_run.swords[0].cooldown_left = 0.0
	windup_run.swords[0].position = Vector2(float(idle["setup"]["sword_x"]), float(idle["setup"]["sword_y"]))
	var winding: ProjectileState = windup_run.spawn_projectile(windup_run.swords[0].position, Vector2.ZERO)
	windup_run.step()
	_ok("a sword in its windup parries nothing either (phase %s)" % _phase_name(windup_run.swords[0]), _phase_name(windup_run.swords[0]) == "WINDUP" and winding.fate == ProjectileState.Fate.FLYING)


func _check_hit_versus_parry() -> void:
	print("parry: a sweep that hits an enemy does not parry on that tick")
	var parry: Dictionary = _ref["fang_parry"]
	var case: Dictionary = parry["hit_tick_does_not_parry"]
	var enemy_setup: Dictionary = case["setup"]["enemy"]
	var run: GameRun = _strike_run(case["setup"]["sword"], [enemy_setup])
	var projectile: ProjectileState = _shoot(run, case["setup"]["projectile"])
	var husk: EnemyState = run.enemies[0]
	run.step()
	_ok("the strike hits the husk (health %.0f) and ends in recovery; the orb in the same sweep is not parried; hitstop is the hit's %.2f, not the parry's 0.025" % [husk.hp, float(case["hitstop"])],
		_near(husk.hp, float(case["enemy_hp"]), SCALAR_TOL) and _phase_name(run.swords[0]) == String(case["sword_state"]).to_upper() and projectile.fate == ProjectileState.Fate.FLYING and bool(case["projectile_alive"]) and _near(run.hitstop, float(case["hitstop"]), SCALAR_TOL) and run.cue_count(SimCue.Kind.PROJECTILE_PARRIED) == 0 and run.cue_count(SimCue.Kind.ENEMY_HIT) == 1)
	var later: Dictionary = parry["recovering_sword_does_not_parry"]
	var later_run: GameRun = _strike_run(later["setup"]["sword"], [later["setup"]["enemy"]])
	var later_orb: ProjectileState = _shoot(later_run, later["setup"]["projectile"])
	_steps(later_run, 6)
	_ok("the recovering sword leaves the orb alone on the following ticks", later_orb.fate == ProjectileState.Fate.FLYING and not bool(later["parried"]) and _phase_name(later_run.swords[0]) == "RECOVER")
	var hit_cues: int = later_run.cue_count(SimCue.Kind.ENEMY_HIT)
	var parry_cues: int = later_run.cue_count(SimCue.Kind.PROJECTILE_PARRIED)
	_ok("a hit and a parry are different events: %d enemy hit cue, %d parry cues, no player hurt" % [hit_cues, parry_cues], hit_cues == 1 and parry_cues == 0 and later_run.cue_count(SimCue.Kind.PLAYER_HURT) == 0)
	var quirk: Dictionary = _ref["prototype_quirk"]
	var parry_run: GameRun = _strike_run(quirk["setup"]["sword"])
	var clipped: ProjectileState = _shoot(parry_run, quirk["setup"]["projectile"])
	parry_run.step()
	_ok("DELIBERATE EXCEPTION: the prototype still hurt the player (health %.0f) with an orb the sweep had just destroyed; here the orb resolves once, as a parry (health %.0f, no hurt cue)" % [float(quirk["player_hp"]), parry_run.hp],
		bool(quirk["parried"]) and float(quirk["player_hp"]) == 92.0 and clipped.fate == ProjectileState.Fate.PARRIED and parry_run.hp == 100.0 and parry_run.cue_count(SimCue.Kind.PLAYER_HURT) == 0 and parry_run.cue_count(SimCue.Kind.PROJECTILE_PARRIED) == 1)


func _check_fang_auto() -> void:
	print("parry: a Fang that acquires, winds up and strikes by itself")
	var auto: Dictionary = _ref["fang_auto"]
	for label: String in ["on_the_line", "near_the_line", "clear_of_the_line"]:
		var case: Dictionary = auto[label]
		var specs: Array[SwordSpec] = [SwordSpec.make(&"fang", 0, &"poison")]
		var scenario: RunScenario = _arena(case["setup"], specs)
		scenario.sword_start_cooldowns = [0.4]
		var run: GameRun = GameRun.new(scenario)
		var husk: EnemyState = run.enemies[0]
		var projectile: ProjectileState = _shoot(run, case["projectile"])
		var parried_at: int = 0
		var hit_at: int = 0
		var hitstop_then: float = -1.0
		var last_hp: float = husk.hp
		for tick_index: int in range(1, 61):
			run.step()
			if projectile.fate == ProjectileState.Fate.PARRIED and parried_at == 0:
				parried_at = tick_index
				hitstop_then = run.hitstop
			if husk.hp < last_hp and hit_at == 0:
				hit_at = tick_index
			last_hp = husk.hp
		var expects_parry: bool = case["parried_tick"] != null
		var parry_ok: bool = (parried_at != 0) == expects_parry and (not expects_parry or (_ticks_close(parried_at, int(case["parried_tick"])) and _near(hitstop_then, float(case["hitstop_at_parry"]), SCALAR_TOL)))
		_ok("%s (%.0f px off): %s; the husk is first hit on tick %d (%d here)" % [label, float(case["offset"]), "parried on tick %d (%d here)" % [int(case["parried_tick"]), parried_at] if expects_parry else "left alone", int(case["first_hit_tick"]), hit_at],
			parry_ok and _ticks_close(hit_at, int(case["first_hit_tick"])) and run.projectiles.has(projectile) == bool(case["alive"]))
	var undefended: Dictionary = auto["undefended_shot"]
	var run: GameRun = GameRun.new(_arena(undefended["setup"]))
	var shot_at: int = 0
	var hurt_at: int = 0
	for tick_index: int in range(1, 181):
		run.step()
		run.take_cues()
		if not run.projectiles.is_empty() and shot_at == 0:
			shot_at = tick_index
		if run.hp < 100.0 and hurt_at == 0:
			hurt_at = tick_index
	_ok("an undefended player is shot at on tick %d (%d here), hit on tick %d (%d here) and loses 8 (health %.0f)" % [int(undefended["shot_tick"]), shot_at, int(undefended["hit_tick"]), hurt_at, run.hp],
		_ticks_close(shot_at, int(undefended["shot_tick"])) and _ticks_close(hurt_at, int(undefended["hit_tick"])) and _near(run.hp, float(undefended["hp"]), SCALAR_TOL))


# ------------------------------------------------- exactly once, whatever
func _check_exactly_once() -> void:
	print("projectiles: every orb resolves exactly once")
	var parry: Dictionary = _ref["fang_parry"]
	var case: Dictionary = parry["two_in_one_sweep"]
	var run: GameRun = _strike_run(case["setup"]["sword"])
	var a: ProjectileState = _shoot(run, case["setup"]["projectiles"][0])
	run.step()
	var again: int = run.parry_projectiles(Vector2(900.0, 500.0), Vector2(1200.0, 700.0), 100.0)
	_ok("an orb that was parried cannot be parried again (a second sweep over it finds nothing, one cue, one hitstop)", again == 0 and run.cue_count(SimCue.Kind.PROJECTILE_PARRIED) == 1 and a.fate == ProjectileState.Fate.PARRIED)
	var twice_run: GameRun = GameRun.new(_arena([]))
	var twice_orb: ProjectileState = twice_run.spawn_projectile(Vector2(1000.0, 600.0), Vector2.ZERO)
	var first_parry: int = twice_run.parry_projectiles(Vector2(990.0, 600.0), Vector2(1010.0, 600.0), 6.0)
	var second_parry: int = twice_run.parry_projectiles(Vector2(990.0, 600.0), Vector2(1010.0, 600.0), 6.0)
	_ok("two sweeps in the same tick over one orb parry it once (%d then %d), with one cue" % [first_parry, second_parry], first_parry == 1 and second_parry == 0 and twice_orb.fate == ProjectileState.Fate.PARRIED and twice_run.cue_count(SimCue.Kind.PROJECTILE_PARRIED) == 1)
	_ok("resolving a resolved orb changes nothing: the first fate stands", not a.resolve(ProjectileState.Fate.HIT_PLAYER) and a.fate == ProjectileState.Fate.PARRIED)
	var arena: GameRun = GameRun.new(_arena([]))
	var struck: ProjectileState = _shoot(arena, _ref["player_hit"]["head_on"]["setup"])
	_until(arena, 60, func() -> bool: return arena.hp < 100.0)
	var parried_after: int = arena.parry_projectiles(struck.position - Vector2(40.0, 0.0), struck.position + Vector2(40.0, 0.0), 40.0)
	_ok("an orb that hit the player is gone and cannot also be parried or cause a second hit", parried_after == 0 and struck.fate == ProjectileState.Fate.HIT_PLAYER and arena.cue_count(SimCue.Kind.PLAYER_HURT) == 1 and arena.cue_count(SimCue.Kind.PROJECTILE_PARRIED) == 0)
	var cleared_run: GameRun = GameRun.new(_arena([]))
	var cleared: ProjectileState = _shoot(cleared_run, _ref["player_hit"]["head_on"]["setup"])
	cleared_run.clear_projectiles_in_circle(cleared.position, 50.0)
	_steps(cleared_run, 40)
	_ok("an orb cleared before it arrives never hurts the player and is not counted as a parry", cleared_run.hp == 100.0 and cleared.fate == ProjectileState.Fate.CLEARED and cleared_run.cue_count(SimCue.Kind.PROJECTILE_PARRIED) == 0)

	# A whole fight: spitters only, so every PLAYER_HURT is an orb and each fired
	# orb is accounted for exactly once.
	var scenario: RunScenario = RunScenario.new()
	scenario.seed = 17
	scenario.waves_enabled = false
	scenario.sword_start_cooldowns = [0.3, 0.4, 0.5]
	var placements: Array[EnemyPlacement] = []
	var bearings: Array[float] = [0.0, PI, PI / 4.0]
	for i: int in bearings.size():
		var spitter: EnemyPlacement = EnemyPlacement.make(EnemyDefs.SPITTER, CENTER + SimMath.polar(bearings[i], 300.0 + 30.0 * float(i)))
		spitter.shoot_cooldown = 0.2 + 0.4 * float(i)
		spitter.speed_scale = 0.0
		placements.append(spitter)
	var post: EnemyPlacement = EnemyPlacement.make(EnemyDefs.HUSK, CENTER + Vector2(110.0, 0.0))
	post.speed_scale = 0.0
	post.hp = 9000.0
	placements.append(post)
	var west: EnemyPlacement = EnemyPlacement.make(EnemyDefs.HUSK, CENTER + Vector2(-110.0, 0.0))
	west.speed_scale = 0.0
	west.hp = 9000.0
	placements.append(west)
	scenario.initial_enemies = placements
	var fight: GameRun = GameRun.new(scenario)
	var seen: Dictionary = {}
	var created_ticks: int = 0
	for tick_index: int in range(1, 60 * 25 + 1):
		fight.step()
		fight.take_cues()
		created_ticks += 1
		for projectile: ProjectileState in fight.projectiles:
			seen[projectile] = true
		if fight.dead:
			break
	var fired: int = fight.cue_count(SimCue.Kind.PROJECTILE_FIRED)
	var hurt: int = fight.cue_count(SimCue.Kind.PLAYER_HURT)
	var parried: int = fight.cue_count(SimCue.Kind.PROJECTILE_PARRIED)
	var flying: int = fight.projectiles.size()
	var resolved_otherwise: int = fired - hurt - parried - flying
	# Alive: every hurt cue cost exactly 8. Dead: the 13th orb (8 x 13 >= 100) killed
	# the player and no orb after it counted as another hit.
	var accounted: bool = hurt * ProjectileState.DAMAGE == int(fight.max_hp - fight.hp) if not fight.dead else hurt == ceili(fight.max_hp / float(ProjectileState.DAMAGE))
	_ok("in a %d-tick fight %d orbs were fired, %d hurt the player, %d were parried, %d still fly and %d expired or left the arena (none lost or counted twice)" % [created_ticks, fired, hurt, parried, flying, resolved_otherwise],
		fired >= 15 and hurt >= 1 and parried >= 1 and resolved_otherwise >= 0 and accounted)
	var every_fate_single: bool = true
	var fates: Dictionary = {}
	for projectile: Variant in seen:
		var p: ProjectileState = projectile as ProjectileState
		fates[p.fate] = int(fates.get(p.fate, 0)) + 1
		every_fate_single = every_fate_single and (p.is_resolved() or fight.projectiles.has(p))
	_ok("every orb that left the run was resolved, and every orb still in the run is flying (%s)" % [fates], every_fate_single and fight.projectiles.all(func(p: ProjectileState) -> bool: return not p.is_resolved()))


# ----------------------------------------------------- paused and dead
func _check_paused_and_dead() -> void:
	print("parry: paused and dead states")
	var parry: Dictionary = _ref["fang_parry"]
	var case: Dictionary = parry["perpendicular_reach"]["off_+0"]
	var run: GameRun = _strike_run(case["setup"]["sword"])
	var projectile: ProjectileState = _shoot(run, case["setup"]["projectile"])
	run.apply(GameCommand.pause())
	var start: Vector2 = run.swords[0].position
	_steps(run, 30)
	_ok("a paused strike neither moves nor parries", run.swords[0].position == start and projectile.fate == ProjectileState.Fate.FLYING and run.cue_count(SimCue.Kind.PROJECTILE_PARRIED) == 0)
	run.apply(GameCommand.resume())
	run.step()
	_ok("resuming lets the same sweep parry on the very next tick", projectile.fate == ProjectileState.Fate.PARRIED)
	var corpse: GameRun = _strike_run(case["setup"]["sword"])
	var spared: ProjectileState = _shoot(corpse, case["setup"]["projectile"])
	corpse.dead = true
	corpse.step()
	_ok("once the player is dead his swords fall idle and parry nothing", spared.fate == ProjectileState.Fate.FLYING and _phase_name(corpse.swords[0]) == "IDLE" and corpse.cue_count(SimCue.Kind.PROJECTILE_PARRIED) == 0)
	var lethal: Dictionary = _ref["player_hit"]["lethal"]
	var lethal_scenario: RunScenario = _arena([])
	lethal_scenario.start_health = 8.0
	var lethal_run: GameRun = GameRun.new(lethal_scenario)
	_shoot(lethal_run, lethal["setup"])
	var follower: ProjectileState = lethal_run.spawn_projectile(Vector2(float(lethal["setup"]["x"]) + 60.0, float(lethal["setup"]["y"])), Vector2(-270.0, 0.0))
	_until(lethal_run, 90, func() -> bool: return lethal_run.dead and not lethal_run.projectiles.has(follower))
	_ok("a second orb arriving at the corpse is not a second death: one hurt cue, one death cue, health stays 0", lethal_run.cue_count(SimCue.Kind.PLAYER_HURT) == 1 and lethal_run.cue_count(SimCue.Kind.PLAYER_DIED) == 1 and lethal_run.hp == 0.0)
	var restart: GameRun = GameRun.new(_arena([]))
	_shoot(restart, _ref["player_hit"]["head_on"]["setup"])
	restart.take_cues()
	restart.apply(GameCommand.restart())
	_ok("restarting drops every orb in flight and their counters", restart.projectiles.is_empty() and restart.cue_count(SimCue.Kind.PROJECTILE_FIRED) == 0)
	var scenario: RunScenario = RunScenario.spitter_encounter()
	scenario.seed = 6
	scenario.first_wave_delay = 0.0
	var long_run: GameRun = GameRun.new(scenario)
	_until(long_run, 900, func() -> bool: return long_run.cue_count(SimCue.Kind.PROJECTILE_FIRED) > 0)
	long_run.apply(GameCommand.restart())
	_ok("restarting the spitter encounter clears its enemies and projectiles too", long_run.projectiles.is_empty() and long_run.enemies.is_empty())


# ------------------------------------------------- the shared parry rule
func _check_shared_parry_rule() -> void:
	print("parry: the one rule later sword slices will share")
	var run: GameRun = GameRun.new(_arena([]))
	var segment_from: Vector2 = Vector2(1000.0, 600.0)
	var segment_to: Vector2 = Vector2(1100.0, 600.0)
	var inside: ProjectileState = run.spawn_projectile(Vector2(1050.0, 600.0 + 14.9), Vector2.ZERO)
	var exact: ProjectileState = run.spawn_projectile(Vector2(1050.0, 600.0 + 15.0), Vector2.ZERO)
	var past_end: ProjectileState = run.spawn_projectile(Vector2(1100.0 + 14.9, 600.0), Vector2.ZERO)
	var before_start: ProjectileState = run.spawn_projectile(Vector2(1000.0 - 15.1, 600.0), Vector2.ZERO)
	var count: int = run.parry_projectiles(segment_from, segment_to, 8.0)
	_ok("a segment parries orbs closer than radius + pad (7 + 8): 14.9 px parried, 15.0 px and 15.1 px past the end not (returns %d)" % count,
		count == 2 and inside.fate == ProjectileState.Fate.PARRIED and past_end.fate == ProjectileState.Fate.PARRIED and exact.fate == ProjectileState.Fate.FLYING and before_start.fate == ProjectileState.Fate.FLYING)
	var wide: GameRun = GameRun.new(_arena([]))
	var orb: ProjectileState = wide.spawn_projectile(Vector2(1050.0, 600.0 + 20.0), Vector2.ZERO)
	_ok("the pad is the caller's: 8 does not reach 20 px, 14 (a Skewer thrust) does", wide.parry_projectiles(segment_from, segment_to, 8.0) == 0 and wide.parry_projectiles(segment_from, segment_to, 14.0) == 1 and orb.fate == ProjectileState.Fate.PARRIED)
	var point: GameRun = GameRun.new(_arena([]))
	var spot: ProjectileState = point.spawn_projectile(Vector2(1000.0, 610.0), Vector2.ZERO)
	_ok("a zero-length segment is a point test", point.parry_projectiles(Vector2(1000.0, 600.0), Vector2(1000.0, 600.0), 6.0) == 1 and spot.fate == ProjectileState.Fate.PARRIED)
	var stop: GameRun = GameRun.new(_arena([]))
	stop.hitstop = 0.07
	stop.spawn_projectile(Vector2(1000.0, 600.0), Vector2.ZERO)
	stop.parry_projectiles(Vector2(990.0, 600.0), Vector2(1010.0, 600.0), 6.0)
	var calm: GameRun = GameRun.new(_arena([]))
	calm.spawn_projectile(Vector2(1000.0, 600.0), Vector2.ZERO)
	calm.parry_projectiles(Vector2(990.0, 600.0), Vector2(1010.0, 600.0), 6.0)
	_ok("a parry sets hitstop to 0.025 but never shortens a longer one (%.3f / %.3f)" % [calm.hitstop, stop.hitstop], _near(calm.hitstop, 0.025, 0.00001) and _near(stop.hitstop, 0.07, 0.00001))
	var clear: GameRun = GameRun.new(_arena([]))
	var near: ProjectileState = clear.spawn_projectile(Vector2(1000.0, 600.0 + 59.0), Vector2.ZERO)
	var far: ProjectileState = clear.spawn_projectile(Vector2(1000.0, 600.0 + 61.0), Vector2.ZERO)
	var removed: int = clear.clear_projectiles_in_circle(Vector2(1000.0, 600.0), 60.0)
	_ok("a slam clears the orbs inside its circle (59 px) and leaves those outside (61 px), silently and without hitstop",
		removed == 1 and near.fate == ProjectileState.Fate.CLEARED and far.fate == ProjectileState.Fate.FLYING and clear.hitstop == 0.0 and clear.cue_count(SimCue.Kind.PROJECTILE_PARRIED) == 0)
	var cue_run: GameRun = GameRun.new(_arena([]))
	cue_run.spawn_projectile(Vector2(1000.0, 600.0), Vector2(0.0, 270.0))
	cue_run.take_cues()
	cue_run.parry_projectiles(Vector2(990.0, 600.0), Vector2(1010.0, 600.0), 6.0)
	var cues: Array[SimCue] = cue_run.take_cues()
	_ok("the parry cue sits where the orb died and points back along its flight", cues.size() == 1 and cues[0].kind == SimCue.Kind.PROJECTILE_PARRIED and cues[0].position == Vector2(1000.0, 600.0) and cues[0].direction == Vector2(0.0, -1.0))


# --------------------------------------------- encounter, cycle, launch
func _check_encounter_and_cycle() -> void:
	print("spitters: the encounter fixture and the dev-encounter cycle")
	var scenario: RunScenario = RunScenario.spitter_encounter()
	var spitters: int = scenario.wave_kinds.count(EnemyDefs.SPITTER)
	var husks: int = scenario.wave_kinds.count(EnemyDefs.HUSK)
	_ok("the spitter encounter is one wave of %d spitters and %d husks with the three-Fang fixture loadout and no shove" % [spitters, husks], spitters == 5 and husks == 3 and scenario.wave_kinds.size() == 8 and scenario.loadout.size() == 3 and not scenario.dev_shove and scenario.encounter == RunScenario.ENCOUNTER_SPITTERS and scenario.waves_enabled)
	var run: GameRun = GameRun.new(RunScenario.new())
	var visited: Array[StringName] = [run.scenario.encounter]
	for i: int in 3:
		run.apply(GameCommand.toggle_encounter())
		visited.append(run.scenario.encounter)
	_ok("the dev command cycles normal -> crowd -> spitters -> normal, restarting each time (%s)" % [visited], visited == [&"", &"crowd", &"spitters", &""] and run.restarts == 3)
	var from_spitters: GameRun = GameRun.new(RunScenario.spitter_encounter())
	from_spitters.apply(GameCommand.toggle_encounter())
	_ok("a run that began in the spitter encounter continues to the normal run", from_spitters.scenario.encounter == RunScenario.ENCOUNTER_NORMAL and from_spitters.scenario.wave_kinds.is_empty())
	from_spitters.apply(GameCommand.toggle_encounter())
	_ok("and then to the crowd", from_spitters.scenario.encounter == RunScenario.ENCOUNTER_CROWD)
	var wall: GameRun = GameRun.new(RunScenario.wall_encounter())
	wall.apply(GameCommand.toggle_encounter())
	wall.apply(GameCommand.toggle_encounter())
	wall.apply(GameCommand.toggle_encounter())
	_ok("the wall encounter keeps the crowd slot: spitters, normal, then the pinned crowd again", wall.scenario.encounter == RunScenario.ENCOUNTER_CROWD and wall.enemies.size() == 14 and not wall.scenario.waves_enabled)
	var custom: RunScenario = RunScenario.new()
	custom.seed = 77
	var custom_run: GameRun = GameRun.new(custom)
	for i: int in 3:
		custom_run.apply(GameCommand.toggle_encounter())
	_ok("a custom scenario is the normal slot and returns after the cycle", custom_run.scenario == custom)
	var launched_spitters: RunScenario = LaunchOptions.scenario_for("spitters")
	var launched_crowd: RunScenario = LaunchOptions.scenario_for("crowd")
	var launched_wall: RunScenario = LaunchOptions.scenario_for("wall")
	_ok("the launch option asks for the spitter encounter", launched_spitters != null and launched_spitters.encounter == RunScenario.ENCOUNTER_SPITTERS and launched_crowd != null and launched_crowd.encounter == RunScenario.ENCOUNTER_CROWD and launched_wall != null and launched_wall.encounter == RunScenario.ENCOUNTER_CROWD and LaunchOptions.scenario_for("nonsense") == null)
	_ok("the dev button names where it leads: %s" % [[RunScenario.encounter_title(RunScenario.next_encounter(&"")), RunScenario.encounter_title(RunScenario.next_encounter(&"crowd")), RunScenario.encounter_title(RunScenario.next_encounter(&"spitters"))]],
		RunScenario.encounter_title(RunScenario.next_encounter(&"")) == "Crowd" and RunScenario.encounter_title(RunScenario.next_encounter(&"crowd")) == "Spitters" and RunScenario.encounter_title(RunScenario.next_encounter(&"spitters")) == "Normal")
	var played: RunScenario = RunScenario.spitter_encounter()
	played.seed = 21
	played.first_wave_delay = 0.2
	var played_run: GameRun = GameRun.new(played)
	var kinds: Dictionary = {}
	var first_cooldowns: Dictionary = {}
	for tick_index: int in 60 * 8:
		played_run.step()
		played_run.take_cues()
		for enemy: EnemyState in played_run.enemies:
			kinds[enemy.kind] = true
			if enemy.kind == EnemyDefs.SPITTER and not first_cooldowns.has(enemy.serial):
				first_cooldowns[enemy.serial] = enemy.shoot_cooldown
	# A spitter that the wave director spawns draws the prototype's 1.5-3.0 s first cooldown
	# (it has already counted down a tick or two by the time it is first seen).
	var draws: Array = first_cooldowns.values()
	var in_range: bool = draws.size() == 5 and draws.all(func(value: float) -> bool: return value >= EnemyDefs.SPITTER_FIRST_COOLDOWN_MIN - 0.05 and value <= EnemyDefs.SPITTER_FIRST_COOLDOWN_MAX)
	_ok("each spitter the wave director spawns starts with a first cooldown drawn from 1.5-3.0 s, and the draws differ (%s)" % [draws], in_range and draws.any(func(value: float) -> bool: return not is_equal_approx(value, draws[0])))
	_ok("the encounter's wave spawns through telegraphs and fields spitters that shoot (%s, %d orbs)" % [kinds.keys(), played_run.cue_count(SimCue.Kind.PROJECTILE_FIRED)], kinds.has(EnemyDefs.SPITTER) and kinds.has(EnemyDefs.HUSK) and played_run.cue_count(SimCue.Kind.PROJECTILE_FIRED) >= 1 and played_run.cue_count(SimCue.Kind.ENEMY_SPAWNED) == 8)


func _check_normal_run_unchanged() -> void:
	print("spitters: the normal run is unchanged")
	var scenario: RunScenario = RunScenario.new()
	scenario.seed = 5
	var run: GameRun = GameRun.new(scenario)
	var kinds: Dictionary = {}
	for tick_index: int in 60 * 12:
		run.step()
		run.take_cues()
		for enemy: EnemyState in run.enemies:
			kinds[enemy.kind] = true
	_ok("wave 1 of the normal run has husks only and fires nothing (%s)" % [kinds.keys()], kinds.keys() == [EnemyDefs.HUSK] and run.cue_count(SimCue.Kind.PROJECTILE_FIRED) == 0 and run.projectiles.is_empty())
	_ok("the plain scenario names no encounter and no composition", scenario.encounter == RunScenario.ENCOUNTER_NORMAL and scenario.wave_kinds.is_empty() and not scenario.dev_shove)


# ------------------------------------------------------ real Main scene
func _main_with(scenario: RunScenario, enemy_scene: String = "") -> Main:
	var main: Main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Main
	main.scenario = scenario
	if not enemy_scene.is_empty():
		main.enemy_visual = load(enemy_scene)
	_tree.root.add_child(main)
	main.set_physics_process(false)
	return main


func _tick_main(main: Main, count: int) -> void:
	for i: int in count:
		main._physics_process(GameRun.TICK_DT)


func _check_main_scene() -> void:
	print("spitters: the Main scene shows spitters, their wind-up and the dev controls")
	var scenario: RunScenario = RunScenario.spitter_encounter()
	scenario.seed = 12
	scenario.first_wave_delay = 0.1
	var main: Main = _main_with(scenario, "res://tests/alt_enemy.tscn")
	await _tree.process_frame
	main._sfx.unlock()
	main._sfx.played.clear()
	var winding: EnemyState = null
	for tick_index: int in 60 * 10:
		_tick_main(main, 1)
		for enemy: EnemyState in main.run.enemies:
			if enemy.telegraph() > 0.3:
				winding = enemy
		if winding != null:
			break
	await _tree.process_frame
	_ok("a spitter reached its wind-up in the real scene", winding != null)
	var told: float = -1.0
	for child: Node in main._presenter.get_children():
		if child is AltEnemyVisual and (child as AltEnemyVisual).last_telegraph > told:
			told = (child as AltEnemyVisual).last_telegraph
	_ok("the visuals are told the wind-up fraction (%.2f) and nothing else about the shot" % told, winding != null and told > 0.3 and _near(told, winding.telegraph(), 0.001))
	var shot_before: int = main.run.cue_count(SimCue.Kind.PROJECTILE_FIRED)
	_tick_main(main, 60 * 3)
	_ok("shots are heard (the shot sound played) and flying orbs are in the run (%d fired)" % main.run.cue_count(SimCue.Kind.PROJECTILE_FIRED), main.run.cue_count(SimCue.Kind.PROJECTILE_FIRED) > shot_before and main._sfx.played.has("shot"), "%s" % [main._sfx.played])
	_ok("the presenter shows a visual for every enemy and the three swords: %d for %d" % [main._presenter.visual_count(), main.run.enemies.size()], main._presenter.visual_count() == main.run.enemies.size() + 3)
	_ok("the legend names the encounter as a dev fixture and counts the orbs", main._hud._encounter_label.visible and main._hud._encounter_label.text.begins_with("SPITTER ENCOUNTER (dev fixture)") and main._hud._encounter_label.text.contains("spitter") and main._hud._encounter_label.text.contains("parried"), main._hud._encounter_label.text)
	_ok("the dev button says where it leads and that it restarts play, and the shove stays hidden here", main._hud._encounter_button.text == "Dev: Normal (restarts)" and not main._hud._shove_button.visible, main._hud._encounter_button.text)
	main._sfx.played.clear()
	main._sfx.play_cue(SimCue.make(SimCue.Kind.PROJECTILE_PARRIED, Vector2.ZERO))
	_ok("a parry has its own sound, different from a hit's", main._sfx.played.has("parry") and not main._sfx.played.has("hit"), "%s" % [main._sfx.played])
	main._hud._encounter_button.button_down.emit()
	await _tree.process_frame
	_ok("the dev button returns to the normal run: no enemies, no orbs, controls and legend hidden", main.run.scenario.encounter == RunScenario.ENCOUNTER_NORMAL and main.run.enemies.is_empty() and main.run.projectiles.is_empty() and not main._hud._encounter_label.visible and main._hud._encounter_button.text == "Dev: Crowd (restarts)", main._hud._encounter_button.text)
	main.queue_free()
	await _tree.process_frame
	# Silhouettes: every type reads differently without final art.
	var colors: Array[Color] = []
	for kind: StringName in [EnemyDefs.HUSK, EnemyDefs.RUNNER, EnemyDefs.SPITTER, EnemyDefs.BRUTE]:
		colors.append(PlaceholderEnemyVisual.color_of(kind))
	var distinct: bool = true
	for i: int in colors.size():
		for j: int in range(i + 1, colors.size()):
			distinct = distinct and colors[i] != colors[j]
	_ok("husk, runner, spitter and brute each have their own colour", distinct)
	_ok("the spitter's drawn size follows its collision size", PlaceholderEnemyVisual.visual_radius_of(EnemyDefs.SPITTER) == EnemyDefs.SPITTER_RADIUS)
	var drawn: PlaceholderEnemyVisual = PlaceholderEnemyVisual.new()
	drawn.setup(EnemyDefs.SPITTER)
	drawn.apply_pose(Vector2.ZERO, Vector2.RIGHT, 0.0, 0.0, 1.0, false, 0.6)
	_ok("the placeholder accepts the wind-up (it draws the glow and aim line from it)", drawn._telegraph == 0.6)
	drawn.free()


func _check_visual_independence() -> void:
	print("spitters: swapping enemy visuals leaves the spitter fight unchanged")
	var results: Array[Dictionary] = []
	var hosts: Array[Main] = []
	for use_alt: bool in [false, true]:
		var scenario: RunScenario = RunScenario.spitter_encounter()
		scenario.seed = 14
		scenario.first_wave_delay = 0.2
		hosts.append(_main_with(scenario, "res://tests/alt_enemy.tscn" if use_alt else ""))
	await _tree.process_frame
	for main: Main in hosts:
		_tick_main(main, 900)
		results.append(main.run.snapshot())
	_ok("a huge replacement enemy visual changes nothing about shots, parries, hits or deaths", results[0] == results[1])
	_ok("the fixture fought: orbs were fired (%d) and %d kills" % [hosts[0].run.cue_count(SimCue.Kind.PROJECTILE_FIRED), hosts[0].run.kills], hosts[0].run.cue_count(SimCue.Kind.PROJECTILE_FIRED) >= 3)
	for main: Main in hosts:
		main.queue_free()
	await _tree.process_frame


# -------------------------------------------------------- render rates
func _check_render_rates() -> void:
	print("spitters: identical outcomes at low and high render rates")
	var headless: Dictionary = RenderRateScenario.play_headless(RenderRateScenario.SPITTERS)
	var expected_digest: Dictionary = JSON.parse_string(JSON.stringify(headless))
	_ok("the scripted fight does something worth comparing (orbs %d, parried %d, player hurt %d, alive %s)" % [int(headless["shot_cues"]), int(headless["parry_cues"]), int(headless["hurt_cues"]), not bool(headless["dead"])],
		int(headless["shot_cues"]) >= 25 and int(headless["parry_cues"]) >= 5 and int(headless["hurt_cues"]) >= 3 and not bool(headless["dead"]))
	# Health is the maximum, less 8 per orb that hurt, plus 0.5 per healing mote already collected.
	var healed: float = Mote.HEAL * float(3 * int(headless["kills"]) - int(headless["motes"]))
	_ok("exactly once: every hurt cue cost 8 health and none is lost (health %.1f = 100 - 8 x %d + %.1f healed)" % [float(headless["hp"]), int(headless["hurt_cues"]), healed], absf(float(headless["hp"]) - (GameRun.PLAYER_MAX_HP - float(int(headless["hurt_cues"]) * ProjectileState.DAMAGE) + healed)) < 0.01)
	var executable: String = OS.get_executable_path()
	var project: String = ProjectSettings.globalize_path("res://")
	var frames: Dictionary[int, int] = {}
	for rate: int in PROBE_FRAME_RATES:
		var output: Array = []
		var arguments: PackedStringArray = ["--headless", "--path", project, "--fixed-fps", str(rate), "--script", PROBE_SCRIPT, "--", "--probe=rate-spitters"]
		var code: int = OS.execute(executable, arguments, output, true)
		var line: String = _probe_line(output)
		_ok("the engine played the orb fight at %d fps (exit %d)" % [rate, code], code == 0 and not line.is_empty(), "%s" % [output])
		if line.is_empty():
			continue
		var result: Dictionary = JSON.parse_string(line)
		frames[rate] = int(result["frames"])
		var comparable: Dictionary = result.duplicate()
		for key: String in ["frames", "visuals", "enemies"]:
			comparable.erase(key)
		_ok("at %d fps the real Main scene ends the fight exactly like the bare simulation: same orbs, parries, hits, survivors and orbs in the air" % rate, comparable == expected_digest, _first_difference(comparable, expected_digest))
	_ok("the rates really differed: the engine drew %s frames for the same %d ticks" % [frames, RenderRateScenario.TOTAL_TICKS],
		frames.size() == PROBE_FRAME_RATES.size() and frames[5] < frames[20] and frames[20] < frames[60] and frames[60] < frames[240])
	var launch_output: Array = []
	OS.execute(executable, ["--headless", "--path", project, "--script", PROBE_SCRIPT, "--", "--probe=launch", "--encounter=spitters"], launch_output, true)
	var launch_line: String = _probe_line(launch_output)
	var launched: Dictionary = JSON.parse_string(launch_line) if not launch_line.is_empty() else {}
	_ok("the launch option --encounter=spitters starts the spitter encounter", String(launched.get("encounter", "")) == "spitters" and int(launched.get("wave_kinds", 0)) == 8 and not bool(launched.get("dev_shove", true)), "%s" % [launch_output])


func _probe_line(output: Array) -> String:
	for chunk: Variant in output:
		for line: String in String(chunk).split("\n"):
			if line.begins_with("PROBE {"):
				return line.trim_prefix("PROBE ")
	return ""


func _first_difference(a: Dictionary, b: Dictionary) -> String:
	for key: Variant in a:
		if JSON.stringify(a[key]) != JSON.stringify(b.get(key)):
			return "%s: %s vs %s" % [key, a[key], b.get(key)]
	return ""
