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
mutate visual-not-updated   scripts/main.gd "	visual.apply_pose(run.position, run.facing, moving)" "	pass"
mutate sound-never-unlocks  scripts/audio/sfx_bank.gd "	unlocked = true
	play(\"unlock\")" "	play(\"unlock\")"

echo
if ((survived)); then echo "$survived mutation(s) survived"; fi
if ((inconclusive)); then echo "$inconclusive mutation(s) were inconclusive (crash, timeout or script error instead of a check verdict)"; fi
((survived + inconclusive == 0)) || exit 1
echo "all mutations were caught as behavioural rejections by the headless checks (0 inconclusive)"
