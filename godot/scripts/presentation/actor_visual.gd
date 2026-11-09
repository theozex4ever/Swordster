class_name ActorVisual
extends Node2D
## Replaceable actor presentation contract.
##
## Gameplay hands a visual only its logical pose; it never reads anything back
## from it. A texture/sprite-based replacement subclasses or mimics this
## script, sets its own scale, pivot and orientation locally, and is swapped in
## through the `actor_visual` export on the arena. Hitboxes, reach and timing
## stay in `GameRun`.


## Called every fixed tick. `world_position` is the logical (gameplay) position.
func apply_pose(world_position: Vector2, facing: Vector2, moving: bool) -> void:
	position = world_position
	_on_pose(facing, moving)


## Called after a restart so interpolation does not smear across the reset.
func snap() -> void:
	reset_physics_interpolation()


func _on_pose(_facing: Vector2, _moving: bool) -> void:
	pass
