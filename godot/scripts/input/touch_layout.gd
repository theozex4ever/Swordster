class_name TouchLayout
extends RefCounted
## Where the touch controls sit (issue #20), as pure geometry in viewport (logical) pixels so every
## viewport, orientation and safe area can be checked without a screen. Everything is placed
## relative to the HUD's own Dash button, which stays where the HUD put it, and kept inside the
## safe area (`insets`: left, top, right, bottom in logical pixels, the notches and bars the page does
## not already avoid).
##
## Landscape (the view the game is laid out for):
##
##   top right:        [Fullscreen] [Ranges]            (under the HUD's Pause / Restart / Dev buttons)
##   centre:           [Resume] while paused, [Restart] once the run is over
##   bottom right:                [Swap 1][Swap 2][Swap 3]
##                      [Q][E][R]   [Converge]
##                                  [Dash]   (the HUD's)
##
## A narrow view (portrait) cannot hold the HUD's sword cards beside these, so the bottom rows lift above them.

const BUTTON: float = 96.0
const CONVERGE_SIZE: float = 104.0
const SWAP_SIZE: Vector2 = Vector2(96.0, 60.0)
const SMALL_SIZE: Vector2 = Vector2(80.0, 52.0)
const BIG_SIZE: Vector2 = Vector2(260.0, 96.0)
const GAP: float = 10.0
const MARGIN: float = 24.0
## The room the HUD's Shove button (a development fixture) keeps left of Dash, so nothing is built over it.
const SHOVE_ROOM: float = 120.0
## Views narrower than this lift their bottom rows above the HUD's sword cards (their width plus the buttons).
const WIDE_VIEW: float = 1100.0
const LIFT: float = 126.0
## Where the joystick may start: the left share of the view, below the HUD's top line.
const JOYSTICK_WIDTH_SHARE: float = 0.55
const JOYSTICK_TOP_SHARE: float = 0.15
## The two base sizes the game is laid out for, by orientation.
const LANDSCAPE_BASE: Vector2i = Vector2i(1280, 720)
const PORTRAIT_BASE: Vector2i = Vector2i(720, 1280)

const CONVERGE: StringName = &"converge"
const ULTIMATE: StringName = &"ultimate"
const SWAP: StringName = &"swap"
const RANGES: StringName = &"ranges"
const FULLSCREEN: StringName = &"fullscreen"
const RESUME: StringName = &"resume"
const RESTART: StringName = &"restart"


## The base viewport size for a window of `window_size` physical pixels: portrait windows get the portrait base, so the
## controls stay as large on a phone held upright as on one held sideways (the HUD is laid out for 1280 x 720 or 720 x 1280).
static func base_size_for(window_size: Vector2i) -> Vector2i:
	return PORTRAIT_BASE if window_size.y > window_size.x else LANDSCAPE_BASE


static func is_portrait(view: Vector2) -> bool:
	return view.y > view.x


## The rectangle of every touch button, by id ("ultimate0".."ultimate2", "swap0".."swap2" for the slots).
static func button_rects(view: Vector2, insets: Vector4, dash: Rect2) -> Dictionary[StringName, Rect2]:
	var rects: Dictionary[StringName, Rect2] = {}
	var lift: float = 0.0 if view.x >= WIDE_VIEW else LIFT
	var right: float = view.x - insets.z
	var bottom: float = view.y - insets.w
	# the HUD's Dash button (or where it would be) is the anchor of the bottom right cluster, pulled inside the safe area
	var anchor: Rect2 = dash
	if not anchor.has_area():
		anchor = Rect2(right - MARGIN - 104.0, bottom - MARGIN - 104.0, 104.0, 104.0)
	anchor.position = Vector2(minf(anchor.position.x, right - MARGIN - anchor.size.x), minf(anchor.position.y, bottom - MARGIN - anchor.size.y))
	rects[CONVERGE] = Rect2(anchor.position.x - (CONVERGE_SIZE - anchor.size.x) * 0.5, anchor.position.y - GAP - CONVERGE_SIZE, CONVERGE_SIZE, CONVERGE_SIZE)
	var row_right: float = anchor.position.x - SHOVE_ROOM - GAP
	var row_y: float = anchor.end.y - BUTTON - lift
	for slot: int in 3:
		var x: float = row_right - float(3 - slot) * BUTTON - float(2 - slot) * GAP
		rects[ultimate_id(slot)] = Rect2(x, row_y, BUTTON, BUTTON)
		rects[swap_id(slot)] = Rect2(x + (BUTTON - SWAP_SIZE.x) * 0.5, row_y - GAP - SWAP_SIZE.y, SWAP_SIZE.x, SWAP_SIZE.y)
	var top_y: float = maxf(116.0, insets.y + GAP)
	rects[RANGES] = Rect2(right - MARGIN - SMALL_SIZE.x, top_y, SMALL_SIZE.x, SMALL_SIZE.y)
	rects[FULLSCREEN] = Rect2(right - MARGIN - SMALL_SIZE.x * 2.0 - GAP, top_y, SMALL_SIZE.x, SMALL_SIZE.y)
	var centre: Vector2 = Vector2((insets.x + right) * 0.5, view.y * 0.5 + 130.0)
	rects[RESUME] = Rect2(centre - BIG_SIZE * 0.5, BIG_SIZE)
	rects[RESTART] = rects[RESUME]
	return rects


## Where the movement joystick may start.
static func joystick_zone(view: Vector2, insets: Vector4) -> Rect2:
	var top: float = maxf(view.y * JOYSTICK_TOP_SHARE, insets.y)
	var left: float = insets.x
	var right: float = view.x * JOYSTICK_WIDTH_SHARE
	var bottom: float = view.y - insets.w
	return Rect2(left, top, maxf(right - left, 0.0), maxf(bottom - top, 0.0))


static func ultimate_id(slot: int) -> StringName:
	return StringName("%s%d" % [ULTIMATE, slot])


static func swap_id(slot: int) -> StringName:
	return StringName("%s%d" % [SWAP, slot])


## Safe-area insets from the page's CSS env() values: `css` is (top, right, bottom, left) in CSS pixels, scaled onto the
## viewport by `logical_per_css` (the viewport's width over the page's). Returns (left, top, right, bottom), never negative.
static func insets_from_css(css: Vector4, logical_per_css: float) -> Vector4:
	var scale: float = maxf(logical_per_css, 0.0)
	return Vector4(maxf(css.w, 0.0) * scale, maxf(css.x, 0.0) * scale, maxf(css.y, 0.0) * scale, maxf(css.z, 0.0) * scale)
