class_name Hud
extends CanvasLayer
## Overlay UI: build label, controls hint, pause/restart buttons, audio-unlock
## prompt, pause overlay and the touch joystick indicator. It reports button
## presses by signal and owns no gameplay state.

signal pause_pressed
signal restart_pressed

var _build_label: Label
var _hint_label: Label
var _audio_prompt: Label
var _pause_overlay: Label
var _pause_button: Button
var _restart_button: Button
var _stick: Control
var _joystick: TouchJoystick


func _ready() -> void:
	var root: Control = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_build_label = _make_label(root, "Build %s (%s)" % [BuildInfo.BUILD_ID, BuildInfo.SOURCE_COMMIT.substr(0, 9)])
	_build_label.position = Vector2(16.0, 12.0)

	_hint_label = _make_label(root, "WASD / arrows: move   P / Esc: pause   R: restart\nTouch: drag on the left half to move")
	_hint_label.position = Vector2(16.0, 40.0)

	_pause_button = _make_button(root, "Pause", Vector2(-176.0, 16.0))
	_pause_button.pressed.connect(func() -> void: pause_pressed.emit())
	_restart_button = _make_button(root, "Restart", Vector2(-96.0, 16.0))
	_restart_button.pressed.connect(func() -> void: restart_pressed.emit())

	_pause_overlay = _make_label(root, "PAUSED\nPress P / Esc or tap Resume")
	_center(_pause_overlay)
	_pause_overlay.visible = false

	_audio_prompt = _make_label(root, "Click or tap to enable sound")
	_audio_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_audio_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_audio_prompt.position.y = -96.0

	_stick = Control.new()
	_stick.set_anchors_preset(Control.PRESET_FULL_RECT)
	_stick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stick.draw.connect(_draw_stick)
	root.add_child(_stick)


func bind_joystick(joystick: TouchJoystick) -> void:
	_joystick = joystick


## Screen rectangles the touch joystick must not start in.
func button_rects() -> Array[Rect2]:
	var rects: Array[Rect2] = []
	rects.append(_pause_button.get_global_rect().grow(8.0))
	rects.append(_restart_button.get_global_rect().grow(8.0))
	return rects


func show_state(paused: bool, audio_unlocked: bool) -> void:
	_pause_overlay.visible = paused
	_pause_button.text = "Resume" if paused else "Pause"
	_audio_prompt.visible = not audio_unlocked


func refresh_stick() -> void:
	_stick.queue_redraw()


func _draw_stick() -> void:
	if _joystick == null or not _joystick.is_active():
		return
	_stick.draw_arc(_joystick.origin, TouchJoystick.RADIUS, 0.0, TAU, 48, Color(1.0, 1.0, 1.0, 0.35), 3.0)
	var knob: Vector2 = _joystick.origin + _joystick.axis() * TouchJoystick.RADIUS
	_stick.draw_circle(knob, 30.0, Color(1.0, 1.0, 1.0, 0.45))


func _make_label(parent: Control, text: String) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(0.9, 0.92, 1.0))
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.8))
	label.add_theme_constant_override("outline_size", 4)
	parent.add_child(label)
	return label


func _make_button(parent: Control, text: String, offset: Vector2) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(72.0, 44.0)
	button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	button.position = offset
	button.size = Vector2(72.0, 44.0)
	parent.add_child(button)
	return button


func _center(label: Label) -> void:
	label.set_anchors_preset(Control.PRESET_CENTER)
	label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	label.grow_vertical = Control.GROW_DIRECTION_BOTH
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 40)
