class_name Mote
extends RefCounted
## Healing mote dropped by a dead enemy (game/main.py `Mote`): it scatters,
## then homes in on the player and heals 0.5 health when it arrives.

const HEAL: float = 0.5
const COLLECT_RADIUS: float = 18.0
const HOMING_DELAY: float = 0.25

var position: Vector2 = Vector2.ZERO
var velocity: Vector2 = Vector2.ZERO
var age: float = 0.0
var collected: bool = false


static func scatter(at: Vector2, rng: RandomNumberGenerator) -> Mote:
	var mote: Mote = Mote.new()
	mote.position = at
	mote.velocity = SimMath.polar(rng.randf_range(0.0, TAU), rng.randf_range(120.0, 260.0))
	return mote
