class_name RunScenario
extends RefCounted
## Controlled starting conditions for a run. Used by headless checks (and the
## game itself, with defaults) so no check needs a parallel rules implementation.

var start_position: Vector2 = GameRun.WORLD.get_center()
