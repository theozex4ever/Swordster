class_name InputTranslator
extends RefCounted
## Turns keyboard and touch input into GameCommands. Key state is tracked from
## events (not polled) so `release_all` can reliably clear it on focus loss.
##
## Aliases preserved from the prototype (`Game.handle`): WASD or arrow keys
## move, P or Escape pause, Space or either Shift dash. Q, E and R trigger the
## ultimate of sword slots one, two and three, aimed at the mouse cursor in world
## coordinates. R is also the restart key once the death screen is up: it sends
## the ultimate first and the restart after it, and the run refuses whichever does
## not apply (an ultimate once dead, a restart while alive or before the delay).

const MOVE_LEFT: Array[Key] = [KEY_A, KEY_LEFT]
const MOVE_RIGHT: Array[Key] = [KEY_D, KEY_RIGHT]
const MOVE_UP: Array[Key] = [KEY_W, KEY_UP]
const MOVE_DOWN: Array[Key] = [KEY_S, KEY_DOWN]
const PAUSE_KEYS: Array[Key] = [KEY_P, KEY_ESCAPE]
## Godot reports left and right Shift as the same key.
const DASH_KEYS: Array[Key] = [KEY_SPACE, KEY_SHIFT]
const RESTART_KEYS: Array[Key] = [KEY_R]
## Ultimate keys by sword slot: Q = slot one, E = slot two, R = slot three.
const ULTIMATE_KEYS: Array[Key] = [KEY_Q, KEY_E, KEY_R]
## DEVELOPMENT FIXTURE keys (crowd encounter): F shoves nearby enemies, C
## switches between the normal wave and the crowd encounter.
const SHOVE_KEYS: Array[Key] = [KEY_F]
const ENCOUNTER_KEYS: Array[Key] = [KEY_C]

var joystick: TouchJoystick = TouchJoystick.new()
## Where the mouse cursor last was, in viewport coordinates. Mouse aiming only; a
## touch UI (issue #20) aims through `GameCommand.ultimate_at_nearest`.
var pointer: Vector2 = Vector2.ZERO
## Converts a viewport point to a world point (the scene sets it from the camera);
## without it the viewport point is used as is.
var to_world: Callable = Callable()
var _held: Dictionary = {}


## Feeds one raw event. Returns the discrete commands it produced.
func handle_event(event: InputEvent) -> Array[GameCommand]:
	var commands: Array[GameCommand] = []
	if event is InputEventMouse:
		pointer = (event as InputEventMouse).position
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
			elif code in SHOVE_KEYS:
				commands.append(GameCommand.dev_shove())
			elif code in ENCOUNTER_KEYS:
				commands.append(GameCommand.toggle_encounter())
		else:
			_held.erase(code)
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
	joystick.release()


func _any_held(codes: Array[Key]) -> bool:
	for code: Key in codes:
		if _held.has(code):
			return true
	return false
