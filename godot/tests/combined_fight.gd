class_name CombinedFight
extends RefCounted
## The one scripted fight behind the render-rate check (issue #41; render_rate_checks.gd): the same scenarios, the
## same commands at the same simulation ticks, observed through a digest that must come out identical however the
## frames around those ticks are cut. It replaces the nine per-slice fights (crowd, spitters, flurry, conditions,
## warden, pike, colossus, converge, drops): frame-rate independence lives in shared code (the fixed 60 Hz tick
## loop and the cue queue), so one fight that exercises every mechanic proves it as well as nine that each
## exercised one. The probe (`frame_rate_probe.gd`) plays it through the real Main scene under the engine's own
## fixed-step loop at different frame rates; the checks also play it with bare `GameRun.step()` calls.
## The digest is `GameRun.state_digest()`: the whole run state by reflection (dash and Converge cooldowns, the gameplay
## random generator, every sword and enemy member, fields, pickups, wave director), taken at every CHECKPOINT_EVERY ticks
## (as a hash) and at the end of each segment (in full), so nothing that could differ at a frame-rate-dependent moment
## hides between two equal endings.
##
## The fight has two SEGMENTS, because a wave can only be cleared once nothing stands any more:
##   - FIGHT (segment 0, FIGHT_TICKS): the mechanics. The player stands 400 px from the north and east walls with the
##     prototype's default loadout (Fang poison, Warden ice, Colossus fire). Around him, pinned in place (speed_scale 0):
##       - four ARMED foes within a few steps (a husk, runner, brute and spitter carrying a Pike, a Fang, a Warden and a
##         Colossus of different rarities) that die and drop their swords; swaps (two refused before anything lies)
##         put the Pike into slot 0 and a Fang into slot 2, and the slots' recharges carry over;
##       - a column north (husks, a runner, a brute) that a Skewer carries into the north wall, a sturdy pack east
##         (between him and the east wall: Converge target, then the dev shove bowls it into the wall) and a tight
##         pack west (husks, runners and brutes that burn, poison, freeze, shatter and spread fire);
##       - sturdy husks south that fields and slams keep dosing, and two spitters whose orbs the swords parry or clear.
##     And four STALKERS, one of each enemy type, that start far away and move under their own power: they chase the
##     player across the arena, are pushed apart by the packs they meet (separation), weave (the runner), keep their
##     distance and shoot (the spitter), and die to the swords when they arrive. The fight records how far each type
##     really walked (`REQUIRED_TRAVEL`), so a fight in which nothing moves fails instead of proving nothing.
##     The script (`script()`) fires Cataclysm, Converge, Viper Flurry (twice), Maelstrom, two Skewers (north into the
##     wall, east to the range limit: the second starts from the first's state), refused presses, the shove and a dash.
##   - WAVES (segment 1, WAVES_TICKS): the run restarts into the normal run (generated, armed waves) with a short first
##     break. Wave 1 telegraphs its spawn markers, its enemies arrive and chase, armed ones drop swords, the wave clears
##     (the clear slow motion and banner), the break runs, and wave 2 starts and telegraphs its first markers.
##
## Playing it is the slowest part of the checks, so the render-rate group starts with
## `if not RenderRateScenario.probes_enabled(): return` (see run_checks.gd's switches).

## Segment 0 (the mechanics) and segment 1 (the waves): their lengths in simulation ticks, and the whole fight's.
const FIGHT_TICKS: int = 1700
const WAVES_TICKS: int = 1000
const TOTAL_TICKS: int = FIGHT_TICKS + WAVES_TICKS
## The state is hashed every this many ticks of each segment (and the end of each segment is kept in full).
const CHECKPOINT_EVERY: int = 50
## The normal run of segment 1: its own seed, a short first break, fixed first cooldowns.
const WAVES_SEED: int = 43
const WAVES_FIRST_DELAY: float = 0.5

## The player: 400 px from the north wall and from the east wall (the arena is 2600 x 1800).
const PLAYER: Vector2 = Vector2(2200.0, 400.0)
const STURDY_HP: float = 2500.0
const POST_HP: float = 5000.0
## The second spitter is not a post: it can die, so the shots do not keep coming for the whole fight.
const SHOOTER_HP: float = 200.0
const COLUMN_HP: float = 400.0

## The armed foes (`ARMED_KINDS` carry `ARMED_SWORDS`: Vector3(index into LootDefs.DROP_TYPES, rarity, element index)).
const ARMED_POSTS: Array[Vector2] = [Vector2(-34.0, 0.0), Vector2(48.0, 20.0), Vector2(-20.0, 56.0), Vector2(20.0, -58.0)]
const ARMED_KINDS: Array[StringName] = [&"husk", &"runner", &"brute", &"spitter"]
const ARMED_SWORDS: Array[Vector3] = [Vector3(2.0, 2.0, 1.0), Vector3(0.0, 1.0, 2.0), Vector3(1.0, 1.0, 1.0), Vector3(3.0, 0.0, 0.0)]
const ARMED_HP: float = 45.0
## A column north (a Skewer north carries it into the wall), a pack east (between the player and the east wall).
const NORTH: Array[Vector2] = [Vector2(0.0, -130.0), Vector2(14.0, -190.0), Vector2(-12.0, -250.0), Vector2(6.0, -310.0), Vector2(-4.0, -355.0)]
const NORTH_KINDS: Array[StringName] = [&"husk", &"runner", &"husk", &"brute", &"husk"]
const EAST: Array[Vector2] = [Vector2(140.0, 6.0), Vector2(205.0, -10.0), Vector2(270.0, 12.0), Vector2(340.0, -4.0), Vector2(180.0, 60.0), Vector2(250.0, -70.0)]
const EAST_KINDS: Array[StringName] = [&"husk", &"brute", &"husk", &"runner", &"husk", &"husk"]
## A tight pack west with brutes and runners: burning spreads through it, brutes freeze for less.
const WEST_PACK: Array[Vector2] = [Vector2(-150.0, 0.0), Vector2(-186.0, 0.0), Vector2(-150.0, 36.0), Vector2(-186.0, 36.0), Vector2(-150.0, -36.0), Vector2(-186.0, -36.0), Vector2(-222.0, 0.0)]
const WEST_BRUTES: Array[Vector2] = [Vector2(-260.0, 30.0), Vector2(-240.0, -90.0)]
const WEST_RUNNERS: Array[Vector2] = [Vector2(-120.0, -110.0), Vector2(-80.0, -130.0), Vector2(-200.0, 100.0)]
## Sturdy husks south that the fields and slams keep dosing, and spitters that keep shooting.
const SOUTH: Array[Vector2] = [Vector2(20.0, 230.0), Vector2(-40.0, 250.0), Vector2(70.0, 270.0), Vector2(10.0, 300.0), Vector2(-60.0, 310.0)]
const SPITTERS: Array[Vector2] = [Vector2(300.0, 230.0), Vector2(-300.0, 220.0)]
const SPITTER_COOLDOWNS: Array[float] = [0.4, 1.0]

## One stalker of each type: far from the player (over 600 px), so it has to cross the arena, push through the packs
## and, for the spitter, settle at its firing distance. Offsets from the player.
const STALKERS: Array[Vector2] = [Vector2(-700.0, 700.0), Vector2(-1200.0, 300.0), Vector2(-550.0, 400.0), Vector2(-700.0, -250.0)]
const STALKER_KINDS: Array[StringName] = [&"husk", &"runner", &"brute", &"spitter"]
const STALKER_SPITTER_COOLDOWN: float = 1.0

const KIND_CONVERGE: int = 0
const KIND_ULTIMATE: int = 1
const KIND_SWAP: int = 2
const KIND_DASH: int = 3
const KIND_SHOVE: int = 4

static func scenario() -> RunScenario:
	var scenario: RunScenario = RunScenario.new()
	scenario.seed = 18
	scenario.waves_enabled = false
	scenario.dev_shove = true
	scenario.start_position = PLAYER
	scenario.sword_start_cooldowns = [0.3, 0.4, 0.5]
	var placements: Array[EnemyPlacement] = []
	for i: int in ARMED_POSTS.size():
		var carried: Vector3 = ARMED_SWORDS[i]
		var armed: EnemyPlacement = EnemyPlacement.make(ARMED_KINDS[i], PLAYER + ARMED_POSTS[i]).armed_with(SwordSpec.make(LootDefs.DROP_TYPES[int(carried.x)], int(carried.y), SwordDefs.ELEMENT_ORDER[int(carried.z)]))
		armed.speed_scale = 0.0
		armed.hp = 1.0 if i == 0 else ARMED_HP
		placements.append(armed)
	for i: int in NORTH.size():
		placements.append(_post(NORTH_KINDS[i], NORTH[i], COLUMN_HP))
	for i: int in EAST.size():
		placements.append(_post(EAST_KINDS[i], EAST[i], STURDY_HP))
	for offset: Vector2 in WEST_PACK:
		placements.append(_post(EnemyDefs.HUSK, offset))
	for offset: Vector2 in WEST_BRUTES:
		placements.append(_post(EnemyDefs.BRUTE, offset))
	for offset: Vector2 in WEST_RUNNERS:
		placements.append(_post(EnemyDefs.RUNNER, offset))
	for offset: Vector2 in SOUTH:
		placements.append(_post(EnemyDefs.HUSK, offset, STURDY_HP))
	for i: int in SPITTERS.size():
		var shooter: EnemyPlacement = _post(EnemyDefs.SPITTER, SPITTERS[i], POST_HP if i == 0 else SHOOTER_HP)
		shooter.shoot_cooldown = SPITTER_COOLDOWNS[i]
		placements.append(shooter)
	for i: int in STALKERS.size():
		var stalker: EnemyPlacement = EnemyPlacement.make(STALKER_KINDS[i], PLAYER + STALKERS[i])
		if STALKER_KINDS[i] == EnemyDefs.SPITTER:
			stalker.shoot_cooldown = STALKER_SPITTER_COOLDOWN
		placements.append(stalker)
	scenario.initial_enemies = placements
	return scenario


## Segment 1: the normal run (generated, armed waves) from the start, with a short first break.
static func waves_scenario() -> RunScenario:
	var scenario: RunScenario = RunScenario.normal_run()
	scenario.seed = WAVES_SEED
	scenario.sword_start_cooldowns = [0.3, 0.4, 0.5]
	scenario.first_wave_delay = WAVES_FIRST_DELAY
	return scenario


## The segments in order: [scenario factory, ticks].
static func segment_scenario(segment: int) -> RunScenario:
	return scenario() if segment == 0 else waves_scenario()


static func segment_ticks(segment: int) -> int:
	return FIGHT_TICKS if segment == 0 else WAVES_TICKS


const SEGMENTS: int = 2


## A standing foe; health 0 leaves the kind's own.
static func _post(kind: StringName, offset: Vector2, hp: float = 0.0) -> EnemyPlacement:
	var post: EnemyPlacement = EnemyPlacement.make(kind, PLAYER + offset)
	post.speed_scale = 0.0
	if hp > 0.0:
		post.hp = hp
	return post


## THE SCRIPT of segment 0: every command of the mechanics fight, in one place (segment 1 plays without commands).
## To make the fight cover something new (a mechanic of a later slice, say) add its foes to `scenario()` and its
## commands here, then add its cue to `REQUIRED_CUES` below so the fight fails if it ever stops exercising it. The digest
## is the whole run state by reflection, so nothing in it changes; `render_rate_checks.gd` compares it at every frame
## rate. Keep FIGHT_TICKS past the last step. Aims are offsets from the player; slots count from 0.
static func script() -> Array[Dictionary]:
	return [
		# Swaps before anything lies are refused; Cataclysm east (slot 2, Colossus), Converge on the east pack, Viper Flurry west (slot 0, Fang).
		_step(5, KIND_SWAP, 1), _step(12, KIND_SWAP, 0),
		_step(20, KIND_ULTIMATE, 2, Vector2(250.0, 0.0)), _step(30, KIND_CONVERGE, 0, Vector2(262.0, 5.0)),
		_step(50, KIND_ULTIMATE, 0, Vector2(-250.0, 0.0)), _step(60, KIND_ULTIMATE, 2, Vector2(250.0, 0.0)),
		# The Pike's drop is swapped into slot 0 (the Fang's slot).
		_step(150, KIND_SWAP, 0),
		# Maelstrom west (slot 1, Warden), then a refused repeat; a swap into the Colossus slot.
		_step(300, KIND_ULTIMATE, 1, Vector2(-200.0, 20.0)), _step(380, KIND_ULTIMATE, 1, Vector2(-200.0, 20.0)),
		_step(400, KIND_SWAP, 2),
		# Skewers (slot 0, Pike): two presses at the start are refused (the swapped-in sword is still recharging), then north into the wall, the same again refused, and east to the range limit once it has recharged (a second Skewer starts from the first's state).
		_step(220, KIND_ULTIMATE, 0, Vector2(0.0, -300.0)), _step(240, KIND_ULTIMATE, 0, Vector2(0.0, -300.0)),
		_step(700, KIND_CONVERGE, 0, Vector2(262.0, 5.0)),
		_step(620, KIND_ULTIMATE, 0, Vector2(0.0, -300.0)), _step(640, KIND_ULTIMATE, 0, Vector2(0.0, -300.0)), _step(900, KIND_ULTIMATE, 2, Vector2(-250.0, 0.0)), _step(1040, KIND_ULTIMATE, 1, Vector2(-200.0, 20.0)),
		_step(1000, KIND_CONVERGE, 0, Vector2(-150.0, 0.0)),
		# The dev shove bowls the east pack into the wall; a dash at the end.
		_step(1300, KIND_ULTIMATE, 0, Vector2(300.0, 0.0)), _step(1400, KIND_SHOVE), _step(1500, KIND_DASH),
	]


static func _step(tick: int, kind: int, slot: int = 0, aim: Vector2 = Vector2.ZERO) -> Dictionary:
	return {"tick": tick, "kind": kind, "slot": slot, "aim": aim}


## Commands to issue once `completed_ticks` ticks of `segment` have run.
static func commands_at(segment: int, completed_ticks: int) -> Array[GameCommand]:
	var commands: Array[GameCommand] = []
	if segment != 0:
		return commands
	for step: Dictionary in script():
		if int(step["tick"]) != completed_ticks:
			continue
		var aim: Vector2 = PLAYER + (step["aim"] as Vector2)
		match int(step["kind"]):
			KIND_CONVERGE:
				commands.append(GameCommand.converge(aim))
			KIND_ULTIMATE:
				commands.append(GameCommand.ultimate(int(step["slot"]), aim))
			KIND_SWAP:
				commands.append(GameCommand.swap(int(step["slot"])))
			KIND_DASH:
				commands.append(GameCommand.dash())
			KIND_SHOVE:
				commands.append(GameCommand.dev_shove())
	return commands


# ------------------------------------------------------------------ the driver
## What the fight has done so far, driven one simulation tick at a time by whoever plays it: `play()` (bare steps) and
## the probe (the real Main scene under the engine's loop) call `before_tick(run)` once per tick, before the tick runs.
## It issues the tick's commands, hashes the state at the checkpoints, and at the end of a segment keeps the state in
## full and restarts the run into the next segment (or finishes).
var segment: int = 0
var finished: bool = false
## "segment:tick" -> hash of the full state digest at that moment.
var checkpoints: Dictionary = {}
## The full state digest at the end of each segment, and the counters read from the run at that moment.
var finals: Array[Dictionary] = []
var counters: Array[Dictionary] = []
## Ultimates started so far, by sword type (for the coverage checks).
var ultimates: Dictionary = {}
var _last_tick: int = -1


func before_tick(run: GameRun) -> void:
	while not finished:
		if run.tick == _last_tick:
			return
		_last_tick = run.tick
		if run.tick % CHECKPOINT_EVERY == 0:
			checkpoints["%d:%d" % [segment, run.tick]] = JSON.stringify(run.state_digest()).sha256_text()
		if run.tick >= segment_ticks(segment):
			finals.append(run.state_digest())
			counters.append(counters_of(run))
			segment += 1
			if segment >= SEGMENTS:
				finished = true
				return
			run.restart_with(segment_scenario(segment))
			_last_tick = -1
			continue
		for command: GameCommand in commands_at(segment, run.tick):
			var started_before: int = run.cue_count(SimCue.Kind.ULTIMATE_STARTED)
			var sword_type: StringName = &""
			if command.kind == GameCommand.Kind.ULTIMATE and command.slot >= 0 and command.slot < run.swords.size():
				sword_type = run.swords[command.slot].spec.type_id
			run.apply(command)
			if run.cue_count(SimCue.Kind.ULTIMATE_STARTED) > started_before:
				ultimates[sword_type] = int(ultimates.get(sword_type, 0)) + 1
		return


## What a probe or a check reports of a finished fight: every checkpoint hash and the end-of-segment digests.
func result() -> Dictionary:
	return {"checkpoints": checkpoints, "finals": finals}


## Plays the whole fight with bare simulation steps. Returns `result()` plus, for the coverage checks, the counters of
## each segment (`counters`), how many ultimates each sword type started (`started`: type id -> count) and what the
## ticks showed (`observed`, see `_Observer`).
static func play() -> Dictionary:
	var fight: CombinedFight = CombinedFight.new()
	var run: GameRun = GameRun.new(segment_scenario(0))
	var observer: Observer = Observer.new()
	# A guard of ten steps per scripted tick (hitstop and slow motion add steps that do not advance the tick): a mutation that
	# stops the tick counter must end the script, not hang it.
	var steps: int = 0
	while not fight.finished and steps < TOTAL_TICKS * 10:
		var segment_before: int = fight.segment
		fight.before_tick(run)
		if fight.finished:
			break
		if fight.segment != segment_before:
			observer.next_segment()
		observer.before_step(run)
		run.step()
		observer.after_step(run)
		run.take_cues()
		steps += 1
	var played: Dictionary = fight.result()
	played["counters"] = fight.counters
	played["observed"] = observer.report()
	played["started"] = fight.ultimates
	return played


## What the ticks of the bare play showed (the probe does not need it: its end states must equal the bare ones).
class Observer extends RefCounted:
	## Distance walked by enemies that move under their own power, per kind, in each segment, and what the wave
	## director did in segment 1.
	var travel: Array[Dictionary] = [{}, {}]
	var max_markers: int = 0
	var armed_foes_seen: Dictionary = {}
	var max_slowmo: float = 0.0
	var break_ticks: int = 0
	var max_wave: int = 0
	var _segment: int = 0
	var _positions: Dictionary = {}

	func next_segment() -> void:
		_segment += 1
		_positions = {}

	func before_step(run: GameRun) -> void:
		_positions = {}
		for enemy: EnemyState in run.enemies:
			_positions[enemy.serial] = enemy.position

	func after_step(run: GameRun) -> void:
		for enemy: EnemyState in run.enemies:
			if enemy.speed > 0.0 and _positions.has(enemy.serial):
				var walked: float = ((_positions[enemy.serial] as Vector2) - enemy.position).length()
				var kinds: Dictionary = travel[_segment]
				kinds[enemy.kind] = float(kinds.get(enemy.kind, 0.0)) + walked
			if enemy.armed != null and _segment == 1:
				armed_foes_seen[enemy.serial] = true
		if _segment == 1:
			max_markers = maxi(max_markers, run.director.markers.size())
			max_slowmo = maxf(max_slowmo, run.slowmo)
			max_wave = maxi(max_wave, run.director.wave)
			if not run.director.in_wave and run.director.break_left > 0.0:
				break_ticks += 1

	func report() -> Dictionary:
		return {"travel": travel, "max_markers": max_markers, "armed_foes": armed_foes_seen.size(), "max_slowmo": max_slowmo, "break_ticks": break_ticks, "max_wave": max_wave}


## Every counter the coverage checks read, from the run at the end of a segment.
static func counters_of(run: GameRun) -> Dictionary:
	return {
		"kills": run.kills, "hit_cues": run.cue_count(SimCue.Kind.ENEMY_HIT), "ultimate_cues": run.cue_count(SimCue.Kind.ULTIMATE_STARTED),
		"refused_cues": run.cue_count(SimCue.Kind.ULTIMATE_REFUSED), "hurt_cues": run.cue_count(SimCue.Kind.PLAYER_HURT),
		"shove_cues": run.cue_count(SimCue.Kind.SHOVE), "bowl_cues": run.cue_count(SimCue.Kind.BOWLED), "slam_cues": run.cue_count(SimCue.Kind.WALL_SLAM),
		"shot_cues": run.cue_count(SimCue.Kind.PROJECTILE_FIRED), "parry_cues": run.cue_count(SimCue.Kind.PROJECTILE_PARRIED), "orbs_cleared": run.projectiles_cleared,
		"beat_cues": run.cue_count(SimCue.Kind.MAELSTROM_BEAT), "burst_cues": run.cue_count(SimCue.Kind.MAELSTROM_BURST),
		"skewer_launch_cues": run.cue_count(SimCue.Kind.SKEWER_LAUNCHED), "skewer_release_cues": run.cue_count(SimCue.Kind.SKEWER_RELEASED),
		"colossus_slam_cues": run.cue_count(SimCue.Kind.COLOSSUS_SLAM), "field_created_cues": run.cue_count(SimCue.Kind.FIELD_CREATED),
		"field_pulse_cues": run.cue_count(SimCue.Kind.FIELD_PULSED), "converge_cues": run.cue_count(SimCue.Kind.CONVERGE),
		"drop_cues": run.cue_count(SimCue.Kind.SWORD_DROPPED), "swap_cues": run.cue_count(SimCue.Kind.SWORD_SWAPPED), "swap_refused_cues": run.cue_count(SimCue.Kind.SWAP_REFUSED),
		"frozen_cues": run.cue_count(SimCue.Kind.ENEMY_FROZEN), "shatter_cues": run.cue_count(SimCue.Kind.ENEMY_SHATTERED), "spread_cues": run.cue_count(SimCue.Kind.FIRE_SPREAD),
		"condition_damage_cues": run.cue_count(SimCue.Kind.CONDITION_DAMAGE),
		"spawn_cues": run.cue_count(SimCue.Kind.ENEMY_SPAWNED), "wave_started_cues": run.cue_count(SimCue.Kind.WAVE_STARTED), "wave_cleared_cues": run.cue_count(SimCue.Kind.WAVE_CLEARED),
		"kill_cues": run.cue_count(SimCue.Kind.ENEMY_KILLED),
		"dead": run.dead, "pickups": run.pickups.size(), "wave": run.director.wave,
	}


# ------------------------------------------------------------------ coverage
## Every requirement below is a minimum count of something the fight must have made happen, so a fight that has
## quietly stopped exercising a mechanic (and would then prove nothing about it) fails here instead of passing.
## Segment 0 (the mechanics):
const REQUIRED_CUES: Dictionary = {
	"kills": 12, "hit_cues": 60, "ultimate_cues": 6, "refused_cues": 3, "hurt_cues": 1,
	"shove_cues": 1, "bowl_cues": 3, "slam_cues": 2,
	"shot_cues": 3, "parry_cues": 1, "orbs_cleared": 1,
	"beat_cues": 3, "burst_cues": 1, "skewer_launch_cues": 2, "skewer_release_cues": 2,
	"colossus_slam_cues": 2, "field_created_cues": 1, "field_pulse_cues": 3, "converge_cues": 3,
	"drop_cues": 4, "swap_cues": 2, "swap_refused_cues": 2,
	"frozen_cues": 1, "shatter_cues": 1, "spread_cues": 1, "condition_damage_cues": 10,
}
## Segment 1 (the waves): two waves started, one cleared, enemies spawned from markers, kills, and an armed enemy's drop.
const REQUIRED_WAVE_CUES: Dictionary = {
	"wave_started_cues": 2, "wave_cleared_cues": 1, "spawn_cues": 8, "kills": 8, "drop_cues": 1, "wave": 2,
}
## Pixels each enemy type must have walked under its own power in segment 0 (a stalker crossing the arena), and in
## segment 1 (every wave enemy, any type): a fight whose enemies cannot move fails here.
const REQUIRED_TRAVEL: Dictionary = {&"husk": 300.0, &"runner": 300.0, &"brute": 300.0, &"spitter": 300.0}
const REQUIRED_WAVE_TRAVEL: float = 1000.0
## What the wave director must have been seen doing in segment 1: telegraphed markers, armed foes on the field, the clear's slow motion,
## and the break after it, in ticks.
const REQUIRED_MARKERS: int = 1
const REQUIRED_ARMED_FOES: int = 1
const REQUIRED_SLOWMO: float = 0.3
const REQUIRED_BREAK_TICKS: int = 100
## One ultimate of each of these sword types must have started (Viper Flurry, Maelstrom, Skewer, Cataclysm).
const REQUIRED_ULTIMATE_TYPES: Array[StringName] = [SwordDefs.FANG, SwordDefs.WARDEN, SwordDefs.PIKE, SwordDefs.COLOSSUS]
const REQUIRED_KINDS: Array[StringName] = [EnemyDefs.HUSK, EnemyDefs.RUNNER, EnemyDefs.BRUTE, EnemyDefs.SPITTER]


## The requirements the played fight misses, as [label, detail] pairs; empty when it covers everything.
static func coverage_failures(played: Dictionary) -> Array[Array]:
	var counted: Array = played["counters"]
	var observed: Dictionary = played["observed"]
	var missed: Array[Array] = []
	if counted.size() != SEGMENTS:
		missed.append(["the combined fight plays every segment", "%d of %d finished" % [counted.size(), SEGMENTS]])
		return missed
	var fight: Dictionary = counted[0]
	var waves: Dictionary = counted[1]
	for key: String in REQUIRED_CUES:
		if int(fight[key]) < int(REQUIRED_CUES[key]):
			missed.append(["the combined fight reaches %d of %s" % [int(REQUIRED_CUES[key]), key], "only %d" % int(fight[key])])
	for key: String in REQUIRED_WAVE_CUES:
		if int(waves[key]) < int(REQUIRED_WAVE_CUES[key]):
			missed.append(["the combined fight's waves reach %d of %s" % [int(REQUIRED_WAVE_CUES[key]), key], "only %d" % int(waves[key])])
	var walked: Array = observed["travel"]
	for kind: StringName in REQUIRED_TRAVEL:
		var distance: float = float((walked[0] as Dictionary).get(kind, 0.0))
		if distance < float(REQUIRED_TRAVEL[kind]):
			missed.append(["the combined fight's %s walks %d px under its own power" % [kind, int(REQUIRED_TRAVEL[kind])], "only %d px" % int(distance)])
	var wave_distance: float = 0.0
	for kind: Variant in (walked[1] as Dictionary):
		wave_distance += float((walked[1] as Dictionary)[kind])
	if wave_distance < REQUIRED_WAVE_TRAVEL:
		missed.append(["the combined fight's wave enemies walk %d px in all" % int(REQUIRED_WAVE_TRAVEL), "only %d px" % int(wave_distance)])
	if int(observed["max_markers"]) < REQUIRED_MARKERS:
		missed.append(["the combined fight telegraphs spawn markers", "most at once: %d" % int(observed["max_markers"])])
	if int(observed["armed_foes"]) < REQUIRED_ARMED_FOES:
		missed.append(["the combined fight's waves field armed enemies", "armed enemies seen: %d" % int(observed["armed_foes"])])
	if float(observed["max_slowmo"]) < REQUIRED_SLOWMO:
		missed.append(["the combined fight's wave clear plays its slow motion", "longest: %.2f s" % float(observed["max_slowmo"])])
	if int(observed["break_ticks"]) < REQUIRED_BREAK_TICKS:
		missed.append(["the combined fight's wave break runs", "%d ticks" % int(observed["break_ticks"])])
	for sword_type: StringName in REQUIRED_ULTIMATE_TYPES:
		if int((played["started"] as Dictionary).get(sword_type, 0)) < 1:
			missed.append(["the combined fight starts an ultimate of the %s" % sword_type, "started: %s" % [played["started"]]])
	var kinds: Dictionary = {}
	for placement: EnemyPlacement in scenario().initial_enemies:
		kinds[placement.kind] = true
		if placement.armed != null:
			kinds["armed"] = true
	for kind: StringName in REQUIRED_KINDS:
		if not kinds.has(kind):
			missed.append(["the combined fight fields every enemy type", "no %s" % kind])
	for index: int in counted.size():
		if bool((counted[index] as Dictionary)["dead"]):
			missed.append(["the player survives segment %d of the combined fight" % index, "dead"])
	if int(fight["pickups"]) == 0:
		missed.append(["a dropped sword is still lying at the end of the mechanics fight", "none"])
	return missed


static func coverage_summary(played: Dictionary) -> String:
	var counted: Array = played["counters"]
	var parts: Array[String] = []
	for key: String in REQUIRED_CUES:
		parts.append("%s %d" % [key.trim_suffix("_cues"), int((counted[0] as Dictionary)[key])])
	parts.append("ultimates by type %s" % [played["started"]])
	var walked: Array = (played["observed"] as Dictionary)["travel"]
	var distances: Array[String] = []
	for kind: Variant in (walked[0] as Dictionary):
		distances.append("%s %d" % [kind, int((walked[0] as Dictionary)[kind])])
	parts.append("walked px " + ", ".join(distances))
	var wave: Dictionary = counted[1]
	parts.append("waves: started %d, cleared %d, spawned %d, kills %d, drops %d" % [int(wave["wave_started_cues"]), int(wave["wave_cleared_cues"]), int(wave["spawn_cues"]), int(wave["kills"]), int(wave["drop_cues"])])
	return ", ".join(parts)
