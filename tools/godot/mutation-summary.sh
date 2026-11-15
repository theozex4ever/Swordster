#!/usr/bin/env bash
# Judges a full mutation pass from the per-shard result files that
# .github/workflows/mutation.yml collects (one `result-<shard>.txt` per shard, the shard's
# `RESULT …` line from tools/godot/mutation-check.sh plus the `exit=<status>` the shard step
# recorded). It exits 0 only when the pass covered the WHOLE mutation list and every shard is
# accounted for and clean:
#   - the matrix job as a whole succeeded (MATRIX_RESULT=success; a failed, cancelled or
#     timed-out shard makes it anything else, whatever files survived),
#   - the expected assignment is derived here, not taken from the results: the size of the full
#     list comes from `SECTIONS=count mutation-check.sh` of the same commit, SHARDS from the
#     workflow (and, when WORKFLOW_FILE is set, it must equal the length of that file's matrix),
#     and shard i must run exactly the mutations i, i+SHARDS, i+2*SHARDS, ... of the list,
#   - every shard 0..SHARDS-1 is present exactly once (no missing, duplicate or extra file) with
#     exit=0, mode=classic, shards=SHARDS, total and selected equal to the full list, no
#     ONLY/SECTIONS/CORE filter (filters=none), ran equal to its expected count, caught == ran,
#     and zero survived / inconclusive / not_applied / unfinished,
#   - the shards together ran exactly the full list.
# A markdown table goes to $GITHUB_STEP_SUMMARY (or stdout); the failures are listed and
# reported as ::error annotations.
#
#   MATRIX_RESULT=success SHARDS=12 [WORKFLOW_FILE=.github/workflows/mutation.yml] \
#     tools/godot/mutation-summary.sh <results-dir>
set -Eeuo pipefail
dir="${1:?usage: mutation-summary.sh <results-dir>}"
SHARDS="${SHARDS:?SHARDS must be set to the number of shards}"
MATRIX_RESULT="${MATRIX_RESULT:-unknown}"
out="${GITHUB_STEP_SUMMARY:-/dev/stdout}"

# The full list, counted by the checker script itself (it reads its own mutation list).
CHECKER="${BASH_SOURCE[0]%/*}/mutation-check.sh"
FULL="$(SECTIONS=count "$CHECKER" 2>/dev/null || true)"
[[ "$FULL" =~ ^[1-9][0-9]*$ ]] || { echo "::error title=Mutation checks failed::cannot count the mutation list with $CHECKER" >&2; exit 1; }
[[ "$SHARDS" =~ ^[1-9][0-9]*$ ]] || { echo "::error title=Mutation checks failed::SHARDS must be a positive integer (got '$SHARDS')" >&2; exit 1; }

problems=()
if [[ -n "${WORKFLOW_FILE:-}" ]]; then
  # The matrix line looks like `shard: [0, 1, 2, ...]`; its length is the shard count the CI job ran.
  matrix_line="$(grep -E '^[[:space:]]+shard:[[:space:]]*\[' "$WORKFLOW_FILE" | head -n 1 || true)"
  matrix_shards="$(grep -o '[0-9][0-9]*' <<<"${matrix_line#*[}" | wc -l)"
  ((matrix_shards == SHARDS)) || problems+=("the workflow matrix has $matrix_shards shards but SHARDS is $SHARDS")
fi
[[ "$MATRIX_RESULT" == success ]] || problems+=("the shard job finished as '$MATRIX_RESULT', not 'success' (a shard failed, was cancelled or timed out)")

{
  echo "### Mutation checks, full pass (classic mode: every mutation runs the complete suite)"
  echo
  echo "| Shard | Ran | Caught | Survived | Inconclusive | Not applied | Exit | Verdict |"
  echo "| ---: | ---: | ---: | ---: | ---: | ---: | ---: | :--- |"
} >> "$out"

declare -A seen=()
declare -A total=([ran]=0 [caught]=0 [survived]=0 [inconclusive]=0 [not_applied]=0)
for ((s = 0; s < SHARDS; s++)); do
  file="$dir/result-$s.txt"
  if [[ ! -f "$file" ]]; then
    echo "| $s | | | | | | | **MISSING** |" >> "$out"
    problems+=("shard $s: no result file")
    continue
  fi
  declare -A kv=()
  fields=(); read -r -a fields < "$file" || true
  for field in "${fields[@]}"; do
    [[ "$field" == *=* ]] && kv[${field%%=*}]="${field#*=}"
  done
  bad=()
  for key in shard shards total selected ran caught survived inconclusive not_applied exit; do
    [[ "${kv[$key]:-}" =~ ^[0-9]+$ ]] || bad+=("$key is missing or not a number")
  done
  if ((${#bad[@]} == 0)); then
    [[ "${kv[shard]}" == "$s" ]] || bad+=("the file says shard ${kv[shard]}")
    if [[ -n "${seen[${kv[shard]}]+x}" ]]; then bad+=("shard index ${kv[shard]} is reported twice (also by ${seen[${kv[shard]}]})"); fi
    seen[${kv[shard]}]="result-$s.txt"
    ((kv[shards] == SHARDS)) || bad+=("it was run with shards=${kv[shards]}, the matrix has $SHARDS")
    ((kv[total] == FULL)) || bad+=("it knows ${kv[total]} mutations, the list has $FULL")
    ((kv[selected] == FULL)) || bad+=("it selected ${kv[selected]} of $FULL mutations")
    [[ "${kv[filters]:-}" == none ]] || bad+=("a selection filter was active (filters=${kv[filters]:-missing})")
    expected=$(((FULL - s + SHARDS - 1) / SHARDS)); ((s < FULL)) || expected=0
    ((kv[ran] == expected)) || bad+=("it ran ${kv[ran]} mutations, expected $expected")
    [[ "${kv[exit]}" == 0 ]] || bad+=("the shard exited ${kv[exit]}")
    [[ "${kv[mode]:-}" == classic ]] || bad+=("mode is '${kv[mode]:-}', not classic")
    ((kv[ran] > 0)) || bad+=("it ran no mutation")
    ((kv[caught] == kv[ran])) || bad+=("${kv[caught]} of ${kv[ran]} caught")
    ((kv[survived] + kv[inconclusive] + kv[not_applied] == 0)) || bad+=("${kv[survived]} survived, ${kv[inconclusive]} inconclusive, ${kv[not_applied]} not applied")
    for key in "${!total[@]}"; do total[$key]=$((total[$key] + kv[$key])); done
  fi
  if ((${#bad[@]})); then
    echo "| $s | ${kv[ran]:-?} | ${kv[caught]:-?} | ${kv[survived]:-?} | ${kv[inconclusive]:-?} | ${kv[not_applied]:-?} | ${kv[exit]:-?} | **FAILED** |" >> "$out"
    problems+=("shard $s: $(IFS=';'; echo "${bad[*]}")")
  else
    echo "| $s | ${kv[ran]} | ${kv[caught]} | ${kv[survived]} | ${kv[inconclusive]} | ${kv[not_applied]} | ${kv[exit]} | ok |" >> "$out"
  fi
  unset kv
done
echo "| **all** | **${total[ran]}** | **${total[caught]}** | **${total[survived]}** | **${total[inconclusive]}** | **${total[not_applied]}** | | |" >> "$out"
((total[ran] > 0)) || problems+=("no mutation ran at all")
((total[ran] == FULL)) || problems+=("the shards ran ${total[ran]} mutations, the full list has $FULL")
for file in "$dir"/result-*.txt; do
  [[ -e "$file" ]] || continue
  index="${file##*/result-}"; index="${index%.txt}"
  [[ "$index" =~ ^[0-9]+$ ]] && ((10#$index < SHARDS)) || problems+=("unexpected result file ${file##*/} (shards are 0..$((SHARDS - 1)))")
done

if ((${#problems[@]})); then
  { echo; echo "**Mutation checks FAILED:**"; for p in "${problems[@]}"; do echo "- $p"; done; } >> "$out"
  for p in "${problems[@]}"; do echo "::error title=Mutation checks failed::$p"; done
  exit 1
fi
echo "all $SHARDS shards succeeded: ${total[caught]} of ${total[ran]} mutations caught, ${total[ran]} of $FULL expected"
