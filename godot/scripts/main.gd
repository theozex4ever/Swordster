class_name Main
extends Node2D
## Arena scene root. Wires input -> commands -> GameRun, steps the run once per
## 60 Hz physics tick, and hands the resulting logical state to the replaceable
## visuals, HUD and audio. The run never looks at any of them.

## Replaceable presentation scenes (roots must extend ActorVisual, SwordVisual
## and EnemyVisual respectively).
@export var actor_visual: PackedScene
@export var sword_visual: PackedScene
@export var enemy_visual: PackedScene

## Starting conditions of the run. Checks set it before adding the scene to the
## tree; the game leaves it null for the prototype defaults.
var scenario: RunScenario
var run: GameRun
var input: InputTranslator = InputTranslator.new()
var visual: ActorVisual

## Shake offsets are cosmetic randomness: a stream of their own, never the run's.
var _fx_rng: RandomNumberGenerator = RandomNumberGenerator.new()

@onready var _camera: Camera2D = $Camera2D
@onready var _sfx: SfxBank = $Sfx
@onready var _hud: Hud = $Hud
@onready var _presenter: RunPresenter = $Presenter


func _ready() -> void:
	run = GameRun.new(scenario)
	_fx_rng.randomize()
	visual = actor_visual.instantiate() as ActorVisual
	add_child(visual)
	move_child(visual, _presenter.get_index())
	_presenter.configure(sword_visual, enemy_visual)
	_present()
	visual.snap()

	_camera.global_position = run.camera
	_camera.reset_smoothing()

	_hud.bind_joystick(input.joystick)
	_hud.pause_pressed.connect(func() -> void: _submit(GameCommand.toggle_pause()))
	_hud.restart_pressed.connect(func() -> void: _submit(GameCommand.restart()))
	_hud.dash_pressed.connect(func() -> void: _submit(GameCommand.dash()))
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
		_presenter.reset()
		_present()
		visual.snap()
		_camera.reset_smoothing()
		_camera.reset_physics_interpolation()
		_sfx.play("restart")
	elif run.paused != was_paused:
		_sfx.play("pause" if run.paused else "resume")
	_dispatch_cues()
	_hud.show_state(run.paused, _sfx.unlocked)
	_hud.show_run(run)


func _present() -> void:
	var moving: bool = run.velocity.length_squared() > 25.0
	visual.apply_pose(run.position, run.facing, moving)
	visual.apply_state(run.iframes > 0.0, run.dead)
	_presenter.sync(run)
	_dispatch_cues()
	var trauma_squared: float = run.trauma * run.trauma
	var shake: Vector2 = Vector2(_fx_rng.randf_range(-1.0, 1.0), _fx_rng.randf_range(-1.0, 1.0)) * trauma_squared * 26.0
	_camera.global_position = run.camera + shake + run.kick
	_hud.show_run(run)


func _dispatch_cues() -> void:
	var cues: Array[SimCue] = run.take_cues()
	for cue: SimCue in cues:
		_sfx.play_cue(cue)
	_presenter.apply_cues(cues)


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
