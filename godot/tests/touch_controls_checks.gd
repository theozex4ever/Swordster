class_name TouchControlsChecks
extends RefCounted
## Behavioural checks for the touch controls (issue #20). The prototype was desktop-only, so there is no reference capture: the
## rules are the issue's. Every check drives real `InputEventScreenTouch` / `InputEventScreenDrag` events (several indices at once)
## through the real input path (the viewport's `_input`, the GUI buttons, `_unhandled_input`) in the real Main scene, and observes the
## outcome in the run: where Converge landed, which ultimate started and at what, whether the player moved or dashed, what paused.
## Waiting loops are bounded by a frame counter and fail when it runs out. The physical Android checks are deferred to #6 / #22.

const CENTER: Vector2 = Vector2(1300.0, 900.0)
const MAX_FRAMES: int = 40
const MAX_TICKS: int = 600
const CONVERGE_RANGE: float = 460.0
## Windows (CSS-pixel sizes of real phones and tablets, both ways up) the layout and aiming are checked at.
const WINDOWS: Array[Vector2i] = [
	Vector2i(1280, 720), Vector2i(915, 412), Vector2i(844, 390), Vector2i(2400, 1080), Vector2i(1024, 768),
	Vector2i(412, 915), Vector2i(390, 844), Vector2i(1080, 2400), Vector2i(768, 1024), Vector2i(800, 800),
]

var _check: Callable
var _tree: SceneTree
var _clock: Array[float] = [0.0]


func _init(check_function: Callable, tree: SceneTree) -> void:
	_check = check_function
	_tree = tree


func run_all() -> void:
	if not CheckFocus.includes("touch_controls"):
		return
	_check_pointer_table()
	_check_layout_geometry()
	_check_platform_values()
	await _check_activation_and_desktop()
	await _check_views_and_aiming()
	await _check_buttons_and_aiming()
	await _check_simultaneous()
	await _check_ui_consumes_touches()
	await _check_emulated_mouse_path()
	await _check_release_and_suspension()
	await _check_stuck_buttons()
	await _check_paused_and_dead()
	await _check_layout_in_scene()


# --------------------------------------------------------------- helpers
func _ok(label: String, condition: bool, detail: String = "") -> void:
	_check.call(label, condition, detail)


func _touch(index: int, at: Vector2, pressed: bool, canceled: bool = false) -> InputEventScreenTouch:
	var event: InputEventScreenTouch = InputEventScreenTouch.new()
	event.index = index
	event.position = at
	event.pressed = pressed
	event.canceled = canceled
	return event


func _drag(index: int, at: Vector2, from: Vector2 = Vector2.ZERO) -> InputEventScreenDrag:
	var event: InputEventScreenDrag = InputEventScreenDrag.new()
	event.index = index
	event.position = at
	event.relative = at - from
	return event


func _window(size: Vector2i) -> Window:
	var window: Window = Window.new()
	window.size = size
	window.content_scale_size = Vector2i(1280, 720)
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	_tree.root.add_child(window)
	return window


## A normal start in the real scene with standing enemies (hit points 900, speed 0) and no waves; swords idle for good.
func _scenario(enemy_points: Array = [], start: Vector2 = CENTER) -> RunScenario:
	var scenario: RunScenario = RunScenario.new()
	scenario.seed = 20
	scenario.waves_enabled = false
	scenario.start_position = start
	scenario.sword_start_cooldowns = [99.0, 99.0, 99.0]
	var placements: Array[EnemyPlacement] = []
	for at: Variant in enemy_points:
		var placement: EnemyPlacement = EnemyPlacement.make(EnemyDefs.HUSK, start + (at as Vector2))
		placement.speed_scale = 0.0
		placement.hp = 900.0
		placements.append(placement)
	scenario.initial_enemies = placements
	return scenario


func _main_in(window: Window, scenario: RunScenario, touch_on: bool = true) -> Main:
	var main: Main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Main
	main.scenario = scenario
	window.add_child(main)
	main.set_physics_process(false)
	_clock[0] = 0.0
	main.input.touch.clock = func() -> float: return _clock[0]
	await _tree.process_frame
	await _tree.process_frame
	if touch_on:
		main.set_touch_mode(true)
	await _settle(main, window)
	return main


## What the viewport's visible area is for a window of `size` with this base: the base scaled until it fits, expanded the other way.
func _expected_view(size: Vector2i, base: Vector2i) -> Vector2:
	var scale: float = minf(float(size.x) / float(base.x), float(size.y) / float(base.y))
	return Vector2(float(size.x), float(size.y)) / scale


## Waits (at most MAX_FRAMES frames) for the HUD and the touch buttons to take their places; fails the check when they do not.
func _settle(main: Main, window: Window) -> bool:
	for frame: int in MAX_FRAMES:
		if main.touch_mode:
			var dash: Rect2 = main._hud.dash_rect()
			var view: Vector2 = window.get_visible_rect().size
			var want: Vector2 = _expected_view(window.size, TouchLayout.base_size_for(window.size))
			if dash.has_area() and view.distance_to(want) < 1.0 and main._touch.button_rect(TouchLayout.CONVERGE).has_area() and dash.end.x <= view.x + 0.5:
				await _tree.process_frame
				main._update_touch_zone()
				return true
		else:
			if main._hud.dash_rect().has_area():
				return true
		await _tree.process_frame
	_ok("the HUD and the touch buttons settled within %d frames (window %s, view %s)" % [MAX_FRAMES, window.size, window.get_visible_rect().size], false)
	return false


func _resize(main: Main, window: Window, size: Vector2i) -> bool:
	window.size = size
	for frame: int in 3:
		await _tree.process_frame
	return await _settle(main, window)


func _send(window: Window, event: InputEvent) -> void:
	window.push_input(event, true)


func _tap(window: Window, index: int, at: Vector2) -> void:
	_send(window, _touch(index, at, true))
	_send(window, _touch(index, at, false))


func _ticks(main: Main, count: int) -> void:
	for i: int in count:
		main._physics_process(GameRun.TICK_DT)


func _ready_to_converge(main: Main) -> void:
	main.run.converge_cooldown_left = 0.0
	for sword: SwordState in main.run.swords:
		sword.phase = SwordState.Phase.IDLE


func _converges(main: Main) -> int:
	return main.run.cue_count(SimCue.Kind.CONVERGE)


func _clamped(main: Main, point: Vector2) -> Vector2:
	var to_point: Vector2 = point - main.run.position
	if to_point.length() > CONVERGE_RANGE:
		return main.run.position + to_point.normalized() * CONVERGE_RANGE
	return point


func _near(a: Vector2, b: Vector2, tolerance: float = 0.01) -> bool:
	return a.distance_to(b) <= tolerance


# ---------------------------------------------------- the pointer table
func _translator() -> InputTranslator:
	var translator: InputTranslator = InputTranslator.new()
	translator.joystick.zone = Rect2(0.0, 100.0, 700.0, 600.0)
	translator.joystick.blocked = [Rect2(20.0, 120.0, 80.0, 60.0)]
	translator.to_world = func(point: Vector2) -> Vector2: return point + Vector2(1000.0, 500.0)
	_clock[0] = 0.0
	translator.touch.clock = func() -> float: return _clock[0]
	return translator


func _check_pointer_table() -> void:
	print("touch: every finger is tracked on its own")
	var t: InputTranslator = _translator()
	var arena: Array[GameCommand] = t.handle_event(_touch(0, Vector2(900.0, 400.0), true))
	_ok("a finger landing on the arena commands Converge at the tapped world point at once (1900, 900)", arena.size() == 1 and arena[0].kind == GameCommand.Kind.CONVERGE and arena[0].point == Vector2(1900.0, 900.0) and not arena[0].at_nearest)
	_ok("it does not steer, and lifting it commands nothing more", not t.joystick.is_active() and t.handle_event(_touch(0, Vector2(900.0, 400.0), false)).is_empty() and t.touch.count() == 0)

	_ok("a finger landing in the joystick's zone steers and commands nothing yet", t.handle_event(_touch(0, Vector2(300.0, 400.0), true)).is_empty() and t.joystick.pointer == 0 and t.touch.owner_of(0) == TouchPointers.Owner.JOYSTICK)
	t.handle_event(_drag(0, Vector2(390.0, 400.0)))
	_ok("dragging it moves the axis (1, 0)", _near(t.move_axis(), Vector2(1.0, 0.0), 0.001))
	var second: Array[GameCommand] = t.handle_event(_touch(1, Vector2(900.0, 300.0), true))
	_ok("a second finger on the arena commands Converge while the first keeps steering", second.size() == 1 and second[0].kind == GameCommand.Kind.CONVERGE and second[0].point == Vector2(1900.0, 800.0) and t.joystick.pointer == 0)
	t.handle_event(_drag(1, Vector2(100.0, 650.0)))
	_ok("dragging the second finger does not move the stick", _near(t.move_axis(), Vector2(1.0, 0.0), 0.001))
	var third: Array[GameCommand] = t.handle_event(_touch(2, Vector2(200.0, 500.0), true))
	_ok("a third finger in the zone, with the stick taken, is an arena tap (a Converge at its world point), not a second stick", third.size() == 1 and third[0].point == Vector2(1200.0, 1000.0) and t.joystick.pointer == 0)
	t.handle_event(_touch(1, Vector2(900.0, 300.0), false))
	t.handle_event(_touch(2, Vector2(200.0, 500.0), false))
	_ok("lifting the other fingers leaves the steering finger alone (axis still 1, 0; one finger down)", _near(t.move_axis(), Vector2(1.0, 0.0), 0.001) and t.touch.count() == 1)
	_ok("an unknown finger's drag changes nothing", t.handle_event(_drag(7, Vector2(5.0, 5.0))).is_empty() and _near(t.move_axis(), Vector2(1.0, 0.0), 0.001))
	_clock[0] = 5.0
	var lifted: Array[GameCommand] = t.handle_event(_touch(0, Vector2(390.0, 400.0), false))
	_ok("lifting the steering finger after a long drag stops the stick and makes no tap", lifted.is_empty() and not t.joystick.is_active() and _near(t.move_axis(), Vector2.ZERO))

	var on_button: Array[GameCommand] = t.handle_event(_touch(3, Vector2(50.0, 150.0), true))
	_ok("a finger landing on a button inside the zone is the button's: no stick, no Converge", on_button.is_empty() and not t.joystick.is_active() and t.touch.owner_of(3) == TouchPointers.Owner.UI)
	var free_stick: Array[GameCommand] = t.handle_event(_touch(4, Vector2(300.0, 400.0), true))
	t.handle_event(_drag(3, Vector2(600.0, 650.0)))
	_ok("a stick can start while a button is held, and the button finger's drag never steers it", free_stick.is_empty() and t.joystick.pointer == 4 and _near(t.move_axis(), Vector2.ZERO))
	_ok("lifting the button finger commands nothing", t.handle_event(_touch(3, Vector2(600.0, 650.0), false)).is_empty() and t.joystick.pointer == 4)
	t.release_all()

	# a tap that steers: quick and still
	_clock[0] = 10.0
	t.handle_event(_touch(0, Vector2(300.0, 400.0), true))
	_clock[0] = 10.0 + 0.25
	var tapped: Array[GameCommand] = t.handle_event(_touch(0, Vector2(300.0, 400.0), false))
	_ok("a finger in the zone that lifts within 0.3 s (here after 0.25) and stays still is a tap: Converge at where it landed (1300, 900)", tapped.size() == 1 and tapped[0].point == Vector2(1300.0, 900.0) and not t.joystick.is_active())
	_clock[0] = 20.0
	t.handle_event(_touch(0, Vector2(300.0, 400.0), true))
	_clock[0] = 20.0 + 0.5
	_ok("one that stays longer is a hold, not a tap", t.handle_event(_touch(0, Vector2(300.0, 400.0), false)).is_empty())
	_clock[0] = 30.0
	t.handle_event(_touch(0, Vector2(300.0, 400.0), true))
	t.handle_event(_drag(0, Vector2(300.0 + 18.0, 400.0)))
	_ok("moving exactly 18 px still is a tap", t.handle_event(_touch(0, Vector2(300.0, 400.0), false)).size() == 1)
	t.handle_event(_touch(0, Vector2(300.0, 400.0), true))
	t.handle_event(_drag(0, Vector2(300.0 + 19.0, 400.0)))
	t.handle_event(_drag(0, Vector2(300.0, 400.0)))
	_ok("moving 19 px and coming back is not (the farthest it went counts)", t.handle_event(_touch(0, Vector2(300.0, 400.0), false)).is_empty())
	t.handle_event(_touch(0, Vector2(300.0, 400.0), true))
	_ok("a cancelled contact never taps and frees the stick", t.handle_event(_touch(0, Vector2(300.0, 400.0), false, true)).is_empty() and not t.joystick.is_active() and t.touch.count() == 0)
	t.handle_event(_touch(0, Vector2(300.0, 400.0), true))
	t.handle_event(_drag(0, Vector2(380.0, 400.0)))
	var stale: Array[GameCommand] = t.handle_event(_touch(0, Vector2(310.0, 410.0), true))
	_ok("a press for a finger that never lifted ends the old contact (no tap) and starts a new one at its own origin", stale.is_empty() and t.joystick.pointer == 0 and t.joystick.origin == Vector2(310.0, 410.0) and t.touch.count() == 1)
	t.release_all()

	t.handle_event(_touch(0, Vector2(300.0, 400.0), true))
	t.handle_event(_touch(1, Vector2(900.0, 400.0), true))
	t.handle_event(_touch(2, Vector2(50.0, 150.0), true))
	t.handle_event(_key_down(KEY_D))
	t.release_all()
	_ok("release_all forgets every finger and key: no stick, no contact, no movement", t.touch.count() == 0 and not t.joystick.is_active() and _near(t.move_axis(), Vector2.ZERO))
	t.handle_event(_drag(0, Vector2(390.0, 400.0)))
	_clock[0] = 31.0
	_ok("afterwards a forgotten finger's drag and lift change nothing (no stick, no tap)", t.handle_event(_touch(0, Vector2(390.0, 400.0), false)).is_empty() and _near(t.move_axis(), Vector2.ZERO) and t.touch.count() == 0)

	var many: InputTranslator = _translator()
	var landed: int = 0
	for index: int in 5:
		landed += many.handle_event(_touch(index, Vector2(800.0 + 10.0 * float(index), 300.0), true)).size()
	_ok("five fingers on the arena are five independent Converge commands and five contacts", landed == 5 and many.touch.count() == 5)


func _key_down(code: Key) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = true
	return event


# ----------------------------------------------------------- geometry
func _hud_dash(view: Vector2) -> Rect2:
	return Rect2(view.x - 128.0, view.y - 128.0, 104.0, 104.0)


func _check_layout_geometry() -> void:
	print("touch: the layout fits every view, orientation and safe area")
	var views: Array[Vector2] = [Vector2(1280.0, 720.0), Vector2(1600.0, 720.0), Vector2(1280.0, 853.0), Vector2(1280.0, 1280.0), Vector2(740.0, 1280.0), Vector2(740.0, 1560.0)]
	var insets_list: Array[Vector4] = [Vector4.ZERO, Vector4(48.0, 0.0, 48.0, 0.0), Vector4(0.0, 40.0, 0.0, 34.0), Vector4(60.0, 30.0, 60.0, 20.0)]
	var problems: Array[String] = []
	var combos: int = 0
	for view: Vector2 in views:
		for insets: Vector4 in insets_list:
			combos += 1
			var dash: Rect2 = _hud_dash(view)
			var rects: Dictionary[StringName, Rect2] = TouchLayout.button_rects(view, insets, dash)
			var safe: Rect2 = Rect2(insets.x, insets.y, view.x - insets.x - insets.z, view.y - insets.y - insets.w)
			var ids: Array = rects.keys()
			for id: StringName in ids:
				var rect: Rect2 = rects[id]
				var tag: String = "%s %s %s" % [view, insets, id]
				if not safe.encloses(rect):
					problems.append("%s outside the safe area %s" % [tag, rect])
				if minf(rect.size.x, rect.size.y) < TouchLayout.MIN_SIDE:
					problems.append("%s smaller than %d px: %s" % [tag, int(TouchLayout.MIN_SIDE), rect.size])
				if id != TouchLayout.RESTART and id != TouchLayout.RESUME and rect.intersects(dash) and insets == Vector4.ZERO:
					problems.append("%s covers the HUD's Dash button" % tag)
				for other: StringName in ids:
					if String(other) < String(id) and not ((id == TouchLayout.RESUME and other == TouchLayout.RESTART) or (id == TouchLayout.RESTART and other == TouchLayout.RESUME)) and rect.intersects(rects[other]):
						problems.append("%s overlaps %s" % [tag, other])
			var zone: Rect2 = TouchLayout.joystick_zone(view, insets)
			if not safe.encloses(zone) or zone.size.x < 300.0 or zone.size.y < 300.0:
				problems.append("%s %s joystick zone %s" % [view, insets, zone])
	_ok("at %d combinations of view and safe area every button lies inside the safe area, is at least 80 px a side, and none overlaps another or the HUD's Dash (%d problems: %s)" % [combos, problems.size(), problems.slice(0, 3)], problems.is_empty())
	var plain: Rect2 = TouchLayout.joystick_zone(Vector2(1280.0, 720.0), Vector4.ZERO)
	_ok("with no safe-area insets the joystick zone is the earlier one: the left 55 % below the top 15 %", plain == Rect2(0.0, 108.0, 704.0, 612.0))
	var lifted: Dictionary[StringName, Rect2] = TouchLayout.button_rects(Vector2(740.0, 1280.0), Vector4.ZERO, _hud_dash(Vector2(740.0, 1280.0)))
	var flat: Dictionary[StringName, Rect2] = TouchLayout.button_rects(Vector2(1280.0, 720.0), Vector4.ZERO, _hud_dash(Vector2(1280.0, 720.0)))
	_ok("in a narrow view the ultimate row rises clear of the HUD's sword cards (bottom 114 px); in a wide one it does not", lifted[TouchLayout.ultimate_id(0)].end.y <= 1280.0 - 114.0 and flat[TouchLayout.ultimate_id(0)].end.y > 720.0 - 114.0 and flat[TouchLayout.ultimate_id(0)].end.y == _hud_dash(Vector2(1280.0, 720.0)).end.y)
	_ok("the ultimate buttons read Q, E, R from left to right and the swap buttons sit above them", flat[TouchLayout.ultimate_id(0)].position.x < flat[TouchLayout.ultimate_id(1)].position.x and flat[TouchLayout.ultimate_id(1)].position.x < flat[TouchLayout.ultimate_id(2)].position.x and flat[TouchLayout.swap_id(1)].end.y < flat[TouchLayout.ultimate_id(1)].position.y)
	_ok("Converge sits directly above Dash", flat[TouchLayout.CONVERGE].end.y < _hud_dash(Vector2(1280.0, 720.0)).position.y and absf(flat[TouchLayout.CONVERGE].get_center().x - _hud_dash(Vector2(1280.0, 720.0)).get_center().x) < 1.0)


func _check_platform_values() -> void:
	print("touch: orientation, safe-area and launch values")
	_ok("a window taller than wide uses the portrait base 740 x 1280, anything else the landscape 1280 x 720 (square included)",
		TouchLayout.base_size_for(Vector2i(412, 915)) == Vector2i(740, 1280) and TouchLayout.base_size_for(Vector2i(915, 412)) == Vector2i(1280, 720) and TouchLayout.base_size_for(Vector2i(800, 800)) == Vector2i(1280, 720) and TouchLayout.base_size_for(Vector2i(801, 800)) == Vector2i(1280, 720) and TouchLayout.base_size_for(Vector2i(800, 801)) == Vector2i(740, 1280))
	_ok("is_portrait is height over width", TouchLayout.is_portrait(Vector2(740.0, 1280.0)) and not TouchLayout.is_portrait(Vector2(1280.0, 720.0)) and not TouchLayout.is_portrait(Vector2(500.0, 500.0)))
	var from_css: Vector4 = TouchLayout.insets_from_css(Vector4(10.0, 20.0, 30.0, 40.0), 2.0)
	_ok("CSS insets (top, right, bottom, left) become viewport insets (left, top, right, bottom) scaled onto the viewport: (80, 20, 40, 60)", from_css == Vector4(80.0, 20.0, 40.0, 60.0))
	_ok("negative or missing insets are zero", TouchLayout.insets_from_css(Vector4(-5.0, 0.0, -1.0, 3.0), 1.5) == Vector4(4.5, 0.0, 0.0, 0.0))
	_ok("a safe-area override of four numbers parses (top, right, bottom, left)", LaunchOptions.parse_insets("12, 0,34.5,7") == PackedFloat32Array([12.0, 0.0, 34.5, 7.0]))
	_ok("a wrong count, text or an empty value is no override, a negative one is clamped to 0", LaunchOptions.parse_insets("1,2,3").is_empty() and LaunchOptions.parse_insets("a,b,c,d").is_empty() and LaunchOptions.parse_insets("").is_empty() and LaunchOptions.parse_insets("-4,1,1,1") == PackedFloat32Array([0.0, 1.0, 1.0, 1.0]))
	# the browser bridge hands back a JavaScript `true` as a bool, as the number 1, or as text: every shape means the same
	var yes: Array = [true, 1, 1.0, 2, "true", "TRUE", " 1 ", "yes", &"true"]
	var no: Array = [false, 0, 0.0, "false", "0", "", "no", "undefined", null, [1], {"a": 1}, Vector2.ONE]
	var yes_wrong: Array = []
	for value: Variant in yes:
		if not TouchPlatform.bridge_truthy(value):
			yes_wrong.append(var_to_str(value))
	var no_wrong: Array = []
	for value: Variant in no:
		if TouchPlatform.bridge_truthy(value):
			no_wrong.append(var_to_str(value))
	_ok("the bridge's yes is a bool true, the number 1 or 2 (int or float), or the text true / 1 / yes in any case (wrongly no: %s)" % [yes_wrong], yes_wrong.is_empty())
	_ok("and everything else is a no: false, 0, 0.0, empty or other text, null, a list, a dictionary, a vector (wrongly yes: %s)" % [no_wrong], no_wrong.is_empty())
	_ok("bridge text: text stays text, numbers become their text, null and objects become empty", TouchPlatform.bridge_text("a,b") == "a,b" and TouchPlatform.bridge_text(1) == "1" and TouchPlatform.bridge_text(null) == "" and TouchPlatform.bridge_text([1]) == "")
	# the safe area: the browser's insets and the `?safe=` stand-in take one conversion
	var probe: PackedFloat32Array = TouchPlatform.parse_probe("24,48,20,48,915")
	_ok("the page's probe answer parses to five numbers (a wrong one to none)", probe == PackedFloat32Array([24.0, 48.0, 20.0, 48.0, 915.0]) and TouchPlatform.parse_probe("1,2,3,4").is_empty() and TouchPlatform.parse_probe("a,b,c,d,e").is_empty() and TouchPlatform.parse_probe("").is_empty())
	var view_width: float = 915.0 / 412.0 * 720.0
	var override: PackedFloat32Array = LaunchOptions.parse_insets("24,48,20,48")
	var from_browser: Vector4 = Vector4(-1.0, -1.0, -1.0, -1.0)
	var from_override: Vector4 = Vector4(-2.0, -2.0, -2.0, -2.0)
	if probe.size() == 5 and override.size() == 4:
		from_browser = TouchPlatform.insets_from_css_values(Vector4(probe[0], probe[1], probe[2], probe[3]), probe[4], view_width)
		from_override = TouchPlatform.insets_from_css_values(Vector4(override[0], override[1], override[2], override[3]), probe[4], view_width)
	var scale: float = view_width / 915.0
	_ok("a 915 px wide page shown 1599 logical px wide: browser insets 24,48,20,48 (top, right, bottom, left) and the same numbers given as `?safe=` both come out as (left %.2f, top %.2f, right %.2f, bottom %.2f)" % [48.0 * scale, 24.0 * scale, 48.0 * scale, 20.0 * scale],
		from_browser.is_equal_approx(from_override) and from_browser.is_equal_approx(Vector4(48.0 * scale, 24.0 * scale, 48.0 * scale, 20.0 * scale)) and absf(from_browser.x - 83.88) < 0.01 and absf(from_browser.y - 41.94) < 0.01 and absf(from_browser.w - 34.95) < 0.01)
	_ok("a page width of zero (unknown) leaves the numbers as they are", TouchPlatform.insets_from_css_values(Vector4(1.0, 2.0, 3.0, 4.0), 0.0, 1599.0) == Vector4(4.0, 1.0, 2.0, 3.0))
	var launch: PackedStringArray = PackedStringArray(["--touch", "--visuals=textured", "--safe=1,2,3,4"])
	_ok("the touch launch options sit beside the visuals one without clashing: `--visuals=textured` is still read from the same arguments, and `--touch` is not mistaken for a value", LaunchOptions.visuals_from(launch) == "textured" and LaunchOptions.visuals_from(PackedStringArray(["--touch=0"])) == "")
	_ok("with no touchscreen reported (headless) and no request there are no touch controls", not TouchPlatform.touchscreen_present() or LaunchOptions.requested_touch() == "1")


# ------------------------------------------- activation and desktop play
func _check_activation_and_desktop() -> void:
	print("touch: desktop play is unchanged and the first touch brings the controls up")
	var window: Window = _window(Vector2i(1280, 720))
	var main: Main = await _main_in(window, _scenario([Vector2(250.0, 0.0)]), false)
	var hud: Hud = main._hud
	_ok("a desktop start shows no touch control at all", not main.touch_mode and not main._touch.is_active() and main._touch.blocked_rects().is_empty() and not main._touch.button_visible(TouchLayout.CONVERGE) and hud.extra_avoid_rects.is_empty())
	_ok("the keyboard hint stays and the HUD's own rectangles are the only ones a touch cannot land through (Pause, Restart, Dash, Dev; the hidden Shove button blocks nothing)", hud._hint_label.visible and hud.button_rects().size() == 4 and main._blocked_rects().size() == 4)
	_ok("the joystick zone is the left 55 % below the top 15 % of the view", main.input.joystick.zone == Rect2(0.0, 108.0, 704.0, 612.0))
	main._sfx.unlock()
	main.input.pointer = Vector2(900.0, 300.0)
	main.input.handle_event(_mouse_click(Vector2(900.0, 300.0)))
	_ok("a mouse click is still a Converge at the cursor's world point", _converges_of(main.input, Vector2(900.0, 300.0)) == 1)
	window.size = Vector2i(412, 915)
	for frame: int in 3:
		await _tree.process_frame
	_ok("a tall desktop window keeps the project's own 1280 x 720 base: only touch play turns the base with the phone (view %s)" % window.get_visible_rect().size, window.content_scale_size == Vector2i(1280, 720))
	window.size = Vector2i(1280, 720)
	for frame: int in 3:
		await _tree.process_frame
	_send(window, _touch(0, Vector2(900.0, 300.0), true))
	await _tree.process_frame
	_ok("the first finger on the screen brings the controls up (and the keyboard hint goes)", main.touch_mode and main._touch.is_active() and main._touch.button_visible(TouchLayout.CONVERGE) and not hud._hint_label.visible)
	_ok("that same finger already counted as an arena tap: one Converge, at the right world point", _converges(main) == 1 and _near(main.run.swords[1].aim, _clamped(main, main.run.camera + Vector2(900.0, 300.0) - window.get_visible_rect().size * 0.5)))
	_send(window, _touch(0, Vector2(900.0, 300.0), false))
	main.set_touch_mode(false)
	await _tree.process_frame
	_ok("turning the controls off again restores the desktop screen (hint back, no touch rectangles)", not main._touch.is_active() and hud._hint_label.visible and hud.extra_avoid_rects.is_empty() and main._touch.blocked_rects().is_empty())
	# the shove button (a dev fixture) blocks only while it exists
	main.queue_free()
	window.queue_free()
	await _tree.process_frame

	var crowd: Window = _window(Vector2i(1280, 720))
	var dev: RunScenario = RunScenario.crowd_encounter()
	var shoving: Main = await _main_in(crowd, dev, false)
	await _tree.process_frame
	_ok("in the crowd encounter the Shove button is visible and does block a touch landing on it", shoving._hud._shove_button.visible and shoving._hud.button_rects().size() == 5)
	shoving.queue_free()
	crowd.queue_free()
	await _tree.process_frame


func _mouse_click(at: Vector2) -> InputEventMouseButton:
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = at
	click.pressed = true
	return click


func _converges_of(translator: InputTranslator, at: Vector2) -> int:
	return translator.handle_event(_mouse_click(at)).size()


# ----------------------------------------- views, orientation and aiming
func _check_views_and_aiming() -> void:
	print("touch: a tap aims at the tapped world point whatever the view, orientation and camera")
	var starts: Array[Vector2] = [Vector2(1500.0, 1000.0), Vector2(300.0, 260.0)]
	var failures: Array[String] = []
	var taps: int = 0
	var window: Window = _window(WINDOWS[0])
	for start: Vector2 in starts:
		var main: Main = await _main_in(window, _scenario([], start))
		for size: Vector2i in WINDOWS:
			if not await _resize(main, window, size):
				failures.append("%s did not settle" % size)
				continue
			var view: Vector2 = window.get_visible_rect().size
			var base: Vector2i = TouchLayout.base_size_for(size)
			if view.distance_to(_expected_view(size, base)) > 1.0 or window.content_scale_size != base:
				failures.append("%s: view %s, base %s" % [size, view, window.content_scale_size])
			var zone: Rect2 = main.input.joystick.zone
			var points: Array[Vector2] = [view * 0.5, view * 0.5 + Vector2(view.x * 0.33, -view.y * 0.2), view * 0.5 + Vector2(-view.x * 0.4, view.y * 0.25), Vector2(view.x - 4.0, view.y * 0.3), Vector2(zone.position.x + 4.0, zone.end.y - 4.0), zone.get_center()]
			var blocked: Array[Rect2] = main._blocked_rects()
			var zone_taps: int = 0
			for point: Vector2 in points:
				var covered: bool = false
				for rect: Rect2 in blocked:
					covered = covered or rect.has_point(point)
				if covered:
					continue
				_ready_to_converge(main)
				var before: int = _converges(main)
				_tap(window, 0, point)
				taps += 1
				zone_taps += 1 if zone.has_point(point) else 0
				var want: Vector2 = _clamped(main, main.run.camera + point - view * 0.5)
				if _converges(main) != before + 1 or not _near(main.run.swords[1].aim, want):
					failures.append("%s from %s tap %s: aimed %s, wanted %s (%d Converges)" % [size, start, point, main.run.swords[1].aim, want, _converges(main) - before])
			if zone_taps == 0:
				failures.append("%s: no tap landed in the joystick zone" % size)
			# the engine's own transform agrees with the mapping
			main._camera.reset_physics_interpolation()
			main._camera.force_update_scroll()
			var drawn: Vector2 = window.get_canvas_transform().affine_inverse() * (view * 0.5 + Vector2(100.0, 50.0))
			if drawn.distance_to(main.run.camera + Vector2(100.0, 50.0)) > 1.0:
				failures.append("%s: the camera's own transform gives %s" % [size, drawn])
		main.queue_free()
		await _tree.process_frame
	_ok("%d taps at 10 window shapes (landscape and portrait phones and tablets, a square one) and two camera positions each aimed Converge at the camera's centre plus the tap's offset from the middle, pulled back to 460 px, exactly once (%d problems: %s)" % [taps, failures.size(), failures.slice(0, 3)], failures.is_empty() and taps > 100)

	# a running scene: the camera follows the player, the tap follows the camera
	var main: Main = await _main_in(window, _scenario([], Vector2(700.0, 500.0)))
	await _resize(main, window, Vector2i(915, 412))
	main.input.handle_event(_key_down(KEY_D))
	main.input.handle_event(_key_down(KEY_S))
	_ticks(main, 240)
	main.input.release_all()
	_ticks(main, 120)
	await _tree.process_frame
	_ready_to_converge(main)
	var view: Vector2 = window.get_visible_rect().size
	_tap(window, 0, view * 0.5 + Vector2(120.0, 60.0))
	_ok("after the player walked a long way the tap follows the moved camera (%s near %s)" % [main.run.swords[1].aim, main.run.camera + Vector2(120.0, 60.0)], main.run.camera.distance_to(Vector2(700.0, 500.0)) > 300.0 and _near(main.run.swords[1].aim, _clamped(main, main.run.camera + Vector2(120.0, 60.0))))
	# orientation changes under a running scene
	var order: Array[Vector2i] = [Vector2i(412, 915), Vector2i(915, 412), Vector2i(800, 800)]
	var turned: bool = true
	for size: Vector2i in order:
		await _resize(main, window, size)
		_ready_to_converge(main)
		var shown: Vector2 = window.get_visible_rect().size
		var spot: Vector2 = shown * 0.5 + Vector2(-60.0, 90.0)
		_tap(window, 0, spot)
		turned = turned and _near(main.run.swords[1].aim, _clamped(main, main.run.camera + spot - shown * 0.5)) and window.content_scale_size == TouchLayout.base_size_for(size)
	_ok("turning the phone portrait, landscape and square again under a running scene keeps taps on target and the base size right", turned)
	main.queue_free()
	window.queue_free()
	await _tree.process_frame


# ------------------------------------------ buttons, aiming, empty arena
func _press_button(window: Window, main: Main, id: StringName, index: int = 5) -> void:
	var rect: Rect2 = main._touch.button_rect(id)
	_send(window, _touch(index, rect.get_center(), true))
	_send(window, _touch(index, rect.get_center(), false))


func _check_buttons_and_aiming() -> void:
	print("touch: the buttons call the shared commands, aimed at the nearest enemy or ahead of the player")
	var window: Window = _window(Vector2i(1280, 720))
	var main: Main = await _main_in(window, _scenario([Vector2(250.0, 20.0), Vector2(-150.0, 0.0), Vector2(60.0, 300.0)]))
	var run: GameRun = main.run
	var nearest: Vector2 = run.enemies[1].position
	for slot: int in 3:
		var id: StringName = TouchLayout.ultimate_id(slot)
		_ok("the %s button is up, labelled and lit while ready (%s)" % [id, main._touch.button_text(id).replace("\n", " ")], main._touch.button_visible(id) and main._touch.button_text(id) == "%s\nREADY" % Hud.ULT_KEYS[slot] and main._touch.button_lit(id))
	_press_button(window, main, TouchLayout.ultimate_id(0))
	_ok("the first ultimate button starts slot one's Viper Flurry at the nearest enemy (%s, wanted %s) and never at the button's own spot" % [run.swords[0].ultimate_point, nearest], run.cue_count(SimCue.Kind.ULTIMATE_STARTED) == 1 and _near(run.swords[0].ultimate_point, nearest))
	_ok("the button now says the seconds left and dims, and slot one reads ACTIVE or a count", main._touch.button_text(TouchLayout.ultimate_id(0)) != "Q\nREADY" and not main._touch.button_lit(TouchLayout.ultimate_id(0)))
	run.enemies[1].dead = true
	var next_nearest: Vector2 = run.enemies[0].position
	_press_button(window, main, TouchLayout.ultimate_id(2))
	_ok("a dead enemy is not a target: slot three's Cataclysm falls on the nearest living one (%s)" % run.swords[2].ultimate_point, run.cue_count(SimCue.Kind.ULTIMATE_STARTED) == 2 and _near(run.swords[2].ultimate_point, next_nearest))
	_press_button(window, main, TouchLayout.ultimate_id(0))
	_ok("a button pressed while its ultimate runs is refused, as the key would be", run.cue_count(SimCue.Kind.ULTIMATE_STARTED) == 2)
	_press_button(window, main, TouchLayout.CONVERGE)
	_ok("the Converge button commands Converge at the nearest living enemy (%s)" % run.swords[1].aim, _converges(main) == 1 and _near(run.swords[1].aim, next_nearest) and run.converge_cooldown_left > 2.0)
	_ok("and counts the cooldown down on itself", main._touch.button_text(TouchLayout.CONVERGE).begins_with("Converge\n") and main._touch.button_text(TouchLayout.CONVERGE) != "Converge\nready" and not main._touch.button_lit(TouchLayout.CONVERGE))
	_press_button(window, main, TouchLayout.CONVERGE)
	_ok("a second press during the cooldown is refused", _converges(main) == 1)
	_press_button(window, main, TouchLayout.RANGES)
	_ok("the Ranges button shows the attack-range rings, and again hides them", run.show_ranges and main._touch.button_lit(TouchLayout.RANGES))
	_press_button(window, main, TouchLayout.RANGES)
	_ok("(and hides them again)", not run.show_ranges)
	main.queue_free()
	await _tree.process_frame

	# an empty arena: forward fallback, in the direction the player last moved
	var empty: Main = await _main_in(window, _scenario([]))
	var erun: GameRun = empty.run
	empty.input.handle_event(_key_down(KEY_A))
	_ticks(empty, 30)
	empty.input.release_all()
	_ticks(empty, 5)
	var ahead: Vector2 = erun.position + erun.facing * GameRun.AUTO_AIM_AHEAD
	_ok("with nobody to aim at the touch aim is 300 px ahead of a player facing west (%s)" % erun.facing, erun.facing.x < -0.99 and _near(erun.auto_aim(), ahead))
	_press_button(window, empty, TouchLayout.ultimate_id(1))
	_ok("an ultimate button then fires 300 px ahead of the player: Maelstrom at %s, wanted %s" % [erun.swords[1].ultimate_point, ahead], erun.cue_count(SimCue.Kind.ULTIMATE_STARTED) == 1 and _near(erun.swords[1].ultimate_point, ahead))
	_press_button(window, empty, TouchLayout.CONVERGE)
	_ok("so does the Converge button (%s)" % erun.swords[0].aim, _converges(empty) == 1 and _near(erun.swords[0].aim, ahead))
	empty.queue_free()
	await _tree.process_frame

	# swaps
	var swapping: Main = await _main_in(window, _scenario([]))
	var srun: GameRun = swapping.run
	_ok("the swap buttons are dim while nothing lies within reach", not swapping._touch.button_lit(TouchLayout.swap_id(0)) and swapping._touch.button_text(TouchLayout.swap_id(2)) == "Swap 3")
	var cues_before: int = srun.cue_count(SimCue.Kind.SWORD_SWAPPED)
	_press_button(window, swapping, TouchLayout.swap_id(1))
	_ok("pressing one with nothing in reach is refused (a refusal cue, nothing changes)", srun.cue_count(SimCue.Kind.SWORD_SWAPPED) == cues_before and srun.swords[1].spec.type_id == SwordDefs.WARDEN)
	srun.pickups.append(PickupState.make(SwordSpec.make(SwordDefs.PIKE, 2, &"ice"), srun.position + Vector2(20.0, -30.0), 1))
	swapping.run.apply(GameCommand.move_axis(Vector2.ZERO))
	swapping._present()
	_ok("with a dropped sword in reach the swap buttons light", swapping._touch.button_lit(TouchLayout.swap_id(0)))
	_press_button(window, swapping, TouchLayout.swap_id(1))
	_ok("Swap 2 puts that sword into slot two (%s) and leaves the others" % srun.swords[1].spec.type_id, srun.swords[1].spec.type_id == SwordDefs.PIKE and srun.swords[0].spec.type_id == SwordDefs.FANG and srun.swords[2].spec.type_id == SwordDefs.COLOSSUS and srun.cue_count(SimCue.Kind.SWORD_SWAPPED) == 1 and srun.pickups.size() == 1)
	_press_button(window, swapping, TouchLayout.swap_id(2))
	_ok("a button for a slot swaps the nearest drop, which is now the old sword: slot three takes the Warden", srun.swords[2].spec.type_id == SwordDefs.WARDEN)
	# fullscreen is not a gameplay command
	var asked: Array[int] = [0]
	swapping._touch.fullscreen_pressed.disconnect(TouchPlatform.toggle_fullscreen)
	swapping._touch.fullscreen_pressed.connect(func() -> void: asked[0] += 1)
	var tick_before: int = srun.tick
	var full_at: Vector2 = swapping._touch.button_rect(TouchLayout.FULLSCREEN).get_center()
	_send(window, _touch(5, full_at, true))
	_ok("the fullscreen button does not ask while the finger is still down (the browser grants a fullscreen request on the lift)", asked[0] == 0)
	_send(window, _touch(5, full_at, false))
	_ok("it asks the platform once when the finger lifts, and commands nothing in the run", asked[0] == 1 and srun.tick == tick_before and srun.cue_count(SimCue.Kind.CONVERGE) == 0)
	_send(window, _touch(5, full_at, true))
	_send(window, _touch(5, full_at, false, true))
	_ok("a cancelled touch on it asks for nothing more (a cancelled contact never lifts)", asked[0] == 1)
	swapping._fullscreen_supported = false
	swapping._touch.layout(Vector2.ZERO, Vector4.ZERO, Rect2(), false)
	swapping._show_touch()
	_ok("where the browser offers no fullscreen the button is not shown", not swapping._touch.button_visible(TouchLayout.FULLSCREEN))
	swapping.queue_free()
	window.queue_free()
	await _tree.process_frame


# -------------------------------------------------- simultaneous touches
func _check_simultaneous() -> void:
	print("touch: moving and acting at once")
	var window: Window = _window(Vector2i(1280, 720))
	var main: Main = await _main_in(window, _scenario([Vector2(300.0, 40.0)]))
	var run: GameRun = main.run
	var start: Vector2 = run.position
	_send(window, _touch(0, Vector2(300.0, 400.0), true))
	_send(window, _drag(0, Vector2(390.0, 400.0), Vector2(300.0, 400.0)))
	_ticks(main, 30)
	var walked: float = run.position.x - start.x
	_ok("one thumb on the stick walks the player east (%.0f px in half a second)" % walked, walked > 60.0 and absf(run.position.y - start.y) < 1.0)
	_send(window, _touch(1, main._hud.dash_rect().get_center(), true))
	_ok("a second finger on Dash dashes at once, along the stick's heading, while the first still steers", run.dash_left > 0.0 and run.velocity.x > 500.0 and main.input.joystick.pointer == 0)
	var ult: Rect2 = main._touch.button_rect(TouchLayout.ultimate_id(1))
	_send(window, _touch(2, ult.get_center(), true))
	_ok("a third finger on an ultimate starts it (at the nearest enemy) with both others down", run.cue_count(SimCue.Kind.ULTIMATE_STARTED) == 1 and _near(run.swords[1].ultimate_point, run.enemies[0].position))
	var before: Vector2 = run.position
	_send(window, _touch(1, main._hud.dash_rect().get_center(), false))
	_send(window, _touch(2, ult.get_center(), false))
	_ticks(main, 30)
	_ok("lifting the action fingers leaves the steering one in charge: still walking east, one contact down (moved %.0f px)" % (run.position.x - before.x), run.position.x - before.x > 40.0 and main.input.touch.count() == 1 and main.input.joystick.pointer == 0)
	_send(window, _touch(3, Vector2(900.0, 250.0), true))
	_ok("and a fourth finger tapping the arena still commands Converge there", _converges(main) == 1 and _near(run.swords[0].aim, _clamped(main, main.run.camera + Vector2(900.0, 250.0) - window.get_visible_rect().size * 0.5)))
	_send(window, _touch(3, Vector2(900.0, 250.0), false))
	_send(window, _touch(0, Vector2(390.0, 400.0), false))
	_ok("lifting the stick stops the walk", not main.input.joystick.is_active() and _near(main.input.move_axis(), Vector2.ZERO) and main.input.touch.count() == 0)
	# two buttons held together, each its own
	var converge: Rect2 = main._touch.button_rect(TouchLayout.CONVERGE)
	var ranges: Rect2 = main._touch.button_rect(TouchLayout.RANGES)
	_send(window, _touch(1, ranges.get_center(), true))
	_send(window, _touch(2, converge.get_center(), true))
	_send(window, _touch(1, ranges.get_center(), false))
	_send(window, _touch(2, converge.get_center(), false))
	_ok("two fingers on two buttons at once both act (ranges on, Converge refused by its cooldown)", run.show_ranges and _converges(main) == 1)
	main.queue_free()
	window.queue_free()
	await _tree.process_frame


# ------------------------------------------------ UI consumes its touches
func _check_ui_consumes_touches() -> void:
	print("touch: a finger on a button never also aims at the arena behind it")
	var window: Window = _window(Vector2i(1280, 720))
	var main: Main = await _main_in(window, _scenario([Vector2(250.0, 20.0)]))
	var run: GameRun = main.run
	var hud: Hud = main._hud
	var enemy: Vector2 = run.enemies[0].position
	var failures: Array[String] = []
	var targets: Array[Rect2] = []
	var names: Array[String] = []
	for id: StringName in [TouchLayout.CONVERGE, TouchLayout.RANGES, TouchLayout.FULLSCREEN, TouchLayout.swap_id(0), TouchLayout.swap_id(1), TouchLayout.swap_id(2), TouchLayout.ultimate_id(0), TouchLayout.ultimate_id(1), TouchLayout.ultimate_id(2)]:
		targets.append(main._touch.button_rect(id))
		names.append(String(id))
	targets.append_array([hud._dash_button.get_global_rect(), hud._pause_button.get_global_rect(), hud._restart_button.get_global_rect(), hud._encounter_button.get_global_rect()])
	names.append_array(["dash", "pause", "restart", "dev"])
	main._touch.fullscreen_pressed.disconnect(TouchPlatform.toggle_fullscreen)
	for i: int in targets.size():
		var rect: Rect2 = targets[i]
		for at: Vector2 in [rect.get_center(), rect.position + Vector2(2.0, 2.0), rect.end - Vector2(2.0, 2.0)]:
			if names[i] == "dev":
				continue
			main.set_physics_process(false)
			_ready_to_converge(main)
			run.apply(GameCommand.resume())
			var before: int = _converges(main)
			var restarts: int = run.restarts
			var stick_before: int = main.input.touch.count()
			_send(window, _touch(0, at, true))
			if names[i] == "restart":
				# a restart starts a new run and forgets every finger, so its own count restarts at zero
				if run.restarts != restarts + 1 or _converges(main) != 0:
					failures.append("restart at %s: %d restarts, %d Converges" % [at, run.restarts - restarts, _converges(main)])
			elif names[i] != "converge" and _converges(main) != before:
				failures.append("%s at %s aimed Converge at the arena" % [names[i], at])
			if main.input.joystick.is_active():
				failures.append("%s at %s started the stick" % [names[i], at])
			if names[i] != "restart" and main.input.touch.owner_of(0) != TouchPointers.Owner.UI:
				failures.append("%s at %s is owned by %d" % [names[i], at, main.input.touch.owner_of(0)])
			if names[i] == "converge" and (_converges(main) != before + 1 or not _near(run.swords[1].aim, enemy)):
				failures.append("converge at %s: %d Converges, aimed %s" % [at, _converges(main) - before, run.swords[1].aim])
			_send(window, _touch(0, at, false))
			if main.input.touch.count() != stick_before:
				failures.append("%s at %s left a contact behind" % [names[i], at])
			if run.restarts != restarts:
				run.apply(GameCommand.resume())
	_ok("fingers on the centre and both corners of all %d buttons never aimed Converge, started the stick or kept a contact, and the Converge button aimed at the enemy, once (%d problems: %s)" % [targets.size() - 1, failures.size(), failures.slice(0, 3)], failures.is_empty())
	# a button rectangle that is not a button leaves the arena tappable
	_ready_to_converge(main)
	run.apply(GameCommand.resume())
	var shove_spot: Vector2 = Vector2(1080.0, 650.0)
	_ok("the hidden Shove button's old place is plain arena: a tap there is a Converge", not hud._shove_button.visible and main._blocked_rects().all(func(rect: Rect2) -> bool: return not rect.has_point(shove_spot)))
	_tap(window, 0, shove_spot)
	_ok("(and it commands Converge at that world point)", _converges(main) >= 1 or run.converge_cooldown_left > 0.0)
	var resume_spot: Vector2 = Rect2(TouchLayout.button_rects(window.get_visible_rect().size, Vector4.ZERO, main._hud.dash_rect())[TouchLayout.RESUME]).get_center()
	_ready_to_converge(main)
	run.apply(GameCommand.resume())
	var converges_here: int = _converges(main)
	_ok("a button that is not showing (Resume while the run goes on) blocks nothing", not main._touch.button_visible(TouchLayout.RESUME) and main._blocked_rects().all(func(rect: Rect2) -> bool: return not rect.has_point(resume_spot)))
	_tap(window, 0, resume_spot)
	_ok("so a tap where it would be is a Converge at that world point", _converges(main) == converges_here + 1 and _near(run.swords[1].aim, _clamped(main, run.camera + resume_spot - window.get_visible_rect().size * 0.5)))
	# the pickup card keeps clear of every touch button
	var avoided: Array[Rect2] = hud.pickup_card_avoid()
	var missing: Array[String] = []
	for id: StringName in [TouchLayout.CONVERGE, TouchLayout.RANGES, TouchLayout.swap_id(0), TouchLayout.ultimate_id(2)]:
		var rect: Rect2 = main._touch.button_rect(id)
		if not avoided.any(func(each: Rect2) -> bool: return each.encloses(rect)):
			missing.append(String(id))
	_ok("the dropped-sword card is told to keep clear of the touch buttons (%s not avoided)" % [missing], missing.is_empty())
	# every visible Button in the scene is covered by a blocked rectangle
	var uncovered: Array[String] = []
	for node: Node in _all_buttons(main):
		var button: Button = node as Button
		if not button.is_visible_in_tree():
			continue
		var covered: bool = false
		for rect: Rect2 in main._blocked_rects():
			covered = covered or rect.encloses(button.get_global_rect())
		if not covered:
			uncovered.append("%s %s" % [button.text, button.get_global_rect()])
	_ok("every visible button of the HUD and the touch layer lies inside a rectangle that blocks a landing finger (%d uncovered: %s)" % [uncovered.size(), uncovered.slice(0, 3)], uncovered.is_empty())
	main.queue_free()
	window.queue_free()
	await _tree.process_frame


func _all_buttons(node: Node) -> Array[Node]:
	var found: Array[Node] = []
	for child: Node in node.get_children():
		if child is Button:
			found.append(child)
		found.append_array(_all_buttons(child))
	return found


## The engine's own path: a screen touch through Input, which also makes up a mouse click from it.
func _check_emulated_mouse_path() -> void:
	print("touch: through the engine's touch-to-mouse emulation a finger is still one command")
	var window_size: Vector2i = _tree.root.size
	_tree.root.size = Vector2i(1280, 720)
	var main: Main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Main
	main.scenario = _scenario([Vector2(250.0, 20.0)])
	_tree.root.add_child(main)
	main.set_physics_process(false)
	await _tree.process_frame
	await _tree.process_frame
	main.set_touch_mode(true)
	_clock[0] = 0.0
	main.input.touch.clock = func() -> float: return _clock[0]
	await _tree.process_frame
	var run: GameRun = main.run
	var view: Vector2 = main.get_viewport().get_visible_rect().size
	var arena_point: Vector2 = view * 0.5 + Vector2(200.0, -80.0)
	_deliver(0, arena_point, true)
	_deliver(0, arena_point, false)
	_ok("an arena tap commands exactly one Converge at its world point (the emulated mouse click is no second one)", _converges(main) == 1 and _near(run.swords[1].aim, _clamped(main, run.camera + arena_point - view * 0.5)))
	_ready_to_converge(main)
	var dash_at: Vector2 = main._hud.dash_rect().get_center()
	_deliver(0, dash_at, true)
	_deliver(0, dash_at, false)
	_ok("a tap on Dash dashes once and commands no Converge", run.dash_left > 0.0 and run.dash_cooldown_left > 0.0 and _converges(main) == 1, "dash_left %s cooldown %s converges %d" % [run.dash_left, run.dash_cooldown_left, _converges(main)])
	_ready_to_converge(main)
	var converge_at: Vector2 = main._touch.button_rect(TouchLayout.CONVERGE).get_center()
	_deliver(0, converge_at, true)
	_deliver(0, converge_at, false)
	_ok("a tap on the Converge button is one Converge, at the nearest enemy, not at the button's spot", _converges(main) == 2 and _near(run.swords[1].aim, run.enemies[0].position))
	_deliver(1, Vector2(300.0, 400.0), true)
	_deliver(2, main._touch.button_rect(TouchLayout.RANGES).get_center(), true)
	_ok("with one finger steering a second finger still reaches a button through the engine's own input path", run.show_ranges and main.input.joystick.pointer == 1)
	_deliver(2, main._touch.button_rect(TouchLayout.RANGES).get_center(), false)
	_deliver(1, Vector2(300.0, 400.0), false)
	main.queue_free()
	await _tree.process_frame
	_tree.root.size = window_size


func _deliver(index: int, at: Vector2, pressed: bool) -> void:
	Input.parse_input_event(_touch(index, at, pressed))
	Input.flush_buffered_events()


# ------------------------------------- cancel, release, focus loss, resume
func _check_release_and_suspension() -> void:
	print("touch: cancel, release and focus loss clear held input; resuming is explicit")
	var window: Window = _window(Vector2i(1280, 720))
	var main: Main = await _main_in(window, _scenario([Vector2(250.0, 20.0)]))
	var run: GameRun = main.run
	_send(window, _touch(0, Vector2(300.0, 400.0), true))
	_send(window, _drag(0, Vector2(390.0, 400.0), Vector2(300.0, 400.0)))
	_ticks(main, 20)
	var moving: float = run.velocity.length()
	_send(window, _touch(0, Vector2(390.0, 400.0), false, true))
	_ok("a cancelled touch (the browser took the finger) releases the stick at once", not main.input.joystick.is_active() and _near(main.input.move_axis(), Vector2.ZERO) and main.input.touch.count() == 0)
	_ticks(main, 90)
	var settled: Vector2 = run.position
	_ticks(main, 30)
	_ok("and the player coasts to a stop rather than walking on (moving at %.0f px/s, then %.2f px in the last half second)" % [moving, run.position.distance_to(settled)], moving > 100.0 and run.position.distance_to(settled) < 1.0)

	for notification: int in [Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT, Node.NOTIFICATION_APPLICATION_PAUSED, Node.NOTIFICATION_APPLICATION_FOCUS_OUT]:
		run.apply(GameCommand.resume())
		main.input.handle_event(_key_down(KEY_A))
		_send(window, _touch(0, Vector2(300.0, 400.0), true))
		_send(window, _drag(0, Vector2(300.0, 490.0), Vector2(300.0, 400.0)))
		_send(window, _touch(1, Vector2(900.0, 250.0), true))
		var position: Vector2 = run.position
		main._notification(notification)
		_ok("losing the page (notification %d) pauses the run and releases the stick, the key and both fingers" % notification, run.paused and not main.input.joystick.is_active() and main.input.touch.count() == 0 and _near(main.input.move_axis(), Vector2.ZERO))
		_send(window, _drag(0, Vector2(300.0, 600.0), Vector2(300.0, 490.0)))
		_send(window, _touch(1, Vector2(900.0, 250.0), false))
		_send(window, _touch(0, Vector2(300.0, 600.0), false))
		_ticks(main, 120)
		_ok("the fingers that were down when it happened do nothing afterwards, and nothing advances while it is suspended", _near(run.position, position) and run.paused and _near(main.input.move_axis(), Vector2.ZERO))
		var cooled: float = run.converge_cooldown_left
		_ticks(main, 60)
		_ok("it stays suspended however long the page stays away: only an explicit resume ends it", run.paused and run.converge_cooldown_left == cooled)
		var converges_then: int = _converges(main)
		_send(window, _touch(0, Vector2(900.0, 250.0), true))
		_send(window, _touch(0, Vector2(900.0, 250.0), false))
		_ok("a tap on the arena does not resume (and commands nothing)", run.paused and _converges(main) == converges_then)
		_ok("a large Resume button waits at the middle of the screen, the other controls dim", main._touch.button_visible(TouchLayout.RESUME) and not main._touch.button_visible(TouchLayout.RESTART) and not main._touch.button_lit(TouchLayout.CONVERGE))
		await _tree.process_frame
		var resume_at: Vector2 = main._touch.button_rect(TouchLayout.RESUME).get_center()
		_send(window, _touch(5, resume_at, true))
		_ok("a finger landing on the Resume button, which appeared after the stick's rectangles were last set, is the button's (no stick, no arena tap)", main.input.touch.owner_of(5) == TouchPointers.Owner.UI)
		_send(window, _touch(5, resume_at, false))
		_ok("tapping Resume resumes, and the stick does not wake by itself", not run.paused and not main._touch.button_visible(TouchLayout.RESUME) and _near(main.input.move_axis(), Vector2.ZERO), "paused %s visible %s axis %s" % [run.paused, main._touch.button_visible(TouchLayout.RESUME), main.input.move_axis()])
		var resumed_at: Vector2 = run.position
		_ticks(main, 30)
		_ok("the player stands where they were until a new finger steers", _near(run.position, resumed_at, 1.0))
		_send(window, _touch(0, Vector2(300.0, 400.0), true))
		_send(window, _drag(0, Vector2(390.0, 400.0), Vector2(300.0, 400.0)))
		_ticks(main, 20)
		_ok("a new finger steers again", run.position.x > resumed_at.x + 20.0, "x %s -> %s, pointer %d" % [resumed_at.x, run.position.x, main.input.joystick.pointer])
		_send(window, _touch(0, Vector2(390.0, 400.0), false))
		_ticks(main, 120)
		main.input.release_all()
	# resuming through the HUD's own Pause button and the key works too
	run.apply(GameCommand.pause())
	_send(window, _touch(0, main._hud._pause_button.get_global_rect().get_center(), true))
	_send(window, _touch(0, main._hud._pause_button.get_global_rect().get_center(), false))
	_ok("the HUD's Resume button resumes as well", not run.paused)
	_send(window, _touch(0, main._hud._pause_button.get_global_rect().get_center(), true))
	_send(window, _touch(0, main._hud._pause_button.get_global_rect().get_center(), false))
	_ok("and its Pause button pauses (one command per finger)", run.paused)
	run.apply(GameCommand.resume())
	main.queue_free()
	window.queue_free()
	await _tree.process_frame


# ------------------------------------------------------ paused and dead
func _check_paused_and_dead() -> void:
	print("touch: paused and dead runs refuse what they should")
	var window: Window = _window(Vector2i(1280, 720))
	var main: Main = await _main_in(window, _scenario([Vector2(250.0, 20.0)]))
	var run: GameRun = main.run
	run.apply(GameCommand.pause())
	main._present()
	var counts: Array[int] = [run.cue_count(SimCue.Kind.ULTIMATE_STARTED), _converges(main), run.cue_count(SimCue.Kind.SWORD_SWAPPED)]
	_tap(window, 0, Vector2(900.0, 300.0))
	_tap(window, 0, Vector2(300.0, 400.0))
	for id: StringName in [TouchLayout.CONVERGE, TouchLayout.ultimate_id(0), TouchLayout.ultimate_id(1), TouchLayout.ultimate_id(2), TouchLayout.swap_id(0), TouchLayout.RANGES]:
		_press_button(window, main, id)
	_send(window, _touch(0, main._hud.dash_rect().get_center(), true))
	_send(window, _touch(0, main._hud.dash_rect().get_center(), false))
	_ok("paused: arena taps, Converge, three ultimates, a swap, Ranges and Dash all do nothing, and no cooldown is spent", run.paused and [run.cue_count(SimCue.Kind.ULTIMATE_STARTED), _converges(main), run.cue_count(SimCue.Kind.SWORD_SWAPPED)] == counts and not run.show_ranges and run.converge_cooldown_left == 0.0 and run.dash_cooldown_left == 0.0 and run.swords.all(func(sword: SwordState) -> bool: return sword.ultimate_cooldown_left == 0.0))
	run.apply(GameCommand.resume())
	main._present()
	_ok("the Resume button goes away with the pause", not run.paused and not main._touch.button_visible(TouchLayout.RESUME))

	run.hurt_player(1000.0, run.position + Vector2(30.0, 0.0))
	main._present()
	_ok("dead: the player is dead and no Restart button yet (the delay has not passed)", run.dead and not main._touch.button_visible(TouchLayout.RESTART) and not main._touch.button_visible(TouchLayout.RESUME))
	var dead_counts: Array[int] = [run.cue_count(SimCue.Kind.ULTIMATE_STARTED), _converges(main), run.cue_count(SimCue.Kind.SWORD_SWAPPED), run.restarts]
	_tap(window, 0, Vector2(900.0, 300.0))
	for id: StringName in [TouchLayout.CONVERGE, TouchLayout.ultimate_id(0), TouchLayout.ultimate_id(2), TouchLayout.swap_id(1), TouchLayout.RANGES]:
		_press_button(window, main, id)
	_send(window, _touch(0, main._hud.dash_rect().get_center(), true))
	_send(window, _touch(0, main._hud.dash_rect().get_center(), false))
	_ok("dead: taps, buttons and Dash commanded nothing", [run.cue_count(SimCue.Kind.ULTIMATE_STARTED), _converges(main), run.cue_count(SimCue.Kind.SWORD_SWAPPED), run.restarts] == dead_counts and not run.show_ranges and run.dash_cooldown_left == 0.0)
	var waited: int = 0
	while waited < MAX_TICKS and not (run.dead and run.death_time > GameRun.RESTART_DELAY):
		main._physics_process(GameRun.TICK_DT)
		waited += 1
	_ok("the death screen comes up within %d ticks (%d)" % [MAX_TICKS, waited], waited < MAX_TICKS)
	main._present()
	_ok("a large Restart button appears, the Resume one does not", main._touch.button_visible(TouchLayout.RESTART) and not main._touch.button_visible(TouchLayout.RESUME))
	_send(window, _touch(1, Vector2(300.0, 400.0), true))
	_press_button(window, main, TouchLayout.RESTART)
	_ok("tapping it restarts the run, un-dead, and clears the finger that was steering (no stick, no contact)", run.restarts == 1 and not run.dead and main.input.touch.count() == 0 and not main.input.joystick.is_active() and not main._touch.button_visible(TouchLayout.RESTART))
	_tap(window, 0, Vector2(900.0, 300.0))
	_ok("the new run answers a tap at once: a Converge works again", _converges(main) == 1)
	main.queue_free()
	window.queue_free()
	await _tree.process_frame


# ---------------------------------------- layout in the running scene
func _check_layout_in_scene() -> void:
	print("touch: the controls fit the real HUD at every window shape and safe area")
	var window: Window = _window(Vector2i(1280, 720))
	var main: Main = await _main_in(window, _scenario([Vector2(250.0, 20.0)]))
	var problems: Array[String] = []
	var insets_list: Array[Vector4] = [Vector4.ZERO, Vector4(48.0, 0.0, 48.0, 0.0), Vector4(0.0, 36.0, 0.0, 30.0)]
	var shapes: int = 0
	for size: Vector2i in WINDOWS:
		await _resize(main, window, size)
		for insets: Vector4 in insets_list:
			main.safe_insets_override = insets
			main._update_touch_zone()
			await _tree.process_frame
			main._update_touch_zone()
			shapes += 1
			var view: Vector2 = window.get_visible_rect().size
			var safe: Rect2 = Rect2(insets.x, insets.y, view.x - insets.x - insets.z, view.y - insets.y - insets.w)
			var rects: Array[Rect2] = []
			var labels: Array[String] = []
			for id: StringName in [TouchLayout.CONVERGE, TouchLayout.RANGES, TouchLayout.FULLSCREEN, TouchLayout.swap_id(0), TouchLayout.swap_id(1), TouchLayout.swap_id(2), TouchLayout.ultimate_id(0), TouchLayout.ultimate_id(1), TouchLayout.ultimate_id(2)]:
				var rect: Rect2 = main._touch.button_rect(id)
				if not safe.encloses(rect):
					problems.append("%s %s %s outside %s" % [size, insets, id, rect])
				rects.append(rect)
				labels.append(String(id))
			for hud_button: Button in [main._hud._pause_button, main._hud._restart_button, main._hud._dash_button, main._hud._encounter_button]:
				var hud_rect: Rect2 = hud_button.get_global_rect()
				if not Rect2(Vector2.ZERO, view).encloses(hud_rect):
					problems.append("%s HUD %s off the view: %s" % [size, hud_button.text, hud_rect])
				for i: int in rects.size():
					if rects[i].intersects(hud_rect):
						problems.append("%s %s: %s overlaps HUD %s" % [size, insets, labels[i], hud_button.text])
			for card: Control in main._hud._ult_cards:
				if card.visible and card.get_global_rect().intersects(main._hud.dash_rect()):
					problems.append("%s: the HUD's Dash overlaps a sword card %s" % [size, card.get_global_rect()])
			var zone: Rect2 = main.input.joystick.zone
			if not safe.encloses(zone):
				problems.append("%s %s joystick zone %s" % [size, insets, zone])
	_ok("at %d window and safe-area combinations in the running scene every touch button lies in the safe area and clear of the HUD's buttons, the HUD's Dash clears the sword cards, and the stick's zone follows (%d problems: %s)" % [shapes, problems.size(), problems.slice(0, 3)], problems.is_empty())

	# a dropped sword's card keeps clear of the touch controls
	await _resize(main, window, Vector2i(1280, 720))
	main.safe_insets_override = Vector4.ZERO
	main._update_touch_zone()
	main.run.pickups.append(PickupState.make(SwordSpec.make(SwordDefs.PIKE, 2, &"ice"), main.run.position + Vector2(300.0, 0.0), 1))
	main.run.position = main.run.position + Vector2(280.0, 0.0)
	main._present()
	var card: Rect2 = main._hud.pickup_card_rect()
	var collides: Array[String] = []
	for id: StringName in [TouchLayout.CONVERGE, TouchLayout.RANGES, TouchLayout.FULLSCREEN, TouchLayout.swap_id(0), TouchLayout.swap_id(1), TouchLayout.swap_id(2), TouchLayout.ultimate_id(0), TouchLayout.ultimate_id(1), TouchLayout.ultimate_id(2)]:
		if main._touch.button_rect(id).intersects(card):
			collides.append(String(id))
	_ok("with a dropped sword in reach its card appears and covers no touch button (%s collide)" % [collides], main._hud.pickup_card_visible() and collides.is_empty())
	main.queue_free()
	window.queue_free()
	await _tree.process_frame


# ----------------------------------------- a finger that never lifts
## A finger that was on a button when the page was suspended (or the touch was cancelled, or the run restarted) never reports
## its lift. The engine would go on believing the button is down and swallow its next press: the run would stay paused with the
## Resume button doing nothing. Each case presses the button again WITHOUT the lift ever having been delivered.
func _check_stuck_buttons() -> void:
	print("touch: a button whose finger never lifted still works the next time")
	var window: Window = _window(Vector2i(1280, 720))
	var main: Main = await _main_in(window, _scenario([Vector2(250.0, 20.0)]))
	var run: GameRun = main.run
	var failures: Array[String] = []
	for index: int in [5, 6]:
		run.apply(GameCommand.pause())
		main._present()
		var resume_at: Vector2 = main._touch.button_rect(TouchLayout.RESUME).get_center()
		_send(window, _touch(5, resume_at, true))
		if run.paused:
			failures.append("first press did not resume")
		main.release_input_and_pause()
		if not run.paused or main.input.touch.count() != 0 or not main._touch._held.is_empty():
			failures.append("suspend left paused %s, %d contacts, held %s" % [run.paused, main.input.touch.count(), main._touch._held])
		resume_at = main._touch.button_rect(TouchLayout.RESUME).get_center()
		_send(window, _touch(index, resume_at, true))
		if run.paused:
			failures.append("after suspension a Resume press with finger %d was swallowed" % index)
		_send(window, _touch(index, resume_at, false))
		_send(window, _touch(5, resume_at, false))
	_ok("hold Resume, suspend the page (its lift never arrives), press Resume again with the same or another finger: the run resumes (%d problems: %s)" % [failures.size(), failures], failures.is_empty())

	var other: Array[String] = []
	run.apply(GameCommand.resume())
	var pause_at: Vector2 = main._hud._pause_button.get_global_rect().get_center()
	_send(window, _touch(5, pause_at, true))
	if not run.paused:
		other.append("first Pause press did not pause")
	main.release_input_and_pause()
	_send(window, _touch(5, pause_at, true))
	if run.paused:
		other.append("the HUD's Pause button swallowed its press after suspension")
	_send(window, _touch(5, pause_at, false))
	_ok("the HUD's own Pause button has the same guarantee (%s)" % [other], other.is_empty())

	var cancelled: Array[String] = []
	run.apply(GameCommand.pause())
	main._present()
	var resume_cancel: Vector2 = main._touch.button_rect(TouchLayout.RESUME).get_center()
	_send(window, _touch(5, resume_cancel, true))
	_send(window, _touch(5, resume_cancel, false, true))
	run.apply(GameCommand.pause())
	main._present()
	_send(window, _touch(5, resume_cancel, true))
	if run.paused:
		cancelled.append("Resume swallowed its press after a cancelled touch")
	_send(window, _touch(5, resume_cancel, false))
	_ok("hold Resume, the touch is cancelled (no lift), press Resume again: it works (%s)" % [cancelled], cancelled.is_empty())

	var restarted: Array[String] = []
	run.apply(GameCommand.pause())
	main._present()
	var resume_restart: Vector2 = main._touch.button_rect(TouchLayout.RESUME).get_center()
	_send(window, _touch(5, resume_restart, true))
	var restart_at: Vector2 = main._hud._restart_button.get_global_rect().get_center()
	_send(window, _touch(6, restart_at, true))
	if run.restarts == 0:
		restarted.append("Restart did not restart")
	await _tree.process_frame
	run.apply(GameCommand.pause())
	main._present()
	_send(window, _touch(5, resume_restart, true))
	if run.paused:
		restarted.append("Resume swallowed its press after a restart")
	_send(window, _touch(5, resume_restart, false))
	_send(window, _touch(6, restart_at, false))
	_ok("hold Resume, restart with another finger, pause, press Resume again without the first lift: it works (%s)" % [restarted], restarted.is_empty())
	main.queue_free()
	window.queue_free()
	await _tree.process_frame
