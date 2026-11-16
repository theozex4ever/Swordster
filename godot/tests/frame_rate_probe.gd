extends SceneTree
## Plays `CombinedFight` through the real Main scene under the engine's own
## fixed-step loop and prints one `PROBE {json}` line. The checks (render_rate_checks.gd) start this script in a
## child Godot process at several `--fixed-fps` values (frames per second of the engine's clock): at 20 fps the
## engine runs three 1/60 s ticks per frame, at 240 fps one tick every four frames, and the digest must not notice.
## `--probe=rate` plays the combined fight. With `--probe=launch` it instead reports which scenario a Main scene
## picks when it is given none (the launch-option path).
##
##   godot --headless --path godot --fixed-fps 20 --script res://tests/frame_rate_probe.gd -- --probe=rate

const FRAME_LIMIT: int = 24000

var _main: Main
var _frames: int = 0
var _reported: bool = false
var _fight: CombinedFight = CombinedFight.new()


func _initialize() -> void:
	var mode: String = "rate"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--probe="):
			mode = argument.trim_prefix("--probe=")
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Main
	if mode == "rate":
		_main.scenario = CombinedFight.segment_scenario(0)
	root.add_child(_main)
	if mode == "launch":
		_report_launch.call_deferred()
		return
	physics_frame.connect(_before_tick)
	process_frame.connect(_count_frame)


## Emitted before every engine physics iteration, ahead of Main's own step, so
## a command lands before the same tick whatever the frame rate. The fight issues the commands, takes its
## checkpoints and, between its segments, restarts the run into the next scenario (the presenter is reset the way
## Main resets it on any restart).
func _before_tick() -> void:
	var restarts: int = _main.run.restarts
	_fight.before_tick(_main.run)
	if _main.run.restarts != restarts:
		_main._presenter.reset()
	if _fight.finished:
		_report()


func _count_frame() -> void:
	_frames += 1
	if _frames > FRAME_LIMIT:
		print("PROBE TIMEOUT")
		quit(2)


func _report() -> void:
	if _reported:
		return
	_reported = true
	var result: Dictionary = _fight.result()
	result["frames"] = _frames
	result["visuals"] = _main._presenter.visual_count()
	result["enemies"] = _main.run.enemies.size()
	result["pickups"] = _main.run.pickups.size()
	result["pickup_visuals"] = _main._presenter.pickup_visual_count()
	print("PROBE " + JSON.stringify(result))
	quit(0)


func _report_launch() -> void:
	var picked: RunScenario = _main.run.scenario
	print("PROBE " + JSON.stringify({"dev_shove": picked.dev_shove, "encounter": String(picked.encounter), "wave_kinds": picked.wave_kinds.size(), "standing": picked.initial_enemies.size()}))
	quit(0)
