class_name SimCue
extends RefCounted
## One thing that happened during simulation, for presentation and audio only.
## Gameplay never reads cues back; they are drained with `GameRun.take_cues()`.

enum Kind {
	DASH,
	SWORD_STRIKE,
	ENEMY_HIT,
	ENEMY_KILLED,
	ENEMY_SPAWNED,
	PLAYER_HURT,
	PLAYER_DIED,
	MOTE_COLLECTED,
	WAVE_STARTED,
	WAVE_CLEARED,
	## A launched enemy knocked into another (`amount` = the 3 damage dealt).
	BOWLED,
	## An enemy hit the arena wall hard enough to take damage (`amount` = damage).
	WALL_SLAM,
	## The dev shove went off around the player.
	SHOVE,
	## A spitter fired an orb (`position` = the muzzle, `direction` = its heading).
	PROJECTILE_FIRED,
	## A sword parried an orb (`position` = where it was destroyed, `direction`
	## = back along its flight). Distinct from a hit: the player takes no damage
	## and PLAYER_HURT is not produced.
	PROJECTILE_PARRIED,
	## A sword slot's ultimate started (`position` = where the sword landed, `origin` =
	## where it was, `direction` = origin toward position, `amount` = the slot index).
	ULTIMATE_STARTED,
	## An ultimate command was refused because its sword slot is still recharging
	## (`position` = the player, `amount` = whole seconds left, `critical` unused).
	## Refusals for any other reason (paused, dead, already active) are silent.
	ULTIMATE_REFUSED,
}

var kind: Kind = Kind.DASH
var position: Vector2 = Vector2.ZERO
var direction: Vector2 = Vector2.ZERO
## Damage dealt/taken, where meaningful.
var amount: int = 0
var critical: bool = false
## Where a moving thing came from, when that matters (an ultimate's blink).
var origin: Vector2 = Vector2.ZERO


static func make(kind_value: Kind, at: Vector2, direction_value: Vector2 = Vector2.ZERO, amount_value: int = 0, critical_value: bool = false) -> SimCue:
	var cue: SimCue = SimCue.new()
	cue.kind = kind_value
	cue.position = at
	cue.direction = direction_value
	cue.amount = amount_value
	cue.critical = critical_value
	return cue
