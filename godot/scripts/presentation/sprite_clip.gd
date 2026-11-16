class_name SpriteClip
extends Resource
## A short flip-book: which frames of a sheet to show, in order, how fast, and whether it repeats. Animation
## follows gameplay cues; it is a picture's own clock and never decides anything about the fight (ADR 0003).

@export var frames: PackedInt32Array = PackedInt32Array([0])
@export_range(0.1, 60.0) var fps: float = 8.0
@export var loop: bool = true


## Seconds one pass through the frames takes.
func duration() -> float:
	return float(maxi(frames.size(), 1)) / maxf(fps, 0.001)


## The frame to show `seconds` after the clip began (a clip that does not loop holds its last frame).
func frame_at(seconds: float) -> int:
	if frames.is_empty():
		return 0
	var index: int = int(floorf(maxf(seconds, 0.0) * fps))
	if loop:
		return frames[index % frames.size()]
	return frames[mini(index, frames.size() - 1)]


## True once a clip that does not loop has shown its last frame for its whole slot.
func is_finished_at(seconds: float) -> bool:
	return not loop and seconds >= duration()
