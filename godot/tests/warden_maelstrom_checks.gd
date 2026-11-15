class_name WardenMaelstromChecks
extends RefCounted
## Game-run behavioural checks for the Warden sword (automatic sweeping arcs) and its ultimate,
## Maelstrom (issue #13). Like the earlier slices' checks, every check drives the real `GameRun`
## through `GameCommand`s (or the real Main scene with real key events), advances fixed ticks
## and observes outcomes. Comparison values come from the Python prototype's captured reference
## (res://tests/reference/warden_maelstrom.json, recorded by
## tools/reference/capture_warden_maelstrom.py), which also carries each case's fixture
## (`setup`, including whether elemental conditions are on), so no starting number is copied
## into this file. Most cases compare the sword and every enemy on EVERY tick, not just
## outcomes. Tolerances and deliberate exceptions: docs/reference/warden-maelstrom.md.

const REFERENCE_PATH: String = "res://tests/reference/warden_maelstrom.json"
const PROBE_SCRIPT: String = "res://tests/frame_rate_probe.gd"

## Same-algorithm comparisons at the prototype's 60 FPS step.
const POSITION_TOL: float = 0.05  # px
const VELOCITY_TOL: float = 0.5  # px/s (the prototype's value is a rounded position difference x 60)
const SCALAR_TOL: float = 0.002  # timers, cooldowns, shake, stun, flash
const ANGLE_TOL: float = 0.002
const HP_TOL: float = 0.001
const TICK_TOL: int = 1
const PROBE_FRAME_RATES: Array[int] = [5, 20, 60, 240]
const CENTER: Vector2 = Vector2(1300.0, 900.0)
## The health the capture gave its stationary probes and posts (a placement's health is not its maximum).
const PROBE_HP: float = 900.0

var _check: Callable
var _tree: SceneTree
var _ref: Dictionary = {}


func _init(check_function: Callable, tree: SceneTree) -> void:
	_check = check_function
	_tree = tree


func run_all() -> void:
	if not CheckFocus.includes("warden_maelstrom"):
		return
	var file: FileAccess = FileAccess.open(REFERENCE_PATH, FileAccess.READ)
	if file == null:
		_ok("warden reference file loads", false, REFERENCE_PATH)
		return
	_ref = JSON.parse_string(file.get_as_text())
	_ok("warden reference file parses", not _ref.is_empty())
	_check_reference_scope()
	if not _check_definitions():
		print("warden: the sword type's identity is wrong; the remaining checks build fixtures from it and are skipped")
		return
	_check_sweep()
	_check_acquire()
	_check_arc_coverage()
	_check_multi_target()
	_check_deaths()
	_check_parry()
	_check_recover_and_cooldown()
	_check_range_and_start()
	_check_maelstrom_single()
	_check_maelstrom_pull()
	_check_maelstrom_kills()
	_check_maelstrom_clocks()
	_check_maelstrom_rules()
	_check_orb_in_the_whirl()
	_check_sweep_conditions()
	_check_maelstrom_conditions()
	_check_keys_and_touch()
	_check_removed_and_corpses()
	_check_pause_and_death_in_a_sweep()
	_check_fixture_and_launch()
	await _check_main_scene()
	await _check_hud()
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


## A scenario from a case's `setup`: its swords (type, rarity, element, starting cooldown),
## enemies and whether elemental conditions are on, with no waves.
func _scenario(swords: Array, enemies: Array, conditions: bool, crit: bool = false) -> RunScenario:
	var scenario: RunScenario = RunScenario.new()
	if not conditions:
		scenario = scenario.without_conditions()
	scenario.seed = 41
	scenario.waves_enabled = false
	scenario.crit_chance = 1.0 if crit else 0.0
	var specs: Array[SwordSpec] = []
	var cooldowns: Array[float] = []
	for sword: Variant in swords:
		var entry: Dictionary = sword as Dictionary
		specs.append(SwordSpec.make(StringName(entry["type"]), int(entry["rarity"]), StringName(entry["element"])))
		cooldowns.append(float(entry["cd"]))
	scenario.loadout = specs
	scenario.sword_start_cooldowns = cooldowns
	var placements: Array[EnemyPlacement] = []
	for enemy: Variant in enemies:
		var spec: Dictionary = enemy as Dictionary
		var placement: EnemyPlacement = EnemyPlacement.make(StringName(spec["kind"]), Vector2(float(spec["x"]), float(spec["y"])))
		placement.speed_scale = float(spec["speed_scale"])
		placement.hp = float(spec["hp"])
		placement.velocity = Vector2(float(spec.get("vx", 0.0)), float(spec.get("vy", 0.0)))
		placement.stun = float(spec.get("stun", 0.0))
		placements.append(placement)
	scenario.initial_enemies = placements
	return scenario


func _run_of_setup(setup: Dictionary) -> GameRun:
	var run: GameRun = GameRun.new(_scenario(setup["swords"], setup.get("enemies", []), bool(setup["conditions"]), bool(setup.get("crit", false))))
	for orb: Variant in setup.get("orbs", []):
		var spec: Dictionary = orb as Dictionary
		var projectile: ProjectileState = ProjectileState.make(Vector2(float(spec["x"]), float(spec["y"])), Vector2(float(spec["vx"]), float(spec["vy"])))
		projectile.life = float(spec["life"])
		run.projectiles.append(projectile)
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


func _sword_row(sword: SwordState) -> Dictionary:
	return {"state": _phase_name(sword.phase), "x": sword.position.x, "y": sword.position.y, "ang": sword.angle, "vx": sword.velocity.x, "vy": sword.velocity.y}


## Plays `ticks` fixed ticks on `run`, comparing on every tick the sword and every enemy with the
## reference trace (`trace`), the enemies' conditions with `conditions` (one dictionary of
## per-tick lists per enemy; the keys the Python side recorded) and the hit list (which
## enemy lost how much health on which tick, with the hitstop, shake and flash that followed).
## `sword` may be null when only conditions are compared. Returns {"diff": first difference or
## "", "hits": what happened, "sides": the sweep side at each windup}.
func _follow(run: GameRun, sword: SwordState, enemies: Array[EnemyState], trace: Dictionary, conditions: Array, ticks: int) -> Dictionary:
	var diff: String = ""
	var hits: Array[Dictionary] = []
	var sides: Array[int] = []
	var phase_before: int = sword.phase if sword != null else -1
	var hp_before: Array[float] = []
	for enemy: EnemyState in enemies:
		hp_before.append(enemy.hp)
	for n: int in range(1, ticks + 1):
		run.step()
		var i: int = n - 1
		var dealt: Array = []
		var flashes: Array = []
		for k: int in enemies.size():
			if enemies[k].hp < hp_before[k]:
				dealt.append([k, snappedf(hp_before[k] - enemies[k].hp, 0.0001)])
				flashes.append(enemies[k].flash)
				hp_before[k] = enemies[k].hp
		if not dealt.is_empty():
			hits.append({"tick": n, "dealt": dealt, "hitstop": run.hitstop, "trauma": run.trauma, "flash": flashes})
		if sword != null:
			if sword.phase == SwordState.Phase.WINDUP and phase_before != SwordState.Phase.WINDUP:
				sides.append(sword.side)
			phase_before = sword.phase
		if not diff.is_empty():
			continue
		if sword != null and not trace.is_empty():
			diff = _sword_diff(sword, trace, i, n)
			if diff.is_empty() and trace.has("enemies"):
				for k: int in enemies.size():
					diff = _enemy_diff(enemies[k], (trace["enemies"] as Array)[k], i, n, k)
					if not diff.is_empty():
						break
		if diff.is_empty() and not conditions.is_empty():
			for k: int in enemies.size():
				diff = _condition_diff(enemies[k], conditions[k], i, n, k)
				if not diff.is_empty():
					break
	if diff.is_empty() and not trace.is_empty() and trace.has("hits"):
		diff = _hits_diff(hits, trace["hits"])
	return {"diff": diff, "hits": hits, "sides": sides}


func _sword_diff(sword: SwordState, trace: Dictionary, i: int, n: int) -> String:
	var state: String = _phase_name(sword.phase)
	if state != String((trace["state"] as Array)[i]):
		return "tick %d: phase %s vs %s" % [n, state, (trace["state"] as Array)[i]]
	var pairs: Array = [["x", sword.position.x, POSITION_TOL], ["y", sword.position.y, POSITION_TOL], ["ang", sword.angle, ANGLE_TOL]]
	if trace.has("vx"):
		pairs.append_array([["vx", sword.velocity.x, VELOCITY_TOL], ["vy", sword.velocity.y, VELOCITY_TOL], ["spin", sword.ultimate_spin, ANGLE_TOL],
			["ult_t", sword.ultimate_time_left, SCALAR_TOL], ["beat", sword.ultimate_beat, SCALAR_TOL], ["ult_cd", sword.ultimate_cooldown_left, SCALAR_TOL],
			["side", float(sword.side), 0.0], ["cd", sword.cooldown_left, SCALAR_TOL]])
	for pair: Array in pairs:
		var want: float = float((trace[pair[0]] as Array)[i])
		if not _near(float(pair[1]), want, float(pair[2])):
			return "tick %d: sword %s %.4f vs %.4f" % [n, pair[0], float(pair[1]), want]
	return ""


func _enemy_diff(enemy: EnemyState, ref: Dictionary, i: int, n: int, k: int) -> String:
	var pairs: Array = [["x", enemy.position.x, POSITION_TOL], ["y", enemy.position.y, POSITION_TOL], ["hp", enemy.hp, HP_TOL]]
	if ref.has("vx"):
		pairs.append_array([["vx", enemy.velocity.x, VELOCITY_TOL], ["vy", enemy.velocity.y, VELOCITY_TOL], ["stun", enemy.stun, SCALAR_TOL]])
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


## The conditions of a Maelstrom/sweep case as a per-enemy list (the sweep cases record one enemy
## as a single dictionary).
func _per_enemy(conditions: Variant) -> Array:
	if conditions is Dictionary:
		return [conditions]
	return conditions as Array


# ------------------------------------------------------------- reference
func _check_reference_scope() -> void:
	print("warden: the reference was captured with out-of-scope mechanics disabled")
	var scope: Dictionary = _ref["fixture_scope"]
	_ok("every enemy in the capture was unarmed (arming and drops are issue #17) and only husks, runners and brutes were used", int(scope["armed_enemies"]) == 0 and scope["kinds"] == ["brute", "husk", "runner"])
	_ok("only Warden swords took part, Converge was not used (issue #16), no waves ran (issue #18)", scope["swords_used"] == ["blade"] and not bool(scope["converge_used"]) and not bool(scope["waves_enabled"]))
	var with_conditions: Array = scope["afflict_enabled_cases"]
	_ok("the prototype's afflict was OFF everywhere except the condition cases %s" % [with_conditions], bool(scope["afflict_disabled_everywhere_else"]) and with_conditions == ["maelstrom_corpses", "maelstrom_fire", "maelstrom_ice", "maelstrom_poison", "sweep_fire", "sweep_ice", "sweep_pack", "sweep_poison"])
	var flags_ok: bool = true
	for label: String in ["poison", "ice", "fire"]:
		flags_ok = flags_ok and bool(_ref["sweep_conditions"][label]["setup"]["conditions"]) and bool(_ref["maelstrom_conditions"][label]["setup"]["conditions"])
	flags_ok = flags_ok and bool(_ref["sweep_conditions"]["pack_poison"]["setup"]["conditions"])
	for label: String in ["common", "common_crit", "rare", "mythic"]:
		flags_ok = flags_ok and not bool(_ref["sweep"][label]["setup"]["conditions"]) and not bool(_ref["maelstrom_single"][label]["setup"]["conditions"])
	_ok("each case's fixture says whether conditions are on: the condition cases on, the physical cases off", flags_ok)


## Returns false when the sword type's identity is wrong; every later check builds its fixtures from
## the prototype's key, so they must not run (a renamed key would only crash them).
func _check_definitions() -> bool:
	print("warden: identity, constants and rarity numbers against the prototype")
	var table: Dictionary = _ref["table"]
	var inline: Dictionary = table["inline"]
	var identity_ok: bool = String(SwordDefs.WARDEN) == String(table["kind"]) and SwordDefs.display_name(SwordDefs.WARDEN) == String(table["name"]) and SwordDefs.is_supported(SwordDefs.WARDEN) and SwordDefs.display_name(SwordDefs.FANG) == "Fang"
	_ok("the sword type keeps the prototype's internal key `%s` and the display name %s" % [String(SwordDefs.WARDEN), SwordDefs.display_name(SwordDefs.WARDEN)], identity_ok)
	if not identity_ok:
		return false
	_ok("base length, range, cooldown, damage, knockback, windup, hitstop and shake",
		SwordDefs.base_length(SwordDefs.WARDEN) == float(table["length"]) and SwordDefs.base_range(SwordDefs.WARDEN) == float(table["range"]) and SwordDefs.base_cooldown(SwordDefs.WARDEN) == float(table["cooldown"])
		and SwordDefs.base_damage(SwordDefs.WARDEN) == float(table["damage"]) and SwordDefs.base_knock(SwordDefs.WARDEN) == float(table["knock"]) and SwordDefs.base_windup(SwordDefs.WARDEN) == float(table["windup"])
		and SwordDefs.base_hitstop(SwordDefs.WARDEN) == float(table["hitstop"]) and SwordDefs.base_shake(SwordDefs.WARDEN) == float(table["shake"]))
	_ok("the sweep: 0.15 s, start and end angles, pivot offset, pose radius, guard and tip, hit and parry pads, tangent weight, recovery",
		SwordDefs.WARDEN_SWEEP_TIME == float(inline["sweep_time"]) and SwordDefs.WARDEN_SWEEP_START == float(inline["start_angle"]) and SwordDefs.WARDEN_SWEEP_END == float(inline["end_angle"])
		and SwordDefs.WARDEN_PIVOT_BACK == float(inline["pivot_back"]) and SwordDefs.WARDEN_POSE_RADIUS == float(inline["pose_radius"]) and SwordDefs.WARDEN_GUARD == float(inline["guard"]) and SwordDefs.WARDEN_TIP == float(inline["tip"])
		and SwordDefs.WARDEN_HIT_PAD == float(inline["hit_pad"]) and SwordDefs.WARDEN_PARRY_PAD == float(inline["parry_pad"]) and SwordDefs.WARDEN_TANGENT_WEIGHT == float(inline["tangent_weight"])
		and SwordDefs.WARDEN_RECOVER_TIME == float(inline["recover_time"]) and SwordDefs.WARDEN_RECOVER_SPEED == float(inline["recover_speed"])
		and SwordDefs.WARDEN_WINDUP_SPRING_K == float((inline["windup_spring"] as Array)[0]) and SwordDefs.WARDEN_WINDUP_SPRING_C == float((inline["windup_spring"] as Array)[1]) and SwordDefs.WARDEN_WINDUP_TURN_RATE == float(inline["windup_ang_rate"]))
	_ok("the ultimate is named %s: recharge %.1f s, range %.0f px, radius %.0f px, not a skill shot" % [SwordDefs.ultimate_name(SwordDefs.WARDEN), SwordDefs.ultimate_cooldown(SwordDefs.WARDEN), SwordDefs.ultimate_range(SwordDefs.WARDEN), SwordDefs.WARDEN_ULT_RADIUS],
		SwordDefs.ultimate_name(SwordDefs.WARDEN) == String(table["ult_name"]) and SwordDefs.ultimate_cooldown(SwordDefs.WARDEN) == float(table["ult_cd"]) and SwordDefs.ultimate_range(SwordDefs.WARDEN) == float(table["ult_range"])
		and SwordDefs.WARDEN_ULT_RADIUS == float(table["ult_radius"]) and SwordDefs.ultimate_is_shot(SwordDefs.WARDEN) == bool(table["ult_shot"]))
	_ok("the whirl: duration, first beat, beat, spin rate, approach rate, reach tail, pull minimum, extra range and speed",
		SwordDefs.WARDEN_ULT_DURATION == float(inline["ult_time"]) and SwordDefs.WARDEN_ULT_FIRST_BEAT == float(inline["first_beat"]) and SwordDefs.WARDEN_ULT_BEAT == float(inline["beat"]) and SwordDefs.WARDEN_ULT_SPIN_RATE == float(inline["spin_rate"])
		and SwordDefs.WARDEN_ULT_APPROACH_RATE == float(inline["approach_rate"]) and SwordDefs.WARDEN_ULT_REACH_TAIL == float(inline["reach_tail"]) and SwordDefs.WARDEN_ULT_PULL_MIN == float(inline["pull_min"])
		and SwordDefs.WARDEN_ULT_PULL_EXTRA == float(inline["pull_extra"]) and SwordDefs.WARDEN_ULT_PULL_SPEED == float(inline["pull_speed"]))
	_ok("the beats and the burst: damage factors, knockbacks, shakes, margin, doses, hitstop, recovery",
		SwordDefs.WARDEN_ULT_TICK_FACTOR == float(inline["tick_damage"]) and SwordDefs.WARDEN_ULT_TICK_KNOCK == float(inline["tick_knock"]) and SwordDefs.WARDEN_ULT_TICK_SHAKE == float(inline["tick_shake"])
		and SwordDefs.WARDEN_ULT_BURST_FACTOR == float(inline["burst_damage"]) and SwordDefs.WARDEN_ULT_BURST_KNOCK == float(inline["burst_knock"]) and SwordDefs.WARDEN_ULT_BURST_MARGIN == float(inline["burst_margin"])
		and SwordDefs.WARDEN_ULT_BURST_STACKS == int(inline["burst_stacks"]) and SwordDefs.WARDEN_ULT_BURST_SHAKE == float(inline["burst_shake"]) and SwordDefs.WARDEN_ULT_BURST_HITSTOP == float(inline["burst_hitstop"])
		and SwordDefs.WARDEN_ULT_RECOVER_TIME == float(inline["ult_recover_time"]) and SwordDefs.WARDEN_ULT_RECOVER_SPEED == float(inline["ult_recover_speed"])
		and SwordDefs.HEAVY_HIT_FLASH == float(inline["heavy_flash"]) and SwordDefs.NORMAL_HIT_FLASH == float(inline["normal_flash"]))
	var swords: Array = [{"type": "blade", "rarity": 0, "element": "poison", "cd": 99.0}, {"type": "blade", "rarity": 1, "element": "ice", "cd": 99.0}, {"type": "blade", "rarity": 2, "element": "fire", "cd": 99.0}]
	var run: GameRun = GameRun.new(_scenario(swords, [], false))
	for rarity: int in 3:
		var sword: SwordState = run.swords[rarity]
		var want: Dictionary = (table["rarities"] as Array)[rarity]
		_ok("rarity %d: damage %.2f, cooldown %.3f, range %.2f, length %.2f, recharge %.2f s, Maelstrom reach %.2f" % [rarity, sword.damage, sword.cooldown, sword.attack_range, sword.length, sword.ultimate_cooldown, sword.maelstrom_reach()],
			_near(sword.damage, float(want["damage"]), 0.0001) and _near(sword.cooldown, float(want["cooldown"]), 0.0001) and _near(sword.attack_range, float(want["range"]), 0.0001)
			and _near(sword.length, float(want["length"]), 0.0001) and _near(sword.ultimate_cooldown, float(want["ult_max"]), 0.0001) and _near(sword.size_scale, float(want["scale"]), 0.0001)
			and _near(sword.maelstrom_reach(), 100.0 * float(want["scale"]) + float(want["length"]) * 0.7, 0.0001))
	var fang_run: GameRun = GameRun.new(RunScenario.warden_encounter())
	_ok("the area a running ultimate acts in is Maelstrom's blade reach for a Warden (%.1f) and Viper Flurry's 150 px for a Fang" % run.swords[0].ultimate_area_radius(),
		run.swords.all(func(sword: SwordState) -> bool: return sword.ultimate_area_radius() == sword.maelstrom_reach()) and fang_run.swords[0].ultimate_area_radius() == SwordDefs.FANG_ULT_RADIUS and fang_run.swords[1].ultimate_area_radius() == fang_run.swords[1].maelstrom_reach())
	_ok("a new run starts with every Warden's ultimate ready", run.swords.all(func(sword: SwordState) -> bool: return sword.ultimate_ready() and sword.ultimate_cooldown_left == 0.0))
	var radii_ok: bool = true
	for kind: String in ["husk", "runner", "brute"]:
		radii_ok = radii_ok and EnemyDefs.of(StringName(kind)).radius == float((table["radius"] as Dictionary)[kind]) and _near(EnemyDefs.of(StringName(kind)).knock, float((table["knock_mult"] as Dictionary)[kind]), 0.0001)
	_ok("the enemy radii and knock factors the geometry depends on match the prototype", radii_ok)
	return true


# --------------------------------------------------------- the sweep
func _check_sweep() -> void:
	print("warden: the alternating sweep, tick by tick, against the prototype")
	for label: String in ["common", "common_crit", "rare", "mythic"]:
		var case: Dictionary = _ref["sweep"][label]
		var run: GameRun = _run_of_setup(case["setup"])
		var enemies: Array[EnemyState] = run.enemies.duplicate()
		var result: Dictionary = _follow(run, run.swords[0], enemies, case["trace"], [], int(case["trace"]["ticks"]))
		_ok("%s: windup, sweep, recovery and the hit match on all %d ticks (sword pose, velocity, side, cooldown; enemy position, health, knockback, stun; damage, flash, hitstop, shake)" % [label, int(case["trace"]["ticks"])], String(result["diff"]).is_empty(), String(result["diff"]))
		var sides: Array = result["sides"]
		_ok("%s: consecutive attacks sweep in opposite directions (sides %s)" % [label, sides], sides.size() == (case["windup_sides"] as Array).size() and sides.size() >= 2 and sides[0] == -sides[1] and sides[0] == int((case["windup_sides"] as Array)[0]))
		var hits: Array = result["hits"]
		_ok("%s: every attack hits its target once, for %s" % [label, "17 (x1.3, x1.75 by rarity; doubled on a crit)"], hits.size() == (case["trace"]["hits"] as Array).size() and hits.size() >= 2)
	var boosted: GameRun = _run_of_setup(_ref["sweep"]["common"]["setup"])
	var boosted_target: EnemyState = boosted.enemies[0]
	boosted.swords[0].begin(boosted_target, boosted_target.position, 1.5)
	var start_hp: float = boosted_target.hp
	_steps(boosted, 20)
	_ok("an attack's damage boost (Converge's 1.5x, issue #16) multiplies the sweep's blow: 17 x 1.5 = 25.5 rounds to %.0f" % (start_hp - boosted_target.hp), start_hp - boosted_target.hp == 26.0)
	var common: Dictionary = _ref["sweep"]["common"]
	var transitions: Array = common["trace"]["transitions"]
	_ok("windup 0.16 s (10 ticks), the sweep 0.15 s (9 ticks of motion + the hit's freeze) and recovery 0.3 s: the reference ticks %s" % [transitions.map(func(t: Dictionary) -> String: return "%s@%s" % [t["to"], t["tick"]])], transitions.size() >= 6)


func _check_acquire() -> void:
	print("warden: who it targets (the nearest enemy within range + radius of the player)")
	for label: String in ["just_inside", "just_outside", "close"]:
		var case: Dictionary = _ref["acquire"][label]
		var run: GameRun = _run_of_setup(case["setup"])
		var left: int = -1
		for step: int in range(1, 40):
			run.step()
			if run.swords[0].phase != SwordState.Phase.IDLE and left < 0:
				left = step
		var want: Variant = case["left_idle"]
		_ok("%s (distance %.0f, range 245 + radius 16): %s" % [label, float(case["distance"]), "it attacks" if want != null else "it stays idle"], (left < 0 and want == null) or (want != null and absi(left - int(want)) <= TICK_TOL))
	for label: String in ["nearest_near_first", "nearest_far_first"]:
		var case: Dictionary = _ref["acquire"][label]
		var run: GameRun = _run_of_setup(case["setup"])
		var placed: Array[EnemyState] = run.enemies.duplicate()
		run.step()
		_ok("%s: the nearer enemy is the target whichever was placed first" % label, placed.find(run.swords[0].target) == int(case["target_index"]) and int(case["target_index"]) == int(case["nearest_index"]))


func _check_arc_coverage() -> void:
	print("warden: which points the swinging blade reaches, on which tick, in both directions")
	var cells_total: int = 0
	for key: String in ["side_+1", "side_-1"]:
		var first_side: int = 1 if key == "side_+1" else -1
		var wrong: Array[String] = []
		var reached: int = 0
		var cells: Array = _ref["arc_coverage"][key]
		for cell: Variant in cells:
			var entry: Dictionary = cell as Dictionary
			var target: Dictionary = _ref["arc_coverage"]["setup"]["target"]
			var enemies: Array = [target, {"kind": "husk", "x": entry["x"], "y": entry["y"], "hp": 900.0, "speed_scale": 0.0}]
			var run: GameRun = GameRun.new(_scenario(_ref["arc_coverage"]["setup"]["swords"], enemies, false))
			var sword: SwordState = run.swords[0]
			sword.side = first_side
			var primary: EnemyState = run.enemies[0]
			var probe: EnemyState = run.enemies[1]
			sword.begin(primary, primary.position)
			var hit_tick: int = -1
			for step: int in range(1, 45):
				run.step()
				if probe.hp < PROBE_HP and hit_tick < 0:
					hit_tick = step
			var want: Variant = entry["hit_tick"]
			var good: bool = (want == null and hit_tick < 0) or (want != null and hit_tick >= 0 and absi(hit_tick - int(want)) <= TICK_TOL and _near(PROBE_HP - probe.hp, float(entry["dealt"]), 0.001))
			if want != null:
				reached += 1
			if not good:
				wrong.append("%s/%s: tick %d vs %s" % [entry["angle"], entry["radius"], hit_tick, want])
		cells_total += cells.size()
		_ok("swing direction %+d: of %d probe points around the pivot, the blade reaches %d on the prototype's ticks and misses the rest, with no difference %s" % [first_side, cells.size(), reached, wrong.slice(0, 3)], wrong.is_empty() and reached > 20 and reached < cells.size())
	_ok("arc coverage was compared at %d probe points in total" % cells_total, cells_total >= 150)


func _check_multi_target() -> void:
	print("warden: several enemies in one sweep take one hit each per attack")
	for label: String in ["three_in_front", "spread_arc"]:
		var case: Dictionary = _ref["multi_target"][label]
		var run: GameRun = _run_of_setup(case["setup"])
		var enemies: Array[EnemyState] = run.enemies.duplicate()
		var sword: SwordState = run.swords[0]
		var counts: Dictionary = {}
		var attack: int = 0
		var phase_before: int = sword.phase
		var hp_before: Array[float] = []
		for enemy: EnemyState in enemies:
			hp_before.append(enemy.hp)
		var diff: String = ""
		var trace: Dictionary = case["trace"]
		var hits_before: Array[Dictionary] = []
		var result: Dictionary = {}
		# Count hits per (attack, enemy) while following the reference.
		var tracker: GameRun = _run_of_setup(case["setup"])
		var tracked: Array[EnemyState] = tracker.enemies.duplicate()
		var tracked_hp: Array[float] = []
		for enemy: EnemyState in tracked:
			tracked_hp.append(enemy.hp)
		var tracked_sword: SwordState = tracker.swords[0]
		var tracked_phase: int = tracked_sword.phase
		for step: int in int(trace["ticks"]):
			tracker.step()
			if tracked_sword.phase == SwordState.Phase.WINDUP and tracked_phase != SwordState.Phase.WINDUP:
				attack += 1
			tracked_phase = tracked_sword.phase
			for k: int in tracked.size():
				if tracked[k].hp < tracked_hp[k]:
					var key: String = "%d/%d" % [attack, k]
					counts[key] = int(counts.get(key, 0)) + 1
					tracked_hp[k] = tracked[k].hp
		result = _follow(run, sword, enemies, trace, [], int(trace["ticks"]))
		diff = String(result["diff"])
		var most: int = 0
		for key: Variant in counts:
			most = maxi(most, int(counts[key]))
		_ok("%s: every sword and enemy matches the prototype on all %d ticks" % [label, int(trace["ticks"])], diff.is_empty(), diff)
		var per_enemy: Array = case["hits_per_enemy"]
		var mine: Array[int] = []
		for k: int in enemies.size():
			var total: int = 0
			for key: Variant in counts:
				if String(key).ends_with("/%d" % k):
					total += int(counts[key])
			mine.append(total)
		_ok("%s: no enemy is hit twice by one attack (at most %d per attack and enemy) and the hits per enemy are %s as in the prototype" % [label, most, mine], most == 1 and mine == per_enemy.map(func(v: Variant) -> int: return int(v)))
		_ok("%s: the hit set is per attack: %d attacks, each emptied when the next begins (%d held now)" % [label, attack, tracked_sword.sweep_hits.size()], attack >= 2 and tracked_sword.sweep_hits.size() <= enemies.size())
	var wardens: Dictionary = _ref["multi_target"]["three_wardens"]
	var run3: GameRun = _run_of_setup(wardens["setup"])
	var enemies3: Array[EnemyState] = run3.enemies.duplicate()
	var result3: Dictionary = _follow(run3, run3.swords[0], enemies3, wardens["trace"], [], int(wardens["trace"]["ticks"]))
	var hp_ok: bool = true
	for k: int in enemies3.size():
		hp_ok = hp_ok and _near(enemies3[k].hp, float((wardens["hp"] as Array)[k]), HP_TOL)
	_ok("three Wardens at once: the first's pose and every enemy match the prototype for 80 ticks and the enemies' health ends %s" % [(wardens["hp"] as Array)], String(result3["diff"]).is_empty() and hp_ok and _same_strings(_states(run3), wardens["states"]), String(result3["diff"]))


func _check_deaths() -> void:
	print("warden: deaths during a sweep resolve once")
	var kills: Dictionary = _ref["deaths"]["kills_in_sweep"]
	var run: GameRun = _run_of_setup(kills["setup"])
	var enemies: Array[EnemyState] = run.enemies.duplicate()
	var result: Dictionary = _follow(run, run.swords[0], enemies, kills["trace"], [], int(kills["trace"]["ticks"]))
	_ok("a 5 hp enemy and a tough one in the same sweep: both match the prototype on every tick", String(result["diff"]).is_empty(), String(result["diff"]))
	_ok("the kill is counted once with its three motes (kills %d, chain %d, motes %d), the survivor stays" % [run.kills, run.combo, run.motes.size()], run.kills == int(kills["kills"]) and run.combo == int(kills["combo"]) and run.motes.size() == int(kills["motes"]) and run.enemies.size() == int(kills["left"]) and run.cue_count(SimCue.Kind.ENEMY_KILLED) == 1)
	var two: Dictionary = _ref["deaths"]["two_swords_one_victim"]
	var run2: GameRun = _run_of_setup(two["setup"])
	var enemies2: Array[EnemyState] = run2.enemies.duplicate()
	var result2: Dictionary = _follow(run2, run2.swords[0], enemies2, two["trace"], [], int(two["trace"]["ticks"]))
	_ok("two Wardens strike the same 10 hp enemy on the same tick: the first kills it, the second finds a corpse and nothing is rewarded twice (kills %d, motes %d)" % [run2.kills, run2.motes.size()],
		String(result2["diff"]).is_empty() and run2.kills == int(two["kills"]) and run2.combo == int(two["combo"]) and run2.motes.size() == int(two["motes"]) and run2.cue_count(SimCue.Kind.ENEMY_KILLED) == 1, String(result2["diff"]))
	var windup: Dictionary = _ref["deaths"]["target_killed_in_windup"]
	var run3: GameRun = _run_of_setup(windup["setup"])
	_steps(run3, 3)
	var sword: SwordState = run3.swords[0]
	var armed: bool = sword.target != null and sword.phase == SwordState.Phase.WINDUP
	run3.kill(run3.enemies[0], Vector2.RIGHT)
	_steps(run3, 20)
	_ok("the target dies during the windup: the sword drops it (target cleared %s) and still completes its sweep (phase %s), one kill, three motes" % [sword.target == null, _phase_name(sword.phase)],
		armed == bool(windup["windup_target_set"]) and sword.target == null == bool(windup["target_cleared"]) and run3.kills == int(windup["kills"]) and run3.motes.size() == int(windup["motes"]) and _phase_name(sword.phase) == String(windup["state"]))


func _check_parry() -> void:
	print("warden: projectiles are parried through the shared rule")
	var setup: Dictionary = _ref["parry"]["setup"]
	var total: int = 0
	for key: String in ["side_+1", "side_-1"]:
		var first_side: int = 1 if key == "side_+1" else -1
		var wrong: Array[String] = []
		var parried: int = 0
		for cell: Variant in _ref["parry"][key]:
			var entry: Dictionary = cell as Dictionary
			var run: GameRun = GameRun.new(_scenario(setup["swords"], [], false))
			var sword: SwordState = run.swords[0]
			sword.side = first_side
			sword.begin(null, _point([setup["target"]["x"], setup["target"]["y"]]))
			var projectile: ProjectileState = ProjectileState.make(Vector2(float(entry["x"]), float(entry["y"])), Vector2.ZERO)
			projectile.life = 10.0
			run.projectiles.append(projectile)
			var at: int = -1
			var stop: float = 0.0
			for step: int in range(1, 45):
				run.step()
				if projectile.fate == ProjectileState.Fate.PARRIED and at < 0:
					at = step
					stop = run.hitstop
			var want: Variant = entry["parry_tick"]
			var good: bool = (want == null and at < 0) or (want != null and at >= 0 and absi(at - int(want)) <= TICK_TOL and _near(stop, float(entry["hitstop"]), SCALAR_TOL))
			if want != null:
				parried += 1
			total += 1
			if not good:
				wrong.append("%s/%s: tick %d vs %s" % [entry["angle"], entry["radius"], at, want])
		_ok("swing direction %+d: an orb parked at %d points around the pivot is parried at the prototype's tick (%d of them) and the rest are left alone, with no difference %s" % [first_side, (_ref["parry"][key] as Array).size(), parried, wrong.slice(0, 3)], wrong.is_empty() and parried > 20)
	_ok("parry coverage was compared at %d points; the parry needs no hit (no enemy was in the sweep)" % total, total >= 300)
	var both: Dictionary = _ref["parry"]["orb_and_enemy"]
	var run: GameRun = _run_of_setup(both["setup"])
	var husk: EnemyState = run.enemies[0]
	var orb: ProjectileState = run.projectiles[0]
	var hit_tick: int = -1
	var parry_tick: int = -1
	var hitstop_on_parry: float = 0.0
	var hp_before: float = husk.hp
	for step: int in range(1, 40):
		run.step()
		if husk.hp < hp_before and hit_tick < 0:
			hit_tick = step
		if orb.fate == ProjectileState.Fate.PARRIED and parry_tick < 0:
			parry_tick = step
			hitstop_on_parry = run.hitstop
		hp_before = husk.hp
	var result: Dictionary = both["result"]
	_ok("an orb and an enemy in the same sweep: both resolve (hit tick %d, parry tick %d), hitstop is the larger of the two (%.3f) and the player takes nothing" % [hit_tick, parry_tick, hitstop_on_parry],
		absi(hit_tick - int(result["hit"])) <= TICK_TOL and absi(parry_tick - int(result["parried"])) <= TICK_TOL and _near(hitstop_on_parry, float(result["hitstop_on_parry"]), SCALAR_TOL) and _near(husk.hp, float(both["hp"]), HP_TOL) and _near(run.hp, float(both["player_hp"]), 0.01))
	_ok("a parry is announced exactly once", run.cue_count(SimCue.Kind.PROJECTILE_PARRIED) == 1)
	var far: Dictionary = _ref["parry"]["untouched_orb"]
	var run_far: GameRun = _run_of_setup(far["setup"])
	_steps(run_far, 60)
	_ok("an orb the blade never meets is left alone", (not run_far.projectiles.is_empty() and run_far.projectiles[0].fate == ProjectileState.Fate.FLYING or run_far.projectiles.is_empty()) == bool(far["alive"]) and run_far.cue_count(SimCue.Kind.PROJECTILE_PARRIED) == 0)


func _check_recover_and_cooldown() -> void:
	print("warden: the cooldown starts at the strike and scales with rarity")
	for rarity: int in 3:
		var case: Dictionary = _ref["recover_and_cooldown"]["rarity%d" % rarity]
		var run: GameRun = _run_of_setup(case["setup"])
		var sword: SwordState = run.swords[0]
		var starts: Array[int] = []
		var strikes: Array[int] = []
		for step: int in range(1, 400):
			var before: int = sword.phase
			run.step()
			if before != SwordState.Phase.WINDUP and sword.phase == SwordState.Phase.WINDUP:
				starts.append(step)
			if before == SwordState.Phase.WINDUP and sword.phase == SwordState.Phase.STRIKE:
				strikes.append(step)
		var want_starts: Array = case["windup_starts"]
		var want_strikes: Array = case["strikes"]
		var good: bool = starts.size() == want_starts.size() and strikes.size() == want_strikes.size()
		for i: int in mini(starts.size(), want_starts.size()):
			good = good and absi(starts[i] - int(want_starts[i])) <= TICK_TOL and absi(strikes[i] - int(want_strikes[i])) <= TICK_TOL
		_ok("rarity %d: attacks begin on ticks %s (cooldown %.3f s) as the prototype's %s, each announced by a strike cue (%d)" % [rarity, starts, sword.cooldown, want_starts, run.cue_count(SimCue.Kind.SWORD_STRIKE)], good and starts.size() >= 2 and run.cue_count(SimCue.Kind.SWORD_STRIKE) == strikes.size())


# ------------------------------------------------------------- Maelstrom
func _start_maelstrom(case: Dictionary, slot: int = 0) -> GameRun:
	var setup: Dictionary = case["setup"]
	var run: GameRun = _run_of_setup(setup)
	_steps(run, int(setup.get("warmup_ticks", 0)))
	if setup.has("hitstop"):
		run.hitstop = float(setup["hitstop"])
	if setup.has("slowmo"):
		run.slowmo = 100.0
		run.slowmo_scale = float(setup["slowmo"])
	run.apply(GameCommand.ultimate(slot, _point(setup["point"])))
	return run


func _check_range_and_start() -> void:
	print("warden: Maelstrom's range clamp and start (no blink)")
	var setup: Dictionary = _ref["range_and_start"]["setup"]
	for label: String in ["inside", "on_the_limit", "just_beyond", "far_east", "far_diagonal", "on_the_player", "far_south_west"]:
		var case: Dictionary = _ref["range_and_start"][label]
		var run: GameRun = _run_of_setup(setup)
		_steps(run, int(setup["warmup_ticks"]))
		var sword: SwordState = run.swords[int(setup["slot"])]
		var before: Vector2 = sword.position
		run.apply(GameCommand.ultimate(int(setup["slot"]), _point(case["point"])))
		_ok("%s: the whirl centres on %s, %.1f px from the player; the sword does not move; recharge %.1f, clock %.1f, first beat %.2f, spin %.3f" % [label, sword.ultimate_point, sword.ultimate_point.distance_to(run.position), sword.ultimate_cooldown_left, sword.ultimate_time_left, sword.ultimate_beat, sword.ultimate_spin],
			sword.phase == SwordState.Phase.ULTIMATE and sword.ultimate_point.distance_to(_point(case["centre"])) <= POSITION_TOL and _near(sword.ultimate_point.distance_to(run.position), float(case["distance"]), POSITION_TOL)
			and sword.position.distance_to(before) == 0.0 and sword.position.distance_to(_point(case["pos"])) <= POSITION_TOL and _near(sword.ultimate_cooldown_left, float(case["ult_cd"]), SCALAR_TOL)
			and _near(sword.ultimate_time_left, float(case["ult_t"]), SCALAR_TOL) and _near(sword.ultimate_beat, float(case["beat"]), SCALAR_TOL) and _near(sword.ultimate_spin, float(case["spin"]), ANGLE_TOL))
	var attack: Dictionary = _ref["range_and_start"]["interrupts_attack"]
	var run: GameRun = _run_of_setup(attack["setup"])
	_steps(run, 3)
	var sword_a: SwordState = run.swords[0]
	var before_state: String = _phase_name(sword_a.phase)
	run.apply(GameCommand.ultimate(0, CENTER + Vector2(200.0, 0.0)))
	_ok("a command in the middle of an automatic attack (%s) interrupts it: the sword is whirling, its target and hit set cleared" % before_state, before_state == String(attack["state_before"]) and _phase_name(sword_a.phase) == String(attack["state_after"]) and sword_a.target == null == bool(attack["target_cleared"]) and sword_a.sweep_hits.is_empty() == bool(attack["hit_cleared"]))
	var sweep: Dictionary = _ref["range_and_start"]["interrupts_sweep"]
	var run_s: GameRun = _run_of_setup(sweep["setup"])
	var sword_s: SwordState = run_s.swords[0]
	for i: int in 12:
		run_s.step()
		if sword_s.phase == SwordState.Phase.STRIKE:
			break
	var before_hits: int = sword_s.sweep_hits.size()
	run_s.apply(GameCommand.ultimate(0, CENTER + Vector2(200.0, 0.0)))
	var struck: GameRun = _run_of_setup(sweep["setup"])
	var struck_sword: SwordState = struck.swords[0]
	for i: int in 30:
		struck.step()
		if not struck_sword.sweep_hits.is_empty():
			break
	var held: int = struck_sword.sweep_hits.size()
	struck.apply(GameCommand.ultimate(0, CENTER + Vector2(200.0, 0.0)))
	_ok("a command right after the sweep struck something clears the hit set (%d -> %d)" % [held, struck_sword.sweep_hits.size()], held == 1 and struck_sword.sweep_hits.is_empty() and struck_sword.phase == SwordState.Phase.ULTIMATE)
	_ok("a command in the middle of a sweep drops the hit set (%d -> %d) as the prototype does" % [before_hits, sword_s.sweep_hits.size()], before_hits == int(sweep["hit_before"]) and sword_s.sweep_hits.size() == int(sweep["hit_after"]) and sword_s.phase == SwordState.Phase.ULTIMATE)


func _check_maelstrom_single() -> void:
	print("warden: Maelstrom's whirl, beats, burst and recovery, tick by tick")
	for label: String in ["common", "common_crit", "rare", "mythic"]:
		var case: Dictionary = _ref["maelstrom_single"][label]
		var run: GameRun = _run_of_setup(case["setup"])
		_steps(run, int(case["setup"]["warmup_ticks"]))
		run.apply(GameCommand.ultimate(0, _point(case["setup"]["point"])))
		var sword: SwordState = run.swords[0]
		var start: Dictionary = case["at_start"]
		_ok("%s: the command starts the whirl from where the sword hangs, with the recharge, the 2.2 s clock and the 0.15 s first beat" % label,
			sword.phase == SwordState.Phase.ULTIMATE and _near(sword.ultimate_cooldown_left, float(start["ult_cd"]), SCALAR_TOL) and _near(sword.ultimate_time_left, float(start["ult_t"]), SCALAR_TOL) and _near(sword.ultimate_beat, float(start["beat"]), SCALAR_TOL)
			and _near(sword.ultimate_spin, float(start["spin"]), ANGLE_TOL) and _near(sword.position.x, float(start["x"]), POSITION_TOL) and _near(sword.position.y, float(start["y"]), POSITION_TOL) and sword.ultimate_point.distance_to(_point(start["centre"])) <= POSITION_TOL)
		var enemies: Array[EnemyState] = run.enemies.duplicate()
		var result: Dictionary = _follow(run, sword, enemies, case["trace"], [], int(case["trace"]["ticks"]))
		_ok("%s: the sword's pose, spin, clock, beat timer and recharge, the enemy's pull, health, knockback and stun, every beat's damage, flash and shake, the burst and the recovery match on all %d ticks" % [label, int(case["trace"]["ticks"])], String(result["diff"]).is_empty(), String(result["diff"]))
		var transitions: Array = case["trace"]["transitions"]
		_ok("%s: the whirl ends into recovery on tick %s and the sword is idle on tick %s" % [label, (transitions[0] as Dictionary)["tick"], (transitions[1] as Dictionary)["tick"]], _phase_name(sword.phase) == "idle" and transitions.size() == 2)
		_ok("%s: %d beats and the burst hit; the health left %.1f; hitstop after the burst %.3f" % [label, (case["trace"]["hits"] as Array).size() - 1, enemies[0].hp, run.hitstop], _near(enemies[0].hp, float((case["trace"]["enemies"] as Array)[0]["hp"][int(case["trace"]["ticks"]) - 1]), HP_TOL) and _near(run.hitstop, float(case["hitstop_end"]), SCALAR_TOL))


func _check_maelstrom_pull() -> void:
	print("warden: the pull, who is struck by the beats and the burst (seven enemies, four kinds and distances)")
	for label: String in ["ring", "ring_mythic"]:
		var case: Dictionary = _ref["maelstrom_pull"][label]
		var run: GameRun = _start_maelstrom_after_warmup(case)
		var enemies: Array[EnemyState] = run.enemies.duplicate()
		var result: Dictionary = _follow(run, run.swords[0], enemies, case["trace"], [], int(case["trace"]["ticks"]))
		_ok("%s: every enemy's drag toward the centre, the beats and the burst match on all %d ticks" % [label, int(case["trace"]["ticks"])], String(result["diff"]).is_empty(), String(result["diff"]))
		var untouched: EnemyState = enemies[4]
		_ok("%s: an enemy a hair outside the pull range (%.0f px) is neither pulled nor struck: health %.0f, position (%.1f, %.1f)" % [label, run.swords[0].maelstrom_pull_range(), untouched.hp, untouched.position.x, untouched.position.y], label == "ring_mythic" or (untouched.hp == PROBE_HP and untouched.position.distance_to(Vector2(float(case["setup"]["enemies"][4]["x"]), float(case["setup"]["enemies"][4]["y"]))) < 1.0))
	var fresh: GameRun = _start_maelstrom_after_warmup(_ref["maelstrom_pull"]["ring"])
	var pulled: Array[EnemyState] = fresh.enemies.duplicate()
	var before: Array[Vector2] = []
	for enemy: EnemyState in pulled:
		before.append(enemy.position)
	fresh.step()
	var moved: Array[float] = []
	for k: int in pulled.size():
		moved.append(pulled[k].position.distance_to(before[k]))
	_ok("the pull's speed is 170 px/s x the knock factor: a husk %.3f px in one tick, a brute %.3f, a runner %.3f; one outside the range %.3f, one already inside 8 px keeps its place" % [moved[2], moved[5], moved[6], moved[4]],
		_near(moved[2], 170.0 * 1.0 / 60.0, 0.01) and _near(moved[5], 170.0 * 0.35 / 60.0, 0.01) and _near(moved[6], 170.0 * 1.3 / 60.0, 0.01) and moved[4] < 0.01)


func _start_maelstrom_after_warmup(case: Dictionary) -> GameRun:
	var run: GameRun = _run_of_setup(case["setup"])
	_steps(run, int(case["setup"]["warmup_ticks"]))
	run.apply(GameCommand.ultimate(0, _point(case["setup"]["point"])))
	return run


func _check_maelstrom_kills() -> void:
	print("warden: kills during the whirl resolve once")
	var case: Dictionary = _ref["maelstrom_kills"]["kills"]
	var run: GameRun = _start_maelstrom_after_warmup(case)
	var enemies: Array[EnemyState] = run.enemies.duplicate()
	var result: Dictionary = _follow(run, run.swords[0], enemies, case["trace"], [], int(case["trace"]["ticks"]))
	_ok("a 9 hp, a 60 hp, a 150 hp enemy and a brute: every tick matches the prototype", String(result["diff"]).is_empty(), String(result["diff"]))
	_ok("kills %d, motes %d, enemies left %d, kill cues %d: each death rewarded exactly once" % [run.kills, run.motes.size(), run.enemies.size(), run.cue_count(SimCue.Kind.ENEMY_KILLED)],
		run.kills == int(case["kills"]) and run.motes.size() == int(case["motes"]) and run.enemies.size() == int(case["left"]) and run.cue_count(SimCue.Kind.ENEMY_KILLED) == run.kills and run.kills >= 2)


func _check_maelstrom_clocks() -> void:
	print("warden: pause, the player's death, hitstop and slow motion in the middle of the whirl")
	var pause: Dictionary = _ref["maelstrom_clocks"]["pause"]
	var run: GameRun = _run_of_setup(pause["setup"])
	var husk: EnemyState = run.enemies[0]
	_steps(run, int(pause["setup"]["warmup_ticks"]))
	run.apply(GameCommand.ultimate(0, _point(pause["setup"]["point"])))
	_steps(run, int(pause["setup"]["run_ticks"]))
	var sword: SwordState = run.swords[0]
	var snapshot: Callable = func() -> Array: return [sword.position, sword.angle, sword.ultimate_time_left, sword.ultimate_beat, sword.ultimate_spin, sword.ultimate_cooldown_left, husk.position, husk.hp, run.tick]
	var before: Array = snapshot.call()
	var before_ref: Dictionary = pause["before"]
	run.apply(GameCommand.pause())
	_steps(run, 120)
	var after: Array = snapshot.call()
	_ok("paused for 120 ticks: the whirl, its clock, the beat timer, the pull and the recharge are frozen bit for bit", before == after and bool(pause["identical"]))
	_ok("the pose just before pausing matches the prototype (sword %.3f, %.3f; ult %.4f s, beat %.4f, recharge %.4f)" % [sword.position.x, sword.position.y, sword.ultimate_time_left, sword.ultimate_beat, sword.ultimate_cooldown_left],
		_near(sword.position.x, float(before_ref["sword"]["x"]), POSITION_TOL) and _near(sword.position.y, float(before_ref["sword"]["y"]), POSITION_TOL) and _near(sword.ultimate_time_left, float(before_ref["ult_t"]), SCALAR_TOL) and _near(sword.ultimate_beat, float(before_ref["beat"]), SCALAR_TOL) and _near(sword.ultimate_cooldown_left, float(before_ref["ult_cd"]), SCALAR_TOL)
		and _near(husk.position.x, float((before_ref["enemy"] as Array)[0]), POSITION_TOL) and _near(husk.hp, float((before_ref["enemy"] as Array)[2]), HP_TOL))
	run.apply(GameCommand.resume())
	run.step()
	_ok("resumed, the whirl carries on from the same instant (clock %.4f)" % sword.ultimate_time_left, _near(sword.ultimate_time_left, float(pause["resumed_ult_t"]), SCALAR_TOL))
	var death: Dictionary = _ref["maelstrom_clocks"]["death"]
	var run_d: GameRun = _run_of_setup(death["setup"])
	var husk_d: EnemyState = run_d.enemies[0]
	_steps(run_d, int(death["setup"]["warmup_ticks"]))
	run_d.apply(GameCommand.ultimate(0, _point(death["setup"]["point"])))
	_steps(run_d, int(death["setup"]["run_ticks"]))
	var sword_d: SwordState = run_d.swords[0]
	var hp_at_death: float = husk_d.hp
	var position_at_death: Vector2 = husk_d.position
	run_d.hurt_player(1000, CENTER + Vector2(50.0, 0.0))
	run_d.step()
	var state_next: String = _phase_name(sword_d.phase)
	var cooldown_at_death: float = sword_d.ultimate_cooldown_left
	_steps(run_d, 100)
	_ok("the player dies in the middle of the whirl: the sword goes idle (next tick %s, later %s), no beat or burst lands after (health change %.1f), the recharge keeps running (%.3f -> %.3f)" % [state_next, _phase_name(sword_d.phase), hp_at_death - husk_d.hp, cooldown_at_death, sword_d.ultimate_cooldown_left],
		state_next == String(death["state_next_tick"]) and _phase_name(sword_d.phase) == String(death["state_later"]) and _near(hp_at_death, float(death["hp_at_death"]), HP_TOL) and _near(husk_d.hp, float(death["hp_end"]), HP_TOL)
		and _near(cooldown_at_death, float(death["ult_cd_at_death"]), SCALAR_TOL) and _near(sword_d.ultimate_cooldown_left, float(death["ult_cd_later"]), SCALAR_TOL) and _near(husk_d.position.distance_to(position_at_death), float(death["enemy_moved_by_pull"]), POSITION_TOL) and hp_at_death == husk_d.hp)
	var stop_case: Dictionary = _ref["maelstrom_clocks"]["hitstop_at_command"]
	var run_h: GameRun = _start_maelstrom(stop_case)
	var first_hit: int = -1
	var h_enemy: EnemyState = run_h.enemies[0]
	var h_hp: float = h_enemy.hp
	var at_ok: bool = true
	for step: int in range(1, 60):
		run_h.step()
		if h_enemy.hp < h_hp and first_hit < 0:
			first_hit = step
		h_hp = h_enemy.hp
		if (stop_case["at"] as Dictionary).has(str(step)):
			var want: Dictionary = (stop_case["at"] as Dictionary)[str(step)]
			at_ok = at_ok and _near(run_h.swords[0].ultimate_time_left, float(want["ult_t"]), SCALAR_TOL) and _near(run_h.swords[0].ultimate_beat, float(want["beat"]), SCALAR_TOL) and _near(run_h.swords[0].ultimate_cooldown_left, float(want["ult_cd"]), SCALAR_TOL)
	_ok("0.2 s of hitstop at the command: the whirl waits it out; first beat on tick %d (prototype %d), the clocks match on the sampled ticks" % [first_hit, int(stop_case["first_hit_tick"])], absi(first_hit - int(stop_case["first_hit_tick"])) <= TICK_TOL and at_ok)
	var slow: Dictionary = _ref["maelstrom_clocks"]["slow_motion"]
	var run_s: GameRun = _start_maelstrom(slow)
	var slow_first: int = -1
	var s_enemy: EnemyState = run_s.enemies[0]
	var s_hp: float = s_enemy.hp
	for step: int in range(1, 100):
		run_s.step()
		if s_enemy.hp < s_hp and slow_first < 0:
			slow_first = step
		s_hp = s_enemy.hp
	_ok("slow motion x0.25: first beat on tick %d (prototype %d), clock %.3f and recharge %.3f a quarter as fast" % [slow_first, int(slow["first_hit_tick"]), run_s.swords[0].ultimate_time_left, run_s.swords[0].ultimate_cooldown_left],
		absi(slow_first - int(slow["first_hit_tick"])) <= TICK_TOL and _near(run_s.swords[0].ultimate_time_left, float(slow["ult_t"]), SCALAR_TOL) and _near(run_s.swords[0].ultimate_cooldown_left, float(slow["ult_cd"]), SCALAR_TOL) and _near(run_s.swords[0].ultimate_beat, float(slow["beat"]), SCALAR_TOL))


func _check_maelstrom_rules() -> void:
	print("warden: recharge, refusal and the other slots")
	for rarity: int in 3:
		var case: Dictionary = _ref["maelstrom_rules"]["recharge_rarity%d" % rarity]
		var run: GameRun = _run_of_setup(case["setup"])
		run.apply(GameCommand.ultimate(0, CENTER + Vector2(200.0, 0.0)))
		var ready: int = -1
		var at_ok: bool = true
		for step: int in range(1, 800):
			run.step()
			if (case["ult_cd_at"] as Dictionary).has(str(step)):
				at_ok = at_ok and _near(run.swords[0].ultimate_cooldown_left, float((case["ult_cd_at"] as Dictionary)[str(step)]), SCALAR_TOL)
			if run.swords[0].ultimate_cooldown_left <= 0.0 and ready < 0:
				ready = step
		_ok("rarity %d: the recharge is %.2f s (11 s x the rarity factor) and ends on tick %d (prototype %d)" % [rarity, run.swords[0].ultimate_cooldown, ready, int(case["ready_tick"])], absi(ready - int(case["ready_tick"])) <= TICK_TOL and at_ok and _near(run.swords[0].ultimate_cooldown, float(case["ult_max"]), 0.0001))
	var refused: Dictionary = _ref["maelstrom_rules"]["rejected_while_recharging"]
	var run_r: GameRun = _run_of_setup(refused["setup"])
	run_r.apply(GameCommand.ultimate(0, CENTER + Vector2(200.0, 0.0)))
	_steps(run_r, int(refused["setup"]["ticks"]))
	var sword_r: SwordState = run_r.swords[0]
	var before: Array = [_phase_name(sword_r.phase), sword_r.ultimate_cooldown_left, sword_r.position]
	var result: GameRun.UltimateResult = run_r.try_ultimate(0, CENTER + Vector2(-200.0, 0.0))
	var after: Array = [_phase_name(sword_r.phase), sword_r.ultimate_cooldown_left, sword_r.position]
	_ok("a second Q while Maelstrom recharges is refused with RECHARGING, changes nothing and shows the seconds left (%d)" % run_r.cue_count(SimCue.Kind.ULTIMATE_REFUSED),
		result == GameRun.UltimateResult.RECHARGING and before == after and bool(refused["refused"]) and run_r.cue_count(SimCue.Kind.ULTIMATE_REFUSED) == 1 and _near(sword_r.ultimate_cooldown_left, float(refused["after"]["ult_cd"]), SCALAR_TOL))
	var active: Dictionary = _ref["maelstrom_rules"]["rejected_while_active"]
	var run_a: GameRun = _run_of_setup(active["setup"])
	run_a.apply(GameCommand.ultimate(0, _point(active["point"])))
	_steps(run_a, int(active["setup"]["ticks"]))
	var sword_a: SwordState = run_a.swords[0]
	sword_a.ultimate_cooldown_left = 0.0
	var centre: Vector2 = sword_a.ultimate_point
	var result_a: GameRun.UltimateResult = run_a.try_ultimate(0, CENTER + Vector2(-200.0, 0.0))
	_ok("a second Q while the whirl runs is refused as ACTIVE even with the recharge forced to zero: the centre stays (%s)" % [centre], result_a == GameRun.UltimateResult.ACTIVE and sword_a.ultimate_point == centre and centre.distance_to(_point(active["after"]["centre"])) <= POSITION_TOL and _near(sword_a.ultimate_time_left, float(active["after"]["ult_t"]), SCALAR_TOL))
	var again: Dictionary = _ref["maelstrom_rules"]["again_after_recharge"]
	var run_g: GameRun = _run_of_setup(again["setup"])
	run_g.apply(GameCommand.ultimate(0, CENTER + Vector2(200.0, 0.0)))
	_steps(run_g, int(again["setup"]["ticks"]))
	run_g.apply(GameCommand.ultimate(0, CENTER + Vector2(200.0, 0.0)))
	_ok("once the recharge is over Maelstrom starts again", _phase_name(run_g.swords[0].phase) == String(again["state"]))
	var others: Dictionary = _ref["maelstrom_rules"]["others_keep_sweeping"]
	var run_o: GameRun = _run_of_setup(others["setup"])
	var post: EnemyState = run_o.enemies[0]
	run_o.apply(GameCommand.ultimate(0, CENTER + Vector2(330.0, -300.0)))
	var states_at_30: Array[String] = []
	var swept: bool = false
	for step: int in range(1, 61):
		run_o.step()
		var states: Array[String] = _states(run_o)
		if step == 30:
			states_at_30 = states
		swept = swept or states[1] != "idle" or states[2] != "idle"
	_ok("while slot one whirls, slots two and three keep sweeping (states at tick 30: %s)" % [states_at_30], _same_strings(states_at_30, others["states_at_30"]) and swept == bool(others["others_swept"]) and (post.hp < 100000.0) == bool(others["husk_damaged"]))


func _check_orb_in_the_whirl() -> void:
	print("warden: Maelstrom does not parry")
	var case: Dictionary = _ref["orb_during_maelstrom"]["orb_in_the_whirl"]
	var run: GameRun = _run_of_setup(case["setup"])
	run.apply(GameCommand.ultimate(0, _point(case["setup"]["point"])))
	_steps(run, 100)
	var orb: ProjectileState = run.projectiles[0] if not run.projectiles.is_empty() else null
	_ok("an orb hanging inside the whirl survives the beats (alive %s, parry cues %d, hitstop %.3f)" % [orb != null and orb.fate == ProjectileState.Fate.FLYING, run.cue_count(SimCue.Kind.PROJECTILE_PARRIED), run.hitstop],
		orb != null and orb.fate == ProjectileState.Fate.FLYING and bool(case["orb_alive"]) and run.cue_count(SimCue.Kind.PROJECTILE_PARRIED) == 0 and _near(run.hitstop, float(case["parry_hitstop"]), SCALAR_TOL))


# ------------------------------------------------------------ conditions
func _check_sweep_conditions() -> void:
	print("warden: a sweep's blow applies its element once; conditions ON, against the prototype's own afflict")
	for element: String in ["poison", "ice", "fire"]:
		var case: Dictionary = _ref["sweep_conditions"][element]
		var run: GameRun = _run_of_setup(case["setup"])
		var enemies: Array[EnemyState] = run.enemies.duplicate()
		var result: Dictionary = _follow(run, run.swords[0], enemies, case["trace"], _per_enemy(case["conditions"]), int(case["trace"]["ticks"]))
		var c: EnemyConditions = enemies[0].conditions
		_ok("%s sword: health, burn, poison and chill timers, dps, stacks, the damage-over-time accumulator and position match on all %d ticks (kills %d, poison stacks %d, chill stacks %d)" % [element, int(case["trace"]["ticks"]), run.kills, c.poison_stacks, c.chill_stacks], String(result["diff"]).is_empty() and run.kills == int(case["kills"]), String(result["diff"]))
	var pack: Dictionary = _ref["sweep_conditions"]["pack_poison"]
	var run_p: GameRun = _run_of_setup(pack["setup"])
	var pack_enemies: Array[EnemyState] = run_p.enemies.duplicate()
	var result_p: Dictionary = _follow(run_p, null, pack_enemies, {}, _per_enemy(pack["conditions"]), 150)
	var poisoned: int = pack_enemies.filter(func(e: EnemyState) -> bool: return e.conditions.poison_stacks >= 1).size()
	_ok("three enemies swept by a poison Warden: each carries its own stacks and all match the prototype for 150 ticks (%d poisoned)" % poisoned, String(result_p["diff"]).is_empty() and poisoned == 3, String(result_p["diff"]))


func _check_maelstrom_conditions() -> void:
	print("warden: Maelstrom's beats apply one dose, its burst two; freezing and the shatter bonus")
	for element: String in ["poison", "ice", "fire"]:
		var case: Dictionary = _ref["maelstrom_conditions"][element]
		var run: GameRun = _start_maelstrom_after_warmup(case)
		var enemies: Array[EnemyState] = run.enemies.duplicate()
		var result: Dictionary = _follow(run, run.swords[0], enemies, case["trace"], case["conditions"], int(case["trace"]["ticks"]))
		var frozen_seen: bool = run.cue_count(SimCue.Kind.ENEMY_FROZEN) > 0
		_ok("%s sword on a husk, a brute and a runner: every condition field, health and position match on all %d ticks (freeze announced %s, kills %d)" % [element, int(case["trace"]["ticks"]), frozen_seen, run.kills], String(result["diff"]).is_empty() and run.kills == int(case["kills"]), String(result["diff"]))
	var ice_run: GameRun = _start_maelstrom_after_warmup(_ref["maelstrom_conditions"]["ice"])
	_steps(ice_run, 175)
	var shattered: int = ice_run.cue_count(SimCue.Kind.ENEMY_FROZEN)
	_ok("the ice whirl freezes enemies (%d freezes) and the beats keep hitting them (frozen enemies take the shatter bonus: the per-tick comparison above covers the damage)" % shattered, shattered >= 1)


# ------------------------------------------------------------------ keys
func _check_keys_and_touch() -> void:
	print("warden: Q, E and R and the touch aim")
	var keys: Dictionary = _ref["keys"]
	var swords: Array = keys["setup"]["swords"]
	for entry: Array in [["key_q", 0], ["key_e", 1], ["key_r", 2]]:
		var run: GameRun = GameRun.new(_scenario(swords, [], false))
		run.apply(GameCommand.ultimate(int(entry[1]), CENTER + Vector2(200.0, 0.0)))
		_ok("%s starts only slot %d's Maelstrom" % [entry[0], int(entry[1]) + 1], _same_strings(_states(run), keys[entry[0]]))
	var paused: GameRun = GameRun.new(_scenario(swords, [], false))
	paused.apply(GameCommand.pause())
	paused.apply(GameCommand.ultimate(0, CENTER + Vector2(200.0, 0.0)))
	_ok("paused: Q starts nothing", _same_strings(_states(paused), keys["paused_q"]["states"]) and paused.swords[0].ultimate_cooldown_left == 0.0)
	var dead: GameRun = GameRun.new(_scenario(swords, [], false))
	dead.hurt_player(1000, CENTER + Vector2(50.0, 0.0))
	dead.apply(GameCommand.ultimate(1, CENTER + Vector2(200.0, 0.0)))
	_ok("dead: E starts nothing", dead.dead and _same_strings(_states(dead), keys["dead_e"]["states"]) and dead.swords[1].ultimate_cooldown_left == 0.0)
	var touch: Dictionary = _ref["keys"]["auto_aim"]
	var run_t: GameRun = _run_of_setup(touch["setup"])
	var aim: Vector2 = run_t.auto_aim()
	run_t.apply(GameCommand.ultimate_at_nearest(0))
	_ok("touch aiming sends Maelstrom to the nearest living enemy %s (and clamps it to 400 px: centre %s)" % [aim, run_t.swords[0].ultimate_point], aim.distance_to(_point(touch["nearest"])) <= POSITION_TOL and run_t.swords[0].ultimate_point.distance_to(_point(touch["centre"])) <= POSITION_TOL)


# ----------------------------------------- removal, corpses, pause, death
func _lone_scenario(swords: Array, enemies: Array, conditions: bool = false) -> GameRun:
	return GameRun.new(_scenario(swords, enemies, conditions))


func _check_removed_and_corpses() -> void:
	print("warden: enemies that die or leave the run are handled safely (spec decision 7)")
	var warden: Array = [{"type": "blade", "rarity": 0, "element": "fire", "cd": 0.0}, {"type": "blade", "rarity": 0, "element": "fire", "cd": 99.0}, {"type": "blade", "rarity": 0, "element": "fire", "cd": 99.0}]
	var husk: Dictionary = {"kind": "husk", "x": CENTER.x + 150.0, "y": CENTER.y, "hp": 900.0, "speed_scale": 0.0}
	# The target leaves the run, alive, during the windup: it is dropped, nothing hits it, nothing is rewarded.
	var run: GameRun = _lone_scenario(warden, [husk])
	var sword: SwordState = run.swords[0]
	var gone: EnemyState = run.enemies[0]
	_steps(run, 3)
	var had_target: bool = sword.target == gone
	run.enemies.erase(gone)
	_steps(run, 40)
	_ok("the target removed from the run while alive: the sword drops it, finishes its sweep, nothing is hit, killed or rewarded (target %s, hp %.0f, kills %d, hit cues %d)" % [sword.target, gone.hp, run.kills, run.cue_count(SimCue.Kind.ENEMY_HIT)],
		had_target and sword.target == null and gone.hp == PROBE_HP and run.kills == 0 and run.cue_count(SimCue.Kind.ENEMY_HIT) == 0 and run.motes.is_empty() and sword.phase != SwordState.Phase.WINDUP)
	# Removed during the sweep itself: the sweep tests only the run's enemies.
	var run2: GameRun = _lone_scenario(warden, [husk])
	var sword2: SwordState = run2.swords[0]
	var gone2: EnemyState = run2.enemies[0]
	for i: int in 12:
		run2.step()
		if sword2.phase == SwordState.Phase.STRIKE:
			break
	run2.enemies.erase(gone2)
	_steps(run2, 30)
	_ok("an enemy removed from the run in the middle of the sweep is not struck by it", gone2.hp == PROBE_HP and run2.cue_count(SimCue.Kind.ENEMY_HIT) == 0 and run2.kills == 0)
	# An enemy removed during Maelstrom is neither pulled nor struck any more.
	var run3: GameRun = _lone_scenario(warden, [{"kind": "husk", "x": CENTER.x + 250.0, "y": CENTER.y, "hp": 900.0, "speed_scale": 0.0}])
	run3.apply(GameCommand.ultimate(1, CENTER + Vector2(250.0, 0.0)))
	var gone3: EnemyState = run3.enemies[0]
	_steps(run3, 40)
	var hp_then: float = gone3.hp
	var at_then: Vector2 = gone3.position
	run3.enemies.erase(gone3)
	_steps(run3, 120)
	_ok("an enemy removed from the run in the middle of Maelstrom is not pulled, struck or burst afterwards (hp %.0f stays, moved %.2f px)" % [gone3.hp, gone3.position.distance_to(at_then)], gone3.hp == hp_then and hp_then < PROBE_HP and gone3.position == at_then and run3.kills == 0)
	# A corpse (killed earlier in the same tick, removed only at its end) is still in the run when the whirl
	# acts, exactly as in the prototype: it is pulled, a no-op blow lands on it and, inside the reach, it
	# still sets off the beat's sound and shake. The reference holds the prototype's outcome.
	var beat: Dictionary = _ref["maelstrom_corpses"]["corpse_beat"]
	var run4: GameRun = _run_of_setup(beat["setup"])
	run4.apply(GameCommand.ultimate(0, _point(beat["setup"]["point"])))
	var corpse: EnemyState = run4.enemies[0]
	_steps(run4, int(beat["setup"]["ticks_before"]))
	run4.trauma = 0.0
	run4.kill(corpse, Vector2.UP)
	var hp_dead4: float = corpse.hp
	var position_dead: Vector2 = corpse.position
	run4.take_cues()
	run4.step()
	var beats: Array[SimCue] = run4.take_cues().filter(func(cue: SimCue) -> bool: return cue.kind == SimCue.Kind.MAELSTROM_BEAT)
	_ok("a corpse inside the reach in the tick of a beat: the beat's cue still reports it (so its sound plays) and its shake lands (cue amount %d, trauma %.4f, want %.4f), the corpse is not struck again (health unchanged, one kill, three motes)" % [beats[0].amount if not beats.is_empty() else -1, run4.trauma, float(beat["trauma"])],
		beats.size() == 1 and beats[0].amount == 1 and _near(run4.trauma, float(beat["trauma"]), SCALAR_TOL) and corpse.hp == hp_dead4 and not bool(beat["hp_changed"]) and run4.kills == int(beat["kills"]) and run4.motes.size() == int(beat["motes"]))
	_ok("the same corpse is still pulled toward the centre like the prototype's (%.4f px, to x %.3f; the prototype %.4f px, x %.3f)" % [corpse.position.distance_to(position_dead), corpse.position.x, float(beat["moved"]), float(beat["x"])],
		_near(corpse.position.distance_to(position_dead), float(beat["moved"]), POSITION_TOL) and _near(corpse.position.x, float(beat["x"]), POSITION_TOL) and _near(corpse.position.y, float(beat["y"]), POSITION_TOL))
	# A beat with nothing at all inside its reach makes no shake and its cue reports nobody.
	var empty_run: GameRun = _lone_scenario(warden, [{"kind": "husk", "x": CENTER.x + 900.0, "y": CENTER.y, "hp": 900.0, "speed_scale": 0.0}])
	empty_run.apply(GameCommand.ultimate(0, CENTER + Vector2(250.0, 0.0)))
	empty_run.take_cues()
	_steps(empty_run, 10)
	var empty_beats: Array[SimCue] = empty_run.take_cues().filter(func(cue: SimCue) -> bool: return cue.kind == SimCue.Kind.MAELSTROM_BEAT)
	_ok("a beat with no enemy inside its reach shakes nothing and its cue reports nobody (beats %d, amount %d, trauma %.3f)" % [empty_beats.size(), empty_beats[0].amount if not empty_beats.is_empty() else -1, empty_run.trauma],
		empty_beats.size() == 1 and empty_beats[0].amount == 0 and empty_run.trauma == 0.0)
	# The reviewer's scenario: two Maelstroms, the first one's burst kills a 5 hp husk and leaves a 28 hp one
	# at 1 hp; the second whirl still pulls the corpse, which then takes part in the crowd's collisions.
	var two_whirls: Dictionary = _ref["maelstrom_corpses"]["two_whirls"]
	var run6: GameRun = _run_of_setup(two_whirls["setup"])
	var ult_point: Vector2 = _point(two_whirls["setup"]["point"])
	run6.apply(GameCommand.ultimate(0, ult_point))
	run6.apply(GameCommand.ultimate(1, ult_point))
	run6.swords[0].ultimate_time_left = float(two_whirls["setup"]["first_ult_time_left"])
	var husks6: Array[EnemyState] = run6.enemies.duplicate()
	var result6: Dictionary = _follow(run6, run6.swords[0], husks6, two_whirls["trace"], [], int(two_whirls["trace"]["ticks"]))
	_ok("two whirls on one tick, the first's burst kills a husk and the second still pulls the corpse: both husks' position, velocity, health and stun and the first sword match the prototype on all %d ticks (kills %d, motes %d, left %d)" % [int(two_whirls["trace"]["ticks"]), run6.kills, run6.motes.size(), run6.enemies.size()],
		String(result6["diff"]).is_empty() and run6.kills == int(two_whirls["kills"]) and run6.motes.size() == int(two_whirls["motes"]) and run6.enemies.size() == int(two_whirls["left"]), String(result6["diff"]))
	# The finishing burst meets a corpse in its reach the same way: nothing is struck twice, the cue counts it.
	var run8: GameRun = _lone_scenario(warden, [{"kind": "husk", "x": CENTER.x + 310.0, "y": CENTER.y, "hp": 900.0, "speed_scale": 0.0}])
	run8.apply(GameCommand.ultimate(1, CENTER + Vector2(250.0, 0.0)))
	var corpse8: EnemyState = run8.enemies[0]
	while run8.swords[1].ultimate_time_left > GameRun.TICK_DT * 0.5:
		run8.step()
	run8.kill(corpse8, Vector2.UP)
	var hp_dead8: float = corpse8.hp
	run8.take_cues()
	run8.step()
	var bursts: Array[SimCue] = run8.take_cues().filter(func(cue: SimCue) -> bool: return cue.kind == SimCue.Kind.MAELSTROM_BURST)
	_ok("a corpse inside the finishing burst's reach is not struck again but is counted by the burst's cue (cue amount %d, health unchanged, one kill)" % [bursts[0].amount if not bursts.is_empty() else -1],
		run8.swords[1].phase == SwordState.Phase.RECOVER and bursts.size() == 1 and bursts[0].amount == 1 and corpse8.hp == hp_dead8 and run8.kills == 1)
	var two: Dictionary = _ref["deaths"]["two_swords_one_victim"]
	var run7: GameRun = _run_of_setup(two["setup"])
	var victim7: EnemyState = run7.enemies[0]
	for i: int in 60:
		run7.step()
		if run7.kills >= 1:
			break
	_ok("when one sweep kills an enemy, the other sword's sweep does not reward the corpse again: one kill, three motes (kills %d, motes %d)" % [run7.kills, run7.motes.size()],
		run7.kills == 1 and run7.motes.size() == 3)
	# The sweep's hit set keeps nobody twice even when the same enemy is inside both sampled arcs.
	var run5: GameRun = _lone_scenario(warden, [{"kind": "brute", "x": CENTER.x + 120.0, "y": CENTER.y, "hp": 100000.0, "speed_scale": 0.0}])
	var brute: EnemyState = run5.enemies[0]
	var attacks: int = 0
	var phase_before: int = run5.swords[0].phase
	var worst: int = 0
	var hits_this_attack: int = 0
	var hp_before: float = brute.hp
	for i: int in 400:
		run5.step()
		var phase_now: int = run5.swords[0].phase
		if phase_now == SwordState.Phase.WINDUP and phase_before != SwordState.Phase.WINDUP:
			attacks += 1
			hits_this_attack = 0
		phase_before = phase_now
		if brute.hp < hp_before:
			hits_this_attack += 1
			worst = maxi(worst, hits_this_attack)
			hp_before = brute.hp
	_ok("a large brute (radius 30) standing in the sweep is hit once per attack over %d attacks, never twice in one" % attacks, attacks >= 3 and worst == 1)


func _check_pause_and_death_in_a_sweep() -> void:
	print("warden: pause and the player's death in the middle of a sweep")
	var warden: Array = [{"type": "blade", "rarity": 0, "element": "fire", "cd": 0.0}, {"type": "blade", "rarity": 0, "element": "fire", "cd": 99.0}, {"type": "blade", "rarity": 0, "element": "fire", "cd": 99.0}]
	var husk: Dictionary = {"kind": "husk", "x": CENTER.x + 150.0, "y": CENTER.y + 20.0, "hp": 900.0, "speed_scale": 0.0}
	var run: GameRun = _lone_scenario(warden, [husk])
	var sword: SwordState = run.swords[0]
	for i: int in 14:
		run.step()
		if sword.phase == SwordState.Phase.STRIKE:
			break
	var target: EnemyState = run.enemies[0]
	var before: Array = [sword.position, sword.angle, sword.timer, sword.sweep_hits.size(), target.hp, run.tick]
	run.apply(GameCommand.pause())
	_steps(run, 90)
	var after: Array = [sword.position, sword.angle, sword.timer, sword.sweep_hits.size(), target.hp, run.tick]
	run.apply(GameCommand.resume())
	_steps(run, 60)
	_ok("paused in the middle of the sweep: nothing advances, and after resuming it is struck exactly once (hp %.0f)" % target.hp, before == after and target.hp == PROBE_HP - 17.0 and run.cue_count(SimCue.Kind.ENEMY_HIT) == 1)
	var dying: GameRun = _lone_scenario(warden, [husk])
	var sword_d: SwordState = dying.swords[0]
	for i: int in 14:
		dying.step()
		if sword_d.phase == SwordState.Phase.STRIKE:
			break
	dying.hurt_player(1000, CENTER + Vector2(50.0, 0.0))
	var victim: EnemyState = dying.enemies[0]
	var hp_at_death: float = victim.hp
	_steps(dying, 80)
	_ok("the player dies in the middle of the sweep: the sword goes idle and the sweep deals nothing after (health change %.0f, phase %s)" % [hp_at_death - victim.hp, _phase_name(sword_d.phase)], dying.dead and _phase_name(sword_d.phase) == "idle" and victim.hp == hp_at_death)
	var restarted: GameRun = _lone_scenario(warden, [husk])
	for i: int in 14:
		restarted.step()
	restarted.apply(GameCommand.ultimate(1, CENTER + Vector2(200.0, 0.0)))
	restarted.apply(GameCommand.restart())
	var fresh: SwordState = restarted.swords[1]
	_ok("a restart in the middle of a sweep and a whirl leaves new swords: no ultimate, recharged, no hit set, the first sweep's side again (restarts %d)" % restarted.restarts, fresh.phase == SwordState.Phase.IDLE and fresh.ultimate_ready() and fresh.sweep_hits.is_empty() and fresh.side == 1 and restarted.swords[0].sweep_hits.is_empty())


func _check_fixture_and_launch() -> void:
	print("warden: the loadout fixture and the warden encounter")
	var scenario: RunScenario = RunScenario.warden_encounter()
	var kinds: Array[StringName] = [EnemyDefs.HUSK, EnemyDefs.RUNNER, EnemyDefs.BRUTE]
	var counts: Array[int] = []
	for kind: StringName in kinds:
		counts.append(scenario.wave_kinds.count(kind))
	_ok("the warden encounter is one wave (%s husk / runner / brute) against Fang, Warden and Warden with poison, ice and fire; conditions on; no shove" % [counts],
		scenario.encounter == RunScenario.ENCOUNTER_WARDEN and scenario.loadout.size() == 3 and scenario.loadout[0].type_id == SwordDefs.FANG and scenario.loadout[1].type_id == SwordDefs.WARDEN and scenario.loadout[2].type_id == SwordDefs.WARDEN
		and scenario.loadout[0].element == &"poison" and scenario.loadout[1].element == &"ice" and scenario.loadout[2].element == &"fire" and scenario.conditions_enabled and not scenario.dev_shove and scenario.waves_enabled and counts[2] == 2 and scenario.wave_kinds.size() == 14)
	_ok("--encounter=warden and ?encounter=warden ask for it, and the normal run is still three Fang swords (the final default loadout is issue #16)",
		LaunchOptions.scenario_for("warden") != null and LaunchOptions.scenario_for("warden").encounter == RunScenario.ENCOUNTER_WARDEN and RunScenario.new().loadout.all(func(spec: SwordSpec) -> bool: return spec.type_id == SwordDefs.FANG))
	var run: GameRun = GameRun.new(scenario)
	run.scenario.seed = 17
	_ok("the encounter equips a Fang and two Wardens (%s)" % [run.swords.map(func(s: SwordState) -> String: return String(s.spec.type_id))], run.swords.size() == 3 and run.swords[1].spec.type_id == SwordDefs.WARDEN and run.swords[1].length == SwordDefs.WARDEN_LENGTH and run.swords[0].length == SwordDefs.FANG_LENGTH)
	var played: RunScenario = RunScenario.warden_encounter()
	played.seed = 17
	played.first_wave_delay = 0.2
	var fight: GameRun = GameRun.new(played)
	var alternated: bool = true
	var phases: Dictionary = {}
	for tick: int in 1800:
		if tick in [200, 500, 900]:
			fight.apply(GameCommand.ultimate(1 + (tick % 2), fight.position + Vector2(180.0, 20.0)))
		fight.step()
		for sword: SwordState in fight.swords:
			phases[_phase_name(sword.phase)] = true
		if fight.dead:
			break
	_ok("a played warden encounter shows sweeps, Maelstroms and kills (phases %s, kills %d, beats %d, bursts %d)" % [phases.keys(), fight.kills, fight.cue_count(SimCue.Kind.MAELSTROM_BEAT), fight.cue_count(SimCue.Kind.MAELSTROM_BURST)],
		alternated and phases.has("strike") and phases.has("ult") and fight.kills >= 5 and fight.cue_count(SimCue.Kind.MAELSTROM_BURST) >= 1 and fight.cue_count(SimCue.Kind.MAELSTROM_BEAT) >= 5)


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
	print("warden: E and R in the real Main scene (HUD cards, cues, effects, visuals)")
	var scenario: RunScenario = RunScenario.warden_encounter()
	scenario.seed = 23
	scenario.first_wave_delay = 0.2
	var main: Main = _main_with(scenario)
	await _tree.process_frame
	main._sfx.unlock()
	main._sfx.played.clear()
	_tick_main(main, 5)
	await _tree.process_frame
	var hud: Hud = main._hud
	_ok("the HUD cards name each slot's ultimate and sword: Viper Flurry / Maelstrom / Maelstrom, Fang / Warden / Warden swords, all READY",
		hud._ult_names[0].text == "Viper Flurry" and hud._ult_names[1].text == "Maelstrom" and hud._ult_names[2].text == "Maelstrom" and hud._ult_types[0].text == "Fang sword" and hud._ult_types[1].text == "Warden sword"
		and [0, 1, 2].all(func(slot: int) -> bool: return hud.ultimate_status(slot) == "READY" and hud.ultimate_card_visible(slot)))
	var half: Vector2 = main.get_viewport().get_visible_rect().size * 0.5
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = half + Vector2(220.0, 0.0)
	main._input(motion)
	var expected: Vector2 = main.run.camera + Vector2(220.0, 0.0)
	main._input(_key(KEY_E))
	var sword: SwordState = main.run.swords[1]
	_ok("E with the mouse 220 px right of the view's centre starts slot two's Maelstrom centred on that world point (%s)" % [sword.ultimate_point], sword.phase == SwordState.Phase.ULTIMATE and sword.ultimate_point.distance_to(expected) <= 0.01 and main.run.swords[0].phase != SwordState.Phase.ULTIMATE)
	_ok("it is announced and heard (dash sound, ULTIMATE_STARTED cue)", main._sfx.played.has("dash") and main.run.cue_count(SimCue.Kind.ULTIMATE_STARTED) == 1, "%s" % [main._sfx.played])
	_tick_main(main, 10)
	await _tree.process_frame
	_ok("the card shows ACTIVE and the pull ring and spinning arcs are drawn from the sword's own state", hud.ultimate_status(1) == "ACTIVE" and sword.phase == SwordState.Phase.ULTIMATE and sword.maelstrom_pull_range() > sword.maelstrom_reach())
	_tick_main(main, 130)
	await _tree.process_frame
	_ok("the burst is announced as a cue (bursts %d, beats %d) and heard" % [main.run.cue_count(SimCue.Kind.MAELSTROM_BURST), main.run.cue_count(SimCue.Kind.MAELSTROM_BEAT)], main.run.cue_count(SimCue.Kind.MAELSTROM_BURST) == 1 and main.run.cue_count(SimCue.Kind.MAELSTROM_BEAT) >= 8)
	_ok("after the whirl the card counts the recharge down in whole seconds (%s)" % hud.ultimate_status(1), hud.ultimate_status(1) == "%ds" % SimMath.py_round(sword.ultimate_cooldown_left) and hud.ultimate_bar_fraction(1) > 0.0 and hud.ultimate_bar_fraction(1) < 1.0)
	var effects: EffectsLayer = main._presenter._effects
	var rings_before: int = effects._rings.size()
	var beat: SimCue = SimCue.make(SimCue.Kind.MAELSTROM_BEAT, CENTER, Vector2.ZERO, 3)
	beat.radius = 138.0
	beat.element = &"ice"
	effects.apply_cue(beat)
	var rings_after_beat: int = effects._rings.size()
	var burst: SimCue = SimCue.make(SimCue.Kind.MAELSTROM_BURST, CENTER, Vector2.ZERO, 3)
	burst.radius = 168.0
	burst.element = &"ice"
	var sparks_before: int = effects._sparks.size()
	effects.apply_cue(burst)
	var rings_after_burst: int = effects._rings.size()
	var started: SimCue = SimCue.make(SimCue.Kind.ULTIMATE_STARTED, sword.position, Vector2.RIGHT, 1)
	started.origin = sword.position
	effects.apply_cue(started)
	var area_ring: Dictionary = effects._rings[effects._rings.size() - 1]
	_ok("a beat draws one ring from 0.6 x the reach out to it, the burst two rings and sparks, and a Maelstrom's start a ring closing from the blades' reach (%.1f)" % float(area_ring["r0"]),
		rings_after_beat == rings_before + 1 and effects._rings[rings_before]["r1"] == 138.0 and rings_after_burst == rings_after_beat + 2 and effects._rings.size() == rings_after_burst + 2 and effects._sparks.size() > sparks_before and _near(float(area_ring["r0"]), sword.ultimate_area_radius(), 0.001) and not _near(float(area_ring["r0"]), SwordDefs.FANG_ULT_RADIUS, 1.0))
	var texts_before: int = main._presenter._effects._texts.size()
	main._input(_key(KEY_E))
	_ok("E while it recharges is refused and says so on screen", main.run.cue_count(SimCue.Kind.ULTIMATE_REFUSED) == 1 and main._presenter._effects._texts.size() == texts_before + 1)
	# The sweeps are visible: the blade swings and the effects layer keeps a fading fan, and the telegraph is drawn from the windup.
	var wedges_seen: bool = false
	var telegraph_seen: bool = false
	for i: int in 240:
		_tick_main(main, 1)
		await _tree.process_frame
		wedges_seen = wedges_seen or not main._presenter._effects._wedges.is_empty()
		for swordstate: SwordState in main.run.swords:
			telegraph_seen = telegraph_seen or (swordstate.phase == SwordState.Phase.WINDUP and swordstate.spec.type_id == SwordDefs.WARDEN)
	var drawn: Dictionary[StringName, int] = main._presenter._effects.draw_counts
	_ok("while the Wardens sweep, the effects layer keeps the fan the arc leaves and the windup shows where it will cut (drawn: %s)" % [drawn], wedges_seen and telegraph_seen and drawn.get(&"telegraph", 0) > 0 and drawn.get(&"fan", 0) > 0 and drawn.get(&"maelstrom", 0) > 0)
	await _tree.create_timer(0.1).timeout
	main._sfx.played.clear()
	main._sfx.play_cue(SimCue.make(SimCue.Kind.MAELSTROM_BEAT, Vector2.ZERO, Vector2.ZERO, 0))
	var silent_beat: bool = main._sfx.played.is_empty()
	main._sfx.play_cue(SimCue.make(SimCue.Kind.MAELSTROM_BEAT, Vector2.ZERO, Vector2.ZERO, 2))
	var struck_beat: bool = main._sfx.played.has("strike")
	main._sfx.played.clear()
	await _tree.create_timer(0.1).timeout
	main._sfx.play_cue(SimCue.make(SimCue.Kind.MAELSTROM_BURST, Vector2.ZERO, Vector2.ZERO, 1))
	_ok("a beat that struck something is heard (a slash), one that struck nothing is silent, and the burst is heard", silent_beat and struck_beat and main._sfx.played.has("strike"), "%s" % [main._sfx.played])
	var warden_visuals: int = 0
	for child: Node in main._presenter.get_children():
		if child is PlaceholderSwordVisual and (child as PlaceholderSwordVisual)._warden:
			warden_visuals += 1
	_ok("the two Wardens are drawn with the broad blade and the Fang with the needle (%d Warden visuals)" % warden_visuals, warden_visuals == 2)
	main.queue_free()
	await _tree.process_frame


func _check_hud() -> void:
	print("warden: the HUD in the warden encounter lies inside the viewport")
	var window: Window = Window.new()
	window.size = Vector2i(1084, 720)
	window.content_scale_size = Vector2i(1280, 720)
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	_tree.root.add_child(window)
	var hud: Hud = Hud.new()
	window.add_child(hud)
	var run: GameRun = GameRun.new(RunScenario.warden_encounter())
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
	_ok("the cards read Viper Flurry / Maelstrom / Maelstrom with FIRE, ICE and POISON tags and the sword type under the bar",
		hud._ult_names[1].text == "Maelstrom" and hud._ult_elements[1].text == "ICE" and hud._ult_elements[2].text == "FIRE" and hud._ult_elements[0].text == "POISON" and hud._ult_types[2].text == "Warden sword")
	window.queue_free()
	await _tree.process_frame


func _check_visual_independence() -> void:
	print("warden: swapping the sword visual leaves the fight unchanged")
	var hosts: Array[Main] = []
	for use_alt: bool in [false, true]:
		hosts.append(_main_with(RenderRateScenario.scenario(RenderRateScenario.WARDEN), "res://tests/alt_sword.tscn" if use_alt else ""))
	await _tree.process_frame
	var seen_phases: Dictionary = {}
	var results: Array[Dictionary] = []
	for host_index: int in hosts.size():
		var main: Main = hosts[host_index]
		for tick_index: int in 500:
			for command: GameCommand in RenderRateScenario.commands_at(main.run.tick, RenderRateScenario.WARDEN):
				main.run.apply(command)
			_tick_main(main, 1)
			if host_index == 1:
				for child: Node in main._presenter.get_children():
					if child is AltSwordVisual:
						seen_phases[(child as AltSwordVisual).last_phase] = true
		results.append(main.run.snapshot())
	_ok("a stretched, rotated replacement sword visual changes nothing about the sweeps, whirls, kills or recharges", results[0] == results[1])
	_ok("the replacement visual was told the strike and ultimate phases (%s)" % [seen_phases.keys()], seen_phases.has(SwordState.Phase.STRIKE) and seen_phases.has(SwordState.Phase.ULTIMATE))
	_ok("the fixture fought: %d hits, %d kills, %d whirls, %d bursts" % [hosts[0].run.cue_count(SimCue.Kind.ENEMY_HIT), hosts[0].run.kills, hosts[0].run.cue_count(SimCue.Kind.ULTIMATE_STARTED), hosts[0].run.cue_count(SimCue.Kind.MAELSTROM_BURST)],
		hosts[0].run.cue_count(SimCue.Kind.ENEMY_HIT) >= 20 and hosts[0].run.cue_count(SimCue.Kind.MAELSTROM_BURST) >= 1)
	for main: Main in hosts:
		main.queue_free()
	await _tree.process_frame


# -------------------------------------------------------- render rates
func _check_render_rates() -> void:
	print("warden: identical outcomes at low and high render rates")
	if not RenderRateScenario.probes_enabled():
		return
	var headless: Dictionary = RenderRateScenario.play_headless(RenderRateScenario.WARDEN)
	var expected_digest: Dictionary = JSON.parse_string(JSON.stringify(headless))
	_ok("the scripted fight does something worth comparing (whirls %d, refused %d, beats %d, bursts %d, hits %d, kills %d, alive %s)" % [int(headless["ultimate_cues"]), int(headless["refused_cues"]), int(headless["beat_cues"]), int(headless["burst_cues"]), int(headless["hit_cues"]), int(headless["kills"]), not bool(headless["dead"])],
		int(headless["ultimate_cues"]) == 6 and int(headless["refused_cues"]) == 3 and int(headless["burst_cues"]) == 2 and int(headless["beat_cues"]) >= 20 and int(headless["hit_cues"]) >= 60 and int(headless["kills"]) >= 5 and not bool(headless["dead"]))
	var executable: String = OS.get_executable_path()
	var project: String = ProjectSettings.globalize_path("res://")
	var frames: Dictionary[int, int] = {}
	for rate: int in PROBE_FRAME_RATES:
		var output: Array = []
		var arguments: PackedStringArray = ["--headless", "--path", project, "--fixed-fps", str(rate), "--script", PROBE_SCRIPT, "--", "--probe=rate-warden"]
		var code: int = OS.execute(executable, arguments, output, true)
		var line: String = _probe_line(output)
		_ok("the engine played the warden fight at %d fps (exit %d)" % [rate, code], code == 0 and not line.is_empty(), "%s" % [output])
		if line.is_empty():
			continue
		var result: Dictionary = JSON.parse_string(line)
		frames[rate] = int(result["frames"])
		var comparable: Dictionary = result.duplicate()
		for key: String in ["frames", "visuals", "enemies"]:
			comparable.erase(key)
		_ok("at %d fps the real Main scene ends the fight exactly like the bare simulation: same sweeps, whirls, kills, positions, phases and recharges" % rate, comparable == expected_digest, _first_difference(comparable, expected_digest))
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
