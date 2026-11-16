class_name TouchPointers
extends RefCounted
## Independent tracking of every finger on the screen (issue #20). Each touch index is a contact
## with ONE owner for its whole life, decided when it lands:
##
## - UI: it landed on a button (`blocked`). The button acts on its own (Godot's GUI delivers it);
##   the contact is consumed here, so it can neither steer the joystick nor aim Converge at the arena.
## - JOYSTICK: it landed in the joystick's zone while the joystick was free (`TouchJoystick` claims it).
## - ARENA: anywhere else, or in the zone while another finger already steers. Landing commands
##   Converge at the tapped world point at once, like a mouse click.
##
## A finger that steers but only taps (lifts within `TAP_SECONDS` having moved at most `TAP_TRAVEL`) also
## commands Converge at where it landed, so the whole arena can be tapped, not just the right of the screen.
## A cancelled contact never taps. `release_all` (focus loss, suspension, restart) forgets every contact, so a
## later drag or lift of a forgotten finger changes nothing.

enum Owner { UI, JOYSTICK, ARENA }

## A finger that lifts within this many seconds of landing, having moved at most `TAP_TRAVEL` px, was a tap.
const TAP_SECONDS: float = 0.3
const TAP_TRAVEL: float = 18.0


class Contact extends RefCounted:
	var owner: Owner = Owner.ARENA
	var start: Vector2 = Vector2.ZERO
	var since: float = 0.0
	var travel: float = 0.0


var joystick: TouchJoystick
## Viewport point -> world point (the scene's camera mapping).
var to_world: Callable = Callable()
## Returns the screen rectangles buttons occupy right now; without it the joystick's own `blocked` list is used.
var blocked_provider: Callable = Callable()
## Returns the current time in seconds; replaced by checks to run taps on a fake clock.
var clock: Callable = Callable()
var _contacts: Dictionary[int, Contact] = {}


func _init(stick: TouchJoystick) -> void:
	joystick = stick


## Feeds a screen touch or drag. Returns the commands it produced (a Converge at a tapped world point).
func handle_event(event: InputEvent) -> Array[GameCommand]:
	var commands: Array[GameCommand] = []
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event
		if touch.pressed and not touch.canceled:
			if _contacts.has(touch.index):
				_end(touch.index, true)
			_land(touch, commands)
		elif _contacts.has(touch.index):
			commands.append_array(_end(touch.index, touch.canceled, touch))
	elif event is InputEventScreenDrag:
		var drag: InputEventScreenDrag = event
		var contact: Contact = _contacts.get(drag.index)
		if contact != null:
			contact.travel = maxf(contact.travel, drag.position.distance_to(contact.start))
			if contact.owner == Owner.JOYSTICK:
				joystick.handle_event(drag)
	return commands


## Number of fingers currently down.
func count() -> int:
	return _contacts.size()


## The fingers that landed on a button and are still down.
func ui_indices() -> Array[int]:
	var found: Array[int] = []
	for index: int in _contacts:
		if _contacts[index].owner == Owner.UI:
			found.append(index)
	return found


func owner_of(index: int) -> int:
	var contact: Contact = _contacts.get(index)
	return -1 if contact == null else contact.owner


## Forgets every finger and releases the joystick.
func release_all() -> void:
	_contacts.clear()
	joystick.release()


func _land(touch: InputEventScreenTouch, commands: Array[GameCommand]) -> void:
	var contact: Contact = Contact.new()
	contact.start = touch.position
	contact.since = _now()
	if _is_blocked(touch.position):
		contact.owner = Owner.UI
	elif joystick.handle_event(touch):
		contact.owner = Owner.JOYSTICK
	else:
		contact.owner = Owner.ARENA
		commands.append(GameCommand.converge(_world(touch.position)))
	_contacts[touch.index] = contact


## Ends a contact. A lift or cancel that arrived as an event is the joystick's own to handle (`event`); a contact ended without
## one (a stale press) is released outright. Returns the Converge a tap makes (none for a cancelled contact or a stale one).
func _end(index: int, cancelled: bool, event: InputEvent = null) -> Array[GameCommand]:
	var commands: Array[GameCommand] = []
	var contact: Contact = _contacts[index]
	_contacts.erase(index)
	if contact.owner == Owner.JOYSTICK:
		if event != null:
			joystick.handle_event(event)
		elif joystick.pointer == index:
			joystick.release()
		if not cancelled and _now() - contact.since <= TAP_SECONDS and contact.travel <= TAP_TRAVEL:
			commands.append(GameCommand.converge(_world(contact.start)))
	return commands


func _is_blocked(point: Vector2) -> bool:
	var rects: Array[Rect2] = joystick.blocked
	if blocked_provider.is_valid():
		rects = blocked_provider.call()
		joystick.blocked = rects
	for rect: Rect2 in rects:
		if rect.has_point(point):
			return true
	return false


func _world(point: Vector2) -> Vector2:
	if to_world.is_valid():
		return to_world.call(point)
	return point


func _now() -> float:
	if clock.is_valid():
		return clock.call()
	return float(Time.get_ticks_msec()) / 1000.0
