class_name Main
extends Node2D
## Arena scene root. Wires input -> commands -> GameRun, steps the run once per
## 60 Hz physics tick, and hands the resulting logical pose to the replaceable
## actor visual. The run never looks at the visual.

## Replaceable actor presentation (root must extend ActorVisual).
@export var actor_visual: PackedScene

var run: GameRun
var input: InputTranslator = InputTranslator.new()
var visual: ActorVisual

@onready var _camera: Camera2D = $Camera2D
@onready var _sfx: SfxBank = $Sfx
@onready var _hud: Hud = $Hud


func _ready() -> void:
	run = GameRun.new()
	visual = actor_visual.instantiate() as ActorVisual
	add_child(visual)
	visual.apply_pose(run.position, run.facing, false)
	visual.snap()

	var world: Rect2 = GameRun.WORLD
	_camera.limit_left = int(world.position.x)
	_camera.limit_top = int(world.position.y)
	_camera.limit_right = int(world.end.x)
	_camera.limit_bottom = int(world.end.y)
	_camera.global_position = run.position
	_camera.reset_smoothing()

	_hud.bind_joystick(input.joystick)
	_hud.pause_pressed.connect(func() -> void: _submit(GameCommand.toggle_pause()))
	_hud.restart_pressed.connect(func() -> void: _submit(GameCommand.restart()))
	get_viewport().size_changed.connect(_update_touch_zone)
	_update_touch_zone.call_deferred()
	_hud.show_state(run.paused, _sfx.unlocked)


func _input(event: InputEvent) -> void:
	if _is_user_gesture(event):
		_unlock_audio()
	for command: GameCommand in input.handle_event(event):
		_submit(command)
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		_hud.refresh_stick()


func _physics_process(_delta: float) -> void:
	run.apply(GameCommand.move_axis(input.move_axis()))
	run.step()
	_present()


func _notification(what: int) -> void:
	# Focus loss / suspension: drop all held input and stop gameplay; resuming
	# is always an explicit player action.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT \
			or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT \
			or what == NOTIFICATION_APPLICATION_PAUSED:
		release_input_and_pause()


func release_input_and_pause() -> void:
	input.release_all()
	if run != null and not run.paused:
		_submit(GameCommand.pause())
	if _hud != null:
		_hud.refresh_stick()


func _submit(command: GameCommand) -> void:
	var was_paused: bool = run.paused
	var restarts_before: int = run.restarts
	run.apply(command)
	if run.restarts != restarts_before:
		input.release_all()
		_present()
		visual.snap()
		_camera.reset_smoothing()
		_camera.reset_physics_interpolation()
		_sfx.play("restart")
	elif run.paused != was_paused:
		_sfx.play("pause" if run.paused else "resume")
	_hud.show_state(run.paused, _sfx.unlocked)


func _present() -> void:
	var moving: bool = run.velocity.length_squared() > 25.0
	visual.apply_pose(run.position, run.facing, moving)
	_camera.global_position = run.position


func _unlock_audio() -> void:
	if _sfx.unlocked:
		return
	_sfx.unlock()
	_hud.show_state(run.paused, _sfx.unlocked)


func _update_touch_zone() -> void:
	var size: Vector2 = get_viewport().get_visible_rect().size
	input.joystick.zone = Rect2(0.0, size.y * 0.15, size.x * 0.55, size.y * 0.85)
	input.joystick.blocked = _hud.button_rects()


func _is_user_gesture(event: InputEvent) -> bool:
	if event is InputEventKey:
		return (event as InputEventKey).pressed
	if event is InputEventMouseButton:
		return (event as InputEventMouseButton).pressed
	if event is InputEventScreenTouch:
		return (event as InputEventScreenTouch).pressed
	return false
