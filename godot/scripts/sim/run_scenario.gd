class_name RunScenario
extends RefCounted
## Controlled starting conditions for a run. Used by headless checks (and the
## game itself, with defaults) so no check needs a parallel rules implementation.
## Every field has the prototype's behaviour as its default.

## Gameplay randomness seed. Negative: seed randomly. Cosmetic randomness is
## separate and never uses this stream.
var seed: int = -1
var start_position: Vector2 = GameRun.WORLD.get_center()
## Starting health; negative means full health.
var start_health: float = -1.0
## Equipped spirit swords, one per sword slot (slot 1 first).
var loadout: Array[SwordSpec] = RunScenario.fang_fixture_loadout()
## Starting `cd` of each sword slot. Empty: drawn from uniform(0.2, 0.6) as in
## the prototype. Fixtures fill it to be deterministic.
var sword_start_cooldowns: Array[float] = []
## False: no waves at all (isolated mechanics fixtures).
var waves_enabled: bool = true
## Delay before the first wave starts (prototype `break_t = 1.6`).
var first_wave_delay: float = 1.6
## Waves the run plays before it counts as survived. Multi-wave generation
## arrives later; this slice plays exactly one.
var wave_count: int = 1
## Husks in the wave; negative uses the prototype formula `5 + 3 * wave`.
var husk_count: int = -1
## Explicit wave composition, spawned in this order. Empty means `husk_count`
## husks. The prototype only unlocks runners and brutes from wave 2; a fixture
## can field them in the first wave (full wave generation is issue #18).
var wave_kinds: Array[StringName] = []
## Husks already standing when the run starts (world positions).
var initial_husks: Array[Vector2] = []
## Enemies of any ported type already standing (or flying) when the run starts.
var initial_enemies: Array[EnemyPlacement] = []
## DEVELOPMENT FIXTURE: enables `GameCommand.dev_shove`, a stand-in for a heavy
## Colossus blow so crowd bowling and wall slams can be played before the
## sword types that cause them are ported. Off in the normal game.
var dev_shove: bool = false
## Healing motes already in the arena (world positions).
var initial_motes: Array[Vector2] = []
## Prototype husks draw their speed factor from uniform(0.9, 1.12); false pins it to 1.
var enemy_speed_jitter: bool = true
## Multiplies every husk's chase speed (fixtures use 0 for a stationary target).
var enemy_speed_scale: float = 1.0
## Probability of a critical hit (prototype: 12%).
var crit_chance: float = 0.12

const CROWD_WAVE: Array[StringName] = [
	&"brute", &"runner", &"husk", &"runner", &"husk", &"runner", &"husk",
	&"brute", &"runner", &"husk", &"runner", &"husk",
]


## DEVELOPMENT FIXTURE, not the final default loadout: three Fang swords (one
## per sword slot) so the first combat slice exercises all three slots while
## Warden, Pike and Colossus are not ported yet. The prototype's own default is
## Fang / Warden / Colossus with poison / ice / fire.
static func fang_fixture_loadout() -> Array[SwordSpec]:
	var specs: Array[SwordSpec] = []
	specs.append(SwordSpec.make(&"fang", 0, &"poison"))
	specs.append(SwordSpec.make(&"fang", 0, &"ice"))
	specs.append(SwordSpec.make(&"fang", 0, &"fire"))
	return specs


## The crowd encounter: DEVELOPMENT FIXTURE for issue #9. One wave of five
## husks, five runners and two brutes (interleaved so the arrival reads), played
## with the three-Fang fixture loadout and the dev shove enabled. The prototype
## would not field runners or brutes before wave 2; the composition is a
## deliberate fixture, not a wave-generation rule (issue #18).
static func crowd_encounter() -> RunScenario:
	var scenario: RunScenario = RunScenario.new()
	scenario.wave_kinds = CROWD_WAVE.duplicate()
	scenario.dev_shove = true
	scenario.first_wave_delay = 1.0
	return scenario
