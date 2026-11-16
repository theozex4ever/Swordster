class_name VisualReplacementChecks
extends RefCounted
## Behavioural checks for replacing the actor and sword visuals with texture-based art without touching gameplay
## (issue #21, ADR 0003). The `textured` visual set (godot/art/placeholder) is real texture art with its own sizes, pivots,
## orientation and clips; these checks drive the real `GameRun` fixtures of the earlier slices through the real Main scene
## with the default drawn visuals and with every kind of replacement, and require the same movement, hit geometry, damage,
## timing, cooldowns and targets, tick by tick. They also check that every cue the art must show (facing, pose, phase,
## element, rarity, lift, altitude, hover) reaches the picture, that the art's own numbers (scale, pivot, orientation) are
## applied only to the picture, and that no animation callback can reach the run.

const TICKS: int = 900
## The scripted fights replayed with each look: a spitter fight (orbs, parries, the player's dashes and damage), the default
## loadout commanded by Converge, all four sword types and rarities swapped in from drops, and three Colossi (altitude).
const FIGHTS: Array[String] = [RenderRateScenario.SPITTERS, RenderRateScenario.CONVERGE, RenderRateScenario.DROPS, RenderRateScenario.COLOSSUS]
## The fights replayed with every deliberately hostile replacement as well.
const HOSTILE_FIGHTS: Array[String] = [RenderRateScenario.CONVERGE, RenderRateScenario.DROPS]
const SWORD_TYPES: Array[StringName] = [SwordDefs.FANG, SwordDefs.WARDEN, SwordDefs.PIKE, SwordDefs.COLOSSUS]
const ELEMENTS: Array[StringName] = [&"fire", &"ice", &"poison"]
const ACTOR_SETTINGS: String = "res://art/placeholder/actor_settings.tres"
const SWORD_SETTINGS: String = "res://art/placeholder/sword_settings.tres"
## Where a replacement's own source of truth is allowed to be (nothing in the simulation may mention any of it).
const PRESENTATION_WORDS: Array[String] = ["Visual", "Sprite", "Presenter", "AnimationPlayer", "clip_finished", "Texture"]

var _check: Callable
var _tree: SceneTree


func _init(check_function: Callable, tree: SceneTree) -> void:
	_check = check_function
	_tree = tree


func run_all() -> void:
	if not CheckFocus.includes("visual_replacement"):
		return
	_check_selection()
	_check_art_contract()
	await _check_actor_cues()
	await _check_sword_cues()
	await _check_clip_callbacks()
	_check_simulation_stays_blind()
	await _check_equivalence()
	await _check_hostile_replacements()
	await _check_real_scene()


func _ok(label: String, condition: bool, detail: String = "") -> void:
	_check.call(label, condition, detail)


# ------------------------------------------------------------------ selection
func _check_selection() -> void:
	print("visual replacement: the look is chosen by a presentation setting, the shipped look stays the default")
	_ok("the shipped look is the default", VisualSets.DEFAULT == VisualSets.PLACEHOLDER and VisualSets.resolve("") == VisualSets.PLACEHOLDER)
	_ok("an unknown or misspelled set keeps the default", VisualSets.resolve("fancy") == VisualSets.PLACEHOLDER and VisualSets.resolve("textur") == VisualSets.PLACEHOLDER)
	_ok("the textured set is asked for by name, in any case", VisualSets.resolve("textured") == VisualSets.TEXTURED and VisualSets.resolve(" Textured ") == VisualSets.TEXTURED)
	_ok("two sets exist", VisualSets.ids().size() == 2 and VisualSets.ids().has(VisualSets.PLACEHOLDER) and VisualSets.ids().has(VisualSets.TEXTURED))
	_ok("a launch option and a page address both carry it", LaunchOptions.VISUALS_ARGUMENT_PREFIX == "--visuals=" and LaunchOptions.VISUALS_QUERY == "visuals")
	_ok("with nothing asked for, nothing is requested", LaunchOptions.requested_visuals().is_empty() and LaunchOptions.visuals_from(PackedStringArray()).is_empty())
	_ok("the launch option is read among the other arguments", LaunchOptions.visuals_from(PackedStringArray(["--encounter=drops", "--visuals=textured", "--visuals=other"])) == "textured" and LaunchOptions.visuals_from(PackedStringArray(["--encounter=drops", "--visual=textured"])).is_empty())
	var actor_scene: PackedScene = load(VisualSets.scene_path(VisualSets.TEXTURED, "actor")) as PackedScene
	var sword_scene: PackedScene = load(VisualSets.scene_path(VisualSets.TEXTURED, "sword")) as PackedScene
	var enemy_scene: PackedScene = load(VisualSets.scene_path(VisualSets.TEXTURED, "enemy")) as PackedScene
	_ok("every scene of every set loads", actor_scene != null and sword_scene != null and enemy_scene != null and load(VisualSets.scene_path(VisualSets.PLACEHOLDER, "actor")) is PackedScene and load(VisualSets.scene_path(VisualSets.PLACEHOLDER, "sword")) is PackedScene and load(VisualSets.scene_path(VisualSets.PLACEHOLDER, "enemy")) is PackedScene)
	var actor: Node = actor_scene.instantiate()
	var sword: Node = sword_scene.instantiate()
	var enemy: Node = enemy_scene.instantiate()
	_ok("the textured set's views honour the replaceable contracts", actor is TexturedActorVisual and actor is ActorVisual and sword is TexturedSwordVisual and sword is SwordVisual and enemy is EnemyVisual)
	_ok("the textured set shows a texture-based actor and sword and keeps the drawn enemies", not (actor is PlaceholderActorVisual) and not (sword is PlaceholderSwordVisual) and enemy is PlaceholderEnemyVisual)
	actor.free()
	sword.free()
	enemy.free()


# --------------------------------------------------------------- art contract
func _check_art_contract() -> void:
	print("visual replacement: the placeholder art is real texture art with its own sizes, pivots and orientation")
	var actor: ActorSpriteSettings = load(ACTOR_SETTINGS) as ActorSpriteSettings
	var swords: SwordSpriteSettings = load(SWORD_SETTINGS) as SwordSpriteSettings
	_ok("both settings resources load", actor != null and swords != null)
	if actor == null or swords == null:
		return
	var arts: Array[SpriteArt] = [swords.fang, swords.warden, swords.pike, swords.colossus]
	var sizes: Dictionary = {}
	var all_inside: bool = true
	var all_off_centre: bool = true
	var all_textured: bool = true
	for art: SpriteArt in arts:
		all_textured = all_textured and art != null and art.texture != null and art.frame_count == 4
		var frame: Vector2 = art.frame_size()
		sizes[frame] = true
		all_inside = all_inside and art.pivot.x >= 0.0 and art.pivot.y >= 0.0 and art.pivot.x <= frame.x and art.pivot.y <= frame.y
		all_off_centre = all_off_centre and not art.pivot.is_equal_approx(frame * 0.5)
	_ok("each sword type has its own texture sheet of four frames", all_textured)
	_ok("the four sword sheets differ in size (%s)" % [sizes.keys()], sizes.size() == 4)
	var frames_fit: bool = true
	for art: SpriteArt in arts + [actor.body, actor.shadow, swords.glow, swords.shadow]:
		frames_fit = frames_fit and art.frame_size().x * float(art.frame_count) == float(art.texture.get_width()) and art.frame_size().y == float(art.texture.get_height())
	_ok("a frame is the texture's width over its frame count, and its full height", frames_fit)
	_ok("every sword pivot lies inside its frame and is not the frame's centre", all_inside and all_off_centre)
	_ok("the sword art points up (orientation 90) and is drawn at its own scale", swords.fang.orientation_degrees == 90.0 and not swords.fang.visual_scale.is_equal_approx(Vector2.ONE) and not swords.warden.visual_scale.is_equal_approx(swords.fang.visual_scale))
	var body: SpriteArt = actor.body
	_ok("the actor is a sheet of five frames facing down, pivoted on its body rather than its centre", body.texture != null and body.frame_count == 5 and body.orientation_degrees == -90.0 and not body.pivot.is_equal_approx(body.frame_size() * 0.5))
	_ok("the actor's texture is not the drawn placeholder's footprint (a disc of radius %.0f)" % PlaceholderActorVisual.BODY_RADIUS, body.frame_size().x != PlaceholderActorVisual.BODY_RADIUS * 2.0 and body.frame_size().y != PlaceholderActorVisual.BODY_RADIUS * 2.0)
	var clips: Array[SpriteClip] = [actor.idle_clip, actor.moving_clip, actor.dead_clip, swords.idle_clip, swords.windup_clip, swords.strike_clip, swords.recover_clip, swords.ultimate_clip]
	var frames_valid: bool = true
	for clip: SpriteClip in clips:
		frames_valid = frames_valid and clip != null and not clip.frames.is_empty()
		for index: int in clip.frames:
			frames_valid = frames_valid and index >= 0 and index < (arts[0].frame_count if clip in [swords.idle_clip, swords.windup_clip, swords.strike_clip, swords.recover_clip, swords.ultimate_clip] else body.frame_count)
	_ok("every clip names frames that exist in its sheet", frames_valid)
	_ok("the phases that must read apart show different frames (idle, windup and strike share none)", not _shares(swords.idle_clip, swords.windup_clip) and not _shares(swords.windup_clip, swords.strike_clip) and not _shares(swords.idle_clip, swords.strike_clip))
	var tints: Array[Color] = [swords.fire_tint, swords.ice_tint, swords.poison_tint]
	var distinct: bool = true
	for i: int in tints.size():
		for j: int in range(i + 1, tints.size()):
			distinct = distinct and absf(tints[i].r - tints[j].r) + absf(tints[i].g - tints[j].g) + absf(tints[i].b - tints[j].b) > 0.6
	_ok("the three element tints are clearly apart", distinct)
	_ok("an attacking sword floats lower than an idle one, so the dip can be seen", swords.lift_attack < swords.lift_idle - 5.0)
	var clip: SpriteClip = SpriteClip.new()
	clip.frames = PackedInt32Array([5, 6, 7])
	clip.fps = 10.0
	clip.loop = false
	_ok("a clip steps through its frames at its own rate and holds the last one", clip.frame_at(0.0) == 5 and clip.frame_at(0.11) == 6 and clip.frame_at(0.25) == 7 and clip.frame_at(5.0) == 7 and not clip.is_finished_at(0.29) and clip.is_finished_at(0.3))
	clip.loop = true
	_ok("a looping clip wraps and never finishes", clip.frame_at(0.31) == 5 and clip.frame_at(0.45) == 6 and not clip.is_finished_at(100.0))


func _shares(a: SpriteClip, b: SpriteClip) -> bool:
	for frame: int in a.frames:
		if b.frames.has(frame):
			return true
	return false


# ------------------------------------------------------------------- actor cues
func _check_actor_cues() -> void:
	print("visual replacement: the actor shows facing, moving, invulnerable and dead")
	var settings: ActorSpriteSettings = load(ACTOR_SETTINGS) as ActorSpriteSettings
	var actor: TexturedActorVisual = (load("res://scenes/textured_actor.tscn") as PackedScene).instantiate() as TexturedActorVisual
	_tree.root.add_child(actor)
	var sprite: Sprite2D = actor.body_sprite()
	_ok("the body sprite takes its art's pivot, scale and sheet", sprite.texture == settings.body.texture and sprite.hframes == 5 and not sprite.centered and sprite.offset.is_equal_approx(-settings.body.pivot) and sprite.scale.is_equal_approx(settings.body.visual_scale))
	_ok("the shadow sits at its own offset", actor.shadow_sprite().position.is_equal_approx(settings.shadow_offset) and actor.shadow_sprite().offset.is_equal_approx(-settings.shadow.pivot))
	actor.apply_pose(Vector2(300.0, 200.0), Vector2.RIGHT, false)
	actor.apply_state(false, false)
	_ok("the actor stands at the logical position", actor.position == Vector2(300.0, 200.0))
	_ok("facing east turns art that points down by the art's own orientation (-90 deg)", is_equal_approx(sprite.rotation, 0.0 + deg_to_rad(-90.0)))
	actor.apply_pose(Vector2(300.0, 200.0), Vector2.DOWN, false)
	_ok("facing south leaves art that points down upright", is_equal_approx(sprite.rotation, PI / 2.0 + deg_to_rad(-90.0)))
	actor.apply_pose(Vector2(300.0, 200.0), Vector2(-1.0, 0.0), false)
	_ok("facing west is half a turn from east", is_equal_approx(absf(sprite.rotation), PI + deg_to_rad(-90.0)) or is_equal_approx(sprite.rotation, PI + deg_to_rad(-90.0)) or is_equal_approx(sprite.rotation, -PI + deg_to_rad(-90.0)))
	var standing_frames: Dictionary = {}
	for tick: int in 90:
		actor.apply_pose(Vector2(300.0, 200.0), Vector2.RIGHT, false)
		actor.apply_state(false, false)
		standing_frames[sprite.frame] = true
	_ok("standing plays the idle clip's frames %s" % [standing_frames.keys()], _within(standing_frames, settings.idle_clip) and standing_frames.size() == settings.idle_clip.frames.size())
	var moving_frames: Dictionary = {}
	for tick: int in 90:
		actor.apply_pose(Vector2(300.0, 200.0), Vector2.RIGHT, true)
		actor.apply_state(false, false)
		moving_frames[sprite.frame] = true
	_ok("moving plays the moving clip's frames %s, which are not the idle frames" % [moving_frames.keys()], _within(moving_frames, settings.moving_clip) and not _overlap(moving_frames, standing_frames))
	var blinks: Dictionary = {}
	for tick: int in 12:
		actor.apply_pose(Vector2(300.0, 200.0), Vector2.RIGHT, true)
		actor.apply_state(true, false)
		blinks[snappedf(sprite.modulate.a, 0.01)] = true
	_ok("invulnerable blinks between full and the faded opacity %s" % [blinks.keys()], blinks.has(1.0) and blinks.has(snappedf(settings.invulnerable_alpha, 0.01)) and blinks.size() == 2)
	actor.apply_state(false, false)
	_ok("vulnerable is fully opaque", sprite.modulate.a == 1.0)
	actor.apply_pose(Vector2(300.0, 200.0), Vector2.RIGHT, false)
	actor.apply_state(false, true)
	_ok("dead shows the fallen frame", sprite.frame == settings.dead_clip.frames[0])
	actor.apply_pose(Vector2(300.0, 200.0), Vector2.RIGHT, true)
	actor.apply_state(false, true)
	_ok("dead stays fallen whatever the movement", sprite.frame == settings.dead_clip.frames[0])
	actor.free()


func _within(seen: Dictionary, clip: SpriteClip) -> bool:
	for frame: Variant in seen:
		if not clip.frames.has(int(frame)):
			return false
	return true


func _overlap(a: Dictionary, b: Dictionary) -> bool:
	for frame: Variant in a:
		if b.has(frame):
			return true
	return false


# ------------------------------------------------------------------- sword cues
func _check_sword_cues() -> void:
	print("visual replacement: every sword type, element and rarity reaches the picture")
	var settings: SwordSpriteSettings = load(SWORD_SETTINGS) as SwordSpriteSettings
	var scene: PackedScene = load("res://scenes/textured_sword.tscn") as PackedScene
	var correct_art: bool = true
	var correct_tint: bool = true
	var correct_glow: bool = true
	var correct_size: bool = true
	var correct_pose: bool = true
	var tints_seen: Dictionary = {}
	var glows_seen: Dictionary = {}
	var failing: String = ""
	for type_id: StringName in SWORD_TYPES:
		for element: StringName in ELEMENTS:
			for rarity: int in 3:
				var spec: SwordSpec = SwordSpec.make(type_id, rarity, element)
				var sword: TexturedSwordVisual = scene.instantiate() as TexturedSwordVisual
				_tree.root.add_child(sword)
				sword.setup(spec)
				sword.apply_pose(Vector2(120.0, 80.0), 0.7, SwordState.Phase.IDLE)
				var blade: Sprite2D = sword.blade_sprite()
				var art: SpriteArt = sword.art_of(type_id)
				var tint: Color = sword.tint_of(element)
				var glow_tint: Color = SwordDefs.RARITY_COLORS[rarity] if rarity > 0 else tint
				var label: String = "%s/%s/%d" % [type_id, element, rarity]
				var art_ok: bool = blade.texture == art.texture and blade.hframes == art.frame_count and not blade.centered and blade.offset.is_equal_approx(-art.pivot)
				var tint_ok: bool = blade.modulate.is_equal_approx(tint)
				var glow_ok: bool = sword.glow_sprite().modulate.r == glow_tint.r and sword.glow_sprite().modulate.g == glow_tint.g and sword.glow_sprite().modulate.b == glow_tint.b
				var blade_length: float = art.frame_size().y * art.visual_scale.y * SwordDefs.RARITY_SIZE[rarity]
				var size_ok: bool = blade.scale.is_equal_approx(art.visual_scale * SwordDefs.RARITY_SIZE[rarity]) and is_equal_approx(sword.glow_sprite().scale.x * settings.glow.frame_size().x, blade_length * 1.5) and sword.glow_sprite().texture == settings.glow.texture
				var pose_ok: bool = sword.position == Vector2(120.0, 80.0) and is_equal_approx(blade.rotation, 0.7 + deg_to_rad(art.orientation_degrees))
				correct_art = correct_art and art_ok
				correct_tint = correct_tint and tint_ok
				correct_glow = correct_glow and glow_ok
				correct_size = correct_size and size_ok
				correct_pose = correct_pose and pose_ok
				if failing.is_empty() and not (art_ok and tint_ok and glow_ok and size_ok and pose_ok):
					failing = label
				tints_seen[snappedf(blade.modulate.r, 0.01) * 1000.0 + snappedf(blade.modulate.g, 0.01) * 10.0 + snappedf(blade.modulate.b, 0.01)] = true
				glows_seen[sword.glow_sprite().modulate.to_html(false)] = true
				sword.free()
	_ok("each type draws its own sheet with the art's pivot (36 swords; first wrong: '%s')" % failing, correct_art)
	_ok("the element tints the blade (fire, ice, poison)", correct_tint and tints_seen.size() == 3)
	_ok("the glow is the rarity's colour for a Rare or Mythic sword and the element's for a Common one (%d colours)" % glows_seen.size(), correct_glow and glows_seen.size() == 5)
	_ok("rarity scales the blade by its size factor, and the glow rings the blade at 1.5 blade lengths across", correct_size)
	_ok("the blade turns to the sword's heading plus the art's orientation", correct_pose)
	_ok("a Mythic blade is drawn larger than a Rare, a Rare larger than a Common", SwordDefs.RARITY_SIZE[2] > SwordDefs.RARITY_SIZE[1] and SwordDefs.RARITY_SIZE[1] > SwordDefs.RARITY_SIZE[0])
	await _check_sword_phases(settings, scene)


func _check_sword_phases(settings: SwordSpriteSettings, scene: PackedScene) -> void:
	var sword: TexturedSwordVisual = scene.instantiate() as TexturedSwordVisual
	_tree.root.add_child(sword)
	sword.setup(SwordSpec.make(SwordDefs.WARDEN, 0, &"ice"))
	var blade: Sprite2D = sword.blade_sprite()
	var expected: Dictionary = {
		SwordState.Phase.IDLE: settings.idle_clip,
		SwordState.Phase.WINDUP: settings.windup_clip,
		SwordState.Phase.STRIKE: settings.strike_clip,
		SwordState.Phase.RECOVER: settings.recover_clip,
		SwordState.Phase.ULTIMATE: settings.ultimate_clip,
		SwordState.Phase.STUCK: settings.strike_clip,
	}
	var wrong: String = ""
	for phase: int in expected:
		var clip: SpriteClip = expected[phase]
		var seen: Dictionary = {}
		for tick: int in 60:
			sword.apply_pose(Vector2.ZERO, 0.0, phase)
			seen[blade.frame] = true
		if not _within(seen, clip) and wrong.is_empty():
			wrong = "phase %d showed %s" % [phase, seen.keys()]
	_ok("each phase plays the clip the animation mapping gives it (%s)" % wrong, wrong.is_empty())
	sword.apply_pose(Vector2.ZERO, 0.0, SwordState.Phase.STRIKE)
	_ok("a striking blade brightens past its element's tint", blade.modulate.r > sword.tint_of(&"ice").r and blade.modulate.g >= sword.tint_of(&"ice").g)
	for tick: int in 80:
		sword.apply_pose(Vector2.ZERO, 0.0, SwordState.Phase.IDLE)
	_ok("an idle sword floats at its idle height above its shadow", is_equal_approx(blade.position.y, -settings.lift_idle) and sword.glow_sprite().position.is_equal_approx(blade.position))
	for tick: int in 80:
		sword.apply_pose(Vector2.ZERO, 0.0, SwordState.Phase.WINDUP)
	_ok("an attacking sword dips to its attack height", absf(blade.position.y + settings.lift_attack) < 0.01)
	_ok("the shadow stays on the ground", sword.shadow_sprite().position == Vector2(0.0, 6.0))
	sword.apply_flash(1.0)
	sword.apply_pose(Vector2.ZERO, 0.0, SwordState.Phase.IDLE)
	var flashing: float = sword.glow_sprite().modulate.a
	sword.apply_flash(0.0)
	sword.apply_pose(Vector2.ZERO, 0.0, SwordState.Phase.IDLE)
	_ok("a freshly swapped-in sword's glow flares and settles", flashing > sword.glow_sprite().modulate.a + 0.2)
	sword.free()
	var pickup: TexturedSwordVisual = scene.instantiate() as TexturedSwordVisual
	_tree.root.add_child(pickup)
	pickup.setup(SwordSpec.make(SwordDefs.PIKE, 2, &"fire"))
	pickup.apply_hover(41.0)
	pickup.apply_pose(Vector2(10.0, 20.0), PI / 2.0, SwordState.Phase.IDLE)
	_ok("a dropped sword hovers at the height it is given, point-down", is_equal_approx(pickup.blade_sprite().position.y, -41.0) and is_equal_approx(pickup.blade_sprite().rotation, PI / 2.0 + deg_to_rad(pickup.art_of(SwordDefs.PIKE).orientation_degrees)))
	pickup.free()
	var colossus: TexturedSwordVisual = scene.instantiate() as TexturedSwordVisual
	_tree.root.add_child(colossus)
	colossus.setup(SwordSpec.make(SwordDefs.COLOSSUS, 1, &"poison"))
	colossus.apply_altitude(0.0)
	colossus.apply_pose(Vector2.ZERO, -PI / 2.0, SwordState.Phase.IDLE)
	var grounded_shadow: float = colossus.shadow_sprite().scale.x
	colossus.apply_altitude(240.0)
	colossus.apply_pose(Vector2.ZERO, -PI / 2.0, SwordState.Phase.WINDUP)
	_ok("a Colossus is drawn as high as the run reports and its shadow shrinks as it climbs", is_equal_approx(colossus.blade_sprite().position.y, -240.0) and colossus.shadow_sprite().scale.x < grounded_shadow)
	colossus.free()
	await _tree.process_frame


# ---------------------------------------------------------------- clip callbacks
func _check_clip_callbacks() -> void:
	print("visual replacement: an animation that runs out is announced, and the announcement changes nothing")
	var scene: PackedScene = load("res://scenes/textured_sword.tscn") as PackedScene
	var sword: TexturedSwordVisual = scene.instantiate() as TexturedSwordVisual
	_tree.root.add_child(sword)
	sword.setup(SwordSpec.make(SwordDefs.FANG, 0, &"fire"))
	var heard: Array[SpriteClip] = []
	sword.clip_finished.connect(func(clip: SpriteClip) -> void: heard.append(clip))
	var settings: SwordSpriteSettings = sword.settings
	for tick: int in 90:
		sword.apply_pose(Vector2.ZERO, 0.0, SwordState.Phase.IDLE)
	_ok("a clip that loops never announces its end", heard.is_empty() and sword.clips_finished == 0)
	for tick: int in 60:
		sword.apply_pose(Vector2.ZERO, 0.0, SwordState.Phase.WINDUP)
	_ok("a windup that has played through announces it once and holds its last frame", heard.size() == 1 and heard[0] == settings.windup_clip and sword.clips_finished == 1 and sword.blade_sprite().frame == settings.windup_clip.frames[settings.windup_clip.frames.size() - 1])
	for tick: int in 10:
		sword.apply_pose(Vector2.ZERO, 0.0, SwordState.Phase.IDLE)
	for tick: int in 60:
		sword.apply_pose(Vector2.ZERO, 0.0, SwordState.Phase.WINDUP)
	_ok("a windup that starts again announces again", heard.size() == 2)
	sword.free()
	await _tree.process_frame


# ------------------------------------------------------- the simulation is blind
func _check_simulation_stays_blind() -> void:
	print("visual replacement: no simulation script knows about visuals, textures or animation")
	var offenders: Array[String] = []
	var scanned: int = 0
	var dir: DirAccess = DirAccess.open("res://scripts/sim")
	if dir == null:
		_ok("the simulation folder opens", false)
		return
	for file: String in dir.get_files():
		if not file.ends_with(".gd"):
			continue
		scanned += 1
		var source: String = FileAccess.get_file_as_string("res://scripts/sim/%s" % file)
		for line: String in source.split("\n"):
			var code: String = line.split("#")[0]
			for word: String in PRESENTATION_WORDS:
				if code.contains(word):
					offenders.append("%s: %s" % [file, word])
	_ok("%d simulation scripts never name a visual, sprite, texture, presenter or animation callback %s" % [scanned, offenders], scanned >= 20 and offenders.is_empty())


# ------------------------------------------------------------------ equivalence
func _check_equivalence() -> void:
	print("visual replacement: the same fights play out identically with the drawn and the textured look")
	for fight: String in FIGHTS:
		var bare: Dictionary = _play_bare(fight)
		var drawn: Dictionary = await _play_main(fight, "")
		var textured: Dictionary = await _play_main(fight, VisualSets.TEXTURED)
		var busy: bool = int(bare["hit_cues"]) >= 10 and int(bare["kills"]) >= 1 and int(bare["cues"]) >= 40
		_ok("%s: the fight is worth comparing (%d cues, %d hits, %d kills)" % [fight, bare["cues"], bare["hit_cues"], bare["kills"]], busy)
		_ok("%s: the drawn look plays the bare simulation's fight tick for tick" % fight, drawn["trace"] == bare["trace"], "%s vs %s" % [drawn["trace"], bare["trace"]])
		_ok("%s: the textured look plays it tick for tick too: movement, hit geometry, damage, timing, cooldowns and targets" % fight, textured["trace"] == bare["trace"], "%s vs %s" % [textured["trace"], bare["trace"]])
		_ok("%s: the textured look ends on the very same outcome digest" % fight, textured["digest"] == bare["digest"] and drawn["digest"] == bare["digest"])
		_ok("%s: the textured look really was on screen (%d sword visuals, frames %s, %d clips finished)" % [fight, textured["textured_swords"], textured["frames_seen"], textured["clips_finished"]], int(textured["textured_swords"]) >= 3 and (textured["frames_seen"] as Array).size() >= 3 and int(textured["clips_finished"]) > 0 and bool(textured["textured_actor"]))
		_ok("%s: the drawn look had none of it" % fight, int(drawn["textured_swords"]) == 0 and not bool(drawn["textured_actor"]))
		if fight == RenderRateScenario.DROPS:
			_ok("drops: the lying swords were drawn with the textured look too (up to %d at once)" % textured["pickups"], int(textured["pickups"]) >= 2)


func _check_hostile_replacements() -> void:
	print("visual replacement: art of any size, pivot, orientation, speed and length changes nothing")
	var variants: Dictionary = {
		"animations a tenth of the speed": _variant(func(art: Node) -> void: _retime(art, 0.1, false)),
		"animations sixty times faster, each playing once": _variant(func(art: Node) -> void: _retime(art, 60.0, true)),
		"huge, shifted, turned art on a different texture": _variant(func(art: Node) -> void: _reskin(art)),
	}
	for fight: String in HOSTILE_FIGHTS:
		var bare: Dictionary = _play_bare(fight)
		for name: String in variants:
			var result: Dictionary = await _play_main(fight, "", variants[name] as Callable)
			_ok("%s with %s: still the bare simulation's fight, tick for tick" % [fight, name], result["trace"] == bare["trace"] and result["digest"] == bare["digest"], "%s vs %s" % [result["trace"], bare["trace"]])
			_ok("%s with %s: the replacement really drew differently (%d clips finished, %s frames)" % [fight, name, result["clips_finished"], (result["frames_seen"] as Array).size()], int(result["textured_swords"]) >= 3 and bool(result["textured_actor"]))
			if name.begins_with("animations sixty"):
				_ok("%s: its animations ran out over and over (%d times) without moving a hair of the fight" % [fight, result["clips_finished"]], int(result["clips_finished"]) >= 50)
			if name.begins_with("huge"):
				_ok("%s: a bigger texture, scale, pivot and orientation reached the picture (blade scale %s, offset %s)" % [fight, result["blade_scale"], result["blade_offset"]], (result["blade_scale"] as Vector2).x > 3.0 and absf((result["blade_offset"] as Vector2).x) > 200.0)


## A scene of the textured set (actor and sword) whose art settings `change` has edited: the same scripts, other numbers.
func _variant(change: Callable) -> Callable:
	return func() -> Array[PackedScene]:
		var scenes: Array[PackedScene] = []
		for path: String in [VisualSets.scene_path(VisualSets.TEXTURED, "actor"), VisualSets.scene_path(VisualSets.TEXTURED, "sword")]:
			var root: Node = (load(path) as PackedScene).instantiate()
			change.call(root)
			var packed: PackedScene = PackedScene.new()
			packed.pack(root)
			root.free()
			scenes.append(packed)
		return scenes


## Every clip's speed times `speed`; with `once` no clip loops, so every one of them runs out over and over.
func _retime(root: Node, speed: float, once: bool) -> void:
	var settings: Resource = root.get("settings") as Resource
	var copy: Resource = settings.duplicate(true)
	for property: Dictionary in copy.get_property_list():
		var value: Variant = copy.get(property["name"])
		if value is SpriteClip:
			(value as SpriteClip).fps = clampf((value as SpriteClip).fps * speed, 0.1, 60.0)
			if once:
				(value as SpriteClip).loop = false
	root.set("settings", copy)


## Other textures altogether (size and sheet layout), pivots moved far away, much bigger, turned by 33 degrees.
func _reskin(root: Node) -> void:
	var settings: Resource = root.get("settings") as Resource
	var copy: Resource = settings.duplicate(true)
	var image: Image = Image.create_empty(1500, 900, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.9, 0.2, 0.7, 0.8))
	var texture: ImageTexture = ImageTexture.create_from_image(image)
	for property: Dictionary in copy.get_property_list():
		var value: Variant = copy.get(property["name"])
		if value is SpriteArt:
			var art: SpriteArt = value as SpriteArt
			art.texture = texture
			art.frame_count = 5
			art.pivot = art.pivot + Vector2(240.0, -95.0)
			art.visual_scale = art.visual_scale * 7.0
			art.orientation_degrees += 33.0
	root.set("settings", copy)


# ------------------------------------------------------------------ real scene
func _check_real_scene() -> void:
	print("visual replacement: the real arena shows the replacement and survives a restart")
	var drawn: Main = await _new_main(RenderRateScenario.scenario(RenderRateScenario.DROPS), "")
	_ok("by default the arena shows the drawn actor and swords", drawn.visual is PlaceholderActorVisual and drawn.sword_visual.resource_path.ends_with("placeholder_sword.tscn"))
	var main: Main = await _new_main(RenderRateScenario.scenario(RenderRateScenario.DROPS), VisualSets.TEXTURED)
	_ok("the visuals setting swaps the arena's actor, swords and enemies without any other change", main.visual is TexturedActorVisual and main.sword_visual.resource_path.ends_with("textured_sword.tscn") and main.enemy_visual.resource_path.ends_with("placeholder_enemy.tscn"))
	for tick: int in 120:
		main._physics_process(GameRun.TICK_DT)
	var swords: int = 0
	for child: Node in main._presenter.get_children():
		if child is TexturedSwordVisual:
			swords += 1
	_ok("the presenter drew all three equipped swords with the textured scene (%d)" % swords, swords >= 3)
	_ok("the actor follows the logical position", main.visual.position == main.run.position)
	main.run.apply(GameCommand.restart())
	main._presenter.reset()
	main._present()
	await _tree.process_frame
	var after: int = 0
	for child: Node in main._presenter.get_children():
		if child is TexturedSwordVisual:
			after += 1
	_ok("a restart frees the old swords' visuals and draws the new ones (%d)" % after, after == 3 and main._presenter.visual_count() == 3 + main.run.enemies.size())
	drawn.queue_free()
	main.queue_free()
	await _tree.process_frame


# -------------------------------------------------------------------- playing
func _new_main(scenario: RunScenario, visuals: String, scenes: Callable = Callable()) -> Main:
	var main: Main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Main
	main.scenario = scenario
	main.visuals = visuals
	if scenes.is_valid():
		main.visuals = ""
		var packed: Array[PackedScene] = scenes.call()
		main.actor_visual = packed[0]
		main.sword_visual = packed[1]
	_tree.root.add_child(main)
	main.set_physics_process(false)
	await _tree.process_frame
	return main


func _play_bare(fight: String) -> Dictionary:
	var run: GameRun = GameRun.new(RenderRateScenario.scenario(fight))
	var context: HashingContext = HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	var cues: int = 0
	for step: int in TICKS:
		for command: GameCommand in RenderRateScenario.commands_at(run.tick, fight):
			run.apply(command)
		run.apply(GameCommand.move_axis(Vector2.ZERO))
		run.step()
		cues += _record(context, run)
		run.take_cues()
	return _summary(run, context, cues)


## Plays a fight through the real Main scene exactly like `_physics_process` does (commands, step, present), recording the
## run before the presentation drains its cues. `scenes` (see `_variant`) replaces the textured actor and sword scenes.
func _play_main(fight: String, visuals: String, scenes: Callable = Callable()) -> Dictionary:
	var shown: String = VisualSets.TEXTURED if scenes.is_valid() else visuals
	var main: Main = await _new_main(RenderRateScenario.scenario(fight), shown, scenes)
	var context: HashingContext = HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	var cues: int = 0
	var frames_seen: Dictionary = {}
	var pickups: int = 0
	var textured_swords: int = 0
	var blade_scale: Vector2 = Vector2.ZERO
	var blade_offset: Vector2 = Vector2.ZERO
	for step: int in TICKS:
		for command: GameCommand in RenderRateScenario.commands_at(main.run.tick, fight):
			main.run.apply(command)
		main.run.apply(GameCommand.move_axis(main.input.move_axis()))
		main.run.step()
		cues += _record(context, main.run)
		main._present()
		if shown == VisualSets.TEXTURED:
			textured_swords = 0
			for child: Node in main._presenter.get_children():
				if child is TexturedSwordVisual:
					textured_swords += 1
					frames_seen[(child as TexturedSwordVisual).blade_sprite().frame] = true
					blade_scale = (child as TexturedSwordVisual).blade_sprite().scale
					blade_offset = (child as TexturedSwordVisual).blade_sprite().offset
			pickups = maxi(pickups, main._presenter.pickup_visual_count())
	var result: Dictionary = _summary(main.run, context, cues)
	var finished: int = 0
	for child: Node in main._presenter.get_children():
		if child is TexturedSwordVisual:
			finished += (child as TexturedSwordVisual).clips_finished
	if main.visual is TexturedActorVisual:
		finished += (main.visual as TexturedActorVisual).clips_finished
	result["frames_seen"] = frames_seen.keys()
	result["pickups"] = pickups
	result["textured_swords"] = textured_swords
	result["textured_actor"] = main.visual is TexturedActorVisual
	result["clips_finished"] = finished
	result["blade_scale"] = blade_scale
	result["blade_offset"] = blade_offset
	main.queue_free()
	await _tree.process_frame
	return result


## Folds one tick of everything gameplay owns into the running hash: the observation snapshot, each sword's phase, timers,
## cooldowns, heading and target, and every cue the tick produced (where, which way, how much, how far it reached). Returns
## how many cues there were.
func _record(context: HashingContext, run: GameRun) -> int:
	context.update(var_to_bytes(run.snapshot()))
	for sword: SwordState in run.swords:
		context.update(var_to_bytes([sword.phase, sword.timer, sword.cooldown_left, sword.angle, sword.position, sword.boost, sword.target.serial if sword.target != null else -1, sword.spec.display_name()]))
	for enemy: EnemyState in run.enemies:
		context.update(var_to_bytes([enemy.serial, enemy.position, enemy.hp, enemy.stun, enemy.flash]))
	for cue: SimCue in run._cues:
		context.update(var_to_bytes([cue.kind, cue.position, cue.direction, cue.amount, cue.critical, cue.origin, String(cue.element), cue.radius, cue.spec.display_name() if cue.spec != null else ""]))
	return run._cues.size()


func _summary(run: GameRun, context: HashingContext, cues: int) -> Dictionary:
	return {
		"trace": context.finish().hex_encode(),
		"digest": RenderRateScenario.digest(run),
		"cues": cues,
		"hit_cues": run.cue_count(SimCue.Kind.ENEMY_HIT),
		"kills": run.kills,
	}
