class_name TouchJoystick
extends RefCounted
## Floating movement joystick driven by raw touch events. It claims exactly one
## pointer (by index) inside `zone`, outside `blocked`; every other pointer is
## ignored so buttons and future arena taps stay independent.

const RADIUS: float = 90.0
const DEADZONE: float = 0.12

var zone: Rect2 = Rect2()
## Screen regions (e.g. buttons) a touch must not start the joystick in.
var blocked: Array[Rect2] = []
var pointer: int = -1
var origin: Vector2 = Vector2.ZERO
var current: Vector2 = Vector2.ZERO


func is_active() -> bool:
	return pointer != -1


## Returns true when the event belongs to the joystick's pointer.
func handle_event(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event
		if touch.pressed and not touch.canceled:
			if pointer == -1 and _can_start_at(touch.position):
				pointer = touch.index
				origin = touch.position
				current = touch.position
				return true
			return false
		if touch.index == pointer:
			release()
			return true
		return false
	if event is InputEventScreenDrag:
		var drag: InputEventScreenDrag = event
		if drag.index == pointer:
			current = drag.position
			return true
	return false


func axis() -> Vector2:
	if pointer == -1:
		return Vector2.ZERO
	var offset: Vector2 = (current - origin) / RADIUS
	offset = offset.limit_length(1.0)
	if offset.length() < DEADZONE:
		return Vector2.ZERO
	return offset


func release() -> void:
	pointer = -1
	origin = Vector2.ZERO
	current = Vector2.ZERO


func _can_start_at(point: Vector2) -> bool:
	if not zone.has_point(point):
		return false
	for rect: Rect2 in blocked:
		if rect.has_point(point):
			return false
	return true
