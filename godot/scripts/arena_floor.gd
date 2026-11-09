class_name ArenaFloor
extends Node2D
## Draws the bounded arena: floor, grid and border. Purely cosmetic.

const FLOOR_COLOR: Color = Color(0.055, 0.047, 0.078)
const GRID_COLOR: Color = Color(0.11, 0.10, 0.16)
const BORDER_COLOR: Color = Color(0.36, 0.30, 0.55)
const GRID_STEP: float = 100.0


func _draw() -> void:
	var world: Rect2 = GameRun.WORLD
	draw_rect(world, FLOOR_COLOR)
	var x: float = world.position.x
	while x <= world.end.x:
		draw_line(Vector2(x, world.position.y), Vector2(x, world.end.y), GRID_COLOR, 1.0)
		x += GRID_STEP
	var y: float = world.position.y
	while y <= world.end.y:
		draw_line(Vector2(world.position.x, y), Vector2(world.end.x, y), GRID_COLOR, 1.0)
		y += GRID_STEP
	draw_rect(world, BORDER_COLOR, false, 6.0)
