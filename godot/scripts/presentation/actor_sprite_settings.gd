class_name ActorSpriteSettings
extends Resource
## Everything a texture-based player actor needs from its artist: the body art, its ground shadow and which
## clip plays for which cue. See docs/art/replacing-visuals.md.

@export var body: SpriteArt
@export var shadow: SpriteArt
## Where the shadow sits, relative to the actor's logical position.
@export var shadow_offset: Vector2 = Vector2(0.0, 6.0)
@export var shadow_alpha: float = 0.35
## Clips for the cues "standing", "moving" and "dead".
@export var idle_clip: SpriteClip
@export var moving_clip: SpriteClip
@export var dead_clip: SpriteClip
## While the actor cannot be hurt it blinks between full and this opacity.
@export_range(0.0, 1.0) var invulnerable_alpha: float = 0.45
