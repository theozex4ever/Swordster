extends SceneTree
## Draws the PLACEHOLDER texture art for the `textured` visual set (issue #21) into godot/art/placeholder/.
## Original, procedurally drawn stand-ins (no third-party art): an actor sheet, four sword sheets, a glow and a
## shadow, with deliberately different sizes and pivots from the drawn placeholders, so a texture swap really
## exercises scale, pivot and orientation. They are meant to be replaced by real art
## (docs/art/replacing-visuals.md). The committed PNGs are what the build uses; run this only to regenerate them:
##
##   godot --headless --script tools/godot/gen_placeholder_art.gd           (from the repository root)
##   godot --headless --path godot --import                                  (then refresh the .import files)
##
## Output is deterministic. Art conventions (they are recorded in the settings resources, not here):
##   actor.png     5 frames of 64x80: standing x2, walking x2, fallen. Faces DOWN. Pivot (32, 44) = the body's centre.
##   sword_*.png   4 frames each: idle, glint, windup, strike. Blade points UP. Drawn white/grey: the game tints it
##                 with the sword's element. Pivot = the guard.
##   glow.png / shadow.png   soft round glow and ground shadow.

const SAMPLES: int = 4

var _out: String = "godot/art/placeholder"


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for arg: String in args:
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(_out)
	_actor()
	_sword("fang", Vector2i(24, 96), Callable(self, "_fang_layers"))
	_sword("warden", Vector2i(40, 128), Callable(self, "_warden_layers"))
	_sword("pike", Vector2i(28, 176), Callable(self, "_pike_layers"))
	_sword("colossus", Vector2i(64, 208), Callable(self, "_colossus_layers"))
	_soft_disc("glow", 128, 0.0, 1.0)
	_shadow()
	print("placeholder art written to %s" % _out)
	quit(0)


# ------------------------------------------------------------------ painter
## A layer is {"cover": Callable(Vector2) -> float 0..1, "color": Color}; layers paint in order, each over the last.
func _paint(image: Image, origin: Vector2i, size: Vector2i, layers: Array) -> void:
	var steps: float = float(SAMPLES)
	for y: int in size.y:
		for x: int in size.x:
			var pixel: Color = image.get_pixel(origin.x + x, origin.y + y)
			for layer: Dictionary in layers:
				var cover: Callable = layer["cover"]
				var hits: float = 0.0
				for sy: int in SAMPLES:
					for sx: int in SAMPLES:
						hits += float(cover.call(Vector2(float(x) + (float(sx) + 0.5) / steps, float(y) + (float(sy) + 0.5) / steps)))
				var color: Color = layer["color"]
				var alpha: float = color.a * hits / (steps * steps)
				if alpha <= 0.0:
					continue
				var out_alpha: float = alpha + pixel.a * (1.0 - alpha)
				pixel = Color((color.r * alpha + pixel.r * pixel.a * (1.0 - alpha)) / out_alpha, (color.g * alpha + pixel.g * pixel.a * (1.0 - alpha)) / out_alpha, (color.b * alpha + pixel.b * pixel.a * (1.0 - alpha)) / out_alpha, out_alpha)
			image.set_pixel(origin.x + x, origin.y + y, pixel)


func _layer(cover: Callable, color: Color) -> Dictionary:
	return {"cover": cover, "color": color}


func _ellipse(center: Vector2, radii: Vector2) -> Callable:
	return func(p: Vector2) -> float:
		var d: Vector2 = (p - center) / radii
		return 1.0 if d.length_squared() <= 1.0 else 0.0


func _polygon(points: PackedVector2Array) -> Callable:
	return func(p: Vector2) -> float: return 1.0 if Geometry2D.is_point_in_polygon(p, points) else 0.0


func _rect(from: Vector2, to: Vector2) -> Callable:
	return func(p: Vector2) -> float: return 1.0 if p.x >= from.x and p.x < to.x and p.y >= from.y and p.y < to.y else 0.0


func _save(image: Image, name: String) -> void:
	var path: String = "%s/%s.png" % [_out, name]
	if image.save_png(path) != OK:
		push_error("cannot write %s" % path)
		quit(1)


# --------------------------------------------------------------------- actor
func _actor() -> void:
	var frame: Vector2i = Vector2i(64, 80)
	var image: Image = Image.create_empty(frame.x * 5, frame.y, false, Image.FORMAT_RGBA8)
	for index: int in 5:
		var origin: Vector2i = Vector2i(index * frame.x, 0)
		var body: Color = Color(0.30, 0.74, 0.96)
		var trim: Color = Color(0.10, 0.28, 0.45)
		var cape: Color = Color(0.16, 0.42, 0.70)
		var crest: Color = Color(0.95, 0.98, 1.0)
		var stride: float = 0.0
		if index == 1:
			stride = 1.5
		if index == 2:
			stride = 6.0
		if index == 3:
			stride = -6.0
		var squash: float = 1.0
		if index == 4:
			body = Color(0.40, 0.44, 0.52)
			trim = Color(0.20, 0.22, 0.28)
			cape = Color(0.30, 0.33, 0.40)
			crest = Color(0.6, 0.62, 0.68)
			squash = 0.78
		var layers: Array = [
			# A cloak trailing behind (up, because the art faces down): the sprite reaches far above its pivot.
			_layer(_polygon(PackedVector2Array([Vector2(32.0, 6.0 + stride * 0.3), Vector2(50.0, 34.0), Vector2(14.0, 34.0)])), cape),
			# Two feet that swap places while walking.
			_layer(_ellipse(Vector2(24.0, 60.0 + stride), Vector2(6.0, 5.0)), trim),
			_layer(_ellipse(Vector2(40.0, 60.0 - stride), Vector2(6.0, 5.0)), trim),
			# The body, centred on the pivot (32, 44), with a dark rim.
			_layer(_ellipse(Vector2(32.0, 44.0), Vector2(17.0, 17.0 * squash)), trim),
			_layer(_ellipse(Vector2(32.0, 44.0), Vector2(15.0, 15.0 * squash)), body),
			# A pointed crest on the front (down) so the facing reads.
			_layer(_polygon(PackedVector2Array([Vector2(32.0, 70.0), Vector2(38.0, 54.0), Vector2(26.0, 54.0)])), crest),
			# A bright eye.
			_layer(_ellipse(Vector2(32.0, 47.0), Vector2(5.0, 4.0)), crest),
		]
		_paint(image, origin, frame, layers)
	_save(image, "actor")


# -------------------------------------------------------------------- swords
func _sword(name: String, frame: Vector2i, layers_for: Callable) -> void:
	var image: Image = Image.create_empty(frame.x * 4, frame.y, false, Image.FORMAT_RGBA8)
	for index: int in 4:
		_paint(image, Vector2i(index * frame.x, 0), frame, layers_for.call(index, frame) as Array)
	_save(image, "sword_%s" % name)


## The shared look of a frame: how bright the blade is and which extras it carries.
func _blade_tone(index: int) -> Color:
	match index:
		1:
			return Color(0.98, 0.98, 0.98)
		2:
			return Color(0.80, 0.80, 0.84)
		3:
			return Color(1.0, 1.0, 1.0)
	return Color(0.88, 0.88, 0.90)


## Extras per frame, drawn over the blade between y = `top` and `bottom` at column `x`: a glint (frame 1), a charged
## core with sparks beside the guard (frame 2) and a ghost trail behind the hilt (frame 3).
func _frame_extras(index: int, frame: Vector2i, x: float, top: float, bottom: float, guard_y: float, spread: float) -> Array:
	var extras: Array = []
	if index == 1:
		extras.append(_layer(_polygon(PackedVector2Array([Vector2(x - 1.5, top + (bottom - top) * 0.2), Vector2(x + 1.5, top + (bottom - top) * 0.2), Vector2(x + 1.5, top + (bottom - top) * 0.55), Vector2(x - 1.5, top + (bottom - top) * 0.55)])), Color(1.0, 1.0, 1.0, 0.95)))
	if index == 2:
		extras.append(_layer(_rect(Vector2(x - 1.0, top + 4.0), Vector2(x + 1.0, bottom)), Color(1.0, 1.0, 1.0, 1.0)))
		extras.append(_layer(_ellipse(Vector2(x - spread, guard_y - 4.0), Vector2(2.0, 2.0)), Color(1.0, 1.0, 1.0, 0.9)))
		extras.append(_layer(_ellipse(Vector2(x + spread, guard_y - 4.0), Vector2(2.0, 2.0)), Color(1.0, 1.0, 1.0, 0.9)))
	if index == 3:
		extras.append(_layer(_rect(Vector2(x - spread * 0.5, guard_y + 2.0), Vector2(x + spread * 0.5, float(frame.y) - 2.0)), Color(1.0, 1.0, 1.0, 0.22)))
	return extras


func _fang_layers(index: int, frame: Vector2i) -> Array:
	var x: float = 12.0
	var tone: Color = _blade_tone(index)
	var blade: PackedVector2Array = PackedVector2Array([Vector2(x, 4.0), Vector2(x + 5.0, 46.0), Vector2(x + 4.0, 66.0), Vector2(x - 4.0, 66.0), Vector2(x - 5.0, 46.0)])
	var layers: Array = [
		_layer(_polygon(PackedVector2Array([Vector2(x, 2.0), Vector2(x + 7.0, 46.0), Vector2(x + 6.0, 66.0), Vector2(x - 6.0, 66.0), Vector2(x - 7.0, 46.0)])), Color(0.30, 0.30, 0.34)),
		_layer(_polygon(blade), tone),
		_layer(_rect(Vector2(x - 11.0, 66.0), Vector2(x + 11.0, 71.0)), Color(0.40, 0.40, 0.44)),
		_layer(_rect(Vector2(x - 2.5, 71.0), Vector2(x + 2.5, 88.0)), Color(0.36, 0.36, 0.40)),
		_layer(_ellipse(Vector2(x, 91.0), Vector2(4.0, 4.0)), Color(0.46, 0.46, 0.5)),
	]
	layers.append_array(_frame_extras(index, frame, x, 10.0, 62.0, 66.0, 9.0))
	return layers


func _warden_layers(index: int, frame: Vector2i) -> Array:
	var x: float = 20.0
	var tone: Color = _blade_tone(index)
	var layers: Array = [
		_layer(_polygon(PackedVector2Array([Vector2(x - 10.0, 90.0), Vector2(x - 10.0, 26.0), Vector2(x - 4.0, 10.0), Vector2(x, 4.0), Vector2(x + 4.0, 10.0), Vector2(x + 10.0, 26.0), Vector2(x + 10.0, 90.0)])), Color(0.30, 0.30, 0.34)),
		_layer(_polygon(PackedVector2Array([Vector2(x - 8.0, 88.0), Vector2(x - 8.0, 27.0), Vector2(x - 3.0, 12.0), Vector2(x, 7.0), Vector2(x + 3.0, 12.0), Vector2(x + 8.0, 27.0), Vector2(x + 8.0, 88.0)])), tone),
		_layer(_rect(Vector2(x - 0.8, 16.0), Vector2(x + 0.8, 84.0)), Color(0.62, 0.62, 0.68)),
		_layer(_rect(Vector2(x - 19.0, 90.0), Vector2(x + 19.0, 97.0)), Color(0.40, 0.40, 0.44)),
		_layer(_rect(Vector2(x - 3.0, 97.0), Vector2(x + 3.0, 116.0)), Color(0.36, 0.36, 0.40)),
		_layer(_ellipse(Vector2(x, 120.0), Vector2(6.0, 6.0)), Color(0.46, 0.46, 0.5)),
	]
	layers.append_array(_frame_extras(index, frame, x, 14.0, 86.0, 90.0, 13.0))
	return layers


func _pike_layers(index: int, frame: Vector2i) -> Array:
	var x: float = 14.0
	var tone: Color = _blade_tone(index)
	var head: PackedVector2Array = PackedVector2Array([Vector2(x, 2.0), Vector2(x + 10.0, 30.0), Vector2(x + 4.0, 56.0), Vector2(x - 4.0, 56.0), Vector2(x - 10.0, 30.0)])
	var rim: PackedVector2Array = PackedVector2Array([Vector2(x, 0.0), Vector2(x + 12.0, 30.0), Vector2(x + 5.5, 58.0), Vector2(x - 5.5, 58.0), Vector2(x - 12.0, 30.0)])
	var layers: Array = [
		_layer(_rect(Vector2(x - 2.5, 56.0), Vector2(x + 2.5, 164.0)), Color(0.34, 0.34, 0.38)),
		_layer(_polygon(rim), Color(0.30, 0.30, 0.34)),
		_layer(_polygon(head), tone),
		_layer(_rect(Vector2(x - 8.0, 58.0), Vector2(x + 8.0, 62.0)), Color(0.42, 0.42, 0.46)),
		_layer(_ellipse(Vector2(x, 168.0), Vector2(5.0, 5.0)), Color(0.46, 0.46, 0.5)),
	]
	layers.append_array(_frame_extras(index, frame, x, 8.0, 52.0, 60.0, 11.0))
	return layers


func _colossus_layers(index: int, frame: Vector2i) -> Array:
	var x: float = 32.0
	var tone: Color = _blade_tone(index)
	var layers: Array = [
		_layer(_polygon(PackedVector2Array([Vector2(x - 20.0, 150.0), Vector2(x - 20.0, 14.0), Vector2(x - 14.0, 4.0), Vector2(x + 14.0, 4.0), Vector2(x + 20.0, 14.0), Vector2(x + 20.0, 150.0)])), Color(0.30, 0.30, 0.34)),
		_layer(_polygon(PackedVector2Array([Vector2(x - 17.0, 148.0), Vector2(x - 17.0, 15.0), Vector2(x - 12.0, 8.0), Vector2(x + 12.0, 8.0), Vector2(x + 17.0, 15.0), Vector2(x + 17.0, 148.0)])), tone),
		_layer(_rect(Vector2(x - 1.5, 18.0), Vector2(x + 1.5, 140.0)), Color(0.60, 0.60, 0.66)),
		_layer(_rect(Vector2(x - 30.0, 150.0), Vector2(x + 30.0, 162.0)), Color(0.40, 0.40, 0.44)),
		_layer(_rect(Vector2(x - 5.0, 162.0), Vector2(x + 5.0, 192.0)), Color(0.36, 0.36, 0.40)),
		_layer(_ellipse(Vector2(x, 198.0), Vector2(9.0, 9.0)), Color(0.46, 0.46, 0.5)),
	]
	layers.append_array(_frame_extras(index, frame, x, 14.0, 144.0, 150.0, 22.0))
	return layers


# ------------------------------------------------------------- glow, shadow
func _soft_disc(name: String, size: int, inner: float, outer: float) -> void:
	var image: Image = Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var half: float = float(size) * 0.5
	for y: int in size:
		for x: int in size:
			var d: float = Vector2(float(x) + 0.5 - half, float(y) + 0.5 - half).length() / half
			var alpha: float = clampf(1.0 - d, 0.0, 1.0)
			alpha = alpha * alpha
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha * outer + inner))
	_save(image, name)


func _shadow() -> void:
	var image: Image = Image.create_empty(48, 24, false, Image.FORMAT_RGBA8)
	_paint(image, Vector2i.ZERO, Vector2i(48, 24), [_layer(_ellipse(Vector2(24.0, 12.0), Vector2(22.0, 10.0)), Color(0.0, 0.0, 0.0, 1.0))])
	_save(image, "shadow")
