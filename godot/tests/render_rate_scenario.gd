class_name RenderRateScenario
extends RefCounted
## Scripted fights shared by the render-rate checks: the same scenario, the same
## commands at the same simulation ticks, observed through a digest that must
## come out identical however the frames around those ticks are cut. Two
## scripts: "crowd" (issue #9: a shoved crowd against the wall) and "spitters"
## (issue #10: orbs fired, parried and dodged). The probe (`frame_rate_probe.gd`)
## plays one through the real Main scene under the engine's own fixed-step loop
## at different frame rates; the checks also play it with bare `GameRun.step()`
## calls.

const REFERENCE_PATH: String = "res://tests/reference/crowd_and_walls.json"
const CROWD: String = "crowd"
const SPITTERS: String = "spitters"
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


## Commands to issue once `completed_ticks` ticks have run.
static func commands_at(completed_ticks: int, name: String = CROWD) -> Array[GameCommand]:
	var commands: Array[GameCommand] = []
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
		"alive": alive,
	}
