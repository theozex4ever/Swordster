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
## One sword visual per dropped sword lying in the arena (the same replaceable scene as the equipped ones).
var _pickup_visuals: Dictionary = {}
var _effects: EffectsLayer = EffectsLayer.new()


func _ready() -> void:
	_effects.z_index = 5
	add_child(_effects)


func configure(sword: PackedScene, enemy: PackedScene) -> void:
	sword_scene = sword
	enemy_scene = enemy


## Number of live entity visuals (checks use it to prove nothing leaks). Dropped swords have visuals of their own
## (`pickup_visual_count`) and are not counted here.
func visual_count() -> int:
	return _sword_visuals.size() + _enemy_visuals.size()


func pickup_visual_count() -> int:
	return _pickup_visuals.size()


func sync(run: GameRun) -> void:
	_sync_swords(run)
	_sync_pickups(run)
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
	for visual: Node in _pickup_visuals.values():
		visual.queue_free()
	_sword_visuals.clear()
	_enemy_visuals.clear()
	_pickup_visuals.clear()
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
		visual.apply_altitude(sword.altitude)
		visual.apply_flash(sword.flash)
		visual.apply_pose(sword.position, sword.angle, sword.phase)
		if fresh:
			visual.snap()
	_drop_missing(_sword_visuals, live)


## A dropped sword hangs point-down above its shadow, bobbing and swaying (the prototype's `draw_pickup`: height 0.6 blade lengths
## plus 3 px of bob, a slow 0.08 rad sway), each on its own phase so a pile of drops does not move in lockstep; hidden on
## the off beats of its expiry blink. The phase is cosmetic and comes from the pickup's serial, never from the run's stream.
func _sync_pickups(run: GameRun) -> void:
	var live: Dictionary = {}
	for pickup: PickupState in run.pickups:
		var key: int = pickup.get_instance_id()
		live[key] = true
		var visual: SwordVisual = _pickup_visuals.get(key)
		var fresh: bool = visual == null
		if fresh:
			visual = sword_scene.instantiate() as SwordVisual
			add_child(visual)
			visual.setup(pickup.spec)
			_pickup_visuals[key] = visual
		var phase: float = pickup.age + float(pickup.serial) * 1.7
		visual.apply_hover(SwordDefs.length_of(pickup.spec) * 0.6 + sin(phase * 3.0) * 3.0)
		visual.apply_pose(pickup.position, PI / 2.0 + sin(phase * 1.3) * 0.08, SwordState.Phase.IDLE)
		visual.visible = not pickup.blink_hidden()
		if fresh:
			visual.snap()
	_drop_missing(_pickup_visuals, live)


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
			visual.apply_armed(enemy.armed)
			_enemy_visuals[key] = visual
		visual.apply_pose(enemy.position, enemy.facing, enemy.flash, enemy.squash, enemy.hp / enemy.max_hp, enemy.stun > 0.0, enemy.telegraph())
		visual.apply_conditions(enemy.conditions.view())
		if fresh:
			visual.snap()
	_drop_missing(_enemy_visuals, live)


func _drop_missing(visuals: Dictionary, live: Dictionary) -> void:
	for key: int in visuals.keys():
		if not live.has(key):
			(visuals[key] as Node).queue_free()
			visuals.erase(key)
