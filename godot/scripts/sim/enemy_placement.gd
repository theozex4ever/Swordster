class_name EnemyPlacement
extends RefCounted
## An enemy standing in the arena when a run starts: a controlled fixture for
## checks and for the crowd encounter (not a spawn rule). Every field beyond
## kind and position is optional; the defaults are a freshly spawned enemy.

var kind: StringName = EnemyDefs.HUSK
var position: Vector2 = Vector2.ZERO
var velocity: Vector2 = Vector2.ZERO
## Seconds of knockback stun it starts with (a launched enemy is stunned).
var stun: float = 0.0
## Starting value of the enemy's own clock (prototype `Enemy.t`): sets the
## runner's weave phase.
var phase: float = 0.0
var wave: int = 1
## Multiplies the type's chase speed (0 = stands still).
var speed_scale: float = 1.0
## Starting health; negative means the type's full (wave-scaled) health.
var hp: float = -1.0
## Spitter only: seconds until its first shot may start winding up; negative
## draws it from the run's gameplay stream like a spawned spitter. `charge` is
## how far into a shot it already is.
var shoot_cooldown: float = -1.0
var charge: float = 0.0


static func make(kind_value: StringName, at: Vector2) -> EnemyPlacement:
	var placement: EnemyPlacement = EnemyPlacement.new()
	placement.kind = kind_value
	placement.position = at
	return placement


## Builder-style setter for the common "launched" fixture.
func launched(velocity_value: Vector2, stun_value: float) -> EnemyPlacement:
	velocity = velocity_value
	stun = stun_value
	return self
