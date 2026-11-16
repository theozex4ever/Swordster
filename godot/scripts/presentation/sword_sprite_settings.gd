class_name SwordSpriteSettings
extends Resource
## Everything a texture-based spirit sword needs from its artist: one piece of art per sword type, the glow and
## shadow, the colour of each element, and which clip plays for which phase. The element tints the blade, the rarity
## sizes it and colours its glow (see TexturedSwordVisual). See docs/art/replacing-visuals.md.

@export var fang: SpriteArt
@export var warden: SpriteArt
@export var pike: SpriteArt
@export var colossus: SpriteArt
## A soft round glow drawn behind the blade (tinted per sword) and the ground shadow.
@export var glow: SpriteArt
@export var shadow: SpriteArt
@export var fire_tint: Color = Color(1.0, 0.46, 0.17)
@export var ice_tint: Color = Color(0.47, 0.80, 1.0)
@export var poison_tint: Color = Color(0.52, 0.90, 0.26)
## Clips for the phases of an attack. A sword that is stuck in an enemy plays the strike clip.
@export var idle_clip: SpriteClip
@export var windup_clip: SpriteClip
@export var strike_clip: SpriteClip
@export var recover_clip: SpriteClip
@export var ultimate_clip: SpriteClip
## How high above its shadow a sword floats at rest and while attacking, in pixels.
@export var lift_idle: float = 34.0
@export var lift_attack: float = 14.0
