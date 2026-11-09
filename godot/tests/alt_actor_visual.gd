class_name AltActorVisual
extends ActorVisual
## Check-only stand-in for a texture-based actor: different internal offset,
## scale and orientation handling. Gameplay must be indifferent to it.

var last_facing: Vector2 = Vector2.ZERO
var pose_calls: int = 0


func _init() -> void:
	scale = Vector2(3.0, 0.5)
	rotation = 0.7


func _on_pose(facing: Vector2, _moving: bool) -> void:
	last_facing = facing
	pose_calls += 1
