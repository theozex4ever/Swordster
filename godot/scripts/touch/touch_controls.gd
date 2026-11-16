class_name TouchControls
extends CanvasLayer
## The touch controls (issue #20), in a layer of their own above the HUD: Converge, the three ultimates, the three swaps, the
## attack-range toggle, fullscreen where the browser offers it, and a large Resume (while paused) or Restart (once the run is
## over). Dash, Pause and Restart stay the HUD's own buttons, joystick included. Every press becomes one of the shared
## `GameCommand`s (the very ones keys and the mouse produce); aiming is the prototype's touch aiming: the nearest living enemy, or
## 300 px ahead of the player. The layer owns no gameplay state: what it shows is read from the run each tick.
##
## Buttons act on the finger landing (`button_down`), like the HUD's, and Godot delivers every finger to them independently, so
## one thumb can steer while another presses. The rectangles they occupy (`blocked_rects`) are what keeps a press on a button from
## also steering the joystick or aiming Converge at the arena behind it (see `TouchPointers`).

signal command_requested(command: GameCommand)
signal fullscreen_pressed

const DIM: Color = Color(1.0, 1.0, 1.0, 0.6)
const LIT: Color = Color(1.0, 1.0, 1.0, 0.92)

## Set while the scene hands the engine the lift of a finger that never reported one: no button may act on it.
var quiet: bool = false

var _root: Control
var _buttons: Dictionary[StringName, Button] = {}
var _rotate_hint: Label
var _view: Vector2 = Vector2.ZERO
var _insets: Vector4 = Vector4.ZERO
var _dash: Rect2 = Rect2()
var _fullscreen_supported: bool = false
## Slot buttons only exist for slots the run holds a sword in; remembered so a hidden slot blocks nothing.
var _active: bool = false
## The big Resume / Restart buttons are hidden by the very press that uses them; the engine then loses that finger's release and
## ignores the button's next press. So a held button stays up until its finger lifts: whether each is wanted, and whether held.
var _wanted: Dictionary[StringName, bool] = {}
var _held: Dictionary[StringName, bool] = {}


func _ready() -> void:
	layer = 2
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_add(TouchLayout.CONVERGE, "Converge", func() -> void: command_requested.emit(GameCommand.converge_at_nearest()))
	for slot: int in 3:
		_add(TouchLayout.ultimate_id(slot), "", func() -> void: command_requested.emit(GameCommand.ultimate_at_nearest(slot)))
		_add(TouchLayout.swap_id(slot), "Swap %d" % (slot + 1), func() -> void: command_requested.emit(GameCommand.swap(slot)))
	_add(TouchLayout.RANGES, "Ranges", func() -> void: command_requested.emit(GameCommand.toggle_ranges()))
	# the browser grants a fullscreen request only inside a user activation, and a touch gives one when the finger lifts
	# (`pressed`: a lift on the button; one the engine is given to drop a hold, off the button, never asks)
	_add(TouchLayout.FULLSCREEN, "Full", func() -> void: fullscreen_pressed.emit(), true)
	_add(TouchLayout.RESUME, "Resume", func() -> void: command_requested.emit(GameCommand.resume()))
	_add(TouchLayout.RESTART, "Restart", func() -> void: command_requested.emit(GameCommand.restart()))
	for id: StringName in [TouchLayout.RESUME, TouchLayout.RESTART]:
		_buttons[id].add_theme_font_size_override("font_size", 34)
	_rotate_hint = Label.new()
	_rotate_hint.text = "Turn your phone sideways for a wider view"
	_rotate_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rotate_hint.add_theme_font_size_override("font_size", 16)
	_rotate_hint.add_theme_color_override("font_color", Color(0.9, 0.92, 1.0, 0.8))
	_rotate_hint.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.8))
	_rotate_hint.add_theme_constant_override("outline_size", 4)
	_rotate_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_rotate_hint)
	_apply_visibility()


## Shows or hides the whole layer (hidden: no button, no rectangle, nothing for a touch to land on).
func set_active(active: bool) -> void:
	_active = active
	_apply_visibility()


func is_active() -> bool:
	return _active


## Lays the buttons out for a viewport, its safe-area insets and the HUD's Dash button, when any of them changed.
func layout(view: Vector2, insets: Vector4, dash: Rect2, fullscreen_supported: bool) -> void:
	if view == _view and insets == _insets and dash == _dash and fullscreen_supported == _fullscreen_supported:
		return
	_view = view
	_insets = insets
	_dash = dash
	_fullscreen_supported = fullscreen_supported
	var rects: Dictionary[StringName, Rect2] = TouchLayout.button_rects(view, insets, dash)
	for id: StringName in rects:
		if _buttons.has(id):
			var rect: Rect2 = rects[id]
			_buttons[id].position = rect.position
			_buttons[id].size = rect.size
	_rotate_hint.position = Vector2(insets.x, maxf(insets.y, 0.0) + 60.0)
	_rotate_hint.size = Vector2(view.x - insets.x - insets.z, 24.0)


## The screen rectangles of every visible button: what a touch must not also steer or aim through.
func blocked_rects() -> Array[Rect2]:
	var rects: Array[Rect2] = []
	if not _active:
		return rects
	for id: StringName in _buttons:
		var button: Button = _buttons[id]
		if button.visible:
			rects.append(Rect2(button.position, button.size).grow(8.0))
	return rects


## Every visible button's rectangle, by id (checks read it).
func button_rect(id: StringName) -> Rect2:
	var button: Button = _buttons.get(id)
	if button == null or not _active or not button.visible:
		return Rect2()
	return Rect2(button.position, button.size)


func button_visible(id: StringName) -> bool:
	var button: Button = _buttons.get(id)
	return button != null and _active and button.visible


func button_text(id: StringName) -> String:
	var button: Button = _buttons.get(id)
	return "" if button == null else button.text


func button_lit(id: StringName) -> bool:
	var button: Button = _buttons.get(id)
	return button != null and button.modulate.a > 0.7


## Reads the run for what each button says and whether it is worth pressing now (display only).
func show_run(run: GameRun) -> void:
	if not _active:
		return
	var over: bool = run.outcome() != GameRun.Outcome.RUNNING
	var restartable: bool = (run.dead and run.death_time > GameRun.RESTART_DELAY) or run.outcome() == GameRun.Outcome.SURVIVED
	_want(TouchLayout.RESUME, run.paused and not over)
	_want(TouchLayout.RESTART, restartable)
	var live: bool = not run.paused and not run.dead
	var converge: Button = _buttons[TouchLayout.CONVERGE]
	converge.text = "Converge\nready" if run.converge_cooldown_left <= 0.0 else "Converge\n%.1fs" % run.converge_cooldown_left
	converge.modulate = LIT if live and run.converge_cooldown_left <= 0.0 else DIM
	var pickup_near: bool = run.nearest_pickup() != null
	for slot: int in 3:
		var held: bool = slot < run.swords.size()
		var ultimate: Button = _buttons[TouchLayout.ultimate_id(slot)]
		var swap: Button = _buttons[TouchLayout.swap_id(slot)]
		ultimate.visible = held
		swap.visible = held
		if not held:
			continue
		var sword: SwordState = run.swords[slot]
		var status: String = "ACTIVE" if sword.phase == SwordState.Phase.ULTIMATE else ("READY" if sword.ultimate_ready() else "%ds" % SimMath.py_round(sword.ultimate_cooldown_left))
		ultimate.text = "%s\n%s" % [Hud.ULT_KEYS[slot], status]
		ultimate.modulate = LIT if live and sword.ultimate_ready() else DIM
		swap.modulate = LIT if live and pickup_near else DIM
	_buttons[TouchLayout.RANGES].modulate = LIT if run.show_ranges else DIM
	_buttons[TouchLayout.FULLSCREEN].modulate = LIT
	_rotate_hint.visible = TouchLayout.is_portrait(_view)
	_buttons[TouchLayout.FULLSCREEN].visible = _fullscreen_supported


func _apply_visibility() -> void:
	if _root == null:
		return
	_root.visible = _active
	for id: StringName in [TouchLayout.RESUME, TouchLayout.RESTART]:
		_want(id, false)


func _want(id: StringName, wanted: bool) -> void:
	_wanted[id] = wanted
	_buttons[id].visible = wanted or _held.get(id, false)


## Forgets every held button (focus loss, suspension, a cancelled touch, a restart): the finger that was on one will never
## report its lift. Hidden-while-held buttons come back to what the run wants. (The engine's own hold on a pressed button is
## dropped by `Main`, which gives it the missing lift.)
func release_all() -> void:
	_held.clear()
	for id: StringName in _buttons:
		if _wanted.has(id):
			_buttons[id].visible = _wanted[id]


func _add(id: StringName, text: String, on_action: Callable, on_release: bool = false) -> void:
	var button: Button = Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 20)
	# a plain, readable pad: the default theme's near-black one vanishes against the arena
	for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		var pad: StyleBoxFlat = StyleBoxFlat.new()
		pad.bg_color = Color(0.2, 0.23, 0.34, 0.8) if state != "pressed" else Color(0.36, 0.42, 0.6, 0.9)
		pad.set_corner_radius_all(10)
		pad.set_border_width_all(2)
		pad.border_color = Color(0.7, 0.75, 0.95, 0.55)
		button.add_theme_stylebox_override(state, pad)
	button.button_down.connect(func() -> void:
		_held[id] = true
		if not on_release:
			on_action.call())
	button.button_up.connect(func() -> void:
		_held.erase(id)
		if _wanted.has(id):
			button.visible = _wanted[id])
	if on_release:
		button.pressed.connect(func() -> void:
			if not quiet:
				on_action.call())
	_root.add_child(button)
	_buttons[id] = button
