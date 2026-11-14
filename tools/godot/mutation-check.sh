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

SCRATCH="$(mktemp -d)"; trap 'rm -rf "$SCRATCH"' EXIT
export XDG_DATA_HOME="$SCRATCH/home/data" XDG_CONFIG_HOME="$SCRATCH/home/config" XDG_CACHE_HOME="$SCRATCH/home/cache"
cp -a "$REPO/godot" "$SCRATCH/base"; rm -rf "$SCRATCH/base/.godot"
"$GODOT_BIN" --headless --path "$SCRATCH/base" --import >/dev/null 2>&1

run_checks() { timeout 120 "$GODOT_BIN" --headless --path "$1" --script res://tests/run_checks.gd 2>&1; }

if ! out="$(run_checks "$SCRATCH/base")" || ! grep -q '^CHECKS PASSED' <<<"$out"; then
  echo "baseline: unmodified project does NOT pass its checks"; echo "$out" | tail -20; exit 1
fi
echo "baseline: $(grep '^CHECKS PASSED' <<<"$out")"

# SHARD=i SHARDS=n runs every n-th mutation starting at i (0-based), so n copies of
# this script can run in parallel over the same list; each prints its own totals.
SHARD="${SHARD:-0}" SHARDS="${SHARDS:-1}" mutation_index=0
mutate() { # name file old new
  local name="$1" file="$2" old="$3" new="$4" dir="$SCRATCH/m-$1"
  if (( mutation_index++ % SHARDS != SHARD )); then return 0; fi
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
mutate flurry-strikes-the-dead     scripts/sim/sword_state.gd "		if struck != null and not struck.dead:" "		if struck != null:"
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
mutate flurry-survives-death       scripts/sim/sword_state.gd "		phase = Phase.IDLE
		ultimate_victim = null
		return" "		ultimate_victim = null
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

echo
echo "shard $SHARD of $SHARDS: $ran mutation(s) run, $((ran - survived - inconclusive)) caught"
if ((survived)); then echo "$survived mutation(s) survived"; fi
if ((inconclusive)); then echo "$inconclusive mutation(s) were inconclusive (crash, timeout or script error instead of a check verdict)"; fi
((survived + inconclusive == 0)) || exit 1
echo "all mutations were caught as behavioural rejections by the headless checks (0 inconclusive)"
