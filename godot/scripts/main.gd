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
## Whether the touch controls are up (issue #20): the platform reports a touchscreen, `--touch` / `?touch=1` asked for them, or a
## finger has touched the screen. Desktop play with mouse and keys never shows them.
var touch_mode: bool = false
## Stand-in safe-area insets (left, top, right, bottom, in viewport pixels) for checks; null reads the platform's.
var safe_insets_override: Variant = null

## Shake offsets are cosmetic randomness: a stream of their own, never the run's.
var _fx_rng: RandomNumberGenerator = RandomNumberGenerator.new()

@onready var _camera: Camera2D = $Camera2D
@onready var _sfx: SfxBank = $Sfx
@onready var _hud: Hud = $Hud
@onready var _presenter: RunPresenter = $Presenter
@onready var _touch: TouchControls = $Touch

var _platform: TouchPlatform = TouchPlatform.new()
var _fullscreen_supported: bool = false


func _ready() -> void:
	if scenario == null:
		scenario = LaunchOptions.requested_scenario()
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

	input.pointer = get_viewport().get_mouse_position()
	input.to_world = _world_at
	input.touch.blocked_provider = _blocked_rects
	_hud.bind_joystick(input.joystick)
	_hud.pause_pressed.connect(func() -> void: _submit(GameCommand.toggle_pause()))
	_hud.restart_pressed.connect(func() -> void: _submit(GameCommand.restart()))
	_hud.dash_pressed.connect(func() -> void: _submit(GameCommand.dash()))
	_hud.encounter_pressed.connect(func() -> void: _submit(GameCommand.toggle_encounter()))
	_hud.shove_pressed.connect(func() -> void: _submit(GameCommand.dev_shove()))
	_touch.command_requested.connect(_submit)
	_touch.fullscreen_pressed.connect(TouchPlatform.toggle_fullscreen)
	_fullscreen_supported = TouchPlatform.fullscreen_supported()
	get_viewport().size_changed.connect(_update_touch_zone)
	_hud.show_state(run.paused, _sfx.unlocked)
	_platform.install_suspend_hook(release_input_and_pause)
	set_touch_mode(TouchPlatform.touchscreen_present())
	_update_touch_zone.call_deferred()


func _input(event: InputEvent) -> void:
	if _is_user_gesture(event):
		_unlock_audio()
	if event is InputEventScreenTouch and not touch_mode:
		set_touch_mode(true)
	# A mouse click is only a Converge when nothing in the HUD took it (the Pause, Restart and Dev
	# buttons), so it is translated in `_unhandled_input`; here it only keeps the pointer current.
	if event is InputEventMouseButton:
		input.pointer = (event as InputEventMouseButton).position
		return
	for command: GameCommand in input.handle_event(event):
		_submit(command)
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		_hud.refresh_stick()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		for command: GameCommand in input.handle_event(event):
			_submit(command)


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
	_show_touch()


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
	_show_touch()


func _dispatch_cues() -> void:
	var cues: Array[SimCue] = run.take_cues()
	for cue: SimCue in cues:
		_sfx.play_cue(cue)
	_presenter.apply_cues(cues)


## A viewport point's world position (the prototype's `mouse_world`: the camera's
## unshaken centre plus the offset from the middle of the view).
func _world_at(viewport_point: Vector2) -> Vector2:
	return run.camera + viewport_point - get_viewport().get_visible_rect().size * 0.5


func _unlock_audio() -> void:
	if _sfx.unlocked:
		return
	_sfx.unlock()
	_hud.show_state(run.paused, _sfx.unlocked)


## Shows or hides the touch controls (issue #20) and lays the screen out for them.
func set_touch_mode(on: bool) -> void:
	if touch_mode == on and _touch.is_active() == on:
		return
	touch_mode = on
	_touch.set_active(on)
	_hud.set_touch_mode(on)
	if not on:
		_hud.extra_avoid_rects = []
	_update_touch_zone()
	_show_touch()


## The viewport changed (or the controls came up): the joystick's zone, the orientation's base size and the buttons' places.
func _update_touch_zone() -> void:
	if not is_inside_tree():
		return
	_apply_orientation()
	var size: Vector2 = get_viewport().get_visible_rect().size
	input.joystick.zone = TouchLayout.joystick_zone(size, _insets())
	input.joystick.blocked = _blocked_rects()
	_show_touch()


## Touch play keeps the HUD at the size it was laid out for in either orientation: a window taller than wide uses the portrait
## base, so the controls are as big on a phone held upright as sideways. Desktop windows keep the project's own base size.
func _apply_orientation() -> void:
	if not touch_mode:
		return
	var window: Window = get_window()
	var base: Vector2i = TouchLayout.base_size_for(window.size)
	if window.content_scale_size != base:
		window.content_scale_size = base


func _insets() -> Vector4:
	if not touch_mode:
		return Vector4.ZERO
	if safe_insets_override is Vector4:
		return safe_insets_override as Vector4
	return TouchPlatform.safe_insets(get_viewport().get_visible_rect().size)


## Every screen rectangle a finger lands on a button in: the HUD's and the touch controls'.
func _blocked_rects() -> Array[Rect2]:
	var rects: Array[Rect2] = _hud.button_rects()
	rects.append_array(_touch.blocked_rects())
	return rects


func _show_touch() -> void:
	if _touch == null or not _touch.is_active():
		return
	_touch.layout(get_viewport().get_visible_rect().size, _insets(), _hud.dash_rect(), _fullscreen_supported)
	_touch.show_run(run)
	_hud.extra_avoid_rects = _touch.blocked_rects()


func _is_user_gesture(event: InputEvent) -> bool:
	if event is InputEventKey:
		return (event as InputEventKey).pressed
	if event is InputEventMouseButton:
		return (event as InputEventMouseButton).pressed
	if event is InputEventScreenTouch:
		return (event as InputEventScreenTouch).pressed
	return false
