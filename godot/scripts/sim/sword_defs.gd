class_name SwordDefs
extends RefCounted
## Immutable sword-type and rarity constants copied from game/main.py
## `SWORD_TYPES` (lines 79-113) and `RARITIES` (126-130). All four sword types exist: Fang,
## Warden, Pike and Colossus. The ultimate constants
## (`SWORD_TYPES[..]["ult"]`) sit beside each type's own and, like the type's base
## numbers, are read through per-type accessors (`base_*`, `ultimate_*`): a small
## `match` each, not an ability framework.
##
## The sword type identities are the prototype's own keys: Fang is `fang` and
## Warden is `blade` (`SWORD_TYPES["blade"]`, displayed "Warden"; its ultimate is
## "Maelstrom"), so a saved or logged type id never changes with the display name. Pike is
## `SWORD_TYPES["lance"]` (displayed "Pike"; its ultimate is "Skewer"), so its id is `lance`.

const FANG: StringName = &"fang"
const WARDEN: StringName = &"blade"
const PIKE: StringName = &"lance"
## Colossus is `SWORD_TYPES["colossus"]`, so its id is the prototype's own key (displayed "Colossus";
## its ultimate is "Cataclysm").
const COLOSSUS: StringName = &"colossus"

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

## Pike: long / piercing thrust (prototype `SWORD_TYPES["lance"]`). The thrust's geometry lives
## inline in the prototype's lance branches of `Sword.acquire` / `update` / `strike`.
const PIKE_LENGTH: float = 74.0
const PIKE_RANGE: float = 430.0
const PIKE_COOLDOWN: float = 1.35
const PIKE_DAMAGE: float = 24.0
const PIKE_KNOCK: float = 380.0
const PIKE_WINDUP: float = 0.32
const PIKE_SPEED: float = 2400.0
const PIKE_HITSTOP: float = 0.06
const PIKE_SHAKE: float = 0.2
## Targeting: of the enemies in range, only those farther than this from the player are
## considered while any exist (the Pike prefers a long thrust), then the nearest of them.
const PIKE_FAR_MIN: float = 130.0
## Windup: the sword springs to `aim - d * (STANDOFF_LENGTH x length + STANDOFF_EXTRA)` (d = the
## player-to-aim heading) with SPRING_K / SPRING_C and turns toward d at TURN_RATE.
const PIKE_WINDUP_STANDOFF_LENGTH: float = 0.5
const PIKE_WINDUP_STANDOFF_EXTRA: float = 120.0
const PIKE_WINDUP_SPRING_K: float = 150.0
const PIKE_WINDUP_SPRING_C: float = 20.0
const PIKE_WINDUP_TURN_RATE: float = 16.0
## The thrust flies along a fixed line at PIKE_SPEED for (distance to the aim point + OVERSHOOT) / speed.
## Every tick the swept segment runs from TAIL x length behind where the sword was to TIP x length
## ahead of where it is; an enemy within its radius + HIT_PAD of it is struck once per attack.
const PIKE_STRIKE_OVERSHOOT: float = 170.0
const PIKE_TAIL_FRACTION: float = 0.3
const PIKE_TIP_FRACTION: float = 0.65
const PIKE_HIT_PAD: float = 7.0
const PIKE_PARRY_PAD: float = 8.0
const PIKE_RECOVER_TIME: float = 0.35
const PIKE_RECOVER_SPEED: float = 420.0

## Pike's ultimate, Skewer (prototype `SWORD_TYPES["lance"]["ult"]`: cd 10.0, range 950, shot, speed
## 2600) and the numbers inline in `Sword.ultimate` / `Sword.update_ult`. A skill shot: the aim
## point only gives the heading, the sword flies SKEWER_RANGE px along it.
const PIKE_ULT_NAME: String = "Skewer"
const PIKE_ULT_COOLDOWN: float = 10.0
const PIKE_ULT_RANGE: float = 950.0
const PIKE_ULT_SPEED: float = 2600.0
## The aim phase: the sword springs to `player - d x STANDOFF` (SPRING_K / SPRING_C) and faces d
## for AIM_TIME, then launches from LAUNCH_AHEAD px in front of the player with a shake kick.
const PIKE_ULT_AIM_TIME: float = 0.38
const PIKE_ULT_AIM_STANDOFF: float = 40.0
const PIKE_ULT_AIM_SPRING_K: float = 200.0
const PIKE_ULT_AIM_SPRING_C: float = 24.0
const PIKE_ULT_LAUNCH_AHEAD: float = 10.0
const PIKE_ULT_LAUNCH_SHAKE: float = 0.2
## The flight: each tick the swept segment runs from TAIL x length behind to TIP x length ahead; an
## enemy within its radius + HIT_PAD of it (once per Skewer) takes DAMAGE_FACTOR x damage, heavy,
## no knockback of its own and STACKS doses of the element, shakes the screen, and if it survives
## is carried (moved by the sword's whole step, velocity zeroed, stunned for at least CARRY_STUN).
## Every orb within PARRY_PAD of the segment is parried.
const PIKE_ULT_TAIL_FRACTION: float = 0.3
const PIKE_ULT_TIP_FRACTION: float = 0.65
const PIKE_ULT_HIT_PAD: float = 18.0
const PIKE_ULT_DAMAGE_FACTOR: float = 2.2
const PIKE_ULT_STACKS: int = 2
const PIKE_ULT_HIT_SHAKE: float = 0.12
const PIKE_ULT_CARRY_STUN: float = 0.5
const PIKE_ULT_PARRY_PAD: float = 14.0
## The flight ends when the range is spent or the tip leaves the arena shrunk by WALL_MARGIN on
## every side (the prototype's `WORLD.inflate(-20, -20)` removes 20 px from the width and from the
## height, so 10 px from each side). Whatever is still impaled is flung along the heading at RELEASE_SPEED (at the
## wall, where it slams) or RELEASE_SPEED_RANGE (at the range limit), stunned for at least
## RELEASE_STUN; the sword recovers for RECOVER_TIME, kicked back from a wall.
const PIKE_ULT_WALL_MARGIN: float = 10.0
const PIKE_ULT_RELEASE_SPEED_RANGE: float = 750.0
const PIKE_ULT_RELEASE_SPEED_WALL: float = 1100.0
const PIKE_ULT_RELEASE_STUN: float = 0.6
const PIKE_ULT_RECOVER_TIME: float = 0.35
const PIKE_ULT_RECOVER_SPEED_RANGE: float = 420.0
const PIKE_ULT_RECOVER_SPEED_WALL: float = 300.0

## Colossus: far / slow / crushing slam (prototype `SWORD_TYPES["colossus"]`). The slam's timing and
## geometry live inline in the prototype's colossus branches of `Sword.acquire` / `update` / `strike`
## and in `Game.slam`.
const COLOSSUS_LENGTH: float = 88.0
const COLOSSUS_WIDTH: float = 15.0
const COLOSSUS_RANGE: float = 330.0
const COLOSSUS_COOLDOWN: float = 2.1
const COLOSSUS_DAMAGE: float = 50.0
const COLOSSUS_KNOCK: float = 650.0
const COLOSSUS_WINDUP: float = 0.55
const COLOSSUS_HITSTOP: float = 0.13
const COLOSSUS_SHAKE: float = 0.6
## The slam's radius (before the rarity's size factor) and, in the same type table, the radius
## within which `acquire` counts neighbours when it picks the target with the biggest cluster. That count
## uses the radius WITHOUT the rarity's size factor, the slam itself uses it (prototype quirk, mirrored).
const COLOSSUS_AOE: float = 118.0
## Altitude and fall. The prototype keeps a height `z` and a fall speed `vz` for every sword and, for
## Colossus alone, they decide WHEN the slam lands (`z <= 0`), so they are gameplay state here
## (`SwordState.altitude`, `fall_speed`); the visual only draws them (ADR 0003).
## At rest (idle or recovering) the altitude eases toward `REST_BASE + REST_LENGTH x length + sin(time x REST_BOB_RATE
## + slot x REST_BOB_SLOT) x REST_BOB` at REST_RATE per second; a new sword hangs at START_ALTITUDE.
const COLOSSUS_START_ALTITUDE: float = 30.0
const COLOSSUS_REST_BASE: float = 34.0
const COLOSSUS_REST_LENGTH: float = 0.15
const COLOSSUS_REST_BOB_RATE: float = 2.2
const COLOSSUS_REST_BOB_SLOT: float = 2.1
const COLOSSUS_REST_BOB: float = 7.0
const COLOSSUS_REST_RATE: float = 5.0
## The dead player's swords sink at this many px/s.
const COLOSSUS_SINK_RATE: float = 120.0
## Windup: the sword springs onto the aim point (SPRING_K / SPRING_C), rises toward WINDUP_ALTITUDE at
## WINDUP_RATE per second and turns upright (PI/2 plus a tremble) at TURN_RATE.
const COLOSSUS_WINDUP_SPRING_K: float = 120.0
const COLOSSUS_WINDUP_SPRING_C: float = 18.0
const COLOSSUS_WINDUP_ALTITUDE: float = 200.0
const COLOSSUS_WINDUP_RATE: float = 7.0
const COLOSSUS_WINDUP_TREMBLE_RATE: float = 30.0
const COLOSSUS_WINDUP_TREMBLE: float = 0.03
const COLOSSUS_WINDUP_TURN_RATE: float = 10.0
## The fall: the impact point is fixed when the strike starts; the sword closes `min(1, dt x GLIDE_RATE)`
## of the way to it each tick while it drops with a fall speed that starts at STRIKE_FALL_SPEED and
## grows by STRIKE_GRAVITY per second; the slam lands on the first tick the altitude reaches 0.
const COLOSSUS_GLIDE_RATE: float = 30.0
const COLOSSUS_STRIKE_FALL_SPEED: float = 300.0
const COLOSSUS_STRIKE_GRAVITY: float = 9000.0
## The slam (`Game.slam`): every enemy within `aoe + radius` of the point is struck (the dead included:
## `hit_enemy` ignores them but they still count as "hit anything") for `damage x boost x power x fall`,
## where `fall` = 1 - FALLOFF x clamp(distance / aoe, 0, 1), with `knock x fall` and a heavy blow; every orb within
## `aoe` of the point is cleared. Hitstop and shake are the sword type's if anything was in the area, else
## EMPTY_HITSTOP / EMPTY_SHAKE, with a kick straight down.
const COLOSSUS_SLAM_FALLOFF: float = 0.45
const COLOSSUS_SLAM_EMPTY_HITSTOP: float = 0.04
const COLOSSUS_SLAM_EMPTY_SHAKE: float = 0.35
## Stuck in the floor, then recovery.
const COLOSSUS_STUCK_TIME: float = 0.32
const COLOSSUS_STUCK_TREMBLE_RATE: float = 60.0
const COLOSSUS_STUCK_TREMBLE: float = 0.08
const COLOSSUS_RECOVER_TIME: float = 0.4
const COLOSSUS_RECOVER_VELOCITY: Vector2 = Vector2(0.0, -60.0)

## Colossus's ultimate, Cataclysm (prototype `SWORD_TYPES["colossus"]["ult"]`: cd 14.0, range 480, aoe 1.8,
## targeted) and the numbers inline in `Sword.ultimate` / `Sword.update_ult`. Its area is the type's
## radius x AOE_FACTOR x the rarity's size factor.
const COLOSSUS_ULT_NAME: String = "Cataclysm"
const COLOSSUS_ULT_COOLDOWN: float = 14.0
const COLOSSUS_ULT_RANGE: float = 480.0
const COLOSSUS_ULT_AOE_FACTOR: float = 1.8
## RISE_TIME seconds of rising (spring onto the point, altitude toward RISE_ALTITUDE at RISE_RATE, trembling),
## then it falls from FALL_SPEED with FALL_GRAVITY and lands at the first tick the altitude reaches 0:
## a slam of DAMAGE_FACTOR x damage, STACKS doses of the element, a field and an extra shake.
const COLOSSUS_ULT_RISE_TIME: float = 0.75
const COLOSSUS_ULT_RISE_ALTITUDE: float = 420.0
const COLOSSUS_ULT_RISE_RATE: float = 5.0
const COLOSSUS_ULT_TREMBLE_RATE: float = 40.0
const COLOSSUS_ULT_TREMBLE: float = 0.04
const COLOSSUS_ULT_FALL_SPEED: float = 600.0
const COLOSSUS_ULT_FALL_GRAVITY: float = 12000.0
const COLOSSUS_ULT_DAMAGE_FACTOR: float = 2.2
const COLOSSUS_ULT_STACKS: int = 3
const COLOSSUS_ULT_SHAKE: float = 0.4
const COLOSSUS_ULT_STUCK_TIME: float = 0.6
## The elemental field Cataclysm leaves (`Field`): radius FIELD_RADIUS_FACTOR x the area, FIELD_LIFE seconds,
## the sword's element at the sword's damage as its power, applied every FIELD_PERIOD seconds.
const COLOSSUS_FIELD_RADIUS_FACTOR: float = 1.1
const COLOSSUS_FIELD_LIFE: float = 5.0
const COLOSSUS_FIELD_PERIOD: float = 0.5

## Flash of an enemy hit by a heavy blow (a normal hit flashes 0.11).
const HEAVY_HIT_FLASH: float = 0.2
const NORMAL_HIT_FLASH: float = 0.11


## Base length, range, recharge-free cooldown, damage, knockback, windup, hitstop and shake
## of a sword type's automatic attack (before the rarity factors).
static func base_length(type_id: StringName) -> float:
	match type_id:
		WARDEN:
			return WARDEN_LENGTH
		PIKE:
			return PIKE_LENGTH
		COLOSSUS:
			return COLOSSUS_LENGTH
		_:
			return FANG_LENGTH


static func base_range(type_id: StringName) -> float:
	match type_id:
		WARDEN:
			return WARDEN_RANGE
		PIKE:
			return PIKE_RANGE
		COLOSSUS:
			return COLOSSUS_RANGE
		_:
			return FANG_RANGE


static func base_cooldown(type_id: StringName) -> float:
	match type_id:
		WARDEN:
			return WARDEN_COOLDOWN
		PIKE:
			return PIKE_COOLDOWN
		COLOSSUS:
			return COLOSSUS_COOLDOWN
		_:
			return FANG_COOLDOWN


static func base_damage(type_id: StringName) -> float:
	match type_id:
		WARDEN:
			return WARDEN_DAMAGE
		PIKE:
			return PIKE_DAMAGE
		COLOSSUS:
			return COLOSSUS_DAMAGE
		_:
			return FANG_DAMAGE


static func base_knock(type_id: StringName) -> float:
	match type_id:
		WARDEN:
			return WARDEN_KNOCK
		PIKE:
			return PIKE_KNOCK
		COLOSSUS:
			return COLOSSUS_KNOCK
		_:
			return FANG_KNOCK


static func base_windup(type_id: StringName) -> float:
	match type_id:
		WARDEN:
			return WARDEN_WINDUP
		PIKE:
			return PIKE_WINDUP
		COLOSSUS:
			return COLOSSUS_WINDUP
		_:
			return FANG_WINDUP


static func base_hitstop(type_id: StringName) -> float:
	match type_id:
		WARDEN:
			return WARDEN_HITSTOP
		PIKE:
			return PIKE_HITSTOP
		COLOSSUS:
			return COLOSSUS_HITSTOP
		_:
			return FANG_HITSTOP


static func base_shake(type_id: StringName) -> float:
	match type_id:
		WARDEN:
			return WARDEN_SHAKE
		PIKE:
			return PIKE_SHAKE
		COLOSSUS:
			return COLOSSUS_SHAKE
		_:
			return FANG_SHAKE


## Name of a sword type's ultimate.
static func ultimate_name(type_id: StringName) -> String:
	match type_id:
		WARDEN:
			return WARDEN_ULT_NAME
		PIKE:
			return PIKE_ULT_NAME
		FANG:
			return FANG_ULT_NAME
		COLOSSUS:
			return COLOSSUS_ULT_NAME
		_:
			return String(type_id)


## Base recharge of a sword type's ultimate in seconds (before the rarity factor).
static func ultimate_cooldown(type_id: StringName) -> float:
	match type_id:
		WARDEN:
			return WARDEN_ULT_COOLDOWN
		PIKE:
			return PIKE_ULT_COOLDOWN
		FANG:
			return FANG_ULT_COOLDOWN
		COLOSSUS:
			return COLOSSUS_ULT_COOLDOWN
		_:
			return 0.0


## How far from the player a targeted ultimate may land; a farther aim point is
## pulled back onto this distance. For a skill shot (Skewer) it is the distance the
## shot flies instead.
static func ultimate_range(type_id: StringName) -> float:
	match type_id:
		WARDEN:
			return WARDEN_ULT_RANGE
		PIKE:
			return PIKE_ULT_RANGE
		FANG:
			return FANG_ULT_RANGE
		COLOSSUS:
			return COLOSSUS_ULT_RANGE
		_:
			return 0.0


## Skill-shot ultimates (Pike's Skewer) fire toward the aim point instead of
## landing on it, so their aim point is not clamped. Fang's, Warden's and Colossus's land.
static func ultimate_is_shot(type_id: StringName) -> bool:
	return type_id == PIKE


static func is_supported(type_id: StringName) -> bool:
	return type_id == FANG or type_id == WARDEN or type_id == PIKE or type_id == COLOSSUS


static func display_name(type_id: StringName) -> String:
	match type_id:
		WARDEN:
			return "Warden"
		PIKE:
			return "Pike"
		COLOSSUS:
			return "Colossus"
		FANG:
			return "Fang"
		_:
			return String(type_id)
