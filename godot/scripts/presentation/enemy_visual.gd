class_name EnemyVisual
extends Node2D
## Replaceable enemy presentation contract (ADR 0003): it receives the enemy's
## logical pose and cosmetic timers and gives nothing back. Collision radius and
## reach belong to `EnemyState`, never to the visual's size.


## Called once when the enemy appears. `kind` is the enemy type id.
func setup(kind: StringName) -> void:
	_on_setup(kind)


## Called every fixed tick. `flash` and `squash` are cosmetic timers from the
## simulation; `hp_fraction` is health as 0..1.
func apply_pose(world_position: Vector2, facing: Vector2, flash: float, squash: float, hp_fraction: float) -> void:
	position = world_position
	_on_pose(facing, flash, squash, hp_fraction)


func snap() -> void:
	reset_physics_interpolation()


func _on_setup(_kind: StringName) -> void:
	pass


func _on_pose(_facing: Vector2, _flash: float, _squash: float, _hp_fraction: float) -> void:
	pass
