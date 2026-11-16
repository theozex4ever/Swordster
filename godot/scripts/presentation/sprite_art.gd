class_name SpriteArt
extends Resource
## One piece of texture art and everything the picture needs to know about itself: how many frames sit side by
## side in the file, where its pivot is, how big to draw it and which way it points. These numbers are
## presentation only. They never reach reach, hit geometry, collision or timing (ADR 0003): swapping the
## texture for one of another size changes nothing but the picture.

## The sheet: `frame_count` equal frames laid out left to right.
@export var texture: Texture2D
@export_range(1, 32) var frame_count: int = 1
## The point of ONE frame (in texture pixels, from its top-left corner) that sits on the thing's logical position.
@export var pivot: Vector2 = Vector2.ZERO
## How much bigger or smaller than the file the art is drawn.
@export var visual_scale: Vector2 = Vector2.ONE
## The way the art points as drawn, in degrees, measured the way the game measures angles (0 = right/east, 90 = down/south).
## The game turns the picture by its own heading PLUS this, so an art that points up needs 90 and one that points down needs -90.
@export var orientation_degrees: float = 0.0


## The size of one frame in texture pixels (zero without a texture).
func frame_size() -> Vector2:
	if texture == null:
		return Vector2.ZERO
	return Vector2(float(texture.get_width()) / float(maxi(frame_count, 1)), float(texture.get_height()))


## Points `sprite` at this art: texture, sheet layout and pivot. The pivot is the sprite's origin, so rotating and scaling
## the sprite turns and grows it around that point. `extra_scale` is a further factor (a sword's rarity size).
func configure(sprite: Sprite2D, extra_scale: float = 1.0) -> void:
	sprite.texture = texture
	sprite.hframes = maxi(frame_count, 1)
	sprite.centered = false
	sprite.offset = -pivot
	sprite.scale = visual_scale * extra_scale


## The rotation that makes this art point along `heading` (radians, the game's own angle).
func rotation_for(heading: float) -> float:
	return heading + deg_to_rad(orientation_degrees)
