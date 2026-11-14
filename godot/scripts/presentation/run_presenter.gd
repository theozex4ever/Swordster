class_name RunPresenter
extends Node2D
## Keeps one replaceable visual child per sword and per enemy in step with the
## run's logical state, plus the cosmetic effects layer. The run never looks at
## any of it. Visuals appear when the run creates an entity and are freed when
## it leaves the run (death, restart), so nothing outlives its run.

var sword_scene: PackedScene
var enemy_scene: PackedScene

var _sword_visuals: Dictionary = {}
var _enemy_visuals: Dictionary = {}
var _effects: EffectsLayer = EffectsLayer.new()


func _ready() -> void:
	_effects.z_index = 5
	add_child(_effects)


func configure(sword: PackedScene, enemy: PackedScene) -> void:
	sword_scene = sword
	enemy_scene = enemy


## Number of live entity visuals (checks use it to prove nothing leaks).
func visual_count() -> int:
	return _sword_visuals.size() + _enemy_visuals.size()


func sync(run: GameRun) -> void:
	_sync_swords(run)
	_sync_enemies(run)
	_effects.sync(run)


func apply_cues(cues: Array[SimCue]) -> void:
	for cue: SimCue in cues:
		_effects.apply_cue(cue)


func reset() -> void:
	for visual: Node in _sword_visuals.values():
		visual.queue_free()
	for visual: Node in _enemy_visuals.values():
		visual.queue_free()
	_sword_visuals.clear()
	_enemy_visuals.clear()
	_effects.clear()


func _sync_swords(run: GameRun) -> void:
	var live: Dictionary = {}
	for sword: SwordState in run.swords:
		var key: int = sword.get_instance_id()
		live[key] = true
		var visual: SwordVisual = _sword_visuals.get(key)
		var fresh: bool = visual == null
		if fresh:
			visual = sword_scene.instantiate() as SwordVisual
			add_child(visual)
			visual.setup(sword.spec)
			_sword_visuals[key] = visual
		visual.apply_pose(sword.position, sword.angle, sword.phase)
		if fresh:
			visual.snap()
	_drop_missing(_sword_visuals, live)


func _sync_enemies(run: GameRun) -> void:
	var live: Dictionary = {}
	for enemy: EnemyState in run.enemies:
		var key: int = enemy.get_instance_id()
		live[key] = true
		var visual: EnemyVisual = _enemy_visuals.get(key)
		var fresh: bool = visual == null
		if fresh:
			visual = enemy_scene.instantiate() as EnemyVisual
			add_child(visual)
			visual.setup(enemy.kind)
			_enemy_visuals[key] = visual
		visual.apply_pose(enemy.position, enemy.facing, enemy.flash, enemy.squash, enemy.hp / enemy.max_hp, enemy.stun > 0.0, enemy.telegraph())
		if fresh:
			visual.snap()
	_drop_missing(_enemy_visuals, live)


func _drop_missing(visuals: Dictionary, live: Dictionary) -> void:
	for key: int in visuals.keys():
		if not live.has(key):
			(visuals[key] as Node).queue_free()
			visuals.erase(key)
