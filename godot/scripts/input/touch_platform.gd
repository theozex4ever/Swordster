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


## The safe-area insets (left, top, right, bottom) in viewport pixels for a viewport `view` wide.
static func safe_insets(view: Vector2) -> Vector4:
	var override: PackedFloat32Array = LaunchOptions.requested_safe_insets()
	var css: Vector4 = Vector4.ZERO
	var css_width: float = maxf(view.x, 1.0)
	if override.size() == 4:
		css = Vector4(override[0], override[1], override[2], override[3])
	elif OS.has_feature("web"):
		var probed: Variant = JavaScriptBridge.eval(SAFE_AREA_PROBE)
		if probed is String:
			var parts: PackedStringArray = (probed as String).split(",")
			if parts.size() == 5:
				css = Vector4(parts[0].to_float(), parts[1].to_float(), parts[2].to_float(), parts[3].to_float())
				css_width = maxf(parts[4].to_float(), 1.0)
	else:
		var screen: Vector2i = DisplayServer.screen_get_size()
		var safe: Rect2i = DisplayServer.get_display_safe_area()
		if screen.x > 0 and safe.has_area():
			css = Vector4(float(safe.position.y), float(screen.x - safe.end.x), float(screen.y - safe.end.y), float(safe.position.x))
			css_width = float(screen.x)
	return TouchLayout.insets_from_css(css, view.x / css_width)


## Whether the browser (or the OS) lets the game go fullscreen.
static func fullscreen_supported() -> bool:
	if OS.has_feature("web"):
		var allowed: Variant = JavaScriptBridge.eval("document.fullscreenEnabled === true")
		return allowed == true
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
