class_name GameCommand
extends RefCounted
## One gameplay command. Keyboard and touch input both translate into these;
## automated checks submit the very same commands.

enum Kind { MOVE, PAUSE, RESUME, TOGGLE_PAUSE, DASH, RESTART, RESTART_FROM_KEY, DEV_SHOVE, TOGGLE_ENCOUNTER }

var kind: Kind = Kind.MOVE
## Only meaningful for MOVE. Magnitude is clamped to 1 by the run.
var axis: Vector2 = Vector2.ZERO


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


## The R key: only restarts once the death screen is up. While alive R is the
## slot-three ultimate key (not ported yet), so it does nothing then.
static func restart_from_key() -> GameCommand:
	return _of(Kind.RESTART_FROM_KEY)


## DEVELOPMENT FIXTURE: launches the enemies around the player like a heavy
## blow. Does nothing unless the scenario enables `dev_shove`.
static func dev_shove() -> GameCommand:
	return _of(Kind.DEV_SHOVE)


## DEVELOPMENT FIXTURE: switches between the normal wave and the crowd
## encounter. The run does not interpret it; the scene that owns the scenarios
## does, by restarting the run with the other one.
static func toggle_encounter() -> GameCommand:
	return _of(Kind.TOGGLE_ENCOUNTER)


static func _of(kind_value: Kind) -> GameCommand:
	var command: GameCommand = GameCommand.new()
	command.kind = kind_value
	return command
