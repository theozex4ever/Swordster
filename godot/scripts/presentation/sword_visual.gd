class_name SwordVisual
extends Node2D
## Replaceable spirit-sword presentation contract (ADR 0003).
##
## The run hands a visual the sword's logical pose (position, blade angle) and
## action phase. Animation follows the phase; it never delivers damage, never
## advances the sword's state and never feeds anything back. Texture size,
## pivot, lift and orientation are local to the visual. Reach and hit geometry
## stay in `SwordState`.


## Called once when the sword is equipped.
func setup(spec: SwordSpec) -> void:
	_on_setup(spec)


## Called every fixed tick. `phase` is a `SwordState.Phase` value.
func apply_pose(world_position: Vector2, angle: float, phase: int) -> void:
	position = world_position
	_on_pose(angle, phase)


## Called when the visual is first shown so interpolation does not smear.
func snap() -> void:
	reset_physics_interpolation()


func _on_setup(_spec: SwordSpec) -> void:
	pass


func _on_pose(_angle: float, _phase: int) -> void:
	pass
