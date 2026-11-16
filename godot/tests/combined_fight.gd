class_name CombinedFight
extends RefCounted
## The one scripted fight behind the render-rate check (issue #41; render_rate_checks.gd): the same scenario, the
## same commands at the same simulation ticks, observed through a digest that must come out identical however the
## frames around those ticks are cut. It replaces the nine per-slice fights (crowd, spitters, flurry, conditions,
## warden, pike, colossus, converge, drops): frame-rate independence lives in shared code (the fixed 60 Hz tick
## loop and the cue queue), so one fight that exercises every mechanic proves it as well as nine that each
## exercised one. The probe (`frame_rate_probe.gd`) plays it through the real Main scene under the engine's own
## fixed-step loop at different frame rates; the checks also play it with bare `GameRun.step()` calls.
##
## The player stands still 400 px from the north and east walls with the prototype's default loadout (Fang poison,
## Warden ice, Colossus fire). Around him stand, every foe pinned in place (speed_scale 0):
##   - eight ARMED foes a few steps away (every enemy type, a Pike or one of every other type, every rarity): they die,
##     their swords lie, and swaps (two refused before anything lies) put a Pike, a Warden, a Fang and a Colossus into
##     the slots; the slots' recharges carry over;
##   - a column to the north (husks, a runner, a brute) that a Skewer carries into the north wall, and packs east
##     (between him and the east wall: a Converge target, then the dev shove bowls it into the wall) and west
##     (tight husks, runners and brutes that burn, poison, freeze and spread fire);
##   - spitters that keep shooting orbs the swords parry or the player dashes through, and sturdy posts that
##     soak up Maelstroms, slams and Cataclysm fields.
## Commands (`COMMANDS`, same index in `AIMS`): (tick, kind, slot), with kind 0 Converge, 1 an ultimate of the slot,
## 2 a swap into the slot, 3 a dash, 4 the dev shove; the aim is an offset from the player.
##
## Playing it is the slowest part of the checks, so the render-rate group starts with
## `if not RenderRateScenario.probes_enabled(): return` (see run_checks.gd's switches).

const TOTAL_TICKS: int = 1500

## The player: 400 px from the north wall and from the east wall (the arena is 2600 x 1800).
const PLAYER: Vector2 = Vector2(2200.0, 400.0)
const STURDY_HP: float = 2500.0
const POST_HP: float = 5000.0
const COLUMN_HP: float = 400.0

## The armed foes (`ARMED_KINDS` carry `ARMED_SWORDS`: Vector3(index into LootDefs.DROP_TYPES, rarity, element index)).
const ARMED_POSTS: Array[Vector2] = [
	Vector2(46.0, 4.0), Vector2(34.0, 38.0), Vector2(-4.0, 48.0), Vector2(-38.0, 34.0), Vector2(-48.0, -6.0), Vector2(-30.0, -40.0), Vector2(8.0, -50.0), Vector2(40.0, -34.0),
]
const ARMED_KINDS: Array[StringName] = [&"husk", &"runner", &"brute", &"spitter", &"husk", &"brute", &"runner", &"husk"]
const ARMED_SWORDS: Array[Vector3] = [
	Vector3(0.0, 0.0, 0.0), Vector3(1.0, 1.0, 1.0), Vector3(2.0, 2.0, 2.0), Vector3(3.0, 1.0, 0.0), Vector3(0.0, 2.0, 1.0), Vector3(1.0, 0.0, 2.0), Vector3(2.0, 1.0, 0.0), Vector3(3.0, 2.0, 1.0),
]
const ARMED_HP: float = 45.0
## A column north (a Skewer north carries it into the wall), a pack east (between the player and the east wall).
const NORTH: Array[Vector2] = [Vector2(0.0, -130.0), Vector2(14.0, -190.0), Vector2(-12.0, -250.0), Vector2(6.0, -310.0), Vector2(-4.0, -355.0)]
const NORTH_KINDS: Array[StringName] = [&"husk", &"runner", &"husk", &"brute", &"husk"]
const EAST: Array[Vector2] = [Vector2(140.0, 6.0), Vector2(205.0, -10.0), Vector2(270.0, 12.0), Vector2(340.0, -4.0), Vector2(180.0, 60.0), Vector2(250.0, -70.0)]
const EAST_KINDS: Array[StringName] = [&"husk", &"brute", &"husk", &"runner", &"husk", &"husk"]
## A tight pack west with brutes and runners: burning spreads through it, brutes freeze for less.
const WEST_PACK: Array[Vector2] = [Vector2(-150.0, 0.0), Vector2(-186.0, 0.0), Vector2(-150.0, 36.0), Vector2(-186.0, 36.0), Vector2(-150.0, -36.0), Vector2(-186.0, -36.0), Vector2(-222.0, 0.0)]
const WEST_BRUTES: Array[Vector2] = [Vector2(-260.0, 30.0), Vector2(-240.0, -90.0)]
const WEST_RUNNERS: Array[Vector2] = [Vector2(-120.0, -110.0), Vector2(-80.0, -130.0), Vector2(-200.0, 100.0)]
## Sturdy husks south that the fields and slams keep dosing, and spitters that keep shooting.
const SOUTH: Array[Vector2] = [Vector2(20.0, 230.0), Vector2(-40.0, 250.0), Vector2(70.0, 270.0), Vector2(10.0, 300.0), Vector2(-60.0, 310.0)]
const SPITTERS: Array[Vector2] = [Vector2(-300.0, 220.0), Vector2(300.0, 230.0), Vector2(-360.0, 120.0)]
const SPITTER_COOLDOWNS: Array[float] = [0.4, 1.0, 1.6]

const KIND_CONVERGE: int = 0
const KIND_ULTIMATE: int = 1
const KIND_SWAP: int = 2
const KIND_DASH: int = 3
const KIND_SHOVE: int = 4
const COMMANDS: Array[Vector3] = [
	Vector3(5.0, 2.0, 1.0), Vector3(12.0, 2.0, 0.0), Vector3(20.0, 1.0, 2.0), Vector3(30.0, 0.0, 0.0), Vector3(50.0, 1.0, 0.0),
	Vector3(200.0, 2.0, 2.0), Vector3(240.0, 2.0, 0.0), Vector3(280.0, 2.0, 1.0),
]
const AIMS: Array[Vector2] = [
	Vector2.ZERO, Vector2.ZERO, Vector2(250.0, 0.0), Vector2(262.0, 5.0), Vector2(-250.0, 0.0),
	Vector2.ZERO, Vector2.ZERO, Vector2.ZERO,
]


static func scenario() -> RunScenario:
	var scenario: RunScenario = RunScenario.new()
	scenario.seed = 18
	scenario.waves_enabled = false
	scenario.dev_shove = true
	scenario.start_position = PLAYER
	scenario.sword_start_cooldowns = [0.3, 0.4, 0.5]
	var placements: Array[EnemyPlacement] = []
	for i: int in ARMED_POSTS.size():
		var carried: Vector3 = ARMED_SWORDS[i]
		var armed: EnemyPlacement = EnemyPlacement.make(ARMED_KINDS[i], PLAYER + ARMED_POSTS[i]).armed_with(SwordSpec.make(LootDefs.DROP_TYPES[int(carried.x)], int(carried.y), SwordDefs.ELEMENT_ORDER[int(carried.z)]))
		armed.speed_scale = 0.0
		armed.hp = ARMED_HP
		placements.append(armed)
	for i: int in NORTH.size():
		placements.append(_post(NORTH_KINDS[i], NORTH[i], COLUMN_HP))
	for i: int in EAST.size():
		placements.append(_post(EAST_KINDS[i], EAST[i], STURDY_HP))
	for offset: Vector2 in WEST_PACK:
		placements.append(_post(EnemyDefs.HUSK, offset))
	for offset: Vector2 in WEST_BRUTES:
		placements.append(_post(EnemyDefs.BRUTE, offset))
	for offset: Vector2 in WEST_RUNNERS:
		placements.append(_post(EnemyDefs.RUNNER, offset))
	for offset: Vector2 in SOUTH:
		placements.append(_post(EnemyDefs.HUSK, offset, STURDY_HP))
	for i: int in SPITTERS.size():
		var shooter: EnemyPlacement = _post(EnemyDefs.SPITTER, SPITTERS[i], POST_HP)
		shooter.shoot_cooldown = SPITTER_COOLDOWNS[i]
		placements.append(shooter)
	scenario.initial_enemies = placements
	return scenario


## A standing foe; health 0 leaves the kind's own.
static func _post(kind: StringName, offset: Vector2, hp: float = 0.0) -> EnemyPlacement:
	var post: EnemyPlacement = EnemyPlacement.make(kind, PLAYER + offset)
	post.speed_scale = 0.0
	if hp > 0.0:
		post.hp = hp
	return post


## Commands to issue once `completed_ticks` ticks have run.
static func commands_at(completed_ticks: int) -> Array[GameCommand]:
	var commands: Array[GameCommand] = []
	for i: int in COMMANDS.size():
		var entry: Vector3 = COMMANDS[i]
		if completed_ticks != int(entry.x):
			continue
		var aim: Vector2 = PLAYER + AIMS[i]
		match int(entry.y):
			KIND_CONVERGE:
				commands.append(GameCommand.converge(aim))
			KIND_ULTIMATE:
				commands.append(GameCommand.ultimate(int(entry.z), aim))
			KIND_SWAP:
				commands.append(GameCommand.swap(int(entry.z)))
			KIND_DASH:
				commands.append(GameCommand.dash())
			KIND_SHOVE:
				commands.append(GameCommand.dev_shove())
	return commands


## Plays the whole script with bare simulation steps. Returns the digest and, for the coverage checks, how many
## ultimates each sword type started (`started`: type id -> count) and which enemy kinds the fight began with.
static func play() -> Dictionary:
	var run: GameRun = GameRun.new(scenario())
	var started: Dictionary = {}
	# A guard of ten steps per scripted tick (hitstop and slow motion add steps that do not advance the tick): a mutation that
	# stops the tick counter must end the script, not hang it.
	var steps: int = 0
	while run.tick < TOTAL_TICKS and steps < TOTAL_TICKS * 10:
		for command: GameCommand in commands_at(run.tick):
			var before: int = run.cue_count(SimCue.Kind.ULTIMATE_STARTED)
			var sword_type: StringName = &""
			if command.kind == GameCommand.Kind.ULTIMATE and command.slot >= 0 and command.slot < run.swords.size():
				sword_type = run.swords[command.slot].spec.type_id
			run.apply(command)
			if run.cue_count(SimCue.Kind.ULTIMATE_STARTED) > before:
				started[sword_type] = int(started.get(sword_type, 0)) + 1
		run.step()
		run.take_cues()
		steps += 1
	return {"digest": RenderRateScenario.digest(run), "started": started}


## Every requirement below is a minimum count of something the fight must have made happen, so a fight that has
## quietly stopped exercising a mechanic (and would then prove nothing about it) fails here instead of passing.
const REQUIRED_CUES: Dictionary = {
	"kills": 12, "hit_cues": 60, "ultimate_cues": 8, "refused_cues": 1, "hurt_cues": 1,
	"shove_cues": 1, "bowl_cues": 3, "slam_cues": 2,
	"shot_cues": 3, "parry_cues": 1, "orbs_cleared": 1,
	"beat_cues": 3, "burst_cues": 1, "skewer_launch_cues": 1, "skewer_release_cues": 1,
	"colossus_slam_cues": 3, "field_created_cues": 2, "field_pulse_cues": 3, "converge_cues": 1,
	"drop_cues": 6, "swap_cues": 3, "swap_refused_cues": 1,
	"frozen_cues": 1, "shatter_cues": 1, "spread_cues": 1, "condition_damage_cues": 10,
}
## One ultimate of each of these sword types must have started (Viper Flurry, Maelstrom, Skewer, Cataclysm).
const REQUIRED_ULTIMATE_TYPES: Array[StringName] = [SwordDefs.FANG, SwordDefs.WARDEN, SwordDefs.PIKE, SwordDefs.COLOSSUS]
const REQUIRED_KINDS: Array[StringName] = [EnemyDefs.HUSK, EnemyDefs.RUNNER, EnemyDefs.BRUTE, EnemyDefs.SPITTER]


## The requirements the played fight misses, as [label, detail] pairs; empty when it covers everything.
static func coverage_failures(played: Dictionary) -> Array[Array]:
	var digest: Dictionary = played["digest"]
	var missed: Array[Array] = []
	for key: String in REQUIRED_CUES:
		if int(digest[key]) < int(REQUIRED_CUES[key]):
			missed.append(["the combined fight reaches %d of %s" % [int(REQUIRED_CUES[key]), key], "only %d" % int(digest[key])])
	for sword_type: StringName in REQUIRED_ULTIMATE_TYPES:
		if int((played["started"] as Dictionary).get(sword_type, 0)) < 1:
			missed.append(["the combined fight starts an ultimate of the %s" % sword_type, "started: %s" % [played["started"]]])
	var kinds: Dictionary = {}
	for placement: EnemyPlacement in scenario().initial_enemies:
		kinds[placement.kind] = true
		if placement.armed != null:
			kinds["armed"] = true
	for kind: StringName in REQUIRED_KINDS:
		if not kinds.has(kind):
			missed.append(["the combined fight fields every enemy type", "no %s" % kind])
	if bool(digest["dead"]):
		missed.append(["the player survives the combined fight", "dead"])
	if (digest["pickups"] as Array).is_empty():
		missed.append(["a dropped sword is still lying at the end", "none"])
	return missed


static func coverage_summary(played: Dictionary) -> String:
	var digest: Dictionary = played["digest"]
	var parts: Array[String] = []
	for key: String in REQUIRED_CUES:
		parts.append("%s %d" % [key.trim_suffix("_cues"), int(digest[key])])
	parts.append("ultimates by type %s" % [played["started"]])
	return ", ".join(parts)
