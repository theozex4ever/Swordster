class_name TexturedSwordVisual
extends SwordVisual
## Texture-based spirit sword: the artist's blade for the sword's type, tinted by its element, drawn as much larger as its
## rarity says and ringed by a glow in the rarity's colour (the element's for a Common sword), riding above a ground
## shadow. The attack phase picks the clip (idle, windup, strike, recover, ultimate) and a striking blade brightens. A
## sword lying in the arena hovers point-down; a Colossus is drawn as high as the run reports. Everything it reads is a
## logical pose or cue handed in by the run; texture size, pivot, orientation and clips come from `SwordSpriteSettings`,
## and nothing here can reach back into the run (ADR 0003).

## Emitted when a clip that does not loop has shown all its frames (cosmetic: nothing in gameplay connects to it).
signal clip_finished(clip: SpriteClip)

const TICK: float = 1.0 / 60.0
## How much the glow lights up for a freshly swapped-in sword, on top of its resting brightness.
const GLOW_BASE_ALPHA: float = 0.36
const GLOW_FLASH_ALPHA: float = 0.4

@export var settings: SwordSpriteSettings

## How many clips have run out so far (checks read it to prove the callbacks really fire).
var clips_finished: int = 0

## The sprites exist once the visual is in the tree (a scene that is only instantiated owns none).
var _shadow: Sprite2D = null
var _glow: Sprite2D = null
var _blade: Sprite2D = null
var _art: SpriteArt = null
var _player: SpriteClipPlayer = SpriteClipPlayer.new()
var _tint: Color = Color.WHITE
var _glow_tint: Color = Color.WHITE
var _rarity_size: float = 1.0
var _colossus: bool = false
var _angle: float = -PI / 2.0
var _phase: int = SwordState.Phase.IDLE
var _lift: float = 0.0
var _altitude: float = 0.0
var _flash: float = 0.0
var _hover: float = 0.0
var _resting: bool = false


func _ready() -> void:
	_shadow = Sprite2D.new()
	_glow = Sprite2D.new()
	_blade = Sprite2D.new()
	_shadow.name = "Shadow"
	_glow.name = "Glow"
	_blade.name = "Blade"
	add_child(_shadow)
	add_child(_glow)
	add_child(_blade)
	if settings == null:
		push_error("TexturedSwordVisual has no settings")
		return
	_lift = settings.lift_idle
	settings.shadow.configure(_shadow)
	_shadow.position = Vector2(0.0, 6.0)
	_player.play(settings.idle_clip)
	_layout()


func blade_sprite() -> Sprite2D:
	return _blade


func glow_sprite() -> Sprite2D:
	return _glow


func shadow_sprite() -> Sprite2D:
	return _shadow


## The element's tint under these settings (white for an unknown element).
func tint_of(element: StringName) -> Color:
	match element:
		&"fire":
			return settings.fire_tint
		&"ice":
			return settings.ice_tint
		&"poison":
			return settings.poison_tint
	return Color.WHITE


func art_of(type_id: StringName) -> SpriteArt:
	match type_id:
		SwordDefs.WARDEN:
			return settings.warden
		SwordDefs.PIKE:
			return settings.pike
		SwordDefs.COLOSSUS:
			return settings.colossus
	return settings.fang


func _on_setup(spec: SwordSpec) -> void:
	_art = art_of(spec.type_id)
	_colossus = spec.type_id == SwordDefs.COLOSSUS
	_tint = tint_of(spec.element)
	_rarity_size = SwordDefs.RARITY_SIZE[spec.rarity]
	_glow_tint = SwordDefs.RARITY_COLORS[spec.rarity] if spec.rarity > 0 else _tint
	_art.configure(_blade, _rarity_size)
	_blade.modulate = _tint
	settings.glow.configure(_glow)
	_layout()


func _on_altitude(height: float) -> void:
	_altitude = height


func _on_flash(amount: float) -> void:
	_flash = amount


func _on_hover(height: float) -> void:
	_resting = true
	_hover = height


func _on_pose(angle: float, phase: int) -> void:
	_angle = angle
	_phase = phase
	var attacking: bool = phase == SwordState.Phase.WINDUP or phase == SwordState.Phase.STRIKE or phase == SwordState.Phase.ULTIMATE
	_lift = _hover if _resting else _altitude if _colossus else lerpf(_lift, settings.lift_attack if attacking else settings.lift_idle, 0.25)
	_player.play(_clip_for(phase))
	if _player.advance(TICK):
		clips_finished += 1
		clip_finished.emit(_player.clip)
	_layout()


## The animation mapping: which clip a phase shows.
func _clip_for(phase: int) -> SpriteClip:
	match phase:
		SwordState.Phase.WINDUP:
			return settings.windup_clip
		SwordState.Phase.STRIKE, SwordState.Phase.STUCK:
			return settings.strike_clip
		SwordState.Phase.RECOVER:
			return settings.recover_clip
		SwordState.Phase.ULTIMATE:
			return settings.ultimate_clip
	return settings.idle_clip


func _layout() -> void:
	if _art == null:
		return
	_blade.frame = _player.frame()
	_blade.position = Vector2(0.0, -_lift)
	_blade.rotation = _art.rotation_for(_angle)
	var striking: bool = _phase == SwordState.Phase.STRIKE or _phase == SwordState.Phase.ULTIMATE
	_blade.modulate = _tint.lerp(Color.WHITE, 0.3 if striking else 0.0)
	# The glow rings the blade: 0.75 blade lengths across on each side, brighter while a swapped-in sword's slot flashes.
	var length: float = _art.frame_size().y * _art.visual_scale.y * _rarity_size
	var glow_art: SpriteArt = settings.glow
	var glow_across: float = maxf(glow_art.frame_size().x, 1.0)
	_glow.position = Vector2(0.0, -_lift)
	_glow.scale = glow_art.visual_scale * (length * 1.5 / glow_across)
	_glow.modulate = Color(_glow_tint, GLOW_BASE_ALPHA + GLOW_FLASH_ALPHA * _flash)
	# The shadow stays on the ground; a high Colossus shrinks and fades it.
	var high: float = clampf(_altitude / 260.0, 0.0, 1.0) if _colossus else 0.0
	_shadow.scale = settings.shadow.visual_scale * (1.0 if not _colossus else lerpf(1.6, 0.8, high))
	_shadow.modulate = Color(1.0, 1.0, 1.0, lerpf(0.34, 0.12, high) if _colossus else 0.3)
