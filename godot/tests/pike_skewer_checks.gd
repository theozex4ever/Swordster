class_name PikeSkewerChecks
extends RefCounted
## Game-run behavioural checks for the Pike sword (automatic long piercing thrusts) and its
## ultimate, Skewer (issue #14). Like the earlier slices' checks, every check drives the real
## `GameRun` through `GameCommand`s (or the real Main scene with real key events), advances fixed
## ticks and observes outcomes. Comparison values come from the Python prototype's captured
## reference (res://tests/reference/pike_skewer.json, recorded by
## tools/reference/capture_pike_skewer.py), which also carries each case's fixture (`setup`:
## swords, enemies, orbs, the player's position and facing, whether elemental conditions are on),
## so no starting number is copied into this file. Most cases compare the sword and every enemy on
## EVERY tick, not just outcomes. Tolerances and deliberate exceptions: docs/reference/pike-skewer.md.

const REFERENCE_PATH: String = "res://tests/reference/pike_skewer.json"

## Same-algorithm comparisons at the prototype's 60 FPS step.
const POSITION_TOL: float = 0.05  # px
const VELOCITY_TOL: float = 0.5  # px/s (the prototype's value is a rounded position difference x 60)
const SCALAR_TOL: float = 0.002  # timers, cooldowns, shake, stun, flash
const ANGLE_TOL: float = 0.002
const DIR_TOL: float = 0.0001
const HP_TOL: float = 0.001
const TICK_TOL: int = 1
const CENTER: Vector2 = Vector2(1300.0, 900.0)
## The health the capture gave its stationary probes and posts (a placement's health is not its maximum).
const PROBE_HP: float = 900.0
const SLOT_KEYS: Array[Key] = [KEY_Q, KEY_E, KEY_R]

var _check: Callable
var _tree: SceneTree
var _ref: Dictionary = {}


func _init(check_function: Callable, tree: SceneTree) -> void:
	_check = check_function
	_tree = tree


func run_all() -> void:
	if not CheckFocus.includes("pike_skewer"):
		return
	var file: FileAccess = FileAccess.open(REFERENCE_PATH, FileAccess.READ)
	if file == null:
		_ok("pike reference file loads", false, REFERENCE_PATH)
		return
	_ref = JSON.parse_string(file.get_as_text())
	_ok("pike reference file parses", not _ref.is_empty())
	_check_reference_scope()
	if not _check_definitions():
		print("pike: the sword type's identity is wrong; the remaining checks build fixtures from it and are skipped")
		return
	_check_thrust()
	_check_acquire()
	_check_geometry()
	_check_piercing()
	_check_deaths()
	_check_parry()
	_check_start()
	_check_skewer_single()
	_check_skewer_carry()
	_check_skewer_empty()
	_check_skewer_walls()
	_check_skewer_boundary()
	_check_skewer_range()
	_check_skewer_deaths()
	_check_skewer_rules()
	_check_skewer_parry()
	_check_conditions()
	_check_keys()
	_check_removed_and_cleanup()
	_check_pause_and_death()
	_check_fixture_and_launch()
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


## A scenario from a case's `setup`: its swords (type, rarity, element, starting cooldown),
## enemies, player position and facing, and whether elemental conditions are on, with no waves.
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
	if setup.has("facing"):
		run.facing = _point(setup["facing"])
	for orb: Variant in setup.get("orbs", []):
		var spec: Dictionary = orb as Dictionary
		var projectile: ProjectileState = ProjectileState.make(Vector2(float(spec["x"]), float(spec["y"])), Vector2(float(spec["vx"]), float(spec["vy"])))
		projectile.life = float(spec["life"])
		run.projectiles.append(projectile)
	return run


## A run of `setup` with the Skewer commanded from `slot` at the setup's `point`.
func _skewer_run(setup: Dictionary, slot: int = 0) -> GameRun:
	var run: GameRun = _run_of_setup(setup)
	_steps(run, int(setup.get("warmup_ticks", 0)))
	run.apply(GameCommand.ultimate(slot, _point(setup["point"])))
	return run


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


## The Skewer's sub-phase as the prototype names it (`Sword.phase`, only meaningful while "ult").
func _ult_phase(sword: SwordState) -> String:
	if sword.phase != SwordState.Phase.ULTIMATE:
		return ""
	return "fly" if sword.skewer_flying else "aim"


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


## Plays `ticks` fixed ticks on `run`, comparing on every tick the sword and every enemy with the
## reference trace (`trace`, starting at tick index `first`) and, unless `compare_hits` is off,
## the hit list (which enemy lost how much health on which tick, with the hitstop, shake and flash
## that followed). Returns {"diff": first difference or "", "hits": what happened}.
func _follow(run: GameRun, sword: SwordState, enemies: Array[EnemyState], trace: Dictionary, ticks: int, first: int = 0, compare_hits: bool = true) -> Dictionary:
	var diff: String = ""
	var hits: Array[Dictionary] = []
	var hp_before: Array[float] = []
	for enemy: EnemyState in enemies:
		hp_before.append(enemy.hp)
	for n: int in range(1, ticks + 1):
		run.step()
		var i: int = first + n - 1
		var dealt: Array = []
		var flashes: Array = []
		for k: int in enemies.size():
			if enemies[k].hp < hp_before[k]:
				dealt.append([k, snappedf(hp_before[k] - enemies[k].hp, 0.0001)])
				flashes.append(enemies[k].flash)
				hp_before[k] = enemies[k].hp
		if not dealt.is_empty():
			hits.append({"tick": first + n, "dealt": dealt, "hitstop": run.hitstop, "trauma": run.trauma, "flash": flashes})
		if not diff.is_empty():
			continue
		diff = _sword_diff(sword, trace, i, first + n)
		if diff.is_empty():
			for k: int in enemies.size():
				diff = _enemy_diff(enemies[k], (trace["enemies"] as Array)[k], i, first + n, k)
				if not diff.is_empty():
					break
	if diff.is_empty() and compare_hits:
		diff = _hits_diff(hits, trace["hits"])
	return {"diff": diff, "hits": hits}


func _sword_diff(sword: SwordState, trace: Dictionary, i: int, n: int) -> String:
	var state: String = _phase_name(sword.phase)
	if state != String((trace["state"] as Array)[i]):
		return "tick %d: phase %s vs %s" % [n, state, (trace["state"] as Array)[i]]
	if _ult_phase(sword) != String((trace["phase"] as Array)[i]):
		return "tick %d: ultimate phase '%s' vs '%s'" % [n, _ult_phase(sword), (trace["phase"] as Array)[i]]
	if sword.skewer_carried.size() != int((trace["carried"] as Array)[i]):
		return "tick %d: carrying %d vs %d" % [n, sword.skewer_carried.size(), (trace["carried"] as Array)[i]]
	var pairs: Array = [["x", sword.position.x, POSITION_TOL], ["y", sword.position.y, POSITION_TOL], ["ang", sword.angle, ANGLE_TOL],
		["vx", sword.velocity.x, VELOCITY_TOL], ["vy", sword.velocity.y, VELOCITY_TOL], ["ult_t", sword.ultimate_time_left, SCALAR_TOL],
		["ult_cd", sword.ultimate_cooldown_left, SCALAR_TOL], ["cd", sword.cooldown_left, SCALAR_TOL]]
	for pair: Array in pairs:
		var want: float = float((trace[pair[0]] as Array)[i])
		if not _near(float(pair[1]), want, float(pair[2])):
			return "tick %d: sword %s %.4f vs %.4f" % [n, pair[0], float(pair[1]), want]
	return ""


func _enemy_diff(enemy: EnemyState, ref: Dictionary, i: int, n: int, k: int) -> String:
	if int(enemy.dead) != int((ref["dead"] as Array)[i]):
		return "tick %d: enemy %d dead %s vs %s" % [n, k, enemy.dead, (ref["dead"] as Array)[i]]
	var pairs: Array = [["x", enemy.position.x, POSITION_TOL], ["y", enemy.position.y, POSITION_TOL], ["hp", enemy.hp, HP_TOL],
		["vx", enemy.velocity.x, VELOCITY_TOL], ["vy", enemy.velocity.y, VELOCITY_TOL], ["stun", enemy.stun, SCALAR_TOL]]
	for pair: Array in pairs:
		var want: float = float((ref[pair[0]] as Array)[i])
		if not _near(float(pair[1]), want, float(pair[2])):
			return "tick %d: enemy %d %s %.4f vs %.4f" % [n, k, pair[0], float(pair[1]), want]
	return ""


func _condition_diff(enemy: EnemyState, ref: Dictionary, i: int, n: int, k: int) -> String:
	var c: EnemyConditions = enemy.conditions
	var pairs: Array = [["hp", enemy.hp], ["burn", c.burn], ["burn_dps", c.burn_dps], ["poison", c.poison], ["poison_dps", c.poison_dps],
		["poison_stacks", float(c.poison_stacks)], ["chill", c.chill], ["chill_stacks", float(c.chill_stacks)], ["frozen", c.frozen], ["dot", c.dot]]
	for pair: Array in pairs:
		var want: float = float((ref[pair[0]] as Array)[i])
		if not _near(float(pair[1]), want, SCALAR_TOL):
			return "tick %d: enemy %d %s %.4f vs %.4f" % [n, k, pair[0], float(pair[1]), want]
	if not _near(enemy.position.x, float((ref["x"] as Array)[i]), POSITION_TOL) or not _near(enemy.position.y, float((ref["y"] as Array)[i]), POSITION_TOL):
		return "tick %d: enemy %d position (%.3f, %.3f) vs (%.3f, %.3f)" % [n, k, enemy.position.x, enemy.position.y, float((ref["x"] as Array)[i]), float((ref["y"] as Array)[i])]
	return ""


func _hits_diff(mine: Array[Dictionary], want: Array) -> String:
	if mine.size() != want.size():
		return "%d hit ticks vs %d" % [mine.size(), want.size()]
	for j: int in mine.size():
		var a: Dictionary = mine[j]
		var b: Dictionary = want[j]
		if int(a["tick"]) != int(b["tick"]) or (a["dealt"] as Array).size() != (b["dealt"] as Array).size():
			return "hit %d: tick %s %s vs %s %s" % [j, a["tick"], a["dealt"], b["tick"], b["dealt"]]
		for m: int in (a["dealt"] as Array).size():
			var got: Array = (a["dealt"] as Array)[m]
			var exp: Array = (b["dealt"] as Array)[m]
			if int(got[0]) != int(exp[0]) or not _near(float(got[1]), float(exp[1]), 0.001) or not _near(float((a["flash"] as Array)[m]), float((b["flash"] as Array)[m]), SCALAR_TOL):
				return "hit %d (tick %s): %s flash %s vs %s flash %s" % [j, a["tick"], a["dealt"], a["flash"], b["dealt"], b["flash"]]
		if not _near(float(a["hitstop"]), float(b["hitstop"]), SCALAR_TOL) or not _near(float(a["trauma"]), float(b["trauma"]), SCALAR_TOL):
			return "hit %d (tick %s): hitstop %.4f trauma %.4f vs %.4f %.4f" % [j, a["tick"], a["hitstop"], a["trauma"], b["hitstop"], b["trauma"]]
	return ""


## Follows a captured trace of slot `slot` (the Skewer commanded on tick 0 when `skewer`), returning the
## run, the enemies and the comparison. Every case is compared on every tick to the end of its trace,
## release and what follows it included.
func _replay(case: Dictionary, slot: int = 0, skewer: bool = true) -> Dictionary:
	var setup: Dictionary = case["setup"]
	var run: GameRun = _skewer_run(setup, slot) if skewer else _run_of_setup(setup)
	var enemies: Array[EnemyState] = run.enemies.duplicate()
	var result: Dictionary = _follow(run, run.swords[slot], enemies, case["trace"], int(case["trace"]["ticks"]))
	result["run"] = run
	result["enemies"] = enemies
	result["compared"] = int(case["trace"]["ticks"])
	return result


func _hit_count(trace: Dictionary, index: int) -> int:
	var total: int = 0
	for hit: Variant in trace["hits"]:
		for pair: Variant in (hit as Dictionary)["dealt"]:
			if int((pair as Array)[0]) == index:
				total += 1
	return total


func _transition_ticks(trace: Dictionary, to: String) -> Array[int]:
	var ticks: Array[int] = []
	for entry: Variant in trace["transitions"]:
		if String((entry as Dictionary)["to"]) == to:
			ticks.append(int((entry as Dictionary)["tick"]))
	return ticks


# ------------------------------------------------------------- reference
func _check_reference_scope() -> void:
	print("pike: the reference was captured with out-of-scope mechanics disabled")
	var scope: Dictionary = _ref["fixture_scope"]
	_ok("every enemy in the capture was unarmed (arming and drops are issue #17) and only husks, runners and brutes were used", int(scope["armed_enemies"]) == 0 and scope["kinds"] == ["brute", "husk", "runner"])
	_ok("only Pike swords took part, Converge was not used (issue #16), no waves ran (issue #18)", scope["swords_used"] == ["lance"] and not bool(scope["converge_used"]) and not bool(scope["waves_enabled"]))
	var with_conditions: Array = scope["afflict_enabled_cases"]
	_ok("the prototype's afflict was OFF everywhere except the condition cases %s" % [with_conditions], bool(scope["afflict_disabled_everywhere_else"])
		and with_conditions == ["skewer_burn_dies_after_release", "skewer_fire", "skewer_ice", "skewer_poison", "thrust_fire", "thrust_ice", "thrust_poison"])
	var flags_ok: bool = true
	for label: String in ["poison", "ice", "fire"]:
		flags_ok = flags_ok and bool(_ref["conditions"]["thrust"][label]["setup"]["conditions"]) and bool(_ref["conditions"]["skewer"][label]["setup"]["conditions"])
	flags_ok = flags_ok and bool(_ref["skewer_deaths"]["burns_after_release"]["setup"]["conditions"])
	for label: String in ["common", "common_crit", "rare", "mythic"]:
		flags_ok = flags_ok and not bool(_ref["thrust"][label]["setup"]["conditions"]) and not bool(_ref["skewer_single"][label]["setup"]["conditions"])
	_ok("each case's fixture says whether conditions are on: the condition cases on, the physical cases off", flags_ok)


## Returns false when the sword type's identity is wrong; every later check builds its fixtures from
## the prototype's key, so they must not run (a renamed key would only crash them).
func _check_definitions() -> bool:
	print("pike: identity, constants and rarity numbers against the prototype")
	var table: Dictionary = _ref["table"]
	var inline: Dictionary = table["inline"]
	var identity_ok: bool = String(SwordDefs.PIKE) == String(table["kind"]) and SwordDefs.display_name(SwordDefs.PIKE) == String(table["name"]) and SwordDefs.is_supported(SwordDefs.PIKE) and SwordDefs.display_name(SwordDefs.WARDEN) == "Warden"
	_ok("the sword type keeps the prototype's internal key `%s` and the display name %s" % [String(SwordDefs.PIKE), SwordDefs.display_name(SwordDefs.PIKE)], identity_ok)
	if not identity_ok:
		return false
	_ok("base length, range, cooldown, damage, knockback, windup, thrust speed, hitstop and shake",
		SwordDefs.base_length(SwordDefs.PIKE) == float(table["length"]) and SwordDefs.base_range(SwordDefs.PIKE) == float(table["range"]) and SwordDefs.base_cooldown(SwordDefs.PIKE) == float(table["cooldown"])
		and SwordDefs.base_damage(SwordDefs.PIKE) == float(table["damage"]) and SwordDefs.base_knock(SwordDefs.PIKE) == float(table["knock"]) and SwordDefs.base_windup(SwordDefs.PIKE) == float(table["windup"])
		and SwordDefs.PIKE_SPEED == float(table["speed"]) and SwordDefs.base_hitstop(SwordDefs.PIKE) == float(table["hitstop"]) and SwordDefs.base_shake(SwordDefs.PIKE) == float(table["shake"]))
	_ok("targeting and the thrust: far preference over 130 px, windup standoff, spring, turn rate, overshoot, tail, tip, hit and parry pads, recovery",
		SwordDefs.PIKE_FAR_MIN == float(inline["far_min"]) and SwordDefs.PIKE_WINDUP_STANDOFF_LENGTH == float(inline["windup_standoff_length"]) and SwordDefs.PIKE_WINDUP_STANDOFF_EXTRA == float(inline["windup_standoff_extra"])
		and SwordDefs.PIKE_WINDUP_SPRING_K == float((inline["windup_spring"] as Array)[0]) and SwordDefs.PIKE_WINDUP_SPRING_C == float((inline["windup_spring"] as Array)[1]) and SwordDefs.PIKE_WINDUP_TURN_RATE == float(inline["windup_ang_rate"])
		and SwordDefs.PIKE_STRIKE_OVERSHOOT == float(inline["overshoot"]) and SwordDefs.PIKE_TAIL_FRACTION == float(inline["tail"]) and SwordDefs.PIKE_TIP_FRACTION == float(inline["tip"])
		and SwordDefs.PIKE_HIT_PAD == float(inline["hit_pad"]) and SwordDefs.PIKE_PARRY_PAD == float(inline["parry_pad"]) and SwordDefs.PIKE_RECOVER_TIME == float(inline["recover_time"]) and SwordDefs.PIKE_RECOVER_SPEED == float(inline["recover_speed"]))
	_ok("the ultimate is named %s: recharge %.1f s, range %.0f px, speed %.0f px/s, a skill shot" % [SwordDefs.ultimate_name(SwordDefs.PIKE), SwordDefs.ultimate_cooldown(SwordDefs.PIKE), SwordDefs.ultimate_range(SwordDefs.PIKE), SwordDefs.PIKE_ULT_SPEED],
		SwordDefs.ultimate_name(SwordDefs.PIKE) == String(table["ult_name"]) and SwordDefs.ultimate_cooldown(SwordDefs.PIKE) == float(table["ult_cd"]) and SwordDefs.ultimate_range(SwordDefs.PIKE) == float(table["ult_range"])
		and SwordDefs.PIKE_ULT_SPEED == float(table["ult_speed"]) and SwordDefs.ultimate_is_shot(SwordDefs.PIKE) == bool(table["ult_shot"]) and SwordDefs.ultimate_is_shot(SwordDefs.PIKE) and not SwordDefs.ultimate_is_shot(SwordDefs.WARDEN))
	_ok("the aim and launch: 0.38 s, standoff, spring, launch offset and shake",
		SwordDefs.PIKE_ULT_AIM_TIME == float(inline["ult_aim_time"]) and SwordDefs.PIKE_ULT_AIM_STANDOFF == float(inline["ult_aim_standoff"]) and SwordDefs.PIKE_ULT_AIM_SPRING_K == float((inline["ult_aim_spring"] as Array)[0])
		and SwordDefs.PIKE_ULT_AIM_SPRING_C == float((inline["ult_aim_spring"] as Array)[1]) and SwordDefs.PIKE_ULT_LAUNCH_AHEAD == float(inline["launch_ahead"]) and SwordDefs.PIKE_ULT_LAUNCH_SHAKE == float(inline["launch_shake"]))
	_ok("the flight and the blow: tail, tip, reach pad, damage factor, doses, shake, carry stun, parry pad",
		SwordDefs.PIKE_ULT_TAIL_FRACTION == float(inline["ult_tail"]) and SwordDefs.PIKE_ULT_TIP_FRACTION == float(inline["ult_tip"]) and SwordDefs.PIKE_ULT_HIT_PAD == float(inline["ult_hit_pad"])
		and SwordDefs.PIKE_ULT_DAMAGE_FACTOR == float(inline["ult_damage"]) and SwordDefs.PIKE_ULT_STACKS == int(inline["ult_stacks"]) and SwordDefs.PIKE_ULT_HIT_SHAKE == float(inline["ult_hit_shake"])
		and SwordDefs.PIKE_ULT_CARRY_STUN == float(inline["carry_stun"]) and SwordDefs.PIKE_ULT_PARRY_PAD == float(inline["ult_parry_pad"]))
	_ok("the ending: wall margin %.0f px a side (the prototype's inflate(-20, -20)), release speeds, stun, recovery" % SwordDefs.PIKE_ULT_WALL_MARGIN,
		SwordDefs.PIKE_ULT_WALL_MARGIN == float(inline["wall_margin"]) and SwordDefs.PIKE_ULT_RELEASE_SPEED_RANGE == float(inline["release_range"]) and SwordDefs.PIKE_ULT_RELEASE_SPEED_WALL == float(inline["release_wall"])
		and SwordDefs.PIKE_ULT_RELEASE_STUN == float(inline["release_stun"]) and SwordDefs.PIKE_ULT_RECOVER_TIME == float(inline["ult_recover_time"]) and SwordDefs.PIKE_ULT_RECOVER_SPEED_RANGE == float(inline["recover_range"])
		and SwordDefs.PIKE_ULT_RECOVER_SPEED_WALL == float(inline["recover_wall"]) and SwordDefs.HEAVY_HIT_FLASH == float(inline["heavy_flash"]) and SwordDefs.NORMAL_HIT_FLASH == float(inline["normal_flash"]))
	var world: Array = table["world"]
	_ok("the arena the wall tests use is the prototype's 2600 x 1800", GameRun.WORLD == Rect2(float(world[0]), float(world[1]), float(world[2]) - float(world[0]), float(world[3]) - float(world[1])))
	var swords: Array = [{"type": "lance", "rarity": 0, "element": "poison", "cd": 99.0}, {"type": "lance", "rarity": 1, "element": "ice", "cd": 99.0}, {"type": "lance", "rarity": 2, "element": "fire", "cd": 99.0}]
	var run: GameRun = GameRun.new(_scenario({"conditions": false, "swords": swords}))
	for rarity: int in 3:
		var sword: SwordState = run.swords[rarity]
		var want: Dictionary = (table["rarities"] as Array)[rarity]
		_ok("rarity %d: damage %.2f, cooldown %.3f, range %.2f, length %.2f, recharge %.2f s" % [rarity, sword.damage, sword.cooldown, sword.attack_range, sword.length, sword.ultimate_cooldown],
			_near(sword.damage, float(want["damage"]), 0.0001) and _near(sword.cooldown, float(want["cooldown"]), 0.0001) and _near(sword.attack_range, float(want["range"]), 0.0001)
			and _near(sword.length, float(want["length"]), 0.0001) and _near(sword.ultimate_cooldown, float(want["ult_max"]), 0.0001) and _near(sword.size_scale, float(want["scale"]), 0.0001))
	_ok("a Pike's ultimate has no area (the HUD and effects read 0 for a skill shot) and a new run starts with every ultimate ready",
		run.swords.all(func(sword: SwordState) -> bool: return sword.ultimate_area_radius() == 0.0 and sword.ultimate_ready() and sword.ultimate_cooldown_left == 0.0 and not sword.skewer_flying and sword.skewer_carried.is_empty()))
	var radii_ok: bool = true
	for kind: String in ["husk", "runner", "brute"]:
		radii_ok = radii_ok and EnemyDefs.of(StringName(kind)).radius == float((table["radius"] as Dictionary)[kind]) and _near(EnemyDefs.of(StringName(kind)).knock, float((table["knock_mult"] as Dictionary)[kind]), 0.0001)
	_ok("the enemy radii and knock factors the geometry depends on match the prototype", radii_ok)
	return true


# --------------------------------------------------------- the thrust
func _check_thrust() -> void:
	print("pike: the long thrust, tick by tick, against the prototype")
	for label: String in ["common", "common_crit", "rare", "mythic"]:
		var case: Dictionary = _ref["thrust"][label]
		var result: Dictionary = _replay(case, 0, false)
		_ok("%s: windup, thrust, recovery, the cooldown and the second thrust match on all %d ticks (sword pose, velocity, cooldown; enemy position, health, knockback, stun; damage, flash, hitstop, shake)" % [label, int(case["trace"]["ticks"])], String(result["diff"]).is_empty(), String(result["diff"]))
		var hits: Array = result["hits"]
		_ok("%s: every thrust hits its target once (%d hits, %d strikes)" % [label, hits.size(), _transition_ticks(case["trace"], "strike").size()], hits.size() == _transition_ticks(case["trace"], "strike").size() and hits.size() >= 2)
	var common: Dictionary = _ref["thrust"]["common"]
	var run: GameRun = _run_of_setup(common["setup"])
	var starts: Array[int] = []
	var strikes: Array[int] = []
	var sword: SwordState = run.swords[0]
	for step: int in range(1, int(common["trace"]["ticks"]) + 1):
		var before: int = sword.phase
		run.step()
		if before != SwordState.Phase.WINDUP and sword.phase == SwordState.Phase.WINDUP:
			starts.append(step)
		if before == SwordState.Phase.WINDUP and sword.phase == SwordState.Phase.STRIKE:
			strikes.append(step)
	var want_starts: Array[int] = _transition_ticks(common["trace"], "windup")
	var want_strikes: Array[int] = _transition_ticks(common["trace"], "strike")
	_ok("attacks begin on ticks %s and strike on %s as the prototype's %s / %s (cooldown %.3f s, windup %.2f s), each announced by a strike cue (%d)" % [starts, strikes, want_starts, want_strikes, sword.cooldown, sword.windup, run.cue_count(SimCue.Kind.SWORD_STRIKE)],
		starts == want_starts and strikes == want_strikes and run.cue_count(SimCue.Kind.SWORD_STRIKE) == strikes.size())
	var boosted: GameRun = _run_of_setup(common["setup"])
	var boosted_target: EnemyState = boosted.enemies[0]
	boosted.swords[0].begin(boosted_target, boosted_target.position, 1.5)
	var start_hp: float = boosted_target.hp
	_steps(boosted, 40)
	_ok("an attack's damage boost (Converge's 1.5x, issue #16) multiplies the thrust's blow: 24 x 1.5 = 36 (%.0f)" % (start_hp - boosted_target.hp), start_hp - boosted_target.hp == 36.0)


func _check_acquire() -> void:
	print("pike: who it targets (the nearest enemy within range, but any farther than 130 px first)")
	for label: String in ["just_inside", "just_outside", "close"]:
		var case: Dictionary = _ref["acquire"][label]
		var run: GameRun = _run_of_setup(case["setup"])
		var left: int = -1
		for step: int in range(1, 60):
			run.step()
			if run.swords[0].phase != SwordState.Phase.IDLE and left < 0:
				left = step
		var want: Variant = case["left_idle"]
		_ok("%s (distance %.0f, range 430 + radius 16): %s" % [label, float(case["distance"]), "it attacks" if want != null else "it stays idle"], (left < 0 and want == null) or (want != null and absi(left - int(want)) <= TICK_TOL))
	var wrong: Array[String] = []
	var count: int = 0
	for key: String in _ref["acquire"]:
		if not key.begins_with("target_"):
			continue
		var case: Dictionary = _ref["acquire"][key]
		var run: GameRun = _run_of_setup(case["setup"])
		var placed: Array[EnemyState] = run.enemies.duplicate()
		run.step()
		count += 1
		var index: int = placed.find(run.swords[0].target)
		if index != int(case["target_index"]):
			wrong.append("%s: %d vs %s" % [key, index, case["target_index"]])
	_ok("the target of %d layouts (a far one preferred over a nearer one in either placement order, the 130 px boundary, the nearest of several far ones, a far one out of range, runners and brutes) matches: %s" % [count, wrong], wrong.is_empty() and count == 10)
	var far: Dictionary = _ref["acquire"]["target_far_preferred"]
	_ok("a farther enemy really is preferred: the fixture's two candidates are at %.0f and %.0f px" % [float(far["setup"]["enemies"][0]["x"]) - CENTER.x, absf(float(far["setup"]["enemies"][1]["x"]) - CENTER.x)], int(far["target_index"]) == 1)


func _check_geometry() -> void:
	print("pike: which points around a thrust it reaches, and on which tick")
	var setup: Dictionary = _ref["geometry"]["setup"]
	var total: int = 0
	var reached: int = 0
	for kind: String in ["husk", "brute"]:
		var wrong: Array[String] = []
		for cell: Variant in _ref["geometry"]["probe_" + kind]:
			var entry: Dictionary = cell as Dictionary
			var probe_spec: Dictionary = {"kind": kind, "x": entry["x"], "y": entry["y"], "hp": PROBE_HP, "speed_scale": 0.0}
			var run: GameRun = _run_of_setup({"conditions": false, "swords": setup["swords"], "enemies": [setup["target"], probe_spec]})
			var primary: EnemyState = run.enemies[0]
			var probe: EnemyState = run.enemies[1]
			run.swords[0].begin(primary, primary.position)
			var hit_tick: int = -1
			for step: int in range(1, 70):
				run.step()
				if probe.hp < PROBE_HP and hit_tick < 0:
					hit_tick = step
			var want: Variant = entry["hit_tick"]
			total += 1
			var good: bool = (want == null and hit_tick < 0) or (want != null and hit_tick >= 0 and absi(hit_tick - int(want)) <= TICK_TOL and _near(PROBE_HP - probe.hp, float(entry["dealt"]), 0.001))
			if good:
				if want != null:
					reached += 1
			else:
				wrong.append("(%s along %.0f, lateral %.0f: tick %d vs %s)" % [kind, float(entry["along"]), float(entry["lateral"]), hit_tick, want])
		_ok("%s probes: every one of %d points reached, or not, on the same tick as the prototype's thrust, for the same damage: %s" % [kind, (_ref["geometry"]["probe_" + kind] as Array).size(), wrong.slice(0, 4)], wrong.is_empty())
	_ok("the grid is a real test: %d of %d probes were hit and the rest were missed" % [reached, total], reached > 30 and reached < total - 30)


func _check_piercing() -> void:
	print("pike: a thrust pierces every enemy on its line, once each, with no gaps")
	for label: String in ["dense_line", "spread_pack"]:
		var case: Dictionary = _ref["piercing"][label]
		var result: Dictionary = _replay(case, 0, false)
		var strikes: int = _transition_ticks(case["trace"], "strike").size()
		var worst: int = 0
		var struck: int = 0
		var enemy_count: int = (case["setup"]["enemies"] as Array).size()
		for k: int in enemy_count:
			var times: int = _hit_count(case["trace"], k)
			worst = maxi(worst, times)
			if times > 0:
				struck += 1
		_ok("%s: all %d ticks match the prototype (%d enemies struck, none more than once per thrust: at most %d hits in %d thrusts)" % [label, int(case["trace"]["ticks"]), struck, worst, strikes], String(result["diff"]).is_empty() and worst <= strikes and struck >= 4, String(result["diff"]))
		_ok("%s: the per-enemy hit counts are the prototype's %s" % [label, case["hits_per_enemy"]], _hit_counts_of(result["hits"], enemy_count) == _int_array(case["hits_per_enemy"]))
	var line: Dictionary = _ref["piercing"]["dense_line"]
	var first_attack: Array[int] = []
	for k: int in 9:
		first_attack.append(0)
	for hit: Variant in line["trace"]["hits"]:
		var hit_entry: Dictionary = hit as Dictionary
		if int(hit_entry["tick"]) > int(_transition_ticks(line["trace"], "recover")[0]):
			break
		for pair: Variant in hit_entry["dealt"]:
			if int((pair as Array)[0]) < 9:
				first_attack[int((pair as Array)[0])] += 1
	_ok("one thrust through a dense line of 11 husks 38 px apart (no gap for 2400 px/s to jump) strikes the first nine exactly once each %s and the two beyond its reach not at all" % [first_attack],
		first_attack == [1, 1, 1, 1, 1, 1, 1, 1, 1] and _hit_count(line["trace"], 9) == 0 and _hit_count(line["trace"], 10) == 0)
	var across: Dictionary = _ref["piercing"]["brute_across_attacks"]
	var result_b: Dictionary = _replay(across, 0, false)
	var attacks: int = _transition_ticks(across["trace"], "strike").size()
	_ok("a large brute (radius 30) standing in the line is hit once per thrust over %d thrusts, never twice in one, and the sword goes on after the first hit" % attacks, String(result_b["diff"]).is_empty() and _hit_count(across["trace"], 0) == attacks and attacks >= 3, String(result_b["diff"]))
	var three: Dictionary = _ref["piercing"]["three_pikes"]
	var result_t: Dictionary = _replay(three, 0, false)
	var run_t: GameRun = result_t["run"]
	_ok("three Pikes at once: the first Pike and every enemy match on all %d ticks, and the states and health end as the prototype's (%s, kills %d)" % [int(three["trace"]["ticks"]), _states(run_t), run_t.kills],
		String(result_t["diff"]).is_empty() and _same_strings(_states(run_t), three["states"]) and run_t.kills == int(three["kills"]), String(result_t["diff"]))


func _int_array(values: Array) -> Array[int]:
	var out: Array[int] = []
	for value: Variant in values:
		out.append(int(value))
	return out


func _hit_counts_of(hits: Array, enemy_count: int) -> Array[int]:
	var counts: Array[int] = []
	for k: int in enemy_count:
		counts.append(0)
	for hit: Variant in hits:
		for pair: Variant in (hit as Dictionary)["dealt"]:
			counts[int((pair as Array)[0])] += 1
	return counts


func _check_deaths() -> void:
	print("pike: deaths during a thrust resolve once")
	var kills: Dictionary = _ref["deaths"]["kills_in_thrust"]
	var result: Dictionary = _replay(kills, 0, false)
	var run: GameRun = result["run"]
	_ok("two fragile enemies and a sturdy one on one thrust: all match on %d ticks; kills %d, combo %d, motes %d, left %d as the prototype" % [int(kills["trace"]["ticks"]), run.kills, run.combo, run.motes.size(), run.enemies.size()],
		String(result["diff"]).is_empty() and run.kills == int(kills["kills"]) and run.combo == int(kills["combo"]) and run.motes.size() == int(kills["motes"]) and run.enemies.size() == int(kills["left"]), String(result["diff"]))
	var two: Dictionary = _ref["deaths"]["two_swords_one_victim"]
	var result_two: Dictionary = _replay(two, 0, false)
	var run_two: GameRun = result_two["run"]
	_ok("when one Pike's thrust kills an enemy, the other Pike's thrust does not reward the corpse again: one kill, %d motes (kills %d)" % [run_two.motes.size(), run_two.kills],
		String(result_two["diff"]).is_empty() and run_two.kills == 1 and run_two.kills == int(two["kills"]) and run_two.motes.size() == int(two["motes"]), String(result_two["diff"]))


func _check_parry() -> void:
	print("pike: the thrust parries every orb its swept segment touches")
	var setup: Dictionary = _ref["parry"]["setup"]
	var wrong: Array[String] = []
	var parried: int = 0
	var cells: Array = _ref["parry"]["grid"]
	for cell: Variant in cells:
		var entry: Dictionary = cell as Dictionary
		var orb: Dictionary = {"x": entry["x"], "y": entry["y"], "vx": 0.0, "vy": 0.0, "life": 10.0}
		var run: GameRun = _run_of_setup({"conditions": false, "swords": setup["swords"], "enemies": [setup["target"]], "orbs": [orb]})
		var primary: EnemyState = run.enemies[0]
		run.swords[0].begin(primary, primary.position)
		var projectile: ProjectileState = run.projectiles[0]
		var tick_parried: int = -1
		for step: int in range(1, 60):
			run.step()
			if projectile.is_resolved() and tick_parried < 0:
				tick_parried = step
		var want: Variant = entry["parried_tick"]
		if (want == null and tick_parried < 0) or (want != null and tick_parried >= 0 and absi(tick_parried - int(want)) <= TICK_TOL):
			if want != null:
				parried += 1
		else:
			wrong.append("(along %.0f lateral %.0f: %d vs %s)" % [float(entry["along"]), float(entry["lateral"]), tick_parried, want])
	_ok("an orb at each of %d points around the thrust is parried (on the prototype's tick) or left alone exactly as the prototype's: %s" % [cells.size(), wrong.slice(0, 4)], wrong.is_empty() and parried > 8 and parried < cells.size() - 8)
	var path: Dictionary = _ref["parry"]["orb_in_the_path"]
	var run_p: GameRun = _run_of_setup(path["setup"])
	var orb_p: ProjectileState = run_p.projectiles[0]
	var tick_p: int = -1
	var hitstop: float = 0.0
	for step: int in range(1, 80):
		run_p.step()
		if orb_p.is_resolved() and tick_p < 0:
			tick_p = step
			hitstop = run_p.hitstop
	_ok("an orb behind the target but on the thrust's line is parried on tick %d (the prototype's %s), with the parry's freeze (%.4f), whatever the thrust hit or missed" % [tick_p, path["parried_tick"], hitstop],
		absi(tick_p - int(path["parried_tick"])) <= TICK_TOL and _near(hitstop, float(path["hitstop"]), SCALAR_TOL) and run_p.cue_count(SimCue.Kind.PROJECTILE_PARRIED) == 1)


# ------------------------------------------------------------- Skewer
func _check_start() -> void:
	print("pike: Skewer's heading (a skill shot, never pulled back to a range) and start")
	var start: Dictionary = _ref["start"]
	var wrong: Array[String] = []
	var count: int = 0
	for key: String in start:
		if key.begins_with("setup") or key.begins_with("interrupts"):
			continue
		var case: Dictionary = start[key]
		var setup: Dictionary = start["setup_facing_north"] if key.ends_with("_facing_north") else start["setup"]
		var run: GameRun = _run_of_setup(setup)
		_steps(run, int(setup["warmup_ticks"]))
		var sword: SwordState = run.swords[int(setup["slot"])]
		var before: Vector2 = sword.position
		run.apply(GameCommand.ultimate(int(setup["slot"]), _point(case["point"])))
		count += 1
		var good: bool = sword.phase == SwordState.Phase.ULTIMATE and not sword.skewer_flying and _ult_phase(sword) == String(case["phase"]) and sword.dir.distance_to(_point(case["dir"])) <= DIR_TOL
		good = good and sword.position.distance_to(before) == 0.0 and sword.position.distance_to(_point(case["pos"])) <= POSITION_TOL and _near(sword.ultimate_cooldown_left, float(case["ult_cd"]), SCALAR_TOL) and _near(sword.ultimate_time_left, float(case["ult_t"]), SCALAR_TOL)
		good = good and run.facing.distance_to(_point(case["facing"])) <= DIR_TOL
		if not good:
			wrong.append("%s: dir %s vs %s" % [key, sword.dir, case["dir"]])
	_ok("the heading, aim clock, recharge and unmoved sword for %d points (inside, at and past the 950 px range, diagonal, south, on the player with either facing) match the prototype: %s" % [count, wrong], wrong.is_empty() and count == 14)
	var windup: Dictionary = start["interrupts_windup"]
	var run_w: GameRun = _run_of_setup(windup["setup"])
	_steps(run_w, 3)
	var sword_w: SwordState = run_w.swords[0]
	var before_state: String = _phase_name(sword_w.phase)
	run_w.apply(GameCommand.ultimate(0, CENTER + Vector2(200.0, 0.0)))
	_ok("a command in the middle of an automatic attack (%s) interrupts it: the sword is aiming, its target and hit set cleared" % before_state, before_state == String(windup["state_before"]) and _phase_name(sword_w.phase) == String(windup["state_after"]) and (sword_w.target == null) == bool(windup["target_cleared"]) and sword_w.sweep_hits.is_empty() == bool(windup["hit_cleared"]) and _ult_phase(sword_w) == String(windup["phase"]))
	var thrust: Dictionary = start["interrupts_thrust"]
	var run_t: GameRun = _run_of_setup(thrust["setup"])
	var sword_t: SwordState = run_t.swords[0]
	for i: int in 60:
		run_t.step()
		if sword_t.phase == SwordState.Phase.STRIKE:
			break
	var hits_before: int = sword_t.sweep_hits.size()
	var state_before: String = _phase_name(sword_t.phase)
	run_t.apply(GameCommand.ultimate(0, CENTER + Vector2(-200.0, 0.0)))
	_ok("a command in the middle of a thrust (%s, hit set %d) drops the thrust and its hit set (%d) and aims the other way" % [state_before, hits_before, sword_t.sweep_hits.size()],
		state_before == String(thrust["state_before"]) and hits_before == int(thrust["hit_before"]) and sword_t.sweep_hits.size() == int(thrust["hit_after"]) and sword_t.phase == SwordState.Phase.ULTIMATE and sword_t.dir.distance_to(_point(thrust["dir"])) <= DIR_TOL)


func _check_skewer_single() -> void:
	print("pike: one Skewer through one enemy: aim, launch, the heavy blow, carry, release")
	for label: String in ["common", "common_crit", "rare", "mythic"]:
		var case: Dictionary = _ref["skewer_single"][label]
		var result: Dictionary = _replay(case)
		var run: GameRun = result["run"]
		_ok("%s: the aim, flight, blow, carry, release and recovery match on all %d ticks (sword, enemy position, velocity, health, stun; heavy flash, shake)" % [label, int(case["trace"]["ticks"])], String(result["diff"]).is_empty(), String(result["diff"]))
		_ok("%s: the enemy is struck exactly once for 2.2 x the sword's damage with no hitstop (%d hits)" % [label, (result["hits"] as Array).size()], (result["hits"] as Array).size() == 1 and run.cue_count(SimCue.Kind.ENEMY_HIT) == 1 and _near(float((result["hits"] as Array)[0]["hitstop"]), float(case["trace"]["hits"][0]["hitstop"]), SCALAR_TOL))
	var common: Dictionary = _ref["skewer_single"]["common"]
	var run_c: GameRun = _skewer_run(common["setup"])
	var launches: int = 0
	var released: int = 0
	var release_amount: int = -1
	for i: int in 110:
		run_c.step()
	for cue: SimCue in run_c.take_cues():
		if cue.kind == SimCue.Kind.SKEWER_LAUNCHED:
			launches += 1
		if cue.kind == SimCue.Kind.SKEWER_RELEASED:
			released += 1
			release_amount = cue.amount
	_ok("the launch and the release are announced once each (cues: %d launched, %d released, %d carried at the end)" % [launches, released, release_amount], launches == 1 and released == 1 and release_amount == 1)


func _check_skewer_carry() -> void:
	print("pike: a Skewer impales what its segment touches and carries it together")
	var line: Dictionary = _ref["skewer_carry"]["line"]
	var result: Dictionary = _replay(line)
	var count: int = (line["setup"]["enemies"] as Array).size()
	var blows: Array[int] = _hit_counts_of(result["hits"], count)
	_ok("a line of enemies, some beside the line, one behind the player and one beyond the range: the aim, flight, blows and carry match on all %d ticks, the release and what follows it included; blows per enemy %s as the prototype's %s" % [int(result["compared"]), blows, _hit_counts_of(line["trace"]["hits"], count)],
		String(result["diff"]).is_empty() and blows == _hit_counts_of(line["trace"]["hits"], count), String(result["diff"]))
	var before_release: Array = (result["hits"] as Array).filter(func(hit: Dictionary) -> bool: return int(hit["tick"]) < _transition_ticks(line["trace"], "recover")[0])
	var struck: Array[int] = _hit_counts_of(before_release, count)
	_ok("no enemy is struck twice by one Skewer before it lets go (most blows on one enemy: %d; the later hits are the release's bowling), and the Skewer ends carrying nothing (%d)" % [struck.max(), (result["run"] as GameRun).swords[0].skewer_carried.size()], struck.max() == 1 and (result["run"] as GameRun).swords[0].skewer_carried.is_empty() and (result["run"] as GameRun).swords[0].phase != SwordState.Phase.ULTIMATE)
	var muzzle: Dictionary = _ref["skewer_carry"]["muzzle"]
	var result_m: Dictionary = _replay(muzzle)
	_ok("enemies right at the muzzle, behind it and beside it (the first flight tick's segment reaches 0.3 lengths behind the launch): the same ones are struck, on the first flight tick (%s), and all %d ticks match" % [_hit_counts_of(result_m["hits"], 6), int(result_m["compared"])],
		String(result_m["diff"]).is_empty() and _hit_counts_of(result_m["hits"], 6) == _hit_counts_of(muzzle["trace"]["hits"], 6) and _hit_counts_of(result_m["hits"], 6) == [1, 0, 1, 0, 0, 1], String(result_m["diff"]))
	var crowd: Dictionary = _ref["skewer_carry"]["crowd"]
	var result_c: Dictionary = _replay(crowd)
	_ok("twelve overlapping enemies carried together (crowd separation pushes them apart while they are carried): the blows, the carry and the release match on all %d ticks" % int(result_c["compared"]),
		String(result_c["diff"]).is_empty() and _hit_counts_of(result_c["hits"], 12) == _hit_counts_of(crowd["trace"]["hits"], 12), String(result_c["diff"]))
	var three: Dictionary = _ref["skewer_carry"]["three_skewers"]
	var run_t: GameRun = _run_of_setup(three["setup"])
	var points: Array = three["setup"]["points"]
	for slot: int in 3:
		run_t.apply(GameCommand.ultimate(slot, _point(points[slot])))
	var enemies_t: Array[EnemyState] = run_t.enemies.duplicate()
	var result_t: Dictionary = _follow(run_t, run_t.swords[0], enemies_t, three["trace"], int(three["trace"]["ticks"]))
	var hp_ok: bool = true
	for k: int in enemies_t.size():
		hp_ok = hp_ok and _near(enemies_t[k].hp, float((three["hp"] as Array)[k]), HP_TOL)
	_ok("three Skewers on one tick (east, west, north), each with its own hit set and carry: the first sword and all four enemies match on %d ticks; states %s, health %s" % [int(three["trace"]["ticks"]), _states(run_t), enemies_t.map(func(e: EnemyState) -> float: return e.hp)],
		String(result_t["diff"]).is_empty() and _same_strings(_states(run_t), three["states"]) and hp_ok, String(result_t["diff"]))


func _check_skewer_empty() -> void:
	print("pike: a Skewer with nothing to hit")
	for label: String in ["range", "wall", "diagonal_range"]:
		var case: Dictionary = _ref["skewer_empty"][label]
		var result: Dictionary = _replay(case)
		var run: GameRun = result["run"]
		_ok("%s: the aim, flight, ending and recovery match on all %d ticks; no hit, no kill (hit cues %d)" % [label, int(case["trace"]["ticks"]), run.cue_count(SimCue.Kind.ENEMY_HIT)], String(result["diff"]).is_empty() and run.cue_count(SimCue.Kind.ENEMY_HIT) == 0 and run.kills == 0, String(result["diff"]))
		var released: Array[SimCue] = run.take_cues().filter(func(cue: SimCue) -> bool: return cue.kind == SimCue.Kind.SKEWER_RELEASED)
		_ok("%s: the ending is announced once, with nobody to fling, as %s" % [label, "a wall" if label == "wall" else "the range limit"], released.size() == 1 and released[0].amount == 0 and released[0].critical == (label == "wall"))


func _check_skewer_walls() -> void:
	print("pike: a Skewer into a wall flings what it carries and the wall slams it")
	for label: String in ["east", "west", "north", "south", "corner_north_east", "corner_south_west", "pile_up"]:
		var case: Dictionary = _ref["skewer_walls"][label]
		var result: Dictionary = _replay(case)
		var run: GameRun = result["run"]
		_ok("%s: the carry, the release at 1100 px/s, the slam damage, bowling and the sword's kick-back match on all %d ticks (kills %d, slam cues %d)" % [label, int(result["compared"]), run.kills, run.cue_count(SimCue.Kind.WALL_SLAM)],
			String(result["diff"]).is_empty() and run.kills == int(case["kills"]) and run.cue_count(SimCue.Kind.WALL_SLAM) >= 1, String(result["diff"]))
		# the port's own outcome against the capture's: one wall slam for every enemy the prototype slammed, and one release
		# announced as a wall carrying what the Skewer carried on the tick before it let go
		var trace: Dictionary = case["trace"]
		var release_tick: int = _transition_ticks(trace, "recover")[0]
		var carried_before: int = int((trace["carried"] as Array)[release_tick - 2])
		var announced: Array[SimCue] = run.take_cues().filter(func(cue: SimCue) -> bool: return cue.kind == SimCue.Kind.SKEWER_RELEASED)
		_ok("%s: the port slams %d enemies (the prototype slammed %d on and after its release tick %d) and announces one release as a wall with %d impaled (the prototype let go of %d)" % [label, run.cue_count(SimCue.Kind.WALL_SLAM), _slams_from(trace, release_tick), release_tick, announced[0].amount if not announced.is_empty() else -1, carried_before],
			run.cue_count(SimCue.Kind.WALL_SLAM) == _slams_from(trace, release_tick) and announced.size() == 1 and announced[0].critical and announced[0].amount == carried_before)
	var east: Dictionary = _ref["skewer_walls"]["east"]
	var run_e: GameRun = _skewer_run(east["setup"])
	var released: Array[SimCue] = []
	var slammed: int = 0
	for i: int in int(east["trace"]["ticks"]):
		run_e.step()
		for cue: SimCue in run_e.take_cues():
			if cue.kind == SimCue.Kind.SKEWER_RELEASED:
				released.append(cue)
			if cue.kind == SimCue.Kind.WALL_SLAM:
				slammed += 1
	_ok("the release is announced once as a wall slam of %d enemies, and the wall slam cue is the existing one (#9): %d slams" % [released[0].amount if not released.is_empty() else -1, slammed], released.size() == 1 and released[0].critical and released[0].amount >= 5 and slammed >= 5)
	for label: String in ["corner_north_east", "corner_south_west"]:
		var corner: Dictionary = _ref["skewer_walls"][label]
		var run_k: GameRun = _skewer_run(corner["setup"])
		var sword_k: SwordState = run_k.swords[0]
		var release_k: int = _transition_ticks(corner["trace"], "recover")[0]
		var launch_dir: Vector2 = Vector2.ZERO
		var released_dir: Vector2 = Vector2.ZERO
		for n: int in range(1, release_k + 1):
			run_k.step()
			if n == 1:
				launch_dir = sword_k.dir
		released_dir = sword_k.dir
		for n: int in range(release_k, int(corner["trace"]["ticks"])):
			run_k.step()
		var slams_k: int = run_k.cue_count(SimCue.Kind.WALL_SLAM)
		_ok("%s: the diagonal heading is kept to the release on tick %d (%s then %s); the port slams %d enemies as the prototype did (%d) and kills %d (%d)" % [label, release_k, launch_dir, released_dir, slams_k, _slams_from(corner["trace"], release_k), run_k.kills, int(corner["kills"])],
			launch_dir.is_equal_approx(released_dir) and absf(launch_dir.x) > 0.5 and absf(launch_dir.y) > 0.5 and slams_k == _slams_from(corner["trace"], release_k) and slams_k >= 5 and run_k.kills == int(corner["kills"]))


## How many enemies the capture's trace shows slammed into a wall: a loss of more than a bowling blow (3 hp) on
## or after the tick the Skewer let go.
func _slams_from(trace: Dictionary, release_tick: int) -> int:
	var slams: int = 0
	for hit: Variant in trace["hits"]:
		if int((hit as Dictionary)["tick"]) < release_tick:
			continue
		for pair: Variant in (hit as Dictionary)["dealt"]:
			if float((pair as Array)[1]) > 10.0:
				slams += 1
	return slams


func _check_skewer_boundary() -> void:
	print("pike: the wall test is the tip against the arena shrunk by 20 px in each dimension")
	var wrong: Array[String] = []
	for key: String in _ref["skewer_boundary"]:
		var case: Dictionary = _ref["skewer_boundary"][key]
		var setup: Dictionary = case["setup"]
		var run: GameRun = _run_of_setup(setup)
		var sword: SwordState = run.swords[0]
		sword.phase = SwordState.Phase.ULTIMATE
		sword.skewer_flying = true
		sword.dir = _point(setup["heading"])
		sword.position = _point(setup["start"])
		sword.ultimate_time_left = float(setup["ult_t"])
		sword.ultimate_cooldown_left = sword.ultimate_cooldown
		sword.sweep_hits.clear()
		var enemies: Array[EnemyState] = run.enemies.duplicate()
		var result: Dictionary = _follow(run, sword, enemies, case["trace"], int(case["trace"]["ticks"]), 0, false)
		if not String(result["diff"]).is_empty():
			wrong.append("%s: %s" % [key, result["diff"]])
	_ok("eight placements, 0.01 px inside and outside each of the four edges of the 10 px margin, end (or do not end) on the prototype's tick and move the victim as it does: %s" % [wrong], wrong.is_empty() and _ref["skewer_boundary"].size() == 8)
	var inside: int = int(_ref["skewer_boundary"]["east_inside"]["left_tick"])
	var outside: int = int(_ref["skewer_boundary"]["east_outside"]["left_tick"])
	_ok("just inside flies one more tick than just outside (%d vs %d)" % [inside, outside], inside == outside + 1)


func _check_skewer_range() -> void:
	print("pike: a Skewer ends at its range and flings what it carries at 750 px/s")
	for label: String in ["near_the_end", "beyond", "diagonal_near_the_end"]:
		var case: Dictionary = _ref["skewer_range"][label]
		var result: Dictionary = _replay(case)
		_ok("%s: the aim, flight, carry and the release at 750 px/s match on all %d ticks (the flight lasts range / speed seconds from the launch)" % [label, int(result["compared"])], String(result["diff"]).is_empty() and (result["run"] as GameRun).swords[0].skewer_carried.is_empty(), String(result["diff"]))
	var near: Dictionary = _ref["skewer_range"]["near_the_end"]
	var run: GameRun = _skewer_run(near["setup"])
	var released: Array[SimCue] = []
	for i: int in 80:
		run.step()
		released.append_array(run.take_cues().filter(func(cue: SimCue) -> bool: return cue.kind == SimCue.Kind.SKEWER_RELEASED))
	_ok("the range ending is announced once as a release of what was impaled, not a wall slam (amount %d, wall %s)" % [released[0].amount if not released.is_empty() else -1, released[0].critical if not released.is_empty() else "n/a"], released.size() == 1 and released[0].amount >= 1 and not released[0].critical)


func _check_skewer_deaths() -> void:
	print("pike: enemies that die while impaled (spec decision 7): corpses still go through movement and separation")
	var deaths: Dictionary = _ref["skewer_deaths"]
	var blow: Dictionary = deaths["killed_by_the_blow"]
	var result_b: Dictionary = _replay(blow)
	var run_b: GameRun = result_b["run"]
	_ok("two enemies killed by the blow itself are not carried and the Skewer flies on: all %d ticks match; kills %d, motes %d, left %d as the prototype" % [int(blow["trace"]["ticks"]), run_b.kills, run_b.motes.size(), run_b.enemies.size()],
		String(result_b["diff"]).is_empty() and run_b.kills == int(blow["kills"]) and run_b.motes.size() == int(blow["motes"]) and run_b.enemies.size() == int(blow["left"]), String(result_b["diff"]))
	for label: String in ["killed_while_carried_at_once", "killed_while_carried_later"]:
		var case: Dictionary = deaths[label]
		var setup: Dictionary = case["setup"]
		var run: GameRun = _skewer_run(setup)
		var enemies: Array[EnemyState] = run.enemies.duplicate()
		var sword: SwordState = run.swords[0]
		var diff: String = ""
		var hp_before: Array[float] = []
		var armed_at: int = -1
		var victim: EnemyState = enemies[int(setup["kill_index"])]
		for n: int in range(1, int(case["trace"]["ticks"]) + 1):
			run.step()
			if diff.is_empty():
				diff = _sword_diff(sword, case["trace"], n - 1, n)
				for k: int in enemies.size():
					if diff.is_empty():
						diff = _enemy_diff(enemies[k], (case["trace"]["enemies"] as Array)[k], n - 1, n, k)
			if armed_at < 0 and sword.skewer_carried.has(enemies[0]) and sword.skewer_carried.has(enemies[1]):
				armed_at = n
			if armed_at >= 0 and n == armed_at + int(setup["kill_after_ticks"]):
				run.kill(victim, Vector2.UP)
		_ok("%s: an impaled enemy killed from outside %d ticks after it was carried (corpse still in the run and the carry list for a tick, beside living neighbours): all %d ticks match; kills %d, motes %d, left %d, carrying %d" % [label, int(setup["kill_after_ticks"]), int(case["trace"]["ticks"]), run.kills, run.motes.size(), run.enemies.size(), sword.skewer_carried.size()],
			diff.is_empty() and armed_at == int(case["armed_at"]) and run.kills == int(case["kills"]) and run.motes.size() == int(case["motes"]) and run.enemies.size() == int(case["left"]), diff)
	var burn: Dictionary = deaths["burns_after_release"]
	var result_n: Dictionary = _replay(burn)
	var run_n: GameRun = result_n["run"]
	var enemies_n: Array[EnemyState] = result_n["enemies"]
	var burn_release: int = _transition_ticks(burn["trace"], "recover")[0]
	_ok("an enemy left at 2 hp by the blow is released on tick %d and burns to death on tick %s (as the prototype: the burn needs longer than the flight leaves, so it dies in the sword's recovery) with neighbours flung on: all %d ticks match; kills %d, motes %d" % [burn_release, burn["died_tick"], int(burn["trace"]["ticks"]), run_n.kills, run_n.motes.size()],
		String(result_n["diff"]).is_empty() and enemies_n[0].dead and int(burn["died_tick"]) > burn_release and run_n.kills == int(burn["kills"]) and run_n.motes.size() == int(burn["motes"]), String(result_n["diff"]))
	var joined: Dictionary = deaths["corpse_joins_the_hit_set"]
	var setup_j: Dictionary = joined["setup"]
	var run_j: GameRun = _run_of_setup(setup_j)
	var skewer_j: SwordState = run_j.swords[int(setup_j["skewer_slot"])]
	var thrust_j: SwordState = run_j.swords[int(setup_j["thrust_slot"])]
	run_j.apply(GameCommand.ultimate(int(setup_j["skewer_slot"]), _point(setup_j["point"])))
	var enemies_j: Array[EnemyState] = run_j.enemies.duplicate()
	var diff_j: String = ""
	for n: int in range(1, int(joined["trace"]["ticks"]) + 1):
		if n == int(setup_j["thrust_begin_tick"]):
			thrust_j.begin(enemies_j[0], enemies_j[0].position)
		run_j.step()
		if diff_j.is_empty():
			diff_j = _sword_diff(skewer_j, joined["trace"], n - 1, n)
			for k: int in enemies_j.size():
				if diff_j.is_empty():
					diff_j = _enemy_diff(enemies_j[k], (joined["trace"]["enemies"] as Array)[k], n - 1, n, k)
	_ok("a Pike's thrust kills an enemy on the very tick the Skewer reaches it: the corpse is in the Skewer's hit set, is not impaled and is not struck or rewarded again (hit set %d, carrying %d, kills %d): all %d ticks match" % [skewer_j.sweep_hits.size(), skewer_j.skewer_carried.size(), run_j.kills, int(joined["trace"]["ticks"])],
		diff_j.is_empty() and not skewer_j.skewer_carried.has(enemies_j[0]) and skewer_j.sweep_hits.has(enemies_j[0]) and skewer_j.sweep_hits.size() == int(joined["hit_size"]) and run_j.kills == int(joined["kills"]) and run_j.motes.size() == int(joined["motes"]), diff_j)
	var wall: Dictionary = deaths["corpses_at_the_wall"]
	var setup_w: Dictionary = wall["setup"]
	var run_w: GameRun = _skewer_run(setup_w)
	var enemies_w: Array[EnemyState] = run_w.enemies.duplicate()
	var sword_w: SwordState = run_w.swords[0]
	var diff_w: String = ""
	for n: int in range(1, int(wall["trace"]["ticks"]) + 1):
		run_w.step()
		if diff_w.is_empty():
			diff_w = _sword_diff(sword_w, wall["trace"], n - 1, n)
			for k: int in enemies_w.size():
				if diff_w.is_empty():
					diff_w = _enemy_diff(enemies_w[k], (wall["trace"]["enemies"] as Array)[k], n - 1, n, k)
		if n == int(setup_w["kill_after_tick"]):
			for index: Variant in setup_w["kill_indices"]:
				run_w.kill(enemies_w[int(index)], Vector2.UP)
	_ok("two impaled enemies (one pinned at the wall) die the tick before the Skewer ends at the east wall: the corpses are dropped from the carry, still moved and separated, the rest are flung and slam: all %d ticks match; kills %d, motes %d, left %d" % [int(wall["trace"]["ticks"]), run_w.kills, run_w.motes.size(), run_w.enemies.size()],
		diff_w.is_empty() and sword_w.phase != SwordState.Phase.ULTIMATE and run_w.kills >= int(wall["kills"]) and run_w.enemies.size() == int(wall["left"]), diff_w)


func _check_skewer_rules() -> void:
	print("pike: Skewer's recharge, refusals and the other Pikes keep thrusting")
	var rules: Dictionary = _ref["skewer_rules"]
	for rarity: int in 3:
		var case: Dictionary = rules["recharge_rarity%d" % rarity]
		var run: GameRun = _run_of_setup(case["setup"])
		run.apply(GameCommand.ultimate(0, CENTER + Vector2(400.0, 0.0)))
		var sword: SwordState = run.swords[0]
		var ready: int = -1
		var good_at: bool = true
		var at: Dictionary = case["ult_cd_at"]
		for step: int in range(1, 800):
			run.step()
			if at.has(str(step)):
				good_at = good_at and _near(sword.ultimate_cooldown_left, float(at[str(step)]), SCALAR_TOL)
			if sword.ultimate_cooldown_left <= 0.0 and ready < 0:
				ready = step
		_ok("rarity %d: the recharge is %.2f s and ends on tick %d (the prototype's %s); the countdown matches at sampled ticks" % [rarity, sword.ultimate_cooldown, ready, case["ready_tick"]], absi(ready - int(case["ready_tick"])) <= TICK_TOL and good_at and _near(sword.ultimate_cooldown, float(case["ult_max"]), 0.0001))
	var recharging: Dictionary = rules["rejected_while_recharging"]
	var run_r: GameRun = _run_of_setup(recharging["setup"])
	run_r.apply(GameCommand.ultimate(0, CENTER + Vector2(400.0, 0.0)))
	_steps(run_r, int(recharging["setup"]["ticks"]))
	var sword_r: SwordState = run_r.swords[0]
	var before_pos: Vector2 = sword_r.position
	var before_cd: float = sword_r.ultimate_cooldown_left
	run_r.take_cues()
	run_r.apply(GameCommand.ultimate(0, CENTER + Vector2(-200.0, 0.0)))
	_ok("a second Skewer while recharging is refused (%.1f s left) and says so on screen; nothing about the sword changes" % before_cd, bool(recharging["refused"]) and sword_r.position == before_pos and sword_r.ultimate_cooldown_left == before_cd and run_r.cue_count(SimCue.Kind.ULTIMATE_REFUSED) == 1 and sword_r.phase != SwordState.Phase.ULTIMATE)
	var active: Dictionary = rules["rejected_while_active"]
	var run_a: GameRun = _run_of_setup(active["setup"])
	run_a.apply(GameCommand.ultimate(0, CENTER + Vector2(400.0, 0.0)))
	_steps(run_a, int(active["setup"]["ticks"]))
	var sword_a: SwordState = run_a.swords[0]
	sword_a.ultimate_cooldown_left = 0.0
	var dir_before: Vector2 = sword_a.dir
	var result: GameRun.UltimateResult = run_a.try_ultimate(0, CENTER + Vector2(-200.0, 0.0))
	_ok("a flying Skewer refuses a second command even with its recharge forced to zero: still %s, heading %s unchanged" % [_ult_phase(sword_a), sword_a.dir], result == GameRun.UltimateResult.ACTIVE and _ult_phase(sword_a) == String(active["after"]["phase"]) and sword_a.dir == dir_before and String(active["before"]["phase"]) == "fly")
	var again: Dictionary = rules["again_after_recharge"]
	var run_g: GameRun = _run_of_setup(again["setup"])
	run_g.apply(GameCommand.ultimate(0, CENTER + Vector2(400.0, 0.0)))
	_steps(run_g, int(again["setup"]["ticks"]))
	run_g.apply(GameCommand.ultimate(0, CENTER + Vector2(-300.0, 0.0)))
	_ok("once the recharge is over Q fires again, now west", run_g.swords[0].phase == SwordState.Phase.ULTIMATE and run_g.swords[0].dir.distance_to(_point(again["dir"])) <= DIR_TOL and String(again["state"]) == "ult")
	var others: Dictionary = rules["others_keep_thrusting"]
	var run_o: GameRun = _run_of_setup(others["setup"])
	var behind: EnemyState = run_o.enemies[0]
	run_o.apply(GameCommand.ultimate(0, CENTER + Vector2(400.0, 0.0)))
	var swept: bool = false
	var states_30: Array[String] = []
	for tick: int in 80:
		run_o.step()
		if tick == 29:
			states_30 = _states(run_o)
		swept = swept or run_o.swords[1].phase != SwordState.Phase.IDLE or run_o.swords[2].phase != SwordState.Phase.IDLE
	_ok("while slot 1 skewers, slots 2 and 3 keep thrusting at the enemy behind the player (states at tick 30: %s)" % [states_30], swept == bool(others["others_thrust"]) and _same_strings(states_30, others["states_at_30"]) and (behind.hp < 100000.0) == bool(others["husk_damaged"]))


func _check_skewer_parry() -> void:
	print("pike: a Skewer parries every orb its segment touches within 14 px")
	var setup: Dictionary = _ref["skewer_parry"]["setup"]
	var wrong: Array[String] = []
	var parried: int = 0
	var cells: Array = _ref["skewer_parry"]["grid"]
	for cell: Variant in cells:
		var entry: Dictionary = cell as Dictionary
		var orb: Dictionary = {"x": entry["x"], "y": entry["y"], "vx": 0.0, "vy": 0.0, "life": 10.0}
		var run: GameRun = _run_of_setup({"conditions": false, "swords": setup["swords"], "orbs": [orb]})
		run.apply(GameCommand.ultimate(0, _point(setup["point"])))
		var projectile: ProjectileState = run.projectiles[0]
		var tick_parried: int = -1
		for step: int in range(1, 90):
			run.step()
			if projectile.is_resolved() and tick_parried < 0:
				tick_parried = step
		var want: Variant = entry["parried_tick"]
		if (want == null and tick_parried < 0) or (want != null and tick_parried >= 0 and absi(tick_parried - int(want)) <= TICK_TOL):
			if want != null:
				parried += 1
		else:
			wrong.append("(along %.0f lateral %.0f: %d vs %s)" % [float(entry["along"]), float(entry["lateral"]), tick_parried, want])
	_ok("an orb at each of %d points (behind the player, along the line, off to the side, at and past the range) is parried on the prototype's tick or left alone: %s" % [cells.size(), wrong.slice(0, 4)], wrong.is_empty() and parried > 8 and parried < cells.size() - 8)
	var aim: Dictionary = _ref["skewer_parry"]["orb_during_aim"]
	var run_a: GameRun = _run_of_setup(aim["setup"])
	var aim_orb: ProjectileState = run_a.projectiles[0]
	run_a.apply(GameCommand.ultimate(0, _point(aim["setup"]["point"])))
	_steps(run_a, int(aim["setup"]["ticks"]))
	_ok("while the Skewer only aims, an orb beside the sword is left alone", (not aim_orb.is_resolved()) == bool(aim["alive"]) and bool(aim["alive"]))


func _check_conditions() -> void:
	print("pike: the conditions the blows leave (thrust one dose, Skewer two)")
	for kind: String in ["thrust", "skewer"]:
		for element: String in ["poison", "ice", "fire"]:
			var case: Dictionary = _ref["conditions"][kind][element]
			var setup: Dictionary = case["setup"]
			var run: GameRun = _skewer_run(setup) if kind == "skewer" else _run_of_setup(setup)
			var enemies: Array[EnemyState] = run.enemies.duplicate()
			var columns: Array = case["conditions"]
			var ticks: int = (columns[0]["x"] as Array).size()
			var diff: String = ""
			for n: int in range(1, ticks + 1):
				run.step()
				for k: int in enemies.size():
					if diff.is_empty():
						diff = _condition_diff(enemies[k], columns[k], n - 1, n, k)
			var last: EnemyConditions = enemies[0].conditions
			_ok("%s with %s: hit points, burn, poison, chill and freeze stacks and positions of three enemies match on all %d ticks (stacks left: poison %d, chill %d, burn %.1f)" % [kind, element, ticks, last.poison_stacks, last.chill_stacks, last.burn], diff.is_empty(), diff)
	var skewer_poison: Array = _ref["conditions"]["skewer"]["poison"]["conditions"]
	var first_stacks: int = 0
	for value: Variant in skewer_poison[0]["poison_stacks"]:
		first_stacks = maxi(first_stacks, int(value))
	_ok("a Skewer's blow leaves two doses on the first enemy (poison stacks %d)" % first_stacks, first_stacks == 2)


func _check_keys() -> void:
	print("pike: Q, E and R and the touch aim")
	var keys: Dictionary = _ref["keys"]
	var setup: Dictionary = keys["setup"]
	for entry: Array in [["key_q", 0], ["key_e", 1], ["key_r", 2]]:
		var run: GameRun = _run_of_setup(setup)
		run.apply(GameCommand.ultimate(int(entry[1]), CENTER + Vector2(400.0, 0.0)))
		_ok("%s starts only slot %d's Skewer" % [entry[0], int(entry[1]) + 1], _same_strings(_states(run), keys[entry[0]]))
	var paused: GameRun = _run_of_setup(setup)
	paused.apply(GameCommand.pause())
	paused.apply(GameCommand.ultimate(0, CENTER + Vector2(400.0, 0.0)))
	_ok("paused: Q starts nothing", _same_strings(_states(paused), keys["paused_q"]["states"]) and paused.swords[0].ultimate_cooldown_left == 0.0)
	var dead: GameRun = _run_of_setup(setup)
	dead.hurt_player(1000, CENTER + Vector2(50.0, 0.0))
	dead.apply(GameCommand.ultimate(1, CENTER + Vector2(400.0, 0.0)))
	_ok("dead: E starts nothing", dead.dead and _same_strings(_states(dead), keys["dead_e"]["states"]) and dead.swords[1].ultimate_cooldown_left == 0.0)
	var touch: Dictionary = keys["auto_aim"]
	var run_t: GameRun = _run_of_setup(touch["setup"])
	var aim: Vector2 = run_t.auto_aim()
	run_t.apply(GameCommand.ultimate_at_nearest(0))
	_ok("touch aiming sends the Skewer toward the nearest living enemy %s (heading %s, not clamped)" % [aim, run_t.swords[0].dir], aim.distance_to(_point(touch["nearest"])) <= POSITION_TOL and run_t.swords[0].dir.distance_to(_point(touch["dir"])) <= DIR_TOL)
	var empty: Dictionary = keys["auto_aim_empty"]
	var run_e: GameRun = _run_of_setup(empty["setup"])
	run_e.apply(GameCommand.ultimate_at_nearest(0))
	_ok("touch aiming with nobody around fires 300 px ahead of the player (heading %s)" % run_e.swords[0].dir, run_e.auto_aim().distance_to(_point(empty["aim"])) <= POSITION_TOL and run_e.swords[0].dir.distance_to(_point(empty["dir"])) <= DIR_TOL)


# ----------------------------------------- removal, cleanup, pause, death
func _lone_run(swords: Array, enemies: Array, conditions: bool = false) -> GameRun:
	return GameRun.new(_scenario({"conditions": conditions, "swords": swords, "enemies": enemies}))


func _pike_trio(cooldown: float) -> Array:
	return [{"type": "lance", "rarity": 0, "element": "fire", "cd": cooldown}, {"type": "lance", "rarity": 0, "element": "fire", "cd": 99.0}, {"type": "lance", "rarity": 0, "element": "fire", "cd": 99.0}]


func _husk_at(dx: float, dy: float, hp: float = PROBE_HP, kind: String = "husk") -> Dictionary:
	return {"kind": kind, "x": CENTER.x + dx, "y": CENTER.y + dy, "hp": hp, "speed_scale": 0.0}


func _check_removed_and_cleanup() -> void:
	print("pike: enemies that leave the run are handled safely (spec decision 7)")
	# The thrust's target leaves the run alive during the windup: it is dropped, nothing is struck.
	var run: GameRun = _lone_run(_pike_trio(0.0), [_husk_at(300.0, 0.0)])
	var sword: SwordState = run.swords[0]
	var gone: EnemyState = run.enemies[0]
	_steps(run, 3)
	var had_target: bool = sword.target == gone
	run.enemies.erase(gone)
	_steps(run, 60)
	_ok("the target removed from the run while alive: the Pike drops it, finishes its thrust, nothing is hit, killed or rewarded (target %s, hp %.0f, kills %d)" % [sword.target, gone.hp, run.kills], had_target and sword.target == null and gone.hp == PROBE_HP and run.kills == 0 and run.cue_count(SimCue.Kind.ENEMY_HIT) == 0 and run.motes.is_empty())
	var run2: GameRun = _lone_run(_pike_trio(0.0), [_husk_at(300.0, 0.0)])
	var sword2: SwordState = run2.swords[0]
	var gone2: EnemyState = run2.enemies[0]
	for i: int in 40:
		run2.step()
		if sword2.phase == SwordState.Phase.STRIKE:
			break
	run2.enemies.erase(gone2)
	_steps(run2, 30)
	_ok("an enemy removed from the run in the middle of the thrust is not struck by it", gone2.hp == PROBE_HP and run2.cue_count(SimCue.Kind.ENEMY_HIT) == 0 and run2.kills == 0)
	# An impaled enemy leaves the run alive: it is no longer carried and not flung; the others carry on.
	var enemies: Array = [_husk_at(250.0, 0.0), _husk_at(262.0, 14.0), _husk_at(330.0, 4.0, PROBE_HP, "runner")]
	var run3: GameRun = _lone_run(_pike_trio(99.0), enemies)
	run3.apply(GameCommand.ultimate(0, CENTER + Vector2(400.0, 0.0)))
	var carried_enemies: Array[EnemyState] = run3.enemies.duplicate()
	var skewer: SwordState = run3.swords[0]
	for i: int in 200:
		run3.step()
		if skewer.skewer_carried.size() >= 2:
			break
	var removed: EnemyState = carried_enemies[0]
	var carried_before: int = skewer.skewer_carried.size()
	run3.enemies.erase(removed)
	var removed_at: Vector2 = removed.position
	var removed_velocity: Vector2 = removed.velocity
	var neighbour: EnemyState = carried_enemies[1]
	var neighbour_before: Vector2 = neighbour.position
	_steps(run3, 3)
	_ok("an impaled enemy removed from the run (alive): it is let go (%d carried before, %d after), no longer moved (%.1f px), the neighbour is still carried on (%.1f px) and nothing breaks" % [carried_before, skewer.skewer_carried.size(), removed.position.distance_to(removed_at), neighbour.position.distance_to(neighbour_before)],
		carried_before >= 2 and not skewer.skewer_carried.has(removed) and removed.position == removed_at and removed.velocity == removed_velocity and neighbour.position.distance_to(neighbour_before) > 100.0 and skewer.skewer_carried.has(neighbour))
	_steps(run3, 120)
	_ok("and when the Skewer ends, the removed enemy is not flung or given any stun (hp %.0f, velocity %s)" % [removed.hp, removed.velocity], removed.position == removed_at and removed.velocity == removed_velocity and skewer.phase != SwordState.Phase.ULTIMATE and skewer.skewer_carried.is_empty())
	# The impaled enemy is removed from the run in the same tick the Skewer ends at a wall.
	var wall_enemies: Array = [{"kind": "husk", "x": 2300.0, "y": 900.0, "hp": PROBE_HP, "speed_scale": 0.0}, {"kind": "husk", "x": 2330.0, "y": 905.0, "hp": PROBE_HP, "speed_scale": 0.0}]
	var wall_scenario: RunScenario = _scenario({"conditions": false, "swords": _pike_trio(99.0), "enemies": wall_enemies, "player": [2150.0, 900.0]})
	var run4: GameRun = GameRun.new(wall_scenario)
	run4.apply(GameCommand.ultimate(0, Vector2(2500.0, 900.0)))
	var pair: Array[EnemyState] = run4.enemies.duplicate()
	var sword4: SwordState = run4.swords[0]
	for i: int in 60:
		run4.step()
		if sword4.skewer_carried.size() == 2 and sword4.ultimate_time_left > 0.2:
			break
	run4.enemies.erase(pair[0])
	_steps(run4, 40)
	_ok("an impaled enemy removed just before the wall: the other is still flung and slams (%d slam cues), the removed one keeps its place and velocity" % run4.cue_count(SimCue.Kind.WALL_SLAM), run4.cue_count(SimCue.Kind.WALL_SLAM) >= 1 and pair[0].velocity.is_zero_approx() and sword4.phase != SwordState.Phase.ULTIMATE)
	# A restart in the middle of a flight leaves new swords: nothing carried, hit sets empty, ready.
	var restarted: GameRun = _lone_run(_pike_trio(99.0), enemies)
	restarted.apply(GameCommand.ultimate(0, CENTER + Vector2(400.0, 0.0)))
	_steps(restarted, 40)
	restarted.apply(GameCommand.restart())
	var fresh: SwordState = restarted.swords[0]
	_ok("a restart in the middle of a Skewer leaves a new sword: idle, ready, nothing carried, no hit set, not flying (restarts %d)" % restarted.restarts, fresh.phase == SwordState.Phase.IDLE and fresh.ultimate_ready() and fresh.skewer_carried.is_empty() and fresh.sweep_hits.is_empty() and not fresh.skewer_flying)


func _check_pause_and_death() -> void:
	print("pike: pause and the player's death in the middle of a flight")
	var case: Dictionary = _ref["skewer_single"]["common"]
	var run: GameRun = _skewer_run(case["setup"])
	var enemies: Array[EnemyState] = run.enemies.duplicate()
	var sword: SwordState = run.swords[0]
	var first: Dictionary = _follow(run, sword, enemies, case["trace"], 35, 0, false)
	var before: Array = [sword.position, sword.dir, sword.ultimate_time_left, sword.skewer_carried.size(), enemies[0].position, enemies[0].hp, run.tick]
	run.apply(GameCommand.pause())
	_steps(run, 90)
	var after: Array = [sword.position, sword.dir, sword.ultimate_time_left, sword.skewer_carried.size(), enemies[0].position, enemies[0].hp, run.tick]
	run.apply(GameCommand.resume())
	var rest: Dictionary = _follow(run, sword, enemies, case["trace"], int(case["trace"]["ticks"]) - 35, 35, false)
	_ok("paused with an enemy impaled (carrying %d): nothing advances, and after resuming the Skewer and the enemy follow the prototype's remaining ticks exactly (health %.0f, one hit cue %d)" % [sword.skewer_carried.size(), enemies[0].hp, run.cue_count(SimCue.Kind.ENEMY_HIT)],
		String(first["diff"]).is_empty() and before == after and (before[3] as int) == 1 and String(rest["diff"]).is_empty() and run.cue_count(SimCue.Kind.ENEMY_HIT) == 1, "%s / %s" % [first["diff"], rest["diff"]])
	var death: Dictionary = _ref["skewer_deaths"]["player_dies_in_flight"]
	var setup: Dictionary = death["setup"]
	var run_d: GameRun = _skewer_run(setup)
	var enemies_d: Array[EnemyState] = run_d.enemies.duplicate()
	var sword_d: SwordState = run_d.swords[0]
	var part_one: Dictionary = _follow(run_d, sword_d, enemies_d, death["trace"], int(setup["die_after_ticks"]), 0, false)
	var carried_at_death: int = sword_d.skewer_carried.size()
	run_d.hurt_player(1000, CENTER + Vector2(-50.0, 0.0))
	var part_two: Dictionary = _follow(run_d, sword_d, enemies_d, death["trace"], int(death["trace"]["ticks"]) - int(setup["die_after_ticks"]), int(setup["die_after_ticks"]), false)
	_ok("the player dies in the middle of the flight (carrying %d): the sword goes idle and lets go, the enemies follow the prototype's remaining ticks, nothing is struck after (%s, carrying %d)" % [carried_at_death, _phase_name(sword_d.phase), sword_d.skewer_carried.size()],
		String(part_one["diff"]).is_empty() and String(part_two["diff"]).is_empty() and run_d.dead and _phase_name(sword_d.phase) == String(death["state"]) and sword_d.skewer_carried.size() == int(death["carried"]) and carried_at_death == int(death["carried_at_death"]) and carried_at_death >= 1, "%s / %s" % [part_one["diff"], part_two["diff"]])


func _check_fixture_and_launch() -> void:
	print("pike: the loadout fixture and the pike encounter")
	var scenario: RunScenario = RunScenario.pike_encounter()
	var kinds: Array[StringName] = [EnemyDefs.HUSK, EnemyDefs.RUNNER, EnemyDefs.BRUTE]
	var counts: Array[int] = []
	for kind: StringName in kinds:
		counts.append(scenario.wave_kinds.count(kind))
	_ok("the pike encounter is a column of %d foes toward the north wall and one wave (%s husk / runner / brute) against three Pikes with poison, ice and fire; conditions on; no shove" % [scenario.initial_enemies.size(), counts],
		scenario.encounter == RunScenario.ENCOUNTER_PIKE and scenario.loadout.size() == 3 and scenario.loadout.all(func(spec: SwordSpec) -> bool: return spec.type_id == SwordDefs.PIKE) and scenario.loadout[0].element == &"poison" and scenario.loadout[1].element == &"ice" and scenario.loadout[2].element == &"fire"
		and scenario.conditions_enabled and not scenario.dev_shove and scenario.waves_enabled and scenario.initial_enemies.size() == 6 and scenario.wave_kinds.size() == 12 and counts[2] == 2 and scenario.start_position.y == 700.0)
	_ok("--encounter=pike and ?encounter=pike ask for it, and asking for nothing starts the normal run with the default loadout (Fang, Warden, Colossus; issue #16)",
		LaunchOptions.scenario_for("pike") != null and LaunchOptions.scenario_for("pike").encounter == RunScenario.ENCOUNTER_PIKE and LaunchOptions.scenario_for("") == null and GameRun.new(LaunchOptions.scenario_for("")).swords.map(func(sword: SwordState) -> StringName: return sword.spec.type_id) == [SwordDefs.FANG, SwordDefs.WARDEN, SwordDefs.COLOSSUS])
	var column_ok: bool = true
	for placement: EnemyPlacement in scenario.initial_enemies:
		var north: float = scenario.start_position.y - placement.position.y
		column_ok = column_ok and north > 300.0 and north < 650.0 and absf(placement.position.x - scenario.start_position.x) < 80.0
	_ok("the column of six stands 300 to 650 px north of the player, in a line a Skewer north passes through (and the wall is north of it)", column_ok and scenario.start_position.y - 650.0 > 0.0)
	var fixed: RunScenario = RunScenario.pike_encounter()
	fixed.seed = 17
	var run: GameRun = GameRun.new(fixed)
	_ok("the encounter equips three Pikes with the Pike's own length (%s) and starts with the column in place" % [run.swords.map(func(s: SwordState) -> float: return s.length)], run.swords.size() == 3 and run.swords.all(func(s: SwordState) -> bool: return s.spec.type_id == SwordDefs.PIKE and s.length == SwordDefs.PIKE_LENGTH) and run.enemies.size() == 6)
	var played: RunScenario = RunScenario.pike_encounter()
	played.seed = 17
	played.first_wave_delay = 0.2
	var fight: GameRun = GameRun.new(played)
	var phases: Dictionary = {}
	for tick: int in 1800:
		if tick in [60, 400, 800]:
			fight.apply(GameCommand.ultimate((tick / 400) % 3, fight.position + Vector2(0.0, -300.0)))
		fight.step()
		for sword: SwordState in fight.swords:
			phases[_phase_name(sword.phase)] = true
		if fight.dead:
			break
	_ok("a played pike encounter shows thrusts, Skewers, kills and a wall (phases %s, kills %d, launched %d, released %d, slams %d)" % [phases.keys(), fight.kills, fight.cue_count(SimCue.Kind.SKEWER_LAUNCHED), fight.cue_count(SimCue.Kind.SKEWER_RELEASED), fight.cue_count(SimCue.Kind.WALL_SLAM)],
		phases.has("strike") and phases.has("ult") and fight.kills >= 5 and fight.cue_count(SimCue.Kind.SKEWER_LAUNCHED) == 3 and fight.cue_count(SimCue.Kind.WALL_SLAM) >= 1)


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
	print("pike: Q, E and R in the real Main scene (HUD cards, cues, effects, visuals)")
	var scenario: RunScenario = RunScenario.pike_encounter()
	scenario.seed = 23
	scenario.first_wave_delay = 0.2
	var main: Main = _main_with(scenario)
	await _tree.process_frame
	main._sfx.unlock()
	main._sfx.played.clear()
	_tick_main(main, 5)
	await _tree.process_frame
	var hud: Hud = main._hud
	_ok("the HUD cards name each slot's ultimate and sword: Skewer x3, Pike sword (skill shot), all READY",
		hud._ult_names[0].text == "Skewer" and hud._ult_names[1].text == "Skewer" and hud._ult_names[2].text == "Skewer" and hud._ult_types[0].text.begins_with("Pike sword") and hud._ult_types[0].text.contains("skill shot")
		and [0, 1, 2].all(func(slot: int) -> bool: return hud.ultimate_status(slot) == "READY" and hud.ultimate_card_visible(slot)))
	var half: Vector2 = main.get_viewport().get_visible_rect().size * 0.5
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = half + Vector2(0.0, -300.0)
	main._input(motion)
	var expected: Vector2 = Vector2(0.0, -1.0)
	main._input(_key(KEY_E))
	var sword: SwordState = main.run.swords[1]
	_ok("E with the mouse 300 px above the view's centre starts slot two's Skewer heading north (%s) while the others stay put" % [sword.dir], sword.phase == SwordState.Phase.ULTIMATE and sword.dir.distance_to(expected) <= 0.01 and main.run.swords[0].phase != SwordState.Phase.ULTIMATE)
	_ok("it is announced and heard (a heave sound, ULTIMATE_STARTED cue)", main.run.cue_count(SimCue.Kind.ULTIMATE_STARTED) == 1 and main._sfx.played.has("dash"), "%s" % [main._sfx.played])
	var effects: EffectsLayer = main._presenter._effects
	_tick_main(main, 8)
	await _tree.process_frame
	_ok("while it aims, the card shows ACTIVE and the layer draws the aim line from the sword's own state (drawn: %s)" % [effects.draw_counts], hud.ultimate_status(1) == "ACTIVE" and sword.phase == SwordState.Phase.ULTIMATE and not sword.skewer_flying and effects.draw_counts.get(&"skewer_aim_band", 0) > 0 and effects.draw_counts.get(&"skewer_aim_line", 0) > 0 and effects.draw_counts.get(&"skewer_carry_ring", 0) == 0)
	var carry_seen: bool = false
	var launch_heard: bool = false
	for i: int in 70:
		_tick_main(main, 1)
		await _tree.process_frame
		carry_seen = carry_seen or (effects.draw_counts.get(&"skewer_carry_ring", 0) > 0 and effects.draw_counts.get(&"skewer_carry_line", 0) > 0)
		launch_heard = launch_heard or main._sfx.played.has("strike")
	_ok("in flight it rings the enemies it carries (%d draws) and the launch and the release are cues (launched %d, released %d)" % [effects.draw_counts.get(&"skewer_carry_ring", 0), main.run.cue_count(SimCue.Kind.SKEWER_LAUNCHED), main.run.cue_count(SimCue.Kind.SKEWER_RELEASED)],
		carry_seen and main.run.cue_count(SimCue.Kind.SKEWER_LAUNCHED) == 1 and main.run.cue_count(SimCue.Kind.SKEWER_RELEASED) == 1 and main.run.cue_count(SimCue.Kind.ENEMY_HIT) >= 3)
	_ok("the encounter legend counts what happened (skewers launched 1, wall slams %d): %s" % [main.run.cue_count(SimCue.Kind.WALL_SLAM), hud._encounter_label.text.get_slice("\n", 0)],
		main.run.cue_count(SimCue.Kind.WALL_SLAM) >= 1 and hud._encounter_label.text.contains("skewers launched 1") and hud._encounter_label.text.contains("wall slams %d" % main.run.cue_count(SimCue.Kind.WALL_SLAM)))
	_ok("after the Skewer the card counts the recharge down in whole seconds (%s)" % hud.ultimate_status(1), hud.ultimate_status(1) == "%ds" % SimMath.py_round(sword.ultimate_cooldown_left) and hud.ultimate_bar_fraction(1) > 0.0 and hud.ultimate_bar_fraction(1) < 1.0)
	var rings_before: int = effects._rings.size()
	var launched: SimCue = SimCue.make(SimCue.Kind.SKEWER_LAUNCHED, CENTER, Vector2.RIGHT)
	effects.apply_cue(launched)
	var rings_after_launch: int = effects._rings.size()
	var texts_before: int = effects._texts.size()
	effects.apply_cue(SimCue.make(SimCue.Kind.SKEWER_RELEASED, CENTER, Vector2.RIGHT, 4, true))
	var rings_after_release: int = effects._rings.size()
	var texts_after_release: int = effects._texts.size()
	effects.apply_cue(SimCue.make(SimCue.Kind.SKEWER_RELEASED, CENTER, Vector2.RIGHT, 0, false))
	var texts_after_empty: int = effects._texts.size()
	var started: SimCue = SimCue.make(SimCue.Kind.ULTIMATE_STARTED, sword.position, Vector2.RIGHT, 1)
	started.origin = sword.position
	var rings_before_start: int = effects._rings.size()
	effects.apply_cue(started)
	_ok("a launch draws one ring, a release one ring and a 'SLAM x4' number (an empty release no number), and a Skewer's start draws only its own ring, no landing ring (a skill shot has no area)",
		rings_after_launch == rings_before + 1 and rings_after_release == rings_after_launch + 1 and texts_after_release == texts_before + 1 and texts_after_empty == texts_after_release and effects._rings.size() == rings_before_start + 1)
	var texts_now: int = effects._texts.size()
	main._input(_key(KEY_E))
	_ok("E while it recharges is refused and says so on screen", main.run.cue_count(SimCue.Kind.ULTIMATE_REFUSED) == 1 and effects._texts.size() == texts_now + 1)
	var telegraph_seen: bool = false
	for i: int in 240:
		_tick_main(main, 1)
		await _tree.process_frame
		telegraph_seen = telegraph_seen or (effects.draw_counts.get(&"thrust_telegraph_band", 0) > 0 and effects.draw_counts.get(&"thrust_telegraph_line", 0) > 0)
	_ok("while the Pikes thrust, the windup shows the line it will cut (drawn: %s)" % [effects.draw_counts], telegraph_seen)
	await _tree.create_timer(0.1).timeout
	main._sfx.played.clear()
	main._sfx.play_cue(SimCue.make(SimCue.Kind.SKEWER_LAUNCHED, Vector2.ZERO, Vector2.RIGHT))
	var launch_is_heard: bool = main._sfx.played.has("strike")
	main._sfx.played.clear()
	await _tree.create_timer(0.1).timeout
	main._sfx.play_cue(SimCue.make(SimCue.Kind.SKEWER_RELEASED, Vector2.ZERO, Vector2.ZERO, 0))
	var silent_release: bool = main._sfx.played.is_empty()
	main._sfx.play_cue(SimCue.make(SimCue.Kind.SKEWER_RELEASED, Vector2.ZERO, Vector2.ZERO, 3))
	_ok("the launch is heard (a thrust's sound), a release that flung something is heard, one that flung nothing is silent", launch_is_heard and silent_release and main._sfx.played.has("hit"), "%s" % [main._sfx.played])
	var pike_visuals: int = 0
	for child: Node in main._presenter.get_children():
		if child is PlaceholderSwordVisual and (child as PlaceholderSwordVisual)._pike:
			pike_visuals += 1
	_ok("the three Pikes are drawn with the long shaft and leaf head (%d Pike visuals)" % pike_visuals, pike_visuals == 3)
	main.queue_free()
	await _tree.process_frame


func _check_hud() -> void:
	print("pike: the HUD in the pike encounter lies inside the viewport")
	var window: Window = Window.new()
	window.size = Vector2i(1084, 720)
	window.content_scale_size = Vector2i(1280, 720)
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	_tree.root.add_child(window)
	var hud: Hud = Hud.new()
	window.add_child(hud)
	var run: GameRun = GameRun.new(RunScenario.pike_encounter())
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
	_ok("the cards read Skewer x3 with POISON, ICE and FIRE tags and 'Pike sword  skill shot' under the bar",
		hud._ult_names[1].text == "Skewer" and hud._ult_elements[0].text == "POISON" and hud._ult_elements[1].text == "ICE" and hud._ult_elements[2].text == "FIRE" and hud._ult_types[2].text.begins_with("Pike sword") and hud._ult_types[2].text.contains("skill shot"))
	_ok("the encounter legend names the Skewer count and the wall slams", hud._encounter_label.visible and hud._encounter_label.text.contains("PIKE ENCOUNTER") and hud._encounter_label.text.contains("skewers launched 0") and hud._encounter_label.text.contains("wall slams 0"))
	window.queue_free()
	await _tree.process_frame


func _check_visual_independence() -> void:
	print("pike: swapping the sword visual leaves the fight unchanged")
	var hosts: Array[Main] = []
	for use_alt: bool in [false, true]:
		hosts.append(_main_with(RenderRateScenario.scenario(RenderRateScenario.PIKE), "res://tests/alt_sword.tscn" if use_alt else ""))
	await _tree.process_frame
	var seen_phases: Dictionary = {}
	var results: Array[Dictionary] = []
	for host_index: int in hosts.size():
		var main: Main = hosts[host_index]
		for tick_index: int in 500:
			for command: GameCommand in RenderRateScenario.commands_at(main.run.tick, RenderRateScenario.PIKE):
				main.run.apply(command)
			_tick_main(main, 1)
			if host_index == 1:
				for child: Node in main._presenter.get_children():
					if child is AltSwordVisual:
						seen_phases[(child as AltSwordVisual).last_phase] = true
		results.append(main.run.snapshot())
	_ok("a stretched, rotated replacement sword visual changes nothing about the thrusts, Skewers, carries, kills or recharges", results[0] == results[1])
	_ok("the replacement visual was told the strike and ultimate phases (%s)" % [seen_phases.keys()], seen_phases.has(SwordState.Phase.STRIKE) and seen_phases.has(SwordState.Phase.ULTIMATE))
	_ok("the fixture fought: %d hits, %d kills, %d Skewers launched, %d released, %d slams" % [hosts[0].run.cue_count(SimCue.Kind.ENEMY_HIT), hosts[0].run.kills, hosts[0].run.cue_count(SimCue.Kind.SKEWER_LAUNCHED), hosts[0].run.cue_count(SimCue.Kind.SKEWER_RELEASED), hosts[0].run.cue_count(SimCue.Kind.WALL_SLAM)],
		hosts[0].run.cue_count(SimCue.Kind.ENEMY_HIT) >= 20 and hosts[0].run.cue_count(SimCue.Kind.SKEWER_RELEASED) >= 2 and hosts[0].run.cue_count(SimCue.Kind.WALL_SLAM) >= 2)
	for main: Main in hosts:
		main.queue_free()
	await _tree.process_frame
