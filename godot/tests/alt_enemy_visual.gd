class_name AltEnemyVisual
extends EnemyVisual
## Check-only stand-in for a texture-based enemy: much larger than the husk's
## collision radius. Reach and collision must not follow it.

var last_hp_fraction: float = -1.0
var last_stunned: bool = false
var last_telegraph: float = 0.0
var pose_calls: int = 0
var last_conditions: ConditionView = null


func _init() -> void:
	scale = Vector2(5.0, 0.2)
	rotation = -0.6


func _on_pose(_facing: Vector2, _flash: float, _squash: float, hp_fraction: float, stunned: bool, telegraph: float) -> void:
	last_hp_fraction = hp_fraction
	last_stunned = stunned
	last_telegraph = telegraph
	pose_calls += 1


func _on_conditions(view: ConditionView) -> void:
	last_conditions = view
