class_name PlaceholderSwordVisual
extends SwordVisual
## Temporary drawn sword: a tinted blade that rides above its shadow. Fang is a thin
## needle; Warden a longer, broader blade with a heavy crossguard and pommel; Pike a long thin
## shaft ending in a leaf-shaped head; Colossus a huge, broad slab of a blade that hangs point-down
## above its shadow, so the four read apart at a glance. The rarity shows twice: the blade is as much larger as
## the rarity's size factor (Rare 1.08, Mythic 1.18) and a glow rings it, in the rarity's colour for a Rare or Mythic sword
## and the element's for a Common one; a freshly swapped-in sword's glow flares. A sword lying in the arena as a drop
## hovers point-down over its shadow. Length, width and lift are this visual's own numbers and do not
## feed reach (that is `SwordState`). A Colossus is drawn as high above the ground as the simulation's altitude
## says (the height is read, never changed).

const BLADE_LENGTH: float = 34.0
const BLADE_WIDTH: float = 6.0
const WARDEN_BLADE_LENGTH: float = 54.0
const WARDEN_BLADE_WIDTH: float = 9.0
const PIKE_BLADE_LENGTH: float = 74.0
const PIKE_BLADE_WIDTH: float = 6.0
const COLOSSUS_BLADE_LENGTH: float = 88.0
const COLOSSUS_BLADE_WIDTH: float = 15.0
const ELEMENT_COLORS: Dictionary = {
	&"fire": Color(1.0, 0.46, 0.17),
	&"ice": Color(0.47, 0.80, 1.0),
	&"poison": Color(0.52, 0.90, 0.26),
}
const LIFT_IDLE: float = 34.0
const LIFT_ATTACK: float = 14.0

var _color: Color = Color.WHITE
var _warden: bool = false
var _pike: bool = false
var _colossus: bool = false
## The rarity's size factor (it scales the drawn blade and its glow), the glow's colour, the swap flare (1 -> 0) and
## whether this visual is a dropped sword resting in the arena (it then hovers at `_hover` instead of lifting by phase).
var _scale: float = 1.0
var _glow: Color = Color.WHITE
var _flash: float = 0.0
var _resting: bool = false
var _hover: float = 0.0
## A Colossus's height above the ground as the simulation reports it (px).
var _altitude: float = 0.0
var _angle: float = -PI / 2.0
var _lift: float = LIFT_IDLE
var _phase: int = SwordState.Phase.IDLE
## Afterimages while an ultimate runs: the blade's recent positions, newest last.
## Purely this visual's own memory of where it was drawn.
var _afterimages: Array[Dictionary] = []

const AFTERIMAGE_LIMIT: int = 6


func _on_setup(spec: SwordSpec) -> void:
	_color = ELEMENT_COLORS.get(spec.element, Color.WHITE)
	_warden = spec.type_id == SwordDefs.WARDEN
	_pike = spec.type_id == SwordDefs.PIKE
	_colossus = spec.type_id == SwordDefs.COLOSSUS
	_scale = SwordDefs.RARITY_SIZE[spec.rarity]
	_glow = SwordDefs.RARITY_COLORS[spec.rarity] if spec.rarity > 0 else _color
	queue_redraw()


func _on_altitude(height: float) -> void:
	_altitude = height


func _on_flash(amount: float) -> void:
	_flash = amount


func _on_hover(height: float) -> void:
	_resting = true
	_hover = height


func _on_pose(angle: float, phase: int) -> void:
	_angle = angle
	_phase = phase
	var attacking: bool = phase == SwordState.Phase.WINDUP or phase == SwordState.Phase.STRIKE or phase == SwordState.Phase.ULTIMATE
	_lift = _hover if _resting else _altitude if _colossus else lerpf(_lift, LIFT_ATTACK if attacking else LIFT_IDLE, 0.25)
	if phase == SwordState.Phase.ULTIMATE:
		_afterimages.append({"world": position, "angle": angle})
		while _afterimages.size() > AFTERIMAGE_LIMIT:
			_afterimages.pop_front()
	elif not _afterimages.is_empty():
		_afterimages.pop_front()
	queue_redraw()


func _draw() -> void:
	var l: float = (COLOSSUS_BLADE_LENGTH if _colossus else PIKE_BLADE_LENGTH if _pike else WARDEN_BLADE_LENGTH if _warden else BLADE_LENGTH) * _scale
	var w: float = (COLOSSUS_BLADE_WIDTH if _colossus else PIKE_BLADE_WIDTH if _pike else WARDEN_BLADE_WIDTH if _warden else BLADE_WIDTH) * _scale
	if _colossus:
		# The shadow stays on the ground and shrinks and fades as the blade climbs.
		var high: float = clampf(_altitude / 260.0, 0.0, 1.0)
		draw_circle(Vector2(0.0, 6.0), lerpf(26.0, 12.0, high), Color(0.0, 0.0, 0.0, lerpf(0.34, 0.12, high)))
	else:
		draw_circle(Vector2(0.0, 6.0), 11.0 if _warden or _pike else 8.0, Color(0.0, 0.0, 0.0, 0.3))
	# The rarity's glow rings the blade (prototype: a glow of 0.75 blade lengths, brighter while a swapped-in sword's slot flashes).
	draw_circle(Vector2(0.0, -_lift), l * 0.75, Color(_glow, 0.1 + 0.2 * _flash))
	draw_circle(Vector2(0.0, -_lift), l * 0.4, Color(_glow, 0.12 + 0.2 * _flash))
	# Viper Flurry afterimages: faint copies of the blade where it just was, so the
	# darts read as streaks (each is stored in world space, drawn relative to the blade).
	for i: int in _afterimages.size():
		var image: Dictionary = _afterimages[i]
		var fade: float = float(i + 1) / float(_afterimages.size() + 1)
		draw_set_transform(Vector2(image["world"]) - position + Vector2(0.0, -_lift), float(image["angle"]), Vector2.ONE)
		draw_line(Vector2(-l * 0.35, 0.0), Vector2(l, 0.0), Color(_color, 0.35 * fade), 5.0 if _warden or _pike else 3.0)
	draw_set_transform(Vector2(0.0, -_lift), _angle, Vector2.ONE)
	var origin: Vector2 = Vector2(-l * 0.35, 0.0)
	var bright: Color = _color.lerp(Color.WHITE, 0.55 + (0.3 if _phase == SwordState.Phase.STRIKE or _phase == SwordState.Phase.ULTIMATE else 0.0))
	if _colossus:
		# A huge slab of a blade with a squared-off point, a pale fuller, a very wide guard and a heavy
		# pommel: far wider and heavier than any other sword, with a blade you can read from afar.
		var slab: PackedVector2Array = PackedVector2Array([
			origin + Vector2(0.0, w * 0.55),
			origin + Vector2(l * 0.84, w * 0.5),
			origin + Vector2(l, 0.0),
			origin + Vector2(l * 0.84, -w * 0.5),
			origin + Vector2(0.0, -w * 0.55),
		])
		draw_colored_polygon(slab, bright)
		draw_polyline(PackedVector2Array([slab[0], slab[1], slab[2], slab[3], slab[4], slab[0]]), _color.darkened(0.5), 2.0)
		draw_line(origin + Vector2(l * 0.08, 0.0), origin + Vector2(l * 0.72, 0.0), _color.darkened(0.5), maxf(1.0, w * 0.2))
		draw_line(origin + Vector2(0.0, w * 1.25), origin + Vector2(0.0, -w * 1.25), _color, maxf(2.0, w * 0.45))
		draw_line(origin, origin + Vector2(-l * 0.22, 0.0), _color.darkened(0.55), maxf(2.0, w * 0.4))
		draw_circle(origin + Vector2(-l * 0.22, 0.0), maxf(2.0, w * 0.42), _color)
	elif _pike:
		# A long thin shaft with a leaf-shaped head, a narrow crossguard and a round pommel: a
		# spear, much longer than it is wide.
		var tail: Vector2 = origin - Vector2(l * 0.28, 0.0)
		var head: Vector2 = origin + Vector2(l * 0.6, 0.0)
		var leaf: PackedVector2Array = PackedVector2Array([
			head + Vector2(0.0, w * 0.35),
			head + Vector2(l * 0.13, w * 1.35),
			origin + Vector2(l, 0.0),
			head + Vector2(l * 0.13, -w * 1.35),
			head + Vector2(0.0, -w * 0.35),
		])
		draw_line(tail, head, _color.darkened(0.4), maxf(2.0, w * 0.55))
		draw_colored_polygon(leaf, bright)
		draw_line(head + Vector2(0.0, w * 1.2), head + Vector2(0.0, -w * 1.2), _color, 2.0)
		draw_circle(tail, maxf(2.0, w * 0.6), _color)
	elif _warden:
		# A broad, straight blade with a clipped point, a pale fuller down its middle, a wide
		# crossguard and a round pommel.
		var broad: PackedVector2Array = PackedVector2Array([
			origin + Vector2(0.0, w * 0.5),
			origin + Vector2(l * 0.62, w * 0.62),
			origin + Vector2(l * 0.9, w * 0.2),
			origin + Vector2(l, 0.0),
			origin + Vector2(l * 0.9, -w * 0.2),
			origin + Vector2(l * 0.62, -w * 0.62),
			origin + Vector2(0.0, -w * 0.5),
		])
		draw_colored_polygon(broad, bright)
		draw_line(origin + Vector2(l * 0.08, 0.0), origin + Vector2(l * 0.85, 0.0), Color(1.0, 1.0, 1.0, 0.55), 1.5)
		draw_line(origin + Vector2(0.0, w * 2.4), origin + Vector2(0.0, -w * 2.4), _color, 4.0)
		draw_line(origin, origin + Vector2(-l * 0.22, 0.0), _color.darkened(0.55), 4.0)
		draw_circle(origin + Vector2(-l * 0.26, 0.0), 3.5, _color.darkened(0.3))
	else:
		var blade: PackedVector2Array = PackedVector2Array([
			origin + Vector2(0.0, w * 0.5),
			origin + Vector2(l * 0.55, w * 0.65),
			origin + Vector2(l, 0.0),
			origin + Vector2(l * 0.5, -w * 0.3),
			origin + Vector2(0.0, -w * 0.5),
		])
		draw_colored_polygon(blade, bright)
		draw_line(origin + Vector2(0.0, w * 1.7), origin + Vector2(0.0, -w * 1.7), _color, 2.0)
		draw_line(origin, origin + Vector2(-l * 0.3, 0.0), _color.darkened(0.55), 2.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
