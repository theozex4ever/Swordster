extends SceneTree
## Plays `RenderRateScenario` through the real Main scene under the engine's own
## fixed-step loop and prints one `PROBE {json}` line. The checks start this
## script in a child Godot process at several `--fixed-fps` values (frames per
## second of the engine's clock): at 20 fps the engine runs three 1/60 s ticks
## per frame, at 240 fps one tick every four frames, and the digest must not
## notice. `--probe=rate` plays the crowd fight, `--probe=rate-spitters` the
## orbs-and-parries fight, `--probe=rate-flurry` the Viper Flurry fight. With `--probe=launch` it instead reports which
## scenario a Main scene picks when it is given none (the launch-option path).
##
##   godot --headless --path godot --fixed-fps 20 --script res://tests/frame_rate_probe.gd -- --probe=rate

const FRAME_LIMIT: int = 8000

var _main: Main
var _script_name: String = RenderRateScenario.CROWD
var _frames: int = 0
var _last_issued_tick: int = -1


func _initialize() -> void:
	var mode: String = "rate"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--probe="):
			mode = argument.trim_prefix("--probe=")
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Main
	if mode == "rate-spitters":
		_script_name = RenderRateScenario.SPITTERS
	if mode == "rate-flurry":
		_script_name = RenderRateScenario.FLURRY
	if mode == "rate" or mode == "rate-spitters" or mode == "rate-flurry":
		_main.scenario = RenderRateScenario.scenario(_script_name)
	root.add_child(_main)
	if mode == "launch":
		_report_launch.call_deferred()
		return
	physics_frame.connect(_before_tick)
	process_frame.connect(_count_frame)


## Emitted before every engine physics iteration, ahead of Main's own step, so
## a command lands before the same tick whatever the frame rate.
func _before_tick() -> void:
	var run: GameRun = _main.run
	if run.tick == _last_issued_tick:
		return
	_last_issued_tick = run.tick
	for command: GameCommand in RenderRateScenario.commands_at(run.tick, _script_name):
		run.apply(command)
	if run.tick >= RenderRateScenario.TOTAL_TICKS:
		_report()


func _count_frame() -> void:
	_frames += 1
	if _frames > FRAME_LIMIT:
		print("PROBE TIMEOUT")
		quit(2)


func _report() -> void:
	var result: Dictionary = RenderRateScenario.digest(_main.run)
	result["frames"] = _frames
	result["visuals"] = _main._presenter.visual_count()
	result["enemies"] = _main.run.enemies.size()
	print("PROBE " + JSON.stringify(result))
	quit(0)


func _report_launch() -> void:
	var picked: RunScenario = _main.run.scenario
	print("PROBE " + JSON.stringify({"dev_shove": picked.dev_shove, "encounter": String(picked.encounter), "wave_kinds": picked.wave_kinds.size(), "standing": picked.initial_enemies.size()}))
	quit(0)
