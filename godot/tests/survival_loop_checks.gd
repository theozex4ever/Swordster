class_name SurvivalLoopChecks
extends RefCounted
## Game-run behavioural checks for the Fang survival loop (issue #8). Every
## check drives the real `GameRun` through the same `GameCommand`s that player
## input produces, advances fixed ticks, and observes outcomes. Comparison
## values come from the Python prototype's captured reference
## (res://tests/reference/fang_survival_loop.json, recorded by
## tools/reference/capture_fang_survival_loop.py) with the tolerances declared
## below and explained in docs/reference/fang-survival-loop.md.

const REFERENCE_PATH: String = "res://tests/reference/fang_survival_loop.json"

## Numeric tolerances for same-algorithm comparisons at the prototype's 60 FPS.
const POSITION_TOL: float = 0.05  # px
const VELOCITY_TOL: float = 0.05  # px/s
const SCALAR_TOL: float = 0.002  # health, timers, shake
## Event timing tolerance: one fixed tick.
const TICK_TOL: int = 1

var _check: Callable
var _tree: SceneTree
var _ref: Dictionary = {}


func _init(check_function: Callable, tree: SceneTree) -> void:
	_check = check_function
	_tree = tree


func run_all() -> void:
	var file: FileAccess = FileAccess.open(REFERENCE_PATH, FileAccess.READ)
	if file == null:
		_check.call("reference file loads", false, REFERENCE_PATH)
		return
	_ref = JSON.parse_string(file.get_as_text())
	_check.call("reference file parses", not _ref.is_empty())
	_check_movement_and_camera()
	_check_dash()
	_check_damage_and_death()
	_check_restart_rules()
	_check_time_scales()
	_check_motes()
	_check_fang()
	_check_wave_and_outcomes()
	_check_pause_rules()
	_check_restart_cleanup()
	_check_input_aliases()
	await _check_main_scene_loop()
	await _check_touch_buttons()
	await _check_visual_independence()


# --------------------------------------------------------------- helpers
func _plain() -> RunScenario:
	var scenario: RunScenario = RunScenario.new().without_conditions()
	scenario.seed = 11
	scenario.waves_enabled = false
	var no_swords: Array[SwordSpec] = []
	scenario.loadout = no_swords
	return scenario


func _fang_slots(rarities: Array[int]) -> Array[SwordSpec]:
	var specs: Array[SwordSpec] = []
	for rarity: int in rarities:
		specs.append(SwordSpec.make(&"fang", rarity, &"fire"))
	return specs


func _steps(run: GameRun, count: int) -> void:
	for i: int in count:
		run.step()


func _ticks_for(seconds: float) -> int:
	return roundi(seconds * float(GameRun.TICK_RATE))


func _near(a: float, b: float, tolerance: float) -> bool:
	return absf(a - b) <= tolerance


func _near_v(a: Vector2, b: Vector2, tolerance: float) -> bool:
	return a.distance_to(b) <= tolerance


func _arr_vec(values: Array) -> Vector2:
	return Vector2(float(values[0]), float(values[1]))


func _ok(label: String, condition: bool, detail: String = "") -> void:
	_check.call(label, condition, detail)


func _count_cues(cues: Array[SimCue], kind: SimCue.Kind) -> int:
	var count: int = 0
	for cue: SimCue in cues:
		if cue.kind == kind:
			count += 1
	return count


## Steps the run, returning the tick of every cue of `kind` seen.
func _cue_ticks(run: GameRun, kind: SimCue.Kind, ticks: int) -> Array[int]:
	var found: Array[int] = []
	for i: int in ticks:
		run.step()
		for cue: SimCue in run.take_cues():
			if cue.kind == kind:
				found.append(run.tick)
	return found


func _within(actual: Array[int], expected: Array[int], tolerance: int) -> bool:
	if actual.size() != expected.size():
		return false
	for i: int in actual.size():
		if absi(actual[i] - expected[i]) > tolerance:
			return false
	return true


# ---------------------------------------------------- movement and camera
func _check_movement_and_camera() -> void:
	print("survival: movement and camera against the prototype")
	var movement: Dictionary = _ref["movement"]
	var trace: Dictionary = movement["dt_0.0167"]
	var centre: Vector2 = GameRun.WORLD.get_center()
	var run: GameRun = GameRun.new(_plain())
	run.apply(GameCommand.move_axis(Vector2.RIGHT))
	var sample_ticks: Dictionary = {15: "0.25", 30: "0.5", 60: "1.0", 120: "2.0"}
	for tick_index: int in range(1, 121):
		run.step()
		if sample_ticks.has(tick_index):
			var expected: Dictionary = trace[sample_ticks[tick_index]]
			var label: String = "t=%ss" % sample_ticks[tick_index]
			_ok("move right: x offset %s matches the prototype" % label, _near(run.position.x - centre.x, float(expected["x"]), POSITION_TOL), "%f vs %f" % [run.position.x - centre.x, float(expected["x"])])
			_ok("move right: velocity %s matches" % label, _near(run.velocity.x, float(expected["vx"]), VELOCITY_TOL), "%f vs %f" % [run.velocity.x, float(expected["vx"])])
			_ok("camera look-ahead %s matches (camera x offset)" % label, _near(run.camera.x - centre.x, float(expected["cam_x"]), POSITION_TOL), "%f vs %f" % [run.camera.x - centre.x, float(expected["cam_x"])])
			_ok("camera lags the player by the reference amount %s" % label, _near(run.camera.x - run.position.x, float(expected["cam_lead"]), POSITION_TOL))

	var diagonal: GameRun = GameRun.new(_plain())
	diagonal.apply(GameCommand.move_axis(Vector2(1.0, 1.0)))
	_steps(diagonal, 120)
	_ok("diagonal speed is 285 (normalised)", _near(diagonal.velocity.length(), float(movement["diagonal_speed_after_2s"]), VELOCITY_TOL))
	_ok("diagonal facing is the unit diagonal", _near_v(diagonal.facing, _arr_vec(movement["diagonal_facing"]), 0.001))

	var east: GameRun = GameRun.new(_plain())
	east.apply(GameCommand.move_axis(Vector2.RIGHT))
	_steps(east, 720)
	var east_ref: Dictionary = movement["east_wall"]
	_ok("east wall clamps the player like the prototype", _near(east.position.x, float(east_ref["player_x"]), POSITION_TOL))
	_ok("camera stops 140 px past the east wall", _near(east.camera.x, float(east_ref["cam_x"]), POSITION_TOL), str(east.camera))
	var corner: GameRun = GameRun.new(_plain())
	corner.apply(GameCommand.move_axis(Vector2(-1.0, -1.0)))
	_steps(corner, 720)
	var corner_ref: Dictionary = movement["north_west_wall"]
	_ok("north-west corner clamps the player", _near_v(corner.position, _arr_vec(corner_ref["player"]), POSITION_TOL))
	_ok("north-west camera clamp matches", _near_v(corner.camera, _arr_vec(corner_ref["cam"]), POSITION_TOL), str(corner.camera))

	var release: GameRun = GameRun.new(_plain())
	release.apply(GameCommand.move_axis(Vector2.RIGHT))
	_steps(release, 60)
	release.apply(GameCommand.move_axis(Vector2.ZERO))
	var release_ref: Dictionary = movement["release_velocity"]
	var release_ticks: Dictionary = {6: "0.1", 12: "0.2", 30: "0.5"}
	for tick_index: int in range(1, 31):
		release.step()
		if release_ticks.has(tick_index):
			_ok("velocity decay %ss after release matches" % release_ticks[tick_index], _near(release.velocity.x, float(release_ref[release_ticks[tick_index]]), VELOCITY_TOL))

	# Frame-rate independence is by construction (fixed tick). The accepted
	# deviation from the prototype's variable step is documented, not asserted.
	_ok("the simulation advances in whole fixed ticks", GameRun.TICK_RATE == 60 and _near(GameRun.TICK_DT * 60.0, 1.0, 1e-9))


# ------------------------------------------------------------------ dash
func _check_dash() -> void:
	print("survival: dash")
	var dash_ref: Dictionary = _ref["dash"]
	var trace: Dictionary = dash_ref["dt_0.0167"]["trace"]
	var run: GameRun = GameRun.new(_plain())
	var start: Vector2 = run.position
	run.apply(GameCommand.dash())
	_ok("dash starts the cooldown and invulnerability", _near(run.dash_cooldown_left, float(dash_ref["cooldown_at_dash"]), SCALAR_TOL) and _near(run.iframes, float(dash_ref["iframes_at_dash"]), SCALAR_TOL))
	_ok("dash launches at 1000 px/s", _near(run.velocity.length(), 1000.0, VELOCITY_TOL))
	var motion_ticks: int = 0
	var sample_ticks: Dictionary = {12: "0.2", 18: "0.3", 30: "0.5", 60: "1.0"}
	for tick_index: int in range(1, 61):
		run.step()
		if motion_ticks == 0 and run.dash_left <= 0.0:
			motion_ticks = tick_index
		if sample_ticks.has(tick_index):
			var expected: Dictionary = trace[sample_ticks[tick_index]]
			_ok("dash displacement at %ss matches" % sample_ticks[tick_index], _near(run.position.x - start.x, float(expected["dx"]), POSITION_TOL), "%f vs %f" % [run.position.x - start.x, float(expected["dx"])])
			_ok("dash velocity at %ss matches" % sample_ticks[tick_index], _near(run.velocity.x, float(expected["vx"]), VELOCITY_TOL))
	_ok("dash drives the player for the reference number of ticks", motion_ticks == int(dash_ref["dt_0.0167"]["dash_motion_ticks"]), str(motion_ticks))
	_ok("dash total distance ~205 px", _near(run.position.x - start.x, float(trace["1.0"]["dx"]), POSITION_TOL))

	var diagonal: GameRun = GameRun.new(_plain())
	diagonal.apply(GameCommand.move_axis(Vector2(-1.0, -1.0)))
	_steps(diagonal, 30)
	diagonal.apply(GameCommand.dash())
	_ok("dash goes where movement is held (normalised diagonal)", _near_v(diagonal.velocity, _arr_vec(dash_ref["dash_diagonal_velocity"]), 0.01), str(diagonal.velocity))
	var idle: GameRun = GameRun.new(_plain())
	idle.apply(GameCommand.move_axis(Vector2.LEFT))
	_steps(idle, 18)
	idle.apply(GameCommand.move_axis(Vector2.ZERO))
	_steps(idle, 6)
	idle.apply(GameCommand.dash())
	_ok("an idle dash uses the facing direction", _near_v(idle.velocity, _arr_vec(dash_ref["dash_uses_facing_when_idle"]), 0.01), str(idle.velocity))

	var gating: Dictionary = dash_ref["dash_gating"]
	for key: String in gating:
		var probe: GameRun = GameRun.new(_plain())
		probe.apply(GameCommand.dash())
		_steps(probe, _ticks_for(float(key)))
		probe.apply(GameCommand.dash())
		var accepted: bool = probe.dash_left > 0.0
		_ok("dash %ss after a dash is %s" % [key, gating[key]], accepted == (gating[key] == "accepted"), "dash_left=%f" % probe.dash_left)

	var dead: GameRun = GameRun.new(_plain())
	dead.hp = 0.0
	dead.dead = true
	dead.apply(GameCommand.dash())
	_ok("a dead player cannot dash", _near(dead.dash_cooldown_left, float(dash_ref["dead_dash_cooldown"]), SCALAR_TOL) and dead.velocity == Vector2.ZERO)

	var paused: GameRun = GameRun.new(_plain())
	paused.apply(GameCommand.pause())
	paused.apply(GameCommand.dash())
	_ok("dash is refused while paused", paused.dash_cooldown_left == 0.0 and paused.velocity == Vector2.ZERO)
	paused.apply(GameCommand.resume())
	paused.apply(GameCommand.dash())
	_ok("dash works again after resume", paused.dash_cooldown_left > 0.0)

	# Invulnerability: a husk parked on the player cannot hurt it during the dash.
	var invulnerable_scenario: RunScenario = _plain()
	invulnerable_scenario.initial_husks = [Vector2(2000.0, 900.0)]
	invulnerable_scenario.start_position = Vector2(1980.0, 900.0)
	var shielded: GameRun = GameRun.new(invulnerable_scenario)
	shielded.apply(GameCommand.dash())
	_steps(shielded, 12)
	_ok("contact during the dash's invulnerability does no damage", shielded.hp == GameRun.PLAYER_MAX_HP, str(shielded.hp))
	var exposed: GameRun = GameRun.new(invulnerable_scenario)
	_steps(exposed, 1)
	_ok("the same contact without dashing hurts", exposed.hp == GameRun.PLAYER_MAX_HP - 10.0)


# ---------------------------------------------------- damage, death, R
func _park_husk(run: GameRun) -> void:
	run.enemies[0].position = run.position + Vector2(20.0, 0.0)
	run.enemies[0].stun = 0.0


func _contact_scenario(health: float = -1.0) -> RunScenario:
	var scenario: RunScenario = _plain()
	scenario.initial_husks = [GameRun.WORLD.get_center() + Vector2(20.0, 0.0)]
	scenario.start_health = health
	return scenario


func _check_damage_and_death() -> void:
	print("survival: incoming damage, invulnerability and death")
	var damage_ref: Dictionary = _ref["damage"]
	var first: Dictionary = damage_ref["first_contact"]
	var run: GameRun = GameRun.new(_contact_scenario())
	run.step()
	_ok("husk contact deals 10", run.hp == float(first["hp"]), str(run.hp))
	_ok("a hit grants 0.8 s invulnerability", _near(run.iframes, float(first["iframes"]), SCALAR_TOL))
	_ok("a hit freezes gameplay for 0.07 s (hitstop)", _near(run.hitstop, float(first["hitstop"]), SCALAR_TOL))
	_ok("a hit adds 0.45 shake", _near(run.trauma, float(first["shake_trauma"]), SCALAR_TOL))
	_ok("a hit knocks the player back 420 px/s away from the husk", _near_v(run.velocity, _arr_vec(first["player_vel"]), VELOCITY_TOL), str(run.velocity))

	var sequence_run: GameRun = GameRun.new(_contact_scenario())
	var expected_hits: Array = damage_ref["contact_hit_sequence_first_6"]
	var seen: Array[int] = []
	var last_hp: float = sequence_run.hp
	for i: int in _ticks_for(4.0):
		sequence_run.step()
		if sequence_run.hp < last_hp:
			_ok("each contact hit is exactly 10 (hp %d)" % int(sequence_run.hp), last_hp - sequence_run.hp == 10.0)
			seen.append(sequence_run.tick)
			last_hp = sequence_run.hp
		_park_husk(sequence_run)
	var expected_ticks: Array[int] = []
	for entry: Dictionary in expected_hits:
		expected_ticks.append(roundi(float(entry["t_real"]) * 60.0))
	_ok("parked husk hurts once per invulnerability window (ticks %s vs %s)" % [seen, expected_ticks], _within(seen, expected_ticks, TICK_TOL))

	# Death: slow motion, delayed restart eligibility.
	var dying: GameRun = GameRun.new(_contact_scenario(10.0))
	dying.step()
	var death_ref: Dictionary = damage_ref["death"]
	_ok("lethal damage kills the player at 0 health", dying.dead and dying.hp == 0.0 and dying.outcome() == GameRun.Outcome.LOST)
	_ok("death starts 1.4 s of slow motion at 0.25 scale", _near(dying.slowmo, float(death_ref["slowmo"]), SCALAR_TOL) and _near(dying.slowmo_scale, float(death_ref["slowmo_scale"]), SCALAR_TOL))
	var death_tick: int = dying.tick
	var eligible_after: int = -1
	for i: int in _ticks_for(4.0):
		dying.step()
		if eligible_after < 0 and dying.can_restart_from_key():
			eligible_after = dying.tick - death_tick
	var expected_delay: int = roundi(float(damage_ref["restart_eligible_real_s_after_death"]) * 60.0)
	_ok("R becomes eligible %d real ticks after death (reference %d)" % [eligible_after, expected_delay], absi(eligible_after - expected_delay) <= TICK_TOL)
	_ok("dead players take no further damage", dying.hp == float(damage_ref["hp_after_death"]))
	_check_post_death_wandering()


## After the player dies husks stop chasing and drift at 0.3x their speed in a
## slowly turning direction. The drift's starting angle depends on object
## identity in the prototype, so only phase-independent numbers are compared:
## speed, distance from the start and how far the heading turns.
func _check_post_death_wandering() -> void:
	var ref: Dictionary = _ref["death_wander"]
	var scenario: RunScenario = _plain()
	scenario.initial_husks = [GameRun.WORLD.get_center() + Vector2(300.0, 0.0)]
	var run: GameRun = GameRun.new(scenario)
	var start: Vector2 = run.enemies[0].position
	run.dead = true
	run.hp = 0.0
	var checkpoints: Dictionary = {30: "0.5", 60: "1.0", 120: "2.0", 180: "3.0"}
	var headings: Dictionary = {}
	var speeds_match: bool = true
	var distances_match: bool = true
	var detail: String = ""
	for i: int in range(1, 181):
		run.step()
		if checkpoints.has(i):
			var key: String = checkpoints[i]
			var enemy: EnemyState = run.enemies[0]
			var expected: Dictionary = ref["samples"][key]
			speeds_match = speeds_match and _near(enemy.velocity.length(), float(expected["speed"]), VELOCITY_TOL)
			distances_match = distances_match and _near((enemy.position - start).length(), float(expected["distance"]), POSITION_TOL)
			headings[key] = enemy.velocity.angle()
			detail += " %ss: speed %.4f dist %.4f;" % [key, enemy.velocity.length(), (enemy.position - start).length()]
	_ok("a dead player's husk drifts at the prototype's speed ramp toward 0.3 x its speed" + detail, speeds_match and _near(run.enemies[0].velocity.length(), float(ref["target_speed"]), VELOCITY_TOL))
	_ok("a dead player's husk covers the prototype's distance from where it stood", distances_match)
	var turn: float = wrapf(float(headings["3.0"]) - float(headings["1.0"]), -PI, PI)
	_ok("the drift heading keeps turning (%.4f rad from 1 s to 3 s, reference %.4f)" % [turn, float(ref["heading_turn_1s_to_3s_rad"])], _near(turn, float(ref["heading_turn_1s_to_3s_rad"]), 0.002))
	_ok("the husk does not chase: it ends no closer to the dead player than it began", (run.enemies[0].position - run.position).length() > (start - run.position).length() - 100.0)


func _check_restart_rules() -> void:
	print("survival: restart eligibility")
	var run: GameRun = GameRun.new(_contact_scenario())
	run.apply(GameCommand.restart_from_key())
	_ok("R while alive is refused (it is the slot-three ultimate key)", run.restarts == 0)
	run.hp = 10.0
	run.step()
	_ok("the player died", run.dead)
	run.apply(GameCommand.restart_from_key())
	_ok("R right after death is refused", run.restarts == 0 and run.dead)
	var ticks_until_eligible: int = 0
	while not run.can_restart_from_key() and ticks_until_eligible < 600:
		run.step()
		ticks_until_eligible += 1
	run.apply(GameCommand.restart_from_key())
	_ok("R after the delay restarts", run.restarts == 1 and not run.dead and run.hp == GameRun.PLAYER_MAX_HP)

	# Slow motion stretches the delay in real time: 0.8 gameplay seconds.
	var slow: GameRun = GameRun.new(_contact_scenario(10.0))
	slow.step()
	_steps(slow, 60)
	_ok("one real second after death the delay has not elapsed (slow motion)", not slow.can_restart_from_key() and slow.death_time < GameRun.RESTART_DELAY, str(slow.death_time))
	slow.apply(GameCommand.pause())
	_steps(slow, 600)
	_ok("pause does not run out the restart delay", not slow.can_restart_from_key())
	slow.apply(GameCommand.resume())
	_steps(slow, 200)
	slow.apply(GameCommand.pause())
	slow.apply(GameCommand.restart_from_key())
	_ok("the prototype lets an eligible R restart even while paused; the new run is not left paused", slow.restarts == 1 and not slow.paused)

	var button: GameRun = GameRun.new(_contact_scenario())
	_steps(button, 30)
	button.apply(GameCommand.pause())
	button.apply(GameCommand.restart())
	_ok("the Restart button always restarts and un-pauses", button.restarts == 1 and not button.paused and button.tick == 0)

	var dead_move: GameRun = GameRun.new(_contact_scenario(10.0))
	var dead_still: GameRun = GameRun.new(_contact_scenario(10.0))
	dead_move.step()
	dead_still.step()
	dead_move.apply(GameCommand.move_axis(Vector2.RIGHT))
	_steps(dead_move, 90)
	_steps(dead_still, 90)
	_ok("a dead player ignores movement input (only knockback decays)", dead_move.position == dead_still.position and dead_move.velocity == dead_still.velocity)
	dead_move.apply(GameCommand.toggle_pause())
	_ok("a dead run can still be paused", dead_move.paused)


# ---------------------------------------------------- hitstop and slow-mo
func _check_time_scales() -> void:
	print("survival: hitstop, slow motion and real/scaled time")
	var ref: Dictionary = _ref["time_scale"]
	var hitstop_run: GameRun = GameRun.new(_plain())
	hitstop_run.apply(GameCommand.move_axis(Vector2.RIGHT))
	hitstop_run.hitstop = 0.05
	var frozen_updates: int = 0
	var time_before: float = hitstop_run.gameplay_time
	var x_before: float = hitstop_run.position.x
	while hitstop_run.hitstop > 0.0 and frozen_updates < 600:
		hitstop_run.step()
		frozen_updates += 1
	_ok("0.05 s of hitstop freezes %d ticks (reference %d)" % [frozen_updates, int(ref["hitstop_0.05_frozen_updates"])], frozen_updates == int(ref["hitstop_0.05_frozen_updates"]))
	_ok("hitstop freezes gameplay time and movement", hitstop_run.gameplay_time == time_before and hitstop_run.position.x == x_before)
	_ok("real time keeps running during hitstop", _near(hitstop_run.real_time, float(frozen_updates) / 60.0, 1e-6))
	var short: GameRun = GameRun.new(_plain())
	short.hitstop = 0.02
	var short_updates: int = 0
	while short.hitstop > 0.0 and short_updates < 600:
		short.step()
		short_updates += 1
	_ok("0.02 s of hitstop freezes %d ticks (reference)" % int(ref["hitstop_0.02_frozen_updates"]), short_updates == int(ref["hitstop_0.02_frozen_updates"]))

	var slow_half: GameRun = GameRun.new(_plain())
	slow_half.slowmo = 1.4
	slow_half.slowmo_scale = 0.25
	_steps(slow_half, 30)
	var half_ref: Dictionary = ref["slowmo_0.5s_real"]
	_ok("slow motion: 0.5 real s is %.3f scaled s" % float(half_ref["scaled_time"]), _near(slow_half.real_time, float(half_ref["real_time"]), 1e-6) and _near(slow_half.gameplay_time, float(half_ref["scaled_time"]), 1e-6), "%f / %f" % [slow_half.real_time, slow_half.gameplay_time])
	_ok("slow motion's own timer runs on real time", _near(slow_half.slowmo, float(half_ref["slowmo_left"]), SCALAR_TOL))
	var slow_full: GameRun = GameRun.new(_plain())
	slow_full.slowmo = 1.4
	slow_full.slowmo_scale = 0.25
	_steps(slow_full, 120)
	var full_ref: Dictionary = ref["slowmo_2s_real"]
	_ok("slow motion ends on schedule: 2 real s is %.2f scaled s" % float(full_ref["scaled_time"]), _near(slow_full.gameplay_time, float(full_ref["scaled_time"]), 0.02), str(slow_full.gameplay_time))

	var waiting: GameRun = GameRun.new(_plain())
	waiting.hitstop = 0.05
	waiting.slowmo = 1.0
	waiting.slowmo_scale = 0.25
	var waiting_ref: Dictionary = ref["slowmo_during_0.05s_hitstop"]
	var waiting_ticks: int = 0
	while waiting.hitstop > 0.0 and waiting_ticks < 600:
		waiting.step()
		waiting_ticks += 1
	_ok("the slow-motion timer waits out hitstop instead of running down (left %.3f, reference %.3f)" % [waiting.slowmo, float(waiting_ref["slowmo_left"])], waiting_ticks == int(waiting_ref["frozen_updates"]) and _near(waiting.slowmo, float(waiting_ref["slowmo_left"]), SCALAR_TOL) and _near(waiting.gameplay_time, float(waiting_ref["scaled_time"]), 1e-6))

	var paused: GameRun = GameRun.new(_plain())
	paused.apply(GameCommand.move_axis(Vector2.RIGHT))
	paused.apply(GameCommand.pause())
	paused.hitstop = 0.3
	paused.slowmo = 1.0
	paused.trauma = 0.5
	_steps(paused, 60)
	var paused_ref: Dictionary = ref["paused_1s"]
	_ok("pause freezes real time, scaled time and movement", paused.real_time == float(paused_ref["real_time"]) and paused.gameplay_time == float(paused_ref["time"]) and paused.position == GameRun.WORLD.get_center())
	_ok("pause also freezes hitstop, slow motion and shake decay", paused.hitstop == 0.3 and paused.slowmo == 1.0 and paused.trauma == 0.5)

	var shake: GameRun = GameRun.new(_plain())
	shake.trauma = 1.0
	shake.hitstop = 0.5
	_steps(shake, 15)
	_ok("shake keeps decaying during hitstop (real time)", _near(shake.trauma, float(ref["trauma_after_0.25s_hitstop"]), SCALAR_TOL), str(shake.trauma))

	# Enemies move in scaled time: a slowed husk covers a quarter of the distance.
	var scaled: RunScenario = _plain()
	scaled.initial_husks = [Vector2(300.0, 900.0)]
	scaled.enemy_speed_jitter = false
	var normal_run: GameRun = GameRun.new(scaled)
	var slowed_run: GameRun = GameRun.new(scaled)
	slowed_run.slowmo = 5.0
	slowed_run.slowmo_scale = 0.25
	_steps(normal_run, 30)
	_steps(slowed_run, 30)
	var normal_travel: float = absf(normal_run.enemies[0].position.x - 300.0)
	var slowed_travel: float = absf(slowed_run.enemies[0].position.x - 300.0)
	_ok("slow motion slows enemy chase (%.1f px vs %.1f px)" % [slowed_travel, normal_travel], slowed_travel < normal_travel * 0.45 and slowed_travel > 0.0)

	# Wave-clear slow motion is part of the same machinery.
	var cleared: RunScenario = RunScenario.new().without_conditions()
	cleared.seed = 5
	cleared.husk_count = 0
	cleared.first_wave_delay = 0.1
	var clear_run: GameRun = GameRun.new(cleared)
	_steps(clear_run, 20)
	_ok("an empty wave clears at once and starts the 0.7 s slow motion at 0.3", clear_run.director.survived and clear_run.slowmo > 0.0 and clear_run.slowmo_scale == 0.3 and clear_run.banner_title == "WAVE CLEARED")


# ----------------------------------------------------------- healing motes
func _check_motes() -> void:
	print("survival: healing motes")
	var ref: Dictionary = _ref["motes"]
	var motes: Array[Vector2] = []
	for i: int in 3:
		motes.append(GameRun.WORLD.get_center() + Vector2(60.0, 0.0))
	var scenario: RunScenario = _plain()
	scenario.initial_motes = motes
	scenario.start_health = 50.0
	var run: GameRun = GameRun.new(scenario)
	_steps(run, 120)
	_ok("three motes heal 1.5 (0.5 each) and are consumed", _near(run.hp, float(ref["three_motes_from_50"]["hp"]), SCALAR_TOL) and run.motes.is_empty(), str(run.hp))

	scenario.start_health = 99.8
	var nearly_full: GameRun = GameRun.new(scenario)
	_steps(nearly_full, 120)
	_ok("healing never exceeds the 100 health cap", nearly_full.hp == float(ref["three_motes_from_99.8"]["hp"]) and nearly_full.motes.is_empty(), str(nearly_full.hp))

	var single: Array[Vector2] = [GameRun.WORLD.get_center() + Vector2(40.0, 0.0)]
	scenario.initial_motes = single
	scenario.start_health = -1.0
	var full: GameRun = GameRun.new(scenario)
	_steps(full, 120)
	_ok("a mote is still consumed at full health", full.hp == 100.0 and full.motes.is_empty())

	var dead_run: GameRun = GameRun.new(scenario)
	dead_run.hp = 0.0
	dead_run.dead = true
	_steps(dead_run, 120)
	_ok("a dead player is not healed by motes", dead_run.hp == float(ref["mote_when_dead"]["hp"]) and dead_run.motes.is_empty())

	var cues_scenario: RunScenario = _plain()
	cues_scenario.initial_motes = single
	cues_scenario.start_health = 60.0
	var cue_run: GameRun = GameRun.new(cues_scenario)
	var collected: Array[int] = _cue_ticks(cue_run, SimCue.Kind.MOTE_COLLECTED, 120)
	_ok("collecting a mote is announced once", collected.size() == 1, str(collected))


# -------------------------------------------------------------- Fang combat
func _fang_fixture(rarity: int, crit: float, husk_at_x: float, speed_scale: float = 0.0) -> RunScenario:
	var scenario: RunScenario = _plain()
	scenario.loadout = _fang_slots([rarity])
	scenario.sword_start_cooldowns = [0.4]
	scenario.initial_husks = [GameRun.WORLD.get_center() + Vector2(husk_at_x, 0.0)]
	scenario.enemy_speed_scale = speed_scale
	scenario.crit_chance = crit
	return scenario


func _check_fang() -> void:
	print("survival: Fang automatic attack")
	var ref: Dictionary = _ref["fang"]
	var consts: Dictionary = ref["fang_constants"]
	_ok("Fang constants match the prototype table", SwordDefs.FANG_LENGTH == float(consts["length"]) and SwordDefs.FANG_RANGE == float(consts["range"]) and SwordDefs.FANG_COOLDOWN == float(consts["cooldown"]) and SwordDefs.FANG_DAMAGE == float(consts["damage"]) and SwordDefs.FANG_KNOCK == float(consts["knock"]) and SwordDefs.FANG_WINDUP == float(consts["windup"]) and SwordDefs.FANG_SPEED == float(consts["speed"]) and SwordDefs.FANG_HITSTOP == float(consts["hitstop"]) and SwordDefs.FANG_SHAKE == float(consts["shake"]))

	# Timeline against a stationary husk 100 px away.
	var run: GameRun = GameRun.new(_fang_fixture(0, 0.0, 100.0))
	var husk: EnemyState = run.enemies[0]
	var phases: Array[String] = []
	var hit_ticks: Array[int] = []
	var last_phase: SwordState.Phase = run.swords[0].phase
	var first_windup_tick: int = -1
	var strike_tick: int = -1
	for i: int in _ticks_for(4.0):
		run.step()
		var phase: SwordState.Phase = run.swords[0].phase
		if phase != last_phase:
			if phase == SwordState.Phase.WINDUP and first_windup_tick < 0:
				first_windup_tick = run.tick
			if phase == SwordState.Phase.STRIKE and strike_tick < 0:
				strike_tick = run.tick
			last_phase = phase
		for cue: SimCue in run.take_cues():
			if cue.kind == SimCue.Kind.ENEMY_HIT:
				hit_ticks.append(run.tick)
				_ok("every Fang hit on a Common sword deals 7", cue.amount == 7 and not cue.critical, str(cue.amount))
	var timeline: Array = ref["one_fang_one_husk_timeline_seed1"]
	var expected_first_windup: int = roundi(float(timeline[0]["t"]) * 60.0)
	var expected_strike: int = roundi(float(timeline[1]["t"]) * 60.0)
	_ok("Fang acquires its target after its start cooldown (tick %d vs %d)" % [first_windup_tick, expected_first_windup], absi(first_windup_tick - expected_first_windup) <= TICK_TOL)
	_ok("windup lasts 0.06 s then it strikes (tick %d vs %d)" % [strike_tick, expected_strike], absi(strike_tick - expected_strike) <= TICK_TOL)
	var expected_hit_ticks: Array[int] = []
	for time_value: Variant in ref["one_fang_one_husk_hit_times_by_seed"]["1"]:
		expected_hit_ticks.append(roundi(float(time_value) * 60.0))
	_ok("attack cadence matches the prototype (hit ticks %s vs %s)" % [hit_ticks, expected_hit_ticks], _within(hit_ticks, expected_hit_ticks, TICK_TOL))
	_ok("four 7-damage hits leave the 30-health husk at 2", husk.hp == 2.0 and not husk.dead, str(husk.hp))
	_ok("knockback pushed the stationary husk out of the 175+16 px range", (husk.position - run.position).length() > SwordDefs.FANG_RANGE + husk.radius)

	# Acquisition range: 175 + the target's 16 px radius.
	var ranges: Dictionary = ref["acquire_range_175_plus_radius_16_is_191"]
	for key: String in ranges:
		var probe: GameRun = GameRun.new(_fang_fixture(0, 0.0, float(key)))
		_steps(probe, 60)
		var engaged: bool = probe.enemies[0].hp < probe.enemies[0].max_hp
		_ok("husk at %s px is %s" % [key, ranges[key]], engaged == (ranges[key] == "engaged"))

	# Damage, crit and rounding (Python's round-half-even), by rarity.
	var rounding: Dictionary = ref["rounding"]
	for rarity: int in 3:
		for crit: bool in [false, true]:
			var key: String = "rarity%d%s" % [rarity, "_crit" if crit else ""]
			var probe: GameRun = GameRun.new(_fang_fixture(rarity, 1.0 if crit else 0.0, 100.0))
			var dealt: int = -1
			var was_crit: bool = false
			for i: int in 120:
				probe.step()
				for cue: SimCue in probe.take_cues():
					if cue.kind == SimCue.Kind.ENEMY_HIT and dealt < 0:
						dealt = cue.amount
						was_crit = cue.critical
			_ok("%s hit deals %d (reference)" % [key, int(rounding[key]["dealt"])], dealt == int(rounding[key]["dealt"]) and was_crit == crit, str(dealt))
	_ok("Mythic critical rounds 24.5 to 24, not 25 (half-even)", SimMath.py_round(24.5) == 24 and SimMath.py_round(25.5) == 26 and SimMath.py_round(12.25) == 12 and SimMath.py_round(0.5) == 0 and SimMath.py_round(1.5) == 2)
	_ok("rarity multipliers match the table", _near(SwordState.equip(SwordSpec.make(&"fang", 1, &"ice"), Vector2.ZERO, 0.0).damage, 9.1, 1e-6) and _near(SwordState.equip(SwordSpec.make(&"fang", 2, &"ice"), Vector2.ZERO, 0.0).cooldown, 0.222, 1e-6))

	# Hit feedback and knockback of one critical and one normal hit.
	var normal: GameRun = GameRun.new(_fang_fixture(0, 0.0, 100.0))
	normal.hit_enemy(normal.enemies[0], 7.0, Vector2.RIGHT, SwordDefs.FANG_KNOCK, normal.swords[0])
	var normal_ref: Dictionary = ref["common_hit"]
	_ok("normal hit: damage, knockback, stun, hitstop and shake match", normal.enemies[0].hp == 23.0 and _near_v(normal.enemies[0].velocity, _arr_vec(normal_ref["vel"]), VELOCITY_TOL) and _near(normal.enemies[0].stun, float(normal_ref["stun"]), 0.001) and _near(normal.hitstop, float(normal_ref["hitstop"]), SCALAR_TOL) and _near(normal.trauma, float(normal_ref["trauma"]), SCALAR_TOL), "%s %f %f %f" % [normal.enemies[0].velocity, normal.enemies[0].stun, normal.hitstop, normal.trauma])
	var critical: GameRun = GameRun.new(_fang_fixture(0, 1.0, 100.0))
	critical.hit_enemy(critical.enemies[0], 7.0, Vector2.RIGHT, SwordDefs.FANG_KNOCK, critical.swords[0])
	var crit_ref: Dictionary = ref["crit_hit"]
	_ok("critical hit: x2 damage, x1.3 knockback, longer hitstop and shake match", critical.enemies[0].hp == 16.0 and _near_v(critical.enemies[0].velocity, _arr_vec(crit_ref["vel"]), VELOCITY_TOL) and _near(critical.enemies[0].stun, float(crit_ref["stun"]), 0.001) and _near(critical.hitstop, float(crit_ref["hitstop"]), SCALAR_TOL) and _near(critical.trauma, float(crit_ref["trauma"]), SCALAR_TOL), "%s %f %f %f" % [critical.enemies[0].velocity, critical.enemies[0].stun, critical.hitstop, critical.trauma])
	var crit_count: int = 0
	var trials: GameRun = GameRun.new(_fang_fixture(0, 0.12, 100.0))
	trials.enemies[0].hp = 1.0e9
	trials.enemies[0].max_hp = 1.0e9
	for i: int in 4000:
		var before: float = trials.enemies[0].hp
		trials.hit_enemy(trials.enemies[0], 7.0, Vector2.RIGHT, 0.0, trials.swords[0])
		if before - trials.enemies[0].hp == 14.0:
			crit_count += 1
	_ok("the default critical chance is ~12%% (%d of 4000)" % crit_count, crit_count > 4000 * 0.12 * 0.8 and crit_count < 4000 * 0.12 * 1.2)

	# Death and reward resolve once, even with three swords on one husk.
	var crowd: RunScenario = _plain()
	crowd.loadout = RunScenario.fang_fixture_loadout()
	crowd.sword_start_cooldowns = [0.1, 0.1, 0.1]
	crowd.initial_husks = [GameRun.WORLD.get_center() + Vector2(90.0, 0.0)]
	crowd.enemy_speed_scale = 0.0
	crowd.crit_chance = 1.0
	var crowd_run: GameRun = GameRun.new(crowd)
	var kill_cues: int = 0
	var mote_peak: int = 0
	for i: int in 240:
		crowd_run.step()
		kill_cues += _count_cues(crowd_run.take_cues(), SimCue.Kind.ENEMY_KILLED)
		mote_peak = maxi(mote_peak, crowd_run.motes.size())
	_ok("a husk killed by three swords dies exactly once (kills=%d, kill cues=%d)" % [crowd_run.kills, kill_cues], crowd_run.kills == 1 and kill_cues == 1)
	_ok("its reward is exactly three healing motes (peak %d)" % mote_peak, mote_peak == 3)
	_ok("dead enemies leave the run and swords settle", crowd_run.enemies.is_empty() and crowd_run.swords[0].target == null)
	_ok("combo and kill counters follow the kill", crowd_run.best_combo == 1 and crowd_run.kills == 1)

	var wall: GameRun = GameRun.new(_plain())
	wall.enemies.append(EnemyState.husk(Vector2(10.0, 10.0), 1, 1.0, 99))
	wall.hit_enemy(wall.enemies[0], 1000.0, Vector2.LEFT, 0.0, null)
	var kills_after: int = wall.kills
	var hp_after: float = wall.enemies[0].hp
	wall.hit_enemy(wall.enemies[0], 1000.0, Vector2.LEFT, 0.0, null)
	wall.kill(wall.enemies[0], Vector2.LEFT)
	_ok("hitting or killing an already dead enemy changes nothing", wall.kills == kills_after and wall.motes.size() == 3 and wall.enemies[0].hp == hp_after)


# ------------------------------------------------- the wave and its outcome
func _check_wave_and_outcomes() -> void:
	print("survival: telegraphed wave, survive or lose")
	var wave_ref: Dictionary = _ref["wave"]
	var scenario: RunScenario = RunScenario.new().without_conditions()
	scenario.seed = 21
	var no_swords: Array[SwordSpec] = []
	scenario.loadout = no_swords
	scenario.enemy_speed_scale = 0.0
	var run: GameRun = GameRun.new(scenario)
	var wave_start_tick: int = -1
	var marker_ticks: Array[int] = []
	var spawn_ticks: Array[int] = []
	var seen_markers: int = 0
	var seen_enemies: int = 0
	for i: int in _ticks_for(8.0):
		run.step()
		if wave_start_tick < 0 and run.director.wave == 1:
			wave_start_tick = run.tick
		var markers_created: int = (8 - run.director.queue.size()) if run.director.wave >= 1 else 0
		if markers_created > seen_markers:
			marker_ticks.append(run.tick)
			seen_markers = markers_created
		var enemies_created: int = run.enemies.size()
		if enemies_created > seen_enemies:
			spawn_ticks.append(run.tick)
		seen_enemies = enemies_created
	_ok("wave 1 starts after the 1.6 s break (tick %d)" % wave_start_tick, absi(wave_start_tick - roundi(float(wave_ref["wave1_start_real_s"]) * 60.0)) <= TICK_TOL)
	var expected_markers: Array[int] = []
	for time_value: Variant in wave_ref["wave1_marker_times"]:
		expected_markers.append(roundi(float(time_value) * 60.0))
	var expected_spawns: Array[int] = []
	for time_value: Variant in wave_ref["wave1_enemy_spawn_times"]:
		expected_spawns.append(roundi(float(time_value) * 60.0))
	_ok("eight spawn telegraphs appear on the prototype's cadence (%s)" % [marker_ticks], _within(marker_ticks, expected_markers, TICK_TOL))
	_ok("each husk appears 0.7 s after its telegraph (%s)" % [spawn_ticks], _within(spawn_ticks, expected_spawns, TICK_TOL))
	_ok("the wave has the prototype's 5 + 3 husks", run.enemies.size() == int(wave_ref["enemy_count_wave1"]), str(run.enemies.size()))
	var all_husks: bool = true
	var all_far: bool = true
	var all_inside: bool = true
	for enemy: EnemyState in run.enemies:
		all_husks = all_husks and enemy.kind == EnemyState.HUSK and enemy.max_hp == float(wave_ref["wave1_enemy_hp_if_unarmed"])
		all_far = all_far and (enemy.position - run.position).length() > 320.0
		all_inside = all_inside and GameRun.WORLD.grow(-50.0).has_point(enemy.position)
	_ok("wave 1 is husk-only with the unarmed base health", all_husks)
	_ok("spawn points are over 320 px from the player and inside the arena margin", all_far and all_inside)

	# Survived: the fixture loadout clears the wave across seeds, inside the reference band.
	var survival_ref: Array = _ref["survival"]["wave1_three_fangs_stationary_player"]
	var lowest: float = INF
	var highest: float = 0.0
	for entry: Dictionary in survival_ref:
		lowest = minf(lowest, float(entry["cleared_at"]))
		highest = maxf(highest, float(entry["cleared_at"]))
	var reference_unarmed: bool = survival_ref.size() == 8
	for entry: Dictionary in survival_ref:
		reference_unarmed = reference_unarmed and int(entry["armed_enemies"]) == 0 and int(entry["husks_spawned"]) == 8 and int(entry["kills"]) == 8 and not bool(entry["died"])
	_ok("the survival reference is the unarmed fixture (no armed foe, 8 husks, 8 kills, never died)", reference_unarmed)
	var all_survived: bool = true
	var cleared_in_band: bool = true
	var min_hp: float = 100.0
	for seed_value: int in range(1, 9):
		var survive_scenario: RunScenario = RunScenario.new().without_conditions()
		survive_scenario.seed = seed_value
		var survive_run: GameRun = GameRun.new(survive_scenario)
		var ticks_taken: int = 0
		while survive_run.outcome() == GameRun.Outcome.RUNNING and ticks_taken < 60 * 60:
			survive_run.step()
			ticks_taken += 1
		var seconds: float = float(ticks_taken) / 60.0
		all_survived = all_survived and survive_run.outcome() == GameRun.Outcome.SURVIVED and survive_run.kills == 8 and not survive_run.dead
		cleared_in_band = cleared_in_band and seconds > lowest - 1.0 and seconds < highest + 1.0
		min_hp = minf(min_hp, survive_run.hp)
		if seed_value == 1:
			_ok("clearing the wave announces it and starts slow motion", survive_run.banner_title == "WAVE CLEARED" and survive_run.slowmo > 0.0 and survive_run.enemies.is_empty() and survive_run.director.markers.is_empty() and survive_run.director.queue.is_empty())
			_ok("the player kept some health and no entity of the wave remains", survive_run.hp > 0.0 and survive_run.hp <= 100.0)
	_ok("the three-Fang fixture survives the wave on all 8 seeds with all 8 kills", all_survived)
	_ok("wave clear time stays within the reference band %.1f-%.1f s +-1 s" % [lowest, highest], cleared_in_band)
	_ok("the survived runs stayed healthy (lowest health %.1f)" % min_hp, min_hp > 40.0)

	# Lost: no swords, the husks reach the player.
	var lose_scenario: RunScenario = RunScenario.new().without_conditions()
	lose_scenario.seed = 33
	lose_scenario.loadout = no_swords
	var lost_run: GameRun = GameRun.new(lose_scenario)
	var guard: int = 0
	while not lost_run.dead and guard < 60 * 90:
		lost_run.step()
		guard += 1
	_ok("a wave with no swords can be lost (tick %d)" % guard, lost_run.dead and lost_run.outcome() == GameRun.Outcome.LOST and lost_run.hp == 0.0)
	var queue_at_death: int = lost_run.director.queue.size()
	_steps(lost_run, 600)
	_ok("the spawn schedule stops once the player is dead", lost_run.director.queue.size() == queue_at_death)
	_ok("a lost run's counters are kept for the death screen", lost_run.director.wave == 1)


# ------------------------------------------------------------------- pause
func _check_pause_rules() -> void:
	print("survival: pause freezes the whole run")
	var scenario: RunScenario = RunScenario.new().without_conditions()
	scenario.seed = 8
	var run: GameRun = GameRun.new(scenario)
	_steps(run, 400)
	_ok("setup: enemies and a wave are in play", run.enemies.size() > 0 and run.director.wave == 1)
	run.apply(GameCommand.pause())
	var frozen: Dictionary = run.snapshot()
	run.apply(GameCommand.dash())
	run.apply(GameCommand.move_axis(Vector2.LEFT))
	_steps(run, 300)
	var still: Dictionary = run.snapshot()
	still.erase("move_input")
	frozen.erase("move_input")
	_ok("nothing in the run advances while paused (remembered input aside)", still == frozen, _diff_keys(still, frozen))
	run.apply(GameCommand.resume())
	_steps(run, 30)
	_ok("resume continues the same run", run.tick == int(frozen["tick"]) + 30 and run.dash_cooldown_left == 0.0)
	var heading_left: Vector2 = run.facing
	_ok("input given while paused applies after resume", heading_left == Vector2.LEFT)
	_ok("a dash refused while paused did not leak through on resume", run.hp >= 0.0 and run.dash_left == 0.0)


# ----------------------------------------------------------------- restart
func _check_restart_cleanup() -> void:
	print("survival: restart clears every run-owned entity and counter")
	var scenario: RunScenario = RunScenario.new().without_conditions()
	scenario.seed = 8
	var run: GameRun = GameRun.new(scenario)
	var fresh: Dictionary = GameRun.new(scenario).snapshot()
	run.apply(GameCommand.move_axis(Vector2(1.0, 0.5)))
	_steps(run, 600)
	_ok("setup: the run has kills, enemies, motes and a started wave", run.kills > 0 and run.director.wave == 1)
	run.apply(GameCommand.dash())
	run.hitstop = 0.4
	run.slowmo = 1.0
	run.slowmo_scale = 0.3
	run.trauma = 1.0
	run.apply(GameCommand.restart())
	var restarted: Dictionary = run.snapshot()
	restarted.erase("restarts")
	fresh.erase("restarts")
	_ok("restart equals a fresh run, field by field", restarted == fresh, _diff_keys(restarted, fresh))
	_ok("restart clears enemies, motes, telegraphs and the spawn queue", run.enemies.is_empty() and run.motes.is_empty() and run.director.markers.is_empty() and run.director.queue.is_empty() and run.director.wave == 0)
	_ok("restart clears hitstop, slow motion, shake, banner and combo", run.hitstop == 0.0 and run.slowmo == 0.0 and run.slowmo_scale == 1.0 and run.trauma == 0.0 and run.kick == Vector2.ZERO and run.banner_title == "" and run.combo == 0 and run.best_combo == 0)
	_ok("restart refills health and clears dash and invulnerability", run.hp == 100.0 and not run.dead and run.dash_left == 0.0 and run.dash_cooldown_left == 0.0 and run.iframes == 0.0)
	_ok("restart re-equips three Fang sword slots at rest", run.swords.size() == 3 and run.swords[0].phase == SwordState.Phase.IDLE and run.swords[2].target == null)
	_ok("restart discards undelivered cues", run.take_cues().is_empty())
	_steps(run, 600)
	var again: GameRun = GameRun.new(scenario)
	_steps(again, 600)
	var rerun: Dictionary = run.snapshot()
	var baseline: Dictionary = again.snapshot()
	rerun.erase("restarts")
	baseline.erase("restarts")
	_ok("a restarted seeded run replays exactly like a fresh one", rerun == baseline, _diff_keys(rerun, baseline))


func _diff_keys(a: Dictionary, b: Dictionary) -> String:
	var different: Array[String] = []
	for key: String in a:
		if a[key] != b.get(key):
			different.append(key)
	return str(different)


# ------------------------------------------------------------ input aliases
func _key(code: Key) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = true
	return event


func _check_input_aliases() -> void:
	print("survival: dash and restart key aliases")
	for code: Key in [KEY_SPACE, KEY_SHIFT]:
		var translator: InputTranslator = InputTranslator.new()
		var commands: Array[GameCommand] = translator.handle_event(_key(code))
		_ok("%s dashes" % OS.get_keycode_string(code), commands.size() == 1 and commands[0].kind == GameCommand.Kind.DASH)
	var held: InputTranslator = InputTranslator.new()
	held.handle_event(_key(KEY_SPACE))
	var echo: InputEventKey = _key(KEY_SPACE)
	echo.echo = true
	_ok("a held dash key does not repeat", held.handle_event(echo).is_empty())
	var r_key: InputTranslator = InputTranslator.new()
	var restart: Array[GameCommand] = r_key.handle_event(_key(KEY_R))
	_ok("R translates to the slot-three ultimate and the delayed keyboard restart, not the button's restart", restart.size() == 2 and restart[0].kind == GameCommand.Kind.ULTIMATE and restart[0].slot == 2 and restart[1].kind == GameCommand.Kind.RESTART_FROM_KEY)


# --------------------------------------------------- the real Main scene
func _main_scenario() -> RunScenario:
	var scenario: RunScenario = RunScenario.new().without_conditions()
	scenario.seed = 17
	return scenario


func _press(main: Main, code: Key) -> void:
	main._input(_key(code))


func _tick_main(main: Main, count: int) -> void:
	for i: int in count:
		main._physics_process(GameRun.TICK_DT)


func _check_main_scene_loop() -> void:
	print("survival: the Main scene plays the loop (HUD, presenters, keys)")
	var scene: PackedScene = load("res://scenes/main.tscn")
	var main: Main = scene.instantiate() as Main
	var quick: RunScenario = RunScenario.new().without_conditions()
	quick.seed = 4
	quick.first_wave_delay = 0.1
	quick.husk_count = 3
	main.scenario = quick
	_tree.root.add_child(main)
	main.set_physics_process(false)
	await _tree.process_frame
	_press(main, KEY_SPACE)
	_ok("Space dashes the real run", main.run.dash_left > 0.0 and main._sfx.played.has("dash"), str(main._sfx.played))
	var dash_left_before: float = main.run.dash_left
	var velocity_before: Vector2 = main.run.velocity
	_press(main, KEY_SHIFT)
	_ok("Shift while the dash is on cooldown is refused", main.run.dash_left == dash_left_before and main.run.velocity == velocity_before)
	_tick_main(main, 30)
	await _tree.process_frame
	_ok("telegraphs and husks reach the presenter (setup)", main._presenter.visual_count() >= 3)
	var guard: int = 0
	while main.run.outcome() == GameRun.Outcome.RUNNING and guard < 60 * 40:
		_tick_main(main, 1)
		guard += 1
	_ok("the HUD reports the survived outcome", main._hud.outcome_text() == "WAVE SURVIVED" and main.run.outcome() == GameRun.Outcome.SURVIVED, main._hud.outcome_text())
	_press(main, KEY_R)
	_ok("R after surviving does not restart (it is an ultimate key)", main.run.restarts == 0)
	main._hud.restart_pressed.emit()
	_ok("the Restart button restarts and clears the outcome screen", main.run.restarts == 1 and main._hud.outcome_text() == "" and main.run.tick == 0)
	await _tree.process_frame
	_ok("restart removes every enemy visual (only the three swords remain)", main._presenter.visual_count() == 3, str(main._presenter.visual_count()))
	main.queue_free()
	await _tree.process_frame

	# Lost: a lethal contact fixture.
	var doom: RunScenario = RunScenario.new().without_conditions()
	doom.seed = 6
	doom.waves_enabled = false
	doom.start_health = 10.0
	doom.initial_husks = [GameRun.WORLD.get_center() + Vector2(20.0, 0.0)]
	var loser: Main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Main
	loser.scenario = doom
	_tree.root.add_child(loser)
	loser.set_physics_process(false)
	await _tree.process_frame
	_tick_main(loser, 2)
	_ok("the player dies in the scene", loser.run.dead)
	_press(loser, KEY_R)
	_ok("R during the death slow motion does nothing", loser.run.restarts == 0)
	_tick_main(loser, 60)
	_ok("the death screen is not up yet after one real second", loser._hud.outcome_text() == "" and loser.run.restarts == 0)
	_press(loser, KEY_R)
	_ok("R before the delay is still refused", loser.run.restarts == 0)
	_tick_main(loser, 70)
	_ok("the HUD reports the lost outcome once the delay passes", loser._hud.outcome_text() == "THE SWORDS FALL SILENT", loser._hud.outcome_text())
	_press(loser, KEY_R)
	_ok("R after the delay restarts", loser.run.restarts == 1 and not loser.run.dead and loser._hud.outcome_text() == "")
	loser.queue_free()
	await _tree.process_frame


# ------------------------------------------------ HUD buttons, real input
## One pointer contact on a HUD button, delivered the way the engine delivers
## it: a mouse button through the viewport's GUI pipeline, or a screen touch
## that Godot's touch-to-mouse emulation turns into that same mouse button.
func _contact(main: Main, position: Vector2, pressed: bool, via_touch: bool) -> void:
	if via_touch:
		var touch: InputEventScreenTouch = InputEventScreenTouch.new()
		touch.index = 0
		touch.position = position
		touch.pressed = pressed
		Input.parse_input_event(touch)
		Input.flush_buffered_events()
		return
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = position
	click.global_position = position
	click.pressed = pressed
	click.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	main.get_viewport().push_input(motion)
	main.get_viewport().push_input(click)


func _check_touch_buttons() -> void:
	print("survival: HUD buttons act on press like the prototype's pointerdown")
	# The headless window is 64x64; give it the game's real size so pointer
	# positions map onto the HUD exactly as on a 1280x720 screen.
	var window_size: Vector2i = _tree.root.size
	_tree.root.size = Vector2i(1280, 720)
	for via_touch: bool in [false, true]:
		var how: String = "touch" if via_touch else "mouse"
		var main: Main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Main
		main.scenario = _contact_scenario()
		_tree.root.add_child(main)
		main.set_physics_process(false)
		await _tree.process_frame
		await _tree.process_frame
		var hud: Hud = main._hud
		var presses: Array[int] = [0, 0, 0]  # dash, pause, restart
		hud.dash_pressed.connect(func() -> void: presses[0] += 1)
		hud.pause_pressed.connect(func() -> void: presses[1] += 1)
		hud.restart_pressed.connect(func() -> void: presses[2] += 1)

		# Dash: the whole point is that the finger-down starts it, with the
		# invulnerability window open before the very next contact tick.
		var dash_at: Vector2 = hud._dash_button.get_global_rect().get_center()
		_contact(main, dash_at, true, via_touch)
		_ok("%s: Dash starts on finger-down, before release" % how, main.run.dash_left > 0.0 and main.run.iframes > 0.0 and presses[0] == 1, "dash_left=%f iframes=%f presses=%d" % [main.run.dash_left, main.run.iframes, presses[0]])
		_tick_main(main, 2)
		_ok("%s: the contact tick right after the press costs no health" % how, main.run.hp == GameRun.PLAYER_MAX_HP, str(main.run.hp))
		_tick_main(main, 90)
		_ok("%s: holding the Dash button does not repeat the dash (even after the cooldown)" % how, presses[0] == 1 and main.run.dash_cooldown_left == 0.0, "presses=%d" % presses[0])
		_contact(main, dash_at, false, via_touch)
		_ok("%s: releasing Dash does nothing extra" % how, presses[0] == 1 and main.run.dash_left <= 0.0 and main.run.dash_cooldown_left == 0.0, "presses=%d dash_left=%f cooldown=%f" % [presses[0], main.run.dash_left, main.run.dash_cooldown_left])
		_contact(main, dash_at, true, via_touch)
		_contact(main, dash_at, false, via_touch)
		_ok("%s: a second tap dashes again once the cooldown is over" % how, presses[0] == 2 and main.run.dash_left > 0.0)

		# Pause / Resume toggle on press, never again on release.
		var pause_at: Vector2 = hud._pause_button.get_global_rect().get_center()
		_contact(main, pause_at, true, via_touch)
		_ok("%s: Pause pauses on finger-down" % how, main.run.paused and presses[1] == 1)
		_contact(main, pause_at, false, via_touch)
		_ok("%s: releasing Pause does not resume" % how, main.run.paused and presses[1] == 1)
		_contact(main, pause_at, true, via_touch)
		_ok("%s: Resume resumes on finger-down" % how, not main.run.paused and presses[1] == 2)
		_contact(main, pause_at, false, via_touch)
		_ok("%s: releasing Resume does not pause again" % how, not main.run.paused and presses[1] == 2)

		# Restart restarts on press.
		_tick_main(main, 10)
		var restart_at: Vector2 = hud._restart_button.get_global_rect().get_center()
		_contact(main, restart_at, true, via_touch)
		_ok("%s: Restart restarts on finger-down" % how, main.run.restarts == 1 and presses[2] == 1 and main.run.tick == 0)
		_contact(main, restart_at, false, via_touch)
		_ok("%s: releasing Restart does not restart again" % how, main.run.restarts == 1 and presses[2] == 1)

		# A press that slides off a button and lifts elsewhere still counted on
		# the press; a press that begins off a button never triggers it.
		_contact(main, Vector2(5.0, 700.0), true, via_touch)
		_contact(main, dash_at, false, via_touch)
		_ok("%s: a contact that starts off the button and lifts on it does nothing" % how, presses[0] == 2 and main.run.dash_left <= 0.0)
		main.queue_free()
		await _tree.process_frame
	_tree.root.size = window_size

func _check_visual_independence() -> void:
	print("survival: swapping actor, sword and enemy visuals leaves combat unchanged")
	var results: Array[Dictionary] = []
	var hosts: Array[Main] = []
	for use_alt: bool in [false, true]:
		var main: Main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Main
		var scenario: RunScenario = RunScenario.new().without_conditions()
		scenario.seed = 29
		scenario.first_wave_delay = 0.2
		main.scenario = scenario
		if use_alt:
			main.actor_visual = load("res://tests/alt_actor.tscn")
			main.sword_visual = load("res://tests/alt_sword.tscn")
			main.enemy_visual = load("res://tests/alt_enemy.tscn")
		_tree.root.add_child(main)
		main.set_physics_process(false)
		hosts.append(main)
	await _tree.process_frame
	for main: Main in hosts:
		main.input.handle_event(_key(KEY_D))
		_tick_main(main, 200)
		_press(main, KEY_SPACE)
		_tick_main(main, 400)
		results.append(main.run.snapshot())
	_ok("combat is identical with replaced actor, sword and enemy visuals", results[0] == results[1], _diff_keys(results[0], results[1]))
	_ok("the fixture actually fought (kills and hits happened)", int(results[0]["kills"]) > 0 and int(results[0]["wave"]) == 1)
	var alt: Main = hosts[1]
	var alt_swords: int = 0
	var alt_enemies: int = 0
	for child: Node in alt._presenter.get_children():
		if child.is_queued_for_deletion():
			continue
		if child is AltSwordVisual:
			alt_swords += 1
			_ok("the replacement sword visual received the logical pose and setup", (child as AltSwordVisual).pose_calls > 0 and (child as AltSwordVisual).configured_with != null)
		if child is AltEnemyVisual:
			alt_enemies += 1
	_ok("one replacement sword visual per sword slot", alt_swords == 3)
	_ok("replacement enemy visuals follow the run's enemies", alt_enemies == alt.run.enemies.size(), "%d vs %d" % [alt_enemies, alt.run.enemies.size()])
	_ok("a huge, squashed enemy visual does not change who can be hit (collision stays the husk's 16 px)", EnemyState.HUSK_RADIUS == 16.0 and (alt.run.enemies.is_empty() or alt.run.enemies[0].radius == 16.0))
	for main: Main in hosts:
		main.queue_free()
	await _tree.process_frame
