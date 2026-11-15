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
	_check_default_wave()
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
	_ok("each dev fixture keeps its own loadout (crowd, spitters and conditions the Fang fixture; warden, pike, colossus and drops theirs); only the normal start equips the default (the drops fixture happens to equal it) (%s)" % [loadouts],
		loadouts == [": fang,blade,colossus", "crowd: fang,fang,fang", "spitters: fang,fang,fang", "conditions: fang,fang,fang", "warden: fang,blade,blade", "pike: lance,lance,lance", "colossus: colossus,colossus,colossus", "drops: fang,blade,colossus"])
	_ok("the wall encounter, a variant of the crowd, also keeps the Fang fixture", RunScenario.wall_encounter().loadout[1].type_id == SwordDefs.FANG)


## The normal start against the first wave across seeds, once with no input and once with a Converge at the nearest enemy every 3 s,
## against the prototype's own default-loadout runs (random spawn points and the Fang's recoil cannot match: a band of +-1 s).
func _check_default_wave() -> void:
	print("converge: the default loadout clears the first wave like the prototype's")
	var reference: Dictionary = _ref["default_wave"]
	for variant: String in ["no_input", "converge_every_3s"]:
		var entries: Array = reference[variant]
		var lowest: float = INF
		var highest: float = 0.0
		var unarmed: bool = entries.size() == 8
		for entry: Dictionary in entries:
			lowest = minf(lowest, float(entry["cleared_at"]))
			highest = maxf(highest, float(entry["cleared_at"]))
			unarmed = unarmed and int(entry["armed_enemies"]) == 0 and int(entry["kills"]) == 8 and not bool(entry["died"])
		_ok("%s: the prototype's reference is the unarmed first wave: 8 kills on 8 seeds, never died, cleared between %.2f and %.2f s" % [variant, lowest, highest], unarmed)
		var all_survived: bool = true
		var in_band: bool = true
		var converges: int = 0
		var lowest_hp: float = 100.0
		var times: Array[float] = []
		for seed_value: int in range(1, 9):
			var scenario: RunScenario = RunScenario.new()
			scenario.seed = seed_value
			var run: GameRun = GameRun.new(scenario)
			var ticks_taken: int = 0
			while run.outcome() == GameRun.Outcome.RUNNING and ticks_taken < 60 * 60:
				if variant == "converge_every_3s" and ticks_taken % 180 == 179 and not run.enemies.is_empty():
					var before: int = run.cue_count(SimCue.Kind.CONVERGE)
					run.apply(GameCommand.converge_at_nearest())
					converges += run.cue_count(SimCue.Kind.CONVERGE) - before
				run.step()
				ticks_taken += 1
			var seconds: float = float(ticks_taken) / 60.0
			times.append(snappedf(seconds, 0.01))
			all_survived = all_survived and run.outcome() == GameRun.Outcome.SURVIVED and run.kills == 8 and not run.dead
			in_band = in_band and seconds > lowest - 1.0 and seconds < highest + 1.0
			lowest_hp = minf(lowest_hp, run.hp)
		_ok("%s: the default loadout survives the wave on all 8 seeds with all 8 kills (lowest health %.1f)" % [variant, lowest_hp], all_survived and lowest_hp > 40.0)
		_ok("%s: the wave is cleared within the prototype's band %.1f-%.1f s +-1 s (ours: %s)" % [variant, lowest, highest, times], in_band)
		if variant == "converge_every_3s":
			var reference_converges: int = 0
			for entry: Dictionary in entries:
				reference_converges += int(entry["converged"])
			_ok("a player who only clicks lands about as many Converges (%d over 8 runs, the prototype's %d)" % [converges, reference_converges], absi(converges - reference_converges) <= 8)


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
## The converge cues a run has produced since `before` (a count), as the clamped points they carry.
func _last_converge_point(run: GameRun) -> Vector2:
	var found: Vector2 = Vector2(INF, INF)
	for cue: SimCue in run.take_cues():
		if cue.kind == SimCue.Kind.CONVERGE:
			found = cue.position
	return found


func _hit_amounts(run: GameRun) -> Array[int]:
	var amounts: Array[int] = []
	for cue: SimCue in run.take_cues():
		if cue.kind == SimCue.Kind.ENEMY_HIT:
			amounts.append(cue.amount)
	return amounts


func _check_damage_boost() -> void:
	print("converge: a commanded attack's damage boost is 1.5x, once")
	var wanted: Dictionary = {SwordDefs.FANG: [7, 10], SwordDefs.WARDEN: [17, 26], SwordDefs.PIKE: [24, 36], SwordDefs.COLOSSUS: [50, 75]}
	for type_id: StringName in wanted:
		var plain_run: GameRun = _lone_run([type_id], [CENTER + Vector2(150.0, -30.0)])
		plain_run.swords[0].cooldown_left = 0.0
		plain_run.take_cues()
		var plain: int = 0
		for i: int in 120:
			plain_run.step()
			var hits: Array[int] = _hit_amounts(plain_run)
			if not hits.is_empty():
				plain = hits[0]
				break
		var boosted_run: GameRun = _lone_run([type_id], [CENTER + Vector2(150.0, -30.0)])
		boosted_run.apply(GameCommand.converge(CENTER + Vector2(155.0, -30.0)))
		boosted_run.take_cues()
		var boosted: int = 0
		for i: int in 120:
			boosted_run.step()
			var hits: Array[int] = _hit_amounts(boosted_run)
			if not hits.is_empty():
				boosted = hits[0]
				break
		_ok("%s: an automatic attack deals %d and the commanded one %d (the sword's damage x 1.5, rounded half to even)" % [SwordDefs.display_name(type_id), plain, boosted], plain == int((wanted[type_id] as Array)[0]) and boosted == int((wanted[type_id] as Array)[1]))
	var fang: GameRun = _lone_run([SwordDefs.FANG], [CENTER + Vector2(150.0, 0.0)])
	fang.apply(GameCommand.converge(CENTER + Vector2(150.0, 0.0)))
	_ok("the command sets the boost and a windup of 0.6 x the type's (%.4f s of %.2f s) for the whole attack" % [fang.swords[0].timer, fang.swords[0].windup], fang.swords[0].boost == 1.5 and _near(fang.swords[0].timer, fang.swords[0].windup * 0.6, 0.0001) and _near(fang.swords[0].windup_span, fang.swords[0].timer, 0.0001))
	var next_attack: bool = false
	for i: int in 200:
		fang.step()
		if fang.swords[0].phase == SwordState.Phase.IDLE:
			fang.swords[0].cooldown_left = 0.0
			fang.step()
			next_attack = fang.swords[0].phase == SwordState.Phase.WINDUP and fang.swords[0].boost == 1.0 and _near(fang.swords[0].timer, fang.swords[0].windup, 0.0001)
			break
	_ok("the next automatic attack is unboosted again, with the type's own full windup", next_attack)
	var pike: GameRun = _lone_run([SwordDefs.PIKE], [CENTER + Vector2(300.0, 0.0)])
	pike.apply(GameCommand.converge(CENTER + Vector2(300.0, 0.0)))
	var start_progress: float = pike.swords[0].windup_progress()
	_steps(pike, 5)
	var mid: float = pike.swords[0].windup_progress()
	_ok("a commanded Pike's telegraph runs over its shortened windup (%.2f after 5 of its 11.5 ticks, not %.2f of the full 0.32 s)" % [mid, 5.0 / 19.2], start_progress == 0.0 and _near(mid, 5.0 * GameRun.TICK_DT / (0.32 * 0.6), 0.02))


func _check_range_and_target_rules() -> void:
	print("converge: range, near and far points, and the target")
	var cases: Array = [
		["a point inside the range is used as clicked", Vector2(300.0, -100.0), Vector2(300.0, -100.0)],
		["a point exactly 460 px away is used as clicked", Vector2(460.0, 0.0), Vector2(460.0, 0.0)],
		["a point 460.1 px away is pulled back to 460", Vector2(460.1, 0.0), Vector2(460.0, 0.0)],
		["a far point east is pulled back along its direction", Vector2(1000.0, 0.0), Vector2(460.0, 0.0)],
		["a far diagonal keeps its direction (3-4-5)", Vector2(600.0, 800.0), Vector2(276.0, 368.0)],
		["a far point behind the player too", Vector2(-1500.0, 0.0), Vector2(-460.0, 0.0)],
		["the player's own position is a valid point", Vector2.ZERO, Vector2.ZERO],
	]
	for entry: Array in cases:
		var run: GameRun = _lone_run([SwordDefs.FANG, SwordDefs.WARDEN, SwordDefs.COLOSSUS], [])
		run.apply(GameCommand.converge(CENTER + (entry[1] as Vector2)))
		var got: Vector2 = _last_converge_point(run)
		_ok("%s (%s)" % [entry[0], got - CENTER], got.is_equal_approx(CENTER + (entry[2] as Vector2)) and run.swords[0].aim.is_equal_approx(got) and run.swords[2].aim.is_equal_approx(got))
	var moved: GameRun = _lone_run([SwordDefs.WARDEN], [])
	moved.position = CENTER + Vector2(-700.0, 300.0)
	moved.apply(GameCommand.converge(CENTER + Vector2(900.0, 300.0)))
	_ok("the range is measured from the player, wherever the player stands", _last_converge_point(moved).is_equal_approx(moved.position + Vector2(460.0, 0.0)))
	var target: GameRun = _lone_run([SwordDefs.WARDEN], [CENTER + Vector2(300.0, 0.0), CENTER + Vector2(300.0, 60.0), CENTER + Vector2(300.0, -20.0)])
	var sword: SwordState = target.swords[0]
	var click_at: Vector2 = CENTER + Vector2(300.0, 0.0) + Vector2(0.0, -15.0)
	sword.command(target, click_at)
	_ok("the target is the enemy nearest the point within 90 px (the first of equals in the run's order): the one 15 px away, not the one 5 px beyond it", sword.target == target.enemies[0] or sword.target == target.enemies[2])
	var near_two: GameRun = _lone_run([SwordDefs.WARDEN], [CENTER + Vector2(300.0, 0.0), CENTER + Vector2(300.0, 40.0)])
	near_two.swords[0].command(near_two, CENTER + Vector2(300.0, 20.0))
	_ok("two enemies equally near the point: the first in the run's order is the target", near_two.swords[0].target == near_two.enemies[0])
	var edge: GameRun = _lone_run([SwordDefs.WARDEN, SwordDefs.WARDEN], [CENTER + Vector2(300.0, 0.0)])
	edge.swords[0].command(edge, CENTER + Vector2(300.0, 89.9))
	edge.swords[1].command(edge, CENTER + Vector2(300.0, 90.0))
	_ok("an enemy 89.9 px from the point is the target and one exactly 90 px away is not (the prototype's strict <)", edge.swords[0].target == edge.enemies[0] and edge.swords[1].target == null)
	_ok("with no target the sword aims at the point itself and still winds up (boost %.1f, aim %s)" % [edge.swords[1].boost, edge.swords[1].aim - CENTER], edge.swords[1].phase == SwordState.Phase.WINDUP and edge.swords[1].aim.is_equal_approx(CENTER + Vector2(300.0, 90.0)) and edge.swords[1].boost == 1.5)
	var empty: GameRun = _lone_run([SwordDefs.FANG], [])
	empty.apply(GameCommand.converge(CENTER + Vector2(120.0, 0.0)))
	var hung: bool = false
	for i: int in 60:
		empty.step()
	_ok("an empty point strikes and the sword is back to idle afterwards (nothing to hit, nothing stuck): phase %d" % empty.swords[0].phase, empty.swords[0].phase == SwordState.Phase.IDLE or empty.swords[0].phase == SwordState.Phase.RECOVER)
	var gone: GameRun = _lone_run([SwordDefs.WARDEN], [CENTER + Vector2(200.0, 0.0), CENTER + Vector2(240.0, 100.0)])
	gone.apply(GameCommand.converge(CENTER + Vector2(205.0, 0.0)))
	var victim: EnemyState = gone.enemies[0]
	gone.enemies.erase(victim)
	gone.step()
	_ok("an enemy that leaves the run while alive is dropped as the target (the strike carries on to its last point) and is never struck", gone.swords[0].target == null and victim.hp == 900.0 and gone.swords[0].aim.distance_to(CENTER + Vector2(205.0, 0.0)) < 0.5)
	var touch: GameRun = _lone_run([SwordDefs.WARDEN], [CENTER + Vector2(-350.0, 0.0), CENTER + Vector2(150.0, 100.0)])
	touch.apply(GameCommand.converge_at_nearest())
	_ok("the touch Converge aims at the nearest enemy (%s)" % [_last_converge_point(touch) - CENTER], touch.swords[0].aim.is_equal_approx(CENTER + Vector2(150.0, 100.0)) and touch.converge_cooldown_left == 2.5)
	var lonely: GameRun = _lone_run([SwordDefs.WARDEN], [])
	lonely.facing = Vector2.LEFT
	lonely.apply(GameCommand.converge_at_nearest())
	_ok("and 300 px ahead of the player when nothing is alive", _last_converge_point(lonely).is_equal_approx(CENTER + Vector2(-300.0, 0.0)))


func _check_cooldown_rules() -> void:
	print("converge: the shared cooldown")
	var run: GameRun = _lone_run([SwordDefs.FANG, SwordDefs.WARDEN, SwordDefs.COLOSSUS], [CENTER + Vector2(200.0, 0.0)])
	_ok("Converge is ready at the start", run.converge_cooldown_left == 0.0 and run.try_converge(CENTER + Vector2(200.0, 0.0)) == GameRun.ConvergeResult.COMMANDED)
	_ok("and the cooldown is the prototype's 2.5 s at once", run.converge_cooldown_left == 2.5)
	var result_again: int = run.try_converge(CENTER + Vector2(100.0, 0.0))
	var windups: Array[float] = [run.swords[0].timer, run.swords[1].timer]
	_ok("a second click during the cooldown is refused and changes nothing (aim, timers)", result_again == GameRun.ConvergeResult.COOLING_DOWN and run.swords[0].aim.is_equal_approx(CENTER + Vector2(200.0, 0.0)) and run.converge_cooldown_left == 2.5 and run.swords[1].timer == windups[1])
	var accepted_at: int = -1
	for i: int in 400:
		run.step()
		if accepted_at < 0 and run.converge_cooldown_left == 0.0:
			accepted_at = run.tick
	_ok("it runs out after 2.5 s of gameplay time (tick %d, with the hitstop of the blows it dealt in between: %.2f s)" % [accepted_at, float(accepted_at) / 60.0], accepted_at >= 150 and accepted_at < 200)
	_ok("and then Converge is accepted again", run.try_converge(CENTER + Vector2(100.0, 0.0)) == GameRun.ConvergeResult.COMMANDED)
	var spam: GameRun = _lone_run([SwordDefs.WARDEN, SwordDefs.PIKE], [CENTER + Vector2(200.0, 0.0)])
	var accepted: int = 0
	for i: int in 149:
		if spam.try_converge(CENTER + Vector2(150.0, 20.0)) == GameRun.ConvergeResult.COMMANDED:
			accepted += 1
		spam.step()
	_ok("a click every tick for 2.5 s is accepted once (%d accepted, %d Converge cues)" % [accepted, spam.cue_count(SimCue.Kind.CONVERGE)], accepted == 1 and spam.cue_count(SimCue.Kind.CONVERGE) == 1)
	var paused: GameRun = _lone_run([SwordDefs.WARDEN], [CENTER + Vector2(200.0, 0.0)])
	paused.apply(GameCommand.pause())
	var paused_result: int = paused.try_converge(CENTER + Vector2(200.0, 0.0))
	_ok("a paused run refuses Converge without starting the cooldown or moving a sword", paused_result == GameRun.ConvergeResult.UNAVAILABLE and paused.converge_cooldown_left == 0.0 and paused.swords[0].phase == SwordState.Phase.IDLE and paused.cue_count(SimCue.Kind.CONVERGE) == 0)
	paused.apply(GameCommand.resume())
	paused.apply(GameCommand.converge(CENTER + Vector2(200.0, 0.0)))
	paused.apply(GameCommand.pause())
	var frozen: float = paused.converge_cooldown_left
	_steps(paused, 200)
	_ok("a paused run does not tick the cooldown down (%.2f s kept)" % frozen, paused.converge_cooldown_left == frozen and frozen == 2.5)
	var dead: GameRun = _lone_run([SwordDefs.WARDEN], [CENTER + Vector2(200.0, 0.0)])
	dead.hurt_player(1000, CENTER + Vector2(50.0, 0.0))
	var dead_result: int = dead.try_converge(CENTER + Vector2(200.0, 0.0))
	_ok("a dead player cannot command Converge: no cooldown, no sword moved", dead.dead and dead_result == GameRun.ConvergeResult.UNAVAILABLE and dead.converge_cooldown_left == 0.0 and dead.swords[0].phase == SwordState.Phase.IDLE)
	var freeze: GameRun = _lone_run([SwordDefs.WARDEN], [])
	freeze.apply(GameCommand.converge(CENTER + Vector2(200.0, 0.0)))
	freeze.hitstop = 0.5
	_steps(freeze, 10)
	_ok("hitstop holds the cooldown still, as it holds all gameplay (%.3f s)" % freeze.converge_cooldown_left, freeze.converge_cooldown_left == 2.5)
	var slow: GameRun = _lone_run([SwordDefs.WARDEN], [])
	slow.apply(GameCommand.converge(CENTER + Vector2(200.0, 0.0)))
	slow.slowmo = 5.0
	slow.slowmo_scale = 0.25
	_steps(slow, 60)
	_ok("slow motion slows it with the rest of gameplay time (%.3f s after one real second at quarter speed)" % slow.converge_cooldown_left, _near(slow.converge_cooldown_left, 2.5 - 0.25, 0.001))
	var hitstop_click: GameRun = _lone_run([SwordDefs.WARDEN], [CENTER + Vector2(200.0, 0.0)])
	hitstop_click.hitstop = 0.4
	hitstop_click.apply(GameCommand.converge(CENTER + Vector2(200.0, 0.0)))
	_ok("a click during hitstop is taken at once (the sword is already winding up)", hitstop_click.swords[0].phase == SwordState.Phase.WINDUP and hitstop_click.converge_cooldown_left == 2.5)
	var busy: GameRun = _lone_run([SwordDefs.WARDEN, SwordDefs.PIKE, SwordDefs.COLOSSUS], [CENTER + Vector2(200.0, 0.0)])
	for slot: int in 3:
		busy.apply(GameCommand.ultimate(slot, CENTER + Vector2(190.0, -22.0)))
	busy.take_cues()
	var busy_result: int = busy.try_converge(CENTER + Vector2(200.0, 0.0))
	var cue_amount: int = -1
	for cue: SimCue in busy.take_cues():
		if cue.kind == SimCue.Kind.CONVERGE:
			cue_amount = cue.amount
	_ok("with every sword in its ultimate nobody takes the command (cue says %d) but the cooldown starts all the same" % cue_amount, busy_result == GameRun.ConvergeResult.COMMANDED and cue_amount == 0 and busy.converge_cooldown_left == 2.5)


func _check_eligibility_rules() -> void:
	print("converge: which swords take the command")
	var run: GameRun = _lone_run([SwordDefs.COLOSSUS, SwordDefs.COLOSSUS, SwordDefs.COLOSSUS], [CENTER + Vector2(300.0, 0.0)])
	var sword: SwordState = run.swords[0]
	sword.phase = SwordState.Phase.STRIKE
	run.swords[1].phase = SwordState.Phase.STUCK
	run.swords[2].begin_ultimate(run, CENTER + Vector2(300.0, 0.0))
	run.take_cues()
	run.apply(GameCommand.converge(CENTER + Vector2(300.0, 0.0)))
	var untouched: bool = true
	for each: SwordState in run.swords:
		untouched = untouched and each.boost == 1.0 and each.phase != SwordState.Phase.WINDUP
	_ok("a striking sword, a buried one and one in its ultimate all ignore the command (boost stays 1, none winds up)", untouched and run.swords[2].phase == SwordState.Phase.ULTIMATE)
	var states: GameRun = _lone_run([SwordDefs.WARDEN, SwordDefs.WARDEN, SwordDefs.WARDEN], [CENTER + Vector2(300.0, 0.0)])
	states.swords[1].phase = SwordState.Phase.WINDUP
	states.swords[1].timer = 0.1
	states.swords[2].phase = SwordState.Phase.RECOVER
	states.swords[2].timer = 0.2
	states.apply(GameCommand.converge(CENTER + Vector2(300.0, 0.0)))
	var all_windup: bool = true
	for each: SwordState in states.swords:
		all_windup = all_windup and each.phase == SwordState.Phase.WINDUP and each.boost == 1.5 and _near(each.timer, each.windup * 0.6, 0.0001)
	_ok("an idle sword, one already winding up (the windup starts again, shorter) and one recovering all take it", all_windup)
	_ok("whatever its automatic attack's cooldown says: a sword that still has 99 s to wait takes the command", states.swords[0].cooldown_left == 99.0 and states.swords[0].phase == SwordState.Phase.WINDUP)
	_steps(states, 12)
	_ok("a commanded strike restarts the sword's automatic cooldown from its own (%.2f s)" % states.swords[0].cooldown, states.swords[0].phase == SwordState.Phase.STRIKE and _near(states.swords[0].cooldown_left, states.swords[0].cooldown - 2.0 * GameRun.TICK_DT, 0.01))
	var ult: GameRun = _lone_run([SwordDefs.WARDEN, SwordDefs.PIKE, SwordDefs.COLOSSUS], [CENTER + Vector2(300.0, 0.0)])
	ult.apply(GameCommand.converge(CENTER + Vector2(300.0, 0.0)))
	ult.apply(GameCommand.ultimate(0, CENTER + Vector2(300.0, 0.0)))
	ult.apply(GameCommand.ultimate(2, CENTER + Vector2(300.0, 0.0)))
	_ok("an ultimate pressed while the sword winds up for a commanded attack takes over (the shared cooldown does not gate it, nor it the cooldown)", ult.swords[0].phase == SwordState.Phase.ULTIMATE and ult.swords[2].phase == SwordState.Phase.ULTIMATE and ult.swords[1].phase == SwordState.Phase.WINDUP and ult.converge_cooldown_left == 2.5 and ult.swords[0].boost == 1.0)
	var after: GameRun = _lone_run([SwordDefs.WARDEN, SwordDefs.WARDEN, SwordDefs.WARDEN], [])
	after.apply(GameCommand.ultimate(1, CENTER + Vector2(200.0, 0.0)))
	after.apply(GameCommand.converge(CENTER + Vector2(300.0, 0.0)))
	_ok("a Converge right after an ultimate is accepted by the other two swords while the whirling one carries on", after.swords[1].phase == SwordState.Phase.ULTIMATE and after.swords[0].phase == SwordState.Phase.WINDUP and after.swords[2].phase == SwordState.Phase.WINDUP and after.converge_cooldown_left == 2.5)
	var fight: GameRun = GameRun.new(RenderRateScenario.scenario(RenderRateScenario.CONVERGE))
	var kinds: Array[String] = []
	for each: SwordState in fight.swords:
		kinds.append(String(each.spec.type_id))
	_ok("the default loadout's three slots hold Viper Flurry, Maelstrom and Cataclysm for Q, E and R (%s)" % [kinds], kinds == ["fang", "blade", "colossus"] and [0, 1, 2].all(func(slot: int) -> bool: return fight.swords[slot].ultimate_ready())
		and SwordDefs.ultimate_name(fight.swords[0].spec.type_id) == "Viper Flurry" and SwordDefs.ultimate_name(fight.swords[1].spec.type_id) == "Maelstrom" and SwordDefs.ultimate_name(fight.swords[2].spec.type_id) == "Cataclysm")


func _check_restart_and_ranges() -> void:
	print("converge: restart and the attack-range toggle")
	var run: GameRun = _lone_run([SwordDefs.WARDEN], [CENTER + Vector2(200.0, 0.0)])
	run.apply(GameCommand.converge(CENTER + Vector2(200.0, 0.0)))
	run.apply(GameCommand.toggle_ranges())
	run.apply(GameCommand.restart())
	_ok("a restart clears the Converge cooldown and the commanded sword (a fresh run) but keeps the range display, like the prototype's session flag", run.converge_cooldown_left == 0.0 and run.swords[0].phase == SwordState.Phase.IDLE and run.swords[0].boost == 1.0 and run.show_ranges)
	run.apply(GameCommand.toggle_ranges())
	_ok("Tab or G toggles it back off", not run.show_ranges)
	run.apply(GameCommand.pause())
	run.apply(GameCommand.toggle_ranges())
	_ok("the toggle is ignored while paused", not run.show_ranges)
	run.apply(GameCommand.resume())
	run.hurt_player(1000, CENTER + Vector2(30.0, 0.0))
	run.apply(GameCommand.toggle_ranges())
	_ok("and while dead", not run.show_ranges)


func _check_input_translation() -> void:
	print("converge: the mouse and keys that command it")
	var translator: InputTranslator = InputTranslator.new()
	translator.to_world = func(viewport_point: Vector2) -> Vector2: return viewport_point + Vector2(1000.0, 500.0)
	var left: Array[GameCommand] = translator.handle_event(_mouse_button(1, Vector2(30.0, 40.0)))
	_ok("a left click is a Converge at the cursor's world position (not a stale pointer): (1030, 540)", left.size() == 1 and left[0].kind == GameCommand.Kind.CONVERGE and left[0].point == Vector2(1030.0, 540.0) and not left[0].at_nearest)
	var right: Array[GameCommand] = translator.handle_event(_mouse_button(3, Vector2(-5.0, 7.0)))
	_ok("so is a right click", right.size() == 1 and right[0].kind == GameCommand.Kind.CONVERGE and right[0].point == Vector2(995.0, 507.0))
	_ok("a middle click, a button release and the wheel are not", translator.handle_event(_mouse_button(2, Vector2(1.0, 1.0))).is_empty() and translator.handle_event(_mouse_button(1, Vector2(1.0, 1.0), false)).is_empty())
	var wheel: InputEventMouseButton = InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	_ok("the wheel (a press of its own button) does not command Converge", translator.handle_event(wheel).is_empty())
	var emulated: InputEventMouseButton = _mouse_button(1, Vector2(9.0, 9.0))
	emulated.device = InputEvent.DEVICE_ID_EMULATION
	_ok("a click the engine made up from a touch is not a Converge (the touch UI of issue #20 aims its own)", translator.handle_event(emulated).is_empty())
	var tab: Array[GameCommand] = translator.handle_event(_key(KEY_TAB))
	var g_key: Array[GameCommand] = translator.handle_event(_key(KEY_G))
	_ok("Tab and G are the attack-range toggle", tab.size() == 1 and tab[0].kind == GameCommand.Kind.TOGGLE_RANGES and g_key.size() == 1 and g_key[0].kind == GameCommand.Kind.TOGGLE_RANGES)
	var echo: InputEventKey = _key(KEY_TAB)
	echo.echo = true
	_ok("a held Tab does not flicker the display", translator.handle_event(echo).is_empty())
	var ultimates: Array[GameCommand.Kind] = []
	for code: Key in [KEY_Q, KEY_E]:
		for command: GameCommand in translator.handle_event(_key(code)):
			ultimates.append(command.kind)
	_ok("Q and E are still the slot ultimates (a click never starts one, a key never commands Converge)", ultimates == [GameCommand.Kind.ULTIMATE, GameCommand.Kind.ULTIMATE])
	var converge_touch: GameCommand = GameCommand.converge_at_nearest()
	_ok("the touch command exists for issue #20 and carries no point", converge_touch.kind == GameCommand.Kind.CONVERGE and converge_touch.at_nearest)


# ------------------------------------------------------ real Main scene
## A real click as the engine delivers it: the pointer moves there, the button goes down and comes up, through the viewport's own
## input path (`_input`, the HUD's controls, then `_unhandled_input`). `local` says `at` is already a viewport (canvas) position.
func _click(viewport: Viewport, at: Vector2, button: int = 1, local: bool = false) -> void:
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	viewport.push_input(motion, local)
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = _mouse_button(button, at, pressed)
		event.global_position = at
		viewport.push_input(event, local)


func _main_with(scenario: RunScenario, sword_scene: String = "", parent: Node = null) -> Main:
	var main: Main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Main
	main.scenario = scenario
	if not sword_scene.is_empty():
		main.sword_visual = load(sword_scene)
	(parent if parent != null else _tree.root).add_child(main)
	main.set_physics_process(false)
	return main


func _tick_main(main: Main, count: int) -> void:
	for i: int in count:
		main._physics_process(GameRun.TICK_DT)


## A normal start in the real scene with a few standing enemies, no waves and no randomness in what it does.
func _arena_scenario(enemy_points: Array = []) -> RunScenario:
	var scenario: RunScenario = RunScenario.new()
	scenario.seed = 16
	scenario.waves_enabled = false
	scenario.sword_start_cooldowns = [99.0, 99.0, 99.0]
	var placements: Array[EnemyPlacement] = []
	for at: Variant in enemy_points:
		var placement: EnemyPlacement = EnemyPlacement.make(EnemyDefs.HUSK, CENTER + (at as Vector2))
		placement.speed_scale = 0.0
		placement.hp = 900.0
		placements.append(placement)
	scenario.initial_enemies = placements
	return scenario


func _check_main_scene() -> void:
	print("converge: the normal start and a click in the real Main scene")
	var normal: Main = _main_with(null)
	await _tree.process_frame
	var names: Array[String] = []
	var types: Array[String] = []
	var elements: Array[String] = []
	for slot: int in 3:
		names.append(normal._hud._ult_names[slot].text)
		types.append(normal._hud._ult_types[slot].text)
		elements.append(normal._hud._ult_elements[slot].text)
	_ok("launched with no encounter, the scene's run is the normal start: Fang, Warden and Colossus on the cards (%s / %s)" % [names, elements],
		normal.run.scenario.encounter == RunScenario.ENCOUNTER_NORMAL and names == ["Viper Flurry", "Maelstrom", "Cataclysm"] and types[0].begins_with("Fang sword") and types[1].begins_with("Warden sword") and types[2].begins_with("Colossus sword")
		and elements == ["POISON", "ICE", "FIRE"])
	normal.queue_free()
	await _tree.process_frame

	# The headless window is 64x64; give it the game's real size so pointer positions map onto the HUD as on a 1280x720 screen.
	var window_size: Vector2i = _tree.root.size
	_tree.root.size = Vector2i(1280, 720)
	var main: Main = _main_with(_arena_scenario([Vector2(260.0, -20.0), Vector2(-300.0, 40.0)]))
	await _tree.process_frame
	await _tree.process_frame
	var hud: Hud = main._hud
	var viewport: Viewport = main.get_viewport()
	main._sfx.unlock()
	main._sfx.played.clear()
	_tick_main(main, 3)
	var half: Vector2 = viewport.get_visible_rect().size * 0.5
	_ok("the HUD shows Converge ready before any click", hud.converge_status() == "converge ready" and hud.converge_bar_fraction() == 1.0)
	var pause_at: Vector2 = hud._pause_button.get_global_rect().get_center()
	_click(viewport, pause_at)
	_ok("a click on the HUD's Pause button pauses and is not also a Converge (the HUD takes it before the arena does)", main.run.paused and main.run.converge_cooldown_left == 0.0 and main.run.cue_count(SimCue.Kind.CONVERGE) == 0)
	_click(viewport, hud._pause_button.get_global_rect().get_center())
	_ok("and a second click on it resumes", not main.run.paused and main.run.cue_count(SimCue.Kind.CONVERGE) == 0)
	_click(viewport, half + Vector2(250.0, -20.0))
	var sword: SwordState = main.run.swords[0]
	_ok("a left click on the arena commands Converge at the cursor's world point (%s): every sword winds up at once, boosted" % sword.aim,
		main.run.cue_count(SimCue.Kind.CONVERGE) == 1 and main.run.converge_cooldown_left == 2.5 and sword.phase == SwordState.Phase.WINDUP and sword.boost == 1.5
		and main.run.swords.all(func(each: SwordState) -> bool: return each.phase == SwordState.Phase.WINDUP)
		and main.run.swords[0].aim.is_equal_approx(main.run.camera + Vector2(250.0, -20.0)))
	_ok("it is heard (a chime) and shown (the HUD counts the cooldown down)", main._sfx.played.has("chime") and hud.converge_status() == "converge 2.5s" and hud.converge_bar_fraction() == 0.0, "%s %s" % [main._sfx.played, hud.converge_status()])
	main._sfx.played.clear()
	_click(viewport, half + Vector2(-300.0, 40.0), 3)
	_ok("a right click during the cooldown is refused: no second command, no sound", main.run.cue_count(SimCue.Kind.CONVERGE) == 1 and not main._sfx.played.has("chime"))
	_tick_main(main, 40)
	await _tree.process_frame
	var left: float = main.run.converge_cooldown_left
	_ok("the HUD counts the seconds down as the run does (%s with %.2f s left, bar %.2f)" % [hud.converge_status(), left, hud.converge_bar_fraction()],
		left > 0.5 and left < 2.4 and hud.converge_status() == "converge %.1fs" % left and _near(hud.converge_bar_fraction(), 1.0 - left / 2.5, 0.001))
	_tick_main(main, 130)
	_ok("when it is over the HUD says ready again", hud.converge_status() == "converge ready" and hud.converge_bar_fraction() == 1.0)
	_click(viewport, half + Vector2(-300.0, 40.0), 3)
	_ok("and the right button commands it again", main.run.cue_count(SimCue.Kind.CONVERGE) == 2)
	main.run.apply(GameCommand.pause())
	_click(viewport, half)
	_ok("a click while paused does nothing", main.run.cue_count(SimCue.Kind.CONVERGE) == 2)
	main.run.apply(GameCommand.resume())
	main._input(_key(KEY_Q))
	main._input(_key(KEY_E))
	main._input(_key(KEY_R))
	_ok("Q, E and R still start the slots' ultimates in the default loadout (Viper Flurry, Maelstrom, Cataclysm): %d started" % main.run.cue_count(SimCue.Kind.ULTIMATE_STARTED), main.run.cue_count(SimCue.Kind.ULTIMATE_STARTED) == 3 and main.run.swords.all(func(each: SwordState) -> bool: return each.phase == SwordState.Phase.ULTIMATE))
	main.run.hurt_player(1000, CENTER + Vector2(40.0, 0.0))
	main.run.converge_cooldown_left = 0.0
	_click(viewport, half + Vector2(100.0, 0.0))
	_ok("once dead a click commands nothing", main.run.dead and main.run.cue_count(SimCue.Kind.CONVERGE) == 2)
	main.queue_free()
	await _tree.process_frame
	_tree.root.size = window_size


## Clicks and the view: the cursor's world point is the camera's centre plus the cursor's offset from the middle of the visible
## area, whatever the window's shape, and after the view changes under a running scene.
func _check_aim_across_views() -> void:
	print("converge: aiming stays camera-relative across window sizes and view changes")
	var sizes: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1084, 720), Vector2i(1000, 563), Vector2i(1920, 1080), Vector2i(800, 1280), Vector2i(1280, 1024)]
	var window: Window = Window.new()
	window.size = sizes[0]
	window.content_scale_size = Vector2i(1280, 720)
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	_tree.root.add_child(window)
	var scenario: RunScenario = _arena_scenario()
	scenario.start_position = Vector2(1500.0, 1000.0)
	var main: Main = _main_with(scenario, "", window)
	await _tree.process_frame
	var worst: float = 0.0
	var failures: Array[String] = []
	for size: Vector2i in sizes:
		window.size = size
		await _tree.process_frame
		await _tree.process_frame
		main.run.converge_cooldown_left = 0.0
		var view: Vector2 = window.get_visible_rect().size
		var offsets: Array[Vector2] = [Vector2.ZERO, Vector2(300.0, -100.0), Vector2(-250.0, 200.0), Vector2(0.0, -view.y * 0.5), Vector2(view.x * 0.5 - 1.0, view.y * 0.5 - 1.0), Vector2(-view.x * 0.5, -view.y * 0.5)]
		for offset: Vector2 in offsets:
			main.run.converge_cooldown_left = 0.0
			for sword: SwordState in main.run.swords:
				sword.phase = SwordState.Phase.IDLE
			main.run.take_cues()
			_click(window, view * 0.5 + offset, 1, true)
			var want: Vector2 = main.run.camera + offset
			var to_player: Vector2 = want - main.run.position
			if to_player.length() > SwordDefs.CONVERGE_RANGE:
				want = main.run.position + to_player.normalized() * SwordDefs.CONVERGE_RANGE
			var got: Vector2 = main.run.swords[1].aim
			# What the engine itself draws there: the inverse of the viewport's canvas transform (the camera's own).
			main._camera.reset_physics_interpolation()
			main._camera.force_update_scroll()
			var drawn: Vector2 = window.get_canvas_transform().affine_inverse() * (view * 0.5 + offset)
			var engine_gap: float = (drawn - (main.run.camera + offset)).length()
			worst = maxf(worst, engine_gap)
			if got.distance_to(want) > 0.01 or engine_gap > 1.0:
				failures.append("%s offset %s: aimed %s wanted %s, engine says %s" % [size, offset, got, want, drawn])
	_ok("at six window sizes (visible areas 1280x720, 1280x850, 1280x720, 1280x720, 1280x2048, 1280x1024) a click at the middle, in each quadrant and at the corners aims at the camera's centre plus its offset, pulled back to 460 px, and the point agrees with the camera's own transform within %.2f px" % worst, failures.is_empty(), "; ".join(failures))
	_tick_main(main, 60)
	main.run.position = Vector2(700.0, 500.0)
	main.run.velocity = Vector2.ZERO
	_tick_main(main, 240)
	await _tree.process_frame
	main.run.converge_cooldown_left = 0.0
	_click(window, window.get_visible_rect().size * 0.5 + Vector2(120.0, 60.0), 1, true)
	_ok("after the player and the camera moved far away the point follows the camera (%s near %s)" % [main.run.swords[1].aim, main.run.camera + Vector2(120.0, 60.0)], main.run.swords[1].aim.distance_to(main.run.camera + Vector2(120.0, 60.0)) < 0.01 and main.run.camera.distance_to(Vector2(1500.0, 1000.0)) > 500.0)
	main.queue_free()
	window.queue_free()
	await _tree.process_frame


func _check_hud_and_effects() -> void:
	print("converge: the HUD, the ring, the chime and the attack-range display")
	var main: Main = _main_with(_arena_scenario([Vector2(260.0, -20.0)]))
	await _tree.process_frame
	var effects: EffectsLayer = main._presenter._effects
	main._sfx.unlock()
	var rings_before: int = effects._rings.size()
	main._input(_mouse_button(1, main.get_viewport().get_visible_rect().size * 0.5 + Vector2(200.0, 0.0)))
	main._unhandled_input(_mouse_button(1, main.get_viewport().get_visible_rect().size * 0.5 + Vector2(200.0, 0.0)))
	_ok("a Converge draws a ring closing on its point (%d new ring) and plays the chime" % (effects._rings.size() - rings_before), effects._rings.size() == rings_before + 1 and main._sfx.played.has("chime"))
	_tick_main(main, 2)
	await _tree.process_frame
	_ok("ranges are off by default: no ring is drawn", main.run.show_ranges == false and effects.draw_counts.get(&"range_ring", 0) == 0)
	main._input(_key(KEY_TAB))
	_tick_main(main, 2)
	await _tree.process_frame
	var shown: int = effects.draw_counts.get(&"range_ring", 0)
	_ok("Tab shows one ring per sword around the player (%d drawn over the frames since)" % shown, main.run.show_ranges and shown >= 3 and shown % 3 == 0)
	main._input(_key(KEY_G))
	_tick_main(main, 2)
	var after_g: int = effects.draw_counts.get(&"range_ring", 0)
	await _tree.process_frame
	_ok("G hides them again", not main.run.show_ranges and effects.draw_counts.get(&"range_ring", 0) == after_g)
	main._input(_key(KEY_G))
	_tick_main(main, 1)
	await _tree.process_frame
	var before_dead: int = effects.draw_counts.get(&"range_ring", 0)
	main.run.hurt_player(1000, CENTER + Vector2(40.0, 0.0))
	_tick_main(main, 2)
	await _tree.process_frame
	await _tree.process_frame
	_ok("a dead player's rings are not drawn", main.run.dead and main.run.show_ranges and effects.draw_counts.get(&"range_ring", 0) == before_dead)
	var hint: String = main._hud._hint_label.text
	_ok("the controls hint names the click and Tab / G and fits the view (%s)" % [main._hud._hint_label.get_global_rect()], hint.contains("Click: Converge") and hint.contains("Tab / G") and main.get_viewport().get_visible_rect().grow(0.5).encloses(main._hud._hint_label.get_global_rect()))
	var hint_text: Rect2 = Rect2(main._hud._hint_label.get_global_rect().position, main._hud._hint_label.get_minimum_size())
	var buttons: Array[Control] = [main._hud._pause_button, main._hud._restart_button, main._hud._encounter_button]
	_ok("the hint's text (%s) leaves the pause, restart and dev-encounter buttons alone (%s)" % [hint_text, buttons.map(func(button: Control) -> Rect2: return button.get_global_rect())], buttons.all(func(button: Control) -> bool: return not hint_text.intersects(button.get_global_rect())) and hint.contains("swap a drop") and hint.contains("P / Esc: pause"))
	main.queue_free()
	await _tree.process_frame
	var window: Window = Window.new()
	window.size = Vector2i(1084, 720)
	window.content_scale_size = Vector2i(1280, 720)
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	_tree.root.add_child(window)
	var hud: Hud = Hud.new()
	window.add_child(hud)
	var run: GameRun = GameRun.new(RunScenario.new())
	await _tree.process_frame
	run.try_converge(CENTER)
	hud.show_state(false, false)
	hud.show_run(run)
	await _tree.process_frame
	var visible_rect: Rect2 = window.get_visible_rect()
	_ok("the Converge label and bar lie inside a 1084x720 window's view (%s, %s)" % [hud._converge_label.get_global_rect(), hud._converge_track.get_global_rect()], visible_rect.grow(0.5).encloses(hud._converge_label.get_global_rect()) and visible_rect.grow(0.5).encloses(hud._converge_track.get_global_rect()) and not hud._converge_label.get_global_rect().intersects(hud._dash_label.get_global_rect()))
	window.queue_free()
	await _tree.process_frame


func _check_visual_independence() -> void:
	print("converge: swapping the sword visual leaves the default-loadout fight unchanged")
	var hosts: Array[Main] = []
	for use_alt: bool in [false, true]:
		hosts.append(_main_with(RenderRateScenario.scenario(RenderRateScenario.CONVERGE), "res://tests/alt_sword.tscn" if use_alt else ""))
	await _tree.process_frame
	var seen_phases: Dictionary = {}
	var results: Array[Dictionary] = []
	for host_index: int in hosts.size():
		var main: Main = hosts[host_index]
		for tick_index: int in 700:
			for command: GameCommand in RenderRateScenario.commands_at(main.run.tick, RenderRateScenario.CONVERGE):
				main.run.apply(command)
			_tick_main(main, 1)
			if host_index == 1:
				for child: Node in main._presenter.get_children():
					if child is AltSwordVisual:
						seen_phases[(child as AltSwordVisual).last_phase] = true
		results.append(main.run.snapshot())
	_ok("a stretched, rotated replacement sword visual changes nothing about the commanded strikes, the ultimates or the conditions", results[0] == results[1])
	_ok("the replacement visual was told the windup, strike and ultimate phases (%s)" % [seen_phases.keys()], seen_phases.has(SwordState.Phase.WINDUP) and seen_phases.has(SwordState.Phase.STRIKE) and seen_phases.has(SwordState.Phase.ULTIMATE))
	for main: Main in hosts:
		main.queue_free()
	await _tree.process_frame


# -------------------------------------------------------- render rates
func _check_render_rates() -> void:
	if not RenderRateScenario.probes_enabled():
		return
	print("converge: identical outcomes at low and high render rates")
	var headless: Dictionary = RenderRateScenario.play_headless(RenderRateScenario.CONVERGE)
	var expected_digest: Dictionary = JSON.parse_string(JSON.stringify(headless))
	_ok("the scripted fight does something worth comparing (Converges %d, ultimates %d, slams %d, beats %d, hits %d, kills %d, frozen %d, alive %s)" % [int(headless["converge_cues"]), int(headless["ultimate_cues"]), int(headless["colossus_slam_cues"]), int(headless["beat_cues"]), int(headless["hit_cues"]), int(headless["kills"]), int(headless["frozen_cues"]), not bool(headless["dead"])],
		int(headless["converge_cues"]) == 4 and int(headless["ultimate_cues"]) == 4 and int(headless["colossus_slam_cues"]) >= 5 and int(headless["beat_cues"]) >= 5 and int(headless["hit_cues"]) >= 40 and int(headless["kills"]) >= 5 and int(headless["frozen_cues"]) >= 1 and not bool(headless["dead"]))
	var executable: String = OS.get_executable_path()
	var project: String = ProjectSettings.globalize_path("res://")
	var frames: Dictionary[int, int] = {}
	for rate: int in PROBE_FRAME_RATES:
		var output: Array = []
		var arguments: PackedStringArray = ["--headless", "--path", project, "--fixed-fps", str(rate), "--script", PROBE_SCRIPT, "--", "--probe=rate-converge"]
		var code: int = OS.execute(executable, arguments, output, true)
		var line: String = _probe_line(output)
		_ok("the engine played the converge fight at %d fps (exit %d)" % [rate, code], code == 0 and not line.is_empty(), "%s" % [output])
		if line.is_empty():
			continue
		var result: Dictionary = JSON.parse_string(line)
		frames[rate] = int(result["frames"])
		var comparable: Dictionary = result.duplicate()
		for key: String in ["frames", "visuals", "enemies"]:
			comparable.erase(key)
		_ok("at %d fps the real Main scene ends the fight exactly like the bare simulation: same Converges, ultimates, doses, kills, positions, phases and recharges" % rate, comparable == expected_digest, _first_difference(comparable, expected_digest))
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
