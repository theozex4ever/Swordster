class_name TouchPlatform
extends RefCounted
## What the host platform says about touch (issue #20): whether a touchscreen is there, the safe-area insets, whether the
## browser offers fullscreen, a hook that reports the page being hidden, and a hook that reports a finger the browser took
## (a cancelled touch, which the Web engine does not report as one). Everything else about touch is the same on every
## platform; this is the one place that asks the browser.

## The probe: a hidden element padded by the page's safe-area `env()` values reads them back as plain numbers, and the
## page's inner width says how many CSS pixels the viewport spans. "top,right,bottom,left,innerWidth".
const SAFE_AREA_PROBE: String = "(function(){var d=document.createElement('div');d.style.cssText='position:fixed;left:0;top:0;visibility:hidden;pointer-events:none;padding:env(safe-area-inset-top,0px) env(safe-area-inset-right,0px) env(safe-area-inset-bottom,0px) env(safe-area-inset-left,0px)';document.body.appendChild(d);var s=getComputedStyle(d);var r=[s.paddingTop,s.paddingRight,s.paddingBottom,s.paddingLeft].map(parseFloat);document.body.removeChild(d);return r.join(',')+','+window.innerWidth;})()"
## Calls `window.__swordsterSuspend()` when the page is hidden, is being left or loses focus; installed once.
const SUSPEND_HOOK: String = "(function(){if(window.__swordsterHookInstalled){return;}window.__swordsterHookInstalled=true;var fire=function(){if(window.__swordsterSuspend){window.__swordsterSuspend();}};document.addEventListener('visibilitychange',function(){if(document.hidden){fire();}});window.addEventListener('pagehide',fire);window.addEventListener('blur',fire);})()"

## A browser tells the page when it takes a finger away (`touchcancel`: a system gesture, the notification shade, a palm), but
## the pinned Web engine hears `touchcancel` with the very handler it hears `touchend` with, so the game would get a plain
## lift, and a lift is a tap. This listener hears the browser first (capture phase on the window, which runs before the
## engine's own listener on the canvas) and calls `window.__swordsterTouchCancel(identifier, x, y)` for each finger taken
## from the game's canvas: the identifier as the engine numbers its touch index (a 32-bit integer) and the place in canvas
## pixels as the engine computes it. The engine's own lift for that finger follows and finds nothing left to lift. Without
## the callback (or if it throws) nothing is done here and the engine's lift stands, as before. Installed once.
const CANCEL_HOOK: String = "(function(){if(window.__swordsterCancelHookInstalled){return;}window.__swordsterCancelHookInstalled=true;window.addEventListener('touchcancel',function(evt){var feed=window.__swordsterTouchCancel,canvas=evt.target;if(typeof feed!=='function'||!(canvas instanceof HTMLCanvasElement)){return;}var rect=canvas.getBoundingClientRect();var sx=rect.width>0?canvas.width/rect.width:1,sy=rect.height>0?canvas.height/rect.height:1;for(var i=0;i<evt.changedTouches.length;i++){var t=evt.changedTouches[i];try{feed(t.identifier|0,(t.clientX-rect.x)*sx,(t.clientY-rect.y)*sy);}catch(e){}}},true);})()"

var _suspend_callback: JavaScriptObject
var _cancel_callback: JavaScriptObject


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
## unit and go through the very same conversion onto the viewport (`insets_from_probe`). Elsewhere an override is in window pixels.
static func safe_insets(view: Vector2) -> Vector4:
	var override: PackedFloat32Array = LaunchOptions.requested_safe_insets()
	if OS.has_feature("web"):
		return insets_from_probe(parse_probe(bridge_text(JavaScriptBridge.eval(SAFE_AREA_PROBE))), override, view.x)
	if override.size() == 4:
		return insets_from_css_values(Vector4(override[0], override[1], override[2], override[3]), float(DisplayServer.window_get_size().x), view.x)
	var screen: Vector2i = DisplayServer.screen_get_size()
	var safe: Rect2i = DisplayServer.get_display_safe_area()
	if screen.x > 0 and safe.has_area():
		var edges: Vector4 = Vector4(float(safe.position.y), float(screen.x - safe.end.x), float(screen.y - safe.end.y), float(safe.position.x))
		return insets_from_css_values(edges, float(screen.x), view.x)
	return Vector4.ZERO


## The browser's insets for a viewport `view_width` wide: from the page's probe ("top,right,bottom,left,innerWidth" as five
## numbers), or from an override of four numbers in its place. A probe that failed (not five numbers) gives no insets of its
## own, but an override still applies: the page's width is then unknown, so its numbers are taken as they are.
static func insets_from_probe(probe: PackedFloat32Array, override: PackedFloat32Array, view_width: float) -> Vector4:
	var page_width: float = probe[4] if probe.size() == 5 else 0.0
	if override.size() == 4:
		return insets_from_css_values(Vector4(override[0], override[1], override[2], override[3]), page_width, view_width)
	if probe.size() != 5:
		return Vector4.ZERO
	return insets_from_css_values(Vector4(probe[0], probe[1], probe[2], probe[3]), page_width, view_width)


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


## In a browser: has the page report every finger the browser takes away (see `CANCEL_HOOK`). Native platforms report a
## cancelled touch themselves (`InputEventScreenTouch.canceled`) and need nothing.
func install_cancel_hook() -> void:
	if not OS.has_feature("web"):
		return
	_cancel_callback = JavaScriptBridge.create_callback(TouchPlatform.feed_cancelled_touch)
	JavaScriptBridge.get_interface("window").set("__swordsterTouchCancel", _cancel_callback)
	JavaScriptBridge.eval(CANCEL_HOOK)


## What the page calls for a finger the browser took: `arguments` is (identifier, x, y). The engine's input is given the
## cancelled touch a native platform would have reported, so everything after it (the pointers, the buttons, the engine's
## mouse emulation) sees one kind of cancel on every platform. Anything that is not those three numbers is ignored.
static func feed_cancelled_touch(arguments: Array) -> void:
	var event: InputEventScreenTouch = cancelled_touch(arguments)
	if event != null:
		Input.parse_input_event(event)


## The cancelled touch for the page's (identifier, x, y), or null when the arguments are not that: three numbers (the bridge
## hands a whole number over as an `int` and any other as a `float`), the first a whole one.
static func cancelled_touch(arguments: Array) -> InputEventScreenTouch:
	var numbers: PackedFloat64Array = PackedFloat64Array()
	for value: Variant in arguments:
		if (value is int or value is float) and is_finite(float(value)):
			numbers.append(float(value))
	if arguments.size() != 3 or numbers.size() != 3 or numbers[0] != floorf(numbers[0]):
		return null
	var event: InputEventScreenTouch = InputEventScreenTouch.new()
	event.index = int(numbers[0])
	event.position = Vector2(numbers[1], numbers[2])
	event.pressed = false
	event.canceled = true
	return event
