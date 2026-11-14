class_name WaveDirector
extends RefCounted
## Wave schedule and spawn telegraphs (game/main.py `start_wave`,
## `update_waves`, `spawn_point`). Waves are husk-only unless a scenario names
## an explicit composition (the crowd encounter fixture); composition unlocks,
## armed enemies and sword drops arrive with the later slices, and the scenario
## normally asks for exactly one wave.

const SPAWN_MIN_DISTANCE: float = 420.0
const SPAWN_MAX_DISTANCE: float = 720.0
const SPAWN_NEAR_LIMIT: float = 320.0
const SPAWN_EDGE_MARGIN: float = 50.0
const FIRST_SPAWN_DELAY: float = 0.3
const CLEARED_BREAK: float = 3.2
const CLEARED_SLOWMO: float = 0.7
const CLEARED_SLOWMO_SCALE: float = 0.3
const WAVE_BANNER: float = 2.4
const CLEARED_BANNER: float = 2.6

var wave: int = 0
var in_wave: bool = false
var break_left: float = 0.0
var queue: Array[StringName] = []
var spawn_timer: float = 0.0
var markers: Array[SpawnMarker] = []
## True once the scenario's last wave has been cleared.
var survived: bool = false

var _enabled: bool = true
var _wave_count: int = 1
var _husk_count: int = -1
var _wave_kinds: Array[StringName] = []
var _speed_jitter: bool = true


func _init(scenario: RunScenario) -> void:
	_enabled = scenario.waves_enabled
	_wave_count = scenario.wave_count
	_husk_count = scenario.husk_count
	_wave_kinds = scenario.wave_kinds
	_speed_jitter = scenario.enemy_speed_jitter
	break_left = scenario.first_wave_delay


func update(run: GameRun, dt: float) -> void:
	if not _enabled or run.dead:
		return
	if not queue.is_empty():
		spawn_timer -= dt
		if spawn_timer <= 0.0:
			var kind: StringName = queue.pop_front()
			markers.append(SpawnMarker.make(kind, _spawn_point(run)))
			spawn_timer = maxf(0.12, 0.42 - float(wave) * 0.02)
	for marker: SpawnMarker in markers:
		marker.remaining -= dt
		if marker.remaining <= 0.0:
			var factor: float = (run.rng.randf_range(0.9, 1.12) if _speed_jitter else 1.0) * run.scenario.enemy_speed_scale
			var phase: float = run.rng.randf_range(0.0, 10.0)
			var enemy: EnemyState = EnemyState.make(marker.kind, marker.position, wave, factor, run.next_serial(), phase)
			run.enemies.append(enemy)
			run.add_cue(SimCue.make(SimCue.Kind.ENEMY_SPAWNED, marker.position))
	var waiting: Array[SpawnMarker] = []
	for marker: SpawnMarker in markers:
		if marker.remaining > 0.0:
			waiting.append(marker)
	markers = waiting
	if in_wave and queue.is_empty() and markers.is_empty() and run.enemies.is_empty():
		in_wave = false
		break_left = CLEARED_BREAK
		run.slowmo = CLEARED_SLOWMO
		run.slowmo_scale = CLEARED_SLOWMO_SCALE
		run.set_banner("WAVE CLEARED", CLEARED_BANNER)
		run.add_cue(SimCue.make(SimCue.Kind.WAVE_CLEARED, run.position))
		if wave >= _wave_count:
			survived = true
	if not in_wave and not survived:
		break_left -= dt
		if break_left <= 0.0:
			_start_wave(run)


func _start_wave(run: GameRun) -> void:
	wave += 1
	queue.clear()
	if not _wave_kinds.is_empty():
		queue.append_array(_wave_kinds)
	else:
		var count: int = _husk_count if _husk_count >= 0 else 5 + wave * 3
		for i: int in count:
			queue.append(EnemyDefs.HUSK)
	spawn_timer = FIRST_SPAWN_DELAY
	in_wave = true
	run.set_banner("WAVE %d" % wave, WAVE_BANNER)
	run.add_cue(SimCue.make(SimCue.Kind.WAVE_STARTED, run.position))


func _spawn_point(run: GameRun) -> Vector2:
	var inner: Rect2 = GameRun.WORLD.grow(-SPAWN_EDGE_MARGIN)
	var point: Vector2 = Vector2.ZERO
	for attempt: int in 12:
		point = run.position + SimMath.polar(run.rng.randf_range(0.0, TAU), run.rng.randf_range(SPAWN_MIN_DISTANCE, SPAWN_MAX_DISTANCE))
		point = point.clamp(inner.position, inner.end)
		if (point - run.position).length() > SPAWN_NEAR_LIMIT:
			return point
	return point
