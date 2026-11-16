class_name SpriteClipPlayer
extends RefCounted
## Plays one `SpriteClip` at a time on the picture's own clock, which a visual advances once per fixed tick. It only
## ever answers "which frame?" and "did a clip just run out?": nothing it reports is read back by gameplay.

var clip: SpriteClip = null
var seconds: float = 0.0
var _announced: bool = false


## Starts `next` from its first frame. Asking for the clip that already plays changes nothing.
func play(next: SpriteClip) -> void:
	if next == clip:
		return
	clip = next
	seconds = 0.0
	_announced = false


## Moves the picture's clock on. Returns true once, on the tick a clip that does not loop has shown all its frames.
func advance(delta: float) -> bool:
	seconds += delta
	if clip != null and not _announced and clip.is_finished_at(seconds):
		_announced = true
		return true
	return false


func frame() -> int:
	return clip.frame_at(seconds) if clip != null else 0
