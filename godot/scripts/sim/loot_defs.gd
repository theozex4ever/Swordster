class_name LootDefs
extends RefCounted
## Immutable loot constants and the arming rule, copied from game/main.py: `DROP_WEIGHTS`
## (line 104), `ENEMY_TYPES[..]["armed"]` (125-128), `Enemy.__init__` (the armed health factor),
## `Pickup` (391), `Game.swap` (1417) and the arming inside `Game.start_wave` (1451-1460). See
## docs/reference/drops-swaps.md for each value and its capture.
##
## An armed enemy carries one spirit sword (a `SwordSpec`); when it dies the sword lies where it
## fell for PICKUP_LIFE seconds, and the player may swap it into a sword slot while standing within
## PICKUP_REACH of it. Everything here is read-only data or a pure function of its arguments, so no
## sword or enemy can change what a Rare Fang is for the next one.

## How long a dropped sword lies before it is gone, and the distance (strictly less than) from the player
## inside which it can be claimed.
const PICKUP_LIFE: float = 45.0
const PICKUP_REACH: float = 80.0
## A pickup with less than this many seconds left blinks (hidden on every other eighth of a second).
const PICKUP_BLINK_BELOW: float = 6.0
const PICKUP_BLINK_RATE: float = 8.0
## The sword a swap replaces comes back as a drop: this far below the claimed pickup and up to
## RETURN_SPREAD to either side of it (a uniform draw from the run's gameplay stream).
const RETURN_DROP: float = 24.0
const RETURN_SPREAD: float = 20.0
## A freshly swapped-in sword starts where the pickup lay, rising at SWAP_START_VELOCITY, at SWAP_ALTITUDE
## (a Colossus's height, see `SwordState.altitude`), with SWAP_START_COOLDOWN before its first attack and a card flash.
const SWAP_START_COOLDOWN: float = 0.4
const SWAP_ALTITUDE: float = 10.0
const SWAP_START_VELOCITY: Vector2 = Vector2(0.0, -200.0)
const SWAP_FLASH: float = 1.0

## An armed enemy's maximum health is this much more than an unarmed one's.
const ARMED_HP_FACTOR: float = 1.35

## Which sword types armed enemies drop, and how likely each is (`DROP_WEIGHTS`, in the prototype's order).
const DROP_TYPES: Array[StringName] = [SwordDefs.FANG, SwordDefs.WARDEN, SwordDefs.PIKE, SwordDefs.COLOSSUS]
const DROP_WEIGHTS: Array[float] = [3.0, 3.0, 2.5, 1.6]
## The first wave arms its first FIRST_WAVE_ARMED enemies for sure, and the very first carries a Pike.
const FIRST_WAVE_ARMED: int = 2
## Rarity rolls: Mythic below `min(MYTHIC_CAP, MYTHIC_BASE + MYTHIC_PER_WAVE x wave) + bonus x 0.5`, Rare below
## `min(RARE_CAP, RARE_BASE + RARE_PER_WAVE x wave) + bonus`, else Common; a brute's bonus is BRUTE_RARITY_BONUS.
const MYTHIC_CAP: float = 0.25
const MYTHIC_BASE: float = 0.02
const MYTHIC_PER_WAVE: float = 0.02
const RARE_CAP: float = 0.55
const RARE_BASE: float = 0.16
const RARE_PER_WAVE: float = 0.04
const BRUTE_RARITY_BONUS: float = 0.15

const ARMED_CHANCE_HUSK: float = 0.2
const ARMED_CHANCE_RUNNER: float = 0.12
const ARMED_CHANCE_SPITTER: float = 0.22
const ARMED_CHANCE_BRUTE: float = 0.75


## The chance that an enemy of a kind spawns armed (outside the first wave's guaranteed two).
static func armed_chance(kind: StringName) -> float:
	match kind:
		EnemyDefs.RUNNER:
			return ARMED_CHANCE_RUNNER
		EnemyDefs.SPITTER:
			return ARMED_CHANCE_SPITTER
		EnemyDefs.BRUTE:
			return ARMED_CHANCE_BRUTE
		_:
			return ARMED_CHANCE_HUSK


## Whether the arming roll is skipped and the enemy is armed (`w == 1 and j < 2`).
static func is_guaranteed(wave: int, index: int) -> bool:
	return wave == 1 and index < FIRST_WAVE_ARMED


## The drop type a uniform draw `u` in [0, total weight) picks (the prototype's `weighted`: walk the list taking
## each weight off the draw until it is spent; a draw that never spends it takes the last).
static func drop_type_for(draw: float) -> StringName:
	var remaining: float = draw
	for i: int in DROP_TYPES.size():
		remaining -= DROP_WEIGHTS[i]
		if remaining <= 0.0:
			return DROP_TYPES[i]
	return DROP_TYPES[DROP_TYPES.size() - 1]


static func total_drop_weight() -> float:
	var total: float = 0.0
	for weight: float in DROP_WEIGHTS:
		total += weight
	return total


## 0 Common, 1 Rare, 2 Mythic for a draw `roll` in [0, 1) at a wave, for an enemy of `kind`.
static func rarity_for(roll: float, wave: int, kind: StringName) -> int:
	var bonus: float = BRUTE_RARITY_BONUS if kind == EnemyDefs.BRUTE else 0.0
	if roll < minf(MYTHIC_CAP, MYTHIC_BASE + MYTHIC_PER_WAVE * float(wave)) + bonus * 0.5:
		return 2
	if roll < minf(RARE_CAP, RARE_BASE + RARE_PER_WAVE * float(wave)) + bonus:
		return 1
	return 0


## The sword an enemy is armed with, from the four draws the prototype makes (`arm_roll` against the chance,
## `drop_draw` in [0, total weight), `rarity_roll` and `element_index` into `SwordDefs.ELEMENT_ORDER`); null when
## the arming roll misses. The first wave's first two are armed whatever `arm_roll` says, and its very first with a Pike
## whatever `drop_draw` says. A pure function, so the reference cases can pin every branch without a random stream.
static func armed_from_draws(kind: StringName, wave: int, index: int, arm_roll: float, drop_draw: float, rarity_roll: float, element_index: int) -> SwordSpec:
	if not is_guaranteed(wave, index) and arm_roll >= armed_chance(kind):
		return null
	var type_id: StringName = SwordDefs.PIKE if wave == 1 and index == 0 else drop_type_for(drop_draw)
	return SwordSpec.make(type_id, rarity_for(rarity_roll, wave, kind), SwordDefs.ELEMENT_ORDER[element_index])


## Rolls an enemy's arming from the run's gameplay stream. Only the draws the prototype makes are drawn: no arm roll
## for a guaranteed enemy, and no drop, rarity or element draw for an unarmed one.
static func roll_armed(rng: RandomNumberGenerator, kind: StringName, wave: int, index: int) -> SwordSpec:
	var arm_roll: float = 0.0
	if not is_guaranteed(wave, index):
		arm_roll = rng.randf()
		if arm_roll >= armed_chance(kind):
			return null
	var drop_draw: float = 0.0
	if not (wave == 1 and index == 0):
		drop_draw = rng.randf_range(0.0, total_drop_weight())
	var rarity_roll: float = rng.randf()
	var element_index: int = rng.randi_range(0, SwordDefs.ELEMENT_ORDER.size() - 1)
	return armed_from_draws(kind, wave, index, arm_roll, drop_draw, rarity_roll, element_index)
