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
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(VISUALS_ARGUMENT_PREFIX):
			return argument.trim_prefix(VISUALS_ARGUMENT_PREFIX)
	if OS.has_feature("web"):
		var query: Variant = JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('%s')" % VISUALS_QUERY)
		if query is String:
			return query as String
	return ""
