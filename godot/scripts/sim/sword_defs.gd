class_name SwordDefs
extends RefCounted
## Immutable sword-type and rarity constants copied from game/main.py
## `SWORD_TYPES` (lines 79-113) and `RARITIES` (126-130). Only Fang exists in
## this slice; Warden, Pike and Colossus land with their own slices. The
## ultimate constants (`SWORD_TYPES[..]["ult"]`) sit beside each type's own and are read through the
## `ultimate_*` accessors, a small per-type dispatch rather than an ability framework.

const FANG: StringName = &"fang"

## Rarity: damage, cooldown, range and size multipliers (Common, Rare, Mythic).
const RARITY_DAMAGE: Array[float] = [1.0, 1.3, 1.75]
const RARITY_COOLDOWN: Array[float] = [1.0, 0.87, 0.74]
const RARITY_RANGE: Array[float] = [1.0, 1.06, 1.12]
const RARITY_SIZE: Array[float] = [1.0, 1.08, 1.18]
const RARITY_NAMES: Array[String] = ["Common", "Rare", "Mythic"]

## Fang: close / rapid (prototype `SWORD_TYPES["fang"]`).
const FANG_LENGTH: float = 34.0
const FANG_RANGE: float = 175.0
const FANG_COOLDOWN: float = 0.30
const FANG_DAMAGE: float = 7.0
const FANG_KNOCK: float = 170.0
const FANG_WINDUP: float = 0.06
const FANG_SPEED: float = 1700.0
const FANG_HITSTOP: float = 0.02
const FANG_SHAKE: float = 0.07
## Strike geometry that lives inline in the prototype's Fang strike branch.
const FANG_STRIKE_TIME: float = 0.3
const FANG_TIP_FRACTION: float = 0.65
const FANG_HIT_PAD: float = 6.0
const FANG_RECOVER_AFTER_HIT: float = 0.25
const FANG_RECOVER_AFTER_MISS: float = 0.2
## Extra reach of the strike's swept segment when parrying a projectile
## (`g.parry_projectiles(prev, tip, 8)`); the projectile's own radius adds to it.
const FANG_PARRY_PAD: float = 8.0


## Fang's ultimate, Viper Flurry (prototype `SWORD_TYPES["fang"]["ult"]`: cd 9.0, range
## 420, radius 150) and the numbers inline in `Sword.ultimate` / `Sword.update_ult`.
const FANG_ULT_NAME: String = "Viper Flurry"
const FANG_ULT_COOLDOWN: float = 9.0
const FANG_ULT_RANGE: float = 420.0
const FANG_ULT_RADIUS: float = 150.0
## The flurry lasts this long, darting every FANG_ULT_CADENCE seconds.
const FANG_ULT_DURATION: float = 1.25
const FANG_ULT_CADENCE: float = 0.08
const FANG_ULT_DAMAGE_FACTOR: float = 1.2
const FANG_ULT_KNOCK: float = 120.0
const FANG_ULT_SHAKE: float = 0.05
## Per-tick fraction of the way to the dart goal is `min(1, dt * rate)`.
const FANG_ULT_APPROACH_RATE: float = 28.0
## The goal sits this far past the victim's edge, away from the sword.
const FANG_ULT_STANDOFF: float = 20.0
## With nothing to strike the sword wanders to a point between these distances
## (the maximum is a fraction of the radius) from the centre.
const FANG_ULT_WANDER_MIN: float = 20.0
const FANG_ULT_WANDER_FRACTION: float = 0.7
const FANG_ULT_RECOVER_TIME: float = 0.3
const FANG_ULT_RECOVER_SPEED: float = 300.0
## Flash of an enemy hit by a heavy blow (a normal hit flashes 0.11).
const HEAVY_HIT_FLASH: float = 0.2
const NORMAL_HIT_FLASH: float = 0.11


## Name of a sword type's ultimate.
static func ultimate_name(type_id: StringName) -> String:
	return FANG_ULT_NAME if type_id == FANG else String(type_id)


## Base recharge of a sword type's ultimate in seconds (before the rarity factor).
static func ultimate_cooldown(type_id: StringName) -> float:
	return FANG_ULT_COOLDOWN if type_id == FANG else 0.0


## How far from the player a targeted ultimate may land; a farther aim point is
## pulled back onto this distance.
static func ultimate_range(type_id: StringName) -> float:
	return FANG_ULT_RANGE if type_id == FANG else 0.0


## Skill-shot ultimates (Pike's Skewer) fire toward the aim point instead of
## landing on it, so their aim point is not clamped. Fang's lands.
static func ultimate_is_shot(_type_id: StringName) -> bool:
	return false


static func is_supported(type_id: StringName) -> bool:
	return type_id == FANG


static func display_name(type_id: StringName) -> String:
	return "Fang" if type_id == FANG else String(type_id)
