class_name WaveDirector
extends RefCounted
## Wave schedule and spawn telegraphs (game/main.py `start_wave`, `update_waves`, `spawn_point`). The normal run plays the
## prototype's own waves, one after another until the player dies (`RunScenario.generated_waves`: the composition, its unlocks
## and `WaveDefs`' formulas; `arm_waves`: the arming rule of issue #17). The earlier slices' fixtures keep what they named: a husk
## count or an explicit composition, unarmed, for as many waves as the scenario asks (`wave_count`). A wave is complete only when
## its queue, its telegraphed markers and its living enemies are all gone; nothing caps how many arrive.

const CLEARED_BREAK: float = 3.2
const CLEARED_SLOWMO: float = 0.7
const CLEARED_SLOWMO_SCALE: float = 0.3

var wave: int = 0
var in_wave: bool = false
var break_left: float = 0.0
var queue: Array[StringName] = []
## The sword each queued enemy will carry, parallel to `queue` (null: unarmed). Rolled when the wave starts, as in
## the prototype's `spawn_queue` of (kind, armed).
var queue_armed: Array[SwordSpec] = []
var spawn_timer: float = 0.0
var markers: Array[SpawnMarker] = []
## True once the scenario's last wave has been cleared.
var survived: bool = false

var _enabled: bool = true
var _wave_count: int = 1
var _generated: bool = false
var _husk_count: int = -1
var _wave_kinds: Array[StringName] = []
var _speed_jitter: bool = true
var _arm_waves: bool = false


func _init(scenario: RunScenario) -> void:
	_enabled = scenario.waves_enabled
	_wave_count = scenario.wave_count
	_generated = scenario.generated_waves
	_husk_count = scenario.husk_count
	_wave_kinds = scenario.wave_kinds
	_speed_jitter = scenario.enemy_speed_jitter
	_arm_waves = scenario.arm_waves
	break_left = scenario.first_wave_delay


func update(run: GameRun, dt: float) -> void:
	if not _enabled or run.dead:
		return
	if not queue.is_empty():
		spawn_timer -= dt
		if spawn_timer <= 0.0:
			var kind: StringName = queue.pop_front()
			var carried: SwordSpec = queue_armed.pop_front()
			markers.append(SpawnMarker.make(kind, _spawn_point(run), carried))
			spawn_timer = WaveDefs.spawn_interval(wave)
	for marker: SpawnMarker in markers:
		marker.remaining -= dt
		if marker.remaining <= 0.0:
			var factor: float = (run.rng.randf_range(0.9, 1.12) if _speed_jitter else 1.0) * run.scenario.enemy_speed_scale
			var phase: float = run.rng.randf_range(0.0, 10.0)
			var cooldown: float = 0.0
			if marker.kind == EnemyDefs.SPITTER:
				cooldown = run.rng.randf_range(EnemyDefs.SPITTER_FIRST_COOLDOWN_MIN, EnemyDefs.SPITTER_FIRST_COOLDOWN_MAX)
			var enemy: EnemyState = EnemyState.make(marker.kind, marker.position, wave, factor, run.next_serial(), phase, cooldown, marker.armed)
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
		run.set_banner("WAVE CLEARED", WaveDefs.CLEARED_BANNER_SECONDS, WaveDefs.CLEARED_BANNER_SUB if _arm_waves else "")
		run.add_cue(SimCue.make(SimCue.Kind.WAVE_CLEARED, run.position))
		if _wave_count > 0 and wave >= _wave_count:
			survived = true
	if not in_wave and not survived:
		break_left -= dt
		if break_left <= 0.0:
			_start_wave(run)


func _start_wave(run: GameRun) -> void:
	wave += 1
	queue.clear()
	queue_armed.clear()
	var fixed_kinds: Array[StringName] = []
	if not _generated:
		if not _wave_kinds.is_empty():
			fixed_kinds.append_array(_wave_kinds)
		else:
			var count: int = _husk_count if _husk_count >= 0 else WaveDefs.enemy_count(wave)
			for i: int in count:
				fixed_kinds.append(EnemyDefs.HUSK)
	var total: int = WaveDefs.enemy_count(wave) if _generated else fixed_kinds.size()
	# Each enemy of the wave, in order: its kind (a generated wave draws it from the weighted pool of the wave) and then
	# whether it carries a sword (prototype `start_wave`). A run that does not arm its waves (every earlier fixture) draws nothing
	# from the gameplay stream for arming, so it plays exactly as before.
	for index: int in total:
		var kind: StringName = WaveDefs.roll_kind(run.rng, wave) if _generated else fixed_kinds[index]
		queue.append(kind)
		queue_armed.append(LootDefs.roll_armed(run.rng, kind, wave, index) if _arm_waves else null)
	spawn_timer = WaveDefs.FIRST_SPAWN_DELAY
	in_wave = true
	run.set_banner("WAVE %d" % wave, WaveDefs.WAVE_BANNER_SECONDS, WaveDefs.WAVE_BANNER_SUB if _arm_waves else "")
	run.add_cue(SimCue.make(SimCue.Kind.WAVE_STARTED, run.position))


func _spawn_point(run: GameRun) -> Vector2:
	var rng: RandomNumberGenerator = run.rng
	var next_draw: Callable = func() -> Vector2:
		var angle: float = rng.randf_range(0.0, TAU)
		return Vector2(angle, rng.randf_range(WaveDefs.SPAWN_MIN_DISTANCE, WaveDefs.SPAWN_MAX_DISTANCE))
	return WaveDefs.spawn_point(run.position, GameRun.WORLD, next_draw)
