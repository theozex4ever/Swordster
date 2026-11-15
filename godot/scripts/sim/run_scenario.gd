class_name RunScenario
extends RefCounted
## Controlled starting conditions for a run. Used by headless checks (and the
## game itself, with defaults) so no check needs a parallel rules implementation.
## Every field has the prototype's behaviour as its default.

## The wall encounter's crowd: fourteen enemies pinned between the player
## (WALL_PLAYER) and the east wall, in the order of WALL_CROWD_POINTS. It is the
## composite case of docs/reference/runners-brutes-crowd.md, so the reference
## and the playable fixture are the same arrangement.
const WALL_PLAYER: Vector2 = Vector2(2250.0, 900.0)
const WALL_CROWD_KINDS: Array[StringName] = [
	&"brute", &"brute", &"husk", &"husk", &"husk", &"husk", &"runner",
	&"runner", &"runner", &"runner", &"runner", &"husk", &"runner", &"runner",
]
const WALL_CROWD_POINTS: Array[Vector2] = [
	Vector2(2420.0, 900.0), Vector2(2470.0, 990.0), Vector2(2450.0, 815.0),
	Vector2(2500.0, 860.0), Vector2(2510.0, 945.0), Vector2(2420.0, 760.0),
	Vector2(2490.0, 1010.0), Vector2(2540.0, 885.0), Vector2(2442.0, 1045.0),
	Vector2(2435.0, 815.0), Vector2(2550.0, 1000.0), Vector2(2380.0, 1090.0),
	Vector2(2515.0, 925.0), Vector2(2530.0, 835.0),
]

## The crowd encounter's wave: five husks, five runners and two brutes,
## interleaved so the arrival reads (see `crowd_encounter`).
const CROWD_WAVE: Array[StringName] = [
	&"brute", &"runner", &"husk", &"runner", &"husk", &"runner", &"husk",
	&"brute", &"runner", &"husk", &"runner", &"husk",
]

## The spitter encounter's wave: five spitters among three husks, spawned in
## this order so shooters keep arriving while the husks close in.
const SPITTER_WAVE: Array[StringName] = [
	&"spitter", &"husk", &"spitter", &"spitter", &"husk", &"spitter", &"husk", &"spitter",
]

## The conditions encounter's wave: two brutes (to show their shorter freeze) and
## clustering husks and runners (to show fire spreading), arriving together.
const CONDITIONS_WAVE: Array[StringName] = [
	&"brute", &"husk", &"husk", &"runner", &"husk", &"husk", &"brute", &"husk", &"husk", &"runner", &"husk", &"husk",
]

## The warden encounter's wave: a mixed crowd (husks and runners around two brutes) that
## a sweeping arc catches several of at once and a Maelstrom can gather and finish.
const WARDEN_WAVE: Array[StringName] = [
	&"husk", &"husk", &"runner", &"husk", &"brute", &"husk", &"runner", &"husk", &"husk", &"runner", &"brute", &"husk", &"husk", &"runner",
]

## The pike encounter's wave: husks and runners that line up in front of a Skewer, and two
## brutes (which a carry moves like anyone else), behind the six standing in the first row.
const PIKE_WAVE: Array[StringName] = [
	&"husk", &"runner", &"husk", &"husk", &"brute", &"runner", &"husk", &"husk", &"runner", &"husk", &"brute", &"husk",
]
## The pike encounter's player and its first row: a column of foes strung out toward the
## north wall, 700 px north of the player, so a Skewer north carries them into the wall.
const PIKE_PLAYER: Vector2 = Vector2(1300.0, 700.0)
const PIKE_ROW_KINDS: Array[StringName] = [&"husk", &"husk", &"runner", &"husk", &"brute", &"husk"]
const PIKE_ROW_POINTS: Array[Vector2] = [
	Vector2(1290.0, 330.0), Vector2(1325.0, 270.0), Vector2(1280.0, 200.0),
	Vector2(1310.0, 140.0), Vector2(1300.0, 90.0), Vector2(1250.0, 250.0),
]

## The dev encounters the C key / dev button cycles through, in order. The empty
## name is the normal run (or whatever custom scenario the run was made with).
const ENCOUNTER_NORMAL: StringName = &""
const ENCOUNTER_CROWD: StringName = &"crowd"
const ENCOUNTER_SPITTERS: StringName = &"spitters"
const ENCOUNTER_CONDITIONS: StringName = &"conditions"
const ENCOUNTER_WARDEN: StringName = &"warden"
const ENCOUNTER_PIKE: StringName = &"pike"
const ENCOUNTER_CYCLE: Array[StringName] = [ENCOUNTER_NORMAL, ENCOUNTER_CROWD, ENCOUNTER_SPITTERS, ENCOUNTER_CONDITIONS, ENCOUNTER_WARDEN, ENCOUNTER_PIKE]

## Gameplay randomness seed. Negative: seed randomly. Cosmetic randomness is
## separate and never uses this stream.
var seed: int = -1
## Which dev encounter this scenario is (`ENCOUNTER_*`); empty for the normal run.
## The wall encounter is a variant of the crowd encounter and shares its name.
var encounter: StringName = ENCOUNTER_NORMAL
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
## False makes the run a condition-free FIXTURE: swords still hit, but no element
## is ever applied. The earlier slices' references were captured with the prototype's
## `afflict` switched off, and their checks compare against them in this mode. The
## game itself always plays with conditions on.
var conditions_enabled: bool = true


## Turns this scenario into a condition-free fixture (see `conditions_enabled`).
func without_conditions() -> RunScenario:
	conditions_enabled = false
	return self


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


## DEVELOPMENT FIXTURE for issue #13, not the final default loadout: Fang, Warden and Warden
## (one per sword slot, poison / ice / fire) so Warden's sweeps, its Maelstrom and a mixed
## loadout can be played before Colossus is ported. The prototype's own default is Fang /
## Warden / Colossus with the same three elements; the final default arrives with #16.
static func warden_fixture_loadout() -> Array[SwordSpec]:
	var specs: Array[SwordSpec] = []
	specs.append(SwordSpec.make(&"fang", 0, &"poison"))
	specs.append(SwordSpec.make(SwordDefs.WARDEN, 0, &"ice"))
	specs.append(SwordSpec.make(SwordDefs.WARDEN, 0, &"fire"))
	return specs


## DEVELOPMENT FIXTURE for issue #14, not the final default loadout: three Pikes (one per sword
## slot, poison / ice / fire) so the long thrust and Skewer can be played before the final default
## (issue #16) is set. The prototype's own default is Fang / Warden / Colossus.
static func pike_fixture_loadout() -> Array[SwordSpec]:
	var specs: Array[SwordSpec] = []
	specs.append(SwordSpec.make(SwordDefs.PIKE, 0, &"poison"))
	specs.append(SwordSpec.make(SwordDefs.PIKE, 0, &"ice"))
	specs.append(SwordSpec.make(SwordDefs.PIKE, 0, &"fire"))
	return specs


## The crowd encounter: DEVELOPMENT FIXTURE for issue #9. One wave of five
## husks, five runners and two brutes (interleaved so the arrival reads), played
## with the three-Fang fixture loadout and the dev shove enabled. The prototype
## would not field runners or brutes before wave 2; the composition is a
## deliberate fixture, not a wave-generation rule (issue #18).
static func crowd_encounter() -> RunScenario:
	var scenario: RunScenario = RunScenario.new()
	scenario.encounter = ENCOUNTER_CROWD
	scenario.wave_kinds = CROWD_WAVE.duplicate()
	scenario.dev_shove = true
	scenario.first_wave_delay = 1.0
	return scenario


## The wall encounter: DEVELOPMENT FIXTURE for issue #9. The crowd is already
## standing between the player and the east wall and no wave follows, so a shove
## immediately shows crowd bowling and wall slams. Same fixture loadout and shove.
static func wall_encounter() -> RunScenario:
	var scenario: RunScenario = crowd_encounter()
	scenario.waves_enabled = false
	scenario.start_position = WALL_PLAYER
	var placements: Array[EnemyPlacement] = []
	for i: int in WALL_CROWD_KINDS.size():
		placements.append(EnemyPlacement.make(WALL_CROWD_KINDS[i], WALL_CROWD_POINTS[i]))
	scenario.initial_enemies = placements
	return scenario


## The spitter encounter: DEVELOPMENT FIXTURE for issue #10. One wave of five
## spitters and three husks against the three-Fang fixture loadout, so shooting,
## dodging and parrying can be played at once. The prototype only brings
## spitters in from wave 3; the composition is a fixture, not a wave-generation
## rule (issue #18). No shove: nothing here needs a heavy blow.
static func spitter_encounter() -> RunScenario:
	var scenario: RunScenario = RunScenario.new()
	scenario.encounter = ENCOUNTER_SPITTERS
	scenario.wave_kinds = SPITTER_WAVE.duplicate()
	scenario.first_wave_delay = 1.0
	return scenario


## The conditions encounter: DEVELOPMENT FIXTURE for issue #11. One wave of husks and
## runners with two brutes, against the three-Fang fixture loadout whose swords carry
## poison, ice and fire: stacks, freezing (shorter on a brute), chill, burning and
## fire spreading through the clustered crowd can all be watched. The prototype would
## not field runners or brutes before wave 2; the composition is a fixture, not a
## wave-generation rule (issue #18).
static func conditions_encounter() -> RunScenario:
	var scenario: RunScenario = RunScenario.new()
	scenario.encounter = ENCOUNTER_CONDITIONS
	scenario.wave_kinds = CONDITIONS_WAVE.duplicate()
	scenario.first_wave_delay = 1.0
	return scenario


## The warden encounter: DEVELOPMENT FIXTURE for issue #13. One wave of husks, runners and two
## brutes against the mixed Fang / Warden / Warden loadout: sweeps alternate and catch several
## foes at once, Q / E / R each start their slot's ultimate (Viper Flurry, Maelstrom, Maelstrom).
## The wave is a fixture, not a wave-generation rule (issue #18); the normal run is unchanged.
static func warden_encounter() -> RunScenario:
	var scenario: RunScenario = RunScenario.new()
	scenario.encounter = ENCOUNTER_WARDEN
	scenario.loadout = warden_fixture_loadout()
	scenario.wave_kinds = WARDEN_WAVE.duplicate()
	scenario.first_wave_delay = 1.0
	return scenario


## The pike encounter: DEVELOPMENT FIXTURE for issue #14. The player stands 700 px south of the
## north wall with a column of foes already strung out toward it and a wave of husks, runners and
## two brutes on its way, against three Pikes: thrusts pierce several foes at once, and Q / E / R
## each fire a Skewer that carries what it spears and slams it into the wall (aim north), or
## releases it at the range limit (aim east or west). The composition is a fixture, not a
## wave-generation rule (issue #18); the normal run is unchanged.
static func pike_encounter() -> RunScenario:
	var scenario: RunScenario = RunScenario.new()
	scenario.encounter = ENCOUNTER_PIKE
	scenario.loadout = pike_fixture_loadout()
	scenario.start_position = PIKE_PLAYER
	var placements: Array[EnemyPlacement] = []
	for i: int in PIKE_ROW_KINDS.size():
		placements.append(EnemyPlacement.make(PIKE_ROW_KINDS[i], PIKE_ROW_POINTS[i]))
	scenario.initial_enemies = placements
	scenario.wave_kinds = PIKE_WAVE.duplicate()
	scenario.first_wave_delay = 1.0
	return scenario


## Display name of an encounter for the dev button and legend.
static func encounter_title(name: StringName) -> String:
	match name:
		ENCOUNTER_CROWD:
			return "Crowd"
		ENCOUNTER_SPITTERS:
			return "Spitters"
		ENCOUNTER_CONDITIONS:
			return "Conditions"
		ENCOUNTER_WARDEN:
			return "Warden"
		ENCOUNTER_PIKE:
			return "Pike"
		_:
			return "Normal"


## The encounter the dev button / C key leads to from `name`.
static func next_encounter(name: StringName) -> StringName:
	return ENCOUNTER_CYCLE[(ENCOUNTER_CYCLE.find(name) + 1) % ENCOUNTER_CYCLE.size()]
