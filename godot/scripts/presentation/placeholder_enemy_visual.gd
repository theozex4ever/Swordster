class_name PlaceholderEnemyVisual
extends EnemyVisual
## Temporary drawn enemies with a distinct silhouette per type, so a crowd reads
## at a glance without final art:
##   * husk   - mid-size red disc with two eyes (the baseline),
##   * runner - small orange disc ringed by spinning spikes (fast, fragile),
##   * spitter - mid-size green disc with a forward snout that swells and glows
##     (with a dashed aim line) while it winds up a shot,
##   * brute  - large dark-purple armoured body with a bright rim and horns.
## Every size here is the visual's own; none feeds collision or reach. A white
## dashed ring marks an enemy that is stunned or flying (knocked back).

const HUSK_COLOR: Color = Color(0.84, 0.28, 0.34)
const RUNNER_COLOR: Color = Color(1.0, 0.55, 0.27)
const BRUTE_COLOR: Color = Color(0.67, 0.35, 0.86)
const SPITTER_COLOR: Color = Color(0.51, 0.82, 0.35)
## Warning glow of a spitter's shot; the orbs it fires share it (see EffectsLayer).
const SPIT_GLOW: Color = Color(0.78, 1.0, 0.45)
const EYE_COLOR: Color = Color(1.0, 0.94, 0.78)

var _kind: StringName = EnemyDefs.HUSK
var _body_radius: float = 16.0
var _facing: Vector2 = Vector2.LEFT
var _flash: float = 0.0
var _squash: float = 0.0
var _hp_fraction: float = 1.0
var _stunned: bool = false
var _telegraph: float = 0.0
## Cosmetic clock for spinning parts; advances once per fixed tick.
var _clock: float = 0.0


## Placeholder palette per enemy type (also tints spawn telegraphs).
static func color_of(kind: StringName) -> Color:
	match kind:
		EnemyDefs.RUNNER:
			return RUNNER_COLOR
		EnemyDefs.BRUTE:
			return BRUTE_COLOR
		EnemyDefs.SPITTER:
			return SPITTER_COLOR
		_:
			return HUSK_COLOR


## Placeholder body radius per enemy type: the prototype's drawn size, kept
## here as a plain visual setting rather than read from collision.
static func visual_radius_of(kind: StringName) -> float:
	match kind:
		EnemyDefs.RUNNER:
			return 11.0
		EnemyDefs.BRUTE:
			return 30.0
		EnemyDefs.SPITTER:
			return 15.0
		_:
			return 16.0


func _on_setup(kind: StringName) -> void:
	_kind = kind
	_body_radius = visual_radius_of(kind)


func _on_pose(facing: Vector2, flash: float, squash: float, hp_fraction: float, stunned: bool, telegraph: float) -> void:
	_telegraph = telegraph
	_facing = facing
	_flash = flash
	_squash = squash
	_hp_fraction = hp_fraction
	_stunned = stunned
	_clock += GameRun.TICK_DT
	queue_redraw()


func _draw() -> void:
	var radius: float = _body_radius
	var base: Color = color_of(_kind)
	draw_circle(Vector2(0.0, radius * 0.4), radius, Color(0.0, 0.0, 0.0, 0.35))
	var stretch: float = 1.0 + _squash * 0.18
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(stretch, 1.0 / stretch))
	var rim: Color = base.lerp(Color.WHITE, clampf(_flash * 6.0, 0.0, 1.0))
	match _kind:
		EnemyDefs.RUNNER:
			_draw_runner(radius, rim)
		EnemyDefs.BRUTE:
			_draw_brute(radius, base, rim)
		EnemyDefs.SPITTER:
			_draw_spitter(radius, base, rim)
		_:
			draw_circle(Vector2.ZERO, radius, rim)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_eyes(radius)
	if _kind == EnemyDefs.SPITTER and _telegraph > 0.0:
		_draw_spit_telegraph(radius)
	if _stunned:
		_draw_stun_ring(radius)
	if _hp_fraction < 1.0:
		var width: float = radius * 2.0
		draw_rect(Rect2(-width * 0.5, -radius - 10.0, width, 4.0), Color(0.0, 0.0, 0.0, 0.6))
		draw_rect(Rect2(-width * 0.5, -radius - 10.0, width * _hp_fraction, 4.0), Color(0.95, 0.35, 0.4))


func _draw_runner(radius: float, rim: Color) -> void:
	for spike: int in 5:
		var angle: float = _clock * 6.0 + float(spike) * TAU / 5.0
		draw_line(SimMath.polar(angle, radius * 0.8), SimMath.polar(angle, radius * 1.55), rim, 2.5)
	draw_circle(Vector2.ZERO, radius, rim)


func _draw_brute(radius: float, base: Color, rim: Color) -> void:
	draw_circle(Vector2.ZERO, radius, base.darkened(0.55).lerp(Color.WHITE, clampf(_flash * 6.0, 0.0, 1.0)))
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 40, rim, 4.0)
	draw_arc(Vector2.ZERO, radius * 0.6, 0.0, TAU, 28, base.darkened(0.2), 2.0)
	for side: float in [-1.0, 1.0]:
		var root: Vector2 = Vector2(side * radius * 0.6, -radius * 0.7)
		draw_line(root, root + Vector2(side * 8.0, -12.0), rim, 4.0)


## A disc with a darker core and a snout pointing at the player, so a spitter
## reads as "faces me, shoots" even before it glows.
func _draw_spitter(radius: float, base: Color, rim: Color) -> void:
	var side: Vector2 = Vector2(-_facing.y, _facing.x)
	var snout: PackedVector2Array = PackedVector2Array([
		_facing * radius * 0.6 + side * radius * 0.55,
		_facing * radius * 1.55,
		_facing * radius * 0.6 - side * radius * 0.55,
	])
	draw_colored_polygon(snout, rim.darkened(0.2))
	draw_circle(Vector2.ZERO, radius, rim)
	draw_arc(Vector2.ZERO, radius * 0.55, 0.0, TAU, 20, base.darkened(0.45), 2.5)


## The shot's wind-up: a glow that swells at the muzzle, a ring tightening on the
## body and a dashed aim line growing toward the player. Pure presentation; the
## 0..1 progress comes from the simulation.
func _draw_spit_telegraph(radius: float) -> void:
	var muzzle: Vector2 = _facing * radius * 1.55
	draw_circle(muzzle, 5.0 + 11.0 * _telegraph, Color(SPIT_GLOW.r, SPIT_GLOW.g, SPIT_GLOW.b, 0.25 + 0.55 * _telegraph))
	draw_circle(muzzle, 2.0 + 4.0 * _telegraph, Color(1.0, 1.0, 0.9, 0.9))
	draw_arc(Vector2.ZERO, radius + 10.0 - 6.0 * _telegraph, 0.0, TAU, 28, Color(SPIT_GLOW.r, SPIT_GLOW.g, SPIT_GLOW.b, 0.35 + 0.5 * _telegraph), 2.0)
	var reach: float = 40.0 + 120.0 * _telegraph
	var dash: float = 10.0
	var at: float = radius * 1.9
	var on: bool = true
	while at < radius * 1.9 + reach:
		if on:
			draw_line(_facing * at, _facing * minf(at + dash, radius * 1.9 + reach), Color(SPIT_GLOW.r, SPIT_GLOW.g, SPIT_GLOW.b, 0.2 + 0.5 * _telegraph), 2.0)
		on = not on
		at += dash


func _draw_eyes(radius: float) -> void:
	var side: Vector2 = Vector2(-_facing.y, _facing.x)
	for sign_value: float in [-1.0, 1.0]:
		var at: Vector2 = _facing * radius * 0.45 + side * sign_value * radius * 0.32 - Vector2(0.0, radius * 0.1)
		draw_circle(at, maxf(2.0, radius * 0.14), EYE_COLOR)


func _draw_stun_ring(radius: float) -> void:
	var ring: float = radius + 6.0
	var dashes: int = 8
	for dash: int in dashes:
		var start: float = -_clock * 5.0 + float(dash) * TAU / float(dashes)
		draw_arc(Vector2.ZERO, ring, start, start + TAU / float(dashes) * 0.55, 6, Color(1.0, 1.0, 1.0, 0.85), 2.0)
