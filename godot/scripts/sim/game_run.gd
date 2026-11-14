class_name GameRun
extends RefCounted
## The simulation of one run. Owns every run-owned entity and counter (player,
## equipped spirit swords, enemies, motes, wave schedule, time scales) and knows
## nothing about nodes, rendering, audio or input devices.
##
## Ported from game/main.py (`Game.update`, `Player`, `hit_enemy`, `kill`,
## `hurt_player`, `separate`) and stepped at a fixed 60 Hz; the prototype uses a
## variable step capped at 1/30. The update order inside `step()` is the
## prototype's, explicitly. See docs/reference/fang-survival-loop.md for the
## captured reference values and tolerances.
##
## Three clocks, as in the prototype:
##   * real time (`real_time`, `tick`): advances every unpaused tick, including
##     hitstop and slow motion. Shake decay and the hitstop/slow-motion timers run on it.
##   * gameplay time (`gameplay_time`): scaled time. Frozen during hitstop,
##     slowed during slow motion. Everything gameplay-related advances by it.
##   * paused: nothing advances.

const TICK_RATE: int = 60
const TICK_DT: float = 1.0 / 60.0
const WORLD: Rect2 = Rect2(0.0, 0.0, 2600.0, 1800.0)
## Reference view used by the camera clamp (prototype W x H).
const VIEW: Vector2 = Vector2(1280.0, 720.0)

const PLAYER_RADIUS: float = 14.0
const PLAYER_SPEED: float = 285.0
const ACCELERATION: float = 14.0
const PLAYER_MAX_HP: float = 100.0

const DASH_SPEED: float = 1000.0
const DASH_TIME: float = 0.14
const DASH_COOLDOWN: float = 0.65
const DASH_IFRAMES: float = 0.24

const HURT_IFRAMES: float = 0.8
const HURT_KNOCKBACK: float = 420.0
const HURT_HITSTOP: float = 0.07
const HURT_SHAKE: float = 0.45
const CONTACT_KNOCKBACK: float = 200.0
const CONTACT_STUN: float = 0.2

const DEATH_SLOWMO: float = 1.4
const DEATH_SLOWMO_SCALE: float = 0.25
## Gameplay seconds after death before the R key restarts (prototype `death_t > 0.8`).
const RESTART_DELAY: float = 0.8

const CRIT_MULTIPLIER: float = 2.0
const CRIT_KNOCK_BONUS: float = 1.3
const CRIT_HITSTOP_FACTOR: float = 1.5
const CRIT_SHAKE_BONUS: float = 0.1
const COMBO_WINDOW: float = 2.6
const MAX_QUEUED_CUES: int = 256

const CAMERA_LOOKAHEAD: float = 0.12
const CAMERA_RATE: float = 7.0
const CAMERA_OVERSCAN: float = 140.0

enum Outcome { RUNNING, SURVIVED, LOST }

var scenario: RunScenario
## Gameplay randomness (crits, spawn points, knock directions). Cosmetic
## randomness never draws from it.
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

# --- clocks
## Fixed ticks that advanced real time (never advances while paused).
var tick: int = 0
## Real seconds the run has been unpaused (`tick * TICK_DT`).
var real_time: float = 0.0
## Scaled gameplay seconds: frozen during hitstop, slowed during slow motion.
var gameplay_time: float = 0.0
var paused: bool = false
## Real seconds of hitstop still to wait out; all gameplay is frozen meanwhile.
var hitstop: float = 0.0
## Real seconds of slow motion left, and the gameplay-time scale while it lasts.
var slowmo: float = 0.0
var slowmo_scale: float = 1.0
## Screen-shake intensity (decays in real time) and its directional kick.
var trauma: float = 0.0
var kick: Vector2 = Vector2.ZERO
## How many times this run was restarted; presenters use it to drop stale visuals.
var restarts: int = 0

# --- player
var position: Vector2 = Vector2.ZERO
var velocity: Vector2 = Vector2.ZERO
var facing: Vector2 = Vector2.RIGHT
var hp: float = PLAYER_MAX_HP
var max_hp: float = PLAYER_MAX_HP
var dead: bool = false
## Remaining invulnerability seconds (dash and damage both grant it).
var iframes: float = 0.0
var dash_left: float = 0.0
var dash_cooldown_left: float = 0.0
## Gameplay seconds since the player died.
var death_time: float = 0.0

# --- run-owned entities
var swords: Array[SwordState] = []
var enemies: Array[EnemyState] = []
var motes: Array[Mote] = []
var director: WaveDirector

# --- counters
var kills: int = 0
var combo: int = 0
var best_combo: int = 0
var combo_left: float = 0.0
var banner_title: String = ""
var banner_left: float = 0.0

## Camera centre (player plus velocity look-ahead, eased and clamped).
var camera: Vector2 = Vector2.ZERO

var _move_input: Vector2 = Vector2.ZERO
var _cues: Array[SimCue] = []
var _next_serial: int = 0


func _init(scenario_value: RunScenario = null) -> void:
	scenario = scenario_value if scenario_value != null else RunScenario.new()
	if scenario.seed < 0:
		rng.randomize()
	_reset_state()


# ----------------------------------------------------------------- commands
## Applies a command. Movement while paused is remembered but has no effect
## until the run resumes; every other action has its own eligibility rule.
func apply(command: GameCommand) -> void:
	match command.kind:
		GameCommand.Kind.MOVE:
			_move_input = command.axis.limit_length(1.0)
		GameCommand.Kind.PAUSE:
			paused = true
		GameCommand.Kind.RESUME:
			paused = false
		GameCommand.Kind.TOGGLE_PAUSE:
			paused = not paused
		GameCommand.Kind.DASH:
			_try_dash()
		GameCommand.Kind.RESTART:
			restarts += 1
			_reset_state()
		GameCommand.Kind.RESTART_FROM_KEY:
			if dead and death_time > RESTART_DELAY:
				restarts += 1
				_reset_state()


func _try_dash() -> void:
	if paused or dead or dash_cooldown_left > 0.0:
		return
	var heading: Vector2 = _move_input if _move_input.length_squared() > 0.0 else facing
	velocity = heading.normalized() * DASH_SPEED
	dash_left = DASH_TIME
	dash_cooldown_left = DASH_COOLDOWN
	iframes = maxf(iframes, DASH_IFRAMES)
	add_cue(SimCue.make(SimCue.Kind.DASH, position, heading.normalized()))


# --------------------------------------------------------------------- step
## Advances exactly one fixed tick. Does nothing while paused.
func step() -> void:
	if paused:
		return
	tick += 1
	real_time += TICK_DT
	trauma = maxf(0.0, trauma - TICK_DT * 1.6)
	kick *= exp(-TICK_DT * 12.0)
	if hitstop > 0.0:
		hitstop -= TICK_DT
		return
	var dt: float = TICK_DT
	if slowmo > 0.0:
		slowmo -= dt
		dt *= slowmo_scale
	gameplay_time += dt
	if dead:
		death_time += dt

	_update_player(dt)
	var sword_count: int = swords.size()
	for i: int in sword_count:
		swords[i].update(self, dt, i, sword_count)
	for enemy: EnemyState in enemies:
		enemy.update(self, dt)
	_separate()
	_resolve_contacts()
	var alive: Array[EnemyState] = []
	for enemy: EnemyState in enemies:
		if not enemy.dead:
			alive.append(enemy)
	enemies = alive
	_update_motes(dt)

	combo_left -= dt
	if combo_left <= 0.0:
		combo = 0
	if banner_left > 0.0:
		banner_left -= dt
		if banner_left <= 0.0:
			banner_title = ""
	director.update(self, dt)
	_update_camera(dt)


func _update_player(dt: float) -> void:
	var move: Vector2 = Vector2.ZERO if dead else _move_input
	if move.length_squared() > 0.0:
		facing = move.normalized()
	iframes = maxf(0.0, iframes - dt)
	dash_cooldown_left = maxf(0.0, dash_cooldown_left - dt)
	if dash_left > 0.0:
		dash_left -= dt
	else:
		velocity += (move * PLAYER_SPEED - velocity) * minf(1.0, dt * ACCELERATION)
	position += velocity * dt
	var inner: Rect2 = WORLD.grow(-PLAYER_RADIUS)
	position = position.clamp(inner.position, inner.end)


func _update_camera(dt: float) -> void:
	var goal: Vector2 = position + velocity * CAMERA_LOOKAHEAD
	camera += (goal - camera) * (1.0 - exp(-dt * CAMERA_RATE))
	var half: Vector2 = VIEW * 0.5 - Vector2(CAMERA_OVERSCAN, CAMERA_OVERSCAN)
	camera = camera.clamp(WORLD.position + half, WORLD.end - half)


## Enemies touching the player hurt it (unless invulnerable) and are knocked
## back regardless. Prototype order: after enemy movement and separation.
func _resolve_contacts() -> void:
	for enemy: EnemyState in enemies:
		if not enemy.dead and (enemy.position - position).length() < enemy.radius + PLAYER_RADIUS:
			hurt_player(enemy.damage, enemy.position)
			enemy.velocity = SimMath.norm(enemy.position - position, rng) * CONTACT_KNOCKBACK
			enemy.stun = CONTACT_STUN


func _update_motes(dt: float) -> void:
	for mote: Mote in motes:
		mote.age += dt
		var to_player: Vector2 = position - mote.position
		var dist: float = to_player.length()
		if mote.age > Mote.HOMING_DELAY:
			mote.velocity += SimMath.norm(to_player, rng) * 2400.0 * dt
			mote.velocity *= exp(-dt * 2.5)
		else:
			mote.velocity *= exp(-dt * 5.0)
		mote.position += mote.velocity * dt
		if dist < Mote.COLLECT_RADIUS and mote.age > Mote.HOMING_DELAY:
			mote.collected = true
			if not dead:
				hp = minf(max_hp, hp + Mote.HEAL)
				add_cue(SimCue.make(SimCue.Kind.MOTE_COLLECTED, mote.position))
	var remaining: Array[Mote] = []
	for mote: Mote in motes:
		if not mote.collected:
			remaining.append(mote)
	motes = remaining


## Pairwise enemy push-apart (heavier = r*r moves less) with the prototype's
## "bowling" transfer from launched enemies.
func _separate() -> void:
	var count: int = enemies.size()
	for i: int in count:
		var a: EnemyState = enemies[i]
		for j: int in range(i + 1, count):
			var b: EnemyState = enemies[j]
			var d: Vector2 = b.position - a.position
			var reach: float = a.radius + b.radius
			if absf(d.x) > reach or absf(d.y) > reach:
				continue
			var dist: float = d.length()
			if dist >= reach or dist == 0.0:
				continue
			var normal: Vector2 = d / dist
			var overlap: float = reach - dist
			var mass_a: float = a.radius * a.radius
			var mass_b: float = b.radius * b.radius
			a.position -= normal * overlap * mass_b / (mass_a + mass_b)
			b.position += normal * overlap * mass_a / (mass_a + mass_b)
			_bowl(a, b, normal, 1.0)
			_bowl(b, a, normal, -1.0)


func _bowl(launched: EnemyState, hit: EnemyState, normal: Vector2, sign_value: float) -> void:
	if launched.stun > 0.0 and launched.velocity.length() > 340.0 and launched.velocity.dot(normal * sign_value) > 0.0:
		hit.velocity += launched.velocity * 0.55 * launched.radius / hit.radius * 0.6
		hit.stun = maxf(hit.stun, 0.25)
		hit.flash = 0.08
		hit.hp -= 3.0
		launched.velocity *= 0.6
		add_shake(0.06)
		if hit.hp <= 0.0 and not hit.dead:
			kill(hit, SimMath.norm(launched.velocity, rng))


# ------------------------------------------------------------------- combat
## A sword hits an enemy (prototype `hit_enemy`): critical roll, rounding
## (Python round-half-even), knockback, stun, hitstop and shake. A dead enemy
## ignores further hits so its death and rewards resolve exactly once.
func hit_enemy(enemy: EnemyState, raw_damage: float, direction: Vector2, knock: float, sword: SwordState) -> void:
	if enemy.dead:
		return
	var crit: bool = rng.randf() < scenario.crit_chance
	var dmg: float = raw_damage
	if crit:
		dmg *= CRIT_MULTIPLIER
	var dealt: int = maxi(1, SimMath.py_round(dmg))
	enemy.hp -= float(dealt)
	enemy.flash = 0.11
	enemy.squash = 1.0
	var d: Vector2 = SimMath.norm(direction, rng)
	var force: float = knock * enemy.knock_mult * (CRIT_KNOCK_BONUS if crit else 1.0)
	enemy.velocity = enemy.velocity * 0.3 + d * force
	enemy.stun = maxf(enemy.stun, 0.08 + force / 1500.0)
	var stop: float = SwordDefs.FANG_HITSTOP * (CRIT_HITSTOP_FACTOR if crit else 1.0)
	hitstop = maxf(hitstop, stop)
	add_shake(SwordDefs.FANG_SHAKE + (CRIT_SHAKE_BONUS if crit else 0.0), d, true)
	add_cue(SimCue.make(SimCue.Kind.ENEMY_HIT, enemy.position, d, dealt, crit))
	if enemy.hp <= 0.0:
		kill(enemy, d)


## Resolves an enemy's death exactly once: counters, combo and healing motes.
func kill(enemy: EnemyState, direction: Vector2) -> void:
	if enemy.dead:
		return
	enemy.dead = true
	kills += 1
	combo += 1
	combo_left = COMBO_WINDOW
	best_combo = maxi(best_combo, combo)
	for i: int in 3:
		motes.append(Mote.scatter(enemy.position, rng))
	add_cue(SimCue.make(SimCue.Kind.ENEMY_KILLED, enemy.position, direction))


## An enemy launched into the arena wall (prototype `wall_slam`).
func wall_slam(enemy: EnemyState, speed: float) -> void:
	enemy.stun = minf(enemy.stun, 0.15)
	var dealt: int = SimMath.py_round(6.0 + (speed - 380.0) * 0.04)
	enemy.hp -= float(dealt)
	enemy.flash = 0.12
	add_shake(0.18)
	hitstop = maxf(hitstop, 0.04)
	add_cue(SimCue.make(SimCue.Kind.ENEMY_HIT, enemy.position, Vector2.ZERO, dealt, false))
	if enemy.hp <= 0.0 and not enemy.dead:
		kill(enemy, SimMath.norm(-enemy.velocity, rng))


## Damage to the player (prototype `hurt_player`): ignored while invulnerable
## or dead; grants invulnerability, knockback, hitstop and shake; dying starts
## the slow-motion death.
func hurt_player(amount: int, source: Vector2) -> void:
	if iframes > 0.0 or dead:
		return
	hp -= float(amount)
	iframes = HURT_IFRAMES
	var d: Vector2 = SimMath.norm(position - source, rng)
	velocity = d * HURT_KNOCKBACK
	add_shake(HURT_SHAKE, d, true)
	hitstop = maxf(hitstop, HURT_HITSTOP)
	add_cue(SimCue.make(SimCue.Kind.PLAYER_HURT, position, d, amount))
	if hp <= 0.0:
		hp = 0.0
		dead = true
		slowmo = DEATH_SLOWMO
		slowmo_scale = DEATH_SLOWMO_SCALE
		death_time = 0.0
		add_cue(SimCue.make(SimCue.Kind.PLAYER_DIED, position))


func add_shake(amount: float, direction: Vector2 = Vector2.ZERO, with_kick: bool = false) -> void:
	trauma = minf(1.0, trauma + amount)
	if with_kick:
		kick += SimMath.norm(direction, rng) * amount * 16.0


func set_banner(title: String, seconds: float) -> void:
	banner_title = title
	banner_left = seconds


func next_serial() -> int:
	_next_serial += 1
	return _next_serial


func add_cue(cue: SimCue) -> void:
	if _cues.size() < MAX_QUEUED_CUES:
		_cues.append(cue)


## Drains the cues produced since the last call (presentation/audio only).
func take_cues() -> Array[SimCue]:
	var taken: Array[SimCue] = _cues
	_cues = []
	return taken


func outcome() -> Outcome:
	if dead:
		return Outcome.LOST
	if director.survived:
		return Outcome.SURVIVED
	return Outcome.RUNNING


## Whether the R key would restart right now.
func can_restart_from_key() -> bool:
	return dead and death_time > RESTART_DELAY


## Observation adapter for checks: plain values only.
func snapshot() -> Dictionary:
	var sword_positions: Array[Vector2] = []
	var sword_phases: Array[int] = []
	for sword: SwordState in swords:
		sword_positions.append(sword.position)
		sword_phases.append(sword.phase)
	var enemy_positions: Array[Vector2] = []
	var enemy_hp: Array[float] = []
	for enemy: EnemyState in enemies:
		enemy_positions.append(enemy.position)
		enemy_hp.append(enemy.hp)
	return {
		"tick": tick,
		"real_time": real_time,
		"gameplay_time": gameplay_time,
		"paused": paused,
		"restarts": restarts,
		"position": position,
		"velocity": velocity,
		"facing": facing,
		"move_input": _move_input,
		"hp": hp,
		"dead": dead,
		"iframes": iframes,
		"dash_left": dash_left,
		"dash_cooldown_left": dash_cooldown_left,
		"hitstop": hitstop,
		"slowmo": slowmo,
		"camera": camera,
		"kills": kills,
		"combo": combo,
		"wave": director.wave,
		"outcome": outcome(),
		"enemy_positions": enemy_positions,
		"enemy_hp": enemy_hp,
		"mote_count": motes.size(),
		"sword_positions": sword_positions,
		"sword_phases": sword_phases,
	}


func _reset_state() -> void:
	if scenario.seed >= 0:
		rng.seed = scenario.seed
	tick = 0
	real_time = 0.0
	gameplay_time = 0.0
	paused = false
	hitstop = 0.0
	slowmo = 0.0
	slowmo_scale = 1.0
	trauma = 0.0
	kick = Vector2.ZERO
	position = scenario.start_position
	velocity = Vector2.ZERO
	facing = Vector2.RIGHT
	max_hp = PLAYER_MAX_HP
	hp = max_hp if scenario.start_health < 0.0 else minf(max_hp, scenario.start_health)
	dead = false
	iframes = 0.0
	dash_left = 0.0
	dash_cooldown_left = 0.0
	death_time = 0.0
	kills = 0
	combo = 0
	best_combo = 0
	combo_left = 0.0
	banner_title = ""
	banner_left = 0.0
	camera = position
	_move_input = Vector2.ZERO
	_cues = []
	_next_serial = 0
	swords = []
	for i: int in scenario.loadout.size():
		var start_cd: float = scenario.sword_start_cooldowns[i] if i < scenario.sword_start_cooldowns.size() else rng.randf_range(0.2, 0.6)
		swords.append(SwordState.equip(scenario.loadout[i], position, start_cd))
	enemies = []
	for at: Vector2 in scenario.initial_husks:
		enemies.append(EnemyState.husk(at, 1, scenario.enemy_speed_scale, next_serial()))
	motes = []
	for at: Vector2 in scenario.initial_motes:
		motes.append(Mote.scatter(at, rng))
	director = WaveDirector.new(scenario)
