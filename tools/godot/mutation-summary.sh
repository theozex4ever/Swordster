#!/usr/bin/env bash
# Judges a full mutation pass from the per-shard result files that
# .github/workflows/mutation.yml collects (one `result-<shard>.txt` per shard, the shard's
# `RESULT …` line from tools/godot/mutation-check.sh plus the `exit=<status>` the shard step
# recorded). It exits 0 only when EVERY shard is accounted for and clean:
#   - the matrix job as a whole succeeded (MATRIX_RESULT=success; a failed, cancelled or
#     timed-out shard makes it anything else, whatever files survived),
#   - every shard 0..SHARDS-1 has a well-formed result file with exit=0, mode=classic,
#     ran > 0, caught == ran, and zero survived / inconclusive / not_applied / unfinished.
# A markdown table goes to $GITHUB_STEP_SUMMARY (or stdout); the failures are listed and
# reported as ::error annotations.
#
#   MATRIX_RESULT=success SHARDS=12 tools/godot/mutation-summary.sh <results-dir>
set -Eeuo pipefail
dir="${1:?usage: mutation-summary.sh <results-dir>}"
SHARDS="${SHARDS:?SHARDS must be set to the number of shards}"
MATRIX_RESULT="${MATRIX_RESULT:-unknown}"
out="${GITHUB_STEP_SUMMARY:-/dev/stdout}"

problems=()
[[ "$MATRIX_RESULT" == success ]] || problems+=("the shard job finished as '$MATRIX_RESULT', not 'success' (a shard failed, was cancelled or timed out)")

{
  echo "### Mutation checks, full pass (classic mode: every mutation runs the complete suite)"
  echo
  echo "| Shard | Ran | Caught | Survived | Inconclusive | Not applied | Exit | Verdict |"
  echo "| ---: | ---: | ---: | ---: | ---: | ---: | ---: | :--- |"
} >> "$out"

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
  for key in shard ran caught survived inconclusive not_applied exit; do
    [[ "${kv[$key]:-}" =~ ^[0-9]+$ ]] || bad+=("$key is missing or not a number")
  done
  if ((${#bad[@]} == 0)); then
    [[ "${kv[shard]}" == "$s" ]] || bad+=("the file says shard ${kv[shard]}")
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

if ((${#problems[@]})); then
  { echo; echo "**Mutation checks FAILED:**"; for p in "${problems[@]}"; do echo "- $p"; done; } >> "$out"
  for p in "${problems[@]}"; do echo "::error title=Mutation checks failed::$p"; done
  exit 1
fi
echo "all $SHARDS shards succeeded: ${total[caught]} of ${total[ran]} mutations caught"
