class_name EffectsLayer
extends Node2D
## Cosmetic world effects: spawn telegraphs (tinted and sized by enemy type),
## healing motes, enemy projectiles, hit rings, damage numbers, crowd-collision
## sparks, wall-slam bursts, dash afterimages and parry sparks. A parry reads
## differently from a hit on purpose: green sparks and a "PARRY" tag where the
## orb died, with no number; a hit on an enemy is a white ring and a damage
## number, a hit on the player a red ring and "-8". A sword's ultimate announces itself with a
## ring where the sword left, a ring closing on the area it landed in and its name over the
## player; while it runs the area is outlined and each dart leaves a streak. Conditions
## shed their own particles (rising embers on a burning enemy, green drips on a poisoned
## one, ice motes on a chilled one) and cue bursts: FROZEN when an enemy freezes, a shatter
## when it dies frozen, a fire ring when a burning enemy dies, a coloured number for each
## damage-over-time landing. A Warden's sweep is telegraphed during its windup (the arc it will
## cut) and leaves a fading fan along the arc it cut; its Maelstrom shows the reach of its blades,
## the range it pulls from, spinning arcs, a ring at every beat and a burst at the end. A Pike's thrust
## is telegraphed along its line during the windup; a Skewer shows its aim line while it aims, rings
## the enemies it carries and ends in a burst where it lets go. A Colossus telegraphs the ring its slam will
## crush while it winds up and falls, a slam and a Cataclysm end in rings, sparks and smoke, and the
## elemental ground Cataclysm leaves is drawn as a pulsing ellipse of its element until it fades, shedding
## the element's particles. Purely visual: it reads the
## run's state and cues, owns its own random stream and never influences gameplay.

const MAX_EFFECTS: int = 160

var _rings: Array[Dictionary] = []
var _texts: Array[Dictionary] = []
var _sparks: Array[Dictionary] = []
## Streaks left by a sword darting during its ultimate, and where each sword was drawn last.
var _streaks: Array[Dictionary] = []
var _last_sword_at: Dictionary = {}
## Element particles (embers, drips, ice motes): pos, vel, life, max, color, size.
var _embers: Array[Dictionary] = []
## The fading fan a Warden's sweep leaves (one wedge per tick), and the heading each sweeping
## sword was drawn at last tick.
var _wedges: Array[Dictionary] = []
var _last_sweep_angle: Dictionary = {}
## How many times each kind of Warden or Pike effect has been drawn (`telegraph`, `fan`, `maelstrom`,
## `thrust_telegraph`, `skewer_aim`, `skewer_carry`, `slam_telegraph`, `cataclysm_ring`, `field`);
## checks read it to prove the layer really draws what the sword's state asks for.
var draw_counts: Dictionary[StringName, int] = {}
var _run: GameRun
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func clear() -> void:
	_rings.clear()
	_texts.clear()
	_sparks.clear()
	_streaks.clear()
	_embers.clear()
	_wedges.clear()
	_last_sweep_angle.clear()
	_last_sword_at.clear()
	queue_redraw()


## Called once per fixed tick after the run stepped.
func sync(run: GameRun) -> void:
	_run = run
	var dt: float = GameRun.TICK_DT
	if not run.paused:
		for ring: Dictionary in _rings:
			ring["life"] = float(ring["life"]) - dt
		for text: Dictionary in _texts:
			text["life"] = float(text["life"]) - dt
			text["pos"] = Vector2(text["pos"]) + Vector2(text["vel"]) * dt
			text["vel"] = Vector2(text["vel"]) * exp(-dt * 4.0)
		for spark: Dictionary in _sparks:
			spark["life"] = float(spark["life"]) - dt
			spark["pos"] = Vector2(spark["pos"]) + Vector2(spark["vel"]) * dt
			spark["vel"] = Vector2(spark["vel"]) * exp(-dt * 7.0)
		for streak: Dictionary in _streaks:
			streak["life"] = float(streak["life"]) - dt
		_streaks = _streaks.filter(func(st: Dictionary) -> bool: return float(st["life"]) > 0.0)
		for wedge: Dictionary in _wedges:
			wedge["life"] = float(wedge["life"]) - dt
		_wedges = _wedges.filter(func(wd: Dictionary) -> bool: return float(wd["life"]) > 0.0)
		_add_sweep_wedges(run)
		for ember: Dictionary in _embers:
			ember["life"] = float(ember["life"]) - dt
			ember["pos"] = Vector2(ember["pos"]) + Vector2(ember["vel"]) * dt
		_embers = _embers.filter(func(em: Dictionary) -> bool: return float(em["life"]) > 0.0)
		_add_dart_streaks(run)
		_add_condition_particles(run, dt)
		_add_field_particles(run, dt)
		_sparks = _sparks.filter(func(sp: Dictionary) -> bool: return float(sp["life"]) > 0.0)
		_rings = _rings.filter(func(r: Dictionary) -> bool: return float(r["life"]) > 0.0)
		_texts = _texts.filter(func(t: Dictionary) -> bool: return float(t["life"]) > 0.0)
		if run.dash_left > 0.0:
			_add_ring(run.position, GameRun.PLAYER_RADIUS * 0.6, GameRun.PLAYER_RADIUS * 1.2, 0.22, Color(0.35, 0.65, 0.85, 0.7), 2.0)
	queue_redraw()


## A sword in its ultimate leaves a short bright streak along every move.
func _add_dart_streaks(run: GameRun) -> void:
	for sword: SwordState in run.swords:
		var key: int = sword.get_instance_id()
		var streaking: bool = sword.phase == SwordState.Phase.ULTIMATE or (sword.phase == SwordState.Phase.STRIKE and sword.spec.type_id == SwordDefs.PIKE)
		if streaking and _last_sword_at.has(key):
			var from: Vector2 = _last_sword_at[key]
			if from.distance_to(sword.position) > 12.0 and _streaks.size() < MAX_EFFECTS:
				_streaks.append({"from": from, "to": sword.position, "life": 0.18, "max": 0.18, "color": _sword_color(sword.spec)})
		_last_sword_at[key] = sword.position


## While a Warden sweeps, every tick adds the wedge between last tick's heading and this one.
func _add_sweep_wedges(run: GameRun) -> void:
	for sword: SwordState in run.swords:
		if sword.spec.type_id != SwordDefs.WARDEN:
			continue
		var key: int = sword.get_instance_id()
		if sword.phase == SwordState.Phase.STRIKE:
			var from_angle: float = _last_sweep_angle.get(key, sword.sweep_from)
			if absf(sword.angle - from_angle) > 0.001 and _wedges.size() < MAX_EFFECTS:
				_wedges.append({"pivot": sword.sweep_pivot, "from": from_angle, "to": sword.angle, "life": 0.28, "max": 0.28, "color": _sword_color(sword.spec), "length": sword.length})
			_last_sweep_angle[key] = sword.angle
		else:
			_last_sweep_angle.erase(key)


static func _sword_color(spec: SwordSpec) -> Color:
	return element_color(spec.element)


static func element_color(element: StringName) -> Color:
	return PlaceholderSwordVisual.ELEMENT_COLORS.get(element, Color.WHITE)


## Particles an enemy sheds while it burns (rises), is poisoned (drips; more stacks, more
## drips) or is chilled (drifts), at the prototype's rates. Drawn from this layer's own
## random stream; nothing here reaches the run.
func _add_condition_particles(run: GameRun, dt: float) -> void:
	for enemy: EnemyState in run.enemies:
		var conditions: EnemyConditions = enemy.conditions
		if conditions.is_burning() and _rng.randf() < dt * 14.0:
			_add_ember(enemy.position, enemy.radius * 0.8, Vector2(_rng.randf_range(-25.0, 25.0), _rng.randf_range(-150.0, -70.0)), _rng.randf_range(0.3, 0.55), ConditionDefs.FIRE, _rng.randf_range(1.5, 3.0), _rng.randf())
		if conditions.poison > 0.0 and _rng.randf() < dt * float(3 + 2 * conditions.poison_stacks):
			_add_ember(enemy.position, enemy.radius * 0.8, Vector2(_rng.randf_range(-10.0, 10.0), _rng.randf_range(-45.0, -15.0)), _rng.randf_range(0.5, 0.9), ConditionDefs.POISON, _rng.randf_range(1.5, 3.5), 0.0)
		if conditions.is_chilled() and _rng.randf() < dt * 5.0:
			_add_ember(enemy.position, enemy.radius, SimMath.polar(_rng.randf_range(0.0, TAU), _rng.randf_range(10.0, 50.0)), _rng.randf_range(0.4, 0.7), ConditionDefs.ICE, _rng.randf_range(1.0, 2.5), 0.5)


## One element particle near `at` (within `spread` px), tinted by the element and
## `mix_white` toward white (fire: toward yellow-white).
func _add_ember(at: Vector2, spread: float, velocity: Vector2, life: float, element: StringName, size: float, mix_white: float) -> void:
	if _embers.size() >= MAX_EFFECTS:
		return
	var tint: Color = element_color(element)
	tint = tint.lerp(Color(1.0, 0.86, 0.35) if element == ConditionDefs.FIRE else Color.WHITE, mix_white)
	var origin: Vector2 = at + SimMath.polar(_rng.randf_range(0.0, TAU), _rng.randf_range(0.0, spread))
	_embers.append({"pos": origin, "vel": velocity, "life": life, "max": life, "color": tint, "size": size})


## Particles a field sheds (prototype `update_fields`: `dt x radius x 0.12` chances a tick, each at a random
## point of the ellipse the field is drawn as), in its element's look. Cosmetic random stream.
func _add_field_particles(run: GameRun, dt: float) -> void:
	for field: FieldState in run.fields:
		if _rng.randf() < dt * field.radius * 0.12:
			var angle: float = _rng.randf_range(0.0, TAU)
			var spot: Vector2 = field.position + Vector2(cos(angle), sin(angle) * 0.6) * _rng.randf_range(0.0, field.radius)
			match field.element:
				ConditionDefs.FIRE:
					_add_ember(spot, 4.0, Vector2(_rng.randf_range(-25.0, 25.0), _rng.randf_range(-150.0, -70.0)), _rng.randf_range(0.3, 0.55), field.element, _rng.randf_range(1.5, 3.0), _rng.randf())
				ConditionDefs.ICE:
					_add_ember(spot, 4.0, SimMath.polar(_rng.randf_range(0.0, TAU), _rng.randf_range(10.0, 50.0)), _rng.randf_range(0.4, 0.7), field.element, _rng.randf_range(1.0, 2.5), 0.5)
				_:
					_add_ember(spot, 4.0, Vector2(_rng.randf_range(-10.0, 10.0), _rng.randf_range(-45.0, -15.0)), _rng.randf_range(0.5, 0.9), field.element, _rng.randf_range(1.5, 3.5), 0.0)


func apply_cue(cue: SimCue) -> void:
	match cue.kind:
		SimCue.Kind.ENEMY_HIT:
			_add_ring(cue.position, 10.0, 30.0 + float(cue.amount) * 0.4, 0.18, Color(1.0, 0.95, 0.8, 0.9), 2.0)
			var jitter: Vector2 = Vector2(_rng.randf_range(-10.0, 10.0), -22.0)
			var label: String = "%d%s" % [cue.amount, "!" if cue.critical else ""]
			var number: Color = Color(1.0, 0.88, 0.35) if cue.critical else Color.WHITE
			if cue.element == ConditionDefs.ICE:
				number = Color(0.78, 0.94, 1.0)
			_add_text(cue.position + jitter, label, number, 1.0 if cue.critical else 0.75, 28 if cue.critical else 22)
		SimCue.Kind.ENEMY_FROZEN:
			_add_ring(cue.position, 16.0, 40.0, 0.3, Color(element_color(ConditionDefs.ICE), 0.95), 3.0)
			_add_text(cue.position + Vector2(0.0, -40.0), "FROZEN", element_color(ConditionDefs.ICE), 0.7, 22)
			for i: int in 10:
				_add_ember(cue.position, 16.0, SimMath.polar(_rng.randf_range(0.0, TAU), _rng.randf_range(10.0, 50.0)), _rng.randf_range(0.4, 0.7), ConditionDefs.ICE, _rng.randf_range(1.0, 2.5), 0.5)
		SimCue.Kind.ENEMY_SHATTERED:
			for i: int in 18:
				_add_ember(cue.position, 16.0, SimMath.polar(_rng.randf_range(0.0, TAU), _rng.randf_range(60.0, 260.0)), _rng.randf_range(0.4, 0.7), ConditionDefs.ICE, _rng.randf_range(1.0, 2.5), 0.5)
		SimCue.Kind.FIRE_SPREAD:
			_add_ring(cue.position, 16.0, 16.0 + ConditionDefs.SPREAD_REACH + 20.0, 0.3, Color(element_color(ConditionDefs.FIRE), 0.95), 3.0)
			for i: int in 14:
				_add_ember(cue.position, 16.0, Vector2(_rng.randf_range(-25.0, 25.0), _rng.randf_range(-150.0, -70.0)), _rng.randf_range(0.3, 0.55), ConditionDefs.FIRE, _rng.randf_range(1.5, 3.0), _rng.randf())
		SimCue.Kind.CONDITION_DAMAGE:
			_add_text(cue.position + Vector2(_rng.randf_range(-12.0, 12.0), -18.0), str(cue.amount), element_color(cue.element), 0.6, 20)
		SimCue.Kind.ENEMY_KILLED:
			_add_ring(cue.position, 12.0, 52.0, 0.3, Color(0.9, 0.5, 0.6, 0.9), 3.0)
		SimCue.Kind.ENEMY_SPAWNED:
			_add_ring(cue.position, 6.0, 50.0, 0.3, Color(0.78, 0.31, 0.47, 0.9), 2.0)
		SimCue.Kind.PLAYER_HURT:
			_add_ring(cue.position, 10.0, 60.0, 0.3, Color(1.0, 0.35, 0.35, 0.9), 3.0)
			_add_text(cue.position + Vector2(0.0, -30.0), "-%d" % cue.amount, Color(1.0, 0.35, 0.35), 0.8, 30)
		SimCue.Kind.PLAYER_DIED:
			_add_ring(cue.position, 10.0, 220.0, 0.8, Color(0.47, 0.86, 1.0, 0.9), 4.0)
		SimCue.Kind.DASH:
			_add_ring(cue.position, 10.0, 46.0, 0.25, Color(0.35, 0.65, 0.85, 0.8), 2.0)
		SimCue.Kind.BOWLED:
			_add_ring(cue.position, 6.0, 28.0, 0.16, Color(1.0, 0.86, 0.78, 0.9), 3.0)
			_add_text(cue.position + Vector2(_rng.randf_range(-8.0, 8.0), -18.0), "-%d" % cue.amount, Color(1.0, 0.86, 0.78), 0.5, 18)
		SimCue.Kind.WALL_SLAM:
			_add_ring(cue.position, 12.0, 70.0, 0.3, Color(1.0, 0.55, 0.38, 0.95), 4.0)
			_add_text(cue.position + Vector2(0.0, -30.0), "SLAM %d" % cue.amount, Color(1.0, 0.59, 0.47), 0.8, 26)
		SimCue.Kind.SHOVE:
			_add_ring(cue.position, 20.0, GameRun.DEV_SHOVE_RADIUS, 0.35, Color(0.75, 0.85, 1.0, 0.7), 3.0)
		SimCue.Kind.PROJECTILE_FIRED:
			_add_ring(cue.position, 3.0, 20.0, 0.14, Color(PlaceholderEnemyVisual.SPIT_GLOW, 0.8), 2.0)
		SimCue.Kind.PROJECTILE_PARRIED:
			_add_ring(cue.position, 4.0, 30.0, 0.2, Color(PlaceholderEnemyVisual.SPIT_GLOW, 0.95), 2.0)
			_add_ring(cue.position, 2.0, 16.0, 0.12, Color(1.0, 1.0, 0.92, 0.95), 3.0)
			for i: int in 10:
				var heading: float = cue.direction.angle() + _rng.randf_range(-1.1, 1.1)
				_add_spark(cue.position, SimMath.polar(heading, _rng.randf_range(150.0, 450.0)), _rng.randf_range(0.12, 0.28))
			_add_text(cue.position + Vector2(0.0, -20.0), "PARRY", PlaceholderEnemyVisual.SPIT_GLOW, 0.55, 20)
		SimCue.Kind.ULTIMATE_STARTED:
			_apply_ultimate_started(cue)
		SimCue.Kind.MAELSTROM_BEAT:
			var beat_tint: Color = element_color(cue.element)
			_add_ring(cue.position, cue.radius * 0.6, cue.radius, 0.2, Color(beat_tint, 0.9), 2.0)
		SimCue.Kind.MAELSTROM_BURST:
			var burst_tint: Color = element_color(cue.element).lerp(Color.WHITE, 0.4)
			_add_ring(cue.position, 20.0, cue.radius * 1.6, 0.4, Color(burst_tint, 0.95), 5.0)
			_add_ring(cue.position, 10.0, cue.radius, 0.25, Color(1.0, 1.0, 1.0, 0.8), 3.0)
			for i: int in 30:
				_add_spark(cue.position, SimMath.polar(_rng.randf_range(0.0, TAU), _rng.randf_range(300.0, 800.0)), _rng.randf_range(0.15, 0.4), burst_tint)
		SimCue.Kind.SKEWER_LAUNCHED:
			var launch_tint: Color = Color(1.0, 1.0, 1.0, 0.9)
			_add_ring(cue.position, 6.0, 44.0, 0.2, launch_tint, 3.0)
			for i: int in 8:
				_add_spark(cue.position, SimMath.polar(cue.direction.angle() + _rng.randf_range(-0.35, 0.35), _rng.randf_range(500.0, 1100.0)), _rng.randf_range(0.1, 0.25), Color(1.0, 1.0, 0.9))
		SimCue.Kind.SKEWER_RELEASED:
			_add_ring(cue.position, 10.0, 60.0 + float(cue.amount) * 8.0, 0.3, Color(1.0, 0.92, 0.7, 0.95), 4.0)
			var back: float = cue.direction.angle() + PI
			for i: int in 12 if cue.critical else 6:
				_add_spark(cue.position, SimMath.polar(back + _rng.randf_range(-0.9, 0.9), _rng.randf_range(200.0, 700.0)), _rng.randf_range(0.15, 0.35), Color(1.0, 0.85, 0.6))
			if cue.amount > 0:
				_add_text(cue.position + Vector2(0.0, -30.0), "%s x%d" % ["SLAM" if cue.critical else "FLUNG", cue.amount], Color(1.0, 0.92, 0.7), 0.7, 24)
		SimCue.Kind.COLOSSUS_SLAM:
			var slam_tint: Color = element_color(cue.element).lerp(Color.WHITE, 0.5)
			_add_ring(cue.position, 10.0, cue.radius * 1.35, 0.35, Color(slam_tint, 0.95), 6.0)
			_add_ring(cue.position, 6.0, cue.radius * 0.8, 0.22, Color(1.0, 1.0, 1.0, 0.9), 3.0)
			for i: int in 30:
				_add_spark(cue.position, SimMath.polar(_rng.randf_range(0.0, TAU), _rng.randf_range(200.0, 800.0)), _rng.randf_range(0.2, 0.5), slam_tint)
			if cue.critical:
				_add_text(cue.position + Vector2(0.0, -cue.radius * 0.35), "CATACLYSM", slam_tint, 0.9, 30)
		SimCue.Kind.FIELD_CREATED:
			_add_ring(cue.position, cue.radius * 0.6, cue.radius, 0.4, Color(element_color(cue.element), 0.9), 4.0)
		SimCue.Kind.FIELD_PULSED:
			if cue.amount > 0:
				_add_ring(cue.position, cue.radius * 0.9, cue.radius, 0.25, Color(element_color(cue.element), 0.45), 2.0)
		SimCue.Kind.ULTIMATE_REFUSED:
			if _run != null:
				_add_text(cue.position + Vector2(0.0, -46.0), "recharging %ds" % cue.amount, Color(0.62, 0.6, 0.78), 0.5, 22)
		_:
			pass


## The blink: a small ring where the sword was, a ring closing from the area's edge
## onto its centre where it landed, the sword's colour and the ultimate's name.
func _apply_ultimate_started(cue: SimCue) -> void:
	if _run == null or cue.amount < 0 or cue.amount >= _run.swords.size():
		return
	var sword: SwordState = _run.swords[cue.amount]
	var tint: Color = _sword_color(sword.spec)
	_add_ring(cue.origin, 4.0, 40.0, 0.25, Color(tint, 0.9), 2.0)
	if not SwordDefs.ultimate_is_shot(sword.spec.type_id):
		_add_ring(sword.ultimate_point, sword.ultimate_area_radius(), 10.0, 0.3, Color(tint, 0.95), 3.0)
	_add_text(_run.position + Vector2(0.0, -56.0), SwordDefs.ultimate_name(sword.spec.type_id).to_upper(), tint.lerp(Color.WHITE, 0.3), 1.0, 32)


func _add_ring(at: Vector2, r0: float, r1: float, life: float, color: Color, width: float) -> void:
	if _rings.size() < MAX_EFFECTS:
		_rings.append({"pos": at, "r0": r0, "r1": r1, "life": life, "max": life, "color": color, "width": width})


func _add_spark(at: Vector2, velocity: Vector2, life: float, color: Color = Color(0.85, 1.0, 0.65)) -> void:
	if _sparks.size() < MAX_EFFECTS:
		_sparks.append({"pos": at, "vel": velocity, "life": life, "max": life, "color": color})


func _add_text(at: Vector2, text: String, color: Color, life: float, size: int) -> void:
	if _texts.size() < MAX_EFFECTS:
		_texts.append({"pos": at, "vel": Vector2(0.0, -80.0), "life": life, "max": life, "text": text, "color": color, "size": size})


func _draw() -> void:
	if _run == null:
		return
	for marker: SpawnMarker in _run.director.markers:
		var u: float = 1.0 - clampf(marker.remaining / SpawnMarker.TELEGRAPH, 0.0, 1.0)
		var pulse: float = 0.5 + 0.5 * sin(u * 24.0)
		var tint: Color = PlaceholderEnemyVisual.color_of(marker.kind)
		var scale: float = PlaceholderEnemyVisual.visual_radius_of(marker.kind) / 16.0
		draw_arc(marker.position, (38.0 - 22.0 * u) * scale, 0.0, TAU, 32, Color(tint.r, tint.g, tint.b, 0.35 + 0.5 * u), 2.0 + pulse)
		draw_circle(marker.position, (5.0 + 6.0 * u) * scale, Color(tint.r, tint.g, tint.b, 0.25 + 0.4 * u))
	for mote: Mote in _run.motes:
		draw_circle(mote.position, 6.0, Color(0.4, 1.0, 0.8, 0.25))
		draw_circle(mote.position, 3.0, Color(0.75, 1.0, 0.92))
	for projectile: ProjectileState in _run.projectiles:
		_draw_projectile(projectile)
	for wedge: Dictionary in _wedges:
		draw_counts[&"fan"] = draw_counts.get(&"fan", 0) + 1
		var wedge_fade: float = clampf(float(wedge["life"]) / float(wedge["max"]), 0.0, 1.0)
		var span: float = float(wedge["length"]) * (SwordDefs.WARDEN_TIP - SwordDefs.WARDEN_GUARD)
		var mid: float = float(wedge["length"]) * (SwordDefs.WARDEN_TIP + SwordDefs.WARDEN_GUARD) * 0.5
		draw_arc(Vector2(wedge["pivot"]), mid, float(wedge["from"]), float(wedge["to"]), 6, Color(Color(wedge["color"]).lerp(Color.WHITE, 0.55), 0.55 * wedge_fade), span)
	for field: FieldState in _run.fields:
		_draw_field(field)
	for sword: SwordState in _run.swords:
		if sword.spec.type_id == SwordDefs.COLOSSUS and (sword.phase == SwordState.Phase.WINDUP or sword.phase == SwordState.Phase.STRIKE):
			_draw_slam_telegraph(sword)
		if sword.phase == SwordState.Phase.WINDUP and sword.spec.type_id == SwordDefs.WARDEN:
			_draw_sweep_telegraph(sword)
		if sword.phase == SwordState.Phase.WINDUP and sword.spec.type_id == SwordDefs.PIKE:
			_draw_thrust_telegraph(sword)
		if sword.phase == SwordState.Phase.ULTIMATE and sword.spec.type_id == SwordDefs.PIKE:
			_draw_skewer(sword, _sword_color(sword.spec))
		elif sword.phase == SwordState.Phase.ULTIMATE:
			var tint: Color = _sword_color(sword.spec)
			var area: float = sword.ultimate_area_radius()
			draw_arc(sword.ultimate_point, area, 0.0, TAU, 48, Color(tint, 0.35), 2.0)
			draw_circle(sword.ultimate_point, area, Color(tint, 0.06))
			if sword.spec.type_id == SwordDefs.WARDEN:
				_draw_maelstrom(sword, tint)
			if sword.spec.type_id == SwordDefs.COLOSSUS:
				draw_counts[&"cataclysm_ring"] = draw_counts.get(&"cataclysm_ring", 0) + 1
				_draw_impact_ring(sword.ultimate_point, area, sword.cataclysm_rise_progress(), tint)
			if sword.ultimate_victim != null and not sword.ultimate_victim.dead:
				draw_arc(sword.ultimate_victim.position, sword.ultimate_victim.radius + 8.0, 0.0, TAU, 20, Color(tint, 0.7), 2.0)
	for ember: Dictionary in _embers:
		var ember_fade: float = clampf(float(ember["life"]) / float(ember["max"]), 0.0, 1.0)
		draw_circle(Vector2(ember["pos"]), float(ember["size"]), Color(Color(ember["color"]), ember_fade))
	for streak: Dictionary in _streaks:
		var streak_fade: float = clampf(float(streak["life"]) / float(streak["max"]), 0.0, 1.0)
		draw_line(Vector2(streak["from"]), Vector2(streak["to"]), Color(Color(streak["color"]).lerp(Color.WHITE, 0.5), streak_fade), 3.0)
	for spark: Dictionary in _sparks:
		var fade: float = clampf(float(spark["life"]) / float(spark["max"]), 0.0, 1.0)
		var head: Vector2 = Vector2(spark["pos"])
		var tail: Vector2 = head - Vector2(spark["vel"]) * 0.025
		draw_line(tail, head, Color(Color(spark["color"]), fade), 2.0)
	for ring: Dictionary in _rings:
		var t: float = 1.0 - float(ring["life"]) / float(ring["max"])
		var color: Color = ring["color"]
		color.a *= 1.0 - t
		draw_arc(Vector2(ring["pos"]), lerpf(float(ring["r0"]), float(ring["r1"]), t), 0.0, TAU, 24, color, float(ring["width"]))
	var font: Font = ThemeDB.fallback_font
	for text: Dictionary in _texts:
		var a: float = clampf(float(text["life"]) / float(text["max"]) * 2.0, 0.0, 1.0)
		var color: Color = text["color"]
		color.a = a
		var at: Vector2 = Vector2(text["pos"])
		draw_string(font, at + Vector2(2.0, 2.0), String(text["text"]), HORIZONTAL_ALIGNMENT_CENTER, -1.0, int(text["size"]), Color(0.0, 0.0, 0.0, a))
		draw_string(font, at, String(text["text"]), HORIZONTAL_ALIGNMENT_CENTER, -1.0, int(text["size"]), color)


## The arc a Warden is about to cut: a faint band along the whole sweep that brightens as the
## windup runs out, so a strike can be read before it lands. Follows the target like the sweep.
func _draw_sweep_telegraph(sword: SwordState) -> void:
	draw_counts[&"telegraph"] = draw_counts.get(&"telegraph", 0) + 1
	var u: float = 1.0 - clampf(sword.timer / sword.windup, 0.0, 1.0)
	var span: float = sword.length * (SwordDefs.WARDEN_TIP - SwordDefs.WARDEN_GUARD)
	var mid: float = sword.length * (SwordDefs.WARDEN_TIP + SwordDefs.WARDEN_GUARD) * 0.5
	var tint: Color = _sword_color(sword.spec)
	draw_arc(sword.sweep_pivot, mid, sword.sweep_from, sword.sweep_to, 24, Color(tint, 0.05 + 0.15 * u), span)
	draw_arc(sword.sweep_pivot, sword.length * SwordDefs.WARDEN_TIP, sword.sweep_from, sword.sweep_to, 24, Color(tint, 0.25 + 0.4 * u), 2.0)


## The ring a Colossus's slam is about to crush, closing in as the windup runs out and full while the
## blade falls (it follows the target during the windup and stays on the impact point afterwards).
func _draw_slam_telegraph(sword: SwordState) -> void:
	draw_counts[&"slam_telegraph"] = draw_counts.get(&"slam_telegraph", 0) + 1
	var winding: bool = sword.phase == SwordState.Phase.WINDUP
	_draw_impact_ring(sword.aim if winding else sword.impact, sword.slam_radius(), sword.windup_progress() if winding else 1.0, _sword_color(sword.spec))


## An impact marker (the prototype's `draw_impact`): the area as a faint disc with a bright rim, and a
## ring that closes from the rim toward the centre as `progress` goes 0 to 1.
func _draw_impact_ring(at: Vector2, radius: float, progress: float, tint: Color) -> void:
	draw_circle(at, radius, Color(tint, 0.05 + 0.08 * progress))
	draw_arc(at, radius, 0.0, TAU, 48, Color(tint, 0.3 + 0.5 * progress), 2.0)
	draw_arc(at, maxf(8.0, radius * (1.0 - 0.85 * progress)), 0.0, TAU, 32, Color(tint, 0.25 + 0.55 * progress), 3.0)


## A Cataclysm's elemental ground: a flattened ellipse (the arena is seen from an angle) of the field's
## element, faint fill and a pulsing rim, fading out over its last third of life (prototype `draw`).
func _draw_field(field: FieldState) -> void:
	draw_counts[&"field"] = draw_counts.get(&"field", 0) + 1
	var fade: float = field.fade()
	var tint: Color = element_color(field.element)
	var pulse: float = 0.5 + 0.2 * sin(_run.gameplay_time * 6.0 + field.position.x)
	draw_set_transform(field.position, 0.0, Vector2(1.0, 0.6))
	draw_circle(Vector2.ZERO, field.radius, Color(tint, 0.16 * fade))
	draw_arc(Vector2.ZERO, field.radius, 0.0, TAU, 48, Color(tint, pulse * fade), 2.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The line a Pike is about to thrust along: from where the sword hangs, past the aim point by the
## thrust's overshoot, brightening as the windup runs out. Follows the target like the thrust.
func _draw_thrust_telegraph(sword: SwordState) -> void:
	draw_counts[&"thrust_telegraph"] = draw_counts.get(&"thrust_telegraph", 0) + 1
	var u: float = sword.windup_progress()
	var heading: Vector2 = (sword.aim - sword.position).normalized()
	var tint: Color = _sword_color(sword.spec)
	var reach: float = (sword.aim - sword.position).length() + SwordDefs.PIKE_STRIKE_OVERSHOOT
	var from: Vector2 = sword.position + heading * sword.length * SwordDefs.PIKE_TIP_FRACTION
	var to: Vector2 = sword.position + heading * reach
	draw_line(from, to, Color(tint, 0.06 + 0.12 * u), 14.0)
	draw_line(from, to, Color(tint, 0.25 + 0.4 * u), 2.0)


## A Skewer: while it aims, the line it will fly along (the prototype's: from the player out to the
## range, a faint wide band under a thin line, both brightening); in flight, a ring on every
## enemy it carries and a short line back to the point.
func _draw_skewer(sword: SwordState, tint: Color) -> void:
	if not sword.skewer_flying:
		draw_counts[&"skewer_aim"] = draw_counts.get(&"skewer_aim", 0) + 1
		var u: float = sword.skewer_aim_progress()
		var end: Vector2 = _run.position + sword.dir * SwordDefs.PIKE_ULT_RANGE
		draw_line(_run.position, end, Color(tint, 0.15 + 0.25 * u), 24.0)
		draw_line(_run.position, end, Color(tint, 0.25 + 0.35 * u), 2.0)
		return
	var tip: Vector2 = sword.position + sword.dir * sword.length * SwordDefs.PIKE_ULT_TIP_FRACTION
	for enemy: EnemyState in sword.skewer_carried:
		draw_counts[&"skewer_carry"] = draw_counts.get(&"skewer_carry", 0) + 1
		draw_arc(enemy.position, enemy.radius + 7.0, 0.0, TAU, 20, Color(tint, 0.85), 3.0)
		draw_line(enemy.position, tip, Color(tint, 0.4), 2.0)


## A running Maelstrom: the range it pulls from (dashed), spinning arcs inside the reach of its
## blades, and the pull's inward ticks on every enemy it is dragging.
func _draw_maelstrom(sword: SwordState, tint: Color) -> void:
	draw_counts[&"maelstrom"] = draw_counts.get(&"maelstrom", 0) + 1
	var centre: Vector2 = sword.ultimate_point
	var pull: float = sword.maelstrom_pull_range()
	for dash: int in 36:
		var start: float = float(dash) * TAU / 36.0
		draw_arc(centre, pull, start, start + TAU / 72.0, 4, Color(tint, 0.22), 2.0)
	for arm: int in 4:
		var base_angle: float = sword.ultimate_spin * 0.5 + float(arm) * TAU / 4.0
		draw_arc(centre, sword.maelstrom_reach() * 0.55, base_angle, base_angle + 1.0, 10, Color(tint, 0.55), 3.0)
		draw_arc(centre, sword.maelstrom_reach() * 0.9, -base_angle, -base_angle + 0.8, 10, Color(tint, 0.4), 2.0)
	for enemy: EnemyState in _run.enemies:
		var offset: Vector2 = centre - enemy.position
		var dist: float = offset.length()
		if not enemy.dead and SwordDefs.WARDEN_ULT_PULL_MIN < dist and dist < pull:
			draw_line(enemy.position, enemy.position + offset / dist * 18.0, Color(tint, 0.55), 2.0)


## An orb: a green glow, a body and a bright core, with a short streak behind it
## along its flight. Drawn size is the visual's own (collision uses
## `ProjectileState.radius`).
func _draw_projectile(projectile: ProjectileState) -> void:
	var glow: Color = PlaceholderEnemyVisual.SPIT_GLOW
	var back: Vector2 = -projectile.velocity.normalized() * 14.0
	draw_line(projectile.position, projectile.position + back, Color(glow, 0.35), 5.0)
	draw_circle(projectile.position, 14.0, Color(glow, 0.18))
	draw_circle(projectile.position, ProjectileState.RADIUS, Color(0.67, 0.94, 0.47))
	draw_circle(projectile.position, ProjectileState.RADIUS * 0.5, Color(0.94, 1.0, 0.86))
