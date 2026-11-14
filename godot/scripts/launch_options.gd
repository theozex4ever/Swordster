class_name LaunchOptions
extends RefCounted
## What the player asked for at launch, read from the platform: command-line
## user arguments (after `--`, e.g. `Swordster.exe -- --encounter=crowd`) or,
## in a browser, the page address (`index.html?encounter=crowd`). Any other
## value, or none, starts the normal run. The C key (and Crowd button) switches
## at any time, so launch options are a convenience, not the only way in.

const ENCOUNTER_ARGUMENT: String = "--encounter=crowd"
const ENCOUNTER_QUERY: String = "encounter"
const ENCOUNTER_VALUE: String = "crowd"


## True when the crowd encounter fixture was asked for at launch.
static func crowd_requested() -> bool:
	if OS.get_cmdline_user_args().has(ENCOUNTER_ARGUMENT):
		return true
	if OS.has_feature("web"):
		var query: Variant = JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('%s')" % ENCOUNTER_QUERY)
		return query is String and (query as String) == ENCOUNTER_VALUE
	return false
