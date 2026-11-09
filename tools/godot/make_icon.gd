extends SceneTree
## Renders godot/icon.svg to godot/icon.png (256px) and a multi-size PNG-in-ICO
## godot/icon.ico (16-256px). Authoring helper; the committed outputs are what
## the build uses.
## Run from the repo root: godot --headless --script tools/godot/make_icon.gd

const SIZES: Array[int] = [16, 32, 48, 64, 128, 256]


func _init() -> void:
	var svg_path: String = _arg("--svg", "godot/icon.svg")
	var out_dir: String = _arg("--out", "godot")
	var svg: String = FileAccess.get_file_as_string(svg_path)
	var pngs: Array[PackedByteArray] = []
	for size: int in SIZES:
		var image: Image = Image.new()
		if image.load_svg_from_string(svg, float(size) / 64.0) != OK:
			push_error("svg load failed")
			quit(1)
			return
		if image.get_width() != size:
			image.resize(size, size, Image.INTERPOLATE_LANCZOS)
		pngs.append(image.save_png_to_buffer())
	FileAccess.open(out_dir.path_join("icon.png"), FileAccess.WRITE).store_buffer(pngs[pngs.size() - 1])

	var ico: PackedByteArray = PackedByteArray()
	ico.resize(6)
	ico.encode_u16(2, 1)  # type: icon
	ico.encode_u16(4, SIZES.size())
	var offset: int = 6 + 16 * SIZES.size()
	var data: PackedByteArray = PackedByteArray()
	for i: int in SIZES.size():
		var entry: PackedByteArray = PackedByteArray()
		entry.resize(16)
		var dim: int = 0 if SIZES[i] >= 256 else SIZES[i]
		entry.encode_u8(0, dim)
		entry.encode_u8(1, dim)
		entry.encode_u16(4, 1)  # planes
		entry.encode_u16(6, 32)  # bits per pixel
		entry.encode_u32(8, pngs[i].size())
		entry.encode_u32(12, offset + data.size())
		ico.append_array(entry)
		data.append_array(pngs[i])
	ico.append_array(data)
	FileAccess.open(out_dir.path_join("icon.ico"), FileAccess.WRITE).store_buffer(ico)
	print("icon.png %d bytes, icon.ico %d bytes (%d sizes)" % [pngs[pngs.size() - 1].size(), ico.size(), SIZES.size()])
	quit(0)


func _arg(name: String, fallback: String) -> String:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var i: int = args.find(name)
	if i != -1 and i + 1 < args.size():
		return args[i + 1]
	return fallback
