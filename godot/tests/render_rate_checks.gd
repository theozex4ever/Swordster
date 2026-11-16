class_name RenderRateChecks
extends RefCounted
## The one place where the engine's frame rate is varied (issue #41). Every simulation outcome must be
## independent of how the frames around the fixed 60 Hz ticks are cut: `Main` steps the simulation from the
## engine's physics loop and the presentation only reads it. That property lives in shared code (the tick loop,
## `GameRun.step`, the cue queue the presentation drains), not in any one slice, so ONE scripted fight proves it:
## `CombinedFight` plays every sword type (Fang, Warden, Colossus, and a Pike swapped in), every
## ultimate (Viper Flurry, Maelstrom, Skewer, Cataclysm) and Converge, every enemy type, all three conditions,
## fields, orbs and parries, a bowled crowd and wall slams, drops and swaps. The checks play it with bare
## `GameRun.step()` calls, then through the real Main scene in a child Godot process at each of
## PROBE_FRAME_RATES frames per second (the engine runs three 1/60 s ticks per frame at 20 fps and one tick every
## four frames at 240 fps) and require the same digest. The child processes run at the same time, each bounded by a
## deadline, so the whole group costs about as much as one of them. The launch options (`--encounter=`) are
## checked in child processes too, because their arguments are only read at engine start.
##
## Every check here starts with `RenderRateScenario.probes_enabled()` (see run_checks.gd's switches), so the
## mutation checker's quick steps skip it, as they skipped the nine per-slice probes it replaced.

const PROBE_SCRIPT: String = "res://tests/frame_rate_probe.gd"
const PROBE_FRAME_RATES: Array[int] = [5, 20, 60, 240]
## Wall-clock limit of a batch of child processes: the longest probe takes a few seconds, so a child still running
## after this is hung; it is killed and the check fails instead of waiting for ever.
const PROBE_DEADLINE_MSEC: int = 120000
const POLL_MSEC: int = 20
## How many child Godot processes run at once (the machine they run on is shared).
const MAX_CHILDREN: int = 4

var _check: Callable
var _tree: SceneTree


func _init(check_function: Callable, tree: SceneTree) -> void:
	_check = check_function
	_tree = tree


func run_all() -> void:
	if not CheckFocus.includes("render_rate"):
		return
	if not RenderRateScenario.probes_enabled():
		return
	print("render rates: identical outcomes at low and high render rates")
	_check_combined_fight()
	_check_launch_options()


func _ok(label: String, condition: bool, detail: String = "") -> void:
	_check.call(label, condition, detail)


# ------------------------------------------------------------ the combined fight
func _check_combined_fight() -> void:
	var played: Dictionary = CombinedFight.play()
	var headless: Dictionary = played["digest"]
	# Probe output travels as JSON text, so compare both sides after the same round trip.
	var expected_digest: Dictionary = JSON.parse_string(JSON.stringify(headless))
	for coverage: Array in CombinedFight.coverage_failures(played):
		_ok(String(coverage[0]), false, String(coverage[1]))
	_ok("the combined fight covers everything it is meant to (%s)" % CombinedFight.coverage_summary(played), CombinedFight.coverage_failures(played).is_empty())
	_ok("exactly once: kills equal kill cues", int(headless["kills"]) == int(headless["kill_cues"]))
	var arguments: Array[PackedStringArray] = []
	for rate: int in PROBE_FRAME_RATES:
		arguments.append(PackedStringArray(["--fixed-fps", str(rate), "--script", PROBE_SCRIPT, "--", "--probe=rate"]))
	var runs: Array[Dictionary] = _run_children(arguments)
	var frames: Dictionary[int, int] = {}
	for i: int in PROBE_FRAME_RATES.size():
		var rate: int = PROBE_FRAME_RATES[i]
		var run: Dictionary = runs[i]
		var line: String = _probe_line(String(run["output"]))
		_ok("the engine played the combined fight at %d fps (exit %d)" % [rate, int(run["code"])], int(run["code"]) == 0 and not line.is_empty(), String(run["output"]))
		if line.is_empty():
			continue
		var result: Dictionary = JSON.parse_string(line)
		frames[rate] = int(result["frames"])
		var comparable: Dictionary = result.duplicate()
		for key: String in ["frames", "visuals", "enemies", "pickup_visuals"]:
			comparable.erase(key)
		_ok("at %d fps the real Main scene ends the fight exactly like the bare simulation: same hits, deaths, conditions, fields, orbs, drops, swaps, positions, phases and recharges" % rate, comparable == expected_digest, _first_difference(comparable, expected_digest))
		_ok("at %d fps every kill is rewarded exactly once and every living enemy and lying sword has its visual (kills %d, kill cues %d, alive %d, visuals %d, pickups %d, pickup visuals %d)" % [rate, int(result["kills"]), int(result["kill_cues"]), int(result["enemies"]), int(result["visuals"]), (result["pickups"] as Array).size(), int(result["pickup_visuals"])],
			int(result["kills"]) == int(result["kill_cues"]) and int(result["visuals"]) == int(result["enemies"]) + 3 and int(result["pickup_visuals"]) == (result["pickups"] as Array).size())
	_ok("the rates really differed: the engine drew %s frames for the same %d ticks" % [frames, CombinedFight.TOTAL_TICKS],
		frames.size() == PROBE_FRAME_RATES.size() and frames[5] < frames[20] and frames[20] < frames[60] and frames[60] < frames[240])


# ------------------------------------------------------------ launch options
## `--encounter=<name>` is read from the command line when the engine starts, so each case is a child process.
func _check_launch_options() -> void:
	var cases: Array[String] = ["crowd", "wall", "spitters", "nonsense"]
	var arguments: Array[PackedStringArray] = []
	for encounter: String in cases:
		arguments.append(PackedStringArray(["--script", PROBE_SCRIPT, "--", "--probe=launch", "--encounter=%s" % encounter]))
	# A launch without any option at all: the normal husk wave.
	arguments.append(PackedStringArray(["--script", PROBE_SCRIPT, "--", "--probe=launch"]))
	var runs: Array[Dictionary] = _run_children(arguments)
	for i: int in cases.size():
		var encounter: String = cases[i]
		var line: String = _probe_line(String(runs[i]["output"]))
		var launched: Dictionary = JSON.parse_string(line) if not line.is_empty() else {}
		if encounter == "crowd" or encounter == "wall":
			var standing: int = RunScenario.WALL_CROWD_KINDS.size() if encounter == "wall" else 0
			_ok("the launch option --encounter=%s starts that encounter" % encounter, bool(launched.get("dev_shove", false)) and int(launched.get("standing", -1)) == standing, String(runs[i]["output"]))
		elif encounter == "spitters":
			_ok("the launch option --encounter=spitters starts the spitter encounter", String(launched.get("encounter", "")) == "spitters" and int(launched.get("wave_kinds", 0)) == 8 and not bool(launched.get("dev_shove", true)), String(runs[i]["output"]))
		else:
			_ok("an unknown launch option starts the normal husk wave", launched.has("dev_shove") and not bool(launched["dev_shove"]) and int(launched["wave_kinds"]) == 0 and int(launched["standing"]) == 0, String(runs[i]["output"]))
	var plain_line: String = _probe_line(String(runs[cases.size()]["output"]))
	var plain: Dictionary = JSON.parse_string(plain_line) if not plain_line.is_empty() else {}
	_ok("a missing launch option starts the normal husk wave", plain.has("dev_shove") and not bool(plain["dev_shove"]) and int(plain["wave_kinds"]) == 0 and int(plain["standing"]) == 0, String(runs[cases.size()]["output"]))


# ------------------------------------------------------------ child processes
## Runs one headless Godot per argument list on this project, at most MAX_CHILDREN at the same time (the next one
## starts as soon as one ends), and returns, in the order of the lists, the exit `code` and the `output` text of
## each. Running them together is what keeps this group at about the cost of its slowest children instead of the
## sum. The whole batch is bounded by PROBE_DEADLINE_MSEC: a child still running by then is killed (code -1) and
## the ones not yet started never run (code -1), so a hang fails a check instead of hanging the suite. Each
## child's output is read after it ends, so it must stay below a pipe buffer (64 KB): a probe prints one JSON line.
func _run_children(argument_lists: Array[PackedStringArray]) -> Array[Dictionary]:
	var executable: String = OS.get_executable_path()
	var project: String = ProjectSettings.globalize_path("res://")
	var results: Array[Dictionary] = []
	var pipes: Dictionary[int, FileAccess] = {}
	var pids: Dictionary[int, int] = {}
	for i: int in argument_lists.size():
		results.append({"code": -1, "output": "not started: the batch ran out of time"})
	var next: int = 0
	var running: Array[int] = []
	var started: int = Time.get_ticks_msec()
	while (next < argument_lists.size() or not running.is_empty()) and Time.get_ticks_msec() - started < PROBE_DEADLINE_MSEC:
		while next < argument_lists.size() and running.size() < MAX_CHILDREN:
			var full: PackedStringArray = PackedStringArray(["--headless", "--path", project])
			full.append_array(argument_lists[next])
			var child: Dictionary = OS.execute_with_pipe(executable, full)
			if child.is_empty():
				results[next] = {"code": -1, "output": "the child process could not start"}
			else:
				pids[next] = int(child["pid"])
				pipes[next] = child["stdio"] as FileAccess
				running.append(next)
			next += 1
		OS.delay_msec(POLL_MSEC)
		for index: int in running.duplicate():
			if not OS.is_process_running(pids[index]):
				results[index] = {"code": OS.get_process_exit_code(pids[index]), "output": _drain(pipes[index])}
				running.erase(index)
	for index: int in running:
		OS.kill(pids[index])
		results[index] = {"code": -1, "output": "killed after %d ms" % PROBE_DEADLINE_MSEC}
	return results


func _drain(pipe: FileAccess) -> String:
	var text: String = ""
	while pipe != null and pipe.is_open() and not pipe.eof_reached():
		var line: String = pipe.get_line()
		if line.is_empty() and pipe.eof_reached():
			break
		text += line + "\n"
	return text


func _probe_line(output: String) -> String:
	for line: String in output.split("\n"):
		if line.begins_with("PROBE {"):
			return line.trim_prefix("PROBE ")
	return ""


func _first_difference(a: Dictionary, b: Dictionary) -> String:
	for key: Variant in a:
		if JSON.stringify(a[key]) != JSON.stringify(b.get(key)):
			return "%s: %s vs %s" % [key, a[key], b.get(key)]
	return ""
