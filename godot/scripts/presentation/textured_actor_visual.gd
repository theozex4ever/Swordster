class_name TexturedActorVisual
extends ActorVisual
## Texture-based player actor: the artist's body sheet and shadow, driven only by the logical pose and cues the
## run hands every visual (ADR 0003). Facing turns the art (heading plus the art's own orientation), "moving" and "dead"
## pick a clip, invulnerability blinks it. Scale, pivot, orientation and the animation mapping all come from the
## `ActorSpriteSettings` resource, so replacing the art edits no script. A clip that runs out only emits
## `clip_finished`: nothing in gameplay listens to it, and nothing here can reach the run.

## Emitted when a clip that does not loop has shown all its frames (cosmetic: nothing in gameplay connects to it).
signal clip_finished(clip: SpriteClip)

const TICK: float = 1.0 / 60.0

@export var settings: ActorSpriteSettings

## How many clips have run out so far (checks read it to prove the callbacks really fire).
var clips_finished: int = 0

## The sprites exist once the visual is in the tree (a scene that is only instantiated owns none).
var _body: Sprite2D = null
var _shadow: Sprite2D = null
var _player: SpriteClipPlayer = SpriteClipPlayer.new()
var _facing: Vector2 = Vector2.DOWN
var _moving: bool = false
var _invulnerable: bool = false
var _dead: bool = false
var _blink: int = 0


func _ready() -> void:
	_shadow = Sprite2D.new()
	_body = Sprite2D.new()
	_shadow.name = "Shadow"
	_body.name = "Body"
	add_child(_shadow)
	add_child(_body)
	if settings == null:
		push_error("TexturedActorVisual has no settings")
		return
	settings.shadow.configure(_shadow)
	_shadow.position = settings.shadow_offset
	_shadow.modulate = Color(1.0, 1.0, 1.0, settings.shadow_alpha)
	settings.body.configure(_body)
	_turn()
	_play()


## The body sprite (checks read its offset, scale, rotation and frame).
func body_sprite() -> Sprite2D:
	return _body


func shadow_sprite() -> Sprite2D:
	return _shadow


func _on_pose(facing: Vector2, moving: bool) -> void:
	_facing = facing
	_moving = moving
	_turn()


func _on_state(invulnerable: bool, dead: bool) -> void:
	_invulnerable = invulnerable
	_dead = dead
	_blink += 1
	_play()
	if _player.advance(TICK):
		clips_finished += 1
		clip_finished.emit(_player.clip)
	_body.frame = _player.frame()
	var alpha: float = settings.invulnerable_alpha if _invulnerable and _blink % 6 < 3 else 1.0
	_body.modulate = Color(1.0, 1.0, 1.0, alpha)


func _turn() -> void:
	if settings != null and settings.body != null:
		_body.rotation = settings.body.rotation_for(_facing.angle())


func _play() -> void:
	if settings == null:
		return
	_player.play(settings.dead_clip if _dead else settings.moving_clip if _moving else settings.idle_clip)
