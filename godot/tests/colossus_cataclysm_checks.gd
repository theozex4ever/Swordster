class_name ColossusCataclysmChecks
extends RefCounted
## Game-run behavioural checks for the Colossus sword (automatic crushing slams), its ultimate,
## Cataclysm, and the elemental ground fields Cataclysm leaves (issue #15). Like the earlier slices'
## checks, every check drives the real `GameRun` through `GameCommand`s (or the real Main scene with real
## key events), advances fixed ticks and observes outcomes. Comparison values come from the Python
## prototype's captured reference (res://tests/reference/colossus_cataclysm.json, recorded by
## tools/reference/capture_colossus_cataclysm.py), which also carries each case's fixture (`setup`: swords,
## enemies, orbs, the player, whether elemental conditions are on, and a short script of timed commands),
## so no starting number is copied into this file. Most cases compare the swords, every enemy, the
## fields and the run's shared counters on EVERY tick, not just outcomes. Tolerances and deliberate
## exceptions: docs/reference/colossus-cataclysm.md.

const REFERENCE_PATH: String = "res://tests/reference/colossus_cataclysm.json"

## Same-algorithm comparisons at the prototype's 60 FPS step.
const POSITION_TOL: float = 0.05  # px
const VELOCITY_TOL: float = 0.5  # px/s (the prototype's value is a rounded position difference x 60)
const SCALAR_TOL: float = 0.002  # timers, cooldowns, shake, stun, flash
const KICK_TOL: float = 0.01
const ANGLE_TOL: float = 0.002
const HP_TOL: float = 0.001
const CENTER: Vector2 = Vector2(1300.0, 900.0)
const SLOT_KEYS: Array[Key] = [KEY_Q, KEY_E, KEY_R]
const FAR_FUTURE: int = 1 << 30

var _check: Callable
var _tree: SceneTree
var _ref: Dictionary = {}


func _init(check_function: Callable, tree: SceneTree) -> void:
	_check = check_function
	_tree = tree


func run_all() -> void:
	if not CheckFocus.includes("colossus_cataclysm"):
		return
	var file: FileAccess = FileAccess.open(REFERENCE_PATH, FileAccess.READ)
	if file == null:
		_ok("colossus reference file loads", false, REFERENCE_PATH)
		return
	_ref = JSON.parse_string(file.get_as_text())
	_ok("colossus reference file parses", not _ref.is_empty())
	_check_reference_scope()
	if not _check_definitions():
		print("colossus: the sword type's identity is wrong; the remaining checks build fixtures from it and are skipped")
		return
	_check_slam()
	_check_acquire()
	_check_timing()
	_check_geometry()
	_check_empty_slam()
	_check_orbs()
	_check_deaths()
	_check_start()
	_check_single()
	_check_edge()
	_check_conditions()
	_check_field_reach()
	_check_overlap()
	_check_field_deaths()
	_check_rules()
	_check_keys()
	_check_pause_and_hitstop()
	_check_fight()
	_check_removed_and_cleanup()
	_check_pause_and_death()
	_check_fixture_and_launch()
	_check_progress_and_fields()
	await _check_field_particles()
	await _check_main_scene()
	await _check_hud()
	await _check_visual_independence()


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
	var scenario: RunScenario = RunScenario.fang_fixture()
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
		placements.append(_placement(enemy as Dictionary))
	scenario.initial_enemies = placements
	return scenario


func _placement(spec: Dictionary) -> EnemyPlacement:
	var placement: EnemyPlacement = EnemyPlacement.make(StringName(spec["kind"]), Vector2(float(spec["x"]), float(spec["y"])))
	placement.speed_scale = float(spec["speed_scale"])
	placement.hp = float(spec["hp"])
	placement.velocity = Vector2(float(spec.get("vx", 0.0)), float(spec.get("vy", 0.0)))
	placement.stun = float(spec.get("stun", 0.0))
	return placement


func _run_of_setup(setup: Dictionary) -> GameRun:
	var run: GameRun = GameRun.new(_scenario(setup))
	for orb: Variant in setup.get("orbs", []):
		var spec: Dictionary = orb as Dictionary
		var projectile: ProjectileState = ProjectileState.make(Vector2(float(spec["x"]), float(spec["y"])), Vector2(float(spec["vx"]), float(spec["vy"])))
		projectile.life = float(spec["life"])
		run.projectiles.append(projectile)
	return run


## A run of `swords` (each {type, rarity, element, cd}) against `enemies` ({kind, x, y, hp, speed_scale}).
func _lone_run(swords: Array, enemies: Array, conditions: bool = false) -> GameRun:
	return GameRun.new(_scenario({"conditions": conditions, "swords": swords, "enemies": enemies}))


func _trio(rarity: int, cooldown: float, elements: Array = ["poison", "ice", "fire"]) -> Array:
	return [{"type": "colossus", "rarity": rarity, "element": elements[0], "cd": cooldown}, {"type": "colossus", "rarity": rarity, "element": elements[1], "cd": 99.0}, {"type": "colossus", "rarity": rarity, "element": elements[2], "cd": 99.0}]


func _husk_at(dx: float, dy: float, hp: float = 900.0, kind: String = "husk", speed: float = 0.0) -> Dictionary:
	return {"kind": kind, "x": CENTER.x + dx, "y": CENTER.y + dy, "hp": hp, "speed_scale": speed}


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
			return "ult_fall" if sword.cataclysm_falling else "ult_rise"


func _states(run: GameRun) -> Array[String]:
	var names: Array[String] = []
	for sword: SwordState in run.swords:
		names.append(_state_name(sword))
	return names


func _same_strings(actual: Array[String], expected: Array) -> bool:
	if actual.size() != expected.size():
		return false
	for i: int in actual.size():
		if actual[i] != String(expected[i]):
			return false
	return true


## Executes one scripted command on `run` (the capture's own script format), logging key presses the way the capture does.
func _apply_op(run: GameRun, enemies: Array[EnemyState], op: Dictionary, presses: Array[Dictionary]) -> void:
	match String(op["op"]):
		"begin":
			var target: EnemyState = null if op["target"] == null else enemies[int(op["target"])]
			run.swords[int(op["sword"])].begin(target, _point(op["aim"]))
		"key":
			var slot: int = "qer".find(String(op["key"]))
			var sword: SwordState = run.swords[slot]
			var before: String = _state_name(sword)
			var cooldown_before: float = sword.ultimate_cooldown_left
			run.apply(GameCommand.ultimate(slot, _point(op["point"])))
			var after: String = _state_name(sword)
			presses.append({"tick": run.tick, "key": String(op["key"]), "before": before, "ult_cd_before": cooldown_before, "after": after, "started": sword.phase == SwordState.Phase.ULTIMATE and before != after})
		"kill":
			run.kill(enemies[int(op["enemy"])], Vector2.UP)
		"hurt":
			run.hurt_player(1000, CENTER + Vector2(50.0, 0.0))
		"pause":
			run.apply(GameCommand.pause())
		"resume":
			run.apply(GameCommand.resume())


## What differs on tick `i` (the trace's index) between `run` and the reference trace, or "". `slam_n`, `slam_radius` and
## `pulses` come from the cues of this tick.
func _tick_diff(run: GameRun, enemies: Array[EnemyState], orbs: Array[ProjectileState], trace: Dictionary, skip: Dictionary, i: int, n: int, slam_n: int, slam_radius: float, pulses: int) -> String:
	var shared: Dictionary = trace["run"]
	var run_pairs: Array = [["hitstop", run.hitstop, SCALAR_TOL], ["trauma", run.trauma, SCALAR_TOL], ["kick_x", run.kick.x, KICK_TOL], ["kick_y", run.kick.y, KICK_TOL],
		["kills", float(run.kills), 0.0], ["combo", float(run.combo), 0.0], ["player_x", run.position.x, POSITION_TOL], ["player_y", run.position.y, POSITION_TOL],
		["player_hp", run.hp, SCALAR_TOL + 1.5 * float((shared["kills"] as Array)[i])], ["fields", float(run.fields.size()), 0.0], ["slam_n", float(slam_n), 0.0], ["slam_radius", slam_radius, 0.001], ["pulses", float(pulses), 0.0]]
	for pair: Array in run_pairs:
		var want: float = float((shared[pair[0]] as Array)[i])
		if not _near(float(pair[1]), want, float(pair[2])):
			return "tick %d: %s %.4f vs %.4f" % [n, pair[0], float(pair[1]), want]
	var field_cols: Array = trace["fields"]
	for j: int in field_cols.size():
		var life: float = -1.0
		var clock: float = -1.0
		if j < run.fields.size():
			life = run.fields[j].life
			clock = run.fields[j].tick_left
		if not _near(life, float(((field_cols[j] as Dictionary)["life"] as Array)[i]), SCALAR_TOL) or not _near(clock, float(((field_cols[j] as Dictionary)["tick"] as Array)[i]), SCALAR_TOL):
			return "tick %d: field %d life %.4f clock %.4f vs %.4f %.4f" % [n, j, life, clock, ((field_cols[j] as Dictionary)["life"] as Array)[i], ((field_cols[j] as Dictionary)["tick"] as Array)[i]]
	var sword_cols: Array = trace["swords"]
	for w: int in sword_cols.size():
		if sword_cols[w] == null:
			continue
		var cols: Dictionary = sword_cols[w]
		var sword: SwordState = run.swords[w]
		if _state_name(sword) != String((cols["state"] as Array)[i]):
			return "tick %d: sword %d state %s vs %s" % [n, w, _state_name(sword), (cols["state"] as Array)[i]]
		var pairs: Array = [["x", sword.position.x, POSITION_TOL], ["y", sword.position.y, POSITION_TOL], ["ang", sword.angle, ANGLE_TOL], ["vx", sword.velocity.x, VELOCITY_TOL], ["vy", sword.velocity.y, VELOCITY_TOL],
			["z", sword.altitude, POSITION_TOL], ["vz", sword.fall_speed, POSITION_TOL], ["ult_t", sword.ultimate_time_left, SCALAR_TOL], ["ult_cd", sword.ultimate_cooldown_left, SCALAR_TOL], ["cd", sword.cooldown_left, SCALAR_TOL]]
		if sword.phase == SwordState.Phase.STRIKE:
			pairs.append(["ix", sword.impact.x, POSITION_TOL])
			pairs.append(["iy", sword.impact.y, POSITION_TOL])
		for pair: Array in pairs:
			var want: float = float((cols[pair[0]] as Array)[i])
			if not _near(float(pair[1]), want, float(pair[2])):
				return "tick %d: sword %d %s %.4f vs %.4f" % [n, w, pair[0], float(pair[1]), want]
	var enemy_cols: Array = trace["enemies"]
	for k: int in enemy_cols.size():
		var enemy: EnemyState = enemies[k]
		var col: Dictionary = enemy_cols[k]
		if int(enemy.dead) != int((col["dead"] as Array)[i]):
			return "tick %d: enemy %d dead %s vs %s" % [n, k, enemy.dead, (col["dead"] as Array)[i]]
		var kinematic: bool = n < int(skip.get(str(k), FAR_FUTURE))
		var pairs: Array = [["hp", enemy.hp, HP_TOL], ["stun", enemy.stun, SCALAR_TOL], ["flash", enemy.flash, SCALAR_TOL]]
		if kinematic:
			pairs.append_array([["x", enemy.position.x, POSITION_TOL], ["y", enemy.position.y, POSITION_TOL], ["vx", enemy.velocity.x, VELOCITY_TOL], ["vy", enemy.velocity.y, VELOCITY_TOL]])
		if col.has("burn"):
			var c: EnemyConditions = enemy.conditions
			pairs.append_array([["burn", c.burn, SCALAR_TOL], ["burn_dps", c.burn_dps, SCALAR_TOL], ["poison", c.poison, SCALAR_TOL], ["poison_dps", c.poison_dps, SCALAR_TOL],
				["poison_stacks", float(c.poison_stacks), 0.0], ["chill", c.chill, SCALAR_TOL], ["chill_stacks", float(c.chill_stacks), 0.0], ["frozen", c.frozen, SCALAR_TOL], ["dot", c.dot, SCALAR_TOL]])
		for pair: Array in pairs:
			var want: float = float((col[pair[0]] as Array)[i])
			if not _near(float(pair[1]), want, float(pair[2])):
				return "tick %d: enemy %d %s %.4f vs %.4f" % [n, k, pair[0], float(pair[1]), want]
	var orb_cols: Array = trace["orbs"]
	for m: int in orb_cols.size():
		if int(orbs[m].is_resolved()) != int((orb_cols[m] as Array)[i]):
			return "tick %d: orb %d resolved %s vs %s" % [n, m, orbs[m].is_resolved(), (orb_cols[m] as Array)[i]]
	return ""


## Replays a captured case on a fresh run, executing its script and comparing every tick with its trace (`stop_at` plays only
## that many ticks). Returns the first difference ("" if none), the run, its enemies and orbs, the key presses and the tick on which
## each sword first had a ready recharge.
func _replay(case: Dictionary, stop_at: int = -1) -> Dictionary:
	var setup: Dictionary = case["setup"]
	var trace: Dictionary = case["trace"]
	var run: GameRun = _run_of_setup(setup)
	var enemies: Array[EnemyState] = run.enemies.duplicate()
	var orbs: Array[ProjectileState] = run.projectiles.duplicate()
	var script: Array = setup["script"]
	var total: int = int(trace["ticks"]) if stop_at < 0 else stop_at
	var skip: Dictionary = case["random_heading"]
	var diff: String = ""
	var presses: Array[Dictionary] = []
	run.take_cues()
	for n: int in range(total + 1):
		for op: Variant in script:
			if int((op as Dictionary)["t"]) == n:
				_apply_op(run, enemies, op as Dictionary, presses)
		if n == total:
			break
		run.step()
		var slam_n: int = -1
		var slam_radius: float = 0.0
		var pulses: int = 0
		for cue: SimCue in run.take_cues():
			if cue.kind == SimCue.Kind.COLOSSUS_SLAM:
				slam_n = maxi(slam_n, 0) + cue.amount
				slam_radius = cue.radius
			elif cue.kind == SimCue.Kind.FIELD_PULSED:
				pulses += cue.amount
		if diff.is_empty():
			diff = _tick_diff(run, enemies, orbs, trace, skip, n, n + 1, slam_n, slam_radius, pulses)
	return {"diff": diff, "run": run, "enemies": enemies, "orbs": orbs, "presses": presses}


## Replays a case that has no trace (only a script and the key presses it logged), comparing the presses.
func _replay_presses(case: Dictionary) -> Dictionary:
	var setup: Dictionary = case["setup"]
	var run: GameRun = _run_of_setup(setup)
	var enemies: Array[EnemyState] = run.enemies.duplicate()
	var script: Array = setup["script"]
	var total: int = int(case["ticks"])
	var presses: Array[Dictionary] = []
	var ready: int = -1
	for n: int in range(total + 1):
		for op: Variant in script:
			if int((op as Dictionary)["t"]) == n:
				_apply_op(run, enemies, op as Dictionary, presses)
		if n == total:
			break
		run.step()
		if ready < 0 and run.swords[0].ultimate_cooldown_left == 0.0 and run.swords[0].phase != SwordState.Phase.ULTIMATE and n > 5:
			ready = n + 1
	var wanted: Array = case["presses"]
	var diff: String = ""
	if presses.size() != wanted.size():
		diff = "%d presses vs %d" % [presses.size(), wanted.size()]
	else:
		for i: int in presses.size():
			var got: Dictionary = presses[i]
			var want: Dictionary = wanted[i]
			if String(got["before"]) != String(want["before"]) or String(got["after"]) != String(want["after"]) or bool(got["started"]) != bool(want["started"]) or not _near(float(got["ult_cd_before"]), float(want["ult_cd_before"]), 0.0002):
				diff = "press %d (key %s): %s -> %s started %s cd %.4f vs %s -> %s started %s cd %.4f" % [i, got["key"], got["before"], got["after"], got["started"], got["ult_cd_before"], want["before"], want["after"], want["started"], want["ult_cd_before"]]
				break
	return {"diff": diff, "run": run, "enemies": enemies, "presses": presses, "ready": ready}


func _transition_ticks(case: Dictionary, sword: int, to: String) -> Array[int]:
	var ticks: Array[int] = []
	for entry: Variant in (case["trace"]["transitions"] as Array)[sword]:
		if String((entry as Dictionary)["to"]) == to:
			ticks.append(int((entry as Dictionary)["tick"]))
	return ticks


## What a heavy blow leaves: `damage x boost x power x fall`, doubled for a critical, 1.3x on a frozen enemy, rounded half to even, at least 1.
func _expected_blow(damage: float, power: float, dist: float, radius: float, crit: bool = false) -> int:
	var fall: float = 1.0 - 0.45 * clampf(dist / radius, 0.0, 1.0)
	var dealt: float = damage * 1.0 * power * fall
	if crit:
		dealt *= 2.0
	return maxi(1, SimMath.py_round(dealt))


# ------------------------------------------------------------- reference
func _check_reference_scope() -> void:
	print("colossus: the reference was captured with out-of-scope mechanics disabled")
	var scope: Dictionary = _ref["fixture_scope"]
	_ok("every enemy in the capture was unarmed (arming and drops are issue #17) and only husks, runners and brutes were used", int(scope["armed_enemies"]) == 0 and scope["kinds"] == ["brute", "husk", "runner"])
	_ok("only Colossus swords took part, Converge was not used (issue #16), no waves ran (issue #18)", scope["swords_used"] == ["colossus"] and not bool(scope["converge_used"]) and not bool(scope["waves_enabled"]))
	var with_conditions: Array = scope["afflict_enabled_cases"]
	_ok("the prototype's afflict was OFF everywhere except the condition cases %s" % [with_conditions], bool(scope["afflict_disabled_everywhere_else"])
		and with_conditions == ["deaths_fire", "deaths_poison", "field_corpse", "field_fire", "field_ice", "field_player_dies", "field_poison", "fight", "overlap_apart", "overlap_same_tick", "overlap_three", "pause_field"])
	_ok("Q, E and R all went through the prototype's real key handler (%s)" % [scope["keys_used"]], scope["keys_used"] == ["e", "q", "r"])
	var flags_ok: bool = true
	for label: String in ["poison", "ice", "fire"]:
		flags_ok = flags_ok and bool(_ref["conditions"][label]["setup"]["conditions"])
	for label: String in ["common", "common_crit", "rare", "mythic"]:
		flags_ok = flags_ok and not bool(_ref["slam"][label]["setup"]["conditions"]) and not bool(_ref["single"][label]["setup"]["conditions"])
	flags_ok = flags_ok and bool(_ref["fight"]["setup"]["conditions"]) and bool(_ref["field_deaths"]["burn_down_fire"]["setup"]["conditions"])
	_ok("each case's fixture says whether conditions are on: the condition cases on, the physical cases off", flags_ok)


## Returns false when the sword type's identity is wrong; every later check builds its fixtures from
## the prototype's key, so they must not run (a renamed key would only crash them).
func _check_definitions() -> bool:
	print("colossus: identity, constants and rarity numbers against the prototype")
	var table: Dictionary = _ref["table"]
	var inline: Dictionary = table["inline"]
	var identity_ok: bool = String(SwordDefs.COLOSSUS) == String(table["kind"]) and SwordDefs.display_name(SwordDefs.COLOSSUS) == String(table["name"]) and SwordDefs.is_supported(SwordDefs.COLOSSUS) and SwordDefs.display_name(SwordDefs.PIKE) == "Pike"
	_ok("the sword type keeps the prototype's internal key `%s` and the display name %s" % [String(SwordDefs.COLOSSUS), SwordDefs.display_name(SwordDefs.COLOSSUS)], identity_ok)
	if not identity_ok:
		return false
	_ok("base length, width, range, cooldown, damage, knockback, windup, hitstop, shake and slam radius",
		SwordDefs.base_length(SwordDefs.COLOSSUS) == float(table["length"]) and SwordDefs.COLOSSUS_WIDTH == float(table["width"]) and SwordDefs.base_range(SwordDefs.COLOSSUS) == float(table["range"])
		and SwordDefs.base_cooldown(SwordDefs.COLOSSUS) == float(table["cooldown"]) and SwordDefs.base_damage(SwordDefs.COLOSSUS) == float(table["damage"]) and SwordDefs.base_knock(SwordDefs.COLOSSUS) == float(table["knock"])
		and SwordDefs.base_windup(SwordDefs.COLOSSUS) == float(table["windup"]) and SwordDefs.base_hitstop(SwordDefs.COLOSSUS) == float(table["hitstop"]) and SwordDefs.base_shake(SwordDefs.COLOSSUS) == float(table["shake"])
		and SwordDefs.COLOSSUS_AOE == float(table["aoe"]))
	_ok("the ultimate is named %s: recharge %.1f s, range %.0f px, area factor %.1f, a targeted ultimate (not a skill shot)" % [SwordDefs.ultimate_name(SwordDefs.COLOSSUS), SwordDefs.ultimate_cooldown(SwordDefs.COLOSSUS), SwordDefs.ultimate_range(SwordDefs.COLOSSUS), SwordDefs.COLOSSUS_ULT_AOE_FACTOR],
		SwordDefs.ultimate_name(SwordDefs.COLOSSUS) == String(table["ult_name"]) and SwordDefs.ultimate_cooldown(SwordDefs.COLOSSUS) == float(table["ult_cd"]) and SwordDefs.ultimate_range(SwordDefs.COLOSSUS) == float(table["ult_range"])
		and SwordDefs.COLOSSUS_ULT_AOE_FACTOR == float(table["ult_aoe"]) and SwordDefs.ultimate_is_shot(SwordDefs.COLOSSUS) == bool(table["ult_shot"]) and not SwordDefs.ultimate_is_shot(SwordDefs.COLOSSUS))
	_ok("altitude: a new sword hangs at 30, rests at 34 + 0.15 x length + a bob, sinks when the player dies",
		SwordDefs.COLOSSUS_START_ALTITUDE == float(inline["start_altitude"]) and SwordDefs.COLOSSUS_REST_BASE == float(inline["rest_base"]) and SwordDefs.COLOSSUS_REST_LENGTH == float(inline["rest_length"])
		and SwordDefs.COLOSSUS_REST_BOB_RATE == float(inline["rest_bob_rate"]) and SwordDefs.COLOSSUS_REST_BOB_SLOT == float(inline["rest_bob_slot"]) and SwordDefs.COLOSSUS_REST_BOB == float(inline["rest_bob"])
		and SwordDefs.COLOSSUS_REST_RATE == float(inline["rest_rate"]) and SwordDefs.COLOSSUS_SINK_RATE == float(inline["sink_rate"]))
	_ok("the windup: spring, altitude 200 at rate 7, tremble and turn rate",
		SwordDefs.COLOSSUS_WINDUP_SPRING_K == float((inline["windup_spring"] as Array)[0]) and SwordDefs.COLOSSUS_WINDUP_SPRING_C == float((inline["windup_spring"] as Array)[1]) and SwordDefs.COLOSSUS_WINDUP_ALTITUDE == float(inline["windup_altitude"])
		and SwordDefs.COLOSSUS_WINDUP_RATE == float(inline["windup_rate"]) and SwordDefs.COLOSSUS_WINDUP_TREMBLE_RATE == float(inline["windup_tremble_rate"]) and SwordDefs.COLOSSUS_WINDUP_TREMBLE == float(inline["windup_tremble"])
		and SwordDefs.COLOSSUS_WINDUP_TURN_RATE == float(inline["windup_turn"]))
	_ok("the fall and the slam: glide, fall speed and gravity, falloff 0.45, the short hitstop and shake of an empty slam",
		SwordDefs.COLOSSUS_GLIDE_RATE == float(inline["glide_rate"]) and SwordDefs.COLOSSUS_STRIKE_FALL_SPEED == float(inline["strike_fall_speed"]) and SwordDefs.COLOSSUS_STRIKE_GRAVITY == float(inline["strike_gravity"])
		and SwordDefs.COLOSSUS_SLAM_FALLOFF == float(inline["falloff"]) and SwordDefs.COLOSSUS_SLAM_EMPTY_HITSTOP == float(inline["empty_hitstop"]) and SwordDefs.COLOSSUS_SLAM_EMPTY_SHAKE == float(inline["empty_shake"]))
	_ok("stuck and recovery: 0.32 s, tremble, 0.4 s, kicked upward at 60 px/s",
		SwordDefs.COLOSSUS_STUCK_TIME == float(inline["stuck_time"]) and SwordDefs.COLOSSUS_STUCK_TREMBLE_RATE == float(inline["stuck_tremble_rate"]) and SwordDefs.COLOSSUS_STUCK_TREMBLE == float(inline["stuck_tremble"])
		and SwordDefs.COLOSSUS_RECOVER_TIME == float(inline["recover_time"]) and SwordDefs.COLOSSUS_RECOVER_VELOCITY == _point(inline["recover_velocity"]))
	_ok("Cataclysm: rise 0.75 s to altitude 420, fall from 600 with gravity 12000, 2.2 x damage, three doses, shake 0.4, stuck 0.6 s",
		SwordDefs.COLOSSUS_ULT_RISE_TIME == float(inline["rise_time"]) and SwordDefs.COLOSSUS_ULT_RISE_ALTITUDE == float(inline["rise_altitude"]) and SwordDefs.COLOSSUS_ULT_RISE_RATE == float(inline["rise_rate"])
		and SwordDefs.COLOSSUS_ULT_TREMBLE_RATE == float(inline["ult_tremble_rate"]) and SwordDefs.COLOSSUS_ULT_TREMBLE == float(inline["ult_tremble"]) and SwordDefs.COLOSSUS_ULT_FALL_SPEED == float(inline["ult_fall_speed"])
		and SwordDefs.COLOSSUS_ULT_FALL_GRAVITY == float(inline["ult_gravity"]) and SwordDefs.COLOSSUS_ULT_DAMAGE_FACTOR == float(inline["ult_damage"]) and SwordDefs.COLOSSUS_ULT_STACKS == int(inline["ult_stacks"])
		and SwordDefs.COLOSSUS_ULT_SHAKE == float(inline["ult_shake"]) and SwordDefs.COLOSSUS_ULT_STUCK_TIME == float(inline["ult_stuck_time"]))
	_ok("the field: 1.1 x the area, 5 s of life, a dose every 0.5 s; blows flash 0.2 s (heavy) or 0.11 s",
		SwordDefs.COLOSSUS_FIELD_RADIUS_FACTOR == float(inline["field_radius_factor"]) and SwordDefs.COLOSSUS_FIELD_LIFE == float(inline["field_life"]) and SwordDefs.COLOSSUS_FIELD_PERIOD == float(inline["field_period"])
		and SwordDefs.HEAVY_HIT_FLASH == float(inline["heavy_flash"]) and SwordDefs.NORMAL_HIT_FLASH == float(inline["normal_flash"]))
	var world: Array = table["world"]
	_ok("the arena is the prototype's 2600 x 1800", GameRun.WORLD == Rect2(float(world[0]), float(world[1]), float(world[2]) - float(world[0]), float(world[3]) - float(world[1])))
	var swords: Array = [{"type": "colossus", "rarity": 0, "element": "poison", "cd": 99.0}, {"type": "colossus", "rarity": 1, "element": "ice", "cd": 99.0}, {"type": "colossus", "rarity": 2, "element": "fire", "cd": 99.0}]
	var run: GameRun = GameRun.new(_scenario({"conditions": false, "swords": swords}))
	for rarity: int in 3:
		var sword: SwordState = run.swords[rarity]
		var want: Dictionary = (table["rarities"] as Array)[rarity]
		_ok("rarity %d: damage %.2f, cooldown %.3f, range %.2f, length %.2f, recharge %.2f s, slam radius %.2f, Cataclysm radius %.2f" % [rarity, sword.damage, sword.cooldown, sword.attack_range, sword.length, sword.ultimate_cooldown, sword.slam_radius(), sword.cataclysm_radius()],
			_near(sword.damage, float(want["damage"]), 0.0001) and _near(sword.cooldown, float(want["cooldown"]), 0.0001) and _near(sword.attack_range, float(want["range"]), 0.0001) and _near(sword.length, float(want["length"]), 0.0001)
			and _near(sword.ultimate_cooldown, float(want["ult_max"]), 0.0001) and _near(sword.size_scale, float(want["scale"]), 0.0001) and _near(sword.slam_radius(), float(want["slam_radius"]), 0.0001) and _near(sword.cataclysm_radius(), float(want["ult_aoe"]), 0.0001)
			and sword.ultimate_area_radius() == sword.cataclysm_radius())
	_ok("a new run starts every Colossus ready, hanging at altitude 30, not falling, with no field", run.swords.all(func(sword: SwordState) -> bool: return sword.ultimate_ready() and sword.altitude == SwordDefs.COLOSSUS_START_ALTITUDE and not sword.cataclysm_falling and sword.fall_speed == 0.0) and run.fields.is_empty())
	var radii_ok: bool = true
	for kind: String in ["husk", "runner", "brute"]:
		radii_ok = radii_ok and EnemyDefs.of(StringName(kind)).radius == float((table["radius"] as Dictionary)[kind]) and _near(EnemyDefs.of(StringName(kind)).knock, float((table["knock_mult"] as Dictionary)[kind]), 0.0001)
	_ok("the enemy radii and knock factors the geometry depends on match the prototype", radii_ok)
	return true


# ------------------------------------------------------------- the slam
func _check_slam() -> void:
	print("colossus: acquire, windup, fall, slam, stuck, recovery and the second slam, tick by tick, against the prototype")
	for label: String in ["common", "common_crit", "rare", "mythic"]:
		var case: Dictionary = _ref["slam"][label]
		var result: Dictionary = _replay(case)
		_ok("%s: every one of %d ticks matches (sword pose, altitude and fall speed, phases; enemy position, health, knockback, stun, flash; hitstop, shake and its kick, kills, the slam's area, fields)" % [label, int(case["trace"]["ticks"])], String(result["diff"]).is_empty(), String(result["diff"]))
	var common: Dictionary = _ref["slam"]["common"]
	var run: GameRun = _run_of_setup(common["setup"])
	var sword: SwordState = run.swords[0]
	var starts: Array[int] = []
	var strikes: Array[int] = []
	var landings: Array[int] = []
	for step: int in range(1, int(common["trace"]["ticks"]) + 1):
		var before: int = sword.phase
		run.step()
		if before != SwordState.Phase.WINDUP and sword.phase == SwordState.Phase.WINDUP:
			starts.append(step)
		if before == SwordState.Phase.WINDUP and sword.phase == SwordState.Phase.STRIKE:
			strikes.append(step)
		if before == SwordState.Phase.STRIKE and sword.phase == SwordState.Phase.STUCK:
			landings.append(step)
	var want_starts: Array[int] = _transition_ticks(common, 0, "windup")
	var want_strikes: Array[int] = _transition_ticks(common, 0, "strike")
	var want_landings: Array[int] = _transition_ticks(common, 0, "stuck")
	_ok("attacks begin on ticks %s, fall on %s and land on %s as the prototype's %s / %s / %s (cooldown %.1f s, windup %.2f s); each strike is announced by a cue (%d) and each landing by a slam cue (%d)" % [starts, strikes, landings, want_starts, want_strikes, want_landings, sword.cooldown, sword.windup, run.cue_count(SimCue.Kind.SWORD_STRIKE), run.cue_count(SimCue.Kind.COLOSSUS_SLAM)],
		starts == want_starts and strikes == want_strikes and landings == want_landings and run.cue_count(SimCue.Kind.SWORD_STRIKE) == strikes.size() and run.cue_count(SimCue.Kind.COLOSSUS_SLAM) == landings.size() and landings.size() == 2)
	# The formula: each struck enemy lost `round(damage x falloff)` (the capture's slam log says who was struck and how far from the point).
	var slams: Array = common["slams"]
	var formula_ok: bool = true
	var detail: String = ""
	var replay: GameRun = _run_of_setup(common["setup"])
	var replay_enemies: Array[EnemyState] = replay.enemies.duplicate()
	var hp_before: Array[float] = [replay_enemies[0].hp, replay_enemies[1].hp]
	var slam_index: int = 0
	for step: int in range(1, int(common["trace"]["ticks"]) + 1):
		replay.step()
		if slam_index < slams.size() and int((slams[slam_index] as Dictionary)["tick"]) == step:
			for area: Variant in (slams[slam_index] as Dictionary)["area"]:
				var entry: Dictionary = area as Dictionary
				var k: int = int(entry["enemy"])
				var lost: float = hp_before[k] - replay_enemies[k].hp
				var expected: int = _expected_blow(50.0, 1.0, float(entry["dist"]), 118.0)
				if lost != float(expected):
					formula_ok = false
					detail += " slam %d enemy %d lost %.0f expected %d;" % [slam_index, k, lost, expected]
			slam_index += 1
		hp_before = [replay_enemies[0].hp, replay_enemies[1].hp]
	_ok("each blow is round(50 x (1 - 0.45 x distance / 118)): 50 at the centre down to 28 at the edge, both slams, nothing struck twice%s" % detail, formula_ok and slam_index == 2)
	var cue_run: GameRun = _run_of_setup(common["setup"])
	cue_run.take_cues()
	var slam_cues: Array[SimCue] = []
	var strike_cues: Array[SimCue] = []
	for step: int in range(1, int(common["trace"]["ticks"]) + 1):
		cue_run.step()
		for cue: SimCue in cue_run.take_cues():
			if cue.kind == SimCue.Kind.COLOSSUS_SLAM:
				slam_cues.append(cue)
			elif cue.kind == SimCue.Kind.SWORD_STRIKE:
				strike_cues.append(cue)
	var cues_ok: bool = slam_cues.size() == 2 and strike_cues.size() == 2
	for i: int in mini(slam_cues.size(), 2):
		var logged: Dictionary = slams[i]
		cues_ok = cues_ok and not slam_cues[i].critical and slam_cues[i].element == &"poison" and slam_cues[i].radius == 118.0 and slam_cues[i].amount == (logged["area"] as Array).size()
		cues_ok = cues_ok and slam_cues[i].position.distance_to(Vector2(float(logged["x"]), float(logged["y"]))) <= 0.01 and slam_cues[i].direction == Vector2.DOWN
	for cue: SimCue in strike_cues:
		cues_ok = cues_ok and cue.direction == Vector2.DOWN
	_ok("each landing is announced by a slam cue at the impact point with its radius (118), the number of enemies in reach and the sword's element, not marked a Cataclysm; each fall begins with a strike cue pointing down", cues_ok)
	var crit_case: Dictionary = _ref["slam"]["common_crit"]
	var crit_run: GameRun = _run_of_setup(crit_case["setup"])
	var crit_enemy: EnemyState = crit_run.enemies[0]
	var crit_start: float = crit_enemy.hp
	var first_dist: float = float(((crit_case["slams"] as Array)[0] as Dictionary)["area"][0]["dist"])
	_steps(crit_run, int((crit_case["slams"] as Array)[0]["tick"]))
	_ok("a critical slam doubles the blow before the falloff rounds (%.0f = %d) and its knockback is 1.3x" % [crit_start - crit_enemy.hp, _expected_blow(50.0, 1.0, first_dist, 118.0, true)], crit_start - crit_enemy.hp == float(_expected_blow(50.0, 1.0, first_dist, 118.0, true)))
	var boosted: GameRun = _run_of_setup(common["setup"])
	var boosted_target: EnemyState = boosted.enemies[0]
	boosted.swords[0].begin(boosted_target, boosted_target.position, 1.5)
	var start_hp: float = boosted_target.hp
	var dist_at_landing: float = 0.0
	for step: int in 80:
		dist_at_landing = (boosted_target.position - boosted.swords[0].impact).length()
		boosted.step()
		if boosted.swords[0].phase == SwordState.Phase.STUCK:
			break
	_ok("an attack's damage boost (Converge's 1.5x, issue #16) multiplies the slam's blow: 50 x 1.5 x falloff (%.0f = %d)" % [start_hp - boosted_target.hp, _expected_blow(50.0 * 1.5, 1.0, dist_at_landing, 118.0)], start_hp - boosted_target.hp > 0.0 and start_hp - boosted_target.hp == float(_expected_blow(50.0 * 1.5, 1.0, dist_at_landing, 118.0)))


func _check_acquire() -> void:
	print("colossus: who it targets (the biggest cluster within range, the nearer on equal counts)")
	for label: String in ["just_inside", "just_outside", "close"]:
		var case: Dictionary = _ref["acquire"][label]
		var run: GameRun = _run_of_setup(case["setup"])
		var left: int = -1
		for step: int in range(1, 60):
			run.step()
			if run.swords[0].phase != SwordState.Phase.IDLE and left < 0:
				left = step
		var want: int = -1 if case["left_idle"] == null else int(case["left_idle"])
		_ok("an enemy at %.0f px (range 330 + radius 16 = 346): the sword %s (tick %d vs %d)" % [float(case["distance"]), "acquires it" if left > 0 else "ignores it", left, want], left == want)
	var wrong: Array[String] = []
	var count: int = 0
	for key: String in _ref["acquire"]:
		if not key.begins_with("target_"):
			continue
		var case: Dictionary = _ref["acquire"][key]
		var run: GameRun = _run_of_setup(case["setup"])
		run.step()
		var index: int = run.enemies.find(run.swords[0].target) if run.swords[0].target != null else -1
		var want: int = -1 if case["target_index"] == null else int(case["target_index"])
		count += 1
		if index != want:
			wrong.append("%s: %d vs %d" % [key, index, want])
	_ok("the target of %d layouts (a cluster over a nearer lone foe, the nearest of a cluster, ties to the first in order, neighbours out of range and behind counted, 117 and 118 px edges, brutes and runners, the plain radius a Mythic counts with) matches the prototype: %s" % [count, wrong], wrong.is_empty() and count == 12)


func _check_timing() -> void:
	print("colossus: a slam begun at different moments of the idle bob lands on the prototype's ticks")
	var timing: Dictionary = _ref["timing"]
	var wrong: Array[String] = []
	var impacts: Array[int] = []
	var runs: Array = timing["runs"]
	for i: int in runs.size():
		var result: Dictionary = _replay(runs[i] as Dictionary)
		if not String(result["diff"]).is_empty():
			wrong.append("%d: %s" % [i, result["diff"]])
		var run: GameRun = result["run"]
		impacts.append(_transition_ticks(runs[i] as Dictionary, 0, "stuck")[0])
	_ok("slams begun at eight different moments of the idle bob (the altitude the windup climbs from differs) match the prototype on every tick (%s)" % [wrong], wrong.is_empty())
	var distinct: Dictionary = {}
	for tick: int in impacts:
		distinct[tick] = true
	var strikes: Array = timing["strike_ticks"]
	var gaps: Array[int] = []
	for i: int in impacts.size():
		gaps.append(impacts[i] - int(strikes[i]))
	_ok("the landing ticks %s follow when the windup began, each a fall of %s ticks after its strike (the windup's climb all but forgets where it began); the same as the prototype's %s" % [impacts, gaps, timing["impact_ticks"]], impacts == _int_array(timing["impact_ticks"]) and distinct.size() >= 6 and gaps.all(func(gap: int) -> bool: return gap == 11))


func _int_array(values: Array) -> Array[int]:
	var out: Array[int] = []
	for value: Variant in values:
		out.append(int(value))
	return out


func _check_geometry() -> void:
	print("colossus: what a slam reaches and how hard (area, falloff, knockback)")
	var geometry: Dictionary = _ref["geometry"]
	var setup: Dictionary = geometry["setup"]
	var target: Vector2 = _point(setup["target"])
	var total: int = 0
	var wrong: Array[String] = []
	var hit_distances: Dictionary = {}
	for key: String in geometry:
		if not key.begins_with("probe_"):
			continue
		var kind: String = key.split("_")[1]
		var rarity: int = int(key.split("_")[2].trim_prefix("r"))
		for cell: Variant in geometry[key]:
			var entry: Dictionary = cell as Dictionary
			var swords: Array = [{"type": "colossus", "rarity": rarity, "element": "poison", "cd": 99.0}, {"type": "colossus", "rarity": 0, "element": "ice", "cd": 99.0}, {"type": "colossus", "rarity": 0, "element": "fire", "cd": 99.0}]
			var run: GameRun = _lone_run(swords, [{"kind": kind, "x": target.x + float(entry["dist"]), "y": target.y, "hp": 900.0, "speed_scale": 0.0}])
			var probe: EnemyState = run.enemies[0]
			run.swords[0].begin(null, target)
			var landed: int = -1
			for step: int in range(1, 60):
				run.step()
				if run.swords[0].phase == SwordState.Phase.STUCK and landed < 0:
					landed = step
					break
			total += 1
			var hit: bool = probe.hp < 900.0
			var good: bool = landed == int(entry["slam_tick"]) and hit == bool(entry["hit"]) and _near(900.0 - probe.hp, float(entry["dealt"]), HP_TOL) and probe.velocity.distance_to(Vector2(float(entry["vx"]), float(entry["vy"]))) <= VELOCITY_TOL
			good = good and _near(probe.stun, float(entry["stun"]), SCALAR_TOL) and _near(probe.flash, float(entry["flash"]), SCALAR_TOL) and probe.position.distance_to(Vector2(float(entry["x"]), float(entry["y"]))) <= POSITION_TOL
			good = good and _near(run.hitstop, float(entry["hitstop"]), SCALAR_TOL) and _near(run.trauma, float(entry["trauma"]), SCALAR_TOL) and _near(run.kick.y, float(entry["kick_y"]), KICK_TOL)
			if not good:
				wrong.append("%s d=%s: hit %s dealt %.1f vs %s %s" % [key, entry["dist"], hit, 900.0 - probe.hp, entry["hit"], entry["dealt"]])
			if hit:
				hit_distances[key] = maxf(float(hit_distances.get(key, 0.0)), float(entry["dist"]))
	_ok("%d probes (husk and brute, Common and Mythic, 0.5 to 160 px from the impact) are struck or missed exactly as the prototype's, for the same damage, knockback, stun, flash, hitstop, shake and kick: %s" % [total, wrong], wrong.is_empty() and total == 56)
	_ok("the reach is the slam radius plus the target's own: a husk is struck out to 133 px and not at 134 (118 + 16), a brute to 147 (118 + 30), a Mythic's wider slam (139.24) reaches a husk at 149 and a brute at 148", hit_distances.get("probe_husk_r0", 0.0) == 133.0 and hit_distances.get("probe_brute_r0", 0.0) == 147.0 and hit_distances.get("probe_husk_r2", 0.0) == 149.0 and hit_distances.get("probe_brute_r2", 0.0) == 160.0, "%s" % [hit_distances])


func _check_empty_slam() -> void:
	print("colossus: an empty slam, and a corpse that still counts as something struck")
	var empty_case: Dictionary = _ref["empty_slam"]["empty"]
	var empty: Dictionary = _replay(empty_case)
	_ok("a slam with nothing in reach matches the prototype tick by tick", String(empty["diff"]).is_empty(), String(empty["diff"]))
	var landed: int = _transition_ticks(empty_case, 0, "stuck")[0]
	var run: GameRun = _run_of_setup(empty_case["setup"])
	run.swords[0].begin(null, _point((empty_case["setup"]["script"] as Array)[0]["aim"]))
	_steps(run, landed)
	_ok("an empty slam freezes gameplay for 0.04 s and shakes by 0.35, not the sword's 0.13 s and 0.6 (hitstop %.3f, trauma %.2f)" % [run.hitstop, run.trauma], _near(run.hitstop, 0.04, 0.0001) and _near(run.trauma, 0.35, 0.0001))
	var one: Dictionary = _replay(_ref["empty_slam"]["one_kill"])
	_ok("a slam that kills its only foe matches the prototype tick by tick", String(one["diff"]).is_empty(), String(one["diff"]))
	var corpse: Dictionary = _replay(_ref["empty_slam"]["two_slams_corpse"])
	var far: Dictionary = _replay(_ref["empty_slam"]["two_slams_corpse_far"])
	_ok("two Colossi slam on one tick, the first killing two foes that stand in the second's area: the second still counts them as struck (shake 0.6 + 0.6 caps at 1.0), as the prototype does", String(corpse["diff"]).is_empty(), String(corpse["diff"]))
	_ok("the same two slams with the dead outside the second's area: its area is empty (shake 0.6 + 0.35 = 0.95)", String(far["diff"]).is_empty(), String(far["diff"]))
	var trauma_corpse: float = (corpse["run"] as GameRun).trauma
	var landed_tick: int = _transition_ticks(_ref["empty_slam"]["two_slams_corpse"], 0, "stuck")[0]
	var run_c: GameRun = _run_of_setup(_ref["empty_slam"]["two_slams_corpse"]["setup"])
	var run_f: GameRun = _run_of_setup(_ref["empty_slam"]["two_slams_corpse_far"]["setup"])
	for pair: Array in [[run_c, _ref["empty_slam"]["two_slams_corpse"]], [run_f, _ref["empty_slam"]["two_slams_corpse_far"]]]:
		var pair_run: GameRun = pair[0]
		for op: Variant in (pair[1]["setup"]["script"] as Array):
			pair_run.swords[int((op as Dictionary)["sword"])].begin(null, _point((op as Dictionary)["aim"]))
		_steps(pair_run, landed_tick)
	_ok("the corpse is what raises the shake: %.2f with the dead in the second slam's area, %.2f without" % [run_c.trauma, run_f.trauma], _near(run_c.trauma, 1.0, 0.0001) and _near(run_f.trauma, 0.95, 0.0001) and trauma_corpse >= 0.0)


func _check_orbs() -> void:
	print("colossus: orbs a slam clears")
	var orbs_ref: Dictionary = _ref["orbs"]
	var target: Vector2 = _point(orbs_ref["setup"]["target"])
	var wrong: Array[String] = []
	var count: int = 0
	for cell: Variant in orbs_ref["grid"]:
		var entry: Dictionary = cell as Dictionary
		var swords: Array = [{"type": "colossus", "rarity": int(entry["rarity"]), "element": "poison", "cd": 99.0}, {"type": "colossus", "rarity": 0, "element": "ice", "cd": 99.0}, {"type": "colossus", "rarity": 0, "element": "fire", "cd": 99.0}]
		var run: GameRun = _lone_run(swords, [{"kind": "husk", "x": target.x + 400.0, "y": target.y, "hp": 900.0, "speed_scale": 0.0}])
		var orb: ProjectileState = ProjectileState.make(Vector2(float(entry["x"]), float(entry["y"])), Vector2.ZERO)
		orb.life = 10.0
		run.projectiles.append(orb)
		run.swords[0].begin(null, target)
		for step: int in range(1, 60):
			run.step()
			if run.swords[0].phase == SwordState.Phase.STUCK:
				break
		count += 1
		var cleared: bool = orb.fate == ProjectileState.Fate.CLEARED
		if cleared != bool(entry["cleared"]) or not _near(run.hitstop, float(entry["hitstop"]), SCALAR_TOL):
			wrong.append("r%s %s %s: cleared %s vs %s" % [entry["rarity"], entry["side"], entry["dist"], cleared, entry["cleared"]])
	_ok("%d orbs around a slam (Common and Mythic, east and north, 0 to 213 px) are cleared exactly when their centre is inside the radius (118, 139.24), with no padding for the orb's own size: %s" % [count, wrong], wrong.is_empty() and count == 40)
	var point: Vector2 = _point(orbs_ref["setup"]["point"])
	var ult_wrong: Array[String] = []
	var ult_count: int = 0
	var cleared_at: Dictionary = {}
	for cell: Variant in orbs_ref["cataclysm_grid"]:
		var entry: Dictionary = cell as Dictionary
		var swords: Array = [{"type": "colossus", "rarity": int(entry["rarity"]), "element": "poison", "cd": 99.0}, {"type": "colossus", "rarity": 0, "element": "ice", "cd": 99.0}, {"type": "colossus", "rarity": 0, "element": "fire", "cd": 99.0}]
		var run: GameRun = _lone_run(swords, [{"kind": "husk", "x": point.x - 400.0, "y": point.y, "hp": 900.0, "speed_scale": 0.0}])
		var orb: ProjectileState = ProjectileState.make(Vector2(float(entry["x"]), float(entry["y"])), Vector2.ZERO)
		orb.life = 10.0
		run.projectiles.append(orb)
		run.apply(GameCommand.ultimate(0, point))
		_steps(run, 120)
		ult_count += 1
		var cleared: bool = orb.fate == ProjectileState.Fate.CLEARED
		if cleared != bool(entry["cleared"]):
			ult_wrong.append("r%s %s: cleared %s vs %s" % [entry["rarity"], entry["dist"], cleared, entry["cleared"]])
		if cleared:
			cleared_at[int(entry["rarity"])] = maxf(float(cleared_at.get(int(entry["rarity"]), 0.0)), float(entry["dist"]))
	_ok("%d orbs around a Cataclysm are cleared inside 212.4 px (Mythic 250.6) and no farther: %s" % [ult_count, ult_wrong], ult_wrong.is_empty() and ult_count == 14 and cleared_at.get(0, 0.0) == 212.0 and cleared_at.get(2, 0.0) == 250.0, "%s" % [cleared_at])
	var quirk: Dictionary = orbs_ref["destroyed_orb_still_hurts_in_the_prototype"]
	var run_q: GameRun = _run_of_setup(quirk["setup"])
	var enemies_q: Array[EnemyState] = run_q.enemies.duplicate()
	run_q.iframes = float(quirk["setup"]["iframes"])
	run_q.swords[0].begin(null, _point((quirk["setup"]["script"] as Array)[0]["aim"]))
	var landed_q: int = -1
	for step: int in range(1, 80):
		run_q.step()
		if run_q.swords[0].phase == SwordState.Phase.STUCK and landed_q < 0:
			landed_q = step
	_steps(run_q, 0)
	_ok("DELIBERATE EXCEPTION (shared with issue #10): an orb a slam destroys on a tick is not also moved and hurt the player; the prototype's loop still moves it and hurts the player for 8 (%.0f health) where the port keeps %.0f, with no hurt cue" % [float(quirk["player_hp_prototype"]), run_q.hp],
		bool(quirk["orb_dead"]) and float(quirk["player_hp_prototype"]) == 92.0 and landed_q == int(quirk["landing_tick"]) and run_q.hp == 100.0 and run_q.cue_count(SimCue.Kind.PLAYER_HURT) == 0 and run_q.projectiles.is_empty() and not enemies_q.is_empty())
	var flight: Dictionary = _replay(orbs_ref["orbs_in_flight"])
	_ok("orbs flying across a walking husk's slam (some cleared, the rest on to the player) match the prototype on every tick", String(flight["diff"]).is_empty(), String(flight["diff"]))
	var flight_run: GameRun = flight["run"]
	_ok("they resolve exactly once each (%s) and the slam cleared at least one of them" % [(flight["orbs"] as Array).map(func(p: ProjectileState) -> int: return p.fate)], (flight["orbs"] as Array).any(func(p: ProjectileState) -> bool: return p.fate == ProjectileState.Fate.CLEARED) and flight_run.cue_count(SimCue.Kind.PROJECTILE_PARRIED) == 0)


func _check_deaths() -> void:
	print("colossus: deaths in and around a slam resolve once; corpses are in the loops as in the prototype")
	var deaths: Dictionary = _ref["deaths"]
	var kills_case: Dictionary = deaths["kills_in_slam"]
	var kills: Dictionary = _replay(kills_case)
	var kills_run: GameRun = kills["run"]
	_ok("a slam kills the weak and leaves the strong: every tick matches (kills %d, combo %d, motes %d, left %d)" % [kills_run.kills, kills_run.combo, kills_run.motes.size(), kills_run.enemies.size()],
		String(kills["diff"]).is_empty() and kills_run.kills == int(kills_case["kills"]) and kills_run.combo == int(kills_case["combo"]) and kills_run.motes.size() == int(kills_case["motes"]) and kills_run.enemies.size() == int(kills_case["left"]), String(kills["diff"]))
	_ok("each death is announced once and pays its three motes once (%d kill cues, %d motes)" % [kills_run.cue_count(SimCue.Kind.ENEMY_KILLED), kills_run.motes.size()], kills_run.cue_count(SimCue.Kind.ENEMY_KILLED) == kills_run.kills and kills_run.motes.size() == 3 * kills_run.kills)
	var windup: Dictionary = _replay(deaths["target_killed_in_the_windup"])
	var windup_run: GameRun = windup["run"]
	_ok("the target killed from outside during the windup is dropped: the sword still lands on the point it was going to and crushes its neighbours, tick by tick as the prototype's (%d slams)" % windup_run.cue_count(SimCue.Kind.COLOSSUS_SLAM), String(windup["diff"]).is_empty() and windup_run.cue_count(SimCue.Kind.COLOSSUS_SLAM) >= 1, String(windup["diff"]))
	var cluster_case: Dictionary = deaths["corpse_cluster_is_targeted"]
	var cluster: Dictionary = _replay(cluster_case)
	var cluster_run: GameRun = cluster["run"]
	var second_windup: Array[int] = _transition_ticks(cluster_case, 1, "windup")
	_ok("the dead cluster is a target: the second Colossus, looking on the very tick the first one's slam killed four foes, finds them still in the run's list, counts them and winds up on them (tick %s) instead of the living foe; every tick matches" % [second_windup], String(cluster["diff"]).is_empty() and second_windup == _int_array(cluster_case["second_windup_tick"]) and second_windup[0] == int(cluster_case["setup"]["slam_tick"]), String(cluster["diff"]))
	_ok("and that slam lands on a spot with nobody left in it, the living foe untouched (hp %.0f)" % cluster_run.enemies[0].hp, cluster_run.enemies.size() == 1 and cluster_run.enemies[0].hp == 900.0)
	var fall: Dictionary = _replay(deaths["player_dies_in_the_fall"])
	var fall_run: GameRun = fall["run"]
	_ok("the player dies in the middle of a fall: the sword goes idle where it is, no slam happens and its altitude sinks (%.0f px), every tick as the prototype's" % fall_run.swords[0].altitude, String(fall["diff"]).is_empty() and fall_run.dead and fall_run.cue_count(SimCue.Kind.COLOSSUS_SLAM) == 0 and fall_run.swords[0].phase == SwordState.Phase.IDLE, String(fall["diff"]))


# ------------------------------------------------------------- Cataclysm
func _check_start() -> void:
	print("colossus: Cataclysm's start (a targeted ultimate pulled back onto 480 px) and what it interrupts")
	var start: Dictionary = _ref["start"]
	var points: Dictionary = start["points"]
	var wrong: Array[String] = []
	for label: String in points:
		var entry: Dictionary = points[label]
		var run: GameRun = _run_of_setup(start["setup"])
		_steps(run, 5)
		var sword: SwordState = run.swords[0]
		var before: Vector2 = sword.position
		run.apply(GameCommand.ultimate(0, _point(entry["point"])))
		var good: bool = _state_name(sword) == String(entry["phase"]) and sword.ultimate_point.distance_to(Vector2(float(entry["x"]), float(entry["y"]))) <= POSITION_TOL and _near(sword.ultimate_time_left, float(entry["ult_t"]), SCALAR_TOL)
		good = good and _near(sword.ultimate_cooldown_left, float(entry["ult_cd"]), SCALAR_TOL) and sword.position.distance_to(before) == 0.0 and _near(sword.altitude, float(entry["z"]), POSITION_TOL)
		if not good:
			wrong.append("%s: %s -> %s" % [label, sword.ultimate_point, Vector2(float(entry["x"]), float(entry["y"]))])
	_ok("the landing point, rise clock (0.75 s), recharge (14 s) and unmoved sword for %d points (inside, at and past the 480 px range, diagonal, south, on the player, far west) match the prototype: %s" % [points.size(), wrong], wrong.is_empty() and points.size() == 7)
	var clamp_run: GameRun = _run_of_setup(start["setup"])
	clamp_run.apply(GameCommand.ultimate(0, CENTER + Vector2(700.0, 0.0)))
	_ok("a point past the range is pulled back onto it, measured from the player: 700 px east becomes 480 px east (%s)" % clamp_run.swords[0].ultimate_point, clamp_run.swords[0].ultimate_point.distance_to(CENTER + Vector2(480.0, 0.0)) <= 0.001)
	for label: String in ["interrupts_windup", "interrupts_fall", "interrupts_stuck"]:
		var case: Dictionary = start[label]
		var result: Dictionary = _replay(case)
		var run: GameRun = _run_of_setup(case["setup"])
		var wanted_before: String = String(case["state_before"])
		var ticks_before: int = int(((case["setup"]["script"] as Array)[0] as Dictionary)["t"])
		_steps(run, ticks_before)
		_ok("a Cataclysm pressed in the %s phase (the sword was %s) takes over and runs on, every tick as the prototype's (altitude carried on from %.0f px)" % [label.trim_prefix("interrupts_"), wanted_before, run.swords[0].altitude], String(result["diff"]).is_empty() and _state_name(run.swords[0]) == wanted_before, String(result["diff"]))


func _check_single() -> void:
	print("colossus: one Cataclysm, rise to field, tick by tick")
	for label: String in ["common", "common_crit", "rare", "mythic"]:
		var case: Dictionary = _ref["single"][label]
		var result: Dictionary = _replay(case)
		_ok("%s: every one of %d ticks matches (rise, altitude and fall speed, the slam, knockback, shake, the field's life and clock)" % [label, int(case["trace"]["ticks"])], String(result["diff"]).is_empty(), String(result["diff"]))
	var common: Dictionary = _ref["single"]["common"]
	var run: GameRun = _run_of_setup(common["setup"])
	var sword: SwordState = run.swords[0]
	var point: Vector2 = _point((common["setup"]["script"] as Array)[0]["point"])
	run.apply(GameCommand.ultimate(0, point))
	var rises: int = 0
	var landed: int = -1
	var peak: float = 0.0
	var landing_spot: Vector2 = Vector2.ZERO
	for step: int in range(1, int(common["trace"]["ticks"]) + 1):
		run.step()
		peak = maxf(peak, sword.altitude)
		if _state_name(sword) == "ult_rise":
			rises += 1
		if sword.phase == SwordState.Phase.STUCK and landed < 0:
			landed = step
			landing_spot = sword.position
	var slam: Dictionary = (common["slams"] as Array)[0]
	_ok("it rises for %d ticks (0.75 s: the 45th turns it into a fall), climbing to %.0f px, and lands on tick %d (the prototype's %d), exactly on the point %s, with the area %.1f px (118 x 1.8)" % [rises, peak, landed, int(slam["tick"]), point, float(slam["radius"])],
		rises == 44 and landed == int(slam["tick"]) and landing_spot.distance_to(point) <= 0.01 and _near(float(slam["radius"]), 212.4, 0.0001) and peak > 300.0)
	var cat_run: GameRun = _run_of_setup(common["setup"])
	cat_run.apply(GameCommand.ultimate(0, point))
	var cat_cues: Array[SimCue] = []
	for step: int in 70:
		cat_run.step()
		cat_cues.append_array(cat_run.take_cues())
	var cat_slams: Array[SimCue] = cat_cues.filter(func(cue: SimCue) -> bool: return cue.kind == SimCue.Kind.COLOSSUS_SLAM)
	var cat_fields: Array[SimCue] = cat_cues.filter(func(cue: SimCue) -> bool: return cue.kind == SimCue.Kind.FIELD_CREATED)
	_ok("the landing is one slam cue marked as a Cataclysm (radius 212.4, six enemies in reach, poison) and the field one cue at the point (radius 233.64, poison)",
		cat_slams.size() == 1 and cat_slams[0].critical and _near(cat_slams[0].radius, 212.4, 0.0001) and cat_slams[0].amount == 6 and cat_slams[0].element == &"poison" and cat_slams[0].position.distance_to(point) <= 0.01
		and cat_fields.size() == 1 and _near(cat_fields[0].radius, 233.64, 0.001) and cat_fields[0].element == &"poison" and cat_fields[0].position.distance_to(point) <= 0.01)
	var blow_ok: bool = true
	var detail: String = ""
	var check_run: GameRun = _run_of_setup(common["setup"])
	var check_enemies: Array[EnemyState] = check_run.enemies.duplicate()
	var hp_before: Array[float] = []
	for enemy: EnemyState in check_enemies:
		hp_before.append(enemy.hp)
	check_run.apply(GameCommand.ultimate(0, point))
	_steps(check_run, int(slam["tick"]))
	for area: Variant in slam["area"]:
		var entry: Dictionary = area as Dictionary
		var k: int = int(entry["enemy"])
		var lost: float = hp_before[k] - check_enemies[k].hp
		var expected: int = _expected_blow(50.0, 2.2, float(entry["dist"]), 212.4)
		if lost != float(expected):
			blow_ok = false
			detail += " enemy %d lost %.0f expected %d;" % [k, lost, expected]
	_ok("every enemy in the area took round(50 x 2.2 x (1 - 0.45 x distance / 212.4)): 110 at the centre down to 63 at 202 px (%d struck)%s" % [(slam["area"] as Array).size(), detail], blow_ok and (slam["area"] as Array).size() == 6)
	_ok("an enemy beyond the area was left alone: the one 252 px from the point has all its health", check_enemies[6].hp == 900.0)
	_ok("it leaves ONE field at the point: %.1f px wide (1.1 x 212.4), %.0f s of life, poison at the sword's damage; a cue announces it (%d)" % [212.4 * 1.1, 5.0, check_run.cue_count(SimCue.Kind.FIELD_CREATED)], check_run.fields.size() == 1 and check_run.cue_count(SimCue.Kind.FIELD_CREATED) == 1 and _near(check_run.fields[0].radius, 233.64, 0.001) and check_run.fields[0].position == point and check_run.fields[0].element == &"poison" and check_run.fields[0].power == 50.0)
	var field_ticks: Array[int] = [-1]
	var life_run: GameRun = _run_of_setup(common["setup"])
	life_run.apply(GameCommand.ultimate(0, point))
	for step: int in range(1, int(common["trace"]["ticks"]) + 1):
		life_run.step()
		if not life_run.fields.is_empty():
			field_ticks.append(step)
	field_ticks.remove_at(0)
	if field_ticks.is_empty():
		field_ticks.append(-1)
	var field_column: Array[int] = _int_array(common["trace"]["run"]["fields"])
	var first_tick: int = field_column.find(1) + 1
	var last_tick: int = field_column.rfind(1) + 1
	_ok("the field lives from tick %d to %d (the prototype's %d to %d): 5 s of gameplay time plus the hitstop it froze through" % [field_ticks[0], field_ticks[-1], first_tick, last_tick], field_ticks[0] == first_tick and field_ticks[-1] == last_tick and field_ticks.size() == last_tick - first_tick + 1 and life_run.fields.is_empty())
	var crit_case: Dictionary = _ref["single"]["common_crit"]
	var crit_run: GameRun = _run_of_setup(crit_case["setup"])
	var crit_enemies: Array[EnemyState] = crit_run.enemies.duplicate()
	crit_run.apply(GameCommand.ultimate(0, point))
	_steps(crit_run, int((crit_case["slams"] as Array)[0]["tick"]))
	var crit_first: Dictionary = ((crit_case["slams"] as Array)[0] as Dictionary)["area"][0]
	_ok("a critical Cataclysm doubles every blow: the nearest foe loses %.0f = %d" % [900.0 - crit_enemies[0].hp, _expected_blow(50.0, 2.2, float(crit_first["dist"]), 212.4, true)], 900.0 - crit_enemies[0].hp == float(_expected_blow(50.0, 2.2, float(crit_first["dist"]), 212.4, true)))


func _check_edge() -> void:
	print("colossus: a Cataclysm's reach")
	var edge: Dictionary = _ref["edge"]
	var point: Vector2 = _point(edge["setup"]["point"])
	var wrong: Array[String] = []
	var reached: Dictionary = {}
	for key: String in edge:
		if not key.begins_with("probe_"):
			continue
		var kind: String = key.trim_prefix("probe_")
		for cell: Variant in edge[key]:
			var entry: Dictionary = cell as Dictionary
			var run: GameRun = _lone_run(_trio(0, 99.0), [{"kind": kind, "x": point.x + float(entry["dist"]), "y": point.y, "hp": 900.0, "speed_scale": 0.0}])
			var probe: EnemyState = run.enemies[0]
			run.apply(GameCommand.ultimate(0, point))
			var landed: int = -1
			for step: int in range(1, 100):
				run.step()
				if run.swords[0].phase == SwordState.Phase.STUCK and landed < 0:
					landed = step
					break
			var hit: bool = probe.hp < 900.0
			if hit:
				reached[kind] = maxf(float(reached.get(kind, 0.0)), float(entry["dist"]))
			if landed != int(entry["slam_tick"]) or hit != bool(entry["hit"]) or not _near(900.0 - probe.hp, float(entry["dealt"]), HP_TOL) or probe.velocity.distance_to(Vector2(float(entry["vx"]), float(entry["vy"]))) > VELOCITY_TOL:
				wrong.append("%s %s: hit %s dealt %.1f vs %s %s" % [kind, entry["dist"], hit, 900.0 - probe.hp, entry["hit"], entry["dealt"]])
	_ok("probes at the edge of a Cataclysm (husk 211 to 230 px, brute 242 to 245 px) are struck or missed as the prototype's: a husk out to 228 (212.4 + 16), a brute to 242 (212.4 + 30), for the same damage and knockback: %s" % [wrong], wrong.is_empty() and reached.get("husk", 0.0) == 228.0 and reached.get("brute", 0.0) == 242.0, "%s" % [reached])


# ----------------------------------------------------------------- fields
func _check_conditions() -> void:
	print("colossus: the slam's doses and the field's cadence, per element, on every tick (conditions on)")
	for element: String in ["poison", "ice", "fire"]:
		var case: Dictionary = _ref["conditions"][element]
		var result: Dictionary = _replay(case)
		_ok("%s: every one of %d ticks matches (condition timers, stacks, damage over time and health of three enemies in the field; the field's life and clock; each pulse)" % [element, int(case["trace"]["ticks"])], String(result["diff"]).is_empty(), String(result["diff"]))
	# The cadence, read from the real simulation: one dose on the impact tick (the field ticks the tick it is made), then every
	# 31 ticks of gameplay time (0.5 s of dt does not quite run out in 30), not counting the ticks hitstop froze.
	var case_p: Dictionary = _ref["conditions"]["poison"]
	var run: GameRun = _run_of_setup(case_p["setup"])
	var enemy: EnemyState = run.enemies[1]
	run.apply(GameCommand.ultimate(0, _point((case_p["setup"]["script"] as Array)[0]["point"])))
	var pulse_ticks: Array[int] = []
	var stacks_at_pulse: Array[int] = []
	for step: int in range(1, int(case_p["trace"]["ticks"]) + 1):
		var before: int = run.cue_count(SimCue.Kind.FIELD_PULSED)
		run.step()
		if run.cue_count(SimCue.Kind.FIELD_PULSED) > before:
			pulse_ticks.append(step)
			stacks_at_pulse.append(enemy.conditions.poison_stacks)
	var want_pulses: Array = []
	for i: int in (case_p["trace"]["run"]["pulses"] as Array).size():
		if int((case_p["trace"]["run"]["pulses"] as Array)[i]) > 0:
			want_pulses.append(i + 1)
	_ok("poison stacks 4 on the impact tick (the slam's three doses and the field's first), then 5, then the cap of 6 on the pulses at ticks %s (the prototype's %s)" % [pulse_ticks, want_pulses], pulse_ticks == _int_array(want_pulses) and stacks_at_pulse.slice(0, 3) == [4, 5, 6] and stacks_at_pulse.size() == 10)
	var ice_run: GameRun = _run_of_setup(_ref["conditions"]["ice"]["setup"])
	var ice_enemies: Array[EnemyState] = ice_run.enemies.duplicate()
	ice_run.apply(GameCommand.ultimate(0, _point((_ref["conditions"]["ice"]["setup"]["script"] as Array)[0]["point"])))
	var landed_ice: int = int(((_ref["conditions"]["ice"]["slams"] as Array)[0] as Dictionary)["tick"])
	_steps(ice_run, landed_ice)
	_ok("an ice Cataclysm freezes everyone it struck on the impact tick (the slam's three doses plus the field's first make four; a brute for 0.96 s, a husk for 1.6 s: %.2f / %.2f / %.2f), %d frozen cues" % [ice_enemies[0].conditions.frozen, ice_enemies[1].conditions.frozen, ice_enemies[2].conditions.frozen, ice_run.cue_count(SimCue.Kind.ENEMY_FROZEN)],
		ice_enemies.all(func(e: EnemyState) -> bool: return e.conditions.is_frozen()) and _near(ice_enemies[1].conditions.frozen, 0.96, 0.001) and _near(ice_enemies[0].conditions.frozen, 1.6, 0.001) and ice_run.cue_count(SimCue.Kind.ENEMY_FROZEN) == 3)
	var fire_run: GameRun = _run_of_setup(_ref["conditions"]["fire"]["setup"])
	var fire_enemies: Array[EnemyState] = fire_run.enemies.duplicate()
	fire_run.apply(GameCommand.ultimate(0, _point((_ref["conditions"]["fire"]["setup"]["script"] as Array)[0]["point"])))
	_steps(fire_run, int(((_ref["conditions"]["fire"]["slams"] as Array)[0] as Dictionary)["tick"]))
	var power: float = fire_run.swords[0].damage
	_ok("a fire Cataclysm leaves every enemy it struck burning at (1.5 + 0.2 x power) x 3 doses = %.1f per second for 3 s, and the field's dose cannot weaken it" % ConditionDefs.burn_dps(power, 3),
		fire_enemies.all(func(e: EnemyState) -> bool: return e.conditions.is_burning() and _near(e.conditions.burn_dps, ConditionDefs.burn_dps(power, 3), 0.001) and _near(e.conditions.burn, 3.0, 0.001)))
	var no_conditions: GameRun = GameRun.new(_scenario({"conditions": false, "swords": _trio(0, 99.0), "enemies": [_husk_at(325.0, -5.0)]}))
	var plain_husk: EnemyState = no_conditions.enemies[0]
	no_conditions.apply(GameCommand.ultimate(0, CENTER + Vector2(300.0, -20.0)))
	_steps(no_conditions, 120)
	_ok("in a condition-free fixture the field still stands and pulses but applies nothing (%d pulses, poison %d)" % [no_conditions.cue_count(SimCue.Kind.FIELD_PULSED), plain_husk.conditions.poison_stacks], no_conditions.cue_count(SimCue.Kind.FIELD_PULSED) >= 2 and plain_husk.conditions.poison_stacks == 0)


func _check_field_reach() -> void:
	print("colossus: which enemies a field doses (centre within radius + the enemy's own)")
	var reach: Dictionary = _ref["field_reach"]
	var point: Vector2 = _point(reach["setup"]["point"])
	var wrong: Array[String] = []
	var inside: Dictionary = {}
	for key: String in reach:
		if not key.begins_with("probe_"):
			continue
		var kind: String = key.trim_prefix("probe_")
		for cell: Variant in reach[key]:
			var entry: Dictionary = cell as Dictionary
			var run: GameRun = GameRun.new(_scenario({"conditions": true, "swords": _trio(0, 99.0), "enemies": [{"kind": kind, "x": point.x + float(entry["dist"]), "y": point.y, "hp": 2000.0, "speed_scale": 0.0}]}))
			var probe: EnemyState = run.enemies[0]
			run.apply(GameCommand.ultimate(0, point))
			var rows: Array = entry["poison_rows"]
			var diff: String = ""
			for step: int in range(1, rows.size() + 1):
				run.step()
				if diff.is_empty() and probe.conditions.poison_stacks != int(rows[step - 1]):
					diff = "tick %d: %d stacks vs %s" % [step, probe.conditions.poison_stacks, rows[step - 1]]
			if not diff.is_empty() or probe.conditions.poison_stacks != int(entry["poison"]):
				wrong.append("%s %s: %s" % [kind, entry["dist"], diff])
			if probe.conditions.poison_stacks > 0:
				inside[kind] = maxf(float(inside.get(kind, 0.0)), float(entry["dist"]))
	_ok("%d probes around the field's edge (husk 246 to 253 px, brute 260 to 267 px, all outside the slam's own area) are dosed or not exactly as the prototype's: a husk out to 249.5 (1.1 x 212.4 = 233.64, plus 16) and not at 249.75, a brute to 263.5 (plus 30) and not at 263.75: %s" % [(reach["probe_husk"] as Array).size() + (reach["probe_brute"] as Array).size(), wrong],
		wrong.is_empty() and inside.get("husk", 0.0) == 249.5 and inside.get("brute", 0.0) == 263.5, "%s" % [inside])


func _check_overlap() -> void:
	print("colossus: overlapping fields (each has its own clock; an enemy in both is dosed by both)")
	for label: String in ["same_tick", "twenty_ticks_apart", "three_elements"]:
		var case: Dictionary = _ref["overlap"][label]
		var result: Dictionary = _replay(case)
		_ok("%s: every one of %d ticks matches (both elements' timers, stacks and damage on three enemies standing in both fields)" % [label, int(case["trace"]["ticks"])], String(result["diff"]).is_empty(), String(result["diff"]))
	var apart: Dictionary = _replay(_ref["overlap"]["twenty_ticks_apart"])
	var apart_run: GameRun = apart["run"]
	var counts: Array[int] = _int_array(_ref["overlap"]["twenty_ticks_apart"]["trace"]["run"]["fields"])
	var gap: int = counts.find(2) - counts.find(1)
	var mine: Array[int] = []
	var gap_run: GameRun = _run_of_setup(_ref["overlap"]["twenty_ticks_apart"]["setup"])
	for step: int in counts.size():
		for op: Variant in (_ref["overlap"]["twenty_ticks_apart"]["setup"]["script"] as Array):
			if int((op as Dictionary)["t"]) == step:
				gap_run.apply(GameCommand.ultimate("qer".find(String((op as Dictionary)["key"])), _point((op as Dictionary)["point"])))
		gap_run.step()
		mine.append(gap_run.fields.size())
	_ok("two fields stand together (%d at the end of the replay) and pulse on their own clocks: the second was made %d ticks after the first (twenty ticks later plus the first slam's hitstop), the prototype's %d" % [apart_run.fields.size(), mine.find(2) - mine.find(1), gap], apart_run.fields.size() == 2 and mine.find(2) - mine.find(1) == gap and gap > 20)
	var three: Dictionary = _replay(_ref["overlap"]["three_elements"])
	var three_run: GameRun = three["run"]
	_ok("three Colossi leave poison, ice and fire fields; the cues name each element (%d created) and the run tracks all of them (%d at most)" % [three_run.cue_count(SimCue.Kind.FIELD_CREATED), _int_array(_ref["overlap"]["three_elements"]["trace"]["run"]["fields"]).max()], three_run.cue_count(SimCue.Kind.FIELD_CREATED) == 3 and _int_array(_ref["overlap"]["three_elements"]["trace"]["run"]["fields"]).max() == 3)


func _check_field_deaths() -> void:
	print("colossus: deaths inside fields (burned or poisoned down, corpses skipped, the player's death)")
	var fire: Dictionary = _ref["field_deaths"]["burn_down_fire"]
	var fire_result: Dictionary = _replay(fire)
	var fire_run: GameRun = fire_result["run"]
	_ok("a fire Cataclysm burns down the enemies that survived its slam, and a burning death ignites its neighbours: every tick matches (kills %d, combo %d, motes %d)" % [fire_run.kills, fire_run.combo, fire_run.motes.size()],
		String(fire_result["diff"]).is_empty() and fire_run.kills == int(fire["kills"]) and fire_run.motes.size() == int(fire["motes"]) and fire_run.kills >= 3, String(fire_result["diff"]))
	_ok("each of those deaths came from the condition's damage over time, not from a blow after the slam (%d slam, %d blows, %d kills, %d spreads)" % [fire_run.cue_count(SimCue.Kind.COLOSSUS_SLAM), fire_run.cue_count(SimCue.Kind.ENEMY_HIT), fire_run.kills, fire_run.cue_count(SimCue.Kind.FIRE_SPREAD)], fire_run.cue_count(SimCue.Kind.COLOSSUS_SLAM) == 1 and fire_run.cue_count(SimCue.Kind.ENEMY_HIT) == 5 and fire_run.cue_count(SimCue.Kind.FIRE_SPREAD) >= 1 and fire_run.cue_count(SimCue.Kind.CONDITION_DAMAGE) >= 5)
	var poison: Dictionary = _ref["field_deaths"]["burn_down_poison"]
	var poison_result: Dictionary = _replay(poison)
	var poison_run: GameRun = poison_result["run"]
	_ok("a poison Cataclysm poisons the survivors down (kills %d): every tick matches" % poison_run.kills, String(poison_result["diff"]).is_empty() and poison_run.kills == int(poison["kills"]) and poison_run.kills >= 2, String(poison_result["diff"]))
	var corpse: Dictionary = _ref["field_deaths"]["corpse_on_a_pulse_tick"]
	var corpse_result: Dictionary = _replay(corpse)
	var corpse_run: GameRun = corpse_result["run"]
	var pulse_ticks: Array = []
	for i: int in (corpse["trace"]["run"]["pulses"] as Array).size():
		if int((corpse["trace"]["run"]["pulses"] as Array)[i]) > 0:
			pulse_ticks.append(i + 1)
	var slam_ticks: Array = []
	for slam: Variant in corpse["slams"]:
		slam_ticks.append(int((slam as Dictionary)["tick"]))
	_ok("a second Colossus kills two enemies standing in the field on the very tick the field pulses (slams %s, pulses %s): the field's loop skips the corpses and doses only the survivor (%s doses on that tick)" % [slam_ticks, pulse_ticks, (corpse["trace"]["run"]["pulses"] as Array)[slam_ticks[1] - 1]],
		String(corpse_result["diff"]).is_empty() and slam_ticks[1] in pulse_ticks and int((corpse["trace"]["run"]["pulses"] as Array)[slam_ticks[1] - 1]) == 1, String(corpse_result["diff"]))
	_ok("and the corpses stayed in the loop only for that tick: two kills, two kill cues, the survivor still in the field (%d left)" % corpse_run.enemies.size(), corpse_run.kills == 2 and corpse_run.cue_count(SimCue.Kind.ENEMY_KILLED) == 2 and corpse_run.enemies.size() == 1)
	var dies: Dictionary = _ref["field_deaths"]["player_dies_field_goes_on"]
	var dies_result: Dictionary = _replay(dies)
	var dies_run: GameRun = dies_result["run"]
	_ok("the player dies with a field down: it goes on pulsing (%d pulses in all, the death in slow motion at tick 80), every tick as the prototype's" % dies_run.cue_count(SimCue.Kind.FIELD_PULSED), String(dies_result["diff"]).is_empty() and dies_run.dead and dies_run.cue_count(SimCue.Kind.FIELD_PULSED) >= 3, String(dies_result["diff"]))


# ------------------------------------------------------------ rules, keys
func _check_rules() -> void:
	print("colossus: Cataclysm's recharge, refusals and the ready tick")
	for rarity: int in 3:
		var case: Dictionary = _ref["rules"]["rarity_%d" % rarity]
		var result: Dictionary = _replay_presses(case)
		var run: GameRun = result["run"]
		var want_recharge: float = [14.0, 12.18, 10.36][rarity]
		_ok("rarity %d (recharge %.2f s): the first press starts it, the presses while it runs (rise) and while it recharges (after the slam, at 200) are refused, the six presses around tick %d start it exactly once, on the first tick it is ready (%d); each press matches the prototype's" % [rarity, want_recharge, int(case["ready_tick"]), int(result["ready"])],
			String(result["diff"]).is_empty() and int(result["ready"]) == int(case["ready_tick"]) and _near(run.swords[0].ultimate_cooldown, want_recharge, 0.0001), String(result["diff"]))
		var started: int = 0
		for press: Dictionary in result["presses"]:
			started += 1 if bool(press["started"]) else 0
		_ok("rarity %d: exactly two of its presses started a Cataclysm (the first and the one after the recharge); %d refusal cues" % [rarity, run.cue_count(SimCue.Kind.ULTIMATE_REFUSED)], started == 2 and run.cue_count(SimCue.Kind.ULTIMATE_REFUSED) >= 2 and run.cue_count(SimCue.Kind.ULTIMATE_STARTED) == 2)
	var others: Dictionary = _replay(_ref["rules"]["others_keep_slamming"])
	var others_run: GameRun = others["run"]
	_ok("while slot one is in its Cataclysm the other two Colossi keep slamming walking enemies (%d slams, one a Cataclysm), every tick matching the prototype" % others_run.cue_count(SimCue.Kind.COLOSSUS_SLAM), String(others["diff"]).is_empty() and others_run.cue_count(SimCue.Kind.COLOSSUS_SLAM) >= 3, String(others["diff"]))


func _check_keys() -> void:
	print("colossus: Q, E and R and touch aiming")
	var keys: Dictionary = _ref["keys"]
	var point: Vector2 = CENTER + Vector2(300.0, -20.0)
	for name: String in ["q", "e", "r"]:
		var run: GameRun = _run_of_setup(keys["setup"])
		var slot: int = "qer".find(name)
		run.apply(GameCommand.ultimate(slot, point))
		_ok("%s starts slot %d's Cataclysm and nobody else's (%s vs %s)" % [name.to_upper(), slot + 1, _states(run), keys["key_" + name]], _same_strings(_states(run), keys["key_" + name]))
	var paused: GameRun = _run_of_setup(keys["setup"])
	paused.apply(GameCommand.pause())
	paused.apply(GameCommand.ultimate(0, point))
	_ok("a Cataclysm pressed while paused starts nothing and uses no recharge", _same_strings(_states(paused), keys["paused_q"]["states"]) and paused.swords[0].ultimate_cooldown_left == 0.0)
	var dead: GameRun = _run_of_setup(keys["setup"])
	dead.hurt_player(1000, CENTER + Vector2(50.0, 0.0))
	dead.apply(GameCommand.ultimate(1, point))
	_ok("a Cataclysm pressed by a dead player starts nothing", _same_strings(_states(dead), keys["dead_e"]["states"]) and dead.swords[1].ultimate_cooldown_left == 0.0)
	var aim_case: Dictionary = keys["auto_aim"]
	var touch: GameRun = _run_of_setup(aim_case["setup"])
	var aim: Vector2 = touch.auto_aim()
	touch.apply(GameCommand.ultimate(0, aim))
	_ok("touch aiming at the nearest enemy lands the Cataclysm on it (%s)" % touch.swords[0].ultimate_point, aim.distance_to(_point(aim_case["nearest"])) <= POSITION_TOL and touch.swords[0].ultimate_point.distance_to(_point(aim_case["point"])) <= POSITION_TOL)
	var empty_case: Dictionary = keys["auto_aim_empty"]
	var touch_empty: GameRun = _run_of_setup(empty_case["setup"])
	var aim_empty: Vector2 = touch_empty.auto_aim()
	touch_empty.apply(GameCommand.ultimate(0, aim_empty))
	_ok("with no enemy the touch aim is 300 px ahead of the player and the Cataclysm lands there (%s)" % touch_empty.swords[0].ultimate_point, aim_empty.distance_to(_point(empty_case["aim"])) <= POSITION_TOL and touch_empty.swords[0].ultimate_point.distance_to(_point(empty_case["point"])) <= POSITION_TOL)


func _check_pause_and_hitstop() -> void:
	print("colossus: a field stands still while the run is paused or in hitstop")
	var case: Dictionary = _ref["pause_and_hitstop"]["pause_over_a_field"]
	var result: Dictionary = _replay(case)
	var run: GameRun = result["run"]
	_ok("pausing 30 ticks over a poisoned field and resuming: every iteration matches the prototype's, the field's life and clock frozen meanwhile (%d fields)" % run.fields.size(), String(result["diff"]).is_empty() and run.fields.size() == 1, String(result["diff"]))
	var life_run: GameRun = _run_of_setup(case["setup"])
	life_run.apply(GameCommand.ultimate(0, _point((case["setup"]["script"] as Array)[0]["point"])))
	_steps(life_run, 70)
	if life_run.fields.is_empty():
		_ok("a field stands 70 ticks after the Cataclysm", false)
		return
	var field: FieldState = life_run.fields[0]
	var before: Array = [field.life, field.tick_left, life_run.tick, life_run.enemies[0].conditions.poison, life_run.gameplay_time]
	life_run.apply(GameCommand.pause())
	_steps(life_run, 120)
	var after: Array = [field.life, field.tick_left, life_run.tick, life_run.enemies[0].conditions.poison, life_run.gameplay_time]
	life_run.apply(GameCommand.resume())
	_steps(life_run, 1)
	_ok("paused for 120 ticks: the field's life, its dose clock, the enemy's poison and the clocks did not move; one tick after resuming they do", before == after and field.life < float(before[0]) and life_run.tick == int(before[2]) + 1)
	var hit_run: GameRun = _run_of_setup(case["setup"])
	hit_run.apply(GameCommand.ultimate(0, _point((case["setup"]["script"] as Array)[0]["point"])))
	var frozen_ticks: int = 0
	var life_in_hitstop: Array[float] = []
	for step: int in 80:
		var life_before: float = hit_run.fields[0].life if not hit_run.fields.is_empty() else -1.0
		var in_stop: bool = hit_run.hitstop > 0.0
		hit_run.step()
		if in_stop and not hit_run.fields.is_empty() and life_before >= 0.0:
			frozen_ticks += 1
			life_in_hitstop.append(life_before - hit_run.fields[0].life)
	_ok("the slam's hitstop (0.13 s, %d ticks) froze the field too: its life did not change on those ticks" % frozen_ticks, frozen_ticks >= 7 and life_in_hitstop.all(func(change: float) -> bool: return change == 0.0), "%s" % [life_in_hitstop])


func _check_fight() -> void:
	print("colossus: three Colossi against a walking ring, conditions on, tick by tick")
	var case: Dictionary = _ref["fight"]
	var result: Dictionary = _replay(case)
	var run: GameRun = result["run"]
	_ok("every one of %d ticks matches (slams, a Cataclysm and its field, burning and poisoned and frozen enemies, deaths, contact with the player; %d kills, %d slams, %d fields, %d pulses)" % [int(case["trace"]["ticks"]), run.kills, run.cue_count(SimCue.Kind.COLOSSUS_SLAM), run.cue_count(SimCue.Kind.FIELD_CREATED), run.cue_count(SimCue.Kind.FIELD_PULSED)],
		String(result["diff"]).is_empty() and run.kills >= 3 and run.cue_count(SimCue.Kind.COLOSSUS_SLAM) >= 4 and run.cue_count(SimCue.Kind.FIELD_CREATED) == 1, String(result["diff"]))


# ----------------------------------------- removal, cleanup, pause, death
func _check_removed_and_cleanup() -> void:
	print("colossus: enemies that leave the run, restart and the player's death are handled safely (spec decision 7)")
	# The slam's target leaves the run alive during the windup: it is dropped and the slam lands on the spot it had been aiming at.
	var run: GameRun = _lone_run(_trio(0, 0.0), [_husk_at(260.0, 30.0), _husk_at(300.0, 50.0)])
	var sword: SwordState = run.swords[0]
	var gone: EnemyState = run.enemies[0]
	_steps(run, 3)
	var had_target: bool = sword.target == gone
	var aim_before: Vector2 = sword.aim
	run.enemies.erase(gone)
	_steps(run, 80)
	_ok("the target removed from the run while alive: the Colossus drops it, still lands on its last aim point (%s) and slams, and the removed enemy is never struck or rewarded (target %s, hp %.0f, kills %d)" % [aim_before, sword.target, gone.hp, run.kills],
		had_target and sword.target == null and gone.hp == 900.0 and run.cue_count(SimCue.Kind.COLOSSUS_SLAM) >= 1 and run.kills == 0 and sword.impact.distance_to(aim_before) <= 0.01)
	# A Cataclysm in the air and a field on the ground are run-owned: a restart removes them and the sword is new.
	var restart_run: GameRun = _lone_run(_trio(0, 99.0), [_husk_at(325.0, 0.0), _husk_at(260.0, 20.0)], true)
	restart_run.apply(GameCommand.ultimate(0, CENTER + Vector2(300.0, -20.0)))
	_steps(restart_run, 52)
	var in_the_air: bool = restart_run.swords[0].altitude > 100.0 and restart_run.fields.is_empty()
	_steps(restart_run, 20)
	var field_stood: bool = restart_run.fields.size() == 1
	restart_run.apply(GameCommand.restart())
	var fresh: SwordState = restart_run.swords[0]
	_ok("a restart in the middle of a fight (a sword was in the air, then a field stood) leaves no field, a new sword hanging at 30 px, idle, ready, not falling, and nothing left of the cues (restarts %d)" % restart_run.restarts,
		in_the_air and field_stood and restart_run.fields.is_empty() and fresh.phase == SwordState.Phase.IDLE and fresh.ultimate_ready() and fresh.altitude == 30.0 and not fresh.cataclysm_falling and fresh.fall_speed == 0.0 and restart_run.cue_count(SimCue.Kind.FIELD_CREATED) == 0 and restart_run.take_cues().is_empty())
	var counted: GameRun = _lone_run(_trio(0, 99.0), [_husk_at(325.0, 0.0)])
	var orb: ProjectileState = ProjectileState.make(CENTER + Vector2(300.0, -20.0), Vector2.ZERO)
	counted.projectiles.append(orb)
	counted.apply(GameCommand.ultimate(0, CENTER + Vector2(300.0, -20.0)))
	_steps(counted, 62)
	var snapshot: Dictionary = counted.snapshot()
	_ok("the run counts the orbs its slams destroyed (%d) and lists its fields in the observation snapshot (%d, life %s)" % [counted.projectiles_cleared, int(snapshot["field_count"]), snapshot["field_lives"]], counted.projectiles_cleared == 1 and orb.fate == ProjectileState.Fate.CLEARED and int(snapshot["field_count"]) == 1 and (snapshot["field_lives"] as Array).size() == 1)
	counted.apply(GameCommand.restart())
	_ok("a restart zeroes that count", counted.projectiles_cleared == 0 and int(counted.snapshot()["field_count"]) == 0)
	var cycle: GameRun = GameRun.new(RunScenario.colossus_encounter())
	cycle.apply(GameCommand.ultimate(1, cycle.position + Vector2(200.0, 0.0)))
	_steps(cycle, 70)
	var had_field: bool = cycle.fields.size() == 1
	cycle.apply(GameCommand.toggle_encounter())
	_ok("switching dev encounter with a field down clears it and the swords with it (had a field: %s, now %d, encounter %s)" % [had_field, cycle.fields.size(), cycle.scenario.encounter], had_field and cycle.fields.is_empty() and cycle.scenario.encounter == RunScenario.ENCOUNTER_DROPS)
	# The player's death while a sword is high up: it hangs idle and sinks, and no slam is made.
	var death_run: GameRun = _lone_run(_trio(0, 0.0), [_husk_at(260.0, 30.0)])
	_steps(death_run, 25)
	var high: float = death_run.swords[0].altitude
	death_run.hurt_player(1000, CENTER + Vector2(50.0, 0.0))
	_steps(death_run, 120)
	_ok("the player dies during a windup: the sword goes idle and its altitude sinks from %.0f px to %.0f at 120 px/s, with no slam" % [high, death_run.swords[0].altitude], high > 100.0 and death_run.swords[0].phase == SwordState.Phase.IDLE and death_run.swords[0].altitude < high - 20.0 and death_run.cue_count(SimCue.Kind.COLOSSUS_SLAM) == 0)
	# Two fields at one spot and an enemy leaving the run alive while standing in them: nothing breaks.
	var leave: GameRun = _lone_run(_trio(0, 99.0), [_husk_at(325.0, 0.0), _husk_at(260.0, 20.0)], true)
	var standing: EnemyState = leave.enemies[0]
	leave.apply(GameCommand.ultimate(0, CENTER + Vector2(300.0, -20.0)))
	leave.apply(GameCommand.ultimate(1, CENTER + Vector2(300.0, -20.0)))
	_steps(leave, 62)
	leave.enemies.erase(standing)
	var poison_before: int = standing.conditions.poison_stacks
	_steps(leave, 120)
	_ok("an enemy removed from the run while two fields stand over it is simply no longer dosed (stacks %d, then %d)" % [poison_before, standing.conditions.poison_stacks], standing.conditions.poison_stacks == poison_before and leave.fields.size() == 2)
	# A field hit by the end of its life: never negative, removed at once, no dose after.
	var expiry: GameRun = _lone_run(_trio(0, 99.0), [_husk_at(325.0, -5.0, 9000.0, "brute")], true)
	expiry.apply(GameCommand.ultimate(0, CENTER + Vector2(300.0, -20.0)))
	var gone_at: int = -1
	var pulses_after: int = 0
	for step: int in 420:
		var pulses: int = expiry.cue_count(SimCue.Kind.FIELD_PULSED)
		var had: bool = not expiry.fields.is_empty()
		expiry.step()
		if gone_at < 0 and had and expiry.fields.is_empty():
			gone_at = step + 1
		if gone_at >= 0 and expiry.cue_count(SimCue.Kind.FIELD_PULSED) > pulses and not had:
			pulses_after += 1
	_ok("a field expires after exactly 5 s of gameplay time (it went on tick %d, and nothing dosed after)" % gone_at, gone_at > 300 and expiry.fields.is_empty() and pulses_after == 0)


func _check_pause_and_death() -> void:
	print("colossus: pause and restart over a Cataclysm in flight")
	var run: GameRun = _lone_run(_trio(0, 99.0), [_husk_at(325.0, -5.0)])
	run.apply(GameCommand.ultimate(0, CENTER + Vector2(300.0, -20.0)))
	_steps(run, 20)
	var sword: SwordState = run.swords[0]
	var before: Array = [sword.altitude, sword.ultimate_time_left, sword.position, run.tick]
	run.apply(GameCommand.pause())
	_steps(run, 90)
	var after: Array = [sword.altitude, sword.ultimate_time_left, sword.position, run.tick]
	run.apply(GameCommand.resume())
	_steps(run, 1)
	_ok("paused in the middle of the rise: nothing moves (altitude %.1f, %.2f s of rise left), and after resuming it goes on from where it was" % [sword.altitude, float(before[1])], before == after and sword.altitude != float(before[0]))
	var landing: GameRun = _lone_run(_trio(0, 99.0), [_husk_at(325.0, -5.0)])
	landing.apply(GameCommand.ultimate(0, CENTER + Vector2(300.0, -20.0)))
	var landed: int = -1
	for step: int in range(1, 120):
		landing.step()
		if landing.swords[0].phase == SwordState.Phase.STUCK:
			landed = step
			break
	var paused_landing: GameRun = _lone_run(_trio(0, 99.0), [_husk_at(325.0, -5.0)])
	paused_landing.apply(GameCommand.ultimate(0, CENTER + Vector2(300.0, -20.0)))
	var paused_landed: int = -1
	for step: int in range(1, 400):
		if step == 30:
			paused_landing.apply(GameCommand.pause())
		if step == 60:
			paused_landing.apply(GameCommand.resume())
		paused_landing.step()
		if paused_landing.swords[0].phase == SwordState.Phase.STUCK:
			paused_landed = step
			break
	_ok("a pause of 30 ticks delays the landing by exactly 30 ticks (landed at %d instead of %d)" % [paused_landed, landed], paused_landed == landed + 30)
	var halt: GameRun = _lone_run(_trio(0, 99.0), [_husk_at(325.0, -5.0)], true)
	halt.apply(GameCommand.ultimate(0, CENTER + Vector2(300.0, -20.0)))
	_steps(halt, 70)
	halt.hurt_player(1000, CENTER + Vector2(50.0, 0.0))
	var fields_before: int = halt.fields.size()
	var pulses_before: int = halt.cue_count(SimCue.Kind.FIELD_PULSED)
	_steps(halt, 240)
	_ok("the player's death does not end a field (%d before, %d after, pulses %d to %d)" % [fields_before, halt.fields.size(), pulses_before, halt.cue_count(SimCue.Kind.FIELD_PULSED)], fields_before == 1 and halt.fields.size() == 1 and halt.cue_count(SimCue.Kind.FIELD_PULSED) > pulses_before)


func _check_fixture_and_launch() -> void:
	print("colossus: the loadout fixture and the colossus encounter")
	var scenario: RunScenario = RunScenario.colossus_encounter()
	var kinds: Array[StringName] = [EnemyDefs.HUSK, EnemyDefs.RUNNER, EnemyDefs.SPITTER, EnemyDefs.BRUTE]
	var counts: Array[int] = []
	for kind: StringName in kinds:
		counts.append(scenario.wave_kinds.count(kind))
	_ok("the colossus encounter is a cluster of %d husks and one wave (%s husk / runner / spitter / brute) against three Colossus swords with poison, ice and fire; conditions on; no shove" % [scenario.initial_enemies.size(), counts],
		scenario.encounter == RunScenario.ENCOUNTER_COLOSSUS and scenario.loadout.size() == 3 and scenario.loadout.all(func(spec: SwordSpec) -> bool: return spec.type_id == SwordDefs.COLOSSUS) and scenario.loadout[0].element == &"poison" and scenario.loadout[1].element == &"ice" and scenario.loadout[2].element == &"fire"
		and scenario.conditions_enabled and not scenario.dev_shove and scenario.waves_enabled and scenario.initial_enemies.size() == 7 and scenario.wave_kinds.size() == 16 and counts[2] == 2 and counts[3] == 2)
	_ok("the dev cycle reaches it after the pike encounter and leaves it for the drops encounter (issue #17), and the dev button names it",
		RunScenario.next_encounter(RunScenario.ENCOUNTER_PIKE) == RunScenario.ENCOUNTER_COLOSSUS and RunScenario.next_encounter(RunScenario.ENCOUNTER_COLOSSUS) == RunScenario.ENCOUNTER_DROPS and RunScenario.encounter_title(RunScenario.ENCOUNTER_COLOSSUS) == "Colossus" and RunScenario.ENCOUNTER_CYCLE.has(RunScenario.ENCOUNTER_COLOSSUS))
	var from_pike: GameRun = GameRun.new(RunScenario.pike_encounter())
	from_pike.apply(GameCommand.toggle_encounter())
	_ok("the encounter command goes from the pike encounter to the colossus one (three Colossi, restarts %d), and from it to the drops encounter" % from_pike.restarts, from_pike.scenario.encounter == RunScenario.ENCOUNTER_COLOSSUS and from_pike.swords.all(func(sword: SwordState) -> bool: return sword.spec.type_id == SwordDefs.COLOSSUS) and from_pike.restarts == 1)
	from_pike.apply(GameCommand.toggle_encounter())
	_ok("and one more press goes to the drops encounter (issue #17)", from_pike.scenario.encounter == RunScenario.ENCOUNTER_DROPS and from_pike.restarts == 2)
	_ok("--encounter=colossus and ?encounter=colossus ask for it, and asking for nothing starts the normal run with the default loadout (Fang, Warden, Colossus; issue #16)",
		LaunchOptions.scenario_for("colossus") != null and LaunchOptions.scenario_for("colossus").encounter == RunScenario.ENCOUNTER_COLOSSUS and LaunchOptions.scenario_for("") == null and GameRun.new(LaunchOptions.scenario_for("")).swords.map(func(sword: SwordState) -> StringName: return sword.spec.type_id) == [SwordDefs.FANG, SwordDefs.WARDEN, SwordDefs.COLOSSUS])
	var cluster_ok: bool = true
	for point: Vector2 in scenario.initial_enemies.map(func(placement: EnemyPlacement) -> Vector2: return placement.position):
		cluster_ok = cluster_ok and point.distance_to(scenario.start_position) > 280.0 and point.distance_to(scenario.start_position) < 440.0
	_ok("the cluster stands 280 to 440 px from the player, tight enough for one slam to catch several (cluster targeting) and far enough to give Cataclysm a point to land on", cluster_ok)
	var fixed: RunScenario = RunScenario.colossus_encounter()
	fixed.seed = 17
	var run: GameRun = GameRun.new(fixed)
	_ok("the encounter equips three Colossi with their own length (%s) and starts with the cluster in place and no field" % [run.swords.map(func(s: SwordState) -> float: return s.length)], run.swords.size() == 3 and run.swords.all(func(s: SwordState) -> bool: return s.spec.type_id == SwordDefs.COLOSSUS and s.length == SwordDefs.COLOSSUS_LENGTH) and run.enemies.size() == 7 and run.fields.is_empty())
	var played: RunScenario = RunScenario.colossus_encounter()
	played.seed = 17
	played.first_wave_delay = 0.2
	var fight: GameRun = GameRun.new(played)
	var phases: Dictionary = {}
	var elements: Dictionary = {}
	for tick: int in 2400:
		if tick == 40:
			fight.apply(GameCommand.ultimate(0, fight.position + Vector2(320.0, 0.0)))
		if tick == 60:
			fight.apply(GameCommand.ultimate(1, fight.position + Vector2(-250.0, 100.0)))
		if tick == 80:
			fight.apply(GameCommand.ultimate(2, fight.position + Vector2(100.0, -300.0)))
		fight.step()
		for sword: SwordState in fight.swords:
			phases[_state_name(sword)] = true
		for field: FieldState in fight.fields:
			elements[field.element] = true
		if fight.dead:
			break
	_ok("a played colossus encounter shows slams, Cataclysms, all three elements' fields and kills (phases %s, elements %s, kills %d, slams %d, fields %d)" % [phases.keys(), elements.keys(), fight.kills, fight.cue_count(SimCue.Kind.COLOSSUS_SLAM), fight.cue_count(SimCue.Kind.FIELD_CREATED)],
		phases.has("strike") and phases.has("stuck") and phases.has("ult_rise") and phases.has("ult_fall") and elements.size() == 3 and fight.kills >= 8 and fight.cue_count(SimCue.Kind.FIELD_CREATED) == 3 and fight.cue_count(SimCue.Kind.COLOSSUS_SLAM) >= 8)


## What presentation reads from the sword and the field: how far the windup or the rise has run, and how a field fades.
func _check_progress_and_fields() -> void:
	print("colossus: the progress and fade values the presentation reads")
	var run: GameRun = _lone_run(_trio(0, 0.0), [_husk_at(260.0, 30.0)])
	var sword: SwordState = run.swords[0]
	var before: float = sword.windup_progress()
	_steps(run, 17)
	var mid: float = sword.windup_progress()
	_steps(run, 40)
	_ok("a slam's windup progress is 0 before it, %.2f halfway through 0.55 s and 0 once it is falling (%.2f)" % [mid, sword.windup_progress()], before == 0.0 and _near(mid, 0.5, 0.04) and sword.phase != SwordState.Phase.WINDUP and sword.windup_progress() == 0.0)
	var rise: GameRun = _lone_run(_trio(0, 99.0), [_husk_at(325.0, 0.0)])
	var cataclysm: SwordState = rise.swords[0]
	var idle_progress: float = cataclysm.cataclysm_rise_progress()
	rise.apply(GameCommand.ultimate(0, CENTER + Vector2(300.0, -20.0)))
	var start_progress: float = cataclysm.cataclysm_rise_progress()
	_steps(rise, 22)
	var half: float = cataclysm.cataclysm_rise_progress()
	_steps(rise, 30)
	var falling: float = cataclysm.cataclysm_rise_progress()
	_steps(rise, 60)
	_ok("a Cataclysm's rise progress is 0 at rest and when it starts, %.2f halfway through 0.75 s, 1 while it falls (%.1f) and 0 again afterwards (%.1f)" % [half, falling, cataclysm.cataclysm_rise_progress()],
		idle_progress == 0.0 and start_progress == 0.0 and _near(half, 0.49, 0.04) and falling == 1.0 and cataclysm.cataclysm_rise_progress() == 0.0)
	var field: FieldState = FieldState.make(CENTER, 233.64, &"fire", 50.0, 5.0)
	var full: float = field.fade()
	field.life = 5.0 / 3.0
	var third: float = field.fade()
	field.life = 5.0 / 6.0
	var half_faded: float = field.fade()
	field.life = 0.0
	var gone: float = field.fade()
	_ok("a field is drawn at full strength until its last third, half strength with a sixth of its life left, and not at all at the end (%.2f, %.2f, %.2f, %.2f)" % [full, third, half_faded, gone], full == 1.0 and _near(third, 1.0, 0.0001) and _near(half_faded, 0.5, 0.0001) and gone == 0.0)
	var exact: FieldState = FieldState.make(CENTER, 100.0, &"ice", 50.0, 5.0)
	_ok("a field does not reach an enemy exactly on its edge (100 + 16 = 116 px away), only strictly inside it, as the prototype's `<`", not exact.reaches(EnemyState.make(EnemyDefs.HUSK, CENTER + Vector2(116.0, 0.0), 1, 0.0, 5)) and exact.reaches(EnemyState.make(EnemyDefs.HUSK, CENTER + Vector2(115.5, 0.0), 1, 0.0, 6)))
	var husk: EnemyState = EnemyState.make(EnemyDefs.HUSK, CENTER + Vector2(249.0, 0.0), 1, 0.0, 1)
	var brute: EnemyState = EnemyState.make(EnemyDefs.BRUTE, CENTER + Vector2(262.0, 0.0), 1, 0.0, 2)
	field.position = CENTER
	_ok("a field reaches an enemy whose centre is within its radius plus the enemy's own: a husk at 249 (233.64 + 16) and a brute at 262 (233.64 + 30) yes, 250 and 264 no",
		field.reaches(husk) and field.reaches(brute) and not field.reaches(EnemyState.make(EnemyDefs.HUSK, CENTER + Vector2(250.0, 0.0), 1, 0.0, 3)) and not field.reaches(EnemyState.make(EnemyDefs.BRUTE, CENTER + Vector2(264.0, 0.0), 1, 0.0, 4)))


## A field sheds the particles of its element (prototype `update_fields`), whether or not anything stands in it.
func _check_field_particles() -> void:
	print("colossus: a field sheds its element's particles")
	for element: StringName in [&"fire", &"ice", &"poison"]:
		var run: GameRun = GameRun.new(RunScenario.fang_fixture().without_conditions())
		run.fields.append(FieldState.make(CENTER + Vector2(200.0, 0.0), 233.0, element, 50.0, 5.0))
		var effects: EffectsLayer = EffectsLayer.new()
		_tree.root.add_child(effects)
		var most: int = 0
		var inside: bool = true
		for i: int in 120:
			effects.sync(run)
			most = maxi(most, effects._embers.size())
			inside = inside and effects._embers.all(func(ember: Dictionary) -> bool: return (Vector2(ember["pos"]) - Vector2(CENTER.x + 200.0, CENTER.y)).length() < 260.0)
		_ok("a %s field keeps up to %d particles alive around it over 2 s (it emits about 28 a second; they last under a second)" % [element, most], most >= 4 and inside)
		effects.queue_free()
	await _tree.process_frame


# ------------------------------------------------------ real Main scene
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


func _key(code: Key) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = true
	return event


func _check_main_scene() -> void:
	print("colossus: Q, E and R in the real Main scene (HUD cards, cues, effects, visuals)")
	var scenario: RunScenario = RunScenario.colossus_encounter()
	scenario.seed = 23
	scenario.first_wave_delay = 0.2
	var main: Main = _main_with(scenario)
	await _tree.process_frame
	main._sfx.unlock()
	main._sfx.played.clear()
	_tick_main(main, 5)
	await _tree.process_frame
	var hud: Hud = main._hud
	_ok("the HUD cards name each slot's ultimate and sword: Cataclysm x3, Colossus sword, all READY with POISON, ICE and FIRE tags",
		hud._ult_names[0].text == "Cataclysm" and hud._ult_names[1].text == "Cataclysm" and hud._ult_names[2].text == "Cataclysm" and hud._ult_types[0].text.begins_with("Colossus sword") and not hud._ult_types[0].text.contains("skill shot")
		and hud._ult_elements[0].text == "POISON" and hud._ult_elements[1].text == "ICE" and hud._ult_elements[2].text == "FIRE" and [0, 1, 2].all(func(slot: int) -> bool: return hud.ultimate_status(slot) == "READY" and hud.ultimate_card_visible(slot)))
	var half: Vector2 = main.get_viewport().get_visible_rect().size * 0.5
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = half + Vector2(320.0, 0.0)
	main._input(motion)
	main._input(_key(KEY_E))
	var sword: SwordState = main.run.swords[1]
	_ok("E with the mouse 320 px east of the view's centre starts slot two's Cataclysm there (%s) while the others stay put" % [sword.ultimate_point], sword.phase == SwordState.Phase.ULTIMATE and sword.ultimate_point.distance_to(main.run.camera + Vector2(320.0, 0.0)) <= 1.0 and main.run.swords[0].phase != SwordState.Phase.ULTIMATE)
	_ok("it is announced and heard (ULTIMATE_STARTED cue, a sound)", main.run.cue_count(SimCue.Kind.ULTIMATE_STARTED) == 1 and main._sfx.played.has("dash"), "%s" % [main._sfx.played])
	var effects: EffectsLayer = main._presenter._effects
	_tick_main(main, 8)
	await _tree.process_frame
	_ok("while it rises the card shows ACTIVE and the layer draws the ring it will crush from the sword's own state (drawn: %s)" % [effects.draw_counts], hud.ultimate_status(1) == "ACTIVE" and _state_name(sword) == "ult_rise" and sword.altitude > 40.0 and effects.draw_counts.get(&"cataclysm_ring_fill", 0) > 0 and effects.draw_counts.get(&"cataclysm_ring_rim", 0) > 0 and effects.draw_counts.get(&"cataclysm_ring_closing", 0) > 0)
	var slam_seen: bool = false
	var field_seen: bool = false
	var highest: float = 0.0
	for i: int in 110:
		_tick_main(main, 1)
		await _tree.process_frame
		highest = maxf(highest, sword.altitude)
		slam_seen = slam_seen or main.run.cue_count(SimCue.Kind.COLOSSUS_SLAM) > 0
		field_seen = field_seen or (effects.draw_counts.get(&"field_fill", 0) > 0 and effects.draw_counts.get(&"field_rim", 0) > 0)
	_ok("it climbs to %.0f px, lands (%d slam cue), leaves a field the layer draws (%d draws, %d fields in the run) and the field is announced (%d cue)" % [highest, main.run.cue_count(SimCue.Kind.COLOSSUS_SLAM), effects.draw_counts.get(&"field_rim", 0), main.run.fields.size(), main.run.cue_count(SimCue.Kind.FIELD_CREATED)],
		highest > 300.0 and slam_seen and field_seen and main.run.fields.size() == 1 and main.run.cue_count(SimCue.Kind.FIELD_CREATED) == 1)
	var cataclysm_visual: PlaceholderSwordVisual = main._presenter._sword_visuals[sword.get_instance_id()] as PlaceholderSwordVisual
	_ok("the Colossus visual hangs where the simulation says (its drawn lift %.1f = the sword's altitude %.1f)" % [cataclysm_visual._lift, sword.altitude], _near(cataclysm_visual._lift, sword.altitude, 0.001))
	_ok("the encounter legend counts what happened (slams %d, fields %d, live %d): %s" % [main.run.cue_count(SimCue.Kind.COLOSSUS_SLAM), main.run.cue_count(SimCue.Kind.FIELD_CREATED), main.run.fields.size(), hud._encounter_label.text.get_slice("\n", 0)],
		hud._encounter_label.text.contains("COLOSSUS ENCOUNTER") and hud._encounter_label.text.contains("slams %d" % main.run.cue_count(SimCue.Kind.COLOSSUS_SLAM)) and hud._encounter_label.text.contains("fields 1 (live 1)"))
	_ok("after the Cataclysm the card counts the recharge down in whole seconds (%s)" % hud.ultimate_status(1), hud.ultimate_status(1) == "%ds" % SimMath.py_round(sword.ultimate_cooldown_left) and hud.ultimate_bar_fraction(1) > 0.0 and hud.ultimate_bar_fraction(1) < 1.0)
	var rings_before: int = effects._rings.size()
	var texts_first: int = effects._texts.size()
	var slam_cue: SimCue = SimCue.make(SimCue.Kind.COLOSSUS_SLAM, CENTER, Vector2.DOWN, 3, false)
	slam_cue.radius = 118.0
	slam_cue.element = &"fire"
	effects.apply_cue(slam_cue)
	var rings_after_slam: int = effects._rings.size()
	var texts_before: int = effects._texts.size()
	var big_cue: SimCue = SimCue.make(SimCue.Kind.COLOSSUS_SLAM, CENTER, Vector2.DOWN, 3, true)
	big_cue.radius = 212.4
	big_cue.element = &"ice"
	effects.apply_cue(big_cue)
	var texts_after: int = effects._texts.size()
	_ok("a slam cue draws two rings and a Cataclysm's names itself ('CATACLYSM'), an automatic slam's does not", rings_after_slam == rings_before + 2 and effects._rings.size() == rings_after_slam + 2 and texts_before == texts_first and texts_after == texts_before + 1)
	var sparks_before: int = effects._sparks.size()
	effects.apply_cue(slam_cue)
	var field_cue: SimCue = SimCue.make(SimCue.Kind.FIELD_CREATED, CENTER)
	field_cue.radius = 233.0
	field_cue.element = &"ice"
	var rings_field: int = effects._rings.size()
	effects.apply_cue(field_cue)
	var rings_after_field: int = effects._rings.size()
	var pulse_cue: SimCue = SimCue.make(SimCue.Kind.FIELD_PULSED, CENTER, Vector2.ZERO, 2)
	pulse_cue.radius = 233.0
	pulse_cue.element = &"ice"
	effects.apply_cue(pulse_cue)
	var rings_after_pulse: int = effects._rings.size()
	var empty_pulse: SimCue = SimCue.make(SimCue.Kind.FIELD_PULSED, CENTER, Vector2.ZERO, 0)
	empty_pulse.radius = 233.0
	effects.apply_cue(empty_pulse)
	_ok("a slam throws 30 sparks (%d), a new field one ring, a pulse that dosed someone one ring and an empty pulse none" % (effects._sparks.size() - sparks_before), effects._sparks.size() - sparks_before == 30 and rings_after_field == rings_field + 1 and rings_after_pulse == rings_after_field + 1 and effects._rings.size() == rings_after_pulse)
	var texts_now: int = effects._texts.size()
	main._input(_key(KEY_E))
	_ok("E while it recharges is refused and says so on screen", main.run.cue_count(SimCue.Kind.ULTIMATE_REFUSED) == 1 and effects._texts.size() == texts_now + 1)
	var telegraph_seen: bool = false
	for i: int in 240:
		_tick_main(main, 1)
		await _tree.process_frame
		telegraph_seen = telegraph_seen or (effects.draw_counts.get(&"slam_telegraph_fill", 0) > 0 and effects.draw_counts.get(&"slam_telegraph_rim", 0) > 0 and effects.draw_counts.get(&"slam_telegraph_closing", 0) > 0)
	_ok("while the Colossi wind up and fall, the layer draws the ring they will crush (drawn: %s)" % [effects.draw_counts], telegraph_seen)
	await _tree.create_timer(0.1).timeout
	main._sfx.played.clear()
	main._sfx.play_cue(SimCue.make(SimCue.Kind.COLOSSUS_SLAM, Vector2.ZERO, Vector2.DOWN, 0))
	_ok("a slam is heard even when it struck nothing", main._sfx.played.has("hit"), "%s" % [main._sfx.played])
	var colossus_visuals: int = 0
	for child: Node in main._presenter.get_children():
		if child is PlaceholderSwordVisual and (child as PlaceholderSwordVisual)._colossus:
			colossus_visuals += 1
	_ok("the three Colossi are drawn as a huge slab of a blade (%d Colossus visuals)" % colossus_visuals, colossus_visuals == 3)
	main.queue_free()
	await _tree.process_frame


func _check_hud() -> void:
	print("colossus: the HUD in the colossus encounter lies inside the viewport")
	var window: Window = Window.new()
	window.size = Vector2i(1084, 720)
	window.content_scale_size = Vector2i(1280, 720)
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	_tree.root.add_child(window)
	var hud: Hud = Hud.new()
	window.add_child(hud)
	var run: GameRun = GameRun.new(RunScenario.colossus_encounter())
	await _tree.process_frame
	hud.show_state(false, false)
	hud.show_run(run)
	await _tree.process_frame
	var visible_rect: Rect2 = window.get_visible_rect()
	var outside: Array[String] = []
	var counted: int = 0
	for slot: int in 3:
		for control: Control in [hud._ult_cards[slot], hud._ult_names[slot], hud._ult_status[slot], hud._ult_types[slot], hud._ult_elements[slot]]:
			counted += 1
			if not visible_rect.grow(0.5).encloses(control.get_global_rect()):
				outside.append("%s %s" % [control.name, control.get_global_rect()])
	_ok("the three slot cards and their texts (%d controls) are inside the %s view in a 1084x720 window: %s" % [counted, visible_rect.size, outside], outside.is_empty())
	_ok("the cards read Cataclysm x3 with POISON, ICE and FIRE tags and 'Colossus sword' under the bar", hud._ult_names[1].text == "Cataclysm" and hud._ult_elements[0].text == "POISON" and hud._ult_elements[1].text == "ICE" and hud._ult_elements[2].text == "FIRE" and hud._ult_types[2].text.begins_with("Colossus sword"))
	var legend_rect: Rect2 = hud._encounter_label.get_global_rect()
	_ok("the encounter legend names the slams and fields and fits the view (%s)" % legend_rect, hud._encounter_label.visible and hud._encounter_label.text.contains("COLOSSUS ENCOUNTER") and hud._encounter_label.text.contains("slams 0") and hud._encounter_label.text.contains("fields 0 (live 0)") and visible_rect.grow(0.5).encloses(legend_rect))
	window.queue_free()
	await _tree.process_frame


func _check_visual_independence() -> void:
	print("colossus: swapping the sword visual leaves the fight unchanged, and a visual's height is read-only")
	var hosts: Array[Main] = []
	for use_alt: bool in [false, true]:
		hosts.append(_main_with(RenderRateScenario.scenario(RenderRateScenario.COLOSSUS), "res://tests/alt_sword.tscn" if use_alt else ""))
	await _tree.process_frame
	var seen_phases: Dictionary = {}
	var highest: float = 0.0
	var results: Array[Dictionary] = []
	for host_index: int in hosts.size():
		var main: Main = hosts[host_index]
		for tick_index: int in 700:
			for command: GameCommand in RenderRateScenario.commands_at(main.run.tick, RenderRateScenario.COLOSSUS):
				main.run.apply(command)
			_tick_main(main, 1)
			if host_index == 1:
				for child: Node in main._presenter.get_children():
					if child is AltSwordVisual:
						seen_phases[(child as AltSwordVisual).last_phase] = true
						highest = maxf(highest, (child as AltSwordVisual).last_altitude)
		results.append(main.run.snapshot())
	_ok("a stretched, rotated replacement sword visual changes nothing about the slams, Cataclysms, fields, kills or recharges", results[0] == results[1])
	_ok("the replacement visual was told the strike, stuck and ultimate phases (%s) and the sword's height (up to %.0f px)" % [seen_phases.keys(), highest], seen_phases.has(SwordState.Phase.STRIKE) and seen_phases.has(SwordState.Phase.STUCK) and seen_phases.has(SwordState.Phase.ULTIMATE) and highest > 300.0)
	_ok("the fixture fought: %d slams, %d fields, %d kills, %d hits" % [hosts[0].run.cue_count(SimCue.Kind.COLOSSUS_SLAM), hosts[0].run.cue_count(SimCue.Kind.FIELD_CREATED), hosts[0].run.kills, hosts[0].run.cue_count(SimCue.Kind.ENEMY_HIT)],
		hosts[0].run.cue_count(SimCue.Kind.COLOSSUS_SLAM) >= 8 and hosts[0].run.cue_count(SimCue.Kind.FIELD_CREATED) == 3 and hosts[0].run.kills >= 3)
	for main: Main in hosts:
		main.queue_free()
	await _tree.process_frame
