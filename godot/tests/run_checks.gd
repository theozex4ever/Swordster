extends SceneTree
## Headless behavioural checks. Drives the real GameRun, InputTranslator and
## Main scene with the same commands/events players produce.
##
##   godot --headless --path godot --script res://tests/run_checks.gd
##
## Prints "CHECKS PASSED: <n>" on success; the build requires that line as well
## as exit status 0 because Godot can exit 0 after a script error.

const EPS: float = 0.001

var _total: int = 0
var _failed: int = 0


func _initialize() -> void:
	_run_all.call_deferred()


func _run_all() -> void:
	_check_scripts_load()
	_check_movement()
	_check_pause()
	_check_reset()
	_check_keyboard_translation()
	_check_touch_joystick()
	await _check_main_scene()
	var survival: SurvivalLoopChecks = SurvivalLoopChecks.new(_check, self)
	await survival.run_all()
	var crowd: CrowdAndWallChecks = CrowdAndWallChecks.new(_check, self)
	await crowd.run_all()
	var spitters: SpitterAndParryChecks = SpitterAndParryChecks.new(_check, self)
	await spitters.run_all()
	var flurry: ViperFlurryChecks = ViperFlurryChecks.new(_check, self)
	await flurry.run_all()
	if _failed == 0 and _total > 0:
		print("CHECKS PASSED: %d" % _total)
		quit(0)
	else:
		print("CHECKS FAILED: %d of %d" % [_failed, _total])
		quit(1)


# --------------------------------------------------------------- helpers
func _check(label: String, condition: bool, detail: String = "") -> void:
	_total += 1
	if condition:
		print("  ok   %s" % label)
	else:
		_failed += 1
		print("  FAIL %s %s" % [label, detail])


func _near(a: Vector2, b: Vector2, tolerance: float = EPS) -> bool:
	return a.distance_to(b) <= tolerance


func _run_with(axis: Vector2, ticks: int, run: GameRun = null) -> GameRun:
	var game: GameRun = run if run != null else GameRun.new()
	game.apply(GameCommand.move_axis(axis))
	for i: int in ticks:
		game.step()
	return game


func _key(code: Key, pressed: bool, echo: bool = false) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	event.echo = echo
	return event


func _touch(index: int, at: Vector2, pressed: bool, canceled: bool = false) -> InputEventScreenTouch:
	var event: InputEventScreenTouch = InputEventScreenTouch.new()
	event.index = index
	event.position = at
	event.pressed = pressed
	event.canceled = canceled
	return event


func _drag(index: int, at: Vector2) -> InputEventScreenDrag:
	var event: InputEventScreenDrag = InputEventScreenDrag.new()
	event.index = index
	event.position = at
	return event


# ---------------------------------------------------------------- checks
## Seeded, wave-free scenario so scene-level movement checks stay deterministic.
func _quiet_scenario() -> RunScenario:
	var scenario: RunScenario = RunScenario.new().without_conditions()
	scenario.seed = 3
	scenario.waves_enabled = false
	return scenario


func _check_scripts_load() -> void:
	print("scripts")
	var unloadable: Array[String] = []
	for path: String in _gd_files("res://"):
		var script: GDScript = load(path) as GDScript
		if script == null or not script.can_instantiate() and not script.is_abstract():
			unloadable.append(path)
	_check("every GDScript parses and loads", unloadable.is_empty(), str(unloadable))


func _gd_files(dir_path: String) -> Array[String]:
	var found: Array[String] = []
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return found
	for entry: String in dir.get_directories():
		if not entry.begins_with("."):
			found.append_array(_gd_files(dir_path.path_join(entry)))
	for file: String in dir.get_files():
		if file.ends_with(".gd"):
			found.append(dir_path.path_join(file))
	return found


func _check_movement() -> void:
	print("movement")
	var fresh: GameRun = GameRun.new()
	_check("run starts at the arena centre", _near(fresh.position, GameRun.WORLD.get_center()))
	_check("physics tick is 60 Hz", GameRun.TICK_RATE == 60 and absf(GameRun.TICK_DT - 1.0 / 60.0) < 1e-9)

	var east: GameRun = _run_with(Vector2.RIGHT, 120)
	_check("moving right gains x only", east.position.x > fresh.position.x + 200.0 and absf(east.position.y - fresh.position.y) < EPS)
	_check("speed settles at the prototype's 285", absf(east.velocity.length() - 285.0) < 1.0, str(east.velocity))
	_check("one second of motion stays under top speed distance", east.position.x - fresh.position.x < 285.0 * 2.0)
	_check("facing follows movement", _near(east.facing, Vector2.RIGHT))

	var west: GameRun = _run_with(Vector2.LEFT, 30)
	_check("moving left decreases x", west.position.x < fresh.position.x)

	var diagonal: GameRun = _run_with(Vector2(1.0, 1.0), 180)
	_check("diagonal movement is normalised", diagonal.velocity.length() <= 285.0 + 0.5, str(diagonal.velocity.length()))
	var oversized: GameRun = _run_with(Vector2(7.0, 0.0), 120)
	_check("oversized input is clamped like a unit axis", _near(oversized.position, east.position))

	var held: GameRun = _run_with(Vector2.UP, 30)
	var facing_before: Vector2 = held.facing
	_run_with(Vector2.ZERO, 30, held)
	_check("facing is kept when input stops", _near(held.facing, facing_before))
	_check("movement decays to a stop", held.velocity.length() < 1.0, str(held.velocity.length()))

	var inner: Rect2 = GameRun.WORLD.grow(-GameRun.PLAYER_RADIUS)
	var wall_w: GameRun = _run_with(Vector2.LEFT, 900)
	_check("west wall clamps position", absf(wall_w.position.x - inner.position.x) < EPS, str(wall_w.position))
	var wall_e: GameRun = _run_with(Vector2.RIGHT, 900)
	_check("east wall clamps position", absf(wall_e.position.x - inner.end.x) < EPS, str(wall_e.position))
	var wall_n: GameRun = _run_with(Vector2.UP, 900)
	_check("north wall clamps position", absf(wall_n.position.y - inner.position.y) < EPS, str(wall_n.position))
	var wall_s: GameRun = _run_with(Vector2.DOWN, 900)
	_check("south wall clamps position", absf(wall_s.position.y - inner.end.y) < EPS, str(wall_s.position))

	var scenario: RunScenario = RunScenario.new().without_conditions()
	scenario.start_position = Vector2(100.0, 200.0)
	_check("scenario controls the start position", _near(GameRun.new(scenario).position, Vector2(100.0, 200.0)))


func _check_pause() -> void:
	print("pause")
	var game: GameRun = _run_with(Vector2.RIGHT, 30)
	game.apply(GameCommand.pause())
	var frozen: Dictionary = game.snapshot()
	for i: int in 120:
		game.step()
	var after: Dictionary = game.snapshot()
	_check("paused run does not advance position", _near(after["position"], frozen["position"]))
	_check("paused run does not advance gameplay time", after["tick"] == frozen["tick"] and after["gameplay_time"] == frozen["gameplay_time"])
	_check("paused flag is observable", after["paused"] == true)

	game.apply(GameCommand.move_axis(Vector2.LEFT))
	game.step()
	_check("input while paused has no effect", _near(game.position, frozen["position"]))

	game.apply(GameCommand.resume())
	for i: int in 30:
		game.step()
	_check("resume continues gameplay time from where it stopped", game.tick == int(frozen["tick"]) + 30)
	_check("resume applies the latest input", game.position.x < float(frozen["position"].x) + 20.0 and game.velocity.x < 100.0, str(game.velocity))

	var toggle: GameRun = GameRun.new()
	toggle.apply(GameCommand.toggle_pause())
	var first: bool = toggle.paused
	toggle.apply(GameCommand.toggle_pause())
	_check("toggle pauses then resumes", first == true and toggle.paused == false)
	toggle.apply(GameCommand.resume())
	_check("resume on a running run is harmless", toggle.paused == false)


func _check_reset() -> void:
	print("reset")
	var game: GameRun = _run_with(Vector2(1.0, -1.0), 200)
	game.apply(GameCommand.pause())
	game.apply(GameCommand.restart())
	var fresh: Dictionary = GameRun.new().snapshot()
	var reset: Dictionary = game.snapshot()
	_check("restart restores start pose", _near(reset["position"], fresh["position"]) and _near(reset["velocity"], Vector2.ZERO))
	_check("restart clears time and ticks", reset["tick"] == 0 and reset["gameplay_time"] == 0.0)
	_check("restart leaves the run running", reset["paused"] == false)
	_check("restart is counted for presenters", reset["restarts"] == 1)
	_check("restart drops held movement input", _near(reset["move_input"], Vector2.ZERO))
	for i: int in 60:
		game.step()
	_check("run stays put after restart until new input", _near(game.position, fresh["position"]))
	_run_with(Vector2.RIGHT, 20, game)
	game.apply(GameCommand.restart())
	_check("repeated restarts also reset", _near(game.position, fresh["position"]) and game.snapshot()["restarts"] == 2)


func _check_keyboard_translation() -> void:
	print("keyboard")
	var cases: Dictionary = {
		KEY_W: Vector2.UP, KEY_UP: Vector2.UP,
		KEY_S: Vector2.DOWN, KEY_DOWN: Vector2.DOWN,
		KEY_A: Vector2.LEFT, KEY_LEFT: Vector2.LEFT,
		KEY_D: Vector2.RIGHT, KEY_RIGHT: Vector2.RIGHT,
	}
	for code: Key in cases:
		var translator: InputTranslator = InputTranslator.new()
		translator.handle_event(_key(code, true))
		_check("%s moves %s" % [OS.get_keycode_string(code), cases[code]], _near(translator.move_axis(), cases[code]))
		translator.handle_event(_key(code, false))
		_check("%s release stops movement" % OS.get_keycode_string(code), _near(translator.move_axis(), Vector2.ZERO))

	var combo: InputTranslator = InputTranslator.new()
	combo.handle_event(_key(KEY_W, true))
	combo.handle_event(_key(KEY_D, true))
	_check("W+D is a normalised diagonal", absf(combo.move_axis().length() - 1.0) < EPS)
	combo.handle_event(_key(KEY_A, true))
	combo.handle_event(_key(KEY_A, true, true))
	_check("opposing keys cancel", absf(combo.move_axis().x) < EPS and combo.move_axis().y < 0.0)

	var pause_keys: InputTranslator = InputTranslator.new()
	_check("P toggles pause", _kinds(pause_keys.handle_event(_key(KEY_P, true))) == [GameCommand.Kind.TOGGLE_PAUSE])
	_check("Escape toggles pause", _kinds(pause_keys.handle_event(_key(KEY_ESCAPE, true))) == [GameCommand.Kind.TOGGLE_PAUSE])
	_check("held pause key does not repeat", pause_keys.handle_event(_key(KEY_P, true, true)).is_empty())
	_check("R is the slot-three ultimate first and then asks for the delayed keyboard restart", _kinds(pause_keys.handle_event(_key(KEY_R, true))) == [GameCommand.Kind.ULTIMATE, GameCommand.Kind.RESTART_FROM_KEY])
	_check("key release emits no command", pause_keys.handle_event(_key(KEY_P, false)).is_empty())

	var stuck: InputTranslator = InputTranslator.new()
	stuck.handle_event(_key(KEY_D, true))
	stuck.release_all()
	_check("release_all clears held keys", _near(stuck.move_axis(), Vector2.ZERO))


func _kinds(commands: Array[GameCommand]) -> Array[GameCommand.Kind]:
	var kinds: Array[GameCommand.Kind] = []
	for command: GameCommand in commands:
		kinds.append(command.kind)
	return kinds


func _check_touch_joystick() -> void:
	print("touch")
	var translator: InputTranslator = InputTranslator.new()
	translator.joystick.zone = Rect2(0.0, 100.0, 700.0, 620.0)
	translator.joystick.blocked = [Rect2(10.0, 110.0, 80.0, 50.0)]

	translator.handle_event(_touch(0, Vector2(300.0, 400.0), true))
	_check("touch inside the zone claims the joystick", translator.joystick.pointer == 0)
	translator.handle_event(_drag(0, Vector2(390.0, 400.0)))
	_check("dragging right moves right", _near(translator.move_axis(), Vector2.RIGHT, 0.01), str(translator.move_axis()))
	translator.handle_event(_drag(0, Vector2(300.0, 100000.0)))
	_check("far drags are clamped to a unit axis", absf(translator.move_axis().length() - 1.0) < 0.01)
	translator.handle_event(_drag(0, Vector2(305.0, 402.0)))
	_check("tiny drags stay inside the dead zone", _near(translator.move_axis(), Vector2.ZERO))

	translator.handle_event(_drag(0, Vector2(300.0, 310.0)))
	var held_axis: Vector2 = translator.move_axis()
	translator.handle_event(_touch(1, Vector2(200.0, 300.0), true))
	translator.handle_event(_drag(1, Vector2(500.0, 600.0)))
	_check("a second finger does not steal or move the joystick", translator.joystick.pointer == 0 and _near(translator.move_axis(), held_axis))
	translator.handle_event(_touch(1, Vector2(500.0, 600.0), false))
	_check("lifting an unrelated finger keeps movement", translator.joystick.pointer == 0 and _near(translator.move_axis(), held_axis))
	translator.handle_event(_touch(0, Vector2(300.0, 310.0), false))
	_check("lifting the joystick finger stops movement", translator.joystick.pointer == -1 and _near(translator.move_axis(), Vector2.ZERO))

	translator.handle_event(_touch(2, Vector2(300.0, 400.0), true))
	translator.handle_event(_touch(2, Vector2(300.0, 400.0), false, true))
	_check("a cancelled touch releases input", translator.joystick.pointer == -1)

	translator.handle_event(_touch(3, Vector2(800.0, 400.0), true))
	_check("touch outside the zone is ignored", translator.joystick.pointer == -1)
	translator.handle_event(_touch(4, Vector2(50.0, 130.0), true))
	_check("touch on a button does not start the joystick", translator.joystick.pointer == -1)

	translator.handle_event(_key(KEY_A, true))
	translator.handle_event(_touch(5, Vector2(300.0, 400.0), true))
	translator.handle_event(_drag(5, Vector2(300.0, 500.0)))
	_check("touch overrides keyboard while in use", translator.move_axis().y > 0.5 and absf(translator.move_axis().x) < 0.01)
	translator.release_all()
	_check("release_all drops touch and keys together", translator.joystick.pointer == -1 and _near(translator.move_axis(), Vector2.ZERO))


func _check_main_scene() -> void:
	print("main scene")
	var scene: PackedScene = load("res://scenes/main.tscn")
	var main: Main = scene.instantiate() as Main
	main.scenario = _quiet_scenario()
	root.add_child(main)
	await process_frame
	main.run.apply(GameCommand.restart())

	_check("run starts running with sound locked", not main.run.paused and not main._sfx.unlocked)

	main._input(_key(KEY_D, true))
	_check("first key press unlocks sound", main._sfx.unlocked and main._sfx.played == ["unlock"], str(main._sfx.played))
	for i: int in 60:
		main._physics_process(GameRun.TICK_DT)
	var moved_to: Vector2 = main.run.position
	_check("keyboard moves the real run", moved_to.x > GameRun.WORLD.get_center().x + 100.0)
	_check("the visual receives the logical pose", _near(main.visual.position, moved_to))

	main._input(_key(KEY_ESCAPE, true))
	_check("Escape pauses the run", main.run.paused)
	for i: int in 60:
		main._physics_process(GameRun.TICK_DT)
	_check("scene does not advance while paused", _near(main.run.position, moved_to) and _near(main.visual.position, moved_to))
	main._input(_key(KEY_ESCAPE, true))
	_check("a second Escape resumes", not main.run.paused)
	_check("pause and resume are audible", main._sfx.played.has("pause") and main._sfx.played.has("resume"), str(main._sfx.played))

	main.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check("focus loss pauses", main.run.paused)
	main._input(_key(KEY_ESCAPE, true))
	var resumed_at: Vector2 = main.run.position
	for i: int in 30:
		main._physics_process(GameRun.TICK_DT)
	_check("focus loss released held keys (nothing stuck after resume)", _near(main.input.move_axis(), Vector2.ZERO))
	_check("explicit resume after focus loss decays rather than drives", main.run.velocity.length() < 285.0 and main.run.position.distance_to(resumed_at) < 100.0)

	var restarts_before: int = main.run.restarts
	main._input(_key(KEY_R, true))
	_check("R while alive does not restart (it is the slot-three ultimate key)", main.run.restarts == restarts_before)
	main._hud.restart_pressed.emit()
	_check("the Restart button restarts the scene's run", main.run.restarts == restarts_before + 1 and main.run.tick == 0 and _near(main.run.position, GameRun.WORLD.get_center()))
	_check("restart snaps the visual back", _near(main.visual.position, GameRun.WORLD.get_center()))

	# Visual independence: the same commands against a very different visual
	# must produce identical gameplay.
	var alt_scene: Node = load("res://scenes/main.tscn").instantiate()
	var alt: Main = alt_scene as Main
	alt.scenario = _quiet_scenario()
	alt.actor_visual = load("res://tests/alt_actor.tscn")
	root.add_child(alt)
	await process_frame
	main.run.apply(GameCommand.restart())
	alt.run.apply(GameCommand.restart())
	for target: Main in [main, alt]:
		target.input.handle_event(_key(KEY_S, true))
		target.input.handle_event(_key(KEY_D, true))
		for i: int in 90:
			target._physics_process(GameRun.TICK_DT)
	var baseline: Dictionary = main.run.snapshot()
	var alternate: Dictionary = alt.run.snapshot()
	baseline.erase("restarts")
	alternate.erase("restarts")
	_check("an alternate actor visual leaves gameplay unchanged", baseline == alternate)
	_check("the alternate visual still gets the logical pose", alt.visual is AltActorVisual and _near(alt.visual.position, alt.run.position))
	main.queue_free()
	alt.queue_free()
	await process_frame
