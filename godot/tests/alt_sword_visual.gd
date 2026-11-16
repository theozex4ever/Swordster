class_name AltSwordVisual
extends SwordVisual
## Check-only stand-in for a texture-based sword: a different scale, pivot offset
## and rotation, and its own idea of facing. Gameplay must be indifferent to it.

var last_angle: float = 0.0
var last_phase: int = -1
var pose_calls: int = 0
## The height the simulation last reported (a Colossus's altitude); this visual only records it.
var last_altitude: float = 0.0
var configured_with: SwordSpec = null
## The hover height a dropped sword was last given (0 for an equipped one).
var last_hover: float = 0.0


func _init() -> void:
	scale = Vector2(0.3, 4.0)
	rotation = 1.1


func _on_setup(spec: SwordSpec) -> void:
	configured_with = spec


func _on_pose(angle: float, phase: int) -> void:
	last_angle = angle
	last_phase = phase
	pose_calls += 1


func _on_altitude(height: float) -> void:
	last_altitude = height


func _on_hover(height: float) -> void:
	last_hover = height
