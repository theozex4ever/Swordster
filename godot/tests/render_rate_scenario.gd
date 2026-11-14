class_name RenderRateScenario
extends RefCounted
## One scripted crowd fight shared by the render-rate checks: the same scenario,
## the same commands at the same simulation ticks, observed through a digest
## that must come out identical however the frames around those ticks are cut.
## The probe (`frame_rate_probe.gd`) plays it through the real Main scene under
## the engine's own fixed-step loop at different frame rates; the checks also
## play it with bare `GameRun.step()` calls.

const REFERENCE_PATH: String = "res://tests/reference/crowd_and_walls.json"
const TOTAL_TICKS: int = 900
## Simulation ticks (ticks already completed) before which each command is issued.
const SHOVE_TICKS: Array[int] = [0, 200, 420, 520, 560, 640, 700]
const DASH_TICK: int = 500


## The crowd pinned against the east wall (the reference's composite
## formation) plus the crowd encounter's own wave arriving later, with the
## three-Fang fixture loadout defending a stationary player.
static func scenario() -> RunScenario:
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


## Commands to issue once `completed_ticks` ticks have run.
static func commands_at(completed_ticks: int) -> Array[GameCommand]:
	var commands: Array[GameCommand] = []
	if completed_ticks in SHOVE_TICKS:
		commands.append(GameCommand.dev_shove())
	if completed_ticks == DASH_TICK:
		commands.append(GameCommand.dash())
	return commands


## Plays the whole script with bare simulation steps.
static func play_headless() -> Dictionary:
	var run: GameRun = GameRun.new(scenario())
	while run.tick < TOTAL_TICKS:
		for command: GameCommand in commands_at(run.tick):
			run.apply(command)
		run.step()
		run.take_cues()
	return digest(run)


## Everything that must not depend on frame rate, as plain values.
static func digest(run: GameRun) -> Dictionary:
	var alive: Array[String] = []
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
		"spawn_cues": run.cue_count(SimCue.Kind.ENEMY_SPAWNED),
		"alive": alive,
	}
