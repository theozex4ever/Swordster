class_name PlaceholderSwordVisual
extends SwordVisual
## Temporary drawn Fang: a tinted blade that rides above its shadow. Length,
## width and lift are this visual's own numbers and do not feed reach.

const BLADE_LENGTH: float = 34.0
const BLADE_WIDTH: float = 6.0
const ELEMENT_COLORS: Dictionary = {
	&"fire": Color(1.0, 0.46, 0.17),
	&"ice": Color(0.47, 0.80, 1.0),
	&"poison": Color(0.52, 0.90, 0.26),
}
const LIFT_IDLE: float = 34.0
const LIFT_ATTACK: float = 14.0

var _color: Color = Color.WHITE
var _angle: float = -PI / 2.0
var _lift: float = LIFT_IDLE
var _phase: int = SwordState.Phase.IDLE


func _on_setup(spec: SwordSpec) -> void:
	_color = ELEMENT_COLORS.get(spec.element, Color.WHITE)
	queue_redraw()


func _on_pose(angle: float, phase: int) -> void:
	_angle = angle
	_phase = phase
	var goal: float = LIFT_ATTACK if phase == SwordState.Phase.WINDUP or phase == SwordState.Phase.STRIKE else LIFT_IDLE
	_lift = lerpf(_lift, goal, 0.25)
	queue_redraw()


func _draw() -> void:
	draw_circle(Vector2(0.0, 6.0), 8.0, Color(0.0, 0.0, 0.0, 0.3))
	draw_set_transform(Vector2(0.0, -_lift), _angle, Vector2.ONE)
	var l: float = BLADE_LENGTH
	var w: float = BLADE_WIDTH
	var origin: Vector2 = Vector2(-l * 0.35, 0.0)
	var blade: PackedVector2Array = PackedVector2Array([
		origin + Vector2(0.0, w * 0.5),
		origin + Vector2(l * 0.55, w * 0.65),
		origin + Vector2(l, 0.0),
		origin + Vector2(l * 0.5, -w * 0.3),
		origin + Vector2(0.0, -w * 0.5),
	])
	var bright: Color = _color.lerp(Color.WHITE, 0.55 + (0.3 if _phase == SwordState.Phase.STRIKE else 0.0))
	draw_colored_polygon(blade, bright)
	draw_line(origin + Vector2(0.0, w * 1.7), origin + Vector2(0.0, -w * 1.7), _color, 2.0)
	draw_line(origin, origin + Vector2(-l * 0.3, 0.0), _color.darkened(0.55), 2.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
