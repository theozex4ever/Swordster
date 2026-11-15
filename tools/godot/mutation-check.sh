#!/usr/bin/env bash
# Proves the headless checks can fail: applies one deliberate behavioural bug at a
# time to a scratch copy of the Godot project and requires run_checks.gd to
# reject each one (and to accept the unmodified project first).
#
# A mutation only counts as caught when run_checks.gd itself rejects it: the process
# must exit with the checks' ordinary failure status (1, from quit(1) after the
# verdict) AND print "CHECKS FAILED" with at least one "  FAIL" line and no script
# errors. Printing a failure verdict and then dying (signal, timeout, any other
# status) proves nothing, so any other execution (engine crash, timeout,
# parse/script error, no verdict at all) is INCONCLUSIVE: it is retried once, then reported and, if it
# persists, makes the script fail instead of silently counting as detection.
# Needs the pinned Godot in the cache: run ./build-godot.sh --bootstrap-only first.
set -Eeuo pipefail
REPO="$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd)"
# shellcheck source=tools/godot/godot.lock
source "$REPO/tools/godot/godot.lock"
CACHE_ROOT="${SWORDSTER_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/swordster}"
GODOT_BIN="$CACHE_ROOT/godot-$GODOT_VERSION/editor/godot"
[[ -x "$GODOT_BIN" ]] || { echo "pinned Godot missing; run ./build-godot.sh --bootstrap-only" >&2; exit 1; }

# SHARDS must be a positive integer and SHARD an integer in [0, SHARDS): anything else would
# silently select no mutations and report success, so it is refused before any work starts.
SHARD="${SHARD:-0}" SHARDS="${SHARDS:-1}"
if [[ ! "$SHARDS" =~ ^[1-9][0-9]*$ || ! "$SHARD" =~ ^[0-9]+$ ]] || ((10#$SHARD >= 10#$SHARDS)); then
  echo "invalid shard selection: SHARDS must be a positive integer and SHARD an integer with 0 <= SHARD < SHARDS (got SHARD=$SHARD SHARDS=$SHARDS)" >&2
  exit 2
fi
SHARD=$((10#$SHARD)) SHARDS=$((10#$SHARDS))

SCRATCH="$(mktemp -d)"; trap 'rm -rf "$SCRATCH"' EXIT
export XDG_DATA_HOME="$SCRATCH/home/data" XDG_CONFIG_HOME="$SCRATCH/home/config" XDG_CACHE_HOME="$SCRATCH/home/cache"
cp -a "$REPO/godot" "$SCRATCH/base"; rm -rf "$SCRATCH/base/.godot"
"$GODOT_BIN" --headless --path "$SCRATCH/base" --import >/dev/null 2>&1

run_checks() { timeout 120 "$GODOT_BIN" --headless --path "$1" --script res://tests/run_checks.gd 2>&1; }

if ! out="$(run_checks "$SCRATCH/base")" || ! grep -q '^CHECKS PASSED' <<<"$out"; then
  echo "baseline: unmodified project does NOT pass its checks"; echo "$out" | tail -20; exit 1
fi
echo "baseline: $(grep '^CHECKS PASSED' <<<"$out")"

# ONLY=a,b reruns just the named mutations. SHARD=i SHARDS=n runs every n-th mutation starting at i (0-based), so n copies of
# this script can run in parallel over the same list; each prints its own totals.
mutation_index=0
mutate() { # name file old new
  local name="$1" file="$2" old="$3" new="$4" dir="$SCRATCH/m-$1"
  if (( mutation_index++ % SHARDS != SHARD )); then return 0; fi
  # ONLY=name,name reruns just those mutations (after fixing a check, say).
  if [[ -n "${ONLY:-}" && ",$ONLY," != *",$1,"* ]]; then return 0; fi
  ran=$((ran + 1))
  cp -a "$SCRATCH/base" "$dir"
  python3 -I - "$dir/$file" "$old" "$new" <<'PY' || { echo "MUTATION NOT APPLIED: $name"; exit 1; }
import sys
path, old, new = sys.argv[1:4]
text = open(path).read()
if text.count(old) != 1:
    raise SystemExit(1)
open(path, "w").write(text.replace(old, new))
PY
  local verdict="" detail="" attempt status log
  for attempt in 1 2; do
    status=0; log="$(run_checks "$dir")" || status=$?
    if grep -q '^CHECKS PASSED' <<<"$log" && ((status == 0)); then
      verdict=SURVIVED; break
    elif ((status == 1)) && grep -q '^CHECKS FAILED' <<<"$log" && grep -q '^  FAIL ' <<<"$log" \
         && ! grep -Eq 'SCRIPT ERROR|Parse Error|Failed to load script' <<<"$log"; then
      verdict=CAUGHT; detail="$(grep -m1 '^  FAIL ' <<<"$log" | cut -c1-90)"; break
    fi
    verdict=INCONCLUSIVE; detail="exit $status, no behavioural verdict: $(tail -n 1 <<<"$log" | cut -c1-70)"
    ((attempt == 1)) && echo "retry     $name   (inconclusive run: $detail)"
  done
  case "$verdict" in
    CAUGHT)       echo "caught    $name   ($detail)" ;;
    SURVIVED)     echo "SURVIVED  $name   <-- checks failed to detect this bug"; survived=$((survived + 1)) ;;
    INCONCLUSIVE) echo "INCONCLUSIVE $name   <-- $detail"; inconclusive=$((inconclusive + 1)) ;;
  esac
}

survived=0; inconclusive=0; ran=0
mutate speed-zero           scripts/sim/game_run.gd  "PLAYER_SPEED: float = 285.0" "PLAYER_SPEED: float = 0.0"
mutate pause-ignored        scripts/sim/game_run.gd  "	if paused:
		return
	tick += 1" "	tick += 1"
mutate resume-never         scripts/sim/game_run.gd  "		GameCommand.Kind.RESUME:
			paused = false" "		GameCommand.Kind.RESUME:
			paused = paused"
mutate restart-keeps-pose   scripts/sim/game_run.gd  "	position = scenario.start_position" "	position = position"
mutate restart-keeps-input  scripts/sim/game_run.gd  "	_move_input = Vector2.ZERO
	_cues = []" "	_cues = []"
mutate no-diagonal-clamp    scripts/sim/game_run.gd  "command.axis.limit_length(1.0)" "command.axis"
mutate no-wall-clamp        scripts/sim/game_run.gd  "	position = position.clamp(inner.position, inner.end)" "	position = position + Vector2.ZERO"
# --- Fang survival loop (slice #8)
mutate dash-no-cooldown     scripts/sim/game_run.gd  "dash_cooldown_left = DASH_COOLDOWN" "dash_cooldown_left = 0.0"
mutate dash-while-dead      scripts/sim/game_run.gd  "if paused or dead or dash_cooldown_left > 0.0:" "if paused or dash_cooldown_left > 0.0:"
mutate dash-while-paused    scripts/sim/game_run.gd  "if paused or dead or dash_cooldown_left > 0.0:" "if dead or dash_cooldown_left > 0.0:"
mutate dash-no-iframes      scripts/sim/game_run.gd  "iframes = maxf(iframes, DASH_IFRAMES)" "iframes = iframes"
mutate hurt-no-iframes      scripts/sim/game_run.gd  "iframes = HURT_IFRAMES" "iframes = 0.0"
mutate contact-ignores-iframes scripts/sim/game_run.gd "if iframes > 0.0 or dead:" "if dead:"
mutate restart-no-delay     scripts/sim/game_run.gd  "			if dead and death_time > RESTART_DELAY:" "			if dead:"
mutate r-restarts-while-alive scripts/sim/game_run.gd "			if dead and death_time > RESTART_DELAY:" "			if true:"
mutate hitstop-ignored      scripts/sim/game_run.gd  "	if hitstop > 0.0:
		hitstop -= TICK_DT
		return" "	if false:
		return"
mutate slowmo-unscaled      scripts/sim/game_run.gd  "		dt *= slowmo_scale" "		dt *= 1.0"
mutate no-death-slowmo      scripts/sim/game_run.gd  "		slowmo = DEATH_SLOWMO
" "		slowmo = 0.0
"
mutate mote-overheal        scripts/sim/game_run.gd  "hp = minf(max_hp, hp + Mote.HEAL)" "hp = hp + Mote.HEAL"
mutate no-motes             scripts/sim/game_run.gd  "	for i: int in 3:
		motes.append" "	for i: int in 0:
		motes.append"
mutate dead-enemy-rehit     scripts/sim/game_run.gd  "	if enemy.dead:
		return
	var crit: bool" "	var crit: bool"
mutate double-kill          scripts/sim/game_run.gd  "func kill(enemy: EnemyState, direction: Vector2) -> void:
	if enemy.dead:
		return
	enemy.dead = true
	kills += 1" "func kill(enemy: EnemyState, direction: Vector2) -> void:
	enemy.dead = true
	kills += 2"
mutate crit-round-half-up   scripts/sim/sim_math.gd  "return int(lower) if int(lower) % 2 == 0 else int(lower) + 1" "return int(lower) + 1"
mutate fang-damage          scripts/sim/sword_defs.gd "FANG_DAMAGE: float = 7.0" "FANG_DAMAGE: float = 8.0"
mutate fang-range           scripts/sim/sword_defs.gd "FANG_RANGE: float = 175.0" "FANG_RANGE: float = 200.0"
mutate fang-windup          scripts/sim/sword_defs.gd "FANG_WINDUP: float = 0.06" "FANG_WINDUP: float = 0.2"
mutate fang-knockback       scripts/sim/sword_defs.gd "FANG_KNOCK: float = 170.0" "FANG_KNOCK: float = 400.0"
mutate restart-keeps-enemies scripts/sim/game_run.gd "	enemies = []
	projectiles = []
	for at: Vector2 in scenario.initial_husks:" "	projectiles = []
	for at: Vector2 in scenario.initial_husks:"
mutate camera-no-lookahead  scripts/sim/game_run.gd  "CAMERA_LOOKAHEAD: float = 0.12" "CAMERA_LOOKAHEAD: float = 0.0"
mutate telegraph-shortened  scripts/sim/spawn_marker.gd "TELEGRAPH: float = 0.7" "TELEGRAPH: float = 0.1"
mutate wave-never-clears    scripts/sim/wave_director.gd "		if wave >= _wave_count:
			survived = true" "		if wave >= _wave_count:
			survived = false"
mutate dash-key-lost        scripts/input/input_translator.gd "[KEY_SPACE, KEY_SHIFT]" "[KEY_SPACE]"
mutate r-key-always-restarts scripts/input/input_translator.gd "commands.append(GameCommand.restart_from_key())" "commands.append(GameCommand.restart())"
mutate lost-arrow-alias     scripts/input/input_translator.gd "[KEY_A, KEY_LEFT]" "[KEY_A]"
mutate touch-steals-pointer scripts/input/touch_joystick.gd  "if pointer == -1 and _can_start_at" "if _can_start_at"
mutate touch-ignores-cancel scripts/input/touch_joystick.gd  "		if touch.index == pointer:
			release()" "		if touch.index == pointer and not touch.canceled:
			release()"
mutate focus-keeps-input    scripts/main.gd "	input.release_all()
	if run != null and not run.paused:" "	if run != null and not run.paused:"
mutate focus-keeps-running  scripts/main.gd "	if run != null and not run.paused:
		_submit(GameCommand.pause())" "	if false:
		_submit(GameCommand.pause())"
mutate dash-button-on-release scripts/hud.gd "_dash_button.button_down.connect" "_dash_button.pressed.connect"
mutate pause-button-on-release scripts/hud.gd "_pause_button.button_down.connect" "_pause_button.pressed.connect"
mutate restart-button-on-release scripts/hud.gd "_restart_button.button_down.connect" "_restart_button.pressed.connect"
mutate dead-husk-keeps-chasing scripts/sim/enemy_state.gd "		if run.dead:
			want = SimMath.polar" "		if false:
			want = SimMath.polar"
mutate wander-too-fast      scripts/sim/enemy_state.gd "speed * 0.3)" "speed * 0.6)"
mutate slowmo-runs-in-hitstop scripts/sim/game_run.gd "	if hitstop > 0.0:
		hitstop -= TICK_DT
		return" "	if hitstop > 0.0:
		hitstop -= TICK_DT
		slowmo -= TICK_DT
		return"
mutate visual-not-updated   scripts/main.gd "	visual.apply_pose(run.position, run.facing, moving)" "	pass"
mutate sound-never-unlocks  scripts/audio/sfx_bank.gd "	unlocked = true
	play(\"unlock\")" "	play(\"unlock\")"
# --- runners, brutes, crowds and walls (slice #9)
mutate runner-no-weave      scripts/sim/enemy_state.gd "RUNNER_WEAVE_AMPLITUDE: float = 0.5" "RUNNER_WEAVE_AMPLITUDE: float = 0.0"
mutate runner-weave-rate    scripts/sim/enemy_state.gd "RUNNER_WEAVE_RATE: float = 5.0" "RUNNER_WEAVE_RATE: float = 3.0"
mutate weave-for-everyone   scripts/sim/enemy_state.gd "		elif kind == EnemyDefs.RUNNER:" "		elif kind != EnemyDefs.BRUTE:"
mutate runner-speed         scripts/sim/enemy_defs.gd "RUNNER_SPEED: float = 178.0" "RUNNER_SPEED: float = 120.0"
mutate runner-radius        scripts/sim/enemy_defs.gd "RUNNER_RADIUS: float = 11.0" "RUNNER_RADIUS: float = 16.0"
mutate runner-damage        scripts/sim/enemy_defs.gd "RUNNER_DAMAGE: int = 6" "RUNNER_DAMAGE: int = 10"
mutate runner-knock         scripts/sim/enemy_defs.gd "RUNNER_KNOCK: float = 1.3" "RUNNER_KNOCK: float = 1.0"
mutate runner-hp            scripts/sim/enemy_defs.gd "RUNNER_HP: float = 14.0" "RUNNER_HP: float = 30.0"
mutate brute-hp             scripts/sim/enemy_defs.gd "BRUTE_HP: float = 170.0" "BRUTE_HP: float = 100.0"
mutate brute-speed          scripts/sim/enemy_defs.gd "BRUTE_SPEED: float = 52.0" "BRUTE_SPEED: float = 92.0"
mutate brute-damage         scripts/sim/enemy_defs.gd "BRUTE_DAMAGE: int = 20" "BRUTE_DAMAGE: int = 10"
mutate brute-knock-resist   scripts/sim/enemy_defs.gd "BRUTE_KNOCK: float = 0.35" "BRUTE_KNOCK: float = 1.0"
mutate brute-radius         scripts/sim/enemy_defs.gd "BRUTE_RADIUS: float = 30.0" "BRUTE_RADIUS: float = 20.0"
mutate wave-health-scaling  scripts/sim/enemy_defs.gd "HP_PER_WAVE: float = 0.1" "HP_PER_WAVE: float = 0.2"
mutate hit-ignores-resistance scripts/sim/game_run.gd "var force: float = knock * enemy.knock_mult * (CRIT_KNOCK_BONUS" "var force: float = knock * (CRIT_KNOCK_BONUS"
mutate launch-forgets-velocity scripts/sim/enemy_state.gd "	velocity = velocity * 0.3 + direction * force" "	velocity = direction * force"
mutate launch-stun-flat     scripts/sim/enemy_state.gd "	stun = maxf(stun, 0.08 + force / 1500.0)" "	stun = maxf(stun, 0.08)"
mutate separation-equal-split scripts/sim/game_run.gd "a.position -= normal * overlap * mass_b / (mass_a + mass_b)" "a.position -= normal * overlap * 0.5"
mutate separation-masses-swapped scripts/sim/game_run.gd "b.position += normal * overlap * mass_a / (mass_a + mass_b)" "b.position += normal * overlap * mass_b / (mass_a + mass_b)"
mutate separation-radius-padding scripts/sim/game_run.gd "if dist >= reach or dist == 0.0:" "if dist >= reach + 3.0 or dist == 0.0:"
mutate separation-box-too-tight scripts/sim/game_run.gd "if absf(d.x) > reach or absf(d.y) > reach:" "if absf(d.x) > reach * 0.5 or absf(d.y) > reach * 0.5:"
mutate bowl-min-speed       scripts/sim/game_run.gd "BOWL_MIN_SPEED: float = 340.0" "BOWL_MIN_SPEED: float = 200.0"
mutate bowl-needs-no-stun   scripts/sim/game_run.gd "if launched.stun > 0.0 and launched.velocity.length() > BOWL_MIN_SPEED" "if launched.velocity.length() > BOWL_MIN_SPEED"
mutate bowl-ignores-direction scripts/sim/game_run.gd " and launched.velocity.dot(normal * sign_value) > 0.0:" ":"
mutate bowl-damage          scripts/sim/game_run.gd "BOWL_DAMAGE: float = 3.0" "BOWL_DAMAGE: float = 1.0"
mutate bowl-impulse         scripts/sim/game_run.gd "BOWL_IMPULSE: float = 0.55" "BOWL_IMPULSE: float = 0.3"
mutate bowl-size-ratio      scripts/sim/game_run.gd "launched.velocity * BOWL_IMPULSE * launched.radius / hit.radius * 0.6" "launched.velocity * BOWL_IMPULSE * 0.6"
mutate bowl-launcher-drag   scripts/sim/game_run.gd "BOWL_SELF_DRAG: float = 0.6" "BOWL_SELF_DRAG: float = 1.0"
mutate bowl-stun            scripts/sim/game_run.gd "BOWL_STUN: float = 0.25" "BOWL_STUN: float = 0.1"
mutate bowl-never-kills     scripts/sim/game_run.gd "		if hit.hp <= 0.0 and not hit.dead:
			kill(hit, SimMath.norm(launched.velocity, rng))" "		if false:
			kill(hit, SimMath.norm(launched.velocity, rng))"
mutate bowl-not-reported    scripts/sim/game_run.gd "		add_cue(SimCue.make(SimCue.Kind.BOWLED, (launched.position + hit.position) * 0.5, SimMath.norm(launched.velocity, rng, Vector2.RIGHT, true), int(BOWL_DAMAGE)))" "		pass"
mutate wall-threshold       scripts/sim/game_run.gd "WALL_SLAM_MIN_SPEED: float = 380.0" "WALL_SLAM_MIN_SPEED: float = 300.0"
mutate wall-base-damage     scripts/sim/game_run.gd "WALL_SLAM_BASE_DAMAGE: float = 6.0" "WALL_SLAM_BASE_DAMAGE: float = 4.0"
mutate wall-speed-damage    scripts/sim/game_run.gd "WALL_SLAM_DAMAGE_PER_SPEED: float = 0.04" "WALL_SLAM_DAMAGE_PER_SPEED: float = 0.02"
mutate wall-stun-cap        scripts/sim/game_run.gd "WALL_SLAM_STUN_CAP: float = 0.15" "WALL_SLAM_STUN_CAP: float = 0.3"
mutate wall-hitstop         scripts/sim/game_run.gd "WALL_SLAM_HITSTOP: float = 0.04" "WALL_SLAM_HITSTOP: float = 0.0"
mutate wall-shake           scripts/sim/game_run.gd "WALL_SLAM_SHAKE: float = 0.18" "WALL_SLAM_SHAKE: float = 0.0"
mutate wall-slam-never-kills scripts/sim/game_run.gd "	if enemy.hp <= 0.0 and not enemy.dead:
		kill(enemy, SimMath.norm(-enemy.velocity, rng))" "	if false:
		kill(enemy, SimMath.norm(-enemy.velocity, rng))"
mutate wall-slam-unstunned  scripts/sim/enemy_state.gd "	if slammed and stun > 0.0 and speed_before" "	if slammed and speed_before"
mutate wall-bounce-x        scripts/sim/enemy_state.gd "velocity.x *= -0.35" "velocity.x *= -0.6"
mutate wall-bounce-y        scripts/sim/enemy_state.gd "velocity.y *= -0.35" "velocity.y *= 0.0"
mutate wall-slam-not-reported scripts/sim/game_run.gd "	add_cue(SimCue.make(SimCue.Kind.WALL_SLAM, enemy.position, Vector2.ZERO, dealt))" "	add_cue(SimCue.make(SimCue.Kind.ENEMY_HIT, enemy.position, Vector2.ZERO, dealt))"
mutate shove-without-fixture scripts/sim/game_run.gd "	if not scenario.dev_shove or paused or dead:" "	if paused or dead:"
mutate shove-while-paused   scripts/sim/game_run.gd "	if not scenario.dev_shove or paused or dead:" "	if not scenario.dev_shove or dead:"
mutate shove-radius         scripts/sim/game_run.gd "DEV_SHOVE_RADIUS: float = 320.0" "DEV_SHOVE_RADIUS: float = 200.0"
mutate shove-knock          scripts/sim/game_run.gd "DEV_SHOVE_KNOCK: float = 650.0" "DEV_SHOVE_KNOCK: float = 300.0"
mutate shove-ignores-resistance scripts/sim/game_run.gd "DEV_SHOVE_KNOCK * enemy.knock_mult" "DEV_SHOVE_KNOCK"
mutate shove-wakes-the-dead scripts/sim/game_run.gd "		if enemy.dead or offset.length() > DEV_SHOVE_RADIUS:" "		if offset.length() > DEV_SHOVE_RADIUS:"
mutate shove-key-lost       scripts/input/input_translator.gd "SHOVE_KEYS: Array[Key] = [KEY_F]" "SHOVE_KEYS: Array[Key] = [KEY_G]"
mutate encounter-toggle-lost scripts/sim/game_run.gd "			restart_with(_encounter_scenarios[RunScenario.ENCOUNTER_CYCLE.find(RunScenario.next_encounter(scenario.encounter))])" "			pass"
mutate restart-with-keeps-scenario scripts/sim/game_run.gd "	scenario = new_scenario
	restarts += 1" "	restarts += 1"
mutate restart-keeps-cue-counts scripts/sim/game_run.gd "	_cue_counts = {}
" "	_cue_counts = _cue_counts
"
mutate placement-position-dropped scripts/sim/game_run.gd "EnemyState.make(placement.kind, placement.position," "EnemyState.make(placement.kind, placement.position + Vector2(40.0, 0.0),"
mutate placement-velocity-dropped scripts/sim/game_run.gd "		enemy.velocity = placement.velocity" "		enemy.velocity = Vector2.ZERO"
mutate placement-health-dropped scripts/sim/game_run.gd "		if placement.hp >= 0.0:
			enemy.hp = placement.hp" "		if false:
			enemy.hp = placement.hp"
mutate composition-ignored  scripts/sim/wave_director.gd "		queue.append_array(_wave_kinds)" "		queue.append_array([])"
mutate spawn-always-husk    scripts/sim/wave_director.gd "EnemyState.make(marker.kind, marker.position," "EnemyState.make(EnemyDefs.HUSK, marker.position,"
mutate spawn-phase-fixed    scripts/sim/wave_director.gd "var phase: float = run.rng.randf_range(0.0, 10.0)" "var phase: float = 0.0"
mutate marker-kind-lost     scripts/sim/wave_director.gd "markers.append(SpawnMarker.make(kind, _spawn_point(run)))" "markers.append(SpawnMarker.make(EnemyDefs.HUSK, _spawn_point(run)))"
mutate stun-flag-dropped    scripts/presentation/run_presenter.gd "enemy.hp / enemy.max_hp, enemy.stun > 0.0, enemy.telegraph())" "enemy.hp / enemy.max_hp, false, enemy.telegraph())"
mutate brute-drawn-small    scripts/presentation/placeholder_enemy_visual.gd "			return 30.0" "			return 16.0"
mutate runner-same-colour   scripts/presentation/placeholder_enemy_visual.gd "const RUNNER_COLOR: Color = Color(1.0, 0.55, 0.27)" "const RUNNER_COLOR: Color = Color(0.84, 0.28, 0.34)"
mutate shove-button-on-release scripts/hud.gd "_shove_button.button_down.connect" "_shove_button.pressed.connect"
mutate shove-button-unwired scripts/main.gd "	_hud.shove_pressed.connect(func() -> void: _submit(GameCommand.dev_shove()))" "	_hud.shove_pressed.connect(func() -> void: pass)"
mutate crowd-button-unwired scripts/main.gd "	_hud.encounter_pressed.connect(func() -> void: _submit(GameCommand.toggle_encounter()))" "	_hud.encounter_pressed.connect(func() -> void: pass)"
mutate launch-option-lost   scripts/launch_options.gd 'ENCOUNTER_ARGUMENT_PREFIX: String = "--encounter="' 'ENCOUNTER_ARGUMENT_PREFIX: String = "--enc="'
mutate wall-crowd-moved     scripts/sim/run_scenario.gd "Vector2(2420.0, 900.0)," "Vector2(2420.0, 930.0),"
mutate wall-encounter-wave-on scripts/sim/run_scenario.gd "	scenario.waves_enabled = false
	scenario.start_position = WALL_PLAYER" "	scenario.start_position = WALL_PLAYER"
mutate render-rate-dependent scripts/main.gd "func _physics_process(_delta: float) -> void:" "func _process(_delta: float) -> void:
	run.step()


func _physics_process(_delta: float) -> void:"
mutate wall-slam-sound-lost scripts/audio/sfx_bank.gd "		SimCue.Kind.ENEMY_HIT, SimCue.Kind.WALL_SLAM:" "		SimCue.Kind.ENEMY_HIT:"

# --- spitters, projectiles and parries (slice #10)
mutate spitter-radius              scripts/sim/enemy_defs.gd "SPITTER_RADIUS: float = 15.0" "SPITTER_RADIUS: float = 12.0"
mutate spitter-hp                  scripts/sim/enemy_defs.gd "SPITTER_HP: float = 24.0" "SPITTER_HP: float = 30.0"
mutate spitter-speed               scripts/sim/enemy_defs.gd "SPITTER_SPEED: float = 85.0" "SPITTER_SPEED: float = 100.0"
mutate spitter-damage              scripts/sim/enemy_defs.gd "SPITTER_DAMAGE: int = 8" "SPITTER_DAMAGE: int = 10"
mutate spitter-knock               scripts/sim/enemy_defs.gd "SPITTER_KNOCK: float = 1.1" "SPITTER_KNOCK: float = 1.0"
mutate spitter-retreat-range       scripts/sim/enemy_defs.gd "SPITTER_RETREAT_RANGE: float = 260.0" "SPITTER_RETREAT_RANGE: float = 200.0"
mutate spitter-orbit-range         scripts/sim/enemy_defs.gd "SPITTER_ORBIT_RANGE: float = 380.0" "SPITTER_ORBIT_RANGE: float = 450.0"
mutate spitter-orbit-speed         scripts/sim/enemy_defs.gd "SPITTER_ORBIT_SPEED: float = 0.6" "SPITTER_ORBIT_SPEED: float = 1.0"
mutate spitter-fire-range          scripts/sim/enemy_defs.gd "SPITTER_FIRE_RANGE: float = 620.0" "SPITTER_FIRE_RANGE: float = 500.0"
mutate spitter-charge-slow         scripts/sim/enemy_defs.gd "SPITTER_CHARGE_SLOW: float = 0.15" "SPITTER_CHARGE_SLOW: float = 0.5"
mutate spitter-charge-time         scripts/sim/enemy_defs.gd "SPITTER_CHARGE_TIME: float = 0.5" "SPITTER_CHARGE_TIME: float = 0.3"
mutate spitter-cooldown-min        scripts/sim/enemy_defs.gd "SPITTER_COOLDOWN_MIN: float = 2.0" "SPITTER_COOLDOWN_MIN: float = 1.0"
mutate spitter-cooldown-max        scripts/sim/enemy_defs.gd "SPITTER_COOLDOWN_MAX: float = 2.9" "SPITTER_COOLDOWN_MAX: float = 4.0"
mutate spitter-first-cooldown-max  scripts/sim/enemy_defs.gd "SPITTER_FIRST_COOLDOWN_MAX: float = 3.0" "SPITTER_FIRST_COOLDOWN_MAX: float = 5.0"
mutate spitter-first-cooldown-min  scripts/sim/enemy_defs.gd "SPITTER_FIRST_COOLDOWN_MIN: float = 1.5" "SPITTER_FIRST_COOLDOWN_MIN: float = 0.5"
mutate spitter-shot-speed          scripts/sim/enemy_defs.gd "SPITTER_SHOT_SPEED: float = 270.0" "SPITTER_SHOT_SPEED: float = 200.0"
mutate projectile-radius           scripts/sim/projectile_state.gd "const RADIUS: float = 7.0" "const RADIUS: float = 10.0"
mutate projectile-lifetime         scripts/sim/projectile_state.gd "const LIFETIME: float = 4.0" "const LIFETIME: float = 3.0"
mutate projectile-damage           scripts/sim/projectile_state.gd "const DAMAGE: int = 8" "const DAMAGE: int = 10"
mutate spitter-never-retreats      scripts/sim/enemy_state.gd "if dist < EnemyDefs.SPITTER_RETREAT_RANGE:" "if false:"
mutate spitter-orbit-direction     scripts/sim/enemy_state.gd "want = Vector2(-toward.y, toward.x) * speed * EnemyDefs.SPITTER_ORBIT_SPEED" "want = Vector2(toward.y, -toward.x) * speed * EnemyDefs.SPITTER_ORBIT_SPEED"
mutate spitter-never-orbits        scripts/sim/enemy_state.gd "elif dist < EnemyDefs.SPITTER_ORBIT_RANGE:" "elif false:"
mutate spitter-ignores-cooldown    scripts/sim/enemy_state.gd "if shoot_cooldown <= 0.0 and dist < EnemyDefs.SPITTER_FIRE_RANGE:" "if dist < EnemyDefs.SPITTER_FIRE_RANGE:"
mutate spitter-shoots-out-of-range scripts/sim/enemy_state.gd "if shoot_cooldown <= 0.0 and dist < EnemyDefs.SPITTER_FIRE_RANGE:" "if shoot_cooldown <= 0.0:"
mutate spitter-no-charge-slow      scripts/sim/enemy_state.gd "want *= EnemyDefs.SPITTER_CHARGE_SLOW" "want *= 1.0"
mutate spitter-stun-keeps-charge   scripts/sim/enemy_state.gd "		velocity *= exp(-dt * 5.0)
		charge = 0.0
" "		velocity *= exp(-dt * 5.0)
"
mutate spitter-fires-wrong-way     scripts/sim/enemy_state.gd "toward * EnemyDefs.SPITTER_SHOT_SPEED)" "Vector2.RIGHT * EnemyDefs.SPITTER_SHOT_SPEED)"
mutate spitter-muzzle-at-centre    scripts/sim/enemy_state.gd "run.spawn_projectile(position + toward * radius," "run.spawn_projectile(position,"
mutate spitter-no-cooldown         scripts/sim/enemy_state.gd "shoot_cooldown = run.rng.randf_range(EnemyDefs.SPITTER_COOLDOWN_MIN, EnemyDefs.SPITTER_COOLDOWN_MAX)" "shoot_cooldown = 0.0"
mutate spitter-fixed-cooldown      scripts/sim/enemy_state.gd "shoot_cooldown = run.rng.randf_range(EnemyDefs.SPITTER_COOLDOWN_MIN, EnemyDefs.SPITTER_COOLDOWN_MAX)" "shoot_cooldown = 2.45"
mutate spitter-charge-not-reset    scripts/sim/enemy_state.gd "			charge = 0.0
			shoot_cooldown = run.rng" "			shoot_cooldown = run.rng"
mutate spitter-shoots-over-the-dead scripts/sim/enemy_state.gd "		if run.dead:
			want = SimMath.polar(age * 0.3 + float(serial % 7), speed * 0.3)
		elif kind == EnemyDefs.SPITTER:" "		if run.dead and kind != EnemyDefs.SPITTER:
			want = SimMath.polar(age * 0.3 + float(serial % 7), speed * 0.3)
		elif kind == EnemyDefs.SPITTER:"
mutate spitter-telegraph-lost      scripts/sim/enemy_state.gd "return clampf(charge / EnemyDefs.SPITTER_CHARGE_TIME, 0.0, 1.0)" "return 0.0"
mutate spawned-spitter-no-cooldown scripts/sim/wave_director.gd "cooldown = run.rng.randf_range(EnemyDefs.SPITTER_FIRST_COOLDOWN_MIN, EnemyDefs.SPITTER_FIRST_COOLDOWN_MAX)" "cooldown = 0.0"
mutate placed-spitter-no-cooldown-draw scripts/sim/game_run.gd "cooldown = rng.randf_range(EnemyDefs.SPITTER_FIRST_COOLDOWN_MIN, EnemyDefs.SPITTER_FIRST_COOLDOWN_MAX)" "cooldown = 0.0"
mutate placement-cooldown-dropped  scripts/sim/game_run.gd "placement.phase, maxf(cooldown, 0.0))" "placement.phase, 0.0)"
mutate placement-charge-dropped    scripts/sim/game_run.gd "		enemy.charge = placement.charge
" ""
mutate projectile-never-moves      scripts/sim/game_run.gd "projectile.position += projectile.velocity * dt" "projectile.position += Vector2.ZERO"
mutate projectile-ignores-slow-motion scripts/sim/game_run.gd "projectile.position += projectile.velocity * dt" "projectile.position += projectile.velocity * TICK_DT"
mutate projectile-never-expires    scripts/sim/game_run.gd "projectile.life -= dt" "projectile.life -= 0.0"
mutate projectile-immortal-in-arena scripts/sim/game_run.gd "elif not WORLD.has_point(projectile.position):" "elif false:"
mutate projectile-ignores-invulnerability scripts/sim/game_run.gd "elif iframes <= 0.0 and not dead and (projectile.position - position)" "elif not dead and (projectile.position - position)"
mutate projectile-hits-the-dead    scripts/sim/game_run.gd "elif iframes <= 0.0 and not dead and (projectile.position - position)" "elif iframes <= 0.0 and (projectile.position - position)"
mutate projectile-hit-radius       scripts/sim/game_run.gd "< projectile.radius + PLAYER_RADIUS:" "< projectile.radius:"
mutate projectile-knock-source     scripts/sim/game_run.gd "hurt_player(ProjectileState.DAMAGE, projectile.position)" "hurt_player(ProjectileState.DAMAGE, position + Vector2.RIGHT * 1000.0)"
mutate projectile-damage-from-shooter scripts/sim/game_run.gd "hurt_player(ProjectileState.DAMAGE, projectile.position)" "hurt_player(3, projectile.position)"
mutate resolved-projectile-still-hits scripts/sim/game_run.gd "		if projectile.is_resolved():
			continue
		projectile.position += " "		projectile.position += "
mutate projectile-update-dropped   scripts/sim/game_run.gd "	_update_projectiles(dt)
" ""
mutate projectile-not-cleared-on-restart scripts/sim/game_run.gd "	enemies = []
	projectiles = []
" "	enemies = []
"
mutate firing-not-reported         scripts/sim/game_run.gd "	add_cue(SimCue.make(SimCue.Kind.PROJECTILE_FIRED, at, velocity_value.normalized()))
" ""
mutate parry-ignores-radius        scripts/sim/game_run.gd "< projectile.radius + pad:" "< pad:"
mutate parry-point-test            scripts/sim/game_run.gd "SimMath.seg_dist(projectile.position, from, to) <" "(projectile.position - to).length() <"
mutate parry-twice                 scripts/sim/game_run.gd "		if projectile.is_resolved():
			continue
		if SimMath.seg_dist" "		if SimMath.seg_dist"
mutate parry-no-hitstop            scripts/sim/game_run.gd "			hitstop = maxf(hitstop, PARRY_HITSTOP)
" ""
mutate parry-hitstop-value         scripts/sim/game_run.gd "PARRY_HITSTOP: float = 0.025" "PARRY_HITSTOP: float = 0.1"
mutate parry-hitstop-overwrites    scripts/sim/game_run.gd "hitstop = maxf(hitstop, PARRY_HITSTOP)" "hitstop = PARRY_HITSTOP"
mutate parry-not-reported         scripts/sim/game_run.gd "			add_cue(SimCue.make(SimCue.Kind.PROJECTILE_PARRIED, projectile.position, SimMath.norm(-projectile.velocity, rng, Vector2.LEFT, true)))
" ""
mutate parry-cue-direction         scripts/sim/game_run.gd "SimMath.norm(-projectile.velocity, rng, Vector2.LEFT, true)" "SimMath.norm(projectile.velocity, rng, Vector2.LEFT, true)"
mutate parry-count-lost            scripts/sim/game_run.gd "			parried += 1
" ""
mutate slam-clear-radius           scripts/sim/game_run.gd "(projectile.position - center).length() < radius:" "(projectile.position - center).length() < radius * 2.0:"
mutate slam-clear-reported-as-parry scripts/sim/game_run.gd "			projectile.resolve(ProjectileState.Fate.CLEARED)
" "			projectile.resolve(ProjectileState.Fate.PARRIED)
"
mutate resolve-last-wins           scripts/sim/projectile_state.gd "	if fate != Fate.FLYING:
		return false
	fate = how" "	fate = how"
mutate fang-parry-removed          scripts/sim/sword_state.gd "	run.parry_projectiles(previous, tip, SwordDefs.FANG_PARRY_PAD)
" ""
mutate fang-parry-tip-only         scripts/sim/sword_state.gd "run.parry_projectiles(previous, tip, SwordDefs.FANG_PARRY_PAD)" "run.parry_projectiles(tip, tip, SwordDefs.FANG_PARRY_PAD)"
mutate fang-parry-on-hit           scripts/sim/sword_state.gd "			run.hit_enemy(enemy, damage * boost, dir, SwordDefs.FANG_KNOCK, self)
" "			run.parry_projectiles(previous, tip, SwordDefs.FANG_PARRY_PAD)
			run.hit_enemy(enemy, damage * boost, dir, SwordDefs.FANG_KNOCK, self)
"
mutate fang-parry-pad-small        scripts/sim/sword_defs.gd "FANG_PARRY_PAD: float = 8.0" "FANG_PARRY_PAD: float = 4.0"
mutate fang-parry-pad-large        scripts/sim/sword_defs.gd "FANG_PARRY_PAD: float = 8.0" "FANG_PARRY_PAD: float = 20.0"
mutate fang-parry-ends-strike      scripts/sim/sword_state.gd "	run.parry_projectiles(previous, tip, SwordDefs.FANG_PARRY_PAD)
" "	if run.parry_projectiles(previous, tip, SwordDefs.FANG_PARRY_PAD) > 0:
		phase = Phase.RECOVER
		timer = SwordDefs.FANG_RECOVER_AFTER_MISS
"
mutate cycle-skips-spitters        scripts/sim/game_run.gd "restart_with(_encounter_scenarios[RunScenario.ENCOUNTER_CYCLE.find(RunScenario.next_encounter(scenario.encounter))])" "restart_with(_encounter_scenarios[0 if scenario.encounter != RunScenario.ENCOUNTER_NORMAL else 1])"
mutate cycle-too-short             scripts/sim/run_scenario.gd "% ENCOUNTER_CYCLE.size()]" "% 2]"
mutate spitter-wave-short          scripts/sim/run_scenario.gd "&\"spitter\", &\"husk\", &\"spitter\", &\"spitter\", &\"husk\", &\"spitter\", &\"husk\", &\"spitter\"," "&\"spitter\", &\"husk\", &\"spitter\", &\"husk\","
mutate spitter-encounter-with-shove scripts/sim/run_scenario.gd "	scenario.encounter = ENCOUNTER_SPITTERS
" "	scenario.encounter = ENCOUNTER_SPITTERS
	scenario.dev_shove = true
"
mutate spitter-launch-option-lost  scripts/launch_options.gd "\"spitters\":" "\"spitterz\":"
mutate dev-button-label-lost       scripts/hud.gd "\"Dev: %s (restarts)\" % RunScenario" "\"%s\" % RunScenario"
mutate spitter-legend-lost         scripts/hud.gd "SPITTER ENCOUNTER (dev fixture)" "ENCOUNTER"
mutate parry-sound-lost            scripts/audio/sfx_bank.gd "SimCue.Kind.PROJECTILE_PARRIED:
			play(\"parry\")" "SimCue.Kind.PROJECTILE_PARRIED:
			play(\"hit\")"
mutate shot-sound-lost             scripts/audio/sfx_bank.gd "SimCue.Kind.PROJECTILE_FIRED:
			play(\"shot\")" "SimCue.Kind.PROJECTILE_FIRED:
			pass"
mutate telegraph-not-passed        scripts/presentation/run_presenter.gd "enemy.stun > 0.0, enemy.telegraph())" "enemy.stun > 0.0, 0.0)"
mutate spitter-same-colour-as-husk scripts/presentation/placeholder_enemy_visual.gd "const SPITTER_COLOR: Color = Color(0.51, 0.82, 0.35)" "const SPITTER_COLOR: Color = Color(0.84, 0.28, 0.34)"
mutate spitter-drawn-small         scripts/presentation/placeholder_enemy_visual.gd "		EnemyDefs.SPITTER:
			return 15.0" "		EnemyDefs.SPITTER:
			return 10.0"
mutate render-rate-spitters-dependent scripts/sim/game_run.gd "	_update_projectiles(dt)
	_update_motes(dt)
" "	_update_projectiles(dt)
	_update_motes(dt)
	if tick % 7 == 0:
		_update_projectiles(dt)
"
# --- Viper Flurry and the slot ultimates (slice #12)
mutate flurry-cooldown-short       scripts/sim/sword_defs.gd "FANG_ULT_COOLDOWN: float = 9.0" "FANG_ULT_COOLDOWN: float = 4.0"
mutate flurry-range-longer         scripts/sim/sword_defs.gd "FANG_ULT_RANGE: float = 420.0" "FANG_ULT_RANGE: float = 520.0"
mutate flurry-radius-wider         scripts/sim/sword_defs.gd "FANG_ULT_RADIUS: float = 150.0" "FANG_ULT_RADIUS: float = 200.0"
mutate flurry-duration             scripts/sim/sword_defs.gd "FANG_ULT_DURATION: float = 1.25" "FANG_ULT_DURATION: float = 2.0"
mutate flurry-cadence              scripts/sim/sword_defs.gd "FANG_ULT_CADENCE: float = 0.08" "FANG_ULT_CADENCE: float = 0.16"
mutate flurry-damage-factor        scripts/sim/sword_defs.gd "FANG_ULT_DAMAGE_FACTOR: float = 1.2" "FANG_ULT_DAMAGE_FACTOR: float = 1.0"
mutate flurry-knockback            scripts/sim/sword_defs.gd "FANG_ULT_KNOCK: float = 120.0" "FANG_ULT_KNOCK: float = 300.0"
mutate flurry-shake-lost           scripts/sim/sword_defs.gd "FANG_ULT_SHAKE: float = 0.05" "FANG_ULT_SHAKE: float = 0.0"
mutate flurry-approach-slow        scripts/sim/sword_defs.gd "FANG_ULT_APPROACH_RATE: float = 28.0" "FANG_ULT_APPROACH_RATE: float = 14.0"
mutate flurry-standoff             scripts/sim/sword_defs.gd "FANG_ULT_STANDOFF: float = 20.0" "FANG_ULT_STANDOFF: float = 0.0"
mutate flurry-recovery-long        scripts/sim/sword_defs.gd "FANG_ULT_RECOVER_TIME: float = 0.3" "FANG_ULT_RECOVER_TIME: float = 0.6"
mutate flurry-recovery-speed       scripts/sim/sword_defs.gd "FANG_ULT_RECOVER_SPEED: float = 300.0" "FANG_ULT_RECOVER_SPEED: float = 0.0"
mutate flurry-wander-too-wide      scripts/sim/sword_defs.gd "FANG_ULT_WANDER_FRACTION: float = 0.7" "FANG_ULT_WANDER_FRACTION: float = 1.4"
mutate heavy-hit-flash-normal      scripts/sim/sword_defs.gd "HEAVY_HIT_FLASH: float = 0.2" "HEAVY_HIT_FLASH: float = 0.11"
mutate heavy-hit-causes-hitstop    scripts/sim/game_run.gd "	if not heavy:
		var stop: float" "	if true:
		var stop: float"
mutate flurry-dart-not-heavy       scripts/sim/sword_state.gd "SwordDefs.FANG_ULT_KNOCK, self, true)" "SwordDefs.FANG_ULT_KNOCK, self, false)"
mutate flurry-no-range-clamp       scripts/sim/game_run.gd "and to_point.length() > SwordDefs.ultimate_range(type_id):" "and to_point.length() > 99999.0:"
mutate flurry-clamp-from-sword     scripts/sim/game_run.gd "target = position + to_point.normalized() * SwordDefs.ultimate_range(type_id)" "target = sword.position + to_point.normalized() * SwordDefs.ultimate_range(type_id)"
mutate flurry-recharge-not-armed   scripts/sim/sword_state.gd "	ultimate_cooldown_left = ultimate_cooldown
	boost = 1.0" "	ultimate_cooldown_left = 0.0
	boost = 1.0"
mutate flurry-recharge-pauses      scripts/sim/sword_state.gd "	ultimate_cooldown_left = maxf(0.0, ultimate_cooldown_left - dt)" "	if phase != Phase.ULTIMATE:
		ultimate_cooldown_left = maxf(0.0, ultimate_cooldown_left - dt)"
mutate flurry-recharge-ignores-rarity scripts/sim/sword_state.gd "SwordDefs.ultimate_cooldown(spec_value.type_id) * SwordDefs.RARITY_COOLDOWN[rarity]" "SwordDefs.ultimate_cooldown(spec_value.type_id)"
mutate flurry-starts-on-cooldown   scripts/sim/sword_state.gd "	sword.position = at
" "	sword.position = at
	sword.ultimate_cooldown_left = sword.ultimate_cooldown
"
mutate flurry-recharge-refusal-lost scripts/sim/game_run.gd "	if sword.ultimate_cooldown_left > 0.0:
		add_cue" "	if false:
		add_cue"
mutate flurry-active-refusal-lost  scripts/sim/game_run.gd "	if sword.phase == SwordState.Phase.ULTIMATE:
		return UltimateResult.ACTIVE" "	if false:
		return UltimateResult.ACTIVE"
mutate flurry-works-when-dead      scripts/sim/game_run.gd "	if paused or dead:
		return UltimateResult.UNAVAILABLE" "	if paused:
		return UltimateResult.UNAVAILABLE"
mutate flurry-works-when-paused    scripts/sim/game_run.gd "	if paused or dead:
		return UltimateResult.UNAVAILABLE" "	if dead:
		return UltimateResult.UNAVAILABLE"
mutate flurry-refusal-seconds      scripts/sim/game_run.gd "Vector2.ZERO, SimMath.py_round(sword.ultimate_cooldown_left)))" "Vector2.ZERO, 0))"
mutate flurry-wrong-slot           scripts/sim/game_run.gd "	var sword: SwordState = swords[slot]
	if sword.phase" "	var sword: SwordState = swords[(slot + 1) % swords.size()]
	if sword.phase"
mutate flurry-start-cue-lost       scripts/sim/game_run.gd "	cue.origin = origin
	add_cue(cue)" "	cue.origin = origin"
mutate flurry-victim-repeats       scripts/sim/sword_state.gd "				if enemy != struck:" "				if true:"
mutate flurry-strikes-the-dead     scripts/sim/sword_state.gd "		if struck != null and _in_play(run, struck):" "		if struck != null and run.enemies.has(struck):"
mutate flurry-strikes-the-removed  scripts/sim/sword_state.gd "		if struck != null and _in_play(run, struck):" "		if struck != null and not struck.dead:"
mutate attack-keeps-removed-target scripts/sim/sword_state.gd "		if not _in_play(run, target):" "		if target.dead:"
mutate in-play-ignores-dead        scripts/sim/sword_state.gd "	return enemy != null and not enemy.dead and run.enemies.has(enemy)" "	return enemy != null and run.enemies.has(enemy)"
mutate in-play-ignores-removal     scripts/sim/sword_state.gd "	return enemy != null and not enemy.dead and run.enemies.has(enemy)" "	return enemy != null and not enemy.dead"
mutate flurry-targets-the-dead     scripts/sim/sword_state.gd "			if not enemy.dead and (enemy.position - ultimate_point).length() < radius + enemy.radius:" "			if (enemy.position - ultimate_point).length() < radius + enemy.radius:"
mutate flurry-area-ignores-enemy-size scripts/sim/sword_state.gd "(enemy.position - ultimate_point).length() < radius + enemy.radius:" "(enemy.position - ultimate_point).length() < radius:"
mutate flurry-no-blink             scripts/sim/sword_state.gd "			position = point
			ultimate_goal = point" "			ultimate_goal = point"
mutate flurry-hit-direction        scripts/sim/sword_state.gd "SimMath.norm(struck.position - ultimate_point, run.rng, dir, true)" "SimMath.norm(ultimate_point - struck.position, run.rng, dir, true)"
mutate flurry-parries-orbs         scripts/sim/sword_state.gd "	velocity = (position - previous) / maxf(dt, 1e-4)
	if velocity.length_squared() > 400.0:" "	run.parry_projectiles(previous, position, 8.0)
	velocity = (position - previous) / maxf(dt, 1e-4)
	if velocity.length_squared() > 400.0:"
mutate flurry-keeps-target         scripts/sim/sword_state.gd "	boost = 1.0
	target = null
	ultimate_victim = null" "	boost = 1.0
	ultimate_victim = null"
mutate flurry-survives-death                        scripts/sim/sword_state.gd "		phase = Phase.IDLE
		ultimate_victim = null
		skewer_carried.clear()
		return" "		ultimate_victim = null
		skewer_carried.clear()
		return"
mutate flurry-render-rate-dependent scripts/sim/sword_state.gd "	ultimate_time_left -= dt
	ultimate_beat -= dt" "	ultimate_time_left -= dt * (1.0 + float(Engine.get_process_frames() % 2))
	ultimate_beat -= dt"
mutate flurry-auto-aim-ahead       scripts/sim/game_run.gd "AUTO_AIM_AHEAD: float = 300.0" "AUTO_AIM_AHEAD: float = 100.0"
mutate flurry-auto-aim-dead        scripts/sim/game_run.gd "		if not enemy.dead and dist_sq < nearest_sq:" "		if dist_sq < nearest_sq:"
mutate flurry-r-not-ultimate       scripts/input/input_translator.gd "[KEY_Q, KEY_E, KEY_R]" "[KEY_Q, KEY_E]"
mutate flurry-keys-swapped         scripts/input/input_translator.gd "[KEY_Q, KEY_E, KEY_R]" "[KEY_E, KEY_Q, KEY_R]"
mutate flurry-restart-before-ultimate scripts/input/input_translator.gd "				if code in ULTIMATE_KEYS:
					commands.append(GameCommand.ultimate(ULTIMATE_KEYS.find(code), aim_world()))
				if code in RESTART_KEYS:
					commands.append(GameCommand.restart_from_key())" "				if code in RESTART_KEYS:
					commands.append(GameCommand.restart_from_key())
				if code in ULTIMATE_KEYS:
					commands.append(GameCommand.ultimate(ULTIMATE_KEYS.find(code), aim_world()))"
mutate flurry-aim-ignores-camera   scripts/main.gd "	return run.camera + viewport_point - get_viewport().get_visible_rect().size * 0.5" "	return viewport_point - get_viewport().get_visible_rect().size * 0.5"
mutate flurry-aim-ignores-view-centre scripts/main.gd "	return run.camera + viewport_point - get_viewport().get_visible_rect().size * 0.5" "	return run.camera + viewport_point"
mutate flurry-mouse-aim-not-tracked scripts/input/input_translator.gd "		pointer = (event as InputEventMouse).position" "		pointer = pointer"
mutate flurry-hud-card-hidden      scripts/hud.gd "		_ult_cards[slot].visible = shown" "		_ult_cards[slot].visible = false"
mutate flurry-hud-always-ready     scripts/hud.gd "		elif ready:
			_ult_status[slot].text = \"READY\"" "		elif true:
			_ult_status[slot].text = \"READY\""
mutate flurry-hud-bar-full         scripts/hud.gd "(1.0 if active else sword.ultimate_charge())" "1.0"
mutate flurry-hud-no-active        scripts/hud.gd "		if active:
			_ult_status[slot].text = \"ACTIVE\"" "		if false:
			_ult_status[slot].text = \"ACTIVE\""
mutate hud-card-below-the-view     scripts/hud.gd "	card.offset_bottom = -16.0" "	card.offset_bottom = 40.0"
mutate hud-cards-anchored-top      scripts/hud.gd "	card.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)" "	card.set_anchors_preset(Control.PRESET_TOP_LEFT)"
mutate hud-dash-below-the-view     scripts/hud.gd "	_dash_button.offset_bottom = -24.0" "	_dash_button.offset_bottom = 24.0"
mutate hud-stretch-not-expand      project.godot "window/stretch/aspect=\"expand\"" "window/stretch/aspect=\"keep_width\""
mutate flurry-sound-lost           scripts/audio/sfx_bank.gd "SimCue.Kind.DASH, SimCue.Kind.ULTIMATE_STARTED:" "SimCue.Kind.DASH:"
mutate flurry-refusal-text-lost    scripts/presentation/effects_layer.gd "\"recharging %ds\" % cue.amount" "\"\""
mutate flurry-presenter-phase-lost scripts/presentation/run_presenter.gd "visual.apply_pose(sword.position, sword.angle, sword.phase)" "visual.apply_pose(sword.position, sword.angle, SwordState.Phase.IDLE)"

# --- Elemental conditions (slice #11)
mutate cond-burn-time                     scripts/sim/condition_defs.gd "BURN_TIME: float = 3.0" "BURN_TIME: float = 2.0"
mutate cond-poison-time                   scripts/sim/condition_defs.gd "POISON_TIME: float = 4.5" "POISON_TIME: float = 6.0"
mutate cond-chill-time                    scripts/sim/condition_defs.gd "CHILL_TIME: float = 2.5" "CHILL_TIME: float = 4.0"
mutate cond-freeze-time                   scripts/sim/condition_defs.gd "FREEZE_TIME: float = 1.6" "FREEZE_TIME: float = 2.4"
mutate cond-poison-cap                    scripts/sim/condition_defs.gd "POISON_MAX: int = 6" "POISON_MAX: int = 8"
mutate cond-freeze-threshold              scripts/sim/condition_defs.gd "FREEZE_STACKS: int = 4" "FREEZE_STACKS: int = 3"
mutate cond-chill-slow                    scripts/sim/condition_defs.gd "CHILL_SLOW: float = 0.5" "CHILL_SLOW: float = 0.8"
mutate cond-shatter-bonus                 scripts/sim/condition_defs.gd "SHATTER: float = 1.3" "SHATTER: float = 1.5"
mutate cond-freeze-keeps-velocity         scripts/sim/condition_defs.gd "FREEZE_VELOCITY_KEEP: float = 0.2" "FREEZE_VELOCITY_KEEP: float = 1.0"
mutate cond-burn-dps-base                 scripts/sim/condition_defs.gd "BURN_DPS_BASE: float = 1.5" "BURN_DPS_BASE: float = 2.5"
mutate cond-burn-dps-power                scripts/sim/condition_defs.gd "BURN_DPS_PER_POWER: float = 0.2" "BURN_DPS_PER_POWER: float = 0.3"
mutate cond-poison-dps-base               scripts/sim/condition_defs.gd "POISON_DPS_BASE: float = 1.0" "POISON_DPS_BASE: float = 2.0"
mutate cond-poison-dps-power              scripts/sim/condition_defs.gd "POISON_DPS_PER_POWER: float = 0.06" "POISON_DPS_PER_POWER: float = 0.1"
mutate cond-dot-period                    scripts/sim/condition_defs.gd "DOT_PERIOD: float = 0.5" "DOT_PERIOD: float = 1.0"
mutate cond-spread-reach                  scripts/sim/condition_defs.gd "SPREAD_REACH: float = 70.0" "SPREAD_REACH: float = 20.0"
mutate cond-spread-dps-factor             scripts/sim/condition_defs.gd "SPREAD_DPS_FACTOR: float = 0.6" "SPREAD_DPS_FACTOR: float = 1.0"
mutate cond-spread-time-factor            scripts/sim/condition_defs.gd "SPREAD_TIME_FACTOR: float = 0.7" "SPREAD_TIME_FACTOR: float = 0.3"
mutate brute-freezes-fully                scripts/sim/enemy_defs.gd "BRUTE_FREEZE_FACTOR: float = 0.6" "BRUTE_FREEZE_FACTOR: float = 1.0"
mutate brute-freeze-not-wired             scripts/sim/enemy_state.gd "	enemy.conditions.freeze_factor = def.freeze_factor
" ""
mutate fire-dps-replaced-while-burning    scripts/sim/enemy_conditions.gd "burn_dps = maxf(burn_dps, dps) if burn > 0.0 else dps" "burn_dps = dps"
mutate fire-dps-stale-after-expiry        scripts/sim/enemy_conditions.gd "burn_dps = maxf(burn_dps, dps) if burn > 0.0 else dps" "burn_dps = maxf(burn_dps, dps)"
mutate fire-timer-not-refreshed           scripts/sim/enemy_conditions.gd "			burn = ConditionDefs.BURN_TIME
" "			burn = burn if burn > 0.0 else ConditionDefs.BURN_TIME
"
mutate fire-stacks-ignored                scripts/sim/enemy_conditions.gd "var dps: float = ConditionDefs.burn_dps(power, stacks)" "var dps: float = ConditionDefs.burn_dps(power, 1)"
mutate poison-dps-replaced-while-poisoned scripts/sim/enemy_conditions.gd "poison_dps = maxf(poison_dps, dps) if poison > 0.0 else dps" "poison_dps = dps"
mutate poison-dps-stale-after-expiry      scripts/sim/enemy_conditions.gd "poison_dps = maxf(poison_dps, dps) if poison > 0.0 else dps" "poison_dps = maxf(poison_dps, dps)"
mutate poison-uncapped                    scripts/sim/enemy_conditions.gd "poison_stacks = mini(ConditionDefs.POISON_MAX, poison_stacks + stacks)" "poison_stacks = poison_stacks + stacks"
mutate poison-timer-not-refreshed         scripts/sim/enemy_conditions.gd "			poison = ConditionDefs.POISON_TIME
" "			poison = poison if poison > 0.0 else ConditionDefs.POISON_TIME
"
mutate poison-stacks-survive-expiry       scripts/sim/enemy_conditions.gd "		if poison <= 0.0:
			poison_stacks = 0" "		if false:
			poison_stacks = 0"
mutate poison-stacks-not-summed           scripts/sim/enemy_conditions.gd "dps += poison_dps * float(poison_stacks)" "dps += poison_dps"
mutate chill-timer-not-refreshed          scripts/sim/enemy_conditions.gd "			chill = ConditionDefs.CHILL_TIME
" "			chill = chill if chill > 0.0 else ConditionDefs.CHILL_TIME
"
mutate chill-stacks-survive-expiry        scripts/sim/enemy_conditions.gd "	if chill <= 0.0:
		chill_stacks = 0" "	if false:
		chill_stacks = 0"
mutate frozen-gains-chill-stacks          scripts/sim/enemy_conditions.gd "			if frozen > 0.0:
				return false" "			if false:
				return false"
mutate freeze-keeps-stacks                scripts/sim/enemy_conditions.gd "				chill_stacks = 0
				frozen =" "				frozen ="
mutate freeze-not-reported                scripts/sim/enemy_conditions.gd "				return true" "				return false"
mutate freeze-ignores-kind                scripts/sim/enemy_conditions.gd "frozen = ConditionDefs.FREEZE_TIME * freeze_factor" "frozen = ConditionDefs.FREEZE_TIME"
mutate ignite-weakens-stronger-burn       scripts/sim/enemy_conditions.gd "burn_dps = maxf(burn_dps if burn > 0.0 else 0.0, source_burn_dps * ConditionDefs.SPREAD_DPS_FACTOR)" "burn_dps = source_burn_dps * ConditionDefs.SPREAD_DPS_FACTOR"
mutate ignite-shortens-longer-burn        scripts/sim/enemy_conditions.gd "burn = maxf(burn, ConditionDefs.BURN_TIME * ConditionDefs.SPREAD_TIME_FACTOR)" "burn = ConditionDefs.BURN_TIME * ConditionDefs.SPREAD_TIME_FACTOR"
mutate dot-fraction-lost                  scripts/sim/enemy_conditions.gd "	dot -= float(whole)" "	dot = 0.0"
mutate dot-rounds-up                      scripts/sim/enemy_conditions.gd "var whole: int = int(dot)" "var whole: int = ceili(dot)"
mutate dot-timer-not-rearmed              scripts/sim/enemy_conditions.gd "	dot_time = ConditionDefs.DOT_PERIOD
	var whole" "	var whole"
mutate dot-accumulator-not-wiped          scripts/sim/enemy_conditions.gd "	if dps <= 0.0:
		dot = 0.0
		return 0" "	if dps <= 0.0:
		return 0"
mutate burn-last-step-lost                scripts/sim/enemy_conditions.gd "		burn -= dt
		dps += burn_dps" "		burn -= dt
		if burn > 0.0:
			dps += burn_dps"
mutate frozen-never-thaws                 scripts/sim/enemy_conditions.gd "	frozen = maxf(0.0, frozen - dt)" "	frozen = maxf(0.0, frozen - dt * 0.0)"
mutate no-frozen-bonus                    scripts/sim/game_run.gd "	var shattered: bool = enemy.conditions.is_frozen()" "	var shattered: bool = false"
mutate frozen-bonus-before-crit           scripts/sim/game_run.gd "	if crit:
		dmg *= CRIT_MULTIPLIER
	var shattered: bool = enemy.conditions.is_frozen()
	if shattered:
		dmg *= ConditionDefs.SHATTER" "	var shattered: bool = enemy.conditions.is_frozen()
	if shattered:
		dmg *= ConditionDefs.SHATTER
	if crit:
		dmg = ceilf(dmg * CRIT_MULTIPLIER)"
mutate frozen-bonus-ends-freeze           scripts/sim/game_run.gd "	if shattered:
		dmg *= ConditionDefs.SHATTER" "	if shattered:
		dmg *= ConditionDefs.SHATTER
		enemy.conditions.frozen = 0.0"
mutate hit-stacks-ignored                 scripts/sim/game_run.gd "afflict(enemy, sword.spec.element, sword.damage, stacks)" "afflict(enemy, sword.spec.element, sword.damage, 1)"
mutate hit-afflicts-with-blow-damage      scripts/sim/game_run.gd "afflict(enemy, sword.spec.element, sword.damage, stacks)" "afflict(enemy, sword.spec.element, raw_damage, stacks)"
mutate killing-blow-afflicts              scripts/sim/game_run.gd "	if enemy.hp <= 0.0:
		kill(enemy, d)
	elif sword != null:
		afflict(enemy, sword.spec.element, sword.damage, stacks)" "	if sword != null:
		afflict(enemy, sword.spec.element, sword.damage, stacks)
	if enemy.hp <= 0.0:
		kill(enemy, d)"
mutate afflict-ignores-fixture-flag       scripts/sim/game_run.gd "	if not scenario.conditions_enabled or enemy.dead:" "	if enemy.dead:"
mutate freeze-cue-lost                    scripts/sim/game_run.gd "		cue.element = ConditionDefs.ICE
		add_cue(cue)" "		cue.element = ConditionDefs.ICE"
mutate freeze-keeps-full-velocity         scripts/sim/game_run.gd "		enemy.velocity *= ConditionDefs.FREEZE_VELOCITY_KEEP
" ""
mutate conditions-not-ticked              scripts/sim/game_run.gd "	_separate()
	_update_conditions(dt)
" "	_separate()
"
mutate conditions-tick-before-enemies     scripts/sim/game_run.gd "	for enemy: EnemyState in enemies:
		enemy.update(self, dt)
	_separate()
	_update_conditions(dt)
" "	_update_conditions(dt)
	for enemy: EnemyState in enemies:
		enemy.update(self, dt)
	_separate()
"
mutate conditions-tick-after-contacts     scripts/sim/game_run.gd "	_update_conditions(dt)
	_resolve_contacts()
" "	_resolve_contacts()
	_update_conditions(dt)
"
mutate conditions-render-rate-dependent   scripts/sim/game_run.gd "	_update_conditions(dt)
	_resolve_contacts()
" "	_update_conditions(dt * (1.0 + float(Engine.get_process_frames() % 2)))
	_resolve_contacts()
"
mutate dot-kill-skips-rewards             scripts/sim/game_run.gd "		if enemy.hp <= 0.0:
			kill(enemy, Vector2.UP)" "		if enemy.hp <= 0.0:
			enemy.dead = true"
mutate dot-ticks-corpses                  scripts/sim/game_run.gd "		if enemy.dead:
			continue
		var dealt: int = enemy.conditions.tick(dt)" "		var dealt: int = enemy.conditions.tick(dt)"
mutate dot-damage-cue-lost                scripts/sim/game_run.gd "		cue.element = enemy.conditions.dominant_element()
		add_cue(cue)" "		cue.element = enemy.conditions.dominant_element()"
mutate dot-cue-wrong-element              scripts/sim/game_run.gd "		cue.element = enemy.conditions.dominant_element()" "		cue.element = ConditionDefs.POISON"
mutate dot-hits-more-than-once            scripts/sim/game_run.gd "		enemy.hp -= float(dealt)
		var cue: SimCue = SimCue.make(SimCue.Kind.CONDITION_DAMAGE" "		enemy.hp -= float(dealt) * 2.0
		var cue: SimCue = SimCue.make(SimCue.Kind.CONDITION_DAMAGE"
mutate burning-death-spreads-nothing      scripts/sim/game_run.gd "	if enemy.conditions.is_burning():
		_spread_fire(enemy)" "	if false:
		_spread_fire(enemy)"
mutate spread-ignites-the-dead            scripts/sim/game_run.gd "	for other: EnemyState in enemies:
		if other != source and not other.dead and" "	for other: EnemyState in enemies:
		if other != source and"
mutate spread-measures-centres            scripts/sim/game_run.gd "source.radius + other.radius + ConditionDefs.SPREAD_REACH" "ConditionDefs.SPREAD_REACH + 30.0"
mutate spread-cue-lost                    scripts/sim/game_run.gd "	cue.element = ConditionDefs.FIRE
	add_cue(cue)" "	cue.element = ConditionDefs.FIRE"
mutate shatter-cue-lost                   scripts/sim/game_run.gd "		add_cue(SimCue.make(SimCue.Kind.ENEMY_SHATTERED, enemy.position))" "		pass"
mutate frozen-hit-cue-untagged            scripts/sim/game_run.gd "		hit_cue.element = ConditionDefs.ICE" "		hit_cue.element = &\"\""
mutate frozen-enemies-hurt-by-contact     scripts/sim/game_run.gd "not enemy.dead and not enemy.conditions.is_frozen() and (enemy.position - position).length()" "not enemy.dead and (enemy.position - position).length()"
mutate frozen-enemy-steers                scripts/sim/enemy_state.gd "	if stun > 0.0 or conditions.frozen > 0.0:" "	if stun > 0.0:"
mutate frozen-enemy-clock-runs            scripts/sim/enemy_state.gd "	if conditions.frozen <= 0.0:
		age += dt" "	age += dt"
mutate chill-does-not-slow                scripts/sim/enemy_state.gd "		if conditions.chill > 0.0:
			want *= ConditionDefs.CHILL_SLOW" "		if false:
			want *= ConditionDefs.CHILL_SLOW"
mutate fixture-flag-does-nothing          scripts/sim/run_scenario.gd "	conditions_enabled = false
	return self" "	return self"
mutate conditions-off-by-default          scripts/sim/run_scenario.gd "var conditions_enabled: bool = true" "var conditions_enabled: bool = false"
mutate conditions-encounter-not-in-cycle            scripts/sim/run_scenario.gd "ENCOUNTER_SPITTERS, ENCOUNTER_CONDITIONS, ENCOUNTER_WARDEN, ENCOUNTER_PIKE]" "ENCOUNTER_SPITTERS, ENCOUNTER_WARDEN, ENCOUNTER_PIKE]"
mutate conditions-encounter-no-brutes     scripts/sim/run_scenario.gd "	&\"brute\", &\"husk\", &\"husk\", &\"runner\", &\"husk\", &\"husk\", &\"brute\", &\"husk\", &\"husk\", &\"runner\", &\"husk\", &\"husk\"," "	&\"husk\", &\"husk\", &\"husk\", &\"runner\", &\"husk\", &\"husk\", &\"husk\", &\"husk\", &\"husk\", &\"runner\", &\"husk\", &\"husk\","
mutate conditions-launch-option-lost      scripts/launch_options.gd "		\"conditions\":
			return RunScenario.conditions_encounter()" "		\"conditions\":
			return null"
mutate conditions-legend-lost             scripts/hud.gd "	elif run.scenario.encounter == RunScenario.ENCOUNTER_CONDITIONS:" "	elif false:"
mutate presenter-drops-conditions         scripts/presentation/run_presenter.gd "		visual.apply_conditions(enemy.conditions.view())
" ""
mutate view-frozen-lost                   scripts/sim/condition_view.gd "	view.frozen = conditions.is_frozen()" "	view.frozen = false"
mutate view-burning-lost                  scripts/sim/condition_view.gd "	view.burning = conditions.is_burning()" "	view.burning = false"
mutate view-poison-lost                   scripts/sim/condition_view.gd "	view.poison_stacks = conditions.poison_stacks if conditions.poison > 0.0 else 0" "	view.poison_stacks = 0"
mutate sword-card-element-lost            scripts/hud.gd "		_ult_elements[slot].text = String(sword.spec.element).to_upper()" "		_ult_elements[slot].text = \"\""
mutate freeze-sound-lost                  scripts/audio/sfx_bank.gd "SimCue.Kind.ENEMY_FROZEN:
			play(\"parry\")" "SimCue.Kind.ENEMY_FROZEN:
			play(\"hit\")"
mutate condition-particles-lost           scripts/presentation/effects_layer.gd "		_add_condition_particles(run, dt)
" ""
mutate freeze-label-lost                  scripts/presentation/effects_layer.gd "\"FROZEN\", element_color(ConditionDefs.ICE)" "\"\", element_color(ConditionDefs.ICE)"
# --- Warden and Maelstrom (slice #13)
mutate warden-key-renamed                           scripts/sim/sword_defs.gd "const WARDEN: StringName = &\"blade\"" "const WARDEN: StringName = &\"warden\""
mutate warden-damage                                scripts/sim/sword_defs.gd "WARDEN_DAMAGE: float = 17.0" "WARDEN_DAMAGE: float = 18.0"
mutate warden-range                                 scripts/sim/sword_defs.gd "WARDEN_RANGE: float = 245.0" "WARDEN_RANGE: float = 300.0"
mutate warden-cooldown                              scripts/sim/sword_defs.gd "WARDEN_COOLDOWN: float = 0.85" "WARDEN_COOLDOWN: float = 0.5"
mutate warden-windup                                scripts/sim/sword_defs.gd "WARDEN_WINDUP: float = 0.16" "WARDEN_WINDUP: float = 0.3"
mutate warden-knockback                             scripts/sim/sword_defs.gd "WARDEN_KNOCK: float = 300.0" "WARDEN_KNOCK: float = 120.0"
mutate warden-hitstop                               scripts/sim/sword_defs.gd "WARDEN_HITSTOP: float = 0.05" "WARDEN_HITSTOP: float = 0.0"
mutate warden-shake                                 scripts/sim/sword_defs.gd "WARDEN_SHAKE: float = 0.16" "WARDEN_SHAKE: float = 0.0"
mutate warden-length                                scripts/sim/sword_defs.gd "WARDEN_LENGTH: float = 54.0" "WARDEN_LENGTH: float = 30.0"
mutate warden-sweep-time                            scripts/sim/sword_defs.gd "WARDEN_SWEEP_TIME: float = 0.15" "WARDEN_SWEEP_TIME: float = 0.3"
mutate warden-sweep-start-angle                     scripts/sim/sword_defs.gd "WARDEN_SWEEP_START: float = 1.9" "WARDEN_SWEEP_START: float = 1.0"
mutate warden-sweep-end-angle                       scripts/sim/sword_defs.gd "WARDEN_SWEEP_END: float = 1.45" "WARDEN_SWEEP_END: float = 0.6"
mutate warden-pivot-back                            scripts/sim/sword_defs.gd "WARDEN_PIVOT_BACK: float = 0.55" "WARDEN_PIVOT_BACK: float = 0.2"
mutate warden-hit-pad                               scripts/sim/sword_defs.gd "WARDEN_HIT_PAD: float = 8.0" "WARDEN_HIT_PAD: float = 2.0"
mutate warden-parry-pad                             scripts/sim/sword_defs.gd "WARDEN_PARRY_PAD: float = 6.0" "WARDEN_PARRY_PAD: float = 0.0"
mutate warden-guard-too-far                         scripts/sim/sword_defs.gd "WARDEN_GUARD: float = 0.12" "WARDEN_GUARD: float = 0.5"
mutate warden-tip-short                             scripts/sim/sword_defs.gd "WARDEN_TIP: float = 1.15" "WARDEN_TIP: float = 0.8"
mutate warden-tangent-weight                        scripts/sim/sword_defs.gd "WARDEN_TANGENT_WEIGHT: float = 0.6" "WARDEN_TANGENT_WEIGHT: float = 0.0"
mutate warden-recover-time                          scripts/sim/sword_defs.gd "WARDEN_RECOVER_TIME: float = 0.3" "WARDEN_RECOVER_TIME: float = 0.6"
mutate warden-recover-speed                         scripts/sim/sword_defs.gd "WARDEN_RECOVER_SPEED: float = 300.0" "WARDEN_RECOVER_SPEED: float = 0.0"
mutate warden-display-name                          scripts/sim/sword_defs.gd "		WARDEN:
			return \"Warden\"" "		WARDEN:
			return \"Blade\""
mutate maelstrom-name                               scripts/sim/sword_defs.gd "WARDEN_ULT_NAME: String = \"Maelstrom\"" "WARDEN_ULT_NAME: String = \"Whirl\""
mutate maelstrom-recharge                           scripts/sim/sword_defs.gd "WARDEN_ULT_COOLDOWN: float = 11.0" "WARDEN_ULT_COOLDOWN: float = 6.0"
mutate maelstrom-range                              scripts/sim/sword_defs.gd "WARDEN_ULT_RANGE: float = 400.0" "WARDEN_ULT_RANGE: float = 250.0"
mutate maelstrom-radius                             scripts/sim/sword_defs.gd "WARDEN_ULT_RADIUS: float = 100.0" "WARDEN_ULT_RADIUS: float = 70.0"
mutate maelstrom-duration                           scripts/sim/sword_defs.gd "WARDEN_ULT_DURATION: float = 2.2" "WARDEN_ULT_DURATION: float = 1.5"
mutate maelstrom-first-beat                         scripts/sim/sword_defs.gd "WARDEN_ULT_FIRST_BEAT: float = 0.15" "WARDEN_ULT_FIRST_BEAT: float = 0.4"
mutate maelstrom-beat-period                        scripts/sim/sword_defs.gd "WARDEN_ULT_BEAT: float = 0.2" "WARDEN_ULT_BEAT: float = 0.3"
mutate maelstrom-spin-rate                          scripts/sim/sword_defs.gd "WARDEN_ULT_SPIN_RATE: float = 15.0" "WARDEN_ULT_SPIN_RATE: float = 8.0"
mutate maelstrom-approach-rate                      scripts/sim/sword_defs.gd "WARDEN_ULT_APPROACH_RATE: float = 25.0" "WARDEN_ULT_APPROACH_RATE: float = 10.0"
mutate maelstrom-reach-tail                         scripts/sim/sword_defs.gd "WARDEN_ULT_REACH_TAIL: float = 0.7" "WARDEN_ULT_REACH_TAIL: float = 0.3"
mutate maelstrom-pull-speed                         scripts/sim/sword_defs.gd "WARDEN_ULT_PULL_SPEED: float = 170.0" "WARDEN_ULT_PULL_SPEED: float = 90.0"
mutate maelstrom-pull-minimum                       scripts/sim/sword_defs.gd "WARDEN_ULT_PULL_MIN: float = 8.0" "WARDEN_ULT_PULL_MIN: float = 30.0"
mutate maelstrom-pull-range                         scripts/sim/sword_defs.gd "WARDEN_ULT_PULL_EXTRA: float = 120.0" "WARDEN_ULT_PULL_EXTRA: float = 40.0"
mutate maelstrom-beat-damage                        scripts/sim/sword_defs.gd "WARDEN_ULT_TICK_FACTOR: float = 0.6" "WARDEN_ULT_TICK_FACTOR: float = 1.0"
mutate maelstrom-beat-knock                         scripts/sim/sword_defs.gd "WARDEN_ULT_TICK_KNOCK: float = 40.0" "WARDEN_ULT_TICK_KNOCK: float = 200.0"
mutate maelstrom-beat-shake                         scripts/sim/sword_defs.gd "WARDEN_ULT_TICK_SHAKE: float = 0.08" "WARDEN_ULT_TICK_SHAKE: float = 0.3"
mutate maelstrom-burst-damage                       scripts/sim/sword_defs.gd "WARDEN_ULT_BURST_FACTOR: float = 1.6" "WARDEN_ULT_BURST_FACTOR: float = 1.0"
mutate maelstrom-burst-knock                        scripts/sim/sword_defs.gd "WARDEN_ULT_BURST_KNOCK: float = 520.0" "WARDEN_ULT_BURST_KNOCK: float = 200.0"
mutate maelstrom-burst-margin                       scripts/sim/sword_defs.gd "WARDEN_ULT_BURST_MARGIN: float = 30.0" "WARDEN_ULT_BURST_MARGIN: float = 0.0"
mutate maelstrom-burst-one-dose                     scripts/sim/sword_defs.gd "WARDEN_ULT_BURST_STACKS: int = 2" "WARDEN_ULT_BURST_STACKS: int = 1"
mutate maelstrom-burst-shake                        scripts/sim/sword_defs.gd "WARDEN_ULT_BURST_SHAKE: float = 0.35" "WARDEN_ULT_BURST_SHAKE: float = 0.05"
mutate maelstrom-burst-hitstop                      scripts/sim/sword_defs.gd "WARDEN_ULT_BURST_HITSTOP: float = 0.06" "WARDEN_ULT_BURST_HITSTOP: float = 0.0"
mutate maelstrom-recover-time                       scripts/sim/sword_defs.gd "WARDEN_ULT_RECOVER_TIME: float = 0.3" "WARDEN_ULT_RECOVER_TIME: float = 0.1"
mutate maelstrom-recover-speed                      scripts/sim/sword_defs.gd "WARDEN_ULT_RECOVER_SPEED: float = 500.0" "WARDEN_ULT_RECOVER_SPEED: float = 100.0"
mutate sweep-hits-twice                             scripts/sim/sword_state.gd "			if sweep_hits.has(enemy):
				continue" "			if false:
				continue"
mutate sweep-hit-set-kept-between-attacks           scripts/sim/sword_state.gd "	timer = windup
	sweep_hits.clear()
	side = -side" "	timer = windup
	side = -side"
mutate sweep-never-alternates                       scripts/sim/sword_state.gd "	timer = windup
	sweep_hits.clear()
	side = -side" "	timer = windup
	sweep_hits.clear()
	side = side"
mutate sweep-no-parry                               scripts/sim/sword_state.gd "		run.parry_projectiles(guard, tip, SwordDefs.WARDEN_PARRY_PAD)
" "		pass
"
mutate sweep-parry-only-without-a-hit               scripts/sim/sword_state.gd "		run.parry_projectiles(guard, tip, SwordDefs.WARDEN_PARRY_PAD)
" "		if sweep_hits.is_empty():
			run.parry_projectiles(guard, tip, SwordDefs.WARDEN_PARRY_PAD)
"
mutate sweep-end-sample-only                        scripts/sim/sword_state.gd "	for sample: float in [lerpf(previous_angle, swung, 0.5), swung]:" "	for sample: float in [swung]:"
mutate sweep-ignores-boost                          scripts/sim/sword_state.gd "run.hit_enemy(enemy, damage * boost, tangent * SwordDefs.WARDEN_TANGENT_WEIGHT + away, knock, self)" "run.hit_enemy(enemy, damage, tangent * SwordDefs.WARDEN_TANGENT_WEIGHT + away, knock, self)"
mutate sweep-hit-is-heavy                           scripts/sim/sword_state.gd "tangent * SwordDefs.WARDEN_TANGENT_WEIGHT + away, knock, self)" "tangent * SwordDefs.WARDEN_TANGENT_WEIGHT + away, knock, self, true)"
mutate sweep-linear-easing                          scripts/sim/sim_math.gd "	return 1.0 - pow(1.0 - t, 3.0)" "	return t"
mutate sweep-wrong-direction                        scripts/sim/sword_state.gd "	sweep_from = amid - float(side) * SwordDefs.WARDEN_SWEEP_START
	sweep_to = amid + float(side) * SwordDefs.WARDEN_SWEEP_END" "	sweep_from = amid + float(side) * SwordDefs.WARDEN_SWEEP_START
	sweep_to = amid - float(side) * SwordDefs.WARDEN_SWEEP_END"
mutate sweep-pivot-ignores-length                   scripts/sim/sword_state.gd "	sweep_pivot = aim - to_aim * (length * SwordDefs.WARDEN_PIVOT_BACK)" "	sweep_pivot = aim - to_aim * (SwordDefs.WARDEN_LENGTH * SwordDefs.WARDEN_PIVOT_BACK)"
mutate sweep-never-ends                             scripts/sim/sword_state.gd "	if timer <= 0.0:
		phase = Phase.RECOVER
		timer = SwordDefs.WARDEN_RECOVER_TIME" "	if false:
		phase = Phase.RECOVER
		timer = SwordDefs.WARDEN_RECOVER_TIME"
mutate sweep-recovery-lost                          scripts/sim/sword_state.gd "		velocity = SimMath.polar(swung + float(side) * PI * 0.5, SwordDefs.WARDEN_RECOVER_SPEED)" "		velocity = Vector2.ZERO"
mutate sweep-windup-not-following                   scripts/sim/sword_state.gd "	sweep_pivot = aim - to_aim * (length * SwordDefs.WARDEN_PIVOT_BACK)
	var amid: float" "	if sweep_pivot == Vector2.ZERO:
		sweep_pivot = aim - to_aim * (length * SwordDefs.WARDEN_PIVOT_BACK)
	var amid: float"
mutate sweep-cue-lost                               scripts/sim/sword_state.gd "	run.add_cue(SimCue.make(SimCue.Kind.SWORD_STRIKE, position, dir))


## Warden's windup" "	pass


## Warden's windup"
mutate warden-uses-fang-damage                      scripts/sim/sword_state.gd "	sword.damage = SwordDefs.base_damage(type_id) * SwordDefs.RARITY_DAMAGE[rarity]" "	sword.damage = SwordDefs.FANG_DAMAGE * SwordDefs.RARITY_DAMAGE[rarity]"
mutate warden-uses-fang-range                       scripts/sim/sword_state.gd "	sword.attack_range = SwordDefs.base_range(type_id) * SwordDefs.RARITY_RANGE[rarity]" "	sword.attack_range = SwordDefs.FANG_RANGE * SwordDefs.RARITY_RANGE[rarity]"
mutate warden-uses-fang-cooldown                    scripts/sim/sword_state.gd "	sword.cooldown = SwordDefs.base_cooldown(type_id) * SwordDefs.RARITY_COOLDOWN[rarity]" "	sword.cooldown = SwordDefs.FANG_COOLDOWN * SwordDefs.RARITY_COOLDOWN[rarity]"
mutate warden-uses-fang-knockback                   scripts/sim/sword_state.gd "	sword.knock = SwordDefs.base_knock(type_id)" "	sword.knock = SwordDefs.FANG_KNOCK"
mutate warden-rarity-size-lost                      scripts/sim/sword_state.gd "	sword.size_scale = SwordDefs.RARITY_SIZE[rarity]" "	sword.size_scale = 1.0"
mutate warden-rarity-recharge-lost                  scripts/sim/sword_state.gd "	sword.ultimate_cooldown = SwordDefs.ultimate_cooldown(spec_value.type_id) * SwordDefs.RARITY_COOLDOWN[rarity]" "	sword.ultimate_cooldown = SwordDefs.ultimate_cooldown(spec_value.type_id)"
mutate hit-stop-always-fang                         scripts/sim/game_run.gd "(sword.hit_stop if sword != null else SwordDefs.FANG_HITSTOP) * (CRIT_HITSTOP_FACTOR" "SwordDefs.FANG_HITSTOP * (CRIT_HITSTOP_FACTOR"
mutate hit-shake-always-fang                        scripts/sim/game_run.gd "add_shake((sword.hit_shake if sword != null else SwordDefs.FANG_SHAKE) + (CRIT_SHAKE_BONUS" "add_shake(SwordDefs.FANG_SHAKE + (CRIT_SHAKE_BONUS"
mutate maelstrom-blinks-like-flurry                 scripts/sim/sword_state.gd "			ultimate_spin = atan2(position.y - point.y, position.x - point.x)" "			position = point
			ultimate_spin = atan2(position.y - point.y, position.x - point.x)"
mutate maelstrom-spin-starts-at-zero                scripts/sim/sword_state.gd "			ultimate_spin = atan2(position.y - point.y, position.x - point.x)" "			ultimate_spin = 0.0"
mutate maelstrom-spins-backwards                    scripts/sim/sword_state.gd "	ultimate_spin += dt * SwordDefs.WARDEN_ULT_SPIN_RATE" "	ultimate_spin -= dt * SwordDefs.WARDEN_ULT_SPIN_RATE"
mutate maelstrom-no-pull                            scripts/sim/sword_state.gd "			enemy.position += to_centre / dist * SwordDefs.WARDEN_ULT_PULL_SPEED * enemy.knock_mult * dt" "			enemy.position += Vector2.ZERO"
mutate maelstrom-pull-ignores-knock-factor          scripts/sim/sword_state.gd "SwordDefs.WARDEN_ULT_PULL_SPEED * enemy.knock_mult * dt" "SwordDefs.WARDEN_ULT_PULL_SPEED * dt"
mutate maelstrom-pulls-from-everywhere              scripts/sim/sword_state.gd "if SwordDefs.WARDEN_ULT_PULL_MIN < dist and dist < maelstrom_pull_range():" "if SwordDefs.WARDEN_ULT_PULL_MIN < dist:"
mutate maelstrom-pull-skips-corpses                 scripts/sim/sword_state.gd "	for enemy: EnemyState in run.enemies:
		var to_centre" "	for enemy: EnemyState in run.enemies:
		if enemy.dead:
			continue
		var to_centre"
mutate maelstrom-beat-skips-corpses                 scripts/sim/sword_state.gd "		for enemy: EnemyState in run.enemies:
			var off: Vector2 = enemy.position - centre
			if off.length() < reach + enemy.radius:" "		for enemy: EnemyState in run.enemies:
			if enemy.dead:
				continue
			var off: Vector2 = enemy.position - centre
			if off.length() < reach + enemy.radius:"
mutate maelstrom-beat-reach-ignores-radius          scripts/sim/sword_state.gd "			if off.length() < reach + enemy.radius:
				run.hit_enemy(enemy, damage * SwordDefs.WARDEN_ULT_TICK_FACTOR" "			if off.length() < reach:
				run.hit_enemy(enemy, damage * SwordDefs.WARDEN_ULT_TICK_FACTOR"
mutate maelstrom-beat-is-normal-hit                 scripts/sim/sword_state.gd "Vector2(-off.y, off.x), SwordDefs.WARDEN_ULT_TICK_KNOCK, self, true)" "Vector2(-off.y, off.x), SwordDefs.WARDEN_ULT_TICK_KNOCK, self, false)"
mutate maelstrom-beat-pushes-the-wrong-way          scripts/sim/sword_state.gd "Vector2(-off.y, off.x), SwordDefs.WARDEN_ULT_TICK_KNOCK" "Vector2(off.y, -off.x), SwordDefs.WARDEN_ULT_TICK_KNOCK"
mutate maelstrom-beat-shakes-without-a-hit          scripts/sim/sword_state.gd "		if struck > 0:
			run.add_shake(SwordDefs.WARDEN_ULT_TICK_SHAKE)" "		run.add_shake(SwordDefs.WARDEN_ULT_TICK_SHAKE)"
mutate maelstrom-burst-never-comes                  scripts/sim/sword_state.gd "	if ultimate_time_left <= 0.0:
		var caught: int = 0" "	if false:
		var caught: int = 0"
mutate maelstrom-burst-skips-corpses                scripts/sim/sword_state.gd "		for enemy: EnemyState in run.enemies:
			var off: Vector2 = enemy.position - centre
			if off.length() < burst_reach + enemy.radius:" "		for enemy: EnemyState in run.enemies:
			if enemy.dead:
				continue
			var off: Vector2 = enemy.position - centre
			if off.length() < burst_reach + enemy.radius:"
mutate maelstrom-burst-is-normal-hit                scripts/sim/sword_state.gd "off, SwordDefs.WARDEN_ULT_BURST_KNOCK, self, true, SwordDefs.WARDEN_ULT_BURST_STACKS)" "off, SwordDefs.WARDEN_ULT_BURST_KNOCK, self, false, SwordDefs.WARDEN_ULT_BURST_STACKS)"
mutate maelstrom-burst-no-recovery                  scripts/sim/sword_state.gd "		phase = Phase.RECOVER
		timer = SwordDefs.WARDEN_ULT_RECOVER_TIME" "		phase = Phase.IDLE
		timer = SwordDefs.WARDEN_ULT_RECOVER_TIME"
mutate maelstrom-burst-cue-lost                     scripts/sim/sword_state.gd "	cue.element = spec.element
	run.add_cue(cue)" "	cue.element = spec.element"
mutate maelstrom-reach-ignores-rarity-size          scripts/sim/sword_state.gd "	return SwordDefs.WARDEN_ULT_RADIUS * size_scale" "	return SwordDefs.WARDEN_ULT_RADIUS"
mutate maelstrom-reach-without-the-blade            scripts/sim/sword_state.gd "	return maelstrom_radius() + length * SwordDefs.WARDEN_ULT_REACH_TAIL" "	return maelstrom_radius()"
mutate maelstrom-keeps-the-old-hit-set              scripts/sim/sword_state.gd "	ultimate_point = point
	sweep_hits.clear()
	skewer_carried.clear()" "	ultimate_point = point
	skewer_carried.clear()"
mutate maelstrom-area-radius-is-flurry-radius       scripts/sim/sword_state.gd "		SwordDefs.WARDEN:
			return maelstrom_reach()" "		SwordDefs.WARDEN:
			return SwordDefs.FANG_ULT_RADIUS"
mutate warden-encounter-not-in-cycle                scripts/sim/run_scenario.gd "ENCOUNTER_CONDITIONS, ENCOUNTER_WARDEN, ENCOUNTER_PIKE]" "ENCOUNTER_CONDITIONS, ENCOUNTER_PIKE]"
mutate warden-encounter-slot-lost                   scripts/sim/game_run.gd "		scenario if scenario.encounter == RunScenario.ENCOUNTER_WARDEN else RunScenario.warden_encounter(),
" "		RunScenario.new(),
"
mutate warden-fixture-has-no-wardens                scripts/sim/run_scenario.gd "	specs.append(SwordSpec.make(SwordDefs.WARDEN, 0, &\"ice\"))" "	specs.append(SwordSpec.make(&\"fang\", 0, &\"ice\"))"
mutate warden-fixture-wrong-element                 scripts/sim/run_scenario.gd "	specs.append(SwordSpec.make(SwordDefs.WARDEN, 0, &\"fire\"))" "	specs.append(SwordSpec.make(SwordDefs.WARDEN, 0, &\"ice\"))"
mutate warden-encounter-no-brutes                   scripts/sim/run_scenario.gd "&\"husk\", &\"husk\", &\"runner\", &\"husk\", &\"brute\", &\"husk\", &\"runner\", &\"husk\", &\"husk\", &\"runner\", &\"brute\", &\"husk\", &\"husk\", &\"runner\"," "&\"husk\", &\"husk\", &\"runner\", &\"husk\", &\"husk\", &\"husk\", &\"runner\", &\"husk\", &\"husk\", &\"runner\", &\"husk\", &\"husk\", &\"husk\", &\"runner\","
mutate warden-encounter-not-the-default             scripts/sim/run_scenario.gd "var loadout: Array[SwordSpec] = RunScenario.fang_fixture_loadout()" "var loadout: Array[SwordSpec] = RunScenario.warden_fixture_loadout()"
mutate warden-launch-option-lost                    scripts/launch_options.gd "		\"warden\":
			return RunScenario.warden_encounter()" "		\"warden\":
			return null"
mutate warden-dev-button-title                      scripts/sim/run_scenario.gd "		ENCOUNTER_WARDEN:
			return \"Warden\"
" ""
mutate warden-legend-lost                           scripts/hud.gd "	elif run.scenario.encounter == RunScenario.ENCOUNTER_WARDEN:" "	elif false:"
mutate sword-card-type-lost                         scripts/hud.gd "		_ult_types[slot].text = \"%s sword%s\" % [SwordDefs.display_name(sword.spec.type_id), \"  skill shot\" if SwordDefs.ultimate_is_shot(sword.spec.type_id) else \"\"]" "		_ult_types[slot].text = \"\""
mutate sword-card-name-always-flurry                scripts/sim/sword_defs.gd "			return WARDEN_ULT_NAME" "			return FANG_ULT_NAME"
mutate sweep-fan-lost                               scripts/presentation/effects_layer.gd "		_add_sweep_wedges(run)
" ""
mutate sweep-telegraph-lost                         scripts/presentation/effects_layer.gd "			_draw_sweep_telegraph(sword)
" "			pass
"
mutate maelstrom-drawing-lost                       scripts/presentation/effects_layer.gd "				_draw_maelstrom(sword, tint)
" "				pass
"
mutate maelstrom-beat-ring-lost                     scripts/presentation/effects_layer.gd "			_add_ring(cue.position, cue.radius * 0.6, cue.radius, 0.2, Color(beat_tint, 0.9), 2.0)
" "			pass
"
mutate maelstrom-burst-ring-lost                    scripts/presentation/effects_layer.gd "			_add_ring(cue.position, 20.0, cue.radius * 1.6, 0.4, Color(burst_tint, 0.95), 5.0)
" "			pass
"
mutate maelstrom-area-ring-wrong-size               scripts/presentation/effects_layer.gd "	_add_ring(sword.ultimate_point, sword.ultimate_area_radius(), 10.0, 0.3, Color(tint, 0.95), 3.0)" "	_add_ring(sword.ultimate_point, SwordDefs.FANG_ULT_RADIUS, 10.0, 0.3, Color(tint, 0.95), 3.0)"
mutate maelstrom-burst-sound-lost                   scripts/audio/sfx_bank.gd "		SimCue.Kind.MAELSTROM_BURST:
			play(\"strike\")" "		SimCue.Kind.MAELSTROM_BURST:
			pass"
mutate maelstrom-beat-sound-always                  scripts/audio/sfx_bank.gd "			if cue.amount > 0:
				play(\"strike\")" "			play(\"strike\")"
mutate warden-visual-needle                         scripts/presentation/placeholder_sword_visual.gd "	_warden = spec.type_id == SwordDefs.WARDEN" "	_warden = false"
# --- Pike and Skewer (slice #14)
mutate pike-key-renamed                             scripts/sim/sword_defs.gd "const PIKE: StringName = &\"lance\"" "const PIKE: StringName = &\"pike\""
mutate pike-display-name                            scripts/sim/sword_defs.gd "		PIKE:
			return \"Pike\"" "		PIKE:
			return \"Lance\""
mutate pike-length                                  scripts/sim/sword_defs.gd "PIKE_LENGTH: float = 74.0" "PIKE_LENGTH: float = 60.0"
mutate pike-range                                   scripts/sim/sword_defs.gd "PIKE_RANGE: float = 430.0" "PIKE_RANGE: float = 380.0"
mutate pike-cooldown                                scripts/sim/sword_defs.gd "PIKE_COOLDOWN: float = 1.35" "PIKE_COOLDOWN: float = 1.0"
mutate pike-damage                                  scripts/sim/sword_defs.gd "PIKE_DAMAGE: float = 24.0" "PIKE_DAMAGE: float = 25.0"
mutate pike-knockback                               scripts/sim/sword_defs.gd "PIKE_KNOCK: float = 380.0" "PIKE_KNOCK: float = 300.0"
mutate pike-windup                                  scripts/sim/sword_defs.gd "PIKE_WINDUP: float = 0.32" "PIKE_WINDUP: float = 0.2"
mutate pike-thrust-speed                            scripts/sim/sword_defs.gd "PIKE_SPEED: float = 2400.0" "PIKE_SPEED: float = 2000.0"
mutate pike-hitstop                                 scripts/sim/sword_defs.gd "PIKE_HITSTOP: float = 0.06" "PIKE_HITSTOP: float = 0.0"
mutate pike-shake                                   scripts/sim/sword_defs.gd "PIKE_SHAKE: float = 0.2" "PIKE_SHAKE: float = 0.0"
mutate pike-far-minimum                             scripts/sim/sword_defs.gd "PIKE_FAR_MIN: float = 130.0" "PIKE_FAR_MIN: float = 100.0"
mutate pike-windup-standoff-length                  scripts/sim/sword_defs.gd "PIKE_WINDUP_STANDOFF_LENGTH: float = 0.5" "PIKE_WINDUP_STANDOFF_LENGTH: float = 1.0"
mutate pike-windup-standoff-extra                   scripts/sim/sword_defs.gd "PIKE_WINDUP_STANDOFF_EXTRA: float = 120.0" "PIKE_WINDUP_STANDOFF_EXTRA: float = 80.0"
mutate pike-windup-spring                           scripts/sim/sword_defs.gd "PIKE_WINDUP_SPRING_K: float = 150.0" "PIKE_WINDUP_SPRING_K: float = 100.0"
mutate pike-windup-damping                          scripts/sim/sword_defs.gd "PIKE_WINDUP_SPRING_C: float = 20.0" "PIKE_WINDUP_SPRING_C: float = 12.0"
mutate pike-windup-turn-rate                        scripts/sim/sword_defs.gd "PIKE_WINDUP_TURN_RATE: float = 16.0" "PIKE_WINDUP_TURN_RATE: float = 8.0"
mutate pike-overshoot                               scripts/sim/sword_defs.gd "PIKE_STRIKE_OVERSHOOT: float = 170.0" "PIKE_STRIKE_OVERSHOOT: float = 120.0"
mutate pike-tail-fraction                           scripts/sim/sword_defs.gd "PIKE_TAIL_FRACTION: float = 0.3" "PIKE_TAIL_FRACTION: float = 0.0"
mutate pike-tip-fraction                            scripts/sim/sword_defs.gd "PIKE_TIP_FRACTION: float = 0.65" "PIKE_TIP_FRACTION: float = 0.4"
mutate pike-hit-pad                                 scripts/sim/sword_defs.gd "PIKE_HIT_PAD: float = 7.0" "PIKE_HIT_PAD: float = 2.0"
mutate pike-parry-pad                               scripts/sim/sword_defs.gd "PIKE_PARRY_PAD: float = 8.0" "PIKE_PARRY_PAD: float = 4.0"
mutate pike-recover-time                            scripts/sim/sword_defs.gd "PIKE_RECOVER_TIME: float = 0.35" "PIKE_RECOVER_TIME: float = 0.2"
mutate pike-recover-speed                           scripts/sim/sword_defs.gd "PIKE_RECOVER_SPEED: float = 420.0" "PIKE_RECOVER_SPEED: float = 200.0"
mutate skewer-name                                  scripts/sim/sword_defs.gd "PIKE_ULT_NAME: String = \"Skewer\"" "PIKE_ULT_NAME: String = \"Impale\""
mutate skewer-recharge                              scripts/sim/sword_defs.gd "PIKE_ULT_COOLDOWN: float = 10.0" "PIKE_ULT_COOLDOWN: float = 8.0"
mutate skewer-range                                 scripts/sim/sword_defs.gd "PIKE_ULT_RANGE: float = 950.0" "PIKE_ULT_RANGE: float = 800.0"
mutate skewer-speed                                 scripts/sim/sword_defs.gd "PIKE_ULT_SPEED: float = 2600.0" "PIKE_ULT_SPEED: float = 2200.0"
mutate skewer-aim-time                              scripts/sim/sword_defs.gd "PIKE_ULT_AIM_TIME: float = 0.38" "PIKE_ULT_AIM_TIME: float = 0.2"
mutate skewer-aim-standoff                          scripts/sim/sword_defs.gd "PIKE_ULT_AIM_STANDOFF: float = 40.0" "PIKE_ULT_AIM_STANDOFF: float = 20.0"
mutate skewer-aim-spring                            scripts/sim/sword_defs.gd "PIKE_ULT_AIM_SPRING_K: float = 200.0" "PIKE_ULT_AIM_SPRING_K: float = 100.0"
mutate skewer-aim-damping                           scripts/sim/sword_defs.gd "PIKE_ULT_AIM_SPRING_C: float = 24.0" "PIKE_ULT_AIM_SPRING_C: float = 14.0"
mutate skewer-launch-ahead                          scripts/sim/sword_defs.gd "PIKE_ULT_LAUNCH_AHEAD: float = 10.0" "PIKE_ULT_LAUNCH_AHEAD: float = 40.0"
mutate skewer-launch-shake                          scripts/sim/sword_defs.gd "PIKE_ULT_LAUNCH_SHAKE: float = 0.2" "PIKE_ULT_LAUNCH_SHAKE: float = 0.4"
mutate skewer-tail-fraction                         scripts/sim/sword_defs.gd "PIKE_ULT_TAIL_FRACTION: float = 0.3" "PIKE_ULT_TAIL_FRACTION: float = 0.0"
mutate skewer-tip-fraction                          scripts/sim/sword_defs.gd "PIKE_ULT_TIP_FRACTION: float = 0.65" "PIKE_ULT_TIP_FRACTION: float = 0.4"
mutate skewer-hit-pad                               scripts/sim/sword_defs.gd "PIKE_ULT_HIT_PAD: float = 18.0" "PIKE_ULT_HIT_PAD: float = 7.0"
mutate skewer-damage-factor                         scripts/sim/sword_defs.gd "PIKE_ULT_DAMAGE_FACTOR: float = 2.2" "PIKE_ULT_DAMAGE_FACTOR: float = 1.0"
mutate skewer-doses                                 scripts/sim/sword_defs.gd "PIKE_ULT_STACKS: int = 2" "PIKE_ULT_STACKS: int = 1"
mutate skewer-hit-shake                             scripts/sim/sword_defs.gd "PIKE_ULT_HIT_SHAKE: float = 0.12" "PIKE_ULT_HIT_SHAKE: float = 0.0"
mutate skewer-carry-stun                            scripts/sim/sword_defs.gd "PIKE_ULT_CARRY_STUN: float = 0.5" "PIKE_ULT_CARRY_STUN: float = 0.1"
mutate skewer-parry-pad                             scripts/sim/sword_defs.gd "PIKE_ULT_PARRY_PAD: float = 14.0" "PIKE_ULT_PARRY_PAD: float = 8.0"
mutate skewer-wall-margin-too-wide                  scripts/sim/sword_defs.gd "PIKE_ULT_WALL_MARGIN: float = 10.0" "PIKE_ULT_WALL_MARGIN: float = 20.0"
mutate skewer-wall-margin-none                      scripts/sim/sword_defs.gd "PIKE_ULT_WALL_MARGIN: float = 10.0" "PIKE_ULT_WALL_MARGIN: float = 0.0"
mutate skewer-release-speed-range                   scripts/sim/sword_defs.gd "PIKE_ULT_RELEASE_SPEED_RANGE: float = 750.0" "PIKE_ULT_RELEASE_SPEED_RANGE: float = 500.0"
mutate skewer-release-speed-wall                    scripts/sim/sword_defs.gd "PIKE_ULT_RELEASE_SPEED_WALL: float = 1100.0" "PIKE_ULT_RELEASE_SPEED_WALL: float = 900.0"
mutate skewer-release-stun                          scripts/sim/sword_defs.gd "PIKE_ULT_RELEASE_STUN: float = 0.6" "PIKE_ULT_RELEASE_STUN: float = 0.3"
mutate skewer-recover-time                          scripts/sim/sword_defs.gd "PIKE_ULT_RECOVER_TIME: float = 0.35" "PIKE_ULT_RECOVER_TIME: float = 0.6"
mutate skewer-recover-speed-range                   scripts/sim/sword_defs.gd "PIKE_ULT_RECOVER_SPEED_RANGE: float = 420.0" "PIKE_ULT_RECOVER_SPEED_RANGE: float = 100.0"
mutate skewer-recover-speed-wall                    scripts/sim/sword_defs.gd "PIKE_ULT_RECOVER_SPEED_WALL: float = 300.0" "PIKE_ULT_RECOVER_SPEED_WALL: float = 600.0"
mutate skewer-is-clamped-like-an-area-ultimate      scripts/sim/sword_defs.gd "static func ultimate_is_shot(type_id: StringName) -> bool:
	return type_id == PIKE" "static func ultimate_is_shot(type_id: StringName) -> bool:
	return false"
mutate skewer-point-collapses-to-the-player          scripts/sim/game_run.gd "	var target: Vector2 = point" "	var target: Vector2 = position"
mutate pike-far-preference-lost                     scripts/sim/sword_state.gd "				prefer_far = true" "				prefer_far = false"
mutate pike-far-boundary-inclusive                  scripts/sim/sword_state.gd "and far > SwordDefs.PIKE_FAR_MIN:" "and far >= SwordDefs.PIKE_FAR_MIN:"
mutate pike-far-filter-keeps-the-boundary           scripts/sim/sword_state.gd "if prefer_far and dist <= SwordDefs.PIKE_FAR_MIN:" "if prefer_far and dist < SwordDefs.PIKE_FAR_MIN:"
mutate pike-far-preference-picks-farthest           scripts/sim/sword_state.gd "		if dist < attack_range + enemy.radius and dist < best_dist:
			best = enemy
			best_dist = dist" "		if dist < attack_range + enemy.radius and (dist < best_dist or (prefer_far and dist > best_dist)):
			best = enemy
			best_dist = dist"
mutate pike-far-preference-ignores-range            scripts/sim/sword_state.gd "if far < attack_range + enemy.radius and far > SwordDefs.PIKE_FAR_MIN:" "if far > SwordDefs.PIKE_FAR_MIN:"
mutate pike-windup-aims-from-the-sword              scripts/sim/sword_state.gd "_spring(aim - to_aim * (length * SwordDefs.PIKE_WINDUP_STANDOFF_LENGTH" "_spring(aim - (aim - position).normalized() * (length * SwordDefs.PIKE_WINDUP_STANDOFF_LENGTH"
mutate pike-strike-line-from-the-player             scripts/sim/sword_state.gd "			dir = SimMath.norm(aim - position, run.rng)
			timer = ((aim - position).length() + SwordDefs.PIKE_STRIKE_OVERSHOOT)" "			dir = SimMath.norm(aim - run.position, run.rng)
			timer = ((aim - position).length() + SwordDefs.PIKE_STRIKE_OVERSHOOT)"
mutate pike-strike-ignores-the-distance             scripts/sim/sword_state.gd "timer = ((aim - position).length() + SwordDefs.PIKE_STRIKE_OVERSHOOT) / SwordDefs.PIKE_SPEED" "timer = (300.0 + SwordDefs.PIKE_STRIKE_OVERSHOOT) / SwordDefs.PIKE_SPEED"
mutate pike-thrust-hit-set-lost                     scripts/sim/sword_state.gd "			sweep_hits[enemy] = true
			run.hit_enemy(enemy, damage * boost, dir, knock, self)
	run.parry_projectiles(tail, tip, SwordDefs.PIKE_PARRY_PAD)" "			run.hit_enemy(enemy, damage * boost, dir, knock, self)
	run.parry_projectiles(tail, tip, SwordDefs.PIKE_PARRY_PAD)"
mutate pike-thrust-stops-at-the-first-hit           scripts/sim/sword_state.gd "			run.hit_enemy(enemy, damage * boost, dir, knock, self)
	run.parry_projectiles(tail, tip, SwordDefs.PIKE_PARRY_PAD)" "			run.hit_enemy(enemy, damage * boost, dir, knock, self)
			timer = 0.0
			break
	run.parry_projectiles(tail, tip, SwordDefs.PIKE_PARRY_PAD)"
mutate pike-thrust-only-sweeps-the-end              scripts/sim/sword_state.gd "var tail: Vector2 = previous - dir * length * SwordDefs.PIKE_TAIL_FRACTION" "var tail: Vector2 = position - dir * length * SwordDefs.PIKE_TAIL_FRACTION"
mutate pike-thrust-parry-lost                       scripts/sim/sword_state.gd "	run.parry_projectiles(tail, tip, SwordDefs.PIKE_PARRY_PAD)
" ""
mutate pike-thrust-parry-only-without-a-hit         scripts/sim/sword_state.gd "	run.parry_projectiles(tail, tip, SwordDefs.PIKE_PARRY_PAD)
" "	if sweep_hits.is_empty():
		run.parry_projectiles(tail, tip, SwordDefs.PIKE_PARRY_PAD)
"
mutate pike-thrust-ignores-the-boost                scripts/sim/sword_state.gd "run.hit_enemy(enemy, damage * boost, dir, knock, self)
	run.parry_projectiles(tail, tip, SwordDefs.PIKE_PARRY_PAD)" "run.hit_enemy(enemy, damage, dir, knock, self)
	run.parry_projectiles(tail, tip, SwordDefs.PIKE_PARRY_PAD)"
mutate pike-thrust-no-knockback                     scripts/sim/sword_state.gd "run.hit_enemy(enemy, damage * boost, dir, knock, self)
	run.parry_projectiles(tail, tip, SwordDefs.PIKE_PARRY_PAD)" "run.hit_enemy(enemy, damage * boost, dir, 0.0, self)
	run.parry_projectiles(tail, tip, SwordDefs.PIKE_PARRY_PAD)"
mutate pike-thrust-recovery-lost                    scripts/sim/sword_state.gd "		velocity = dir * SwordDefs.PIKE_RECOVER_SPEED
" "		velocity = Vector2.ZERO
"
mutate pike-thrust-never-ends                       scripts/sim/sword_state.gd "	if timer <= 0.0:
		phase = Phase.RECOVER
		timer = SwordDefs.PIKE_RECOVER_TIME" "	if timer <= -9.0:
		phase = Phase.RECOVER
		timer = SwordDefs.PIKE_RECOVER_TIME"
mutate skewer-heading-from-the-sword                scripts/sim/sword_state.gd "dir = SimMath.norm(point - run.position, run.rng, run.facing, true)" "dir = SimMath.norm(point - position, run.rng, run.facing, true)"
mutate skewer-heading-without-the-facing-fallback   scripts/sim/sword_state.gd "dir = SimMath.norm(point - run.position, run.rng, run.facing, true)" "dir = SimMath.norm(point - run.position, run.rng, Vector2.RIGHT, true)"
mutate skewer-aim-clock-not-started                 scripts/sim/sword_state.gd "			ultimate_time_left = SwordDefs.PIKE_ULT_AIM_TIME


func begin(" "			ultimate_time_left = 0.0


func begin("
mutate skewer-restart-keeps-flying                  scripts/sim/sword_state.gd "	skewer_carried.clear()
	skewer_flying = false
	match spec.type_id:" "	skewer_carried.clear()
	match spec.type_id:"
mutate skewer-aim-sword-turns-slowly                scripts/sim/sword_state.gd "		angle = atan2(dir.y, dir.x)
		if ultimate_time_left <= 0.0:" "		angle = SimMath.ang_lerp(angle, atan2(dir.y, dir.x), 0.1)
		if ultimate_time_left <= 0.0:"
mutate skewer-launches-from-the-sword               scripts/sim/sword_state.gd "position = run.position + dir * SwordDefs.PIKE_ULT_LAUNCH_AHEAD" "position = position + dir * SwordDefs.PIKE_ULT_LAUNCH_AHEAD"
mutate skewer-flight-time-not-from-range            scripts/sim/sword_state.gd "ultimate_time_left = SwordDefs.PIKE_ULT_RANGE / SwordDefs.PIKE_ULT_SPEED" "ultimate_time_left = 0.5"
mutate skewer-launch-shake-lost                     scripts/sim/sword_state.gd "			run.add_shake(SwordDefs.PIKE_ULT_LAUNCH_SHAKE, dir, true)
" ""
mutate skewer-launch-cue-lost                       scripts/sim/sword_state.gd "			run.add_cue(SimCue.make(SimCue.Kind.SKEWER_LAUNCHED, position, dir))
" ""
mutate skewer-flight-step-wrong                     scripts/sim/sword_state.gd "var step: Vector2 = dir * SwordDefs.PIKE_ULT_SPEED * dt" "var step: Vector2 = dir * SwordDefs.PIKE_ULT_SPEED * 0.02"
mutate skewer-only-sweeps-the-end                   scripts/sim/sword_state.gd "var tail: Vector2 = previous - dir * length * SwordDefs.PIKE_ULT_TAIL_FRACTION" "var tail: Vector2 = position - dir * length * SwordDefs.PIKE_ULT_TAIL_FRACTION"
mutate skewer-hit-set-lost                          scripts/sim/sword_state.gd "		if sweep_hits.has(enemy):
			continue
		if SimMath.seg_dist(enemy.position, tail, tip) < enemy.radius + SwordDefs.PIKE_ULT_HIT_PAD:" "		if SimMath.seg_dist(enemy.position, tail, tip) < enemy.radius + SwordDefs.PIKE_ULT_HIT_PAD:"
mutate skewer-hit-loop-skips-corpses                scripts/sim/sword_state.gd "		if sweep_hits.has(enemy):
			continue
		if SimMath.seg_dist(enemy.position, tail, tip) < enemy.radius + SwordDefs.PIKE_ULT_HIT_PAD:" "		if sweep_hits.has(enemy) or enemy.dead:
			continue
		if SimMath.seg_dist(enemy.position, tail, tip) < enemy.radius + SwordDefs.PIKE_ULT_HIT_PAD:"
mutate skewer-blow-ignores-the-damage-factor        scripts/sim/sword_state.gd "run.hit_enemy(enemy, damage * SwordDefs.PIKE_ULT_DAMAGE_FACTOR, dir, 0.0, self, true, SwordDefs.PIKE_ULT_STACKS)" "run.hit_enemy(enemy, damage, dir, 0.0, self, true, SwordDefs.PIKE_ULT_STACKS)"
mutate skewer-blow-has-knockback                    scripts/sim/sword_state.gd "run.hit_enemy(enemy, damage * SwordDefs.PIKE_ULT_DAMAGE_FACTOR, dir, 0.0, self, true, SwordDefs.PIKE_ULT_STACKS)" "run.hit_enemy(enemy, damage * SwordDefs.PIKE_ULT_DAMAGE_FACTOR, dir, knock, self, true, SwordDefs.PIKE_ULT_STACKS)"
mutate skewer-blow-is-not-heavy                     scripts/sim/sword_state.gd "dir, 0.0, self, true, SwordDefs.PIKE_ULT_STACKS)" "dir, 0.0, self, false, SwordDefs.PIKE_ULT_STACKS)"
mutate skewer-blow-shake-lost                       scripts/sim/sword_state.gd "			run.add_shake(SwordDefs.PIKE_ULT_HIT_SHAKE, dir, true)
" ""
mutate skewer-impales-the-dead                      scripts/sim/sword_state.gd "			if not enemy.dead:
				skewer_carried.append(enemy)" "			skewer_carried.append(enemy)"
mutate skewer-never-impales                         scripts/sim/sword_state.gd "			if not enemy.dead:
				skewer_carried.append(enemy)" "			if false:
				skewer_carried.append(enemy)"
mutate skewer-carry-keeps-the-dead                  scripts/sim/sword_state.gd "		if _in_play(run, enemy):
			still_carried.append(enemy)" "		if run.enemies.has(enemy):
			still_carried.append(enemy)"
mutate skewer-carry-keeps-the-removed               scripts/sim/sword_state.gd "		if _in_play(run, enemy):
			still_carried.append(enemy)" "		if not enemy.dead:
			still_carried.append(enemy)"
mutate skewer-carry-no-longer-moves                 scripts/sim/sword_state.gd "		enemy.position += step
		enemy.velocity = Vector2.ZERO" "		enemy.velocity = Vector2.ZERO"
mutate skewer-carry-keeps-velocity                  scripts/sim/sword_state.gd "		enemy.velocity = Vector2.ZERO
		enemy.stun = maxf(enemy.stun, SwordDefs.PIKE_ULT_CARRY_STUN)" "		enemy.stun = maxf(enemy.stun, SwordDefs.PIKE_ULT_CARRY_STUN)"
mutate skewer-carry-stun-lost                       scripts/sim/sword_state.gd "		enemy.stun = maxf(enemy.stun, SwordDefs.PIKE_ULT_CARRY_STUN)
" ""
mutate skewer-parry-lost                            scripts/sim/sword_state.gd "	run.parry_projectiles(tail, tip, SwordDefs.PIKE_ULT_PARRY_PAD)
" ""
mutate skewer-parries-during-the-aim                scripts/sim/sword_state.gd "		_spring(run.position - dir * SwordDefs.PIKE_ULT_AIM_STANDOFF," "		run.parry_projectiles(position, position + dir * 400.0, 40.0)
		_spring(run.position - dir * SwordDefs.PIKE_ULT_AIM_STANDOFF,"
mutate skewer-ends-only-at-the-range                scripts/sim/sword_state.gd "if ultimate_time_left <= 0.0 or at_wall:" "if ultimate_time_left <= 0.0:"
mutate skewer-ends-only-at-a-wall                   scripts/sim/sword_state.gd "if ultimate_time_left <= 0.0 or at_wall:" "if at_wall:"
mutate skewer-wall-test-uses-the-whole-arena        scripts/sim/sword_state.gd "var margin: float = SwordDefs.PIKE_ULT_WALL_MARGIN" "var margin: float = 0.0"
mutate skewer-release-speed-swapped                 scripts/sim/sword_state.gd "enemy.velocity = dir * (SwordDefs.PIKE_ULT_RELEASE_SPEED_WALL if at_wall else SwordDefs.PIKE_ULT_RELEASE_SPEED_RANGE)" "enemy.velocity = dir * (SwordDefs.PIKE_ULT_RELEASE_SPEED_RANGE if at_wall else SwordDefs.PIKE_ULT_RELEASE_SPEED_WALL)"
mutate skewer-release-lost                          scripts/sim/sword_state.gd "			enemy.velocity = dir * (SwordDefs.PIKE_ULT_RELEASE_SPEED_WALL if at_wall else SwordDefs.PIKE_ULT_RELEASE_SPEED_RANGE)
" ""
mutate skewer-release-stun-lost                     scripts/sim/sword_state.gd "			enemy.stun = maxf(enemy.stun, SwordDefs.PIKE_ULT_RELEASE_STUN)
" ""
mutate skewer-release-keeps-carrying                scripts/sim/sword_state.gd "		skewer_carried.clear()
		phase = Phase.RECOVER
		timer = SwordDefs.PIKE_ULT_RECOVER_TIME" "		phase = Phase.RECOVER
		timer = SwordDefs.PIKE_ULT_RECOVER_TIME"
mutate skewer-recovery-velocity-swapped             scripts/sim/sword_state.gd "velocity = -dir * SwordDefs.PIKE_ULT_RECOVER_SPEED_WALL if at_wall else dir * SwordDefs.PIKE_ULT_RECOVER_SPEED_RANGE" "velocity = dir * SwordDefs.PIKE_ULT_RECOVER_SPEED_WALL if at_wall else -dir * SwordDefs.PIKE_ULT_RECOVER_SPEED_RANGE"
mutate skewer-release-cue-lost                      scripts/sim/sword_state.gd "		run.add_cue(SimCue.make(SimCue.Kind.SKEWER_RELEASED, tip, dir, released, at_wall))
" ""
mutate skewer-release-cue-never-a-wall              scripts/sim/sword_state.gd "SimCue.make(SimCue.Kind.SKEWER_RELEASED, tip, dir, released, at_wall)" "SimCue.make(SimCue.Kind.SKEWER_RELEASED, tip, dir, released, false)"
mutate skewer-release-cue-counts-nobody             scripts/sim/sword_state.gd "SimCue.make(SimCue.Kind.SKEWER_RELEASED, tip, dir, released, at_wall)" "SimCue.make(SimCue.Kind.SKEWER_RELEASED, tip, dir, 0, at_wall)"
mutate skewer-death-keeps-carrying                  scripts/sim/sword_state.gd "		ultimate_victim = null
		skewer_carried.clear()
		return" "		ultimate_victim = null
		return"
mutate skewer-area-radius-nonzero                   scripts/sim/sword_state.gd "		SwordDefs.PIKE:
			return 0.0" "		SwordDefs.PIKE:
			return 100.0"
mutate pike-encounter-not-in-cycle                  scripts/sim/run_scenario.gd "ENCOUNTER_CONDITIONS, ENCOUNTER_WARDEN, ENCOUNTER_PIKE]" "ENCOUNTER_CONDITIONS, ENCOUNTER_WARDEN]"
mutate pike-encounter-slot-lost                     scripts/sim/game_run.gd "		scenario if scenario.encounter == RunScenario.ENCOUNTER_PIKE else RunScenario.pike_encounter(),
" "		RunScenario.new(),
"
mutate pike-fixture-wrong-element                   scripts/sim/run_scenario.gd "	specs.append(SwordSpec.make(SwordDefs.PIKE, 0, &\"fire\"))" "	specs.append(SwordSpec.make(SwordDefs.PIKE, 0, &\"ice\"))"
mutate pike-fixture-has-no-pikes                    scripts/sim/run_scenario.gd "	specs.append(SwordSpec.make(SwordDefs.PIKE, 0, &\"ice\"))" "	specs.append(SwordSpec.make(&\"fang\", 0, &\"ice\"))"
mutate pike-encounter-no-brutes                     scripts/sim/run_scenario.gd "&\"husk\", &\"runner\", &\"husk\", &\"husk\", &\"brute\", &\"runner\", &\"husk\", &\"husk\", &\"runner\", &\"husk\", &\"brute\", &\"husk\"," "&\"husk\", &\"runner\", &\"husk\", &\"husk\", &\"husk\", &\"runner\", &\"husk\", &\"husk\", &\"runner\", &\"husk\", &\"husk\", &\"husk\","
mutate pike-encounter-column-moved                  scripts/sim/run_scenario.gd "Vector2(1290.0, 330.0), Vector2(1325.0, 270.0)" "Vector2(1290.0, 630.0), Vector2(1325.0, 570.0)"
mutate pike-encounter-not-the-default               scripts/sim/run_scenario.gd "var loadout: Array[SwordSpec] = RunScenario.fang_fixture_loadout()" "var loadout: Array[SwordSpec] = RunScenario.pike_fixture_loadout()"
mutate pike-launch-option-lost                      scripts/launch_options.gd "		\"pike\":
			return RunScenario.pike_encounter()" "		\"pike\":
			return null"
mutate pike-dev-button-title                        scripts/sim/run_scenario.gd "		ENCOUNTER_PIKE:
			return \"Pike\"
" ""
mutate pike-legend-lost                             scripts/hud.gd "	elif run.scenario.encounter == RunScenario.ENCOUNTER_PIKE:" "	elif false:"
mutate pike-legend-counts-nothing                   scripts/hud.gd "run.cue_count(SimCue.Kind.SKEWER_LAUNCHED), run.cue_count(SimCue.Kind.WALL_SLAM), switch_hint]" "0, 0, switch_hint]"
mutate skill-shot-tag-lost                          scripts/hud.gd "\"  skill shot\" if SwordDefs.ultimate_is_shot(sword.spec.type_id) else \"\"" "\"\""
mutate thrust-telegraph-lost                        scripts/presentation/effects_layer.gd "			_draw_thrust_telegraph(sword)
" "			pass
"
mutate skewer-drawing-lost                          scripts/presentation/effects_layer.gd "			_draw_skewer(sword, _sword_color(sword.spec))
" "			pass
"
mutate skewer-aim-line-lost                         scripts/presentation/effects_layer.gd "		draw_line(_run.position, end, Color(tint, 0.15 + 0.25 * u), 24.0)
		draw_line(_run.position, end, Color(tint, 0.25 + 0.35 * u), 2.0)
" "		pass
"
mutate skewer-carry-ring-lost                       scripts/presentation/effects_layer.gd "		draw_arc(enemy.position, enemy.radius + 7.0, 0.0, TAU, 20, Color(tint, 0.85), 3.0)
" "		pass
"
mutate skewer-launch-ring-lost                      scripts/presentation/effects_layer.gd "			_add_ring(cue.position, 6.0, 44.0, 0.2, launch_tint, 3.0)
" "			pass
"
mutate skewer-release-ring-lost                     scripts/presentation/effects_layer.gd "			_add_ring(cue.position, 10.0, 60.0 + float(cue.amount) * 8.0, 0.3, Color(1.0, 0.92, 0.7, 0.95), 4.0)
" "			pass
"
mutate skewer-release-text-lost                     scripts/presentation/effects_layer.gd "				_add_text(cue.position + Vector2(0.0, -30.0), \"%s x%d\" % [\"SLAM\" if cue.critical else \"FLUNG\", cue.amount], Color(1.0, 0.92, 0.7), 0.7, 24)
" "				pass
"
mutate skewer-start-draws-a-landing-ring            scripts/presentation/effects_layer.gd "	if not SwordDefs.ultimate_is_shot(sword.spec.type_id):
		_add_ring(" "	if true:
		_add_ring("
mutate skewer-launch-sound-lost                     scripts/audio/sfx_bank.gd "		SimCue.Kind.SKEWER_LAUNCHED:
			play(\"strike\")" "		SimCue.Kind.SKEWER_LAUNCHED:
			pass"
mutate skewer-release-sound-always                  scripts/audio/sfx_bank.gd "			if cue.amount > 0:
				play(\"hit\")" "			play(\"hit\")"
mutate pike-visual-needle                           scripts/presentation/placeholder_sword_visual.gd "	_pike = spec.type_id == SwordDefs.PIKE" "	_pike = false"

echo
echo "shard $SHARD of $SHARDS: $ran mutation(s) run, $((ran - survived - inconclusive)) caught"
if ((survived)); then echo "$survived mutation(s) survived"; fi
if ((inconclusive)); then echo "$inconclusive mutation(s) were inconclusive (crash, timeout or script error instead of a check verdict)"; fi
((survived + inconclusive == 0)) || exit 1
echo "all mutations were caught as behavioural rejections by the headless checks (0 inconclusive)"
