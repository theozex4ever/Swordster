class_name ScreenFeedback
extends CanvasLayer
## Whole-screen feedback drawn between the world and the HUD: the prototype's dark vignette, the red flash a hit on the player
## leaves (it fades at 2.5 a second) and the slow red pulse while health is below 30 %. Purely visual: it reads the run's
## state and cues and owns nothing the run reads. A restart or a pause leaves it where the run puts it (it only moves with ticks).

const FLASH_DECAY: float = 2.5
const LOW_HEALTH: float = 0.3
## The darkness at the corners and the strongest red flash, as the prototype's vignette strengths (215 and 200 of 255).
const DARK_ALPHA: float = 0.55
const HURT_ALPHA: float = 0.78

var hurt_flash: float = 0.0

var _dark: TextureRect
var _hurt: TextureRect


func _ready() -> void:
	layer = 1
	_dark = _make_vignette(Color(0.0, 0.0, 0.0))
	_dark.modulate.a = DARK_ALPHA
	_hurt = _make_vignette(Color(0.67, 0.04, 0.12))
	_hurt.modulate.a = 0.0


## A hit on the player flashes the screen red.
func apply_cues(cues: Array[SimCue]) -> void:
	for cue: SimCue in cues:
		if cue.kind == SimCue.Kind.PLAYER_HURT:
			hurt_flash = 1.0


## Once per fixed tick, after the run stepped.
func sync(run: GameRun) -> void:
	if not run.paused:
		hurt_flash = maxf(0.0, hurt_flash - GameRun.TICK_DT * FLASH_DECAY)
	if hurt_flash > 0.0:
		_hurt.modulate.a = HURT_ALPHA * hurt_flash
	elif run.hp < run.max_hp * LOW_HEALTH and not run.dead:
		_hurt.modulate.a = (60.0 + 40.0 * sin(run.real_time * 5.0)) / 255.0
	else:
		_hurt.modulate.a = 0.0


func reset() -> void:
	hurt_flash = 0.0
	_hurt.modulate.a = 0.0


## The red layer's strength now (0 to 1). Checks read it.
func hurt_alpha() -> float:
	return _hurt.modulate.a


## A full-screen radial fade from clear in the middle to `color` at the corners.
func _make_vignette(color: Color) -> TextureRect:
	var gradient: Gradient = Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.4, 0.75, 1.0])
	gradient.colors = PackedColorArray([Color(color, 0.0), Color(color, 0.0), Color(color, 0.35), Color(color, 1.0)])
	var texture: GradientTexture2D = GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 128
	texture.height = 72
	var rect: TextureRect = TextureRect.new()
	rect.texture = texture
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rect)
	return rect
