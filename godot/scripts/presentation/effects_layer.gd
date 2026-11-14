class_name EffectsLayer
extends Node2D
## Cosmetic world effects: spawn telegraphs (tinted and sized by enemy type),
## healing motes, enemy projectiles, hit rings, damage numbers, crowd-collision
## sparks, wall-slam bursts, dash afterimages and parry sparks. A parry reads
## differently from a hit on purpose: green sparks and a "PARRY" tag where the
## orb died, with no number; a hit on an enemy is a white ring and a damage
## number, a hit on the player a red ring and "-8". Purely visual: it reads the
## run's state and cues, owns its own random stream and never influences gameplay.

const MAX_EFFECTS: int = 160

var _rings: Array[Dictionary] = []
var _texts: Array[Dictionary] = []
var _sparks: Array[Dictionary] = []
var _run: GameRun
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func clear() -> void:
	_rings.clear()
	_texts.clear()
	_sparks.clear()
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
		_sparks = _sparks.filter(func(sp: Dictionary) -> bool: return float(sp["life"]) > 0.0)
		_rings = _rings.filter(func(r: Dictionary) -> bool: return float(r["life"]) > 0.0)
		_texts = _texts.filter(func(t: Dictionary) -> bool: return float(t["life"]) > 0.0)
		if run.dash_left > 0.0:
			_add_ring(run.position, GameRun.PLAYER_RADIUS * 0.6, GameRun.PLAYER_RADIUS * 1.2, 0.22, Color(0.35, 0.65, 0.85, 0.7), 2.0)
	queue_redraw()


func apply_cue(cue: SimCue) -> void:
	match cue.kind:
		SimCue.Kind.ENEMY_HIT:
			_add_ring(cue.position, 10.0, 30.0 + float(cue.amount) * 0.4, 0.18, Color(1.0, 0.95, 0.8, 0.9), 2.0)
			var jitter: Vector2 = Vector2(_rng.randf_range(-10.0, 10.0), -22.0)
			var label: String = "%d%s" % [cue.amount, "!" if cue.critical else ""]
			_add_text(cue.position + jitter, label, Color(1.0, 0.88, 0.35) if cue.critical else Color.WHITE, 1.0 if cue.critical else 0.75, 28 if cue.critical else 22)
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
		_:
			pass


func _add_ring(at: Vector2, r0: float, r1: float, life: float, color: Color, width: float) -> void:
	if _rings.size() < MAX_EFFECTS:
		_rings.append({"pos": at, "r0": r0, "r1": r1, "life": life, "max": life, "color": color, "width": width})


func _add_spark(at: Vector2, velocity: Vector2, life: float) -> void:
	if _sparks.size() < MAX_EFFECTS:
		_sparks.append({"pos": at, "vel": velocity, "life": life, "max": life})


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
	for spark: Dictionary in _sparks:
		var fade: float = clampf(float(spark["life"]) / float(spark["max"]), 0.0, 1.0)
		var head: Vector2 = Vector2(spark["pos"])
		var tail: Vector2 = head - Vector2(spark["vel"]) * 0.025
		draw_line(tail, head, Color(0.85, 1.0, 0.65, fade), 2.0)
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
