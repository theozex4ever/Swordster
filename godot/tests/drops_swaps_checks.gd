class_name DropsSwapsChecks
extends RefCounted
## Behavioural checks for armed enemies, the swords they drop, the rarity modifiers and swapping a drop into a sword slot
## (issue #17). Like the earlier slices' checks, every check drives the real `GameRun` through `GameCommand`s (or the real
## Main scene with real key events), advances fixed ticks and observes outcomes. Comparison values come from the Python
## prototype's captured reference (res://tests/reference/drops_swaps.json, recorded by tools/reference/capture_drops_swaps.py
## from the prototype's own `Sword`, `Enemy`, `Pickup`, `Game.kill`, `Game.start_wave`, `Game.update`, `Game.swap` and
## `Game.draw_pickup_card`), so no number is copied into this file. Tolerances and deliberate exceptions:
## docs/reference/drops-swaps.md.

const REFERENCE_PATH: String = "res://tests/reference/drops_swaps.json"
const PROBE_SCRIPT: String = "res://tests/frame_rate_probe.gd"

const POSITION_TOL: float = 0.05  # px
const VELOCITY_TOL: float = 0.5  # px/s (the prototype's value is a rounded position difference x 60)
const SCALAR_TOL: float = 0.002  # timers, cooldowns, flash
const STAT_TOL: float = 0.0006  # the reference rounds to four places
const ANGLE_TOL: float = 0.002
const PROBE_FRAME_RATES: Array[int] = [5, 20, 60, 240]
const CENTER: Vector2 = Vector2(1300.0, 900.0)
const PARKED: float = 99.0
const SWAP_KEY_CODES: Array[Key] = [KEY_1, KEY_2, KEY_3]
## How far from its drop the pickup card's centre may be, in view pixels (the card is 448 x 214; the drops legend and the HUD above it can force it
## a screen's third away).
const CARD_NEAR_LIMIT: float = 500.0

var _check: Callable
var _tree: SceneTree
var _ref: Dictionary = {}


func _init(check_function: Callable, tree: SceneTree) -> void:
	_check = check_function
	_tree = tree


func run_all() -> void:
	if not CheckFocus.includes("drops_swaps"):
		return
	var file: FileAccess = FileAccess.open(REFERENCE_PATH, FileAccess.READ)
	if file == null:
		_ok("drops and swaps reference file loads", false, REFERENCE_PATH)
		return
	_ref = JSON.parse_string(file.get_as_text())
	_ok("drops and swaps reference file parses", not _ref.is_empty())
	_check_reference_scope()
	if not _check_identity():
		print("drops and swaps: a sword type's identity is wrong; the remaining checks build fixtures from the prototype's keys and are skipped")
		return
	_check_definitions()
	_check_matrix()
	_check_arming()
	_check_armed_waves()
	_check_death_drops()
	_check_life()
	_check_blink()
	_check_reach()
	_check_swaps()
	_check_returned_drops()
	_check_repeated()
	_check_swap_and_converge()
	_check_trace()
	_check_rules()
	_check_cues()
	_check_shared_definitions()
	_check_fight()
	await _check_main_scene()
	await _check_hud()
	await _check_card_text_bounds()
	await _check_card_clearance()
	await _check_encounter()
	await _check_visual_independence()
	await _check_render_rates()


# --------------------------------------------------------------- helpers
func _ok(label: String, condition: bool, detail: String = "") -> void:
	_check.call(label, condition, detail)


func _near(a: float, b: float, tolerance: float) -> bool:
	return absf(a - b) <= tolerance


func _spec(values: Array) -> SwordSpec:
	return SwordSpec.make(StringName(values[0]), int(values[1]), StringName(values[2]))


func _spec_array(spec: SwordSpec) -> Array:
	return [String(spec.type_id), spec.rarity, String(spec.element)]


func _same(spec: SwordSpec, values: Array) -> bool:
	var other: SwordSpec = _spec(values)
	return spec.type_id == other.type_id and spec.rarity == other.rarity and spec.element == other.element


## A run with the given swords in its slots (all parked, so nothing attacks), no enemies and no waves.
func _run_of(specs: Array, seed_value: int = 41, extra_cooldowns: bool = true) -> GameRun:
	var scenario: RunScenario = RunScenario.new()
	scenario.seed = seed_value
	scenario.waves_enabled = false
	scenario.crit_chance = 0.0
	var loadout: Array[SwordSpec] = []
	var cooldowns: Array[float] = []
	for entry: Variant in specs:
		loadout.append(_spec(entry as Array))
		cooldowns.append(PARKED)
	scenario.loadout = loadout
	if extra_cooldowns:
		scenario.sword_start_cooldowns = cooldowns
	return GameRun.new(scenario)


func _default_specs() -> Array:
	return [["fang", 0, "poison"], ["blade", 0, "ice"], ["colossus", 0, "fire"]]


var _serial: int = 1000


## A pickup lying `dx`, `dy` from the player.
func _put(run: GameRun, values: Array, dx: float, dy: float) -> PickupState:
	_serial += 1
	var pickup: PickupState = PickupState.make(_spec(values), run.position + Vector2(dx, dy), _serial)
	run.pickups.append(pickup)
	return pickup


func _steps(run: GameRun, count: int) -> void:
	for i: int in count:
		run.step()


func _swap_key(run: GameRun, slot: int) -> void:
	var translator: InputTranslator = InputTranslator.new()
	for command: GameCommand in translator.handle_event(_key(SWAP_KEY_CODES[slot])):
		run.apply(command)


func _key(code: Key) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = true
	return event


## Whether the run's swords are exactly `expected` (JSON arrays: the rarity comes back from the parser as a float).
func _specs_match(run: GameRun, expected: Array) -> bool:
	if run.swords.size() != expected.size():
		return false
	for i: int in expected.size():
		if not _same(run.swords[i].spec, expected[i] as Array):
			return false
	return true


func _specs_of(run: GameRun) -> Array:
	var shown: Array = []
	for sword: SwordState in run.swords:
		shown.append(_spec_array(sword.spec))
	return shown


func _phase_name(sword: SwordState) -> String:
	match sword.phase:
		SwordState.Phase.IDLE:
			return "idle"
		SwordState.Phase.WINDUP:
			return "windup"
		SwordState.Phase.STRIKE:
			return "strike"
		SwordState.Phase.RECOVER:
			return "recover"
		SwordState.Phase.STUCK:
			return "stuck"
		_:
			return "ult"


## Whether a freshly swapped-in sword matches the reference's `new` (what the prototype's swap made), field by field.
func _matches_new(sword: SwordState, expected: Dictionary) -> String:
	var problems: Array[String] = []
	if String(sword.spec.type_id) != String(expected["kind"]) or sword.spec.rarity != int(expected["rarity"]) or String(sword.spec.element) != String(expected["element"]):
		problems.append("identity %s" % [_spec_array(sword.spec)])
	if sword.spec.display_name() != String(expected["name"]):
		problems.append("name %s" % sword.spec.display_name())
	var numbers: Dictionary = {
		"damage": [sword.damage, STAT_TOL], "cooldown": [sword.cooldown, STAT_TOL], "range": [sword.attack_range, STAT_TOL],
		"ult_max": [sword.ultimate_cooldown, STAT_TOL], "scale": [sword.size_scale, STAT_TOL], "length": [sword.length, STAT_TOL],
		"ult_cd": [sword.ultimate_cooldown_left, SCALAR_TOL], "cd": [sword.cooldown_left, SCALAR_TOL], "flash": [sword.flash, SCALAR_TOL],
		"vx": [sword.velocity.x, VELOCITY_TOL], "vy": [sword.velocity.y, VELOCITY_TOL], "x": [sword.position.x, POSITION_TOL], "y": [sword.position.y, POSITION_TOL],
	}
	for key: String in numbers:
		var pair: Array = numbers[key]
		if not _near(float(pair[0]), float(expected[key]), float(pair[1])):
			problems.append("%s %f vs %f" % [key, float(pair[0]), float(expected[key])])
	if sword.spec.type_id == SwordDefs.COLOSSUS and not _near(sword.altitude, float(expected["z"]), 0.01):
		problems.append("altitude %f vs z %f" % [sword.altitude, float(expected["z"])])
	if _phase_name(sword) != String(expected["state"]):
		problems.append("state %s" % _phase_name(sword))
	return ", ".join(problems)


# --------------------------------------------------------------- scope
func _check_reference_scope() -> void:
	print("drops and swaps: the reference's scope")
	var scope: Dictionary = _ref["fixture_scope"]
	_ok("the capture ran no waves, no Converge and parked swords; start_wave only in the arming cases", not bool(scope["waves_running"]) and not bool(scope["converge_used"]) and bool(scope["auto_attack_parked"]) and bool(scope["start_wave_only_in_arming_cases"]))
	_ok("the reference holds every case this group compares", ["table", "matrix", "arming", "drops", "life", "reach", "swaps", "repeated", "trace", "rules"].all(func(key: String) -> bool: return _ref.has(key) and not (_ref[key] as Variant == null)))


# --------------------------------------------------------------- definitions
## Returns false when a sword type's internal key is not the prototype's (or the type is not equippable); every later check builds
## its fixtures from the reference's keys, so they must not run (a renamed key would only crash them).
func _check_identity() -> bool:
	print("drops and swaps: the sword types' identity")
	var kinds: Array[String] = []
	for entry: Variant in (_ref["table"] as Dictionary)["types"]:
		kinds.append(String((entry as Dictionary)["kind"]))
	var wrong: Array[String] = []
	for type_id: StringName in [SwordDefs.FANG, SwordDefs.WARDEN, SwordDefs.PIKE, SwordDefs.COLOSSUS]:
		if not (kinds.has(String(type_id)) and SwordDefs.is_supported(type_id)):
			wrong.append(String(type_id))
	for key: String in ["fang", "blade", "lance", "colossus"]:
		if not kinds.has(key) or not SwordDefs.is_supported(StringName(key)):
			wrong.append(key)
	_ok("the four sword types keep the prototype's internal keys (fang, blade, lance, colossus) and are all equippable", wrong.is_empty(), str(wrong))
	return wrong.is_empty()


func _check_definitions() -> void:
	print("drops and swaps: the tables")
	var table: Dictionary = _ref["table"]
	var rarities: Array = table["rarities"]
	var rarity_ok: bool = rarities.size() == 3
	for i: int in rarities.size():
		var entry: Dictionary = rarities[i]
		var color: Array = entry["color"]
		rarity_ok = rarity_ok and SwordDefs.RARITY_NAMES[i] == String(entry["name"]) and _near(SwordDefs.RARITY_DAMAGE[i], float(entry["dmg"]), 1e-9) and _near(SwordDefs.RARITY_COOLDOWN[i], float(entry["cd"]), 1e-9) \
			and _near(SwordDefs.RARITY_RANGE[i], float(entry["rng"]), 1e-9) and _near(SwordDefs.RARITY_SIZE[i], float(entry["size"]), 1e-9) \
			and _near(SwordDefs.RARITY_COLORS[i].r8, int(color[0]), 0.5) and _near(SwordDefs.RARITY_COLORS[i].g8, int(color[1]), 0.5) and _near(SwordDefs.RARITY_COLORS[i].b8, int(color[2]), 0.5)
	_ok("Common, Rare and Mythic: names, damage, cooldown, range and size factors and colours are the prototype's", rarity_ok)
	var elements: Array = table["elements"]
	var element_ok: bool = elements.size() == 3
	for i: int in elements.size():
		var entry: Dictionary = elements[i]
		var color: Array = entry["color"]
		var key: StringName = StringName(entry["key"])
		var drawn: Color = PlaceholderSwordVisual.ELEMENT_COLORS[key]
		element_ok = element_ok and SwordDefs.ELEMENT_ORDER[i] == key and SwordDefs.ELEMENT_ADJECTIVES[key] == String(entry["adj"]) and SwordDefs.ELEMENT_TAGS[key] == String(entry["tag"]) \
			and _near(drawn.r * 255.0, float(color[0]), 2.0) and _near(drawn.g * 255.0, float(color[1]), 2.0) and _near(drawn.b * 255.0, float(color[2]), 2.0)
	_ok("fire, ice and poison: the prototype's order, adjectives (Ember, Frost, Venom), card tags and colours", element_ok)
	var types: Array = table["types"]
	var type_ok: bool = types.size() == 4
	for entry: Variant in types:
		var type_id: StringName = StringName((entry as Dictionary)["kind"])
		var spec: SwordSpec = SwordSpec.make(type_id, 0, &"fire")
		type_ok = type_ok and SwordDefs.display_name(type_id) == String((entry as Dictionary)["name"]) and SwordDefs.blurb(type_id) == String((entry as Dictionary)["blurb"]) \
			and _near(SwordDefs.damage_of(spec), float((entry as Dictionary)["damage"]), 1e-9) and _near(SwordDefs.cooldown_of(spec), float((entry as Dictionary)["cooldown"]), 1e-9) and _near(SwordDefs.range_of(spec), float((entry as Dictionary)["range"]), 1e-9) \
			and SwordDefs.ultimate_name(type_id) == String((entry as Dictionary)["ult_name"]) and _near(SwordDefs.ultimate_recharge_of(spec), float((entry as Dictionary)["ult_cd"]), 1e-9) and SwordDefs.ultimate_is_shot(type_id) == bool((entry as Dictionary)["ult_shot"])
	_ok("the four sword types: display names, blurbs, base stats and ultimates", type_ok)
	var weights: Array = table["drop_weights"]
	var weights_ok: bool = weights.size() == LootDefs.DROP_TYPES.size()
	for i: int in weights.size():
		weights_ok = weights_ok and LootDefs.DROP_TYPES[i] == StringName((weights[i] as Array)[0]) and _near(LootDefs.DROP_WEIGHTS[i], float((weights[i] as Array)[1]), 1e-9)
	_ok("armed enemies drop Fang 3, Warden 3, Pike 2.5 and Colossus 1.6 (the prototype's weights, in its order)", weights_ok)
	var chances: Dictionary = table["armed_chance"]
	_ok("armed chances: husk 20 %, runner 12 %, spitter 22 %, brute 75 %", ["husk", "runner", "spitter", "brute"].all(func(kind: String) -> bool: return _near(LootDefs.armed_chance(StringName(kind)), float(chances[kind]), 1e-9)))
	_ok("a dropped sword lies %.0f s and is claimed within %.0f px" % [LootDefs.PICKUP_LIFE, LootDefs.PICKUP_REACH], _near(LootDefs.PICKUP_LIFE, float((table["pickup"] as Dictionary)["life"]), 1e-9) and _near(LootDefs.PICKUP_REACH, float((table["swap"] as Dictionary)["reach"]), 1e-9))
	var hp_ok: bool = true
	var hp_detail: String = ""
	for entry: Variant in table["armed_hp"]:
		var row: Dictionary = entry as Dictionary
		var kind: StringName = StringName(row["kind"])
		var plain: EnemyState = EnemyState.make(kind, Vector2.ZERO, int(row["wave"]), 1.0, 1)
		var armed: EnemyState = EnemyState.make(kind, Vector2.ZERO, int(row["wave"]), 1.0, 2, 0.0, 0.0, SwordSpec.make(&"fang", 0, &"fire"))
		if not (_near(plain.max_hp, float(row["unarmed"]), STAT_TOL) and _near(armed.max_hp, float(row["armed"]), STAT_TOL) and _near(armed.hp, armed.max_hp, 1e-9) and plain.armed == null and armed.armed != null):
			hp_ok = false
			hp_detail += "%s w%d: %f/%f vs %f/%f; " % [kind, int(row["wave"]), plain.max_hp, armed.max_hp, float(row["unarmed"]), float(row["armed"])]
	_ok("an armed enemy has 1.35 x the health of an unarmed one, for every kind and wave (%d cases)" % (table["armed_hp"] as Array).size(), hp_ok, hp_detail)
	var swap: Dictionary = table["swap"]
	_ok("a swapped-in sword starts with a %.1f s cooldown, at height %.0f, rising at %s px/s with a flash of %.0f; the returned drop falls %.0f px and up to %.0f px aside" % [LootDefs.SWAP_START_COOLDOWN, LootDefs.SWAP_ALTITUDE, LootDefs.SWAP_START_VELOCITY.y, LootDefs.SWAP_FLASH, LootDefs.RETURN_DROP, LootDefs.RETURN_SPREAD],
		_near(LootDefs.SWAP_START_COOLDOWN, float(swap["new_cd"]), 1e-9) and _near(LootDefs.SWAP_ALTITUDE, float(swap["new_z"]), 1e-9) and _near(LootDefs.SWAP_FLASH, float(swap["new_flash"]), 1e-9)
		and _near(LootDefs.SWAP_START_VELOCITY.x, float(swap["new_vx"]), 1e-9) and _near(LootDefs.SWAP_START_VELOCITY.y, float(swap["new_vy"]), 1e-9)
		and (swap["returned_dy"] as Array).size() == 1 and _near(LootDefs.RETURN_DROP, float((swap["returned_dy"] as Array)[0]), 1e-9)
		and float(swap["returned_dx_min"]) >= -LootDefs.RETURN_SPREAD and float(swap["returned_dx_max"]) <= LootDefs.RETURN_SPREAD and float(swap["returned_dx_max"]) > LootDefs.RETURN_SPREAD * 0.9 and float(swap["returned_dx_min"]) < -LootDefs.RETURN_SPREAD * 0.9)


# --------------------------------------------------------------- the rarity matrix
func _check_matrix() -> void:
	print("drops and swaps: every type, rarity and element")
	var matrix: Array = _ref["matrix"]
	_ok("the reference covers the 36 combinations", matrix.size() == 36)
	var bad_swords: Array[String] = []
	var bad_cards: Array[String] = []
	var bad_colors: Array[String] = []
	for entry: Variant in matrix:
		var row: Dictionary = entry as Dictionary
		var spec: SwordSpec = SwordSpec.make(StringName(row["kind"]), int(row["rarity"]), StringName(row["element"]))
		var sword: SwordState = SwordState.equip(spec, Vector2.ZERO, 0.0)
		var expected: Dictionary = row.duplicate()
		expected["ult_cd"] = 0.0
		expected["cd"] = 0.0
		expected["flash"] = 0.0
		expected["vx"] = 0.0
		expected["vy"] = 0.0
		expected["x"] = 0.0
		expected["y"] = 0.0
		expected["z"] = sword.altitude
		expected["state"] = "idle"
		var problems: String = _matches_new(sword, expected)
		if not problems.is_empty():
			bad_swords.append("%s: %s" % [spec.display_name(), problems])
		var card: Array[String] = PickupCard.lines(spec)
		if card != (row["card"] as Array):
			bad_cards.append("%s: %s vs %s" % [spec.display_name(), card, row["card"]])
		var color: Array = row["color"]
		var drawn: Color = PlaceholderSwordVisual.ELEMENT_COLORS[spec.element]
		if not (_near(drawn.r * 255.0, float(color[0]), 2.0) and _near(drawn.g * 255.0, float(color[1]), 2.0) and _near(drawn.b * 255.0, float(color[2]), 2.0)):
			bad_colors.append(spec.display_name())
	_ok("every type x rarity x element is equipped with the prototype's damage, cooldown, range, recharge, size, length and name (%d wrong: %s)" % [bad_swords.size(), bad_swords.slice(0, 3)], bad_swords.is_empty())
	_ok("every pickup card reads exactly the prototype's six lines: name, blurb, DMG / SPD / RNG, element tag, ULT line and key hint (%d wrong: %s)" % [bad_cards.size(), bad_cards.slice(0, 2)], bad_cards.is_empty())
	_ok("every element tints its sword the same colour whatever the type and rarity (%d wrong)" % bad_colors.size(), bad_colors.is_empty())
	# Rarity must make a sword strictly stronger and quicker, and bigger: Common < Rare < Mythic for every type.
	var ladder_ok: bool = true
	for type_id: StringName in [SwordDefs.FANG, SwordDefs.WARDEN, SwordDefs.PIKE, SwordDefs.COLOSSUS]:
		var common: SwordState = SwordState.equip(SwordSpec.make(type_id, 0, &"fire"), Vector2.ZERO, 0.0)
		var rare: SwordState = SwordState.equip(SwordSpec.make(type_id, 1, &"fire"), Vector2.ZERO, 0.0)
		var mythic: SwordState = SwordState.equip(SwordSpec.make(type_id, 2, &"fire"), Vector2.ZERO, 0.0)
		ladder_ok = ladder_ok and common.damage < rare.damage and rare.damage < mythic.damage and common.cooldown > rare.cooldown and rare.cooldown > mythic.cooldown \
			and common.attack_range < rare.attack_range and rare.attack_range < mythic.attack_range and common.ultimate_cooldown > rare.ultimate_cooldown and rare.ultimate_cooldown > mythic.ultimate_cooldown \
			and common.length < rare.length and rare.length < mythic.length
	_ok("for every type Rare beats Common and Mythic beats Rare in damage, speed, range, recharge and size", ladder_ok)


# --------------------------------------------------------------- arming
func _check_arming() -> void:
	print("drops and swaps: arming rolls")
	var arming: Dictionary = _ref["arming"]
	_ok("the element draw order is fire, ice, poison and the weights total 10.1", (arming["element_order"] as Array) == ["fire", "ice", "poison"] and _near(LootDefs.total_drop_weight(), float(arming["total_weight"]), 1e-9))
	var wrong: Array[String] = []
	var armed_count: int = 0
	var types_seen: Dictionary = {}
	var rarities_seen: Dictionary = {}
	for group: String in ["probes", "first_wave"]:
		for entry: Variant in arming[group]:
			var probe: Dictionary = entry as Dictionary
			var got: SwordSpec = LootDefs.armed_from_draws(StringName(probe["kind"]), int(probe["wave"]), int(probe["index"]), float(probe["arm_roll"]), float(probe["drop_draw"]), float(probe["rarity_roll"]), int(probe["element_index"]))
			var expected: Variant = probe["armed"]
			var matches: bool = (got == null) if expected == null else (got != null and _same(got, expected as Array))
			if not matches:
				wrong.append("w%d #%d %s arm %f drop %f rarity %f el %d -> %s vs %s" % [int(probe["wave"]), int(probe["index"]), probe["kind"], float(probe["arm_roll"]), float(probe["drop_draw"]), float(probe["rarity_roll"]), int(probe["element_index"]), "none" if got == null else _spec_array(got), expected])
			if got != null:
				armed_count += 1
				types_seen[got.type_id] = true
				rarities_seen[got.rarity] = true
	_ok("%d scripted wave probes (every kind's chance at, under and over; every weight edge; every element; every wave's rarity thresholds with a brute's bonus; the first wave's guarantees) arm exactly as the prototype's start_wave did (%d wrong: %s)" % [(arming["probes"] as Array).size() + (arming["first_wave"] as Array).size(), wrong.size(), wrong.slice(0, 3)], wrong.is_empty())
	_ok("the probes reach every sword type (%s) and rarity (%s) and arm %d of them" % [types_seen.keys(), rarities_seen.keys(), armed_count], types_seen.size() == 4 and rarities_seen.size() == 3 and armed_count > 100)
	var shape: Dictionary = arming["shape"]
	_ok("the first wave has 8 enemies of which the first two are armed, the first with a Pike (reference shape)", int(shape["first_wave_length"]) == 8 and (shape["first_wave_armed"] as Array) == [true, true, false, false, false, false, false, false] and (shape["first_wave_first"] as Array)[0] == "lance")
	# the roll itself, against the run's own gameplay stream
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 5
	var armed_husks: int = 0
	var armed_brutes: int = 0
	var mythic_brutes: int = 0
	var samples: int = 4000
	for i: int in samples:
		if LootDefs.roll_armed(rng, EnemyDefs.HUSK, 3, 5) != null:
			armed_husks += 1
		var brute: SwordSpec = LootDefs.roll_armed(rng, EnemyDefs.BRUTE, 3, 5)
		if brute != null:
			armed_brutes += 1
			mythic_brutes += 1 if brute.rarity == 2 else 0
	_ok("rolled from the gameplay stream a husk arms about 20 %% of the time (%.3f) and a brute about 75 %% (%.3f)" % [float(armed_husks) / float(samples), float(armed_brutes) / float(samples)],
		_near(float(armed_husks) / float(samples), 0.2, 0.03) and _near(float(armed_brutes) / float(samples), 0.75, 0.03))
	_ok("a wave-3 brute's sword is Mythic about 14 %% of the time (0.08 + 0.15 x 0.5 = 0.135; %.3f)" % [float(mythic_brutes) / float(armed_brutes)], _near(float(mythic_brutes) / float(armed_brutes), 0.135, 0.03))
	var types: Dictionary = {}
	var element_counts: Dictionary = {}
	var drawn: RandomNumberGenerator = RandomNumberGenerator.new()
	drawn.seed = 12
	var armed_total: int = 0
	for i: int in 8000:
		var spec: SwordSpec = LootDefs.roll_armed(drawn, EnemyDefs.BRUTE, 4, 6)
		if spec != null:
			armed_total += 1
			types[spec.type_id] = types.get(spec.type_id, 0) + 1
			element_counts[spec.element] = element_counts.get(spec.element, 0) + 1
	var type_ok: bool = true
	for i: int in LootDefs.DROP_TYPES.size():
		type_ok = type_ok and _near(float(types.get(LootDefs.DROP_TYPES[i], 0)) / float(armed_total), LootDefs.DROP_WEIGHTS[i] / LootDefs.total_drop_weight(), 0.025)
	var element_ok: bool = true
	for element: StringName in SwordDefs.ELEMENT_ORDER:
		element_ok = element_ok and _near(float(element_counts.get(element, 0)) / float(armed_total), 1.0 / 3.0, 0.03)
	_ok("the %d swords rolled for wave-4 brutes follow the drop weights (Fang 30 %%, Warden 30 %%, Pike 25 %%, Colossus 16 %%: %s) and the three elements equally (%s)" % [armed_total, types, element_counts], type_ok and element_ok)
	var first: RandomNumberGenerator = RandomNumberGenerator.new()
	first.seed = 9
	var guaranteed_pike: bool = true
	for i: int in 50:
		var pike: SwordSpec = LootDefs.roll_armed(first, EnemyDefs.HUSK, 1, 0)
		guaranteed_pike = guaranteed_pike and pike != null and pike.type_id == SwordDefs.PIKE
	_ok("the first enemy of the first wave always carries a Pike (50 rolls), the second always some sword", guaranteed_pike and LootDefs.roll_armed(first, EnemyDefs.RUNNER, 1, 1) != null and LootDefs.roll_armed(first, EnemyDefs.RUNNER, 1, 1) != null)
	var draws_a: RandomNumberGenerator = RandomNumberGenerator.new()
	draws_a.seed = 77
	var draws_b: RandomNumberGenerator = RandomNumberGenerator.new()
	draws_b.seed = 77
	LootDefs.roll_armed(draws_a, EnemyDefs.HUSK, 1, 0)
	draws_b.randf()
	draws_b.randi_range(0, 2)
	_ok("a guaranteed first enemy draws no arming roll and no weight draw: only its rarity and element (the generator ends in the same state)", draws_a.state == draws_b.state)
	var draws_c: RandomNumberGenerator = RandomNumberGenerator.new()
	draws_c.seed = 78
	var draws_d: RandomNumberGenerator = RandomNumberGenerator.new()
	draws_d.seed = 78
	var missed: SwordSpec = LootDefs.roll_armed(draws_c, EnemyDefs.HUSK, 4, 3)
	draws_d.randf()
	_ok("an enemy that misses its roll draws nothing more", (missed != null) == (draws_d.state != draws_c.state) or missed == null and draws_c.state == draws_d.state)


func _check_armed_waves() -> void:
	print("drops and swaps: armed waves in a run")
	# A run that does not arm its waves plays exactly as before: the wave start draws nothing from the gameplay stream.
	var plain_scenario: RunScenario = RunScenario.fang_fixture()
	plain_scenario.seed = 31
	var plain: GameRun = GameRun.new(plain_scenario)
	var state_before: int = plain.rng.state
	while plain.director.wave == 0 and plain.tick < 400:
		plain.step()
	_ok("a normal run starts its wave unarmed and without touching the gameplay stream (wave %d, queue %d, %d armed, state kept %s)" % [plain.director.wave, plain.director.queue.size(), plain.director.queue_armed.filter(func(spec: SwordSpec) -> bool: return spec != null).size(), plain.rng.state == state_before],
		plain.director.wave == 1 and plain.director.queue_armed.size() == plain.director.queue.size() and plain.director.queue_armed.all(func(spec: SwordSpec) -> bool: return spec == null) and plain.rng.state == state_before)
	var guaranteed: bool = true
	var detail: String = ""
	for seed_value: int in 12:
		var scenario: RunScenario = RunScenario.fang_fixture()
		scenario.seed = 200 + seed_value
		scenario.arm_waves = true
		var run: GameRun = GameRun.new(scenario)
		while run.director.wave == 0 and run.tick < 400:
			run.step()
		var queue_armed: Array[SwordSpec] = run.director.queue_armed
		var ok: bool = queue_armed.size() == run.director.queue.size() and queue_armed[0] != null and queue_armed[0].type_id == SwordDefs.PIKE and queue_armed[1] != null
		guaranteed = guaranteed and ok
		detail += "%s " % [ok]
	_ok("with arming on, the first wave's first enemy carries a Pike and its second a sword, in each of 12 seeds (%s)" % detail, guaranteed)
	# the sword travels from the queue through the telegraph to the enemy, which has the extra health
	var travel_scenario: RunScenario = RunScenario.fang_fixture()
	travel_scenario.seed = 8
	travel_scenario.arm_waves = true
	travel_scenario.crit_chance = 0.0
	var travel: GameRun = GameRun.new(travel_scenario)
	var queued: Array[SwordSpec] = []
	var marked: int = 0
	var expected_armed: int = 0
	while travel.tick < 1200 and (travel.director.wave == 0 or not travel.director.queue.is_empty() or not travel.director.markers.is_empty()):
		if travel.director.wave >= 1 and queued.is_empty():
			queued = travel.director.queue_armed.duplicate()
			expected_armed = queued.filter(func(spec: SwordSpec) -> bool: return spec != null).size()
		for marker: SpawnMarker in travel.director.markers:
			marked += 1 if marker.armed != null else 0
		travel.step()
	_steps(travel, 90)
	var armed_enemies: Array[EnemyState] = []
	for enemy: EnemyState in travel.enemies:
		if enemy.armed != null:
			armed_enemies.append(enemy)
	var hp_ok: bool = armed_enemies.all(func(enemy: EnemyState) -> bool: return _near(enemy.max_hp, EnemyDefs.of(enemy.kind).hp * LootDefs.ARMED_HP_FACTOR, 1e-6))
	# arming follows the enemy's own kind: a wave of brutes arms about three in four, a wave of husks about one in five
	var armed_by_kind: Dictionary = {}
	for kind: StringName in [EnemyDefs.BRUTE, EnemyDefs.HUSK]:
		var kind_scenario: RunScenario = RunScenario.fang_fixture()
		kind_scenario.seed = 44
		kind_scenario.arm_waves = true
		var many: Array[StringName] = []
		for i: int in 60:
			many.append(kind)
		kind_scenario.wave_kinds = many
		var kind_run: GameRun = GameRun.new(kind_scenario)
		while kind_run.director.wave == 0 and kind_run.tick < 400:
			kind_run.step()
		armed_by_kind[kind] = kind_run.director.queue_armed.filter(func(spec: SwordSpec) -> bool: return spec != null).size()
	_ok("a wave of 60 brutes arms about 45 of them and one of 60 husks about 14 (%s), each by its own kind's chance" % [armed_by_kind], int(armed_by_kind[EnemyDefs.BRUTE]) >= 38 and int(armed_by_kind[EnemyDefs.HUSK]) <= 26 and int(armed_by_kind[EnemyDefs.HUSK]) >= 6)
	_ok("every sword queued for the wave reaches an enemy of its own kind (%d queued armed, %d standing armed or dead, all with 1.35 x health: %s)" % [expected_armed, armed_enemies.size(), hp_ok], expected_armed >= 2 and armed_enemies.size() >= 1 and hp_ok and travel.director.queue.is_empty())


# --------------------------------------------------------------- drops on death
func _check_death_drops() -> void:
	print("drops and swaps: an armed enemy's death")
	var drops: Dictionary = _ref["drops"]
	var wrong: Array[String] = []
	for entry: Variant in drops["kills"]:
		var row: Dictionary = entry as Dictionary
		var run: GameRun = _run_of(_default_specs())
		var spec: SwordSpec = _spec(row["spec"] as Array)
		var enemy: EnemyState = EnemyState.make(StringName(row["kind"]), run.position + Vector2(300.0, 40.0), 1, 0.0, 99, 0.0, 0.0, spec)
		run.enemies.append(enemy)
		run.hit_enemy(enemy, 5000.0, Vector2.RIGHT, 100.0, run.swords[0])
		var after_first: int = run.pickups.size()
		run.hit_enemy(enemy, 5000.0, Vector2.RIGHT, 100.0, run.swords[0])
		var pickup: Dictionary = row["pickup"]
		var ok: bool = after_first == int(row["after_first"]) and run.pickups.size() == int(row["pickups"]) and run.kills == int(row["kills"]) and _near(enemy.max_hp, float(row["maxhp"]), STAT_TOL)
		if ok and not run.pickups.is_empty():
			var lying: PickupState = run.pickups[0]
			ok = _same(lying.spec, [pickup["kind"], pickup["rarity"], pickup["element"]]) and lying.position.distance_to(enemy.position) < 0.001 and _near(lying.position.x, float(pickup["x"]), POSITION_TOL) and _near(lying.position.y, float(pickup["y"]), POSITION_TOL) and _near(lying.life, float(pickup["life"]), 1e-9) \
				and lying.spec == spec and run.cue_count(SimCue.Kind.SWORD_DROPPED) == 1
		if not ok:
			wrong.append("%s %s" % [row["kind"], row["spec"]])
	_ok("each of 4 enemy kinds x 4 swords drops exactly its sword (type, element, rarity) once, where it died, with 45 s to live, however many blows land (%d wrong: %s)" % [wrong.size(), wrong], wrong.is_empty() and (drops["kills"] as Array).size() == 16)
	var unarmed: GameRun = _run_of(_default_specs())
	var plain: EnemyState = EnemyState.make(EnemyDefs.BRUTE, unarmed.position + Vector2(300.0, 0.0), 1, 0.0, 98)
	unarmed.enemies.append(plain)
	unarmed.hit_enemy(plain, 5000.0, Vector2.RIGHT, 100.0, unarmed.swords[0])
	_ok("an unarmed enemy drops nothing (reference: %d pickups, %d kill)" % [int((drops["unarmed"] as Dictionary)["pickups"]), int((drops["unarmed"] as Dictionary)["kills"])], unarmed.pickups.size() == int((drops["unarmed"] as Dictionary)["pickups"]) and unarmed.kills == int((drops["unarmed"] as Dictionary)["kills"]) and unarmed.cue_count(SimCue.Kind.SWORD_DROPPED) == 0)
	var both: GameRun = _run_of(_default_specs())
	var first: EnemyState = EnemyState.make(EnemyDefs.HUSK, both.position + Vector2(300.0, 0.0), 1, 0.0, 1, 0.0, 0.0, SwordSpec.make(&"fang", 0, &"fire"))
	var second: EnemyState = EnemyState.make(EnemyDefs.HUSK, both.position + Vector2(-300.0, 0.0), 1, 0.0, 2, 0.0, 0.0, SwordSpec.make(&"lance", 2, &"poison"))
	both.enemies.append_array([first, second])
	both.hit_enemy(second, 5000.0, Vector2.RIGHT, 100.0, both.swords[0])
	both.hit_enemy(first, 5000.0, Vector2.RIGHT, 100.0, both.swords[0])
	var same_tick: Array = drops["same_tick"]
	var order_ok: bool = both.pickups.size() == 2
	for i: int in mini(2, both.pickups.size()):
		var entry: Dictionary = same_tick[i]
		order_ok = order_ok and _same(both.pickups[i].spec, [entry["kind"], entry["rarity"], entry["element"]]) and _near(both.pickups[i].position.x, float(entry["x"]), POSITION_TOL)
	_ok("two armed enemies that die together leave two drops, in the order they died", order_ok)
	# every cause of death drops through the one `kill`
	var causes: Dictionary = {}
	for cause: String in ["kill_twice", "condition", "wall_slam", "bowling"]:
		var run: GameRun = _run_of(_default_specs())
		var spec: SwordSpec = SwordSpec.make(&"lance", 1, &"ice")
		var victim: EnemyState = EnemyState.make(EnemyDefs.HUSK, run.position + Vector2(400.0, 0.0), 1, 0.0, 5, 0.0, 0.0, spec)
		run.enemies.append(victim)
		match cause:
			"kill_twice":
				run.kill(victim, Vector2.RIGHT)
				run.kill(victim, Vector2.RIGHT)
			"condition":
				victim.hp = 1.0
				victim.conditions.apply(ConditionDefs.POISON, 50.0, 6)
				_steps(run, 90)
			"wall_slam":
				victim.hp = 1.0
				run.wall_slam(victim, 600.0)
				run.wall_slam(victim, 600.0)
			"bowling":
				victim.hp = 1.0
				var launcher: EnemyState = EnemyState.make(EnemyDefs.HUSK, victim.position + Vector2(-20.0, 0.0), 1, 0.0, 6)
				launcher.velocity = Vector2(900.0, 0.0)
				launcher.stun = 1.0
				run.enemies.append(launcher)
				run._separate()
		causes[cause] = run.pickups.size() == 1 and run.pickups[0].spec == spec and run.cue_count(SimCue.Kind.SWORD_DROPPED) == 1 and run.kills >= 1
	_ok("a kill, a damage-over-time death, a wall slam and a bowling hit each leave exactly one drop (%s)" % [causes], causes.values().all(func(ok: bool) -> bool: return ok))
	# a real fight: a Fang kills an armed husk standing in reach, and the drop appears at its feet
	var scenario: RunScenario = RunScenario.fang_fixture()
	scenario.seed = 61
	scenario.waves_enabled = false
	scenario.crit_chance = 0.0
	scenario.sword_start_cooldowns = [0.1, PARKED, PARKED]
	var armed_spec: SwordSpec = SwordSpec.make(&"blade", 2, &"ice")
	scenario.initial_enemies = [EnemyPlacement.make(EnemyDefs.HUSK, CENTER + Vector2(120.0, 0.0)).armed_with(armed_spec)]
	scenario.initial_enemies[0].speed_scale = 0.0
	var fight: GameRun = GameRun.new(scenario)
	var died_at: Vector2 = Vector2.ZERO
	var killed: bool = false
	for tick_index: int in 400:
		var standing: EnemyState = fight.enemies[0] if not fight.enemies.is_empty() else null
		if standing != null:
			died_at = standing.position
		fight.step()
		if fight.kills == 1:
			killed = true
			break
	_ok("a Fang's blows kill an armed husk and its Mythic Frost Warden lies where it fell (killed %s, drops %d at %s, died near %s)" % [killed, fight.pickups.size(), fight.pickups[0].position if not fight.pickups.is_empty() else Vector2.ZERO, died_at],
		killed and fight.pickups.size() == 1 and fight.pickups[0].spec == armed_spec and fight.pickups[0].position.distance_to(died_at) < 80.0 and fight.cue_count(SimCue.Kind.SWORD_DROPPED) == 1)


# --------------------------------------------------------------- pickup life
func _check_life() -> void:
	print("drops and swaps: a pickup's life")
	var life: Dictionary = _ref["life"]
	for name: String in life:
		var row: Dictionary = life[name]
		var run: GameRun = _run_of(_default_specs())
		var pickup: PickupState = _put(run, ["lance", 2, "ice"], 400.0, 0.0)
		if name == "short":
			pickup.life = 1.0
		if name == "nearly_gone":
			pickup.life = 1.0 / 60.0
		var trace: Array = row["trace"]
		var gone_at: int = -1
		var worst: float = 0.0
		for tick_index: int in 3200:
			match [name, tick_index]:
				["hitstop", 100]:
					run.hitstop = 0.5
				["slowmo", 200]:
					run.slowmo = 1.4
					run.slowmo_scale = 0.25
				["paused", 50]:
					run.apply(GameCommand.pause())
				["paused", 110]:
					run.apply(GameCommand.resume())
				["dead_player", 30]:
					run.hurt_player(1000, run.position + Vector2(50.0, 0.0))
			run.step()
			if tick_index < trace.size():
				worst = maxf(worst, absf(pickup.life - float(trace[tick_index])))
			if not run.pickups.has(pickup):
				gone_at = tick_index + 1
				break
		_ok("pickup life, '%s': it follows the prototype's per-tick countdown (worst %.5f over %d ticks) and is removed on tick %d (reference %d)" % [name, worst, mini(trace.size(), 3200), gone_at, int(row["gone_at"])], worst <= SCALAR_TOL and gone_at == int(row["gone_at"]))
	# a pickup that has not yet lived out its time is never removed early
	var early: GameRun = _run_of(_default_specs())
	var young: PickupState = _put(early, ["fang", 0, "fire"], 400.0, 0.0)
	_steps(early, 2699)
	_ok("after 2699 ticks (44.98 s) the drop still lies (life %.4f)" % young.life, early.pickups.has(young) and young.life > 0.0 and young.life < 0.05)
	_steps(early, 2)
	_ok("and is gone by tick 2701", not early.pickups.has(young))


func _check_blink() -> void:
	print("drops and swaps: a drop blinks before it goes")
	var wrong: Array[String] = []
	var hidden: int = 0
	for entry: Variant in _ref["blink"]:
		var row: Dictionary = entry as Dictionary
		var pickup: PickupState = PickupState.make(SwordSpec.make(&"lance", 2, &"ice"), Vector2.ZERO, 1)
		pickup.life = float(row["life"])
		hidden += 1 if pickup.blink_hidden() else 0
		if pickup.blink_hidden() == bool(row["drawn"]):
			wrong.append(str(row["life"]))
	_ok("in its last six seconds a drop is hidden on every other eighth of a second, exactly when the prototype draws nothing (%d lives, %d hidden, wrong at %s)" % [(_ref["blink"] as Array).size(), hidden, wrong], wrong.is_empty() and hidden >= 8 and hidden < (_ref["blink"] as Array).size() - 8)


# --------------------------------------------------------------- reach
func _check_reach() -> void:
	print("drops and swaps: which pickup a swap claims")
	var reach: Dictionary = _ref["reach"]
	var wrong: Array[String] = []
	for entry: Variant in reach["single"]:
		var row: Dictionary = entry as Dictionary
		var run: GameRun = _run_of(_default_specs())
		var direction: Array = row["direction"]
		_put(run, ["blade", 1, "fire"], float(row["dist"]) * float(direction[0]), float(row["dist"]) * float(direction[1]))
		var result: GameRun.SwapResult = run.try_swap(1)
		var swapped: bool = result == GameRun.SwapResult.SWAPPED
		if swapped != bool(row["swapped"]) or (run.pickups.size() != int(row["pickups_after"])):
			wrong.append("%s px %s" % [row["dist"], direction])
	_ok("a pickup is claimed from 0 to 79.95 px away, in three directions, and never from exactly 80 px or beyond (%d wrong: %s)" % [wrong.size(), wrong], wrong.is_empty() and (reach["single"] as Array).size() == 21)
	var multi_wrong: Array[String] = []
	for entry: Variant in reach["multi"]:
		var row: Dictionary = entry as Dictionary
		var run: GameRun = _run_of(_default_specs())
		for placement: Variant in row["placements"]:
			var at: Dictionary = placement as Dictionary
			_put(run, at["spec"] as Array, float(at["dx"]), float(at["dy"]))
		var result: GameRun.SwapResult = run.try_swap(0)
		var claimed: Variant = row["claimed"]
		var ok: bool = (result == GameRun.SwapResult.SWAPPED) == bool(row["swapped"])
		if ok and claimed != null:
			ok = _same(run.swords[0].spec, claimed as Array)
		if ok:
			ok = run.pickups.size() == (row["pickups_after"] as Array).size()
		if not ok:
			multi_wrong.append(String(row["name"]))
	_ok("the nearest of several is claimed, the first of equals wins (listed first / reversed / a three-way tie), far ones are ignored, none in reach claims nothing (%d of %d wrong: %s)" % [multi_wrong.size(), (reach["multi"] as Array).size(), multi_wrong], multi_wrong.is_empty())
	var no_slot: GameRun = _run_of(_default_specs())
	_put(no_slot, ["fang", 0, "fire"], 10.0, 0.0)
	var before: Array = _specs_of(no_slot)
	var result_no_slot: GameRun.SwapResult = no_slot.try_swap(5)
	_ok("a slot that holds no sword refuses and changes nothing (the pickup stays)", result_no_slot == GameRun.SwapResult.NO_SWORD and _specs_of(no_slot) == before and no_slot.pickups.size() == 1 and not bool((reach["no_such_slot"] as Dictionary)["swapped"]))
	var negative: GameRun = _run_of(_default_specs())
	_put(negative, ["fang", 0, "fire"], 10.0, 0.0)
	_ok("so does a negative slot", negative.try_swap(-1) == GameRun.SwapResult.NO_SWORD and negative.pickups.size() == 1)
	var nothing: GameRun = _run_of(_default_specs())
	var empty_before: Array = _specs_of(nothing)
	var nothing_result: GameRun.SwapResult = nothing.try_swap(0)
	_ok("with nothing lying about a swap is refused, visibly (a refusal cue) and changes nothing", nothing_result == GameRun.SwapResult.NO_PICKUP and _specs_of(nothing) == empty_before and nothing.cue_count(SimCue.Kind.SWAP_REFUSED) == 1 and nothing.cue_count(SimCue.Kind.SWORD_SWAPPED) == 0 and not bool((reach["no_pickups"] as Dictionary)["swapped"]))
	var far: GameRun = _run_of(_default_specs())
	_put(far, ["fang", 0, "fire"], 300.0, 0.0)
	far.try_swap(2)
	_ok("a pickup out of reach refuses too, and stays", far.pickups.size() == 1 and _specs_of(far) == empty_before and far.cue_count(SimCue.Kind.SWAP_REFUSED) == 1)
	var moved: GameRun = _run_of(_default_specs())
	_put(moved, ["fang", 0, "fire"], 300.0, 0.0)
	moved.position = moved.position + Vector2(260.0, 0.0)
	_ok("reach follows the player: walk to within 80 px and the same drop can be claimed", moved.try_swap(0) == GameRun.SwapResult.SWAPPED and moved.swords[0].spec.type_id == SwordDefs.FANG)


# --------------------------------------------------------------- swaps
func _check_swaps() -> void:
	print("drops and swaps: the swap of every type, rarity and element")
	var wrong: Array[String] = []
	var cases: Array = _ref["swaps"]
	var slots_seen: Dictionary = {}
	var fractions_seen: Dictionary = {}
	for entry: Variant in cases:
		var row: Dictionary = entry as Dictionary
		var setup: Dictionary = row["setup"]
		var slot: int = int(setup["slot"])
		var specs: Array = _default_specs()
		specs[slot] = setup["old"]
		var run: GameRun = _run_of(specs, 100)
		var old_sword: SwordState = run.swords[slot]
		old_sword.ultimate_cooldown_left = old_sword.ultimate_cooldown * float(setup["fraction"])
		var others: Dictionary = {}
		for i: int in 3:
			if i != slot:
				others[i] = run.swords[i]
		var claimed: PickupState = _put(run, setup["pickup"] as Array, 20.0, -30.0)
		var claimed_spec: SwordSpec = claimed.spec
		var spec_before: Array = _spec_array(claimed_spec)
		_swap_key(run, slot)
		var label: String = "%s into %d (%s)" % [SwordDefs.full_name(claimed_spec), slot + 1, setup["old"]]
		slots_seen[slot] = true
		fractions_seen[float(setup["fraction"])] = true
		var problems: String = _matches_new(run.swords[slot], row["new"] as Dictionary)
		var returned: Dictionary = row["returned"]
		var back: PickupState = run.pickups[run.pickups.size() - 1] if not run.pickups.is_empty() else null
		if not problems.is_empty():
			wrong.append("%s: %s" % [label, problems])
		elif run.pickups.size() != 1 or back == null or not _same(back.spec, [returned["kind"], returned["rarity"], returned["element"]]) or back.spec != old_sword.spec or not _near(back.life, float(returned["life"]), 1e-9) or not _near(back.position.y - claimed.position.y, LootDefs.RETURN_DROP, 0.001) or absf(back.position.x - claimed.position.x) > LootDefs.RETURN_SPREAD + 0.001:
			wrong.append("%s: the replaced sword's drop is wrong" % label)
		elif run.pickups.has(claimed) or run.swords.has(old_sword) or not others.keys().all(func(index: int) -> bool: return run.swords[index] == others[index]):
			wrong.append("%s: the claimed pickup, the old sword or another slot is wrong" % label)
		elif _spec_array(claimed_spec) != spec_before or claimed_spec != run.swords[slot].spec:
			wrong.append("%s: the claimed spec changed" % label)
	_ok("all 36 swaps (every type, rarity and element, into every slot, with a ready, a part-spent and a full recharge) give the slot exactly the prototype's sword: stats, recharge, cooldown, height, velocity, flash, position; the pickup is gone, the old sword lies as a drop, the other slots are untouched (%d wrong: %s)" % [wrong.size(), wrong.slice(0, 3)], wrong.is_empty() and cases.size() == 36)
	_ok("the cases cover all three slots and the recharge fractions 0, 0.37 and 1 (%s / %s)" % [slots_seen.keys(), fractions_seen.keys()], slots_seen.size() == 3 and fractions_seen.size() == 3)


func _check_returned_drops() -> void:
	print("drops and swaps: the sword a swap puts back")
	var dxs: Array[float] = []
	var all_ok: bool = true
	for i: int in 400:
		var run: GameRun = _run_of(_default_specs(), 1000 + i)
		var claimed: PickupState = _put(run, ["lance", 1, "ice"], 10.0, 10.0)
		var old_spec: SwordSpec = run.swords[0].spec
		run.try_swap(0)
		var back: PickupState = run.pickups[0]
		dxs.append(back.position.x - claimed.position.x)
		all_ok = all_ok and back.spec == old_spec and _near(back.position.y - claimed.position.y, 24.0, 0.001) and _near(back.life, 45.0, 1e-9) and run.pickups.size() == 1
	var least: float = dxs.min()
	var most: float = dxs.max()
	_ok("over 400 swaps the old sword lands exactly 24 px below the claimed one and %.1f to %.1f px aside (never beyond 20), at full life, as the same sword" % [least, most], all_ok and least >= -20.001 and most <= 20.001 and least < -17.0 and most > 17.0)
	var spread: Dictionary = {}
	for value: float in dxs:
		spread[snappedf(value, 5.0)] = true
	_ok("and the sideways offsets are spread across the range (%d distinct 5 px bins), not a constant" % spread.size(), spread.size() >= 6)
	# the returned sword can be claimed straight back: no hidden cooldown or ownership
	var again: GameRun = _run_of(_default_specs())
	var original: SwordSpec = again.swords[1].spec
	_put(again, ["lance", 2, "fire"], 5.0, 0.0)
	again.try_swap(1)
	var back_again: GameRun.SwapResult = again.try_swap(1)
	_ok("standing where it fell, the player can swap the old sword straight back (the Pike returns, the original is a drop again)", back_again == GameRun.SwapResult.SWAPPED and again.swords[1].spec == original and again.pickups.size() == 1 and again.pickups[0].spec.type_id == SwordDefs.PIKE)


func _check_repeated() -> void:
	print("drops and swaps: repeated swaps keep the recharge fraction")
	var chain: Array = _ref["repeated"]
	var run: GameRun = _run_of(_default_specs(), 7)
	var sword: SwordState = run.swords[1]
	sword.ultimate_cooldown_left = sword.ultimate_cooldown * 0.6
	var wrong: Array[String] = []
	for index: int in chain.size():
		var row: Dictionary = chain[index]
		_put(run, row["spec"] as Array, 15.0, 0.0)
		var pickups_before: int = run.pickups.size()
		var result: GameRun.SwapResult = run.try_swap(1)
		var now: SwordState = run.swords[1]
		var fraction: float = now.ultimate_cooldown_left / now.ultimate_cooldown
		var problems: String = _matches_new(now, row["new"] as Dictionary)
		var others_ok: bool = _same(run.swords[0].spec, (row["others"] as Array)[0] as Array) and _same(run.swords[2].spec, (row["others"] as Array)[1] as Array)
		if result != GameRun.SwapResult.SWAPPED or not problems.is_empty() or not _near(fraction, float(row["slot_fraction"]), 0.001) or run.pickups.size() != int(row["pickups"]) or pickups_before != int(row["pickups_before"]) or not others_ok:
			wrong.append("#%d %s: %s fraction %.4f vs %.4f" % [index, row["spec"], problems, fraction, float(row["slot_fraction"])])
		_steps(run, 30)
	_ok("ten swaps in a row into one slot (every rarity and type, a recharge running between them) match the prototype step for step: recharge fraction, stats, the drops left lying and the other slots (%d wrong: %s)" % [wrong.size(), wrong.slice(0, 3)], wrong.is_empty() and chain.size() == 10)
	# a recharge that is exactly ready stays ready; a full one stays full, whatever the rarity
	var ready_run: GameRun = _run_of([["fang", 2, "fire"], ["blade", 0, "ice"], ["colossus", 0, "fire"]])
	_put(ready_run, ["colossus", 0, "poison"], 10.0, 0.0)
	ready_run.try_swap(0)
	_ok("a ready ultimate stays ready after the swap (Mythic Fang -> Common Colossus)", ready_run.swords[0].ultimate_cooldown_left == 0.0 and ready_run.swords[0].ultimate_ready())
	var full_run: GameRun = _run_of([["colossus", 0, "fire"], ["blade", 0, "ice"], ["colossus", 0, "fire"]])
	full_run.swords[0].ultimate_cooldown_left = full_run.swords[0].ultimate_cooldown
	_put(full_run, ["fang", 2, "poison"], 10.0, 0.0)
	full_run.try_swap(0)
	_ok("a just-used ultimate is still just used: the Mythic Fang's recharge is full (%.3f of %.3f), so the swap cannot reset it" % [full_run.swords[0].ultimate_cooldown_left, full_run.swords[0].ultimate_cooldown], _near(full_run.swords[0].ultimate_cooldown_left, full_run.swords[0].ultimate_cooldown, 1e-9) and not full_run.swords[0].ultimate_ready())
	# swapping a sword whose ultimate is running does not reset its recharge either (the running one is refused afterwards)
	var running: GameRun = _run_of(_default_specs())
	running.try_ultimate(0, running.position + Vector2(200.0, 0.0))
	_steps(running, 10)
	var left: float = running.swords[0].ultimate_cooldown_left
	var fraction_left: float = left / running.swords[0].ultimate_cooldown
	_put(running, ["lance", 1, "ice"], 10.0, 0.0)
	running.try_swap(0)
	_ok("swapping a sword mid-ultimate hands its recharge fraction on (%.3f) and ends that ultimate (the new sword is idle)" % fraction_left, _near(running.swords[0].ultimate_cooldown_left / running.swords[0].ultimate_cooldown, fraction_left, 1e-6) and running.swords[0].phase == SwordState.Phase.IDLE and running.swords[0].spec.type_id == SwordDefs.PIKE)
	var refused: GameRun.UltimateResult = running.try_ultimate(0, running.position + Vector2(200.0, 0.0))
	_ok("and its recharge still refuses the next ultimate", refused == GameRun.UltimateResult.RECHARGING)


## A run with the default loadout (Fang, Warden, Colossus; all attacks parked), no waves, and one husk of 5000 health that
## stands still `dx` px east of the player (so nothing it does and nothing it takes ends the run).
func _converge_run(dx: float = 200.0) -> GameRun:
	var scenario: RunScenario = RunScenario.new()
	scenario.seed = 17
	scenario.waves_enabled = false
	scenario.crit_chance = 0.0
	scenario.sword_start_cooldowns = [PARKED, PARKED, PARKED]
	var husk: EnemyPlacement = EnemyPlacement.make(EnemyDefs.HUSK, CENTER + Vector2(dx, 0.0))
	husk.speed_scale = 0.0
	husk.hp = 5000.0
	scenario.initial_enemies = [husk]
	return GameRun.new(scenario)


## Stands every sword but one down again after a Converge took them all (idle, no target, no boost), so that what the one
## sword does to the husk is the whole story.
func _stand_down_but(run: GameRun, slot: int) -> void:
	for other: int in run.swords.size():
		if other != slot:
			run.swords[other].phase = SwordState.Phase.IDLE
			run.swords[other].target = null
			run.swords[other].boost = 1.0


## The health the husk loses to the first blow of the one commanded sword in `slot` of `run`.
func _commanded_damage(run: GameRun, slot: int, point: Vector2) -> float:
	var enemy: EnemyState = run.enemies[0]
	run.apply(GameCommand.converge(point))
	_stand_down_but(run, slot)
	var hp_before: float = enemy.hp
	for i: int in 240:
		run.step()
		if enemy.hp < hp_before:
			break
	return hp_before - enemy.hp


## Swapping and Converge together (issues #16 and #17): the cooldown is the run's and a swap neither resets nor skips it, Converge
## commands the swapped-in sword by its own type, and a swap in the middle of a commanded strike drops that strike
## (the prototype's `Game.swap` makes a brand-new idle `Sword`; `Game.converge` is untouched).
func _check_swap_and_converge() -> void:
	print("drops and swaps: swaps and Converge")
	var run: GameRun = _converge_run()
	var point: Vector2 = CENTER + Vector2(200.0, 0.0)
	run.apply(GameCommand.converge(point))
	_steps(run, 30)
	var cooling: float = run.converge_cooldown_left
	_ok("a Converge starts the shared cooldown (%.3f s of %.1f left half a second later)" % [cooling, SwordDefs.CONVERGE_COOLDOWN], cooling > 1.5 and cooling < SwordDefs.CONVERGE_COOLDOWN)
	_ok("a swap with nothing in reach is refused and leaves the Converge cooldown alone", run.try_swap(1) == GameRun.SwapResult.NO_PICKUP and run.converge_cooldown_left == cooling)
	_put(run, ["lance", 1, "fire"], 30.0, 0.0)
	var result: GameRun.SwapResult = run.try_swap(0)
	_ok("a swap during the Converge cooldown goes through and leaves the cooldown exactly where it was", result == GameRun.SwapResult.SWAPPED and run.converge_cooldown_left == cooling and run.swords[0].spec.type_id == SwordDefs.PIKE)
	_ok("and a Converge pressed now is still refused, the swapped-in Pike untouched (idle, %.2f s of its start cooldown)" % run.swords[0].cooldown_left, run.try_converge(point) == GameRun.ConvergeResult.COOLING_DOWN and run.swords[0].phase == SwordState.Phase.IDLE)
	var refused_while_cooling: bool = true
	var ticks_cooling: int = 0
	var time_at_swap: float = run.gameplay_time
	while run.converge_cooldown_left > 0.0 and ticks_cooling < 600:
		refused_while_cooling = refused_while_cooling and run.try_converge(point) == GameRun.ConvergeResult.COOLING_DOWN
		run.step()
		ticks_cooling += 1
	var elapsed: float = run.gameplay_time - time_at_swap
	_ok("every press is refused until the cooldown has run out (%.3f s of play for the %.3f s left at the swap: the swap neither reset nor skipped it)" % [elapsed, cooling], refused_while_cooling and absf(elapsed - cooling) <= 1.5 / 60.0)
	_ok("and then a Converge works, the swapped-in Pike taking it", run.try_converge(point) == GameRun.ConvergeResult.COMMANDED and run.swords[0].phase == SwordState.Phase.WINDUP)
	# the swapped-in sword obeys Converge by its own semantics: an attack cooldown does not matter, the command's boost and shortened windup apply
	for entry: Array in [[0, ["lance", 1, "fire"]], [0, ["colossus", 2, "ice"]], [1, ["blade", 0, "poison"]], [2, ["fang", 2, "fire"]]]:
		var swapped: GameRun = _converge_run()
		var slot: int = int(entry[0])
		var values: Array = entry[1]
		_put(swapped, values, 25.0, 0.0)
		var enemy: EnemyState = swapped.enemies[0]
		_ok("%s swapped into slot %d starts waiting out its %.1f s start cooldown, idle" % [values[0], slot + 1, LootDefs.SWAP_START_COOLDOWN], swapped.try_swap(slot) == GameRun.SwapResult.SWAPPED and swapped.swords[slot].phase == SwordState.Phase.IDLE and _near(swapped.swords[slot].cooldown_left, LootDefs.SWAP_START_COOLDOWN, 1e-9))
		swapped.apply(GameCommand.converge(point))
		var sword: SwordState = swapped.swords[slot]
		_ok("a Converge at once commands the swapped-in %s, though its start cooldown still runs: windup, boost %.1f, shortened windup (%.3f s), aimed at the husk it stands on" % [values[0], SwordDefs.CONVERGE_BOOST, sword.timer],
			sword.phase == SwordState.Phase.WINDUP and sword.boost == SwordDefs.CONVERGE_BOOST and _near(sword.timer, sword.windup * SwordDefs.CONVERGE_WINDUP_FACTOR, 1e-9) and sword.target == enemy and swapped.cue_count(SimCue.Kind.CONVERGE) == 1)
		_stand_down_but(swapped, slot)
		var hp_before: float = enemy.hp
		for i: int in 240:
			swapped.step()
			if enemy.hp < hp_before:
				break
		var dealt: float = hp_before - enemy.hp
		var native_specs: Array = [["fang", 0, "poison"], ["fang", 0, "poison"], ["fang", 0, "poison"]]
		native_specs[slot] = values
		var native: GameRun = _converge_run()
		native.swords.clear()
		for native_values: Array in native_specs:
			native.swords.append(SwordState.equip(_spec(native_values), native.position, PARKED))
		var native_dealt: float = _commanded_damage(native, slot, point)
		_ok("the commanded %s then strikes the husk for %.1f, exactly what the same sword does from its own slot at the start (%.1f)" % [values[0], dealt, native_dealt], dealt > 0.0 and _near(dealt, native_dealt, 1e-6))
	# swapping while the sword is mid-strike: the strike is gone with the old sword
	var strike_run: GameRun = _converge_run(100.0)
	strike_run.apply(GameCommand.converge(CENTER + Vector2(100.0, 0.0)))
	_stand_down_but(strike_run, 0)  # only the Fang's strike is the subject
	var guard: int = 0
	while strike_run.swords[0].phase != SwordState.Phase.STRIKE and guard < 240:
		strike_run.step()
		guard += 1
	var striking: SwordState = strike_run.swords[0]
	var husk_hp: float = strike_run.enemies[0].hp
	var cooldown_then: float = strike_run.converge_cooldown_left
	_ok("the commanded Fang is mid-strike (phase %d after %d ticks) when the swap comes" % [striking.phase, guard], striking.phase == SwordState.Phase.STRIKE)
	_put(strike_run, ["lance", 0, "ice"], 20.0, 0.0)
	var struck_spec: SwordSpec = striking.spec
	_ok("the swap goes through mid-strike", strike_run.try_swap(0) == GameRun.SwapResult.SWAPPED)
	var fresh: SwordState = strike_run.swords[0]
	_ok("the new sword is a fresh idle one, no target, no boost, no strike, waiting out its start cooldown", fresh != striking and fresh.phase == SwordState.Phase.IDLE and fresh.target == null and fresh.boost == 1.0 and _near(fresh.cooldown_left, LootDefs.SWAP_START_COOLDOWN, 1e-9))
	_ok("the Converge cooldown is not touched and the struck Fang lies down as a drop", strike_run.converge_cooldown_left == cooldown_then and strike_run.pickups.any(func(pickup: PickupState) -> bool: return pickup.spec == struck_spec))
	_steps(strike_run, 20)
	_ok("the cancelled strike never lands (husk health %.1f -> %.1f) while the new Pike waits out its cooldown" % [husk_hp, strike_run.enemies[0].hp], strike_run.enemies[0].hp == husk_hp and strike_run.swords[0] == fresh)



func _check_trace() -> void:
	print("drops and swaps: the swapped-in sword's flight")
	for kind: String in ["fang", "blade", "lance", "colossus"]:
		var row: Dictionary = (_ref["trace"] as Dictionary)[kind]
		var trace: Dictionary = row["trace"]
		var run: GameRun = _run_of(_default_specs(), 3)
		run.swords[0].ultimate_cooldown_left = run.swords[0].ultimate_cooldown * 0.5
		_steps(run, int(row["ticks_before_swap"]))
		var at: Array = row["pickup"]
		_put(run, [kind, 1, "ice"], float(at[0]), float(at[1]))
		run.try_swap(0)
		var sword: SwordState = run.swords[0]
		var worst: Dictionary = {"position": 0.0, "velocity": 0.0, "angle": 0.0, "scalar": 0.0, "altitude": 0.0}
		var phases_ok: bool = true
		for i: int in (trace["x"] as Array).size():
			run.step()
			worst["position"] = maxf(float(worst["position"]), maxf(absf(sword.position.x - float((trace["x"] as Array)[i])), absf(sword.position.y - float((trace["y"] as Array)[i]))))
			worst["velocity"] = maxf(float(worst["velocity"]), maxf(absf(sword.velocity.x - float((trace["vx"] as Array)[i])), absf(sword.velocity.y - float((trace["vy"] as Array)[i]))))
			worst["angle"] = maxf(float(worst["angle"]), absf(angle_difference(sword.angle, float((trace["ang"] as Array)[i]))))
			worst["scalar"] = maxf(float(worst["scalar"]), maxf(absf(sword.cooldown_left - float((trace["cd"] as Array)[i])), maxf(absf(sword.ultimate_cooldown_left - float((trace["ult_cd"] as Array)[i])), absf(sword.flash - float((trace["flash"] as Array)[i])))))
			if kind == "colossus":
				worst["altitude"] = maxf(float(worst["altitude"]), absf(sword.altitude - float((trace["z"] as Array)[i])))
			phases_ok = phases_ok and _phase_name(sword) == String((trace["state"] as Array)[i])
		_ok("a swapped-in %s flies as the prototype's did for %d ticks: position within %.4f px, velocity %.4f px/s, heading %.5f, cooldown/recharge/flash %.5f%s" % [kind, (trace["x"] as Array).size(), float(worst["position"]), float(worst["velocity"]), float(worst["angle"]), float(worst["scalar"]), ", altitude %.4f" % float(worst["altitude"]) if kind == "colossus" else ""],
			float(worst["position"]) <= POSITION_TOL and float(worst["velocity"]) <= VELOCITY_TOL and float(worst["angle"]) <= ANGLE_TOL and float(worst["scalar"]) <= SCALAR_TOL and float(worst["altitude"]) <= 0.01 and phases_ok)


# --------------------------------------------------------------- rules
func _check_rules() -> void:
	print("drops and swaps: keys, pause, death and restart")
	var rules: Dictionary = _ref["rules"]
	for slot: int in 3:
		var row: Dictionary = rules["key_%d" % (slot + 1)]
		var run: GameRun = _run_of(_default_specs())
		_put(run, ["lance", 1, "fire"], 10.0, 0.0)
		_swap_key(run, slot)
		_ok("key %d swaps the pickup into slot %d only (%s)" % [slot + 1, slot + 1, _specs_of(run)], _specs_match(run, row["swords_after"] as Array) and bool(row["swapped"]))
	var keys: InputTranslator = InputTranslator.new()
	var kinds: Array[GameCommand.Kind] = []
	var slots: Array[int] = []
	for code: Key in SWAP_KEY_CODES:
		for command: GameCommand in keys.handle_event(_key(code)):
			kinds.append(command.kind)
			slots.append(command.slot)
	_ok("the translator turns the 1, 2 and 3 keys into swap commands for slots 0, 1 and 2", kinds == [GameCommand.Kind.SWAP, GameCommand.Kind.SWAP, GameCommand.Kind.SWAP] and slots == [0, 1, 2])
	var held: InputTranslator = InputTranslator.new()
	held.handle_event(_key(KEY_1))
	var echo: InputEventKey = _key(KEY_1)
	echo.echo = true
	_ok("a held key does not repeat the swap", held.handle_event(echo).is_empty())
	var paused: GameRun = _run_of(_default_specs())
	_put(paused, ["lance", 1, "fire"], 10.0, 0.0)
	paused.apply(GameCommand.pause())
	_swap_key(paused, 0)
	_ok("a paused run refuses the swap silently and changes nothing", _specs_match(paused, (rules["paused"] as Dictionary)["swords_after"] as Array) and paused.pickups.size() == 1 and paused.cue_count(SimCue.Kind.SWAP_REFUSED) == 0 and not bool((rules["paused"] as Dictionary)["swapped"]))
	paused.apply(GameCommand.resume())
	_swap_key(paused, 0)
	_ok("and swaps as soon as it resumes", paused.swords[0].spec.type_id == SwordDefs.PIKE)
	var dead: GameRun = _run_of(_default_specs())
	_put(dead, ["lance", 1, "fire"], 10.0, 0.0)
	dead.hurt_player(1000, dead.position + Vector2(50.0, 0.0))
	_swap_key(dead, 0)
	_ok("a dead player cannot swap (silently)", dead.dead and _specs_match(dead, (rules["dead"] as Dictionary)["swords_after"] as Array) and dead.pickups.size() == 1 and dead.cue_count(SimCue.Kind.SWAP_REFUSED) == 0 and not bool((rules["dead"] as Dictionary)["swapped"]))
	for restart_kind: String in ["button", "key", "scenario"]:
		var run: GameRun = _run_of(_default_specs())
		_put(run, ["lance", 1, "fire"], 10.0, 0.0)
		_put(run, ["fang", 2, "ice"], 500.0, 0.0)
		_swap_key(run, 0)
		var lying: int = run.pickups.size()
		var swapped_cues: int = run.cue_count(SimCue.Kind.SWORD_SWAPPED)
		match restart_kind:
			"button":
				run.apply(GameCommand.restart())
			"key":
				run.hurt_player(1000, run.position + Vector2(50.0, 0.0))
				_steps(run, 400)
				run.apply(GameCommand.restart_from_key())
			_:
				run.restart_with(run.scenario)
		var reset: Dictionary = rules["reset"]
		_ok("restart (%s) clears every drop (%d lying before, %d after, reference %d -> %d), the swapped swords and the counters (swapped cues %d -> %d)" % [restart_kind, lying, run.pickups.size(), int(reset["pickups_before"]), int(reset["pickups_after"]), swapped_cues, run.cue_count(SimCue.Kind.SWORD_SWAPPED)],
			lying == 2 and run.pickups.is_empty() and int(reset["pickups_after"]) == 0 and _specs_of(run) == _default_specs() and run.cue_count(SimCue.Kind.SWORD_SWAPPED) == 0 and run.cue_count(SimCue.Kind.SWORD_DROPPED) == 0)
	var restarted: GameRun = _run_of(_default_specs())
	var enemy: EnemyState = EnemyState.make(EnemyDefs.HUSK, restarted.position + Vector2(300.0, 0.0), 1, 0.0, 3, 0.0, 0.0, SwordSpec.make(&"fang", 1, &"fire"))
	restarted.enemies.append(enemy)
	restarted.kill(enemy, Vector2.RIGHT)
	restarted.apply(GameCommand.restart())
	var after: GameRun = restarted
	_steps(after, 120)
	_ok("after a restart nothing of the old run drops or lies about (no pickups after 120 ticks, no drop cue)", after.pickups.is_empty() and after.cue_count(SimCue.Kind.SWORD_DROPPED) == 0)
	var scenario_drops: GameRun = GameRun.new(RunScenario.drops_encounter())
	var standing: EnemyState = scenario_drops.enemies[0]
	scenario_drops.kill(standing, Vector2.RIGHT)
	var lying_before_restart: int = scenario_drops.pickups.size()
	scenario_drops.apply(GameCommand.restart())
	var armed_standing: int = scenario_drops.enemies.filter(func(enemy_state: EnemyState) -> bool: return enemy_state.armed != null).size()
	_ok("restarting inside the drops encounter puts its twelve armed foes back and leaves no drop lying (%d lay before; %d armed foes standing, %d pickups after)" % [lying_before_restart, armed_standing, scenario_drops.pickups.size()], lying_before_restart == 1 and armed_standing == 12 and scenario_drops.pickups.is_empty())


func _check_cues() -> void:
	print("drops and swaps: cues")
	var run: GameRun = _run_of(_default_specs())
	var enemy: EnemyState = EnemyState.make(EnemyDefs.HUSK, run.position + Vector2(300.0, 20.0), 1, 0.0, 3, 0.0, 0.0, SwordSpec.make(&"colossus", 2, &"poison"))
	run.enemies.append(enemy)
	run.kill(enemy, Vector2.RIGHT)
	var cues: Array[SimCue] = run.take_cues()
	var dropped: Array[SimCue] = cues.filter(func(cue: SimCue) -> bool: return cue.kind == SimCue.Kind.SWORD_DROPPED)
	_ok("a drop is announced once, at the enemy, naming its sword (%s)" % [dropped.map(func(cue: SimCue) -> String: return "(no sword)" if cue.spec == null else cue.spec.display_name())], dropped.size() == 1 and dropped[0].position.distance_to(enemy.position) < 0.001 and dropped[0].spec != null and dropped[0].spec.display_name() == "Mythic Venom Colossus")
	run.position = enemy.position + Vector2(10.0, 0.0)
	run.try_swap(2)
	cues = run.take_cues()
	var swapped: Array[SimCue] = cues.filter(func(cue: SimCue) -> bool: return cue.kind == SimCue.Kind.SWORD_SWAPPED)
	_ok("the run's snapshot counts the drops lying (%d)" % int(run.snapshot()["pickup_count"]), int(run.snapshot()["pickup_count"]) == run.pickups.size() and run.pickups.size() == 1)
	_ok("a swap is announced once with the slot, the new sword, where the pickup lay and where the old one came down", swapped.size() == 1 and swapped[0].amount == 2 and swapped[0].spec != null and swapped[0].spec.display_name() == "Mythic Venom Colossus" and swapped[0].position.distance_to(enemy.position) < 0.001 and absf(swapped[0].origin.y - enemy.position.y - 24.0) < 0.001)
	run.try_swap(0)
	run.try_swap(0)
	var refused: Array[SimCue] = run.take_cues().filter(func(cue: SimCue) -> bool: return cue.kind == SimCue.Kind.SWAP_REFUSED)
	_ok("a swap with something still in reach is not refused, and one with nothing is (cues: swapped %d, refused %d)" % [run.cue_count(SimCue.Kind.SWORD_SWAPPED), run.cue_count(SimCue.Kind.SWAP_REFUSED)], run.cue_count(SimCue.Kind.SWORD_SWAPPED) == 3 and refused.is_empty())
	run.position = Vector2(100.0, 100.0)
	run.try_swap(1)
	_ok("walking away leaves nothing in reach: the refusal is announced", run.cue_count(SimCue.Kind.SWAP_REFUSED) == 1)


func _check_shared_definitions() -> void:
	print("drops and swaps: definitions are never mutated by swaps")
	var rarities: Array = _ref["table"]["rarities"]
	var damage_before: Array[float] = SwordDefs.RARITY_DAMAGE.duplicate()
	var cooldown_before: Array[float] = SwordDefs.RARITY_COOLDOWN.duplicate()
	var run: GameRun = _run_of(_default_specs(), 5)
	var specs: Array = []
	for kind: String in ["fang", "blade", "lance", "colossus"]:
		for rarity: int in 3:
			for element: String in ["fire", "ice", "poison"]:
				specs.append([kind, rarity, element])
	for index: int in specs.size():
		_put(run, specs[index] as Array, 5.0, 0.0)
		run.try_swap(index % 3)
		_steps(run, 3)
	_ok("after 36 swaps the rarity tables, the sword types and the drop weights still hold the prototype's values", SwordDefs.RARITY_DAMAGE == damage_before and SwordDefs.RARITY_COOLDOWN == cooldown_before and _near(SwordDefs.RARITY_DAMAGE[2], float((rarities[2] as Dictionary)["dmg"]), 1e-12) and _near(SwordDefs.base_damage(SwordDefs.FANG), 7.0, 1e-12) and _near(LootDefs.DROP_WEIGHTS[0], 3.0, 1e-12) and _near(LootDefs.PICKUP_LIFE, 45.0, 1e-12))
	var common: SwordState = SwordState.equip(SwordSpec.make(&"fang", 0, &"fire"), Vector2.ZERO, 0.0)
	var mythic: SwordState = SwordState.equip(SwordSpec.make(&"fang", 2, &"fire"), Vector2.ZERO, 0.0)
	var common_again: SwordState = SwordState.equip(SwordSpec.make(&"fang", 0, &"fire"), Vector2.ZERO, 0.0)
	_ok("a Mythic Fang built between two Common ones leaves the second exactly the first (%.2f / %.2f / %.2f)" % [common.damage, mythic.damage, common_again.damage], common.damage == common_again.damage and mythic.damage > common.damage and common.cooldown == common_again.cooldown and common.length == common_again.length)
	var spec: SwordSpec = SwordSpec.make(&"blade", 1, &"ice")
	var lying: PickupState = PickupState.make(spec, Vector2.ZERO, 1)
	var run_two: GameRun = _run_of(_default_specs())
	run_two.pickups.append(PickupState.make(spec, run_two.position + Vector2(4.0, 0.0), 2))
	run_two.try_swap(0)
	run_two.swords[0].damage *= 10.0
	run_two.swords[0].ultimate_cooldown_left = 3.0
	_ok("changing the equipped sword's own numbers never reaches the spec it came from, nor another sword made from it", spec.rarity == 1 and spec.type_id == SwordDefs.WARDEN and SwordDefs.damage_of(spec) == 17.0 * 1.3 and SwordState.equip(spec, Vector2.ZERO, 0.0).damage == 17.0 * 1.3 and lying.spec == spec)


# --------------------------------------------------------------- a whole fight
func _check_fight() -> void:
	print("drops and swaps: the drops encounter, played")
	var scenario: RunScenario = RunScenario.drops_encounter()
	scenario.seed = 21
	scenario.crit_chance = 0.12
	var run: GameRun = GameRun.new(scenario)
	var drops_expected: int = 0
	var swaps: int = 0
	var invalid: Array[String] = []
	var expired: int = 0
	var max_lying: int = 0
	var kinds_dropped: Dictionary = {}
	var rarities_dropped: Dictionary = {}
	var elements_dropped: Dictionary = {}
	var specs_seen: Dictionary = {}
	for tick_index: int in 3900:
		run.hp = run.max_hp
		var armed_before: Array[EnemyState] = []
		for enemy: EnemyState in run.enemies:
			if enemy.armed != null:
				armed_before.append(enemy)
		var lying_before: Array[PickupState] = run.pickups.duplicate()
		var drop_cues_before: int = run.cue_count(SimCue.Kind.SWORD_DROPPED)
		var swap_target: PickupState = null
		if tick_index % 120 == 0 and tick_index < 1300 and not run.pickups.is_empty():
			run.position = run.pickups[0].position + Vector2(20.0, 0.0)
			swap_target = run.nearest_pickup()
			var slot: int = floori(float(tick_index) / 120.0) % 3
			var before_swap: Array = _specs_of(run)
			if run.try_swap(slot) == GameRun.SwapResult.SWAPPED:
				swaps += 1
				if _specs_of(run)[slot] != _spec_array(swap_target.spec) or run.swords.size() != 3:
					invalid.append("tick %d: swap put %s in slot %d (before %s)" % [tick_index, _specs_of(run)[slot], slot, before_swap])
		var after_swap: Array[PickupState] = run.pickups.duplicate()
		run.step()
		var died: int = 0
		for enemy: EnemyState in armed_before:
			if not run.enemies.has(enemy):
				died += 1
				kinds_dropped[enemy.armed.type_id] = true
				rarities_dropped[enemy.armed.rarity] = true
				elements_dropped[enemy.armed.element] = true
		drops_expected += died
		if run.cue_count(SimCue.Kind.SWORD_DROPPED) != drops_expected:
			invalid.append("tick %d: %d drop cues, %d armed deaths" % [tick_index, run.cue_count(SimCue.Kind.SWORD_DROPPED), drops_expected])
		var appeared: int = 0
		for pickup: PickupState in run.pickups:
			if not after_swap.has(pickup):
				appeared += 1
			if pickup.life <= 0.0 or pickup.life > LootDefs.PICKUP_LIFE:
				invalid.append("tick %d: a pickup with life %f" % [tick_index, pickup.life])
		if appeared != died:
			invalid.append("tick %d: %d new pickups for %d armed deaths" % [tick_index, appeared, died])
		for pickup: PickupState in after_swap:
			if not run.pickups.has(pickup):
				expired += 1
				if pickup.life > 0.0:
					invalid.append("tick %d: a pickup vanished with %f s left" % [tick_index, pickup.life])
		max_lying = maxi(max_lying, run.pickups.size())
		for pickup: PickupState in run.pickups:
			specs_seen[SwordDefs.full_name(pickup.spec)] = true
		if run.dead:
			invalid.append("the fixture's player died at tick %d (the check keeps it alive)" % tick_index)
			break
	_ok("a 65-second fight in the drops encounter keeps every rule: one drop cue per armed death, one new pickup per death, no pickup older than 45 s or removed early, swaps put in exactly the claimed sword (%d problems: %s)" % [invalid.size(), invalid.slice(0, 3)], invalid.is_empty())
	_ok("it played: %d armed deaths dropped, %d swaps, %d drops expired unclaimed, up to %d lying at once, %d different swords seen lying" % [drops_expected, swaps, expired, max_lying, specs_seen.size()], drops_expected >= 12 and swaps >= 5 and expired >= 1 and max_lying >= 3 and specs_seen.size() >= 10)
	_ok("armed deaths dropped all four sword types, all three rarities and all three elements (%s / %s / %s)" % [kinds_dropped.keys(), rarities_dropped.keys(), elements_dropped.keys()], kinds_dropped.size() == 4 and rarities_dropped.size() == 3 and elements_dropped.size() == 3)


# --------------------------------------------------------------- the Main scene
func _main_with(scenario: RunScenario, sword_scene: String = "") -> Main:
	var main: Main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Main
	main.scenario = scenario
	if not sword_scene.is_empty():
		main.sword_visual = load(sword_scene)
	_tree.root.add_child(main)
	main.set_physics_process(false)
	return main


func _tick_main(main: Main, count: int) -> void:
	for i: int in count:
		main._physics_process(GameRun.TICK_DT)


func _quiet_scenario() -> RunScenario:
	var scenario: RunScenario = RunScenario.new()
	scenario.seed = 17
	scenario.waves_enabled = false
	scenario.sword_start_cooldowns = [PARKED, PARKED, PARKED]
	scenario.crit_chance = 0.0
	scenario.loadout = RunScenario.drops_fixture_loadout()
	return scenario


func _check_main_scene() -> void:
	print("drops and swaps: the real Main scene (keys, card, cues, effects, visuals)")
	var main: Main = _main_with(_quiet_scenario())
	await _tree.process_frame
	main._sfx.unlock()
	main._sfx.played.clear()
	var run: GameRun = main.run
	var hud: Hud = main._hud
	var presenter: RunPresenter = main._presenter
	var effects: EffectsLayer = presenter._effects
	_tick_main(main, 3)
	await _tree.process_frame
	_ok("with nothing lying about the card is hidden and every sword card says which key swaps it", not hud.pickup_card_visible() and [0, 1, 2].all(func(slot: int) -> bool: return hud._ult_slots[slot].text == "key %d swaps this sword" % (slot + 1)) and presenter.pickup_visual_count() == 0)
	_ok("Common swords show no rarity tag and the grey border (tags: '%s' '%s' '%s')" % [hud._ult_rarities[0].text, hud._ult_rarities[1].text, hud._ult_rarities[2].text], hud._ult_rarities[0].text == "" and hud._ult_rarities[1].text == "" and hud._ult_rarities[2].text == "")
	main._input(_key(KEY_1))
	_ok("pressing 1 with nothing in reach refuses: a refusal cue, nothing changes, and a refusal is shown", run.cue_count(SimCue.Kind.SWAP_REFUSED) == 1 and _specs_of(run) == _default_specs() and effects._texts.any(func(text: Dictionary) -> bool: return String(text["text"]) == "no sword within reach"))
	var common_drop: PickupState = _put(run, ["fang", 0, "fire"], -250.0, 0.0)
	_tick_main(main, 2)
	await _tree.process_frame
	_ok("a Common drop (out of reach) is drawn with its ring and glows but no pillar of light (drawn %s)" % [effects.draw_counts], effects.draw_counts.get(&"pickup_ring", 0) > 0 and effects.draw_counts.get(&"pickup_glow_rarity", 0) > 0 and effects.draw_counts.get(&"pickup_glow_element", 0) > 0 and effects.draw_counts.get(&"pickup_beam", 0) == 0 and presenter.pickup_visual_count() == 1)
	var mythic: PickupState = _put(run, ["lance", 2, "ice"], 30.0, -20.0)
	var rare: PickupState = _put(run, ["fang", 1, "fire"], -300.0, 0.0)
	_tick_main(main, 2)
	await _tree.process_frame
	var spec: SwordSpec = mythic.spec
	var shown: Array[String] = hud.pickup_card_lines()
	var reference_card: Array[String] = PickupCard.lines(spec)
	_ok("a Mythic Frost Pike drop in reach shows its card: %s" % [shown], hud.pickup_card_visible() and shown == reference_card and shown[0] == "Mythic Frost Pike" and shown[5] == "press 1 / 2 / 3 to swap")
	var compare: Array[String] = hud.pickup_card_comparisons()
	_ok("the card compares it with each equipped sword: %s" % [compare], compare == ["1  Common Venom Fang   DMG +35   SPD -2.3/s   RNG +307", "2  Common Frost Warden   DMG +25   SPD -0.2/s   RNG +237", "3  Common Ember Colossus   DMG -8   SPD +0.5/s   RNG +152"])
	_ok("a drop out of reach (300 px away) has no card, only the nearest in reach does", hud.pickup_card_lines()[0] == "Mythic Frost Pike" and presenter.pickup_visual_count() == 3)
	_ok("the card's name is in the Mythic colour and its element line in the element's (%s / %s)" % [hud._pickup_lines[0].modulate, hud._pickup_lines[3].modulate], hud._pickup_lines[0].modulate.is_equal_approx(SwordDefs.RARITY_COLORS[2]) and hud._pickup_lines[3].modulate.is_equal_approx(PlaceholderSwordVisual.ELEMENT_COLORS[&"ice"]) and hud._pickup_style.border_color.is_equal_approx(SwordDefs.RARITY_COLORS[2]))
	var view: Rect2 = main.get_viewport().get_visible_rect()
	_ok("the card lies inside the view (%s in %s) and clear of the sword cards" % [hud.pickup_card_rect(), view], view.grow(0.5).encloses(hud.pickup_card_rect()) and [0, 1, 2].all(func(slot: int) -> bool: return not hud.pickup_card_rect().intersects(hud._ult_cards[slot].get_global_rect())))
	_ok("both drops are drawn: a pickup visual for each, the ground ring and glows, and a pillar of light for the Mythic and the Rare (drawn %s)" % [effects.draw_counts], effects.draw_counts.get(&"pickup_ring", 0) > 0 and effects.draw_counts.get(&"pickup_glow_rarity", 0) > 0 and effects.draw_counts.get(&"pickup_glow_element", 0) > 0 and effects.draw_counts.get(&"pickup_beam", 0) >= 12 and effects.draw_counts.get(&"pickup_beam", 0) % 6 == 0)
	common_drop.life = 5.8
	var rings_before: int = effects.draw_counts.get(&"pickup_ring", 0)
	_tick_main(main, 1)
	await _tree.process_frame
	var rings_drawn: int = effects.draw_counts.get(&"pickup_ring", 0) - rings_before
	_ok("a drop in the hidden half of its blink is not drawn (the layer drew %d of 3 rings and its visual is hidden: %s)" % [rings_drawn, not (presenter._pickup_visuals[common_drop.get_instance_id()] as Node2D).visible], rings_drawn == 2 and not (presenter._pickup_visuals[common_drop.get_instance_id()] as Node2D).visible and (presenter._pickup_visuals[mythic.get_instance_id()] as Node2D).visible)
	common_drop.life = 45.0
	var visual: PlaceholderSwordVisual = null
	for child: Node in presenter.get_children():
		if child is PlaceholderSwordVisual and (child as PlaceholderSwordVisual)._resting and (child as PlaceholderSwordVisual)._scale == SwordDefs.RARITY_SIZE[2]:
			visual = child as PlaceholderSwordVisual
	_ok("the Mythic pickup is a Pike visual at the Mythic size (x1.18), glowing in the Mythic gold, hanging point-down above its shadow", visual != null and visual._pike and _near(visual._scale, 1.18, 1e-6) and visual._glow.is_equal_approx(SwordDefs.RARITY_COLORS[2]) and _near(visual._angle, PI / 2.0, 0.1) and visual._lift > 20.0)
	main._input(_key(KEY_2))
	await _tree.process_frame
	var swords: Array = _specs_of(run)
	_ok("pressing 2 puts the Mythic Frost Pike into slot two and nothing else (%s)" % [swords], swords == [["fang", 0, "poison"], ["lance", 2, "ice"], ["colossus", 0, "fire"]] and not run.pickups.has(mythic) and run.pickups.has(rare))
	_ok("it is announced and heard: a swap cue, the chime, a gold ring, sparks and the sword's name over the player", run.cue_count(SimCue.Kind.SWORD_SWAPPED) == 1 and main._sfx.played.has("chime") and effects._texts.any(func(text: Dictionary) -> bool: return String(text["text"]) == "Mythic Frost Pike" and (text["color"] as Color).is_equal_approx(SwordDefs.RARITY_COLORS[2]))
		and effects._rings.any(func(ring: Dictionary) -> bool: return (ring["color"] as Color).is_equal_approx(SwordDefs.RARITY_COLORS[2])) and effects._sparks.size() >= 20)
	_tick_main(main, 2)
	await _tree.process_frame
	_ok("slot two's card now names the Mythic Frost Pike (%s, tag '%s') in the Mythic colour and flashes (back %s vs slot one %s)" % [hud._ult_names[1].text, hud._ult_rarities[1].text, hud._ult_backs[1].color, hud._ult_backs[0].color],
		hud._ult_names[1].text == "Skewer" and hud._ult_types[1].text.begins_with("Pike sword") and hud._ult_rarities[1].text == "MYTHIC" and hud._ult_rarities[1].modulate.is_equal_approx(SwordDefs.RARITY_COLORS[2]) and hud._ult_backs[1].color.r > hud._ult_backs[0].color.r + 0.02)
	var equipped: PlaceholderSwordVisual = presenter._sword_visuals[run.swords[1].get_instance_id()] as PlaceholderSwordVisual
	var common_visual: PlaceholderSwordVisual = presenter._sword_visuals[run.swords[0].get_instance_id()] as PlaceholderSwordVisual
	_ok("the equipped Mythic Pike is drawn bigger than the Common ones (x%.2f) with the gold glow, flaring from the swap (%.2f); a Common sword glows in its element's colour" % [equipped._scale, equipped._flash], _near(equipped._scale, 1.18, 1e-6) and equipped._glow.is_equal_approx(SwordDefs.RARITY_COLORS[2]) and equipped._flash > 0.5 and common_visual._scale == 1.0 and common_visual._flash == 0.0 and common_visual._glow.is_equal_approx(PlaceholderSwordVisual.ELEMENT_COLORS[&"poison"]))
	_ok("slot cards take their rarity's colour as a border: Mythic gold on slot two, a dimmed grey on the Common slot one", (hud._ult_borders[1].get_theme_stylebox("panel") as StyleBoxFlat).border_color.is_equal_approx(SwordDefs.RARITY_COLORS[2]) and (hud._ult_borders[0].get_theme_stylebox("panel") as StyleBoxFlat).border_color.is_equal_approx(SwordDefs.RARITY_COLORS[0].darkened(0.3)))
	_ok("the old Common Frost Warden lies where the Mythic one was (a pickup visual per drop: %d, swords %d)" % [presenter.pickup_visual_count(), presenter._sword_visuals.size()], presenter.pickup_visual_count() == 3 and presenter._sword_visuals.size() == 3 and run.pickups.size() == 3 and run.pickups.has(common_drop))
	var armed_foe: EnemyState = EnemyState.make(EnemyDefs.HUSK, run.position + Vector2(500.0, 0.0), 1, 0.0, 77, 0.0, 0.0, SwordSpec.make(&"fang", 1, &"fire"))
	run.enemies.append(armed_foe)
	run.kill(armed_foe, Vector2.RIGHT)
	_tick_main(main, 1)
	_ok("an armed foe's death rings and names its sword in the rarity's colour (Rare Ember Fang)", run.cue_count(SimCue.Kind.SWORD_DROPPED) == 1 and effects._texts.any(func(text: Dictionary) -> bool: return String(text["text"]) == "Rare Ember Fang" and (text["color"] as Color).is_equal_approx(SwordDefs.RARITY_COLORS[1])) and effects._rings.any(func(ring: Dictionary) -> bool: return (ring["color"] as Color).is_equal_approx(SwordDefs.RARITY_COLORS[1])))
	# refusal when only far pickups remain
	run.position = Vector2(1900.0, 400.0)
	_tick_main(main, 2)
	await _tree.process_frame
	var refusals: int = run.cue_count(SimCue.Kind.SWAP_REFUSED)
	main._input(_key(KEY_3))
	_ok("walking away hides the card; pressing 3 refuses again and shows it", not hud.pickup_card_visible() and run.cue_count(SimCue.Kind.SWAP_REFUSED) == refusals + 1 and _specs_of(run) == swords)
	hud.restart_pressed.emit()
	await _tree.process_frame
	var sword_visuals: int = presenter.get_children().filter(func(child: Node) -> bool: return child is SwordVisual).size()
	_ok("restarting frees every drop's visual and the swapped swords' (%d sword visuals left: the three equipped; %d drops tracked)" % [sword_visuals, presenter.pickup_visual_count()], sword_visuals == 3 and presenter.pickup_visual_count() == 0 and run.pickups.is_empty())
	main.queue_free()
	await _tree.process_frame


## The text of the pickup card, not just its panel, stays inside the panel and the view: every one of the 36 swords (four
## types, three rarities, three elements) offered against the longest-named equipped swords, with the drop in the middle and at
## each corner of the view, at six window sizes. A label counts by the room its text needs (`get_minimum_size`), since a label
## wider than its panel draws past it whatever the panel's own rectangle says.
func _check_card_text_bounds() -> void:
	print("drops and swaps: every line of the pickup card stays inside its panel and the view")
	var window: Window = Window.new()
	window.size = Vector2i(1280, 720)
	window.content_scale_size = Vector2i(1280, 720)
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	_tree.root.add_child(window)
	var hud: Hud = Hud.new()
	window.add_child(hud)
	await _tree.process_frame
	hud.show_state(false, false)
	var all_specs: Array[SwordSpec] = []
	for type_id: StringName in [SwordDefs.FANG, SwordDefs.WARDEN, SwordDefs.PIKE, SwordDefs.COLOSSUS]:
		for rarity: int in 3:
			for element: StringName in SwordDefs.ELEMENT_ORDER:
				all_specs.append(SwordSpec.make(type_id, rarity, element))
	# the equipped swords whose names take the most room (measured with the card's own font and size)
	var probe: Label = hud._pickup_compare[0]
	var longest: SwordSpec = all_specs[0]
	var longest_width: float = 0.0
	for spec: SwordSpec in all_specs:
		var width: float = probe.get_theme_font("font").get_string_size(SwordDefs.full_name(spec), HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		if width > longest_width:
			longest_width = width
			longest = spec
	var run: GameRun = _run_of([_spec_array(longest), _spec_array(longest), _spec_array(longest)])
	var sizes: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1084, 720), Vector2i(1000, 563), Vector2i(1920, 1080), Vector2i(800, 1280), Vector2i(1280, 1024)]
	var problems: Array[String] = []
	var measured: int = 0
	var widest: float = 0.0
	var widest_label: String = ""
	for size: Vector2i in sizes:
		window.size = size
		await _tree.process_frame
		await _tree.process_frame
		var view: Rect2 = window.get_visible_rect()
		var targets: Array[Vector2] = [view.size * 0.5, Vector2(view.size.x - 2.0, 2.0), view.size - Vector2(2.0, 2.0), Vector2(2.0, 2.0), Vector2(2.0, view.size.y - 2.0)]
		for target: Vector2 in targets:
			for spec: SwordSpec in all_specs:
				run.pickups.clear()
				var pickup: PickupState = _put(run, _spec_array(spec), 10.0, 0.0)
				run.camera = pickup.position - (target - view.size * 0.5)
				hud.show_run(run)
				var panel: Rect2 = hud.pickup_card_rect()
				for label: Label in hud._pickup_lines + hud._pickup_compare:
					if not label.visible or label.text.is_empty():
						continue
					measured += 1
					var text_rect: Rect2 = Rect2(label.get_global_rect().position, label.get_minimum_size())
					var right_edge: float = text_rect.end.x - panel.position.x
					if right_edge > widest:
						widest = right_edge
						widest_label = label.text
					if not panel.grow(0.5).encloses(text_rect) or not view.grow(0.5).encloses(text_rect):
						problems.append("%s window %s target %s: '%s' %s outside panel %s" % [SwordDefs.full_name(spec), size, target, label.text, text_rect, panel])
	_ok("the text of every pickup card line, 36 swords x 5 places x 6 window sizes (%d lines measured, the widest reaching %.0f px into its panel: '%s'), lies inside the panel and the view (%d outside: %s)" % [measured, widest, widest_label, problems.size(), problems.slice(0, 2)], problems.is_empty() and measured > 0)
	window.queue_free()
	await _tree.process_frame


## The rectangle a HUD control draws on (a label only where its text is, the rest its own rectangle at least as large as its
## minimum size). Written apart from `Hud.occupied_rect` so a mistake in one shows against the other.
func _drawn_rect(control: Control) -> Rect2:
	var box: Rect2 = control.get_global_rect()
	if control is Label:
		var label: Label = control
		var need: Vector2 = label.get_minimum_size()
		var spare: Vector2 = Vector2(maxf(box.size.x - need.x, 0.0), maxf(box.size.y - need.y, 0.0))
		var fraction_x: float = [0.0, 0.5, 1.0, 0.0][label.horizontal_alignment]
		var fraction_y: float = [0.0, 0.5, 1.0, 0.0][label.vertical_alignment]
		return Rect2(box.position + Vector2(spare.x * fraction_x, spare.y * fraction_y), need) if not label.text.is_empty() else Rect2()
	return Rect2(box.position, Vector2(maxf(box.size.x, control.get_combined_minimum_size().x), maxf(box.size.y, control.get_combined_minimum_size().y)))


## Every HUD element on screen now, found by walking the HUD's own tree rather than asking it what to avoid: each visible control
## directly under its root except the pickup card itself and the things shown over everything or for a moment (the wave
## banner, the outcome and pause overlays, the touch joystick indicator). Name -> rectangle.
func _live_hud_elements(hud: Hud) -> Dictionary[String, Rect2]:
	var shown_over_everything: Array[Control] = [hud._pickup_card, hud._stick, hud._banner_label, hud._outcome_shade, hud._outcome_title, hud._outcome_detail, hud._outcome_prompt, hud._pause_overlay]
	var found: Dictionary[String, Rect2] = {}
	for child: Node in hud.get_child(0).get_children():
		var control: Control = child as Control
		if control == null or not control.visible or shown_over_everything.has(control):
			continue
		var rect: Rect2 = _drawn_rect(control)
		if rect.has_area():
			found["%s #%d %s" % [control.get_class(), found.size(), (control as Label).text.get_slice("\n", 0).left(24) if control is Label else (control as Button).text if control is Button else ""]] = rect
	return found


## The pickup card never covers a live HUD element. The reviewer's cases: the card used to hide the Converge countdown for a
## player at the world's west edge, the health value in its north-west corner and the Pause button in its north-east one. The
## HUD is walked independently of the code that places the card (`_live_hud_elements`), in three states (the normal run with
## the audio prompt up; the drops encounter with its three-line legend; the crowd encounter with its Shove button), the worst-
## case card text, six window sizes, a grid of 25 player positions through the real camera clamp and 12 forced places on the
## screen. Each must lie inside the view, touch no element and still be near its drop.
func _check_card_clearance() -> void:
	print("drops and swaps: the pickup card keeps clear of every live HUD element")
	var window: Window = Window.new()
	window.size = Vector2i(1280, 720)
	window.content_scale_size = Vector2i(1280, 720)
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	_tree.root.add_child(window)
	var hud: Hud = Hud.new()
	window.add_child(hud)
	await _tree.process_frame
	var worst: SwordSpec = SwordSpec.make(SwordDefs.COLOSSUS, 2, &"poison")
	var run: GameRun = _run_of([_spec_array(worst), _spec_array(worst), _spec_array(worst)])
	var half: Vector2 = GameRun.VIEW * 0.5 - Vector2(GameRun.CAMERA_OVERSCAN, GameRun.CAMERA_OVERSCAN)
	var sizes: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1084, 720), Vector2i(1000, 563), Vector2i(1920, 1080), Vector2i(800, 1280), Vector2i(1280, 1024)]
	var states: Array[Dictionary] = [
		{"name": "normal run", "encounter": RunScenario.ENCOUNTER_NORMAL, "shove": false, "audio": false},
		{"name": "drops encounter", "encounter": RunScenario.ENCOUNTER_DROPS, "shove": false, "audio": true},
		{"name": "crowd encounter", "encounter": RunScenario.ENCOUNTER_CROWD, "shove": true, "audio": true},
	]
	var xs: Array[float] = [30.0, 640.0, 1300.0, 2000.0, 2570.0]
	var ys: Array[float] = [30.0, 360.0, 900.0, 1500.0, 1770.0]
	var cases: int = 0
	var moved: int = 0
	var worst_reach: float = 0.0
	var fewest_elements: int = 1 << 20
	var outside: Array[String] = []
	var covering: Array[String] = []
	var far: Array[String] = []
	var on_drop: Array[String] = []
	for state: Dictionary in states:
		run.scenario.encounter = state["encounter"]
		run.scenario.dev_shove = state["shove"]
		hud.show_state(false, state["audio"])
		for size: Vector2i in sizes:
			window.size = size
			await _tree.process_frame
			await _tree.process_frame
			var view: Rect2 = window.get_visible_rect()
			var places: Array[Dictionary] = []
			for x: float in xs:
				for y: float in ys:
					places.append({"world": Vector2(x, y), "label": "player at (%.0f, %.0f)" % [x, y]})
			for fraction: Vector2 in [Vector2(0.0, 0.0), Vector2(0.5, 0.0), Vector2(1.0, 0.0), Vector2(0.0, 0.5), Vector2(0.5, 0.5), Vector2(1.0, 0.5), Vector2(0.0, 1.0), Vector2(0.5, 1.0), Vector2(1.0, 1.0), Vector2(0.25, 0.1), Vector2(0.75, 0.1), Vector2(0.1, 0.3)]:
				places.append({"screen": Vector2(2.0, 2.0) + fraction * (view.size - Vector2(4.0, 4.0)), "label": "drop at the view's (%.2f, %.2f)" % [fraction.x, fraction.y]})
			for place: Dictionary in places:
				run.pickups.clear()
				var drop_screen: Vector2
				if place.has("world"):
					run.position = place["world"]
					run.camera = (place["world"] as Vector2).clamp(GameRun.WORLD.position + half, GameRun.WORLD.end - half)
					_put(run, _spec_array(worst), 10.0, 0.0)
					drop_screen = run.pickups[0].position - run.camera + view.size * 0.5
				else:
					run.position = GameRun.WORLD.get_center()
					var pickup: PickupState = _put(run, _spec_array(worst), 10.0, 0.0)
					run.camera = pickup.position - ((place["screen"] as Vector2) - view.size * 0.5)
					drop_screen = place["screen"]
				hud.show_run(run)
				cases += 1
				var card: Rect2 = hud.pickup_card_rect()
				var where: String = "%s, %s, window %s, card %s" % [state["name"], place["label"], size, card]
				if not hud.pickup_card_visible() or not view.grow(0.5).encloses(card):
					outside.append(where)
				var elements: Dictionary[String, Rect2] = _live_hud_elements(hud)
				fewest_elements = mini(fewest_elements, elements.size())
				for name: String in elements:
					if card.intersects(elements[name]):
						covering.append("%s covers %s %s" % [where, name, elements[name]])
				if card.has_point(drop_screen):
					on_drop.append(where)
				var reach: float = card.get_center().distance_to(drop_screen)
				worst_reach = maxf(worst_reach, reach)
				if reach > CARD_NEAR_LIMIT:
					far.append("%s is %.0f px from its drop" % [where, reach])
				var margin: Vector2 = Vector2(Hud.PICKUP_CARD_MARGIN, Hud.PICKUP_CARD_MARGIN)
				var ideal: Vector2 = (drop_screen + Vector2(40.0, -Hud.PICKUP_CARD_SIZE.y - 40.0)).clamp(margin, (view.size - Hud.PICKUP_CARD_SIZE - margin).max(margin))
				if not card.position.is_equal_approx(ideal):
					moved += 1
	_ok("the card lies inside the view in all %d cases (3 HUD states x 6 window sizes x 37 places; %d outside: %s)" % [cases, outside.size(), outside.slice(0, 2)], outside.is_empty() and cases == 3 * 6 * 37)
	_ok("and covers no live HUD element in any of them: the health value and bar, the Converge and dash readouts, the Pause, Restart, Dev, Shove and Dash buttons, the hint and build lines, the wave line, the legend, the audio prompt and the sword cards (%d covered: %s)" % [covering.size(), covering.slice(0, 2)], covering.is_empty())
	_ok("each walk found at least 15 live elements, so nothing was skipped by mistake (fewest %d)" % fewest_elements, fewest_elements >= 15)
	_ok("and never hides the dropped sword it describes (%d cards over their drop: %s)" % [on_drop.size(), on_drop.slice(0, 2)], on_drop.is_empty())
	_ok("and stays near its drop: its centre within %.0f px of it in every case (farthest %.0f px; %d farther: %s)" % [CARD_NEAR_LIMIT, worst_reach, far.size(), far.slice(0, 2)], far.is_empty())
	_ok("the card is moved off its ideal spot (right of the drop, above it) in %d of the %d cases, so the placement is really exercised" % [moved, cases], moved > cases / 8)
	# a view too small for the card and the HUD: the documented fallback is the spot that hides the least
	run.pickups.clear()
	window.size = Vector2i(1280, 720)
	await _tree.process_frame
	await _tree.process_frame
	run.position = GameRun.WORLD.get_center()
	run.camera = run.position
	_put(run, _spec_array(worst), 10.0, 0.0)
	run.scenario.encounter = RunScenario.ENCOUNTER_DROPS
	hud.show_run(run)
	var tiny: Vector2 = Vector2(560.0, 340.0)
	var avoid: Array[Rect2] = hud.pickup_card_avoid()
	var spot: Vector2 = hud._pickup_card_spot(tiny * 0.5, tiny)
	var spot_area: float = 0.0
	var best_area: float = INF
	for rect: Rect2 in avoid:
		spot_area += Rect2(spot, Hud.PICKUP_CARD_SIZE).intersection(rect).get_area()
	for x: int in range(10, int(tiny.x - Hud.PICKUP_CARD_SIZE.x - Hud.PICKUP_CARD_MARGIN) + 1, 10):
		for y: int in range(10, int(tiny.y - Hud.PICKUP_CARD_SIZE.y - Hud.PICKUP_CARD_MARGIN) + 1, 10):
			var area: float = 0.0
			for rect: Rect2 in avoid:
				area += Rect2(Vector2(float(x), float(y)), Hud.PICKUP_CARD_SIZE).intersection(rect).get_area()
			best_area = minf(best_area, area)
	_ok("with no free spot (a %s view) the card still lies inside it and covers about as little HUD as any spot on a 10 px grid (%.0f px² against %.0f)" % [tiny, spot_area, best_area],
		spot.x >= 0.0 and spot.y >= 0.0 and spot.x + Hud.PICKUP_CARD_SIZE.x <= tiny.x + 0.5 and spot.y + Hud.PICKUP_CARD_SIZE.y <= tiny.y + 0.5 and spot_area <= best_area + 1.0, str(spot))
	window.queue_free()
	await _tree.process_frame


func _check_hud() -> void:
	print("drops and swaps: the HUD lies inside the viewport")
	var window: Window = Window.new()
	window.size = Vector2i(1084, 720)
	window.content_scale_size = Vector2i(1280, 720)
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	_tree.root.add_child(window)
	var hud: Hud = Hud.new()
	window.add_child(hud)
	var run: GameRun = _run_of([["fang", 2, "poison"], ["colossus", 1, "ice"], ["lance", 0, "fire"]])
	_put(run, ["colossus", 2, "poison"], 40.0, 0.0)
	await _tree.process_frame
	hud.show_state(false, false)
	hud.show_run(run)
	await _tree.process_frame
	var visible_rect: Rect2 = window.get_visible_rect()
	var outside: Array[String] = []
	var counted: int = 0
	for slot: int in 3:
		for control: Control in [hud._ult_cards[slot], hud._ult_names[slot], hud._ult_status[slot], hud._ult_types[slot], hud._ult_elements[slot], hud._ult_rarities[slot], hud._ult_slots[slot]]:
			counted += 1
			if not visible_rect.grow(0.5).encloses(control.get_global_rect()):
				outside.append("%s %s" % [control.name, control.get_global_rect()])
	_ok("the three slot cards with their rarity tags and swap-key lines (%d controls) are inside the %s view in a 1084x720 window: %s" % [counted, visible_rect.size, outside], outside.is_empty())
	_ok("the cards read MYTHIC / RARE / (blank for Common) and each names its swap key (%s %s %s)" % [hud._ult_rarities[0].text, hud._ult_rarities[1].text, hud._ult_rarities[2].text], hud._ult_rarities[0].text == "MYTHIC" and hud._ult_rarities[1].text == "RARE" and hud._ult_rarities[2].text == "" and hud._ult_slots[1].text == "key 2 swaps this sword")
	var card: Rect2 = hud.pickup_card_rect()
	var slot_one: Rect2 = hud._ult_cards[0].get_global_rect()
	_ok("a pickup in reach shows its card inside the view (%s) and clear of the three sword cards (%s)" % [card, slot_one], hud.pickup_card_visible() and visible_rect.grow(0.5).encloses(card) and not card.intersects(slot_one) and not card.intersects(hud._ult_cards[2].get_global_rect()))
	# a drop at the very edge of the view still gets a card inside it
	run.pickups.clear()
	run.camera = run.position - Vector2(560.0, 300.0)
	_put(run, ["fang", 1, "fire"], 10.0, 0.0)
	hud.show_run(run)
	await _tree.process_frame
	_ok("and so does a drop at the edge of the view (%s)" % hud.pickup_card_rect(), visible_rect.grow(0.5).encloses(hud.pickup_card_rect()))
	run.camera = run.position + Vector2(10.0, 0.0) + visible_rect.size * 0.5 - Vector2(120.0, visible_rect.size.y - 30.0)
	hud.show_run(run)
	await _tree.process_frame
	_ok("a drop at the bottom left of the view gets its card clear of the sword cards (%s)" % hud.pickup_card_rect(), visible_rect.grow(0.5).encloses(hud.pickup_card_rect()) and [0, 1, 2].all(func(slot: int) -> bool: return not hud.pickup_card_rect().intersects(hud._ult_cards[slot].get_global_rect())))
	run.pickups.clear()
	hud.show_run(run)
	_ok("the card goes with the drop", not hud.pickup_card_visible() and hud.pickup_card_lines().is_empty())
	_put(run, ["fang", 1, "fire"], 10.0, 0.0)
	run.hurt_player(1000, run.position + Vector2(50.0, 0.0))
	hud.show_run(run)
	_ok("a dead player is offered no card", not hud.pickup_card_visible())
	window.queue_free()
	await _tree.process_frame


func _check_encounter() -> void:
	print("drops and swaps: the drops encounter")
	var scenario: RunScenario = RunScenario.drops_encounter()
	var specs: Array[SwordSpec] = []
	var kinds: Dictionary = {}
	var types: Dictionary = {}
	var rarities: Dictionary = {}
	var elements: Dictionary = {}
	for placement: EnemyPlacement in scenario.initial_enemies:
		kinds[placement.kind] = true
		if placement.armed != null:
			specs.append(placement.armed)
			types[placement.armed.type_id] = true
			rarities[placement.armed.rarity] = true
			elements[placement.armed.element] = true
	_ok("the encounter stands 12 armed foes of all four enemy kinds, carrying all four sword types, all three rarities and all three elements (%s %s %s %s)" % [kinds.keys(), types.keys(), rarities.keys(), elements.keys()], specs.size() == 12 and kinds.size() == 4 and types.size() == 4 and rarities.size() == 3 and elements.size() == 3 and scenario.arm_waves)
	_ok("its loadout is Fang, Warden and Colossus with poison, ice and fire, and it is not the default scenario", _specs_of(GameRun.new(scenario)) == _default_specs() and RunScenario.new().arm_waves == false and RunScenario.new().encounter == RunScenario.ENCOUNTER_NORMAL)
	_ok("--encounter=drops / ?encounter=drops start it; anything else does not", LaunchOptions.scenario_for("drops").encounter == RunScenario.ENCOUNTER_DROPS and LaunchOptions.scenario_for("bogus") == null)
	_ok("the dev cycle ends with it and returns to the normal run", RunScenario.ENCOUNTER_CYCLE[RunScenario.ENCOUNTER_CYCLE.size() - 1] == RunScenario.ENCOUNTER_DROPS and RunScenario.next_encounter(RunScenario.ENCOUNTER_COLOSSUS) == RunScenario.ENCOUNTER_DROPS and RunScenario.next_encounter(RunScenario.ENCOUNTER_DROPS) == RunScenario.ENCOUNTER_NORMAL and RunScenario.encounter_title(RunScenario.ENCOUNTER_DROPS) == "Drops")
	var waved: RunScenario = RunScenario.drops_encounter()
	waved.seed = 3
	var waved_run: GameRun = GameRun.new(waved)
	while waved_run.director.wave == 0 and waved_run.tick < 400:
		waved_run.step()
	var wave_kinds: Array[StringName] = waved_run.director.queue.duplicate()
	_ok("its wave is the ten-enemy mixed one, armed by the prototype's rule (first two armed, the first with a Pike): %s" % [wave_kinds], waved.wave_kinds.size() == 10 and waved_run.director.queue_armed.size() == 10 and waved_run.director.queue_armed[0] != null and waved_run.director.queue_armed[0].type_id == SwordDefs.PIKE and waved_run.director.queue_armed[1] != null and wave_kinds.has(EnemyDefs.BRUTE) and wave_kinds.has(EnemyDefs.SPITTER))
	var colossus: GameRun = GameRun.new(RunScenario.colossus_encounter())
	colossus.apply(GameCommand.toggle_encounter())
	_ok("the C key leads from the colossus encounter to the drops encounter and restarts in it (12 armed foes standing)", colossus.scenario.encounter == RunScenario.ENCOUNTER_DROPS and colossus.enemies.filter(func(e: EnemyState) -> bool: return e.armed != null).size() == 12)
	colossus.apply(GameCommand.toggle_encounter())
	_ok("and once more back to the normal run, unarmed", colossus.scenario.encounter == RunScenario.ENCOUNTER_NORMAL and colossus.enemies.is_empty() and not colossus.scenario.arm_waves)
	var main: Main = _main_with(RunScenario.colossus_encounter())
	await _tree.process_frame
	main._hud._encounter_button.button_down.emit()
	_tick_main(main, 3)
	await _tree.process_frame
	var legend: String = main._hud._encounter_label.text
	_ok("the dev button reaches it and the legend counts armed foes and drops: %s" % legend.get_slice("\n", 0), main.run.scenario.encounter == RunScenario.ENCOUNTER_DROPS and legend.contains("DROPS ENCOUNTER") and legend.contains("armed foes left: 12") and legend.contains("swords lying: 0") and legend.contains("dropped 0, swapped 0") and main._hud._encounter_label.visible)
	var armed_visuals: int = 0
	var unarmed_visuals: int = 0
	for child: Node in main._presenter.get_children():
		if child is PlaceholderEnemyVisual:
			if (child as PlaceholderEnemyVisual)._armed != null:
				armed_visuals += 1
			else:
				unarmed_visuals += 1
	_ok("every armed foe is drawn carrying its sword (%d armed visuals, %d unarmed)" % [armed_visuals, unarmed_visuals], armed_visuals == 12 and unarmed_visuals == 0)
	var armed_standing: int = main.run.enemies.filter(func(enemy_state: EnemyState) -> bool: return enemy_state.armed != null).size()
	var carried_drawn: bool = true
	for child: Node in main._presenter.get_children():
		if child is PlaceholderEnemyVisual:
			carried_drawn = carried_drawn and (child as PlaceholderEnemyVisual).carried_draws > 0
	_ok("each carried sword is really drawn (every armed visual has drawn it)", carried_drawn and armed_visuals == 12)
	_ok("the encounter stands foes to kill once the dev button has led to it (%d standing)" % main.run.enemies.size(), not main.run.enemies.is_empty())
	if main.run.enemies.is_empty():
		main.queue_free()
		await _tree.process_frame
		return
	var victim: EnemyState = main.run.enemies[0]
	main.run.kill(victim, Vector2.RIGHT)
	main.run.position = victim.position + Vector2(10.0, 0.0)
	_tick_main(main, 1)
	main._input(_key(KEY_1))
	_tick_main(main, 100)
	await _tree.process_frame
	var queued_armed: int = 0
	for carried: SwordSpec in main.run.director.queue_armed:
		queued_armed += 1 if carried != null else 0
	var marked_armed: int = 0
	for marker: SpawnMarker in main.run.director.markers:
		marked_armed += 1 if marker.armed != null else 0
	var standing_armed: int = main.run.enemies.filter(func(enemy_state: EnemyState) -> bool: return enemy_state.armed != null).size()
	var legend_after: String = main._hud._encounter_label.text
	_ok("after a kill and a swap the legend counts armed foes (%d standing + %d queued + %d telegraphed, wave %d), swords lying (%d), drops and swaps: %s" % [standing_armed, queued_armed, marked_armed, main.run.director.wave, main.run.pickups.size(), legend_after.get_slice("\n", 0)],
		legend_after.contains("armed foes left: %d" % (standing_armed + queued_armed + marked_armed)) and queued_armed + marked_armed >= 1 and legend_after.contains("swords lying: %d" % main.run.pickups.size()) and main.run.pickups.size() >= 1 and legend_after.contains("dropped %d, swapped 1" % main.run.cue_count(SimCue.Kind.SWORD_DROPPED)) and armed_standing == 12)
	var window_rect: Rect2 = main.get_viewport().get_visible_rect()
	_ok("the legend fits the view (%s)" % main._hud._encounter_label.get_global_rect(), window_rect.grow(0.5).encloses(main._hud._encounter_label.get_global_rect()))
	main.queue_free()
	await _tree.process_frame


func _check_visual_independence() -> void:
	print("drops and swaps: replacing the sword visual leaves the fight unchanged")
	var hosts: Array[Main] = []
	for use_alt: bool in [false, true]:
		hosts.append(_main_with(RenderRateScenario.scenario(RenderRateScenario.DROPS), "res://tests/alt_sword.tscn" if use_alt else ""))
	await _tree.process_frame
	var alt_hovered: bool = false
	var pickup_visuals: int = 0
	var results: Array[Dictionary] = []
	for host_index: int in hosts.size():
		var main: Main = hosts[host_index]
		for tick_index: int in 700:
			for command: GameCommand in RenderRateScenario.commands_at(main.run.tick, RenderRateScenario.DROPS):
				main.run.apply(command)
			_tick_main(main, 1)
			if host_index == 1:
				for child: Node in main._presenter.get_children():
					if child is AltSwordVisual and (child as AltSwordVisual).last_hover > 0.0:
						alt_hovered = true
				pickup_visuals = maxi(pickup_visuals, main._presenter.pickup_visual_count())
		results.append(RenderRateScenario.digest(main.run))
	_ok("a stretched, rotated replacement sword visual changes nothing about the drops, swaps, kills or recharges", results[0] == results[1])
	_ok("the replacement visual was told about the dropped swords' hover (%s) and up to %d lay at once" % [alt_hovered, pickup_visuals], alt_hovered and pickup_visuals >= 2)
	_ok("the fixture dropped %d swords and swapped %d" % [hosts[0].run.cue_count(SimCue.Kind.SWORD_DROPPED), hosts[0].run.cue_count(SimCue.Kind.SWORD_SWAPPED)], hosts[0].run.cue_count(SimCue.Kind.SWORD_DROPPED) >= 4 and hosts[0].run.cue_count(SimCue.Kind.SWORD_SWAPPED) >= 3)
	for main: Main in hosts:
		main.queue_free()
	await _tree.process_frame


# -------------------------------------------------------- render rates
func _check_render_rates() -> void:
	if not RenderRateScenario.probes_enabled():
		return
	print("drops and swaps: identical outcomes at low and high render rates")
	var headless: Dictionary = RenderRateScenario.play_headless(RenderRateScenario.DROPS)
	var expected_digest: Dictionary = JSON.parse_string(JSON.stringify(headless))
	_ok("the scripted fight does something worth comparing (drops %d, swaps %d, refused swaps %d, ultimates %d, refused ultimates %d, hits %d, kills %d, lying %d, alive %s)" % [int(headless["drop_cues"]), int(headless["swap_cues"]), int(headless["swap_refused_cues"]), int(headless["ultimate_cues"]), int(headless["refused_cues"]), int(headless["hit_cues"]), int(headless["kills"]), (headless["pickups"] as Array).size(), not bool(headless["dead"])],
		int(headless["drop_cues"]) >= 6 and int(headless["swap_cues"]) >= 4 and int(headless["swap_refused_cues"]) >= 2 and int(headless["ultimate_cues"]) >= 2 and int(headless["hit_cues"]) >= 20 and int(headless["kills"]) >= 6 and (headless["pickups"] as Array).size() >= 2 and not bool(headless["dead"]))
	var executable: String = OS.get_executable_path()
	var project: String = ProjectSettings.globalize_path("res://")
	var frames: Dictionary[int, int] = {}
	for rate: int in PROBE_FRAME_RATES:
		var output: Array = []
		var arguments: PackedStringArray = ["--headless", "--path", project, "--fixed-fps", str(rate), "--script", PROBE_SCRIPT, "--", "--probe=rate-drops"]
		var code: int = OS.execute(executable, arguments, output, true)
		var line: String = _probe_line(output)
		_ok("the engine played the drops fight at %d fps (exit %d)" % [rate, code], code == 0 and not line.is_empty(), "%s" % [output])
		if line.is_empty():
			continue
		var result: Dictionary = JSON.parse_string(line)
		frames[rate] = int(result["frames"])
		var comparable: Dictionary = result.duplicate()
		for key: String in ["frames", "visuals", "enemies", "pickup_visuals"]:
			comparable.erase(key)
		_ok("at %d fps the real Main scene ends the fight exactly like the bare simulation: same drops, swaps, loadout, lying swords, recharges, kills and positions" % rate, comparable == expected_digest, _first_difference(comparable, expected_digest))
	_ok("the rates really differed: the engine drew %s frames for the same %d ticks" % [frames, RenderRateScenario.TOTAL_TICKS],
		frames.size() == PROBE_FRAME_RATES.size() and frames[5] < frames[20] and frames[20] < frames[60] and frames[60] < frames[240])


func _probe_line(output: Array) -> String:
	for chunk: Variant in output:
		for line: String in String(chunk).split("\n"):
			if line.begins_with("PROBE {"):
				return line.trim_prefix("PROBE ")
	return ""


func _first_difference(a: Dictionary, b: Dictionary) -> String:
	for key: Variant in a:
		if JSON.stringify(a[key]) != JSON.stringify(b.get(key)):
			return "%s: %s vs %s" % [key, a[key], b.get(key)]
	return ""
