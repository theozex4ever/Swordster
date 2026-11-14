class_name PlaceholderEnemyVisual
extends EnemyVisual
## Temporary drawn enemies with a distinct silhouette per type, so a crowd reads
## at a glance without final art:
##   * husk   - mid-size red disc with two eyes (the baseline),
##   * runner - small orange disc ringed by spinning spikes (fast, fragile),
##   * brute  - large dark-purple armoured body with a bright rim and horns.
## Every size here is the visual's own; none feeds collision or reach. A white
## dashed ring marks an enemy that is stunned or flying (knocked back).

const HUSK_COLOR: Color = Color(0.84, 0.28, 0.34)
const RUNNER_COLOR: Color = Color(1.0, 0.55, 0.27)
const BRUTE_COLOR: Color = Color(0.67, 0.35, 0.86)
const EYE_COLOR: Color = Color(1.0, 0.94, 0.78)

var _kind: StringName = EnemyDefs.HUSK
var _body_radius: float = 16.0
var _facing: Vector2 = Vector2.LEFT
var _flash: float = 0.0
var _squash: float = 0.0
var _hp_fraction: float = 1.0
var _stunned: bool = false
## Cosmetic clock for spinning parts; advances once per fixed tick.
var _clock: float = 0.0


## Placeholder palette per enemy type (also tints spawn telegraphs).
static func color_of(kind: StringName) -> Color:
	match kind:
		EnemyDefs.RUNNER:
			return RUNNER_COLOR
		EnemyDefs.BRUTE:
			return BRUTE_COLOR
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
		_:
			return 16.0


func _on_setup(kind: StringName) -> void:
	_kind = kind
	_body_radius = visual_radius_of(kind)


func _on_pose(facing: Vector2, flash: float, squash: float, hp_fraction: float, stunned: bool) -> void:
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
		_:
			draw_circle(Vector2.ZERO, radius, rim)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_eyes(radius)
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
