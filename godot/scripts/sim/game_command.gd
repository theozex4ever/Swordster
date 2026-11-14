class_name GameCommand
extends RefCounted
## One gameplay command. Keyboard and touch input both translate into these;
## automated checks submit the very same commands.

enum Kind { MOVE, PAUSE, RESUME, TOGGLE_PAUSE, DASH, RESTART, RESTART_FROM_KEY, DEV_SHOVE, TOGGLE_ENCOUNTER, ULTIMATE }

var kind: Kind = Kind.MOVE
## Only meaningful for MOVE. Magnitude is clamped to 1 by the run.
var axis: Vector2 = Vector2.ZERO
## Only meaningful for ULTIMATE: the sword slot (0 = Q, 1 = E, 2 = R), the world
## point it is aimed at, and whether to aim at the nearest enemy instead (touch).
var slot: int = 0
var point: Vector2 = Vector2.ZERO
var at_nearest: bool = false


static func move_axis(axis_value: Vector2) -> GameCommand:
	var command: GameCommand = GameCommand.new()
	command.kind = Kind.MOVE
	command.axis = axis_value
	return command


static func pause() -> GameCommand:
	return _of(Kind.PAUSE)


static func resume() -> GameCommand:
	return _of(Kind.RESUME)


static func toggle_pause() -> GameCommand:
	return _of(Kind.TOGGLE_PAUSE)


static func dash() -> GameCommand:
	return _of(Kind.DASH)


## The on-screen Restart button: always restarts (and un-pauses), like the
## prototype's touch "restart" action.
static func restart() -> GameCommand:
	return _of(Kind.RESTART)


## The restart half of the R key: only restarts once the death screen is up and
## does nothing while alive. While alive R is the slot-three ultimate key; the
## input translator sends `ultimate(2, ...)` first and this after it, so a dead
## player's R can never start an ultimate on the freshly restarted run.
static func restart_from_key() -> GameCommand:
	return _of(Kind.RESTART_FROM_KEY)


## Triggers the ultimate of sword slot `slot_value` aimed at a world point (the
## mouse cursor in world coordinates). Refused while paused or dead, while that
## slot's ultimate is active or recharging, or when the slot holds no sword.
static func ultimate(slot_value: int, world_point: Vector2) -> GameCommand:
	var command: GameCommand = _of(Kind.ULTIMATE)
	command.slot = slot_value
	command.point = world_point
	return command


## Same, aimed at the nearest living enemy, or 300 px ahead of the player when
## there is none (the prototype's touch aiming, `Game.auto_aim`).
static func ultimate_at_nearest(slot_value: int) -> GameCommand:
	var command: GameCommand = _of(Kind.ULTIMATE)
	command.slot = slot_value
	command.at_nearest = true
	return command


## DEVELOPMENT FIXTURE: launches the enemies around the player like a heavy
## blow. Does nothing unless the scenario enables `dev_shove`.
static func dev_shove() -> GameCommand:
	return _of(Kind.DEV_SHOVE)


## DEVELOPMENT FIXTURE: cycles to the next dev encounter (normal -> crowd ->
## spitters -> normal) and restarts play in it.
static func toggle_encounter() -> GameCommand:
	return _of(Kind.TOGGLE_ENCOUNTER)


static func _of(kind_value: Kind) -> GameCommand:
	var command: GameCommand = GameCommand.new()
	command.kind = kind_value
	return command
