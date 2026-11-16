class_name GroundMarks
extends Node2D
## Marks a Colossus's slam leaves in the floor, drawn under every actor: a handful of cracked lines that glow orange while fresh and
## then fade into the floor over seven seconds (the prototype's `decals`). Purely visual, with a random stream of its own.

const LIFETIME: float = 7.0
const MAX_DECALS: int = 24

var _decals: Array[Dictionary] = []


func clear() -> void:
	_decals.clear()
	queue_redraw()


## Five to eight cracks spreading from `point`, each a wandering line of three to five short segments.
func add_cracks(point: Vector2, rng: RandomNumberGenerator) -> void:
	var cracks: Array[PackedVector2Array] = []
	for crack: int in rng.randi_range(5, 8):
		var heading: float = rng.randf_range(0.0, TAU)
		var at: Vector2 = point
		var line: PackedVector2Array = PackedVector2Array([at])
		for segment: int in rng.randi_range(3, 5):
			heading += rng.randf_range(-0.6, 0.6)
			at += SimMath.polar(heading, rng.randf_range(14.0, 30.0))
			line.append(at)
		cracks.append(line)
	_decals.append({"cracks": cracks, "life": LIFETIME})
	if _decals.size() > MAX_DECALS:
		_decals.pop_front()
	queue_redraw()


func sync(run: GameRun) -> void:
	if run.paused or _decals.is_empty():
		return
	for decal: Dictionary in _decals:
		decal["life"] = float(decal["life"]) - GameRun.TICK_DT
	_decals = _decals.filter(func(decal: Dictionary) -> bool: return float(decal["life"]) > 0.0)
	queue_redraw()


func decal_count() -> int:
	return _decals.size()


func _draw() -> void:
	for decal: Dictionary in _decals:
		var life: float = float(decal["life"])
		var fresh: float = clampf(life / LIFETIME, 0.0, 1.0)
		for line: PackedVector2Array in decal["cracks"]:
			draw_polyline(line, Color(0.0, 0.0, 0.0, 0.85 * fresh), 3.0)
			if life > LIFETIME - 1.0:
				draw_polyline(line, Color(1.0, 0.63, 0.24, life - (LIFETIME - 1.0)), 2.0)
