class_name PlaceholderActorVisual
extends ActorVisual
## Temporary drawn actor: shadow, body disc and a facing marker.

const BODY_COLOR: Color = Color(0.35, 0.78, 0.95)
const MARKER_COLOR: Color = Color(0.95, 0.98, 1.0)

var _facing: Vector2 = Vector2.RIGHT
var _moving: bool = false


func _on_pose(facing: Vector2, moving: bool) -> void:
	if facing != _facing or moving != _moving:
		_facing = facing
		_moving = moving
		queue_redraw()


func _draw() -> void:
	draw_circle(Vector2(0.0, 6.0), GameRun.PLAYER_RADIUS, Color(0.0, 0.0, 0.0, 0.35))
	draw_circle(Vector2.ZERO, GameRun.PLAYER_RADIUS, BODY_COLOR)
	var marker_size: float = 5.0 if _moving else 4.0
	draw_circle(_facing * (GameRun.PLAYER_RADIUS - 2.0), marker_size, MARKER_COLOR)
