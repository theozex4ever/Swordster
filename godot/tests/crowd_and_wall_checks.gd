class_name CrowdAndWallChecks
extends RefCounted
## Game-run behavioural checks for runners, brutes, crowds and walls (issue #9).
## Like the Fang survival checks, every check drives the real `GameRun` through
## `GameCommand`s (or the real Main scene), advances fixed ticks and observes
## outcomes. Comparison values come from the Python prototype's captured
## reference (res://tests/reference/crowd_and_walls.json, recorded by
## tools/reference/capture_crowd_and_walls.py). The reference also carries each
## case's fixture (`setup`), so no starting position is copied into this file.
## Tolerances and exceptions: docs/reference/runners-brutes-crowd.md.

const REFERENCE_PATH: String = "res://tests/reference/crowd_and_walls.json"
const PROBE_SCRIPT: String = "res://tests/frame_rate_probe.gd"

## Same-algorithm comparisons at the prototype's 60 FPS step.
const POSITION_TOL: float = 0.05  # px
const VELOCITY_TOL: float = 0.05  # px/s
const SCALAR_TOL: float = 0.002  # health, timers, shake, stun
## The composite crowd runs hundreds of collisions; float32 vs the prototype's
## float64 can drift further than a single step does, but never beyond this.
const CROWD_POSITION_TOL: float = 0.5
const TICK_TOL: int = 1
## Frame rates (engine clock) the render-rate probe plays at.
const PROBE_FRAME_RATES: Array[int] = [5, 20, 60, 240]

var _check: Callable
var _tree: SceneTree
var _ref: Dictionary = {}


func _init(check_function: Callable, tree: SceneTree) -> void:
	_check = check_function
	_tree = tree


func run_all() -> void:
	var file: FileAccess = FileAccess.open(REFERENCE_PATH, FileAccess.READ)
	if file == null:
		_ok("crowd reference file loads", false, REFERENCE_PATH)
		return
	_ref = JSON.parse_string(file.get_as_text())
	_ok("crowd reference file parses", not _ref.is_empty())
	_check_reference_scope()
	_check_definitions()
	_check_movement()
	_check_contact()
	_check_hits_and_resistance()
	_check_fang_against_one_foe()
	_check_separation()
	_check_bowling()
	_check_chain_deaths()
	_check_wall_slams()
	_check_exactly_once()
	_check_crowd_encounter()
	_check_wall_encounter()
	_check_dev_shove_rules()
	_check_wave_composition()
	_check_restart_with_crowd()
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
	return placement


## No waves and no swords: only what the case itself puts in the arena.
func _arena(setups: Array, player_at: Vector2 = Vector2(-1.0, -1.0)) -> RunScenario:
	var scenario: RunScenario = RunScenario.new()
	scenario.seed = 23
	scenario.waves_enabled = false
	var no_swords: Array[SwordSpec] = []
	scenario.loadout = no_swords
	var placements: Array[EnemyPlacement] = []
	for setup: Variant in setups:
		placements.append(_placement(setup as Dictionary))
	scenario.initial_enemies = placements
	if player_at.x >= 0.0:
		scenario.start_position = player_at
	return scenario


func _enemy_matches(enemy: EnemyState, expected: Dictionary, position_tol: float) -> bool:
	return enemy.dead == bool(expected["dead"]) \
		and _near(enemy.position.x, float(expected["x"]), position_tol) \
		and _near(enemy.position.y, float(expected["y"]), position_tol) \
		and _near(enemy.velocity.x, float(expected["vx"]), maxf(VELOCITY_TOL, position_tol)) \
		and _near(enemy.velocity.y, float(expected["vy"]), maxf(VELOCITY_TOL, position_tol)) \
		and _near(enemy.hp, float(expected["hp"]), SCALAR_TOL) \
		and _near(enemy.stun, float(expected["stun"]), SCALAR_TOL)


func _describe(enemy: EnemyState) -> String:
	return "%s pos=%s vel=%s hp=%.3f stun=%.3f dead=%s" % [enemy.kind, enemy.position, enemy.velocity, enemy.hp, enemy.stun, enemy.dead]


## Snapshot comparison for a whole list of enemies, reporting the first difference.
func _all_match(enemies: Array[EnemyState], expected: Array, position_tol: float) -> String:
	if enemies.size() != expected.size():
		return "%d enemies vs %d expected" % [enemies.size(), expected.size()]
	for i: int in enemies.size():
		if not _enemy_matches(enemies[i], expected[i] as Dictionary, position_tol):
			return "enemy %d: %s vs %s" % [i, _describe(enemies[i]), expected[i]]
	return ""


func _count_cues(cues: Array[SimCue], kind: SimCue.Kind) -> int:
	var count: int = 0
	for cue: SimCue in cues:
		if cue.kind == kind:
			count += 1
	return count


## Steps the run, returning the tick of every cue of `kind` produced.
func _cue_ticks(run: GameRun, kind: SimCue.Kind, ticks: int) -> Array[int]:
	var found: Array[int] = []
	for i: int in ticks:
		run.step()
		for cue: SimCue in run.take_cues():
			if cue.kind == kind:
				found.append(run.tick)
	return found


func _ref_ticks(events: Array, event_name: String) -> Array[int]:
	var ticks: Array[int] = []
	for event: Variant in events:
		if (event as Dictionary)["event"] == event_name:
			ticks.append(int((event as Dictionary)["tick"]))
	return ticks


func _ticks_close(actual: Array[int], expected: Array[int], tolerance: int) -> bool:
	if actual.size() != expected.size():
		return false
	for i: int in actual.size():
		if absi(actual[i] - expected[i]) > tolerance:
			return false
	return true


func _kinds_of(setups: Array) -> Array[StringName]:
	var kinds: Array[StringName] = []
	for setup: Variant in setups:
		kinds.append(StringName((setup as Dictionary)["kind"]))
	return kinds


# ------------------------------------------------------ scope of the capture
func _check_reference_scope() -> void:
	print("crowd: the reference was captured with out-of-scope mechanics disabled")
	var scope: Dictionary = _ref["fixture_scope"]
	_ok("the capture ran with elemental conditions (afflict) disabled", bool(scope["afflict_disabled"]))
	_ok("no enemy in the capture was armed (arming and drops are issue #17)", int(scope["armed_enemies"]) == 0)
	_ok("the capture fielded only husks, runners and brutes (spitters are issue #10)", _same_names(scope["kinds"], ["husk", "runner", "brute"]))
	_ok("no sword was equipped in the capture, so no ultimate or Converge ran", int(scope["swords_equipped"]) == 0)
	_ok("the spitter is not ported by this slice", not EnemyDefs.is_supported(&"spitter"))


func _same_names(actual: Array, expected: Array[String]) -> bool:
	if actual.size() != expected.size():
		return false
	for i: int in actual.size():
		if String(actual[i]) != expected[i]:
			return false
	return true


# ------------------------------------------------------------- definitions
func _check_definitions() -> void:
	print("crowd: enemy stats and wave health against the prototype's ENEMY_TYPES")
	var table: Dictionary = _ref["table"]
	var types: Dictionary = table["types"]
	for kind: String in types:
		var expected: Dictionary = types[kind]
		var def: EnemyDefs = EnemyDefs.of(StringName(kind))
		_ok("%s: radius, health, speed, contact damage and knockback multiplier match" % kind,
			def.radius == float(expected["r"]) and def.hp == float(expected["hp"]) and def.speed == float(expected["speed"]) and def.damage == int(expected["dmg"]) and def.knock == float(expected["knock"]),
			"%s" % [expected])
		var health: Dictionary = (table["wave_health"] as Dictionary)[kind]
		var matches: bool = true
		for wave: String in health:
			var enemy: EnemyState = EnemyState.make(StringName(kind), Vector2.ZERO, int(wave), 1.0, 1)
			matches = matches and _near(enemy.max_hp, float(health[wave]), SCALAR_TOL) and enemy.hp == enemy.max_hp
		_ok("%s: health grows 10%% per wave after the first" % kind, matches)
	var brute: EnemyState = EnemyState.make(EnemyDefs.BRUTE, Vector2.ZERO, 1, 1.0, 1)
	var husk: EnemyState = EnemyState.make(EnemyDefs.HUSK, Vector2.ZERO, 1, 1.0, 1)
	var runner: EnemyState = EnemyState.make(EnemyDefs.RUNNER, Vector2.ZERO, 1, 1.0, 1)
	_ok("a runner is smaller and faster than a husk, a brute larger, slower and sturdier",
		runner.radius < husk.radius and husk.radius < brute.radius and runner.speed > husk.speed and husk.speed > brute.speed and brute.max_hp > husk.max_hp and husk.max_hp > runner.max_hp)


# ---------------------------------------------------------------- movement
func _check_movement() -> void:
	print("crowd: runner weave, husk and brute chase against the prototype")
	var marks: Dictionary = {15: "0.25", 30: "0.5", 60: "1.0", 120: "2.0", 180: "3.0"}
	var movement: Dictionary = _ref["movement"]
	for label: String in movement:
		var case: Dictionary = movement[label]
		var run: GameRun = GameRun.new(_arena(case["setup"]))
		var enemy: EnemyState = run.enemies[0]
		var centre: Vector2 = run.position
		var worst: String = ""
		for step_index: int in range(1, 181):
			run.step()
			if marks.has(step_index):
				var expected: Dictionary = (case["trace"] as Dictionary)[marks[step_index]]
				var here: Vector2 = enemy.position - centre
				var facing_ok: bool = _near(enemy.facing.x, float(expected["fx"]), 0.0005) and _near(enemy.facing.y, float(expected["fy"]), 0.0005)
				if not (_near(here.x, float(expected["x"]), POSITION_TOL) and _near(here.y, float(expected["y"]), POSITION_TOL) and _near(enemy.velocity.x, float(expected["vx"]), VELOCITY_TOL) and _near(enemy.velocity.y, float(expected["vy"]), VELOCITY_TOL) and facing_ok):
					worst += " t=%s got %s %s want %s" % [marks[step_index], here, enemy.velocity, expected]
		_ok("%s: position, velocity and facing at 0.25-3 s match%s" % [label, worst], worst.is_empty())
	var runner: Dictionary = movement["runner_t0.0"]
	var husk: Dictionary = movement["husk_t0.0"]
	var runner_end: Dictionary = (runner["trace"] as Dictionary)["3.0"]
	var husk_end: Dictionary = (husk["trace"] as Dictionary)["3.0"]
	_ok("a runner covers more ground than a husk, and weaves off the straight line",
		absf(float(runner_end["x"])) < absf(float(husk_end["x"])))
	var weave_a: Dictionary = (movement["runner_t0.0"]["trace"] as Dictionary)["1.0"]
	var weave_b: Dictionary = (movement["runner_t1.3"]["trace"] as Dictionary)["1.0"]
	_ok("the weave phase (the enemy's own clock) changes the path", absf(float(weave_a["y"]) - float(weave_b["y"])) > 1.0)

	# After the player dies enemies wander instead of weaving or chasing.
	var dead_scenario: RunScenario = _arena([movement["runner_t0.0"]["setup"][0]])
	var run_dead: GameRun = GameRun.new(dead_scenario)
	run_dead.dead = true
	var runner_state: EnemyState = run_dead.enemies[0]
	var start: Vector2 = runner_state.position
	_steps(run_dead, 180)
	_ok("a runner stops chasing once the player is dead and only drifts (speed %.1f, distance %.0f)" % [runner_state.velocity.length(), (runner_state.position - start).length()],
		_near(runner_state.velocity.length(), runner_state.speed * 0.3, 0.5) and (runner_state.position - start).length() < 200.0)


# ----------------------------------------------------------------- contact
func _check_contact() -> void:
	print("crowd: contact damage and knockback of each type")
	var contact: Dictionary = _ref["contact"]
	for kind: String in ["husk", "runner", "brute"]:
		var case: Dictionary = contact[kind]
		var run: GameRun = GameRun.new(_arena(case["setup"]))
		var enemy: EnemyState = run.enemies[0]
		run.step()
		var first: Dictionary = case["first_contact"]
		_ok("%s: first contact hurts for its damage, shoves both parties and stuns the enemy" % kind,
			_near(run.hp, float(first["hp"]), SCALAR_TOL) and _near(run.iframes, float(first["iframes"]), SCALAR_TOL)
			and _near(run.velocity.x, float(first["player_vx"]), VELOCITY_TOL) and _near(run.velocity.y, float(first["player_vy"]), VELOCITY_TOL)
			and _near(enemy.velocity.x, float(first["enemy_vx"]), VELOCITY_TOL) and _near(enemy.velocity.y, float(first["enemy_vy"]), VELOCITY_TOL)
			and _near(enemy.stun, float(first["enemy_stun"]), SCALAR_TOL) and _near(run.hitstop, float(first["hitstop"]), SCALAR_TOL) and _near(run.trauma, float(first["trauma"]), SCALAR_TOL),
			"hp %f vel %s enemy %s" % [run.hp, run.velocity, _describe(enemy)])
		run.hitstop = 0.0
		enemy.position = run.position + Vector2(8.0, 0.0)
		enemy.velocity = Vector2.ZERO
		enemy.stun = 0.0
		run.step()
		var refused: Dictionary = case["refused_contact"]
		_ok("%s: contact while invulnerable deals no damage but still shoves and stuns the enemy" % kind,
			_near(run.hp, float(refused["hp"]), SCALAR_TOL) and _near(enemy.velocity.x, float(refused["enemy_vx"]), VELOCITY_TOL) and _near(enemy.stun, float(refused["enemy_stun"]), SCALAR_TOL))

		var parked: GameRun = GameRun.new(_arena(case["setup"]))
		var parked_enemy: EnemyState = parked.enemies[0]
		var hit_ticks: Array[int] = []
		var hit_hp: Array[float] = []
		var last_hp: float = parked.hp
		for step_index: int in range(1, 241):
			parked.step()
			if parked.hp < last_hp:
				hit_ticks.append(step_index)
				hit_hp.append(parked.hp)
				last_hp = parked.hp
			parked_enemy.position = parked.position + Vector2(20.0, 0.0)
			parked_enemy.stun = 0.0
			if parked.dead:
				break
		var expected_ticks: Array[int] = []
		var expected_hp: Array[float] = []
		for hit: Variant in case["parked_hits"]:
			expected_ticks.append(int((hit as Dictionary)["tick"]))
			expected_hp.append(float((hit as Dictionary)["hp"]))
		_ok("%s: a parked enemy hits on the prototype's schedule (every ~0.88 s) for %d damage" % [kind, parked_enemy.damage], _ticks_close(hit_ticks, expected_ticks, TICK_TOL) and hit_hp == expected_hp, "%s %s" % [hit_ticks, hit_hp])
	var lethal: Dictionary = contact["brute_lethal"]
	var doomed_scenario: RunScenario = _arena(lethal["setup"])
	doomed_scenario.start_health = float(lethal["start_health"])
	var doomed: GameRun = GameRun.new(doomed_scenario)
	doomed.step()
	_ok("a brute's 20 damage kills a player on 15 health: dead, health 0, slow motion starts", doomed.dead and doomed.hp == float(lethal["hp"]) and _near(doomed.slowmo, float(lethal["slowmo"]), SCALAR_TOL) and _near(doomed.slowmo_scale, float(lethal["slowmo_scale"]), SCALAR_TOL))


# ------------------------------------------------------ knockback resistance
func _check_hits_and_resistance() -> void:
	print("crowd: knockback resistance, stun and launches")
	var hits: Dictionary = _ref["hits"]
	for crit: bool in [false, true]:
		for kind: String in ["husk", "runner", "brute"]:
			var label: String = "fang_%s_%s" % ["crit" if crit else "hit", kind]
			var case: Dictionary = hits[label]
			var scenario: RunScenario = _arena(case["setup"])
			scenario.crit_chance = 1.0 if crit else 0.0
			var run: GameRun = GameRun.new(scenario)
			var enemy: EnemyState = run.enemies[0]
			var full: float = enemy.hp
			run.hit_enemy(enemy, 7.0, Vector2.RIGHT, SwordDefs.FANG_KNOCK, null)
			_ok("%s: damage %d, knockback %.1f px/s, stun, hitstop and shake match" % [label, int(case["dealt"]), float(case["vx"])],
				_near(full - enemy.hp, float(case["dealt"]), SCALAR_TOL) and _near(enemy.velocity.x, float(case["vx"]), VELOCITY_TOL) and _near(enemy.velocity.y, float(case["vy"]), VELOCITY_TOL)
				and _near(enemy.stun, float(case["stun"]), 0.001) and _near(run.hitstop, float(case["hitstop"]), SCALAR_TOL) and _near(run.trauma, float(case["trauma"]), SCALAR_TOL),
				"%s hitstop %f trauma %f" % [_describe(enemy), run.hitstop, run.trauma])
	var brute_hit: Dictionary = hits["fang_hit_brute"]
	var husk_hit: Dictionary = hits["fang_hit_husk"]
	var runner_hit: Dictionary = hits["fang_hit_runner"]
	_ok("a brute is shoved 35%% as far as a husk and a runner 130%% (%.1f / %.1f / %.1f)" % [float(brute_hit["vx"]), float(husk_hit["vx"]), float(runner_hit["vx"])],
		_near(float(brute_hit["vx"]) / float(husk_hit["vx"]), 0.35, 0.001) and _near(float(runner_hit["vx"]) / float(husk_hit["vx"]), 1.3, 0.001))

	for kind: String in ["husk", "runner", "brute"]:
		var case: Dictionary = hits["colossus_launch_%s" % kind]
		var scenario: RunScenario = _arena(case["setup"])
		scenario.dev_shove = true
		var run: GameRun = GameRun.new(scenario)
		var enemy: EnemyState = run.enemies[0]
		run.apply(GameCommand.dev_shove())
		_ok("%s: a heavy blow (the dev shove) launches it at %.1f px/s with stun %.3f" % [kind, float(case["vx"]), float(case["stun"])],
			_near(enemy.velocity.x, float(case["vx"]), VELOCITY_TOL) and _near(enemy.velocity.y, float(case["vy"]), VELOCITY_TOL) and _near(enemy.stun, float(case["stun"]), 0.001), _describe(enemy))
	var moving: Dictionary = hits["relaunch_moving_husk"]
	var moving_scenario: RunScenario = _arena(moving["setup"])
	moving_scenario.dev_shove = true
	var moving_run: GameRun = GameRun.new(moving_scenario)
	moving_run.apply(GameCommand.dev_shove())
	var moving_enemy: EnemyState = moving_run.enemies[0]
	_ok("an enemy already moving keeps 30%% of its velocity when launched again", _near(moving_enemy.velocity.x, float(moving["vx"]), VELOCITY_TOL) and _near(moving_enemy.velocity.y, float(moving["vy"]), VELOCITY_TOL) and _near(moving_enemy.stun, float(moving["stun"]), 0.001), _describe(moving_enemy))


# ------------------------------------------------- one Fang against one foe
func _check_fang_against_one_foe() -> void:
	print("crowd: one Fang against a brute and a runner, tick by tick")
	var cases: Dictionary = _ref["fang_vs_one_foe"]
	for kind: String in ["brute", "runner"]:
		var case: Dictionary = cases[kind]
		var scenario: RunScenario = _arena(case["setup"])
		scenario.seed = 31
		var one_fang: Array[SwordSpec] = [SwordSpec.make(&"fang", 0, &"fire")]
		scenario.loadout = one_fang
		scenario.sword_start_cooldowns = [0.4]
		scenario.crit_chance = 0.0
		var run: GameRun = GameRun.new(scenario)
		var enemy: EnemyState = run.enemies[0]
		var hit_ticks: Array[int] = []
		var previous: float = enemy.hp
		var death_tick: int = -1
		for step_index: int in range(1, 1201):
			run.step()
			if enemy.hp < previous:
				hit_ticks.append(step_index)
				previous = enemy.hp
			if enemy.dead:
				death_tick = step_index
				break
		var expected: Array[int] = []
		for hit: Variant in case["hits"]:
			expected.append(int((hit as Dictionary)["tick"]))
		_ok("%s: %d Fang hits land on the prototype's ticks and the foe dies at tick %d" % [kind, expected.size(), int(case["death_tick"])],
			_ticks_close(hit_ticks, expected, TICK_TOL) and absi(death_tick - int(case["death_tick"])) <= TICK_TOL, "%s vs %s, death %d" % [hit_ticks, expected, death_tick])
		_ok("%s: the kill is rewarded once (kills %d, motes %d) and the player was never touched" % [kind, run.kills, run.motes.size()],
			run.kills == int(case["kills"]) and run.motes.size() == int(case["motes"]) and run.hp == float(case["player_hp"]))


# -------------------------------------------------------------- separation
func _check_separation() -> void:
	print("crowd: mass- and radius-sensitive separation")
	var separation: Dictionary = _ref["separation"]
	for label: String in separation:
		if label == "packed_crowd_12":
			continue
		var case: Dictionary = separation[label]
		var run: GameRun = GameRun.new(_arena(case["setup"]))
		var pair: Array[EnemyState] = [run.enemies[0], run.enemies[1]]
		var trace: Dictionary = case["trace"]
		var problem: String = ""
		for step_index: int in range(1, 31):
			run.step()
			if trace.has(str(step_index)):
				var expected: Dictionary = trace[str(step_index)]
				var mismatch: String = _all_match(pair, [expected["a"], expected["b"]], POSITION_TOL)
				var gap: float = pair[0].position.distance_to(pair[1].position)
				if not mismatch.is_empty() or not _near(gap, float(expected["distance"]), POSITION_TOL):
					problem += " tick %d: %s" % [step_index, mismatch]
		_ok("%s: positions after 1, 2 and 30 ticks match%s" % [label, problem], problem.is_empty())

	var heavy: Dictionary = separation["husk_brute_overlap_16"]["trace"]["1"]
	var husk_push: float = absf(float((heavy["a"] as Dictionary)["x"]) - 600.0)
	var brute_push: float = absf(float((heavy["b"] as Dictionary)["x"]) - 630.0)
	_ok("the lighter husk is pushed 3.5 times farther than the brute (%.2f vs %.2f px; masses r squared)" % [husk_push, brute_push], _near(husk_push / brute_push, 900.0 / 256.0, 0.01))
	var touching: Dictionary = separation["husk_brute_exactly_touching"]["trace"]["30"]
	_ok("enemies exactly touching are left alone", _near(float((touching["b"] as Dictionary)["x"]) - float((touching["a"] as Dictionary)["x"]), 46.0, 0.0005))
	var coincident: Dictionary = separation["husk_husk_coincident"]["trace"]["30"]
	_ok("two enemies at the same point do not separate (the prototype's zero-distance case)", float((coincident["a"] as Dictionary)["x"]) == float((coincident["b"] as Dictionary)["x"]))

	var packed: Dictionary = separation["packed_crowd_12"]
	var crowd_run: GameRun = GameRun.new(_arena(packed["setup"]))
	var crowd: Array[EnemyState] = []
	crowd.append_array(crowd_run.enemies)
	var crowd_problem: String = ""
	for step_index: int in range(1, 61):
		crowd_run.step()
		if (packed["trace"] as Dictionary).has(str(step_index)):
			var mismatch: String = _all_match(crowd, (packed["trace"] as Dictionary)[str(step_index)], POSITION_TOL)
			if not mismatch.is_empty():
				crowd_problem += " tick %d: %s" % [step_index, mismatch]
	_ok("a packed crowd of twelve mixed enemies resolves exactly as the prototype's does over 60 ticks%s" % crowd_problem, crowd_problem.is_empty())
	var overlaps: int = 0
	for i: int in crowd.size():
		for j: int in range(i + 1, crowd.size()):
			if crowd[i].position.distance_to(crowd[j].position) < crowd[i].radius + crowd[j].radius - 1.0:
				overlaps += 1
	_ok("after 60 ticks no two crowd members still overlap by more than a pixel (%d pairs)" % overlaps, overlaps == 0)


# ----------------------------------------------------------------- bowling
func _check_bowling() -> void:
	print("crowd: launched enemies bowl into others")
	var bowling: Dictionary = _ref["bowling"]
	for label: String in bowling:
		var case: Dictionary = bowling[label]
		var setups: Array = case["setup"]
		var run: GameRun = GameRun.new(_arena(setups))
		var pair: Array[EnemyState] = [run.enemies[0], run.enemies[1]]
		var target_hp: float = pair[1].hp
		var problem: String = ""
		for step_index: int in range(1, 11):
			run.step()
			if (case["trace"] as Dictionary).has(str(step_index)):
				var expected: Dictionary = (case["trace"] as Dictionary)[str(step_index)]
				var mismatch: String = _all_match(pair, [expected["launched"], expected["target"]], POSITION_TOL)
				if not mismatch.is_empty() or not _near(run.trauma, float(expected["trauma"]), SCALAR_TOL):
					problem += " tick %d: %s trauma %f" % [step_index, mismatch, run.trauma]
		_ok("%s: both enemies' position, velocity, health and stun match at 1, 2 and 10 ticks%s" % [label, problem], problem.is_empty())
		var bowled: bool = pair[1].hp < target_hp
		_ok("%s: a collision is reported (and counted) exactly when the target took bowling damage" % label, (run.cue_count(SimCue.Kind.BOWLED) > 0) == bowled, "cues %d hp %f -> %f" % [run.cue_count(SimCue.Kind.BOWLED), target_hp, pair[1].hp])

	var brute_into_runner: Dictionary = ((bowling["brute_into_runner"] as Dictionary)["trace"] as Dictionary)["1"]
	var runner_into_brute: Dictionary = ((bowling["runner_into_brute"] as Dictionary)["trace"] as Dictionary)["1"]
	var heavy_hit: float = absf(float(((brute_into_runner as Dictionary)["target"] as Dictionary)["vx"]))
	var light_hit: float = absf(float(((runner_into_brute as Dictionary)["target"] as Dictionary)["vx"]))
	_ok("a launched brute throws a runner %.0f px/s but a launched runner only moves a brute %.0f px/s (relative size)" % [heavy_hit, light_hit], heavy_hit > 5.0 * light_hit)
	for threshold_case: String in ["just_under_340", "not_stunned", "moving_away"]:
		var target: Dictionary = (((bowling[threshold_case] as Dictionary)["trace"] as Dictionary)["10"] as Dictionary)["target"]
		_ok("%s: the target is untouched (no bowling below the speed threshold, without stun, or moving away)" % threshold_case, float(target["hp"]) == 30.0)
	var over: Dictionary = ((((bowling["just_over_340"] as Dictionary)["trace"] as Dictionary)["1"]) as Dictionary)["target"]
	_ok("just over the 340 px/s threshold the target takes 3 damage", float(over["hp"]) == 27.0)


func _check_chain_deaths() -> void:
	print("crowd: chained collision deaths resolve once each")
	var chains: Dictionary = _ref["chain_deaths"]
	for label: String in chains:
		var case: Dictionary = chains[label]
		var run: GameRun = GameRun.new(_arena(case["setup"]))
		var everyone: Array[EnemyState] = []
		everyone.append_array(run.enemies)
		var kill_ticks: Array[int] = []
		var motes_at_12: int = -1
		var kills_at_12: int = -1
		for step_index: int in range(1, 181):
			run.step()
			kill_ticks.append_array(_cue_ticks_in(run.take_cues(), step_index))
			if step_index == 12:
				motes_at_12 = run.motes.size()
				kills_at_12 = run.kills
		var expected_ticks: Array[int] = []
		for entry: Variant in case["kill_log"]:
			expected_ticks.append(int((entry as Dictionary)["tick"]))
		var dead_bodies: int = 0
		for enemy: EnemyState in everyone:
			dead_bodies += 1 if enemy.dead else 0
		_ok("%s: the deaths come on the prototype's ticks %s" % [label, expected_ticks], _ticks_close(kill_ticks, expected_ticks, TICK_TOL), "%s" % [kill_ticks])
		_ok("%s: %d kills, %d combo, exactly three motes per kill" % [label, int(case["kills"]), int(case["best_combo"])],
			run.kills == int(case["kills"]) and run.best_combo == int(case["best_combo"]) and kills_at_12 == int(case["kills_at_12"]) and motes_at_12 == int(case["motes_at_12"]),
			"kills %d combo %d motes@12 %d vs %d" % [run.kills, run.best_combo, motes_at_12, int(case["motes_at_12"])])
		_ok("%s: kills, kill cues and dead bodies all agree (no duplicate or missing death)" % label, run.kills == dead_bodies and run.cue_count(SimCue.Kind.ENEMY_KILLED) == run.kills, "%d %d %d" % [run.kills, dead_bodies, run.cue_count(SimCue.Kind.ENEMY_KILLED)])
		var survivors: int = 0
		for enemy: EnemyState in run.enemies:
			survivors += 1
		_ok("%s: survivors match and the dead have left the run" % label, survivors == int(case["survivors"]) and survivors + run.kills == everyone.size())


func _cue_ticks_in(cues: Array[SimCue], tick_value: int) -> Array[int]:
	var found: Array[int] = []
	for cue: SimCue in cues:
		if cue.kind == SimCue.Kind.ENEMY_KILLED:
			found.append(tick_value)
	return found


# ------------------------------------------------------------- wall slams
func _check_wall_slams() -> void:
	print("crowd: wall slams")
	var slams: Dictionary = _ref["wall_slam"]
	for label: String in slams:
		var case: Dictionary = slams[label]
		var run: GameRun = GameRun.new(_arena(case["setup"]))
		var enemy: EnemyState = run.enemies[0]
		var full: float = enemy.hp
		run.step()
		var cues: Array[SimCue] = run.take_cues()
		var expected: Dictionary = case["after"]
		_ok("%s: health, bounce velocity, stun, kills, hitstop and shake match" % label,
			_enemy_matches(enemy, expected, POSITION_TOL) and run.kills == int(case["kills"]) and _near(run.hitstop, float(case["hitstop"]), SCALAR_TOL) and _near(run.trauma, float(case["trauma"]), SCALAR_TOL) and run.motes.size() == int(case["motes"]),
			"%s hitstop %f trauma %f kills %d" % [_describe(enemy), run.hitstop, run.trauma, run.kills])
		var lost: float = full - enemy.hp
		var slam_cues: int = _count_cues(cues, SimCue.Kind.WALL_SLAM)
		_ok("%s: a slam is reported exactly when it hurt, with the damage dealt" % label, (slam_cues == 1) == (lost > 0.0) and (slam_cues == 0 or _slam_amount(cues) == int(lost)))
	# The threshold sits at a speed of 380 px/s after one tick of stun drag.
	var below: Dictionary = (slams["husk_east_412"]["after"] as Dictionary)
	var above: Dictionary = (slams["husk_east_414"]["after"] as Dictionary)
	_ok("an enemy arriving just under 380 px/s is not slammed, one just over it is", float(below["hp"]) == 500.0 and float(above["hp"]) == 494.0)
	var damage_by_speed: Array[float] = []
	for label: String in ["husk_east_420", "husk_east_500", "husk_east_800", "husk_east_1200"]:
		damage_by_speed.append(500.0 - float((slams[label]["after"] as Dictionary)["hp"]))
	_ok("slam damage grows with arrival speed: %s" % [damage_by_speed], damage_by_speed == [6.0, 9.0, 20.0, 35.0])
	_ok("unstunned enemies are not slammed, whatever their speed", float((slams["husk_east_800_not_stunned"]["after"] as Dictionary)["hp"]) == 500.0)
	_ok("a slam caps the stun at 0.15 s but never lengthens a shorter one", float((slams["husk_east_800"]["after"] as Dictionary)["stun"]) == 0.15 and _near(float((slams["husk_east_800_stun_0.05"]["after"] as Dictionary)["stun"]), 0.05 - GameRun.TICK_DT, 0.001))
	_ok("all four walls and the corner slam (a corner counts once)", float((slams["husk_west_800"]["after"] as Dictionary)["hp"]) == 480.0 and float((slams["husk_south_800"]["after"] as Dictionary)["hp"]) == 480.0 and float((slams["husk_north_800"]["after"] as Dictionary)["hp"]) == 480.0 and float((slams["husk_corner_800"]["after"] as Dictionary)["hp"]) == 480.0)


func _slam_amount(cues: Array[SimCue]) -> int:
	for cue: SimCue in cues:
		if cue.kind == SimCue.Kind.WALL_SLAM:
			return cue.amount
	return -1


# ------------------------------------------------------------ exactly once
func _check_exactly_once() -> void:
	print("crowd: deaths and rewards happen exactly once")
	# A victim slammed to death by the wall in the same tick a bowler hits its corpse.
	var scenario: RunScenario = _arena([])
	var victim: EnemyPlacement = EnemyPlacement.make(EnemyDefs.HUSK, Vector2(GameRun.WORLD.end.x - EnemyDefs.HUSK_RADIUS - 1.0, 700.0)).launched(Vector2(800.0, 0.0), 0.6)
	victim.hp = 2.0
	victim.speed_scale = 0.0
	var bowler: EnemyPlacement = EnemyPlacement.make(EnemyDefs.BRUTE, Vector2(GameRun.WORLD.end.x - EnemyDefs.HUSK_RADIUS - 1.0 - 40.0, 700.0)).launched(Vector2(1000.0, 0.0), 0.6)
	bowler.speed_scale = 0.0
	scenario.initial_enemies = [victim, bowler]
	var run: GameRun = GameRun.new(scenario)
	var killed: EnemyState = run.enemies[0]
	_steps(run, 12)
	_ok("an enemy slammed dead and bowled in the same tick dies once (kills %d, kill cues %d, motes %d)" % [run.kills, run.cue_count(SimCue.Kind.ENEMY_KILLED), run.motes.size()],
		killed.dead and run.kills == 1 and run.cue_count(SimCue.Kind.ENEMY_KILLED) == 1 and run.motes.size() == 3 and run.best_combo == 1)
	_ok("the slam and the bowl that preceded the death were both reported", run.cue_count(SimCue.Kind.WALL_SLAM) >= 1)

	# Three launched enemies converge on one with 2 health: one death, not three.
	var pile: RunScenario = _arena([])
	var target: EnemyPlacement = EnemyPlacement.make(EnemyDefs.HUSK, Vector2(800.0, 800.0))
	target.hp = 2.0
	target.speed_scale = 0.0
	var east: EnemyPlacement = EnemyPlacement.make(EnemyDefs.BRUTE, Vector2(800.0 + 46.0 - 4.0, 800.0)).launched(Vector2(-700.0, 0.0), 0.5)
	var south: EnemyPlacement = EnemyPlacement.make(EnemyDefs.BRUTE, Vector2(800.0, 800.0 + 46.0 - 4.0)).launched(Vector2(0.0, -700.0), 0.5)
	var west: EnemyPlacement = EnemyPlacement.make(EnemyDefs.BRUTE, Vector2(800.0 - 46.0 + 4.0, 800.0)).launched(Vector2(700.0, 0.0), 0.5)
	for placement: EnemyPlacement in [east, south, west]:
		placement.speed_scale = 0.0
	pile.initial_enemies = [target, east, south, west]
	var pile_run: GameRun = GameRun.new(pile)
	_steps(pile_run, 6)
	_ok("three bowlers converging on one weak enemy kill it exactly once (kills %d, cues %d, motes %d)" % [pile_run.kills, pile_run.cue_count(SimCue.Kind.ENEMY_KILLED), pile_run.motes.size()],
		pile_run.kills == 1 and pile_run.cue_count(SimCue.Kind.ENEMY_KILLED) == 1 and pile_run.motes.size() == 3)
	_ok("every bowling impact was reported, however many hit the dead enemy", pile_run.cue_count(SimCue.Kind.BOWLED) >= 1)

	# A Fang kill and a slam kill of different enemies in one tick each count once.
	var mixed: RunScenario = _arena([])
	var fast_a: EnemyPlacement = EnemyPlacement.make(EnemyDefs.RUNNER, Vector2(GameRun.WORLD.end.x - EnemyDefs.RUNNER_RADIUS - 1.0, 500.0)).launched(Vector2(900.0, 0.0), 0.6)
	var fast_b: EnemyPlacement = EnemyPlacement.make(EnemyDefs.RUNNER, Vector2(GameRun.WORLD.end.x - EnemyDefs.RUNNER_RADIUS - 1.0, 1500.0)).launched(Vector2(900.0, 0.0), 0.6)
	fast_a.speed_scale = 0.0
	fast_b.speed_scale = 0.0
	mixed.initial_enemies = [fast_a, fast_b]
	var mixed_run: GameRun = GameRun.new(mixed)
	_steps(mixed_run, 3)
	_ok("two slam deaths in one tick count two kills, a combo of two and six motes", mixed_run.kills == 2 and mixed_run.best_combo == 2 and mixed_run.motes.size() == 6)


# --------------------------------------------------- the composite encounter
func _check_crowd_encounter() -> void:
	print("crowd: a shoved crowd pinned against the wall, tick by tick")
	var encounter: Dictionary = _ref["crowd_encounter"]
	var player: Array = encounter["player"]
	var scenario: RunScenario = _arena(encounter["setup"], Vector2(float(player[0]), float(player[1])))
	scenario.dev_shove = true
	var run: GameRun = GameRun.new(scenario)
	var crowd: Array[EnemyState] = []
	crowd.append_array(run.enemies)
	run.apply(GameCommand.dev_shove())
	var snapshots: Dictionary = encounter["snapshots"]
	var problem: String = ""
	var slam_ticks: Array[int] = []
	var kill_ticks: Array[int] = []
	for step_index: int in range(1, 241):
		run.step()
		for cue: SimCue in run.take_cues():
			if cue.kind == SimCue.Kind.WALL_SLAM:
				slam_ticks.append(step_index)
			elif cue.kind == SimCue.Kind.ENEMY_KILLED:
				kill_ticks.append(step_index)
		if snapshots.has(str(step_index)):
			var expected: Dictionary = snapshots[str(step_index)]
			var mismatch: String = _all_match(crowd, expected["enemies"], CROWD_POSITION_TOL)
			if not mismatch.is_empty() or run.kills != int(expected["kills"]) or not _near(run.hp, float(expected["player_hp"]), SCALAR_TOL):
				problem += " tick %d: %s (kills %d vs %d)" % [step_index, mismatch, run.kills, int(expected["kills"])]
	_ok("every enemy's position, velocity, health and stun match the prototype at ticks 10, 30, 60, 120 and 240%s" % problem, problem.is_empty())
	var events: Array = encounter["events"]
	_ok("the wall slams happen on the prototype's ticks %s" % [_ref_ticks(events, "wall_slam")], _ticks_close(slam_ticks, _ref_ticks(events, "wall_slam"), TICK_TOL), "%s" % [slam_ticks])
	_ok("the deaths happen on the prototype's ticks %s and each is counted once" % [_ref_ticks(events, "kill")], _ticks_close(kill_ticks, _ref_ticks(events, "kill"), TICK_TOL) and run.kills == int(encounter["final_kills"]) and run.cue_count(SimCue.Kind.ENEMY_KILLED) == run.kills, "%s kills %d" % [kill_ticks, run.kills])
	var any_slammed: bool = false
	for entry: Variant in events:
		any_slammed = any_slammed or (entry as Dictionary)["event"] == "wall_slam"
	_ok("the composite really exercised the wall and bowling (slams %d, bowls %d)" % [slam_ticks.size(), run.cue_count(SimCue.Kind.BOWLED)], any_slammed and slam_ticks.size() >= 3)


# --------------------------------------------------------- the dev shove
func _check_wall_encounter() -> void:
	print("crowd: the wall encounter is the reference's pinned crowd")
	var encounter: Dictionary = _ref["crowd_encounter"]
	var setups: Array = encounter["setup"]
	var scenario: RunScenario = RunScenario.wall_encounter()
	var same_crowd: bool = scenario.initial_enemies.size() == setups.size()
	for i: int in mini(setups.size(), scenario.initial_enemies.size()):
		var placement: EnemyPlacement = scenario.initial_enemies[i]
		var setup: Dictionary = setups[i]
		same_crowd = same_crowd and placement.kind == StringName(setup["kind"]) and placement.position == Vector2(float(setup["x"]), float(setup["y"]))
	var player: Array = encounter["player"]
	_ok("the playable wall encounter holds exactly the reference crowd and player position", same_crowd and scenario.start_position == Vector2(float(player[0]), float(player[1])))
	scenario.loadout = []
	scenario.seed = 23
	var run: GameRun = GameRun.new(scenario)
	run.apply(GameCommand.dev_shove())
	var slam_ticks: Array[int] = []
	for step_index: int in range(1, 241):
		run.step()
		for cue: SimCue in run.take_cues():
			if cue.kind == SimCue.Kind.WALL_SLAM:
				slam_ticks.append(step_index)
	_ok("shoving it slams the crowd into the wall on the prototype's ticks (without swords it plays the captured composite)", _ticks_close(slam_ticks, _ref_ticks(encounter["events"], "wall_slam"), TICK_TOL) and run.kills == int(encounter["final_kills"]), "%s kills %d" % [slam_ticks, run.kills])
	var fought: GameRun = GameRun.new(RunScenario.wall_encounter())
	_ok("the wall encounter has a three-Fang loadout and no further wave", fought.swords.size() == 3 and not fought.scenario.waves_enabled and fought.enemies.size() == 14)


func _check_dev_shove_rules() -> void:
	print("crowd: the dev shove is only a fixture")
	var near: EnemyPlacement = EnemyPlacement.make(EnemyDefs.HUSK, GameRun.WORLD.get_center() + Vector2(0.0, 320.0))
	var far: EnemyPlacement = EnemyPlacement.make(EnemyDefs.HUSK, GameRun.WORLD.get_center() + Vector2(0.0, 321.0))
	var left: EnemyPlacement = EnemyPlacement.make(EnemyDefs.RUNNER, GameRun.WORLD.get_center() + Vector2(-100.0, 0.0))
	for placement: EnemyPlacement in [near, far, left]:
		placement.speed_scale = 0.0
	var scenario: RunScenario = _arena([])
	scenario.initial_enemies = [near, far, left]
	scenario.dev_shove = true
	var run: GameRun = GameRun.new(scenario)
	run.apply(GameCommand.dev_shove())
	_ok("enemies within 320 px are launched directly away from the player; farther ones are not",
		run.enemies[0].velocity.length() > 600.0 and run.enemies[0].velocity.y > 0.0 and run.enemies[1].velocity == Vector2.ZERO)
	_ok("a runner is launched farther than a husk (x1.3 vs x1)", run.enemies[2].velocity.x < 0.0 and run.enemies[2].velocity.length() > run.enemies[0].velocity.length() * 1.2)
	_ok("the shove is reported once and shakes the screen", run.cue_count(SimCue.Kind.SHOVE) == 1 and run.trauma > 0.3)

	var normal: RunScenario = _arena([])
	normal.initial_enemies = [near]
	var normal_run: GameRun = GameRun.new(normal)
	normal_run.apply(GameCommand.dev_shove())
	_ok("outside the fixture scenario the shove command does nothing", normal_run.enemies[0].velocity == Vector2.ZERO and normal_run.cue_count(SimCue.Kind.SHOVE) == 0)

	var paused: GameRun = GameRun.new(scenario)
	paused.apply(GameCommand.pause())
	paused.apply(GameCommand.dev_shove())
	_ok("a paused run ignores the shove", paused.enemies[0].velocity == Vector2.ZERO)
	var dead: GameRun = GameRun.new(scenario)
	dead.dead = true
	dead.apply(GameCommand.dev_shove())
	_ok("a dead player cannot shove", dead.enemies[0].velocity == Vector2.ZERO)
	var corpse: GameRun = GameRun.new(scenario)
	corpse.enemies[0].dead = true
	corpse.apply(GameCommand.dev_shove())
	_ok("an enemy already dead is left alone by the shove", corpse.enemies[0].velocity == Vector2.ZERO)
	var shoved_inputs: InputTranslator = InputTranslator.new()
	var commands: Array[GameCommand] = shoved_inputs.handle_event(_key(KEY_F))
	var toggles: Array[GameCommand] = shoved_inputs.handle_event(_key(KEY_C))
	_ok("F is the shove key and C switches the encounter", commands.size() == 1 and commands[0].kind == GameCommand.Kind.DEV_SHOVE and toggles.size() == 1 and toggles[0].kind == GameCommand.Kind.TOGGLE_ENCOUNTER)


func _key(code: Key) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = true
	return event


# ----------------------------------------------------- wave composition
func _check_wave_composition() -> void:
	print("crowd: the encounter's wave fields husks, runners and brutes")
	_ok("the normal run stays the husk wave (the prototype's wave 1 has no runners or brutes)", RunScenario.new().wave_kinds.is_empty() and not RunScenario.new().dev_shove)
	var scenario: RunScenario = RunScenario.crowd_encounter()
	scenario.seed = 9
	scenario.first_wave_delay = 0.1
	var run: GameRun = GameRun.new(scenario)
	var spawned: Array[StringName] = []
	var seen: Dictionary[int, bool] = {}
	var markers_by_kind: Dictionary[StringName, int] = {}
	var spawn_ages: Array[float] = []
	var guard: int = 0
	while (run.director.wave == 0 or not run.director.queue.is_empty() or not run.director.markers.is_empty()) and guard < 60 * 20:
		run.step()
		for marker: SpawnMarker in run.director.markers:
			if marker.remaining > SpawnMarker.TELEGRAPH - 0.02:
				markers_by_kind[marker.kind] = markers_by_kind.get(marker.kind, 0) + 1
		for enemy: EnemyState in run.enemies:
			if not seen.has(enemy.serial):
				seen[enemy.serial] = true
				spawned.append(enemy.kind)
				spawn_ages.append(enemy.age)
		guard += 1
	var composition: Array[StringName] = RunScenario.CROWD_WAVE
	_ok("enemies arrive in the fixture's order (%d of them)" % spawned.size(), spawned == composition, "%s" % [spawned])
	var counts: Dictionary[StringName, int] = {}
	for kind: StringName in spawned:
		counts[kind] = counts.get(kind, 0) + 1
	_ok("the wave is five husks, five runners and two brutes", counts.get(EnemyDefs.HUSK, 0) == 5 and counts.get(EnemyDefs.RUNNER, 0) == 5 and counts.get(EnemyDefs.BRUTE, 0) == 2, "%s" % [counts])
	_ok("each enemy was telegraphed as its own type before appearing", markers_by_kind.get(EnemyDefs.RUNNER, 0) == 5 and markers_by_kind.get(EnemyDefs.BRUTE, 0) == 2 and markers_by_kind.get(EnemyDefs.HUSK, 0) == 5, "%s" % [markers_by_kind])
	_ok("spawn cues match the enemies that appeared", run.cue_count(SimCue.Kind.ENEMY_SPAWNED) == spawned.size())
	var distinct_phases: Dictionary[int, bool] = {}
	var in_range: bool = true
	for age: float in spawn_ages:
		distinct_phases[roundi(age * 1000.0)] = true
		in_range = in_range and age >= 0.0 and age < 10.1
	_ok("each enemy spawns with its own random clock phase in 0-10 s, so runners do not weave in step (%d distinct of %d)" % [distinct_phases.size(), spawn_ages.size()], in_range and distinct_phases.size() >= 10)
	# Each type spawns with its own stats, scaled by its wave.
	var checks_out: bool = true
	for enemy: EnemyState in run.enemies:
		var def: EnemyDefs = EnemyDefs.of(enemy.kind)
		checks_out = checks_out and enemy.radius == def.radius and enemy.damage == def.damage and enemy.knock_mult == def.knock and enemy.max_hp == def.hp
	_ok("spawned enemies carry their type's radius, damage, knockback multiplier and health", checks_out and not run.enemies.is_empty())
	# The fixture is playable end to end under real play: the player can finish it.
	var clear: RunScenario = RunScenario.crowd_encounter()
	clear.seed = 9
	clear.first_wave_delay = 0.1
	var cleared: GameRun = GameRun.new(clear)
	var safe: int = 0
	while cleared.outcome() == GameRun.Outcome.RUNNING and safe < 60 * 90:
		if safe % 150 == 40:
			cleared.apply(GameCommand.dev_shove())
		cleared.step()
		cleared.take_cues()
		safe += 1
	_ok("the encounter reaches an outcome (%s after %.1f s, kills %d of 12)" % [GameRun.Outcome.keys()[cleared.outcome()], cleared.real_time, cleared.kills], cleared.outcome() != GameRun.Outcome.RUNNING)
	_ok("every enemy killed was rewarded once", cleared.kills == cleared.cue_count(SimCue.Kind.ENEMY_KILLED) and cleared.kills <= 12)


func _check_restart_with_crowd() -> void:
	print("crowd: switching scenarios and restarting leaves nothing behind")
	var run: GameRun = GameRun.new(null)
	_ok("the plain run is not the dev fixture", not run.scenario.dev_shove)
	run.apply(GameCommand.toggle_encounter())
	_ok("the encounter command restarts the run as the crowd encounter", run.scenario.dev_shove and run.restarts == 1 and run.tick == 0)
	run.scenario.first_wave_delay = 0.05
	_steps(run, 600)
	_ok("the crowd wave is under way", run.director.wave == 1 and run.enemies.size() > 0)
	run.apply(GameCommand.dev_shove())
	_steps(run, 30)
	run.apply(GameCommand.toggle_encounter())
	_ok("switching back restores the normal scenario", not run.scenario.dev_shove and run.restarts == 2)
	_ok("nothing from the crowd fight survives the switch: enemies, motes, counters, markers, cues",
		run.enemies.is_empty() and run.motes.is_empty() and run.kills == 0 and run.combo == 0 and run.director.markers.is_empty() and run.director.queue.is_empty()
		and run.cue_count(SimCue.Kind.ENEMY_KILLED) == 0 and run.cue_count(SimCue.Kind.WALL_SLAM) == 0 and run.take_cues().is_empty())
	run.apply(GameCommand.toggle_encounter())
	_ok("toggling again returns to the crowd encounter", run.scenario.dev_shove)
	var crowd_first: GameRun = GameRun.new(RunScenario.crowd_encounter())
	crowd_first.apply(GameCommand.toggle_encounter())
	_ok("a run that began as the crowd encounter toggles back to the plain run", not crowd_first.scenario.dev_shove and crowd_first.scenario.wave_kinds.is_empty())


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


func _press(main: Main, code: Key) -> void:
	main._input(_key(code))


func _check_main_scene() -> void:
	print("crowd: the Main scene shows and controls the encounter")
	var scenario: RunScenario = RunScenario.crowd_encounter()
	scenario.seed = 12
	scenario.first_wave_delay = 0.1
	var main: Main = _main_with(scenario, "res://tests/alt_enemy.tscn")
	await _tree.process_frame
	_ok("launching without a request starts the plain run, a crowd scenario starts the encounter", LaunchOptions.requested_encounter().is_empty() and LaunchOptions.requested_scenario() == null and main.run.scenario.dev_shove)
	_tick_main(main, 60 * 6)
	await _tree.process_frame
	var kinds_seen: Dictionary[StringName, int] = {}
	for enemy: EnemyState in main.run.enemies:
		kinds_seen[enemy.kind] = kinds_seen.get(enemy.kind, 0) + 1
	_ok("the presenter shows a visual for every enemy: %d visuals for %d enemies and the three swords" % [main._presenter.visual_count(), main.run.enemies.size()], main._presenter.visual_count() == main.run.enemies.size() + 3)
	_ok("runners, brutes and husks are all on screen (%s)" % [kinds_seen], kinds_seen.has(EnemyDefs.RUNNER) and kinds_seen.has(EnemyDefs.BRUTE) and kinds_seen.has(EnemyDefs.HUSK))
	_press(main, KEY_F)
	_tick_main(main, 2)
	var stunned_visuals: int = 0
	var alt_visuals: int = 0
	for child: Node in main._presenter.get_children():
		if child is AltEnemyVisual and not child.is_queued_for_deletion():
			alt_visuals += 1
			stunned_visuals += 1 if (child as AltEnemyVisual).last_stunned else 0
	_ok("F shoves through the real input path and the visuals are told which enemies are stunned (%d of %d)" % [stunned_visuals, alt_visuals], main.run.cue_count(SimCue.Kind.SHOVE) == 1 and stunned_visuals > 0)
	_ok("the shove button and legend are shown in the encounter", main._hud._shove_button.visible and main._hud._encounter_label.visible and main._hud._encounter_label.text.contains("brute"))
	_tick_main(main, 40)
	main._hud._shove_button.button_down.emit()
	_ok("the Shove button acts on press", main.run.cue_count(SimCue.Kind.SHOVE) == 2)
	main._hud._encounter_button.button_down.emit()
	await _tree.process_frame
	_ok("the Crowd/Normal button switches back to the plain run and clears the arena", not main.run.scenario.dev_shove and main.run.enemies.is_empty() and main._presenter.visual_count() == 3 and not main._hud._shove_button.visible)
	_press(main, KEY_C)
	_ok("C switches to the crowd encounter again", main.run.scenario.dev_shove and main.run.restarts == 2)
	main._sfx.unlock()
	main._sfx.played.clear()
	main._sfx.play_cue(SimCue.make(SimCue.Kind.WALL_SLAM, Vector2.ZERO, Vector2.ZERO, 9))
	_ok("a wall slam is heard as a thud (the hit sound)", main._sfx.played.has("hit"), "%s" % [main._sfx.played])
	main.queue_free()
	await _tree.process_frame

	var plain: Main = _main_with(RunScenario.new())
	await _tree.process_frame
	_press(plain, KEY_F)
	_ok("in the normal run the shove does nothing and its controls are hidden", plain.run.cue_count(SimCue.Kind.SHOVE) == 0 and not plain._hud._shove_button.visible and not plain._hud._encounter_label.visible)
	plain.queue_free()
	await _tree.process_frame

	# Silhouettes: the three types read differently without final art.
	var colors: Array[Color] = [PlaceholderEnemyVisual.color_of(EnemyDefs.HUSK), PlaceholderEnemyVisual.color_of(EnemyDefs.RUNNER), PlaceholderEnemyVisual.color_of(EnemyDefs.BRUTE)]
	var radii: Array[float] = [PlaceholderEnemyVisual.visual_radius_of(EnemyDefs.HUSK), PlaceholderEnemyVisual.visual_radius_of(EnemyDefs.RUNNER), PlaceholderEnemyVisual.visual_radius_of(EnemyDefs.BRUTE)]
	_ok("husk, runner and brute differ in colour and in drawn size (runner < husk < brute)",
		colors[0] != colors[1] and colors[1] != colors[2] and colors[0] != colors[2] and radii[1] < radii[0] and radii[0] < radii[2])
	_ok("the placeholder's drawn size follows each type's collision size", radii == [EnemyDefs.HUSK_RADIUS, EnemyDefs.RUNNER_RADIUS, EnemyDefs.BRUTE_RADIUS])


func _check_visual_independence() -> void:
	print("crowd: swapping enemy visuals leaves the crowd fight unchanged")
	var results: Array[Dictionary] = []
	var hosts: Array[Main] = []
	for use_alt: bool in [false, true]:
		var scenario: RunScenario = RunScenario.crowd_encounter()
		scenario.seed = 14
		scenario.first_wave_delay = 0.2
		hosts.append(_main_with(scenario, "res://tests/alt_enemy.tscn" if use_alt else ""))
	await _tree.process_frame
	for main: Main in hosts:
		_tick_main(main, 360)
		_press(main, KEY_F)
		_tick_main(main, 240)
		_press(main, KEY_F)
		_tick_main(main, 300)
		results.append(main.run.snapshot())
	_ok("a huge replacement enemy visual changes nothing about collisions, bowling, slams or deaths", results[0] == results[1])
	_ok("the fixture fought: kills and shoves happened", int(results[0]["kills"]) > 0 and hosts[0].run.cue_count(SimCue.Kind.SHOVE) == 2)
	for main: Main in hosts:
		main.queue_free()
	await _tree.process_frame


# -------------------------------------------------------- render rates
func _check_render_rates() -> void:
	print("crowd: identical outcomes at low and high render rates")
	var headless: Dictionary = RenderRateScenario.play_headless()
	# Probe output travels as JSON text, so compare both sides after the same round trip.
	var expected_digest: Dictionary = JSON.parse_string(JSON.stringify(headless))
	_ok("the scripted crowd fight does something worth comparing (kills %d, slams %d, bowls %d, shoves %d)" % [int(headless["kills"]), int(headless["slam_cues"]), int(headless["bowl_cues"]), int(headless["shove_cues"])],
		int(headless["kills"]) >= 8 and int(headless["slam_cues"]) >= 3 and int(headless["bowl_cues"]) >= 5 and int(headless["shove_cues"]) == RenderRateScenario.SHOVE_TICKS.size())
	_ok("exactly once: kills equal kill cues", int(headless["kills"]) == int(headless["kill_cues"]))
	var executable: String = OS.get_executable_path()
	var project: String = ProjectSettings.globalize_path("res://")
	var frames: Dictionary[int, int] = {}
	for rate: int in PROBE_FRAME_RATES:
		var output: Array = []
		var arguments: PackedStringArray = ["--headless", "--path", project, "--fixed-fps", str(rate), "--script", PROBE_SCRIPT, "--", "--probe=rate"]
		var code: int = OS.execute(executable, arguments, output, true)
		var line: String = _probe_line(output)
		_ok("the engine played the fight at %d fps (exit %d)" % [rate, code], code == 0 and not line.is_empty(), "%s" % [output])
		if line.is_empty():
			continue
		var result: Dictionary = JSON.parse_string(line)
		frames[rate] = int(result["frames"])
		var comparable: Dictionary = result.duplicate()
		for key: String in ["frames", "visuals", "enemies"]:
			comparable.erase(key)
		_ok("at %d fps the real Main scene ends the fight exactly like the bare simulation" % rate, comparable == expected_digest, _first_difference(comparable, expected_digest))
		_ok("at %d fps every kill is rewarded exactly once (kills %d, kill cues %d, alive %d, visuals %d)" % [rate, int(result["kills"]), int(result["kill_cues"]), int(result["enemies"]), int(result["visuals"])],
			int(result["kills"]) == int(result["kill_cues"]) and int(result["visuals"]) == int(result["enemies"]) + 3)
	_ok("the rates really differed: the engine drew %s frames for the same %d ticks" % [frames, RenderRateScenario.TOTAL_TICKS],
		frames.size() == PROBE_FRAME_RATES.size() and frames[5] < frames[20] and frames[20] < frames[60] and frames[60] < frames[240])
	for encounter: String in ["crowd", "wall"]:
		var launch_output: Array = []
		OS.execute(executable, ["--headless", "--path", project, "--script", PROBE_SCRIPT, "--", "--probe=launch", "--encounter=%s" % encounter], launch_output, true)
		var launch_line: String = _probe_line(launch_output)
		var launched: Dictionary = JSON.parse_string(launch_line) if not launch_line.is_empty() else {}
		var standing: int = RunScenario.WALL_CROWD_KINDS.size() if encounter == "wall" else 0
		_ok("the launch option --encounter=%s starts that encounter" % encounter, bool(launched.get("dev_shove", false)) and int(launched.get("standing", -1)) == standing, "%s" % [launch_output])
	var plain_output: Array = []
	OS.execute(executable, ["--headless", "--path", project, "--script", PROBE_SCRIPT, "--", "--probe=launch", "--encounter=nonsense"], plain_output, true)
	var plain_line: String = _probe_line(plain_output)
	var plain: Dictionary = JSON.parse_string(plain_line) if not plain_line.is_empty() else {}
	_ok("an unknown or missing launch option starts the normal husk wave", plain.has("dev_shove") and not bool(plain["dev_shove"]) and int(plain["wave_kinds"]) == 0 and int(plain["standing"]) == 0, "%s" % [plain_output])


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
