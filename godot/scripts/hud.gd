class_name Hud
extends CanvasLayer
## Overlay UI: build label, controls hint, health bar, wave/kill counters, dash
## cooldown, wave banner, run outcome screens, pause/restart/dash buttons, the
## crowd-encounter fixture's Crowd/Shove buttons and legend,
## audio-unlock prompt, pause overlay and the touch joystick indicator. It
## reports button presses by signal and owns no gameplay state: everything it
## shows is read from the run each tick.

signal pause_pressed
signal restart_pressed
signal dash_pressed
signal encounter_pressed
signal shove_pressed

const HP_BAR_SIZE: Vector2 = Vector2(260.0, 18.0)
## Death screen fades in after this many gameplay seconds (prototype 0.8).
const OUTCOME_FADE_START: float = GameRun.RESTART_DELAY

var _build_label: Label
var _hint_label: Label
var _audio_prompt: Label
var _pause_overlay: Label
var _pause_button: Button
var _restart_button: Button
var _stick: Control
var _joystick: TouchJoystick
var _dash_button: Button
var _encounter_button: Button
var _shove_button: Button
var _encounter_label: Label
var _hp_back: ColorRect
var _hp_lag: ColorRect
var _hp_fill: ColorRect
var _hp_label: Label
var _wave_label: Label
var _dash_label: Label
var _banner_label: Label
var _outcome_shade: ColorRect
var _outcome_title: Label
var _outcome_detail: Label
var _outcome_prompt: Label
var _hp_shown: float = GameRun.PLAYER_MAX_HP


func _ready() -> void:
	var root: Control = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_build_label = _make_label(root, "Build %s (%s)" % [BuildInfo.BUILD_ID, BuildInfo.SOURCE_COMMIT.substr(0, 9)])
	_build_label.position = Vector2(16.0, 12.0)

	_hint_label = _make_label(root, "WASD / arrows: move   Space / Shift: dash   P / Esc: pause   R: restart after death   C: crowd encounter\nTouch: drag on the left half to move, Dash button to evade")
	_hint_label.position = Vector2(16.0, 40.0)

	_hp_back = _make_rect(root, Color(0.0, 0.0, 0.0, 0.55))
	_hp_back.position = Vector2(16.0, 92.0)
	_hp_back.size = HP_BAR_SIZE + Vector2(4.0, 4.0)
	_hp_lag = _make_rect(root, Color(1.0, 1.0, 1.0, 0.85))
	_hp_lag.position = Vector2(18.0, 94.0)
	_hp_fill = _make_rect(root, Color(0.35, 0.82, 1.0))
	_hp_fill.position = Vector2(18.0, 94.0)
	_hp_label = _make_label(root, "100")
	_hp_label.position = Vector2(HP_BAR_SIZE.x + 30.0, 88.0)
	_dash_label = _make_label(root, "dash ready")
	_dash_label.position = Vector2(16.0, 118.0)
	_wave_label = _make_label(root, "")
	_wave_label.add_theme_font_size_override("font_size", 26)
	_wave_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_wave_label.position.y = 12.0
	_wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_label = _make_label(root, "")
	_banner_label.add_theme_font_size_override("font_size", 56)
	_fill_and_center(_banner_label, VERTICAL_ALIGNMENT_CENTER)
	_banner_label.offset_top = -180.0
	_banner_label.offset_bottom = -180.0

	_outcome_shade = _make_rect(root, Color(0.0, 0.0, 0.0, 0.0))
	_outcome_shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_outcome_title = _make_label(root, "")
	_outcome_title.add_theme_font_size_override("font_size", 64)
	_fill_and_center(_outcome_title, VERTICAL_ALIGNMENT_CENTER)
	_outcome_title.offset_top = -90.0
	_outcome_title.offset_bottom = -90.0
	_outcome_detail = _make_label(root, "")
	_outcome_detail.add_theme_font_size_override("font_size", 26)
	_fill_and_center(_outcome_detail, VERTICAL_ALIGNMENT_CENTER)
	_outcome_detail.offset_top = 0.0
	_outcome_detail.offset_bottom = 0.0
	_outcome_prompt = _make_label(root, "")
	_outcome_prompt.add_theme_font_size_override("font_size", 26)
	_fill_and_center(_outcome_prompt, VERTICAL_ALIGNMENT_CENTER)
	_outcome_prompt.offset_top = 50.0
	_outcome_prompt.offset_bottom = 50.0
	_set_outcome_visible(false)

	_pause_button = _make_button(root, "Pause", Vector2(-176.0, 16.0))
	_pause_button.button_down.connect(func() -> void: pause_pressed.emit())
	_restart_button = _make_button(root, "Restart", Vector2(-96.0, 16.0))
	_restart_button.button_down.connect(func() -> void: restart_pressed.emit())

	_dash_button = _make_button(root, "Dash", Vector2.ZERO)
	_dash_button.custom_minimum_size = Vector2(104.0, 104.0)
	_dash_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_dash_button.offset_left = -128.0
	_dash_button.offset_top = -128.0
	_dash_button.offset_right = -24.0
	_dash_button.offset_bottom = -24.0
	_dash_button.button_down.connect(func() -> void: dash_pressed.emit())

	_encounter_button = _make_button(root, "Crowd", Vector2(-256.0, 16.0))
	_encounter_button.button_down.connect(func() -> void: encounter_pressed.emit())
	_shove_button = _make_button(root, "Shove", Vector2.ZERO)
	_shove_button.custom_minimum_size = Vector2(104.0, 104.0)
	_shove_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_shove_button.offset_left = -248.0
	_shove_button.offset_top = -128.0
	_shove_button.offset_right = -144.0
	_shove_button.offset_bottom = -24.0
	_shove_button.button_down.connect(func() -> void: shove_pressed.emit())
	_shove_button.visible = false
	_encounter_label = _make_label(root, "")
	_encounter_label.position = Vector2(16.0, 146.0)
	_encounter_label.visible = false

	_pause_overlay = _make_label(root, "PAUSED\nPress P / Esc or tap Resume")
	_fill_and_center(_pause_overlay, VERTICAL_ALIGNMENT_CENTER)
	_pause_overlay.add_theme_font_size_override("font_size", 40)
	_pause_overlay.visible = false

	_audio_prompt = _make_label(root, "Click or tap to enable sound")
	_fill_and_center(_audio_prompt, VERTICAL_ALIGNMENT_BOTTOM)
	_audio_prompt.offset_bottom = -72.0

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
	rects.append(_dash_button.get_global_rect().grow(8.0))
	rects.append(_encounter_button.get_global_rect().grow(8.0))
	rects.append(_shove_button.get_global_rect().grow(8.0))
	return rects


## Reads everything shown for the run (called every tick): health bar, counters,
## dash cooldown, wave banner and the run outcome screens. Display only.
func show_run(run: GameRun) -> void:
	var fraction: float = clampf(run.hp / run.max_hp, 0.0, 1.0)
	# The white "recent damage" bar eases down on real time; healing snaps up.
	_hp_shown = lerpf(_hp_shown, run.hp, minf(1.0, GameRun.TICK_DT * 3.0)) if _hp_shown > run.hp else run.hp
	_hp_fill.size = Vector2(HP_BAR_SIZE.x * fraction, HP_BAR_SIZE.y)
	_hp_lag.size = Vector2(HP_BAR_SIZE.x * clampf(_hp_shown / run.max_hp, 0.0, 1.0), HP_BAR_SIZE.y)
	_hp_label.text = "%d" % int(run.hp)
	_wave_label.text = "WAVE %d    kills %d" % [maxi(1, run.director.wave), run.kills]
	if run.combo >= 2:
		_wave_label.text += "    chain %d" % run.combo
	if run.dash_cooldown_left > 0.0:
		_dash_label.text = "dash %.1fs" % run.dash_cooldown_left
	else:
		_dash_label.text = "dash ready"
	_show_encounter(run)
	_banner_label.text = run.banner_title if not run.dead else ""
	_banner_label.modulate.a = clampf(run.banner_left, 0.0, 1.0)

	match run.outcome():
		GameRun.Outcome.LOST:
			var fade: float = clampf((run.death_time - OUTCOME_FADE_START) * 2.0, 0.0, 1.0)
			_set_outcome_visible(fade > 0.0)
			_outcome_shade.color.a = 0.6 * fade
			_outcome_title.text = "THE SWORDS FALL SILENT"
			_outcome_detail.text = "wave %d   kills %d   best chain %d" % [maxi(1, run.director.wave), run.kills, run.best_combo]
			_outcome_prompt.text = "press R to rise again   (or tap Restart)"
			_outcome_title.modulate.a = fade
			_outcome_detail.modulate.a = fade
			_outcome_prompt.modulate.a = fade
		GameRun.Outcome.SURVIVED:
			_set_outcome_visible(true)
			_outcome_shade.color.a = 0.35
			_outcome_title.text = "WAVE SURVIVED"
			_outcome_detail.text = "wave %d   kills %d   best chain %d   health %d" % [run.director.wave, run.kills, run.best_combo, int(run.hp)]
			_outcome_prompt.text = "tap or click Restart to play again"
			_outcome_title.modulate.a = 1.0
			_outcome_detail.modulate.a = 1.0
			_outcome_prompt.modulate.a = 1.0
		_:
			_set_outcome_visible(false)


## The crowd encounter fixture's controls and legend: the Shove button, the
## switch label, and how many foes of each type are still to be beaten
## (standing, telegraphed or queued).
func _show_encounter(run: GameRun) -> void:
	var active: bool = run.scenario.dev_shove
	_encounter_button.text = "Normal" if active else "Crowd"
	_shove_button.visible = active
	_encounter_label.visible = active
	if not active:
		return
	var left: Dictionary[StringName, int] = {EnemyDefs.HUSK: 0, EnemyDefs.RUNNER: 0, EnemyDefs.BRUTE: 0}
	for enemy: EnemyState in run.enemies:
		left[enemy.kind] += 1
	for marker: SpawnMarker in run.director.markers:
		left[marker.kind] += 1
	for kind: StringName in run.director.queue:
		left[kind] += 1
	_encounter_label.text = "CROWD ENCOUNTER (dev fixture)   foes left: %d husk, %d runner, %d brute\nF / Shove: launch nearby foes into each other and the wall   C / Normal: back to the husk wave" % [left[EnemyDefs.HUSK], left[EnemyDefs.RUNNER], left[EnemyDefs.BRUTE]]


## Text of the run outcome currently on screen ("" when none). Checks read it.
func outcome_text() -> String:
	return _outcome_title.text if _outcome_title.visible else ""


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


func _set_outcome_visible(shown: bool) -> void:
	_outcome_shade.visible = shown
	_outcome_title.visible = shown
	_outcome_detail.visible = shown
	_outcome_prompt.visible = shown


func _make_rect(parent: Control, color: Color) -> ColorRect:
	var rect: ColorRect = ColorRect.new()
	rect.color = color
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rect)
	return rect


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


## The prototype's touch buttons act on pointerdown (web/mobile.js), so a Dash
## must start the instant the finger lands, not when it lifts. Callers connect
## `button_down`, not `pressed`: `pressed` fires on release by default, and even
## in press mode Godot delivers a real touch twice (the touch itself and its
## emulated mouse button), so `pressed` would fire twice per touch while
## `button_down` fires once.
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


func _fill_and_center(label: Label, vertical: VerticalAlignment) -> void:
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = vertical
