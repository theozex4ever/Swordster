class_name WavesChecks
extends RefCounted
## Behavioural checks for the wave machine of the normal run (issue #18): composition and its unlocks, the formulas for
## enemy count, health and spawn timing, where markers appear, how often enemies arrive armed and with which swords, how a wave
## completes and the break that follows, death and restart, and the counters a player watches (kills, chain, healing, banners).
## Like the earlier groups every check drives the real `GameRun` (or the real Main scene) with fixed ticks and observes outcomes.
## Comparison values come from the Python prototype's captured reference (res://tests/reference/waves.json, recorded by
## tools/reference/capture_waves.py from the prototype's own `Game.start_wave`, `update_waves`, `spawn_point`, `kill`, `update`,
## `reset`, `draw` and `Enemy`). No check relies on the prototype's random stream: what is exact is compared exactly from
## scripted draws or controlled outcomes (a kill placed by the check, a wave of a named composition), and what is random is
## compared as a distribution within its sampling error. Tolerances and deliberate exceptions: docs/reference/waves.md.

const REFERENCE_PATH: String = "res://tests/reference/waves.json"
const EPS: float = 1e-4
## The reference rounds timers to six places.
const TIMER_TOL: float = 2e-6
const POINT_TOL: float = 0.01
## A sampled share may differ from the reference's by this many standard errors of their difference (and a little more).
const SIGMA: float = 4.5
const SHARE_SLACK: float = 0.004
const HEALED_FULL: float = 1e9
## The armed first wave of the normal run is compared with the prototype's across eight seeds within this many seconds.
const FIRST_WAVE_BAND: float = 1.0

var _check: Callable
var _tree: SceneTree
var _ref: Dictionary = {}


func _init(check_function: Callable, tree: SceneTree) -> void:
	_check = check_function
	_tree = tree


func run_all() -> void:
	if not CheckFocus.includes("waves"):
		return
	var file: FileAccess = FileAccess.open(REFERENCE_PATH, FileAccess.READ)
	if file == null:
		_ok("waves reference file loads", false, REFERENCE_PATH)
		return
	_ref = JSON.parse_string(file.get_as_text())
	_ok("waves reference file parses", not _ref.is_empty())
	_check_reference_scope()
	_check_formulas()
	_check_timing()
	_check_spawn_points()
	_check_distributions()
	_check_first_wave_guarantee()
	_check_completion()
	_check_freeze()
	_check_death_and_restart()
	_check_counters()
	_check_healing()
	_check_progression()
	_check_no_cap()
	_check_normal_first_wave()
	_check_fixtures_unchanged()
	await _check_hud()
	await _check_banner_clearance()
	await _check_main_scene()
	await _check_visual_independence()


# --------------------------------------------------------------- helpers
func _ok(label: String, condition: bool, detail: String = "") -> void:
	_check.call(label, condition, detail)


func _near(a: float, b: float, tolerance: float) -> bool:
	return absf(a - b) <= tolerance


func _steps(run: GameRun, count: int) -> void:
	for i: int in count:
		run.step()


## A normal run with no swords (nothing fights unless a check makes it), a fixed seed and a player nothing can hurt: the
## controlled start for every check that places its own kills.
func _rig(seed_value: int, wave_count: int = 0) -> GameRun:
	var scenario: RunScenario = RunScenario.normal_run()
	scenario.seed = seed_value
	scenario.wave_count = wave_count
	var no_swords: Array[SwordSpec] = []
	scenario.loadout = no_swords
	scenario.crit_chance = 0.0
	return GameRun.new(scenario)


func _invulnerable(run: GameRun) -> void:
	run.iframes = HEALED_FULL
	run.hp = run.max_hp


func _husk_at(point: Vector2, wave: int, armed: SwordSpec = null) -> EnemyState:
	return EnemyState.make(EnemyDefs.HUSK, point, wave, 0.0, 9000, 0.0, 0.0, armed)


func _kinds_in(values: Array) -> String:
	return ",".join(values.map(func(value: Variant) -> String: return String(value)))


## Whether a sampled share agrees with the reference's: within SIGMA standard errors of their difference.
func _share_agrees(sample: float, sample_count: int, reference: float, reference_count: int) -> bool:
	if sample_count <= 0 or reference_count <= 0:
		return false
	var pooled: float = (sample * float(sample_count) + reference * float(reference_count)) / float(sample_count + reference_count)
	var error: float = sqrt(maxf(pooled * (1.0 - pooled), 0.0) * (1.0 / float(sample_count) + 1.0 / float(reference_count)))
	return absf(sample - reference) <= SIGMA * error + SHARE_SLACK


# --------------------------------------------------------------- scope
func _check_reference_scope() -> void:
	var scope: Dictionary = _ref["fixture_scope"]
	_ok("the reference was captured from the prototype's own classes with the swords parked, no Converge, no conditions, no random stream relied on and the distributions marked statistical",
		bool(scope["swords_parked"]) and not bool(scope["converge_used"]) and not bool(scope["conditions_applied"]) and not bool(scope["random_streams_matched"]) and bool(scope["scripted_draws_used_for_exact_cases"]) and bool(scope["distributions_are_statistical"]))


# --------------------------------------------------------------- formulas
func _check_formulas() -> void:
	print("waves: formulas")
	var table: Array = _ref["table"]
	var wrong: Array[String] = []
	for entry: Dictionary in table:
		var wave: int = int(entry["wave"])
		var pool: Array = entry["pool"]
		var kinds: Array[StringName] = WaveDefs.pool_kinds(wave)
		var same: bool = kinds.size() == pool.size() and WaveDefs.enemy_count(wave) == int(entry["count"]) and _near(WaveDefs.total_weight(wave), float(entry["total_weight"]), 1e-9)
		if same:
			for i: int in kinds.size():
				same = same and String(kinds[i]) == String(pool[i][0]) and _near(WaveDefs.weight_of(kinds[i], wave), float(pool[i][1]), 1e-9)
		if not same:
			wrong.append("wave %d: %s x%d" % [wave, _kinds_in(kinds), WaveDefs.enemy_count(wave)])
	_ok("waves 1 to 30 queue 5 + 3 w enemies from the prototype's weighted pool: husks 6, runners 2.5 from wave 2, spitters 2 from wave 3, brutes 0.6 + 0.25 w from wave 2 (%d of %d differ: %s)" % [wrong.size(), table.size(), wrong.slice(0, 3)], wrong.is_empty() and table.size() == 30)
	var unlocks: Array[String] = []
	for wave: int in [1, 2, 3, 4]:
		unlocks.append(_kinds_in(WaveDefs.pool_kinds(wave)))
	_ok("the unlocks are husk; then runners and brutes; then spitters (%s)" % [unlocks], unlocks == ["husk", "husk,runner,brute", "husk,runner,spitter,brute", "husk,runner,spitter,brute"])

	var draws_wrong: Array[String] = []
	var draws_total: int = 0
	for entry: Dictionary in _ref["kind_draws"]:
		var wave: int = int(entry["wave"])
		_ok("wave %d: the reference's total weight %.2f is ours" % [wave, float(entry["total"])], _near(WaveDefs.total_weight(wave), float(entry["total"]), 1e-5))
		for pair: Array in entry["draws"]:
			draws_total += 1
			if String(WaveDefs.kind_for(float(pair[0]), wave)) != String(pair[1]):
				draws_wrong.append("wave %d draw %s: %s, not %s" % [wave, pair[0], WaveDefs.kind_for(float(pair[0]), wave), pair[1]])
	_ok("the kind a draw picks agrees with the prototype's `weighted()` at, just under and just over every cumulative weight (%d draws, %d differ: %s)" % [draws_total, draws_wrong.size(), draws_wrong.slice(0, 2)], draws_wrong.is_empty() and draws_total >= 100)

	var hp_wrong: Array[String] = []
	var armed_spec: SwordSpec = SwordSpec.make(SwordDefs.FANG, 0, &"fire")
	var rows: Array = _ref["hp"]["rows"]
	for row: Dictionary in rows:
		var kind: StringName = StringName(row["kind"])
		var wave: int = int(row["wave"])
		var plain: EnemyState = EnemyState.make(kind, Vector2.ZERO, wave, 1.0, 1)
		var carrying: EnemyState = EnemyState.make(kind, Vector2.ZERO, wave, 1.0, 1, 0.0, 0.0, armed_spec)
		if not _near(plain.max_hp, float(row["unarmed"]), EPS) or not _near(carrying.max_hp, float(row["armed"]), EPS) or not _near(plain.hp, plain.max_hp, 1e-9):
			hp_wrong.append("%s wave %d: %.3f / %.3f" % [kind, wave, plain.max_hp, carrying.max_hp])
	_ok("an enemy's health is its type's x (1 + 0.1 (wave - 1)), x1.35 when armed, for every type over waves 1 to 30 (%d of %d differ: %s)" % [hp_wrong.size(), rows.size(), hp_wrong.slice(0, 3)], hp_wrong.is_empty() and rows.size() == 120)
	_ok("the health factor grows 10 %% of the first wave's per wave, with no ceiling (wave 1: %.2f, 11: %.2f, 101: %.2f)" % [WaveDefs.hp_factor(1), WaveDefs.hp_factor(11), WaveDefs.hp_factor(101)], WaveDefs.hp_factor(1) == 1.0 and _near(WaveDefs.hp_factor(11), 2.0, 1e-9) and _near(WaveDefs.hp_factor(101), 11.0, 1e-9))

	# the speed factor each arriving enemy draws, from the director's own marker-to-enemy step
	var run: GameRun = _rig(5)
	var factors: Array[float] = []
	var base_speed: float = EnemyDefs.HUSK_SPEED
	for batch: int in 40:
		for i: int in 100:
			var marker: SpawnMarker = SpawnMarker.make(EnemyDefs.HUSK, Vector2(500.0, 500.0))
			marker.remaining = 0.0
			run.director.markers.append(marker)
		run.enemies.clear()
		run.director.update(run, GameRun.TICK_DT)
		for enemy: EnemyState in run.enemies:
			factors.append(enemy.speed / base_speed)
	var lowest: float = 9.0
	var highest: float = 0.0
	var mean: float = 0.0
	for factor: float in factors:
		lowest = minf(lowest, factor)
		highest = maxf(highest, factor)
		mean += factor / float(factors.size())
	var speeds: Dictionary = _ref["hp"]
	_ok("arriving enemies draw their speed from 0.9 to 1.12 times the type's, centred like the prototype's (%d drawn: %.3f to %.3f, mean %.3f; reference %.3f to %.3f, mean %.3f)" % [factors.size(), lowest, highest, mean, float(speeds["speed_factor_min"]), float(speeds["speed_factor_max"]), float(speeds["speed_factor_mean"])],
		factors.size() == 4000 and lowest >= 0.9 - 1e-9 and highest <= 1.12 + 1e-9 and lowest < 0.905 and highest > 1.115 and _near(mean, float(speeds["speed_factor_mean"]), 0.004))
	_ok("a wave's banners and timings are the prototype's: wave banner %.1f s, cleared banner %.1f s, break %.1f s, first break %.1f s, marker %.1f s, slow motion %.1f s at x%.1f" % [WaveDefs.WAVE_BANNER_SECONDS, WaveDefs.CLEARED_BANNER_SECONDS, WaveDirector.CLEARED_BREAK, RunScenario.new().first_wave_delay, SpawnMarker.TELEGRAPH, WaveDirector.CLEARED_SLOWMO, WaveDirector.CLEARED_SLOWMO_SCALE],
		WaveDefs.WAVE_BANNER_SECONDS == float(_ref["banners"]["started"][2]) and WaveDefs.CLEARED_BANNER_SECONDS == float(_ref["banners"]["cleared"][2]) and WaveDirector.CLEARED_BREAK == 3.2 and RunScenario.new().first_wave_delay == float(_ref["clear_and_break"]["fresh_break_t"]) and SpawnMarker.TELEGRAPH == float(_ref["timing"]["marker_life"]) and WaveDirector.CLEARED_SLOWMO == 0.7 and WaveDirector.CLEARED_SLOWMO_SCALE == 0.3)


# --------------------------------------------------------------- spawn timing
func _check_timing() -> void:
	print("waves: spawn timing")
	var runs: Array = _ref["timing"]["runs"]
	var differ: Array[String] = []
	var interval_ok: bool = true
	for entry: Dictionary in runs:
		var wave: int = int(entry["wave"])
		var scenario: RunScenario = RunScenario.new()
		scenario.seed = 6
		scenario.husk_count = 8
		scenario.first_wave_delay = 0.0
		scenario.crit_chance = 0.0
		var no_swords: Array[SwordSpec] = []
		scenario.loadout = no_swords
		var run: GameRun = GameRun.new(scenario)
		run.director.wave = wave - 1
		var marker_ticks: Array[int] = []
		var enemy_ticks: Array[int] = []
		var started: int = -1
		for tick_index: int in 420:
			_invulnerable(run)
			run.step()
			var tick: int = tick_index + 1
			if started < 0 and run.director.wave == wave:
				started = tick
			if started >= 0:
				var created: int = 8 - run.director.queue.size()
				while marker_ticks.size() < created:
					marker_ticks.append(tick - started)
				while enemy_ticks.size() < run.enemies.size():
					enemy_ticks.append(tick - started)
		if started != int(entry["started_at"]) or marker_ticks != _ints(entry["marker_ticks"]) or enemy_ticks != _ints(entry["enemy_ticks"]):
			differ.append("wave %d: %s / %s" % [wave, marker_ticks, enemy_ticks])
		interval_ok = interval_ok and _near(WaveDefs.spawn_interval(wave), maxf(0.12, 0.42 - 0.02 * float(wave)), 1e-12)
	_ok("markers appear 0.3 s after a wave starts and then every max(0.12, 0.42 - 0.02 w) s, and each enemy arrives 0.7 s after its marker, on the same ticks as the prototype for waves 1, 2, 3, 5, 10, 15, 19, 20, 21 and 30 (%d differ: %s)" % [differ.size(), differ.slice(0, 2)], differ.is_empty() and runs.size() == 10)
	_ok("the interval floors at 0.12 s from wave 15 and shrinks 0.02 s per wave before (waves 1, 14, 15, 16, 30: %s)" % [[WaveDefs.spawn_interval(1), WaveDefs.spawn_interval(14), WaveDefs.spawn_interval(15), WaveDefs.spawn_interval(16), WaveDefs.spawn_interval(30)]], interval_ok and _near(WaveDefs.spawn_interval(14), 0.14, 1e-9) and _near(WaveDefs.spawn_interval(15), 0.12, 1e-9) and _near(WaveDefs.spawn_interval(30), 0.12, 1e-9))


func _ints(values: Array) -> Array[int]:
	var converted: Array[int] = []
	for value: Variant in values:
		converted.append(int(value))
	return converted


# --------------------------------------------------------------- spawn points
func _check_spawn_points() -> void:
	print("waves: spawn positions")
	var points: Dictionary = _ref["spawn_points"]
	var wrong: Array[String] = []
	var singles: Array = points["single"]
	for case: Dictionary in singles:
		var found: Dictionary = _scripted_spawn(_vec(case["player"]), [[float(case["angle"]), float(case["distance"])]], true)
		if not _near(found["x"], float(case["x"]), POINT_TOL) or not _near(found["y"], float(case["y"]), POINT_TOL) or int(found["attempts"]) != int(case["attempts"]):
			wrong.append("player %s angle %.2f distance %.0f: (%.2f, %.2f) after %d" % [case["player"], case["angle"], case["distance"], found["x"], found["y"], found["attempts"]])
	_ok("a spawn point 420 to 720 px away is clamped 50 px inside the arena and refused within 320 px, exactly as the prototype for %d scripted attempts from 8 places (%d differ: %s)" % [singles.size(), wrong.size(), wrong.slice(0, 2)], wrong.is_empty() and singles.size() == 8 * 16 * 3)
	var mixed_wrong: Array[String] = []
	for case: Dictionary in points["mixed"]:
		var attempts: Array = []
		for i: int in int(case["bad_first"]):
			attempts.append([float(case["toward"]), 720.0])
		for i: int in 12:
			attempts.append([float(case["away"]), 500.0])
		attempts = attempts.slice(0, 12)
		var found: Dictionary = _scripted_spawn(_vec(case["player"]), attempts, false)
		if not _near(found["x"], float(case["x"]), POINT_TOL) or not _near(found["y"], float(case["y"]), POINT_TOL) or int(found["attempts"]) != int(case["attempts"]):
			mixed_wrong.append("%s after %d bad: (%.2f, %.2f) in %d" % [case["player"], case["bad_first"], found["x"], found["y"], found["attempts"]])
	_ok("refused attempts are redrawn and the first good one wins (%d of %d differ: %s)" % [mixed_wrong.size(), points["mixed"].size(), mixed_wrong.slice(0, 2)], mixed_wrong.is_empty() and points["mixed"].size() == 12)
	var fallback: Dictionary = points["fallback"]
	var fallback_attempts: Array = []
	for pair: Array in fallback["attempts_in"]:
		fallback_attempts.append([float(pair[0]), float(pair[1])])
	var fell: Dictionary = _scripted_spawn(_vec(fallback["player"]), fallback_attempts, false)
	_ok("twelve refused attempts in a row take the twelfth, however near (corner player: (%.1f, %.1f) after %d, the prototype's (%.1f, %.1f))" % [fell["x"], fell["y"], fell["attempts"], float(fallback["x"]), float(fallback["y"])],
		int(fell["attempts"]) == 12 and _near(fell["x"], float(fallback["x"]), POINT_TOL) and _near(fell["y"], float(fallback["y"]), POINT_TOL))
	# the unscripted distribution, from the director's own spawn step
	var spread_wrong: Array[String] = []
	var bounds: Dictionary = points["bounds"]
	var inner: Rect2 = GameRun.WORLD.grow(-float(bounds["margin"]))
	for entry: Dictionary in points["distribution"]:
		var run: GameRun = _rig(77)
		var player: Vector2 = _vec(entry["player"])
		run.position = player
		var n: int = int(entry["n"])
		var total: float = 0.0
		var dx: float = 0.0
		var dy: float = 0.0
		var nearest: float = INF
		var farthest: float = 0.0
		var near_count: int = 0
		var outside: int = 0
		for i: int in n:
			var point: Vector2 = run.director._spawn_point(run)
			var away: float = (point - player).length()
			total += away
			dx += point.x - player.x
			dy += point.y - player.y
			nearest = minf(nearest, away)
			farthest = maxf(farthest, away)
			near_count += 1 if away <= float(bounds["near_limit"]) else 0
			outside += 0 if point.x >= inner.position.x - 1e-6 and point.x <= inner.end.x + 1e-6 and point.y >= inner.position.y - 1e-6 and point.y <= inner.end.y + 1e-6 else 1
		if outside > 0 or farthest > float(bounds["max_distance"]) + 1e-6 or not _near(total / float(n), float(entry["mean"]), 8.0) or not _near(dx / float(n), float(entry["mean_dx"]), 12.0) or not _near(dy / float(n), float(entry["mean_dy"]), 12.0) or float(near_count) / float(n) > 0.01 or (nearest < float(bounds["min_distance"]) - 1e-6 and float(entry["min"]) >= float(bounds["min_distance"]) - 1.0):
			spread_wrong.append("%s: mean %.1f dx %.1f dy %.1f near %d outside %d min %.1f max %.1f" % [entry["player"], total / float(n), dx / float(n), dy / float(n), near_count, outside, nearest, farthest])
	_ok("unscripted spawns from the arena's middle, a corner and two walls stay inside the arena, within 720 px, on the prototype's side of the player and with its mean distance and drift (%d of 4 places differ: %s)" % [spread_wrong.size(), spread_wrong.slice(0, 1)], spread_wrong.is_empty() and points["distribution"].size() == 4)


func _vec(values: Array) -> Vector2:
	return Vector2(float(values[0]), float(values[1]))


## `WaveDefs.spawn_point` with scripted attempts ([angle, distance]); `repeat` replays the first attempt as every attempt.
func _scripted_spawn(player: Vector2, attempts: Array, repeat: bool) -> Dictionary:
	var used: Array[int] = [0]
	var next_draw: Callable = func() -> Vector2:
		var pair: Array = attempts[0] if repeat else attempts[mini(used[0], attempts.size() - 1)]
		used[0] += 1
		return Vector2(float(pair[0]), float(pair[1]))
	var point: Vector2 = WaveDefs.spawn_point(player, GameRun.WORLD, next_draw)
	return {"x": point.x, "y": point.y, "attempts": used[0]}


# --------------------------------------------------------------- distributions
func _check_distributions() -> void:
	print("waves: composition, arming and rarity over many waves")
	var failures: Array[String] = []
	var sampled: Array[String] = []
	for entry: Dictionary in _ref["distribution"]:
		var wave: int = int(entry["wave"])
		var waves: int = 600 if wave < 12 else 350
		var run: GameRun = _rig(4200 + wave)
		var kinds: Dictionary = {}
		var armed_by_kind: Dictionary = {}
		var rarity: Array[int] = [0, 0, 0]
		var brute_rarity: Array[int] = [0, 0, 0]
		var types: Dictionary = {}
		var elements: Dictionary = {}
		var total: int = 0
		var armed: int = 0
		var counts_equal: bool = true
		for i: int in waves:
			run.director.wave = wave - 1
			run.director._start_wave(run)
			var queue: Array[StringName] = run.director.queue
			var carried: Array[SwordSpec] = run.director.queue_armed
			counts_equal = counts_equal and queue.size() == WaveDefs.enemy_count(wave) and carried.size() == queue.size() and run.director.wave == wave
			for index: int in queue.size():
				var kind: StringName = queue[index]
				kinds[kind] = int(kinds.get(kind, 0)) + 1
				total += 1
				if carried[index] != null:
					var spec: SwordSpec = carried[index]
					armed += 1
					armed_by_kind[kind] = int(armed_by_kind.get(kind, 0)) + 1
					rarity[spec.rarity] += 1
					if kind == EnemyDefs.BRUTE:
						brute_rarity[spec.rarity] += 1
					types[spec.type_id] = int(types.get(spec.type_id, 0)) + 1
					elements[spec.element] = int(elements.get(spec.element, 0)) + 1
		var reference_total: int = int(entry["enemies"])
		var reference_armed: int = int(entry["armed"])
		if not counts_equal or not bool(entry["counts_equal"]):
			failures.append("wave %d: the wave size was not %d every time" % [wave, WaveDefs.enemy_count(wave)])
		for kind: String in ["husk", "runner", "spitter", "brute"]:
			var share: float = float(int(kinds.get(StringName(kind), 0))) / float(total)
			if not _share_agrees(share, total, float(entry["kind_share"][kind]), reference_total):
				failures.append("wave %d: %s share %.4f, prototype %.4f" % [wave, kind, share, float(entry["kind_share"][kind])])
			if entry["armed_by_kind"][kind] != null:
				var kind_count: int = int(kinds.get(StringName(kind), 0))
				var armed_share: float = float(int(armed_by_kind.get(StringName(kind), 0))) / float(maxi(1, kind_count))
				# wave 1's first two are armed for sure: leave them out of the husks' chance by comparing the overall share there
				if wave > 1 and not _share_agrees(armed_share, kind_count, float(entry["armed_by_kind"][kind]), int(entry["kinds"][kind])):
					failures.append("wave %d: %s armed %.4f, prototype %.4f" % [wave, kind, armed_share, float(entry["armed_by_kind"][kind])])
		if not _share_agrees(float(armed) / float(total), total, float(entry["armed_share"]), reference_total):
			failures.append("wave %d: armed share %.4f, prototype %.4f" % [wave, float(armed) / float(total), float(entry["armed_share"])])
		if armed > 0:
			for tier: int in 3:
				if not _share_agrees(float(rarity[tier]) / float(armed), armed, float(entry["rarity_share"][tier]), reference_armed):
					failures.append("wave %d: rarity %d share %.4f, prototype %.4f" % [wave, tier, float(rarity[tier]) / float(armed), float(entry["rarity_share"][tier])])
			var brute_armed: int = brute_rarity[0] + brute_rarity[1] + brute_rarity[2]
			if brute_armed > 100 and int(entry["brute_armed"]) > 100:
				for tier: int in 3:
					if not _share_agrees(float(brute_rarity[tier]) / float(brute_armed), brute_armed, float(entry["brute_rarity_share"][tier]), int(entry["brute_armed"])):
						failures.append("wave %d: brute rarity %d share %.4f, prototype %.4f" % [wave, tier, float(brute_rarity[tier]) / float(brute_armed), float(entry["brute_rarity_share"][tier])])
			for type_id: String in ["fang", "blade", "lance", "colossus"]:
				var godot_type: StringName = StringName(type_id)
				if not _share_agrees(float(int(types.get(godot_type, 0))) / float(armed), armed, float(entry["type_share"][type_id]), reference_armed):
					failures.append("wave %d: sword type %s share %.4f, prototype %.4f" % [wave, godot_type, float(int(types.get(godot_type, 0))) / float(armed), float(entry["type_share"][type_id])])
			for element: String in ["fire", "ice", "poison"]:
				if not _share_agrees(float(int(elements.get(StringName(element), 0))) / float(armed), armed, float(entry["element_share"][element]), reference_armed):
					failures.append("wave %d: element %s share %.4f, prototype %.4f" % [wave, element, float(int(elements.get(StringName(element), 0))) / float(armed), float(entry["element_share"][element])])
		sampled.append("%d:%.0f%%" % [wave, 100.0 * float(armed) / float(total)])
	_ok("over %d sampled waves each of waves 1, 2, 3, 4, 5, 8, 12, 20 and 30, every kind's share, how many arrive armed (overall and by kind: husk 20 %%, runner 12 %%, spitter 22 %%, brute 75 %%), the rarity mix (Mythic below min(0.25, 0.02 + 0.02 w), Rare below min(0.55, 0.16 + 0.04 w), brutes better), the sword types and the elements agree with the prototype's within sampling error (armed share by wave: %s; %d differ: %s)" % [600, sampled, failures.size(), failures.slice(0, 3)], failures.is_empty() and sampled.size() == 9)
	_ok("rarity progresses with the waves: Mythic and Rare grow until their caps (reference Mythic share at waves 1, 5, 12, 30: %s)" % [_rarity_progress()], _rarity_progress_ok())


func _rarity_progress() -> Array:
	var shares: Array = []
	for entry: Dictionary in _ref["distribution"]:
		if [1, 5, 12, 30].has(int(entry["wave"])):
			shares.append(snappedf(float(entry["rarity_share"][2]), 0.01))
	return shares


func _rarity_progress_ok() -> bool:
	var mythic: Array[float] = []
	for wave: int in [1, 5, 12, 30]:
		var run: GameRun = _rig(31)
		var count: int = 0
		var hits: int = 0
		for i: int in 400:
			run.director.wave = wave - 1
			run.director._start_wave(run)
			for spec: SwordSpec in run.director.queue_armed:
				if spec != null:
					count += 1
					hits += 1 if spec.rarity == 2 else 0
		mythic.append(float(hits) / float(maxi(1, count)))
	return mythic[0] < mythic[1] and mythic[1] < mythic[2] and mythic[2] < mythic[3] + 0.03 and mythic[3] < 0.36 and mythic[0] < 0.1


func _check_first_wave_guarantee() -> void:
	print("waves: the first wave's guaranteed Pike")
	var first: Dictionary = _ref["first_wave"]
	var pike_first: int = 0
	var second_armed: int = 0
	var arrived_pike: int = 0
	var arrived_hp_ok: int = 0
	var seeds: int = 40
	for seed_value: int in seeds:
		var run: GameRun = _rig(seed_value)
		var bound: int = 0
		while run.director.wave == 0 and bound < 400:
			run.step()
			bound += 1
		var carried: Array[SwordSpec] = run.director.queue_armed
		if carried.size() >= 2 and carried[0] != null and carried[0].type_id == SwordDefs.PIKE:
			pike_first += 1
		if carried.size() >= 2 and carried[1] != null:
			second_armed += 1
		_invulnerable(run)
		bound = 0
		while run.enemies.is_empty() and bound < 400:
			_invulnerable(run)
			run.step()
			bound += 1
		if not run.enemies.is_empty() and run.enemies[0].armed != null and run.enemies[0].armed.type_id == SwordDefs.PIKE:
			arrived_pike += 1
			arrived_hp_ok += 1 if _near(run.enemies[0].max_hp, 40.5, 1e-6) else 0
	_ok("on %d seeds the first enemy of the first wave is queued with a Pike and the second with some sword (the prototype: %d of %d and %d of %d)" % [seeds, int(first["first_wave_first_is_lance"]), int(first["seeds"]), int(first["first_wave_second_armed"]), int(first["seeds"])], pike_first == seeds and second_armed == seeds and int(first["first_wave_first_is_lance"]) == int(first["seeds"]) and int(first["first_wave_second_armed"]) == int(first["seeds"]))
	_ok("and that Pike arrives on the first enemy to appear, who carries it with 1.35 x the health (%d of %d)" % [arrived_pike, seeds], arrived_pike == seeds and arrived_hp_ok == seeds)
	# later waves guarantee nothing: the first enemy of wave 2 is unarmed about as often as the prototype's
	var unarmed_first: int = 0
	var lance_first: int = 0
	var trials: int = 600
	var run: GameRun = _rig(88)
	for i: int in trials:
		run.director.wave = 1
		run.director._start_wave(run)
		unarmed_first += 1 if run.director.queue_armed[0] == null else 0
		lance_first += 1 if run.director.queue_armed[0] != null and run.director.queue_armed[0].type_id == SwordDefs.PIKE else 0
	_ok("wave 2's first enemy is armed by chance only (unarmed %d of %d, Pike %d; the prototype's %d and %d of %d)" % [unarmed_first, trials, lance_first, int(first["second_wave_first_unarmed"]), int(first["second_wave_first_lance"]), int(first["seeds"])],
		_share_agrees(float(unarmed_first) / float(trials), trials, float(first["second_wave_first_unarmed"]) / float(first["seeds"]), int(first["seeds"])) and _share_agrees(float(lance_first) / float(trials), trials, float(first["second_wave_first_lance"]) / float(first["seeds"]), int(first["seeds"])))


# --------------------------------------------------------------- completion and breaks
func _check_completion() -> void:
	print("waves: completion and breaks")
	var waits: Dictionary = _ref["waits"]
	var wrong: Array[String] = []
	for case: Dictionary in waits["combinations"]:
		var run: GameRun = _rig(3)
		run.director.wave = 2
		run.director.in_wave = true
		run.director.spawn_timer = 5.0
		if bool(case["queue"]):
			var queued: Array[StringName] = [EnemyDefs.HUSK]
			var carried: Array[SwordSpec] = [null]
			run.director.queue = queued
			run.director.queue_armed = carried
		if bool(case["marker"]):
			run.director.markers.append(SpawnMarker.make(EnemyDefs.HUSK, Vector2(100.0, 100.0)))
		if bool(case["enemy"]):
			run.enemies.append(_husk_at(Vector2(2000.0, 1700.0), 3))
		run.director.update(run, GameRun.TICK_DT)
		var cleared: bool = run.banner_title == "WAVE CLEARED"
		if run.director.in_wave != bool(case["in_wave"]) or run.director.wave != int(case["wave"]) or cleared != (case["banner"] == "WAVE CLEARED"):
			wrong.append("queue %s marker %s enemy %s: in_wave %s" % [case["queue"], case["marker"], case["enemy"], run.director.in_wave])
	_ok("a wave completes only when its queue, its telegraphed markers and its living enemies are all gone: each of the 8 combinations of the three agrees with the prototype (%d differ: %s)" % [wrong.size(), wrong.slice(0, 2)], wrong.is_empty() and waits["combinations"].size() == 8)
	var corpse_run: GameRun = _rig(4)
	corpse_run.director.wave = 2
	corpse_run.director.in_wave = true
	var corpse: EnemyState = _husk_at(Vector2(2000.0, 1700.0), 3)
	corpse.dead = true
	corpse_run.enemies.append(corpse)
	corpse_run.director.update(corpse_run, GameRun.TICK_DT)
	_ok("a corpse still in the enemy list holds the wave open, as the prototype's loop does until its dead are filtered out", bool(waits["corpse_in_list_holds_wave"]) and corpse_run.director.in_wave)

	var trace: Dictionary = _ref["clear_and_break"]
	var run: GameRun = _rig(9)
	run.director.wave = 1
	run.director.in_wave = true
	var last: EnemyState = _husk_at(Vector2(2200.0, 1700.0), 1)
	run.enemies.append(last)
	for i: int in 30:
		_invulnerable(run)
		run.step()
	_ok("with an enemy standing, thirty ticks later the wave is still on", run.director.in_wave and run.enemies.size() == 1)
	run.kills = 7
	run.kill(last, Vector2.RIGHT)
	var cleared_at: int = -1
	var next_at: int = -1
	var at_clear: Dictionary = {}
	var at_next: Dictionary = {}
	var samples: Array = []
	for tick_index: int in 900:
		_invulnerable(run)
		run.step()
		var tick: int = tick_index + 1
		if cleared_at < 0 and not run.director.in_wave:
			cleared_at = tick
			at_clear = _wave_state(run)
		if cleared_at >= 0 and [0, 30, 60, 120].has(tick - cleared_at):
			samples.append([tick - cleared_at, run.director.break_left, run.slowmo])
		if cleared_at >= 0 and run.director.wave == 2:
			next_at = tick
			at_next = _wave_state(run)
			break
	var ref_clear: Dictionary = trace["at_clear"]
	_ok("the last kill completes the wave on the next tick with the banner, the 0.7 s slow motion at x0.3 and a 3.2 s break (%s)" % [at_clear],
		cleared_at == int(trace["cleared_at_tick"]) and not at_clear.is_empty() and not bool(at_clear["in_wave"]) and int(at_clear["queue"]) == 0 and int(at_clear["markers"]) == 0 and int(at_clear["enemies"]) == 0 and _near(float(at_clear["break"]), float(ref_clear["break_t"]), TIMER_TOL)
		and _near(float(at_clear["slowmo"]), float(ref_clear["slowmo"]), TIMER_TOL) and float(at_clear["slowmo_scale"]) == float(ref_clear["slowmo_scale"]) and at_clear["banner"] == ref_clear["banner"][0] and at_clear["sub"] == ref_clear["banner"][1] and _near(float(at_clear["banner_left"]), float(ref_clear["banner"][2]), TIMER_TOL))
	var trace_ok: bool = samples.size() == 4
	for i: int in mini(samples.size(), 4):
		var wanted: Array = trace["break_trace"][i]
		trace_ok = trace_ok and int(samples[i][0]) == int(wanted[0]) and _near(float(samples[i][1]), float(wanted[1]), 1e-5) and _near(float(samples[i][2]), float(wanted[2]), 1e-5)
	_ok("the break counts down in slowed time through the slow motion and in full time after it (%s)" % [samples], trace_ok)
	var ref_next: Dictionary = trace["at_next_wave"]
	_ok("the next wave starts %d ticks after the clear (the prototype's %d) with wave 2's 11 enemies queued, its marker timer at 0.3 s and its banner" % [next_at - cleared_at, int(trace["next_wave_after_ticks"])],
		next_at - cleared_at == int(trace["next_wave_after_ticks"]) and at_next["queue"] == int(trace["next_wave_queue"]) and _near(run.director.spawn_timer, float(trace["next_wave_spawn_timer"]), TIMER_TOL) and at_next["banner"] == ref_next["banner"][0] and at_next["sub"] == ref_next["banner"][1] and bool(at_next["in_wave"]))

	var fresh: GameRun = _rig(10)
	var first_at: int = -1
	var first_state: Dictionary = {}
	for tick_index: int in 400:
		fresh.step()
		if fresh.director.wave == 1:
			first_at = tick_index + 1
			first_state = _wave_state(fresh)
			break
	var ref_first: Dictionary = trace["first_wave_state"]
	_ok("a fresh run waits 1.6 s and starts wave 1 on tick %d (the prototype's %d) with 8 enemies queued and its banner" % [first_at, int(trace["first_wave_after_ticks"])],
		first_at == int(trace["first_wave_after_ticks"]) and first_state["queue"] == int(ref_first["queue"]) and first_state["banner"] == ref_first["banner"][0] and first_state["sub"] == ref_first["banner"][1] and _near(float(first_state["break"]), float(ref_first["break_t"]), TIMER_TOL))
	var banners: Dictionary = _ref["banners"]
	_ok("the two banners' texts are the prototype's own: '%s' / '%s' and '%s' / '%s'" % [WaveDefs.WAVE_BANNER_SUB, WaveDefs.CLEARED_BANNER_SUB, banners["started"][0], banners["cleared"][0]],
		WaveDefs.WAVE_BANNER_SUB == banners["started"][1] and WaveDefs.CLEARED_BANNER_SUB == banners["cleared"][1] and first_state["banner"] == banners["started"][0] and at_clear["banner"] == banners["cleared"][0])


func _wave_state(run: GameRun) -> Dictionary:
	return {"in_wave": run.director.in_wave, "wave": run.director.wave, "queue": run.director.queue.size(), "markers": run.director.markers.size(), "enemies": run.enemies.size(),
		"break": run.director.break_left, "slowmo": run.slowmo, "slowmo_scale": run.slowmo_scale, "banner": run.banner_title, "sub": run.banner_sub, "banner_left": run.banner_left}


func _check_freeze() -> void:
	print("waves: pause and hitstop freeze the wave machine")
	var freeze: Dictionary = _ref["freeze"]
	var run: GameRun = _rig(12)
	run.director.wave = 3
	run.director.in_wave = true
	var queued: Array[StringName] = [EnemyDefs.HUSK, EnemyDefs.HUSK, EnemyDefs.HUSK, EnemyDefs.HUSK]
	var carried: Array[SwordSpec] = [null, null, null, null]
	run.director.queue = queued
	run.director.queue_armed = carried
	run.director.spawn_timer = 1.0
	_invulnerable(run)
	run.step()
	var before: float = run.director.spawn_timer
	run.apply(GameCommand.pause())
	_steps(run, 60)
	var paused: float = run.director.spawn_timer
	run.apply(GameCommand.resume())
	run.hitstop = 0.5
	_steps(run, 20)
	var hitstop: float = run.director.spawn_timer
	run.hitstop = 0.0
	run.step()
	var spawn: Dictionary = freeze["spawn_timer"]
	_ok("the spawn timer does not move while paused (%.4f -> %.4f) or in hitstop (%.4f) and moves again after (%.4f); the prototype's %s" % [before, paused, hitstop, run.director.spawn_timer, spawn],
		_near(before, float(spawn["before"]), TIMER_TOL) and _near(paused, float(spawn["paused"]), TIMER_TOL) and _near(hitstop, float(spawn["hitstop"]), TIMER_TOL) and _near(run.director.spawn_timer, float(spawn["after"]), TIMER_TOL))
	var brk: GameRun = _rig(13)
	brk.director.wave = 3
	brk.director.in_wave = false
	brk.director.break_left = 2.0
	_invulnerable(brk)
	brk.step()
	var break_before: float = brk.director.break_left
	brk.apply(GameCommand.pause())
	_steps(brk, 60)
	var break_paused: float = brk.director.break_left
	brk.apply(GameCommand.resume())
	brk.hitstop = 0.5
	_steps(brk, 20)
	var break_hitstop: float = brk.director.break_left
	brk.hitstop = 0.0
	brk.slowmo = 5.0
	brk.slowmo_scale = 0.3
	brk.step()
	var slowed_step: float = break_hitstop - brk.director.break_left
	var timer: Dictionary = freeze["break_timer"]
	_ok("the break timer is frozen the same way (%.4f -> %.4f -> %.4f) and runs at 0.3 x in slow motion (a step of %.4f s, the prototype's %.4f)" % [break_before, break_paused, break_hitstop, slowed_step, float(timer["slowed_step"])],
		_near(break_before, float(timer["before"]), TIMER_TOL) and _near(break_paused, float(timer["paused"]), TIMER_TOL) and _near(break_hitstop, float(timer["hitstop"]), TIMER_TOL) and _near(slowed_step, float(timer["slowed_step"]), 1e-6))


# --------------------------------------------------------------- death and restart
func _check_death_and_restart() -> void:
	print("waves: death and restart")
	var reference: Dictionary = _ref["death_and_restart"]
	var dead_ref: Dictionary = reference["dead"]
	var run: GameRun = _rig(13)
	run.director.wave = 3
	run.director.in_wave = true
	var queued: Array[StringName] = [EnemyDefs.HUSK, EnemyDefs.HUSK, EnemyDefs.HUSK, EnemyDefs.HUSK, EnemyDefs.HUSK]
	var carried: Array[SwordSpec] = [null, null, null, null, null]
	run.director.queue = queued
	run.director.queue_armed = carried
	run.director.spawn_timer = 0.0
	run.director.markers.append(SpawnMarker.make(EnemyDefs.HUSK, Vector2(100.0, 100.0)))
	var standing: EnemyState = _husk_at(Vector2(2000.0, 1700.0), 3)
	run.enemies.append(standing)
	run.hurt_player(1000, run.position + Vector2(50.0, 0.0))
	var marker_before: float = run.director.markers[0].remaining
	_steps(run, 120)
	_ok("with the player dead nothing spawns, nothing is telegraphed further and the wave neither ends nor advances (queue %d, marker %.3f -> %.3f, wave %d, in wave %s)" % [run.director.queue.size(), marker_before, run.director.markers[0].remaining, run.director.wave, run.director.in_wave],
		run.dead and bool(dead_ref["dead"]) and run.director.queue.size() == int(dead_ref["queue_after"]) and _near(run.director.markers[0].remaining, float(dead_ref["marker_t_after"]), TIMER_TOL) and _near(marker_before, float(dead_ref["marker_t_before"]), TIMER_TOL)
		and run.director.markers.size() == int(dead_ref["markers"]) and run.director.in_wave == bool(dead_ref["in_wave"]) and run.director.wave == int(dead_ref["wave"]))
	var empty: GameRun = _rig(14)
	empty.director.wave = 3
	empty.director.in_wave = true
	empty.hurt_player(1000, empty.position + Vector2(50.0, 0.0))
	_steps(empty, 300)
	var empty_ref: Dictionary = reference["dead_empty_field"]
	_ok("a dead player's empty field does not complete the wave or show a banner", empty.director.in_wave == bool(empty_ref["in_wave"]) and empty.director.wave == int(empty_ref["wave"]) and empty.banner_title.is_empty() and empty_ref["banner"] == null)

	var played: GameRun = _rig(14)
	played.director.wave = 6
	played.director.in_wave = true
	played.kills = 40
	played.combo = 12
	played.best_combo = 18
	played.combo_left = 1.0
	played.director.queue = queued.duplicate()
	played.director.markers.append(SpawnMarker.make(EnemyDefs.HUSK, Vector2(100.0, 100.0)))
	played.enemies.append(_husk_at(Vector2(2000.0, 1700.0), 6))
	played.projectiles.append(ProjectileState.make(Vector2(10.0, 10.0), Vector2(1.0, 0.0)))
	played.pickups.append(PickupState.make(SwordSpec.make(SwordDefs.FANG, 0, &"fire"), Vector2(10.0, 10.0), 1))
	played.motes.append(Mote.scatter(Vector2(20.0, 20.0), played.rng))
	played.set_banner("WAVE 6", 2.0, "x")
	played.hp = 30.0
	played.apply(GameCommand.restart())
	var ref_reset: Dictionary = reference["reset"]
	var reset_ok: bool = played.director.wave == int(ref_reset["wave"]) and played.director.in_wave == bool(ref_reset["in_wave"]) and _near(played.director.break_left, float(ref_reset["break_t"]), 1e-9) and played.kills == int(ref_reset["kills"]) and played.combo == int(ref_reset["combo"]) \
		and played.best_combo == int(ref_reset["best_combo"]) and played.combo_left == float(ref_reset["combo_t"]) and played.director.queue.size() == int(ref_reset["queue"]) and played.director.markers.size() == int(ref_reset["markers"]) and played.enemies.size() == int(ref_reset["enemies"]) \
		and played.projectiles.size() == int(ref_reset["projectiles"]) and played.pickups.size() == int(ref_reset["pickups"]) and played.motes.size() == int(ref_reset["motes"]) and played.banner_title.is_empty() and played.banner_sub.is_empty() and played.banner_left == 0.0 and played.hp == float(ref_reset["hp"]) and played.dead == bool(ref_reset["dead"])
	_ok("a restart puts every run-owned thing back as the prototype's reset does: wave 0, 1.6 s to the first wave, no kills, chain or best chain, no queue, markers, enemies, orbs, drops, motes or banner, full health", reset_ok)
	var again: int = -1
	for tick_index: int in 400:
		played.step()
		if played.director.wave == 1:
			again = tick_index + 1
			break
	_ok("and wave 1 comes again after the same 1.6 s (tick %d) with the first wave's 8 enemies, husks only" % again, again == int(_ref["clear_and_break"]["first_wave_after_ticks"]) and played.director.queue.size() == 8 and played.director.queue.all(func(kind: StringName) -> bool: return kind == EnemyDefs.HUSK))
	# the R key restarts only a dead player after the death delay; the restart clears the wave machine the same way
	var keyed: GameRun = _rig(15)
	_steps(keyed, 120)
	keyed.hurt_player(1000, keyed.position + Vector2(20.0, 0.0))
	keyed.apply(GameCommand.restart_from_key())
	var too_early: bool = keyed.dead and keyed.restarts == 0
	_steps(keyed, 120)
	keyed.apply(GameCommand.restart_from_key())
	_ok("R restarts a dead run only after the death delay, and the wave machine starts over (wave %d, %.1f s)" % [keyed.director.wave, keyed.director.break_left], too_early and keyed.restarts == 1 and not keyed.dead and keyed.director.wave == 0 and _near(keyed.director.break_left, 1.6, 1e-9))
	# the dev cycle returns to the same normal run: waves of the prototype, armed
	var cycle: GameRun = GameRun.new()
	_ok("a run made with no scenario is the normal run: the prototype's waves, forever, armed", cycle.scenario.generated_waves and cycle.scenario.arm_waves and cycle.scenario.wave_count == 0 and cycle.scenario.encounter == RunScenario.ENCOUNTER_NORMAL and cycle.outcome() == GameRun.Outcome.RUNNING)


# --------------------------------------------------------------- counters
func _check_counters() -> void:
	print("waves: kills, chain and healing")
	var kills: Dictionary = _ref["kills"]
	var run: GameRun = _rig(21)
	var trace_ok: bool = true
	var detail: String = ""
	var wanted: Dictionary = {}
	for entry: Dictionary in kills["trace"]:
		wanted[int(entry["n"])] = entry
	var chain_cues: Array[int] = []
	for n: int in range(1, 131):
		run.kill(_husk_at(Vector2(2200.0, 1700.0), 1), Vector2.RIGHT)
		if wanted.has(n):
			var entry: Dictionary = wanted[n]
			var same: bool = run.kills == int(entry["kills"]) and run.combo == int(entry["combo"]) and run.best_combo == int(entry["best"]) and _near(run.combo_left, float(entry["combo_t"]), 1e-9) and run.motes.size() == int(entry["motes"])
			trace_ok = trace_ok and same
			if not same:
				detail += "kill %d: kills %d combo %d best %d window %.2f motes %d; " % [n, run.kills, run.combo, run.best_combo, run.combo_left, run.motes.size()]
	for cue: SimCue in run.take_cues():
		if cue.kind == SimCue.Kind.CHAIN_MILESTONE:
			chain_cues.append(cue.amount)
	_ok("each kill counts once, extends the chain, restarts its 2.6 s window and leaves three healing motes, as the prototype's `kill` over 130 kills (%s)" % detail, trace_ok and wanted.size() == 12)
	var chains: Array[int] = []
	for entry: Dictionary in kills["chain_texts"]:
		chains.append(int(entry["combo"]))
	_ok("the chain announces itself at 10, 25, 50 and 100 and nowhere else (%s; the prototype's %s)" % [chain_cues, chains], chain_cues == chains and chains == [10, 25, 50, 100])
	var decay: Dictionary = kills["decay"]
	var decayed: GameRun = _rig(22)
	decayed.kill(_husk_at(Vector2(2200.0, 1700.0), 1), Vector2.RIGHT)
	var reset_at: int = -1
	for tick_index: int in 400:
		_invulnerable(decayed)
		decayed.step()
		if decayed.combo == 0 and reset_at < 0:
			reset_at = tick_index + 1
	_ok("a chain ends %d ticks after its last kill (the prototype's %d), keeping the kills and the best chain" % [reset_at, int(decay["reset_at_tick"])], reset_at == int(decay["reset_at_tick"]) and decayed.kills == int(decay["kills"]) and decayed.best_combo == int(decay["best"]))
	var extend: Dictionary = kills["extend"]
	var extended: GameRun = _rig(23)
	extended.kill(_husk_at(Vector2(2200.0, 1700.0), 1), Vector2.RIGHT)
	_steps(extended, 120)
	var mid: int = extended.combo
	extended.kill(_husk_at(Vector2(2200.0, 1700.0), 1), Vector2.RIGHT)
	_ok("a kill inside the window extends the chain and restarts the window (%d -> %d, %.1f s)" % [mid, extended.combo, extended.combo_left], mid == int(extend["combo_mid"]) and extended.combo == int(extend["combo_after"]) and _near(extended.combo_left, float(extend["combo_t_after"]), 1e-9))
	var best: Dictionary = kills["best_kept"]
	var kept: GameRun = _rig(24)
	for i: int in 5:
		kept.kill(_husk_at(Vector2(2200.0, 1700.0), 1), Vector2.RIGHT)
	for i: int in 200:
		_invulnerable(kept)
		kept.step()
	_ok("the best chain survives the chain's end (%d now, best %d)" % [kept.combo, kept.best_combo], kept.combo == int(best["combo"]) and kept.best_combo == int(best["best"]) and kept.kills == int(best["kills"]))


func _check_healing() -> void:
	print("waves: healing in a normal run")
	var healing: Dictionary = _ref["healing"]
	var run: GameRun = _rig(22)
	run.hp = 50.0
	var enemy: EnemyState = _husk_at(run.position + Vector2(40.0, 0.0), 1)
	run.enemies.append(enemy)
	run.kill(enemy, Vector2.RIGHT)
	var motes: int = run.motes.size()
	_steps(run, 240)
	_ok("a kill leaves %d motes and each heals half a point when it arrives (health 50 -> %.2f, the prototype's %.2f, %d motes left)" % [motes, run.hp, float(healing["one_kill"]["hp_after"]), run.motes.size()], motes == int(healing["one_kill"]["motes_per_kill"]) and _near(run.hp, float(healing["one_kill"]["hp_after"]), 1e-6) and run.motes.is_empty())
	var capped: GameRun = _rig(22)
	capped.hp = 99.8
	var near_enemy: EnemyState = _husk_at(capped.position + Vector2(40.0, 0.0), 1)
	capped.enemies.append(near_enemy)
	capped.kill(near_enemy, Vector2.RIGHT)
	_steps(capped, 240)
	_ok("healing stops at full health (%.1f)" % capped.hp, capped.hp == float(healing["capped"]["hp_after"]) and capped.hp == capped.max_hp)
	var dead: GameRun = _rig(22)
	dead.hp = 50.0
	var last: EnemyState = _husk_at(dead.position + Vector2(40.0, 0.0), 1)
	dead.enemies.append(last)
	dead.kill(last, Vector2.RIGHT)
	dead.hurt_player(1000, dead.position + Vector2(50.0, 0.0))
	_steps(dead, 240)
	_ok("motes never heal a dead player", dead.dead and dead.hp == float(healing["dead_not_healed"]["hp_after"]))


# --------------------------------------------------------------- the progression, played with controlled outcomes
## Plays the normal run through `waves` waves, killing every enemy the moment it arrives (a controlled outcome: no sword
## fights, so the composition and timing are the wave machine's own) and recording what each wave was.
func _play_waves(seed_value: int, waves: int) -> Dictionary:
	var run: GameRun = _rig(seed_value)
	var record: Dictionary = {"run": run, "waves": [], "starved": 0, "held_open": true, "break_ticks": [], "armed_kills": 0, "max_hp_ok": true, "problems": [] as Array[String]}
	var wave_info: Dictionary = {}
	var cleared_at: int = -1
	var bound: int = waves * 1800 + 600
	var hp_rows: Dictionary = {}
	for row: Dictionary in _ref["hp"]["rows"]:
		hp_rows["%s:%d" % [row["kind"], int(row["wave"])]] = row
	for tick_index: int in bound:
		_invulnerable(run)
		var wave_before: int = run.director.wave
		run.step()
		if run.director.wave != wave_before:
			if cleared_at >= 0:
				record["break_ticks"].append(tick_index - cleared_at)
				cleared_at = -1
			if wave_info.has("wave"):
				record["problems"].append("wave %d began before wave %d was cleared" % [run.director.wave, wave_info["wave"]])
			if run.director.wave > waves:
				break
			wave_info = {"wave": run.director.wave, "queued": run.director.queue.duplicate(), "armed": run.director.queue_armed.filter(func(spec: SwordSpec) -> bool: return spec != null).size(), "killed": [], "armed_killed": 0, "spawned": 0}
		for enemy: EnemyState in run.enemies:
			if enemy.dead:
				continue
			var row: Dictionary = hp_rows.get("%s:%d" % [enemy.kind, run.director.wave], {})
			var expected_hp: float = float(row["armed"] if enemy.armed != null else row["unarmed"]) if not row.is_empty() else -1.0
			if expected_hp < 0.0 or not _near(enemy.max_hp, expected_hp, EPS):
				record["problems"].append("%s in wave %d has %.3f health, not %.3f" % [enemy.kind, run.director.wave, enemy.max_hp, expected_hp])
			if not wave_info.has("killed"):
				record["problems"].append("an enemy arrived in wave %d after the wave had been completed" % run.director.wave)
				wave_info = {"wave": run.director.wave, "queued": [], "armed": 0, "killed": [], "armed_killed": 0, "spawned": 0}
			wave_info["killed"].append(enemy.kind)
			wave_info["armed_killed"] += 1 if enemy.armed != null else 0
			run.kill(enemy, Vector2.RIGHT)
		if wave_info.has("wave") and not run.director.in_wave:
			cleared_at = tick_index
			record["waves"].append(wave_info)
			wave_info = {}
	record["tick"] = run.tick
	return record


func _check_progression() -> void:
	print("waves: the normal run, wave after wave")
	var played: Dictionary = _play_waves(7, 9)
	var run: GameRun = played["run"]
	var waves: Array = played["waves"]
	var problems: Array[String] = played["problems"]
	_ok("nine waves were played through with every enemy killed as it arrived (%d completed, %d problems: %s)" % [waves.size(), problems.size(), problems.slice(0, 3)], waves.size() == 9 and problems.is_empty())
	var sizes_ok: bool = true
	var unlock_ok: bool = true
	var seen: Dictionary = {}
	var total_kills: int = 0
	var armed_total: int = 0
	var queue_ok: bool = true
	var first_wave_kinds: String = ""
	for entry: Dictionary in waves:
		var wave: int = int(entry["wave"])
		var killed: Array = entry["killed"]
		total_kills += killed.size()
		armed_total += int(entry["armed_killed"])
		sizes_ok = sizes_ok and killed.size() == WaveDefs.enemy_count(wave) and (entry["queued"] as Array).size() == killed.size()
		queue_ok = queue_ok and int(entry["armed_killed"]) == int(entry["armed"])
		var pool: Array[StringName] = WaveDefs.pool_kinds(wave)
		for kind: Variant in killed:
			seen[kind] = true
			unlock_ok = unlock_ok and pool.has(StringName(kind))
		if wave == 1:
			first_wave_kinds = _kinds_in(killed)
	_ok("each wave brings 5 + 3 w enemies (%d kills in all) and every one is of a kind its wave has unlocked: husks only in wave 1, no spitter before wave 3 (wave 1: %s...)" % [total_kills, first_wave_kinds.left(24)], sizes_ok and unlock_ok and total_kills == 8 + 11 + 14 + 17 + 20 + 23 + 26 + 29 + 32 and run.kills == total_kills)
	_ok("the full enemy variety shows up: %s were fought in nine waves" % [seen.keys()], seen.size() == 4)
	_ok("the arrivals are exactly what each wave queued, armed ones included (%d armed foes killed, each killed enemy's health carries 1.35 x when armed)" % armed_total, queue_ok and armed_total >= 2)
	_ok("every armed kill left its sword where it fell: %d drops for %d armed kills" % [run.cue_count(SimCue.Kind.SWORD_DROPPED), armed_total], run.cue_count(SimCue.Kind.SWORD_DROPPED) == armed_total)
	var breaks: Array = played["break_ticks"]
	var breaks_ok: bool = breaks.size() == 9
	for ticks: int in breaks:
		breaks_ok = breaks_ok and ticks == int(_ref["clear_and_break"]["next_wave_after_ticks"])
	_ok("every break between waves lasts the same %d ticks as the prototype's (%s)" % [int(_ref["clear_and_break"]["next_wave_after_ticks"]), breaks], breaks_ok)
	var first: Dictionary = waves[0]
	_ok("the first wave is 8 husks of which at least the first two carried swords", first["queued"].size() == 8 and first["queued"].all(func(kind: StringName) -> bool: return kind == EnemyDefs.HUSK) and int(first["armed"]) >= 2)
	_ok("the best chain is the biggest wave's kills when they come within the 2.6 s window (%d)" % run.best_combo, run.best_combo == 32)
	# the loot variety of a normal run: over twelve controlled waves every sword type, every rarity and every element is carried
	var types: Dictionary = {}
	var rarities: Dictionary = {}
	var elements: Dictionary = {}
	var loot_run: GameRun = _rig(8)
	for wave: int in range(1, 13):
		loot_run.director.wave = wave - 1
		loot_run.director._start_wave(loot_run)
		for spec: SwordSpec in loot_run.director.queue_armed:
			if spec != null:
				types[spec.type_id] = true
				rarities[spec.rarity] = true
				elements[spec.element] = true
	_ok("twelve waves arm foes with all four sword types, all three rarities and all three elements (%s / %s / %s)" % [types.keys(), rarities.keys(), elements.keys()], types.size() == 4 and rarities.size() == 3 and elements.size() == 3)
	var outcome: GameRun = _rig(9)
	_steps(outcome, 60)
	_ok("the normal run has no end: it is never survived, only lost", outcome.outcome() == GameRun.Outcome.RUNNING and not outcome.director.survived)


func _check_no_cap() -> void:
	print("waves: nothing caps the enemies")
	var scenario: RunScenario = RunScenario.normal_run()
	scenario.seed = 61
	scenario.enemy_speed_scale = 0.0
	scenario.crit_chance = 0.0
	var no_swords: Array[SwordSpec] = []
	scenario.loadout = no_swords
	var run: GameRun = GameRun.new(scenario)
	run.director.wave = 29
	run.director.break_left = 0.0
	var size: int = WaveDefs.enemy_count(30)
	var peak: int = 0
	var queued_kinds: Array[StringName] = []
	for tick_index: int in 1500:
		_invulnerable(run)
		run.step()
		if queued_kinds.is_empty() and run.director.wave == 30:
			queued_kinds = run.director.queue.duplicate()
		peak = maxi(peak, run.enemies.size())
		if run.director.queue.is_empty() and run.director.markers.is_empty() and run.director.wave == 30:
			break
	var kinds_standing: Array[StringName] = []
	for enemy: EnemyState in run.enemies:
		kinds_standing.append(enemy.kind)
	_ok("wave 30 puts all %d of its enemies in the arena at once (%d standing, queue %d, markers %d)" % [size, run.enemies.size(), run.director.queue.size(), run.director.markers.size()], size == 95 and run.enemies.size() == size and peak == size and queued_kinds.size() == size)
	var first_kinds: Array[StringName] = queued_kinds.duplicate()
	var standing_sorted: Array[String] = []
	var queued_sorted: Array[String] = []
	for kind: StringName in kinds_standing:
		standing_sorted.append(String(kind))
	for kind: StringName in first_kinds:
		queued_sorted.append(String(kind))
	standing_sorted.sort()
	queued_sorted.sort()
	_ok("they are exactly the kinds that wave queued, none dropped or added", standing_sorted == queued_sorted)
	var hp_ok: bool = run.enemies.all(func(enemy: EnemyState) -> bool: return _near(enemy.max_hp, EnemyDefs.of(enemy.kind).hp * (1.0 + 0.1 * 29.0) * (LootDefs.ARMED_HP_FACTOR if enemy.armed != null else 1.0), 1e-6))
	_ok("and every one has wave 30's health (x3.9, x1.35 more when armed): the balance does not change with depth", hp_ok)
	run.enemies.clear()
	_steps(run, 2)
	_ok("an arena full of them still completes the wave only when all are gone (cleared once emptied: %s)" % not run.director.in_wave, not run.director.in_wave)


# --------------------------------------------------------------- the normal first wave against the prototype's
func _check_normal_first_wave() -> void:
	print("waves: the normal run's armed first wave clears like the prototype's")
	var reference: Dictionary = _ref["normal_first_wave"]
	for variant: String in ["no_input", "converge_every_3s"]:
		var entries: Array = reference[variant]
		var lowest: float = INF
		var highest: float = 0.0
		var sure: bool = entries.size() == 8
		var armed_low: int = 99
		var armed_high: int = 0
		for entry: Dictionary in entries:
			lowest = minf(lowest, float(entry["cleared_at"]))
			highest = maxf(highest, float(entry["cleared_at"]))
			armed_low = mini(armed_low, int(entry["armed_enemies"]))
			armed_high = maxi(armed_high, int(entry["armed_enemies"]))
			sure = sure and int(entry["kills"]) == 8 and not bool(entry["died"]) and int(entry["swords_lying"]) == int(entry["armed_enemies"]) and bool(entry["first_enemy_armed"]) and String(entry["first_enemy_sword"]) == "lance"
		_ok("%s: the prototype's reference is the armed first wave: 8 kills on 8 seeds, a Pike on the first enemy, as many swords lying as foes were armed (%d to %d), cleared between %.2f and %.2f s" % [variant, armed_low, armed_high, lowest, highest], sure and armed_low >= 2)
		var all_survived: bool = true
		var in_band: bool = true
		var armed_in_range: bool = true
		var swords_lying: bool = true
		var piked: bool = true
		var converges: int = 0
		var lowest_hp: float = 100.0
		var times: Array[float] = []
		var armed_counts: Array[int] = []
		for seed_value: int in range(1, 9):
			var scenario: RunScenario = RunScenario.normal_run()
			scenario.seed = seed_value
			var run: GameRun = GameRun.new(scenario)
			var ticks_taken: int = 0
			var armed_queued: int = -1
			while ticks_taken < 60 * 90 and not run.dead:
				if variant == "converge_every_3s" and ticks_taken % 180 == 179 and not run.enemies.is_empty():
					var before: int = run.cue_count(SimCue.Kind.CONVERGE)
					run.apply(GameCommand.converge_at_nearest())
					converges += run.cue_count(SimCue.Kind.CONVERGE) - before
				run.step()
				ticks_taken += 1
				if armed_queued < 0 and run.director.wave == 1:
					armed_queued = run.director.queue_armed.filter(func(spec: SwordSpec) -> bool: return spec != null).size()
					piked = piked and run.director.queue_armed[0] != null and run.director.queue_armed[0].type_id == SwordDefs.PIKE
				if run.director.wave >= 1 and not run.director.in_wave:
					break
			var seconds: float = float(ticks_taken) / 60.0
			times.append(snappedf(seconds, 0.01))
			armed_counts.append(armed_queued)
			all_survived = all_survived and not run.dead and run.kills == 8 and run.director.wave == 1 and not run.director.in_wave
			in_band = in_band and seconds > lowest - FIRST_WAVE_BAND and seconds < highest + FIRST_WAVE_BAND
			armed_in_range = armed_in_range and armed_queued >= 2 and armed_queued <= 8
			swords_lying = swords_lying and run.pickups.size() == armed_queued
			lowest_hp = minf(lowest_hp, run.hp)
		_ok("%s: the normal run clears its armed first wave on all 8 seeds with all 8 kills and never dies (lowest health %.1f)" % [variant, lowest_hp], all_survived and lowest_hp > 40.0)
		_ok("%s: it is cleared within the prototype's band %.1f-%.1f s +-%.0f s (ours: %s)" % [variant, lowest, highest, FIRST_WAVE_BAND, times], in_band)
		_ok("%s: 2 to 8 foes arrive armed (%s), a Pike on the first, and every armed kill's sword is lying when the wave is cleared" % [variant, armed_counts], armed_in_range and piked and swords_lying)
		if variant == "converge_every_3s":
			var reference_converges: int = 0
			for entry: Dictionary in entries:
				reference_converges += int(entry["converged"])
			_ok("a player who only clicks lands about as many Converges (%d over 8 runs, the prototype's %d)" % [converges, reference_converges], absi(converges - reference_converges) <= 8)


# --------------------------------------------------------------- the fixtures keep their own rules
func _check_fixtures_unchanged() -> void:
	print("waves: the earlier fixtures keep their own waves")
	var fixtures: Array[RunScenario] = [RunScenario.new(), RunScenario.fang_fixture(), RunScenario.crowd_encounter(), RunScenario.spitter_encounter(), RunScenario.conditions_encounter(), RunScenario.warden_encounter(), RunScenario.pike_encounter(), RunScenario.colossus_encounter(), RunScenario.wall_encounter()]
	var names: Array[String] = []
	var ok: bool = true
	for fixture: RunScenario in fixtures:
		ok = ok and not fixture.generated_waves and not fixture.arm_waves and fixture.wave_count == 1
		names.append("%s" % fixture.encounter)
	_ok("the plain scenario and every dev encounter except the drops one still play one unarmed wave of their own composition (%s)" % [names], ok)
	var drops: RunScenario = RunScenario.drops_encounter()
	_ok("the drops encounter keeps its own composition and arms it, as before", drops.arm_waves and not drops.generated_waves and drops.wave_kinds.size() == 10 and drops.wave_count == 1)
	var normal: RunScenario = RunScenario.normal_run()
	_ok("only the normal run generates waves: it keeps the prototype's default loadout and start (%d swords, first wave after %.1f s)" % [normal.loadout.size(), normal.first_wave_delay], normal.generated_waves and normal.arm_waves and normal.wave_count == 0 and normal.loadout.size() == 3 and normal.first_wave_delay == 1.6 and normal.crit_chance == 0.12 and normal.conditions_enabled)
	var survived: GameRun = GameRun.new(RunScenario.crowd_encounter())
	var bound: int = 0
	while survived.director.wave == 0 and bound < 400:
		survived.step()
		bound += 1
	var plain: GameRun = GameRun.new(RunScenario.fang_fixture())
	bound = 0
	while plain.director.wave == 0 and bound < 400:
		plain.step()
		bound += 1
	_ok("an unarmed fixture's banner has no second line about armed foes ('%s', '%s'): that line belongs to the armed normal run" % [plain.banner_title, plain.banner_sub], plain.banner_title == "WAVE 1" and plain.banner_sub.is_empty())
	var cleared: GameRun = GameRun.new(RunScenario.fang_fixture())
	cleared.director.wave = 1
	cleared.director.in_wave = true
	cleared.director.update(cleared, GameRun.TICK_DT)
	_ok("and its cleared banner has none either ('%s', '%s')" % [cleared.banner_title, cleared.banner_sub], cleared.banner_title == "WAVE CLEARED" and cleared.banner_sub.is_empty())
	_ok("a fixture's single wave composition is still its own (the crowd's 12: %d queued, kinds %s)" % [survived.director.queue.size(), _kinds_in(survived.director.queue.slice(0, 3))], survived.director.queue.size() == 12 and survived.director.queue.has(EnemyDefs.BRUTE) and survived.director.queue.has(EnemyDefs.RUNNER))


# --------------------------------------------------------------- the HUD
func _main_with(scenario: RunScenario, enemy_scene: String = "", sword_scene: String = "", actor_scene: String = "") -> Main:
	var main: Main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Main
	main.scenario = scenario
	if not enemy_scene.is_empty():
		main.enemy_visual = load(enemy_scene)
	if not sword_scene.is_empty():
		main.sword_visual = load(sword_scene)
	if not actor_scene.is_empty():
		main.actor_visual = load(actor_scene)
	_tree.root.add_child(main)
	main.set_physics_process(false)
	return main


func _tick_main(main: Main, count: int) -> void:
	for i: int in count:
		main.run.iframes = HEALED_FULL
		main._physics_process(GameRun.TICK_DT)


func _check_hud() -> void:
	print("waves: what the HUD shows in a normal run")
	var hud_ref: Dictionary = _ref["hud"]
	var scenario: RunScenario = RunScenario.normal_run()
	scenario.seed = 72
	var main: Main = _main_with(scenario)
	await _tree.process_frame
	var run: GameRun = main.run
	var hud: Hud = main._hud
	_tick_main(main, 2)
	_ok("before the first wave the HUD reads WAVE 1, kills 0 (%s), the prototype's '%s' and '%s'" % [hud._wave_label.text, hud_ref["start"][0]["text"], hud_ref["start"][1]["text"]],
		hud._wave_label.text.begins_with(String(hud_ref["start"][0]["text"])) and hud._wave_label.text.contains(String(hud_ref["start"][1]["text"])) and not hud._wave_label.text.contains("chain"))
	var started: int = 0
	while run.director.wave == 0 and started < 400:
		_tick_main(main, 1)
		started += 1
	await _tree.process_frame
	var banners: Dictionary = _ref["banners"]
	_ok("when wave 1 starts the banner names it and says what to do ('%s' / '%s'), full strength then fading" % [hud._banner_label.text, hud._banner_sub_label.text],
		hud._banner_label.text == banners["started"][0] and hud._banner_sub_label.text == banners["started"][1] and hud._banner_label.modulate.a >= 0.99 and hud._banner_sub_label.modulate.a >= 0.99)
	_tick_main(main, 100)
	var fading: float = run.banner_left
	_ok("in its last second the banner and its second line fade together (left %.2f s: alpha %.2f and %.2f)" % [fading, hud._banner_label.modulate.a, hud._banner_sub_label.modulate.a], fading > 0.0 and fading < 1.0 and _near(hud._banner_label.modulate.a, fading, 0.02) and _near(hud._banner_sub_label.modulate.a, fading, 0.02))
	_tick_main(main, 50)
	_ok("after its 2.4 s the banner is gone", hud._banner_label.text == "" and hud._banner_sub_label.text == "")
	run.kills = 123
	run.director.wave = 7
	run.combo = 5
	run.combo_left = 1.3
	_tick_main(main, 1)
	var running: Array = hud_ref["running"]
	_ok("the wave, kill and chain readouts say '%s' (the prototype draws '%s', '%s', '%s')" % [hud._wave_label.text, running[0]["text"], running[1]["text"], running[2]["text"]],
		hud._wave_label.text.begins_with(String(running[0]["text"])) and hud._wave_label.text.contains(String(running[1]["text"])) and hud._wave_label.text.contains("chain 5"))
	run.combo = 3
	_tick_main(main, 1)
	_ok("a chain of three is the first to show ('%s')" % hud._wave_label.text, hud._wave_label.text.contains("chain 3"))
	run.combo = 2
	_tick_main(main, 1)
	_ok("a chain of two shows no chain readout, as the prototype's x counter begins at three", not hud._wave_label.text.contains("chain"))
	# the game over statistics line
	run.director.wave = 9
	run.kills = 211
	run.best_combo = 37
	run.hurt_player(1000, run.position + Vector2(30.0, 0.0))
	run.iframes = 0.0
	run.hurt_player(1000, run.position + Vector2(30.0, 0.0))
	_tick_main(main, 150)
	var over: Array = hud_ref["game_over"]
	_ok("the game over screen reads '%s' / '%s' / '%s' (the prototype: '%s' / '%s' / '%s')" % [hud._outcome_title.text, hud._outcome_detail.text, hud._outcome_prompt.text, over[0]["text"], over[1]["text"], over[2]["text"]],
		run.dead and hud._outcome_title.text == String(over[0]["text"]) and hud._outcome_detail.text == String(over[1]["text"]) and hud._outcome_prompt.text.begins_with(String(over[2]["text"])))
	main.queue_free()
	await _tree.process_frame


## The banner and its second line sit clear of the live HUD at several window sizes, and inside the view.
func _check_banner_clearance() -> void:
	print("waves: the banner keeps clear of the HUD")
	var window: Window = Window.new()
	window.size = Vector2i(1280, 720)
	window.content_scale_size = Vector2i(1280, 720)
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	_tree.root.add_child(window)
	var hud: Hud = Hud.new()
	window.add_child(hud)
	await _tree.process_frame
	var run: GameRun = _rig(5)
	run.set_banner("WAVE CLEARED", 2.6, WaveDefs.CLEARED_BANNER_SUB)
	var covered: Array[String] = []
	var outside: Array[String] = []
	var checked: int = 0
	var fewest: int = 1 << 20
	for size: Vector2i in [Vector2i(1280, 720), Vector2i(1084, 720), Vector2i(1000, 563), Vector2i(1920, 1080), Vector2i(800, 1280), Vector2i(1280, 1024)]:
		window.size = size
		hud.show_state(false, false)
		await _tree.process_frame
		await _tree.process_frame
		hud.show_run(run)
		var view: Rect2 = window.get_visible_rect()
		var banner_rects: Array[Rect2] = [_text_rect(hud._banner_label), _text_rect(hud._banner_sub_label)]
		if banner_rects[0].grow(4.0).intersects(banner_rects[1]):
			covered.append("%s: the banner's two lines overlap %s %s" % [size, banner_rects[0], banner_rects[1]])
		var live: Array[Rect2] = []
		var shown_over: Array[Control] = [hud._pickup_card, hud._stick, hud._banner_label, hud._banner_sub_label, hud._outcome_shade, hud._outcome_title, hud._outcome_detail, hud._outcome_prompt, hud._pause_overlay]
		for child: Node in hud.get_child(0).get_children():
			var control: Control = child as Control
			if control == null or not control.visible or shown_over.has(control):
				continue
			var rect: Rect2 = _text_rect(control) if control is Label else control.get_global_rect()
			if rect.has_area():
				live.append(rect)
		fewest = mini(fewest, live.size())
		for rect: Rect2 in banner_rects:
			checked += 1
			if not view.grow(0.5).encloses(rect):
				outside.append("%s: %s in %s" % [size, rect, view])
			for other: Rect2 in live:
				if rect.intersects(other):
					covered.append("%s: banner %s over %s" % [size, rect, other])
	_ok("the banner and its second line lie inside the view at six window sizes (%d texts, %d outside: %s)" % [checked, outside.size(), outside.slice(0, 2)], outside.is_empty() and checked == 12)
	_ok("and cover no live HUD element: health, readouts, buttons, the wave line, the sword cards (%d covered: %s; at least %d live elements walked)" % [covered.size(), covered.slice(0, 2), fewest], covered.is_empty() and fewest >= 12)
	# the pickup card steps aside for the banner: with a drop in reach and the banner up, the card covers neither of its lines
	var worst: SwordSpec = SwordSpec.make(SwordDefs.COLOSSUS, 2, &"poison")
	var card_run: GameRun = _rig(6)
	card_run.set_banner("WAVE CLEARED", 2.6, WaveDefs.CLEARED_BANNER_SUB)
	var half: Vector2 = GameRun.VIEW * 0.5 - Vector2(GameRun.CAMERA_OVERSCAN, GameRun.CAMERA_OVERSCAN)
	var cases: int = 0
	var over_banner: Array[String] = []
	var card_outside: Array[String] = []
	var moved_for_banner: int = 0
	for size: Vector2i in [Vector2i(1280, 720), Vector2i(1000, 563), Vector2i(1920, 1080), Vector2i(800, 1280)]:
		window.size = size
		hud.show_state(false, false)
		await _tree.process_frame
		await _tree.process_frame
		var view: Rect2 = window.get_visible_rect()
		var places: Array[Vector2] = []
		for x: float in [30.0, 640.0, 1300.0, 2000.0, 2570.0]:
			for y: float in [30.0, 360.0, 900.0, 1500.0, 1770.0]:
				places.append(Vector2(x, y))
		for place: Vector2 in places:
			card_run.pickups.clear()
			card_run.position = place
			card_run.camera = place.clamp(GameRun.WORLD.position + half, GameRun.WORLD.end - half)
			card_run.pickups.append(PickupState.make(worst, place + Vector2(10.0, 0.0), 1))
			hud.show_run(card_run)
			cases += 1
			var card: Rect2 = hud.pickup_card_rect()
			var drop_screen: Vector2 = card_run.pickups[0].position - card_run.camera + view.size * 0.5
			var shown: Array[Rect2] = [_text_rect(hud._banner_label), _text_rect(hud._banner_sub_label)]
			for rect: Rect2 in shown:
				if card.intersects(rect):
					over_banner.append("%s: card %s over the banner line %s (player %s)" % [size, card, rect, place])
			if not view.grow(0.5).encloses(card):
				card_outside.append("%s: card %s (player %s)" % [size, card, place])
			var ideal: Vector2 = (drop_screen + Vector2(40.0, -Hud.PICKUP_CARD_SIZE.y - 40.0)).clamp(Vector2(Hud.PICKUP_CARD_MARGIN, Hud.PICKUP_CARD_MARGIN), (view.size - Hud.PICKUP_CARD_SIZE - Vector2(Hud.PICKUP_CARD_MARGIN, Hud.PICKUP_CARD_MARGIN)).max(Vector2(Hud.PICKUP_CARD_MARGIN, Hud.PICKUP_CARD_MARGIN)))
			if not card.position.is_equal_approx(ideal):
				moved_for_banner += 1
	_ok("with the banner up and a drop in reach the pickup card covers neither of its lines in %d cases (4 window sizes x 25 places; %d over it: %s) and stays inside the view (%d outside)" % [cases, over_banner.size(), over_banner.slice(0, 2), card_outside.size()], over_banner.is_empty() and card_outside.is_empty() and cases == 100)
	_ok("the card really does move for the banner: it is off its ideal spot in %d of %d cases" % [moved_for_banner, cases], moved_for_banner > 10)
	window.queue_free()
	await _tree.process_frame


## The rectangle a label's text occupies (a label that fills its parent draws its text in the middle of it).
func _text_rect(control: Control) -> Rect2:
	var label: Label = control as Label
	if label == null or label.text.is_empty():
		return control.get_global_rect() if label == null else Rect2()
	var size: Vector2 = label.get_minimum_size()
	var rect: Rect2 = label.get_global_rect()
	var left: float = rect.position.x
	match label.horizontal_alignment:
		HORIZONTAL_ALIGNMENT_CENTER:
			left = rect.position.x + (rect.size.x - size.x) * 0.5
		HORIZONTAL_ALIGNMENT_RIGHT:
			left = rect.end.x - size.x
	var top: float = rect.position.y
	if label.vertical_alignment == VERTICAL_ALIGNMENT_CENTER:
		top = rect.position.y + (rect.size.y - size.y) * 0.5
	return Rect2(Vector2(left, top), size)


# --------------------------------------------------------------- the real Main scene
func _check_main_scene() -> void:
	print("waves: the real Main scene plays the normal run")
	var scenario: RunScenario = RunScenario.normal_run()
	scenario.seed = 73
	scenario.crit_chance = 0.0
	var main: Main = _main_with(scenario)
	await _tree.process_frame
	main._sfx.unlock()
	main._sfx.played.clear()
	var run: GameRun = main.run
	var presenter: RunPresenter = main._presenter
	var effects: EffectsLayer = presenter._effects
	var bound: int = 0
	while run.director.wave == 0 and bound < 400:
		_tick_main(main, 1)
		bound += 1
	await _tree.process_frame
	_ok("the wave gong sounds when wave 1 starts", main._sfx.played.has("wave"))
	var markers_seen: int = 0
	var armed_marker: int = 0
	var drawn_before: int = 0
	bound = 0
	while run.enemies.is_empty() and bound < 200:
		_tick_main(main, 1)
		markers_seen = maxi(markers_seen, run.director.markers.size())
		for marker: SpawnMarker in run.director.markers:
			armed_marker += 1 if marker.armed != null else 0
		bound += 1
	await _tree.process_frame
	_ok("a spawn warning stands where each enemy will appear before it does (%d telegraphed at once; the first, armed with a Pike, was one of them)" % markers_seen, markers_seen >= 1 and armed_marker >= 1)
	# let the whole first wave arrive, then check what is on screen
	bound = 0
	while (not run.director.queue.is_empty() or not run.director.markers.is_empty()) and bound < 900:
		_tick_main(main, 1)
		bound += 1
	await _tree.process_frame
	var armed_standing: int = run.enemies.filter(func(enemy: EnemyState) -> bool: return enemy.armed != null).size()
	var visuals: int = 0
	var armed_visuals: int = 0
	for child: Node in presenter.get_children():
		if child is PlaceholderEnemyVisual:
			visuals += 1
			armed_visuals += 1 if (child as PlaceholderEnemyVisual)._armed != null else 0
	_ok("every enemy of the wave is drawn, the armed ones carrying their swords (%d visuals for %d enemies, %d armed visuals for %d armed)" % [visuals, run.enemies.size(), armed_visuals, armed_standing], visuals == run.enemies.size() and run.enemies.size() >= 6 and armed_visuals == armed_standing and armed_standing >= 2)
	# kill them in a chain: the announcement, the counters and the drops
	var ahead: int = run.kills
	for enemy: EnemyState in run.enemies.duplicate():
		run.kill(enemy, Vector2.RIGHT)
	_tick_main(main, 2)
	await _tree.process_frame
	var killed: int = run.kills - ahead
	var wave_text: String = main._hud._wave_label.text
	_ok("the kills and the chain are on the HUD ('%s'), and the %d armed foes standing then, and every armed death so far, left their swords lying (%d lying, %d drop cues)" % [wave_text, armed_standing, run.pickups.size(), run.cue_count(SimCue.Kind.SWORD_DROPPED)], wave_text.contains("kills %d" % run.kills) and (killed < 3 or wave_text.contains("chain %d" % run.combo)) and run.pickups.size() == run.cue_count(SimCue.Kind.SWORD_DROPPED) and run.pickups.size() >= armed_standing)
	run.director.wave = 3
	var big_chain: GameRun = run
	for i: int in 12:
		big_chain.kill(_husk_at(big_chain.position + Vector2(300.0, 0.0), 3), Vector2.RIGHT)
	_tick_main(main, 2)
	await _tree.process_frame
	_ok("a chain of ten announces itself above the player (the CHAIN text is on the effects layer: %s)" % [effects._texts.any(func(text: Dictionary) -> bool: return String(text["text"]) == "10 CHAIN!")],
		effects._texts.any(func(text: Dictionary) -> bool: return String(text["text"]) == "10 CHAIN!" and int(text["size"]) == 56 and (text["color"] as Color).is_equal_approx(Color(1.0, 0.78, 0.35)) and _near(float(text["max"]), 1.4, 1e-9) and (text["vel"] as Vector2).y < -30.0 and (text["vel"] as Vector2).y > -40.0 and absf((text["vel"] as Vector2).x) < 1e-9 and _near(((text["pos"] as Vector2) - big_chain.position).y, -60.0 - 0.0, 3.0)))
	# the clear: banner, slow motion, drops
	for enemy: EnemyState in run.enemies.duplicate():
		run.kill(enemy, Vector2.RIGHT)
	_tick_main(main, 3)
	await _tree.process_frame
	bound = 0
	while run.director.in_wave and bound < 900:
		for enemy: EnemyState in run.enemies.duplicate():
			run.kill(enemy, Vector2.RIGHT)
		_tick_main(main, 1)
		bound += 1
	await _tree.process_frame
	_ok("clearing the wave shows WAVE CLEARED and what to do next ('%s' / '%s') and the slow motion starts" % [main._hud._banner_label.text, main._hud._banner_sub_label.text], main._hud._banner_label.text == "WAVE CLEARED" and main._hud._banner_sub_label.text == WaveDefs.CLEARED_BANNER_SUB and run.slowmo > 0.0)
	# restart through the real button drops everything of the run
	main._hud.restart_pressed.emit()
	await _tree.process_frame
	_ok("restarting frees every enemy, marker and drop visual and the banner (%d enemy visuals, wave %d, banner '%s')" % [presenter.get_children().filter(func(child: Node) -> bool: return child is EnemyVisual).size(), run.director.wave, main._hud._banner_label.text],
		presenter.get_children().filter(func(child: Node) -> bool: return child is EnemyVisual).is_empty() and presenter.pickup_visual_count() == 0 and run.director.wave == 0 and run.enemies.is_empty() and run.pickups.is_empty())
	main.queue_free()
	await _tree.process_frame


# --------------------------------------------------------------- visuals and cosmetic randomness
func _check_visual_independence() -> void:
	print("waves: replacing the visuals and the cosmetic randomness leaves the normal run unchanged")
	var hosts: Array[Main] = []
	for use_alt: bool in [false, true]:
		var scenario: RunScenario = RunScenario.normal_run()
		scenario.seed = 74
		hosts.append(_main_with(scenario, "res://tests/alt_enemy.tscn" if use_alt else "", "res://tests/alt_sword.tscn" if use_alt else "", "res://tests/alt_actor.tscn" if use_alt else ""))
	await _tree.process_frame
	hosts[0]._fx_rng.seed = 1
	hosts[1]._fx_rng.seed = 99999
	var results: Array[Dictionary] = []
	for main: Main in hosts:
		for tick_index: int in 1500:
			if tick_index % 60 == 5:
				main.run.apply(GameCommand.move_axis(Vector2(cos(float(tick_index) / 120.0), sin(float(tick_index) / 120.0))))
			if tick_index % 180 == 179 and not main.run.enemies.is_empty():
				main.run.apply(GameCommand.converge_at_nearest())
			main.run.iframes = maxf(main.run.iframes, 0.0)
			main._physics_process(GameRun.TICK_DT)
		var digest: Dictionary = main.run.snapshot()
		digest.erase("restarts")
		digest["pickups"] = main.run.pickups.map(func(pickup: PickupState) -> Array: return [pickup.position, SwordDefs.full_name(pickup.spec), snappedf(pickup.life, 0.0001)])
		digest["kinds"] = main.run.enemies.map(func(enemy: EnemyState) -> String: return String(enemy.kind))
		digest["queue"] = main.run.director.queue.map(func(kind: StringName) -> String: return String(kind))
		digest["armed_queue"] = main.run.director.queue_armed.map(func(spec: SwordSpec) -> String: return "" if spec == null else SwordDefs.full_name(spec))
		results.append(digest)
	_ok("the same normal run, 25 s into wave 2, with a stretched, rotated enemy, sword and actor visual and a different cosmetic random stream, ends in the same state (wave %s, kills %s, %d drops)" % [results[0]["wave"], results[0]["kills"], (results[0]["pickups"] as Array).size()],
		results[0] == results[1] and int(results[0]["kills"]) >= 8 and int(results[0]["wave"]) >= 1)
	_ok("and the effects really were different: the cosmetic streams are not the gameplay one", hosts[0]._fx_rng.state != hosts[1]._fx_rng.state and hosts[0].run.rng.state == hosts[1].run.rng.state)
	for main: Main in hosts:
		main.queue_free()
	await _tree.process_frame
