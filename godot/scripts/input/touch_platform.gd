class_name TouchPlatform
extends RefCounted
## What the host platform says about touch (issue #20): whether a touchscreen is there, the safe-area insets, whether the
## browser offers fullscreen, and a hook that reports the page being hidden. Everything else about touch is the same on
## every platform; this is the one place that asks the browser.

## The probe: a hidden element padded by the page's safe-area `env()` values reads them back as plain numbers, and the
## page's inner width says how many CSS pixels the viewport spans. "top,right,bottom,left,innerWidth".
const SAFE_AREA_PROBE: String = "(function(){var d=document.createElement('div');d.style.cssText='position:fixed;left:0;top:0;visibility:hidden;pointer-events:none;padding:env(safe-area-inset-top,0px) env(safe-area-inset-right,0px) env(safe-area-inset-bottom,0px) env(safe-area-inset-left,0px)';document.body.appendChild(d);var s=getComputedStyle(d);var r=[s.paddingTop,s.paddingRight,s.paddingBottom,s.paddingLeft].map(parseFloat);document.body.removeChild(d);return r.join(',')+','+window.innerWidth;})()"
## Calls `window.__swordsterSuspend()` when the page is hidden, is being left or loses focus; installed once.
const SUSPEND_HOOK: String = "(function(){if(window.__swordsterHookInstalled){return;}window.__swordsterHookInstalled=true;var fire=function(){if(window.__swordsterSuspend){window.__swordsterSuspend();}};document.addEventListener('visibilitychange',function(){if(document.hidden){fire();}});window.addEventListener('pagehide',fire);window.addEventListener('blur',fire);})()"

var _suspend_callback: JavaScriptObject


## True when the platform reports a touchscreen (`--touch` / `?touch=` override it either way).
static func touchscreen_present() -> bool:
	match LaunchOptions.requested_touch():
		"1":
			return true
		"0":
			return false
	return DisplayServer.is_touchscreen_available()


## What a value the browser bridge returned means as a yes / no. The bridge's types are not fixed: a JavaScript `true` can come
## back as a `bool`, as the number 1 (an `int` or a `float`) or as text, and a script that could not run as `null`. Only a clear
## yes counts: `true`, a non-zero number, or the text "true" / "1" / "yes" (any case).
static func bridge_truthy(value: Variant) -> bool:
	if value is bool:
		return value
	if value is int or value is float:
		return float(value) != 0.0
	if value is String or value is StringName:
		return String(value).strip_edges().to_lower() in ["true", "1", "yes"]
	return false


## A value the browser bridge returned as text ("" for null or anything that is not text or a number).
static func bridge_text(value: Variant) -> String:
	if value is String or value is StringName:
		return String(value)
	if value is int or value is float:
		return str(value)
	return ""


## The safe-area insets (left, top, right, bottom) in viewport pixels for a viewport `view` wide. In a browser the page's
## `env(safe-area-inset-*)` are read in CSS pixels together with the page's width; `?safe=` / `--safe=` stand in for them in the same
## unit and go through the very same conversion onto the viewport (`insets_from_css_values`). Elsewhere an override is in window pixels.
static func safe_insets(view: Vector2) -> Vector4:
	var override: PackedFloat32Array = LaunchOptions.requested_safe_insets()
	var override_css: Vector4 = Vector4.ZERO
	if override.size() == 4:
		override_css = Vector4(override[0], override[1], override[2], override[3])
	if OS.has_feature("web"):
		var probe: PackedFloat32Array = parse_probe(bridge_text(JavaScriptBridge.eval(SAFE_AREA_PROBE)))
		if probe.size() != 5:
			return Vector4.ZERO
		var page_width: float = probe[4]
		if override.size() == 4:
			return insets_from_css_values(override_css, page_width, view.x)
		return insets_from_css_values(Vector4(probe[0], probe[1], probe[2], probe[3]), page_width, view.x)
	if override.size() == 4:
		return insets_from_css_values(override_css, float(DisplayServer.window_get_size().x), view.x)
	var screen: Vector2i = DisplayServer.screen_get_size()
	var safe: Rect2i = DisplayServer.get_display_safe_area()
	if screen.x > 0 and safe.has_area():
		var edges: Vector4 = Vector4(float(safe.position.y), float(screen.x - safe.end.x), float(screen.y - safe.end.y), float(safe.position.x))
		return insets_from_css_values(edges, float(screen.x), view.x)
	return Vector4.ZERO


## Insets given as (top, right, bottom, left) in the units of a page `page_width` wide, as viewport insets (left, top, right,
## bottom) for a viewport `view_width` wide. A page width of zero or less leaves the numbers as they are.
static func insets_from_css_values(edges: Vector4, page_width: float, view_width: float) -> Vector4:
	var per_unit: float = 1.0 if page_width <= 0.0 else view_width / page_width
	return TouchLayout.insets_from_css(edges, per_unit)


## The probe's answer "top,right,bottom,left,innerWidth" as five numbers, or none when it is not that.
static func parse_probe(text: String) -> PackedFloat32Array:
	var parts: PackedStringArray = text.split(",")
	var values: PackedFloat32Array = PackedFloat32Array()
	if parts.size() != 5:
		return values
	for part: String in parts:
		if not part.strip_edges().is_valid_float():
			return PackedFloat32Array()
		values.append(part.strip_edges().to_float())
	return values


## Whether the browser (or the OS) lets the game go fullscreen.
static func fullscreen_supported() -> bool:
	if OS.has_feature("web"):
		return bridge_truthy(JavaScriptBridge.eval("document.fullscreenEnabled === true"))
	return not OS.has_feature("mobile")


static func toggle_fullscreen() -> void:
	var fullscreen: bool = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if fullscreen else DisplayServer.WINDOW_MODE_FULLSCREEN)


## In a browser: calls `on_suspend` whenever the page is hidden, left or blurred (the tab switched, the app sent to the
## background, the screen locked). The engine reports some of these as focus loss itself; this makes none of them depend on it.
func install_suspend_hook(on_suspend: Callable) -> void:
	if not OS.has_feature("web"):
		return
	_suspend_callback = JavaScriptBridge.create_callback(func(_arguments: Array) -> void: on_suspend.call())
	JavaScriptBridge.get_interface("window").set("__swordsterSuspend", _suspend_callback)
	JavaScriptBridge.eval(SUSPEND_HOOK)
