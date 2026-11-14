class_name EnemyDefs
extends RefCounted
## Immutable enemy-type constants copied from game/main.py `ENEMY_TYPES`
## (lines 125-130): husk, runner, spitter and brute. The spitter's own AI
## numbers (the distance bands, charge and shot) live inline in the prototype's
## `Enemy.update` (lines 533-545) and are named here. Per-instance state lives in
## `EnemyState`.

const HUSK: StringName = &"husk"
const RUNNER: StringName = &"runner"
const BRUTE: StringName = &"brute"
const SPITTER: StringName = &"spitter"

const HUSK_RADIUS: float = 16.0
const HUSK_HP: float = 30.0
const HUSK_SPEED: float = 92.0
const HUSK_DAMAGE: int = 10
const HUSK_KNOCK: float = 1.0

## Fast and fragile: small, weaves across its line of approach, flung far by blows.
const RUNNER_RADIUS: float = 11.0
const RUNNER_HP: float = 14.0
const RUNNER_SPEED: float = 178.0
const RUNNER_DAMAGE: int = 6
const RUNNER_KNOCK: float = 1.3

## Slow and heavy: large, health-rich, hits hard and barely budges (knockback x0.35).
const BRUTE_RADIUS: float = 30.0
const BRUTE_HP: float = 170.0
const BRUTE_SPEED: float = 52.0
const BRUTE_DAMAGE: int = 20
const BRUTE_KNOCK: float = 0.35
## A brute stays frozen for only this fraction of the usual freeze time (`afflict`).
const BRUTE_FREEZE_FACTOR: float = 0.6

## Ranged: keeps its distance, glows for half a second and spits a slow orb.
const SPITTER_RADIUS: float = 15.0
const SPITTER_HP: float = 24.0
const SPITTER_SPEED: float = 85.0
const SPITTER_DAMAGE: int = 8
const SPITTER_KNOCK: float = 1.1
## Distance bands from the player: closer than RETREAT it backs away, closer
## than ORBIT it circles at ORBIT_SPEED x its speed, farther it approaches.
const SPITTER_RETREAT_RANGE: float = 260.0
const SPITTER_ORBIT_RANGE: float = 380.0
const SPITTER_ORBIT_SPEED: float = 0.6
## It only winds up a shot closer than this, once its cooldown is spent; while
## it charges its wanted movement is multiplied by CHARGE_SLOW.
const SPITTER_FIRE_RANGE: float = 620.0
const SPITTER_CHARGE_SLOW: float = 0.15
const SPITTER_CHARGE_TIME: float = 0.5
## Seconds between a shot and the next cooldown running out (uniform draw), and
## the cooldown a freshly spawned spitter starts with.
const SPITTER_COOLDOWN_MIN: float = 2.0
const SPITTER_COOLDOWN_MAX: float = 2.9
const SPITTER_FIRST_COOLDOWN_MIN: float = 1.5
const SPITTER_FIRST_COOLDOWN_MAX: float = 3.0
## Orb speed in px/s (the orb itself is `ProjectileState`).
const SPITTER_SHOT_SPEED: float = 270.0

## Health grows by this fraction per wave after the first (`Enemy.__init__`).
const HP_PER_WAVE: float = 0.1

var kind: StringName = HUSK
var radius: float = HUSK_RADIUS
var hp: float = HUSK_HP
var speed: float = HUSK_SPEED
var damage: int = HUSK_DAMAGE
## Multiplies the knockback force a blow imparts (resistance below 1).
var knock: float = HUSK_KNOCK
## Multiplies how long a freeze lasts on this type (brutes resist).
var freeze_factor: float = 1.0


static func is_supported(kind_value: StringName) -> bool:
	return kind_value == HUSK or kind_value == RUNNER or kind_value == BRUTE or kind_value == SPITTER


static func of(kind_value: StringName) -> EnemyDefs:
	var def: EnemyDefs = EnemyDefs.new()
	def.kind = kind_value
	match kind_value:
		RUNNER:
			def.radius = RUNNER_RADIUS
			def.hp = RUNNER_HP
			def.speed = RUNNER_SPEED
			def.damage = RUNNER_DAMAGE
			def.knock = RUNNER_KNOCK
		SPITTER:
			def.radius = SPITTER_RADIUS
			def.hp = SPITTER_HP
			def.speed = SPITTER_SPEED
			def.damage = SPITTER_DAMAGE
			def.knock = SPITTER_KNOCK
		BRUTE:
			def.radius = BRUTE_RADIUS
			def.hp = BRUTE_HP
			def.speed = BRUTE_SPEED
			def.damage = BRUTE_DAMAGE
			def.knock = BRUTE_KNOCK
			def.freeze_factor = BRUTE_FREEZE_FACTOR
		_:
			assert(kind_value == HUSK, "enemy type not ported yet: %s" % kind_value)
	return def
