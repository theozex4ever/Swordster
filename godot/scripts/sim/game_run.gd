class_name GameRun
extends RefCounted
## The simulation of one run. Owns all run-owned state (player pose, time,
## pause flag) and knows nothing about nodes, rendering, audio or input devices.
##
## Movement mirrors game/main.py `Player.update` (speed 285, acceleration blend
## `min(1, dt * 14)`, radius 14, 2600x1800 world), stepped at a fixed 60 Hz.
## Dash is intentionally not part of this slice.

const TICK_RATE: int = 60
const TICK_DT: float = 1.0 / 60.0
const WORLD: Rect2 = Rect2(0.0, 0.0, 2600.0, 1800.0)
const PLAYER_RADIUS: float = 14.0
const PLAYER_SPEED: float = 285.0
const ACCELERATION: float = 14.0

var scenario: RunScenario
## Number of fixed ticks that advanced gameplay (never advances while paused).
var tick: int = 0
## Gameplay seconds: advances only while running, in whole fixed ticks.
var gameplay_time: float = 0.0
var paused: bool = false
## How many times this run was restarted; presenters use it to drop stale visuals.
var restarts: int = 0
var position: Vector2 = Vector2.ZERO
var velocity: Vector2 = Vector2.ZERO
var facing: Vector2 = Vector2.RIGHT

var _move_input: Vector2 = Vector2.ZERO


func _init(scenario_value: RunScenario = null) -> void:
	scenario = scenario_value if scenario_value != null else RunScenario.new()
	_reset_state()


## Applies a command. Movement while paused is remembered but has no effect
## until the run resumes.
func apply(command: GameCommand) -> void:
	match command.kind:
		GameCommand.Kind.MOVE:
			_move_input = command.axis.limit_length(1.0)
		GameCommand.Kind.PAUSE:
			paused = true
		GameCommand.Kind.RESUME:
			paused = false
		GameCommand.Kind.TOGGLE_PAUSE:
			paused = not paused
		GameCommand.Kind.RESTART:
			restarts += 1
			_reset_state()


## Advances exactly one fixed tick of gameplay time. Does nothing while paused.
func step() -> void:
	if paused:
		return
	tick += 1
	gameplay_time = tick * TICK_DT
	var move: Vector2 = _move_input
	if move.length_squared() > 0.0:
		facing = move.normalized()
	velocity += (move * PLAYER_SPEED - velocity) * minf(1.0, TICK_DT * ACCELERATION)
	position += velocity * TICK_DT
	var inner: Rect2 = WORLD.grow(-PLAYER_RADIUS)
	position = position.clamp(inner.position, inner.end)


## Observation adapter for checks: plain values only.
func snapshot() -> Dictionary:
	return {
		"tick": tick,
		"gameplay_time": gameplay_time,
		"paused": paused,
		"restarts": restarts,
		"position": position,
		"velocity": velocity,
		"facing": facing,
		"move_input": _move_input,
	}


func _reset_state() -> void:
	tick = 0
	gameplay_time = 0.0
	paused = false
	position = scenario.start_position
	velocity = Vector2.ZERO
	facing = Vector2.RIGHT
	_move_input = Vector2.ZERO
