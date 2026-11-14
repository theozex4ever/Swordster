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
}

var kind: Kind = Kind.DASH
var position: Vector2 = Vector2.ZERO
var direction: Vector2 = Vector2.ZERO
## Damage dealt/taken, where meaningful.
var amount: int = 0
var critical: bool = false


static func make(kind_value: Kind, at: Vector2, direction_value: Vector2 = Vector2.ZERO, amount_value: int = 0, critical_value: bool = false) -> SimCue:
	var cue: SimCue = SimCue.new()
	cue.kind = kind_value
	cue.position = at
	cue.direction = direction_value
	cue.amount = amount_value
	cue.critical = critical_value
	return cue
