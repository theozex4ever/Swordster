class_name ViperFlurryChecks
extends RefCounted
## Game-run behavioural checks for the Fang ultimate, Viper Flurry, and the per-slot
## ultimate commands (issue #12). Like the earlier slices' checks, every check drives the
## real `GameRun` through `GameCommand`s (or the real Main scene with real key events),
## advances fixed ticks and observes outcomes. Comparison values come from the Python
## prototype's captured reference (res://tests/reference/viper_flurry.json, recorded by
## tools/reference/capture_viper_flurry.py), which also carries each case's fixture
## (`setup`), so no starting number is copied into this file. Tolerances and deliberate
## exceptions: docs/reference/viper-flurry.md.

const REFERENCE_PATH: String = "res://tests/reference/viper_flurry.json"
const PROBE_SCRIPT: String = "res://tests/frame_rate_probe.gd"

## Same-algorithm comparisons at the prototype's 60 FPS step.
const POSITION_TOL: float = 0.05  # px
const VELOCITY_TOL: float = 0.05  # px/s
const SCALAR_TOL: float = 0.002  # timers, cooldowns, shake, stun
const TICK_TOL: int = 1
const PROBE_FRAME_RATES: Array[int] = [5, 20, 60, 240]
## The arena centre, where the player starts (the capture's PLAYER).
const CENTER: Vector2 = Vector2(1300.0, 900.0)
## An automatic-attack cooldown that never ends within a case (the capture's PARKED_CD).
const PARKED: float = 99.0

var _check: Callable
var _tree: SceneTree
var _ref: Dictionary = {}


func _init(check_function: Callable, tree: SceneTree) -> void:
	_check = check_function
	_tree = tree


func run_all() -> void:
	var file: FileAccess = FileAccess.open(REFERENCE_PATH, FileAccess.READ)
	if file == null:
		_ok("flurry reference file loads", false, REFERENCE_PATH)
		return
	_ref = JSON.parse_string(file.get_as_text())
	_ok("flurry reference file parses", not _ref.is_empty())
	_check_reference_scope()
	_check_definitions()
	_check_single_victim()
	_check_range_clamp()
	_check_area_and_empty()
	_check_target_replacement()
	_check_removed_while_alive()
	_check_recharge()
	_check_rejections()
	_check_keys_and_r()
	_check_pause_and_death()
	_check_time_scales()
	_check_projectiles_and_others()
	_check_exactly_once()
	_check_touch_aim()
	_check_restart_clears()
	await _check_main_scene()
	await _check_hud_layout()
	await _check_visual_independence()
	await _check_render_rates()


# --------------------------------------------------------------- helpers
func _ok(label: String, condition: bool, detail: String = "") -> void:
	_check.call(label, condition, detail)


func _near(a: float, b: float, tolerance: float) -> bool:
	return absf(a - b) <= tolerance


func _point(values: Array) -> Vector2:
	return Vector2(float(values[0]), float(values[1]))


func _steps(run: GameRun, count: int) -> void:
	for i: int in count:
		run.step()


## Three Fang swords (Q, E, R) with no automatic attacks, enemies standing as the
## reference's `setup` says: no waves, no spawns, only what the case puts in the arena.
func _arena(setups: Array, rarities: Array[int] = [0, 0, 0], crit_chance: float = 0.0) -> RunScenario:
	var scenario: RunScenario = RunScenario.new().without_conditions()
	scenario.seed = 41
	scenario.waves_enabled = false
	scenario.crit_chance = crit_chance
	var specs: Array[SwordSpec] = []
	var elements: Array[StringName] = [&"poison", &"ice", &"fire"]
	for i: int in rarities.size():
		specs.append(SwordSpec.make(&"fang", rarities[i], elements[i]))
	scenario.loadout = specs
	var cooldowns: Array[float] = []
	for i: int in rarities.size():
		cooldowns.append(PARKED)
	scenario.sword_start_cooldowns = cooldowns
	var placements: Array[EnemyPlacement] = []
	for setup: Variant in setups:
		var entry: Dictionary = setup as Dictionary
		var placement: EnemyPlacement = EnemyPlacement.make(EnemyDefs.HUSK, Vector2(float(entry["x"]), float(entry["y"])))
		placement.speed_scale = float(entry["speed_scale"])
		placement.hp = float(entry["hp"])
		placements.append(placement)
	scenario.initial_enemies = placements
	return scenario


func _run_of(setups: Array, rarities: Array[int] = [0, 0, 0], crit_chance: float = 0.0) -> GameRun:
	return GameRun.new(_arena(setups, rarities, crit_chance))


func _phase_name(phase: int) -> String:
	match phase:
		SwordState.Phase.ULTIMATE:
			return "ult"
		SwordState.Phase.RECOVER:
			return "recover"
		SwordState.Phase.IDLE:
			return "idle"
		SwordState.Phase.WINDUP:
			return "windup"
		_:
			return "strike"


func _states(run: GameRun) -> Array[String]:
	var names: Array[String] = []
	for sword: SwordState in run.swords:
		names.append(_phase_name(sword.phase))
	return names


func _same_strings(actual: Array[String], expected: Array) -> bool:
	if actual.size() != expected.size():
		return false
	for i: int in actual.size():
		if actual[i] != String(expected[i]):
			return false
	return true


## How many dart hits of 8 (the Common flurry hit) an enemy has taken.
func _hits(enemy: EnemyState, full_hp: float, damage: float = 8.0) -> float:
	return snappedf((full_hp - enemy.hp) / damage, 0.001)


# ------------------------------------------------------------- reference
func _check_reference_scope() -> void:
	print("flurry: the reference was captured with out-of-scope mechanics disabled")
	var scope: Dictionary = _ref["fixture_scope"]
	_ok("the capture ran with elemental conditions (afflict) disabled (issue #11)", bool(scope["afflict_disabled"]))
	_ok("no enemy in the capture was armed (arming and drops are issue #17)", int(scope["armed_enemies"]) == 0)
	_ok("the capture fielded only husks", scope["kinds"] == ["husk"])
	_ok("only Fang swords took part and Converge was not used (issue #16)", scope["swords_used"] == ["fang"] and not bool(scope["converge_used"]))
	_ok("the capture ran no waves (issue #18) and parked every automatic attack", not bool(scope["waves_enabled"]) and bool(scope["auto_attack_parked"]))


func _check_definitions() -> void:
	print("flurry: constants and recharge against the prototype")
	var table: Dictionary = _ref["table"]
	var inline: Dictionary = table["inline"]
	_ok("the ultimate is named Viper Flurry", SwordDefs.ultimate_name(SwordDefs.FANG) == String(table["name"]))
	_ok("base recharge %.1f s, range %.0f px and radius %.0f px" % [SwordDefs.ultimate_cooldown(SwordDefs.FANG), SwordDefs.ultimate_range(SwordDefs.FANG), SwordDefs.FANG_ULT_RADIUS],
		SwordDefs.ultimate_cooldown(SwordDefs.FANG) == float(table["cd"]) and SwordDefs.ultimate_range(SwordDefs.FANG) == float(table["range"]) and SwordDefs.FANG_ULT_RADIUS == float(table["radius"]))
	_ok("it is a landing ultimate, not a skill shot", SwordDefs.ultimate_is_shot(SwordDefs.FANG) == bool(table["shot"]))
	_ok("duration, cadence, damage factor, knock and shake", SwordDefs.FANG_ULT_DURATION == float(inline["duration"]) and SwordDefs.FANG_ULT_CADENCE == float(inline["cadence"]) and SwordDefs.FANG_ULT_DAMAGE_FACTOR == float(inline["damage_factor"]) and SwordDefs.FANG_ULT_KNOCK == float(inline["knock"]) and SwordDefs.FANG_ULT_SHAKE == float(inline["shake"]))
	_ok("approach rate, standoff, wander bounds, recovery time and speed, heavy flash", SwordDefs.FANG_ULT_APPROACH_RATE == float(inline["approach_rate"]) and SwordDefs.FANG_ULT_STANDOFF == float(inline["standoff"]) and SwordDefs.FANG_ULT_WANDER_MIN == float(inline["wander_min"]) and SwordDefs.FANG_ULT_WANDER_FRACTION == float(inline["wander_max_factor"]) and SwordDefs.FANG_ULT_RECOVER_TIME == float(inline["recover_time"]) and SwordDefs.FANG_ULT_RECOVER_SPEED == float(inline["recover_speed"]) and SwordDefs.HEAVY_HIT_FLASH == float(inline["heavy_flash"]))
	var run: GameRun = _run_of([], [0, 1, 2])
	for rarity: int in 3:
		var sword: SwordState = run.swords[rarity]
		_ok("rarity %d: the recharge is %.2f s (base x the rarity's cooldown factor) and the flurry hits for %.2f" % [rarity, sword.ultimate_cooldown, sword.damage * SwordDefs.FANG_ULT_DAMAGE_FACTOR],
			_near(sword.ultimate_cooldown, float((table["ult_max_by_rarity"] as Array)[rarity]), 0.0001) and _near(sword.damage, float((table["damage_by_rarity"] as Array)[rarity]), 0.0001))
	_ok("a new run starts with every ultimate ready", run.swords.all(func(sword: SwordState) -> bool: return sword.ultimate_ready() and sword.ultimate_cooldown_left == 0.0))


# ------------------------------------------------------- one forced victim
func _check_single_victim() -> void:
	print("flurry: the blink, the darts, the damage and the recovery against the prototype")
	for label: String in ["common", "common_crit", "rare", "mythic"]:
		var case: Dictionary = _ref["single_victim"][label]
		var setup: Dictionary = case["setup"]
		var crit: bool = bool(setup["crit"])
		var rarity: int = int(setup["rarity"])
		var run: GameRun = _run_of(setup["enemies"], [rarity, 0, 0], 1.0 if crit else 0.0)
		var sword: SwordState = run.swords[0]
		var husk: EnemyState = run.enemies[0]
		var full_hp: float = husk.hp
		run.apply(GameCommand.ultimate(0, _point(setup["point"])))
		var start: Dictionary = case["at_start"]
		_ok("%s: the command blinks the sword onto the point and starts the recharge and the clock" % label,
			sword.phase == SwordState.Phase.ULTIMATE and _near(sword.position.x, float(start["x"]), POSITION_TOL) and _near(sword.position.y, float(start["y"]), POSITION_TOL) and _near(sword.ultimate_cooldown_left, float(start["ult_cd"]), SCALAR_TOL) and _near(sword.ultimate_time_left, float(start["ult_t"]), SCALAR_TOL))
		var hits: Array[Dictionary] = []
		var transitions: Array[Dictionary] = []
		var traces: Dictionary = {}
		var phase_before: int = sword.phase
		var hp_before: float = husk.hp
		for step: int in range(1, 130):
			run.step()
			if husk.hp < hp_before:
				hits.append({"tick": step, "dealt": hp_before - husk.hp, "vx": husk.velocity.x, "vy": husk.velocity.y, "stun": husk.stun, "flash": husk.flash, "hitstop": run.hitstop, "trauma": run.trauma})
				hp_before = husk.hp
			if sword.phase != phase_before:
				transitions.append({"tick": step, "to": _phase_name(sword.phase), "ult_cd": sword.ultimate_cooldown_left})
				phase_before = sword.phase
			if (case["trace"] as Dictionary).has(str(step)):
				traces[step] = {"state": _phase_name(sword.phase), "x": sword.position.x, "y": sword.position.y, "ult_cd": sword.ultimate_cooldown_left, "ult_t": sword.ultimate_time_left, "vx": sword.velocity.x, "vy": sword.velocity.y, "ang": sword.angle, "hx": husk.position.x, "hy": husk.position.y}
		var expected_hits: Array = case["hits"]
		var hits_ok: bool = hits.size() == expected_hits.size()
		var detail: String = "%d darts vs %d" % [hits.size(), expected_hits.size()]
		if hits_ok:
			for i: int in hits.size():
				var mine: Dictionary = hits[i]
				var want: Dictionary = expected_hits[i]
				var good: bool = absi(int(mine["tick"]) - int(want["tick"])) <= TICK_TOL and float(mine["dealt"]) == float(want["dealt"]) \
					and _near(float(mine["vx"]), float(want["vx"]), VELOCITY_TOL) and _near(float(mine["vy"]), float(want["vy"]), VELOCITY_TOL) \
					and _near(float(mine["stun"]), float(want["stun"]), SCALAR_TOL) and _near(float(mine["flash"]), float(want["flash"]), SCALAR_TOL) \
					and _near(float(mine["hitstop"]), float(want["hitstop"]), SCALAR_TOL) and _near(float(mine["trauma"]), float(want["trauma"]), SCALAR_TOL)
				if not good:
					hits_ok = false
					detail = "dart %d: %s vs %s" % [i, mine, want]
					break
		_ok("%s: %d darts, five ticks apart, each at the reference tick with its damage %s, knockback, stun, flash, no hitstop and 0.05 shake" % [label, expected_hits.size(), (expected_hits[0] as Dictionary)["dealt"]], hits_ok, detail)
		var phases_ok: bool = transitions.size() == (case["transitions"] as Array).size()
		for i: int in mini(transitions.size(), (case["transitions"] as Array).size()):
			var want_transition: Dictionary = (case["transitions"] as Array)[i]
			phases_ok = phases_ok and String(transitions[i]["to"]) == String(want_transition["to"]) and absi(int(transitions[i]["tick"]) - int(want_transition["tick"])) <= TICK_TOL and _near(float(transitions[i]["ult_cd"]), float(want_transition["ult_cd"]), SCALAR_TOL)
		_ok("%s: the flurry ends after 75 ticks into a 0.3 s recovery and then idles, the recharge still running" % label, phases_ok, "%s vs %s" % [transitions, case["transitions"]])
		var trace_ok: bool = true
		var trace_detail: String = ""
		for key: String in case["trace"]:
			var want_trace: Dictionary = case["trace"][key]
			var step_index: int = int(key)
			if not traces.has(step_index):
				trace_ok = false
				trace_detail = "no sample at tick %s" % key
				break
			var got: Dictionary = traces[step_index]
			if crit and step_index > 65:
				# The crit knockback carries the husk out of the area; the sword then wanders at random.
				continue
			var good_trace: bool = String(got["state"]) == String(want_trace["state"]) and _near(float(got["ult_cd"]), float(want_trace["ult_cd"]), SCALAR_TOL) and _near(float(got["hx"]), float(want_trace["husk_x"]), POSITION_TOL) and _near(float(got["hy"]), float(want_trace["husk_y"]), POSITION_TOL)
			if step_index <= 75:
				good_trace = good_trace and _near(float(got["x"]), float(want_trace["x"]), POSITION_TOL) and _near(float(got["y"]), float(want_trace["y"]), POSITION_TOL) and _near(float(got["ult_t"]), float(want_trace["ult_t"]), SCALAR_TOL) and _near(float(got["ang"]), float(want_trace["ang"]), 0.002)
			if step_index <= 74:
				good_trace = good_trace and _near(float(got["vx"]), float(want_trace["vx"]), 0.5) and _near(float(got["vy"]), float(want_trace["vy"]), 0.5)
			if not good_trace:
				trace_ok = false
				trace_detail = "tick %s: %s vs %s" % [key, got, want_trace]
				break
		_ok("%s: the sword's position, heading, velocity, timer and recharge match the prototype on %d sampled ticks" % [label, (case["trace"] as Dictionary).size()], trace_ok, trace_detail)
		_ok("%s: health left %.1f and kills %d" % [label, husk.hp, run.kills], _near(husk.hp, float(case["hp_end"]), SCALAR_TOL) and run.kills == int(case["kills"]))


# ----------------------------------------------------------------- range
func _check_range_clamp() -> void:
	print("flurry: the aim point is clamped to the 420 px range")
	var cases: Dictionary = _ref["range_clamp"]
	for label: String in ["inside", "on_the_limit", "just_beyond", "far_east", "far_diagonal", "on_the_player", "far_south_west"]:
		var case: Dictionary = cases[label]
		var run: GameRun = _run_of([])
		var result: GameRun.UltimateResult = run.try_ultimate(1, _point(case["point"]))
		var sword: SwordState = run.swords[1]
		_ok("%s: the sword lands %.1f px from the player at %s" % [label, float(case["distance"]), case["blink"]],
			result == GameRun.UltimateResult.STARTED and sword.phase == SwordState.Phase.ULTIMATE and _near(sword.ultimate_point.x, float((case["blink"] as Array)[0]), POSITION_TOL) and _near(sword.ultimate_point.y, float((case["blink"] as Array)[1]), POSITION_TOL) and sword.position == sword.ultimate_point and _near((sword.position - run.position).length(), float(case["distance"]), 0.01) and _near(sword.ultimate_cooldown_left, float(case["ult_cd"]), SCALAR_TOL))
	var moved: Dictionary = cases["from_moved_player"]
	var run_moved: GameRun = _run_of([])
	run_moved.position = _point(moved["player"])
	run_moved.try_ultimate(0, _point(moved["point"]))
	_ok("the range is measured from the player, wherever it stands (%s)" % [moved["blink"]], run_moved.swords[0].ultimate_point.distance_to(_point(moved["blink"])) <= POSITION_TOL)
	var landed: GameRun = _run_of([])
	landed.try_ultimate(2, CENTER + Vector2(0.0, 300.0))
	_ok("the other slots land the same way and only that slot's sword moves", landed.swords[2].phase == SwordState.Phase.ULTIMATE and landed.swords[0].phase == SwordState.Phase.IDLE and landed.swords[1].phase == SwordState.Phase.IDLE)


# ------------------------------------------------------- the area, empty
func _check_area_and_empty() -> void:
	print("flurry: who is inside the 150 px area, and an empty area")
	for label: String in ["just_inside", "just_outside", "centre"]:
		var case: Dictionary = _ref["area_and_empty"][label]
		var setup: Dictionary = case["setup"]
		var run: GameRun = _run_of(setup["enemies"])
		var husk: EnemyState = run.enemies[0]
		run.apply(GameCommand.ultimate(2, _point(setup["point"])))
		var first_hit: int = -1
		var hp_before: float = husk.hp
		for step: int in range(1, 100):
			run.step()
			if husk.hp < hp_before and first_hit < 0:
				first_hit = step
			hp_before = husk.hp
		var want_first: int = -1 if case["first_hit"] == null else int(case["first_hit"])
		_ok("%s: an enemy %.0f px from the point is %s (first dart tick %d, %.0f darts)" % [label, float(case["offset"]), "struck" if want_first > 0 else "never targeted", first_hit, float(case["hits"])],
			(first_hit == want_first or (first_hit > 0 and want_first > 0 and absi(first_hit - want_first) <= TICK_TOL)) and _near(_hits(husk, 500.0), float(case["hits"]), 0.001))
	var empty: Dictionary = _ref["area_and_empty"]["empty_area"]
	var run_empty: GameRun = _run_of([])
	var sword: SwordState = run_empty.swords[0]
	run_empty.apply(GameCommand.ultimate(0, _point(empty["setup"]["point"])))
	var goal_ticks: Array[int] = []
	var last_goal: Vector2 = sword.ultimate_goal
	var min_goal: float = INF
	var max_goal: float = 0.0
	var max_sword: float = 0.0
	for step: int in range(1, 90):
		run_empty.step()
		if sword.phase == SwordState.Phase.ULTIMATE:
			if (sword.ultimate_goal - last_goal).length() > 1e-9:
				goal_ticks.append(step)
				last_goal = sword.ultimate_goal
				var goal_distance: float = (sword.ultimate_goal - sword.ultimate_point).length()
				min_goal = minf(min_goal, goal_distance)
				max_goal = maxf(max_goal, goal_distance)
			max_sword = maxf(max_sword, (sword.position - sword.ultimate_point).length())
	_ok("an empty area is not a failure: the sword picks a new wander point every five ticks (%d of them, as in the prototype)" % goal_ticks.size(), goal_ticks.size() == int(empty["goals"]) and goal_ticks == _int_array(empty["goal_ticks"]), "%s" % [goal_ticks])
	_ok("the wander points lie %.0f-%.0f px from the centre (%.1f..%.1f seen) and the sword stays inside the area" % [float(empty["wander_min"]), float(empty["wander_max"]), min_goal, max_goal],
		min_goal >= float(empty["wander_min"]) - 0.001 and max_goal <= float(empty["wander_max"]) + 0.001 and max_sword <= float(empty["wander_max"]))
	_ok("an empty flurry hits nothing, kills nothing, and recovers on time", run_empty.cue_count(SimCue.Kind.ENEMY_HIT) == 0 and run_empty.kills == 0 and _phase_name(sword.phase) == String(empty["final_state"]))


func _int_array(values: Array) -> Array[int]:
	var converted: Array[int] = []
	for value: Variant in values:
		converted.append(int(value))
	return converted


# ------------------------------------------------------ choosing victims
func _check_target_replacement() -> void:
	print("flurry: dart targets are replaced, never repeated, and dead or removed ones are skipped")
	var cases: Dictionary = _ref["target_replacement"]
	var firsts: Dictionary = {}
	for seed_value: int in range(1, 6):
		var case: Dictionary = cases["two_enemies_seed%d" % seed_value]
		var scenario: RunScenario = _arena(case["setup"])
		scenario.seed = seed_value
		var run: GameRun = GameRun.new(scenario)
		var a: EnemyState = run.enemies[0]
		var b: EnemyState = run.enemies[1]
		run.apply(GameCommand.ultimate(0, CENTER + Vector2(260.0, 0.0)))
		var order: Array[String] = []
		var ticks: Array[int] = []
		var hp_a: float = a.hp
		var hp_b: float = b.hp
		for step: int in range(1, 100):
			run.step()
			if a.hp < hp_a:
				order.append("a")
				ticks.append(step)
				hp_a = a.hp
			if b.hp < hp_b:
				order.append("b")
				ticks.append(step)
				hp_b = b.hp
		var alternates: bool = true
		for i: int in range(order.size() - 1):
			alternates = alternates and order[i] != order[i + 1]
		firsts[order[0] if not order.is_empty() else "none"] = true
		_ok("seed %d: with two enemies in the area the darts strictly alternate (%d darts) at the reference ticks" % [seed_value, order.size()],
			alternates and bool(case["alternates"]) and order.size() == (case["order"] as Array).size() and ticks == _int_array(case["ticks"]), "%s %s" % [order, ticks])
	_ok("the first victim is a random pick: both enemies were chosen first across the seeds", firsts.size() == 2, "%s" % [firsts.keys()])
	var single: Dictionary = cases["one_enemy_repeats"]
	var run_single: GameRun = _run_of(single["setup"])
	var only: EnemyState = run_single.enemies[0]
	run_single.apply(GameCommand.ultimate(0, CENTER + Vector2(260.0, 0.0)))
	_steps(run_single, 99)
	_ok("with one enemy in the area it is struck again and again (%d darts)" % int(single["hits"]), _hits(only, 500.0) == float(single["hits"]))
	var dies: Dictionary = cases["target_dies"]
	var run_dies: GameRun = _run_of(dies["setup"])
	var doomed: EnemyState = run_dies.enemies[0]
	var spared: EnemyState = run_dies.enemies[1]
	var sword_dies: SwordState = run_dies.swords[0]
	run_dies.apply(GameCommand.ultimate(0, CENTER + Vector2(260.0, 0.0)))
	var kill_tick: int = -1
	for step: int in range(1, 100):
		run_dies.step()
		if doomed.dead and kill_tick < 0:
			kill_tick = step
	_ok("a victim that dies on its dart is killed once (tick %d, kills %d, chain %d) and the enemy outside the area is never touched" % [kill_tick, run_dies.kills, run_dies.combo],
		absi(kill_tick - int(dies["kill_tick"])) <= TICK_TOL and run_dies.kills == int(dies["kills"]) and run_dies.combo == int(dies["combo"]) and spared.hp == float(dies["far_hp"]) and run_dies.enemies.size() == int(dies["enemies_left"]))
	_ok("with nobody left the flurry runs out, the sword drops its victim and idles", sword_dies.ultimate_victim == null and _phase_name(sword_dies.phase) == String(dies["state_after"]))
	var other: Dictionary = cases["killed_by_something_else"]
	var run_other: GameRun = _run_of(other["setup"])
	var one: EnemyState = run_other.enemies[0]
	var two: EnemyState = run_other.enemies[1]
	var sword_other: SwordState = run_other.swords[0]
	run_other.apply(GameCommand.ultimate(0, CENTER + Vector2(260.0, 0.0)))
	run_other.step()
	var chosen: EnemyState = sword_other.ultimate_victim
	if chosen == null:
		_ok("the flurry chose a first victim among the two enemies in its area", false)
		return
	var replacement: EnemyState = two if chosen == one else one
	run_other.kill(chosen, Vector2.RIGHT)
	var replacement_hp: float = replacement.hp
	_steps(run_other, 4)
	var dead_took_damage: bool = chosen.hp < 500.0
	var trauma_before_due: float = run_other.trauma
	run_other.step()
	var quiet_for_the_dead: bool = run_other.trauma <= trauma_before_due
	var replaced: bool = sword_other.ultimate_victim == replacement
	var hit_on_due_tick: bool = replacement.hp < replacement_hp
	_steps(run_other, 5)
	_ok("a victim killed by something else before its dart takes no hit and is not killed twice (kills %d)" % run_other.kills,
		not dead_took_damage == not bool(other["dead_victim_took_damage"]) and run_other.kills == int(other["kills"]) and chosen.hp == float(other["victim_hp_after"]))
	_ok("a dead victim's dart makes no shake either: only a real hit shakes the screen", quiet_for_the_dead == bool(other["no_shake_for_a_dead_victim"]) and quiet_for_the_dead)
	var lone: Dictionary = cases["killed_only_enemy"]
	var run_lone: GameRun = _run_of(lone["setup"])
	var sword_lone: SwordState = run_lone.swords[0]
	run_lone.apply(GameCommand.ultimate(0, CENTER + Vector2(260.0, 0.0)))
	_steps(run_lone, 5)
	if sword_lone.ultimate_victim != null:
		run_lone.kill(sword_lone.ultimate_victim, Vector2.RIGHT)
	_steps(run_lone, 1)
	_ok("when the only enemy in the area is killed by something else on the tick its dart is due nobody is chosen next (the corpse is not a candidate) and the sword wanders on", sword_lone.ultimate_victim == null and bool(lone["victim_none"]) and run_lone.kills == int(lone["kills"]) and _phase_name(sword_lone.phase) == String(lone["state"]) and run_lone.trauma <= float(lone["shake_after"]) + SCALAR_TOL)
	_ok("the dart's turn passes without a hit and the other enemy becomes the victim and is struck one beat later", replaced == bool(other["replaced_by_the_other"]) and hit_on_due_tick == bool(other["other_hit_on_due_tick"]) and _hits(replacement, 500.0) == float(other["other_hits_after_replacement"]))
	# A victim that left the run (dead and removed at the end of its tick) between darts.
	var run_removed: GameRun = _run_of(other["setup"])
	var sword_removed: SwordState = run_removed.swords[0]
	var bystander: EnemyState = run_removed.enemies[0]
	var bystander_b: EnemyState = run_removed.enemies[1]
	run_removed.apply(GameCommand.ultimate(0, CENTER + Vector2(260.0, 0.0)))
	run_removed.step()
	var gone: EnemyState = sword_removed.ultimate_victim
	if gone == null:
		_ok("the flurry chose a victim to remove", false)
		return
	run_removed.hit_enemy(gone, 9999.0, Vector2.RIGHT, 0.0, sword_removed)
	_steps(run_removed, 4)  # the hit's own hitstop first, then the dead enemy leaves the run
	_ok("a victim already removed from the run (killed and cleared) is simply skipped: still one kill, the run does not error", run_removed.kills == 1 and not run_removed.enemies.has(gone) and sword_removed.phase == SwordState.Phase.ULTIMATE)
	_steps(run_removed, 12)
	var survivor: EnemyState = bystander_b if gone == bystander else bystander
	_ok("and the remaining enemy takes the rest of the darts (%.0f)" % _hits(survivor, 500.0), _hits(survivor, 500.0) >= 1.0)


# ------------------------------------------- removed while alive (hardening)
## Deliberate deviation (docs/reference/viper-flurry.md, exception 10): the prototype
## only asks `dead`, because an enemy leaves the run only once dead, so this state is
## unreachable in play. A reference an enemy-holding sword keeps across ticks is
## dropped when its enemy is no longer in the run even though it is alive.
func _check_removed_while_alive() -> void:
	print("flurry: an enemy removed from the run while alive is never struck, killed or rewarded")
	var aim: Vector2 = CENTER + Vector2(260.0, 0.0)
	var husk_setup: Array = [_ref["target_replacement"]["target_dies"]["setup"][0]]  # one stationary 5 hp husk
	var run: GameRun = _run_of(husk_setup)
	var sword: SwordState = run.swords[0]
	var victim: EnemyState = run.enemies[0]
	run.apply(GameCommand.ultimate(0, aim))
	run.step()
	var chosen: bool = sword.ultimate_victim == victim
	run.enemies.erase(victim)
	_steps(run, 5)
	_ok("flurry victim removed while alive: no damage (hp %.0f), no kill (%d), no motes (%d), no hit cue (%d)" % [victim.hp, run.kills, run.motes.size(), run.cue_count(SimCue.Kind.ENEMY_HIT)],
		chosen and victim.hp == 5.0 and not victim.dead and run.kills == 0 and run.motes.is_empty() and run.cue_count(SimCue.Kind.ENEMY_HIT) == 0 and run.cue_count(SimCue.Kind.ENEMY_KILLED) == 0)
	_ok("and with nobody left the flurry drops its victim and goes on wandering", sword.ultimate_victim == null and sword.phase == SwordState.Phase.ULTIMATE)
	_steps(run, 120)
	_ok("and it still ends and idles normally, with nothing struck", sword.phase == SwordState.Phase.IDLE and victim.hp == 5.0 and run.cue_count(SimCue.Kind.ENEMY_HIT) == 0)

	var other: Dictionary = _ref["target_replacement"]["killed_by_something_else"]
	var run_two: GameRun = _run_of(other["setup"])
	var sword_two: SwordState = run_two.swords[0]
	run_two.apply(GameCommand.ultimate(0, aim))
	run_two.step()
	var gone: EnemyState = sword_two.ultimate_victim
	if gone == null:
		_ok("the flurry chose a victim to remove (two enemies)", false)
		return
	var stays: EnemyState = run_two.enemies[1] if run_two.enemies[0] == gone else run_two.enemies[0]
	run_two.enemies.erase(gone)
	_steps(run_two, 4)
	var untouched: bool = gone.hp == 500.0 and not gone.dead and run_two.kills == 0 and run_two.cue_count(SimCue.Kind.ENEMY_HIT) == 0
	run_two.step()  # the dart's tick: nothing to strike, the other enemy is chosen
	var replaced: bool = sword_two.ultimate_victim == stays
	_steps(run_two, 5)
	_ok("removed while alive among two: untouched, the other is chosen on the due beat (%s) and struck one beat later (hp %.0f)" % [replaced, stays.hp],
		untouched and replaced and stays.hp == 492.0 and gone.hp == 500.0 and run_two.cue_count(SimCue.Kind.ENEMY_HIT) == 1 and run_two.kills == 0)

	# The Fang's automatic attack keeps its target across ticks the same way.
	var scenario: RunScenario = _arena([{"x": CENTER.x + 100.0, "y": CENTER.y, "hp": 500.0, "speed_scale": 0.0}])
	var cooldowns: Array[float] = [0.0, PARKED, PARKED]
	scenario.sword_start_cooldowns = cooldowns
	var run_auto: GameRun = GameRun.new(scenario)
	var fang: SwordState = run_auto.swords[0]
	var husk: EnemyState = run_auto.enemies[0]
	var guard: int = 0
	while fang.phase != SwordState.Phase.WINDUP and guard < 10:
		run_auto.step()
		guard += 1
	var acquired: bool = fang.target == husk
	var aim_before: Vector2 = fang.aim
	run_auto.enemies.erase(husk)
	husk.position += Vector2(0.0, -50.0)  # a stale enemy, no longer simulated
	run_auto.step()
	_ok("an automatic attack's target removed while alive is dropped and its aim stops following it", acquired and fang.target == null and fang.aim == aim_before)
	_steps(run_auto, 30)
	_ok("and the attack ends without ever damaging it", husk.hp == 500.0 and run_auto.cue_count(SimCue.Kind.ENEMY_HIT) == 0 and fang.phase != SwordState.Phase.STRIKE)


# ------------------------------------------------------------ HUD layout
## The window the player gets is not always 1280x720 (a monitor narrower than the base
## width, a maximised window, a phone): with the project's `canvas_items` stretch and
## `expand` aspect the HUD sees a viewport rectangle that is never smaller than the
## 1280x720 base, anchored to the edges of that rectangle. Every visible HUD control
## (the ultimate cards bottom left, Dash/Shove bottom right, Pause/Restart/Dev top
## right, the top-left lines) must lie inside it at each shape, in the same stretch
## settings the project ships.
const HUD_WINDOW_SIZES: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1084, 720), Vector2i(1000, 563), Vector2i(1366, 768), Vector2i(1920, 1080), Vector2i(2560, 1080), Vector2i(800, 1280), Vector2i(1280, 1024)]


func _check_hud_layout() -> void:
	print("flurry: the HUD lies inside the viewport at every window shape")
	_ok("the project stretches the 1280x720 base with canvas_items and expand (what the HUD layout relies on)",
		ProjectSettings.get_setting("display/window/size/viewport_width") == 1280 and ProjectSettings.get_setting("display/window/size/viewport_height") == 720
		and ProjectSettings.get_setting("display/window/stretch/mode") == "canvas_items" and ProjectSettings.get_setting("display/window/stretch/aspect") == "expand")
	for size: Vector2i in HUD_WINDOW_SIZES:
		var window: Window = Window.new()
		window.size = size
		window.content_scale_size = Vector2i(1280, 720)
		window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
		_tree.root.add_child(window)
		var hud: Hud = Hud.new()
		window.add_child(hud)
		var run: GameRun = GameRun.new(RunScenario.crowd_encounter().without_conditions())
		await _tree.process_frame
		hud.show_state(false, false)
		hud.show_run(run)
		await _tree.process_frame
		var visible_rect: Rect2 = window.get_visible_rect()
		var inside: bool = true
		var outside_names: Array[String] = []
		var counted: int = 0
		for control: Control in _visible_hud_controls(hud):
			var rect: Rect2 = control.get_global_rect()
			counted += 1
			if rect.size.x > 0.0 and rect.size.y > 0.0 and not visible_rect.grow(0.5).encloses(rect):
				inside = false
				outside_names.append("%s %s" % [control.name, rect])
		var cards_ready: bool = [0, 1, 2].all(func(slot: int) -> bool: return hud.ultimate_status(slot) == "READY" and hud.ultimate_card_visible(slot))
		_ok("window %s: visible rect %s is at least the 1280x720 base, and all %d visible HUD controls (cards READY: %s) lie inside it" % [size, visible_rect.size, counted, cards_ready],
			visible_rect.size.x >= 1280.0 - 0.5 and visible_rect.size.y >= 720.0 - 0.5 and inside and cards_ready and counted > 30, str(outside_names))
		window.queue_free()
		await _tree.process_frame


## Every visible HUD control that is not a screen-wide backdrop or overlay.
func _visible_hud_controls(node: Node) -> Array[Control]:
	var found: Array[Control] = []
	for child: Node in node.get_children():
		if child is Control:
			var control: Control = child as Control
			if not control.visible:
				continue
			var full: bool = control.anchor_left == 0.0 and control.anchor_top == 0.0 and control.anchor_right == 1.0 and control.anchor_bottom == 1.0
			if not full and not (control is ColorRect and control.get_parent() is Hud):
				found.append(control)
		found.append_array(_visible_hud_controls(child))
	return found


# -------------------------------------------------------------- recharge
func _check_recharge() -> void:
	print("flurry: the recharge")
	for rarity: int in 3:
		var case: Dictionary = _ref["recharge_and_rejections"]["recharge_rarity%d" % rarity]
		var run: GameRun = _run_of([], [rarity, 0, 0])
		var sword: SwordState = run.swords[0]
		run.apply(GameCommand.ultimate(0, CENTER + Vector2(200.0, 0.0)))
		var ready_tick: int = -1
		var at_ticks: Dictionary = {}
		for step: int in range(1, 700):
			run.step()
			if (case["ult_cd_at"] as Dictionary).has(str(step)):
				at_ticks[str(step)] = sword.ultimate_cooldown_left
			if sword.ultimate_cooldown_left <= 0.0 and ready_tick < 0:
				ready_tick = step
		var values_ok: bool = true
		for key: String in case["ult_cd_at"]:
			values_ok = values_ok and _near(float(at_ticks[key]), float((case["ult_cd_at"] as Dictionary)[key]), SCALAR_TOL)
		_ok("rarity %d: recharged after %d ticks (%.2f s from the moment the ultimate starts)" % [rarity, ready_tick, float(case["ult_max"])], absi(ready_tick - int(case["ready_tick"])) <= TICK_TOL and values_ok and sword.ultimate_ready(), "%s" % [at_ticks])
	var run_charge: GameRun = _run_of([])
	var sword_charge: SwordState = run_charge.swords[0]
	run_charge.apply(GameCommand.ultimate(0, CENTER + Vector2(200.0, 0.0)))
	_steps(run_charge, 270)
	_ok("the HUD's charge fraction runs from 0 to 1 over the recharge (%.2f half way)" % sword_charge.ultimate_charge(), _near(sword_charge.ultimate_charge(), 0.5, 0.01) and not sword_charge.ultimate_ready())
	var slots: Dictionary = _ref["recharge_and_rejections"]["slots_independent"]
	var run_slots: GameRun = _run_of([])
	run_slots.apply(GameCommand.ultimate(0, CENTER + Vector2(200.0, 0.0)))
	_steps(run_slots, 120)
	run_slots.apply(GameCommand.ultimate(1, CENTER + Vector2(0.0, 200.0)))
	var cooldowns: Array[float] = []
	for sword: SwordState in run_slots.swords:
		cooldowns.append(sword.ultimate_cooldown_left)
	_ok("each sword slot recharges on its own clock (%s)" % [cooldowns], _same_strings(_states(run_slots), slots["states"]) and _near(cooldowns[0], float((slots["ult_cd"] as Array)[0]), SCALAR_TOL) and _near(cooldowns[1], float((slots["ult_cd"] as Array)[1]), SCALAR_TOL) and cooldowns[2] == 0.0)
	_ok("slot two landed where it was aimed", run_slots.swords[1].ultimate_point.distance_to(_point(slots["blink_e"])) <= POSITION_TOL)
	_steps(run_slots, 480)
	var later: Dictionary = slots["after_480_more_ticks"]
	_ok("480 ticks later slot one is ready again and slot two still has %.0f s left" % float((later["ult_cd"] as Array)[1]),
		_near(run_slots.swords[0].ultimate_cooldown_left, float((later["ult_cd"] as Array)[0]), SCALAR_TOL) and _near(run_slots.swords[1].ultimate_cooldown_left, float((later["ult_cd"] as Array)[1]), SCALAR_TOL) and _same_strings(_states(run_slots), later["states"]))
	_steps(run_slots, 100)
	run_slots.apply(GameCommand.ultimate(0, CENTER + Vector2(200.0, 0.0)))
	_ok("and slot one can be commanded again", _phase_name(run_slots.swords[0].phase) == String(slots["q_again"]))


func _check_rejections() -> void:
	print("flurry: refusals (recharging, running, no sword, dead, paused, repeated input)")
	var cases: Dictionary = _ref["recharge_and_rejections"]
	var point: Vector2 = CENTER + Vector2(200.0, 0.0)
	var run: GameRun = _run_of([])
	var sword: SwordState = run.swords[0]
	run.apply(GameCommand.ultimate(0, point))
	_steps(run, 100)
	run.take_cues()
	var before: Dictionary = {"phase": sword.phase, "cd": sword.ultimate_cooldown_left, "pos": sword.position, "point": sword.ultimate_point}
	var refused: GameRun.UltimateResult = run.try_ultimate(0, CENTER + Vector2(-200.0, 0.0))
	var refusals: Array[SimCue] = run.take_cues()
	var refusal_amount: int = refusals[0].amount if refusals.size() == 1 and refusals[0].kind == SimCue.Kind.ULTIMATE_REFUSED else -1
	_ok("while recharging a command changes nothing and does not reset the recharge (%.3f s left)" % sword.ultimate_cooldown_left,
		refused == GameRun.UltimateResult.RECHARGING and sword.phase == before["phase"] and sword.ultimate_cooldown_left == before["cd"] and sword.position == before["pos"] and sword.ultimate_point == before["point"] and not bool((cases["rejected_while_recharging"] as Dictionary)["state_changed"]) and not bool((cases["rejected_while_recharging"] as Dictionary)["cd_reset"]))
	_ok("the refusal says how many whole seconds remain (%d)" % refusal_amount, refusal_amount == SimMath.py_round(sword.ultimate_cooldown_left) and refusal_amount == 7)
	# Running: even with the recharge forced to zero a second command is refused.
	var active: Dictionary = cases["rejected_while_active"]
	var run_active: GameRun = _run_of([])
	var sword_active: SwordState = run_active.swords[0]
	run_active.apply(GameCommand.ultimate(0, point))
	_steps(run_active, 10)
	sword_active.ultimate_cooldown_left = 0.0
	run_active.take_cues()
	var point_before: Vector2 = sword_active.ultimate_point
	var time_before: float = sword_active.ultimate_time_left
	var active_result: GameRun.UltimateResult = run_active.try_ultimate(0, CENTER + Vector2(-200.0, 0.0))
	_ok("while the flurry is running a second command is refused even with a zero recharge: the area and the clock stay (%.3f s left)" % sword_active.ultimate_time_left,
		active_result == GameRun.UltimateResult.ACTIVE and sword_active.ultimate_point == point_before and sword_active.ultimate_time_left == time_before and _near(time_before, float(active["ult_t"]), SCALAR_TOL) and run_active.take_cues().is_empty())
	_ok("a running ultimate is not 'ready' even at zero recharge", not sword_active.ultimate_ready())
	# No sword in that slot.
	var duo: RunScenario = _arena([])
	duo.loadout = duo.loadout.slice(0, 2)
	var run_duo: GameRun = GameRun.new(duo)
	var duo_result: GameRun.UltimateResult = run_duo.try_ultimate(2, point)
	_ok("a slot with no sword is ignored (R with two swords equipped)", duo_result == GameRun.UltimateResult.NO_SWORD and _same_strings(_states(run_duo), cases["no_third_sword"]["states"]) and run_duo.try_ultimate(-1, point) == GameRun.UltimateResult.NO_SWORD and run_duo.take_cues().is_empty())
	# Dead and paused.
	var run_dead: GameRun = _run_of([])
	run_dead.hurt_player(1000, CENTER + Vector2(50.0, 0.0))
	var dead_result: GameRun.UltimateResult = run_dead.try_ultimate(1, point)
	_ok("a dead player cannot start an ultimate", dead_result == GameRun.UltimateResult.UNAVAILABLE and _same_strings(_states(run_dead), ["idle", "idle", "idle"]))
	var run_paused: GameRun = _run_of([])
	run_paused.apply(GameCommand.pause())
	run_paused.apply(GameCommand.ultimate(0, point))
	_ok("a paused run starts no ultimate and does not start the recharge", _same_strings(_states(run_paused), ["idle", "idle", "idle"]) and run_paused.swords[0].ultimate_cooldown_left == 0.0)
	run_paused.apply(GameCommand.resume())
	run_paused.apply(GameCommand.ultimate(0, point))
	_ok("after resuming the same command works", run_paused.swords[0].phase == SwordState.Phase.ULTIMATE)
	# The ultimate interrupts the sword's own attack.
	var interrupts: Dictionary = cases["interrupts_attack"]
	var scenario: RunScenario = _arena([{"x": CENTER.x + 100.0, "y": CENTER.y, "hp": 500.0, "speed_scale": 0.0}])
	scenario.sword_start_cooldowns = [0.0, PARKED, PARKED]
	var run_attack: GameRun = GameRun.new(scenario)
	_steps(run_attack, 2)
	var phase_before: String = _phase_name(run_attack.swords[0].phase)
	run_attack.apply(GameCommand.ultimate(0, point))
	_ok("a command interrupts the sword's own automatic attack (%s -> ultimate) and drops its target" % phase_before, phase_before == String(interrupts["state_before"]) and _phase_name(run_attack.swords[0].phase) == String(interrupts["state_after"]) and run_attack.swords[0].target == null and bool(interrupts["target_cleared"]))
	# Repeated input: ten commands in the same tick start it once; later presses are all refused.
	var run_repeat: GameRun = _run_of([])
	for i: int in 10:
		run_repeat.apply(GameCommand.ultimate(0, point))
	_ok("ten commands in one tick start the ultimate once and arm the recharge once", run_repeat.cue_count(SimCue.Kind.ULTIMATE_STARTED) == 1 and run_repeat.cue_count(SimCue.Kind.ULTIMATE_REFUSED) == 0 and run_repeat.swords[0].ultimate_cooldown_left == run_repeat.swords[0].ultimate_cooldown)
	_steps(run_repeat, 120)
	for i: int in 5:
		run_repeat.apply(GameCommand.ultimate(0, point))
	_ok("five presses during the recharge are five visible refusals and no new flurry", run_repeat.cue_count(SimCue.Kind.ULTIMATE_REFUSED) == 5 and run_repeat.cue_count(SimCue.Kind.ULTIMATE_STARTED) == 1)
	_steps(run_repeat, 500)
	run_repeat.apply(GameCommand.ultimate(0, point))
	run_repeat.apply(GameCommand.ultimate(0, point))
	_ok("the first press after the recharge starts it, the second (already running) does not", run_repeat.cue_count(SimCue.Kind.ULTIMATE_STARTED) == 2 and run_repeat.cue_count(SimCue.Kind.ULTIMATE_REFUSED) == 5)


# ------------------------------------------------------------ keys and R
func _check_keys_and_r() -> void:
	print("flurry: Q, E and R through the input translator, and R as restart after death")
	var cases: Dictionary = _ref["keys_and_restart"]
	var codes: Dictionary = {"q": KEY_Q, "e": KEY_E, "r": KEY_R}
	for name: String in ["q", "e", "r"]:
		var translator: InputTranslator = InputTranslator.new()
		translator.pointer = CENTER + Vector2(200.0, 0.0)
		var commands: Array[GameCommand] = translator.handle_event(_key(codes[name], true))
		var run: GameRun = _run_of([])
		for command: GameCommand in commands:
			run.apply(command)
		_ok("%s starts the ultimate of its own slot only (%s)" % [name.to_upper(), _states(run)], _same_strings(_states(run), cases["key_" + name]) and commands[0].kind == GameCommand.Kind.ULTIMATE and commands[0].slot == "qer".find(name) and commands[0].point == CENTER + Vector2(200.0, 0.0))
	var held: InputTranslator = InputTranslator.new()
	held.handle_event(_key(KEY_Q, true))
	_ok("a held Q does not repeat the command", held.handle_event(_key(KEY_Q, true, true)).is_empty())
	var released: InputTranslator = InputTranslator.new()
	released.handle_event(_key(KEY_E, true))
	_ok("releasing E emits nothing", released.handle_event(_key(KEY_E, false)).is_empty())
	var only_q: InputTranslator = InputTranslator.new()
	_ok("Q and E produce the ultimate command alone, R also the delayed restart", only_q.handle_event(_key(KEY_Q, true)).size() == 1 and only_q.handle_event(_key(KEY_E, true)).size() == 1 and only_q.handle_event(_key(KEY_R, true)).size() == 2)
	# The aim point is the mouse in world coordinates.
	var aiming: InputTranslator = InputTranslator.new()
	aiming.to_world = func(viewport_point: Vector2) -> Vector2: return viewport_point + Vector2(1000.0, 500.0)
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = Vector2(300.0, 200.0)
	aiming.handle_event(motion)
	var aimed: Array[GameCommand] = aiming.handle_event(_key(KEY_E, true))
	_ok("the command carries the cursor's world position", aimed.size() == 1 and aimed[0].point == Vector2(1300.0, 700.0))
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.position = Vector2(10.0, 20.0)
	click.pressed = true
	click.button_index = MOUSE_BUTTON_LEFT
	_ok("a mouse click only updates the aim (Converge is a later slice)", aiming.handle_event(click).is_empty() and aiming.pointer == Vector2(10.0, 20.0))
	# R: slot three while alive, never a restart.
	var run_alive: GameRun = _run_of([])
	run_alive.kills = 7
	for command: GameCommand in InputTranslator.new().handle_event(_key(KEY_R, true)):
		run_alive.apply(command)
	_ok("R while alive is the slot-three ultimate and does not restart the run", run_alive.swords[2].phase == SwordState.Phase.ULTIMATE and run_alive.restarts == 0 and run_alive.kills == 7 and bool(cases["r_alive"]["slot3_state"] == "ult") and not bool(cases["r_alive"]["restarted"]))
	# Dead: nothing starts, and R restarts only after the delay.
	var dead_case: Dictionary = cases["dead"]
	var run_dead: GameRun = _run_of([])
	run_dead.hurt_player(1000, CENTER + Vector2(50.0, 0.0))
	var press_r: Callable = func() -> void:
		for command: GameCommand in InputTranslator.new().handle_event(_key(KEY_R, true)):
			run_dead.apply(command)
	for name: String in ["q", "r"]:
		for command: GameCommand in InputTranslator.new().handle_event(_key(codes[name], true)):
			run_dead.apply(command)
	_ok("dead: Q and R before the delay start nothing and do not restart (%s)" % [_states(run_dead)], _same_strings(_states(run_dead), (dead_case["early"] as Dictionary)["states"]) and run_dead.restarts == 0 and not bool((dead_case["early"] as Dictionary)["restarted"]))
	var restart_tick: int = -1
	for step: int in range(1, 400):
		run_dead.step()
		press_r.call()
		if run_dead.restarts > 0:
			restart_tick = step
			break
	_ok("dead: R restarts only after the delay, at tick %d (reference %d)" % [restart_tick, int(dead_case["ticks_to_restart"])], absi(restart_tick - int(dead_case["ticks_to_restart"])) <= TICK_TOL)
	var after: Dictionary = dead_case["after_restart"]
	_ok("the restarted run has full health, idle swords and every ultimate ready", not run_dead.dead and run_dead.hp == float(after["hp"]) and _same_strings(_states(run_dead), after["states"]) and run_dead.swords.all(func(sword: SwordState) -> bool: return sword.ultimate_ready()))
	var run_dead_e: GameRun = _run_of([])
	run_dead_e.hurt_player(1000, CENTER + Vector2(50.0, 0.0))
	for command: GameCommand in InputTranslator.new().handle_event(_key(KEY_E, true)):
		run_dead_e.apply(command)
	_ok("E after death starts nothing", _same_strings(_states(run_dead_e), cases["dead_e"]["states"]))
	# R while paused and dead (after the delay) still restarts: death is tested before the pause.
	var run_pd: GameRun = _run_of([])
	run_pd.hurt_player(1000, CENTER + Vector2(50.0, 0.0))
	while run_pd.death_time <= GameRun.RESTART_DELAY:
		run_pd.step()
	run_pd.apply(GameCommand.pause())
	for command: GameCommand in InputTranslator.new().handle_event(_key(KEY_R, true)):
		run_pd.apply(command)
	_ok("R while paused and dead (after the delay) restarts, as in the prototype", run_pd.restarts == 1 and bool((cases["r_paused_dead"] as Dictionary)["restarted"]))
	var run_pa: GameRun = _run_of([])
	run_pa.apply(GameCommand.pause())
	for command: GameCommand in InputTranslator.new().handle_event(_key(KEY_R, true)):
		run_pa.apply(command)
	_ok("R while paused and alive starts nothing and restarts nothing", _same_strings(_states(run_pa), cases["paused_q"]["states"]) and run_pa.restarts == 0)


func _key(code: Key, pressed: bool, echo: bool = false) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	event.echo = echo
	return event


# ------------------------------------------------------ pause and death
func _check_pause_and_death() -> void:
	print("flurry: pause and death in the middle of the flurry")
	var point: Vector2 = CENTER + Vector2(260.0, 0.0)
	var frozen: Dictionary = _ref["keys_and_restart"]["pause_freezes_flurry"]
	var run: GameRun = _run_of([])
	var sword: SwordState = run.swords[0]
	run.apply(GameCommand.ultimate(0, point))
	_steps(run, 10)
	var before: Array = [sword.phase, sword.position, sword.ultimate_cooldown_left, sword.ultimate_time_left, sword.ultimate_beat]
	run.apply(GameCommand.pause())
	_steps(run, 120)
	var after: Array = [sword.phase, sword.position, sword.ultimate_cooldown_left, sword.ultimate_time_left, sword.ultimate_beat]
	_ok("a paused flurry does not advance: position, flurry clock and recharge are frozen (%.3f s left)" % sword.ultimate_time_left, before == after and bool(frozen["identical"]) and _near(sword.ultimate_time_left, float((frozen["after"] as Dictionary)["ult_t"]), SCALAR_TOL) and _near(sword.ultimate_cooldown_left, float((frozen["after"] as Dictionary)["ult_cd"]), SCALAR_TOL))
	run.apply(GameCommand.resume())
	_steps(run, 65)
	_ok("resumed, the flurry finishes its remaining time and recovers", sword.phase == SwordState.Phase.RECOVER or sword.phase == SwordState.Phase.IDLE)
	var death: Dictionary = _ref["death_during_flurry"]["death"]
	var run_death: GameRun = _run_of(death["setup"])
	var husk: EnemyState = run_death.enemies[0]
	var sword_death: SwordState = run_death.swords[0]
	run_death.apply(GameCommand.ultimate(0, point))
	_steps(run_death, 20)
	var hits_before: float = _hits(husk, 500.0)
	run_death.hurt_player(1000, CENTER + Vector2(50.0, 0.0))
	_steps(run_death, 1)
	var hp_at_death: float = husk.hp
	var cooldown_at_death: float = sword_death.ultimate_cooldown_left
	_steps(run_death, 100)
	_ok("death in the middle of the flurry: %.0f darts landed first, none after (%.0f), the sword goes idle and drops its victim" % [hits_before, (hp_at_death - husk.hp) / 8.0],
		hits_before == float(death["hits_before"]) and husk.hp == hp_at_death and (hp_at_death - husk.hp) / 8.0 == float(death["hits_after"]) and sword_death.phase == SwordState.Phase.IDLE and sword_death.ultimate_victim == null and _phase_name(sword_death.phase) == String(death["victim_cleared_state"]))
	_ok("the recharge keeps running after death (%.3f then %.3f s left)" % [cooldown_at_death, sword_death.ultimate_cooldown_left], _near(cooldown_at_death, float(death["ult_cd_at_death"]), SCALAR_TOL) and _near(sword_death.ultimate_cooldown_left, float(death["ult_cd_100_ticks_later"]), SCALAR_TOL))
	# Death from a hit during the flurry: the dying tick's remaining darts do not happen.
	var run_late: GameRun = _run_of(death["setup"])
	var late_husk: EnemyState = run_late.enemies[0]
	run_late.apply(GameCommand.ultimate(0, point))
	_steps(run_late, 8)
	var hp_mid: float = late_husk.hp
	run_late.hurt_player(1000, CENTER)
	_steps(run_late, 200)
	_ok("a flurry cut off right after its first dart leaves exactly that one dart's damage (%.0f)" % ((500.0 - late_husk.hp) / 8.0), late_husk.hp == hp_mid and run_late.swords[0].phase == SwordState.Phase.IDLE)


# ----------------------------------------------------------- time scales
func _check_time_scales() -> void:
	print("flurry: hitstop and slow motion")
	var point: Vector2 = CENTER + Vector2(260.0, 0.0)
	var stop: Dictionary = _ref["time_scales"]["hitstop_at_command"]
	var run: GameRun = _run_of(stop["setup"])
	var husk: EnemyState = run.enemies[0]
	var sword: SwordState = run.swords[0]
	run.hitstop = float(stop["hitstop"])
	run.apply(GameCommand.ultimate(0, point))
	_ok("a command during hitstop blinks and arms the recharge at once", sword.phase == SwordState.Phase.ULTIMATE and sword.position == sword.ultimate_point and sword.ultimate_cooldown_left == sword.ultimate_cooldown)
	var first_hit: int = -1
	var seen: Dictionary = {}
	var hp_before: float = husk.hp
	for step: int in range(1, 140):
		run.step()
		if husk.hp < hp_before and first_hit < 0:
			first_hit = step
		hp_before = husk.hp
		if (stop["at"] as Dictionary).has(str(step)):
			seen[str(step)] = [sword.ultimate_cooldown_left, sword.ultimate_time_left]
	var clock_ok: bool = true
	for key: String in stop["at"]:
		var want: Dictionary = (stop["at"] as Dictionary)[key]
		clock_ok = clock_ok and _near(float(seen[key][0]), float(want["ult_cd"]), SCALAR_TOL) and _near(float(seen[key][1]), float(want["ult_t"]), SCALAR_TOL)
	_ok("hitstop freezes the whole flurry (first dart on tick %d, reference %d)" % [first_hit, int(stop["first_hit_tick"])], absi(first_hit - int(stop["first_hit_tick"])) <= TICK_TOL and clock_ok, "%s" % [seen])
	var slow: Dictionary = _ref["time_scales"]["slow_motion"]
	var run_slow: GameRun = _run_of(slow["setup"])
	var husk_slow: EnemyState = run_slow.enemies[0]
	var sword_slow: SwordState = run_slow.swords[0]
	run_slow.slowmo = 100.0
	run_slow.slowmo_scale = float(slow["scale"])
	run_slow.apply(GameCommand.ultimate(0, point))
	var slow_first: int = -1
	var slow_hp: float = husk_slow.hp
	for step: int in range(1, 100):
		run_slow.step()
		if husk_slow.hp < slow_hp and slow_first < 0:
			slow_first = step
		slow_hp = husk_slow.hp
	_ok("slow motion slows the flurry, its cadence and its recharge alike (first dart tick %d, %.3f s left of the recharge)" % [slow_first, sword_slow.ultimate_cooldown_left],
		absi(slow_first - int(slow["first_hit_tick"])) <= TICK_TOL and _near(sword_slow.ultimate_cooldown_left, float(slow["ult_cd_after_99"]), SCALAR_TOL) and _near(sword_slow.ultimate_time_left, float(slow["ult_t_after_99"]), SCALAR_TOL) and _phase_name(sword_slow.phase) == String(slow["state"]))


# ------------------------------------------------ projectiles and others
func _check_projectiles_and_others() -> void:
	print("flurry: orbs and the other swords")
	var case: Dictionary = _ref["projectiles"]["orb_in_the_area"]
	var run: GameRun = _run_of((case["setup"] as Dictionary)["enemies"])
	var orb_setup: Dictionary = case["setup"]
	var orb: ProjectileState = run.spawn_projectile(Vector2(float(orb_setup["x"]), float(orb_setup["y"])), Vector2.ZERO)
	orb.life = float(orb_setup["life"])
	run.apply(GameCommand.ultimate(0, CENTER + Vector2(260.0, 0.0)))
	_steps(run, 100)
	_ok("the flurry does not parry: an orb hanging where the sword blinked and darted survives (as in the prototype), and nothing froze for a parry", run.projectiles.has(orb) and bool(case["orb_alive"]) and run.cue_count(SimCue.Kind.PROJECTILE_PARRIED) == 0 and run.hitstop == float(case["parry_hitstop"]))
	var others: Dictionary = _ref["other_swords"]["others"]
	var scenario: RunScenario = _arena(others["setup"])
	scenario.sword_start_cooldowns = [PARKED, 0.0, 0.0]
	var run_others: GameRun = GameRun.new(scenario)
	var husk: EnemyState = run_others.enemies[0]
	run_others.apply(GameCommand.ultimate(0, CENTER + Vector2(330.0, -300.0)))
	var struck: bool = false
	var state_at_ten: String = ""
	for step: int in range(1, 40):
		run_others.step()
		struck = struck or run_others.swords[1].phase != SwordState.Phase.IDLE or run_others.swords[2].phase != SwordState.Phase.IDLE
		if step == 11:
			state_at_ten = _phase_name(run_others.swords[0].phase)
	_ok("while one Fang flurries the other two keep their automatic attacks and hurt a husk (%.0f hp left)" % husk.hp, struck and husk.hp < 500.0 and state_at_ten == String(others["flurry_sword_state"]) and bool(others["others_struck"]) and bool(others["husk_damaged"]))


func _check_exactly_once() -> void:
	print("flurry: deaths and rewards resolve exactly once")
	var setup: Array = [{"x": CENTER.x + 260.0, "y": CENTER.y, "hp": 20.0, "speed_scale": 0.0}, {"x": CENTER.x + 300.0, "y": CENTER.y + 40.0, "hp": 20.0, "speed_scale": 0.0}, {"x": CENTER.x + 240.0, "y": CENTER.y - 40.0, "hp": 20.0, "speed_scale": 0.0}]
	var run: GameRun = _run_of(setup)
	run.apply(GameCommand.ultimate(0, CENTER + Vector2(260.0, 0.0)))
	_steps(run, 75)
	_ok("three weak enemies in the area all die to the flurry: kills %d, kill cues %d, three healing motes each (%d)" % [run.kills, run.cue_count(SimCue.Kind.ENEMY_KILLED), run.motes.size() + run.cue_count(SimCue.Kind.MOTE_COLLECTED)],
		run.kills == 3 and run.cue_count(SimCue.Kind.ENEMY_KILLED) == 3 and run.enemies.is_empty() and run.combo == 3 and run.best_combo == 3 and run.motes.size() + run.cue_count(SimCue.Kind.MOTE_COLLECTED) == 9)
	_ok("every dart is a hit cue: %d darts for %d kills, and none after the area is empty" % [run.cue_count(SimCue.Kind.ENEMY_HIT), run.kills], run.cue_count(SimCue.Kind.ENEMY_HIT) == 9)


func _check_touch_aim() -> void:
	print("flurry: touch aiming (the nearest enemy, or ahead of the player)")
	var case: Dictionary = _ref["keys_and_restart"]["auto_aim"]
	var run: GameRun = _run_of(case["setup"])
	var nearest: Vector2 = run.auto_aim()
	var ahead_run: GameRun = _run_of([])
	ahead_run.facing = _point(case["facing"])
	var ahead: Vector2 = ahead_run.auto_aim()
	_ok("the nearest living enemy is the aim point (%s), and 300 px ahead of the player when there is none (%s)" % [nearest, ahead], nearest.distance_to(_point(case["nearest"])) <= POSITION_TOL and ahead.distance_to(_point(case["forward"])) <= POSITION_TOL)
	run.apply(GameCommand.ultimate_at_nearest(0))
	_ok("the touch command lands there, clamped to the range like any other (%s)" % [run.swords[0].ultimate_point], run.swords[0].ultimate_point.distance_to(_point(case["blink"])) <= POSITION_TOL)
	var corpse_run: GameRun = _run_of(case["setup"])
	corpse_run.kill(corpse_run.enemies[0], Vector2.RIGHT)
	var far_setup: Dictionary = (case["setup"] as Array)[1]
	_ok("a dead enemy is not a touch aim point (the farther living one is)", corpse_run.auto_aim().distance_to(Vector2(float(far_setup["x"]), float(far_setup["y"]))) <= POSITION_TOL)


func _check_restart_clears() -> void:
	print("flurry: restarting clears the ultimate")
	var run: GameRun = _run_of([{"x": CENTER.x + 260.0, "y": CENTER.y, "hp": 500.0, "speed_scale": 0.0}])
	run.apply(GameCommand.ultimate(0, CENTER + Vector2(260.0, 0.0)))
	run.apply(GameCommand.ultimate(1, CENTER + Vector2(260.0, 0.0)))
	_steps(run, 20)
	run.apply(GameCommand.restart())
	_ok("the Restart button clears every flurry, recharge and cue count", run.swords.all(func(sword: SwordState) -> bool: return sword.phase == SwordState.Phase.IDLE and sword.ultimate_ready() and sword.ultimate_victim == null) and run.cue_count(SimCue.Kind.ULTIMATE_STARTED) == 0)
	run.apply(GameCommand.ultimate(0, CENTER))
	_ok("and a fresh run can use its ultimates at once", run.swords[0].phase == SwordState.Phase.ULTIMATE)


# ------------------------------------------------------- real Main scene
func _main_with(scenario: RunScenario, sword_scene: String = "") -> Main:
	var main: Main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Main
	main.scenario = scenario
	if not sword_scene.is_empty():
		main.sword_visual = load(sword_scene)
	_tree.root.add_child(main)
	main.set_physics_process(false)
	return main


func _tick_main(main: Main, count: int) -> void:
	for i: int in count:
		main._physics_process(GameRun.TICK_DT)


func _press(main: Main, code: Key) -> void:
	main._input(_key(code, true))


func _move_mouse(main: Main, viewport_point: Vector2) -> void:
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = viewport_point
	main._input(motion)


func _check_main_scene() -> void:
	print("flurry: Q, E and R in the real Main scene (mouse aim, HUD, sound, effects)")
	var scenario: RunScenario = _arena([{"x": CENTER.x + 250.0, "y": CENTER.y, "hp": 500.0, "speed_scale": 0.0}, {"x": CENTER.x + 290.0, "y": CENTER.y + 30.0, "hp": 500.0, "speed_scale": 0.0}])
	var main: Main = _main_with(scenario)
	await _tree.process_frame
	main._sfx.unlock()
	main._sfx.played.clear()
	_tick_main(main, 5)
	var half: Vector2 = main.get_viewport().get_visible_rect().size * 0.5
	_ok("before any command the HUD shows all three ultimates ready, named Viper Flurry", [0, 1, 2].all(func(slot: int) -> bool: return main._hud.ultimate_status(slot) == "READY" and main._hud.ultimate_card_visible(slot)))
	_move_mouse(main, half + Vector2(250.0, 0.0))
	var expected: Vector2 = main.run.camera + Vector2(250.0, 0.0)
	_press(main, KEY_Q)
	var sword: SwordState = main.run.swords[0]
	_ok("Q with the mouse 250 px right of the view's centre blinks the first sword to that world point (%s)" % [sword.ultimate_point], sword.phase == SwordState.Phase.ULTIMATE and sword.ultimate_point.distance_to(expected) <= 0.01 and main.run.swords[1].phase == SwordState.Phase.IDLE)
	_ok("the blink is heard (dash sound) and announced with a cue", main._sfx.played.has("dash") and main.run.cue_count(SimCue.Kind.ULTIMATE_STARTED) == 1, "%s" % [main._sfx.played])
	_tick_main(main, 10)
	await _tree.process_frame
	_ok("the HUD shows slot one ACTIVE and the others READY", main._hud.ultimate_status(0) == "ACTIVE" and main._hud.ultimate_status(1) == "READY" and main._hud.ultimate_status(2) == "READY", main._hud.ultimate_status(0))
	_press(main, KEY_E)
	_press(main, KEY_R)
	_ok("E and R start slots two and three too, and R does not restart", main.run.swords[1].phase == SwordState.Phase.ULTIMATE and main.run.swords[2].phase == SwordState.Phase.ULTIMATE and main.run.restarts == 0)
	_tick_main(main, 80)
	await _tree.process_frame
	var left: int = SimMath.py_round(main.run.swords[0].ultimate_cooldown_left)
	_ok("after the flurry the HUD counts the recharge down in whole seconds (%s) and the bar fills as it goes (%.2f)" % [main._hud.ultimate_status(0), main._hud.ultimate_bar_fraction(0)], main._hud.ultimate_status(0) == "%ds" % left and left >= 7 and main._hud.ultimate_bar_fraction(0) > 0.1 and main._hud.ultimate_bar_fraction(0) < 0.3)
	var texts_before: int = main._presenter._effects._texts.size()
	_press(main, KEY_Q)
	_ok("pressing Q while it recharges is refused and says so on screen", main.run.cue_count(SimCue.Kind.ULTIMATE_REFUSED) == 1 and main._presenter._effects._texts.size() == texts_before + 1 and String(main._presenter._effects._texts[texts_before]["text"]).begins_with("recharging"), "%d vs %d" % [main._presenter._effects._texts.size(), texts_before])
	_tick_main(main, 540)
	await _tree.process_frame
	_ok("540 ticks after it started the HUD says READY again", main._hud.ultimate_status(0) == "READY" and main._hud.ultimate_bar_fraction(0) == 1.0)
	main.queue_free()
	await _tree.process_frame
	# R as restart in the real scene: refused early, accepted after the delay, and never as an ultimate then.
	var doom: RunScenario = RunScenario.new().without_conditions()
	doom.seed = 6
	doom.waves_enabled = false
	doom.start_health = 10.0
	doom.initial_husks = [GameRun.WORLD.get_center() + Vector2(20.0, 0.0)]
	var loser: Main = _main_with(doom)
	await _tree.process_frame
	_tick_main(loser, 2)
	_press(loser, KEY_R)
	_press(loser, KEY_Q)
	_ok("dead: R and Q during the death slow motion neither restart nor start an ultimate", loser.run.dead and loser.run.restarts == 0 and loser.run.swords.all(func(s: SwordState) -> bool: return s.phase == SwordState.Phase.IDLE))
	_tick_main(loser, 130)
	_press(loser, KEY_R)
	_ok("dead: R after the delay restarts and the new run's slot-three ultimate has not been used", loser.run.restarts == 1 and not loser.run.dead and loser.run.cue_count(SimCue.Kind.ULTIMATE_STARTED) == 0 and loser.run.swords[2].ultimate_ready())
	loser.queue_free()
	await _tree.process_frame
	# Pause: P stops the flurry and Q is refused.
	var paused_main: Main = _main_with(_arena([]))
	await _tree.process_frame
	_press(paused_main, KEY_Q)
	_tick_main(paused_main, 10)
	_press(paused_main, KEY_P)
	var frozen_time: float = paused_main.run.swords[0].ultimate_time_left
	_press(paused_main, KEY_E)
	_tick_main(paused_main, 30)
	_ok("paused in the middle of the flurry: it neither advances nor accepts another slot's command", paused_main.run.paused and paused_main.run.swords[0].ultimate_time_left == frozen_time and paused_main.run.swords[1].phase == SwordState.Phase.IDLE and paused_main._hud.ultimate_status(0) == "ACTIVE")
	paused_main.queue_free()
	await _tree.process_frame


func _check_visual_independence() -> void:
	print("flurry: swapping the sword visual leaves the flurry unchanged")
	var results: Array[Dictionary] = []
	var hosts: Array[Main] = []
	for use_alt: bool in [false, true]:
		var scenario: RunScenario = RenderRateScenario.scenario(RenderRateScenario.FLURRY)
		hosts.append(_main_with(scenario, "res://tests/alt_sword.tscn" if use_alt else ""))
	await _tree.process_frame
	var ultimate_seen: bool = false
	for host_index: int in hosts.size():
		var main: Main = hosts[host_index]
		for tick_index: int in 300:
			for command: GameCommand in RenderRateScenario.commands_at(main.run.tick, RenderRateScenario.FLURRY):
				main.run.apply(command)
			_tick_main(main, 1)
			if host_index == 1:
				for child: Node in main._presenter.get_children():
					if child is AltSwordVisual and (child as AltSwordVisual).last_phase == SwordState.Phase.ULTIMATE:
						ultimate_seen = true
		results.append(main.run.snapshot())
	_ok("a stretched, rotated replacement sword visual changes nothing about the flurry's hits, deaths or recharge", results[0] == results[1])
	_ok("the replacement visual was told the ultimate phase (and nothing else about it)", ultimate_seen)
	_ok("the fixture fought: %d darts, %d kills, %d flurries" % [hosts[0].run.cue_count(SimCue.Kind.ENEMY_HIT), hosts[0].run.kills, hosts[0].run.cue_count(SimCue.Kind.ULTIMATE_STARTED)], hosts[0].run.cue_count(SimCue.Kind.ENEMY_HIT) >= 10 and hosts[0].run.cue_count(SimCue.Kind.ULTIMATE_STARTED) >= 3)
	for main: Main in hosts:
		main.queue_free()
	await _tree.process_frame


# -------------------------------------------------------- render rates
func _check_render_rates() -> void:
	print("flurry: identical outcomes at low and high render rates")
	var headless: Dictionary = RenderRateScenario.play_headless(RenderRateScenario.FLURRY)
	var expected_digest: Dictionary = JSON.parse_string(JSON.stringify(headless))
	_ok("the scripted fight does something worth comparing (flurries %d, refused %d, darts %d, kills %d, alive %s)" % [int(headless["ultimate_cues"]), int(headless["refused_cues"]), int(headless["hit_cues"]), int(headless["kills"]), not bool(headless["dead"])],
		int(headless["ultimate_cues"]) == 6 and int(headless["refused_cues"]) == 4 and int(headless["hit_cues"]) >= 40 and int(headless["kills"]) >= 3 and not bool(headless["dead"]))
	var executable: String = OS.get_executable_path()
	var project: String = ProjectSettings.globalize_path("res://")
	var frames: Dictionary[int, int] = {}
	for rate: int in PROBE_FRAME_RATES:
		var output: Array = []
		var arguments: PackedStringArray = ["--headless", "--path", project, "--fixed-fps", str(rate), "--script", PROBE_SCRIPT, "--", "--probe=rate-flurry"]
		var code: int = OS.execute(executable, arguments, output, true)
		var line: String = _probe_line(output)
		_ok("the engine played the flurry fight at %d fps (exit %d)" % [rate, code], code == 0 and not line.is_empty(), "%s" % [output])
		if line.is_empty():
			continue
		var result: Dictionary = JSON.parse_string(line)
		frames[rate] = int(result["frames"])
		var comparable: Dictionary = result.duplicate()
		for key: String in ["frames", "visuals", "enemies"]:
			comparable.erase(key)
		_ok("at %d fps the real Main scene ends the fight exactly like the bare simulation: same darts, kills, positions, phases and recharges" % rate, comparable == expected_digest, _first_difference(comparable, expected_digest))
	_ok("the rates really differed: the engine drew %s frames for the same %d ticks" % [frames, RenderRateScenario.TOTAL_TICKS],
		frames.size() == PROBE_FRAME_RATES.size() and frames[5] < frames[20] and frames[20] < frames[60] and frames[60] < frames[240])


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
