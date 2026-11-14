class_name EnemyDefs
extends RefCounted
## Immutable enemy-type constants copied from game/main.py `ENEMY_TYPES`
## (lines 125-130). Husk, runner and brute are ported; the spitter (and its
## projectile) arrives with issue #10, so `is_supported` rejects it. Per-instance
## state lives in `EnemyState`.

const HUSK: StringName = &"husk"
const RUNNER: StringName = &"runner"
const BRUTE: StringName = &"brute"

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

## Health grows by this fraction per wave after the first (`Enemy.__init__`).
const HP_PER_WAVE: float = 0.1

var kind: StringName = HUSK
var radius: float = HUSK_RADIUS
var hp: float = HUSK_HP
var speed: float = HUSK_SPEED
var damage: int = HUSK_DAMAGE
## Multiplies the knockback force a blow imparts (resistance below 1).
var knock: float = HUSK_KNOCK


static func is_supported(kind_value: StringName) -> bool:
	return kind_value == HUSK or kind_value == RUNNER or kind_value == BRUTE


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
		BRUTE:
			def.radius = BRUTE_RADIUS
			def.hp = BRUTE_HP
			def.speed = BRUTE_SPEED
			def.damage = BRUTE_DAMAGE
			def.knock = BRUTE_KNOCK
		_:
			assert(kind_value == HUSK, "enemy type not ported yet: %s" % kind_value)
	return def
