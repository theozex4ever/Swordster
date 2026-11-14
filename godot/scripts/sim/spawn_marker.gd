class_name SpawnMarker
extends RefCounted
## Telegraph for an enemy that is about to appear (game/main.py `Marker`).

const TELEGRAPH: float = 0.7

var kind: StringName = EnemyDefs.HUSK
var position: Vector2 = Vector2.ZERO
var remaining: float = TELEGRAPH


static func make(kind_value: StringName, at: Vector2) -> SpawnMarker:
	var marker: SpawnMarker = SpawnMarker.new()
	marker.kind = kind_value
	marker.position = at
	return marker
