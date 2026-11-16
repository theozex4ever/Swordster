class_name RenderRateChecks
extends RefCounted
## The one place where the engine's frame rate is varied (issue #41). Every simulation outcome must be
## independent of how the frames around the fixed 60 Hz ticks are cut: `Main` steps the simulation from the
## engine's physics loop and the presentation only reads it. That property lives in shared code (the tick loop,
## `GameRun.step`, the cue queue the presentation drains), not in any one slice, so ONE scripted fight proves it.
## `CombinedFight` plays every sword type (Fang, Warden, Colossus, and a Pike swapped in), every ultimate (Viper
## Flurry, Maelstrom, Skewer, Cataclysm) and Converge, every enemy type (standing in packs, and four stalkers that walk
## across the arena), all three conditions, fields, orbs and parries, a bowled crowd and wall slams, drops and swaps; then
## restarts into the normal run and plays a wave transition (spawn markers, arrival, clear with its slow motion, the
## break, the next wave). The checks play it with bare `GameRun.step()` calls, then through the real Main scene in a
## child Godot process at each of PROBE_FRAME_RATES frames per second (the engine runs three 1/60 s ticks per frame at 20
## fps and one tick every four frames at 240 fps) and require the same state on EVERY tick (a chained per-tick fingerprint), at every checkpoint and at the end. The state
## is `GameRun.state_digest()`: the whole run by reflection, so a member nobody listed anywhere is compared too. The child
## processes run at the same time, each bounded by a deadline, so the whole group costs about as much as one of them.
## The launch options (`--encounter=`) are checked in child processes too, because their arguments are only read at
## engine start. Every child must also END cleanly: exit status 0 and its output, never one without the other.
##
## The checks on the digest itself (what it leaves out, that every member of the run changes it) are cheap and run
## first, in every run of this group; the probes are the expensive part.
##
## Every probe here starts with `RenderRateScenario.probes_enabled()` (see run_checks.gd's switches), so the
## mutation checker's quick steps skip it, as they skipped the nine per-slice probes it replaced.

const PROBE_SCRIPT: String = "res://tests/frame_rate_probe.gd"
const PROBE_FRAME_RATES: Array[int] = [5, 20, 60, 240]
## Wall-clock limit of a batch of child processes: the longest probe takes a few seconds, so a child still running
## after this is hung; it is killed and the check fails instead of waiting for ever.
const PROBE_DEADLINE_MSEC: int = 120000
const POLL_MSEC: int = 20
## How many child Godot processes run at once (the machine they run on is shared): 4, or the number in the environment
## variable SWORDSTER_PROBE_CHILDREN (1 to 4) for a machine that is lent to several jobs.
const MAX_CHILDREN: int = 4
const CHILDREN_ENV: String = "SWORDSTER_PROBE_CHILDREN"

var _check: Callable
var _tree: SceneTree


func _init(check_function: Callable, tree: SceneTree) -> void:
	_check = check_function
	_tree = tree


func run_all() -> void:
	if not CheckFocus.includes("render_rate"):
		return
	print("render rates: the run state digest, then identical outcomes at low and high render rates")
	_check_state_digest()
	_check_chain_sees_one_tick()
	if not RenderRateScenario.probes_enabled():
		return
	_check_combined_fight()
	_check_launch_options()


func _ok(label: String, condition: bool, detail: String = "") -> void:
	_check.call(label, condition, detail)


# ------------------------------------------------------------ the state digest
## The members `GameRun.state_digest()` is allowed to leave out. Pinned here, so leaving something out is a decision a
## reviewer sees in this file and not a line in the list that nobody notices.
const EXPECTED_EXCLUDED: Array[String] = ["_cues", "_encounter_scenarios", "scenario", "show_ranges"]
## Classes the digest check must have found an instance of in the runs it perturbs (so a fight that stops making
## projectiles, fields or markers cannot silently shrink the check).
const EXPECTED_CLASSES: Array[String] = ["SwordState", "EnemyState", "EnemyConditions", "ProjectileState", "FieldState", "PickupState", "Mote", "WaveDirector", "SpawnMarker", "SwordSpec"]


func _check_state_digest() -> void:
	var excluded: Array[String] = []
	for name: String in GameRun.STATE_DIGEST_EXCLUDED:
		excluded.append(name)
		_ok("the digest leaves out %s for a stated reason" % name, not String(GameRun.STATE_DIGEST_EXCLUDED[name]).is_empty())
	excluded.sort()
	_ok("the run state digest leaves out exactly the reviewed members (%s)" % [excluded], excluded == EXPECTED_EXCLUDED)
	var run: GameRun = GameRun.new(CombinedFight.segment_scenario(0))
	var members: Array[String] = []
	for property: Dictionary in run.get_property_list():
		if int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE != 0:
			members.append(String(property["name"]))
	var digest: Dictionary = run.state_digest()
	var missing: Array[String] = []
	for name: String in members:
		if not digest.has(name) and not GameRun.STATE_DIGEST_EXCLUDED.has(name):
			missing.append(name)
	var stale: Array[String] = []
	for name: String in GameRun.STATE_DIGEST_EXCLUDED:
		if not members.has(name):
			stale.append(name)
	_ok("every member of the run is in the state digest or named as left out (missing %s, stale exclusions %s)" % [missing, stale], missing.is_empty() and stale.is_empty() and digest.size() == members.size() - excluded.size())
	for name: String in ["dash_cooldown_left", "converge_cooldown_left", "iframes", "dash_left", "rng", "director", "swords", "enemies", "projectiles", "fields", "pickups", "motes", "_cue_counts", "_next_serial", "combo_left", "hitstop", "slowmo"]:
		_ok("the state digest holds %s" % name, digest.has(name))
	# Every member that is a plain value of the run, and of one instance of every class it reaches, changes the digest when it changes.
	var reached: Dictionary = {}
	var unseen: Array[String] = []
	var silent: Array[String] = []
	var played: Array[GameRun] = [_run_to(CombinedFight.segment_scenario(0), 420), _run_to(CombinedFight.segment_scenario(1), 150)]
	for index: int in played.size():
		_perturb_everything(played[index], index == 0, reached, silent)
	for class_name_value: String in EXPECTED_CLASSES:
		if not reached.has(class_name_value):
			unseen.append(class_name_value)
	_ok("the state digest check reaches an instance of every class of run state (not reached: %s)" % [unseen], unseen.is_empty())
	_ok("changing any single value of the run changes its state digest (%d values tried; silent: %s)" % [int(reached.get("values", 0)), silent], silent.is_empty() and int(reached.get("values", 0)) > 100)
	var before_draw: Dictionary = played[0].state_digest()
	played[0].rng.randi()
	_ok("a draw from the gameplay random generator changes the state digest", played[0].state_digest() != before_draw)
	var fingerprint_before: int = played[0].state_fingerprint()
	played[0].rng.randi()
	_ok("a draw from the gameplay random generator changes the state fingerprint", played[0].state_fingerprint() != fingerprint_before)
	_ok("the same state gives the same digest and fingerprint twice", played[0].state_digest() == played[0].state_digest() and played[0].state_fingerprint() == played[0].state_fingerprint())


## A run of `scenario` after `ticks` ticks (the fight's own commands in segment 0). Bounded: a run whose ticks do not
## advance (a broken `step()`) ends after a fixed number of steps with a failing check instead of waiting for ever.
func _run_to(scenario: RunScenario, ticks: int) -> GameRun:
	var run: GameRun = GameRun.new(scenario)
	var segment_zero: bool = scenario.encounter == RunScenario.ENCOUNTER_NORMAL and not scenario.generated_waves
	var steps: int = 0
	while run.tick < ticks and steps < ticks * 10:
		if segment_zero:
			for command: GameCommand in CombinedFight.commands_at(0, run.tick):
				run.apply(command)
		run.step()
		run.take_cues()
		steps += 1
	_ok("the simulation reaches tick %d within %d steps for the state digest check (reached %d)" % [ticks, ticks * 10, run.tick], run.tick >= ticks)
	return run


## Changes every plain value (bool, number, text, vector) of `object`, one at a time, and notes in `silent` each one that did not
## change `root`'s digest; then does the same for the first instance of every other class reachable from it. `reached` collects the
## class names and counts the values tried. The top-level object is walked in full; further instances of a class are skipped.
func _perturb_everything(root: GameRun, _full: bool, reached: Dictionary, silent: Array[String]) -> void:
	var before: Dictionary = root.state_digest()
	var before_fingerprint: int = root.state_fingerprint()
	var queue: Array[Object] = [root]
	var visited: Dictionary[int, bool] = {root.get_instance_id(): true}
	while not queue.is_empty():
		var object: Object = queue.pop_front()
		var script: Script = object.get_script() as Script
		var kind: String = script.get_global_name() if script != null else ""
		var first_of_class: bool = object == root or not reached.has(kind)
		reached[kind] = true
		for property: Dictionary in object.get_property_list():
			if int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
				continue
			var name: String = String(property["name"])
			if object == root and GameRun.STATE_DIGEST_EXCLUDED.has(name):
				continue
			var value: Variant = object.get(name)
			if first_of_class:
				var changed: Variant = _changed(value)
				if changed != null:
					object.set(name, changed)
					reached["values"] = int(reached.get("values", 0)) + 1
					if root.state_digest() == before:
						silent.append("%s.%s (digest)" % [kind, name])
					if root.state_fingerprint() == before_fingerprint:
						silent.append("%s.%s (fingerprint)" % [kind, name])
					object.set(name, value)
			for child: Object in _objects_in(value):
				if child != null and not visited.has(child.get_instance_id()) and child.get_script() != null:
					visited[child.get_instance_id()] = true
					queue.append(child)


## A different value of the same type, or null for the types this check does not change (containers and objects: their
## content is reached through the objects they hold).
func _changed(value: Variant) -> Variant:
	match typeof(value):
		TYPE_BOOL:
			return not bool(value)
		TYPE_INT:
			return int(value) + 1
		TYPE_FLOAT:
			return float(value) + 0.25
		TYPE_STRING:
			return String(value) + "x"
		TYPE_STRING_NAME:
			return StringName(String(value) + "x")
		TYPE_VECTOR2:
			return (value as Vector2) + Vector2(1.0, 2.0)
	return null


func _objects_in(value: Variant) -> Array[Object]:
	var found: Array[Object] = []
	match typeof(value):
		TYPE_OBJECT:
			found.append(value as Object)
		TYPE_ARRAY:
			for item: Variant in value:
				if typeof(item) == TYPE_OBJECT:
					found.append(item as Object)
		TYPE_DICTIONARY:
			for key: Variant in value:
				if typeof(key) == TYPE_OBJECT:
					found.append(key as Object)
				if typeof(value[key]) == TYPE_OBJECT:
					found.append(value[key] as Object)
	return found


# ------------------------------------------------------------ the per-tick chain
## The chain of per-tick fingerprints must notice a difference that lasts ONE tick: the fight is played twice in lock
## step, in the second run a value is changed for the single tick 78 (after tick 77's step, put back before tick 78's) , so the two runs are identical again at
## the next checkpoints (the sampled digest cannot tell them apart) while their chains differ from tick 100 on.
func _check_chain_sees_one_tick() -> void:
	var clean: GameRun = GameRun.new(CombinedFight.segment_scenario(0))
	var changed: GameRun = GameRun.new(CombinedFight.segment_scenario(0))
	var clean_fight: CombinedFight = CombinedFight.new()
	var changed_fight: CombinedFight = CombinedFight.new()
	var steps: int = 0
	while clean.tick < 160 and steps < 1600:
		clean_fight.before_tick(clean)
		changed_fight.before_tick(changed)
		# The change exists only between the end of tick 77 and the start of tick 78's step: the fight's before_tick for tick 78 saw it.
		if changed.tick == 78:
			changed.dash_cooldown_left = clean.dash_cooldown_left
		clean.step()
		changed.step()
		if changed.tick == 78:
			changed.dash_cooldown_left += 0.3
		clean.take_cues()
		changed.take_cues()
		steps += 1
	_ok("the simulation reaches tick 160 within 1600 steps for the chain check (reached %d)" % clean.tick, clean.tick >= 160)
	_ok("after the one-tick change the two runs hold the same state again", clean.state_digest() == changed.state_digest())
	_ok("the readable digest at the checkpoints cannot see a one-tick difference (that is why the chain exists)", clean_fight.checkpoints["0:150"] == changed_fight.checkpoints["0:150"])
	_ok("the chains agree before the one-tick change (tick 50)", clean_fight.chains["0:50"] == changed_fight.chains["0:50"])
	_ok("the chain keeps a one-tick difference for good (ticks 100 and 150)", clean_fight.chains["0:100"] != changed_fight.chains["0:100"] and clean_fight.chains["0:150"] != changed_fight.chains["0:150"])


# ------------------------------------------------------------ the combined fight
func _check_combined_fight() -> void:
	var played: Dictionary = CombinedFight.play()
	# Probe output travels as JSON text, so compare both sides after the same round trip.
	var expected: Dictionary = JSON.parse_string(JSON.stringify({"checkpoints": played["checkpoints"], "chains": played["chains"], "finals": played["finals"]}))
	for coverage: Array in CombinedFight.coverage_failures(played):
		_ok(String(coverage[0]), false, String(coverage[1]))
	_ok("the combined fight covers everything it is meant to (%s)" % CombinedFight.coverage_summary(played), CombinedFight.coverage_failures(played).is_empty())
	var counted: Array = played["counters"]
	for index: int in counted.size():
		_ok("exactly once: segment %d's kills equal its kill cues" % index, int((counted[index] as Dictionary)["kills"]) == int((counted[index] as Dictionary)["kill_cues"]))
	var arguments: Array[PackedStringArray] = []
	for rate: int in PROBE_FRAME_RATES:
		arguments.append(PackedStringArray(["--fixed-fps", str(rate), "--script", PROBE_SCRIPT, "--", "--probe=rate"]))
	var runs: Array[Dictionary] = _run_children(arguments)
	var frames: Dictionary[int, int] = {}
	for i: int in PROBE_FRAME_RATES.size():
		var rate: int = PROBE_FRAME_RATES[i]
		var run: Dictionary = runs[i]
		var line: String = _probe_line(String(run["output"]))
		var result: Dictionary = JSON.parse_string(line) if not line.is_empty() else {}
		var valid: bool = result.has("checkpoints") and result.has("chains") and result.has("finals") and result.has("frames")
		_ok("the engine played the combined fight at %d fps and ended cleanly (exit status %d, output %s)" % [rate, int(run["code"]), "valid" if valid else "missing or not valid"], int(run["code"]) == 0 and valid, _tail(String(run["output"])))
		if not valid:
			continue
		frames[rate] = int(result["frames"])
		var comparable: Dictionary = {"checkpoints": result["checkpoints"], "chains": result["chains"], "finals": result["finals"]}
		_ok("at %d fps the real Main scene plays the combined fight exactly like the bare simulation: the same whole run state on every one of %d ticks (the chained per-tick fingerprint), at all %d checkpoints and at the end of each segment" % [rate, CombinedFight.TOTAL_TICKS, (expected["checkpoints"] as Dictionary).size()], comparable == expected, _first_difference(expected, comparable))
		var last: Dictionary = (counted[counted.size() - 1] as Dictionary)
		_ok("at %d fps every living enemy and lying sword has its visual (alive %d, visuals %d, pickups %d, pickup visuals %d)" % [rate, int(result["enemies"]), int(result["visuals"]), int(result["pickups"]), int(result["pickup_visuals"])],
			int(result["visuals"]) == int(result["enemies"]) + 3 and int(result["pickup_visuals"]) == int(result["pickups"]) and int(result["pickups"]) == int(last["pickups"]))
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
		var launched: Dictionary = _clean_launch(runs[i])
		_ok("the launch probe for --encounter=%s ends cleanly (exit status %d, output %s)" % [encounter, int(runs[i]["code"]), "valid" if not launched.is_empty() else "missing or not valid"], not launched.is_empty(), _tail(String(runs[i]["output"])))
		if encounter == "crowd" or encounter == "wall":
			var standing: int = RunScenario.WALL_CROWD_KINDS.size() if encounter == "wall" else 0
			_ok("the launch option --encounter=%s starts that encounter" % encounter, bool(launched.get("dev_shove", false)) and int(launched.get("standing", -1)) == standing, String(runs[i]["output"]))
		elif encounter == "spitters":
			_ok("the launch option --encounter=spitters starts the spitter encounter", String(launched.get("encounter", "")) == "spitters" and int(launched.get("wave_kinds", 0)) == 8 and not bool(launched.get("dev_shove", true)), String(runs[i]["output"]))
		else:
			_ok("an unknown launch option starts the normal run", launched.has("dev_shove") and not bool(launched["dev_shove"]) and int(launched["wave_kinds"]) == 0 and int(launched["standing"]) == 0, String(runs[i]["output"]))
	var plain: Dictionary = _clean_launch(runs[cases.size()])
	_ok("the launch probe without a launch option ends cleanly (exit status %d, output %s)" % [int(runs[cases.size()]["code"]), "valid" if not plain.is_empty() else "missing or not valid"], not plain.is_empty(), _tail(String(runs[cases.size()]["output"])))
	_ok("a missing launch option starts the normal run", plain.has("dev_shove") and not bool(plain["dev_shove"]) and int(plain["wave_kinds"]) == 0 and int(plain["standing"]) == 0, String(runs[cases.size()]["output"]))


## What a launch probe reported, or {} unless the child ended with exit status 0 AND printed its line.
func _clean_launch(run: Dictionary) -> Dictionary:
	if int(run["code"]) != 0:
		return {}
	var line: String = _probe_line(String(run["output"]))
	if line.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(line)
	return parsed as Dictionary if parsed is Dictionary else {}


# ------------------------------------------------------------ child processes
## Runs one headless Godot per argument list on this project, at most MAX_CHILDREN at the same time (the next one
## starts as soon as one ends), and returns, in the order of the lists, the exit `code` and the `output` text of
## each. Running them together is what keeps this group at about the cost of its slowest children instead of the
## sum. The whole batch is bounded by PROBE_DEADLINE_MSEC: a child still running by then is killed (code -1) and
## the ones not yet started never run (code -1), so a hang fails a check instead of hanging the suite. Each
## child's pipe is drained while it runs, so a child may print more than a pipe buffer holds.
func _run_children(argument_lists: Array[PackedStringArray]) -> Array[Dictionary]:
	var executable: String = OS.get_executable_path()
	var project: String = ProjectSettings.globalize_path("res://")
	var results: Array[Dictionary] = []
	var pipes: Dictionary[int, FileAccess] = {}
	var pids: Dictionary[int, int] = {}
	var texts: Dictionary[int, String] = {}
	for i: int in argument_lists.size():
		results.append({"code": -1, "output": "not started: the batch ran out of time"})
	var next: int = 0
	var running: Array[int] = []
	var started: int = Time.get_ticks_msec()
	while (next < argument_lists.size() or not running.is_empty()) and Time.get_ticks_msec() - started < PROBE_DEADLINE_MSEC:
		while next < argument_lists.size() and running.size() < _max_children():
			var full: PackedStringArray = PackedStringArray(["--headless", "--path", project])
			full.append_array(argument_lists[next])
			var child: Dictionary = OS.execute_with_pipe(executable, full)
			if child.is_empty():
				results[next] = {"code": -1, "output": "the child process could not start"}
			else:
				pids[next] = int(child["pid"])
				pipes[next] = child["stdio"] as FileAccess
				texts[next] = ""
				running.append(next)
			next += 1
		OS.delay_msec(POLL_MSEC)
		for index: int in running.duplicate():
			texts[index] += _drain(pipes[index])
			if not OS.is_process_running(pids[index]):
				texts[index] += _drain(pipes[index])
				results[index] = {"code": OS.get_process_exit_code(pids[index]), "output": texts[index]}
				running.erase(index)
	for index: int in running:
		OS.kill(pids[index])
		results[index] = {"code": -1, "output": "killed after %d ms" % PROBE_DEADLINE_MSEC}
	return results


func _max_children() -> int:
	var wanted: String = OS.get_environment(CHILDREN_ENV)
	return clampi(int(wanted), 1, MAX_CHILDREN) if wanted.is_valid_int() else MAX_CHILDREN


## What the child has written to its pipe so far: reads what `get_length()` says is waiting, a bounded number of
## times (a pipe never reports end of file here).
func _drain(pipe: FileAccess) -> String:
	var text: String = ""
	if pipe == null or not pipe.is_open():
		return text
	for read: int in 64:
		var waiting: int = pipe.get_length()
		if waiting <= 0:
			break
		text += pipe.get_buffer(waiting).get_string_from_utf8()
	return text


func _probe_line(output: String) -> String:
	for line: String in output.split("\n"):
		if line.begins_with("PROBE {"):
			return line.trim_prefix("PROBE ")
	return ""


## The last lines of a child's output, for a failing check's detail.
func _tail(output: String) -> String:
	var lines: PackedStringArray = output.split("\n")
	return "\n".join(lines.slice(maxi(0, lines.size() - 6)))


## Where two digests first differ, as a path ("finals/1/director/wave: 2 vs 3"), or what is missing.
func _first_difference(a: Variant, b: Variant, path: String = "") -> String:
	if typeof(a) == TYPE_DICTIONARY and typeof(b) == TYPE_DICTIONARY:
		for key: Variant in (a as Dictionary):
			if not (b as Dictionary).has(key):
				return "%s/%s only in the bare run" % [path, key]
			var inner: String = _first_difference(a[key], b[key], "%s/%s" % [path, key])
			if not inner.is_empty():
				return inner
		for key: Variant in (b as Dictionary):
			if not (a as Dictionary).has(key):
				return "%s/%s only in the Main run" % [path, key]
		return ""
	if typeof(a) == TYPE_ARRAY and typeof(b) == TYPE_ARRAY:
		if (a as Array).size() != (b as Array).size():
			return "%s: %d entries vs %d" % [path, (a as Array).size(), (b as Array).size()]
		for i: int in (a as Array).size():
			var inner: String = _first_difference(a[i], b[i], "%s/%d" % [path, i])
			if not inner.is_empty():
				return inner
		return ""
	if str(a) != str(b) or typeof(a) != typeof(b):
		return "%s: %s vs %s" % [path, str(a).left(80), str(b).left(80)]
	return ""
