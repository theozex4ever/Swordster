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


## Called every fixed tick with the sword's height above the ground, in px. Only a Colossus keeps one in
## the simulation (the prototype's `z`: it decides when its slam lands); it is read-only here, so a visual
## may draw its sword as high as it likes, or ignore it, without changing a single outcome.
func apply_altitude(height: float) -> void:
	_on_altitude(height)


## Called every fixed tick for an equipped sword with how strongly its slot has just been refreshed (1 right after a
## swap, easing to 0): a visual may brighten for it or ignore it. Cosmetic only.
func apply_flash(amount: float) -> void:
	_on_flash(amount)


## Called every fixed tick INSTEAD of `apply_altitude` for a sword that lies in the arena as a dropped pickup: the
## height, in px, it hovers above its shadow (bobbing). A pickup is posed point-down (`apply_pose` is given the angle).
func apply_hover(height: float) -> void:
	_on_hover(height)


## Called when the visual is first shown so interpolation does not smear.
func snap() -> void:
	reset_physics_interpolation()


func _on_setup(_spec: SwordSpec) -> void:
	pass


func _on_pose(_angle: float, _phase: int) -> void:
	pass


func _on_altitude(_height: float) -> void:
	pass


func _on_flash(_amount: float) -> void:
	pass


func _on_hover(_height: float) -> void:
	pass
