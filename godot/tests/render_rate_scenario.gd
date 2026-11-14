class_name RenderRateScenario
extends RefCounted
## Scripted fights shared by the render-rate checks: the same scenario, the same
## commands at the same simulation ticks, observed through a digest that must
## come out identical however the frames around those ticks are cut. Three
## scripts: "crowd" (issue #9: a shoved crowd against the wall), "spitters"
## (issue #10: orbs fired, parried and dodged) and "flurry" (issue #12: Viper
## Flurry commanded from every sword slot, repeated and refused). The probe (`frame_rate_probe.gd`)
## plays one through the real Main scene under the engine's own fixed-step loop
## at different frame rates; the checks also play it with bare `GameRun.step()`
## calls.

const REFERENCE_PATH: String = "res://tests/reference/crowd_and_walls.json"
const CROWD: String = "crowd"
const SPITTERS: String = "spitters"
const FLURRY: String = "flurry"
const TOTAL_TICKS: int = 900
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
	var scenario: RunScenario = RunScenario.new()
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
	var scenario: RunScenario = RunScenario.new()
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


## Commands to issue once `completed_ticks` ticks have run.
static func commands_at(completed_ticks: int, name: String = CROWD) -> Array[GameCommand]:
	var commands: Array[GameCommand] = []
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
		alive.append("%d:%s:%.3f:%.3f:%.3f" % [enemy.serial, enemy.kind, enemy.position.x, enemy.position.y, enemy.hp])
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
		"refused_cues": run.cue_count(SimCue.Kind.ULTIMATE_REFUSED),
		"ultimate_cooldowns": _ultimate_state(run),
		"sword_phases": run.snapshot()["sword_phases"],
		"alive": alive,
	}


static func _ultimate_state(run: GameRun) -> Array[String]:
	var shown: Array[String] = []
	for sword: SwordState in run.swords:
		shown.append("%d:%.3f:%.3f,%.3f" % [sword.phase, sword.ultimate_cooldown_left, sword.position.x, sword.position.y])
	return shown
