#!/usr/bin/env bash
# Regression tests for the mutation checker (mutation-check.sh) and the CI shard summary
# (mutation-summary.sh). They pin behaviour that must not drift:
#   1. a mutation whose search text is stale is reported NOT APPLIED, never caught, and fails
#      the run (it used to count as caught through ran - survived - inconclusive);
#   2. a mutation that fails a check cleanly and would only crash in a LATER check is
#      CAUGHT in the fast mode (it stops at the first clean failure) and INCONCLUSIVE in the
#      strict classic mode, which CI runs: the documented difference between the modes;
#   3. the shard summary succeeds only when the matrix job succeeded and every shard has a
#      clean result file: one aborted shard, a missing file or a cancelled job all fail it;
#   4. a focused run never prints "CHECKS PASSED".
# Needs the pinned Godot in the cache for 1, 2 and 4: ./build-godot.sh --bootstrap-only.
#   tools/godot/test-mutation-runner.sh [summary|stale|crash|focus ...]   (default: all)
set -Eeuo pipefail
REPO="$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd)"
# shellcheck source=tools/godot/godot.lock
source "$REPO/tools/godot/godot.lock"
REAL_CACHE="${SWORDSTER_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/swordster}"
GODOT_BIN="$REAL_CACHE/godot-$GODOT_VERSION/editor/godot"
ROOT="$(mktemp -d)"; trap 'rm -rf "$ROOT"' EXIT
failures=0
want=("$@"); ((${#want[@]})) || want=(summary stale crash focus)
wants() { local t; for t in "${want[@]}"; do [[ "$t" == "$1" ]] && return 0; done; return 1; }
report() { # name PASS|detail log
  if [[ "$2" == PASS ]]; then printf '%-62s PASS\n' "$1"
  else printf '%-62s FAIL(%s)\n' "$1" "$2"; failures=$((failures + 1)); [[ -z "${3:-}" ]] || tail -n 12 "$3"; fi
}
need_godot() { [[ -x "$GODOT_BIN" ]] || { echo "pinned Godot missing; run ./build-godot.sh --bootstrap-only" >&2; exit 1; }; }
sandbox() { # name -> a copy of the tools and the Godot project that mutation-check.sh runs against
  local sb="$ROOT/$1"; mkdir -p "$sb/repo/tools"
  cp -a "$REPO/tools/godot" "$sb/repo/tools/godot"
  cp -a "$REPO/godot" "$sb/repo/godot"; rm -rf "$sb/repo/godot/.godot"
  echo "$sb"
}
checker() { # sandbox mode log -> runs ONLY=speed-zero, prints the exit status
  local status=0
  env -i HOME="$1/home" PATH="$PATH" SWORDSTER_CACHE_DIR="$REAL_CACHE" ONLY=speed-zero FAST="$2" \
    "$1/repo/tools/godot/mutation-check.sh" >"$3" 2>&1 || status=$?
  echo "$status"
}

# ---- 3. the shard summary
if wants summary; then
  SHARDS=12
  results() { # dir -> twelve clean classic results
    mkdir -p "$1"
    for ((s = 0; s < SHARDS; s++)); do
      echo "RESULT shard=$s shards=$SHARDS mode=classic ran=38 caught=38 survived=0 inconclusive=0 not_applied=0 exit=0" > "$1/result-$s.txt"
    done
  }
  judge_set() { # name want-exit matrix-result dir
    local status=0 out="$ROOT/summary-$1.log"
    GITHUB_STEP_SUMMARY="$ROOT/summary-$1.md" MATRIX_RESULT="$3" SHARDS=$SHARDS "$REPO/tools/godot/mutation-summary.sh" "$4" >"$out" 2>&1 || status=$?
    if [[ "$status" == "$2" ]]; then report "summary: $1" PASS; else report "summary: $1" "exit $status, wanted $2" "$out"; fi
  }
  d="$ROOT/s-pass"; results "$d";                                              judge_set "all twelve shards pass" 0 success "$d"
  d="$ROOT/s-aborted"; results "$d"; sed -i 's/exit=0/exit=1/' "$d/result-7.txt"
  judge_set "one shard exited 1 although its counts look clean" 1 success "$d"
  d="$ROOT/s-aborted-matrix"; results "$d"; judge_set "matrix job failed, every file clean" 1 failure "$d"
  d="$ROOT/s-missing"; results "$d"; rm "$d/result-3.txt";                      judge_set "one result file missing" 1 success "$d"
  d="$ROOT/s-cancelled"; results "$d";                                         judge_set "job cancelled, files from finished shards pass" 1 cancelled "$d"
  d="$ROOT/s-none"; mkdir -p "$d";                                              judge_set "no result files at all" 1 failure "$d"
  d="$ROOT/s-early"; results "$d"; echo "RESULT shard=5 (no result: the script stopped early) exit=2" > "$d/result-5.txt"
  judge_set "a shard whose checker died before its RESULT line" 1 success "$d"
  d="$ROOT/s-noexit"; results "$d"; sed -i 's/ exit=0//' "$d/result-2.txt";    judge_set "result without a recorded exit status" 1 success "$d"
  d="$ROOT/s-notapplied"; results "$d"; sed -i 's/caught=38 survived=0 inconclusive=0 not_applied=0/caught=37 survived=0 inconclusive=0 not_applied=1/' "$d/result-9.txt"
  judge_set "a mutation not applied" 1 success "$d"
  d="$ROOT/s-inconclusive"; results "$d"; sed -i 's/caught=38 survived=0 inconclusive=0/caught=37 survived=0 inconclusive=1/' "$d/result-0.txt"
  judge_set "an inconclusive mutation" 1 success "$d"
  d="$ROOT/s-fast"; results "$d"; sed -i 's/mode=classic/mode=fast/' "$d/result-4.txt"; judge_set "a shard that ran in fast mode" 1 success "$d"
  d="$ROOT/s-wrong-shard"; results "$d"; cp "$d/result-1.txt" "$d/result-6.txt"; judge_set "a result file that belongs to another shard" 1 success "$d"
fi

# ---- 1. stale mutation text
if wants stale; then
  need_godot
  sb="$(sandbox stale)"
  python3 -I - "$sb/repo/tools/godot/mutation-check.sh" <<'PY'
import sys
path = sys.argv[1]
text = open(path).read()
old = '"PLAYER_SPEED: float = 285.0" "PLAYER_SPEED: float = 0.0"'
assert text.count(old) == 1
open(path, "w").write(text.replace(old, '"PLAYER_SPEED: float = 999.5" "PLAYER_SPEED: float = 0.0"'))
PY
  for mode in 1 0; do
    log="$ROOT/stale-$mode.log"; status="$(checker "$sb" "$mode" "$log")"; problem=PASS
    [[ "$status" == 1 ]] || problem="exit $status, wanted 1"
    grep -q '^MUTATION NOT APPLIED: speed-zero' "$log" || problem="no MUTATION NOT APPLIED line"
    grep -q '^caught ' "$log" && problem="a stale mutation was reported caught"
    grep -q '^RESULT .* ran=1 caught=0 survived=0 inconclusive=0 not_applied=1$' "$log" || problem="RESULT line is not ran=1 caught=0 not_applied=1: $(grep '^RESULT' "$log")"
    report "stale mutation (FAST=$mode): not applied, never caught, run fails" "$problem" "$log"
  done
fi

# ---- 2. clean failure first, crash in a later check
if wants crash; then
  need_godot
  sb="$(sandbox crash)"
  # The reviewer's mutant, made from the real `speed-zero` mutation: with the player's speed at
  # zero the movement checks FAIL CLEANLY first; then a kill() in a seed-41 scenario (the Flurry
  # and Warden fights) crashes the engine, which only a run that keeps going after the failure
  # ever reaches. The unmutated project is unaffected (the tripwire needs a speed of zero), so
  # the baseline passes.
  python3 -I - "$sb/repo/godot/scripts/sim/game_run.gd" <<'PY'
import sys
path = sys.argv[1]
text = open(path).read()
old = "func kill(enemy: EnemyState, direction: Vector2) -> void:\n"
assert text.count(old) == 1
open(path, "w").write(text.replace(old, old + "\tvar tripwire_speed: float = PLAYER_SPEED\n\tif tripwire_speed < 1.0 and scenario.seed == 41:\n\t\tOS.crash(\"test tripwire: a kill after the movement failure\")\n"))
PY
  log="$ROOT/crash-fast.log"; status="$(checker "$sb" 1 "$log")"; problem=PASS
  [[ "$status" == 0 ]] || problem="exit $status, wanted 0"
  grep -q '^caught    speed-zero' "$log" || problem="fast mode did not call the clean failure caught"
  grep -q '^RESULT .* mode=fast ran=1 caught=1 survived=0 inconclusive=0 not_applied=0$' "$log" || problem="RESULT: $(grep '^RESULT' "$log")"
  report "crash after a clean failure, FAST=1: caught" "$problem" "$log"
  log="$ROOT/crash-classic.log"; status="$(checker "$sb" 0 "$log")"; problem=PASS
  [[ "$status" == 1 ]] || problem="exit $status, wanted 1"
  grep -q '^INCONCLUSIVE speed-zero' "$log" || problem="classic mode did not call the crash inconclusive"
  grep -q '^caught ' "$log" && problem="classic mode called the crash caught"
  grep -q '^RESULT .* mode=classic ran=1 caught=0 survived=0 inconclusive=1 not_applied=0$' "$log" || problem="RESULT: $(grep '^RESULT' "$log")"
  report "crash after a clean failure, FAST=0: inconclusive" "$problem" "$log"
fi

# ---- 4. a focused run is partial evidence
if wants focus; then
  need_godot
  sb="$(sandbox focus)"; cp -a "$sb/repo/godot" "$sb/project"
  env -i HOME="$sb/home" XDG_DATA_HOME="$sb/home/d" XDG_CONFIG_HOME="$sb/home/c" XDG_CACHE_HOME="$sb/home/k" "$GODOT_BIN" --headless --path "$sb/project" --import >/dev/null 2>&1 || true
  for args in "--focus=none" "--focus=none --skip-probes" "--focus=warden_maelstrom,survival_loop --skip-probes --fail-fast"; do
    log="$ROOT/focus.log"; status=0
    env -i HOME="$sb/home" XDG_DATA_HOME="$sb/home/d" XDG_CONFIG_HOME="$sb/home/c" XDG_CACHE_HOME="$sb/home/k" PATH="$PATH" \
      timeout 300 "$GODOT_BIN" --headless --path "$sb/project" --script res://tests/run_checks.gd -- $args >"$log" 2>&1 || status=$?
    problem=PASS
    [[ "$status" == 0 ]] || problem="exit $status"
    grep -q '^CHECKS PASSED' "$log" && problem="a focused run printed CHECKS PASSED"
    grep -q '^CHECKS PARTIAL: ' "$log" || problem="no CHECKS PARTIAL line"
    report "focused run '$args' prints CHECKS PARTIAL" "$problem" "$log"
  done
fi

echo
if ((failures)); then echo "$failures mutation-runner regression case(s) failed"; exit 1; fi
echo "all mutation-runner regression cases behaved as required"
