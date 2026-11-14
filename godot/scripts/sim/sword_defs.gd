class_name SwordDefs
extends RefCounted
## Immutable sword-type and rarity constants copied from game/main.py
## `SWORD_TYPES` (lines 79-113) and `RARITIES` (126-130). Only Fang exists in
## this slice; Warden, Pike and Colossus land with their own slices.

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


static func is_supported(type_id: StringName) -> bool:
	return type_id == FANG


static func display_name(type_id: StringName) -> String:
	return "Fang" if type_id == FANG else String(type_id)
