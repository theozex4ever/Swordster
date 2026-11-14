class_name PlaceholderEnemyVisual
extends EnemyVisual
## Temporary drawn husk: a red disc with a facing eye, a hit flash and a small
## health bar once damaged. Its size is its own and does not feed collision.

const BODY_COLOR: Color = Color(0.84, 0.28, 0.34)
const BODY_RADIUS: float = 16.0

var _facing: Vector2 = Vector2.LEFT
var _flash: float = 0.0
var _squash: float = 0.0
var _hp_fraction: float = 1.0


func _on_pose(facing: Vector2, flash: float, squash: float, hp_fraction: float) -> void:
	_facing = facing
	_flash = flash
	_squash = squash
	_hp_fraction = hp_fraction
	queue_redraw()


func _draw() -> void:
	draw_circle(Vector2(0.0, 6.0), BODY_RADIUS, Color(0.0, 0.0, 0.0, 0.35))
	var stretch: float = 1.0 + _squash * 0.18
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(stretch, 1.0 / stretch))
	var body: Color = BODY_COLOR.lerp(Color.WHITE, clampf(_flash * 6.0, 0.0, 1.0))
	draw_circle(Vector2.ZERO, BODY_RADIUS, body)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_circle(_facing * (BODY_RADIUS * 0.5), 4.0, Color(1.0, 0.9, 0.7))
	if _hp_fraction < 1.0:
		var width: float = BODY_RADIUS * 2.0
		draw_rect(Rect2(-width * 0.5, -BODY_RADIUS - 10.0, width, 4.0), Color(0.0, 0.0, 0.0, 0.6))
		draw_rect(Rect2(-width * 0.5, -BODY_RADIUS - 10.0, width * _hp_fraction, 4.0), Color(0.95, 0.35, 0.4))
