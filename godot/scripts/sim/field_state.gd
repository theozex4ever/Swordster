class_name FieldState
extends RefCounted
## One lingering elemental ground field (game/main.py `Field`), the ground Cataclysm leaves. A run
## owns every live field: it is created at the impact, loses `life` with gameplay time, and every
## `SwordDefs.COLOSSUS_FIELD_PERIOD` seconds applies one dose of its element to every living enemy
## standing in it, through the one condition entry point `GameRun.afflict`. Presentation reads it
## to draw the ground; it never feeds anything back (ADR 0003).

var position: Vector2 = Vector2.ZERO
var radius: float = 0.0
var element: StringName = &"fire"
## The source sword's base damage: the `power` its doses are applied with.
var power: float = 0.0
## Seconds of life left and the seconds it started with.
var life: float = 0.0
var max_life: float = 0.0
## Seconds until the next dose; zero at the start, so the first dose lands on the tick it is made.
var tick_left: float = 0.0


static func make(at: Vector2, radius_value: float, element_value: StringName, power_value: float, life_value: float) -> FieldState:
	var field: FieldState = FieldState.new()
	field.position = at
	field.radius = radius_value
	field.element = element_value
	field.power = power_value
	field.life = life_value
	field.max_life = life_value
	return field


## True when `enemy`'s centre is within the field's radius plus the enemy's own (prototype `update_fields`).
func reaches(enemy: EnemyState) -> bool:
	return (enemy.position - position).length() < radius + enemy.radius


## 0..1 fade of the ground as it runs out, as the prototype draws it: full until the last third of its
## life, then fading (`life / max x 3`, clamped).
func fade() -> float:
	return clampf(life / max_life * 3.0, 0.0, 1.0)
