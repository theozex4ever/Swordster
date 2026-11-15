class_name ConvergeChecks
extends RefCounted
## Behavioural checks for Converge, the player's coordinated command, and the prototype's default
## loadout as the normal start (issue #16). Like the earlier slices' checks, every check drives the real
## `GameRun` through the commands the real `InputTranslator` produces from real mouse and key events (or the
## real Main scene), advances fixed ticks and observes outcomes. Comparison values come from the Python
## prototype's captured reference (res://tests/reference/converge.json, recorded by
## tools/reference/capture_converge.py), which also carries each case's fixture (`setup`: swords, enemies,
## the player, whether conditions are on, and a short script of timed clicks, keys and other ops), so no
## starting number is copied into this file. Most cases compare every sword, every enemy and the run's
## shared counters on EVERY tick. Tolerances and deliberate exceptions: docs/reference/converge.md.

const REFERENCE_PATH: String = "res://tests/reference/converge.json"
const PROBE_SCRIPT: String = "res://tests/frame_rate_probe.gd"

const POSITION_TOL: float = 0.05  # px
const VELOCITY_TOL: float = 0.5  # px/s
const SCALAR_TOL: float = 0.002  # timers, cooldowns, shake, stun, flash
const ANGLE_TOL: float = 0.002
const HP_TOL: float = 0.001
const PROBE_FRAME_RATES: Array[int] = [5, 20, 60, 240]
const CENTER: Vector2 = Vector2(1300.0, 900.0)
const FAR_FUTURE: int = 1 << 30
## The prototype's mouse buttons (1 left, 2 middle, 3 right) as Godot's.
const BUTTONS: Dictionary[int, MouseButton] = {1: MOUSE_BUTTON_LEFT, 2: MOUSE_BUTTON_MIDDLE, 3: MOUSE_BUTTON_RIGHT}
const SLOT_KEYS: Dictionary[String, Key] = {"q": KEY_Q, "e": KEY_E, "r": KEY_R}

var _check: Callable
var _tree: SceneTree
var _ref: Dictionary = {}


func _init(check_function: Callable, tree: SceneTree) -> void:
	_check = check_function
	_tree = tree


func run_all() -> void:
	if not CheckFocus.includes("converge"):
		return
	var file: FileAccess = FileAccess.open(REFERENCE_PATH, FileAccess.READ)
	if file == null:
		_ok("converge reference file loads", false, REFERENCE_PATH)
		return
	_ref = JSON.parse_string(file.get_as_text())
	_ok("converge reference file parses", not _ref.is_empty())
	_check_reference_scope()
	_check_definitions()
	_check_default_start()
	for group: String in ["types", "eligibility", "corpses", "dead_targets", "refusals", "default", "touch_and_ranges"]:
		_check_group(group)
	for name: String in ["cooldown", "spam", "ultimates"]:
		_check_case(name, _ref[name])
	_check_damage_boost()
	_check_range_and_target_rules()
	_check_cooldown_rules()
	_check_eligibility_rules()
	_check_restart_and_ranges()
	_check_input_translation()
	await _check_main_scene()
	await _check_aim_across_views()
	await _check_hud_and_effects()
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


## A scenario from a case's `setup`: its swords (type, rarity, element, starting cooldown), enemies, player
## position, and whether elemental conditions are on, with no waves.
func _scenario(setup: Dictionary) -> RunScenario:
	var scenario: RunScenario = RunScenario.new()
	if not bool(setup["conditions"]):
		scenario = scenario.without_conditions()
	scenario.seed = 41
	scenario.waves_enabled = false
	scenario.crit_chance = 1.0 if bool(setup.get("crit", false)) else 0.0
	if setup.has("player"):
		scenario.start_position = _point(setup["player"])
	var specs: Array[SwordSpec] = []
	var cooldowns: Array[float] = []
	for sword: Variant in setup["swords"]:
		var entry: Dictionary = sword as Dictionary
		specs.append(SwordSpec.make(StringName(entry["type"]), int(entry["rarity"]), StringName(entry["element"])))
		cooldowns.append(float(entry["cd"]))
	scenario.loadout = specs
	scenario.sword_start_cooldowns = cooldowns
	var placements: Array[EnemyPlacement] = []
	for enemy: Variant in setup.get("enemies", []):
		var spec: Dictionary = enemy as Dictionary
		var placement: EnemyPlacement = EnemyPlacement.make(StringName(spec["kind"]), Vector2(float(spec["x"]), float(spec["y"])))
		placement.speed_scale = float(spec["speed_scale"])
		placement.hp = float(spec["hp"])
		placement.velocity = Vector2(float(spec.get("vx", 0.0)), float(spec.get("vy", 0.0)))
		placement.stun = float(spec.get("stun", 0.0))
		placements.append(placement)
	scenario.initial_enemies = placements
	return scenario


## A bare run of `kinds` (one sword each, parked) against husks at `enemy_points`, no waves, no conditions, no crits.
func _lone_run(kinds: Array, enemy_points: Array, conditions: bool = false) -> GameRun:
	var swords: Array = []
	var enemies: Array = []
	for kind: Variant in kinds:
		swords.append({"type": kind, "rarity": 0, "element": "fire", "cd": 99.0})
	for at: Variant in enemy_points:
		enemies.append({"kind": "husk", "x": (at as Vector2).x, "y": (at as Vector2).y, "hp": 900.0, "speed_scale": 0.0})
	return GameRun.new(_scenario({"conditions": conditions, "swords": swords, "enemies": enemies}))


## The state of a sword as the prototype names it (`Sword.state`, with a running ultimate's `phase`).
func _state_name(sword: SwordState) -> String:
	match sword.phase:
		SwordState.Phase.IDLE:
			return "idle"
		SwordState.Phase.WINDUP:
			return "windup"
		SwordState.Phase.STRIKE:
			return "strike"
		SwordState.Phase.RECOVER:
			return "recover"
		SwordState.Phase.STUCK:
			return "stuck"
		_:
			match sword.spec.type_id:
				SwordDefs.FANG:
					return "ult_flurry"
				SwordDefs.WARDEN:
					return "ult_spin"
				SwordDefs.PIKE:
					return "ult_fly" if sword.skewer_flying else "ult_aim"
				_:
					return "ult_fall" if sword.cataclysm_falling else "ult_rise"


func _mouse_button(button: int, at: Vector2, pressed: bool = true) -> InputEventMouseButton:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = BUTTONS[button]
	event.pressed = pressed
	event.position = at
	return event


func _key(code: Key, pressed: bool = true) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	return event


# --------------------------------------------------------------- scope and definitions
func _check_reference_scope() -> void:
	print("converge: the reference's scope")
	var scope: Dictionary = _ref["fixture_scope"]
	_ok("the reference holds only unarmed husks, never the wave machine, and the prototype's own afflict where conditions are on (%d cases)" % int(scope["afflict_enabled_cases"]),
		int(scope["armed_enemies"]) == 0 and not bool(scope["waves_enabled"]) and bool(scope["afflict_disabled_everywhere_else"]) and int(scope["afflict_enabled_cases"]) == 3)
	_ok("all four sword types and the keys Q, E and R are used", (scope["swords_used"] as Array).size() == 4 and (scope["keys_used"] as Array).size() == 3)


func _check_definitions() -> void:
	print("converge: constants")
	var table: Dictionary = _ref["table"]
	_ok("the cooldown is the prototype's CONVERGE_CD (%.1f s), the range clamp 460 px, the target radius 90 px, the boost 1.5 and the windup 0.6 of the type's" % float(table["converge_cd"]),
		SwordDefs.CONVERGE_COOLDOWN == float(table["converge_cd"]) and SwordDefs.CONVERGE_RANGE == float(table["clamp"]) and SwordDefs.CONVERGE_TARGET_RADIUS == float(table["target_radius"])
		and SwordDefs.CONVERGE_BOOST == float(table["boost"]) and SwordDefs.CONVERGE_WINDUP_FACTOR == float(table["windup_factor"]))
	var buttons: Array = table["buttons_that_converge"]
	_ok("the mouse buttons that command Converge are the prototype's left and right (1 and 3), not the middle one", buttons.size() == 2 and BUTTONS[int(buttons[0])] == MOUSE_BUTTON_LEFT and BUTTONS[int(buttons[1])] == MOUSE_BUTTON_RIGHT
		and InputTranslator.CONVERGE_BUTTONS.size() == 2 and InputTranslator.CONVERGE_BUTTONS.has(MOUSE_BUTTON_LEFT) and InputTranslator.CONVERGE_BUTTONS.has(MOUSE_BUTTON_RIGHT) and not InputTranslator.CONVERGE_BUTTONS.has(MOUSE_BUTTON_MIDDLE))
	var wrong: Array[String] = []
	for type_id: StringName in [SwordDefs.FANG, SwordDefs.WARDEN, SwordDefs.PIKE, SwordDefs.COLOSSUS]:
		var want: Dictionary = (table["types"] as Dictionary)[String(type_id)]
		var sword: SwordState = SwordState.equip(SwordSpec.make(type_id, 0, &"fire"), Vector2.ZERO, 0.0)
		if not (_near(sword.damage, float(want["damage"]), 0.0001) and _near(sword.cooldown, float(want["cooldown"]), 0.0001) and _near(sword.attack_range, float(want["range"]), 0.0001)
				and _near(sword.length, float(want["length"]), 0.0001) and _near(sword.windup, float(want["windup"]), 0.0001) and _near(sword.ultimate_cooldown, float(want["ult_max"]), 0.0001)
				and SwordDefs.ultimate_name(type_id) == String(want["ult_name"])):
			wrong.append(String(type_id))
	_ok("every type's damage, cooldown, range, length, windup and ultimate (name, recharge) are the prototype's", wrong.is_empty(), str(wrong))
	var rarities: Array[String] = []
	for type_id: StringName in [SwordDefs.FANG, SwordDefs.WARDEN, SwordDefs.PIKE, SwordDefs.COLOSSUS]:
		var by_rarity: Array = (table["rarity"] as Dictionary)[String(type_id)]
		for rarity: int in 3:
			var sword: SwordState = SwordState.equip(SwordSpec.make(type_id, rarity, &"fire"), Vector2.ZERO, 0.0)
			if not (_near(sword.damage, float(by_rarity[rarity]["damage"]), 0.0001) and _near(sword.attack_range, float(by_rarity[rarity]["range"]), 0.0001)):
				rarities.append("%s %d" % [type_id, rarity])
	_ok("Rare and Mythic damage and range follow the prototype for every type (the attack-range rings use them)", rarities.is_empty(), str(rarities))


func _check_default_start() -> void:
	print("converge: the normal start is the prototype's default loadout")
	var start: Dictionary = _ref["start"]
	var run: GameRun = GameRun.new()
	var want: Array = start["swords"]
	var matched: bool = run.swords.size() == int(start["count"]) and run.swords.size() == want.size()
	var detail: Array[String] = []
	if matched:
		for slot: int in run.swords.size():
			var sword: SwordState = run.swords[slot]
			var entry: Dictionary = want[slot]
			var same: bool = String(sword.spec.type_id) == String(entry["type"]) and sword.spec.rarity == int(entry["rarity"]) and String(sword.spec.element) == String(entry["element"]) \
				and _near(sword.damage, float(entry["damage"]), 0.0001) and _near(sword.cooldown, float(entry["cooldown"]), 0.0001) and _near(sword.attack_range, float(entry["range"]), 0.0001) \
				and _near(sword.ultimate_cooldown, float(entry["ult_max"]), 0.0001) and SwordDefs.ultimate_name(sword.spec.type_id) == String(entry["ult_name"]) \
				and sword.ultimate_cooldown_left == float(entry["ult_cd"]) and _state_name(sword) == String(entry["state"]) and sword.position.is_equal_approx(Vector2(float(entry["x"]), float(entry["y"])))
			if not same:
				detail.append("slot %d %s" % [slot, sword.spec.type_id])
			matched = matched and same
	_ok("a run with no scenario starts with Fang (poison), Warden (ice) and Colossus (fire), all Common, hanging at the player, ultimates ready, as the prototype's Game.reset", matched, str(detail))
	_ok("the normal start is not a fixture: it is not the three-Fang loadout, and a fresh scenario equips exactly that default", RunScenario.new().loadout.size() == 3 and RunScenario.new().loadout[1].type_id == SwordDefs.WARDEN
		and RunScenario.fang_fixture().loadout[1].type_id == SwordDefs.FANG and GameRun.new().scenario.encounter == RunScenario.ENCOUNTER_NORMAL)
	_ok("the player starts at the arena centre with Converge ready, as the prototype", run.position.is_equal_approx(_point(start["player"])) and run.converge_cooldown_left == float(start["converge_cd"]) and not run.show_ranges and not bool(start["show_ranges"]))
	var cooldowns: Array[float] = []
	var in_band: bool = true
	var seeded: GameRun = GameRun.new()
	for sword: SwordState in seeded.swords:
		cooldowns.append(sword.cooldown_left)
		in_band = in_band and sword.cooldown_left >= 0.2 and sword.cooldown_left <= 0.6
	_ok("each sword's first attack cooldown is drawn from the prototype's 0.2 to 0.6 s band (%s)" % [cooldowns], in_band and bool(start["start_cds_in_band"]))
	var encounters: Array[StringName] = []
	var cycle: GameRun = GameRun.new()
	for i: int in RunScenario.ENCOUNTER_CYCLE.size():
		encounters.append(cycle.scenario.encounter)
		cycle.apply(GameCommand.toggle_encounter())
	var loadouts: Array[String] = []
	for encounter: StringName in RunScenario.ENCOUNTER_CYCLE:
		var probe: GameRun = GameRun.new()
		while probe.scenario.encounter != encounter:
			probe.apply(GameCommand.toggle_encounter())
		var names: Array[String] = []
		for sword: SwordState in probe.swords:
			names.append(String(sword.spec.type_id))
		loadouts.append("%s: %s" % [encounter, ",".join(names)])
	_ok("the dev encounter cycle still visits every encounter and returns to the normal start (%s)" % [encounters], encounters == RunScenario.ENCOUNTER_CYCLE and cycle.scenario.encounter == RunScenario.ENCOUNTER_NORMAL)
	_ok("each dev fixture keeps its own loadout (crowd, spitters and conditions the Fang fixture; warden, pike and colossus theirs); only the normal start equips the default (%s)" % [loadouts],
		loadouts == [": fang,blade,colossus", "crowd: fang,fang,fang", "spitters: fang,fang,fang", "conditions: fang,fang,fang", "warden: fang,blade,blade", "pike: lance,lance,lance", "colossus: colossus,colossus,colossus"])
	_ok("the wall encounter, a variant of the crowd, also keeps the Fang fixture", RunScenario.wall_encounter().loadout[1].type_id == SwordDefs.FANG)


# --------------------------------------------------------------- replaying the reference
func _check_group(group: String) -> void:
	print("converge: %s" % group)
	var cases: Dictionary = _ref[group]
	for name: String in cases:
		_check_case(name, cases[name])


## Replays a captured case on a fresh run (through the real translator for clicks, keys and Tab / G), comparing every
## tick with its trace and every click, command and ring with the capture's log.
func _check_case(name: String, case: Dictionary) -> void:
	var played: Dictionary = _replay(case)
	var diff: String = String(played["diff"])
	_ok("%s: %d ticks match the prototype tick by tick (swords, enemies, cooldown), and its %d click(s) / %d command(s) / %d ring(s) agree" % [name, int(case["ticks"]), (case["clicks"] as Array).size(), (case["commands"] as Array).size(), (case["rings"] as Array).size()],
		diff.is_empty(), diff)


func _apply_op(run: GameRun, translator: InputTranslator, enemies: Array[EnemyState], op: Dictionary, log: Dictionary, n: int) -> void:
	match String(op["op"]):
		"begin":
			var target: EnemyState = null if op["target"] == null else enemies[int(op["target"])]
			run.swords[int(op["sword"])].begin(target, _point(op["aim"]))
		"click":
			var states: Array[String] = []
			for sword: SwordState in run.swords:
				states.append(_state_name(sword))
			var before: float = run.converge_cooldown_left
			var point: Vector2 = _point(op["point"])
			var seen: int = run.cue_count(SimCue.Kind.CONVERGE)
			for command: GameCommand in translator.handle_event(_mouse_button(int(op["button"]), point)):
				run.apply(command)
			log["clicks"].append({"tick": n, "button": int(op["button"]), "states_before": states, "cd_before": before, "cd_after": run.converge_cooldown_left,
				"accepted": before <= 0.0 and run.converge_cooldown_left == SwordDefs.CONVERGE_COOLDOWN, "converged": run.cue_count(SimCue.Kind.CONVERGE) - seen,
				"commanded": _commanded_swords(run, states), "paused": run.paused, "dead": run.dead})
		"key":
			translator.handle_event(_mouse_motion(_point(op["point"])))
			for command: GameCommand in translator.handle_event(_key(SLOT_KEYS[String(op["key"])])):
				run.apply(command)
		"tab":
			for command: GameCommand in translator.handle_event(_key(KEY_TAB if String(op.get("key", "tab")) == "tab" else KEY_G)):
				run.apply(command)
			log["ranges"].append({"tick": n, "shown": run.show_ranges})
		"touch_converge":
			var before: float = run.converge_cooldown_left
			var states: Array[String] = []
			for sword: SwordState in run.swords:
				states.append(_state_name(sword))
			run.apply(GameCommand.converge_at_nearest())
			log["clicks"].append({"tick": n, "button": 0, "states_before": states, "cd_before": before, "cd_after": run.converge_cooldown_left,
				"accepted": before <= 0.0 and run.converge_cooldown_left == SwordDefs.CONVERGE_COOLDOWN, "commanded": _commanded_swords(run, states), "paused": run.paused, "dead": run.dead})
		"kill":
			run.kill(enemies[int(op["enemy"])], Vector2.UP)
		"corpse":
			enemies[int(op["enemy"])].dead = true
		"hurt":
			run.hurt_player(1000, CENTER + Vector2(50.0, 0.0))
		"pause":
			run.apply(GameCommand.pause())
		"resume":
			run.apply(GameCommand.resume())
		"reset":
			run.apply(GameCommand.restart())


func _mouse_motion(at: Vector2) -> InputEventMouseMotion:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = at
	return event


## The swords that just took a command: those that were not striking, buried or in an ultimate, once a Converge was accepted.
func _commanded_swords(run: GameRun, states_before: Array[String]) -> Array[int]:
	var taken: Array[int] = []
	if run.converge_cooldown_left != SwordDefs.CONVERGE_COOLDOWN:
		return taken
	for slot: int in run.swords.size():
		var sword: SwordState = run.swords[slot]
		if slot < states_before.size() and not states_before[slot].begins_with("strike") and not states_before[slot].begins_with("stuck") and not states_before[slot].begins_with("ult") and sword.boost == SwordDefs.CONVERGE_BOOST:
			taken.append(slot)
	return taken


func _replay(case: Dictionary) -> Dictionary:
	var setup: Dictionary = case["setup"]
	var trace: Dictionary = case["trace"]
	var run: GameRun = GameRun.new(_scenario(setup))
	var enemies: Array[EnemyState] = run.enemies.duplicate()
	var translator: InputTranslator = InputTranslator.new()
	var script: Array = setup["script"]
	var total: int = mini(int(trace["ticks"]), int(case.get("compare_until", FAR_FUTURE)))
	var log: Dictionary = {"clicks": [], "ranges": []}
	var diff: String = ""
	var rings: Array[Dictionary] = []
	run.take_cues()
	for n: int in range(total + 1):
		for op: Variant in script:
			if int((op as Dictionary)["t"]) == n:
				_apply_op(run, translator, enemies, op as Dictionary, log, n)
				for cue: SimCue in run.take_cues():
					if cue.kind == SimCue.Kind.CONVERGE:
						rings.append({"tick": n, "x": cue.position.x, "y": cue.position.y, "amount": cue.amount})
		if n == total:
			break
		run.step()
		run.take_cues()
		if diff.is_empty():
			diff = _tick_diff(run, enemies, case, n + 1)
	if diff.is_empty():
		diff = _log_diff(case, log, rings, total)
	return {"diff": diff, "run": run, "enemies": enemies, "log": log, "rings": rings}


## What differs on tick `n` (1-based) between `run` and the reference trace, or "".
func _tick_diff(run: GameRun, enemies: Array[EnemyState], case: Dictionary, n: int) -> String:
	var trace: Dictionary = case["trace"]
	var i: int = n - 1
	var shared: Dictionary = trace["run"]
	var run_pairs: Array = [["hitstop", run.hitstop, SCALAR_TOL], ["trauma", run.trauma, SCALAR_TOL], ["kills", float(run.kills), 0.0], ["player_x", run.position.x, POSITION_TOL],
		["player_y", run.position.y, POSITION_TOL], ["player_hp", run.hp, SCALAR_TOL + 1.5 * float((shared["kills"] as Array)[i])], ["converge_cd", run.converge_cooldown_left, SCALAR_TOL],
		["ranges", 1.0 if run.show_ranges else 0.0, 0.0]]
	for pair: Array in run_pairs:
		var want: float = float((shared[pair[0]] as Array)[i])
		if not _near(float(pair[1]), want, float(pair[2])):
			return "tick %d: %s %.4f vs %.4f" % [n, pair[0], float(pair[1]), want]
	var random_sword: Dictionary = case["random_sword"]
	var random_enemy: Dictionary = case["random_enemy"]
	var sword_cols: Array = trace["swords"]
	for w: int in sword_cols.size():
		var cols: Dictionary = sword_cols[w]
		var sword: SwordState = run.swords[w]
		var state: String = _state_name(sword)
		if state != String((cols["state"] as Array)[i]):
			return "tick %d: sword %d state %s vs %s" % [n, w, state, (cols["state"] as Array)[i]]
		var in_ultimate: bool = state.begins_with("ult")
		var pairs: Array = [["ult_cd", sword.ultimate_cooldown_left, SCALAR_TOL], ["boost", sword.boost, 0.0001]]
		if n < int(case.get("random_cd_from", FAR_FUTURE)):
			pairs.append(["cd", sword.cooldown_left, SCALAR_TOL])
		if n < int(random_sword.get(str(w), FAR_FUTURE)):
			pairs.append_array([["x", sword.position.x, POSITION_TOL], ["y", sword.position.y, POSITION_TOL], ["ang", sword.angle, ANGLE_TOL], ["vx", sword.velocity.x, VELOCITY_TOL], ["vy", sword.velocity.y, VELOCITY_TOL]])
		if sword.spec.type_id == SwordDefs.COLOSSUS:
			pairs.append_array([["z", sword.altitude, POSITION_TOL], ["vz", sword.fall_speed, POSITION_TOL]])
		if in_ultimate:
			pairs.append(["ult_t", sword.ultimate_time_left, SCALAR_TOL])
		elif not (state == "strike" and sword.spec.type_id == SwordDefs.COLOSSUS):
			# (a slam's fall is timed by its altitude: the prototype's 1.0 s strike timer is never read)
			pairs.append(["timer", sword.timer, SCALAR_TOL])
		if state == "windup" or state == "strike":
			pairs.append_array([["aim_x", sword.aim.x, POSITION_TOL], ["aim_y", sword.aim.y, POSITION_TOL], ["target", float(enemies.find(sword.target)), 0.0]])
		for pair: Array in pairs:
			var want: float = float((cols[pair[0]] as Array)[i])
			if not _near(float(pair[1]), want, float(pair[2])):
				return "tick %d: sword %d (%s) %s %.4f vs %.4f" % [n, w, state, pair[0], float(pair[1]), want]
	var enemy_cols: Array = trace["enemies"]
	for k: int in enemy_cols.size():
		var enemy: EnemyState = enemies[k]
		var col: Dictionary = enemy_cols[k]
		if int(enemy.dead) != int((col["dead"] as Array)[i]):
			return "tick %d: enemy %d dead %s vs %s" % [n, k, enemy.dead, (col["dead"] as Array)[i]]
		var pairs: Array = [["hp", enemy.hp, HP_TOL], ["stun", enemy.stun, SCALAR_TOL], ["flash", enemy.flash, SCALAR_TOL]]
		if n < int(random_enemy.get(str(k), FAR_FUTURE)):
			pairs.append_array([["x", enemy.position.x, POSITION_TOL], ["y", enemy.position.y, POSITION_TOL], ["vx", enemy.velocity.x, VELOCITY_TOL], ["vy", enemy.velocity.y, VELOCITY_TOL]])
		if col.has("burn"):
			var c: EnemyConditions = enemy.conditions
			pairs.append_array([["burn", c.burn, SCALAR_TOL], ["burn_dps", c.burn_dps, SCALAR_TOL], ["poison", c.poison, SCALAR_TOL], ["poison_dps", c.poison_dps, SCALAR_TOL],
				["poison_stacks", float(c.poison_stacks), 0.0], ["chill", c.chill, SCALAR_TOL], ["chill_stacks", float(c.chill_stacks), 0.0], ["frozen", c.frozen, SCALAR_TOL], ["dot", c.dot, SCALAR_TOL]])
		for pair: Array in pairs:
			var want: float = float((col[pair[0]] as Array)[i])
			if not _near(float(pair[1]), want, float(pair[2])):
				return "tick %d: enemy %d %s %.4f vs %.4f" % [n, k, pair[0], float(pair[1]), want]
	return ""


## The clicks, the commands and the rings the capture logged, against what the port did.
func _log_diff(case: Dictionary, log: Dictionary, rings: Array[Dictionary], total: int) -> String:
	var want_clicks: Array = (case["clicks"] as Array).filter(func(entry: Dictionary) -> bool: return int(entry["tick"]) <= total)
	var got_clicks: Array = log["clicks"]
	if want_clicks.size() != got_clicks.size():
		return "%d clicks vs %d" % [got_clicks.size(), want_clicks.size()]
	for i: int in want_clicks.size():
		var want: Dictionary = want_clicks[i]
		var got: Dictionary = got_clicks[i]
		if int(want["tick"]) != int(got["tick"]) or bool(want["accepted"]) != bool(got["accepted"]) or bool(want["paused"]) != bool(got["paused"]) or bool(want["dead"]) != bool(got["dead"]) \
				or not _near(float(want["cd_before"]), float(got["cd_before"]), SCALAR_TOL) or not _near(float(want["cd_after"]), float(got["cd_after"]), SCALAR_TOL):
			return "click %d: %s vs %s" % [i, got, want]
		var want_taken: Array = want["commanded"]
		if (got["commanded"] as Array).size() != want_taken.size():
			return "click %d: commanded %s vs %s" % [i, got["commanded"], want_taken]
		for j: int in want_taken.size():
			if int((got["commanded"] as Array)[j]) != int(want_taken[j]):
				return "click %d: commanded %s vs %s" % [i, got["commanded"], want_taken]
		if int(want["button"]) != 0 and int(got["converged"]) != (1 if bool(want["accepted"]) else 0):
			return "click %d: %d Converge cues for accepted=%s" % [i, got["converged"], want["accepted"]]
	var want_rings: Array = (case["rings"] as Array).filter(func(entry: Dictionary) -> bool: return int(entry["tick"]) <= total)
	if want_rings.size() != rings.size():
		return "%d rings vs %d" % [rings.size(), want_rings.size()]
	for i: int in want_rings.size():
		var want: Dictionary = want_rings[i]
		var got: Dictionary = rings[i]
		if not _near(float(got["x"]), float(want["x"]), POSITION_TOL) or not _near(float(got["y"]), float(want["y"]), POSITION_TOL):
			return "ring %d at (%.2f, %.2f) vs (%.2f, %.2f)" % [i, got["x"], got["y"], want["x"], want["y"]]
	var want_commands: Array = (case["commands"] as Array).filter(func(entry: Dictionary) -> bool: return int(entry["tick"]) <= total)
	var commanded: int = 0
	for entry: Variant in want_commands:
		if bool((entry as Dictionary)["taken"]):
			commanded += 1
	var taken_total: int = 0
	for click: Variant in got_clicks:
		taken_total += ((click as Dictionary)["commanded"] as Array).size()
	if commanded != taken_total:
		return "%d commanded swords vs %d" % [taken_total, commanded]
	var want_ranges: Array = (case["ranges"] as Array).filter(func(entry: Dictionary) -> bool: return int(entry["tick"]) <= total)
	var got_ranges: Array = log["ranges"]
	if want_ranges.size() != got_ranges.size():
		return "%d range toggles vs %d" % [got_ranges.size(), want_ranges.size()]
	for i: int in want_ranges.size():
		if bool((want_ranges[i] as Dictionary)["shown"]) != bool((got_ranges[i] as Dictionary)["shown"]):
			return "range toggle %d shows %s vs %s" % [i, (got_ranges[i] as Dictionary)["shown"], (want_ranges[i] as Dictionary)["shown"]]
	return ""


# --------------------------------------------------------------- explicit rules
func _check_damage_boost() -> void:
	pass


func _check_range_and_target_rules() -> void:
	pass


func _check_cooldown_rules() -> void:
	pass


func _check_eligibility_rules() -> void:
	pass


func _check_restart_and_ranges() -> void:
	pass


func _check_input_translation() -> void:
	pass


func _check_main_scene() -> void:
	pass


func _check_aim_across_views() -> void:
	pass


func _check_hud_and_effects() -> void:
	pass


func _check_visual_independence() -> void:
	pass


func _check_render_rates() -> void:
	pass
