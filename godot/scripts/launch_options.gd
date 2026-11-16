class_name LaunchOptions
extends RefCounted
## What the player asked for at launch, read from the platform: command-line
## user arguments (after `--`, e.g. `Swordster.exe -- --encounter=crowd`) or,
## in a browser, the page address (`index.html?encounter=crowd`). The value is
## `crowd` (the wave of husks, runners and brutes), `wall` (a crowd already
## pinned against the east wall), `spitters` (the wave of spitters and husks) or
## `conditions` (husks, runners and two brutes, for fire, poison and ice), `warden`
## (a mixed crowd against Fang / Warden / Warden: sweeping arcs and Maelstrom) or `pike`
## (a column of foes against three Pikes near the north wall: thrusts and Skewer) or `colossus`
## (a cluster and a wave against three Colossus swords: slams, Cataclysm and its three elemental fields) or `drops`
## (armed foes carrying swords of every type, rarity and element: kill one, stand on its drop, press 1 / 2 / 3).
## Anything else, or nothing, starts the normal run. The C key and the dev
## encounter button cycle the encounters at any time, so launch options are a
## convenience, not the only way in.

const ENCOUNTER_ARGUMENT_PREFIX: String = "--encounter="
const ENCOUNTER_QUERY: String = "encounter"


## The fixture scenario asked for at launch, or null for the normal run.
static func requested_scenario() -> RunScenario:
	return scenario_for(requested_encounter())


static func scenario_for(encounter: String) -> RunScenario:
	match encounter:
		"crowd":
			return RunScenario.crowd_encounter()
		"wall":
			return RunScenario.wall_encounter()
		"spitters":
			return RunScenario.spitter_encounter()
		"conditions":
			return RunScenario.conditions_encounter()
		"warden":
			return RunScenario.warden_encounter()
		"pike":
			return RunScenario.pike_encounter()
		"colossus":
			return RunScenario.colossus_encounter()
		"drops":
			return RunScenario.drops_encounter()
		_:
			return null


## The raw requested value ("" when none).
static func requested_encounter() -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(ENCOUNTER_ARGUMENT_PREFIX):
			return argument.trim_prefix(ENCOUNTER_ARGUMENT_PREFIX)
	if OS.has_feature("web"):
		var query: Variant = JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('%s')" % ENCOUNTER_QUERY)
		if query is String:
			return query as String
	return ""


const VISUALS_ARGUMENT_PREFIX: String = "--visuals="
const VISUALS_QUERY: String = "visuals"


## The visual set asked for at launch (`--visuals=textured`, `index.html?visuals=textured`), or "" for the default look.
## Which sets exist, and what an unknown value means: `VisualSets`.
static func requested_visuals() -> String:
	var from_arguments: String = visuals_from(OS.get_cmdline_user_args())
	if not from_arguments.is_empty():
		return from_arguments
	if OS.has_feature("web"):
		var query: Variant = JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('%s')" % VISUALS_QUERY)
		if query is String:
			return query as String
	return ""


## The value of the first `--visuals=` among `arguments` ("" when there is none).
static func visuals_from(arguments: PackedStringArray) -> String:
	for argument: String in arguments:
		if argument.begins_with(VISUALS_ARGUMENT_PREFIX):
			return argument.trim_prefix(VISUALS_ARGUMENT_PREFIX)
	return ""


## Issue #20. `--touch` / `?touch=1` shows the touch controls even where no touchscreen is reported (a desktop playtest of the
## touch UI); `--touch=0` / `?touch=0` hides them where one is.
const TOUCH_ARGUMENT: String = "--touch"
const TOUCH_QUERY: String = "touch"
## `--safe=top,right,bottom,left` / `?safe=...` (CSS-style pixels) stands in for the browser's safe-area insets, so a notch can be tried on any screen.
const SAFE_ARGUMENT_PREFIX: String = "--safe="
const SAFE_QUERY: String = "safe"


## "1" or "0" when the player asked for the touch controls on or off, "" for the platform's own answer.
static func requested_touch() -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument == TOUCH_ARGUMENT:
			return "1"
		if argument.begins_with(TOUCH_ARGUMENT + "="):
			return argument.trim_prefix(TOUCH_ARGUMENT + "=")
	if OS.has_feature("web"):
		return TouchPlatform.bridge_text(JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('%s')" % TOUCH_QUERY))
	return ""


## The requested stand-in safe-area insets as (top, right, bottom, left), or an empty array.
static func requested_safe_insets() -> PackedFloat32Array:
	var raw: String = ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(SAFE_ARGUMENT_PREFIX):
			raw = argument.trim_prefix(SAFE_ARGUMENT_PREFIX)
	if raw.is_empty() and OS.has_feature("web"):
		raw = TouchPlatform.bridge_text(JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('%s')" % SAFE_QUERY))
	return parse_insets(raw)


static func parse_insets(raw: String) -> PackedFloat32Array:
	var parts: PackedStringArray = raw.split(",")
	var values: PackedFloat32Array = PackedFloat32Array()
	if parts.size() != 4:
		return values
	for part: String in parts:
		if not part.strip_edges().is_valid_float():
			return PackedFloat32Array()
		values.append(maxf(part.strip_edges().to_float(), 0.0))
	return values
