class_name WaveDefs
extends RefCounted
## The wave formulas, copied from game/main.py `Game.start_wave` (composition and unlocks), `update_waves` (the spawn
## interval), `spawn_point` and `Enemy.__init__` (health per wave). Immutable constants and pure functions of their
## arguments, so a check can pin every boundary without a random stream. See docs/reference/waves.md for each value and
## its capture (tools/reference/capture_waves.py drives the prototype's own `start_wave`, `update_waves` and `Enemy`).
##
## The prototype fields NO cap on how many enemies a wave holds or how many stand at once: wave `w` queues `5 + 3 w` of them
## and they all arrive, however deep the run goes.

## Enemies in wave `w` (`n = 5 + w * 3`).
const ENEMIES_BASE: int = 5
const ENEMIES_PER_WAVE: int = 3

## The weighted pool each queued enemy's kind is drawn from, in the prototype's order. A kind is absent from
## the pool until its first wave (runners and brutes from wave 2, spitters from wave 3).
const HUSK_WEIGHT: float = 6.0
const RUNNER_WEIGHT: float = 2.5
const RUNNER_FIRST_WAVE: int = 2
const SPITTER_WEIGHT: float = 2.0
const SPITTER_FIRST_WAVE: int = 3
## A brute's weight grows with the wave: `0.6 + 0.25 w`.
const BRUTE_WEIGHT_BASE: float = 0.6
const BRUTE_WEIGHT_PER_WAVE: float = 0.25
const BRUTE_FIRST_WAVE: int = 2

## Seconds between one queued enemy's marker and the next (`max(0.12, 0.42 - 0.02 w)`), and before the first.
const SPAWN_INTERVAL_BASE: float = 0.42
const SPAWN_INTERVAL_PER_WAVE: float = 0.02
const SPAWN_INTERVAL_MIN: float = 0.12
const FIRST_SPAWN_DELAY: float = 0.3

## Where a spawn marker may appear: this far from the player (uniform), at least this far after the clamp into the arena
## inset by the margin; the twelfth attempt is taken even if it is still near.
const SPAWN_MIN_DISTANCE: float = 420.0
const SPAWN_MAX_DISTANCE: float = 720.0
const SPAWN_NEAR_LIMIT: float = 320.0
const SPAWN_EDGE_MARGIN: float = 50.0
const SPAWN_ATTEMPTS: int = 12

## The banners (title, then the line under it) of a wave that starts and of a wave that is cleared, and how long they stay.
const WAVE_BANNER_SECONDS: float = 2.4
const WAVE_BANNER_SUB: String = "armed foes carry swords - kill them and claim one"
const CLEARED_BANNER_SECONDS: float = 2.6
const CLEARED_BANNER_SUB: String = "grab dropped swords: stand on one, press 1 / 2 / 3"

## Chain counts that announce themselves with a floating "N CHAIN!" (`Game.kill`).
const CHAIN_MILESTONES: Array[int] = [10, 25, 50, 100]


static func enemy_count(wave: int) -> int:
	return ENEMIES_BASE + wave * ENEMIES_PER_WAVE


## The kinds in the wave's pool, in the prototype's order (husk, runner, spitter, brute) with the absent ones left out.
static func pool_kinds(wave: int) -> Array[StringName]:
	var kinds: Array[StringName] = [EnemyDefs.HUSK]
	if wave >= RUNNER_FIRST_WAVE:
		kinds.append(EnemyDefs.RUNNER)
	if wave >= SPITTER_FIRST_WAVE:
		kinds.append(EnemyDefs.SPITTER)
	if wave >= BRUTE_FIRST_WAVE:
		kinds.append(EnemyDefs.BRUTE)
	return kinds


## The weight of a kind in the wave's pool (0 while it is locked).
static func weight_of(kind: StringName, wave: int) -> float:
	match kind:
		EnemyDefs.HUSK:
			return HUSK_WEIGHT
		EnemyDefs.RUNNER:
			return RUNNER_WEIGHT if wave >= RUNNER_FIRST_WAVE else 0.0
		EnemyDefs.SPITTER:
			return SPITTER_WEIGHT if wave >= SPITTER_FIRST_WAVE else 0.0
		EnemyDefs.BRUTE:
			return BRUTE_WEIGHT_BASE + BRUTE_WEIGHT_PER_WAVE * float(wave) if wave >= BRUTE_FIRST_WAVE else 0.0
	return 0.0


static func total_weight(wave: int) -> float:
	var total: float = 0.0
	for kind: StringName in pool_kinds(wave):
		total += weight_of(kind, wave)
	return total


## The kind a draw in [0, total weight) picks (the prototype's `weighted`: take each weight off the draw until it is
## spent; a draw that never spends it takes the last kind).
static func kind_for(draw: float, wave: int) -> StringName:
	var kinds: Array[StringName] = pool_kinds(wave)
	var remaining: float = draw
	for kind: StringName in kinds:
		remaining -= weight_of(kind, wave)
		if remaining <= 0.0:
			return kind
	return kinds[kinds.size() - 1]


## Draws one queued enemy's kind from the run's gameplay stream.
static func roll_kind(rng: RandomNumberGenerator, wave: int) -> StringName:
	return kind_for(rng.randf_range(0.0, total_weight(wave)), wave)


static func spawn_interval(wave: int) -> float:
	return maxf(SPAWN_INTERVAL_MIN, SPAWN_INTERVAL_BASE - float(wave) * SPAWN_INTERVAL_PER_WAVE)


## A foe's health multiplier in wave `wave` (before the armed factor): it grows by `EnemyDefs.HP_PER_WAVE` for each wave after the first.
static func hp_factor(wave: int) -> float:
	return 1.0 + EnemyDefs.HP_PER_WAVE * float(wave - 1)


## Where the next marker appears (prototype `spawn_point`): up to twelve tries at a point 420-720 px from the player
## in a random direction, each clamped into the arena (inset by 50 px); the first more than 320 px from the player wins and
## the twelfth is taken whatever it is. `next_draw` returns one attempt's (angle, distance), read in the order the prototype
## draws them, so a check can script the attempts.
static func spawn_point(player: Vector2, world: Rect2, next_draw: Callable) -> Vector2:
	var inner: Rect2 = world.grow(-SPAWN_EDGE_MARGIN)
	var point: Vector2 = Vector2.ZERO
	for attempt: int in SPAWN_ATTEMPTS:
		var draw: Vector2 = next_draw.call()
		point = player + SimMath.polar(draw.x, draw.y)
		point = point.clamp(inner.position, inner.end)
		if (point - player).length() > SPAWN_NEAR_LIMIT:
			return point
	return point
