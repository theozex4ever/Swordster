class_name SwordDefs
extends RefCounted
## Immutable sword-type and rarity constants copied from game/main.py
## `SWORD_TYPES` (lines 79-113) and `RARITIES` (126-130). Fang and Warden exist so
## far; Pike and Colossus land with their own slices. The ultimate constants
## (`SWORD_TYPES[..]["ult"]`) sit beside each type's own and, like the type's base
## numbers, are read through per-type accessors (`base_*`, `ultimate_*`): a small
## `match` each, not an ability framework.
##
## The sword type identities are the prototype's own keys: Fang is `fang` and
## Warden is `blade` (`SWORD_TYPES["blade"]`, displayed "Warden"; its ultimate is
## "Maelstrom"), so a saved or logged type id never changes with the display name.

const FANG: StringName = &"fang"
const WARDEN: StringName = &"blade"

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
## Warden: mid / sweeping arc (prototype `SWORD_TYPES["blade"]`). The sweep's geometry
## lives inline in the prototype's blade branches of `Sword.update` / `strike`.
const WARDEN_LENGTH: float = 54.0
const WARDEN_RANGE: float = 245.0
const WARDEN_COOLDOWN: float = 0.85
const WARDEN_DAMAGE: float = 17.0
const WARDEN_KNOCK: float = 300.0
const WARDEN_WINDUP: float = 0.16
const WARDEN_HITSTOP: float = 0.05
const WARDEN_SHAKE: float = 0.16
## The sweep: the blade swings about a pivot this fraction of its length behind the
## aim point (toward the player), from `amid - side * START` to `amid + side * END`
## radians (`amid` is the player-to-aim heading, `side` alternates every attack),
## in WARDEN_SWEEP_TIME seconds eased out. The sword's own pose rides the arc at
## POSE_RADIUS x length from the pivot; the cutting segment runs from GUARD x to
## TIP x length from the pivot and is sampled halfway and at the end of every
## tick's step. A hit needs the enemy's centre within its radius + HIT_PAD of it.
const WARDEN_PIVOT_BACK: float = 0.55
const WARDEN_SWEEP_START: float = 1.9
const WARDEN_SWEEP_END: float = 1.45
const WARDEN_SWEEP_TIME: float = 0.15
const WARDEN_POSE_RADIUS: float = 0.5
const WARDEN_GUARD: float = 0.12
const WARDEN_TIP: float = 1.15
const WARDEN_HIT_PAD: float = 8.0
const WARDEN_PARRY_PAD: float = 6.0
## A hit's direction mixes the blade's tangent (this weight) with the push away from the player.
const WARDEN_TANGENT_WEIGHT: float = 0.6
const WARDEN_RECOVER_TIME: float = 0.3
const WARDEN_RECOVER_SPEED: float = 300.0
## Windup: the sword springs onto the start of the arc and turns toward it.
const WARDEN_WINDUP_SPRING_K: float = 220.0
const WARDEN_WINDUP_SPRING_C: float = 26.0
const WARDEN_WINDUP_TURN_RATE: float = 18.0

## Warden's ultimate, Maelstrom (prototype `SWORD_TYPES["blade"]["ult"]`: cd 11.0, range
## 400, radius 100) and the numbers inline in `Sword.ultimate` / `Sword.update_ult`.
const WARDEN_ULT_NAME: String = "Maelstrom"
const WARDEN_ULT_COOLDOWN: float = 11.0
const WARDEN_ULT_RANGE: float = 400.0
const WARDEN_ULT_RADIUS: float = 100.0
## The whirl lasts this long; its first beat comes after FIRST_BEAT, then every BEAT.
const WARDEN_ULT_DURATION: float = 2.2
const WARDEN_ULT_FIRST_BEAT: float = 0.15
const WARDEN_ULT_BEAT: float = 0.2
## The sword circles the centre at radius (RADIUS x size) turning SPIN_RATE rad/s, closing
## `min(1, dt * APPROACH_RATE)` of the way to its place each tick.
const WARDEN_ULT_SPIN_RATE: float = 15.0
const WARDEN_ULT_APPROACH_RATE: float = 25.0
## The blades reach RADIUS x size + REACH_TAIL x length from the centre.
const WARDEN_ULT_REACH_TAIL: float = 0.7
## Enemies farther than PULL_MIN and nearer than reach + PULL_EXTRA are dragged toward the
## centre at PULL_SPEED x their knock factor.
const WARDEN_ULT_PULL_MIN: float = 8.0
const WARDEN_ULT_PULL_EXTRA: float = 120.0
const WARDEN_ULT_PULL_SPEED: float = 170.0
## A beat strikes everything within reach + its radius for TICK_FACTOR x damage (one dose of the
## element, no hitstop) and shakes the screen if it struck anything.
const WARDEN_ULT_TICK_FACTOR: float = 0.6
const WARDEN_ULT_TICK_KNOCK: float = 40.0
const WARDEN_ULT_TICK_SHAKE: float = 0.08
## The finishing burst strikes within reach + BURST_MARGIN + radius for BURST_FACTOR x damage,
## two doses of the element.
const WARDEN_ULT_BURST_FACTOR: float = 1.6
const WARDEN_ULT_BURST_KNOCK: float = 520.0
const WARDEN_ULT_BURST_MARGIN: float = 30.0
const WARDEN_ULT_BURST_STACKS: int = 2
const WARDEN_ULT_BURST_SHAKE: float = 0.35
const WARDEN_ULT_BURST_HITSTOP: float = 0.06
const WARDEN_ULT_RECOVER_TIME: float = 0.3
const WARDEN_ULT_RECOVER_SPEED: float = 500.0

## Flash of an enemy hit by a heavy blow (a normal hit flashes 0.11).
const HEAVY_HIT_FLASH: float = 0.2
const NORMAL_HIT_FLASH: float = 0.11


## Base length, range, recharge-free cooldown, damage, knockback, windup, hitstop and shake
## of a sword type's automatic attack (before the rarity factors).
static func base_length(type_id: StringName) -> float:
	return WARDEN_LENGTH if type_id == WARDEN else FANG_LENGTH


static func base_range(type_id: StringName) -> float:
	return WARDEN_RANGE if type_id == WARDEN else FANG_RANGE


static func base_cooldown(type_id: StringName) -> float:
	return WARDEN_COOLDOWN if type_id == WARDEN else FANG_COOLDOWN


static func base_damage(type_id: StringName) -> float:
	return WARDEN_DAMAGE if type_id == WARDEN else FANG_DAMAGE


static func base_knock(type_id: StringName) -> float:
	return WARDEN_KNOCK if type_id == WARDEN else FANG_KNOCK


static func base_windup(type_id: StringName) -> float:
	return WARDEN_WINDUP if type_id == WARDEN else FANG_WINDUP


static func base_hitstop(type_id: StringName) -> float:
	return WARDEN_HITSTOP if type_id == WARDEN else FANG_HITSTOP


static func base_shake(type_id: StringName) -> float:
	return WARDEN_SHAKE if type_id == WARDEN else FANG_SHAKE


## Name of a sword type's ultimate.
static func ultimate_name(type_id: StringName) -> String:
	return WARDEN_ULT_NAME if type_id == WARDEN else FANG_ULT_NAME if type_id == FANG else String(type_id)


## Base recharge of a sword type's ultimate in seconds (before the rarity factor).
static func ultimate_cooldown(type_id: StringName) -> float:
	return WARDEN_ULT_COOLDOWN if type_id == WARDEN else FANG_ULT_COOLDOWN if type_id == FANG else 0.0


## How far from the player a targeted ultimate may land; a farther aim point is
## pulled back onto this distance.
static func ultimate_range(type_id: StringName) -> float:
	return WARDEN_ULT_RANGE if type_id == WARDEN else FANG_ULT_RANGE if type_id == FANG else 0.0


## Skill-shot ultimates (Pike's Skewer) fire toward the aim point instead of
## landing on it, so their aim point is not clamped. Fang's and Warden's land.
static func ultimate_is_shot(_type_id: StringName) -> bool:
	return false


static func is_supported(type_id: StringName) -> bool:
	return type_id == FANG or type_id == WARDEN


static func display_name(type_id: StringName) -> String:
	return "Warden" if type_id == WARDEN else "Fang" if type_id == FANG else String(type_id)
