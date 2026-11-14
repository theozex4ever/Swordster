class_name SimMath
extends RefCounted
## Small geometry/number helpers shared by the simulation. They mirror the
## helpers at the top of game/main.py (`norm`, `seg_dist`, `polar`, `ang_lerp`)
## and Python 3's `round()`.


static func polar(angle: float, radius: float = 1.0) -> Vector2:
	return Vector2(cos(angle) * radius, sin(angle) * radius)


## Unit vector of `v`. A (near) zero vector returns `fallback`, or a random
## direction drawn from `rng` when there is none (prototype `norm`).
static func norm(v: Vector2, rng: RandomNumberGenerator, fallback: Vector2 = Vector2.ZERO, has_fallback: bool = false) -> Vector2:
	if v.length_squared() < 1e-6:
		if has_fallback:
			return fallback
		return polar(rng.randf_range(0.0, TAU))
	return v.normalized()


## Distance from point `p` to the segment a-b.
static func seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: Vector2 = b - a
	var l2: float = ab.length_squared()
	if l2 == 0.0:
		return (p - a).length()
	var t: float = clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return (p - (a + ab * t)).length()


## Shortest-way angle interpolation (prototype `ang_lerp`).
static func ang_lerp(a: float, b: float, t: float) -> float:
	var d: float = fposmod(b - a + PI, TAU) - PI
	return a + d * t


## Python 3 `round(x)`: halves round to the nearest EVEN integer (24.5 -> 24),
## unlike GDScript's `roundi`, which rounds halves away from zero.
static func py_round(x: float) -> int:
	var lower: float = floorf(x)
	var diff: float = x - lower
	if diff < 0.5:
		return int(lower)
	if diff > 0.5:
		return int(lower) + 1
	return int(lower) if int(lower) % 2 == 0 else int(lower) + 1
