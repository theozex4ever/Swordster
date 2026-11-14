class_name ConditionDefs
extends RefCounted
## Immutable elemental-condition constants and formulas copied from game/main.py
## (`ELEMENTS`, `BURN_TIME` .. `SHATTER` at lines 109-116, `Game.afflict`, `Game.update_conditions`,
## `Game.kill`, `Game.hit_enemy`). Per-enemy state lives in `EnemyConditions`; the run applies
## the effects (damage, spread, cues). Values are the prototype's and are not rebalanced:
## docs/reference/elemental-conditions.md records each one with its capture.

const FIRE: StringName = &"fire"
const ICE: StringName = &"ice"
const POISON: StringName = &"poison"

## How long each condition lasts after its latest application (seconds).
const BURN_TIME: float = 3.0
const POISON_TIME: float = 4.5
const CHILL_TIME: float = 2.5
const FREEZE_TIME: float = 1.6
## Poison stacks never exceed this; this many ice stacks freeze the enemy.
const POISON_MAX: int = 6
const FREEZE_STACKS: int = 4
## A chilled enemy moves at this fraction of its wanted speed.
const CHILL_SLOW: float = 0.5
## A frozen enemy takes this much more from every blow (applied after the critical
## multiplier and before rounding); the blow does not end the freeze.
const SHATTER: float = 1.3
## Freezing keeps this fraction of the enemy's velocity.
const FREEZE_VELOCITY_KEEP: float = 0.2

## Damage per second: fire `(1.5 + power * 0.2) * stacks` (one burn, never summed),
## poison `1 + power * 0.06` per stack. `power` is the source sword's base damage
## (its type damage times the rarity multiplier), not the damage of the blow.
const BURN_DPS_BASE: float = 1.5
const BURN_DPS_PER_POWER: float = 0.2
const POISON_DPS_BASE: float = 1.0
const POISON_DPS_PER_POWER: float = 0.06
## Damage over time lands in whole points, at most once every this many seconds;
## the fraction carries over to the next landing.
const DOT_PERIOD: float = 0.5

## A burning enemy that dies ignites every living enemy whose edge is within
## SPREAD_REACH of its own: burn dps at SPREAD_DPS_FACTOR of the dead one's, burn time
## at least BURN_TIME * SPREAD_TIME_FACTOR (never shortened, never stronger than what burns already).
const SPREAD_REACH: float = 70.0
const SPREAD_DPS_FACTOR: float = 0.6
const SPREAD_TIME_FACTOR: float = 0.7


static func burn_dps(power: float, stacks: int) -> float:
	return (BURN_DPS_BASE + power * BURN_DPS_PER_POWER) * float(stacks)


static func poison_dps(power: float) -> float:
	return POISON_DPS_BASE + power * POISON_DPS_PER_POWER


static func is_element(element: StringName) -> bool:
	return element == FIRE or element == ICE or element == POISON
