class_name InputTranslator
extends RefCounted
## Turns keyboard and touch input into GameCommands. Key state is tracked from
## events (not polled) so `release_all` can reliably clear it on focus loss.
##
## Aliases preserved from the prototype: WASD or arrow keys move, P or Escape
## pause. R restarts here because the arena has no ultimates yet (the
## prototype's R-after-death restart arrives with combat).

const MOVE_LEFT: Array[Key] = [KEY_A, KEY_LEFT]
const MOVE_RIGHT: Array[Key] = [KEY_D, KEY_RIGHT]
const MOVE_UP: Array[Key] = [KEY_W, KEY_UP]
const MOVE_DOWN: Array[Key] = [KEY_S, KEY_DOWN]
const PAUSE_KEYS: Array[Key] = [KEY_P, KEY_ESCAPE]
const RESTART_KEYS: Array[Key] = [KEY_R]

var joystick: TouchJoystick = TouchJoystick.new()
var _held: Dictionary = {}


## Feeds one raw event. Returns the discrete commands it produced.
func handle_event(event: InputEvent) -> Array[GameCommand]:
	var commands: Array[GameCommand] = []
	if event is InputEventKey:
		var key_event: InputEventKey = event
		var code: Key = key_event.physical_keycode
		if key_event.pressed:
			if key_event.echo:
				return commands
			_held[code] = true
			if code in PAUSE_KEYS:
				commands.append(GameCommand.toggle_pause())
			elif code in RESTART_KEYS:
				commands.append(GameCommand.restart())
		else:
			_held.erase(code)
	else:
		joystick.handle_event(event)
	return commands


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
