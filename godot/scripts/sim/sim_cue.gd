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
	## An enemy froze solid (`position` = where, `element` = ice).
	ENEMY_FROZEN,
	## An enemy died while frozen (`position` = where); alongside ENEMY_KILLED.
	ENEMY_SHATTERED,
	## Burn or poison damage over time landed (`amount` = whole points, `element` =
	## the condition shown, `position` = the enemy).
	CONDITION_DAMAGE,
	## A burning enemy died and set its neighbours alight (`position` = where it died);
	## alongside ENEMY_KILLED.
	FIRE_SPREAD,
	## One beat of a Maelstrom (`position` = its centre, `radius` = the blades' reach, `amount` =
	## how many enemies were inside the reach, a corpse included as in the prototype, `element` = the sword's element).
	MAELSTROM_BEAT,
	## A Maelstrom's finishing burst (`position` = its centre, `radius` = the reach it struck
	## within, `amount` = how many enemies were inside it, corpses included, `element` = the sword's element).
	MAELSTROM_BURST,
	## A Skewer left the aim and launched (`position` = where the sword flew from, `direction` = its heading).
	SKEWER_LAUNCHED,
	## A Skewer ended and let go of what it carried (`position` = its tip, `direction` = its heading,
	## `amount` = how many enemies it flung, `critical` = it ended at a wall rather than at its range).
	SKEWER_RELEASED,
	## A Colossus slam landed (`position` = the impact, `radius` = the area struck within, `amount` = how
	## many enemies were inside it, a corpse included as in the prototype, `element` = the sword's element,
	## `critical` = it was a Cataclysm rather than an automatic slam).
	COLOSSUS_SLAM,
	## Cataclysm left an elemental field (`position` = its centre, `radius` = its radius, `element` = its element).
	FIELD_CREATED,
	## A field dosed the enemies standing in it (`position` = its centre, `radius` = its radius, `amount` = how
	## many living enemies it dosed, `element` = its element).
	FIELD_PULSED,
	## A Converge went out (`position` = the point it was aimed at, after the range clamp, `amount` = how
	## many swords took the command; a sword that was striking, buried or in its ultimate did not).
	CONVERGE,
	## An armed enemy died and its sword now lies where it fell (`position` = where, `spec` = the sword).
	SWORD_DROPPED,
	## A pickup was swapped into a sword slot (`position` = where the pickup lay, `amount` = the slot index, `spec` =
	## the sword now equipped, `origin` = where the replaced sword came back down as a drop).
	SWORD_SWAPPED,
	## A swap was refused because no pickup is within reach (`position` = the player). Refusals for any other reason
	## (paused, dead) are silent.
	SWAP_REFUSED,
	## The kill chain reached 10, 25, 50 or 100 (`position` = the player, `amount` = the chain).
	CHAIN_MILESTONE,
}

var kind: Kind = Kind.DASH
var position: Vector2 = Vector2.ZERO
var direction: Vector2 = Vector2.ZERO
## Damage dealt/taken, where meaningful.
var amount: int = 0
var critical: bool = false
## Where a moving thing came from, when that matters (an ultimate's blink).
var origin: Vector2 = Vector2.ZERO
## The element a condition cue speaks of; `ice` on an ENEMY_HIT that struck a frozen
## enemy for the shatter bonus. Empty when no element is involved.
var element: StringName = &""
## The reach of an area effect (a Maelstrom beat or burst), in pixels.
var radius: float = 0.0
## The spirit sword a drop or swap cue speaks of; on an ENEMY_HIT, SWORD_STRIKE or ULTIMATE_STARTED the sword that
## struck, started its attack or began its ultimate (the sound and the sparks take their character from it).
var spec: SwordSpec = null
## An ENEMY_HIT that was a heavy blow (a Fang dart, a Maelstrom beat or burst, a Skewer, a slam): no hit sound of its own.
var heavy: bool = false
## The kind of enemy an ENEMY_KILLED cue speaks of (its colour tints the burst) and the size of its body in `radius`.
var enemy_kind: StringName = &""


static func make(kind_value: Kind, at: Vector2, direction_value: Vector2 = Vector2.ZERO, amount_value: int = 0, critical_value: bool = false) -> SimCue:
	var cue: SimCue = SimCue.new()
	cue.kind = kind_value
	cue.position = at
	cue.direction = direction_value
	cue.amount = amount_value
	cue.critical = critical_value
	return cue
