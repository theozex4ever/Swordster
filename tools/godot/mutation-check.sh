#!/usr/bin/env bash
# Proves the headless checks can fail: applies one deliberate behavioural bug at a
# time to a scratch copy of the Godot project and requires run_checks.gd to
# reject each one (and to accept the unmodified project first).
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
  local status=0 log
  log="$(run_checks "$dir")" || status=$?
  if grep -q '^CHECKS PASSED' <<<"$log" && ((status == 0)); then
    echo "SURVIVED  $name   <-- checks failed to detect this bug"; survived=$((survived + 1))
  else
    echo "caught    $name   ($(grep -m1 -E '^  FAIL|CHECKS FAILED|SCRIPT ERROR' <<<"$log" | cut -c1-90))"
  fi
}

survived=0
mutate speed-zero           scripts/sim/game_run.gd  "PLAYER_SPEED: float = 285.0" "PLAYER_SPEED: float = 0.0"
mutate pause-ignored        scripts/sim/game_run.gd  "	if paused:
		return
	tick += 1" "	tick += 1"
mutate resume-never         scripts/sim/game_run.gd  "		GameCommand.Kind.RESUME:
			paused = false" "		GameCommand.Kind.RESUME:
			paused = paused"
mutate restart-keeps-pose   scripts/sim/game_run.gd  "	position = scenario.start_position" "	position = position"
mutate restart-keeps-input  scripts/sim/game_run.gd  "	velocity = Vector2.ZERO
	facing = Vector2.RIGHT
	_move_input = Vector2.ZERO" "	velocity = Vector2.ZERO
	facing = Vector2.RIGHT"
mutate no-diagonal-clamp    scripts/sim/game_run.gd  "command.axis.limit_length(1.0)" "command.axis"
mutate no-wall-clamp        scripts/sim/game_run.gd  "	position = position.clamp(inner.position, inner.end)" "	position = position + Vector2.ZERO"
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
if ((survived)); then echo "$survived mutation(s) survived"; exit 1; fi
echo "all mutations were caught by the headless checks"
