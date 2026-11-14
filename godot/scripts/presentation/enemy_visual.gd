class_name EnemyVisual
extends Node2D
## Replaceable enemy presentation contract (ADR 0003): it receives the enemy's
## logical pose and cosmetic timers and gives nothing back. Collision radius and
## reach belong to `EnemyState`, never to the visual's size.


## Called once when the enemy appears. `kind` is the enemy type id.
func setup(kind: StringName) -> void:
	_on_setup(kind)


## Called every fixed tick. `flash` and `squash` are cosmetic timers from the
## simulation; `hp_fraction` is health as 0..1; `stunned` is true while the
## enemy is knocked back and out of control (launched enemies are stunned);
## `telegraph` is 0..1 progress of a ranged enemy's shot wind-up (0 when it is
## not winding up), so the visual can show the warning without owning its timing.
func apply_pose(world_position: Vector2, facing: Vector2, flash: float, squash: float, hp_fraction: float, stunned: bool = false, telegraph: float = 0.0) -> void:
	position = world_position
	_on_pose(facing, flash, squash, hp_fraction, stunned, telegraph)


## Called every fixed tick after `apply_pose`: which elemental conditions are on the
## enemy (a read-only copy). Optional: a visual that does not show conditions can
## ignore it. Timers and damage stay in the simulation; a cue's look never drives them.
func apply_conditions(view: ConditionView) -> void:
	_on_conditions(view)


func snap() -> void:
	reset_physics_interpolation()


func _on_setup(_kind: StringName) -> void:
	pass


func _on_conditions(_view: ConditionView) -> void:
	pass


func _on_pose(_facing: Vector2, _flash: float, _squash: float, _hp_fraction: float, _stunned: bool, _telegraph: float) -> void:
	pass
