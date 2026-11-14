class_name PlaceholderActorVisual
extends ActorVisual
## Temporary drawn actor: shadow, body disc and a facing marker. Blinks while
## invulnerable and greys out when dead. Sizes are this visual's own.

const BODY_COLOR: Color = Color(0.35, 0.78, 0.95)
const DEAD_COLOR: Color = Color(0.35, 0.40, 0.48)
const MARKER_COLOR: Color = Color(0.95, 0.98, 1.0)
const BODY_RADIUS: float = 14.0

var _facing: Vector2 = Vector2.RIGHT
var _moving: bool = false
var _invulnerable: bool = false
var _dead: bool = false
var _blink: int = 0


func _on_pose(facing: Vector2, moving: bool) -> void:
	if facing != _facing or moving != _moving:
		_facing = facing
		_moving = moving
		queue_redraw()


func _on_state(invulnerable: bool, dead: bool) -> void:
	_blink += 1
	if invulnerable != _invulnerable or dead != _dead or (invulnerable and _blink % 3 == 0):
		_invulnerable = invulnerable
		_dead = dead
		queue_redraw()


func _draw() -> void:
	draw_circle(Vector2(0.0, 6.0), BODY_RADIUS, Color(0.0, 0.0, 0.0, 0.35))
	var alpha: float = 0.45 if _invulnerable and _blink % 6 < 3 else 1.0
	var body: Color = DEAD_COLOR if _dead else BODY_COLOR
	body.a = alpha
	draw_circle(Vector2.ZERO, BODY_RADIUS, body)
	var marker_size: float = 5.0 if _moving else 4.0
	var marker: Color = MARKER_COLOR
	marker.a = alpha
	draw_circle(_facing * (BODY_RADIUS - 2.0), marker_size, marker)
