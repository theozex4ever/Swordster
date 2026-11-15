class_name RenderRateScenario
extends RefCounted
## Scripted fights shared by the render-rate checks: the same scenario, the same
## commands at the same simulation ticks, observed through a digest that must
## come out identical however the frames around those ticks are cut. Three
## scripts: "crowd" (issue #9: a shoved crowd against the wall), "spitters"
## (issue #10: orbs fired, parried and dodged) and "flurry" (issue #12: Viper
## Flurry commanded from every sword slot, repeated and refused) and "conditions"
## (issue #11: three elemental swords burning, poisoning and freezing standing packs,
## burning deaths spreading, brutes freezing for less), "warden" (issue #13: a Fang and two
## Wardens sweeping standing packs and whirling Maelstroms through them) and "pike" (issue #14: three
## Pikes thrusting through standing columns and Skewers carrying them into the walls, the range limit
## and a corner, with refused presses and an orb parried) and "colossus" (issue #15: three Colossi crushing
## standing packs, four Cataclysms (two on one spot) leaving poison, ice and fire fields over them, orbs cleared
## by slams, refused presses). The probe (`frame_rate_probe.gd`)
## plays one through the real Main scene under the engine's own fixed-step loop
## at different frame rates; the checks also play it with bare `GameRun.step()`
## calls.
##
## Playing them is the slowest part of the checks, so every group's render-rate check starts with
## `if not RenderRateScenario.probes_enabled(): return` (see run_checks.gd's switches).

const REFERENCE_PATH: String = "res://tests/reference/crowd_and_walls.json"
const CROWD: String = "crowd"
const SPITTERS: String = "spitters"
const FLURRY: String = "flurry"
const CONDITIONS: String = "conditions"
const WARDEN: String = "warden"
const PIKE: String = "pike"
const COLOSSUS: String = "colossus"
const TOTAL_TICKS: int = 900
## Set in the environment by run_checks.gd's --fail-fast once a check has failed.
const STOPPED_ENV: String = "SWORDSTER_CHECKS_STOPPED"
## Simulation ticks (ticks already completed) before which each command is issued.
const SHOVE_TICKS: Array[int] = [0, 200, 420, 520, 560, 640, 700]
const DASH_TICK: int = 500
## The spitters script: the player stands still at the arena centre, four husks
## that never move (and never die) give the three Fang swords something to strike
## near him, and six spitters (staggered first shots) shoot at him. He dashes at
## these ticks, so some orbs meet an invulnerable player.
const SPITTER_DASH_TICKS: Array[int] = [330, 610]
const SPITTER_POSTS: Array[Vector2] = [Vector2(150.0, 0.0), Vector2(0.0, 150.0), Vector2(-150.0, 0.0), Vector2(0.0, -150.0), Vector2(106.0, 106.0), Vector2(-106.0, 106.0), Vector2(-106.0, -106.0), Vector2(106.0, -106.0)]
const SPITTER_SHOOTERS: Array[Vector2] = [Vector2(330.0, 0.0), Vector2(0.0, 400.0), Vector2(-360.0, 0.0), Vector2(0.0, -430.0), Vector2(260.0, 260.0), Vector2(-300.0, 300.0), Vector2(-280.0, -280.0), Vector2(250.0, -250.0), Vector2(460.0, -240.0), Vector2(-440.0, 260.0)]
## The flurry script: the player stands still while the three Fang swords fight a
## cluster of standing enemies. Some have ordinary health and die to the darts, the
## others (`FLURRY_TOUGH`) are far too tough to. Ultimates are commanded at these ticks:
## (tick, slot, aim point as an offset from the player). Presses at ticks the slot
## is still recharging (or running) are refused and must change nothing.
const FLURRY_FRAGILE: Array[Vector2] = [Vector2(260.0, 0.0), Vector2(300.0, 40.0), Vector2(240.0, -50.0), Vector2(-250.0, 20.0), Vector2(-300.0, -30.0), Vector2(20.0, 280.0), Vector2(-40.0, -270.0)]
const FLURRY_TOUGH: Array[Vector2] = [Vector2(330.0, 90.0), Vector2(-320.0, 80.0), Vector2(60.0, 330.0), Vector2(-80.0, -340.0), Vector2(200.0, 200.0), Vector2(-210.0, -190.0)]
const FLURRY_COMMANDS: Array[Vector3] = [
	Vector3(30.0, 0.0, 0.0), Vector3(31.0, 0.0, 0.0), Vector3(40.0, 1.0, 0.0), Vector3(41.0, 1.0, 0.0), Vector3(150.0, 2.0, 0.0),
	Vector3(155.0, 0.0, 0.0), Vector3(300.0, 1.0, 0.0), Vector3(400.0, 2.0, 0.0), Vector3(500.0, 0.0, 0.0), Vector3(600.0, 0.0, 0.0), Vector3(601.0, 0.0, 0.0), Vector3(620.0, 1.0, 0.0), Vector3(760.0, 2.0, 0.0),
]
const FLURRY_AIMS: Array[Vector2] = [Vector2(280.0, 20.0), Vector2(-270.0, 0.0), Vector2(0.0, 290.0), Vector2(900.0, 0.0), Vector2(-250.0, -20.0), Vector2(0.0, -300.0)]
## The conditions script: the player stands still while the three elemental Fang swords
## (poison, ice, fire) fight standing packs: a tight pack of husks (fire spreads through it),
## two brutes, runners, and tough posts that soak up stacks. The same ultimates are commanded
## at these ticks: (tick, slot, aim point as an offset from the player).
const CONDITIONS_PACK: Array[Vector2] = [
	Vector2(150.0, 0.0), Vector2(186.0, 0.0), Vector2(150.0, 36.0), Vector2(186.0, 36.0), Vector2(150.0, -36.0), Vector2(186.0, -36.0), Vector2(222.0, 0.0),
]
const CONDITIONS_BRUTES: Array[Vector2] = [Vector2(-160.0, 20.0), Vector2(-120.0, -110.0)]
const CONDITIONS_RUNNERS: Array[Vector2] = [Vector2(20.0, -150.0), Vector2(60.0, -150.0), Vector2(-30.0, 150.0)]
const CONDITIONS_POSTS: Array[Vector2] = [Vector2(110.0, 130.0), Vector2(-110.0, 130.0)]
const CONDITIONS_COMMANDS: Array[Vector3] = [
	Vector3(150.0, 2.0, 0.0), Vector3(260.0, 0.0, 0.0), Vector3(380.0, 1.0, 0.0), Vector3(520.0, 2.0, 0.0), Vector3(640.0, 0.0, 0.0), Vector3(760.0, 1.0, 0.0),
]
const CONDITIONS_AIMS: Array[Vector2] = [Vector2(170.0, 0.0), Vector2(180.0, 20.0), Vector2(-150.0, 0.0), Vector2(160.0, -20.0), Vector2(0.0, -140.0), Vector2(190.0, 10.0)]
## The warden script: the player stands still while a Fang and two Wardens (poison, ice, fire)
## fight standing enemies: fragile husks and runners that die to the sweeps and Maelstroms,
## sturdier husks that survive the first whirls, two brutes and two tough posts that take hit
## after hit. Commands: (tick, slot) with the aim as an offset from the player. Slots one and two
## whirl Maelstroms (the second time after the recharge, which hitstop stretches, so the last two
## are still whirling when the script ends), slot zero's Viper Flurry is cast twice, and three
## presses at ticks the slot is still recharging are refused.
const WARDEN_FRAGILE: Array[Vector2] = [
	Vector2(160.0, 0.0), Vector2(200.0, 40.0), Vector2(180.0, -50.0), Vector2(-170.0, 20.0), Vector2(-210.0, -30.0),
	Vector2(40.0, 190.0),
]
const WARDEN_STURDY: Array[Vector2] = [
	Vector2(-30.0, -200.0), Vector2(250.0, 100.0), Vector2(-240.0, 90.0), Vector2(110.0, -150.0), Vector2(190.0, -20.0),
	Vector2(-200.0, 10.0), Vector2(230.0, -90.0), Vector2(-170.0, -120.0),
]
const WARDEN_STURDY_HP: float = 220.0
const WARDEN_RUNNERS: Array[Vector2] = [Vector2(215.0, -10.0), Vector2(-195.0, 60.0), Vector2(70.0, 230.0)]
const WARDEN_BRUTES: Array[Vector2] = [Vector2(300.0, -60.0), Vector2(-300.0, 60.0)]
const WARDEN_POSTS: Array[Vector2] = [Vector2(130.0, 110.0), Vector2(-120.0, -110.0)]
const WARDEN_COMMANDS: Array[Vector3] = [
	Vector3(40.0, 1.0, 0.0), Vector3(60.0, 2.0, 0.0), Vector3(100.0, 0.0, 0.0), Vector3(300.0, 1.0, 0.0), Vector3(320.0, 2.0, 0.0),
	Vector3(400.0, 0.0, 0.0), Vector3(720.0, 0.0, 0.0), Vector3(800.0, 1.0, 0.0), Vector3(810.0, 2.0, 0.0),
]
const WARDEN_AIMS: Array[Vector2] = [
	Vector2(220.0, 20.0), Vector2(-210.0, 10.0), Vector2(180.0, -40.0), Vector2(0.0, 250.0), Vector2(-250.0, 0.0),
	Vector2(260.0, 0.0), Vector2(-200.0, 30.0), Vector2(230.0, 10.0), Vector2(-220.0, 20.0),
]
## The pike script: the player stands still 400 px from the north and east walls while three Pikes
## (poison, ice, fire) thrust at standing columns and Skewers are commanded: north, east and
## north-east (a corner) carry a column into a wall; west and south run to the range limit; and two
## presses at ticks the slot is still recharging are refused. Standing husks, runners and brutes have
## enough health to survive the blow and the slam; pinned spitters keep firing orbs the thrusts and
## Skewers cross. Commands: (tick, slot, aim index); the aim is an offset from the player.
const PIKE_PLAYER: Vector2 = Vector2(2200.0, 400.0)
const PIKE_HP: float = 400.0
const PIKE_SPITTER_HP: float = 5000.0
const PIKE_NORTH: Array[Vector2] = [Vector2(0.0, -130.0), Vector2(14.0, -190.0), Vector2(-12.0, -250.0), Vector2(6.0, -310.0), Vector2(-4.0, -355.0)]
const PIKE_NORTH_KINDS: Array[StringName] = [&"husk", &"runner", &"husk", &"brute", &"husk"]
const PIKE_EAST: Array[Vector2] = [Vector2(140.0, 6.0), Vector2(205.0, -10.0), Vector2(270.0, 12.0), Vector2(340.0, -4.0)]
const PIKE_NORTH_EAST: Array[Vector2] = [Vector2(150.0, -150.0), Vector2(210.0, -205.0), Vector2(268.0, -262.0), Vector2(318.0, -300.0)]
const PIKE_WEST: Array[Vector2] = [Vector2(-170.0, 4.0), Vector2(-260.0, -8.0), Vector2(-350.0, 10.0), Vector2(-430.0, 0.0)]
const PIKE_SOUTH: Array[Vector2] = [Vector2(6.0, 160.0), Vector2(-10.0, 240.0), Vector2(4.0, 320.0), Vector2(-6.0, 400.0)]
const PIKE_SPITTERS: Array[Vector2] = [Vector2(-300.0, 220.0), Vector2(-250.0, 300.0), Vector2(-360.0, 120.0)]
const PIKE_SPITTER_COOLDOWNS: Array[float] = [0.4, 1.0, 1.6]
const PIKE_COMMANDS: Array[Vector3] = [
	Vector3(40.0, 0.0, 0.0), Vector3(60.0, 1.0, 1.0), Vector3(80.0, 2.0, 2.0), Vector3(150.0, 1.0, 3.0), Vector3(160.0, 2.0, 3.0),
	Vector3(840.0, 0.0, 3.0), Vector3(850.0, 1.0, 4.0), Vector3(860.0, 2.0, 0.0),
]
const PIKE_AIMS: Array[Vector2] = [Vector2(0.0, -300.0), Vector2(300.0, 0.0), Vector2(300.0, -300.0), Vector2(-300.0, 0.0), Vector2(0.0, 300.0)]
## The colossus script: the player stands still while three Colossi (a Mythic poison, a Rare ice and a Common
## fire sword, so the recharges differ) crush standing packs. Cataclysms are commanded at these ticks: (tick, slot,
## aim index). Slot zero's second comes after its recharge (Mythic, 10.36 s stretched by every slam's hitstop: ready on
## tick 787), and two presses at ticks the slot is still recharging are refused. Fragile foes die to slams and
## fields, sturdy ones outlast them; two pinned spitters keep firing orbs across the packs.
const COLOSSUS_PACK_EAST: Array[Vector2] = [Vector2(250.0, -10.0), Vector2(290.0, 30.0), Vector2(230.0, 50.0), Vector2(275.0, -55.0), Vector2(310.0, -20.0), Vector2(215.0, -30.0)]
const COLOSSUS_PACK_WEST: Array[Vector2] = [Vector2(-240.0, 60.0), Vector2(-280.0, 20.0), Vector2(-225.0, 100.0), Vector2(-265.0, 75.0), Vector2(-300.0, 55.0)]
const COLOSSUS_PACK_NORTH: Array[Vector2] = [Vector2(20.0, -270.0), Vector2(-40.0, -290.0), Vector2(60.0, -300.0), Vector2(10.0, -320.0)]
const COLOSSUS_BRUTES: Array[Vector2] = [Vector2(260.0, 110.0), Vector2(-120.0, -250.0)]
const COLOSSUS_SPITTERS: Array[Vector2] = [Vector2(420.0, -120.0), Vector2(-430.0, 140.0)]
const COLOSSUS_SPITTER_COOLDOWNS: Array[float] = [0.3, 0.9]
const COLOSSUS_FRAGILE_HP: float = 70.0
const COLOSSUS_STURDY_HP: float = 700.0
const COLOSSUS_COMMANDS: Array[Vector3] = [
	Vector3(40.0, 0.0, 0.0), Vector3(100.0, 1.0, 1.0), Vector3(160.0, 2.0, 2.0), Vector3(300.0, 0.0, 0.0), Vector3(350.0, 1.0, 1.0),
	Vector3(800.0, 0.0, 0.0),
]
const COLOSSUS_AIMS: Array[Vector2] = [Vector2(260.0, 10.0), Vector2(-255.0, 60.0), Vector2(20.0, -285.0)]
## The first SPITTER_PINNED shooters stand their ground (their shots keep flying
## along the husk spokes the swords strike); the rest move as spitters do.
const SPITTER_PINNED: int = 8
const SPITTER_COOLDOWNS: Array[float] = [0.2, 0.5, 0.9, 1.3, 1.8, 2.3, 0.7, 1.1, 1.6, 2.0]


## The crowd pinned against the east wall (the reference's composite
## formation) plus the crowd encounter's own wave arriving later, with the
## three-Fang fixture loadout defending a stationary player.
static func scenario(name: String = CROWD) -> RunScenario:
	if name == SPITTERS:
		return _spitter_scenario()
	if name == FLURRY:
		return _flurry_scenario()
	if name == CONDITIONS:
		return _conditions_scenario()
	if name == WARDEN:
		return _warden_scenario()
	if name == PIKE:
		return _pike_scenario()
	if name == COLOSSUS:
		return _colossus_scenario()
	var file: FileAccess = FileAccess.open(REFERENCE_PATH, FileAccess.READ)
	var reference: Dictionary = JSON.parse_string(file.get_as_text())
	var crowd: Dictionary = reference["crowd_encounter"]
	var scenario: RunScenario = RunScenario.crowd_encounter()
	scenario.seed = 5
	scenario.first_wave_delay = 2.0
	scenario.sword_start_cooldowns = [0.3, 0.4, 0.5]
	var player: Array = crowd["player"]
	scenario.start_position = Vector2(float(player[0]), float(player[1]))
	var placements: Array[EnemyPlacement] = []
	for setup: Dictionary in crowd["setup"]:
		var placement: EnemyPlacement = EnemyPlacement.make(StringName(setup["kind"]), Vector2(float(setup["x"]), float(setup["y"])))
		placements.append(placement)
	scenario.initial_enemies = placements
	return scenario


static func _spitter_scenario() -> RunScenario:
	var scenario: RunScenario = RunScenario.fang_fixture()
	scenario.seed = 8
	scenario.waves_enabled = false
	scenario.sword_start_cooldowns = [0.3, 0.4, 0.5]
	var center: Vector2 = scenario.start_position
	var placements: Array[EnemyPlacement] = []
	for offset: Vector2 in SPITTER_POSTS:
		var post: EnemyPlacement = EnemyPlacement.make(EnemyDefs.HUSK, center + offset)
		post.speed_scale = 0.0
		post.hp = 5000.0
		placements.append(post)
	for i: int in SPITTER_SHOOTERS.size():
		var shooter: EnemyPlacement = EnemyPlacement.make(EnemyDefs.SPITTER, center + SPITTER_SHOOTERS[i])
		shooter.shoot_cooldown = SPITTER_COOLDOWNS[i]
		if i < SPITTER_PINNED:
			shooter.speed_scale = 0.0
		placements.append(shooter)
	scenario.initial_enemies = placements
	return scenario


static func _flurry_scenario() -> RunScenario:
	var scenario: RunScenario = RunScenario.fang_fixture()
	scenario.seed = 12
	scenario.waves_enabled = false
	scenario.sword_start_cooldowns = [0.3, 0.4, 0.5]
	var center: Vector2 = scenario.start_position
	var placements: Array[EnemyPlacement] = []
	for offset: Vector2 in FLURRY_FRAGILE:
		var husk: EnemyPlacement = EnemyPlacement.make(EnemyDefs.HUSK, center + offset)
		husk.speed_scale = 0.0
		placements.append(husk)
	for offset: Vector2 in FLURRY_TOUGH:
		var post: EnemyPlacement = EnemyPlacement.make(EnemyDefs.HUSK, center + offset)
		post.speed_scale = 0.0
		post.hp = 5000.0
		placements.append(post)
	scenario.initial_enemies = placements
	return scenario


static func _warden_scenario() -> RunScenario:
	var scenario: RunScenario = RunScenario.fang_fixture()
	scenario.seed = 13
	scenario.waves_enabled = false
	scenario.loadout = RunScenario.warden_fixture_loadout()
	scenario.sword_start_cooldowns = [0.3, 0.4, 0.5]
	var center: Vector2 = scenario.start_position
	var placements: Array[EnemyPlacement] = []
	for offset: Vector2 in WARDEN_FRAGILE:
		var husk: EnemyPlacement = EnemyPlacement.make(EnemyDefs.HUSK, center + offset)
		husk.speed_scale = 0.0
		placements.append(husk)
	for offset: Vector2 in WARDEN_STURDY:
		var sturdy: EnemyPlacement = EnemyPlacement.make(EnemyDefs.HUSK, center + offset)
		sturdy.speed_scale = 0.0
		sturdy.hp = WARDEN_STURDY_HP
		placements.append(sturdy)
	for offset: Vector2 in WARDEN_RUNNERS:
		var runner: EnemyPlacement = EnemyPlacement.make(EnemyDefs.RUNNER, center + offset)
		runner.speed_scale = 0.0
		placements.append(runner)
	for offset: Vector2 in WARDEN_BRUTES:
		var brute: EnemyPlacement = EnemyPlacement.make(EnemyDefs.BRUTE, center + offset)
		brute.speed_scale = 0.0
		placements.append(brute)
	for offset: Vector2 in WARDEN_POSTS:
		var post: EnemyPlacement = EnemyPlacement.make(EnemyDefs.HUSK, center + offset)
		post.speed_scale = 0.0
		post.hp = 5000.0
		placements.append(post)
	scenario.initial_enemies = placements
	return scenario


static func _pike_scenario() -> RunScenario:
	var scenario: RunScenario = RunScenario.fang_fixture()
	scenario.seed = 14
	scenario.waves_enabled = false
	scenario.loadout = RunScenario.pike_fixture_loadout()
	scenario.sword_start_cooldowns = [0.3, 0.4, 0.5]
	scenario.start_position = PIKE_PLAYER
	var placements: Array[EnemyPlacement] = []
	for i: int in PIKE_NORTH.size():
		placements.append(_pike_post(PIKE_NORTH_KINDS[i], PIKE_PLAYER + PIKE_NORTH[i]))
	for offset: Vector2 in PIKE_EAST:
		placements.append(_pike_post(EnemyDefs.HUSK, PIKE_PLAYER + offset))
	for offset: Vector2 in PIKE_NORTH_EAST:
		placements.append(_pike_post(EnemyDefs.RUNNER, PIKE_PLAYER + offset))
	for offset: Vector2 in PIKE_WEST:
		placements.append(_pike_post(EnemyDefs.HUSK, PIKE_PLAYER + offset, 0.0))
	for offset: Vector2 in PIKE_SOUTH:
		placements.append(_pike_post(EnemyDefs.BRUTE if offset.y > 300.0 else EnemyDefs.HUSK, PIKE_PLAYER + offset, 0.0))
	for i: int in PIKE_SPITTERS.size():
		var shooter: EnemyPlacement = EnemyPlacement.make(EnemyDefs.SPITTER, PIKE_PLAYER + PIKE_SPITTERS[i])
		shooter.shoot_cooldown = PIKE_SPITTER_COOLDOWNS[i]
		shooter.speed_scale = 0.0
		shooter.hp = PIKE_SPITTER_HP
		placements.append(shooter)
	scenario.initial_enemies = placements
	return scenario


static func _colossus_scenario() -> RunScenario:
	var scenario: RunScenario = RunScenario.fang_fixture()
	scenario.seed = 15
	scenario.waves_enabled = false
	var specs: Array[SwordSpec] = []
	specs.append(SwordSpec.make(SwordDefs.COLOSSUS, 2, &"poison"))
	specs.append(SwordSpec.make(SwordDefs.COLOSSUS, 1, &"ice"))
	specs.append(SwordSpec.make(SwordDefs.COLOSSUS, 0, &"fire"))
	scenario.loadout = specs
	scenario.sword_start_cooldowns = [0.3, 0.4, 0.5]
	var placements: Array[EnemyPlacement] = []
	var index: int = 0
	for pack: Array[Vector2] in [COLOSSUS_PACK_EAST, COLOSSUS_PACK_WEST, COLOSSUS_PACK_NORTH]:
		for offset: Vector2 in pack:
			var kind: StringName = EnemyDefs.RUNNER if index % 4 == 3 else EnemyDefs.HUSK
			var post: EnemyPlacement = EnemyPlacement.make(kind, GameRun.WORLD.get_center() + offset)
			post.speed_scale = 0.0
			post.hp = COLOSSUS_FRAGILE_HP if index % 3 == 1 else COLOSSUS_STURDY_HP
			placements.append(post)
			index += 1
	for offset: Vector2 in COLOSSUS_BRUTES:
		var brute: EnemyPlacement = EnemyPlacement.make(EnemyDefs.BRUTE, GameRun.WORLD.get_center() + offset)
		brute.speed_scale = 0.0
		brute.hp = COLOSSUS_STURDY_HP
		placements.append(brute)
	for i: int in COLOSSUS_SPITTERS.size():
		var shooter: EnemyPlacement = EnemyPlacement.make(EnemyDefs.SPITTER, GameRun.WORLD.get_center() + COLOSSUS_SPITTERS[i])
		shooter.shoot_cooldown = COLOSSUS_SPITTER_COOLDOWNS[i]
		shooter.speed_scale = 0.0
		shooter.hp = 5000.0
		placements.append(shooter)
	scenario.initial_enemies = placements
	return scenario


## A standing post; health 0 leaves the enemy kind's own (so the blow of a Skewer kills it).
static func _pike_post(kind: StringName, at: Vector2, hp: float = PIKE_HP) -> EnemyPlacement:
	var post: EnemyPlacement = EnemyPlacement.make(kind, at)
	post.speed_scale = 0.0
	if hp > 0.0:
		post.hp = hp
	return post


static func _conditions_scenario() -> RunScenario:
	var scenario: RunScenario = RunScenario.fang_fixture()
	scenario.seed = 11
	scenario.waves_enabled = false
	scenario.sword_start_cooldowns = [0.3, 0.4, 0.5]
	var center: Vector2 = scenario.start_position
	var placements: Array[EnemyPlacement] = []
	for offset: Vector2 in CONDITIONS_PACK:
		var husk: EnemyPlacement = EnemyPlacement.make(EnemyDefs.HUSK, center + offset)
		husk.speed_scale = 0.0
		placements.append(husk)
	for offset: Vector2 in CONDITIONS_BRUTES:
		var brute: EnemyPlacement = EnemyPlacement.make(EnemyDefs.BRUTE, center + offset)
		brute.speed_scale = 0.0
		placements.append(brute)
	for offset: Vector2 in CONDITIONS_RUNNERS:
		var runner: EnemyPlacement = EnemyPlacement.make(EnemyDefs.RUNNER, center + offset)
		runner.speed_scale = 0.0
		placements.append(runner)
	for offset: Vector2 in CONDITIONS_POSTS:
		var post: EnemyPlacement = EnemyPlacement.make(EnemyDefs.HUSK, center + offset)
		post.speed_scale = 0.0
		post.hp = 5000.0
		placements.append(post)
	scenario.initial_enemies = placements
	return scenario


## Commands to issue once `completed_ticks` ticks have run.
static func commands_at(completed_ticks: int, name: String = CROWD) -> Array[GameCommand]:
	var commands: Array[GameCommand] = []
	if name == COLOSSUS:
		for i: int in COLOSSUS_COMMANDS.size():
			var entry: Vector3 = COLOSSUS_COMMANDS[i]
			if completed_ticks == int(entry.x):
				commands.append(GameCommand.ultimate(int(entry.y), GameRun.WORLD.get_center() + COLOSSUS_AIMS[int(entry.z)]))
		return commands
	if name == PIKE:
		for i: int in PIKE_COMMANDS.size():
			var entry: Vector3 = PIKE_COMMANDS[i]
			if completed_ticks == int(entry.x):
				commands.append(GameCommand.ultimate(int(entry.y), PIKE_PLAYER + PIKE_AIMS[int(entry.z)]))
		return commands
	if name == WARDEN:
		for i: int in WARDEN_COMMANDS.size():
			var entry: Vector3 = WARDEN_COMMANDS[i]
			if completed_ticks == int(entry.x):
				commands.append(GameCommand.ultimate(int(entry.y), GameRun.WORLD.get_center() + WARDEN_AIMS[i]))
		return commands
	if name == CONDITIONS:
		for i: int in CONDITIONS_COMMANDS.size():
			var entry: Vector3 = CONDITIONS_COMMANDS[i]
			if completed_ticks == int(entry.x):
				commands.append(GameCommand.ultimate(int(entry.y), GameRun.WORLD.get_center() + CONDITIONS_AIMS[i]))
		return commands
	if name == FLURRY:
		for i: int in FLURRY_COMMANDS.size():
			var entry: Vector3 = FLURRY_COMMANDS[i]
			if completed_ticks == int(entry.x):
				commands.append(GameCommand.ultimate(int(entry.y), GameRun.WORLD.get_center() + FLURRY_AIMS[i % FLURRY_AIMS.size()]))
		return commands
	if name == SPITTERS:
		if completed_ticks in SPITTER_DASH_TICKS:
			commands.append(GameCommand.dash())
		return commands
	if completed_ticks in SHOVE_TICKS:
		commands.append(GameCommand.dev_shove())
	if completed_ticks == DASH_TICK:
		commands.append(GameCommand.dash())
	return commands


## Plays the whole script with bare simulation steps.
static func play_headless(name: String = CROWD) -> Dictionary:
	var run: GameRun = GameRun.new(scenario(name))
	while run.tick < TOTAL_TICKS:
		for command: GameCommand in commands_at(run.tick, name):
			run.apply(command)
		run.step()
		run.take_cues()
	return digest(run)


## Everything that must not depend on frame rate, as plain values.
static func digest(run: GameRun) -> Dictionary:
	var alive: Array[String] = []
	var flying: Array[String] = []
	for projectile: ProjectileState in run.projectiles:
		flying.append("%.3f:%.3f:%.3f" % [projectile.position.x, projectile.position.y, projectile.life])
	var ordered: Array[EnemyState] = run.enemies.duplicate()
	ordered.sort_custom(func(a: EnemyState, b: EnemyState) -> bool: return a.serial < b.serial)
	for enemy: EnemyState in ordered:
		var c: EnemyConditions = enemy.conditions
		alive.append("%d:%s:%.3f:%.3f:%.3f:%.3f:%.3f:%d:%.3f:%d:%.3f:%.3f" % [enemy.serial, enemy.kind, enemy.position.x, enemy.position.y, enemy.hp, c.burn, c.poison, c.poison_stacks, c.chill, c.chill_stacks, c.frozen, c.dot])
	return {
		"tick": run.tick,
		"kills": run.kills,
		"best_combo": run.best_combo,
		"hp": snappedf(run.hp, 0.001),
		"dead": run.dead,
		"position": "%.3f,%.3f" % [run.position.x, run.position.y],
		"motes": run.motes.size(),
		"kill_cues": run.cue_count(SimCue.Kind.ENEMY_KILLED),
		"slam_cues": run.cue_count(SimCue.Kind.WALL_SLAM),
		"bowl_cues": run.cue_count(SimCue.Kind.BOWLED),
		"shove_cues": run.cue_count(SimCue.Kind.SHOVE),
		"shot_cues": run.cue_count(SimCue.Kind.PROJECTILE_FIRED),
		"parry_cues": run.cue_count(SimCue.Kind.PROJECTILE_PARRIED),
		"hurt_cues": run.cue_count(SimCue.Kind.PLAYER_HURT),
		"flying": flying,
		"spawn_cues": run.cue_count(SimCue.Kind.ENEMY_SPAWNED),
		"hit_cues": run.cue_count(SimCue.Kind.ENEMY_HIT),
		"ultimate_cues": run.cue_count(SimCue.Kind.ULTIMATE_STARTED),
		"beat_cues": run.cue_count(SimCue.Kind.MAELSTROM_BEAT),
		"burst_cues": run.cue_count(SimCue.Kind.MAELSTROM_BURST),
		"skewer_launch_cues": run.cue_count(SimCue.Kind.SKEWER_LAUNCHED),
		"skewer_release_cues": run.cue_count(SimCue.Kind.SKEWER_RELEASED),
		"colossus_slam_cues": run.cue_count(SimCue.Kind.COLOSSUS_SLAM),
		"field_created_cues": run.cue_count(SimCue.Kind.FIELD_CREATED),
		"field_pulse_cues": run.cue_count(SimCue.Kind.FIELD_PULSED),
		"orbs_cleared": run.projectiles_cleared,
		"fields": run.fields.map(func(field: FieldState) -> String: return "%s:%.3f:%.3f:%.3f:%.3f" % [field.element, field.position.x, field.position.y, field.life, field.tick_left]),
		"refused_cues": run.cue_count(SimCue.Kind.ULTIMATE_REFUSED),
		"frozen_cues": run.cue_count(SimCue.Kind.ENEMY_FROZEN),
		"shatter_cues": run.cue_count(SimCue.Kind.ENEMY_SHATTERED),
		"spread_cues": run.cue_count(SimCue.Kind.FIRE_SPREAD),
		"condition_damage_cues": run.cue_count(SimCue.Kind.CONDITION_DAMAGE),
		"ultimate_cooldowns": _ultimate_state(run),
		"sword_phases": run.snapshot()["sword_phases"],
		"alive": alive,
	}


static func _ultimate_state(run: GameRun) -> Array[String]:
	var shown: Array[String] = []
	for sword: SwordState in run.swords:
		shown.append("%d:%.3f:%.3f,%.3f:%.3f:%.3f" % [sword.phase, sword.ultimate_cooldown_left, sword.position.x, sword.position.y, sword.altitude, sword.fall_speed])
	return shown


## False when the run was started with `--skip-probes`, or `--fail-fast` has already stopped at a
## failure: the render-rate checks (the scenario played in process, and each probe process) are
## then not run at all.
static func probes_enabled() -> bool:
	return not OS.get_cmdline_user_args().has("--skip-probes") and OS.get_environment(STOPPED_ENV) != "1"
