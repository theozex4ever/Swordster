class_name InputTranslator
extends RefCounted
## Turns keyboard and touch input into GameCommands. Key state is tracked from
## events (not polled) so `release_all` can reliably clear it on focus loss.
##
## Aliases preserved from the prototype (`Game.handle`): WASD or arrow keys
## move, P or Escape pause, Space or either Shift dash. Q, E and R trigger the
## ultimate of sword slots one, two and three, aimed at the mouse cursor in world
## coordinates. Keys 1, 2 and 3 ask to swap the nearest dropped sword into sword slot one, two and
## three (`GameCommand.swap`); the run refuses when none is within reach. R is also the restart key once the death screen is up: it sends
## the ultimate first and the restart after it, and the run refuses whichever does
## not apply (an ultimate once dead, a restart while alive or before the delay). A left or right
## mouse click commands Converge at the cursor's world point, and Tab or G shows or hides the
## attack ranges. A mouse click the engine made up from a touch is not a Converge: touch has its own path (issue #20, `TouchPointers`):
## a finger landing on the arena commands Converge at the tapped world point, the joystick and the buttons take the rest, and every
## finger is tracked by its index alone.

const MOVE_LEFT: Array[Key] = [KEY_A, KEY_LEFT]
const MOVE_RIGHT: Array[Key] = [KEY_D, KEY_RIGHT]
const MOVE_UP: Array[Key] = [KEY_W, KEY_UP]
const MOVE_DOWN: Array[Key] = [KEY_S, KEY_DOWN]
const PAUSE_KEYS: Array[Key] = [KEY_P, KEY_ESCAPE]
## Godot reports left and right Shift as the same key.
const DASH_KEYS: Array[Key] = [KEY_SPACE, KEY_SHIFT]
const RESTART_KEYS: Array[Key] = [KEY_R]
## Mouse buttons that command Converge (the prototype's buttons 1 and 3).
const CONVERGE_BUTTONS: Array[MouseButton] = [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]
const RANGE_KEYS: Array[Key] = [KEY_TAB, KEY_G]
## Ultimate keys by sword slot: Q = slot one, E = slot two, R = slot three.
const ULTIMATE_KEYS: Array[Key] = [KEY_Q, KEY_E, KEY_R]
## Keys 1, 2 and 3 swap the nearest dropped sword into sword slot one, two or three.
const SWAP_KEYS: Array[Key] = [KEY_1, KEY_2, KEY_3]
## DEVELOPMENT FIXTURE keys (crowd encounter): F shoves nearby enemies, C
## switches between the normal wave and the crowd encounter.
const SHOVE_KEYS: Array[Key] = [KEY_F]
const ENCOUNTER_KEYS: Array[Key] = [KEY_C]

var joystick: TouchJoystick = TouchJoystick.new()
## Every finger on the screen, each with one owner (issue #20): the joystick, a button, or the arena it taps Converge into.
var touch: TouchPointers
## Where the mouse cursor last was, in viewport coordinates. Mouse aiming only; a
## touch UI (issue #20) aims through `GameCommand.ultimate_at_nearest`.
var pointer: Vector2 = Vector2.ZERO
## Converts a viewport point to a world point (the scene sets it from the camera);
## without it the viewport point is used as is.
var to_world: Callable = Callable()
var _held: Dictionary = {}


func _init() -> void:
	touch = TouchPointers.new(joystick)
	touch.to_world = _world_point


## Feeds one raw event. Returns the discrete commands it produced.
func handle_event(event: InputEvent) -> Array[GameCommand]:
	var commands: Array[GameCommand] = []
	if event is InputEventMouse:
		pointer = (event as InputEventMouse).position
	if event is InputEventMouseButton:
		var click: InputEventMouseButton = event
		if click.pressed and click.button_index in CONVERGE_BUTTONS and click.device != InputEvent.DEVICE_ID_EMULATION:
			commands.append(GameCommand.converge(aim_world()))
	if event is InputEventKey:
		var key_event: InputEventKey = event
		var code: Key = key_event.physical_keycode
		if key_event.pressed:
			if key_event.echo:
				return commands
			_held[code] = true
			if code in PAUSE_KEYS:
				commands.append(GameCommand.toggle_pause())
			elif code in DASH_KEYS:
				commands.append(GameCommand.dash())
			elif code in ULTIMATE_KEYS or code in RESTART_KEYS:
				if code in ULTIMATE_KEYS:
					commands.append(GameCommand.ultimate(ULTIMATE_KEYS.find(code), aim_world()))
				if code in RESTART_KEYS:
					commands.append(GameCommand.restart_from_key())
			elif code in SWAP_KEYS:
				commands.append(GameCommand.swap(SWAP_KEYS.find(code)))
			elif code in RANGE_KEYS:
				commands.append(GameCommand.toggle_ranges())
			elif code in SHOVE_KEYS:
				commands.append(GameCommand.dev_shove())
			elif code in ENCOUNTER_KEYS:
				commands.append(GameCommand.toggle_encounter())
		else:
			_held.erase(code)
	elif event is InputEventScreenTouch or event is InputEventScreenDrag:
		commands.append_array(touch.handle_event(event))
	else:
		joystick.handle_event(event)
	return commands


## The cursor's world position (what a mouse-aimed command targets).
func aim_world() -> Vector2:
	if to_world.is_valid():
		return to_world.call(pointer)
	return pointer


## Current movement vector. A touch joystick in use wins over the keyboard,
## as in the prototype.
func move_axis() -> Vector2:
	var touch: Vector2 = joystick.axis()
	if touch.length_squared() > 0.0:
		return touch
	var keys: Vector2 = Vector2(
		float(_any_held(MOVE_RIGHT)) - float(_any_held(MOVE_LEFT)),
		float(_any_held(MOVE_DOWN)) - float(_any_held(MOVE_UP)),
	)
	return keys.limit_length(1.0)


## Drops every held key and touch pointer (focus loss, suspension, restart of
## a device context). Nothing may stay stuck afterwards.
func release_all() -> void:
	_held.clear()
	touch.release_all()


func _world_point(viewport_point: Vector2) -> Vector2:
	if to_world.is_valid():
		return to_world.call(viewport_point)
	return viewport_point


func _any_held(codes: Array[Key]) -> bool:
	for code: Key in codes:
		if _held.has(code):
			return true
	return false
