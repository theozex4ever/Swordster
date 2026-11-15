class_name PlaceholderSwordVisual
extends SwordVisual
## Temporary drawn sword: a tinted blade that rides above its shadow. Fang is a thin
## needle; Warden a longer, broader blade with a heavy crossguard and pommel, so the two
## read apart at a glance. Length, width and lift are this visual's own numbers and do not
## feed reach (that is `SwordState`).

const BLADE_LENGTH: float = 34.0
const BLADE_WIDTH: float = 6.0
const WARDEN_BLADE_LENGTH: float = 54.0
const WARDEN_BLADE_WIDTH: float = 9.0
const ELEMENT_COLORS: Dictionary = {
	&"fire": Color(1.0, 0.46, 0.17),
	&"ice": Color(0.47, 0.80, 1.0),
	&"poison": Color(0.52, 0.90, 0.26),
}
const LIFT_IDLE: float = 34.0
const LIFT_ATTACK: float = 14.0

var _color: Color = Color.WHITE
var _warden: bool = false
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
	queue_redraw()


func _on_pose(angle: float, phase: int) -> void:
	_angle = angle
	_phase = phase
	var attacking: bool = phase == SwordState.Phase.WINDUP or phase == SwordState.Phase.STRIKE or phase == SwordState.Phase.ULTIMATE
	_lift = lerpf(_lift, LIFT_ATTACK if attacking else LIFT_IDLE, 0.25)
	if phase == SwordState.Phase.ULTIMATE:
		_afterimages.append({"world": position, "angle": angle})
		while _afterimages.size() > AFTERIMAGE_LIMIT:
			_afterimages.pop_front()
	elif not _afterimages.is_empty():
		_afterimages.pop_front()
	queue_redraw()


func _draw() -> void:
	var l: float = WARDEN_BLADE_LENGTH if _warden else BLADE_LENGTH
	var w: float = WARDEN_BLADE_WIDTH if _warden else BLADE_WIDTH
	draw_circle(Vector2(0.0, 6.0), 11.0 if _warden else 8.0, Color(0.0, 0.0, 0.0, 0.3))
	# Viper Flurry afterimages: faint copies of the blade where it just was, so the
	# darts read as streaks (each is stored in world space, drawn relative to the blade).
	for i: int in _afterimages.size():
		var image: Dictionary = _afterimages[i]
		var fade: float = float(i + 1) / float(_afterimages.size() + 1)
		draw_set_transform(Vector2(image["world"]) - position + Vector2(0.0, -_lift), float(image["angle"]), Vector2.ONE)
		draw_line(Vector2(-l * 0.35, 0.0), Vector2(l, 0.0), Color(_color, 0.35 * fade), 5.0 if _warden else 3.0)
	draw_set_transform(Vector2(0.0, -_lift), _angle, Vector2.ONE)
	var origin: Vector2 = Vector2(-l * 0.35, 0.0)
	var bright: Color = _color.lerp(Color.WHITE, 0.55 + (0.3 if _phase == SwordState.Phase.STRIKE or _phase == SwordState.Phase.ULTIMATE else 0.0))
	if _warden:
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
