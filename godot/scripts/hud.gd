class_name Hud
extends CanvasLayer
## Overlay UI: build label, controls hint, health bar, wave/kill counters, dash and
## Converge cooldowns, one card per sword slot showing its ultimate key, name, availability and
## recharge, wave banner, run outcome screens, pause/restart/dash buttons, the
## dev-encounter button, the crowd fixture's Shove button and the encounter
## legend, audio-unlock prompt, pause overlay and the touch joystick indicator. It
## reports button presses by signal and owns no gameplay state: everything it
## shows is read from the run each tick. Each sword card also names its slot's swap key and the sword's rarity;
## when a dropped sword lies within reach a card beside it describes it (`PickupCard`) and compares it with the three
## equipped swords, and says which keys claim it.

signal pause_pressed
signal restart_pressed
signal dash_pressed
signal encounter_pressed
signal shove_pressed

const HP_BAR_SIZE: Vector2 = Vector2(260.0, 18.0)
## The banner's second line sits this far above the view's centre (the title is 180 px above it).
const BANNER_SUB_OFFSET: float = -118.0
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
var _converge_label: Label
var _converge_track: ColorRect
var _converge_bar: ColorRect
var _banner_label: Label
## The line under the banner (what to do in the wave that starts or the break that follows).
var _banner_sub_label: Label
var _outcome_shade: ColorRect
var _outcome_title: Label
var _outcome_detail: Label
var _outcome_prompt: Label
var _hp_shown: float = GameRun.PLAYER_MAX_HP
## One card per sword slot: key badge, ultimate name, status text and recharge bar.
var _ult_cards: Array[Control] = []
var _ult_names: Array[Label] = []
var _ult_status: Array[Label] = []
var _ult_bars: Array[ColorRect] = []
var _ult_badges: Array[ColorRect] = []
## Each card's element tag (FIRE / ICE / POISON), in the element's colour.
var _ult_elements: Array[Label] = []
## Each card's sword type line ("Fang", "Warden", "Pike", "Colossus"), under the recharge bar.
var _ult_types: Array[Label] = []
## Each card's rarity tag (blank for a Common sword, as in the prototype) and its swap-key line, and the colour of its border.
var _ult_rarities: Array[Label] = []
var _ult_slots: Array[Label] = []
var _ult_borders: Array[Panel] = []
var _ult_backs: Array[ColorRect] = []
## The card of the dropped sword within reach (the one a swap key would claim): a panel, its lines, and the three comparisons.
var _pickup_card: Panel
var _pickup_lines: Array[Label] = []
var _pickup_compare: Array[Label] = []
var _pickup_style: StyleBoxFlat
## Screen rectangles the pickup card must also stay clear of: the touch controls (issue #20), set by the scene each tick.
var extra_avoid_rects: Array[Rect2] = []

## Where the Converge cooldown sits (right of the dash one) and how wide its bar is.
const CONVERGE_LABEL_X: float = 150.0
const CONVERGE_BAR_WIDTH: float = 150.0
const ULT_CARD_SIZE: Vector2 = Vector2(190.0, 98.0)
## Wide enough for the longest comparison line ("1  Common Venom Colossus   DMG -26   SPD +0.3/s   RNG +100" needs 430 px at the
## card's 14 px font from the 12 px margin: `DropsSwapsChecks._check_card_text_bounds` measures all 36 swords, so a longer name fails it).
const PICKUP_CARD_SIZE: Vector2 = Vector2(448.0, 214.0)
const PICKUP_CARD_MARGIN: float = 10.0
## The clear space the card keeps around every other HUD element, and around the dropped sword it describes.
const PICKUP_CARD_GAP: float = 6.0
const PICKUP_DROP_HALO: float = 30.0
const ULT_KEYS: Array[String] = ["Q", "E", "R"]


func _ready() -> void:
	var root: Control = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_build_label = _make_label(root, "Build %s (%s)" % [BuildInfo.BUILD_ID, BuildInfo.SOURCE_COMMIT.substr(0, 9)])
	_build_label.position = Vector2(16.0, 12.0)

	_hint_label = _make_label(root, "WASD / arrows: move   Space / Shift: dash   Click: Converge   Q / E / R: ultimates at the cursor   1 / 2 / 3: swap a drop\nTab / G: ranges   P / Esc: pause   R after death: restart   C: next dev encounter   Touch: drag to move, Dash button")
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
	_converge_label = _make_label(root, "converge ready")
	_converge_label.position = Vector2(CONVERGE_LABEL_X, 118.0)
	_converge_track = _make_rect(root, Color(0.16, 0.2, 0.28))
	_converge_track.position = Vector2(CONVERGE_LABEL_X, 142.0)
	_converge_track.size = Vector2(CONVERGE_BAR_WIDTH, 4.0)
	_converge_bar = _make_rect(root, Color(0.78, 0.9, 1.0))
	_converge_bar.position = Vector2(CONVERGE_LABEL_X, 142.0)
	_converge_bar.size = Vector2(CONVERGE_BAR_WIDTH, 4.0)
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
	_banner_sub_label = _make_label(root, "")
	_banner_sub_label.add_theme_font_size_override("font_size", 22)
	_fill_and_center(_banner_sub_label, VERTICAL_ALIGNMENT_CENTER)
	_banner_sub_label.offset_top = BANNER_SUB_OFFSET
	_banner_sub_label.offset_bottom = BANNER_SUB_OFFSET

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

	# DEVELOPMENT FIXTURE control: cycles the dev encounters and restarts play, so
	# it says so (the label names the encounter the press leads to).
	_encounter_button = _make_button(root, "Dev: Crowd (restarts)", Vector2(-216.0, 64.0))
	_encounter_button.size = Vector2(200.0, 44.0)
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
	_audio_prompt.offset_bottom = -96.0

	for slot: int in ULT_KEYS.size():
		_make_ultimate_card(root, slot)
	_make_pickup_card(root)

	_stick = Control.new()
	_stick.set_anchors_preset(Control.PRESET_FULL_RECT)
	_stick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stick.draw.connect(_draw_stick)
	root.add_child(_stick)


## One sword slot's ultimate card, bottom left, drawn from run state each tick.
func _make_ultimate_card(parent: Control, slot: int) -> void:
	var card: Control = Control.new()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	card.offset_left = 16.0 + float(slot) * (ULT_CARD_SIZE.x + 8.0)
	card.offset_right = card.offset_left + ULT_CARD_SIZE.x
	card.offset_bottom = -16.0
	card.offset_top = -16.0 - ULT_CARD_SIZE.y
	parent.add_child(card)
	var back: ColorRect = _make_rect(card, Color(0.07, 0.06, 0.1, 0.72))
	back.size = ULT_CARD_SIZE
	# The border takes its sword's rarity colour (a Common one is greyer): the slot's rarity at a glance.
	var border: Panel = Panel.new()
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	border.size = ULT_CARD_SIZE
	var border_style: StyleBoxFlat = StyleBoxFlat.new()
	border_style.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	border_style.set_border_width_all(2)
	border_style.set_corner_radius_all(6)
	border_style.border_color = Color(0.3, 0.3, 0.36)
	border.add_theme_stylebox_override("panel", border_style)
	card.add_child(border)
	var badge: ColorRect = _make_rect(card, Color(0.13, 0.12, 0.18))
	badge.position = Vector2(8.0, 8.0)
	badge.size = Vector2(34.0, 34.0)
	var key_label: Label = _make_label(card, ULT_KEYS[slot])
	key_label.position = Vector2(8.0, 10.0)
	key_label.size = Vector2(34.0, 30.0)
	key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	key_label.add_theme_font_size_override("font_size", 22)
	var name_label: Label = _make_label(card, "")
	name_label.position = Vector2(50.0, 4.0)
	var status_label: Label = _make_label(card, "")
	status_label.position = Vector2(50.0, 26.0)
	var element_label: Label = _make_label(card, "")
	element_label.position = Vector2(112.0, 28.0)
	element_label.size = Vector2(70.0, 20.0)
	element_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	element_label.add_theme_font_size_override("font_size", 14)
	var track: ColorRect = _make_rect(card, Color(0.16, 0.14, 0.21))
	track.position = Vector2(8.0, 50.0)
	track.size = Vector2(ULT_CARD_SIZE.x - 16.0, 5.0)
	var bar: ColorRect = _make_rect(card, Color.WHITE)
	bar.position = Vector2(8.0, 50.0)
	bar.size = Vector2(0.0, 5.0)
	var type_label: Label = _make_label(card, "")
	type_label.position = Vector2(8.0, 56.0)
	type_label.size = Vector2(ULT_CARD_SIZE.x - 16.0, 20.0)
	type_label.add_theme_font_size_override("font_size", 14)
	var rarity_label: Label = _make_label(card, "")
	rarity_label.position = Vector2(104.0, 56.0)
	rarity_label.size = Vector2(ULT_CARD_SIZE.x - 112.0, 20.0)
	rarity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rarity_label.add_theme_font_size_override("font_size", 14)
	var slot_label: Label = _make_label(card, "")
	slot_label.position = Vector2(8.0, 76.0)
	slot_label.size = Vector2(ULT_CARD_SIZE.x - 16.0, 18.0)
	slot_label.add_theme_font_size_override("font_size", 13)
	_ult_rarities.append(rarity_label)
	_ult_slots.append(slot_label)
	_ult_borders.append(border)
	_ult_backs.append(back)
	_ult_cards.append(card)
	_ult_names.append(name_label)
	_ult_status.append(status_label)
	_ult_bars.append(bar)
	_ult_badges.append(badge)
	_ult_elements.append(element_label)
	_ult_types.append(type_label)


## The card of a dropped sword: its six prototype lines, then how it compares with each equipped sword. Placed beside
## the sword each tick (`_show_pickup`), above the sword cards.
func _make_pickup_card(parent: Control) -> void:
	_pickup_card = Panel.new()
	_pickup_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pickup_card.size = PICKUP_CARD_SIZE
	_pickup_style = StyleBoxFlat.new()
	_pickup_style.bg_color = Color(0.06, 0.055, 0.095, 0.92)
	_pickup_style.set_border_width_all(2)
	_pickup_style.set_corner_radius_all(8)
	_pickup_card.add_theme_stylebox_override("panel", _pickup_style)
	_pickup_card.visible = false
	parent.add_child(_pickup_card)
	var rows: Array[Vector2] = [Vector2(12.0, 8.0), Vector2(12.0, 34.0), Vector2(12.0, 54.0), Vector2(12.0, 76.0), Vector2(12.0, 96.0), Vector2(12.0, 184.0)]
	var sizes: Array[int] = [22, 14, 16, 14, 15, 18]
	for i: int in rows.size():
		var line: Label = _make_label(_pickup_card, "")
		line.position = rows[i]
		line.add_theme_font_size_override("font_size", sizes[i])
		_pickup_lines.append(line)
	for slot: int in ULT_KEYS.size():
		var compare: Label = _make_label(_pickup_card, "")
		compare.position = Vector2(12.0, 122.0 + float(slot) * 20.0)
		compare.add_theme_font_size_override("font_size", 14)
		_pickup_compare.append(compare)


## The lines the pickup card shows, top to bottom (empty while it is hidden). Checks read it.
func pickup_card_lines() -> Array[String]:
	var shown: Array[String] = []
	if _pickup_card.visible:
		for line: Label in _pickup_lines:
			shown.append(line.text)
	return shown


func pickup_card_comparisons() -> Array[String]:
	var shown: Array[String] = []
	if _pickup_card.visible:
		for compare: Label in _pickup_compare:
			shown.append(compare.text)
	return shown


func pickup_card_visible() -> bool:
	return _pickup_card.visible


func pickup_card_rect() -> Rect2:
	return _pickup_card.get_global_rect()


## Shows the card of the dropped sword a swap key would claim, beside it, or hides it: nothing within reach, or the player
## is dead. Where it goes is `_pickup_card_spot`.
func _show_pickup(run: GameRun) -> void:
	var near: PickupState = null if run.dead else run.nearest_pickup()
	_pickup_card.visible = near != null
	if near == null:
		return
	var spec: SwordSpec = near.spec
	var tint: Color = SwordDefs.RARITY_COLORS[spec.rarity]
	_pickup_style.border_color = tint
	var view: Vector2 = get_viewport().get_visible_rect().size
	_pickup_card.position = _pickup_card_spot(near.position - run.camera + view * 0.5, view)
	var texts: Array[String] = PickupCard.lines(spec)
	for i: int in texts.size():
		_pickup_lines[i].text = texts[i]
	_pickup_lines[0].modulate = tint
	_pickup_lines[1].modulate = Color(0.63, 0.63, 0.71)
	_pickup_lines[2].modulate = Color(0.86, 0.86, 0.92)
	_pickup_lines[3].modulate = PlaceholderSwordVisual.ELEMENT_COLORS.get(spec.element, Color.WHITE)
	_pickup_lines[4].modulate = Color(0.86, 0.84, 0.94)
	_pickup_lines[5].modulate = Color.WHITE
	for slot: int in _pickup_compare.size():
		_pickup_compare[slot].visible = slot < run.swords.size()
		if slot < run.swords.size():
			var equipped: SwordSpec = run.swords[slot].spec
			_pickup_compare[slot].text = PickupCard.compare_to(spec, slot, equipped)
			_pickup_compare[slot].modulate = SwordDefs.RARITY_COLORS[equipped.rarity].lerp(Color.WHITE, 0.35)


## The screen rectangle a HUD control really draws on: a label only where its text is (a full-screen label with a centred
## line occupies that line, not the screen), anything else its own rectangle at least as large as its minimum size (a button
## or label grows to it a frame after its text changes). Empty for a label with no text.
static func occupied_rect(control: Control) -> Rect2:
	var box: Rect2 = control.get_global_rect()
	if control is Label:
		var label: Label = control
		if label.text.is_empty():
			return Rect2()
		var need: Vector2 = label.get_minimum_size()
		var spare: Vector2 = (box.size - need).max(Vector2.ZERO)
		var shift: Vector2 = Vector2(
			0.0 if label.horizontal_alignment == HORIZONTAL_ALIGNMENT_LEFT else (0.5 if label.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER else 1.0),
			0.0 if label.vertical_alignment == VERTICAL_ALIGNMENT_TOP else (0.5 if label.vertical_alignment == VERTICAL_ALIGNMENT_CENTER else 1.0))
		return Rect2(box.position + spare * shift, need)
	return Rect2(box.position, box.size.max(control.get_combined_minimum_size()))


## Every live HUD element the pickup card must stay clear of, each as the rectangle it draws on, widened by
## `PICKUP_CARD_GAP`: the build and hint lines, the health bar and its value, the dash and Converge readouts (text and bar), the
## wave line, the Pause / Restart / Dev / Shove / Dash buttons, the encounter legend, the audio prompt, the sword cards and, while
## it is up, the wave banner with its second line (issue #18: the card used to cover half of "WAVE CLEARED").
## What is not here has no fixed place or lasts a moment: the outcome and pause overlays (full-screen text
## shown over everything by design), the touch joystick indicator, and the world-space effects (range rings, floating texts).
## Controls that are hidden at the moment (the legend outside an encounter, the Shove button, a missing slot) reserve nothing.
func pickup_card_avoid() -> Array[Rect2]:
	var controls: Array[Control] = []
	controls.append_array([_build_label, _hint_label])
	controls.append_array([_hp_back, _hp_label])
	controls.append_array([_dash_label, _converge_label, _converge_track])
	controls.append(_wave_label)
	controls.append_array([_pause_button, _restart_button, _encounter_button, _shove_button, _dash_button])
	controls.append(_encounter_label)
	controls.append(_audio_prompt)
	controls.append_array(_ult_cards)
	# the banner and its second line while they are up (an empty label occupies nothing): the card steps aside for them
	controls.append_array([_banner_label, _banner_sub_label])
	var rects: Array[Rect2] = []
	for control: Control in controls:
		var rect: Rect2 = occupied_rect(control)
		if control.visible and rect.has_area():
			rects.append(rect.grow(PICKUP_CARD_GAP))
	# the touch controls (issue #20), when they are up: rectangles the scene hands in each tick
	for extra: Rect2 in extra_avoid_rects:
		rects.append(extra.grow(PICKUP_CARD_GAP))
	return rects


## Where the pickup card's top left goes for a drop at `drop` on a view of `view`: the free spot nearest the one beside the
## drop (right of it, above it), a spot being free when the card there lies inside the view and covers no HUD element
## (`pickup_card_avoid`) and, if one exists, not the drop itself. Candidates are that ideal spot and, in each axis, the
## places that touch an obstacle or the view's edge. If no spot clears the HUD (a view too small for the card and the HUD
## together; the 1280 x 720 minimum never is) the card goes where it covers the least HUD area.
func _pickup_card_spot(drop: Vector2, view: Vector2) -> Vector2:
	var card: Vector2 = PICKUP_CARD_SIZE
	var low: Vector2 = Vector2(PICKUP_CARD_MARGIN, PICKUP_CARD_MARGIN)
	var high: Vector2 = (view - card - low).max(low)
	var ideal: Vector2 = Vector2(drop.x + 40.0, drop.y - card.y - 40.0).clamp(low, high)
	var avoid: Array[Rect2] = pickup_card_avoid()
	var drop_halo: Rect2 = Rect2(drop - Vector2(PICKUP_DROP_HALO, PICKUP_DROP_HALO), Vector2(PICKUP_DROP_HALO, PICKUP_DROP_HALO) * 2.0)
	var with_halo: Array[Rect2] = avoid.duplicate()
	with_halo.append(drop_halo)
	if _covers_nothing(ideal, with_halo):
		return ideal
	var xs: Array[float] = [low.x, high.x, ideal.x]
	var ys: Array[float] = [low.y, high.y, ideal.y]
	for rect: Rect2 in with_halo:
		xs.append_array([rect.end.x, rect.position.x - card.x, rect.position.x, rect.end.x - card.x])
		ys.append_array([rect.end.y, rect.position.y - card.y, rect.position.y, rect.end.y - card.y])
	var spots: Array[Vector2] = []
	var seen_x: Dictionary[float, bool] = {}
	for x: float in xs:
		var at_x: float = clampf(x, low.x, high.x)
		if seen_x.has(at_x):
			continue
		seen_x[at_x] = true
		var seen_y: Dictionary[float, bool] = {}
		for y: float in ys:
			var at_y: float = clampf(y, low.y, high.y)
			if not seen_y.has(at_y):
				seen_y[at_y] = true
				spots.append(Vector2(at_x, at_y))
	# the nearest spot that clears the HUD and the drop, else the nearest that clears the HUD
	for obstacles: Array[Rect2] in [with_halo, avoid]:
		var best: Vector2 = ideal
		var best_distance: float = INF
		for spot: Vector2 in spots:
			var distance: float = spot.distance_squared_to(ideal)
			if distance < best_distance and _covers_nothing(spot, obstacles):
				best = spot
				best_distance = distance
		if best_distance < INF:
			return best
	# no free spot: the one that hides the least HUD (the nearest to the ideal among equals)
	var least: Vector2 = ideal
	var least_area: float = INF
	var least_distance: float = INF
	for spot: Vector2 in spots:
		var area: float = 0.0
		for rect: Rect2 in avoid:
			area += Rect2(spot, card).intersection(rect).get_area()
		var distance: float = spot.distance_squared_to(ideal)
		if area < least_area - 0.01 or (absf(area - least_area) <= 0.01 and distance < least_distance):
			least = spot
			least_area = area
			least_distance = distance
	return least


func _covers_nothing(spot: Vector2, obstacles: Array[Rect2]) -> bool:
	var card: Rect2 = Rect2(spot, PICKUP_CARD_SIZE)
	for rect: Rect2 in obstacles:
		if card.intersects(rect):
			return false
	return true


## Converge's shared cooldown (prototype `draw_hud`): the label dims and counts the seconds down, and the
## bar under it fills as the cooldown runs out. Checks read `converge_status` and `converge_bar_fraction`.
func _show_converge(run: GameRun) -> void:
	var ready: bool = run.converge_cooldown_left <= 0.0
	_converge_label.text = "converge ready" if ready else "converge %.1fs" % run.converge_cooldown_left
	_converge_label.modulate = Color.WHITE if ready else Color(0.6, 0.65, 0.78)
	_converge_bar.size.x = CONVERGE_BAR_WIDTH * (1.0 - clampf(run.converge_cooldown_left / SwordDefs.CONVERGE_COOLDOWN, 0.0, 1.0))


func converge_status() -> String:
	return _converge_label.text


func converge_bar_fraction() -> float:
	return _converge_bar.size.x / CONVERGE_BAR_WIDTH


## What the slot's card says: READY, ACTIVE while the ultimate runs, or the whole
## seconds left to recharge. Checks read it.
func ultimate_status(slot: int) -> String:
	return _ult_status[slot].text


func ultimate_card_visible(slot: int) -> bool:
	return _ult_cards[slot].visible


func ultimate_bar_fraction(slot: int) -> float:
	return _ult_bars[slot].size.x / (ULT_CARD_SIZE.x - 16.0)


func _show_ultimates(run: GameRun) -> void:
	for slot: int in _ult_cards.size():
		var shown: bool = slot < run.swords.size()
		_ult_cards[slot].visible = shown
		if not shown:
			continue
		var sword: SwordState = run.swords[slot]
		var tint: Color = PlaceholderSwordVisual.ELEMENT_COLORS.get(sword.spec.element, Color.WHITE)
		var active: bool = sword.phase == SwordState.Phase.ULTIMATE
		var ready: bool = sword.ultimate_ready()
		_ult_names[slot].text = SwordDefs.ultimate_name(sword.spec.type_id)
		_ult_names[slot].modulate = Color(0.92, 0.92, 0.98) if ready or active else Color(0.55, 0.53, 0.62)
		if active:
			_ult_status[slot].text = "ACTIVE"
		elif ready:
			_ult_status[slot].text = "READY"
		else:
			_ult_status[slot].text = "%ds" % SimMath.py_round(sword.ultimate_cooldown_left)
		_ult_status[slot].modulate = tint if ready or active else Color(0.62, 0.6, 0.7)
		_ult_elements[slot].text = String(sword.spec.element).to_upper()
		_ult_elements[slot].modulate = tint
		_ult_types[slot].text = "%s sword%s" % [SwordDefs.display_name(sword.spec.type_id), "  skill shot" if SwordDefs.ultimate_is_shot(sword.spec.type_id) else ""]
		_ult_types[slot].modulate = Color(0.78, 0.78, 0.86) if ready or active else Color(0.55, 0.53, 0.62)
		_ult_badges[slot].color = tint if ready or active else Color(0.13, 0.12, 0.18)
		_ult_bars[slot].color = tint
		_ult_bars[slot].size.x = (ULT_CARD_SIZE.x - 16.0) * (1.0 if active else sword.ultimate_charge())
		var rarity_tint: Color = SwordDefs.RARITY_COLORS[sword.spec.rarity]
		_ult_rarities[slot].text = SwordDefs.RARITY_NAMES[sword.spec.rarity].to_upper() if sword.spec.rarity > 0 else ""
		_ult_rarities[slot].modulate = rarity_tint
		_ult_slots[slot].text = "key %d swaps this sword" % (slot + 1)
		_ult_slots[slot].modulate = Color(0.55, 0.53, 0.64)
		(_ult_borders[slot].get_theme_stylebox("panel") as StyleBoxFlat).border_color = rarity_tint.darkened(0.3) if sword.spec.rarity == 0 else rarity_tint
		# A freshly swapped-in sword's card flashes in its element's colour, easing out as the sword's own flash does.
		_ult_backs[slot].color = Color(0.07, 0.06, 0.1, 0.72).lerp(Color(tint, 0.72), 0.12 + 0.35 * sword.flash)


func bind_joystick(joystick: TouchJoystick) -> void:
	_joystick = joystick


## Screen rectangles a touch on the HUD's buttons occupies: it must neither start the touch joystick nor aim Converge at the
## arena behind it. A hidden button (the Shove button outside the crowd encounter) takes no touch, so it blocks none.
func button_rects() -> Array[Rect2]:
	var rects: Array[Rect2] = []
	for button: Button in [_pause_button, _restart_button, _dash_button, _encounter_button, _shove_button]:
		if button.is_visible_in_tree():
			rects.append(button.get_global_rect().grow(8.0))
	return rects


## The Dash button's rectangle: the anchor the touch controls (issue #20) are laid out around.
func dash_rect() -> Rect2:
	return _dash_button.get_global_rect()


## Touch play (issue #20): the keyboard hint line says nothing a touch player can use, so it goes.
func set_touch_mode(on: bool) -> void:
	_hint_label.visible = not on


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
	# The prototype shows the chain from the third kill (`combo >= 3`).
	if run.combo >= 3:
		_wave_label.text += "    chain %d" % run.combo
	if run.dash_cooldown_left > 0.0:
		_dash_label.text = "dash %.1fs" % run.dash_cooldown_left
	else:
		_dash_label.text = "dash ready"
	_show_converge(run)
	_show_ultimates(run)
	# the encounter's legend and buttons first: the pickup card is placed clear of them as they now are
	_show_encounter(run)
	_show_pickup(run)
	_banner_label.text = run.banner_title if not run.dead else ""
	_banner_label.modulate.a = clampf(run.banner_left, 0.0, 1.0)
	_banner_sub_label.text = run.banner_sub if not run.dead else ""
	_banner_sub_label.modulate.a = _banner_label.modulate.a

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


## The dev encounters' controls and legend: the button naming where a press
## leads (it restarts play), the crowd's Shove button, and how many foes of each
## type are still to be beaten (standing, telegraphed or queued).
func _show_encounter(run: GameRun) -> void:
	var active: bool = run.scenario.encounter != RunScenario.ENCOUNTER_NORMAL
	_encounter_button.text = "Dev: %s (restarts)" % RunScenario.encounter_title(RunScenario.next_encounter(run.scenario.encounter))
	_shove_button.visible = run.scenario.dev_shove
	_encounter_label.visible = active
	if not active:
		return
	var left: Dictionary[StringName, int] = {EnemyDefs.HUSK: 0, EnemyDefs.RUNNER: 0, EnemyDefs.SPITTER: 0, EnemyDefs.BRUTE: 0}
	for enemy: EnemyState in run.enemies:
		left[enemy.kind] += 1
	for marker: SpawnMarker in run.director.markers:
		left[marker.kind] += 1
	for kind: StringName in run.director.queue:
		left[kind] += 1
	var switch_hint: String = "C: next dev encounter (restarts)"
	if run.scenario.encounter == RunScenario.ENCOUNTER_SPITTERS:
		_encounter_label.text = "SPITTER ENCOUNTER (dev fixture)   foes left: %d spitter, %d husk   orbs fired %d, parried %d\nSpitters glow, then spit an orb: dash through it or let a striking Fang sweep it away.   %s" % [
			left[EnemyDefs.SPITTER], left[EnemyDefs.HUSK], run.cue_count(SimCue.Kind.PROJECTILE_FIRED), run.cue_count(SimCue.Kind.PROJECTILE_PARRIED), switch_hint]
	elif run.scenario.encounter == RunScenario.ENCOUNTER_WARDEN:
		_encounter_label.text = "WARDEN ENCOUNTER (dev fixture)   foes left: %d husk, %d runner, %d brute   maelstroms finished %d, hits landed %d\nSweeps alternate. E / R: Maelstrom pulls foes in, then bursts. Q: Viper Flurry.   %s" % [
			left[EnemyDefs.HUSK], left[EnemyDefs.RUNNER], left[EnemyDefs.BRUTE], run.cue_count(SimCue.Kind.MAELSTROM_BURST), run.cue_count(SimCue.Kind.ENEMY_HIT), switch_hint]
	elif run.scenario.encounter == RunScenario.ENCOUNTER_PIKE:
		_encounter_label.text = "PIKE ENCOUNTER (dev fixture)   foes left: %d husk, %d runner, %d brute   skewers launched %d, wall slams %d\nPikes thrust through whole lines. Q / E / R: Skewer fires toward the cursor, carries what it spears and slams it into a wall (aim north).   %s" % [
			left[EnemyDefs.HUSK], left[EnemyDefs.RUNNER], left[EnemyDefs.BRUTE], run.cue_count(SimCue.Kind.SKEWER_LAUNCHED), run.cue_count(SimCue.Kind.WALL_SLAM), switch_hint]
	elif run.scenario.encounter == RunScenario.ENCOUNTER_DROPS:
		var armed_left: int = 0
		for enemy: EnemyState in run.enemies:
			armed_left += 1 if enemy.armed != null else 0
		for carried: SwordSpec in run.director.queue_armed:
			armed_left += 1 if carried != null else 0
		for marker: SpawnMarker in run.director.markers:
			armed_left += 1 if marker.armed != null else 0
		_encounter_label.text = "DROPS ENCOUNTER (dev fixture)   armed foes left: %d   swords lying: %d   dropped %d, swapped %d\nKill an armed foe, stand within %d px of its sword and press 1 / 2 / 3 to swap it into that slot.\nThe old sword drops and the slot keeps its ultimate recharge.   %s" % [
			armed_left, run.pickups.size(), run.cue_count(SimCue.Kind.SWORD_DROPPED), run.cue_count(SimCue.Kind.SWORD_SWAPPED), int(LootDefs.PICKUP_REACH), switch_hint]
	elif run.scenario.encounter == RunScenario.ENCOUNTER_COLOSSUS:
		_encounter_label.text = "COLOSSUS ENCOUNTER (dev fixture)   foes left: %d husk, %d runner, %d spitter, %d brute\nslams %d, Cataclysm fields %d (live %d)   Q / E / R: Cataclysm at the cursor, up to 480 px\nColossi crush the biggest cluster and clear orbs.   %s" % [
			left[EnemyDefs.HUSK], left[EnemyDefs.RUNNER], left[EnemyDefs.SPITTER], left[EnemyDefs.BRUTE], run.cue_count(SimCue.Kind.COLOSSUS_SLAM), run.cue_count(SimCue.Kind.FIELD_CREATED), run.fields.size(), switch_hint]
	elif run.scenario.encounter == RunScenario.ENCOUNTER_CONDITIONS:
		var frozen: int = 0
		var burning: int = 0
		var poisoned: int = 0
		for enemy: EnemyState in run.enemies:
			frozen += 1 if enemy.conditions.is_frozen() else 0
			burning += 1 if enemy.conditions.is_burning() else 0
			poisoned += 1 if enemy.conditions.poison > 0.0 else 0
		_encounter_label.text = "CONDITIONS ENCOUNTER (dev fixture)   foes left: %d husk, %d runner, %d brute   burning %d, poisoned %d, frozen %d\nPoison stacks to 6, four ice hits freeze (a brute thaws sooner), a burning death sets its neighbours alight.   %s" % [
			left[EnemyDefs.HUSK], left[EnemyDefs.RUNNER], left[EnemyDefs.BRUTE], burning, poisoned, frozen, switch_hint]
	else:
		_encounter_label.text = "CROWD ENCOUNTER (dev fixture)   foes left: %d husk, %d runner, %d brute\nF / Shove: launch nearby foes into each other and the wall   %s" % [left[EnemyDefs.HUSK], left[EnemyDefs.RUNNER], left[EnemyDefs.BRUTE], switch_hint]


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
