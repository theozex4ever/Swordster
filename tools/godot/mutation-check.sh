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

mutate() { # name file old new
  local name="$1" file="$2" old="$3" new="$4" dir="$SCRATCH/m-$1"
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

survived=0; inconclusive=0
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
	for at: Vector2 in scenario.initial_husks:" "	for at: Vector2 in scenario.initial_husks:"
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
mutate encounter-toggle-lost scripts/sim/game_run.gd "			restart_with(_home_scenario if scenario.dev_shove else _crowd_scenario)" "			pass"
mutate restart-with-keeps-scenario scripts/sim/game_run.gd "	scenario = new_scenario
	restarts += 1" "	restarts += 1"
mutate restart-keeps-cue-counts scripts/sim/game_run.gd "	_cue_counts = {}
" "	_cue_counts = _cue_counts
"
mutate placements-ignored   scripts/sim/game_run.gd "	for placement: EnemyPlacement in scenario.initial_enemies:" "	for placement: EnemyPlacement in []:"
mutate placement-velocity-dropped scripts/sim/game_run.gd "		enemy.velocity = placement.velocity" "		enemy.velocity = Vector2.ZERO"
mutate placement-health-dropped scripts/sim/game_run.gd "		if placement.hp >= 0.0:
			enemy.hp = placement.hp" "		if false:
			enemy.hp = placement.hp"
mutate composition-ignored  scripts/sim/wave_director.gd "		queue.append_array(_wave_kinds)" "		queue.append_array([])"
mutate spawn-always-husk    scripts/sim/wave_director.gd "EnemyState.make(marker.kind, marker.position," "EnemyState.make(EnemyDefs.HUSK, marker.position,"
mutate spawn-phase-fixed    scripts/sim/wave_director.gd "var phase: float = run.rng.randf_range(0.0, 10.0)" "var phase: float = 0.0"
mutate marker-kind-lost     scripts/sim/wave_director.gd "markers.append(SpawnMarker.make(kind, _spawn_point(run)))" "markers.append(SpawnMarker.make(EnemyDefs.HUSK, _spawn_point(run)))"
mutate stun-flag-dropped    scripts/presentation/run_presenter.gd "enemy.hp / enemy.max_hp, enemy.stun > 0.0)" "enemy.hp / enemy.max_hp, false)"
mutate brute-drawn-small    scripts/presentation/placeholder_enemy_visual.gd "			return 30.0" "			return 16.0"
mutate runner-same-colour   scripts/presentation/placeholder_enemy_visual.gd "const RUNNER_COLOR: Color = Color(1.0, 0.55, 0.27)" "const RUNNER_COLOR: Color = Color(0.84, 0.28, 0.34)"
mutate shove-button-on-release scripts/hud.gd "_shove_button.button_down.connect" "_shove_button.pressed.connect"
mutate shove-button-unwired scripts/main.gd "	_hud.shove_pressed.connect(func() -> void: _submit(GameCommand.dev_shove()))" "	_hud.shove_pressed.connect(func() -> void: pass)"
mutate crowd-button-unwired scripts/main.gd "	_hud.encounter_pressed.connect(func() -> void: _submit(GameCommand.toggle_encounter()))" "	_hud.encounter_pressed.connect(func() -> void: pass)"
mutate launch-option-lost   scripts/launch_options.gd 'ENCOUNTER_ARGUMENT: String = "--encounter=crowd"' 'ENCOUNTER_ARGUMENT: String = "--encounter=none"'
mutate render-rate-dependent scripts/main.gd "func _physics_process(_delta: float) -> void:" "func _process(_delta: float) -> void:"
mutate wall-slam-sound-lost scripts/audio/sfx_bank.gd "		SimCue.Kind.ENEMY_HIT, SimCue.Kind.WALL_SLAM:" "		SimCue.Kind.ENEMY_HIT:"

echo
if ((survived)); then echo "$survived mutation(s) survived"; fi
if ((inconclusive)); then echo "$inconclusive mutation(s) were inconclusive (crash, timeout or script error instead of a check verdict)"; fi
((survived + inconclusive == 0)) || exit 1
echo "all mutations were caught as behavioural rejections by the headless checks (0 inconclusive)"
