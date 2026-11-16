#!/usr/bin/env bash
# Regression tests for the mutation checker (mutation-check.sh) and the CI shard summary
# (mutation-summary.sh). They pin behaviour that must not drift:
#   1. a mutation whose search text is stale is reported NOT APPLIED, never caught, and fails
#      the run (it used to count as caught through ran - survived - inconclusive);
#   2. a mutation whose run has at least one genuine `  FAIL[<token>] ` check line (the random per-run token the checker hands
#      run_checks.gd; a tokenless FAIL line or one on standard error, e.g. an engine diagnostic, is NOT genuine) is CAUGHT even if a crash,
#      script error or timeout follows (the fast mode never reaches the later crash and says plain
#      "caught"; the classic mode runs on and says `caught-with-warning`, a hygiene warning that does
#      not fail the run); a run with NO FAIL line that crashes, errors or times out is INCONCLUSIVE
#      in both modes and fails the run. `judge` (the verdict function) is also checked on synthetic logs;
#   3. the shard summary succeeds only when the matrix job succeeded and every shard has a
#      clean result file AND together they cover the whole mutation list (shard count, per-shard
#      counts, mode and filters checked against the list itself): one aborted shard, a missing,
#      duplicate or extra file, a cancelled job, a filtered or short run all fail it; caught-with-warning
#      mutations are listed and never fail it;
#   4. a focused run never prints "CHECKS PASSED";
#   5. a focused or quick step that times out or crashes without a failing check falls through to the full step, which decides.
# Needs the pinned Godot in the cache for 1, 2 and 4 (the judge cases and the summary need none): ./build-godot.sh --bootstrap-only.
#   tools/godot/test-mutation-runner.sh [summary|stale|crash|spoof|judge|focus|fallthrough ...]   (default: all)
set -Eeuo pipefail
REPO="$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd)"
# shellcheck source=tools/godot/godot.lock
source "$REPO/tools/godot/godot.lock"
REAL_CACHE="${SWORDSTER_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/swordster}"
GODOT_BIN="$REAL_CACHE/godot-$GODOT_VERSION/editor/godot"
ROOT="$(mktemp -d)"; trap 'rm -rf "$ROOT"' EXIT
failures=0
want=("$@"); ((${#want[@]})) || want=(summary stale crash spoof judge focus fallthrough)
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
  env -i HOME="$1/home" PATH="$PATH" SWORDSTER_CACHE_DIR="$REAL_CACHE" SWORDSTER_PROBE_CHILDREN="${SWORDSTER_PROBE_CHILDREN:-4}" ONLY=speed-zero FAST="$2" \
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
  result_line() { # shard shards ran caught survived inconclusive not_applied [filters] [selected] [total] [warned] [mode]
    echo "RESULT shard=$1 shards=$2 total=${10:-$FULL} selected=${9:-$FULL} filters=${8:-none} mode=${12:-classic} ran=$3 caught=$4 warned=${11:-0} survived=$5 inconclusive=$6 not_applied=$7 exit=0"
  }
  results() { # dir -> twelve clean classic results that together cover the whole list
    mkdir -p "$1"
    for ((s = 0; s < SHARDS; s++)); do
      n="$(expect "$s")"; result_line "$s" "$SHARDS" "$n" "$n" 0 0 0 > "$1/result-$s.txt"
    done
  }
  judge_set() { # name want-exit matrix-result dir [mode the workflow ran]
    local status=0 out="$ROOT/summary-$1.log"
    GITHUB_STEP_SUMMARY="$ROOT/summary-$1.md" MATRIX_RESULT="$3" SHARDS=$SHARDS MODE="${5:-classic}" "$REPO/tools/godot/mutation-summary.sh" "$4" >"$out" 2>&1 || status=$?
    if [[ "$status" == "$2" ]]; then report "summary: $1" PASS; else report "summary: $1" "exit $status, wanted $2" "$out"; fi
  }
  d="$ROOT/s-pass"; results "$d";                                              judge_set "all twelve shards pass" 0 success "$d"
  grep -q "all $SHARDS shards succeeded: $FULL of $FULL mutations caught (0 with a warning), $FULL of $FULL expected" "$ROOT/summary-all twelve shards pass.log" \
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
  d="$ROOT/s-fast"; results "$d"; sed -i 's/mode=classic/mode=fast/' "$d/result-4.txt"; judge_set "one shard that ran in fast mode in a classic pass" 1 success "$d"
  d="$ROOT/s-fast-all"; results "$d"; sed -i 's/mode=classic/mode=fast/' "$d"/result-*.txt; judge_set "a classic pass whose every shard ran fast" 1 success "$d"
  judge_set "a fast pass whose every shard ran fast" 0 success "$d" fast
  judge_set "a fast pass whose shards ran classic" 1 success "$ROOT/s-pass" fast
  # caught-with-warning: listed, never failing; but caught + warned must still account for every mutation run.
  d="$ROOT/s-warned"; results "$d"; n="$(expect 2)"; result_line 2 $SHARDS "$n" $((n - 2)) 0 0 0 none "$FULL" "$FULL" 2 > "$d/result-2.txt"
  printf '%s\n' "caught    speed-zero   (  FAIL x)   [focused, 2.0s]" "caught-with-warning pike-thrust-never-ends   (  FAIL a; then timed out)   [full, 130.0s]" "caught-with-warning cataclysm-field-never-ends   (  FAIL b; then killed by signal 6)   [full, 9.0s]" > "$d/shard-2.log"
  judge_set "two caught-with-warning mutations in one shard" 0 success "$d"
  grep -q "2 mutation(s) caught with a warning" "$ROOT/summary-two caught-with-warning mutations in one shard.md" && grep -q -- "- pike-thrust-never-ends" "$ROOT/summary-two caught-with-warning mutations in one shard.md" \
    && grep -q -- "- cataclysm-field-never-ends" "$ROOT/summary-two caught-with-warning mutations in one shard.md" \
    && report "summary: the warnings are named in the summary" PASS || report "summary: the warnings are named in the summary" "not listed" "$ROOT/summary-two caught-with-warning mutations in one shard.md"
  d="$ROOT/s-warned-fast"; results "$d"; sed -i 's/mode=classic/mode=fast/' "$d"/result-*.txt; n="$(expect 2)"; result_line 2 $SHARDS "$n" $((n - 2)) 0 0 0 none "$FULL" "$FULL" 2 fast > "$d/result-2.txt"
  judge_set "caught-with-warning mutations in a fast pass" 0 success "$d" fast
  d="$ROOT/s-warned-short"; results "$d"; n="$(expect 2)"; result_line 2 $SHARDS "$n" $((n - 2)) 0 0 0 none "$FULL" "$FULL" 1 > "$d/result-2.txt"
  judge_set "caught + caught-with-warning fall short of the mutations run" 1 success "$d"
  d="$ROOT/s-warned-missing"; results "$d"; sed -i 's/ warned=0//' "$d/result-2.txt"; judge_set "a result without the warned field" 1 success "$d"
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
  # The workflows generate their matrix from the same `shards` input they hand the checker and the summary, so the
  # only thing to pin is that every caller passes a mode and a positive shard count to the reusable pass.
  for wf in "$REPO/.github/workflows/mutation-gate.yml" "$REPO/.github/workflows/mutation.yml"; do
    mode="$(sed -n 's/^      mode: \([a-z]*\)$/\1/p' "$wf")"; shards="$(sed -n 's/^      shards: \([0-9]*\)$/\1/p' "$wf")"
    if [[ ( "$mode" == fast || "$mode" == classic ) && "$shards" =~ ^[1-9][0-9]*$ ]]; then report "workflow ${wf##*/}: mode $mode, $shards shards" PASS; else report "workflow ${wf##*/}: mode and shards" "mode='$mode' shards='$shards'"; fi
  done
  # The gate is a REQUIRED check, so its workflow triggers on every pull request (no path filter: a skipped workflow would leave a
  # required check pending for ever) and decides inside whether the expensive work is needed.
  gate_log="$ROOT/gate-workflow.log"
  if python3 -I - "$REPO/.github/workflows/mutation-gate.yml" "$REPO/.github/workflows/mutation-pass.yml" >"$gate_log" 2>&1 <<'PY'
import re, sys
gate, reusable = (open(p).read() for p in sys.argv[1:3])
on = re.search(r"^on:\n((?:(?:  .*)?\n)+)", gate, re.M).group(1)
assert "paths" not in on, "the gate's trigger has a path filter (paths / paths-ignore): a docs-only pull request would never report the required check"
assert re.search(r"^  pull_request:", on, re.M), "the gate no longer triggers on pull requests"
assert "mutation-gate-paths.sh" in gate and "skip: ${{ needs.changes.outputs.docs_only == 'true' }}" in gate, "the gate does not decide docs-only inside the workflow"
# `all shards` must always run and report: it is `if: always()` and the skip path succeeds without judging.
summary = reusable[reusable.index("  summary:"):]
assert "name: all shards" in summary and "if: always()" in summary, "the aggregate job must always run"
assert summary.count("if: ${{ !inputs.skip }}") == 3 and "if: ${{ inputs.skip }}" in summary, "the aggregate job must judge unless skipped, and say so when skipped"
assert "if: ${{ !inputs.skip }}" in reusable[reusable.index("  mutation:"):reusable.index("  summary:")], "the shards must be skipped when inputs.skip"
print("ok")
PY
  then report "workflow mutation-gate.yml: every pull request triggers it, docs-only skips the shards, all shards always reports" PASS
  else report "workflow mutation-gate.yml: every pull request triggers it, docs-only skips the shards, all shards always reports" "see log" "$gate_log"; fi
  # Which changes skip the expensive work.
  paths_is() { # name want file...
    local name="$1" want="$2"; shift 2
    local got; got="$(printf '%s\n' "$@" | "$REPO/tools/godot/mutation-gate-paths.sh")"
    if [[ "$got" == "docs_only=$want" ]]; then report "gate paths: $name" PASS; else report "gate paths: $name" "got '$got', wanted docs_only=$want"; fi
  }
  paths_is "documentation and root Markdown only skip" true docs/reference/waves.md docs/reference/waves/shot.png GLOSSARY.md AGENTS.md .github/ISSUE_TEMPLATE/bug.md .github/CONTRIBUTING.md LICENSE
  paths_is "a docs-only change skips" true docs/adr/0001-x.md
  for file in build-godot.sh game/main.py .github/workflows/build.yml .github/workflows/mutation-gate.yml .github/workflows/mutation-pass.yml .github/workflows/mutation.yml \
              godot/scripts/main.gd godot/README.md godot/tests/render_rate_checks.gd tools/godot/mutation-check.sh tools/reference/capture_waves.py tools/new-thing.sh godot/project.godot README.txt .github/dependabot.yml; do
    paths_is "$file gates" false "$file"
  done
  paths_is "one gating file among documentation gates" false docs/a.md godot/scripts/main.gd GLOSSARY.md
  paths_is "a nested Markdown file outside docs gates" false tools/notes/README.md
  paths_is "an empty file list (the API failed) gates" false
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
    grep -q '^RESULT .* ran=1 caught=0 warned=0 survived=0 inconclusive=0 not_applied=1$' "$log" || problem="RESULT line is not ran=1 caught=0 not_applied=1: $(grep '^RESULT' "$log")"
    report "stale mutation (FAST=$mode): not applied, never caught, run fails" "$problem" "$log"
  done
fi

# ---- 2. a genuine FAIL line decides; a crash with no FAIL line proves nothing
if wants crash; then
  need_godot
  sb="$(sandbox crash)"
  # The reviewer's mutant, made from the real `speed-zero` mutation: with the player's speed at
  # zero the movement checks FAIL CLEANLY first; then a kill() in a seed-41 scenario (the Flurry
  # and Warden fights) crashes the engine, which only a run that keeps going after the failure
  # ever reaches. The unmutated project is unaffected (the tripwire needs a speed of zero), so
  # the baseline passes.
  python3 -I - "$sb/repo/godot/scripts/sim/game_run.gd" <<'PY'
import re, sys
path = sys.argv[1]
text = open(path).read()
# Whatever parameters kill() has today (it gained `big: bool = false`; a later slice may add more): anchor on its name and first
# parameter only, and insert the tripwire right after the signature line.
pattern = re.compile(r"^func kill\(enemy: EnemyState[^\n]*\) -> void:\n", re.M)
assert len(pattern.findall(text)) == 1, "expected exactly one func kill(enemy: EnemyState, ...) in game_run.gd"
tripwire = "\tvar tripwire_speed: float = PLAYER_SPEED\n\tif tripwire_speed < 1.0 and scenario.seed == 41:\n\t\tOS.crash(\"test tripwire: a kill after the movement failure\")\n"
open(path, "w").write(pattern.sub(lambda m: m.group(0) + tripwire, text, count=1))
PY
  log="$ROOT/crash-fast.log"; status="$(checker "$sb" 1 "$log")"; problem=PASS
  [[ "$status" == 0 ]] || problem="exit $status, wanted 0"
  grep -q '^caught    speed-zero' "$log" || problem="fast mode did not call the clean failure caught"
  grep -q '^RESULT .* mode=fast ran=1 caught=1 warned=0 survived=0 inconclusive=0 not_applied=0$' "$log" || problem="RESULT: $(grep '^RESULT' "$log")"
  report "crash after a clean failure, FAST=1: caught (the crash is never reached)" "$problem" "$log"
  log="$ROOT/crash-classic.log"; status="$(checker "$sb" 0 "$log")"; problem=PASS
  [[ "$status" == 0 ]] || problem="exit $status, wanted 0 (a warning does not fail the run)"
  grep -q '^caught-with-warning speed-zero' "$log" || problem="classic mode did not call the crash after a failure caught-with-warning"
  grep -q '^INCONCLUSIVE ' "$log" && problem="classic mode called the crash after a failure inconclusive"
  grep -q '^RESULT .* mode=classic ran=1 caught=0 warned=1 survived=0 inconclusive=0 not_applied=0$' "$log" || problem="RESULT: $(grep '^RESULT' "$log")"
  report "crash after a clean failure, FAST=0: caught-with-warning, run passes" "$problem" "$log"

  # A crash BEFORE any check fails: no FAIL line, so no behavioural evidence, in both modes.
  sb="$(sandbox crash-no-fail)"
  python3 -I - "$sb/repo/godot/tests/run_checks.gd" <<'PY'
import sys
path = sys.argv[1]
text = open(path).read()
old = "func _run_all() -> void:\n"
assert text.count(old) == 1
open(path, "w").write(text.replace(old, old + "\tif GameRun.PLAYER_SPEED < 1.0:\n\t\tOS.crash(\"test tripwire: a crash before any check\")\n"))
PY
  for mode in 1 0; do
    log="$ROOT/crash-nofail-$mode.log"; status="$(checker "$sb" "$mode" "$log")"; problem=PASS
    [[ "$status" == 1 ]] || problem="exit $status, wanted 1"
    grep -q '^INCONCLUSIVE speed-zero' "$log" || problem="a crash with no failing check was not called inconclusive"
    grep -Eq '^caught' "$log" && problem="a crash with no failing check was called caught"
    grep -q '^RESULT .* ran=1 caught=0 warned=0 survived=0 inconclusive=1 not_applied=0$' "$log" || problem="RESULT: $(grep '^RESULT' "$log")"
    report "crash with no failing check (FAST=$mode): inconclusive, run fails" "$problem" "$log"
  done
fi

# ---- 2a. a diagnostic that merely looks like a failing check proves nothing
if wants spoof; then
  need_godot
  sb="$(sandbox spoof)"
  # The reviewer's spoof: with the player's speed at zero the very first check of the run is replaced by an engine diagnostic
  # whose message contains a newline and "  FAIL diagnostic only" (push_error goes to standard error), plus the same line
  # printed on standard output without the run's token; then the process exits 3. No check failed, so this proves nothing.
  python3 -I - "$sb/repo/godot/tests/run_checks.gd" <<'PY'
import sys
path = sys.argv[1]
text = open(path).read()
old = "func _run_all() -> void:\n"
assert text.count(old) == 1
open(path, "w").write(text.replace(old, old + "\tif GameRun.PLAYER_SPEED < 1.0:\n\t\tpush_error(\"not a check\\n  FAIL diagnostic only\")\n\t\tprint(\"not a check\\n  FAIL diagnostic only\")\n\t\tquit(3)\n\t\treturn\n"))
PY
  for mode in 1 0; do
    log="$ROOT/spoof-$mode.log"; status="$(checker "$sb" "$mode" "$log")"; problem=PASS
    [[ "$status" == 1 ]] || problem="exit $status, wanted 1"
    grep -q '^INCONCLUSIVE speed-zero' "$log" || problem="a diagnostic that looks like a failing check was not called inconclusive"
    grep -Eq '^caught' "$log" && problem="a diagnostic that looks like a failing check was called caught"
    grep -q '^RESULT .* ran=1 caught=0 warned=0 survived=0 inconclusive=1 not_applied=0$' "$log" || problem="RESULT: $(grep '^RESULT' "$log")"
    report "a spoofed FAIL diagnostic (FAST=$mode): inconclusive, run fails" "$problem" "$log"
  done
fi

# ---- 5. a step that proves nothing falls through to the next one
if wants fallthrough; then
  need_godot
  sb="$(sandbox fallthrough)"
  # With the player's speed at zero every run that skips the probes (the focused and the quick step) hangs before any
  # check; the full run is untouched and its movement checks fail. The short timeouts keep the test fast. The hang used to end
  # the mutation INCONCLUSIVE without a full attempt; it must now be CAUGHT by the full step.
  python3 -I - "$sb/repo/godot/tests/run_checks.gd" <<'PY'
import sys
path = sys.argv[1]
text = open(path).read()
old = "func _run_all() -> void:\n"
assert text.count(old) == 1
open(path, "w").write(text.replace(old, old + "\tif GameRun.PLAYER_SPEED < 1.0 and _skip_probes:\n\t\tOS.delay_msec(600000)\n"))
PY
  log="$ROOT/fallthrough.log"; status=0
  env -i HOME="$sb/home" PATH="$PATH" SWORDSTER_CACHE_DIR="$REAL_CACHE" SWORDSTER_PROBE_CHILDREN="${SWORDSTER_PROBE_CHILDREN:-4}" ONLY=speed-zero FAST=1 QUICK_TIMEOUT=6 FULL_TIMEOUT=120 \
    "$sb/repo/tools/godot/mutation-check.sh" >"$log" 2>&1 || status=$?
  problem=PASS
  [[ "$status" == 0 ]] || problem="exit $status, wanted 0"
  grep -q '^caught    speed-zero.*\[full, ' "$log" || problem="the quick step's timeout did not fall through to a full step that caught it"
  grep -q '^INCONCLUSIVE ' "$log" && problem="a quick-step timeout ended inconclusive without the full step deciding"
  grep -q '^RESULT .* mode=fast ran=1 caught=1 warned=0 survived=0 inconclusive=0 not_applied=0$' "$log" || problem="RESULT: $(grep '^RESULT' "$log")"
  report "a timeout in the quick and focused steps falls through to the full step" "$problem" "$log"
fi

# ---- 2b. the verdict function on synthetic logs (no engine needed)
if wants judge; then
  eval "$(sed -n '/^judge() {/,/^}/p' "$REPO/tools/godot/mutation-check.sh")"
  VERDICT_TOKEN=3f9ac1d2e0b74a58
  verdict_is() { # name want status mode log...
    local name="$1" want="$2" status="$3" mode="$4"; shift 4
    judge "$status" "$(printf '%s\n' "$@")" "$mode"
    if [[ "$VERDICT" == "$want" ]]; then report "judge: $name" PASS; else report "judge: $name" "got $VERDICT ($DETAIL), wanted $want"; fi
  }
  fail="  FAIL[$VERDICT_TOKEN] moving right gains x only"
  verdict_is "clean failure verdict" CAUGHT 1 classic "$fail" "CHECKS FAILED: 1 of 5"
  verdict_is "failure, then a timeout" WARNED 124 classic "$fail"
  verdict_is "failure, then the engine aborts (signal 6)" WARNED 134 classic "$fail"
  verdict_is "failure, then a segfault (signal 11)" WARNED 139 full "$fail" "CHECKS FAILED: 1 of 5"
  verdict_is "failure, a script error, then the verdict" WARNED 1 classic "$fail" "SCRIPT ERROR: Invalid access" "CHECKS FAILED: 1 of 5"
  verdict_is "failure, then exit 1 without a verdict" WARNED 1 classic "$fail"
  verdict_is "failure, then an odd exit status" WARNED 3 classic "$fail" "CHECKS FAILED: 1 of 5"
  verdict_is "failure in a quick run, then a crash" WARNED 139 quick "$fail"
  verdict_is "a crash with no failure line" INCONCLUSIVE 139 classic "  ok   something" "ERROR: crash handler"
  verdict_is "a timeout with no failure line" INCONCLUSIVE 124 classic "  ok   something"
  verdict_is "a script error with no failure line" INCONCLUSIVE 1 classic "SCRIPT ERROR: Invalid access" "CHECKS FAILED: 1 of 5"
  verdict_is "FAIL inside an engine error message is not a failing check" INCONCLUSIVE 134 classic "ERROR: lost the node   FAIL in the middle of a line" "  ok   x"
  verdict_is "a tokenless FAIL line is not a failing check" INCONCLUSIVE 3 classic "not a check" "  FAIL diagnostic only"
  verdict_is "a FAIL line with another run's token is not a failing check" INCONCLUSIVE 1 classic "  FAIL[0000deadbeef] x" "CHECKS FAILED: 1 of 5"
  verdict_is "a FAIL line that does not start the line is not a failing check" INCONCLUSIVE 1 classic "x  FAIL[$VERDICT_TOKEN] y" "CHECKS FAILED: 1 of 5"
  verdict_is "a verdict line without any FAIL line" INCONCLUSIVE 1 classic "CHECKS FAILED: 1 of 5"
  verdict_is "no output at all" INCONCLUSIVE 0 classic ""
  verdict_is "the unmutated suite" SURVIVED 0 classic "  ok   x" "CHECKS PASSED: 5"
  verdict_is "a clean quick run" PARTIAL 0 quick "  ok   x" "CHECKS PARTIAL: 5 (--skip-probes: the render-rate probes did not run)"
  verdict_is "a quick run with a script error is not partial" INCONCLUSIVE 0 quick "SCRIPT ERROR: x" "CHECKS PARTIAL: 5"
  # Standard error is never searched for failures; it is only read to notice a script error.
  judge 1 "$(printf '%s\n' "  ok   x" "CHECKS FAILED: 1 of 5")" classic "$(printf '%s\n' "not a check" "  FAIL[$VERDICT_TOKEN] spoofed on standard error")"
  if [[ "$VERDICT" == INCONCLUSIVE ]]; then report "judge: a token line on standard error is not a failing check" PASS; else report "judge: a token line on standard error is not a failing check" "got $VERDICT ($DETAIL)"; fi
  judge 0 "$(printf '%s\n' "  ok   x" "CHECKS PARTIAL: 5")" quick "SCRIPT ERROR: on standard error"
  if [[ "$VERDICT" == INCONCLUSIVE ]]; then report "judge: a script error on standard error is not a clean partial run" PASS; else report "judge: a script error on standard error is not a clean partial run" "got $VERDICT ($DETAIL)"; fi
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
