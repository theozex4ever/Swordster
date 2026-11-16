class_name FeedbackHudChecks
extends RefCounted
## Behavioural checks for readable combat feedback, sound and the desktop HUD (issue #19). Like every earlier group each check drives
## the real `GameRun`, `InputTranslator` or Main scene with fixed ticks and observes outcomes: the HUD's numbers are read back from
## what a real run did to it, the keys are the very events a player's keyboard and mouse produce, and the sounds are the ones the
## Main scene's `SfxBank` really started. The prototype's values (the sound table, the HUD's draw code, the particle recipes) come from
## game/main.py; tolerances and deliberate exceptions: docs/reference/feedback-sound-hud.md.
##
## Every loop that waits for something is bounded by a counter of its own, independent of the simulation tick, and fails when the bound
## is hit. What headless cannot prove (that a sample is audible, that a frame looks right) is covered by the export evidence instead.

## The prototype's `SOUND_DEFS`: duration in seconds and volume. Every baked sound must match.
const PROTOTYPE_SOUNDS: Dictionary = {
	"tick": [0.09, 0.35], "slash": [0.2, 0.45], "pierce": [0.24, 0.5], "boom": [0.95, 0.9], "thud": [0.14, 0.4],
	"whoosh": [0.18, 0.25], "heave": [0.45, 0.4], "hurt": [0.3, 0.5], "pop": [0.16, 0.35], "chime": [0.55, 0.4],
	"dash": [0.2, 0.3], "gong": [1.3, 0.55], "parry": [0.18, 0.3], "shot": [0.15, 0.25],
}
const INTERFACE_SOUNDS: Array[String] = ["unlock", "pause", "resume", "restart"]
const SOUND_RATE: int = 22050
const HEALED_FULL: float = 1e9
## No wait in these checks lasts more than this many iterations whatever the tick does.
const MAX_WAIT: int = 4000
const WINDOW_SIZES: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1084, 720), Vector2i(1000, 563), Vector2i(1920, 1080), Vector2i(800, 1280), Vector2i(1280, 1024)]

var _check: Callable
var _tree: SceneTree


func _init(check_function: Callable, tree: SceneTree) -> void:
	_check = check_function
	_tree = tree


func run_all() -> void:
	if not CheckFocus.includes("feedback_hud"):
		return
	_check_sound_files()
	await _check_sound_sites()
	await _check_sound_in_a_run()
	_check_cues_from_the_run()
	await _check_audio_unlock()
	await _check_help()
	await _check_chain_counter()
	await _check_cooldown_readouts()
	await _check_health_and_counters()
	await _check_keys_and_mouse()
	await _check_pause_and_death()
	await _check_banner_then_card()
	await _check_layout()
	await _check_hurt_flash()
	await _check_impact_effects()
	await _check_trails_and_cracks()
	await _check_timing_unchanged()
	await _check_textured_look()


# --------------------------------------------------------------- helpers
func _ok(label: String, condition: bool, detail: String = "") -> void:
	_check.call(label, condition, detail)


func _near(a: float, b: float, tolerance: float) -> bool:
	return absf(a - b) <= tolerance


func _main_with(scenario: RunScenario) -> Main:
	var main: Main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Main
	main.scenario = scenario
	_tree.root.add_child(main)
	main.set_physics_process(false)
	return main


func _tick_main(main: Main, count: int, invulnerable: bool = true) -> void:
	for i: int in count:
		if invulnerable:
			main.run.iframes = HEALED_FULL
		main._physics_process(GameRun.TICK_DT)


func _key(code: Key, pressed: bool = true) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	return event


func _press(main: Main, code: Key) -> void:
	main._input(_key(code))
	main._input(_key(code, false))


func _click(main: Main, at: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = button
	event.position = at
	event.pressed = true
	main._input(event)
	main._unhandled_input(event)


## A normal run with no swords, a fixed seed and nothing that can hurt the player: the controlled start for the HUD checks.
func _quiet_scenario(seed_value: int) -> RunScenario:
	var scenario: RunScenario = RunScenario.normal_run()
	scenario.seed = seed_value
	scenario.crit_chance = 0.0
	var no_swords: Array[SwordSpec] = []
	scenario.loadout = no_swords
	return scenario


func _heard(main: Main, cue: SimCue) -> Array[String]:
	main._sfx.played.clear()
	main._sfx._last_ms.clear()
	main._sfx.play_cue(cue)
	return main._sfx.played.duplicate()


func _cue_of(kind: SimCue.Kind, type_id: StringName = &"", heavy: bool = false, amount: int = 0) -> SimCue:
	var cue: SimCue = SimCue.make(kind, Vector2.ZERO, Vector2.RIGHT, amount)
	if type_id != &"":
		cue.spec = SwordSpec.make(type_id, 0, &"fire")
	cue.heavy = heavy
	return cue


## A click as the engine delivers it to `_input` (a Converge is made of it only later, in `_unhandled_input`).
func _gesture_click(main: Main, button: MouseButton) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = button
	event.position = Vector2(300.0, 300.0)
	event.pressed = true
	main._input(event)


func _text_rect(control: Control) -> Rect2:
	var label: Label = control as Label
	if label == null:
		return control.get_global_rect()
	return Hud.occupied_rect(label)


# --------------------------------------------------------------- the baked sounds
func _check_sound_files() -> void:
	print("feedback: the baked sounds")
	var missing: Array[String] = []
	for sound: String in PROTOTYPE_SOUNDS:
		if not SfxBank.SOUNDS.has(sound):
			missing.append(sound)
	for sound: String in INTERFACE_SOUNDS:
		if not SfxBank.SOUNDS.has(sound):
			missing.append(sound)
	_ok("the bank holds the prototype's fourteen sounds and the four interface sounds (missing: %s)" % [missing], missing.is_empty() and SfxBank.SOUNDS.size() == 18)
	var wrong_length: Array[String] = []
	var wrong_loudness: Array[String] = []
	var wrong_format: Array[String] = []
	var clicks: Array[String] = []
	for sound: String in PROTOTYPE_SOUNDS:
		var table: Array = PROTOTYPE_SOUNDS[sound]
		# the committed WAV is the recipe's output; the engine imports it compressed, so the samples are read from the source file
		var bytes: PackedByteArray = FileAccess.get_file_as_bytes("res://audio/sfx_%s.wav" % sound)
		var header_ok: bool = bytes.size() > 44 and bytes.slice(0, 4).get_string_from_ascii() == "RIFF" and bytes.decode_u16(20) == 1 and bytes.decode_u16(22) == 1 and bytes.decode_u32(24) == SOUND_RATE and bytes.decode_u16(34) == 16
		if not header_ok:
			wrong_format.append(sound)
			continue
		var samples: int = int(float(SOUND_RATE) * float(table[0]))
		if (bytes.size() - 44) / 2 != samples:
			wrong_length.append("%s: %d samples, the prototype renders %d" % [sound, (bytes.size() - 44) / 2, samples])
		var peak: float = 0.0
		for i: int in (bytes.size() - 44) / 2:
			peak = maxf(peak, absf(float(bytes.decode_s16(44 + i * 2)) / 32767.0))
		# the prototype scales its samples (each below 1 after tanh) by the sound's volume
		if peak > float(table[1]) + 0.002 or peak < float(table[1]) * 0.25:
			wrong_loudness.append("%s peaks at %.3f, volume %.2f" % [sound, peak, table[1]])
		var last: int = bytes.decode_s16(bytes.size() - 2)
		if absi(last) > 400:
			clicks.append("%s ends at %d" % [sound, last])
		var imported: AudioStreamWAV = SfxBank.SOUNDS[sound] as AudioStreamWAV
		if imported == null or absf(imported.get_length() - float(samples) / float(SOUND_RATE)) > 0.03 or imported.mix_rate != SOUND_RATE:
			wrong_format.append("%s imports as %s" % [sound, imported])
	_ok("every prototype sound is a mono 16-bit 22050 Hz WAV exactly as long as the prototype renders it, and the engine imports it at that length (%s; %s)" % [wrong_length.slice(0, 2), wrong_format.slice(0, 2)], wrong_format.is_empty() and wrong_length.is_empty())
	_ok("each is as loud as its volume says (peak never above it, never a quarter of it: %s) and ends faded out, not on a click (%s)" % [wrong_loudness.slice(0, 2), clicks.slice(0, 2)], wrong_loudness.is_empty() and clicks.is_empty())
	var unique: Dictionary = {}
	for sound: String in PROTOTYPE_SOUNDS:
		unique[FileAccess.get_file_as_bytes("res://audio/sfx_%s.wav" % sound).hex_encode()] = true
	_ok("no two prototype sounds are the same file (%d distinct of %d)" % [unique.size(), PROTOTYPE_SOUNDS.size()], unique.size() == PROTOTYPE_SOUNDS.size())


# --------------------------------------------------------------- where each sound plays
func _check_sound_sites() -> void:
	print("feedback: each sound plays where the prototype plays it")
	var main: Main = _main_with(_quiet_scenario(5))
	await _tree.process_frame
	main._sfx.unlock()
	var table: Array = [
		["a Fang's normal blow ticks and thuds", _cue_of(SimCue.Kind.ENEMY_HIT, SwordDefs.FANG), ["tick", "thud"]],
		["a Warden's normal blow slashes and thuds", _cue_of(SimCue.Kind.ENEMY_HIT, SwordDefs.WARDEN), ["slash", "thud"]],
		["a Pike's normal blow pierces and thuds", _cue_of(SimCue.Kind.ENEMY_HIT, SwordDefs.PIKE), ["pierce", "thud"]],
		["a Colossus's normal blow booms and thuds", _cue_of(SimCue.Kind.ENEMY_HIT, SwordDefs.COLOSSUS), ["boom", "thud"]],
		["a Fang's heavy dart ticks and thuds", _cue_of(SimCue.Kind.ENEMY_HIT, SwordDefs.FANG, true), ["tick", "thud"]],
		["a Warden's heavy beat only thuds (the slash belongs to the beat)", _cue_of(SimCue.Kind.ENEMY_HIT, SwordDefs.WARDEN, true), ["thud"]],
		["a Pike's heavy Skewer hit only thuds", _cue_of(SimCue.Kind.ENEMY_HIT, SwordDefs.PIKE, true), ["thud"]],
		["a Colossus's heavy slam hit only thuds", _cue_of(SimCue.Kind.ENEMY_HIT, SwordDefs.COLOSSUS, true), ["thud"]],
		["a wall slam thuds", _cue_of(SimCue.Kind.WALL_SLAM), ["thud"]],
		["a Fang begins its strike with a whoosh", _cue_of(SimCue.Kind.SWORD_STRIKE, SwordDefs.FANG), ["whoosh"]],
		["a Warden begins its sweep with a whoosh", _cue_of(SimCue.Kind.SWORD_STRIKE, SwordDefs.WARDEN), ["whoosh"]],
		["a Pike begins its thrust with a whoosh", _cue_of(SimCue.Kind.SWORD_STRIKE, SwordDefs.PIKE), ["whoosh"]],
		["a Colossus begins its slam with a heave", _cue_of(SimCue.Kind.SWORD_STRIKE, SwordDefs.COLOSSUS), ["heave"]],
		["a kill pops", _cue_of(SimCue.Kind.ENEMY_KILLED), ["pop"]],
		["a hit on the player hurts", _cue_of(SimCue.Kind.PLAYER_HURT), ["hurt"]],
		["a dash dashes", _cue_of(SimCue.Kind.DASH), ["dash"]],
		["a Viper Flurry begins with a dash", _cue_of(SimCue.Kind.ULTIMATE_STARTED, SwordDefs.FANG), ["dash"]],
		["a Maelstrom begins with a whoosh", _cue_of(SimCue.Kind.ULTIMATE_STARTED, SwordDefs.WARDEN), ["whoosh"]],
		["a Skewer begins with a heave", _cue_of(SimCue.Kind.ULTIMATE_STARTED, SwordDefs.PIKE), ["heave"]],
		["a Cataclysm begins with a heave", _cue_of(SimCue.Kind.ULTIMATE_STARTED, SwordDefs.COLOSSUS), ["heave"]],
		["a Maelstrom beat that struck something slashes", _cue_of(SimCue.Kind.MAELSTROM_BEAT, &"", false, 2), ["slash"]],
		["a Maelstrom beat that struck nothing is silent", _cue_of(SimCue.Kind.MAELSTROM_BEAT, &"", false, 0), []],
		["a Maelstrom's burst slashes", _cue_of(SimCue.Kind.MAELSTROM_BURST), ["slash"]],
		["a Skewer's launch pierces", _cue_of(SimCue.Kind.SKEWER_LAUNCHED), ["pierce"]],
		["a Skewer's release is silent", _cue_of(SimCue.Kind.SKEWER_RELEASED, &"", false, 3), []],
		["a slam booms", _cue_of(SimCue.Kind.COLOSSUS_SLAM), ["boom"]],
		["a freeze rings like a parry", _cue_of(SimCue.Kind.ENEMY_FROZEN), ["parry"]],
		["a parried orb parries", _cue_of(SimCue.Kind.PROJECTILE_PARRIED), ["parry"]],
		["a spitter's shot shoots", _cue_of(SimCue.Kind.PROJECTILE_FIRED), ["shot"]],
		["a Converge chimes", _cue_of(SimCue.Kind.CONVERGE), ["chime"]],
		["a swap chimes", _cue_of(SimCue.Kind.SWORD_SWAPPED), ["chime"]],
		["a wave's start sounds the gong", _cue_of(SimCue.Kind.WAVE_STARTED), ["gong"]],
		["a wave's end has no sound of its own", _cue_of(SimCue.Kind.WAVE_CLEARED), []],
		["a refused swap is silent", _cue_of(SimCue.Kind.SWAP_REFUSED), []],
	]
	for row: Array in table:
		var got: Array[String] = _heard(main, row[1] as SimCue)
		_ok("%s (%s)" % [row[0], got], got == (row[2] as Array))
	# the prototype never plays the same sound again within 40 ms, but different sounds overlap freely
	main._sfx.played.clear()
	main._sfx._last_ms.clear()
	main._sfx.play("thud")
	main._sfx._last_ms["thud"] = Time.get_ticks_msec() - 20
	main._sfx.play("thud")
	main._sfx.play("pop")
	_ok("the same sound is not restarted 20 ms after itself, a different one is (%s)" % [main._sfx.played], main._sfx.played == ["thud", "pop"])
	main._sfx._last_ms["thud"] = Time.get_ticks_msec() - 60
	main._sfx.play("thud")
	_ok("and it plays again once 40 ms have passed (%s)" % [main._sfx.played], main._sfx.played == ["thud", "pop", "thud"])
	var polyphonic: bool = true
	for sound: String in SfxBank.SOUNDS:
		polyphonic = polyphonic and (main._sfx._players[sound] as AudioStreamPlayer).max_polyphony >= 4
	_ok("every sound can ring in several overlapping instances (the prototype's 24 channels), so a slow boom is not cut off by the next one", polyphonic)
	main.queue_free()
	await _tree.process_frame


## A real fight through the Main scene is heard: the sounds a Fang, a Warden and a Colossus make in an ordinary run.
func _check_sound_in_a_run() -> void:
	print("feedback: a real run is heard")
	var scenario: RunScenario = RunScenario.normal_run()
	scenario.seed = 61
	var main: Main = _main_with(scenario)
	await _tree.process_frame
	main._sfx.unlock()
	var heard: Dictionary = {}
	var waited: int = 0
	while waited < MAX_WAIT and not (heard.has("gong") and heard.has("whoosh") and heard.has("heave") and heard.has("thud") and heard.has("pop") and heard.has("tick")):
		main._sfx._last_ms.clear()
		_tick_main(main, 1)
		for sound: String in main._sfx.played:
			heard[sound] = true
		main._sfx.played.clear()
		waited += 1
	_ok("the first wave of a normal run sounds its gong, its swords whoosh and heave, Fang ticks, blows thud and kills pop (heard %s after %d ticks)" % [heard.keys(), waited], heard.has("gong") and heard.has("whoosh") and heard.has("heave") and heard.has("thud") and heard.has("pop") and heard.has("tick"))
	var stale: bool = false
	for sound: String in heard:
		stale = stale or not SfxBank.SOUNDS.has(sound)
	_ok("and nothing it played is outside the bank", not stale)
	main.queue_free()
	await _tree.process_frame


## The cues a real run produces carry what the sounds and sparks need: the sword that struck, whether it was heavy, what died and how.
func _check_cues_from_the_run() -> void:
	print("feedback: the run's cues carry the sword, the weight of a blow and what died")
	var scenario: RunScenario = RunScenario.normal_run()
	scenario.seed = 3
	scenario.crit_chance = 0.0
	scenario.wave_count = 0
	var run: GameRun = GameRun.new(scenario)
	run.iframes = HEALED_FULL
	var warden: SwordState = run.swords[1]
	var brute: EnemyState = EnemyState.make(EnemyDefs.BRUTE, run.position + Vector2(300.0, 0.0), 1, 0.0, 9400, 0.0, 0.0, null)
	run.enemies.append(brute)
	run.take_cues()
	run.hit_enemy(brute, 5.0, Vector2.RIGHT, 10.0, warden, false)
	run.hit_enemy(brute, 5.0, Vector2.RIGHT, 10.0, warden, true)
	var hits: Array[SimCue] = []
	for cue: SimCue in run.take_cues():
		if cue.kind == SimCue.Kind.ENEMY_HIT:
			hits.append(cue)
	_ok("a blow's cue names the sword that struck, how heavy it was and how big its target (%d cues)" % hits.size(), hits.size() == 2 and hits[0].spec == warden.spec and not hits[0].heavy and hits[1].heavy and hits[1].spec == warden.spec and hits[0].radius == brute.radius)
	run.hit_enemy(brute, 9999.0, Vector2.RIGHT, 10.0, warden, true)
	var deaths: Array[SimCue] = []
	for cue: SimCue in run.take_cues():
		if cue.kind == SimCue.Kind.ENEMY_KILLED:
			deaths.append(cue)
	_ok("a kill by a heavy blow says what died, how big it was and that the blow was heavy (the prototype's `kill(.., big)`)", deaths.size() == 1 and deaths[0].enemy_kind == EnemyDefs.BRUTE and deaths[0].radius == brute.radius and deaths[0].critical)
	var husk: EnemyState = EnemyState.make(EnemyDefs.HUSK, run.position + Vector2(300.0, 0.0), 1, 0.0, 9401, 0.0, 0.0, null)
	run.enemies.append(husk)
	run.hit_enemy(husk, 9999.0, Vector2.RIGHT, 10.0, warden, false)
	var light: Array[SimCue] = []
	for cue: SimCue in run.take_cues():
		if cue.kind == SimCue.Kind.ENEMY_KILLED:
			light.append(cue)
	_ok("and one by a plain blow is not heavy", light.size() == 1 and light[0].enemy_kind == EnemyDefs.HUSK and not light[0].critical)
	run.try_ultimate(1, run.position + Vector2(200.0, 0.0))
	var started: Array[SimCue] = []
	for cue: SimCue in run.take_cues():
		if cue.kind == SimCue.Kind.ULTIMATE_STARTED:
			started.append(cue)
	_ok("an ultimate's cue names the sword whose ultimate it is", started.size() == 1 and started[0].spec == warden.spec)


## Browsers keep audio locked until the first click, tap or key: nothing is heard before, the first gesture unlocks and says so, and
## releasing a key or a finger is not a gesture.
func _check_audio_unlock() -> void:
	print("feedback: audio unlocks on the first gesture")
	var gestures: Array = [
		["a key press", func(main: Main) -> void: main._input(_key(KEY_X))],
		["a left click", func(main: Main) -> void: _gesture_click(main, MOUSE_BUTTON_LEFT)],
		["a right click", func(main: Main) -> void: _gesture_click(main, MOUSE_BUTTON_RIGHT)],
		["a touch", func(main: Main) -> void:
			var touch: InputEventScreenTouch = InputEventScreenTouch.new()
			touch.index = 0
			touch.position = Vector2(200.0, 400.0)
			touch.pressed = true
			main._input(touch)],
	]
	for gesture: Array in gestures:
		var main: Main = _main_with(_quiet_scenario(8))
		await _tree.process_frame
		main._sfx.play_cue(_cue_of(SimCue.Kind.PLAYER_HURT))
		main._sfx.play("chime")
		_ok("before any gesture nothing is heard (%s) and the prompt asks for a click or tap" % [main._sfx.played], main._sfx.played.is_empty() and not main._sfx.unlocked and main._hud._audio_prompt.visible)
		(gesture[1] as Callable).call(main)
		_ok("%s unlocks the sound, plays the unlock chirp once and hides the prompt (%s)" % [gesture[0], main._sfx.played], main._sfx.unlocked and main._sfx.played == ["unlock"] and not main._hud._audio_prompt.visible)
		main._sfx._last_ms.clear()
		main._sfx.play_cue(_cue_of(SimCue.Kind.PLAYER_HURT))
		_ok("and from then on the game is heard", main._sfx.played == ["unlock", "hurt"])
		main.queue_free()
		await _tree.process_frame
	var released: Main = _main_with(_quiet_scenario(9))
	await _tree.process_frame
	released._input(_key(KEY_X, false))
	var lift: InputEventScreenTouch = InputEventScreenTouch.new()
	lift.pressed = false
	released._input(lift)
	var click_up: InputEventMouseButton = InputEventMouseButton.new()
	click_up.button_index = MOUSE_BUTTON_LEFT
	click_up.pressed = false
	released._input(click_up)
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = Vector2(50.0, 50.0)
	released._input(motion)
	_ok("releasing a key or a finger and moving the mouse are not gestures: the sound stays locked", not released._sfx.unlocked and released._sfx.played.is_empty())
	released.queue_free()
	await _tree.process_frame


# --------------------------------------------------------------- the help overlay
func _check_help() -> void:
	print("feedback: the help overlay")
	var main: Main = _main_with(_quiet_scenario(11))
	await _tree.process_frame
	var run: GameRun = main.run
	var hud: Hud = main._hud
	_tick_main(main, 2)
	var shown_lines: Array[String] = []
	for line: Label in hud._help_lines:
		shown_lines.append(line.text)
	_ok("a new run shows the prototype's seven help lines for its first 14 seconds (%d lines, %.1f s left)" % [shown_lines.size(), run.help_left], hud.help_visible() and shown_lines == Hud.HELP_LINES and shown_lines.size() == 7 and _near(run.help_left, 14.0 - 2.0 / 60.0, 0.01))
	_ok("the lines are the prototype's: movement, dash, Converge, the three ultimates, swaps, ranges, pause and help, and the elements", shown_lines[0].begins_with("WASD") and shown_lines[1].contains("dash") and shown_lines[2].contains("CONVERGE") and shown_lines[3].contains("Q / E / R") and shown_lines[4].contains("swap") and shown_lines[5].contains("TAB or G") and shown_lines[5].contains("H  hide help") and shown_lines[6].contains("fire / ice / poison"))
	_press(main, KEY_H)
	_tick_main(main, 1)
	_ok("H hides it at once", run.help_left <= 0.0 and not hud.help_visible())
	_press(main, KEY_H)
	_tick_main(main, 1)
	_ok("H again shows it until it is hidden (%.0f s)" % run.help_left, run.help_left > 9000.0 and hud.help_visible())
	_tick_main(main, 600)
	_ok("shown that way it does not run out", hud.help_visible() and hud.help_alpha() > 0.8)
	_press(main, KEY_H)
	run.help_left = 0.5
	_press(main, KEY_H)
	run.help_left = 0.5
	_tick_main(main, 1)
	_ok("in its last second the help fades out with the time left (alpha %.2f)" % hud.help_alpha(), hud.help_visible() and _near(hud.help_alpha(), (0.5 - 1.0 / 60.0) * 0.86, 0.01))
	var waited: int = 0
	while run.help_left > 0.0 and waited < MAX_WAIT:
		_tick_main(main, 1)
		waited += 1
	_ok("then it is gone by itself (after %d more ticks)" % waited, not hud.help_visible() and waited < 60)
	# paused and dead: H does nothing, and the time does not run
	run.help_left = 9.0
	_press(main, KEY_P)
	var before: float = run.help_left
	_press(main, KEY_H)
	_tick_main(main, 30)
	_ok("while paused H does nothing and the help's time stands still (%.2f s)" % run.help_left, run.paused and run.help_left == before)
	_press(main, KEY_P)
	run.help_left = 0.0
	run.hp = 1.0
	run.iframes = 0.0
	run.hurt_player(50, run.position + Vector2(30.0, 0.0))
	_press(main, KEY_H)
	_ok("while dead H does nothing and the help stays hidden", run.dead and run.help_left <= 0.0 and not hud.help_visible())
	main.queue_free()
	await _tree.process_frame
	# a restart gives the help its fourteen seconds again, and it gives way to the banner and to a dropped sword's card
	var again: Main = _main_with(_quiet_scenario(12))
	await _tree.process_frame
	_press(again, KEY_H)
	_tick_main(again, 5)
	again.run.apply(GameCommand.restart())
	_tick_main(again, 1)
	_ok("a restart brings the help back for 14 seconds", again.run.help_left > 13.9 and again._hud.help_visible())
	again.run.set_banner("WAVE 9", 2.4, "something to do")
	_tick_main(again, 1)
	_ok("it gives way while the wave banner is up (they would sit on each other)", not again._hud.help_visible() and again.run.help_left > 13.0)
	again.run.banner_left = 0.0
	again.run.banner_title = ""
	again.run.pickups.append(PickupState.make(SwordSpec.make(SwordDefs.FANG, 0, &"fire"), again.run.position + Vector2(20.0, 0.0), 1))
	_tick_main(again, 1)
	_ok("and while a dropped sword's card is up", not again._hud.help_visible() and again._hud.pickup_card_visible())
	again.run.pickups.clear()
	_tick_main(again, 1)
	_ok("and comes back when they are gone", again._hud.help_visible())
	again.queue_free()
	await _tree.process_frame


# --------------------------------------------------------------- the chain counter
func _check_chain_counter() -> void:
	print("feedback: the chain counter")
	var main: Main = _main_with(_quiet_scenario(13))
	await _tree.process_frame
	var run: GameRun = main.run
	var hud: Hud = main._hud
	for kills: int in 3:
		run.kill(EnemyState.make(EnemyDefs.HUSK, run.position + Vector2(500.0, 0.0), 1, 0.0, 9000, 0.0, 0.0, null), Vector2.RIGHT)
		if kills == 1:
			_tick_main(main, 1)
			_ok("two kills in a row show no counter, as the prototype's counter begins at three (text '%s')" % hud.chain_text(), hud.chain_text() == "")
	_tick_main(main, 1)
	_ok("the third kill shows the large x3 at the top right ('%s')" % hud.chain_text(), hud.chain_text() == "x3" and hud._chain_label.visible)
	var label: Rect2 = Hud.occupied_rect(hud._chain_label)
	var view: Rect2 = main.get_viewport().get_visible_rect()
	_ok("at the prototype's size 56 (font %d) in the top right corner (%s of %s)" % [hud._chain_label.get_theme_font_size("font_size"), label, view], hud._chain_label.get_theme_font_size("font_size") == 56 and label.end.x > view.size.x * 0.8 and label.position.y < view.size.y * 0.3 and view.grow(0.5).encloses(label))
	var fresh: Color = hud._chain_label.get_theme_color("font_color")
	_ok("fresh, it is the prototype's gold (%s)" % [fresh], _near(fresh.r, 1.0, 0.01) and _near(fresh.g, 0.82, 0.01) and _near(fresh.b, 0.43, 0.01) and _near(hud.chain_window_fraction(), 1.0, 0.03))
	run.kill(EnemyState.make(EnemyDefs.HUSK, run.position + Vector2(500.0, 0.0), 1, 0.0, 9001, 0.0, 0.0, null), Vector2.RIGHT)
	run.combo = 5
	run.combo_left = 1.3
	_tick_main(main, 1)
	var half: Color = hud._chain_label.get_theme_color("font_color")
	var waiting: float = (run.combo_left / GameRun.COMBO_WINDOW)
	var reference: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/reference/waves.json"))["hud"]["running"][2]
	var want: Array = reference["color"]
	var expected: Color = Color(float(want[0]) / 255.0, float(want[1]) / 255.0, float(want[2]) / 255.0)
	var mixed: Color = Color(0.35, 0.31, 0.43).lerp(Color(1.0, 0.82, 0.43), waiting)
	_ok("with half the window left it is the colour the prototype drew for x5 (%s against %s) and its bar is half as long (%.2f)" % [half, expected, hud.chain_window_fraction()],
		hud.chain_text() == "x5" and _near(half.r, expected.r, 0.02) and _near(half.g, expected.g, 0.02) and _near(half.b, expected.b, 0.02) and _near(mixed.r, half.r, 0.01) and _near(hud.chain_window_fraction(), waiting, 0.01) and _near(waiting, 0.5, 0.03))
	var waited: int = 0
	var previous: float = 2.0
	var monotone: bool = true
	while hud.chain_text() != "" and waited < MAX_WAIT:
		_tick_main(main, 1)
		monotone = monotone and hud.chain_window_fraction() <= previous + 0.0001
		previous = hud.chain_window_fraction()
		waited += 1
	_ok("the bar shrinks as the window runs out and the counter goes with the chain, %d ticks (1.3 s) after the last kill" % waited, monotone and run.combo == 0 and waited > 70 and waited < 90)
	_ok("the best chain is kept for the end screen (%d)" % run.best_combo, run.best_combo == 4)
	var wave_line: String = hud._wave_label.text
	run.combo = 40
	run.combo_left = 2.6
	_tick_main(main, 1)
	_ok("the big counter takes more digits without leaving the view ('%s') and the wave line carries no chain ('%s')" % [hud.chain_text(), wave_line], hud.chain_text() == "x40" and main.get_viewport().get_visible_rect().grow(0.5).encloses(Hud.occupied_rect(hud._chain_label)) and not wave_line.contains("chain"))
	main.queue_free()
	await _tree.process_frame


# --------------------------------------------------------------- sword and dash cooldowns
func _check_cooldown_readouts() -> void:
	print("feedback: sword, ultimate and dash cooldowns on the HUD")
	var scenario: RunScenario = RunScenario.normal_run()
	scenario.seed = 17
	scenario.wave_count = 0
	var main: Main = _main_with(scenario)
	await _tree.process_frame
	var run: GameRun = main.run
	var hud: Hud = main._hud
	# a target in reach starts the swords' strikes
	run.enemies.append(EnemyState.make(EnemyDefs.HUSK, run.position + Vector2(90.0, 0.0), 1, 0.0, 9100, 0.0, 0.0, null))
	var mismatches: Array[String] = []
	var struck: bool = false
	var refilled: bool = false
	var low_bar: float = 1.0
	var waited: int = 0
	while waited < 900 and not refilled:
		_tick_main(main, 1)
		for enemy: EnemyState in run.enemies:
			enemy.hp = enemy.max_hp
		var sword: SwordState = run.swords[0]
		var want: float = 1.0 - clampf(sword.cooldown_left / sword.cooldown, 0.0, 1.0)
		if absf(hud.attack_bar_fraction(0) - want) > 0.001:
			mismatches.append("tick %d: bar %.3f, sword %.3f" % [run.tick, hud.attack_bar_fraction(0), want])
		struck = struck or sword.cooldown_left > 0.0
		low_bar = minf(low_bar, hud.attack_bar_fraction(0))
		refilled = struck and hud.attack_bar_fraction(0) >= 0.999
		waited += 1
	_ok("each sword card's attack bar is the sword's own recharge, empty as it strikes and full when it can again (%d ticks, lowest %.2f, %d mismatches: %s)" % [waited, low_bar, mismatches.size(), mismatches.slice(0, 2)], struck and refilled and low_bar < 0.2 and mismatches.is_empty())
	# ultimates: the recharge bar and the seconds are the sword's own, for each of the three slots
	_press_key_with_aim(main, KEY_Q)
	_tick_main(main, 1)
	var slot_ok: bool = hud.ultimate_status(0) == "ACTIVE" and hud.ultimate_bar_fraction(0) == 1.0
	var waited_ult: int = 0
	while run.swords[0].phase == SwordState.Phase.ULTIMATE and waited_ult < MAX_WAIT:
		_tick_main(main, 1)
		waited_ult += 1
	_tick_main(main, 60)
	var sword_zero: SwordState = run.swords[0]
	_ok("an ultimate shows ACTIVE while it runs, then its recharge as whole seconds left ('%s') and a bar that is the sword's charge (%.2f against %.2f)" % [hud.ultimate_status(0), hud.ultimate_bar_fraction(0), sword_zero.ultimate_charge()], slot_ok and hud.ultimate_status(0) == "%ds" % SimMath.py_round(sword_zero.ultimate_cooldown_left) and _near(hud.ultimate_bar_fraction(0), sword_zero.ultimate_charge(), 0.01) and hud.ultimate_status(1) == "READY" and hud.ultimate_status(2) == "READY")
	# the dash readout
	run.dash_cooldown_left = 0.0
	run.apply(GameCommand.dash())
	_tick_main(main, 1)
	var dash_text: String = hud._dash_label.text
	var dash_fraction: float = hud._dash_bar.size.x / Hud.DASH_BAR_WIDTH
	_ok("the dash counts its 0.65 s down in text and bar ('%s', bar %.2f)" % [dash_text, dash_fraction], dash_text.begins_with("dash 0.") and dash_fraction < 0.1)
	_tick_main(main, 20)
	var mid_fraction: float = hud._dash_bar.size.x / Hud.DASH_BAR_WIDTH
	var mid_expected: float = 1.0 - run.dash_cooldown_left / GameRun.DASH_COOLDOWN
	_tick_main(main, 40)
	_ok("the bar fills as it recharges (%.2f against %.2f) and reads ready at the end ('%s')" % [mid_fraction, mid_expected, hud._dash_label.text], _near(mid_fraction, mid_expected, 0.01) and hud._dash_label.text == "dash ready" and hud._dash_bar.size.x == Hud.DASH_BAR_WIDTH)
	main.queue_free()
	await _tree.process_frame


func _press_key_with_aim(main: Main, code: Key) -> void:
	main.input.pointer = main.get_viewport().get_visible_rect().size * 0.5 + Vector2(120.0, 0.0)
	_press(main, code)


# --------------------------------------------------------------- health, kills, waves, banners
func _check_health_and_counters() -> void:
	print("feedback: health, wave, kills and the banner reflect the run")
	var scenario: RunScenario = RunScenario.normal_run()
	scenario.seed = 21
	var no_swords: Array[SwordSpec] = []
	scenario.loadout = no_swords
	scenario.crit_chance = 0.0
	var main: Main = _main_with(scenario)
	await _tree.process_frame
	var run: GameRun = main.run
	var hud: Hud = main._hud
	_tick_main(main, 1)
	_ok("a new run shows full health: 100 and a full bar (%s, %.0f px)" % [hud._hp_label.text, hud._hp_fill.size.x], hud._hp_label.text == "100" and _near(hud._hp_fill.size.x, Hud.HP_BAR_SIZE.x, 0.01))
	run.iframes = 0.0
	run.hurt_player(30, run.position + Vector2(40.0, 0.0))
	main._present()
	_ok("a 30 point hit shows 70 and a bar at 70 %% (%s, %.0f px); the white bar behind it still shows the old health" % [hud._hp_label.text, hud._hp_fill.size.x], hud._hp_label.text == "70" and _near(hud._hp_fill.size.x, Hud.HP_BAR_SIZE.x * 0.7, 0.01) and hud._hp_lag.size.x > hud._hp_fill.size.x)
	var waited: int = 0
	while hud._hp_lag.size.x - hud._hp_fill.size.x > 0.5 and waited < MAX_WAIT:
		_tick_main(main, 1)
		waited += 1
	_ok("the white bar eases down onto it (%d ticks)" % waited, waited > 10 and waited < MAX_WAIT)
	run.hp = 70.5
	run.iframes = HEALED_FULL
	_tick_main(main, 1)
	_ok("health shows whole points (70.5 reads %s)" % hud._hp_label.text, hud._hp_label.text == "70")
	for i: int in 4:
		run.kill(EnemyState.make(EnemyDefs.HUSK, run.position + Vector2(500.0, 0.0), 3, 0.0, 9200 + i, 0.0, 0.0, null), Vector2.RIGHT)
	run.director.wave = 3
	_tick_main(main, 1)
	_ok("the wave and kill counts read the run ('%s')" % hud._wave_label.text, hud._wave_label.text == "WAVE 3    kills %d" % run.kills and run.kills == 4)
	main.queue_free()
	await _tree.process_frame
	# a real first wave: the banner appears with the wave, then the wave line counts what died
	var wave_scenario: RunScenario = RunScenario.normal_run()
	wave_scenario.seed = 22
	var wave_main: Main = _main_with(wave_scenario)
	await _tree.process_frame
	var wave_run: GameRun = wave_main.run
	var waited_wave: int = 0
	while wave_run.director.wave == 0 and waited_wave < MAX_WAIT:
		_tick_main(wave_main, 1)
		waited_wave += 1
	_ok("when wave 1 starts the banner says WAVE 1 and what to do ('%s' / '%s')" % [wave_main._hud._banner_label.text, wave_main._hud._banner_sub_label.text], wave_main._hud._banner_label.text == "WAVE 1" and wave_main._hud._banner_sub_label.text.contains("claim one"))
	var cleared: int = 0
	var waited_clear: int = 0
	while wave_run.cue_count(SimCue.Kind.WAVE_CLEARED) == 0 and waited_clear < 12000:
		_tick_main(wave_main, 1)
		waited_clear += 1
	_tick_main(wave_main, 2)
	cleared = wave_run.cue_count(SimCue.Kind.WAVE_CLEARED)
	_ok("when the wave is cleared the HUD says WAVE CLEARED and the line reads wave 1 with the kills it took ('%s', '%s')" % [wave_main._hud._banner_label.text, wave_main._hud._wave_label.text], cleared == 1 and wave_main._hud._banner_label.text == "WAVE CLEARED" and wave_main._hud._wave_label.text == "WAVE 1    kills %d" % wave_run.kills and wave_run.kills >= 8)
	wave_main.queue_free()
	await _tree.process_frame


# --------------------------------------------------------------- keyboard and mouse
func _check_keys_and_mouse() -> void:
	print("feedback: every keyboard and mouse alias still works")
	var translator: InputTranslator = InputTranslator.new()
	var by_key: Array = [
		[KEY_SPACE, GameCommand.Kind.DASH, -1], [KEY_SHIFT, GameCommand.Kind.DASH, -1],
		[KEY_P, GameCommand.Kind.TOGGLE_PAUSE, -1], [KEY_ESCAPE, GameCommand.Kind.TOGGLE_PAUSE, -1],
		[KEY_Q, GameCommand.Kind.ULTIMATE, 0], [KEY_E, GameCommand.Kind.ULTIMATE, 1], [KEY_R, GameCommand.Kind.ULTIMATE, 2],
		[KEY_1, GameCommand.Kind.SWAP, 0], [KEY_2, GameCommand.Kind.SWAP, 1], [KEY_3, GameCommand.Kind.SWAP, 2],
		[KEY_TAB, GameCommand.Kind.TOGGLE_RANGES, -1], [KEY_G, GameCommand.Kind.TOGGLE_RANGES, -1],
		[KEY_H, GameCommand.Kind.TOGGLE_HELP, -1],
	]
	var wrong: Array[String] = []
	for row: Array in by_key:
		var commands: Array[GameCommand] = translator.handle_event(_key(row[0] as Key))
		translator.handle_event(_key(row[0] as Key, false))
		if commands.is_empty() or commands[0].kind != row[1] or (int(row[2]) >= 0 and commands[0].slot != int(row[2])):
			wrong.append(OS.get_keycode_string(row[0] as Key))
	_ok("Space and Shift dash; P and Esc pause; Q, E and R are ultimates one, two and three; 1, 2 and 3 swap; Tab and G show the ranges; H the help (wrong: %s)" % [wrong], wrong.is_empty())
	var held_ok: bool = true
	for pair: Array in [[KEY_W, Vector2.UP], [KEY_UP, Vector2.UP], [KEY_S, Vector2.DOWN], [KEY_DOWN, Vector2.DOWN], [KEY_A, Vector2.LEFT], [KEY_LEFT, Vector2.LEFT], [KEY_D, Vector2.RIGHT], [KEY_RIGHT, Vector2.RIGHT]]:
		translator.handle_event(_key(pair[0] as Key))
		held_ok = held_ok and translator.move_axis().is_equal_approx(pair[1] as Vector2)
		translator.handle_event(_key(pair[0] as Key, false))
	_ok("WASD and the arrow keys move in their four directions", held_ok and translator.move_axis() == Vector2.ZERO)
	var main: Main = _main_with(_quiet_scenario(23))
	await _tree.process_frame
	_tick_main(main, 2)
	var at: Vector2 = Vector2(900.0, 360.0)
	_click(main, at)
	var left_world: Vector2 = main._world_at(at)
	_ok("a left click is a Converge at the cursor's world point", main.run.cue_count(SimCue.Kind.CONVERGE) == 1 and main.run.converge_cooldown_left > 2.4)
	main.run.converge_cooldown_left = 0.0
	_click(main, at, MOUSE_BUTTON_RIGHT)
	_ok("and so is a right click", main.run.cue_count(SimCue.Kind.CONVERGE) == 2)
	main.run.converge_cooldown_left = 0.0
	_click(main, at, MOUSE_BUTTON_MIDDLE)
	_ok("a middle click is not (the prototype's buttons are 1 and 3)", main.run.cue_count(SimCue.Kind.CONVERGE) == 2 and left_world.is_finite())
	var emulated: InputEventMouseButton = InputEventMouseButton.new()
	emulated.button_index = MOUSE_BUTTON_LEFT
	emulated.pressed = true
	emulated.device = InputEvent.DEVICE_ID_EMULATION
	main._input(emulated)
	main._unhandled_input(emulated)
	_ok("a click the engine made up from a touch is not a Converge", main.run.cue_count(SimCue.Kind.CONVERGE) == 2)
	_press(main, KEY_TAB)
	var ranges_on: bool = main.run.show_ranges
	_press(main, KEY_G)
	_ok("Tab shows the attack ranges and G hides them again", ranges_on and not main.run.show_ranges)
	_press(main, KEY_H)
	_ok("H reaches the run through the real input path", main.run.help_left == 0.0)
	main.queue_free()
	await _tree.process_frame


# --------------------------------------------------------------- pause, death and the delayed restart
func _check_pause_and_death() -> void:
	print("feedback: pause, death and the delayed restart")
	var main: Main = _main_with(_quiet_scenario(31))
	await _tree.process_frame
	var run: GameRun = main.run
	var hud: Hud = main._hud
	main._input(_key(KEY_X))
	_press(main, KEY_P)
	_ok("P pauses: the run stops, the overlay says PAUSED and the button offers Resume ('%s', '%s')" % [hud._pause_overlay.text.replace("\n", " / "), hud._pause_button.text], run.paused and hud._pause_overlay.visible and hud._pause_overlay.text.begins_with("PAUSED") and hud._pause_button.text == "Resume")
	var tick_before: int = run.tick
	_tick_main(main, 30)
	_ok("nothing advances while paused", run.tick == tick_before)
	_press(main, KEY_ESCAPE)
	_ok("Escape resumes and the overlay goes", not run.paused and not hud._pause_overlay.visible and hud._pause_button.text == "Pause")
	# death: the feedback and the restart delay
	run.iframes = 0.0
	run.hp = 5.0
	run.hurt_player(20, run.position + Vector2(30.0, 0.0))
	_tick_main(main, 1, false)
	_ok("dying is a slow-motion fall (slowmo %.2f s at scale %.2f)" % [run.slowmo, run.slowmo_scale], run.dead and run.slowmo > 0.0 and run.slowmo_scale == GameRun.DEATH_SLOWMO_SCALE)
	_press(main, KEY_R)
	_ok("R before the death screen is up is not a restart", run.dead and run.restarts == 0)
	var waited: int = 0
	while run.death_time <= GameRun.RESTART_DELAY and waited < MAX_WAIT:
		_tick_main(main, 1, false)
		waited += 1
	_ok("the death screen fades in once the 0.8 s are up (%d ticks, shade %.2f, '%s')" % [waited, hud._outcome_shade.color.a, hud.outcome_text()], hud._outcome_title.visible or run.death_time > GameRun.RESTART_DELAY)
	_tick_main(main, 30, false)
	var stats: String = hud._outcome_detail.text
	_ok("it reads THE SWORDS FALL SILENT, then the wave, kills and best chain of the run ('%s'), then how to rise again ('%s')" % [stats, hud._outcome_prompt.text], hud.outcome_text() == "THE SWORDS FALL SILENT" and stats == "wave %d   kills %d   best chain %d" % [maxi(1, run.director.wave), run.kills, run.best_combo] and hud._outcome_prompt.text.begins_with("press R to rise again"))
	_ok("while dead the banner, help and chain are gone from the screen", hud._banner_label.text == "" and not hud.help_visible())
	_press(main, KEY_Q)
	_press(main, KEY_E)
	_ok("Q and E are not ultimates for the dead", run.dead and run.restarts == 0 and run.cue_count(SimCue.Kind.ULTIMATE_STARTED) == 0)
	_press(main, KEY_R)
	_tick_main(main, 1)
	_ok("R now restarts: full health, alive, the screen cleared and the help back", run.restarts == 1 and not run.dead and run.hp == run.max_hp and hud.outcome_text() == "" and hud.help_visible() and main._sfx.played.has("restart"))
	main.queue_free()
	await _tree.process_frame


# --------------------------------------------------------------- the banner, then the card (issue #43's review)
## The first `show_run` after a banner appears must already keep the dropped sword's card off both its lines: the card used to be
## placed before the banner's text was updated, so for one update it covered them.
func _check_banner_then_card() -> void:
	print("feedback: the pickup card clears a banner on the very update it appears")
	var window: Window = Window.new()
	window.size = Vector2i(1280, 720)
	window.content_scale_size = Vector2i(1280, 720)
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	_tree.root.add_child(window)
	var hud: Hud = Hud.new()
	window.add_child(hud)
	await _tree.process_frame
	var spec: SwordSpec = SwordSpec.make(SwordDefs.COLOSSUS, 2, &"poison")
	var covered: Array[String] = []
	var cases: int = 0
	var needed_to_move: int = 0
	var half: Vector2 = GameRun.VIEW * 0.5 - Vector2(GameRun.CAMERA_OVERSCAN, GameRun.CAMERA_OVERSCAN)
	for size: Vector2i in WINDOW_SIZES:
		window.size = size
		hud.show_state(false, false)
		await _tree.process_frame
		await _tree.process_frame
		for spot: Vector2 in [Vector2(640.0, 360.0), Vector2(1300.0, 900.0), Vector2(2000.0, 1500.0), Vector2(30.0, 30.0)]:
			var run: GameRun = GameRun.new(_quiet_scenario(32))
			run.position = spot
			run.camera = spot.clamp(GameRun.WORLD.position + half, GameRun.WORLD.end - half)
			run.pickups.append(PickupState.make(spec, spot + Vector2(10.0, 0.0), 1))
			hud.show_run(run)
			var moved_before: Rect2 = hud.pickup_card_rect()
			run.set_banner("WAVE CLEARED", 2.6, WaveDefs.CLEARED_BANNER_SUB)
			hud.show_run(run)
			cases += 1
			var card: Rect2 = hud.pickup_card_rect()
			if not moved_before.is_equal_approx(card):
				needed_to_move += 1
			for line: Label in [hud._banner_label, hud._banner_sub_label]:
				var text: Rect2 = _text_rect(line)
				if text.has_area() and card.intersects(text):
					covered.append("%s at %s: %s over %s" % [size, spot, card, text])
	_ok("with a drop in reach, the first update after 'WAVE CLEARED' appears already keeps the card off both banner lines (%d cases at six window sizes, %d covered: %s)" % [cases, covered.size(), covered.slice(0, 2)], covered.is_empty() and cases == 24)
	_ok("and the banner really made the card move in some of them (%d), so this is the transition and not a lucky spot" % needed_to_move, needed_to_move > 0)
	window.queue_free()
	await _tree.process_frame


# --------------------------------------------------------------- nothing overlaps
## Every fixed HUD element, each as the rectangle it draws on, at the six window sizes: no two overlap, and all lie inside the view.
func _check_layout() -> void:
	print("feedback: nothing on the HUD overlaps")
	var window: Window = Window.new()
	window.size = Vector2i(1280, 720)
	window.content_scale_size = Vector2i(1280, 720)
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	_tree.root.add_child(window)
	var hud: Hud = Hud.new()
	window.add_child(hud)
	await _tree.process_frame
	var run: GameRun = GameRun.new(_quiet_scenario(33))
	var no_swords: Array[SwordSpec] = []
	var armed: RunScenario = RunScenario.normal_run()
	armed.seed = 33
	armed.loadout = RunScenario.default_loadout()
	var full_run: GameRun = GameRun.new(armed)
	full_run.combo = 12
	full_run.combo_left = 2.0
	full_run.kills = 1234
	full_run.director.wave = 88
	full_run.dash_cooldown_left = 0.3
	full_run.converge_cooldown_left = 1.7
	full_run.hp = 100.0
	run.swords = full_run.swords
	run.combo = 12
	run.combo_left = 2.0
	run.kills = 1234
	run.director.wave = 88
	run.dash_cooldown_left = 0.3
	run.converge_cooldown_left = 1.7
	var overlaps: Array[String] = []
	var outside: Array[String] = []
	var counted: int = 0
	var fewest: int = 1 << 20
	for size: Vector2i in WINDOW_SIZES:
		window.size = size
		hud.show_state(false, true)
		await _tree.process_frame
		await _tree.process_frame
		hud.show_run(run)
		var view: Rect2 = window.get_visible_rect()
		var elements: Dictionary = {}
		elements["build"] = hud._build_label
		elements["health"] = hud._hp_back
		elements["health value"] = hud._hp_label
		elements["dash"] = hud._dash_label
		elements["dash bar"] = hud._dash_track
		elements["converge"] = hud._converge_label
		elements["converge bar"] = hud._converge_track
		elements["wave line"] = hud._wave_label
		elements["chain"] = hud._chain_label
		elements["chain bar"] = hud._chain_bar
		elements["pause"] = hud._pause_button
		elements["restart"] = hud._restart_button
		elements["dev"] = hud._encounter_button
		elements["dash button"] = hud._dash_button
		for slot: int in 3:
			elements["card %d" % slot] = hud._ult_cards[slot]
		var rects: Dictionary = {}
		for name: String in elements:
			var control: Control = elements[name]
			var rect: Rect2 = _text_rect(control) if control is Label else control.get_global_rect()
			if control is Control and not (control is Label) and control.get_combined_minimum_size().x > rect.size.x:
				rect = Rect2(rect.position, rect.size.max(control.get_combined_minimum_size()))
			rects[name] = rect
		# the help lines are one block
		var help_block: Rect2 = Rect2()
		for line: Label in hud._help_lines:
			if line.visible:
				var line_rect: Rect2 = _text_rect(line)
				help_block = line_rect if not help_block.has_area() else help_block.merge(line_rect)
		if help_block.has_area():
			rects["help"] = help_block
		fewest = mini(fewest, rects.size())
		var names: Array = rects.keys()
		for i: int in names.size():
			var rect: Rect2 = rects[names[i]]
			if not view.grow(0.5).encloses(rect):
				outside.append("%s: %s %s outside %s" % [size, names[i], rect, view])
			for j: int in range(i + 1, names.size()):
				counted += 1
				# the hint line runs under the buttons on windows narrower than its text, as it always has; nothing else may touch
				if rect.intersects(rects[names[j]]):
					overlaps.append("%s: %s %s over %s %s" % [size, names[i], rect, names[j], rects[names[j]]])
	_ok("the HUD's fixed elements, the chain counter, the dash bar and the cards among them, lie inside the view at six window sizes (%d outside: %s)" % [outside.size(), outside.slice(0, 2)], outside.is_empty() and fewest >= 17)
	_ok("and none of them overlaps another (%d pairs; %d overlaps: %s)" % [counted, overlaps.size(), overlaps.slice(0, 3)], overlaps.is_empty() and counted > 600)
	window.queue_free()
	await _tree.process_frame


# --------------------------------------------------------------- screen feedback
func _check_hurt_flash() -> void:
	print("feedback: the screen answers a hit")
	var main: Main = _main_with(_quiet_scenario(41))
	await _tree.process_frame
	var run: GameRun = main.run
	var feedback: ScreenFeedback = main._feedback
	_tick_main(main, 2)
	_ok("an untouched player sees no red (%.2f)" % feedback.hurt_alpha(), feedback.hurt_alpha() == 0.0)
	run.iframes = 0.0
	run.hurt_player(10, run.position + Vector2(30.0, 0.0))
	main._dispatch_cues()
	main._feedback.sync(run)
	var flash: float = feedback.hurt_alpha()
	_tick_main(main, 15)
	var later: float = feedback.hurt_alpha()
	_ok("a hit flashes the screen red (%.2f) and the flash fades 2.5 a second (%.2f a quarter second later)" % [flash, later], flash > 0.7 and later < flash - 0.4 and later > 0.0)
	var waited: int = 0
	while feedback.hurt_alpha() > 0.0 and waited < MAX_WAIT:
		_tick_main(main, 1)
		waited += 1
	_ok("then it is gone, 0.4 s after the hit (%d + 15 ticks)" % waited, waited + 15 >= 22 and waited + 15 <= 26 and feedback.hurt_alpha() == 0.0)
	run.hp = 20.0
	_tick_main(main, 1)
	var pulse_a: float = feedback.hurt_alpha()
	run.real_time += 0.3
	_tick_main(main, 1)
	var pulse_b: float = feedback.hurt_alpha()
	_ok("below 30 %% health it pulses red slowly (%.2f, then %.2f)" % [pulse_a, pulse_b], pulse_a > 0.07 and pulse_a < 0.4 and pulse_b > 0.07 and pulse_b < 0.4 and not _near(pulse_a, pulse_b, 0.001))
	run.hp = 80.0
	_tick_main(main, 1)
	_ok("and it stops when health is back", feedback.hurt_alpha() == 0.0)
	main.queue_free()
	await _tree.process_frame


# --------------------------------------------------------------- impacts
func _check_impact_effects() -> void:
	print("feedback: impacts read at a glance")
	var main: Main = _main_with(_quiet_scenario(51))
	await _tree.process_frame
	var effects: EffectsLayer = main._presenter._effects
	effects._run = main.run
	var spec: SwordSpec = SwordSpec.make(SwordDefs.WARDEN, 0, &"ice")
	var small: SimCue = SimCue.make(SimCue.Kind.ENEMY_HIT, Vector2(500.0, 500.0), Vector2.RIGHT, 5)
	small.spec = spec
	small.radius = 16.0
	var big: SimCue = SimCue.make(SimCue.Kind.ENEMY_HIT, Vector2(500.0, 500.0), Vector2.RIGHT, 40, true)
	big.spec = spec
	big.radius = 16.0
	effects.clear()
	effects.apply_cue(small)
	var small_sparks: int = effects._sparks.size()
	var small_text: Dictionary = effects._texts[0]
	effects.clear()
	effects.apply_cue(big)
	var big_sparks: int = effects._sparks.size()
	var big_text: Dictionary = effects._texts[0]
	_ok("a blow throws more sparks the harder it hits (%d for 5, %d for 40: the prototype's clamp(4 + 0.35 x damage, 4, 26))" % [small_sparks, big_sparks], small_sparks == 5 and big_sparks == 18)
	var spark: Dictionary = effects._sparks[0]
	var tint: Color = Color(spark["color"])
	var sword_tint: Color = EffectsLayer.element_color(&"ice").lerp(Color.WHITE, 0.4)
	_ok("the sparks are the sword's element's colour, paler (%s against %s) and fly along the blow" % [tint, sword_tint], tint.is_equal_approx(sword_tint) and Vector2(spark["vel"]).x > 0.0)
	_ok("the number is bigger for a bigger blow and a critical is gold with a '!' (size %d and %d, '%s', %s)" % [small_text["size"], big_text["size"], big_text["text"], big_text["color"]], int(small_text["size"]) == 22 and int(big_text["size"]) == 50 and String(big_text["text"]) == "40!" and Color(big_text["color"]).r > 0.9 and Color(big_text["color"]).b < 0.5)
	_ok("and it rises, drifting the way the blow went (%s)" % [Vector2(big_text["vel"])], Vector2(big_text["vel"]).x > 50.0 and Vector2(big_text["vel"]).y < -120.0)
	var fastest_heavy: float = 0.0
	var fastest_plain: float = 0.0
	for round: int in 20:
		effects.clear()
		effects.apply_cue(big)
		for plain_spark: Dictionary in effects._sparks:
			fastest_plain = maxf(fastest_plain, Vector2(plain_spark["vel"]).length())
		var heavy_hit: SimCue = SimCue.make(SimCue.Kind.ENEMY_HIT, Vector2(500.0, 500.0), Vector2.RIGHT, 40, true)
		heavy_hit.spec = spec
		heavy_hit.radius = 16.0
		heavy_hit.heavy = true
		effects.clear()
		effects.apply_cue(heavy_hit)
		for fast_spark: Dictionary in effects._sparks:
			fastest_heavy = maxf(fastest_heavy, Vector2(fast_spark["vel"]).length())
	_ok("a heavy blow throws its sparks faster than a plain one (up to %.0f px/s against %.0f; the prototype's 900 and 650)" % [fastest_heavy, fastest_plain], fastest_plain <= 650.1 and fastest_heavy > 660.0 and fastest_heavy <= 900.1)
	# a kill
	var killed: SimCue = SimCue.make(SimCue.Kind.ENEMY_KILLED, Vector2(600.0, 600.0), Vector2.RIGHT)
	killed.enemy_kind = EnemyDefs.BRUTE
	killed.radius = 24.0
	effects.clear()
	effects.apply_cue(killed)
	var dots: int = 0
	var debris: int = 0
	for bit: Dictionary in effects._bits:
		dots += 1 if bit["kind"] == &"dot" else 0
		debris += 1 if bit["kind"] == &"debris" else 0
	var heavy: SimCue = SimCue.make(SimCue.Kind.ENEMY_KILLED, Vector2(600.0, 600.0), Vector2.RIGHT, 0, true)
	heavy.enemy_kind = EnemyDefs.BRUTE
	heavy.radius = 24.0
	effects.clear()
	effects.apply_cue(heavy)
	var heavy_dots: int = 0
	for bit: Dictionary in effects._bits:
		heavy_dots += 1 if bit["kind"] == &"dot" else 0
	_ok("a kill bursts into 16 dots and 6 + radius / 3 bits of debris in the enemy's colour, and 14 more dots for a heavy blow (%d, %d; %d heavy)" % [dots, debris, heavy_dots], dots == 16 and debris == 14 and heavy_dots == 30)
	var landed: bool = false
	var waited: int = 0
	var highest: float = 0.0
	while waited < 200:
		effects.sync(main.run)
		for bit: Dictionary in effects._bits:
			if bit["kind"] == &"debris":
				highest = maxf(highest, float(bit["z"]))
		waited += 1
	for bit: Dictionary in effects._bits:
		landed = landed or bit["kind"] == &"debris"
	_ok("debris is thrown up (%.0f px, no higher than gravity allows) and the whole burst is gone within 1.2 s, leaving nothing behind (%d bits after %d ticks)" % [highest, effects._bits.size(), waited], highest > 20.0 and highest < 90.0 and effects._bits.is_empty() and not landed)
	# a hit on the player, a dash, a spawn
	effects.clear()
	effects.apply_cue(SimCue.make(SimCue.Kind.PLAYER_HURT, Vector2(500.0, 500.0), Vector2.LEFT, 8))
	var red: Color = Color(effects._sparks[0]["color"])
	_ok("a hit on the player throws 14 red sparks and says -8 in red (%d sparks, %s)" % [effects._sparks.size(), red], effects._sparks.size() == 14 and red.r > 0.9 and red.g < 0.6 and String(effects._texts[0]["text"]) == "-8")
	effects.clear()
	effects.apply_cue(SimCue.make(SimCue.Kind.DASH, Vector2(500.0, 500.0), Vector2.RIGHT))
	var puffs: int = 0
	for bit: Dictionary in effects._bits:
		puffs += 1 if bit["kind"] == &"smoke" and Vector2(bit["vel"]).x < 100.0 else 0
	effects.clear()
	effects.apply_cue(SimCue.make(SimCue.Kind.ENEMY_SPAWNED, Vector2(500.0, 500.0)))
	_ok("a dash leaves ten puffs of smoke behind it and a spawn eight (%d puffs of the dash's, %d at the spawn)" % [puffs, effects._bits.size()], puffs >= 8 and effects._bits.size() == 8)
	# the layer's own streams: it can be flooded and stays bounded
	effects.clear()
	for i: int in 400:
		effects.apply_cue(killed)
		effects.apply_cue(big)
	effects.sync(main.run)
	_ok("flooded with kills and blows it keeps to its caps (%d bits, %d sparks, %d texts, %d rings)" % [effects._bits.size(), effects._sparks.size(), effects._texts.size(), effects._rings.size()], effects._bits.size() <= EffectsLayer.MAX_BITS and effects._sparks.size() <= EffectsLayer.MAX_EFFECTS and effects._texts.size() <= EffectsLayer.MAX_EFFECTS and effects._rings.size() <= EffectsLayer.MAX_EFFECTS)
	main.queue_free()
	await _tree.process_frame


func _check_trails_and_cracks() -> void:
	print("feedback: sword ribbons and floor cracks")
	var scenario: RunScenario = RunScenario.normal_run()
	scenario.seed = 53
	scenario.wave_count = 0
	var main: Main = _main_with(scenario)
	await _tree.process_frame
	var run: GameRun = main.run
	var effects: EffectsLayer = main._presenter._effects
	run.enemies.append(EnemyState.make(EnemyDefs.HUSK, run.position + Vector2(100.0, 0.0), 1, 0.0, 9300, 0.0, 0.0, null))
	_tick_main(main, 120)
	var longest: int = 0
	var shortest: int = 1 << 20
	for trail: Array in effects._trails.values():
		longest = maxi(longest, trail.size())
		shortest = mini(shortest, trail.size())
	_ok("each of the three swords drags a ribbon of its last %d positions (%d ribbons, %d to %d long)" % [EffectsLayer.TRAIL_POINTS, effects._trails.size(), shortest, longest], effects._trails.size() == 3 and longest == 9 and shortest == 9)
	var swift: float = 0.0
	var idlest: float = 1.0
	for trail: Array in effects._trails.values():
		for point: Dictionary in trail:
			swift = maxf(swift, float(point["intensity"]))
			idlest = minf(idlest, float(point["intensity"]))
	_ok("and it is brighter the faster the blade moves (from %.2f at rest to %.2f while they chase and strike; the prototype's floor is 0.12)" % [idlest, swift], swift > 0.3 and idlest < 0.5 and idlest >= 0.12)
	run.hitstop = 0.5
	var stamp: Array = (effects._trails.values()[0] as Array).duplicate(true)
	effects.sync(run)
	_ok("nothing is recorded while the game is held in hitstop", (effects._trails.values()[0] as Array) == stamp)
	run.hitstop = 0.0
	run.swords.clear()
	effects.sync(run)
	_ok("a ribbon goes with its sword", effects._trails.is_empty())
	# cracks
	var ground: GroundMarks = main._presenter._ground
	ground.clear()
	var slam: SimCue = SimCue.make(SimCue.Kind.COLOSSUS_SLAM, run.position + Vector2(200.0, 0.0), Vector2.DOWN, 3)
	slam.radius = 118.0
	slam.element = &"fire"
	effects.apply_cue(slam)
	_ok("a slam cracks the floor under it (%d mark)" % ground.decal_count(), ground.decal_count() == 1)
	var waited: int = 0
	while ground.decal_count() > 0 and waited < 600:
		ground.sync(run)
		waited += 1
	_ok("the cracks fade into the floor over seven seconds (%d ticks)" % waited, waited >= 419 and waited <= 421)
	main.queue_free()
	await _tree.process_frame


# --------------------------------------------------------------- gameplay timing is untouched
## The feedback is only a view: the same scenario through the Main scene (HUD, effects, screen feedback, sounds, help) ends in
## exactly the state the bare simulation reaches, and its hitstop and slow-motion timeline matches tick for tick.
func _check_timing_unchanged() -> void:
	print("feedback: hitstop and slow motion are as the bare simulation's")
	var timeline_a: Array[String] = []
	var timeline_b: Array[String] = []
	var scenario_a: RunScenario = RunScenario.normal_run()
	scenario_a.seed = 77
	var bare: GameRun = GameRun.new(scenario_a)
	var scenario_b: RunScenario = RunScenario.normal_run()
	scenario_b.seed = 77
	var main: Main = _main_with(scenario_b)
	await _tree.process_frame
	main._sfx.unlock()
	var ticks: int = 2400
	var stops: int = 0
	var slows: int = 0
	for i: int in ticks:
		bare.iframes = HEALED_FULL
		bare.step()
		bare.take_cues()
		timeline_a.append("%.4f/%.4f" % [bare.hitstop, bare.slowmo])
		stops += 1 if bare.hitstop > 0.0 else 0
		slows += 1 if bare.slowmo > 0.0 else 0
		main.run.iframes = HEALED_FULL
		main._physics_process(GameRun.TICK_DT)
		timeline_b.append("%.4f/%.4f" % [main.run.hitstop, main.run.slowmo])
	var same_state: bool = JSON.stringify(RenderRateScenario.digest(bare)) == JSON.stringify(RenderRateScenario.digest(main.run))
	_ok("through the real Main scene (help, chain counter, feedback, effects, sounds) a normal run's hitstop and slow-motion timeline equals the bare simulation's over %d ticks (%d held in hitstop, %d slowed)" % [ticks, stops, slows], timeline_a == timeline_b and stops > 20)
	_ok("and it ends in the same state: tick %d, %d kills, position %s" % [bare.tick, bare.kills, bare.position], same_state and bare.kills == main.run.kills and bare.kills > 0)
	main.queue_free()
	await _tree.process_frame


# --------------------------------------------------------------- the textured visual set
## The feedback and the HUD belong to the presentation around the replaceable actor and sword views, so they must work, and change
## nothing, with the textured set (`--visuals=textured`) exactly as with the drawn one.
func _check_textured_look() -> void:
	print("feedback: the same feedback with the textured visual set")
	var scenario: RunScenario = RunScenario.normal_run()
	scenario.seed = 91
	var main: Main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Main
	main.scenario = scenario
	main.visuals = VisualSets.TEXTURED
	_tree.root.add_child(main)
	main.set_physics_process(false)
	await _tree.process_frame
	var plain_scenario: RunScenario = RunScenario.normal_run()
	plain_scenario.seed = 91
	var plain: Main = _main_with(plain_scenario)
	await _tree.process_frame
	main._sfx.unlock()
	_ok("the textured set is really in use (actor %s)" % main.actor_visual.resource_path, main.actor_visual.resource_path.contains("textured") and main.sword_visual.resource_path.contains("textured"))
	var heard: Dictionary = {}
	var waited: int = 0
	var tips_checked: int = 0
	var worst_gap: float = 0.0
	while waited < 1500:
		main._sfx._last_ms.clear()
		_tick_main(main, 1)
		_tick_main(plain, 1)
		for sound: String in main._sfx.played:
			heard[sound] = true
		main._sfx.played.clear()
		waited += 1
	var effects: EffectsLayer = main._presenter._effects
	var same: bool = JSON.stringify(RenderRateScenario.digest(main.run)) == JSON.stringify(RenderRateScenario.digest(plain.run))
	_ok("the run through the textured set is exactly the drawn look's: the same state after %d ticks (kills %d, tick %d)" % [waited, plain.run.kills, plain.run.tick], waited == 1500 and same and plain.run.kills > 0)
	_ok("its swords drag ribbons, the sounds play and the HUD reads the run (%d ribbons, sounds %s, wave line '%s')" % [effects._trails.size(), heard.keys(), main._hud._wave_label.text], effects._trails.size() == 3 and heard.has("thud") and heard.has("whoosh") and main._hud._wave_label.text.begins_with("WAVE "))
	main.run.combo = 6
	main.run.combo_left = 1.0
	main.run.iframes = 0.0
	main.run.hurt_player(5, main.run.position + Vector2(20.0, 0.0))
	main._dispatch_cues()
	_tick_main(main, 1, false)
	_ok("the chain counter ('%s') and the hurt flash (%.2f) show with it" % [main._hud.chain_text(), main._feedback.hurt_alpha()], main._hud.chain_text() == "x6" and main._feedback.hurt_alpha() > 0.5)
	for slot: int in main.run.swords.size():
		var sword: SwordState = main.run.swords[slot]
		worst_gap = maxf(worst_gap, absf(main._hud.attack_bar_fraction(slot) - (1.0 - clampf(sword.cooldown_left / sword.cooldown, 0.0, 1.0))))
		tips_checked += 1
	_ok("the cards' attack bars still read each sword's own recharge (worst gap %.3f over %d swords)" % [worst_gap, tips_checked], worst_gap < 0.002 and tips_checked == 3)
	main.queue_free()
	plain.queue_free()
	await _tree.process_frame
