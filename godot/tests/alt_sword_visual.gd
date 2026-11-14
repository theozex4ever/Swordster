class_name AltSwordVisual
extends SwordVisual
## Check-only stand-in for a texture-based sword: a different scale, pivot offset
## and rotation, and its own idea of facing. Gameplay must be indifferent to it.

var last_angle: float = 0.0
var last_phase: int = -1
var pose_calls: int = 0
var configured_with: SwordSpec = null


func _init() -> void:
	scale = Vector2(0.3, 4.0)
	rotation = 1.1


func _on_setup(spec: SwordSpec) -> void:
	configured_with = spec


func _on_pose(angle: float, phase: int) -> void:
	last_angle = angle
	last_phase = phase
	pose_calls += 1
