class_name ElementalConditionChecks
extends RefCounted
## Game-run behavioural checks for the elemental conditions (issue #11): fire, poison, ice,
## the damage-over-time cadence, the frozen bonus, frozen contact immunity, brute freeze
## reduction and fire spread on a burning death. Like the earlier slices' checks, every check
## drives the real `GameRun` (or the real Main scene), advances fixed ticks and observes outcomes.
## Comparison values come from the Python prototype's captured reference
## (res://tests/reference/elemental_conditions.json, recorded by
## tools/reference/capture_elemental_conditions.py with the prototype's `afflict` ON). Each case
## there is a SPEC (swords, enemies, events) replayed here tick for tick; nothing in this file
## copies a starting number. Tolerances and exceptions: docs/reference/elemental-conditions.md.

const REFERENCE_PATH: String = "res://tests/reference/elemental_conditions.json"
const PROBE_SCRIPT: String = "res://tests/frame_rate_probe.gd"

## Same-algorithm comparisons at the prototype's 60 FPS step; the reference rounds timers to
## four decimals and positions to three.
const POSITION_TOL: float = 0.05  # px
const VELOCITY_TOL: float = 0.05  # px/s
const TIMER_TOL: float = 0.001    # seconds, accumulators, dps
const HP_TOL: float = 0.001
const PROBE_FRAME_RATES: Array[int] = [5, 20, 60, 240]
const PARKED: float = 99.0
const DT: float = GameRun.TICK_DT

var _check: Callable
var _tree: SceneTree
var _ref: Dictionary = {}


func _init(check_function: Callable, tree: SceneTree) -> void:
	_check = check_function
	_tree = tree


func run_all() -> void:
	var file: FileAccess = FileAccess.open(REFERENCE_PATH, FileAccess.READ)
	if file == null:
		_ok("conditions reference file loads", false, REFERENCE_PATH)
		return
	_ref = JSON.parse_string(file.get_as_text())
	_ok("conditions reference file parses", not _ref.is_empty())
	_check_reference_scope()
	_check_definitions()
	_check_fire()
	_check_poison()
	_check_ice()
	_check_frozen_bonus()
	_check_frozen_contact()
	_check_motion_and_clocks()
	_check_mixed_and_cadence()
	_check_spread()
	_check_chain()
	_check_deaths_exactly_once()
	_check_sword_hits()
	_check_flurry_darts()
	_check_afflict_entry_and_fixture_flag()
	_check_survival_band()
	_check_cues()
	_check_conditions_encounter()
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


## The scenario a reference spec describes: its swords, parked unless the spec says otherwise,
## its enemies as placements, no waves, no crits.
func _scenario_of(spec: Dictionary) -> RunScenario:
	var scenario: RunScenario = RunScenario.new()
	scenario.seed = 61
	scenario.waves_enabled = false
	scenario.crit_chance = 0.0
	var specs: Array[SwordSpec] = []
	for entry: Variant in spec["swords"]:
		var pair: Array = entry as Array
		specs.append(SwordSpec.make(&"fang", int(pair[0]), StringName(pair[1])))
	scenario.loadout = specs
	var cooldowns: Array[float] = []
	for i: int in specs.size():
		cooldowns.append(float((spec["sword_cooldowns"] as Array)[i]) if spec.has("sword_cooldowns") else PARKED)
	scenario.sword_start_cooldowns = cooldowns
	var placements: Array[EnemyPlacement] = []
	for entry: Variant in spec["enemies"]:
		var setup: Dictionary = entry as Dictionary
		var placement: EnemyPlacement = EnemyPlacement.make(StringName(setup["kind"]), Vector2(float(setup["x"]), float(setup["y"])))
		placement.speed_scale = float(setup["speed_scale"])
		placement.hp = float(setup["hp"])
		if setup.has("velocity"):
			var velocity: Array = setup["velocity"]
			placement.velocity = Vector2(float(velocity[0]), float(velocity[1]))
		placement.stun = float(setup.get("stun", 0.0))
		placement.phase = float(setup.get("phase", 0.0))
		if setup.has("shoot_cooldown"):
			placement.shoot_cooldown = float(setup["shoot_cooldown"])
		placements.append(placement)
	scenario.initial_enemies = placements
	return scenario


## The state of the enemy the reference records, as plain values.
func _snap_enemy(enemy: EnemyState) -> Dictionary:
	var c: EnemyConditions = enemy.conditions
	return {
		"hp": enemy.hp, "dead": enemy.dead, "burn": c.burn, "burn_dps": c.burn_dps, "poison": c.poison, "poison_dps": c.poison_dps,
		"poison_stacks": c.poison_stacks, "chill": c.chill, "chill_stacks": c.chill_stacks, "frozen": c.frozen, "dot": c.dot, "dot_t": c.dot_time,
		"x": enemy.position.x, "y": enemy.position.y, "vx": enemy.velocity.x, "vy": enemy.velocity.y, "stun": enemy.stun, "t": enemy.age,
	}


## Replays a spec on the real run. Returns the run, its enemies in spec order (kept even after
## the dead leave the run), what each blow dealt, the first mismatch against the reference trace
## ("" when none) and a per-tick record of every enemy for the semantic checks.
func _play(spec: Dictionary, expected_trace: Dictionary = {}, expected_dealt: Array = []) -> Dictionary:
	var run: GameRun = GameRun.new(_scenario_of(spec))
	var enemies: Array[EnemyState] = run.enemies.duplicate()
	var frozen_start: Array[float] = []
	for entry: Variant in spec["enemies"]:
		frozen_start.append(float((entry as Dictionary).get("frozen", 0.0)))
	for i: int in enemies.size():
		enemies[i].conditions.frozen = frozen_start[i]
	var by_step: Dictionary = {}
	for event: Variant in spec.get("events", []):
		var ev: Dictionary = event as Dictionary
		var list: Array = by_step.get(int(ev["step"]), [])
		list.append(ev)
		by_step[int(ev["step"])] = list
	var watch: Dictionary = {}
	for step_value: Variant in spec["watch"]:
		watch[int(step_value)] = true
	var dealt: Array[Dictionary] = []
	var record: Array = [[]]  # per tick, index = step; [0] unused
	var mismatch: String = ""
	var cues_seen: Dictionary = {}
	var first_cue_step: Dictionary = {}
	for step: int in range(1, int(spec["steps"]) + 1):
		for ev: Dictionary in by_step.get(step, []):
			var target: EnemyState = enemies[int(ev["enemy"])] if ev.has("enemy") else null
			match String(ev["type"]):
				"hit":
					run.scenario.crit_chance = 1.0 if bool(ev.get("crit", false)) else 0.0
					var before: float = target.hp
					run.hit_enemy(target, float(ev["damage"]), Vector2.RIGHT, 0.0, run.swords[int(ev["sword"])], bool(ev.get("heavy", true)))
					run.scenario.crit_chance = 0.0
					dealt.append({"step": step, "enemy": int(ev["enemy"]), "dealt": before - target.hp})
				"afflict":
					run.afflict(target, StringName(ev["element"]), float(ev["power"]), int(ev.get("stacks", 1)))
				"ultimate":
					var point: Array = ev["point"]
					run.try_ultimate(int(ev["slot"]), Vector2(float(point[0]), float(point[1])))
		run.step()
		for cue: SimCue in run.take_cues():
			cues_seen[cue.kind] = int(cues_seen.get(cue.kind, 0)) + 1
			if not first_cue_step.has(cue.kind):
				first_cue_step[cue.kind] = step
		var tick_record: Array[Dictionary] = []
		for enemy: EnemyState in enemies:
			tick_record.append(_snap_enemy(enemy))
		record.append(tick_record)
		if watch.has(step) and expected_trace.has(str(step)) and mismatch.is_empty():
			mismatch = _compare_run(run, enemies, expected_trace[str(step)] as Dictionary, step)
	if not expected_dealt.is_empty() and mismatch.is_empty():
		mismatch = _compare_dealt(dealt, expected_dealt)
	return {"run": run, "enemies": enemies, "dealt": dealt, "mismatch": mismatch, "record": record, "cues": cues_seen, "first_cue_step": first_cue_step}


func _compare_dealt(actual: Array[Dictionary], expected: Array) -> String:
	if actual.size() != expected.size():
		return "%d blows dealt vs %d in the reference" % [actual.size(), expected.size()]
	for i: int in actual.size():
		var want: Dictionary = expected[i] as Dictionary
		if int(want["step"]) != int(actual[i]["step"]) or not _near(float(want["dealt"]), float(actual[i]["dealt"]), 0.0001):
			return "blow %d at step %d dealt %s, reference %s" % [i, int(actual[i]["step"]), actual[i]["dealt"], want["dealt"]]
	return ""


func _compare_run(run: GameRun, enemies: Array[EnemyState], expected: Dictionary, step: int) -> String:
	var want_enemies: Array = expected["enemies"]
	for i: int in enemies.size():
		var want: Dictionary = want_enemies[i] as Dictionary
		var got: Dictionary = _snap_enemy(enemies[i])
		for key: String in want:
			var expected_value: Variant = want[key]
			var actual_value: Variant = got[key]
			var tolerance: float = TIMER_TOL
			match key:
				"x", "y":
					tolerance = POSITION_TOL
				"vx", "vy":
					tolerance = VELOCITY_TOL
				"hp":
					tolerance = HP_TOL
			var equal: bool
			if expected_value is bool or key == "poison_stacks" or key == "chill_stacks":
				equal = int(expected_value) == int(actual_value)
			else:
				equal = _near(float(expected_value), float(actual_value), tolerance)
			if not equal:
				return "step %d enemy %d %s: %s vs reference %s" % [step, i, key, str(actual_value), str(expected_value)]
	if not _near(run.hp, float(expected["player_hp"]), 0.01):
		return "step %d player health %.2f vs reference %s" % [step, run.hp, str(expected["player_hp"])]
	if run.kills != int(expected["kills"]):
		return "step %d kills %d vs reference %d" % [step, run.kills, int(expected["kills"])]
	if run.projectiles.size() != int(expected["projectiles"]):
		return "step %d projectiles %d vs reference %d" % [step, run.projectiles.size(), int(expected["projectiles"])]
	if not _near(run.hitstop, float(expected["hitstop"]), 0.002):
		return "step %d hitstop %.4f vs reference %s" % [step, run.hitstop, str(expected["hitstop"])]
	var want_swords: Array = expected["swords"]
	for i: int in run.swords.size():
		var want_sword: Dictionary = want_swords[i] as Dictionary
		if _phase_name(run.swords[i].phase) != String(want_sword["state"]):
			return "step %d sword %d is %s, reference %s" % [step, i, _phase_name(run.swords[i].phase), str(want_sword["state"])]
		if not _near(run.swords[i].ultimate_cooldown_left, float(want_sword["ult_cd"]), 0.002):
			return "step %d sword %d recharge %.4f vs reference %s" % [step, i, run.swords[i].ultimate_cooldown_left, str(want_sword["ult_cd"])]
	return ""


## One reference case replayed and compared; the played result comes back for the semantic checks.
func _replay(group: String, name: String, label: String) -> Dictionary:
	var entry: Dictionary = (_ref[group] as Dictionary)[name] as Dictionary
	var played: Dictionary = _play(entry["spec"] as Dictionary, entry["trace"] as Dictionary, entry["dealt"] as Array)
	_ok("%s matches the prototype tick for tick over %d watched ticks (%s)" % [label, (entry["trace"] as Dictionary).size(), name], String(played["mismatch"]).is_empty(), String(played["mismatch"]))
	return played


## What the enemy at `index` looked like after `step`.
func _at(played: Dictionary, step: int, index: int = 0) -> Dictionary:
	return ((played["record"] as Array)[step] as Array)[index] as Dictionary


func _first_step(played: Dictionary, from_step: int, test: Callable, index: int = 0) -> int:
	var record: Array = played["record"]
	for step: int in range(from_step, record.size()):
		if test.call(((record[step] as Array)[index] as Dictionary)):
			return step
	return -1


func _ticks(seconds: float) -> int:
	return roundi(seconds * 60.0)


# ------------------------------------------------------ reference scope
func _check_reference_scope() -> void:
	print("conditions: the reference is the prototype with conditions ON, one oracle")
	var scope: Dictionary = _ref["fixture_scope"]
	_ok("the capture drove the prototype's real afflict on Fang swords and unarmed enemies only (%d enemies)" % int(scope["enemies_created"]),
		bool(scope["afflict_enabled"]) and int(scope["armed_enemies"]) == 0 and scope["swords_used"] == ["fang"] and not bool(scope["converge_used"]) and not bool(scope["waves_enabled"]))
	var survival: Array = _ref["survival"]["wave1_three_fangs_stationary_player"]
	var unarmed: bool = survival.size() == 8
	for entry: Dictionary in survival:
		unarmed = unarmed and int(entry["armed_enemies"]) == 0 and int(entry["husks_spawned"]) == 8
	_ok("the conditions-on survival reference is the unarmed first wave", unarmed)


func _check_definitions() -> void:
	print("conditions: constants and formulas")
	var table: Dictionary = _ref["table"]
	_ok("durations and thresholds are the prototype's (burn %.1f, poison %.1f, chill %.1f, freeze %.1f s; poison cap %d; freeze at %d)" % [ConditionDefs.BURN_TIME, ConditionDefs.POISON_TIME, ConditionDefs.CHILL_TIME, ConditionDefs.FREEZE_TIME, ConditionDefs.POISON_MAX, ConditionDefs.FREEZE_STACKS],
		ConditionDefs.BURN_TIME == float(table["burn_time"]) and ConditionDefs.POISON_TIME == float(table["poison_time"]) and ConditionDefs.CHILL_TIME == float(table["chill_time"]) and ConditionDefs.FREEZE_TIME == float(table["freeze_time"])
		and ConditionDefs.POISON_MAX == int(table["poison_max"]) and ConditionDefs.FREEZE_STACKS == int(table["freeze_stacks"]))
	_ok("chill slows to %.1f, shatter multiplies by %.1f, freezing keeps %.1f of the velocity, the dot lands every %.1f s" % [ConditionDefs.CHILL_SLOW, ConditionDefs.SHATTER, ConditionDefs.FREEZE_VELOCITY_KEEP, ConditionDefs.DOT_PERIOD],
		ConditionDefs.CHILL_SLOW == float(table["chill_slow"]) and ConditionDefs.SHATTER == float(table["shatter"]) and ConditionDefs.FREEZE_VELOCITY_KEEP == float(table["freeze_velocity_keep"]) and ConditionDefs.DOT_PERIOD == float(table["dot_period"]))
	_ok("spread reaches %.0f px past the edges at %.1f of the dps and %.1f of the burn time" % [ConditionDefs.SPREAD_REACH, ConditionDefs.SPREAD_DPS_FACTOR, ConditionDefs.SPREAD_TIME_FACTOR],
		ConditionDefs.SPREAD_REACH == float(table["spread_reach"]) and ConditionDefs.SPREAD_DPS_FACTOR == float(table["spread_dps_factor"]) and ConditionDefs.SPREAD_TIME_FACTOR == float(table["spread_time_factor"]))
	_ok("a brute's freeze lasts %.1f of the usual time and every other type's the whole of it" % EnemyDefs.BRUTE_FREEZE_FACTOR,
		EnemyDefs.BRUTE_FREEZE_FACTOR == float(table["brute_freeze_factor"]) and EnemyDefs.of(EnemyDefs.BRUTE).freeze_factor == EnemyDefs.BRUTE_FREEZE_FACTOR
		and EnemyDefs.of(EnemyDefs.HUSK).freeze_factor == 1.0 and EnemyDefs.of(EnemyDefs.RUNNER).freeze_factor == 1.0 and EnemyDefs.of(EnemyDefs.SPITTER).freeze_factor == 1.0)
	var rows: Dictionary = table["dps_by_rarity"]
	var matches: bool = true
	for rarity: int in 3:
		var row: Dictionary = rows[str(rarity)]
		var sword: SwordState = SwordState.equip(SwordSpec.make(&"fang", rarity, &"fire"), Vector2.ZERO, 0.0)
		matches = matches and _near(sword.damage, float(row["power"]), 0.0001) and _near(ConditionDefs.burn_dps(sword.damage, 1), float(row["fire"]), 0.0001) \
			and _near(ConditionDefs.poison_dps(sword.damage), float(row["poison"]), 0.0001) and _near(ConditionDefs.burn_dps(sword.damage, 3), float(row["fire_three_stacks"]), 0.0001)
	_ok("burn dps (1.5 + 0.2 x power) x stacks and poison dps per stack (1 + 0.06 x power) follow the sword's rarity-scaled damage", matches)
	_ok("only the three elements exist", ConditionDefs.is_element(&"fire") and ConditionDefs.is_element(&"ice") and ConditionDefs.is_element(&"poison") and not ConditionDefs.is_element(&"shadow") and table["elements"] == ["fire", "ice", "poison"])


# ------------------------------------------------------------------ fire
func _check_fire() -> void:
	print("conditions: fire burns, refreshes and expires")
	var common: Dictionary = _replay("fire", "fire_common", "a common fire sword's blow")
	var rare: Dictionary = _replay("fire", "fire_rare", "a rare fire sword's blow")
	var mythic: Dictionary = _replay("fire", "fire_mythic", "a mythic fire sword's blow")
	var table: Dictionary = _ref["table"]["dps_by_rarity"]
	_ok("the burn starts at the sword's dps and lasts three seconds (%.2f, %.2f, %.2f dps; %.4f s left after the tick)" % [float(_at(common, 1)["burn_dps"]), float(_at(rare, 1)["burn_dps"]), float(_at(mythic, 1)["burn_dps"]), float(_at(common, 1)["burn"])],
		_near(float(_at(common, 1)["burn_dps"]), float(table["0"]["fire"]), 0.0001) and _near(float(_at(rare, 1)["burn_dps"]), float(table["1"]["fire"]), 0.0001)
		and _near(float(_at(mythic, 1)["burn_dps"]), float(table["2"]["fire"]), 0.0001) and _near(float(_at(common, 1)["burn"]), ConditionDefs.BURN_TIME - DT, 0.0001))
	var last_burning: int = -1
	for step: int in range(1, 200):
		if float(_at(common, step)["burn"]) > 0.0:
			last_burning = step
	_ok("it runs out %d ticks after the blow (three seconds)" % last_burning, absi(last_burning - _ticks(ConditionDefs.BURN_TIME)) <= 1)
	var landings: Array[int] = []
	var damage_total: float = 0.0
	for step: int in range(2, 200):
		var drop: float = float(_at(common, step - 1)["hp"]) - float(_at(common, step)["hp"])
		if drop > 0.0:
			landings.append(step)
			damage_total += drop
			if not is_equal_approx(drop, roundf(drop)):
				damage_total = INF
	var spaced: bool = true
	for i: int in range(1, landings.size()):
		spaced = spaced and landings[i] - landings[i - 1] >= 29
	_ok("damage lands in whole points, never more often than every half second (landings at %s)" % [landings], spaced and is_finite(damage_total) and landings.size() >= 4)
	var burned: float = float(_at(common, 1)["hp"]) - float(_at(common, 200)["hp"])
	_ok("a three-second burn at 2.9 dps deals 7 points in all (%.0f): the fraction carries over, none is invented" % burned, burned >= 6.0 and burned <= ConditionDefs.burn_dps(7.0, 1) * ConditionDefs.BURN_TIME)
	_ok("rarer swords burn harder (%.0f < %.0f < %.0f points)" % [float(_at(common, 200)["hp"]), float(_at(rare, 200)["hp"]), float(_at(mythic, 200)["hp"])],
		float(_at(common, 1)["hp"]) - float(_at(common, 200)["hp"]) < float(_at(rare, 1)["hp"]) - float(_at(rare, 200)["hp"]) or float(_at(rare, 200)["hp"]) > float(_at(mythic, 200)["hp"]))
	var refresh: Dictionary = _replay("fire", "fire_refresh", "burning refreshed by stronger and weaker blows and renewed after expiry")
	_ok("a stronger blow raises the dps while it burns (%.2f -> %.2f) and a weaker one does not lower it (%.2f)" % [float(_at(refresh, 60)["burn_dps"]), float(_at(refresh, 61)["burn_dps"]), float(_at(refresh, 100)["burn_dps"])],
		_near(float(_at(refresh, 60)["burn_dps"]), float(table["0"]["fire"]), 0.0001) and _near(float(_at(refresh, 61)["burn_dps"]), float(table["2"]["fire"]), 0.0001) and _near(float(_at(refresh, 100)["burn_dps"]), float(table["2"]["fire"]), 0.0001))
	_ok("every application refreshes the timer to three seconds (%.4f after the third)" % float(_at(refresh, 100)["burn"]), _near(float(_at(refresh, 100)["burn"]), ConditionDefs.BURN_TIME - DT, 0.0001))
	_ok("a burn that ran out starts again at the new sword's dps, not the stale stronger one (%.2f)" % float(_at(refresh, 300)["burn_dps"]), float(_at(refresh, 290)["burn"]) <= 0.0 and _near(float(_at(refresh, 300)["burn_dps"]), float(table["0"]["fire"]), 0.0001))
	var stacked: Dictionary = _replay("fire", "fire_dose_stacks", "a three-stack fire dose")
	_ok("stacks of one dose multiply the burn (3 x %.1f = %.1f dps) without lengthening it" % [float(table["0"]["fire"]), float(_at(stacked, 1)["burn_dps"])], _near(float(_at(stacked, 1)["burn_dps"]), float(table["0"]["fire_three_stacks"]), 0.0001))


# ---------------------------------------------------------------- poison
func _check_poison() -> void:
	print("conditions: poison stacks to six and expires")
	var stacks: Dictionary = _replay("poison", "poison_stacks", "nine poison blows ten ticks apart")
	var highest: int = 0
	var never_above_cap: bool = true
	var dps_follows: bool = true
	for step: int in range(1, 400):
		var state: Dictionary = _at(stacks, step)
		highest = maxi(highest, int(state["poison_stacks"]))
		never_above_cap = never_above_cap and int(state["poison_stacks"]) <= ConditionDefs.POISON_MAX
	_ok("stacks grow by one a blow and stop at six although nine blows land (%d)" % highest, highest == ConditionDefs.POISON_MAX and never_above_cap and int(_at(stacks, 12)["poison_stacks"]) == 2 and int(_at(stacks, 52)["poison_stacks"]) == 6 and int(_at(stacks, 82)["poison_stacks"]) == 6)
	var per_stack: float = float(_at(stacks, 2)["poison_dps"])
	_ok("every stack deals the same dps (%.2f per stack) and the timer renews to 4.5 s on each blow (%.4f)" % [per_stack, float(_at(stacks, 81)["poison"])], _near(per_stack, ConditionDefs.poison_dps(7.0), 0.0001) and _near(float(_at(stacks, 81)["poison"]), ConditionDefs.POISON_TIME - DT, 0.0001) and dps_follows)
	var expired: int = _first_step(stacks, 83, func(s: Dictionary) -> bool: return int(s["poison_stacks"]) == 0)
	_ok("all stacks fall away together when the 4.5 s run out, %d ticks after the last blow" % (expired - 81), absi(expired - 81 - _ticks(ConditionDefs.POISON_TIME)) <= 2)
	var damage_after_cap: float = float(_at(stacks, 83)["hp"]) - float(_at(stacks, 300)["hp"])
	_ok("six stacks hurt about six times as much as one: %.0f points in the 7 s after the cap (6 x %.2f dps over the remaining %.1f s)" % [damage_after_cap, per_stack, ConditionDefs.POISON_TIME - 0.0], damage_after_cap > 20.0)
	var rarity: Dictionary = _replay("poison", "poison_rarity", "poison from a common then a mythic then a common sword")
	var table: Dictionary = _ref["table"]["dps_by_rarity"]
	_ok("a mythic sword's stack raises the per-stack dps (%.3f -> %.3f) and a later common blow does not lower it (%.3f)" % [float(_at(rarity, 29)["poison_dps"]), float(_at(rarity, 30)["poison_dps"]), float(_at(rarity, 60)["poison_dps"])],
		_near(float(_at(rarity, 29)["poison_dps"]), float(table["0"]["poison"]), 0.0001) and _near(float(_at(rarity, 30)["poison_dps"]), float(table["2"]["poison"]), 0.0001) and _near(float(_at(rarity, 60)["poison_dps"]), float(table["2"]["poison"]), 0.0001))
	_ok("after it ran out, poison starts again from one stack at the new sword's dps (%.3f, %d stack)" % [float(_at(rarity, 400)["poison_dps"]), int(_at(rarity, 400)["poison_stacks"])],
		_near(float(_at(rarity, 400)["poison_dps"]), float(table["0"]["poison"]), 0.0001) and int(_at(rarity, 400)["poison_stacks"]) == 1)


# ------------------------------------------------------------------- ice
func _check_ice() -> void:
	print("conditions: ice chills, freezes at four stacks, thaws and expires")
	var freeze: Dictionary = _replay("ice", "ice_freeze", "ice blows: chill, freeze, frozen blows, thaw, chill again")
	var stacks_by_hit: Array[int] = [int(_at(freeze, 1)["chill_stacks"]), int(_at(freeze, 11)["chill_stacks"]), int(_at(freeze, 21)["chill_stacks"]), int(_at(freeze, 31)["chill_stacks"])]
	_ok("each blow adds a chill stack (%s) and the fourth freezes the enemy and clears them" % [stacks_by_hit], stacks_by_hit == [1, 2, 3, 0] and float(_at(freeze, 30)["frozen"]) == 0.0 and _near(float(_at(freeze, 31)["frozen"]), ConditionDefs.FREEZE_TIME - DT, 0.0001))
	_ok("chill lasts 2.5 s from the latest blow (%.4f)" % float(_at(freeze, 21)["chill"]), _near(float(_at(freeze, 21)["chill"]), ConditionDefs.CHILL_TIME - DT, 0.0001))
	_ok("blows on a frozen enemy refresh the chill (%.4f) but add no stacks (%d) and do not extend the freeze (%.4f left)" % [float(_at(freeze, 41)["chill"]), int(_at(freeze, 51)["chill_stacks"]), float(_at(freeze, 51)["frozen"])],
		_near(float(_at(freeze, 41)["chill"]), ConditionDefs.CHILL_TIME - DT, 0.0001) and int(_at(freeze, 41)["chill_stacks"]) == 0 and int(_at(freeze, 51)["chill_stacks"]) == 0 and float(_at(freeze, 51)["frozen"]) < float(_at(freeze, 41)["frozen"]))
	var thaw: int = _first_step(freeze, 32, func(s: Dictionary) -> bool: return float(s["frozen"]) <= 0.0)
	_ok("the freeze ends %d ticks after it began (1.6 s)" % (thaw - 31), absi(thaw - 31 - _ticks(ConditionDefs.FREEZE_TIME)) <= 1)
	var dealt: Array = freeze["dealt"]
	_ok("a frozen enemy takes 9 from a 7 blow (bonus 1.3, rounded), an unfrozen one 7 (%s)" % [[(dealt[3] as Dictionary)["dealt"], (dealt[4] as Dictionary)["dealt"]]], float((dealt[3] as Dictionary)["dealt"]) == 7.0 and float((dealt[4] as Dictionary)["dealt"]) == 9.0 and float((dealt[5] as Dictionary)["dealt"]) == 9.0 and float((dealt[6] as Dictionary)["dealt"]) == 7.0)
	_ok("after the thaw the chill count starts over: one stack per blow again, a second freeze on the fourth (%d, %d, %d, %.2f)" % [int(_at(freeze, 140)["chill_stacks"]), int(_at(freeze, 150)["chill_stacks"]), int(_at(freeze, 160)["chill_stacks"]), float(_at(freeze, 170)["frozen"])],
		int(_at(freeze, 140)["chill_stacks"]) == 1 and int(_at(freeze, 150)["chill_stacks"]) == 2 and int(_at(freeze, 160)["chill_stacks"]) == 3 and _near(float(_at(freeze, 170)["frozen"]), ConditionDefs.FREEZE_TIME - DT, 0.0001) and int(_at(freeze, 170)["chill_stacks"]) == 0)
	var brute: Dictionary = _replay("ice", "ice_brute", "ice blows on a brute")
	var brute_frozen: float = float(_at(brute, 31)["frozen"])
	_ok("a brute freezes for 0.6 of the time (%.4f s, a husk 1.6 s)" % [brute_frozen + DT], _near(brute_frozen + DT, ConditionDefs.FREEZE_TIME * 0.6, 0.0001))
	var brute_thaw: int = _first_step(brute, 32, func(s: Dictionary) -> bool: return float(s["frozen"]) <= 0.0)
	_ok("and thaws %d ticks later (0.96 s)" % (brute_thaw - 31), absi(brute_thaw - 31 - _ticks(ConditionDefs.FREEZE_TIME * 0.6)) <= 1)
	var expiry: Dictionary = _replay("ice", "ice_chill_expiry", "two ice blows left to expire")
	var chill_gone: int = _first_step(expiry, 12, func(s: Dictionary) -> bool: return float(s["chill"]) <= 0.0)
	_ok("the chill and its stacks vanish together 2.5 s after the last blow (stacks %d at tick %d)" % [int(_at(expiry, 11)["chill_stacks"]), chill_gone], int(_at(expiry, 11)["chill_stacks"]) == 2 and absi(chill_gone - 11 - _ticks(ConditionDefs.CHILL_TIME)) <= 1 and int(_at(expiry, chill_gone)["chill_stacks"]) == 0)
	var types: Dictionary = _replay("ice", "ice_freeze_runner", "runners and spitters freezing like husks")
	_ok("a runner and a spitter freeze for the full 1.6 s on the fourth blow", _near(float(_at(types, 31, 0)["frozen"]) + DT, ConditionDefs.FREEZE_TIME, 0.0001) and _near(float(_at(types, 31, 1)["frozen"]) + DT, ConditionDefs.FREEZE_TIME, 0.0001))


# --------------------------------------------------------- frozen bonus
func _check_frozen_bonus() -> void:
	print("conditions: the frozen damage bonus and its rounding")
	var frozen: Dictionary = _replay("frozen_bonus", "frozen", "thirty blows on frozen enemies")
	var plain: Dictionary = _replay("frozen_bonus", "plain", "the same thirty blows on unfrozen enemies")
	var raws: Array = (_ref["frozen_bonus"]["frozen"] as Dictionary)["raws"]
	var rounding_ok: bool = true
	var detail: String = ""
	var frozen_dealt: Array = frozen["dealt"]
	var plain_dealt: Array = plain["dealt"]
	for i: int in frozen_dealt.size():
		var raw: float = float(raws[i / 2]) * (2.0 if i % 2 == 1 else 1.0)
		var want_frozen: float = float(maxi(1, SimMath.py_round(raw * ConditionDefs.SHATTER)))
		var want_plain: float = float(maxi(1, SimMath.py_round(raw)))
		if float((frozen_dealt[i] as Dictionary)["dealt"]) != want_frozen or float((plain_dealt[i] as Dictionary)["dealt"]) != want_plain:
			rounding_ok = false
			detail += " raw %.2f: frozen %s (want %s), plain %s (want %s)" % [raw, (frozen_dealt[i] as Dictionary)["dealt"], want_frozen, (plain_dealt[i] as Dictionary)["dealt"], want_plain]
	_ok("every blow deals max(1, round(raw x 2 if critical x 1.3 if frozen)) with Python's round-half-even: 5 -> 6 (6.5), 15 -> 20 (19.5), 25 -> 32 (32.5) frozen%s" % detail, rounding_ok)
	var five_frozen: float = float((frozen_dealt[8] as Dictionary)["dealt"])
	var twenty_five: float = float((frozen_dealt[24] as Dictionary)["dealt"])
	_ok("the halves round to even in both directions (5 x 1.3 = 6.5 -> %.0f, 25 x 1.3 = 32.5 -> %.0f)" % [five_frozen, twenty_five], five_frozen == 6.0 and twenty_five == 32.0)
	var kill: Dictionary = _replay("frozen_bonus", "kill_through_bonus", "a blow made lethal by the bonus")
	_ok("a 5-damage blow kills a frozen 6-health enemy (5 x 1.3 = 6.5 -> 6) but not an unfrozen one, which keeps 1 health", bool(_at(kill, 1, 0)["dead"]) and not bool(_at(kill, 1, 1)["dead"]) and float(_at(kill, 1, 1)["hp"]) == 1.0 and (kill["run"] as GameRun).kills == 1)
	var stays: Dictionary = _replay("frozen_bonus", "frozen_stays_frozen", "blows on a frozen enemy")
	_ok("a blow does not end the freeze (%.4f s left after the third)" % float(_at(stays, 41)["frozen"]), float(_at(stays, 41)["frozen"]) > 0.0 and _near(float(_at(stays, 1)["frozen"]), 1.0 - DT, 0.0001) and float(_at(stays, 62)["frozen"]) == 0.0)


# ------------------------------------------------------- frozen contact
func _check_frozen_contact() -> void:
	print("conditions: a frozen enemy cannot hurt the player by contact")
	var plain: Dictionary = _replay("frozen_contact", "plain", "an overlapping husk")
	var frozen: Dictionary = _replay("frozen_contact", "frozen", "an overlapping husk frozen for a second")
	var thawed: Dictionary = _replay("frozen_contact", "frozen_then_thawed", "an overlapping husk frozen for half a second")
	var plain_run: GameRun = plain["run"]
	var frozen_run: GameRun = frozen["run"]
	var hp_by_tick: Array[float] = []
	var first_hurt: int = -1
	var record_frozen: Array = frozen["record"]
	var frozen_run_probe: GameRun = GameRun.new(_scenario_of((_ref["frozen_contact"]["frozen"] as Dictionary)["spec"] as Dictionary))
	frozen_run_probe.enemies[0].conditions.frozen = 1.0
	for step: int in range(1, 100):
		frozen_run_probe.step()
		hp_by_tick.append(frozen_run_probe.hp)
		if first_hurt < 0 and frozen_run_probe.hp < GameRun.PLAYER_MAX_HP:
			first_hurt = step
	_ok("the player is untouched while the husk is frozen and hurt the moment it thaws (first damage at tick %d, 1 s is tick 60)" % first_hurt, first_hurt >= 59 and first_hurt <= 61 and hp_by_tick[0] == GameRun.PLAYER_MAX_HP and hp_by_tick[57] == GameRun.PLAYER_MAX_HP)
	_ok("an unfrozen overlapping husk hurts at once for its 10 damage (%.0f)" % plain_run.hp, float(((plain["record"] as Array)[1] as Array).size()) == 1 and _near(plain_run.hp, 90.0, 0.01) and not frozen_run.dead)
	_ok("a frozen enemy is not shoved by the contact either: it stays put until the thaw (x %.2f, %.2f)" % [float(_at(frozen, 1)["x"]), float(_at(frozen, 50)["x"])], _near(float(_at(frozen, 1)["x"]), float(_at(frozen, 50)["x"]), 1.0) and record_frozen.size() > 50)
	var thawed_run: GameRun = thawed["run"]
	_ok("a short freeze ends and the contact resumes: the player ends the half-second case hurt (%.0f)" % thawed_run.hp, thawed_run.hp < GameRun.PLAYER_MAX_HP)


# ---------------------------------------------------- motion and clocks
func _check_motion_and_clocks() -> void:
	print("conditions: chill slows, a frozen enemy stops steering and its clock stops")
	var chilled: Dictionary = _replay("motion", "chilled_walk", "a chilled husk walking at the player")
	var plain: Dictionary = _replay("motion", "plain_walk", "an unchilled husk walking at the player")
	var start_x: float = float((((_ref["motion"] as Dictionary)["plain_walk"] as Dictionary)["spec"]["enemies"] as Array)[0]["x"])
	var chilled_run: float = start_x - float(_at(chilled, 141)["x"])
	var plain_run: float = start_x - float(_at(plain, 141)["x"])
	_ok("while chilled it advances at about half the pace (%.0f px in 2.3 s against %.0f)" % [chilled_run, plain_run], chilled_run < plain_run * 0.6 and chilled_run > plain_run * 0.4)
	var after: float = (float(_at(chilled, 241)["x"]) - float(_at(chilled, 161)["x"])) / (float(_at(plain, 241)["x"]) - float(_at(plain, 161)["x"]))
	_ok("and when the chill has expired it walks at full pace again (%.2f of the control's speed over the next 1.3 s)" % after, after > 0.9 and after < 1.2)
	_replay("motion", "chilled_runner", "a chilled runner weaving")
	var frozen_runner: Dictionary = _replay("motion", "frozen_runner", "a frozen runner coasting")
	_ok("a frozen enemy's own clock waits for the thaw (%.4f at tick 51, %.4f at 61, %.4f at 71)" % [float(_at(frozen_runner, 51)["t"]), float(_at(frozen_runner, 61)["t"]), float(_at(frozen_runner, 71)["t"])],
		float(_at(frozen_runner, 51)["t"]) == 0.0 and float(_at(frozen_runner, 71)["t"]) > 0.1)
	var plain_spitter: Dictionary = _replay("motion", "spitter_plain", "a spitter free to shoot")
	var frozen_spitter: Dictionary = _replay("motion", "spitter_frozen", "a spitter frozen for a second")
	var shot_free: int = int((plain_spitter["first_cue_step"] as Dictionary).get(SimCue.Kind.PROJECTILE_FIRED, -1))
	var shot_frozen: int = int((frozen_spitter["first_cue_step"] as Dictionary).get(SimCue.Kind.PROJECTILE_FIRED, -1))
	_ok("a frozen spitter holds its fire: its first orb comes %d ticks after the free one (%d vs %d), the length of the freeze" % [shot_frozen - shot_free, shot_frozen, shot_free], absi(shot_frozen - shot_free - 60) <= 2 and shot_free > 0)


# --------------------------------------------------- mixed and cadence
func _check_mixed_and_cadence() -> void:
	print("conditions: mixed conditions and the damage-over-time cadence")
	var mixed: Dictionary = _replay("mixed", "fire_poison_ice", "poison, fire and ice on one enemy")
	var c: Dictionary = _at(mixed, 6)
	_ok("three conditions coexist (burn %.2f s at %.2f dps, %d poison stacks, %d chill stacks) and their dps add up in one accumulator" % [float(c["burn"]), float(c["burn_dps"]), int(c["poison_stacks"]), int(c["chill_stacks"])],
		float(c["burn"]) > 0.0 and int(c["poison_stacks"]) == 3 and int(c["chill_stacks"]) == 2)
	var on_frozen: Dictionary = _replay("mixed", "dot_on_frozen", "poison on a frozen enemy")
	_ok("damage over time is not boosted by the freeze: it lands in the same whole points as on an unfrozen enemy", float(_at(on_frozen, 1)["frozen"]) > 0.0 and float(_at(on_frozen, 200)["hp"]) < float(_at(on_frozen, 1)["hp"]))
	var reset: Dictionary = _replay("mixed", "accumulator_resets", "poison left to run out")
	_ok("when nothing is left to tick the accumulator is wiped (%.4f)" % float(_at(reset, 300)["dot"]), float(_at(reset, 300)["dot"]) == 0.0 and int(_at(reset, 300)["poison_stacks"]) == 0)


# ----------------------------------------------------------------- spread
func _check_spread() -> void:
	print("conditions: a burning death spreads fire to its neighbours")
	var fire: Dictionary = _replay("spread", "burning_death", "a burning husk killed among neighbours")
	var run: GameRun = fire["run"]
	var source_dps: float = ConditionDefs.burn_dps(7.0, 1)
	var spread_dps: float = source_dps * ConditionDefs.SPREAD_DPS_FACTOR
	var at: Callable = func(index: int) -> Dictionary: return _at(fire, 33, index)
	_ok("a husk 101 px away (inside the 102 px reach) is set alight at 0.6 of the dead one's dps (%.3f) for at least 2.1 s" % float((at.call(1) as Dictionary)["burn_dps"]),
		_near(float((at.call(1) as Dictionary)["burn_dps"]), spread_dps, 0.0001) and _near(float((at.call(1) as Dictionary)["burn"]), ConditionDefs.BURN_TIME * ConditionDefs.SPREAD_TIME_FACTOR - 3.0 * DT, 0.0001))
	_ok("a husk 103 px away is not (%.1f)" % float((at.call(2) as Dictionary)["burn"]), float((at.call(2) as Dictionary)["burn"]) == 0.0)
	_ok("a brute 115 px away (inside 16 + 30 + 70 = 116) is ignited, one 117 px away is not", float((at.call(3) as Dictionary)["burn"]) > 0.0 and float((at.call(4) as Dictionary)["burn"]) == 0.0)
	_ok("a neighbour already burning harder keeps its own dps (%.2f); one burning weaker is raised to the spread dps (%.2f)" % [float((at.call(5) as Dictionary)["burn_dps"]), float((at.call(6) as Dictionary)["burn_dps"])],
		_near(float((at.call(5) as Dictionary)["burn_dps"]), ConditionDefs.burn_dps(30.0, 1), 0.0001) and _near(float((at.call(6) as Dictionary)["burn_dps"]), spread_dps, 0.0001))
	_ok("a neighbour that was already burning keeps the longer of its timer and the spread's (%.2f s)" % float((at.call(5) as Dictionary)["burn"]), float((at.call(5) as Dictionary)["burn"]) > ConditionDefs.BURN_TIME * ConditionDefs.SPREAD_TIME_FACTOR)
	_ok("the dead neighbour is not ignited and the dead victim's fire is spent: two deaths, six motes (kills %d, motes %d)" % [run.kills, run.motes.size()], run.kills == 2 and run.cue_count(SimCue.Kind.ENEMY_KILLED) == 2 and bool(_at(fire, 33, 7)["dead"]) and float(_at(fire, 33, 7)["burn"]) == 0.0)
	var poison: Dictionary = _replay("spread", "poison_death_no_spread", "a poisoned and chilled husk killed beside a neighbour")
	_ok("a death without burning spreads no fire", float(_at(poison, 12, 1)["burn"]) == 0.0 and bool(_at(poison, 12, 0)["dead"]) and (poison["run"] as GameRun).cue_count(SimCue.Kind.FIRE_SPREAD) == 0)
	var killing: Dictionary = _replay("spread", "killing_blow_no_ignite", "a fire sword's killing blow")
	_ok("a blow that kills afflicts nothing: no burn on the victim, no spread to the neighbour", float(_at(killing, 2, 0)["burn"]) == 0.0 and float(_at(killing, 2, 1)["burn"]) == 0.0 and (killing["run"] as GameRun).cue_count(SimCue.Kind.FIRE_SPREAD) == 0)
	var blow: Dictionary = _replay("spread", "fire_blow_then_death", "a fire blow that leaves the victim alive, then its death")
	_ok("a fire blow that leaves the victim alive ignites it, and its death then spreads (%.2f dps to the neighbour)" % float(_at(blow, 6, 1)["burn_dps"]), float(_at(blow, 4, 0)["burn"]) > 0.0 and _near(float(_at(blow, 6, 1)["burn_dps"]), spread_dps, 0.0001) and (blow["run"] as GameRun).cue_count(SimCue.Kind.FIRE_SPREAD) == 1)


func _check_chain() -> void:
	print("conditions: spread chains advance one death at a time")
	var chain: Dictionary = _replay("chain", "chain", "five husks in a row, the first burning and killed")
	var run: GameRun = chain["run"]
	var death_steps: Array[int] = []
	for index: int in 6:
		death_steps.append(_first_step(chain, 1, func(s: Dictionary) -> bool: return bool(s["dead"]), index))
	_ok("the victim dies at once, then the neighbours die by their own burns in order (ticks %s)" % [death_steps], death_steps[0] == 2 and death_steps[1] > death_steps[0] and death_steps[2] > death_steps[1] and death_steps[3] == -1 and death_steps[4] == -1 and death_steps[5] == -1)
	var dps: Array[float] = []
	for index: int in 4:
		dps.append(float(_at(chain, 3 if index == 0 else death_steps[index] - 1, index)["burn_dps"]))
	var factor_ok: bool = true
	for index: int in range(1, 3):
		factor_ok = factor_ok and _near(float(_at(chain, death_steps[index - 1] + 1, index)["burn_dps"]), dps[index - 1] * ConditionDefs.SPREAD_DPS_FACTOR, 0.0001) if index > 1 else factor_ok
	_ok("each link burns at 0.6 of the one before (%s) and the chain ends where the burn is too weak to kill (the fourth survives with 1 health)" % [dps], _near(dps[1], dps[0] * 0.6, 0.0001) and _near(float(_at(chain, death_steps[2] - 1, 2)["burn_dps"]), dps[0] * 0.36, 0.0001) and factor_ok and float(_at(chain, 420, 3)["hp"]) == 1.0 and not bool(_at(chain, 420, 3)["dead"]))
	_ok("every death in the chain resolved exactly once: three kills, three kill cues and three fire-spread cues (kills %d, cues %d)" % [run.kills, run.cue_count(SimCue.Kind.ENEMY_KILLED)], run.kills == 3 and run.cue_count(SimCue.Kind.ENEMY_KILLED) == 3 and run.cue_count(SimCue.Kind.FIRE_SPREAD) == 3)


# ------------------------------------------------- deaths exactly once
func _check_deaths_exactly_once() -> void:
	print("conditions: deaths during ongoing effects resolve exactly once")
	var dot: Dictionary = _replay("deaths", "dot_kill", "poison finishing an enemy")
	var run: GameRun = dot["run"]
	_ok("damage over time kills exactly once: one kill, one kill cue (kills %d, cues %d)" % [run.kills, run.cue_count(SimCue.Kind.ENEMY_KILLED)], run.kills == 1 and run.cue_count(SimCue.Kind.ENEMY_KILLED) == 1 and run.combo == 1 and run.enemies.is_empty())
	var two: Dictionary = _replay("deaths", "two_dot_kills", "two enemies dying on the same tick")
	var two_run: GameRun = two["run"]
	_ok("two enemies dying on one tick are two kills (%d), each rewarded once" % two_run.kills, two_run.kills == 2 and two_run.cue_count(SimCue.Kind.ENEMY_KILLED) == 2 and two_run.combo == 2)
	var before: Dictionary = _replay("deaths", "hit_before_dot", "a blow killing an enemy as its poison would land")
	var before_run: GameRun = before["run"]
	_ok("a blow that kills just before the damage over time lands leaves it nothing to kill: one kill (%d), one cue" % before_run.kills, before_run.kills == 1 and before_run.cue_count(SimCue.Kind.ENEMY_KILLED) == 1)
	var frozen: Dictionary = _replay("deaths", "poison_kills_frozen", "poison finishing a frozen enemy")
	var frozen_run: GameRun = frozen["run"]
	_ok("a frozen enemy killed by poison dies once and shatters (kills %d, shatter cues %d)" % [frozen_run.kills, frozen_run.cue_count(SimCue.Kind.ENEMY_SHATTERED)], frozen_run.kills == 1 and frozen_run.cue_count(SimCue.Kind.ENEMY_SHATTERED) == 1 and frozen_run.cue_count(SimCue.Kind.ENEMY_KILLED) == 1)
	var burning: Dictionary = _replay("deaths", "burning_poison_death", "a burning enemy killed by poison")
	var burning_run: GameRun = burning["run"]
	_ok("a burning enemy that poison kills still sets its neighbour alight (burn %.2f s on the neighbour, one kill)" % float(_at(burning, 59, 1)["burn"]), float(_at(burning, 59, 1)["burn"]) > 0.0 and burning_run.kills == 1 and burning_run.cue_count(SimCue.Kind.FIRE_SPREAD) == 1)
	# a condition death while a Viper Flurry has the enemy as its victim: no strike on the corpse, no second kill
	var scenario: RunScenario = RunScenario.new()
	scenario.seed = 62
	scenario.waves_enabled = false
	scenario.crit_chance = 0.0
	var specs: Array[SwordSpec] = [SwordSpec.make(&"fang", 0, &"fire")]
	scenario.loadout = specs
	var cooldowns: Array[float] = [PARKED]
	scenario.sword_start_cooldowns = cooldowns
	var center: Vector2 = scenario.start_position + Vector2(260.0, 0.0)
	var placements: Array[EnemyPlacement] = []
	for offset: Vector2 in [Vector2(-40.0, 0.0), Vector2(40.0, 30.0), Vector2(0.0, -50.0), Vector2(30.0, 60.0)]:
		var placement: EnemyPlacement = EnemyPlacement.make(EnemyDefs.HUSK, center + offset)
		placement.speed_scale = 0.0
		placement.hp = 40.0
		placements.append(placement)
	scenario.initial_enemies = placements
	var flurry_run: GameRun = GameRun.new(scenario)
	var all: Array[EnemyState] = flurry_run.enemies.duplicate()
	for enemy: EnemyState in all:
		flurry_run.afflict(enemy, &"fire", 40.0, 2)
		flurry_run.afflict(enemy, &"poison", 40.0, 6)
	flurry_run.try_ultimate(0, center)
	var kills_seen: int = 0
	var leftovers: bool = false
	for step: int in 300:
		flurry_run.step()
		for cue: SimCue in flurry_run.take_cues():
			kills_seen += 1 if cue.kind == SimCue.Kind.ENEMY_KILLED else 0
		leftovers = leftovers or flurry_run.enemies.any(func(e: EnemyState) -> bool: return e.dead)
	_ok("enemies dying of burn and poison while a flurry is chasing them: each dies once (%d kills for %d enemies, %d cues), none lingers dead in the run" % [flurry_run.kills, all.size(), kills_seen], flurry_run.kills == all.size() and kills_seen == all.size() and not leftovers and flurry_run.enemies.is_empty())


# ----------------------------------------------- swords end to end
func _check_sword_hits() -> void:
	print("conditions: each sword's own blows apply its own element")
	var elements: Dictionary = {}
	for label: String in ["poison", "ice", "fire"]:
		var played: Dictionary = _replay("sword_hits", label, "the %s sword's automatic attack" % label)
		var first: int = int(((_ref["sword_hits"] as Dictionary)[label] as Dictionary)["first_hit"])
		elements[label] = _at(played, first)
		_ok("its first blow lands on tick %d (the reference's) and afflicts one dose" % first, absi(_first_step(played, 1, func(s: Dictionary) -> bool: return float(s["hp"]) < 500.0) - first) <= 1)
	_ok("the poison sword poisons (1 stack), the ice sword chills (1 stack), the fire sword burns, and none applies another element",
		int((elements["poison"] as Dictionary)["poison_stacks"]) == 1 and float((elements["poison"] as Dictionary)["burn"]) == 0.0 and float((elements["poison"] as Dictionary)["chill"]) == 0.0
		and int((elements["ice"] as Dictionary)["chill_stacks"]) == 1 and float((elements["ice"] as Dictionary)["poison"]) == 0.0 and float((elements["ice"] as Dictionary)["burn"]) == 0.0
		and float((elements["fire"] as Dictionary)["burn"]) > 0.0 and float((elements["fire"] as Dictionary)["poison"]) == 0.0 and float((elements["fire"] as Dictionary)["chill"]) == 0.0)


func _check_flurry_darts() -> void:
	print("conditions: Viper Flurry darts apply their sword's element, one dose per dart")
	var poison: Dictionary = _replay("flurry", "poison", "a poison sword's Viper Flurry on one enemy")
	var ice: Dictionary = _replay("flurry", "ice", "an ice sword's Viper Flurry on one enemy")
	var fire: Dictionary = _replay("flurry", "fire", "a fire sword's Viper Flurry on one enemy")
	var first_dart: int = _first_step(poison, 1, func(s: Dictionary) -> bool: return float(s["hp"]) < 5000.0)
	var stack_run: Array[int] = []
	for step: int in range(first_dart, first_dart + 40):
		stack_run.append(int(_at(poison, step)["poison_stacks"]))
	_ok("every dart adds one poison stack, six at most (%s)" % [stack_run.slice(0, 20)], stack_run[0] == 1 and stack_run.max() == ConditionDefs.POISON_MAX and stack_run.min() >= 1)
	var freeze_step: int = _first_step(ice, 1, func(s: Dictionary) -> bool: return float(s["frozen"]) > 0.0)
	var darts_before: int = 0
	var last_hp: float = 5000.0
	for step: int in range(1, freeze_step + 1):
		var hp: float = float(_at(ice, step)["hp"])
		if hp < last_hp:
			darts_before += 1
		last_hp = hp
	_ok("the fourth dart freezes the enemy (%d darts landed, frozen at tick %d) and the darts after it deal the shattered 11 instead of 8" % [darts_before, freeze_step], darts_before == ConditionDefs.FREEZE_STACKS and float(_at(ice, freeze_step + 9)["hp"]) < float(_at(ice, freeze_step)["hp"]))
	var shattered: bool = false
	var drops: Array[float] = []
	last_hp = float(_at(ice, freeze_step)["hp"])
	for step: int in range(freeze_step + 1, 130):
		var hp: float = float(_at(ice, step)["hp"])
		if hp < last_hp:
			drops.append(last_hp - hp)
			shattered = true
		last_hp = hp
	_ok("darts on the frozen enemy deal %s: 8.4 x 1.3 rounds to 11" % [drops.slice(0, 4)], shattered and float(drops[0]) == 11.0)
	_ok("the fire sword's darts keep the burn refreshed to three seconds", float(_at(fire, 40)["burn"]) > ConditionDefs.BURN_TIME - 0.5 and float(_at(fire, 40)["burn_dps"]) > 0.0)


# ------------------------------------------------- entry points, flag
func _check_afflict_entry_and_fixture_flag() -> void:
	print("conditions: the afflict entry point (shared with fields) and the condition-free fixture")
	var scenario: RunScenario = RunScenario.new()
	scenario.waves_enabled = false
	var specs: Array[SwordSpec] = []
	scenario.loadout = specs
	var enemies: Array[EnemyPlacement] = [EnemyPlacement.make(EnemyDefs.HUSK, scenario.start_position + Vector2(400.0, 0.0)), EnemyPlacement.make(EnemyDefs.BRUTE, scenario.start_position + Vector2(-400.0, 0.0))]
	scenario.initial_enemies = enemies
	var run: GameRun = GameRun.new(scenario)
	var husk: EnemyState = run.enemies[0]
	var brute: EnemyState = run.enemies[1]
	for i: int in 4:
		run.afflict(husk, &"ice", 0.0)
		run.afflict(brute, &"ice", 0.0)
	_ok("a field-style dose (no sword, power given) chills and freezes through the same path: %.2f s on a husk, %.2f s on a brute" % [husk.conditions.frozen, brute.conditions.frozen], _near(husk.conditions.frozen, ConditionDefs.FREEZE_TIME, 0.0001) and _near(brute.conditions.frozen, ConditionDefs.FREEZE_TIME * 0.6, 0.0001))
	run.afflict(husk, &"fire", 25.0, 1)
	run.afflict(husk, &"poison", 25.0, 2)
	_ok("fire and poison doses use the given power (burn %.1f dps, poison %.2f per stack x %d)" % [husk.conditions.burn_dps, husk.conditions.poison_dps, husk.conditions.poison_stacks], _near(husk.conditions.burn_dps, ConditionDefs.burn_dps(25.0, 1), 0.0001) and _near(husk.conditions.poison_dps, ConditionDefs.poison_dps(25.0), 0.0001) and husk.conditions.poison_stacks == 2)
	var cues: int = run.cue_count(SimCue.Kind.ENEMY_FROZEN)
	_ok("each freeze is announced once (%d cues for two freezes)" % cues, cues == 2)
	run.afflict(husk, &"shadow", 25.0)
	run.kill(husk, Vector2.RIGHT)
	var burn_before: float = husk.conditions.burn
	run.afflict(husk, &"fire", 99.0)
	_ok("an unknown element does nothing, and a dead enemy takes no dose (burn stays %.2f)" % husk.conditions.burn, husk.conditions.burn == burn_before)
	var fixture: RunScenario = scenario
	fixture.without_conditions()
	var plain_run: GameRun = GameRun.new(fixture)
	plain_run.afflict(plain_run.enemies[0], &"fire", 7.0)
	plain_run.afflict(plain_run.enemies[0], &"poison", 7.0)
	plain_run.afflict(plain_run.enemies[0], &"ice", 7.0)
	var plain_conditions: EnemyConditions = plain_run.enemies[0].conditions
	_ok("a condition-free fixture (the earlier slices' references were captured without them) applies nothing", not plain_conditions.is_burning() and plain_conditions.poison <= 0.0 and plain_conditions.chill <= 0.0)
	_ok("the game's own scenarios apply conditions: the default, the crowd, the spitters and the conditions encounter", RunScenario.new().conditions_enabled and RunScenario.crowd_encounter().conditions_enabled and RunScenario.spitter_encounter().conditions_enabled and RunScenario.conditions_encounter().conditions_enabled and RunScenario.wall_encounter().conditions_enabled)
	var swords: GameRun = GameRun.new(RunScenario.new())
	var elements: Array[StringName] = []
	for sword: SwordState in swords.swords:
		elements.append(sword.spec.element)
	_ok("the fixture loadout fields the three elements (poison, ice, fire)", elements == [&"poison", &"ice", &"fire"])


# --------------------------------------------------- the first wave
func _check_survival_band() -> void:
	print("conditions: the first wave against three elemental Fangs (reference captured with conditions on)")
	var survival_ref: Array = _ref["survival"]["wave1_three_fangs_stationary_player"]
	var lowest: float = INF
	var highest: float = 0.0
	for entry: Dictionary in survival_ref:
		lowest = minf(lowest, float(entry["cleared_at"]))
		highest = maxf(highest, float(entry["cleared_at"]))
	var all_survived: bool = true
	var in_band: bool = true
	var minimum_hp: float = 100.0
	var times: Array[float] = []
	for seed_value: int in range(1, 9):
		var scenario: RunScenario = RunScenario.new()
		scenario.seed = seed_value
		var run: GameRun = GameRun.new(scenario)
		var ticks_taken: int = 0
		while run.outcome() == GameRun.Outcome.RUNNING and ticks_taken < 60 * 60:
			run.step()
			ticks_taken += 1
		var seconds: float = float(ticks_taken) / 60.0
		times.append(seconds)
		all_survived = all_survived and run.outcome() == GameRun.Outcome.SURVIVED and run.kills == 8 and not run.dead and run.enemies.is_empty()
		in_band = in_band and seconds > lowest - 1.0 and seconds < highest + 1.0
		minimum_hp = minf(minimum_hp, run.hp)
	_ok("with the conditions on, the three-Fang fixture still clears the wave on all 8 seeds with all 8 kills", all_survived)
	_ok("and clears it inside the conditions-on reference band %.1f-%.1f s +-1 s (%s)" % [lowest, highest, times], in_band)
	_ok("the player stays healthy (lowest health %.1f)" % minimum_hp, minimum_hp > 40.0)


# ------------------------------------------------------------------ cues
func _check_cues() -> void:
	print("conditions: cues announce conditions without driving them")
	var run: GameRun = GameRun.new(_scenario_of((_ref["chain"]["chain"] as Dictionary)["spec"] as Dictionary))
	var husk: EnemyState = run.enemies[0]
	run.afflict(husk, &"fire", 7.0)
	run.afflict(run.enemies[0], &"ice", 7.0, 4)
	var cues: Array[SimCue] = run.take_cues()
	_ok("freezing produces one ENEMY_FROZEN cue at the enemy carrying the ice element", cues.size() == 1 and cues[0].kind == SimCue.Kind.ENEMY_FROZEN and cues[0].element == &"ice" and cues[0].position == husk.position)
	run.hit_enemy(husk, 7.0, Vector2.RIGHT, 0.0, null, true)
	var hit_cues: Array[SimCue] = run.take_cues()
	_ok("a blow on a frozen enemy is cued as ice-struck with its 9 damage", hit_cues.size() == 1 and hit_cues[0].kind == SimCue.Kind.ENEMY_HIT and hit_cues[0].element == &"ice" and hit_cues[0].amount == 9)
	var damage_cues: int = 0
	var damage_sum: int = 0
	var hp_before: float = husk.hp
	for step: int in 200:
		run.step()
		for cue: SimCue in run.take_cues():
			if cue.kind == SimCue.Kind.CONDITION_DAMAGE and cue.position == husk.position:
				damage_cues += 1
				damage_sum += cue.amount
				if cue.element != &"fire":
					damage_sum = -999999
	_ok("every burn landing is one cue with its points (%d cues, %d points = the %.0f health the burn took)" % [damage_cues, damage_sum, hp_before - husk.hp], damage_cues >= 4 and float(damage_sum) == hp_before - husk.hp)
	# Cosmetic cues never touch the run: applying every cue kind to an effects layer leaves the run as it was
	var layer: EffectsLayer = EffectsLayer.new()
	var fresh: GameRun = GameRun.new(_scenario_of((_ref["chain"]["chain"] as Dictionary)["spec"] as Dictionary))
	layer.sync(fresh)
	var before: Dictionary = fresh.snapshot()
	for kind: SimCue.Kind in [SimCue.Kind.ENEMY_FROZEN, SimCue.Kind.ENEMY_SHATTERED, SimCue.Kind.CONDITION_DAMAGE, SimCue.Kind.FIRE_SPREAD]:
		var cue: SimCue = SimCue.make(kind, Vector2(100.0, 100.0), Vector2.ZERO, 3)
		cue.element = &"fire"
		layer.apply_cue(cue)
	_ok("the effects layer shows frozen, shatter, damage and spread cues (%d rings, %d texts, %d element particles) and the run is untouched" % [layer._rings.size(), layer._texts.size(), layer._embers.size()],
		layer._rings.size() >= 2 and layer._texts.size() >= 2 and layer._embers.size() >= 14 and fresh.snapshot() == before)
	layer.free()


func _check_conditions_encounter() -> void:
	print("conditions: the dev encounter shows them")
	var scenario: RunScenario = RunScenario.conditions_encounter()
	var brutes: int = scenario.wave_kinds.count(EnemyDefs.BRUTE)
	_ok("the conditions encounter is one wave of %d husks, %d runners and %d brutes against the three-Fang fixture loadout" % [scenario.wave_kinds.count(EnemyDefs.HUSK), scenario.wave_kinds.count(EnemyDefs.RUNNER), brutes],
		scenario.wave_kinds.size() == 12 and brutes == 2 and scenario.loadout.size() == 3 and scenario.waves_enabled and scenario.encounter == RunScenario.ENCOUNTER_CONDITIONS and scenario.conditions_enabled and not scenario.dev_shove)
	var launched: RunScenario = LaunchOptions.scenario_for("conditions")
	_ok("--encounter=conditions and ?encounter=conditions ask for it", launched != null and launched.encounter == RunScenario.ENCOUNTER_CONDITIONS)
	scenario.seed = 31
	scenario.first_wave_delay = 0.2
	var run: GameRun = GameRun.new(scenario)
	var burning: int = 0
	var frozen_brute: bool = false
	var frozen: int = 0
	var poisoned: int = 0
	var spread_deaths: int = 0
	for step: int in 60 * 25:
		run.step()
		for enemy: EnemyState in run.enemies:
			burning = maxi(burning, run.enemies.filter(func(e: EnemyState) -> bool: return e.conditions.is_burning()).size())
			frozen_brute = frozen_brute or (enemy.kind == EnemyDefs.BRUTE and enemy.conditions.is_frozen())
			poisoned = maxi(poisoned, 1 if enemy.conditions.poison_stacks > 0 else 0)
			frozen = maxi(frozen, 1 if enemy.conditions.is_frozen() else 0)
		spread_deaths = run.cue_count(SimCue.Kind.FIRE_SPREAD)
		run.take_cues()
		if run.outcome() != GameRun.Outcome.RUNNING:
			break
	_ok("played for real, the encounter burns, poisons and freezes its enemies (burning at once %d, poisoned %d, frozen %d, a brute frozen %s) and ends with an outcome (%s)" % [burning, poisoned, frozen, str(frozen_brute), GameRun.Outcome.keys()[run.outcome()]],
		burning >= 1 and poisoned == 1 and frozen == 1 and run.outcome() != GameRun.Outcome.RUNNING)
	_ok("every kill was rewarded once (%d kills, %d kill cues, %d spreading deaths)" % [run.kills, run.cue_count(SimCue.Kind.ENEMY_KILLED), spread_deaths], run.kills == run.cue_count(SimCue.Kind.ENEMY_KILLED) and run.kills <= 12)


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
	print("conditions: the Main scene shows element and condition cues")
	var scenario: RunScenario = RunScenario.conditions_encounter()
	scenario.seed = 17
	scenario.first_wave_delay = 0.1
	var main: Main = _main_with(scenario)
	await _tree.process_frame
	main._sfx.unlock()
	main._sfx.played.clear()
	var seen_frozen: bool = false
	var seen_burning: bool = false
	var seen_poison: bool = false
	var cue_shown: bool = false
	for tick_index: int in 60 * 20:
		_tick_main(main, 1)
		if tick_index % 5 == 0:
			for child: Node in main._presenter.get_children():
				if child is PlaceholderEnemyVisual:
					var visual: PlaceholderEnemyVisual = child as PlaceholderEnemyVisual
					seen_frozen = seen_frozen or visual._conditions.frozen
					seen_burning = seen_burning or visual._conditions.burning
					seen_poison = seen_poison or visual._conditions.poison_stacks > 0
		cue_shown = cue_shown or main._presenter._effects._embers.size() > 0
	_ok("the enemy visuals are told, from the run's state, who burns, who is poisoned and who is frozen (%s, %s, %s)" % [seen_burning, seen_poison, seen_frozen], seen_burning and seen_poison and seen_frozen)
	_ok("the effects layer sheds condition particles while enemies burn or chill", cue_shown)
	_ok("a freeze is heard (the parry-like ping, as in the prototype)", main._sfx.played.has("parry"), "%s" % [main._sfx.played])
	var tags: Array[String] = []
	for slot: int in main.run.swords.size():
		tags.append(main._hud._ult_elements[slot].text)
	_ok("each sword card names its element in its colour (%s)" % [tags], tags == ["POISON", "ICE", "FIRE"] and main._hud._ult_elements[0].modulate != main._hud._ult_elements[2].modulate)
	_ok("the legend names the dev encounter and counts burning, poisoned and frozen enemies", main._hud._encounter_label.visible and main._hud._encounter_label.text.begins_with("CONDITIONS ENCOUNTER (dev fixture)") and main._hud._encounter_label.text.contains("frozen"), main._hud._encounter_label.text)
	main.queue_free()
	await _tree.process_frame


func _check_visual_independence() -> void:
	print("conditions: replacing the enemy visual changes nothing about the fight")
	var results: Array[Dictionary] = []
	var hosts: Array[Main] = []
	for use_alt: bool in [false, true]:
		var scenario: RunScenario = RunScenario.conditions_encounter()
		scenario.seed = 19
		scenario.first_wave_delay = 0.2
		hosts.append(_main_with(scenario, "res://tests/alt_enemy.tscn" if use_alt else ""))
	await _tree.process_frame
	for main: Main in hosts:
		_tick_main(main, 900)
		var snapshot: Dictionary = main.run.snapshot()
		snapshot["frozen_cues"] = main.run.cue_count(SimCue.Kind.ENEMY_FROZEN)
		snapshot["spread_cues"] = main.run.cue_count(SimCue.Kind.FIRE_SPREAD)
		snapshot["damage_cues"] = main.run.cue_count(SimCue.Kind.CONDITION_DAMAGE)
		results.append(snapshot)
	_ok("a huge replacement enemy visual changes nothing about burns, poison, freezes, deaths or rewards", results[0] == results[1])
	_ok("the fight had conditions in it (%d freezes, %d burning deaths, %d damage ticks)" % [results[0]["frozen_cues"], results[0]["spread_cues"], results[0]["damage_cues"]], int(results[0]["damage_cues"]) >= 10 and int(results[0]["frozen_cues"]) >= 1)
	var told: int = 0
	for child: Node in hosts[1]._presenter.get_children():
		if child is AltEnemyVisual and (child as AltEnemyVisual).last_conditions != null:
			told += 1
	_ok("a replacement visual is handed the conditions every tick, whether or not it draws them (%d visuals told)" % told, told > 0)
	for main: Main in hosts:
		main.queue_free()
	await _tree.process_frame


# -------------------------------------------------------- render rates
func _check_render_rates() -> void:
	print("conditions: identical outcomes at low and high render rates")
	var headless: Dictionary = RenderRateScenario.play_headless(RenderRateScenario.CONDITIONS)
	var expected_digest: Dictionary = JSON.parse_string(JSON.stringify(headless))
	_ok("the scripted fight does something worth comparing (freezes %d, burning deaths %d, damage ticks %d, shatters %d, kills %d)" % [int(headless["frozen_cues"]), int(headless["spread_cues"]), int(headless["condition_damage_cues"]), int(headless["shatter_cues"]), int(headless["kills"])],
		int(headless["frozen_cues"]) >= 2 and int(headless["spread_cues"]) >= 2 and int(headless["condition_damage_cues"]) >= 20 and int(headless["kills"]) >= 6)
	_ok("exactly once: kill cues equal kills (%d) and no dead enemy is still in the run" % int(headless["kills"]), int(headless["kill_cues"]) == int(headless["kills"]))
	var executable: String = OS.get_executable_path()
	var project: String = ProjectSettings.globalize_path("res://")
	var frames: Dictionary[int, int] = {}
	for rate: int in PROBE_FRAME_RATES:
		var output: Array = []
		var arguments: PackedStringArray = ["--headless", "--path", project, "--fixed-fps", str(rate), "--script", PROBE_SCRIPT, "--", "--probe=rate-conditions"]
		var code: int = OS.execute(executable, arguments, output, true)
		var line: String = _probe_line(output)
		_ok("the engine played the conditions fight at %d fps (exit %d)" % [rate, code], code == 0 and not line.is_empty(), "%s" % [output])
		if line.is_empty():
			continue
		var result: Dictionary = JSON.parse_string(line)
		frames[rate] = int(result["frames"])
		var comparable: Dictionary = result.duplicate()
		for key: String in ["frames", "visuals", "enemies"]:
			comparable.erase(key)
		_ok("at %d fps the real Main scene ends the fight exactly like the bare simulation: same burns, poison, freezes, spread deaths and survivors" % rate, comparable == expected_digest, _first_difference(comparable, expected_digest))
	_ok("the rates really differed: the engine drew %s frames for the same %d ticks" % [frames, RenderRateScenario.TOTAL_TICKS],
		frames.size() == PROBE_FRAME_RATES.size() and frames[5] < frames[20] and frames[20] < frames[60] and frames[60] < frames[240])


func _probe_line(output: Array) -> String:
	for chunk: Variant in output:
		for line: String in String(chunk).split("\n"):
			if line.begins_with("PROBE "):
				return line.trim_prefix("PROBE ")
	return ""


func _first_difference(actual: Dictionary, expected: Dictionary) -> String:
	for key: Variant in expected:
		if not actual.has(key) or actual[key] != expected[key]:
			return "%s: %s vs %s" % [key, str(actual.get(key)), str(expected[key])]
	return ""
