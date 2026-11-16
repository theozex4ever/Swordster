#!/usr/bin/env bash
# Regression tests for the mutation checker (mutation-check.sh) and the CI shard summary
# (mutation-summary.sh). They pin behaviour that must not drift:
#   1. a mutation whose search text is stale is reported NOT APPLIED, never caught, and fails
#      the run (it used to count as caught through ran - survived - inconclusive);
#   2. a mutation that fails a check cleanly and would only crash in a LATER check is
#      CAUGHT in the fast mode (it stops at the first clean failure) and INCONCLUSIVE in the
#      strict classic mode, which CI runs: the documented difference between the modes;
#   3. the shard summary succeeds only when the matrix job succeeded and every shard has a
#      clean result file AND together they cover the whole mutation list (shard count, per-shard
#      counts and filters checked against the list itself): one aborted shard, a missing,
#      duplicate or extra file, a cancelled job, a filtered or short run all fail it;
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
  # The size of the whole list, counted here independently of the checker (the summary asks the
  # checker): every `mutate NAME ...` line of the script, like the checker's own parser.
  FULL="$(grep -cE '^mutate[[:space:]]+[^[:space:]]' "$REPO/tools/godot/mutation-check.sh")"
  expect() { echo $(((FULL - $1 + SHARDS - 1) / SHARDS)); } # shard -> its share of the list
  result_line() { # shard shards ran caught survived inconclusive not_applied [filters] [selected] [total]
    echo "RESULT shard=$1 shards=$2 total=${10:-$FULL} selected=${9:-$FULL} filters=${8:-none} mode=classic ran=$3 caught=$4 survived=$5 inconclusive=$6 not_applied=$7 exit=0"
  }
  results() { # dir -> twelve clean classic results that together cover the whole list
    mkdir -p "$1"
    for ((s = 0; s < SHARDS; s++)); do
      n="$(expect "$s")"; result_line "$s" "$SHARDS" "$n" "$n" 0 0 0 > "$1/result-$s.txt"
    done
  }
  judge_set() { # name want-exit matrix-result dir
    local status=0 out="$ROOT/summary-$1.log"
    GITHUB_STEP_SUMMARY="$ROOT/summary-$1.md" MATRIX_RESULT="$3" SHARDS=$SHARDS "$REPO/tools/godot/mutation-summary.sh" "$4" >"$out" 2>&1 || status=$?
    if [[ "$status" == "$2" ]]; then report "summary: $1" PASS; else report "summary: $1" "exit $status, wanted $2" "$out"; fi
  }
  d="$ROOT/s-pass"; results "$d";                                              judge_set "all twelve shards pass" 0 success "$d"
  grep -q "all $SHARDS shards succeeded: $FULL of $FULL mutations caught, $FULL of $FULL expected" "$ROOT/summary-all twelve shards pass.log" \
    && report "summary: the verdict line shows the coverage of the full list" PASS \
    || report "summary: the verdict line shows the coverage of the full list" "no '$FULL of $FULL expected' line" "$ROOT/summary-all twelve shards pass.log"
  d="$ROOT/s-aborted"; results "$d"; sed -i 's/exit=0/exit=1/' "$d/result-7.txt"
  judge_set "one shard exited 1 although its counts look clean" 1 success "$d"
  d="$ROOT/s-aborted-matrix"; results "$d"; judge_set "matrix job failed, every file clean" 1 failure "$d"
  d="$ROOT/s-missing"; results "$d"; rm "$d/result-3.txt";                      judge_set "one result file missing (missing shard index)" 1 success "$d"
  d="$ROOT/s-cancelled"; results "$d";                                         judge_set "job cancelled, files from finished shards pass" 1 cancelled "$d"
  d="$ROOT/s-none"; mkdir -p "$d";                                              judge_set "no result files at all" 1 failure "$d"
  d="$ROOT/s-early"; results "$d"; echo "RESULT shard=5 (no result: the script stopped early) exit=2" > "$d/result-5.txt"
  judge_set "a shard whose checker died before its RESULT line" 1 success "$d"
  d="$ROOT/s-noexit"; results "$d"; sed -i 's/ exit=0//' "$d/result-2.txt";    judge_set "result without a recorded exit status" 1 success "$d"
  d="$ROOT/s-notapplied"; results "$d"; n="$(expect 9)"; result_line 9 $SHARDS "$n" $((n - 1)) 0 0 1 > "$d/result-9.txt"
  judge_set "a mutation not applied" 1 success "$d"
  d="$ROOT/s-inconclusive"; results "$d"; n="$(expect 0)"; result_line 0 $SHARDS "$n" $((n - 1)) 0 1 0 > "$d/result-0.txt"
  judge_set "an inconclusive mutation" 1 success "$d"
  d="$ROOT/s-fast"; results "$d"; sed -i 's/mode=classic/mode=fast/' "$d/result-4.txt"; judge_set "a shard that ran in fast mode" 1 success "$d"
  d="$ROOT/s-wrong-shard"; results "$d"; cp "$d/result-1.txt" "$d/result-6.txt"; judge_set "a result file that belongs to another shard" 1 success "$d"

  # The pass must cover the whole list: none of these may certify an incomplete one.
  d="$ROOT/s-shards24"; mkdir -p "$d"                                  # twelve files of a 24-shard run
  for ((s = 0; s < 12; s++)); do result_line "$s" 24 19 19 0 0 0 > "$d/result-$s.txt"; done
  judge_set "twelve files declaring shards=24, 19 clean catches each" 1 success "$d"
  d="$ROOT/s-one-each"; mkdir -p "$d"                                  # ONLY=<one mutation> on every shard
  for ((s = 0; s < SHARDS; s++)); do result_line "$s" $SHARDS 1 1 0 0 0 ONLY 1 > "$d/result-$s.txt"; done
  judge_set "twelve clean one-mutation results (ONLY filter)" 1 success "$d"
  d="$ROOT/s-one-each-nofilter"; mkdir -p "$d"                         # same counts, the filter not recorded
  for ((s = 0; s < SHARDS; s++)); do result_line "$s" $SHARDS 1 1 0 0 0 none 1 > "$d/result-$s.txt"; done
  judge_set "twelve clean one-mutation results claiming no filter" 1 success "$d"
  d="$ROOT/s-sections"; results "$d"                                   # a SECTIONS-filtered run: every file says so
  for ((s = 0; s < SHARDS; s++)); do n="$(expect "$s")"; result_line "$s" $SHARDS "$n" "$n" 0 0 0 SECTIONS > "$d/result-$s.txt"; done
  judge_set "a SECTIONS filter recorded although the counts look complete" 1 success "$d"
  d="$ROOT/s-sections-short"; mkdir -p "$d"                            # SECTIONS=pike: a smaller selection split in twelve
  for ((s = 0; s < SHARDS; s++)); do result_line "$s" $SHARDS 3 3 0 0 0 SECTIONS 36 > "$d/result-$s.txt"; done
  judge_set "a SECTIONS-filtered selection split over twelve shards" 1 success "$d"
  d="$ROOT/s-core0"; results "$d"; sed -i 's/filters=none/filters=CORE/' "$d/result-8.txt"; judge_set "one shard with a CORE filter" 1 success "$d"
  d="$ROOT/s-nofilters-field"; results "$d"; sed -i 's/ filters=none//' "$d/result-2.txt"; judge_set "a result without the filters field" 1 success "$d"
  d="$ROOT/s-duplicate"; results "$d"; sed -i 's/shard=11 /shard=4 /' "$d/result-11.txt"; judge_set "a duplicate shard index (11 reports 4)" 1 success "$d"
  d="$ROOT/s-extra-file"; results "$d"; cp "$d/result-0.txt" "$d/result-12.txt"; judge_set "an extra result file beyond the last shard" 1 success "$d"
  d="$ROOT/s-count-mismatch"; results "$d"; n="$(expect 5)"; result_line 5 $SHARDS $((n - 1)) $((n - 1)) 0 0 0 > "$d/result-5.txt"
  judge_set "one shard ran one mutation fewer than its share" 1 success "$d"
  d="$ROOT/s-count-more"; results "$d"; n="$(expect 5)"; result_line 5 $SHARDS $((n + 1)) $((n + 1)) 0 0 0 > "$d/result-5.txt"
  judge_set "one shard ran one mutation more than its share" 1 success "$d"
  d="$ROOT/s-total"; results "$d"; sed -i "s/ total=$FULL / total=$((FULL - 1)) /" "$d/result-1.txt"; judge_set "a shard that counts a shorter mutation list" 1 success "$d"
  d="$ROOT/s-selected"; results "$d"; sed -i "s/ selected=$FULL / selected=$((FULL - 1)) /" "$d/result-1.txt"; judge_set "a shard that selected fewer mutations than the list" 1 success "$d"
  d="$ROOT/s-zero-ran"; results "$d"; result_line 3 $SHARDS 0 0 0 0 0 > "$d/result-3.txt"; judge_set "a shard that ran nothing" 1 success "$d"
  # The shard count of the workflow matrix is checked when the summary is told where the workflow is.
  for len in 12 10; do
    wf="$ROOT/matrix-$len.yml"; list="$(seq -s ', ' 0 $((len - 1)))"; printf 'jobs:\n  mutation:\n    strategy:\n      matrix:\n        shard: [%s]\n' "$list" > "$wf"
    d="$ROOT/s-matrix-$len"; results "$d"; status=0; out="$ROOT/summary-matrix-$len.log"
    WORKFLOW_FILE="$wf" GITHUB_STEP_SUMMARY="$ROOT/summary-matrix-$len.md" MATRIX_RESULT=success SHARDS=$SHARDS "$REPO/tools/godot/mutation-summary.sh" "$d" >"$out" 2>&1 || status=$?
    want=0; ((len == SHARDS)) || want=1
    if [[ "$status" == "$want" ]]; then report "summary: workflow matrix of $len shards, SHARDS=$SHARDS" PASS; else report "summary: workflow matrix of $len shards, SHARDS=$SHARDS" "exit $status, wanted $want" "$out"; fi
  done
  # The real workflow file must agree with the SHARDS of its own env block (whatever it is: the clean results are
  # generated for that many shards).
  wf="$REPO/.github/workflows/mutation.yml"; d="$ROOT/s-real-workflow"; status=0; out="$ROOT/summary-real-workflow.log"
  workflow_shards="$(sed -n 's/^  SHARDS: \([0-9]*\)$/\1/p' "$wf")"
  SHARDS="$workflow_shards"; results "$d"
  WORKFLOW_FILE="$wf" GITHUB_STEP_SUMMARY="$ROOT/summary-real-workflow.md" MATRIX_RESULT=success SHARDS="$workflow_shards" "$REPO/tools/godot/mutation-summary.sh" "$d" >"$out" 2>&1 || status=$?
  SHARDS=12
  if [[ "$status" == 0 ]]; then report "summary: the real workflow's SHARDS matches its matrix" PASS; else report "summary: the real workflow's SHARDS matches its matrix" "exit $status" "$out"; fi
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
