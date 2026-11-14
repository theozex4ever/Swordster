class_name ProjectileState
extends RefCounted
## One enemy projectile in flight (game/main.py `Projectile`). A run owns every
## live projectile; it flies in a straight line, expires after `LIFETIME` or on
## leaving the arena, and resolves exactly once: it hurts the player, is parried
## by a sword, or ends on its own. The same state serves every sword type's
## parry (`GameRun.parry_projectiles`), so there is one projectile simulation.

## Collision radius, lifetime in seconds and damage to the player (the prototype
## hurts for a flat 8, whatever shot it).
const RADIUS: float = 7.0
const LIFETIME: float = 4.0
const DAMAGE: int = 8

## How a projectile ended. FLYING until it resolves.
enum Fate { FLYING, HIT_PLAYER, PARRIED, EXPIRED, LEFT_ARENA, CLEARED }

var position: Vector2 = Vector2.ZERO
var velocity: Vector2 = Vector2.ZERO
var radius: float = RADIUS
## Seconds of flight left.
var life: float = LIFETIME
var fate: Fate = Fate.FLYING


static func make(at: Vector2, velocity_value: Vector2) -> ProjectileState:
	var projectile: ProjectileState = ProjectileState.new()
	projectile.position = at
	projectile.velocity = velocity_value
	return projectile


## True once it has hit, been parried or ended; a resolved projectile neither
## moves nor hurts nor can be parried again.
func is_resolved() -> bool:
	return fate != Fate.FLYING


## Ends the projectile with `how`. The first resolution wins; later calls return
## false and change nothing, so a hit and a parry can never both happen.
func resolve(how: Fate) -> bool:
	if fate != Fate.FLYING:
		return false
	fate = how
	return true
