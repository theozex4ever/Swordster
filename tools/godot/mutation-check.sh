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
#
# Speed (issue #35). Nearly all of a full run_checks.gd run (about 45 s) is the render-rate
# probes: sub-Godot processes at 5/20/60/240 fps in each fight group. Almost every mutation is
# rejected by a behavioural check long before them, so each mutation is judged in up to three steps:
#   1. focused: the same quick run restricted to the check group of the mutation's section
#      (`--focus=warden_maelstrom`, see godot/tests/check_focus.gd), so the most relevant
#      checks run first and most mutations end in a second or two.
#   2. quick: `run_checks.gd -- --fail-fast --skip-probes` stops at the first failing check
#      and never launches a probe (a few seconds). A clean failure verdict in step 1 or 2 is
#      CAUGHT; it is the same verdict the full run would give, because these runs only run
#      fewer checks and any check that fails there fails there too.
#   3. full: only when the quick run passes everything it ran (it prints "CHECKS PARTIAL",
#      never "CHECKS PASSED") is the project run again with the probes, still fail-fast.
#      Only a full run that prints "CHECKS PASSED" makes a mutation SURVIVED.
# FAST=0 restores the original behaviour (one complete, non-fail-fast run per mutation, probes
# included) and is the STRICT definition of a caught mutation: the checks must reject the project
# AND the complete run must then still end in the ordinary failure verdict. The CI full pass
# (.github/workflows/mutation.yml) runs FAST=0 and is the authoritative verdict.
# The one difference to know: a fast run stops at the first clean failing check, so a mutation
# that fails a check cleanly and would only CRASH (or time out) in a LATER check is CAUGHT in
# fast mode and INCONCLUSIVE in classic mode. Fast mode treats a clean failure reported through
# run_checks.gd's verdict path as behavioural evidence; classic mode insists on the whole run.
#
# Selection (all compose; every mutation lives in the `slice #N` section it is listed under):
#   SECTIONS=pike,warden   only those sections, plus `core` (the ungrouped mutations at the top
#                          of the list: simulation basics such as speed, pause, restart and the
#                          wall clamp). A section is named by the first word of its header title
#                          or by its slice number (SECTIONS=14 or SECTIONS='#14'). CORE=0 leaves
#                          core out; SECTIONS=all or unset selects every section;
#                          SECTIONS=list prints the sections and exits.
#   ONLY=a,b               only the named mutations (rerun after fixing a check), checked
#                          against the sections too; an unknown name is refused.
#   SHARD=i SHARDS=n       every n-th mutation of the selection starting at i (0-based), so n
#                          copies of this script can run in parallel over the same selection.
#   SECTIONS=count         prints the number of mutations in the whole list and exits (the CI
#                          summary uses it to know what a complete pass must cover).
# Each shard ends with a `RESULT shard=… shards=… total=… selected=… filters=… mode=… ran=…
# caught=… survived=… inconclusive=… not_applied=…` line. `total` is the size of the whole list,
# `selected` the size of the selection before sharding and `filters` names every selection
# variable that was set (ONLY, SECTIONS, CORE; `none` when none was), so a pass that does not
# cover the whole list can be told apart from a complete one (tools/godot/mutation-summary.sh).
# `caught` counts only mutations that were applied and cleanly rejected;
# a mutation whose search text no longer matches is `not_applied` (reported, never caught, and it
# fails the run); `ran` counts every mutation started, so ran = caught + survived + inconclusive
# + not_applied unless the script died in the middle of one.
set -Eeuo pipefail
REPO="$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd)"
# shellcheck source=tools/godot/godot.lock
source "$REPO/tools/godot/godot.lock"
CACHE_ROOT="${SWORDSTER_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/swordster}"
GODOT_BIN="$CACHE_ROOT/godot-$GODOT_VERSION/editor/godot"

# SHARDS must be a positive integer and SHARD an integer in [0, SHARDS): anything else would
# silently select no mutations and report success, so it is refused before any work starts.
SHARD="${SHARD:-0}" SHARDS="${SHARDS:-1}"
if [[ ! "$SHARDS" =~ ^[1-9][0-9]*$ || ! "$SHARD" =~ ^[0-9]+$ ]] || ((10#$SHARD >= 10#$SHARDS)); then
  echo "invalid shard selection: SHARDS must be a positive integer and SHARD an integer with 0 <= SHARD < SHARDS (got SHARD=$SHARD SHARDS=$SHARDS)" >&2
  exit 2
fi
SHARD=$((10#$SHARD)) SHARDS=$((10#$SHARDS))
FAST="${FAST:-1}"
[[ "$FAST" == 0 || "$FAST" == 1 ]] || { echo "FAST must be 0 or 1 (got $FAST)" >&2; exit 2; }

# The mutation list below is plain script text: read it back to learn which section each
# mutation is in, so a section added later is selectable without registering it anywhere.
declare -A SECTION_OF=() SECTION_COUNT=() SECTION_ALIAS=()
MUTATION_NAMES=(); SECTION_KEYS=(core); SECTION_COUNT[core]=0
section=core
while IFS= read -r line; do
  if [[ "$line" =~ ^"# --- "(.+)$ ]]; then
    title="${BASH_REMATCH[1]}"
    key="${title%% *}"; key="${key,,}"; key="${key//[^a-z0-9]/}"
    [[ -n "$key" ]] || key="section$((${#SECTION_KEYS[@]} + 1))"
    section="$key"
    if [[ -z "${SECTION_COUNT[$section]+x}" ]]; then SECTION_COUNT[$section]=0; SECTION_KEYS+=("$section"); fi
    if [[ "$title" =~ \(slice\ \#([0-9]+)\) ]]; then SECTION_ALIAS[${BASH_REMATCH[1]}]="$section"; fi
  elif [[ "$line" =~ ^mutate[[:space:]]+([^[:space:]]+) ]]; then
    SECTION_OF[${BASH_REMATCH[1]}]="$section"; MUTATION_NAMES+=("${BASH_REMATCH[1]}")
    SECTION_COUNT[$section]=$((SECTION_COUNT[$section] + 1))
  fi
done < "${BASH_SOURCE[0]}"

SECTIONS="${SECTIONS:-}"
if [[ "${SECTIONS,,}" == count ]]; then echo "${#MUTATION_NAMES[@]}"; exit 0; fi
if [[ "${SECTIONS,,}" == list ]]; then
  for key in "${SECTION_KEYS[@]}"; do
    aliases=""; for slice in "${!SECTION_ALIAS[@]}"; do [[ "${SECTION_ALIAS[$slice]}" == "$key" ]] && aliases=" (slice #$slice)"; done
    printf '%-12s %3d mutations%s\n' "$key" "${SECTION_COUNT[$key]}" "$aliases"
  done
  exit 0
fi
# The pinned engine is needed from here on (listing and counting the mutations is not).
[[ -x "$GODOT_BIN" ]] || { echo "pinned Godot missing; run ./build-godot.sh --bootstrap-only" >&2; exit 1; }
# Every selection variable that is set, recorded in the RESULT line: a complete pass has none.
filters=()
[[ -z "$SECTIONS" ]] || filters+=(SECTIONS)
[[ -z "${ONLY:-}" ]] || filters+=(ONLY)
[[ -z "${CORE:-}" ]] || filters+=(CORE)
FILTERS=none; ((${#filters[@]} == 0)) || FILTERS="$(IFS=+; echo "${filters[*]}")"
declare -A WANT_SECTION=()
if [[ -n "$SECTIONS" && "${SECTIONS,,}" != all ]]; then
  IFS=',' read -r -a requested <<<"$SECTIONS"
  for token in "${requested[@]}"; do
    token="${token//[[:space:]]/}"; token="${token,,}"; token="${token#\#}"; token="${token#slice}"; token="${token#\#}"
    if [[ -n "${SECTION_COUNT[$token]+x}" ]]; then WANT_SECTION[$token]=1
    elif [[ -n "${SECTION_ALIAS[$token]+x}" ]]; then WANT_SECTION[${SECTION_ALIAS[$token]}]=1
    else
      echo "unknown section '$token' in SECTIONS=$SECTIONS (SECTIONS=list shows them: ${SECTION_KEYS[*]})" >&2
      exit 2
    fi
  done
  [[ "${CORE:-1}" == 0 ]] || WANT_SECTION[core]=1
fi
declare -A WANT_ONLY=()
if [[ -n "${ONLY:-}" ]]; then
  IFS=',' read -r -a requested <<<"$ONLY"
  for token in "${requested[@]}"; do
    [[ -n "${SECTION_OF[$token]+x}" ]] || { echo "unknown mutation '$token' in ONLY=$ONLY" >&2; exit 2; }
    WANT_ONLY[$token]=1
  done
fi
# PLAN is this shard's share of the selection. Sharding is over the selected list (not all
# mutations), so a section run is spread evenly too.
declare -A PLAN=()
selected=0
for name in "${MUTATION_NAMES[@]}"; do
  if ((${#WANT_SECTION[@]})) && [[ -z "${WANT_SECTION[${SECTION_OF[$name]}]+x}" ]]; then continue; fi
  if ((${#WANT_ONLY[@]})) && [[ -z "${WANT_ONLY[$name]+x}" ]]; then continue; fi
  if ((selected++ % SHARDS == SHARD)); then PLAN[$name]=1; fi
done

survived=0; inconclusive=0; ran=0; caught=0; not_applied=0
report_result() { echo "RESULT shard=$SHARD shards=$SHARDS total=${#MUTATION_NAMES[@]} selected=$selected filters=$FILTERS mode=$([[ "$FAST" == 1 ]] && echo fast || echo classic) ran=$ran caught=$caught survived=$survived inconclusive=$inconclusive not_applied=$not_applied"; }
if ((${#PLAN[@]} == 0)); then
  echo "shard $SHARD of $SHARDS: no mutations selected ($selected selected in all)"; report_result; exit 0
fi

SCRATCH="$(mktemp -d)"; trap 'report_result; rm -rf "$SCRATCH"' EXIT
export XDG_DATA_HOME="$SCRATCH/home/data" XDG_CONFIG_HOME="$SCRATCH/home/config" XDG_CACHE_HOME="$SCRATCH/home/cache"
cp -a "$REPO/godot" "$SCRATCH/base"; rm -rf "$SCRATCH/base/.godot"
"$GODOT_BIN" --headless --path "$SCRATCH/base" --import >/dev/null 2>&1

# run_checks DIR MODE: classic = the complete run (every failure reported, probes included);
# quick = fail-fast and no probes; full = fail-fast with the probes.
run_checks() { # dir mode [focus group]
  local extra=()
  case "$2" in
    quick) extra=(-- --fail-fast --skip-probes) ;;
    full) extra=(-- --fail-fast) ;;
  esac
  [[ -z "${3:-}" ]] || extra+=("--focus=$3")
  timeout 120 "$GODOT_BIN" --headless --path "$1" --script res://tests/run_checks.gd "${extra[@]}" 2>&1
}

# The check group a section belongs to, named like its file without `_checks.gd`: "none" for
# core (run_checks.gd's own checks), the table for the early slices, and for any later section
# the one group file that starts with the section's key or whose first word is the key's prefix
# (pike -> pike_skewer_checks.gd). Empty means "no known group": the focused step is skipped.
declare -A FOCUS_OF=([core]=none [fang]=survival_loop [runners]=crowd_and_wall [spitters]=spitter_and_parry
                     [viper]=viper_flurry [elemental]=elemental_condition [warden]=warden_maelstrom)
focus_group() {
  local key="$1" file stem
  if [[ -n "${FOCUS_OF[$key]+x}" ]]; then echo "${FOCUS_OF[$key]}"; return; fi
  for file in "$REPO"/godot/tests/*_checks.gd; do
    stem="${file##*/}"; stem="${stem%_checks.gd}"
    if [[ "$stem" == "$key"* || "$key" == "${stem%%_*}"* ]]; then echo "$stem"; return; fi
  done
}

# judge STATUS LOG MODE sets VERDICT to CAUGHT, SURVIVED, PARTIAL (a clean quick run: nothing
# failed, but the probes did not run) or INCONCLUSIVE, and DETAIL to say why.
judge() {
  local status="$1" log="$2" mode="$3"
  VERDICT=INCONCLUSIVE; DETAIL=""
  if grep -q '^CHECKS PASSED' <<<"$log" && ((status == 0)); then
    VERDICT=SURVIVED
  elif [[ "$mode" == quick ]] && grep -q '^CHECKS PARTIAL' <<<"$log" && ((status == 0)) \
       && ! grep -Eq 'SCRIPT ERROR|Parse Error|Failed to load script' <<<"$log"; then
    VERDICT=PARTIAL
  elif ((status == 1)) && grep -q '^CHECKS FAILED' <<<"$log" && grep -q '^  FAIL ' <<<"$log" \
       && ! grep -Eq 'SCRIPT ERROR|Parse Error|Failed to load script' <<<"$log"; then
    VERDICT=CAUGHT; DETAIL="$(grep -m1 '^  FAIL ' <<<"$log" | cut -c1-90)"
  else
    DETAIL="exit $status, no behavioural verdict: $(tail -n 1 <<<"$log" | cut -c1-70)"
  fi
}

# The unmodified project must be accepted before any rejection means anything. The quick run
# gates every mutation; the complete run (what the build requires) is only needed once a
# mutation gets past the quick run, so it is done at the first such mutation.
baseline_full=0
check_baseline() { # mode
  local out status=0
  out="$(run_checks "$SCRATCH/base" "$1")" || status=$?
  judge "$status" "$out" "$1"
  if [[ "$1" == quick && "$VERDICT" != PARTIAL ]] || [[ "$1" != quick && "$VERDICT" != SURVIVED ]]; then
    echo "baseline: unmodified project does NOT pass its checks ($1 run)"; echo "$out" | tail -20; exit 1
  fi
  echo "baseline: $(grep -m1 '^CHECKS \(PASSED\|PARTIAL\)' <<<"$out") ($1 run)"
}
if [[ "$FAST" == 1 ]]; then check_baseline quick; else check_baseline classic; baseline_full=1; fi

declare -A FOCUS_CACHE=()
for key in "${SECTION_KEYS[@]}"; do FOCUS_CACHE[$key]="$(focus_group "$key")"; done

mutate() { # name file old new
  local name="$1" file="$2" old="$3" new="$4" dir="$SCRATCH/m-$1"
  [[ -n "${PLAN[$name]+x}" ]] || return 0
  ran=$((ran + 1))
  local began=$EPOCHREALTIME
  cp -a "$SCRATCH/base" "$dir"
  # A search text that no longer matches exactly once (or a missing file) means no bug was
  # injected: that is its own outcome, never a rejection. Nothing is run for it.
  if ! python3 -I - "$dir/$file" "$old" "$new" <<'PY'
import sys
path, old, new = sys.argv[1:4]
try:
    text = open(path).read()
except OSError:
    raise SystemExit(1)
if text.count(old) != 1:
    raise SystemExit(1)
open(path, "w").write(text.replace(old, new))
PY
  then
    rm -rf "$dir"
    echo "MUTATION NOT APPLIED: $name   <-- the search text in $file no longer matches exactly once"
    not_applied=$((not_applied + 1))
    return 0
  fi
  local verdict="" detail="" attempt status log focus="${FOCUS_CACHE[${SECTION_OF[$name]}]-}"
  for attempt in 1 2; do
    if [[ "$FAST" == 1 ]]; then
      VERDICT=PARTIAL
      if [[ -n "$focus" ]]; then
        status=0; log="$(run_checks "$dir" quick "$focus")" || status=$?
        judge "$status" "$log" quick
      fi
      if [[ "$VERDICT" == PARTIAL ]]; then
        status=0; log="$(run_checks "$dir" quick)" || status=$?
        judge "$status" "$log" quick
      fi
      if [[ "$VERDICT" == PARTIAL ]]; then
        ((baseline_full)) || { check_baseline full; baseline_full=1; }
        status=0; log="$(run_checks "$dir" full)" || status=$?
        judge "$status" "$log" full
      fi
    else
      status=0; log="$(run_checks "$dir" classic)" || status=$?
      judge "$status" "$log" classic
    fi
    verdict="$VERDICT"; detail="$DETAIL"
    [[ "$verdict" != INCONCLUSIVE ]] && break
    ((attempt == 1)) && echo "retry     $name   (inconclusive run: $detail)"
  done
  rm -rf "$dir"
  local took; took="$(awk -v a="$began" -v b="$EPOCHREALTIME" 'BEGIN { printf "%.1fs", b - a }')"
  case "$verdict" in
    CAUGHT)       echo "caught    $name   ($detail)   [$took]"; caught=$((caught + 1)) ;;
    SURVIVED)     echo "SURVIVED  $name   <-- checks failed to detect this bug   [$took]"; survived=$((survived + 1)) ;;
    INCONCLUSIVE) echo "INCONCLUSIVE $name   <-- $detail   [$took]"; inconclusive=$((inconclusive + 1)) ;;
  esac
}

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
mutate double-kill          scripts/sim/game_run.gd  "func kill(enemy: EnemyState, direction: Vector2, big: bool = false) -> void:
	if enemy.dead:
		return
	enemy.dead = true
	kills += 1" "func kill(enemy: EnemyState, direction: Vector2, big: bool = false) -> void:
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
mutate wave-never-clears    scripts/sim/wave_director.gd "		if _wave_count > 0 and wave >= _wave_count:
			survived = true" "		if _wave_count > 0 and wave >= _wave_count:
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
			kill(hit, SimMath.norm(launched.velocity, rng), true)" "		if false:
			kill(hit, SimMath.norm(launched.velocity, rng), true)"
mutate bowl-not-reported    scripts/sim/game_run.gd "		add_cue(SimCue.make(SimCue.Kind.BOWLED, (launched.position + hit.position) * 0.5, SimMath.norm(launched.velocity, rng, Vector2.RIGHT, true), int(BOWL_DAMAGE)))" "		pass"
mutate wall-threshold       scripts/sim/game_run.gd "WALL_SLAM_MIN_SPEED: float = 380.0" "WALL_SLAM_MIN_SPEED: float = 300.0"
mutate wall-base-damage     scripts/sim/game_run.gd "WALL_SLAM_BASE_DAMAGE: float = 6.0" "WALL_SLAM_BASE_DAMAGE: float = 4.0"
mutate wall-speed-damage    scripts/sim/game_run.gd "WALL_SLAM_DAMAGE_PER_SPEED: float = 0.04" "WALL_SLAM_DAMAGE_PER_SPEED: float = 0.02"
mutate wall-stun-cap        scripts/sim/game_run.gd "WALL_SLAM_STUN_CAP: float = 0.15" "WALL_SLAM_STUN_CAP: float = 0.3"
mutate wall-hitstop         scripts/sim/game_run.gd "WALL_SLAM_HITSTOP: float = 0.04" "WALL_SLAM_HITSTOP: float = 0.0"
mutate wall-shake           scripts/sim/game_run.gd "WALL_SLAM_SHAKE: float = 0.18" "WALL_SLAM_SHAKE: float = 0.0"
mutate wall-slam-never-kills scripts/sim/game_run.gd "	if enemy.hp <= 0.0 and not enemy.dead:
		kill(enemy, SimMath.norm(-enemy.velocity, rng), true)" "	if false:
		kill(enemy, SimMath.norm(-enemy.velocity, rng), true)"
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
mutate composition-ignored  scripts/sim/wave_director.gd "			fixed_kinds.append_array(_wave_kinds)" "			fixed_kinds.append_array([])"
mutate spawn-always-husk    scripts/sim/wave_director.gd "EnemyState.make(marker.kind, marker.position," "EnemyState.make(EnemyDefs.HUSK, marker.position,"
mutate spawn-phase-fixed    scripts/sim/wave_director.gd "var phase: float = run.rng.randf_range(0.0, 10.0)" "var phase: float = 0.0"
mutate marker-kind-lost     scripts/sim/wave_director.gd "markers.append(SpawnMarker.make(kind, _spawn_point(run), carried))" "markers.append(SpawnMarker.make(EnemyDefs.HUSK, _spawn_point(run), carried))"
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
mutate wall-slam-sound-lost scripts/audio/sfx_bank.gd "		SimCue.Kind.WALL_SLAM:
			play(\"thud\")" "		SimCue.Kind.WALL_SLAM:
			pass"

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
mutate placement-cooldown-dropped  scripts/sim/game_run.gd "placement.phase, maxf(cooldown, 0.0), placement.armed)" "placement.phase, 0.0, placement.armed)"
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
mutate flurry-recharge-ignores-rarity scripts/sim/sword_state.gd "SwordDefs.ultimate_recharge_of(spec_value)" "SwordDefs.ultimate_cooldown(spec_value.type_id)"
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
	cue.spec = sword.spec
	add_cue(cue)" "	cue.origin = origin
	cue.spec = sword.spec"
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
mutate flurry-sound-lost           scripts/audio/sfx_bank.gd "		_:
			return \"dash\"" "		_:
			return \"\""
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
		kill(enemy, d, heavy or crit)
	elif sword != null:
		afflict(enemy, sword.spec.element, sword.damage, stacks)" "	if sword != null:
		afflict(enemy, sword.spec.element, sword.damage, stacks)
	if enemy.hp <= 0.0:
		kill(enemy, d, heavy or crit)"
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
	_update_fields(dt)
	_resolve_contacts()
" "	_update_fields(dt)
	_resolve_contacts()
	_update_conditions(dt)
"
mutate conditions-render-rate-dependent   scripts/sim/game_run.gd "	_update_conditions(dt)
	_update_fields(dt)
	_resolve_contacts()
" "	_update_conditions(dt * (1.0 + float(Engine.get_process_frames() % 2)))
	_update_fields(dt)
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
mutate conditions-encounter-not-in-cycle            scripts/sim/run_scenario.gd "ENCOUNTER_SPITTERS, ENCOUNTER_CONDITIONS, ENCOUNTER_WARDEN, ENCOUNTER_PIKE, ENCOUNTER_COLOSSUS, ENCOUNTER_DROPS]" "ENCOUNTER_SPITTERS, ENCOUNTER_WARDEN, ENCOUNTER_PIKE, ENCOUNTER_COLOSSUS, ENCOUNTER_DROPS]"
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
mutate sweep-hit-set-kept-between-attacks           scripts/sim/sword_state.gd "	windup_span = timer
	sweep_hits.clear()
	side = -side" "	windup_span = timer
	side = -side"
mutate sweep-never-alternates                       scripts/sim/sword_state.gd "	windup_span = timer
	sweep_hits.clear()
	side = -side" "	windup_span = timer
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
mutate sweep-cue-lost                               scripts/sim/sword_state.gd "	var strike_cue: SimCue = SimCue.make(SimCue.Kind.SWORD_STRIKE, position, dir)
	strike_cue.spec = spec
	run.add_cue(strike_cue)


## Warden's windup" "	pass


## Warden's windup"
mutate warden-uses-fang-damage                      scripts/sim/sword_state.gd "	sword.damage = SwordDefs.damage_of(spec_value)" "	sword.damage = SwordDefs.FANG_DAMAGE * SwordDefs.RARITY_DAMAGE[rarity]"
mutate warden-uses-fang-range                       scripts/sim/sword_state.gd "	sword.attack_range = SwordDefs.range_of(spec_value)" "	sword.attack_range = SwordDefs.FANG_RANGE * SwordDefs.RARITY_RANGE[rarity]"
mutate warden-uses-fang-cooldown                    scripts/sim/sword_state.gd "	sword.cooldown = SwordDefs.cooldown_of(spec_value)" "	sword.cooldown = SwordDefs.FANG_COOLDOWN * SwordDefs.RARITY_COOLDOWN[rarity]"
mutate warden-uses-fang-knockback                   scripts/sim/sword_state.gd "	sword.knock = SwordDefs.base_knock(type_id)" "	sword.knock = SwordDefs.FANG_KNOCK"
mutate warden-rarity-size-lost                      scripts/sim/sword_state.gd "	sword.size_scale = SwordDefs.RARITY_SIZE[rarity]" "	sword.size_scale = 1.0"
mutate warden-rarity-recharge-lost                  scripts/sim/sword_state.gd "	sword.ultimate_cooldown = SwordDefs.ultimate_recharge_of(spec_value)" "	sword.ultimate_cooldown = SwordDefs.ultimate_cooldown(spec_value.type_id)"
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
mutate warden-encounter-not-in-cycle                scripts/sim/run_scenario.gd "ENCOUNTER_CONDITIONS, ENCOUNTER_WARDEN, ENCOUNTER_PIKE, ENCOUNTER_COLOSSUS, ENCOUNTER_DROPS]" "ENCOUNTER_CONDITIONS, ENCOUNTER_PIKE, ENCOUNTER_COLOSSUS, ENCOUNTER_DROPS]"
mutate warden-encounter-slot-lost                   scripts/sim/game_run.gd "		scenario if scenario.encounter == RunScenario.ENCOUNTER_WARDEN else RunScenario.warden_encounter(),
" "		RunScenario.new(),
"
mutate warden-fixture-has-no-wardens                scripts/sim/run_scenario.gd "	specs.append(SwordSpec.make(&\"fang\", 0, &\"poison\"))
	specs.append(SwordSpec.make(SwordDefs.WARDEN, 0, &\"ice\"))" "	specs.append(SwordSpec.make(&\"fang\", 0, &\"poison\"))
	specs.append(SwordSpec.make(&\"fang\", 0, &\"ice\"))"
mutate warden-fixture-wrong-element                 scripts/sim/run_scenario.gd "	specs.append(SwordSpec.make(SwordDefs.WARDEN, 0, &\"fire\"))" "	specs.append(SwordSpec.make(SwordDefs.WARDEN, 0, &\"ice\"))"
mutate warden-encounter-no-brutes                   scripts/sim/run_scenario.gd "&\"husk\", &\"husk\", &\"runner\", &\"husk\", &\"brute\", &\"husk\", &\"runner\", &\"husk\", &\"husk\", &\"runner\", &\"brute\", &\"husk\", &\"husk\", &\"runner\"," "&\"husk\", &\"husk\", &\"runner\", &\"husk\", &\"husk\", &\"husk\", &\"runner\", &\"husk\", &\"husk\", &\"runner\", &\"husk\", &\"husk\", &\"husk\", &\"runner\","
mutate warden-encounter-not-the-default             scripts/sim/run_scenario.gd "var loadout: Array[SwordSpec] = RunScenario.default_loadout()" "var loadout: Array[SwordSpec] = RunScenario.warden_fixture_loadout()"
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
			play(\"slash\")" "		SimCue.Kind.MAELSTROM_BURST:
			pass"
mutate maelstrom-beat-sound-always                  scripts/audio/sfx_bank.gd "			if cue.amount > 0:
				play(\"slash\")" "			play(\"slash\")"
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
mutate skewer-point-collapses-to-the-player          scripts/sim/game_run.gd "	var type_id: StringName = sword.spec.type_id
	var target: Vector2 = point" "	var type_id: StringName = sword.spec.type_id
	var target: Vector2 = position"
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
mutate pike-encounter-not-in-cycle                  scripts/sim/run_scenario.gd "ENCOUNTER_CONDITIONS, ENCOUNTER_WARDEN, ENCOUNTER_PIKE, ENCOUNTER_COLOSSUS, ENCOUNTER_DROPS]" "ENCOUNTER_CONDITIONS, ENCOUNTER_WARDEN, ENCOUNTER_COLOSSUS, ENCOUNTER_DROPS]"
mutate pike-encounter-slot-lost                     scripts/sim/game_run.gd "		scenario if scenario.encounter == RunScenario.ENCOUNTER_PIKE else RunScenario.pike_encounter(),
" "		RunScenario.new(),
"
mutate pike-fixture-wrong-element                   scripts/sim/run_scenario.gd "	specs.append(SwordSpec.make(SwordDefs.PIKE, 0, &\"fire\"))" "	specs.append(SwordSpec.make(SwordDefs.PIKE, 0, &\"ice\"))"
mutate pike-fixture-has-no-pikes                    scripts/sim/run_scenario.gd "	specs.append(SwordSpec.make(SwordDefs.PIKE, 0, &\"ice\"))" "	specs.append(SwordSpec.make(&\"fang\", 0, &\"ice\"))"
mutate pike-encounter-no-brutes                     scripts/sim/run_scenario.gd "&\"husk\", &\"runner\", &\"husk\", &\"husk\", &\"brute\", &\"runner\", &\"husk\", &\"husk\", &\"runner\", &\"husk\", &\"brute\", &\"husk\"," "&\"husk\", &\"runner\", &\"husk\", &\"husk\", &\"husk\", &\"runner\", &\"husk\", &\"husk\", &\"runner\", &\"husk\", &\"husk\", &\"husk\","
mutate pike-encounter-column-moved                  scripts/sim/run_scenario.gd "Vector2(1290.0, 330.0), Vector2(1325.0, 270.0)" "Vector2(1290.0, 630.0), Vector2(1325.0, 570.0)"
mutate pike-encounter-not-the-default               scripts/sim/run_scenario.gd "var loadout: Array[SwordSpec] = RunScenario.default_loadout()" "var loadout: Array[SwordSpec] = RunScenario.pike_fixture_loadout()"
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
			play(\"pierce\")" "		SimCue.Kind.SKEWER_LAUNCHED:
			pass"
mutate skewer-release-sound-always                  scripts/audio/sfx_bank.gd "		SimCue.Kind.SKEWER_LAUNCHED:
			play(\"pierce\")" "		SimCue.Kind.SKEWER_LAUNCHED:
			play(\"pierce\")
		SimCue.Kind.SKEWER_RELEASED:
			play(\"thud\")"
mutate pike-visual-needle                           scripts/presentation/placeholder_sword_visual.gd "	_pike = spec.type_id == SwordDefs.PIKE" "	_pike = false"

# The Pike's strokes are counted by the same call that draws them (`_stroke`, `_stroke_ring`), so removing the
# real draw call removes the count too: each of these takes out one stroke the layer draws, not a counter.
mutate skewer-aim-band-not-drawn                    scripts/presentation/effects_layer.gd "		_stroke(&\"skewer_aim_band\", _run.position, end, Color(tint, 0.15 + 0.25 * u), 24.0)
" ""
mutate skewer-aim-line-not-drawn                    scripts/presentation/effects_layer.gd "		_stroke(&\"skewer_aim_line\", _run.position, end, Color(tint, 0.25 + 0.35 * u), 2.0)
" ""
mutate skewer-aim-both-strokes-not-drawn            scripts/presentation/effects_layer.gd "		_stroke(&\"skewer_aim_band\", _run.position, end, Color(tint, 0.15 + 0.25 * u), 24.0)
		_stroke(&\"skewer_aim_line\", _run.position, end, Color(tint, 0.25 + 0.35 * u), 2.0)
" ""
mutate skewer-carry-ring-not-drawn                  scripts/presentation/effects_layer.gd "		_stroke_ring(&\"skewer_carry_ring\", enemy.position, enemy.radius + 7.0, Color(tint, 0.85), 3.0)
" ""
mutate skewer-carry-line-not-drawn                  scripts/presentation/effects_layer.gd "		_stroke(&\"skewer_carry_line\", enemy.position, tip, Color(tint, 0.4), 2.0)
" ""
mutate thrust-telegraph-band-not-drawn              scripts/presentation/effects_layer.gd "	_stroke(&\"thrust_telegraph_band\", from, to, Color(tint, 0.06 + 0.12 * u), 14.0)
" ""
mutate thrust-telegraph-line-not-drawn              scripts/presentation/effects_layer.gd "	_stroke(&\"thrust_telegraph_line\", from, to, Color(tint, 0.25 + 0.4 * u), 2.0)
" ""

# The release is compared whole on every fixture (the carried enemies' velocity, health and stun and the slam
# on the release tick), so each part of it is a mutation of its own: the release speeds along a diagonal and a
# straight wall, damage on release, and the slam.
mutate skewer-release-diagonal-wall-speed-halved    scripts/sim/sword_state.gd "enemy.velocity = dir * (SwordDefs.PIKE_ULT_RELEASE_SPEED_WALL if at_wall else SwordDefs.PIKE_ULT_RELEASE_SPEED_RANGE)" "enemy.velocity = dir * (SwordDefs.PIKE_ULT_RELEASE_SPEED_WALL if at_wall else SwordDefs.PIKE_ULT_RELEASE_SPEED_RANGE) * (0.5 if at_wall and absf(dir.x) > 0.5 and absf(dir.y) > 0.5 else 1.0)"
mutate skewer-release-straight-wall-speed-halved    scripts/sim/sword_state.gd "enemy.velocity = dir * (SwordDefs.PIKE_ULT_RELEASE_SPEED_WALL if at_wall else SwordDefs.PIKE_ULT_RELEASE_SPEED_RANGE)" "enemy.velocity = dir * (SwordDefs.PIKE_ULT_RELEASE_SPEED_WALL if at_wall else SwordDefs.PIKE_ULT_RELEASE_SPEED_RANGE) * (0.5 if at_wall and (absf(dir.x) > 0.99 or absf(dir.y) > 0.99) else 1.0)"
mutate skewer-release-diagonal-range-speed-halved   scripts/sim/sword_state.gd "enemy.velocity = dir * (SwordDefs.PIKE_ULT_RELEASE_SPEED_WALL if at_wall else SwordDefs.PIKE_ULT_RELEASE_SPEED_RANGE)" "enemy.velocity = dir * (SwordDefs.PIKE_ULT_RELEASE_SPEED_WALL if at_wall else SwordDefs.PIKE_ULT_RELEASE_SPEED_RANGE) * (0.5 if not at_wall and absf(dir.x) > 0.5 and absf(dir.y) > 0.5 else 1.0)"
mutate skewer-release-deals-damage                  scripts/sim/sword_state.gd "			enemy.stun = maxf(enemy.stun, SwordDefs.PIKE_ULT_RELEASE_STUN)
" "			enemy.stun = maxf(enemy.stun, SwordDefs.PIKE_ULT_RELEASE_STUN)
			enemy.hp -= 1.0
"
mutate skewer-release-heals                         scripts/sim/sword_state.gd "			enemy.stun = maxf(enemy.stun, SwordDefs.PIKE_ULT_RELEASE_STUN)
" "			enemy.stun = maxf(enemy.stun, SwordDefs.PIKE_ULT_RELEASE_STUN)
			enemy.hp += 1.0
"
mutate skewer-release-slam-never-at-wall-speed      scripts/sim/enemy_state.gd "	if slammed and stun > 0.0 and speed_before > GameRun.WALL_SLAM_MIN_SPEED:" "	if slammed and stun > 0.0 and speed_before > GameRun.WALL_SLAM_MIN_SPEED and speed_before < SwordDefs.PIKE_ULT_RELEASE_SPEED_WALL - 1.0:"
mutate skewer-release-slam-a-tick-late              scripts/sim/sword_state.gd "			enemy.velocity = dir * (SwordDefs.PIKE_ULT_RELEASE_SPEED_WALL if at_wall else SwordDefs.PIKE_ULT_RELEASE_SPEED_RANGE)
" "			enemy.velocity = dir * (SwordDefs.PIKE_ULT_RELEASE_SPEED_WALL if at_wall else SwordDefs.PIKE_ULT_RELEASE_SPEED_RANGE)
			enemy.position -= dir * 60.0
"

# --- Colossus and Cataclysm (slice #15)
mutate colossus-key-renamed                         scripts/sim/sword_defs.gd "const COLOSSUS: StringName = &\"colossus\"" "const COLOSSUS: StringName = &\"colossi\""
mutate colossus-display-name                        scripts/sim/sword_defs.gd "		COLOSSUS:
			return \"Colossus\"" "		COLOSSUS:
			return \"Colossal\""
mutate colossus-length                              scripts/sim/sword_defs.gd "COLOSSUS_LENGTH: float = 88.0" "COLOSSUS_LENGTH: float = 80.0"
mutate colossus-width                               scripts/sim/sword_defs.gd "COLOSSUS_WIDTH: float = 15.0" "COLOSSUS_WIDTH: float = 14.0"
mutate colossus-range                               scripts/sim/sword_defs.gd "COLOSSUS_RANGE: float = 330.0" "COLOSSUS_RANGE: float = 360.0"
mutate colossus-cooldown                            scripts/sim/sword_defs.gd "COLOSSUS_COOLDOWN: float = 2.1" "COLOSSUS_COOLDOWN: float = 1.8"
mutate colossus-damage                              scripts/sim/sword_defs.gd "COLOSSUS_DAMAGE: float = 50.0" "COLOSSUS_DAMAGE: float = 51.0"
mutate colossus-knockback                           scripts/sim/sword_defs.gd "COLOSSUS_KNOCK: float = 650.0" "COLOSSUS_KNOCK: float = 600.0"
mutate colossus-windup                              scripts/sim/sword_defs.gd "COLOSSUS_WINDUP: float = 0.55" "COLOSSUS_WINDUP: float = 0.6"
mutate colossus-hitstop                             scripts/sim/sword_defs.gd "COLOSSUS_HITSTOP: float = 0.13" "COLOSSUS_HITSTOP: float = 0.1"
mutate colossus-shake                               scripts/sim/sword_defs.gd "COLOSSUS_SHAKE: float = 0.6" "COLOSSUS_SHAKE: float = 0.5"
mutate colossus-slam-radius                         scripts/sim/sword_defs.gd "COLOSSUS_AOE: float = 118.0" "COLOSSUS_AOE: float = 120.0"
mutate colossus-start-altitude                      scripts/sim/sword_defs.gd "COLOSSUS_START_ALTITUDE: float = 30.0" "COLOSSUS_START_ALTITUDE: float = 40.0"
mutate colossus-rest-base                           scripts/sim/sword_defs.gd "COLOSSUS_REST_BASE: float = 34.0" "COLOSSUS_REST_BASE: float = 36.0"
mutate colossus-rest-length                         scripts/sim/sword_defs.gd "COLOSSUS_REST_LENGTH: float = 0.15" "COLOSSUS_REST_LENGTH: float = 0.2"
mutate colossus-rest-bob-rate                       scripts/sim/sword_defs.gd "COLOSSUS_REST_BOB_RATE: float = 2.2" "COLOSSUS_REST_BOB_RATE: float = 2.0"
mutate colossus-rest-bob-slot                       scripts/sim/sword_defs.gd "COLOSSUS_REST_BOB_SLOT: float = 2.1" "COLOSSUS_REST_BOB_SLOT: float = 2.0"
mutate colossus-rest-bob                            scripts/sim/sword_defs.gd "COLOSSUS_REST_BOB: float = 7.0" "COLOSSUS_REST_BOB: float = 6.0"
mutate colossus-rest-rate                           scripts/sim/sword_defs.gd "COLOSSUS_REST_RATE: float = 5.0" "COLOSSUS_REST_RATE: float = 4.0"
mutate colossus-sink-rate                           scripts/sim/sword_defs.gd "COLOSSUS_SINK_RATE: float = 120.0" "COLOSSUS_SINK_RATE: float = 100.0"
mutate colossus-windup-spring-k                     scripts/sim/sword_defs.gd "COLOSSUS_WINDUP_SPRING_K: float = 120.0" "COLOSSUS_WINDUP_SPRING_K: float = 100.0"
mutate colossus-windup-spring-c                     scripts/sim/sword_defs.gd "COLOSSUS_WINDUP_SPRING_C: float = 18.0" "COLOSSUS_WINDUP_SPRING_C: float = 20.0"
mutate colossus-windup-altitude                     scripts/sim/sword_defs.gd "COLOSSUS_WINDUP_ALTITUDE: float = 200.0" "COLOSSUS_WINDUP_ALTITUDE: float = 180.0"
mutate colossus-windup-rate                         scripts/sim/sword_defs.gd "COLOSSUS_WINDUP_RATE: float = 7.0" "COLOSSUS_WINDUP_RATE: float = 6.0"
mutate colossus-windup-tremble-rate                 scripts/sim/sword_defs.gd "COLOSSUS_WINDUP_TREMBLE_RATE: float = 30.0" "COLOSSUS_WINDUP_TREMBLE_RATE: float = 20.0"
mutate colossus-windup-tremble                      scripts/sim/sword_defs.gd "COLOSSUS_WINDUP_TREMBLE: float = 0.03" "COLOSSUS_WINDUP_TREMBLE: float = 0.05"
mutate colossus-windup-turn-rate                    scripts/sim/sword_defs.gd "COLOSSUS_WINDUP_TURN_RATE: float = 10.0" "COLOSSUS_WINDUP_TURN_RATE: float = 8.0"
mutate colossus-glide-rate                          scripts/sim/sword_defs.gd "COLOSSUS_GLIDE_RATE: float = 30.0" "COLOSSUS_GLIDE_RATE: float = 20.0"
mutate colossus-strike-fall-speed                   scripts/sim/sword_defs.gd "COLOSSUS_STRIKE_FALL_SPEED: float = 300.0" "COLOSSUS_STRIKE_FALL_SPEED: float = 200.0"
mutate colossus-strike-gravity                      scripts/sim/sword_defs.gd "COLOSSUS_STRIKE_GRAVITY: float = 9000.0" "COLOSSUS_STRIKE_GRAVITY: float = 8000.0"
mutate colossus-slam-falloff                        scripts/sim/sword_defs.gd "COLOSSUS_SLAM_FALLOFF: float = 0.45" "COLOSSUS_SLAM_FALLOFF: float = 0.4"
mutate colossus-empty-hitstop                       scripts/sim/sword_defs.gd "COLOSSUS_SLAM_EMPTY_HITSTOP: float = 0.04" "COLOSSUS_SLAM_EMPTY_HITSTOP: float = 0.05"
mutate colossus-empty-shake                         scripts/sim/sword_defs.gd "COLOSSUS_SLAM_EMPTY_SHAKE: float = 0.35" "COLOSSUS_SLAM_EMPTY_SHAKE: float = 0.3"
mutate colossus-stuck-time                          scripts/sim/sword_defs.gd "COLOSSUS_STUCK_TIME: float = 0.32" "COLOSSUS_STUCK_TIME: float = 0.3"
mutate colossus-stuck-tremble-rate                  scripts/sim/sword_defs.gd "COLOSSUS_STUCK_TREMBLE_RATE: float = 60.0" "COLOSSUS_STUCK_TREMBLE_RATE: float = 50.0"
mutate colossus-stuck-tremble                       scripts/sim/sword_defs.gd "COLOSSUS_STUCK_TREMBLE: float = 0.08" "COLOSSUS_STUCK_TREMBLE: float = 0.1"
mutate colossus-recover-time                        scripts/sim/sword_defs.gd "COLOSSUS_RECOVER_TIME: float = 0.4" "COLOSSUS_RECOVER_TIME: float = 0.5"
mutate colossus-recover-velocity                    scripts/sim/sword_defs.gd "Vector2(0.0, -60.0)" "Vector2(0.0, -30.0)"
mutate cataclysm-name                               scripts/sim/sword_defs.gd "COLOSSUS_ULT_NAME: String = \"Cataclysm\"" "COLOSSUS_ULT_NAME: String = \"Cataclism\""
mutate cataclysm-recharge                           scripts/sim/sword_defs.gd "COLOSSUS_ULT_COOLDOWN: float = 14.0" "COLOSSUS_ULT_COOLDOWN: float = 13.0"
mutate cataclysm-range                              scripts/sim/sword_defs.gd "COLOSSUS_ULT_RANGE: float = 480.0" "COLOSSUS_ULT_RANGE: float = 500.0"
mutate cataclysm-area-factor                        scripts/sim/sword_defs.gd "COLOSSUS_ULT_AOE_FACTOR: float = 1.8" "COLOSSUS_ULT_AOE_FACTOR: float = 1.7"
mutate cataclysm-rise-time                          scripts/sim/sword_defs.gd "COLOSSUS_ULT_RISE_TIME: float = 0.75" "COLOSSUS_ULT_RISE_TIME: float = 0.7"
mutate cataclysm-rise-altitude                      scripts/sim/sword_defs.gd "COLOSSUS_ULT_RISE_ALTITUDE: float = 420.0" "COLOSSUS_ULT_RISE_ALTITUDE: float = 400.0"
mutate cataclysm-rise-rate                          scripts/sim/sword_defs.gd "COLOSSUS_ULT_RISE_RATE: float = 5.0" "COLOSSUS_ULT_RISE_RATE: float = 4.0"
mutate cataclysm-tremble-rate                       scripts/sim/sword_defs.gd "COLOSSUS_ULT_TREMBLE_RATE: float = 40.0" "COLOSSUS_ULT_TREMBLE_RATE: float = 30.0"
mutate cataclysm-tremble                            scripts/sim/sword_defs.gd "COLOSSUS_ULT_TREMBLE: float = 0.04" "COLOSSUS_ULT_TREMBLE: float = 0.05"
mutate cataclysm-fall-speed                         scripts/sim/sword_defs.gd "COLOSSUS_ULT_FALL_SPEED: float = 600.0" "COLOSSUS_ULT_FALL_SPEED: float = 500.0"
mutate cataclysm-gravity                            scripts/sim/sword_defs.gd "COLOSSUS_ULT_FALL_GRAVITY: float = 12000.0" "COLOSSUS_ULT_FALL_GRAVITY: float = 10000.0"
mutate cataclysm-damage-factor                      scripts/sim/sword_defs.gd "COLOSSUS_ULT_DAMAGE_FACTOR: float = 2.2" "COLOSSUS_ULT_DAMAGE_FACTOR: float = 2.0"
mutate cataclysm-doses                              scripts/sim/sword_defs.gd "COLOSSUS_ULT_STACKS: int = 3" "COLOSSUS_ULT_STACKS: int = 2"
mutate cataclysm-shake                              scripts/sim/sword_defs.gd "COLOSSUS_ULT_SHAKE: float = 0.4" "COLOSSUS_ULT_SHAKE: float = 0.3"
mutate cataclysm-stuck-time                         scripts/sim/sword_defs.gd "COLOSSUS_ULT_STUCK_TIME: float = 0.6" "COLOSSUS_ULT_STUCK_TIME: float = 0.5"
mutate field-radius-factor                          scripts/sim/sword_defs.gd "COLOSSUS_FIELD_RADIUS_FACTOR: float = 1.1" "COLOSSUS_FIELD_RADIUS_FACTOR: float = 1.0"
mutate field-life                                   scripts/sim/sword_defs.gd "COLOSSUS_FIELD_LIFE: float = 5.0" "COLOSSUS_FIELD_LIFE: float = 4.5"
mutate field-period                                 scripts/sim/sword_defs.gd "COLOSSUS_FIELD_PERIOD: float = 0.5" "COLOSSUS_FIELD_PERIOD: float = 0.6"
mutate cataclysm-treated-as-a-skill-shot            scripts/sim/sword_defs.gd "	return type_id == PIKE
" "	return type_id == PIKE or type_id == COLOSSUS
"
mutate colossus-acquire-cluster-lost                scripts/sim/sword_state.gd "	if spec.type_id == SwordDefs.COLOSSUS:
		return _acquire_cluster(run)
" ""
mutate colossus-acquire-ignores-distance            scripts/sim/sword_state.gd "var score: float = float(crowd) * 1000.0 - dist" "var score: float = float(crowd) * 1000.0"
mutate colossus-acquire-tie-goes-last               scripts/sim/sword_state.gd "if best == null or score > best_score:" "if best == null or score >= best_score:"
mutate colossus-acquire-counts-with-the-rarity-radius scripts/sim/sword_state.gd "if (other.position - enemy.position).length() < SwordDefs.COLOSSUS_AOE:" "if (other.position - enemy.position).length() < slam_radius():"
mutate colossus-acquire-count-inclusive             scripts/sim/sword_state.gd "if (other.position - enemy.position).length() < SwordDefs.COLOSSUS_AOE:" "if (other.position - enemy.position).length() <= SwordDefs.COLOSSUS_AOE:"
mutate colossus-acquire-count-skips-the-dead        scripts/sim/sword_state.gd "if (other.position - enemy.position).length() < SwordDefs.COLOSSUS_AOE:" "if not other.dead and (other.position - enemy.position).length() < SwordDefs.COLOSSUS_AOE:"
mutate colossus-acquire-skips-the-dead              scripts/sim/sword_state.gd "		if dist < attack_range + enemy.radius:
			var crowd: int = 0" "		if not enemy.dead and dist < attack_range + enemy.radius:
			var crowd: int = 0"
mutate colossus-acquire-ignores-enemy-radius        scripts/sim/sword_state.gd "		if dist < attack_range + enemy.radius:
			var crowd: int = 0" "		if dist < attack_range:
			var crowd: int = 0"
mutate colossus-start-altitude-not-set              scripts/sim/sword_state.gd "	if type_id == SwordDefs.COLOSSUS:
		sword.altitude = SwordDefs.COLOSSUS_START_ALTITUDE
" ""
mutate colossus-rest-altitude-frozen                scripts/sim/sword_state.gd "altitude = lerpf(altitude, rest, minf(1.0, dt * SwordDefs.COLOSSUS_REST_RATE))" "altitude = altitude"
mutate colossus-windup-altitude-lost                scripts/sim/sword_state.gd "	altitude = lerpf(altitude, SwordDefs.COLOSSUS_WINDUP_ALTITUDE, minf(1.0, dt * SwordDefs.COLOSSUS_WINDUP_RATE))" "	altitude = altitude"
mutate colossus-windup-spring-lost                  scripts/sim/sword_state.gd "	_spring(aim, SwordDefs.COLOSSUS_WINDUP_SPRING_K, SwordDefs.COLOSSUS_WINDUP_SPRING_C, dt)" "	pass"
mutate colossus-windup-angle-lost                   scripts/sim/sword_state.gd "	angle = SimMath.ang_lerp(angle, PI / 2.0 + sin(run.gameplay_time * SwordDefs.COLOSSUS_WINDUP_TREMBLE_RATE) * SwordDefs.COLOSSUS_WINDUP_TREMBLE, minf(1.0, dt * SwordDefs.COLOSSUS_WINDUP_TURN_RATE))" "	angle = angle"
mutate colossus-impact-is-the-sword                 scripts/sim/sword_state.gd "			impact = aim
" "			impact = position
"
mutate colossus-fall-speed-not-set                  scripts/sim/sword_state.gd "			fall_speed = SwordDefs.COLOSSUS_STRIKE_FALL_SPEED
" ""
mutate colossus-fall-no-glide                       scripts/sim/sword_state.gd "	position = position.lerp(impact, minf(1.0, dt * SwordDefs.COLOSSUS_GLIDE_RATE))" "	position = position"
mutate colossus-fall-no-gravity                     scripts/sim/sword_state.gd "	fall_speed += SwordDefs.COLOSSUS_STRIKE_GRAVITY * dt" "	fall_speed += 0.0"
mutate colossus-lands-late                          scripts/sim/sword_state.gd "	altitude -= fall_speed * dt
	if altitude <= 0.0:
		altitude = 0.0
		position = impact" "	altitude -= fall_speed * dt
	if altitude < -40.0:
		altitude = 0.0
		position = impact"
mutate colossus-slam-radius-unscaled                scripts/sim/sword_state.gd "run.slam(self, impact, slam_radius(), 1.0, 1, false)" "run.slam(self, impact, SwordDefs.COLOSSUS_AOE, 1.0, 1, false)"
mutate colossus-slam-power                          scripts/sim/sword_state.gd "run.slam(self, impact, slam_radius(), 1.0, 1, false)" "run.slam(self, impact, slam_radius(), 1.1, 1, false)"
mutate colossus-slam-doses                          scripts/sim/sword_state.gd "run.slam(self, impact, slam_radius(), 1.0, 1, false)" "run.slam(self, impact, slam_radius(), 1.0, 2, false)"
mutate colossus-slam-marked-a-cataclysm             scripts/sim/sword_state.gd "run.slam(self, impact, slam_radius(), 1.0, 1, false)" "run.slam(self, impact, slam_radius(), 1.0, 1, true)"
mutate colossus-slam-skips-the-stuck-pause          scripts/sim/sword_state.gd "		phase = Phase.STUCK
		timer = SwordDefs.COLOSSUS_STUCK_TIME" "		phase = Phase.RECOVER
		timer = SwordDefs.COLOSSUS_RECOVER_TIME"
mutate colossus-stuck-clock-stopped                 scripts/sim/sword_state.gd "func _update_stuck(dt: float) -> void:
	timer -= dt" "func _update_stuck(dt: float) -> void:
	timer -= 0.0"
mutate colossus-stuck-angle-lost                    scripts/sim/sword_state.gd "	angle = PI / 2.0 + sin(timer * SwordDefs.COLOSSUS_STUCK_TREMBLE_RATE) * SwordDefs.COLOSSUS_STUCK_TREMBLE * timer" "	angle = PI / 2.0"
mutate colossus-recover-without-the-kick            scripts/sim/sword_state.gd "		velocity = SwordDefs.COLOSSUS_RECOVER_VELOCITY" "		velocity = Vector2.ZERO"
mutate colossus-dead-player-altitude-kept           scripts/sim/sword_state.gd "			altitude = maxf(0.0, altitude - dt * SwordDefs.COLOSSUS_SINK_RATE)" "			altitude = altitude"
mutate cataclysm-area-radius-is-the-slam-radius     scripts/sim/sword_state.gd "		SwordDefs.COLOSSUS:
			return cataclysm_radius()" "		SwordDefs.COLOSSUS:
			return slam_radius()"
mutate cataclysm-radius-formula                     scripts/sim/sword_state.gd "return SwordDefs.COLOSSUS_AOE * SwordDefs.COLOSSUS_ULT_AOE_FACTOR * size_scale" "return SwordDefs.COLOSSUS_AOE * SwordDefs.COLOSSUS_ULT_AOE_FACTOR"
mutate cataclysm-rise-progress-stuck-at-one         scripts/sim/sword_state.gd "	if cataclysm_falling:
		return 1.0" "	if cataclysm_falling:
		return 0.0"
mutate cataclysm-rise-progress-guard-lost           scripts/sim/sword_state.gd "	if phase != Phase.ULTIMATE or spec.type_id != SwordDefs.COLOSSUS:
		return 0.0" "	if spec.type_id != SwordDefs.COLOSSUS:
		return 0.0"
mutate cataclysm-rise-clock-stopped                 scripts/sim/sword_state.gd "func _update_cataclysm(run: GameRun, dt: float) -> void:
	ultimate_time_left -= dt" "func _update_cataclysm(run: GameRun, dt: float) -> void:
	ultimate_time_left -= 0.0"
mutate cataclysm-rise-time-not-set                  scripts/sim/sword_state.gd "			ultimate_time_left = SwordDefs.COLOSSUS_ULT_RISE_TIME" "			ultimate_time_left = 0.0"
mutate cataclysm-rise-spring-lost                   scripts/sim/sword_state.gd "		_spring(ultimate_point, SwordDefs.COLOSSUS_WINDUP_SPRING_K, SwordDefs.COLOSSUS_WINDUP_SPRING_C, dt)" "		pass"
mutate cataclysm-rise-altitude-lost                 scripts/sim/sword_state.gd "		altitude = lerpf(altitude, SwordDefs.COLOSSUS_ULT_RISE_ALTITUDE, minf(1.0, dt * SwordDefs.COLOSSUS_ULT_RISE_RATE))" "		pass"
mutate cataclysm-fall-never-starts                  scripts/sim/sword_state.gd "			cataclysm_falling = true
			fall_speed = SwordDefs.COLOSSUS_ULT_FALL_SPEED" "			fall_speed = SwordDefs.COLOSSUS_ULT_FALL_SPEED"
mutate cataclysm-fall-speed-not-set                 scripts/sim/sword_state.gd "			fall_speed = SwordDefs.COLOSSUS_ULT_FALL_SPEED" "			fall_speed = 0.0"
mutate cataclysm-fall-no-glide                      scripts/sim/sword_state.gd "	position = position.lerp(ultimate_point, minf(1.0, dt * SwordDefs.COLOSSUS_GLIDE_RATE))" "	position = position"
mutate cataclysm-lands-late                         scripts/sim/sword_state.gd "	altitude -= fall_speed * dt
	if altitude <= 0.0:
		altitude = 0.0
		position = ultimate_point" "	altitude -= fall_speed * dt
	if altitude < -20.0:
		altitude = 0.0
		position = ultimate_point"
mutate cataclysm-flag-kept-for-the-next-one         scripts/sim/sword_state.gd "			cataclysm_falling = false
			ultimate_time_left = SwordDefs.COLOSSUS_ULT_RISE_TIME" "			ultimate_time_left = SwordDefs.COLOSSUS_ULT_RISE_TIME"
mutate cataclysm-slam-radius-is-the-slam-radius     scripts/sim/sword_state.gd "var area: float = cataclysm_radius()" "var area: float = slam_radius()"
mutate cataclysm-slam-power                         scripts/sim/sword_state.gd "run.slam(self, ultimate_point, area, SwordDefs.COLOSSUS_ULT_DAMAGE_FACTOR, SwordDefs.COLOSSUS_ULT_STACKS, true)" "run.slam(self, ultimate_point, area, 1.0, SwordDefs.COLOSSUS_ULT_STACKS, true)"
mutate cataclysm-slam-doses                         scripts/sim/sword_state.gd "run.slam(self, ultimate_point, area, SwordDefs.COLOSSUS_ULT_DAMAGE_FACTOR, SwordDefs.COLOSSUS_ULT_STACKS, true)" "run.slam(self, ultimate_point, area, SwordDefs.COLOSSUS_ULT_DAMAGE_FACTOR, 1, true)"
mutate cataclysm-slam-not-marked                    scripts/sim/sword_state.gd "run.slam(self, ultimate_point, area, SwordDefs.COLOSSUS_ULT_DAMAGE_FACTOR, SwordDefs.COLOSSUS_ULT_STACKS, true)" "run.slam(self, ultimate_point, area, SwordDefs.COLOSSUS_ULT_DAMAGE_FACTOR, SwordDefs.COLOSSUS_ULT_STACKS, false)"
mutate cataclysm-leaves-no-field                    scripts/sim/sword_state.gd "		run.add_field(FieldState.make(ultimate_point, area * SwordDefs.COLOSSUS_FIELD_RADIUS_FACTOR, spec.element, damage, SwordDefs.COLOSSUS_FIELD_LIFE))
" ""
mutate cataclysm-field-element                      scripts/sim/sword_state.gd "area * SwordDefs.COLOSSUS_FIELD_RADIUS_FACTOR, spec.element, damage," "area * SwordDefs.COLOSSUS_FIELD_RADIUS_FACTOR, &\"fire\", damage,"
mutate cataclysm-field-power                        scripts/sim/sword_state.gd "area * SwordDefs.COLOSSUS_FIELD_RADIUS_FACTOR, spec.element, damage," "area * SwordDefs.COLOSSUS_FIELD_RADIUS_FACTOR, spec.element, 0.0,"
mutate cataclysm-field-radius-from-the-slam         scripts/sim/sword_state.gd "FieldState.make(ultimate_point, area * SwordDefs.COLOSSUS_FIELD_RADIUS_FACTOR," "FieldState.make(ultimate_point, slam_radius() * SwordDefs.COLOSSUS_FIELD_RADIUS_FACTOR,"
mutate cataclysm-field-life                         scripts/sim/sword_state.gd "spec.element, damage, SwordDefs.COLOSSUS_FIELD_LIFE))" "spec.element, damage, SwordDefs.COLOSSUS_FIELD_LIFE * 2.0))"
mutate cataclysm-no-extra-shake                     scripts/sim/sword_state.gd "		run.add_shake(SwordDefs.COLOSSUS_ULT_SHAKE)
" ""
mutate cataclysm-no-stuck-pause                     scripts/sim/sword_state.gd "		phase = Phase.STUCK
		timer = SwordDefs.COLOSSUS_ULT_STUCK_TIME" "		phase = Phase.RECOVER
		timer = SwordDefs.COLOSSUS_RECOVER_TIME"
mutate slam-skips-the-dead                          scripts/sim/game_run.gd "		if dist < radius + enemy.radius:
			var fall" "		if not enemy.dead and dist < radius + enemy.radius:
			var fall"
mutate slam-reach-ignores-the-enemy-radius          scripts/sim/game_run.gd "		if dist < radius + enemy.radius:
			var fall" "		if dist < radius:
			var fall"
mutate slam-reach-inclusive                         scripts/sim/game_run.gd "		if dist < radius + enemy.radius:
			var fall" "		if dist <= radius + enemy.radius:
			var fall"
mutate slam-no-falloff                              scripts/sim/game_run.gd "var fall: float = 1.0 - SwordDefs.COLOSSUS_SLAM_FALLOFF * clampf(dist / radius, 0.0, 1.0)" "var fall: float = 1.0"
mutate slam-falloff-unclamped                       scripts/sim/game_run.gd "clampf(dist / radius, 0.0, 1.0)" "(dist / radius)"
mutate slam-power-ignored                           scripts/sim/game_run.gd "sword.damage * sword.boost * power * fall" "sword.damage * sword.boost * fall"
mutate slam-boost-ignored                           scripts/sim/game_run.gd "sword.damage * sword.boost * power * fall" "sword.damage * power * fall"
mutate slam-knockback-not-scaled                    scripts/sim/game_run.gd "offset, sword.knock * fall, sword, true, stacks)" "offset, sword.knock, sword, true, stacks)"
mutate slam-not-heavy                               scripts/sim/game_run.gd "offset, sword.knock * fall, sword, true, stacks)" "offset, sword.knock * fall, sword, false, stacks)"
mutate slam-doses-dropped                           scripts/sim/game_run.gd "offset, sword.knock * fall, sword, true, stacks)" "offset, sword.knock * fall, sword, true, 1)"
mutate slam-pushes-toward-the-point                 scripts/sim/game_run.gd "sword.damage * sword.boost * power * fall, offset," "sword.damage * sword.boost * power * fall, -offset,"
mutate slam-clears-no-orbs                          scripts/sim/game_run.gd "	clear_projectiles_in_circle(point, radius)
	hitstop" "	hitstop"
mutate slam-clears-orbs-with-padding                scripts/sim/game_run.gd "	clear_projectiles_in_circle(point, radius)
	hitstop" "	clear_projectiles_in_circle(point, radius + 8.0)
	hitstop"
mutate slam-hitstop-always-short                    scripts/sim/game_run.gd "sword.hit_stop if in_area > 0 else SwordDefs.COLOSSUS_SLAM_EMPTY_HITSTOP" "SwordDefs.COLOSSUS_SLAM_EMPTY_HITSTOP"
mutate slam-hitstop-always-long                     scripts/sim/game_run.gd "sword.hit_stop if in_area > 0 else SwordDefs.COLOSSUS_SLAM_EMPTY_HITSTOP" "sword.hit_stop"
mutate slam-shake-always-short                      scripts/sim/game_run.gd "sword.hit_shake if in_area > 0 else SwordDefs.COLOSSUS_SLAM_EMPTY_SHAKE" "SwordDefs.COLOSSUS_SLAM_EMPTY_SHAKE"
mutate slam-shake-always-long                       scripts/sim/game_run.gd "sword.hit_shake if in_area > 0 else SwordDefs.COLOSSUS_SLAM_EMPTY_SHAKE" "sword.hit_shake"
mutate slam-kicks-upward                            scripts/sim/game_run.gd "SwordDefs.COLOSSUS_SLAM_EMPTY_SHAKE, Vector2.DOWN, true)" "SwordDefs.COLOSSUS_SLAM_EMPTY_SHAKE, Vector2.UP, true)"
mutate slam-no-kick                                 scripts/sim/game_run.gd "SwordDefs.COLOSSUS_SLAM_EMPTY_SHAKE, Vector2.DOWN, true)" "SwordDefs.COLOSSUS_SLAM_EMPTY_SHAKE, Vector2.DOWN, false)"
mutate slam-counts-only-the-living                  scripts/sim/game_run.gd "			in_area += 1" "			in_area += 0 if enemy.dead else 1"
mutate slam-cue-lost                                scripts/sim/game_run.gd "	add_cue(cue)
	return in_area" "	return in_area"
mutate slam-cue-radius-lost                         scripts/sim/game_run.gd "	cue.radius = radius
	cue.element = sword.spec.element" "	cue.element = sword.spec.element"
mutate slam-cue-element-lost                        scripts/sim/game_run.gd "	cue.element = sword.spec.element
	add_cue(cue)
	return in_area" "	add_cue(cue)
	return in_area"
mutate slam-cue-always-a-cataclysm                  scripts/sim/game_run.gd "SimCue.make(SimCue.Kind.COLOSSUS_SLAM, point, Vector2.DOWN, in_area, cataclysm)" "SimCue.make(SimCue.Kind.COLOSSUS_SLAM, point, Vector2.DOWN, in_area, true)"
mutate slam-cue-count-lost                          scripts/sim/game_run.gd "SimCue.make(SimCue.Kind.COLOSSUS_SLAM, point, Vector2.DOWN, in_area, cataclysm)" "SimCue.make(SimCue.Kind.COLOSSUS_SLAM, point, Vector2.DOWN, 0, cataclysm)"
mutate field-cue-lost                               scripts/sim/game_run.gd "	var cue: SimCue = SimCue.make(SimCue.Kind.FIELD_CREATED, field.position)
	cue.radius = field.radius
	cue.element = field.element
	add_cue(cue)" "	pass"
mutate field-pulse-cue-count-lost                   scripts/sim/game_run.gd "SimCue.make(SimCue.Kind.FIELD_PULSED, field.position, Vector2.ZERO, dosed)" "SimCue.make(SimCue.Kind.FIELD_PULSED, field.position, Vector2.ZERO, 0)"
mutate field-pulse-cue-lost                         scripts/sim/game_run.gd "			cue.element = field.element
			add_cue(cue)
	var remaining: Array[FieldState] = []" "			cue.element = field.element
	var remaining: Array[FieldState] = []"
mutate fields-never-tick                            scripts/sim/game_run.gd "	_update_fields(dt)
" ""
mutate fields-tick-before-the-conditions            scripts/sim/game_run.gd "	_update_conditions(dt)
	_update_fields(dt)" "	_update_fields(dt)
	_update_conditions(dt)"
mutate fields-life-frozen                           scripts/sim/game_run.gd "		field.life -= dt" "		field.life -= 0.0"
mutate fields-clock-frozen                          scripts/sim/game_run.gd "		field.tick_left -= dt" "		field.tick_left -= 0.0"
mutate fields-first-dose-delayed                    scripts/sim/field_state.gd "var tick_left: float = 0.0" "var tick_left: float = 0.5"
mutate fields-dose-the-dead                         scripts/sim/game_run.gd "				if not enemy.dead and field.reaches(enemy):" "				if field.reaches(enemy):"
mutate fields-dose-twice                            scripts/sim/game_run.gd "					afflict(enemy, field.element, field.power)" "					afflict(enemy, field.element, field.power, 2)"
mutate fields-power-lost                            scripts/sim/game_run.gd "					afflict(enemy, field.element, field.power)" "					afflict(enemy, field.element, 0.0)"
mutate fields-element-lost                          scripts/sim/game_run.gd "					afflict(enemy, field.element, field.power)" "					afflict(enemy, &\"fire\", field.power)"
mutate fields-dose-without-conditions-gate          scripts/sim/game_run.gd "	if not scenario.conditions_enabled or enemy.dead:
		return" "	if enemy.dead:
		return"
mutate fields-expire-late                           scripts/sim/game_run.gd "		if field.life > 0.0:
			remaining.append(field)" "		if field.life > -0.02:
			remaining.append(field)"
mutate fields-expire-early                          scripts/sim/game_run.gd "		if field.life > 0.0:
			remaining.append(field)" "		if field.life > 0.02:
			remaining.append(field)"
mutate fields-never-removed                         scripts/sim/game_run.gd "	fields = remaining" "	fields = fields"
mutate fields-kept-on-restart                       scripts/sim/game_run.gd "	fields = []
	motes = []" "	motes = []"
mutate field-reach-ignores-the-enemy-radius         scripts/sim/field_state.gd "return (enemy.position - position).length() < radius + enemy.radius" "return (enemy.position - position).length() < radius"
mutate field-reach-inclusive                        scripts/sim/field_state.gd "return (enemy.position - position).length() < radius + enemy.radius" "return (enemy.position - position).length() <= radius + enemy.radius"
mutate field-fade-linear                            scripts/sim/field_state.gd "return clampf(life / max_life * 3.0, 0.0, 1.0)" "return clampf(life / max_life, 0.0, 1.0)"
mutate field-max-life-lost                          scripts/sim/field_state.gd "	field.max_life = life_value
" ""
mutate orbs-cleared-inclusive                       scripts/sim/game_run.gd "(projectile.position - center).length() < radius:
			projectile.resolve(ProjectileState.Fate.CLEARED)" "(projectile.position - center).length() <= radius:
			projectile.resolve(ProjectileState.Fate.CLEARED)"
mutate orbs-cleared-counter-lost                    scripts/sim/game_run.gd "	projectiles_cleared += cleared
" ""
mutate orbs-cleared-as-parried                      scripts/sim/game_run.gd "projectile.resolve(ProjectileState.Fate.CLEARED)" "projectile.resolve(ProjectileState.Fate.PARRIED)"
mutate orbs-cleared-counter-kept-on-restart         scripts/sim/game_run.gd "	projectiles_cleared = 0
" ""
mutate snapshot-field-count-lost                    scripts/sim/game_run.gd "		\"field_count\": fields.size()," "		\"field_count\": 0,"
mutate colossus-encounter-not-in-cycle              scripts/sim/run_scenario.gd "ENCOUNTER_WARDEN, ENCOUNTER_PIKE, ENCOUNTER_COLOSSUS, ENCOUNTER_DROPS]" "ENCOUNTER_WARDEN, ENCOUNTER_PIKE, ENCOUNTER_DROPS]"
mutate colossus-encounter-slot-lost                 scripts/sim/game_run.gd "		scenario if scenario.encounter == RunScenario.ENCOUNTER_COLOSSUS else RunScenario.colossus_encounter(),
" "		RunScenario.new(),
"
mutate colossus-fixture-wrong-element               scripts/sim/run_scenario.gd "	specs.append(SwordSpec.make(SwordDefs.COLOSSUS, 0, &\"ice\"))
	specs.append(SwordSpec.make(SwordDefs.COLOSSUS, 0, &\"fire\"))" "	specs.append(SwordSpec.make(SwordDefs.COLOSSUS, 0, &\"ice\"))
	specs.append(SwordSpec.make(SwordDefs.COLOSSUS, 0, &\"ice\"))"
mutate colossus-fixture-has-no-colossi              scripts/sim/run_scenario.gd "	specs.append(SwordSpec.make(SwordDefs.COLOSSUS, 0, &\"ice\"))" "	specs.append(SwordSpec.make(&\"fang\", 0, &\"ice\"))"
mutate colossus-encounter-no-spitters               scripts/sim/run_scenario.gd "&\"spitter\", &\"husk\", &\"runner\", &\"husk\", &\"spitter\"" "&\"husk\", &\"husk\", &\"runner\", &\"husk\", &\"husk\""
mutate colossus-encounter-no-brutes                 scripts/sim/run_scenario.gd "&\"husk\", &\"runner\", &\"husk\", &\"brute\", &\"husk\", &\"spitter\"" "&\"husk\", &\"runner\", &\"husk\", &\"husk\", &\"husk\", &\"spitter\""
mutate colossus-encounter-cluster-moved             scripts/sim/run_scenario.gd "Vector2(1620.0, 880.0), Vector2(1660.0, 925.0)" "Vector2(1920.0, 880.0), Vector2(1960.0, 925.0)"
mutate colossus-encounter-not-the-default           scripts/sim/run_scenario.gd "var loadout: Array[SwordSpec] = RunScenario.default_loadout()" "var loadout: Array[SwordSpec] = RunScenario.colossus_fixture_loadout()"
mutate colossus-launch-option-lost                  scripts/launch_options.gd "		\"colossus\":
			return RunScenario.colossus_encounter()" "		\"colossus\":
			return null"
mutate colossus-dev-button-title                    scripts/sim/run_scenario.gd "		ENCOUNTER_COLOSSUS:
			return \"Colossus\"
" ""
mutate colossus-legend-lost                         scripts/hud.gd "	elif run.scenario.encounter == RunScenario.ENCOUNTER_COLOSSUS:" "	elif false:"
mutate colossus-legend-counts-nothing               scripts/hud.gd "run.cue_count(SimCue.Kind.COLOSSUS_SLAM), run.cue_count(SimCue.Kind.FIELD_CREATED), run.fields.size(), switch_hint]" "0, 0, 0, switch_hint]"
mutate colossus-legend-live-fields-lost             scripts/hud.gd "run.cue_count(SimCue.Kind.FIELD_CREATED), run.fields.size(), switch_hint]" "run.cue_count(SimCue.Kind.FIELD_CREATED), 0, switch_hint]"
mutate slam-telegraph-lost                          scripts/presentation/effects_layer.gd "			_draw_slam_telegraph(sword)
" "			pass
"
mutate field-drawing-lost                           scripts/presentation/effects_layer.gd "		_draw_field(field)
" "		pass
"
mutate slam-telegraph-fill-not-drawn                scripts/presentation/effects_layer.gd "	_disc(StringName(String(kind) + \"_fill\"), at, radius, Color(tint, 0.05 + 0.08 * progress))
" ""
mutate slam-telegraph-rim-not-drawn                 scripts/presentation/effects_layer.gd "	_rim(StringName(String(kind) + \"_rim\"), at, radius, Color(tint, 0.3 + 0.5 * progress), 2.0, 48)
" ""
mutate slam-telegraph-closing-ring-not-drawn        scripts/presentation/effects_layer.gd "	_rim(StringName(String(kind) + \"_closing\"), at, maxf(8.0, radius * (1.0 - 0.85 * progress)), Color(tint, 0.25 + 0.55 * progress), 3.0, 32)
" ""
mutate cataclysm-ring-not-drawn                     scripts/presentation/effects_layer.gd "				_draw_impact_ring(&\"cataclysm_ring\", sword.ultimate_point, area, sword.cataclysm_rise_progress(), tint)" "				pass"
mutate field-fill-not-drawn                         scripts/presentation/effects_layer.gd "	_disc(&\"field_fill\", Vector2.ZERO, field.radius, Color(tint, 0.16 * fade))
" ""
mutate field-rim-not-drawn                          scripts/presentation/effects_layer.gd "	_rim(&\"field_rim\", Vector2.ZERO, field.radius, Color(tint, pulse * fade), 2.0, 48)
" ""
mutate field-particles-lost                         scripts/presentation/effects_layer.gd "		_add_field_particles(run, dt)
" ""
mutate slam-outer-ring-lost                         scripts/presentation/effects_layer.gd "			_add_ring(cue.position, 10.0, cue.radius * 1.35, 0.35, Color(slam_tint, 0.95), 6.0)
" "			pass
"
mutate slam-inner-ring-lost                         scripts/presentation/effects_layer.gd "			_add_ring(cue.position, 6.0, cue.radius * 0.8, 0.22, Color(1.0, 1.0, 1.0, 0.9), 3.0)
" "			pass
"
mutate slam-sparks-lost                             scripts/presentation/effects_layer.gd "			for i: int in 30:
				_add_spark(cue.position, SimMath.polar(_rng.randf_range(0.0, TAU), _rng.randf_range(200.0, 800.0)), _rng.randf_range(0.2, 0.5), slam_tint)" "			pass"
mutate cataclysm-text-lost                          scripts/presentation/effects_layer.gd "				_add_text(cue.position + Vector2(0.0, -cue.radius * 0.35), \"CATACLYSM\", slam_tint, 0.9, 30)" "				pass"
mutate cataclysm-text-on-every-slam                 scripts/presentation/effects_layer.gd "			if cue.critical:
				_add_text(cue.position + Vector2(0.0, -cue.radius * 0.35)" "			if true:
				_add_text(cue.position + Vector2(0.0, -cue.radius * 0.35)"
mutate field-created-ring-lost                      scripts/presentation/effects_layer.gd "			_add_ring(cue.position, cue.radius * 0.6, cue.radius, 0.4, Color(element_color(cue.element), 0.9), 4.0)" "			pass"
mutate field-pulse-ring-lost                        scripts/presentation/effects_layer.gd "				_add_ring(cue.position, cue.radius * 0.9, cue.radius, 0.25, Color(element_color(cue.element), 0.45), 2.0)" "				pass"
mutate field-pulse-ring-when-empty                  scripts/presentation/effects_layer.gd "		SimCue.Kind.FIELD_PULSED:
			if cue.amount > 0:" "		SimCue.Kind.FIELD_PULSED:
			if true:"
mutate slam-sound-lost                              scripts/audio/sfx_bank.gd "		SimCue.Kind.COLOSSUS_SLAM:
			play(\"boom\")" "		SimCue.Kind.COLOSSUS_SLAM:
			pass"
mutate colossus-visual-needle                       scripts/presentation/placeholder_sword_visual.gd "	_colossus = spec.type_id == SwordDefs.COLOSSUS" "	_colossus = false"
mutate colossus-visual-lift-ignores-altitude        scripts/presentation/placeholder_sword_visual.gd "	_lift = _hover if _resting else _altitude if _colossus else lerpf(_lift, LIFT_ATTACK if attacking else LIFT_IDLE, 0.25)" "	_lift = _hover if _resting else lerpf(_lift, LIFT_ATTACK if attacking else LIFT_IDLE, 0.25)"
mutate colossus-visual-altitude-ignored             scripts/presentation/placeholder_sword_visual.gd "func _on_altitude(height: float) -> void:
	_altitude = height" "func _on_altitude(height: float) -> void:
	pass"
mutate presenter-drops-the-altitude                 scripts/presentation/run_presenter.gd "		visual.apply_altitude(sword.altitude)
" ""
mutate sword-visual-contract-drops-the-altitude     scripts/presentation/sword_visual.gd "	_on_altitude(height)
" "	pass
"
# --- Converge and the default loadout (slice #16)
mutate converge-cooldown                                  scripts/sim/sword_defs.gd "CONVERGE_COOLDOWN: float = 2.5" "CONVERGE_COOLDOWN: float = 2.0"
mutate converge-range                                     scripts/sim/sword_defs.gd "CONVERGE_RANGE: float = 460.0" "CONVERGE_RANGE: float = 480.0"
mutate converge-target-radius                             scripts/sim/sword_defs.gd "CONVERGE_TARGET_RADIUS: float = 90.0" "CONVERGE_TARGET_RADIUS: float = 100.0"
mutate converge-boost                                     scripts/sim/sword_defs.gd "CONVERGE_BOOST: float = 1.5" "CONVERGE_BOOST: float = 1.4"
mutate converge-windup-factor                             scripts/sim/sword_defs.gd "CONVERGE_WINDUP_FACTOR: float = 0.6" "CONVERGE_WINDUP_FACTOR: float = 0.7"
mutate converge-strike-takes-the-command                  scripts/sim/sword_state.gd "	if phase == Phase.STRIKE or phase == Phase.STUCK or phase == Phase.ULTIMATE:
		return false
" "	if phase == Phase.STUCK or phase == Phase.ULTIMATE:
		return false
"
mutate converge-stuck-takes-the-command                   scripts/sim/sword_state.gd "	if phase == Phase.STRIKE or phase == Phase.STUCK or phase == Phase.ULTIMATE:
		return false
" "	if phase == Phase.STRIKE or phase == Phase.ULTIMATE:
		return false
"
mutate converge-ultimate-takes-the-command                scripts/sim/sword_state.gd "	if phase == Phase.STRIKE or phase == Phase.STUCK or phase == Phase.ULTIMATE:
		return false
" "	if phase == Phase.STRIKE or phase == Phase.STUCK:
		return false
"
mutate converge-windup-refuses-the-command                scripts/sim/sword_state.gd "	if phase == Phase.STRIKE or phase == Phase.STUCK or phase == Phase.ULTIMATE:
		return false
" "	if phase == Phase.STRIKE or phase == Phase.STUCK or phase == Phase.ULTIMATE or phase == Phase.WINDUP:
		return false
"
mutate converge-recover-refuses-the-command               scripts/sim/sword_state.gd "	if phase == Phase.STRIKE or phase == Phase.STUCK or phase == Phase.ULTIMATE:
		return false
" "	if phase == Phase.STRIKE or phase == Phase.STUCK or phase == Phase.ULTIMATE or phase == Phase.RECOVER:
		return false
"
mutate converge-target-edge-inclusive                     scripts/sim/sword_state.gd "		if dist < nearest_dist:
			nearest = enemy" "		if dist <= nearest_dist:
			nearest = enemy"
mutate converge-skips-corpses                             scripts/sim/sword_state.gd "		if dist < nearest_dist:
			nearest = enemy" "		if dist < nearest_dist and not enemy.dead:
			nearest = enemy"
mutate converge-never-targets                             scripts/sim/sword_state.gd "	begin(nearest, point, SwordDefs.CONVERGE_BOOST, true)" "	begin(null, point, SwordDefs.CONVERGE_BOOST, true)"
mutate converge-aims-at-the-player                        scripts/sim/sword_state.gd "	begin(nearest, point, SwordDefs.CONVERGE_BOOST, true)" "	begin(nearest, run.position, SwordDefs.CONVERGE_BOOST, true)"
mutate converge-no-boost                                  scripts/sim/sword_state.gd "	begin(nearest, point, SwordDefs.CONVERGE_BOOST, true)" "	begin(nearest, point, 1.0, true)"
mutate converge-full-windup                               scripts/sim/sword_state.gd "	begin(nearest, point, SwordDefs.CONVERGE_BOOST, true)" "	begin(nearest, point, SwordDefs.CONVERGE_BOOST, false)"
mutate converge-fast-windup-ignored                       scripts/sim/sword_state.gd "	timer = windup * (SwordDefs.CONVERGE_WINDUP_FACTOR if fast else 1.0)
" "	timer = windup
"
mutate converge-begin-forgets-the-boost                   scripts/sim/sword_state.gd "	boost = new_boost
	phase = Phase.WINDUP" "	boost = 1.0
	phase = Phase.WINDUP"
mutate converge-windup-span-not-set                       scripts/sim/sword_state.gd "	windup_span = timer
" ""
mutate converge-progress-uses-the-full-windup             scripts/sim/sword_state.gd "	return 1.0 - clampf(timer / windup_span, 0.0, 1.0)" "	return 1.0 - clampf(timer / windup, 0.0, 1.0)"
mutate converge-ignores-pause                             scripts/sim/game_run.gd "func try_converge(point: Vector2) -> ConvergeResult:
	if paused or dead:" "func try_converge(point: Vector2) -> ConvergeResult:
	if dead:"
mutate converge-ignores-death                             scripts/sim/game_run.gd "func try_converge(point: Vector2) -> ConvergeResult:
	if paused or dead:" "func try_converge(point: Vector2) -> ConvergeResult:
	if paused:"
mutate converge-ignores-the-cooldown                      scripts/sim/game_run.gd "	if converge_cooldown_left > 0.0:
		return ConvergeResult.COOLING_DOWN
" ""
mutate converge-no-range-clamp                            scripts/sim/game_run.gd "	if to_point.length() > SwordDefs.CONVERGE_RANGE:" "	if to_point.length() > SwordDefs.CONVERGE_RANGE * 3.0:"
mutate converge-range-from-the-camera                     scripts/sim/game_run.gd "	var to_point: Vector2 = point - position
	if to_point.length() > SwordDefs.CONVERGE_RANGE:" "	var to_point: Vector2 = point - camera
	if to_point.length() > SwordDefs.CONVERGE_RANGE:"
mutate converge-clamp-loses-the-direction                 scripts/sim/game_run.gd "		target = position + to_point.normalized() * SwordDefs.CONVERGE_RANGE" "		target = position + Vector2(SwordDefs.CONVERGE_RANGE, 0.0)"
mutate converge-cooldown-only-when-taken                  scripts/sim/game_run.gd "	converge_cooldown_left = SwordDefs.CONVERGE_COOLDOWN
	add_cue(SimCue.make(SimCue.Kind.CONVERGE" "	if taken > 0:
		converge_cooldown_left = SwordDefs.CONVERGE_COOLDOWN
	add_cue(SimCue.make(SimCue.Kind.CONVERGE"
mutate converge-commands-one-sword                        scripts/sim/game_run.gd "	for sword: SwordState in swords:
		if sword.command(self, target):" "	for sword: SwordState in swords.slice(0, 1):
		if sword.command(self, target):"
mutate converge-cue-unclamped                             scripts/sim/game_run.gd "SimCue.make(SimCue.Kind.CONVERGE, target," "SimCue.make(SimCue.Kind.CONVERGE, point,"
mutate converge-cue-counts-all-swords                     scripts/sim/game_run.gd "Vector2.ZERO, taken))" "Vector2.ZERO, swords.size()))"
mutate converge-cooldown-ignores-slowmo                   scripts/sim/game_run.gd "	converge_cooldown_left = maxf(0.0, converge_cooldown_left - dt)" "	converge_cooldown_left = maxf(0.0, converge_cooldown_left - TICK_DT)"
mutate converge-cooldown-never-ticks                      scripts/sim/game_run.gd "	converge_cooldown_left = maxf(0.0, converge_cooldown_left - dt)" "	converge_cooldown_left = maxf(0.0, converge_cooldown_left - 0.0)"
mutate converge-restart-keeps-the-cooldown                scripts/sim/game_run.gd "	converge_cooldown_left = 0.0
	death_time = 0.0
	help_left = HELP_SECONDS
	kills = 0" "	death_time = 0.0
	help_left = HELP_SECONDS
	kills = 0"
mutate converge-touch-aims-at-the-point                   scripts/sim/game_run.gd "try_converge(auto_aim() if command.at_nearest else command.point)" "try_converge(command.point)"
mutate ranges-toggle-while-paused                         scripts/sim/game_run.gd "			if not paused and not dead:
				show_ranges = not show_ranges" "			if not dead:
				show_ranges = not show_ranges"
mutate ranges-toggle-while-dead                           scripts/sim/game_run.gd "			if not paused and not dead:
				show_ranges = not show_ranges" "			if not paused:
				show_ranges = not show_ranges"
mutate ranges-restart-hides-them                          scripts/sim/game_run.gd "	hp = max_hp if scenario.start_health < 0.0" "	show_ranges = false
	hp = max_hp if scenario.start_health < 0.0"
mutate converge-middle-button                             scripts/input/input_translator.gd "[MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]" "[MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]"
mutate converge-left-button-only                          scripts/input/input_translator.gd "[MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]" "[MOUSE_BUTTON_LEFT]"
mutate converge-on-release                                scripts/input/input_translator.gd "if click.pressed and click.button_index in CONVERGE_BUTTONS" "if click.button_index in CONVERGE_BUTTONS"
mutate converge-on-emulated-clicks                        scripts/input/input_translator.gd " and click.device != InputEvent.DEVICE_ID_EMULATION:" ":"
mutate converge-skips-the-world-transform                 scripts/input/input_translator.gd "commands.append(GameCommand.converge(aim_world()))" "commands.append(GameCommand.converge(click.position))"
mutate ranges-tab-only                                    scripts/input/input_translator.gd "const RANGE_KEYS: Array[Key] = [KEY_TAB, KEY_G]" "const RANGE_KEYS: Array[Key] = [KEY_TAB]"
mutate ranges-g-only                                      scripts/input/input_translator.gd "const RANGE_KEYS: Array[Key] = [KEY_TAB, KEY_G]" "const RANGE_KEYS: Array[Key] = [KEY_G]"
mutate converge-touch-command-loses-nearest               scripts/sim/game_command.gd "	var command: GameCommand = _of(Kind.CONVERGE)
	command.at_nearest = true" "	var command: GameCommand = _of(Kind.CONVERGE)
	command.at_nearest = false"
mutate converge-hud-click-passes-through                  scripts/main.gd "		input.pointer = (event as InputEventMouseButton).position
		return
" "		input.pointer = (event as InputEventMouseButton).position
"
mutate converge-world-point-ignores-the-view-size         scripts/main.gd "get_viewport().get_visible_rect().size * 0.5" "Vector2(640.0, 360.0)"
mutate converge-world-point-forgets-the-centre            scripts/main.gd "return run.camera + viewport_point - get_viewport().get_visible_rect().size * 0.5" "return run.camera + viewport_point"
mutate converge-hud-never-ready                           scripts/hud.gd "	var ready: bool = run.converge_cooldown_left <= 0.0
	_converge_label" "	var ready: bool = run.converge_cooldown_left < 0.0
	_converge_label"
mutate converge-hud-bar-inverted                          scripts/hud.gd "CONVERGE_BAR_WIDTH * (1.0 - clampf(run.converge_cooldown_left / SwordDefs.CONVERGE_COOLDOWN, 0.0, 1.0))" "CONVERGE_BAR_WIDTH * clampf(run.converge_cooldown_left / SwordDefs.CONVERGE_COOLDOWN, 0.0, 1.0)"
mutate converge-hud-hint-forgets-the-click                scripts/hud.gd "   Click: Converge   Q / E / R" "   Q / E / R"
mutate ranges-drawn-for-the-dead                          scripts/presentation/effects_layer.gd "	if _run.show_ranges and not _run.dead:" "	if _run.show_ranges:"
mutate converge-ring-not-drawn                            scripts/presentation/effects_layer.gd "		SimCue.Kind.CONVERGE:
			_add_ring(cue.position, 60.0, 8.0, 0.35, Color(0.71, 0.86, 1.0, 0.9), 2.0)
" "		SimCue.Kind.CONVERGE:
			pass
"
mutate converge-chime-silent                              scripts/audio/sfx_bank.gd "		SimCue.Kind.CONVERGE:
			play(\"chime\")" "		SimCue.Kind.CONVERGE:
			pass"
mutate default-loadout-is-the-fang-fixture                scripts/sim/run_scenario.gd "var loadout: Array[SwordSpec] = RunScenario.default_loadout()" "var loadout: Array[SwordSpec] = RunScenario.fang_fixture_loadout()"
mutate default-loadout-colossus-element                   scripts/sim/run_scenario.gd "	specs.append(SwordSpec.make(SwordDefs.WARDEN, 0, &\"ice\"))
	specs.append(SwordSpec.make(SwordDefs.COLOSSUS, 0, &\"fire\"))
	return specs


## A run that equips" "	specs.append(SwordSpec.make(SwordDefs.WARDEN, 0, &\"ice\"))
	specs.append(SwordSpec.make(SwordDefs.COLOSSUS, 0, &\"ice\"))
	return specs


## A run that equips"
mutate default-loadout-warden-is-fang                     scripts/sim/run_scenario.gd "	specs.append(SwordSpec.make(SwordDefs.FANG, 0, &\"poison\"))
	specs.append(SwordSpec.make(SwordDefs.WARDEN, 0, &\"ice\"))
	specs.append(SwordSpec.make(SwordDefs.COLOSSUS, 0, &\"fire\"))" "	specs.append(SwordSpec.make(SwordDefs.FANG, 0, &\"poison\"))
	specs.append(SwordSpec.make(SwordDefs.FANG, 0, &\"ice\"))
	specs.append(SwordSpec.make(SwordDefs.COLOSSUS, 0, &\"fire\"))"
mutate crowd-encounter-takes-the-default-loadout          scripts/sim/run_scenario.gd "static func crowd_encounter() -> RunScenario:
	var scenario: RunScenario = RunScenario.fang_fixture()" "static func crowd_encounter() -> RunScenario:
	var scenario: RunScenario = RunScenario.new()"
mutate conditions-encounter-takes-the-default-loadout     scripts/sim/run_scenario.gd "static func conditions_encounter() -> RunScenario:
	var scenario: RunScenario = RunScenario.fang_fixture()" "static func conditions_encounter() -> RunScenario:
	var scenario: RunScenario = RunScenario.new()"
mutate spitter-encounter-takes-the-default-loadout        scripts/sim/run_scenario.gd "static func spitter_encounter() -> RunScenario:
	var scenario: RunScenario = RunScenario.fang_fixture()" "static func spitter_encounter() -> RunScenario:
	var scenario: RunScenario = RunScenario.new()"
mutate converge-chime-sound-missing-from-the-bank         scripts/audio/sfx_bank.gd "	\"chime\": preload(\"res://audio/sfx_chime.wav\"),
" ""
# --- Drops and swaps (slice #17)
mutate pickup-life-shortened                   scripts/sim/loot_defs.gd "const PICKUP_LIFE: float = 45.0" "const PICKUP_LIFE: float = 40.0"
mutate pickup-reach-widened                    scripts/sim/loot_defs.gd "const PICKUP_REACH: float = 80.0" "const PICKUP_REACH: float = 90.0"
mutate pickup-blink-window                     scripts/sim/loot_defs.gd "const PICKUP_BLINK_BELOW: float = 6.0" "const PICKUP_BLINK_BELOW: float = 5.0"
mutate pickup-blink-rate                       scripts/sim/loot_defs.gd "const PICKUP_BLINK_RATE: float = 8.0" "const PICKUP_BLINK_RATE: float = 6.0"
mutate return-drop-distance                    scripts/sim/loot_defs.gd "const RETURN_DROP: float = 24.0" "const RETURN_DROP: float = 20.0"
mutate return-spread-widened                   scripts/sim/loot_defs.gd "const RETURN_SPREAD: float = 20.0" "const RETURN_SPREAD: float = 40.0"
mutate swap-start-cooldown                     scripts/sim/loot_defs.gd "const SWAP_START_COOLDOWN: float = 0.4" "const SWAP_START_COOLDOWN: float = 0.5"
mutate swap-altitude                           scripts/sim/loot_defs.gd "const SWAP_ALTITUDE: float = 10.0" "const SWAP_ALTITUDE: float = 30.0"
mutate swap-start-velocity                     scripts/sim/loot_defs.gd "Vector2(0.0, -200.0)" "Vector2(0.0, -100.0)"
mutate swap-flash-weak                         scripts/sim/loot_defs.gd "const SWAP_FLASH: float = 1.0" "const SWAP_FLASH: float = 0.5"
mutate armed-hp-factor                         scripts/sim/loot_defs.gd "const ARMED_HP_FACTOR: float = 1.35" "const ARMED_HP_FACTOR: float = 1.3"
mutate drop-weight-colossus                    scripts/sim/loot_defs.gd "[3.0, 3.0, 2.5, 1.6]" "[3.0, 3.0, 2.5, 2.0]"
mutate drop-weight-fang                        scripts/sim/loot_defs.gd "[3.0, 3.0, 2.5, 1.6]" "[4.0, 3.0, 2.5, 1.6]"
mutate drop-types-order                        scripts/sim/loot_defs.gd "[SwordDefs.FANG, SwordDefs.WARDEN, SwordDefs.PIKE, SwordDefs.COLOSSUS]" "[SwordDefs.WARDEN, SwordDefs.FANG, SwordDefs.PIKE, SwordDefs.COLOSSUS]"
mutate first-wave-armed-count                  scripts/sim/loot_defs.gd "const FIRST_WAVE_ARMED: int = 2" "const FIRST_WAVE_ARMED: int = 1"
mutate mythic-cap                              scripts/sim/loot_defs.gd "const MYTHIC_CAP: float = 0.25" "const MYTHIC_CAP: float = 0.3"
mutate mythic-base                             scripts/sim/loot_defs.gd "const MYTHIC_BASE: float = 0.02" "const MYTHIC_BASE: float = 0.03"
mutate mythic-per-wave                         scripts/sim/loot_defs.gd "const MYTHIC_PER_WAVE: float = 0.02" "const MYTHIC_PER_WAVE: float = 0.03"
mutate rare-cap                                scripts/sim/loot_defs.gd "const RARE_CAP: float = 0.55" "const RARE_CAP: float = 0.5"
mutate rare-base                               scripts/sim/loot_defs.gd "const RARE_BASE: float = 0.16" "const RARE_BASE: float = 0.2"
mutate rare-per-wave                           scripts/sim/loot_defs.gd "const RARE_PER_WAVE: float = 0.04" "const RARE_PER_WAVE: float = 0.05"
mutate brute-rarity-bonus                      scripts/sim/loot_defs.gd "const BRUTE_RARITY_BONUS: float = 0.15" "const BRUTE_RARITY_BONUS: float = 0.1"
mutate armed-chance-husk                       scripts/sim/loot_defs.gd "const ARMED_CHANCE_HUSK: float = 0.2" "const ARMED_CHANCE_HUSK: float = 0.25"
mutate armed-chance-runner                     scripts/sim/loot_defs.gd "const ARMED_CHANCE_RUNNER: float = 0.12" "const ARMED_CHANCE_RUNNER: float = 0.15"
mutate armed-chance-spitter                    scripts/sim/loot_defs.gd "const ARMED_CHANCE_SPITTER: float = 0.22" "const ARMED_CHANCE_SPITTER: float = 0.25"
mutate armed-chance-brute                      scripts/sim/loot_defs.gd "const ARMED_CHANCE_BRUTE: float = 0.75" "const ARMED_CHANCE_BRUTE: float = 0.7"
mutate armed-chance-spitter-as-runner          scripts/sim/loot_defs.gd "			return ARMED_CHANCE_SPITTER" "			return ARMED_CHANCE_RUNNER"
mutate arming-guarantee-every-wave             scripts/sim/loot_defs.gd "	return wave == 1 and index < FIRST_WAVE_ARMED" "	return index < FIRST_WAVE_ARMED"
mutate arming-pike-on-second                   scripts/sim/loot_defs.gd "SwordDefs.PIKE if wave == 1 and index == 0 else drop_type_for(drop_draw)" "SwordDefs.PIKE if wave == 1 and index == 1 else drop_type_for(drop_draw)"
mutate arming-pike-every-wave                  scripts/sim/loot_defs.gd "SwordDefs.PIKE if wave == 1 and index == 0 else drop_type_for(drop_draw)" "SwordDefs.PIKE if index == 0 else drop_type_for(drop_draw)"
mutate drop-draw-edge-exclusive                scripts/sim/loot_defs.gd "		if remaining <= 0.0:" "		if remaining < 0.0:"
mutate rarity-mythic-full-bonus                scripts/sim/loot_defs.gd "MYTHIC_PER_WAVE * float(wave)) + bonus * 0.5:" "MYTHIC_PER_WAVE * float(wave)) + bonus:"
mutate rarity-rare-bonus-lost                  scripts/sim/loot_defs.gd "RARE_PER_WAVE * float(wave)) + bonus:" "RARE_PER_WAVE * float(wave)):"
mutate rarity-bonus-for-husks                  scripts/sim/loot_defs.gd "BRUTE_RARITY_BONUS if kind == EnemyDefs.BRUTE else 0.0" "BRUTE_RARITY_BONUS if kind == EnemyDefs.HUSK else 0.0"
mutate arming-chance-edge-inclusive            scripts/sim/loot_defs.gd "if not is_guaranteed(wave, index) and arm_roll >= armed_chance(kind):" "if not is_guaranteed(wave, index) and arm_roll > armed_chance(kind):"
mutate arming-element-never-poison             scripts/sim/loot_defs.gd "rng.randi_range(0, SwordDefs.ELEMENT_ORDER.size() - 1)" "rng.randi_range(0, SwordDefs.ELEMENT_ORDER.size() - 2)"
mutate arming-draw-range-short                 scripts/sim/loot_defs.gd "rng.randf_range(0.0, total_drop_weight())" "rng.randf_range(0.0, 8.5)"
mutate arming-guaranteed-still-rolls           scripts/sim/loot_defs.gd "	if not is_guaranteed(wave, index):
		arm_roll = rng.randf()" "	if true:
		arm_roll = rng.randf()"
mutate arming-pike-still-draws                 scripts/sim/loot_defs.gd "	if not (wave == 1 and index == 0):
		drop_draw" "	if true:
		drop_draw"
mutate pickup-blink-parity                     scripts/sim/pickup_state.gd "% 2 == 0" "% 2 == 1"
mutate pickup-never-blinks                     scripts/sim/pickup_state.gd "return life < LootDefs.PICKUP_BLINK_BELOW and " "return false and "
mutate pickup-spawns-short                     scripts/sim/pickup_state.gd "var life: float = LootDefs.PICKUP_LIFE" "var life: float = 30.0"
mutate rarity-color-common                     scripts/sim/sword_defs.gd "Color(205.0 / 255.0, 205.0 / 255.0, 215.0 / 255.0)," "Color(205.0 / 255.0, 205.0 / 255.0, 200.0 / 255.0),"
mutate rarity-color-rare                       scripts/sim/sword_defs.gd "Color(90.0 / 255.0, 175.0 / 255.0, 255.0 / 255.0)," "Color(90.0 / 255.0, 175.0 / 255.0, 200.0 / 255.0),"
mutate rarity-color-mythic                     scripts/sim/sword_defs.gd "Color(255.0 / 255.0, 196.0 / 255.0, 60.0 / 255.0)," "Color(255.0 / 255.0, 196.0 / 255.0, 160.0 / 255.0),"
mutate element-order                           scripts/sim/sword_defs.gd "const ELEMENT_ORDER: Array[StringName] = [&\"fire\", &\"ice\", &\"poison\"]" "const ELEMENT_ORDER: Array[StringName] = [&\"ice\", &\"fire\", &\"poison\"]"
mutate element-adjective-fire                  scripts/sim/sword_defs.gd "&\"fire\": \"Ember\"" "&\"fire\": \"Embers\""
mutate element-adjective-ice                   scripts/sim/sword_defs.gd "&\"ice\": \"Frost\"" "&\"ice\": \"Frosty\""
mutate element-adjective-poison                scripts/sim/sword_defs.gd "&\"poison\": \"Venom\"" "&\"poison\": \"Toxic\""
mutate element-tag-fire                        scripts/sim/sword_defs.gd "&\"fire\": \"FIRE  burns, spreads\"," "&\"fire\": \"FIRE  burns\","
mutate element-tag-ice                         scripts/sim/sword_defs.gd "&\"ice\": \"ICE  chills, freezes\"," "&\"ice\": \"ICE  chills\","
mutate element-tag-poison                      scripts/sim/sword_defs.gd "&\"poison\": \"POISON  stacking toxin\"," "&\"poison\": \"POISON  toxin\","
mutate blurb-fang                              scripts/sim/sword_defs.gd "const FANG_BLURB: String = \"close / rapid\"" "const FANG_BLURB: String = \"close\""
mutate blurb-warden                            scripts/sim/sword_defs.gd "const WARDEN_BLURB: String = \"mid / sweeping arc\"" "const WARDEN_BLURB: String = \"mid\""
mutate blurb-pike                              scripts/sim/sword_defs.gd "const PIKE_BLURB: String = \"long / piercing thrust\"" "const PIKE_BLURB: String = \"long\""
mutate blurb-colossus                          scripts/sim/sword_defs.gd "const COLOSSUS_BLURB: String = \"far / slow / crushing slam\"" "const COLOSSUS_BLURB: String = \"far\""
mutate blurb-pike-is-fang                      scripts/sim/sword_defs.gd "		PIKE:
			return PIKE_BLURB" "		PIKE:
			return FANG_BLURB"
mutate damage-of-uses-range-factor             scripts/sim/sword_defs.gd "return base_damage(spec.type_id) * RARITY_DAMAGE[spec.rarity]" "return base_damage(spec.type_id) * RARITY_RANGE[spec.rarity]"
mutate cooldown-of-uses-damage-factor          scripts/sim/sword_defs.gd "return base_cooldown(spec.type_id) * RARITY_COOLDOWN[spec.rarity]" "return base_cooldown(spec.type_id) * RARITY_DAMAGE[spec.rarity]"
mutate range-of-uses-cooldown-factor           scripts/sim/sword_defs.gd "return base_range(spec.type_id) * RARITY_RANGE[spec.rarity]" "return base_range(spec.type_id) * RARITY_COOLDOWN[spec.rarity]"
mutate length-of-uses-damage-factor            scripts/sim/sword_defs.gd "return base_length(spec.type_id) * RARITY_SIZE[spec.rarity]" "return base_length(spec.type_id) * RARITY_DAMAGE[spec.rarity]"
mutate recharge-of-ignores-rarity              scripts/sim/sword_defs.gd "return ultimate_cooldown(spec.type_id) * RARITY_COOLDOWN[spec.rarity]" "return ultimate_cooldown(spec.type_id)"
mutate full-name-order                         scripts/sim/sword_defs.gd "[RARITY_NAMES[spec.rarity], ELEMENT_ADJECTIVES.get(spec.element, String(spec.element)), display_name(spec.type_id)]" "[ELEMENT_ADJECTIVES.get(spec.element, String(spec.element)), RARITY_NAMES[spec.rarity], display_name(spec.type_id)]"
mutate swap-recharge-seconds-kept              scripts/sim/sword_state.gd "sword.ultimate_cooldown * replaced.ultimate_cooldown_left / replaced.ultimate_cooldown" "replaced.ultimate_cooldown_left"
mutate swap-recharge-reset                     scripts/sim/sword_state.gd "sword.ultimate_cooldown * replaced.ultimate_cooldown_left / replaced.ultimate_cooldown" "0.0"
mutate swap-recharge-full                      scripts/sim/sword_state.gd "sword.ultimate_cooldown * replaced.ultimate_cooldown_left / replaced.ultimate_cooldown" "sword.ultimate_cooldown"
mutate swap-recharge-wrong-divisor             scripts/sim/sword_state.gd "sword.ultimate_cooldown * replaced.ultimate_cooldown_left / replaced.ultimate_cooldown" "sword.ultimate_cooldown * replaced.ultimate_cooldown_left / sword.ultimate_cooldown"
mutate swap-recharge-from-new-sword            scripts/sim/sword_state.gd "sword.ultimate_cooldown * replaced.ultimate_cooldown_left / replaced.ultimate_cooldown" "replaced.ultimate_cooldown * replaced.ultimate_cooldown_left / sword.ultimate_cooldown"
mutate swap-start-cooldown-lost                scripts/sim/sword_state.gd "equip(spec_value, at, LootDefs.SWAP_START_COOLDOWN)" "equip(spec_value, at, 0.0)"
mutate swap-velocity-lost                      scripts/sim/sword_state.gd "	sword.velocity = LootDefs.SWAP_START_VELOCITY
" ""
mutate swap-flash-lost                         scripts/sim/sword_state.gd "	sword.flash = LootDefs.SWAP_FLASH
" ""
mutate swap-altitude-lost                      scripts/sim/sword_state.gd "		sword.altitude = LootDefs.SWAP_ALTITUDE
" "		pass
"
mutate swap-flash-slow-decay                   scripts/sim/sword_state.gd "flash = maxf(0.0, flash - dt * 3.0)" "flash = maxf(0.0, flash - dt * 1.0)"
mutate swap-flash-never-decays                 scripts/sim/sword_state.gd "	flash = maxf(0.0, flash - dt * 3.0)
" ""
mutate armed-health-lost                       scripts/sim/enemy_state.gd " * (LootDefs.ARMED_HP_FACTOR if armed_spec != null else 1.0)" ""
mutate armed-sword-lost                        scripts/sim/enemy_state.gd "	enemy.armed = armed_spec
" ""
mutate placement-armed-method-lost             scripts/sim/enemy_placement.gd "func armed_with(spec: SwordSpec) -> EnemyPlacement:
	armed = spec" "func armed_with(spec: SwordSpec) -> EnemyPlacement:
	armed = null"
mutate marker-armed-lost                       scripts/sim/spawn_marker.gd "	marker.armed = armed_spec
" ""
mutate wave-arming-always-off                  scripts/sim/wave_director.gd "queue_armed.append(LootDefs.roll_armed(run.rng, kind, wave, index) if _arm_waves else null)" "queue_armed.append(null)"
mutate wave-arming-on-by-default               scripts/sim/wave_director.gd "wave, index) if _arm_waves else null)" "wave, index) if not _arm_waves else null)"
mutate wave-arming-index-shifted               scripts/sim/wave_director.gd "roll_armed(run.rng, kind, wave, index)" "roll_armed(run.rng, kind, wave, index + 1)"
mutate wave-arming-kind-lost                   scripts/sim/wave_director.gd "roll_armed(run.rng, kind, wave, index)" "roll_armed(run.rng, EnemyDefs.HUSK, wave, index)"
mutate wave-queue-sword-dropped                scripts/sim/wave_director.gd "var carried: SwordSpec = queue_armed.pop_front()" "var carried: SwordSpec = null"
mutate wave-marker-sword-dropped               scripts/sim/wave_director.gd "SpawnMarker.make(kind, _spawn_point(run), carried)" "SpawnMarker.make(kind, _spawn_point(run))"
mutate wave-enemy-sword-dropped                scripts/sim/wave_director.gd "run.next_serial(), phase, cooldown, marker.armed)" "run.next_serial(), phase, cooldown)"
mutate pickup-reach-inclusive                  scripts/sim/game_run.gd "if distance < LootDefs.PICKUP_REACH and distance < nearest_distance:" "if distance <= LootDefs.PICKUP_REACH and distance < nearest_distance:"
mutate pickup-nearest-lost                     scripts/sim/game_run.gd "if distance < LootDefs.PICKUP_REACH and distance < nearest_distance:" "if distance < LootDefs.PICKUP_REACH:"
mutate pickup-tie-takes-last                   scripts/sim/game_run.gd "if distance < LootDefs.PICKUP_REACH and distance < nearest_distance:" "if distance < LootDefs.PICKUP_REACH and distance <= nearest_distance:"
mutate pickup-reach-from-camera                scripts/sim/game_run.gd "var distance: float = (pickup.position - position).length()" "var distance: float = (pickup.position - camera).length()"
mutate swap-allowed-while-paused               scripts/sim/game_run.gd "	if paused or dead:
		return SwapResult.UNAVAILABLE" "	if dead:
		return SwapResult.UNAVAILABLE"
mutate swap-allowed-while-dead                 scripts/sim/game_run.gd "	if paused or dead:
		return SwapResult.UNAVAILABLE" "	if paused:
		return SwapResult.UNAVAILABLE"
mutate swap-refusal-silent                     scripts/sim/game_run.gd "		add_cue(SimCue.make(SimCue.Kind.SWAP_REFUSED, position))
" ""
mutate swap-negative-slot-allowed              scripts/sim/game_run.gd "	if slot < 0 or slot >= swords.size():
		return SwapResult.NO_SWORD" "	if slot >= swords.size():
		return SwapResult.NO_SWORD"
mutate swap-always-slot-one                    scripts/sim/game_run.gd "swords[slot] = SwordState.swapped_in(" "swords[0] = SwordState.swapped_in("
mutate swap-starts-at-player                   scripts/sim/game_run.gd "SwordState.swapped_in(claimed.spec, claimed.position, replaced)" "SwordState.swapped_in(claimed.spec, position, replaced)"
mutate swap-pickup-kept                        scripts/sim/game_run.gd "	pickups.erase(claimed)
" ""
mutate swap-returns-the-claimed-sword          scripts/sim/game_run.gd "PickupState.make(replaced.spec, returned_at, _next_pickup_serial)" "PickupState.make(claimed.spec, returned_at, _next_pickup_serial)"
mutate swap-return-in-place                    scripts/sim/game_run.gd "var returned_at: Vector2 = claimed.position + Vector2(rng.randf_range(-LootDefs.RETURN_SPREAD, LootDefs.RETURN_SPREAD), LootDefs.RETURN_DROP)" "var returned_at: Vector2 = claimed.position"
mutate swap-return-no-spread                   scripts/sim/game_run.gd "Vector2(rng.randf_range(-LootDefs.RETURN_SPREAD, LootDefs.RETURN_SPREAD), LootDefs.RETURN_DROP)" "Vector2(0.0, LootDefs.RETURN_DROP)"
mutate swap-return-no-drop                     scripts/sim/game_run.gd "Vector2(rng.randf_range(-LootDefs.RETURN_SPREAD, LootDefs.RETURN_SPREAD), LootDefs.RETURN_DROP)" "Vector2(rng.randf_range(-LootDefs.RETURN_SPREAD, LootDefs.RETURN_SPREAD), 0.0)"
mutate swap-cue-lost                           scripts/sim/game_run.gd "	add_cue(cue)
	return SwapResult.SWAPPED" "	return SwapResult.SWAPPED"
mutate swap-cue-wrong-sword                    scripts/sim/game_run.gd "	cue.spec = claimed.spec
" "	cue.spec = replaced.spec
"
mutate swap-cue-slot-lost                      scripts/sim/game_run.gd "SimCue.make(SimCue.Kind.SWORD_SWAPPED, claimed.position, Vector2.ZERO, slot)" "SimCue.make(SimCue.Kind.SWORD_SWAPPED, claimed.position, Vector2.ZERO, 0)"
mutate swap-cue-origin-lost                    scripts/sim/game_run.gd "	cue.origin = returned_at
" ""
mutate swap-command-wrong-slot                 scripts/sim/game_run.gd "			try_swap(command.slot)" "			try_swap(0)"
mutate drop-lost                               scripts/sim/game_run.gd "	if enemy.armed != null:
		# The sword it carried" "	if false:
		# The sword it carried"
mutate drop-at-player                          scripts/sim/game_run.gd "PickupState.make(enemy.armed, enemy.position, _next_pickup_serial)" "PickupState.make(enemy.armed, position, _next_pickup_serial)"
mutate drop-cue-lost                           scripts/sim/game_run.gd "		add_cue(drop)
" ""
mutate drop-cue-sword-lost                     scripts/sim/game_run.gd "		drop.spec = enemy.armed
" ""
mutate pickup-life-runs-double                 scripts/sim/game_run.gd "		pickup.life -= dt
" "		pickup.life -= dt * 2.0
"
mutate pickup-life-frozen                      scripts/sim/game_run.gd "		pickup.life -= dt
" ""
mutate pickup-removed-late                     scripts/sim/game_run.gd "		if pickup.life > 0.0:
			lying.append(pickup)" "		if pickup.life >= 0.0:
			lying.append(pickup)"
mutate pickup-update-lost                      scripts/sim/game_run.gd "	_update_pickups(dt)
" ""
mutate pickups-kept-on-restart                 scripts/sim/game_run.gd "	_next_pickup_serial = 0
	pickups = []
" "	_next_pickup_serial = 0
"
mutate drops-encounter-slot-lost               scripts/sim/game_run.gd "		scenario if scenario.encounter == RunScenario.ENCOUNTER_DROPS else RunScenario.drops_encounter(),
" "		RunScenario.new(),
"
mutate placement-armed-dropped                 scripts/sim/game_run.gd "placement.phase, maxf(cooldown, 0.0), placement.armed)" "placement.phase, maxf(cooldown, 0.0))"
mutate snapshot-pickup-count-lost              scripts/sim/game_run.gd "\"pickup_count\": pickups.size()," "\"pickup_count\": 0,"
mutate swap-command-slot-lost                  scripts/sim/game_command.gd "	var command: GameCommand = _of(Kind.SWAP)
	command.slot = slot_value" "	var command: GameCommand = _of(Kind.SWAP)"
mutate swap-keys-order                         scripts/input/input_translator.gd "const SWAP_KEYS: Array[Key] = [KEY_1, KEY_2, KEY_3]" "const SWAP_KEYS: Array[Key] = [KEY_1, KEY_3, KEY_2]"
mutate swap-key-slot-lost                      scripts/input/input_translator.gd "commands.append(GameCommand.swap(SWAP_KEYS.find(code)))" "commands.append(GameCommand.swap(0))"
mutate swap-keys-ignored                       scripts/input/input_translator.gd "			elif code in SWAP_KEYS:" "			elif false:"
mutate drops-encounter-not-in-cycle            scripts/sim/run_scenario.gd "ENCOUNTER_COLOSSUS, ENCOUNTER_DROPS]" "ENCOUNTER_COLOSSUS]"
mutate drops-encounter-title                   scripts/sim/run_scenario.gd "		ENCOUNTER_DROPS:
			return \"Drops\"" "		ENCOUNTER_DROPS:
			return \"Drop\""
mutate drops-encounter-wave-unarmed            scripts/sim/run_scenario.gd "	scenario.loadout = drops_fixture_loadout()
	scenario.arm_waves = true
" "	scenario.loadout = drops_fixture_loadout()
"
mutate arming-on-in-every-run                  scripts/sim/run_scenario.gd "var arm_waves: bool = false" "var arm_waves: bool = true"
mutate drops-encounter-foes-unarmed            scripts/sim/run_scenario.gd ".armed_with(spec))" ")"
mutate drops-encounter-all-common              scripts/sim/run_scenario.gd "int(float(i) / 4.0)" "0"
mutate drops-encounter-one-element             scripts/sim/run_scenario.gd "SwordDefs.ELEMENT_ORDER[i % SwordDefs.ELEMENT_ORDER.size()]" "SwordDefs.ELEMENT_ORDER[0]"
mutate drops-encounter-no-spitters-or-brutes   scripts/sim/run_scenario.gd "	&\"husk\", &\"runner\", &\"spitter\", &\"brute\", &\"runner\", &\"husk\", &\"brute\", &\"spitter\", &\"spitter\", &\"brute\", &\"husk\", &\"runner\"," "	&\"husk\", &\"runner\", &\"husk\", &\"husk\", &\"runner\", &\"husk\", &\"husk\", &\"husk\", &\"husk\", &\"husk\", &\"husk\", &\"runner\","
mutate drops-encounter-no-pikes                scripts/sim/run_scenario.gd "SwordDefs.PIKE, SwordDefs.COLOSSUS, SwordDefs.WARDEN, SwordDefs.FANG, SwordDefs.COLOSSUS, SwordDefs.PIKE,
	SwordDefs.PIKE, SwordDefs.COLOSSUS" "SwordDefs.FANG, SwordDefs.COLOSSUS, SwordDefs.WARDEN, SwordDefs.FANG, SwordDefs.COLOSSUS, SwordDefs.FANG,
	SwordDefs.FANG, SwordDefs.COLOSSUS"
mutate drops-encounter-wave-lost               scripts/sim/run_scenario.gd "scenario.wave_kinds = DROPS_WAVE.duplicate()" "scenario.wave_kinds = []"
mutate drops-fixture-no-colossus               scripts/sim/run_scenario.gd "var types: Array[StringName] = [SwordDefs.FANG, SwordDefs.WARDEN, SwordDefs.COLOSSUS]" "var types: Array[StringName] = [SwordDefs.FANG, SwordDefs.WARDEN, SwordDefs.PIKE]"
mutate drops-fixture-wrong-elements            scripts/sim/run_scenario.gd "var elements: Array[StringName] = [&\"poison\", &\"ice\", &\"fire\"]" "var elements: Array[StringName] = [&\"fire\", &\"ice\", &\"poison\"]"
mutate drops-launch-option-lost                scripts/launch_options.gd "		\"drops\":
			return RunScenario.drops_encounter()" "		\"drops\":
			return RunScenario.colossus_encounter()"
mutate drops-legend-lost                       scripts/hud.gd "	elif run.scenario.encounter == RunScenario.ENCOUNTER_DROPS:" "	elif false:"
mutate drops-legend-ignores-standing           scripts/hud.gd "			armed_left += 1 if enemy.armed != null else 0" "			armed_left += 0"
mutate drops-legend-ignores-queue              scripts/hud.gd "			armed_left += 1 if carried != null else 0" "			armed_left += 0"
mutate drops-legend-ignores-markers            scripts/hud.gd "			armed_left += 1 if marker.armed != null else 0" "			armed_left += 0"
mutate drops-legend-lying-lost                 scripts/hud.gd "			armed_left, run.pickups.size(), run.cue_count(SimCue.Kind.SWORD_DROPPED)" "			armed_left, 0, run.cue_count(SimCue.Kind.SWORD_DROPPED)"
mutate drops-legend-dropped-lost               scripts/hud.gd "run.cue_count(SimCue.Kind.SWORD_DROPPED), run.cue_count(SimCue.Kind.SWORD_SWAPPED)" "0, run.cue_count(SimCue.Kind.SWORD_SWAPPED)"
mutate drops-legend-swapped-lost               scripts/hud.gd "run.cue_count(SimCue.Kind.SWORD_SWAPPED), int(LootDefs.PICKUP_REACH)" "0, int(LootDefs.PICKUP_REACH)"
mutate pickup-card-always-shown                scripts/hud.gd "	_pickup_card.visible = near != null
" "	_pickup_card.visible = true
"
mutate pickup-card-offered-when-dead           scripts/hud.gd "var near: PickupState = null if run.dead else run.nearest_pickup()" "var near: PickupState = run.nearest_pickup()"
mutate pickup-card-x-unclamped                 scripts/hud.gd "	var ideal: Vector2 = Vector2(drop.x + 40.0, drop.y - card.y - 40.0).clamp(low, high)" "	var ideal: Vector2 = Vector2(drop.x + 40.0, clampf(drop.y - card.y - 40.0, low.y, high.y))"
mutate pickup-card-y-unclamped                 scripts/hud.gd "	var ideal: Vector2 = Vector2(drop.x + 40.0, drop.y - card.y - 40.0).clamp(low, high)" "	var ideal: Vector2 = Vector2(clampf(drop.x + 40.0, low.x, high.x), drop.y - card.y - 40.0)"
mutate pickup-card-over-the-slot-cards         scripts/hud.gd "	controls.append_array(_ult_cards)" "	controls.append_array([])"
mutate pickup-card-over-the-text-lines             scripts/hud.gd "	controls.append_array([_build_label, _hint_label])" "	controls.append_array([])"
mutate pickup-card-over-the-health                 scripts/hud.gd "	controls.append_array([_hp_back, _hp_label])" "	controls.append_array([])"
mutate pickup-card-over-the-health-value           scripts/hud.gd "	controls.append_array([_hp_back, _hp_label])" "	controls.append_array([_hp_back])"
mutate pickup-card-over-the-cooldowns              scripts/hud.gd "	controls.append_array([_dash_label, _dash_track, _converge_label, _converge_track])" "	controls.append_array([])"
mutate pickup-card-over-the-converge-bar           scripts/hud.gd "	controls.append_array([_dash_label, _dash_track, _converge_label, _converge_track])" "	controls.append_array([_dash_label, _dash_track, _converge_label])"
mutate pickup-card-over-the-buttons                scripts/hud.gd "	controls.append_array([_pause_button, _restart_button, _encounter_button, _shove_button, _dash_button])" "	controls.append_array([])"
mutate pickup-card-over-the-dev-button             scripts/hud.gd "	controls.append_array([_pause_button, _restart_button, _encounter_button, _shove_button, _dash_button])" "	controls.append_array([_pause_button, _restart_button, _shove_button, _dash_button])"
mutate pickup-card-over-the-shove-button           scripts/hud.gd "	controls.append_array([_pause_button, _restart_button, _encounter_button, _shove_button, _dash_button])" "	controls.append_array([_pause_button, _restart_button, _encounter_button, _dash_button])"
mutate pickup-card-over-the-dash-button            scripts/hud.gd "	controls.append_array([_pause_button, _restart_button, _encounter_button, _shove_button, _dash_button])" "	controls.append_array([_pause_button, _restart_button, _encounter_button, _shove_button])"
mutate pickup-card-over-the-legend                 scripts/hud.gd "	controls.append(_encounter_label)" "	controls.append_array([])"
mutate pickup-card-over-the-audio-prompt           scripts/hud.gd "	controls.append(_audio_prompt)" "	controls.append_array([])"
mutate pickup-card-over-the-drop                   scripts/hud.gd "	with_halo.append(drop_halo)" "	with_halo.append(Rect2())"
mutate pickup-card-ignores-the-hud-search          scripts/hud.gd "	if _covers_nothing(ideal, with_halo):" "	if true:"
mutate pickup-card-label-box-not-text              scripts/hud.gd "		return Rect2(box.position + spare * shift, need)" "		return box"
mutate pickup-card-label-alignment-lost            scripts/hud.gd "		return Rect2(box.position + spare * shift, need)" "		return Rect2(box.position, need)"
mutate pickup-card-fallback-ignores-overlap        scripts/hud.gd "		if area < least_area - 0.01 or (absf(area - least_area) <= 0.01 and distance < least_distance):" "		if distance < least_distance:"
mutate pickup-card-too-narrow-for-its-text         scripts/hud.gd "const PICKUP_CARD_SIZE: Vector2 = Vector2(448.0, 214.0)" "const PICKUP_CARD_SIZE: Vector2 = Vector2(360.0, 214.0)"
mutate pickup-card-comparison-font-grows          scripts/hud.gd "		compare.add_theme_font_size_override(\"font_size\", 14)" "		compare.add_theme_font_size_override(\"font_size\", 17)"
mutate controls-hint-runs-into-the-buttons          scripts/hud.gd "1 / 2 / 3: swap a drop\\nTab / G: ranges   H: help   P / Esc: pause" "1 / 2 / 3: swap a drop   Tab / G: ranges   H: help   P / Esc: pause   R after death\\nTab / G: ranges   H: help   P / Esc: pause"
mutate pickup-card-comparison-lost             scripts/hud.gd "			_pickup_compare[slot].text = PickupCard.compare_to(spec, slot, equipped)
" ""
mutate pickup-card-name-colour-lost            scripts/hud.gd "	_pickup_lines[0].modulate = tint
" ""
mutate pickup-card-border-colour-lost          scripts/hud.gd "	_pickup_style.border_color = tint
" ""
mutate pickup-card-element-colour-lost         scripts/hud.gd "	_pickup_lines[3].modulate = PlaceholderSwordVisual.ELEMENT_COLORS.get(spec.element, Color.WHITE)
" ""
mutate slot-card-rarity-tag-on-common          scripts/hud.gd "SwordDefs.RARITY_NAMES[sword.spec.rarity].to_upper() if sword.spec.rarity > 0 else \"\"" "SwordDefs.RARITY_NAMES[sword.spec.rarity].to_upper()"
mutate slot-card-rarity-tag-lost               scripts/hud.gd "SwordDefs.RARITY_NAMES[sword.spec.rarity].to_upper() if sword.spec.rarity > 0 else \"\"" "\"\""
mutate slot-card-key-line-off-by-one           scripts/hud.gd "\"key %d swaps this sword\" % (slot + 1)" "\"key %d swaps this sword\" % slot"
mutate slot-card-border-colour                 scripts/hud.gd "border_color = rarity_tint.darkened(0.3) if sword.spec.rarity == 0 else rarity_tint" "border_color = rarity_tint"
mutate slot-card-flash-lost                    scripts/hud.gd "Color(tint, 0.72), 0.12 + 0.35 * sword.flash)" "Color(tint, 0.72), 0.12)"
mutate card-hint-text                          scripts/pickup_card.gd "const HINT: String = \"press 1 / 2 / 3 to swap\"" "const HINT: String = \"press 1 / 2 / 3\""
mutate card-speed-not-inverted                 scripts/pickup_card.gd "1.0 / SwordDefs.cooldown_of(spec), SwordDefs.range_of(spec)]" "SwordDefs.cooldown_of(spec), SwordDefs.range_of(spec)]"
mutate card-skill-shot-note-lost               scripts/pickup_card.gd "\"  (skill shot)\" if SwordDefs.ultimate_is_shot(spec.type_id) else \"\"" "\"\""
mutate card-recharge-ignores-rarity            scripts/pickup_card.gd "SwordDefs.ultimate_recharge_of(spec)]" "SwordDefs.ultimate_cooldown(spec.type_id)]"
mutate card-element-line-lost                  scripts/pickup_card.gd "found.append(SwordDefs.ELEMENT_TAGS.get(spec.element, String(spec.element).to_upper()))" "found.append(String(spec.element).to_upper())"
mutate card-compare-reversed                   scripts/pickup_card.gd "SwordDefs.damage_of(spec) - SwordDefs.damage_of(equipped)," "SwordDefs.damage_of(equipped) - SwordDefs.damage_of(spec),"
mutate card-compare-slot-number                scripts/pickup_card.gd "		slot + 1,
" "		slot,
"
mutate card-compare-names-the-pickup           scripts/pickup_card.gd "		SwordDefs.full_name(equipped),
" "		SwordDefs.full_name(spec),
"
mutate card-compare-range-reversed             scripts/pickup_card.gd "SwordDefs.range_of(spec) - SwordDefs.range_of(equipped)," "SwordDefs.range_of(equipped) - SwordDefs.range_of(spec),"
mutate card-compare-speed-reversed             scripts/pickup_card.gd "1.0 / SwordDefs.cooldown_of(spec) - 1.0 / SwordDefs.cooldown_of(equipped)," "1.0 / SwordDefs.cooldown_of(equipped) - 1.0 / SwordDefs.cooldown_of(spec),"
mutate presenter-pickups-not-synced            scripts/presentation/run_presenter.gd "	_sync_pickups(run)
" ""
mutate presenter-pickup-hover-lost             scripts/presentation/run_presenter.gd "		visual.apply_hover(SwordDefs.length_of(pickup.spec) * 0.6 + sin(phase * 3.0) * 3.0)
" ""
mutate presenter-pickup-never-blinks           scripts/presentation/run_presenter.gd "		visual.visible = not pickup.blink_hidden()
" ""
mutate presenter-pickup-upright                scripts/presentation/run_presenter.gd "PI / 2.0 + sin(phase * 1.3) * 0.08" "-PI / 2.0"
mutate presenter-pickup-visuals-leak           scripts/presentation/run_presenter.gd "	_drop_missing(_pickup_visuals, live)" "	pass"
mutate presenter-reset-leaks-pickup-visuals    scripts/presentation/run_presenter.gd "	for visual: Node in _pickup_visuals.values():
		visual.queue_free()
" ""
mutate presenter-flash-lost                    scripts/presentation/run_presenter.gd "		visual.apply_flash(sword.flash)
" ""
mutate presenter-armed-sword-lost              scripts/presentation/run_presenter.gd "			visual.apply_armed(enemy.armed)
" ""
mutate sword-visual-contract-drops-flash       scripts/presentation/sword_visual.gd "	_on_flash(amount)" "	pass"
mutate sword-visual-contract-drops-hover       scripts/presentation/sword_visual.gd "	_on_hover(height)" "	pass"
mutate enemy-visual-contract-drops-armed       scripts/presentation/enemy_visual.gd "	_on_armed(spec)" "	pass"
mutate sword-visual-rarity-size-lost           scripts/presentation/placeholder_sword_visual.gd "	_scale = SwordDefs.RARITY_SIZE[spec.rarity]
" ""
mutate sword-visual-glow-always-rarity         scripts/presentation/placeholder_sword_visual.gd "SwordDefs.RARITY_COLORS[spec.rarity] if spec.rarity > 0 else _color" "SwordDefs.RARITY_COLORS[spec.rarity]"
mutate sword-visual-glow-never-rarity          scripts/presentation/placeholder_sword_visual.gd "SwordDefs.RARITY_COLORS[spec.rarity] if spec.rarity > 0 else _color" "_color"
mutate sword-visual-flash-ignored              scripts/presentation/placeholder_sword_visual.gd "func _on_flash(amount: float) -> void:
	_flash = amount" "func _on_flash(amount: float) -> void:
	pass"
mutate sword-visual-hover-not-resting          scripts/presentation/placeholder_sword_visual.gd "	_resting = true
" ""
mutate sword-visual-hover-ignored              scripts/presentation/placeholder_sword_visual.gd "	_hover = height
" ""
mutate enemy-visual-sword-not-drawn            scripts/presentation/placeholder_enemy_visual.gd "	if _armed != null:
		_draw_carried_sword(radius)
" ""
mutate enemy-visual-armed-ignored              scripts/presentation/placeholder_enemy_visual.gd "func _on_armed(spec: SwordSpec) -> void:
	_armed = spec" "func _on_armed(spec: SwordSpec) -> void:
	_armed = null"
mutate pickup-ground-not-drawn                 scripts/presentation/effects_layer.gd "		_draw_pickup_ground(pickup)
" "		pass
"
mutate pickup-blink-ignored-by-layer           scripts/presentation/effects_layer.gd "	if pickup.blink_hidden():
		return
" ""
mutate pickup-ring-not-drawn                   scripts/presentation/effects_layer.gd "	_rim(&\"pickup_ring\", Vector2.ZERO, 22.0, Color(tint, 0.5), 2.0, 24)
" ""
mutate pickup-beam-on-common                   scripts/presentation/effects_layer.gd "	if rarity > 0:
		var height: float = 120.0" "	if true:
		var height: float = 120.0"
mutate pickup-beam-short                       scripts/presentation/effects_layer.gd "for strip: int in 6:" "for strip: int in 3:"
mutate pickup-rarity-glow-not-drawn            scripts/presentation/effects_layer.gd "	_disc(&\"pickup_glow_rarity\", pickup.position, 34.0 + 8.0 * float(rarity), Color(tint, 0.2))
" ""
mutate pickup-element-glow-not-drawn           scripts/presentation/effects_layer.gd "	_disc(&\"pickup_glow_element\", pickup.position, 26.0, Color(element_color(pickup.spec.element), 0.3))
" ""
mutate drop-ring-lost                          scripts/presentation/effects_layer.gd "				_add_ring(cue.position, 10.0, 90.0, 0.5, drop_tint, 2.0)
" ""
mutate drop-name-lost                          scripts/presentation/effects_layer.gd "				_add_text(cue.position + Vector2(0.0, -30.0), cue.spec.display_name(), drop_tint, 1.3, 26, 40.0)
" ""
mutate swap-ring-lost                          scripts/presentation/effects_layer.gd "				_add_ring(cue.position, 8.0, 110.0, 0.45, swap_tint, 3.0)
" ""
mutate swap-sparks-lost                        scripts/presentation/effects_layer.gd "				for i: int in 24:
					_add_spark(cue.position, SimMath.polar(-PI / 2.0 + _rng.randf_range(-PI, PI), _rng.randf_range(150.0, 500.0)), _rng.randf_range(0.2, 0.5), swap_tint)
" ""
mutate swap-name-lost                          scripts/presentation/effects_layer.gd "				_add_text(_run.position + Vector2(0.0, -50.0), cue.spec.display_name(), swap_tint, 1.2, 32, 50.0)
" ""
mutate swap-refusal-text-lost                  scripts/presentation/effects_layer.gd "			_add_text(cue.position + Vector2(0.0, -46.0), \"no sword within reach\", Color(0.62, 0.6, 0.78), 0.5, 22)" "			pass"
mutate swap-sound-lost                         scripts/audio/sfx_bank.gd "		SimCue.Kind.SWORD_SWAPPED:
			play(\"chime\")" "		SimCue.Kind.SWORD_SWAPPED:
			play(\"hit\")"
# --- Waves, breaks and the normal run (slice #18)
mutate waves-enemies-per-wave                   scripts/sim/wave_defs.gd "const ENEMIES_PER_WAVE: int = 3" "const ENEMIES_PER_WAVE: int = 4"
mutate waves-enemies-base                       scripts/sim/wave_defs.gd "const ENEMIES_BASE: int = 5" "const ENEMIES_BASE: int = 6"
mutate waves-husk-weight                        scripts/sim/wave_defs.gd "const HUSK_WEIGHT: float = 6.0" "const HUSK_WEIGHT: float = 5.0"
mutate waves-runner-weight                      scripts/sim/wave_defs.gd "const RUNNER_WEIGHT: float = 2.5" "const RUNNER_WEIGHT: float = 3.0"
mutate waves-runner-unlock-late                 scripts/sim/wave_defs.gd "const RUNNER_FIRST_WAVE: int = 2" "const RUNNER_FIRST_WAVE: int = 3"
mutate waves-spitter-weight                     scripts/sim/wave_defs.gd "const SPITTER_WEIGHT: float = 2.0" "const SPITTER_WEIGHT: float = 2.5"
mutate waves-spitter-unlock-early               scripts/sim/wave_defs.gd "const SPITTER_FIRST_WAVE: int = 3" "const SPITTER_FIRST_WAVE: int = 2"
mutate waves-brute-weight-base                  scripts/sim/wave_defs.gd "const BRUTE_WEIGHT_BASE: float = 0.6" "const BRUTE_WEIGHT_BASE: float = 0.8"
mutate waves-brute-weight-growth                scripts/sim/wave_defs.gd "const BRUTE_WEIGHT_PER_WAVE: float = 0.25" "const BRUTE_WEIGHT_PER_WAVE: float = 0.3"
mutate waves-brute-unlock-late                  scripts/sim/wave_defs.gd "const BRUTE_FIRST_WAVE: int = 2" "const BRUTE_FIRST_WAVE: int = 3"
mutate waves-runner-pool-gate                   scripts/sim/wave_defs.gd "	if wave >= RUNNER_FIRST_WAVE:
" "	if wave > RUNNER_FIRST_WAVE:
"
mutate waves-brute-pool-gate                    scripts/sim/wave_defs.gd "	if wave >= BRUTE_FIRST_WAVE:
" "	if wave >= BRUTE_FIRST_WAVE + 1:
"
mutate waves-pool-order                         scripts/sim/wave_defs.gd "	var kinds: Array[StringName] = [EnemyDefs.HUSK]
	if wave >= RUNNER_FIRST_WAVE:
		kinds.append(EnemyDefs.RUNNER)
	if wave >= SPITTER_FIRST_WAVE:
		kinds.append(EnemyDefs.SPITTER)
	if wave >= BRUTE_FIRST_WAVE:
		kinds.append(EnemyDefs.BRUTE)" "	var kinds: Array[StringName] = [EnemyDefs.HUSK]
	if wave >= RUNNER_FIRST_WAVE:
		kinds.append(EnemyDefs.RUNNER)
	if wave >= BRUTE_FIRST_WAVE:
		kinds.append(EnemyDefs.BRUTE)
	if wave >= SPITTER_FIRST_WAVE:
		kinds.append(EnemyDefs.SPITTER)"
mutate waves-total-weight-flat                  scripts/sim/wave_defs.gd "		total += weight_of(kind, wave)" "		total += 1.0"
mutate waves-kind-edge-exclusive                scripts/sim/wave_defs.gd "		if remaining <= 0.0:
			return kind" "		if remaining < 0.0:
			return kind"
mutate waves-kind-fallback-first                scripts/sim/wave_defs.gd "	return kinds[kinds.size() - 1]" "	return kinds[0]"
mutate waves-spawn-interval-base                scripts/sim/wave_defs.gd "const SPAWN_INTERVAL_BASE: float = 0.42" "const SPAWN_INTERVAL_BASE: float = 0.5"
mutate waves-spawn-interval-slope               scripts/sim/wave_defs.gd "const SPAWN_INTERVAL_PER_WAVE: float = 0.02" "const SPAWN_INTERVAL_PER_WAVE: float = 0.03"
mutate waves-spawn-interval-floor               scripts/sim/wave_defs.gd "const SPAWN_INTERVAL_MIN: float = 0.12" "const SPAWN_INTERVAL_MIN: float = 0.2"
mutate waves-first-spawn-delay                  scripts/sim/wave_defs.gd "const FIRST_SPAWN_DELAY: float = 0.3" "const FIRST_SPAWN_DELAY: float = 0.4"
mutate waves-hp-growth-off-by-one               scripts/sim/wave_defs.gd "1.0 + EnemyDefs.HP_PER_WAVE * float(wave - 1)" "1.0 + EnemyDefs.HP_PER_WAVE * float(wave)"
mutate waves-spawn-min-distance                 scripts/sim/wave_defs.gd "const SPAWN_MIN_DISTANCE: float = 420.0" "const SPAWN_MIN_DISTANCE: float = 380.0"
mutate waves-spawn-max-distance                 scripts/sim/wave_defs.gd "const SPAWN_MAX_DISTANCE: float = 720.0" "const SPAWN_MAX_DISTANCE: float = 800.0"
mutate waves-spawn-near-limit                   scripts/sim/wave_defs.gd "const SPAWN_NEAR_LIMIT: float = 320.0" "const SPAWN_NEAR_LIMIT: float = 250.0"
mutate waves-spawn-edge-margin                  scripts/sim/wave_defs.gd "const SPAWN_EDGE_MARGIN: float = 50.0" "const SPAWN_EDGE_MARGIN: float = 30.0"
mutate waves-spawn-attempts                     scripts/sim/wave_defs.gd "const SPAWN_ATTEMPTS: int = 12" "const SPAWN_ATTEMPTS: int = 8"
mutate waves-spawn-no-clamp                     scripts/sim/wave_defs.gd "		point = point.clamp(inner.position, inner.end)
" ""
mutate waves-spawn-accepts-near                 scripts/sim/wave_defs.gd "		if (point - player).length() > SPAWN_NEAR_LIMIT:" "		if (point - player).length() < SPAWN_NEAR_LIMIT:"
mutate waves-wave-banner-seconds                scripts/sim/wave_defs.gd "const WAVE_BANNER_SECONDS: float = 2.4" "const WAVE_BANNER_SECONDS: float = 2.0"
mutate waves-cleared-banner-seconds             scripts/sim/wave_defs.gd "const CLEARED_BANNER_SECONDS: float = 2.6" "const CLEARED_BANNER_SECONDS: float = 2.0"
mutate waves-wave-banner-text                   scripts/sim/wave_defs.gd "const WAVE_BANNER_SUB: String = \"armed foes carry swords - kill them and claim one\"" "const WAVE_BANNER_SUB: String = \"armed foes carry swords\""
mutate waves-cleared-banner-text                scripts/sim/wave_defs.gd "const CLEARED_BANNER_SUB: String = \"grab dropped swords: stand on one, press 1 / 2 / 3\"" "const CLEARED_BANNER_SUB: String = \"grab dropped swords\""
mutate waves-chain-milestones                   scripts/sim/wave_defs.gd "const CHAIN_MILESTONES: Array[int] = [10, 25, 50, 100]" "const CHAIN_MILESTONES: Array[int] = [10, 25, 50, 75]"
mutate waves-normal-run-ends                    scripts/sim/wave_director.gd "		if _wave_count > 0 and wave >= _wave_count:" "		if wave >= _wave_count:"
mutate waves-complete-ignores-queue             scripts/sim/wave_director.gd "	if in_wave and queue.is_empty() and markers.is_empty() and run.enemies.is_empty():" "	if in_wave and markers.is_empty() and run.enemies.is_empty():"
mutate waves-complete-ignores-markers           scripts/sim/wave_director.gd "	if in_wave and queue.is_empty() and markers.is_empty() and run.enemies.is_empty():" "	if in_wave and queue.is_empty() and run.enemies.is_empty():"
mutate waves-complete-ignores-enemies           scripts/sim/wave_director.gd "	if in_wave and queue.is_empty() and markers.is_empty() and run.enemies.is_empty():" "	if in_wave and queue.is_empty() and markers.is_empty():"
mutate waves-break-length                       scripts/sim/wave_director.gd "const CLEARED_BREAK: float = 3.2" "const CLEARED_BREAK: float = 3.0"
mutate waves-clear-slowmo-length                scripts/sim/wave_director.gd "const CLEARED_SLOWMO: float = 0.7" "const CLEARED_SLOWMO: float = 0.5"
mutate waves-clear-slowmo-scale                 scripts/sim/wave_director.gd "const CLEARED_SLOWMO_SCALE: float = 0.3" "const CLEARED_SLOWMO_SCALE: float = 0.5"
mutate waves-clear-banner-lost                  scripts/sim/wave_director.gd "		run.set_banner(\"WAVE CLEARED\", WaveDefs.CLEARED_BANNER_SECONDS, WaveDefs.CLEARED_BANNER_SUB if _arm_waves else \"\")
" ""
mutate waves-start-banner-lost                  scripts/sim/wave_director.gd "	run.set_banner(\"WAVE %d\" % wave, WaveDefs.WAVE_BANNER_SECONDS, WaveDefs.WAVE_BANNER_SUB if _arm_waves else \"\")
" ""
mutate waves-start-banner-sub-unarmed           scripts/sim/wave_director.gd "WaveDefs.WAVE_BANNER_SUB if _arm_waves else \"\"" "WaveDefs.WAVE_BANNER_SUB"
mutate waves-clear-banner-sub-unarmed           scripts/sim/wave_director.gd "WaveDefs.CLEARED_BANNER_SUB if _arm_waves else \"\"" "WaveDefs.CLEARED_BANNER_SUB"
mutate waves-dead-keeps-spawning                scripts/sim/wave_director.gd "	if not _enabled or run.dead:" "	if not _enabled:"
mutate waves-spawn-gap-after-first              scripts/sim/wave_director.gd "			spawn_timer = WaveDefs.spawn_interval(wave)
" "			spawn_timer = WaveDefs.FIRST_SPAWN_DELAY
"
mutate waves-first-spawn-uses-gap               scripts/sim/wave_director.gd "	spawn_timer = WaveDefs.FIRST_SPAWN_DELAY
	in_wave = true" "	spawn_timer = WaveDefs.spawn_interval(wave)
	in_wave = true"
mutate waves-unlocks-ignored                    scripts/sim/wave_director.gd "WaveDefs.roll_kind(run.rng, wave) if _generated" "WaveDefs.roll_kind(run.rng, 1) if _generated"
mutate waves-arming-uses-next-wave              scripts/sim/wave_director.gd "LootDefs.roll_armed(run.rng, kind, wave, index) if _arm_waves" "LootDefs.roll_armed(run.rng, kind, wave + 1, index) if _arm_waves"
mutate waves-arming-by-wave-size                scripts/sim/wave_director.gd "LootDefs.roll_armed(run.rng, kind, wave, index) if _arm_waves" "LootDefs.roll_armed(run.rng, kind, wave, index + 2) if _arm_waves"
mutate waves-arming-off                         scripts/sim/wave_director.gd "LootDefs.roll_armed(run.rng, kind, wave, index) if _arm_waves else null" "null"
mutate waves-marker-forgets-sword               scripts/sim/wave_director.gd "SpawnMarker.make(kind, _spawn_point(run), carried)" "SpawnMarker.make(kind, _spawn_point(run), null)"
mutate waves-enemy-forgets-sword                scripts/sim/wave_director.gd "run.next_serial(), phase, cooldown, marker.armed)" "run.next_serial(), phase, cooldown, null)"
mutate waves-enemy-health-ignores-wave          scripts/sim/wave_director.gd "EnemyState.make(marker.kind, marker.position, wave, factor," "EnemyState.make(marker.kind, marker.position, 1, factor,"
mutate waves-speed-jitter-range                 scripts/sim/wave_director.gd "run.rng.randf_range(0.9, 1.12)" "run.rng.randf_range(0.9, 1.2)"
mutate waves-generated-size                     scripts/sim/wave_director.gd "var total: int = WaveDefs.enemy_count(wave) if _generated else fixed_kinds.size()" "var total: int = WaveDefs.enemy_count(1) if _generated else fixed_kinds.size()"
mutate waves-fixture-husk-count                 scripts/sim/wave_director.gd "_husk_count if _husk_count >= 0 else WaveDefs.enemy_count(wave)" "_husk_count if _husk_count >= 0 else WaveDefs.enemy_count(wave) + 1"
mutate waves-marker-telegraph                   scripts/sim/spawn_marker.gd "const TELEGRAPH: float = 0.7" "const TELEGRAPH: float = 0.6"
mutate waves-health-factor-lost                 scripts/sim/enemy_state.gd "def.hp * WaveDefs.hp_factor(wave) *" "def.hp *"
mutate waves-default-run-not-normal             scripts/sim/game_run.gd "	scenario = scenario_value if scenario_value != null else RunScenario.normal_run()" "	scenario = scenario_value if scenario_value != null else RunScenario.new()"
mutate waves-cycle-returns-fixture              scripts/sim/game_run.gd "		scenario if scenario.encounter == RunScenario.ENCOUNTER_NORMAL else RunScenario.normal_run()," "		scenario if scenario.encounter == RunScenario.ENCOUNTER_NORMAL else RunScenario.new(),"
mutate waves-chain-cue-lost                     scripts/sim/game_run.gd "	if WaveDefs.CHAIN_MILESTONES.has(combo):" "	if false:"
mutate waves-chain-cue-off-by-one               scripts/sim/game_run.gd "	if WaveDefs.CHAIN_MILESTONES.has(combo):" "	if WaveDefs.CHAIN_MILESTONES.has(combo + 1):"
mutate waves-chain-cue-amount                   scripts/sim/game_run.gd "SimCue.Kind.CHAIN_MILESTONE, position, Vector2.ZERO, combo))" "SimCue.Kind.CHAIN_MILESTONE, position, Vector2.ZERO, 0))"
mutate waves-restart-keeps-banner-line          scripts/sim/game_run.gd "	banner_sub = \"\"
	banner_left = 0.0
	camera = position" "	banner_left = 0.0
	camera = position"
mutate waves-banner-line-never-ends             scripts/sim/game_run.gd "			banner_title = \"\"
			banner_sub = \"\"
	director.update(self, dt)" "			banner_title = \"\"
	director.update(self, dt)"
mutate waves-banner-line-dropped                scripts/sim/game_run.gd "	banner_sub = sub
" "	banner_sub = \"\"
"
mutate waves-chain-readout-from-two             scripts/hud.gd "	var shown: bool = run.combo >= 3" "	var shown: bool = run.combo >= 2"
mutate waves-chain-readout-from-four            scripts/hud.gd "	var shown: bool = run.combo >= 3" "	var shown: bool = run.combo >= 4"
mutate waves-banner-line-not-shown              scripts/hud.gd "	_banner_sub_label.text = run.banner_sub if not run.dead else \"\"" "	_banner_sub_label.text = \"\""
mutate waves-banner-line-no-fade                scripts/hud.gd "	_banner_sub_label.modulate.a = _banner_label.modulate.a" "	_banner_sub_label.modulate.a = 1.0"
mutate waves-banner-line-under-title            scripts/hud.gd "const BANNER_SUB_OFFSET: float = -118.0" "const BANNER_SUB_OFFSET: float = -170.0"
mutate waves-banner-line-off-view               scripts/hud.gd "const BANNER_SUB_OFFSET: float = -118.0" "const BANNER_SUB_OFFSET: float = 400.0"
mutate waves-game-over-best-chain               scripts/hud.gd "_outcome_detail.text = \"wave %d   kills %d   best chain %d\" % [maxi(1, run.director.wave), run.kills, run.best_combo]" "_outcome_detail.text = \"wave %d   kills %d   best chain %d\" % [maxi(1, run.director.wave), run.kills, run.combo]"
mutate waves-game-over-wave                     scripts/hud.gd "_outcome_detail.text = \"wave %d   kills %d   best chain %d\" % [maxi(1, run.director.wave), run.kills, run.best_combo]" "_outcome_detail.text = \"wave %d   kills %d   best chain %d\" % [maxi(1, run.director.wave) + 1, run.kills, run.best_combo]"
mutate waves-hud-kills                          scripts/hud.gd "_wave_label.text = \"WAVE %d    kills %d\" % [maxi(1, run.director.wave), run.kills]" "_wave_label.text = \"WAVE %d    kills %d\" % [maxi(1, run.director.wave), run.best_combo]"
mutate waves-card-ignores-banner                 scripts/hud.gd "	controls.append_array([_banner_label, _banner_sub_label])
" ""
mutate waves-chain-text-lost                    scripts/presentation/effects_layer.gd "			_add_text(cue.position + Vector2(0.0, -60.0), \"%d CHAIN!\" % cue.amount, Color(1.0, 0.78, 0.35), 1.4, 56, 40.0)" "			pass"
mutate waves-chain-text-small                   scripts/presentation/effects_layer.gd "\"%d CHAIN!\" % cue.amount, Color(1.0, 0.78, 0.35), 1.4, 56, 40.0)" "\"%d CHAIN!\" % cue.amount, Color(1.0, 0.78, 0.35), 1.4, 30, 40.0)"
mutate waves-chain-text-short-lived             scripts/presentation/effects_layer.gd "\"%d CHAIN!\" % cue.amount, Color(1.0, 0.78, 0.35), 1.4, 56, 40.0)" "\"%d CHAIN!\" % cue.amount, Color(1.0, 0.78, 0.35), 0.7, 56, 40.0)"
mutate waves-chain-text-colour                  scripts/presentation/effects_layer.gd "\"%d CHAIN!\" % cue.amount, Color(1.0, 0.78, 0.35), 1.4, 56, 40.0)" "\"%d CHAIN!\" % cue.amount, Color(1.0, 1.0, 1.0), 1.4, 56, 40.0)"
mutate waves-chain-text-position                scripts/presentation/effects_layer.gd "_add_text(cue.position + Vector2(0.0, -60.0), \"%d CHAIN!\"" "_add_text(cue.position + Vector2(0.0, 60.0), \"%d CHAIN!\""
mutate waves-gong-silent                        scripts/audio/sfx_bank.gd "		SimCue.Kind.WAVE_STARTED:
			play(\"gong\")" "		SimCue.Kind.WAVE_STARTED:
			play(\"thud\")"
# --- Feedback, sound and HUD (slice #19)
mutate feedback-warden-blow-sound                 scripts/audio/sfx_bank.gd "		SwordDefs.WARDEN:
			return \"slash\"" "		SwordDefs.WARDEN:
			return \"tick\""
mutate feedback-pike-blow-sound                   scripts/audio/sfx_bank.gd "		SwordDefs.PIKE:
			return \"pierce\"" "		SwordDefs.PIKE:
			return \"slash\""
mutate feedback-colossus-blow-sound               scripts/audio/sfx_bank.gd "		SwordDefs.COLOSSUS:
			return \"boom\"" "		SwordDefs.COLOSSUS:
			return \"thud\""
mutate feedback-heavy-hit-plays-blow-sound        scripts/audio/sfx_bank.gd "if cue.spec != null and not cue.heavy:" "if cue.spec != null:"
mutate feedback-fang-dart-silent                  scripts/audio/sfx_bank.gd "			elif cue.spec != null and cue.spec.type_id == SwordDefs.FANG:
				play(\"tick\")
" ""
mutate feedback-hit-without-thud                  scripts/audio/sfx_bank.gd "				play(\"tick\")
			play(\"thud\")
		SimCue.Kind.WALL_SLAM:" "				play(\"tick\")
		SimCue.Kind.WALL_SLAM:"
mutate feedback-colossus-strike-whoosh            scripts/audio/sfx_bank.gd "return \"heave\" if type_id == SwordDefs.COLOSSUS else \"whoosh\"" "return \"whoosh\""
mutate feedback-strike-silent                     scripts/audio/sfx_bank.gd "			if cue.spec != null:
				play(strike_sound(cue.spec.type_id))" "			pass"
mutate feedback-warden-ultimate-sound             scripts/audio/sfx_bank.gd "		SwordDefs.WARDEN:
			return \"whoosh\"
		SwordDefs.PIKE, SwordDefs.COLOSSUS:" "		SwordDefs.WARDEN:
			return \"dash\"
		SwordDefs.PIKE, SwordDefs.COLOSSUS:"
mutate feedback-colossus-ultimate-sound           scripts/audio/sfx_bank.gd "SwordDefs.PIKE, SwordDefs.COLOSSUS:
			return \"heave\"" "SwordDefs.PIKE:
			return \"heave\""
mutate feedback-kill-silent                       scripts/audio/sfx_bank.gd "		SimCue.Kind.ENEMY_KILLED:
			play(\"pop\")" "		SimCue.Kind.ENEMY_KILLED:
			pass"
mutate feedback-hurt-silent                       scripts/audio/sfx_bank.gd "		SimCue.Kind.PLAYER_HURT:
			play(\"hurt\")" "		SimCue.Kind.PLAYER_HURT:
			pass"
mutate feedback-no-overlap-polyphony              scripts/audio/sfx_bank.gd "const POLYPHONY: int = 4" "const POLYPHONY: int = 1"
mutate feedback-no-retrigger-gap                  scripts/audio/sfx_bank.gd "const MIN_GAP_MS: int = 40" "const MIN_GAP_MS: int = 0"
mutate feedback-long-retrigger-gap                scripts/audio/sfx_bank.gd "const MIN_GAP_MS: int = 40" "const MIN_GAP_MS: int = 400"
mutate feedback-beat-sound-always                 scripts/audio/sfx_bank.gd "			if cue.amount > 0:
				play(\"slash\")" "			if true:
				play(\"slash\")"
mutate feedback-unlock-ignores-touch              scripts/main.gd "	if event is InputEventScreenTouch:
		return (event as InputEventScreenTouch).pressed" "	if event is InputEventScreenTouch:
		return false"
mutate feedback-unlock-on-release                 scripts/main.gd "	if event is InputEventMouseButton:
		return (event as InputEventMouseButton).pressed" "	if event is InputEventMouseButton:
		return true"
mutate feedback-unlock-ignores-keys               scripts/main.gd "		return (event as InputEventKey).pressed" "		return false"
mutate feedback-help-key-lost                     scripts/input/input_translator.gd "const HELP_KEYS: Array[Key] = [KEY_H]" "const HELP_KEYS: Array[Key] = [KEY_F1]"
mutate feedback-help-length                       scripts/sim/game_run.gd "const HELP_SECONDS: float = 14.0" "const HELP_SECONDS: float = 6.0"
mutate feedback-help-forever-ends                 scripts/sim/game_run.gd "const HELP_FOREVER: float = 9999.0" "const HELP_FOREVER: float = 5.0"
mutate feedback-help-toggles-while-paused         scripts/sim/game_run.gd "		GameCommand.Kind.TOGGLE_HELP:
			if not paused and not dead:" "		GameCommand.Kind.TOGGLE_HELP:
			if true:"
mutate feedback-help-never-ends                   scripts/sim/game_run.gd "	gameplay_time += dt
	help_left -= dt" "	gameplay_time += dt"
mutate feedback-help-restart-keeps                scripts/sim/game_run.gd "	help_left = HELP_SECONDS
	kills = 0" "	kills = 0"
mutate feedback-help-shown-dead                   scripts/hud.gd "var shown: bool = run.help_left > 0.0 and not run.dead and not gives_way" "var shown: bool = run.help_left > 0.0 and not gives_way"
mutate feedback-help-over-banner                  scripts/hud.gd "var gives_way: bool = (run.banner_left > 0.0 and run.banner_title != \"\") or run.nearest_pickup() != null" "var gives_way: bool = run.nearest_pickup() != null"
mutate feedback-help-over-card                    scripts/hud.gd "var gives_way: bool = (run.banner_left > 0.0 and run.banner_title != \"\") or run.nearest_pickup() != null" "var gives_way: bool = (run.banner_left > 0.0 and run.banner_title != \"\")"
mutate feedback-help-no-fade                      scripts/hud.gd "var alpha: float = clampf(run.help_left, 0.0, 1.0) * 0.86" "var alpha: float = 0.86"
mutate feedback-chain-small                       scripts/hud.gd "_chain_label.add_theme_font_size_override(\"font_size\", 56)" "_chain_label.add_theme_font_size_override(\"font_size\", 30)"
mutate feedback-chain-never-fades                 scripts/hud.gd "var fresh: float = clampf(run.combo_left / GameRun.COMBO_WINDOW, 0.0, 1.0)" "var fresh: float = 1.0"
mutate feedback-chain-wrong-colour                scripts/hud.gd "Color(0.35, 0.31, 0.43).lerp(Color(1.0, 0.82, 0.43), fresh)" "Color(0.35, 0.31, 0.43).lerp(Color(1.0, 0.2, 0.2), fresh)"
mutate feedback-chain-bar-grows                   scripts/hud.gd "_chain_bar.offset_right = -CHAIN_RIGHT_MARGIN - CHAIN_BAR_WIDTH * (1.0 - fresh)" "_chain_bar.offset_right = -CHAIN_RIGHT_MARGIN - CHAIN_BAR_WIDTH * fresh"
mutate feedback-chain-text-lost                   scripts/hud.gd "_chain_label.text = \"x%d\" % run.combo if shown else \"\"" "_chain_label.text = \"\""
mutate feedback-attack-bar-inverted               scripts/hud.gd "(1.0 - clampf(sword.cooldown_left / sword.cooldown, 0.0, 1.0))" "clampf(sword.cooldown_left / sword.cooldown, 0.0, 1.0)"
mutate feedback-attack-bar-sticks-full            scripts/hud.gd "(1.0 - clampf(sword.cooldown_left / sword.cooldown, 0.0, 1.0))" "1.0"
mutate feedback-dash-bar-inverted                 scripts/hud.gd "DASH_BAR_WIDTH * (1.0 - clampf(run.dash_cooldown_left / GameRun.DASH_COOLDOWN, 0.0, 1.0))" "DASH_BAR_WIDTH * clampf(run.dash_cooldown_left / GameRun.DASH_COOLDOWN, 0.0, 1.0)"
mutate feedback-banner-after-card                 scripts/hud.gd "	_banner_label.text = run.banner_title if not run.dead else \"\"
	_banner_label.modulate.a = clampf(run.banner_left, 0.0, 1.0)
	_banner_sub_label.text = run.banner_sub if not run.dead else \"\"
	_banner_sub_label.modulate.a = _banner_label.modulate.a
	_show_encounter(run)
	_show_pickup(run)
" "	_show_encounter(run)
	_show_pickup(run)
	_banner_label.text = run.banner_title if not run.dead else \"\"
	_banner_label.modulate.a = clampf(run.banner_left, 0.0, 1.0)
	_banner_sub_label.text = run.banner_sub if not run.dead else \"\"
	_banner_sub_label.modulate.a = _banner_label.modulate.a
"
mutate feedback-dash-bar-on-label                 scripts/hud.gd "const DASH_BAR_Y: float = 146.0" "const DASH_BAR_Y: float = 126.0"
mutate feedback-chain-bar-on-label                scripts/hud.gd "_chain_bar.offset_top = CHAIN_TOP + 80.0" "_chain_bar.offset_top = CHAIN_TOP + 40.0"
mutate feedback-help-under-encounter-legend       scripts/hud.gd "const HELP_TOP: float = 248.0" "const HELP_TOP: float = 120.0"
mutate feedback-hurt-flash-weak                   scripts/presentation/screen_feedback.gd "const HURT_ALPHA: float = 0.78" "const HURT_ALPHA: float = 0.2"
mutate feedback-hurt-flash-slow                   scripts/presentation/screen_feedback.gd "const FLASH_DECAY: float = 2.5" "const FLASH_DECAY: float = 0.8"
mutate feedback-hurt-flash-never-set              scripts/presentation/screen_feedback.gd "			hurt_flash = 1.0" "			hurt_flash = 0.0"
mutate feedback-no-low-health-pulse               scripts/presentation/screen_feedback.gd "const LOW_HEALTH: float = 0.3" "const LOW_HEALTH: float = 0.0"
mutate feedback-spark-count-flat                  scripts/presentation/effects_layer.gd "clampi(int(4.0 + float(cue.amount) * 0.35), 4, 26)" "4"
mutate feedback-heavy-sparks-slow                 scripts/presentation/effects_layer.gd "Vector2(250.0, 900.0) if cue.heavy else Vector2(200.0, 650.0)" "Vector2(200.0, 650.0)"
mutate feedback-hit-sparks-white                  scripts/presentation/effects_layer.gd "var tint: Color = element_color(cue.spec.element).lerp(Color.WHITE, 0.4) if cue.spec != null else" "var tint: Color = Color.WHITE if cue.spec != null else"
mutate feedback-hit-number-flat                   scripts/presentation/effects_layer.gd "var size: int = 22 if cue.amount < 12 else 32 if cue.amount < 35 else 40" "var size: int = 22"
mutate feedback-crit-number-plain                 scripts/presentation/effects_layer.gd "		size = mini(56, size + 10)" "		size = size"
mutate feedback-hit-number-still                  scripts/presentation/effects_layer.gd "90.0 + float(cue.amount), cue.direction.x * 60.0)" "90.0 + float(cue.amount), 0.0)"
mutate feedback-kill-dots-few                     scripts/presentation/effects_layer.gd "for i: int in 16 + (14 if cue.critical else 0):" "for i: int in 8 + (14 if cue.critical else 0):"
mutate feedback-kill-heavy-same                   scripts/presentation/effects_layer.gd "for i: int in 16 + (14 if cue.critical else 0):" "for i: int in 16:"
mutate feedback-kill-no-debris                    scripts/presentation/effects_layer.gd "for i: int in 6 + int(reach / 3.0):" "for i: int in 0:"
mutate feedback-debris-weightless                 scripts/presentation/effects_layer.gd "bit[\"vz\"] = float(bit[\"vz\"]) - GRAVITY * dt" "bit[\"vz\"] = float(bit[\"vz\"])"
mutate feedback-bits-uncapped                     scripts/presentation/effects_layer.gd "		alive = alive.slice(alive.size() - MAX_BITS)" "		pass"
mutate feedback-hurt-sparks-few                   scripts/presentation/effects_layer.gd "_spray(cue.position, cue.direction, 14, Color(1.0, 0.43, 0.43), Vector2(200.0, 650.0))" "_spray(cue.position, cue.direction, 4, Color(1.0, 0.43, 0.43), Vector2(200.0, 650.0))"
mutate feedback-dash-no-smoke                     scripts/presentation/effects_layer.gd "			for i: int in 10:
				_add_bit(&\"smoke\", cue.position, -cue.direction" "			for i: int in 0:
				_add_bit(&\"smoke\", cue.position, -cue.direction"
mutate feedback-spawn-no-smoke                    scripts/presentation/effects_layer.gd "_puff(cue.position, 8, 120.0, 120.0," "_puff(cue.position, 0, 120.0, 120.0,"
mutate feedback-trail-short                       scripts/presentation/effects_layer.gd "const TRAIL_POINTS: int = 9" "const TRAIL_POINTS: int = 4"
mutate feedback-trail-in-hitstop                  scripts/presentation/effects_layer.gd "	if run.hitstop > 0.0:
		return
	var live: Dictionary = {}" "	var live: Dictionary = {}"
mutate feedback-trail-speed-blind                 scripts/presentation/effects_layer.gd "clampf((sword.velocity.length() + absf(sword.fall_speed)) / 1400.0, 0.12, 1.0)" "1.0"
mutate feedback-trail-outlives-sword              scripts/presentation/effects_layer.gd "		if not live.has(key):
			_trails.erase(key)" "		if not live.has(key):
			pass"
mutate feedback-slam-no-cracks                    scripts/presentation/effects_layer.gd "			if ground != null:
				ground.add_cracks(cue.position, _rng)" "			pass"
mutate feedback-cracks-short-lived                scripts/presentation/ground_marks.gd "const LIFETIME: float = 7.0" "const LIFETIME: float = 3.0"
mutate feedback-cues-lose-sword                   scripts/sim/game_run.gd "	hit_cue.spec = sword.spec if sword != null else null
" ""
mutate feedback-hit-cue-loses-heavy               scripts/sim/game_run.gd "	hit_cue.heavy = heavy
" ""
mutate feedback-kill-never-big                    scripts/sim/game_run.gd "		kill(enemy, d, heavy or crit)" "		kill(enemy, d)"
mutate feedback-kill-cue-loses-kind               scripts/sim/game_run.gd "	killed.enemy_kind = enemy.kind
" ""
mutate feedback-ultimate-cue-loses-sword          scripts/sim/game_run.gd "	cue.origin = origin
	cue.spec = sword.spec
" "	cue.origin = origin
"
mutate feedback-strike-cue-loses-sword            scripts/sim/sword_state.gd "	strike_cue.spec = spec
" ""
mutate feedback-presenter-forgets-floor           scripts/presentation/run_presenter.gd "	_effects.ground = _ground
" ""
# --- Visual replacement (slice #21)
mutate art-pivot-sign-flipped                       scripts/presentation/sprite_art.gd "	sprite.offset = -pivot" "	sprite.offset = pivot"
mutate art-pivot-centred-instead                    scripts/presentation/sprite_art.gd "	sprite.centered = false" "	sprite.centered = true"
mutate art-sheet-frames-lost                        scripts/presentation/sprite_art.gd "	sprite.hframes = maxi(frame_count, 1)" "	sprite.hframes = 1"
mutate art-scale-ignores-the-extra-factor           scripts/presentation/sprite_art.gd "	sprite.scale = visual_scale * extra_scale" "	sprite.scale = visual_scale"
mutate art-scale-ignores-its-own-factor             scripts/presentation/sprite_art.gd "	sprite.scale = visual_scale * extra_scale" "	sprite.scale = Vector2.ONE * extra_scale"
mutate art-orientation-lost                         scripts/presentation/sprite_art.gd "	return heading + deg_to_rad(orientation_degrees)" "	return heading"
mutate art-orientation-subtracted                   scripts/presentation/sprite_art.gd "	return heading + deg_to_rad(orientation_degrees)" "	return heading - deg_to_rad(orientation_degrees)"
mutate art-frame-width-not-divided                  scripts/presentation/sprite_art.gd "Vector2(float(texture.get_width()) / float(maxi(frame_count, 1)), float(texture.get_height()))" "Vector2(float(texture.get_width()), float(texture.get_height()))"
mutate art-texture-not-assigned                     scripts/presentation/sprite_art.gd "	sprite.texture = texture
" ""
mutate clip-does-not-loop                           scripts/presentation/sprite_clip.gd "		return frames[index % frames.size()]" "		return frames[mini(index, frames.size() - 1)]"
mutate clip-ignores-its-rate                        scripts/presentation/sprite_clip.gd "	var index: int = int(floorf(maxf(seconds, 0.0) * fps))" "	var index: int = int(floorf(maxf(seconds, 0.0) * 8.0))"
mutate clip-duration-ignores-its-length             scripts/presentation/sprite_clip.gd "	return float(maxi(frames.size(), 1)) / maxf(fps, 0.001)" "	return 1.0 / maxf(fps, 0.001)"
mutate clip-looping-clip-finishes                   scripts/presentation/sprite_clip.gd "	return not loop and seconds >= duration()" "	return seconds >= duration()"
mutate clip-never-finishes                          scripts/presentation/sprite_clip.gd "	return not loop and seconds >= duration()" "	return false"
mutate clip-holds-its-first-frame                   scripts/presentation/sprite_clip.gd "	return frames[mini(index, frames.size() - 1)]" "	return frames[0]"
mutate player-restarts-the-same-clip                scripts/presentation/sprite_clip_player.gd "	if next == clip:
		return
" ""
mutate player-announces-every-tick                  scripts/presentation/sprite_clip_player.gd "		_announced = true
" "		pass
"
mutate player-clock-stands-still                    scripts/presentation/sprite_clip_player.gd "	seconds += delta
" "	pass
"
mutate sword-warden-wears-fang-art                  scripts/presentation/textured_sword_visual.gd "			return settings.warden" "			return settings.fang"
mutate sword-pike-wears-fang-art                    scripts/presentation/textured_sword_visual.gd "			return settings.pike" "			return settings.fang"
mutate sword-colossus-wears-fang-art                scripts/presentation/textured_sword_visual.gd "			return settings.colossus" "			return settings.fang"
mutate sword-fire-tint-is-ice                       scripts/presentation/textured_sword_visual.gd "			return settings.fire_tint" "			return settings.ice_tint"
mutate sword-poison-tint-is-ice                     scripts/presentation/textured_sword_visual.gd "			return settings.poison_tint" "			return settings.ice_tint"
mutate sword-rarity-size-lost                       scripts/presentation/textured_sword_visual.gd "	_rarity_size = SwordDefs.RARITY_SIZE[spec.rarity]" "	_rarity_size = 1.0"
mutate sword-glow-always-rarity-colour              scripts/presentation/textured_sword_visual.gd "	_glow_tint = SwordDefs.RARITY_COLORS[spec.rarity] if spec.rarity > 0 else _tint" "	_glow_tint = SwordDefs.RARITY_COLORS[spec.rarity]"
mutate sword-glow-always-element-colour             scripts/presentation/textured_sword_visual.gd "	_glow_tint = SwordDefs.RARITY_COLORS[spec.rarity] if spec.rarity > 0 else _tint" "	_glow_tint = _tint"
mutate sword-glow-size                              scripts/presentation/textured_sword_visual.gd "(length * 1.5 / glow_across)" "(length * 0.5 / glow_across)"
mutate sword-heading-ignored                        scripts/presentation/textured_sword_visual.gd "	_blade.rotation = _art.rotation_for(_angle)" "	_blade.rotation = deg_to_rad(_art.orientation_degrees)"
mutate sword-lift-lost                              scripts/presentation/textured_sword_visual.gd "	_blade.position = Vector2(0.0, -_lift)" "	_blade.position = Vector2.ZERO"
mutate sword-glow-not-lifted                        scripts/presentation/textured_sword_visual.gd "	_glow.position = Vector2(0.0, -_lift)" "	_glow.position = Vector2.ZERO"
mutate sword-hover-ignored                          scripts/presentation/textured_sword_visual.gd "	_lift = _hover if _resting else _altitude if _colossus else lerpf(" "	_lift = _altitude if _colossus else lerpf("
mutate sword-altitude-ignored                       scripts/presentation/textured_sword_visual.gd "else _altitude if _colossus else lerpf(" "else lerpf("
mutate sword-attack-does-not-dip                    scripts/presentation/textured_sword_visual.gd "settings.lift_attack if attacking else settings.lift_idle" "settings.lift_idle"
mutate sword-windup-plays-idle                      scripts/presentation/textured_sword_visual.gd "			return settings.windup_clip" "			return settings.idle_clip"
mutate sword-strike-plays-idle                      scripts/presentation/textured_sword_visual.gd "		SwordState.Phase.STRIKE, SwordState.Phase.STUCK:
			return settings.strike_clip" "		SwordState.Phase.STUCK:
			return settings.strike_clip"
mutate sword-stuck-plays-idle                       scripts/presentation/textured_sword_visual.gd "		SwordState.Phase.STRIKE, SwordState.Phase.STUCK:" "		SwordState.Phase.STRIKE:"
mutate sword-recover-plays-idle                     scripts/presentation/textured_sword_visual.gd "			return settings.recover_clip" "			return settings.idle_clip"
mutate sword-ultimate-plays-idle                    scripts/presentation/textured_sword_visual.gd "			return settings.ultimate_clip" "			return settings.idle_clip"
mutate sword-strike-brightness-lost                 scripts/presentation/textured_sword_visual.gd "	_blade.modulate = _tint.lerp(Color.WHITE, 0.3 if striking else 0.0)" "	_blade.modulate = _tint"
mutate sword-swap-flash-lost                        scripts/presentation/textured_sword_visual.gd "GLOW_FLASH_ALPHA * _flash" "GLOW_FLASH_ALPHA * 0.0"
mutate sword-shadow-stays-big                       scripts/presentation/textured_sword_visual.gd "lerpf(1.6, 0.8, high)" "1.6"
mutate sword-shadow-leaves-the-ground               scripts/presentation/textured_sword_visual.gd "	_shadow.position = Vector2(0.0, 6.0)" "	_shadow.position = Vector2(0.0, -20.0)"
mutate sword-frame-stuck-on-first                   scripts/presentation/textured_sword_visual.gd "	_blade.frame = _player.frame()" "	_blade.frame = 0"
mutate sword-clip-end-not-announced                 scripts/presentation/textured_sword_visual.gd "		clip_finished.emit(_player.clip)" "		pass"
mutate sword-clip-end-not-counted                   scripts/presentation/textured_sword_visual.gd "		clips_finished += 1
" "		pass
"
mutate sword-flash-ignored                          scripts/presentation/textured_sword_visual.gd "	_flash = amount" "	_flash = 0.0"
mutate sword-animation-refunds-the-cooldown         scripts/presentation/textured_sword_visual.gd "		clip_finished.emit(_player.clip)
	_layout()" "		clip_finished.emit(_player.clip)
		if get_parent() is RunPresenter:
			(get_parent().get_parent() as Main).run.swords[0].cooldown_left = 0.0
	_layout()"
mutate actor-orientation-lost                       scripts/presentation/textured_actor_visual.gd "		_body.rotation = settings.body.rotation_for(_facing.angle())" "		_body.rotation = _facing.angle()"
mutate actor-facing-ignored                         scripts/presentation/textured_actor_visual.gd "		_body.rotation = settings.body.rotation_for(_facing.angle())" "		_body.rotation = settings.body.rotation_for(0.0)"
mutate actor-moving-plays-idle                      scripts/presentation/textured_actor_visual.gd "settings.moving_clip if _moving else settings.idle_clip" "settings.idle_clip"
mutate actor-dead-plays-idle                        scripts/presentation/textured_actor_visual.gd "settings.dead_clip if _dead else settings.moving_clip" "settings.moving_clip"
mutate actor-never-blinks                           scripts/presentation/textured_actor_visual.gd "settings.invulnerable_alpha if _invulnerable and _blink % 6 < 3 else 1.0" "1.0"
mutate actor-blink-stuck-faded                      scripts/presentation/textured_actor_visual.gd "_invulnerable and _blink % 6 < 3" "_invulnerable"
mutate actor-shadow-offset-lost                     scripts/presentation/textured_actor_visual.gd "	_shadow.position = settings.shadow_offset" "	_shadow.position = Vector2.ZERO"
mutate actor-clip-end-not-announced                 scripts/presentation/textured_actor_visual.gd "		clip_finished.emit(_player.clip)" "		pass"
mutate actor-frame-stuck-on-first                   scripts/presentation/textured_actor_visual.gd "	_body.frame = _player.frame()" "	_body.frame = 0"
mutate actor-visual-heals-the-run                   scripts/presentation/textured_actor_visual.gd "	_blink += 1
" "	_blink += 1
	if get_parent() is Main and _blink == 100:
		(get_parent() as Main).run.hp += 5.0
"
mutate actor-visual-moves-the-run                   scripts/presentation/textured_actor_visual.gd "func _on_pose(facing: Vector2, moving: bool) -> void:
	_facing = facing" "func _on_pose(facing: Vector2, moving: bool) -> void:
	if get_parent() is Main and moving and (get_parent() as Main).run.tick == 200:
		(get_parent() as Main).run.position.x += 1.0
	_facing = facing"
mutate sets-default-is-textured                     scripts/presentation/visual_sets.gd "const DEFAULT: String = PLACEHOLDER" "const DEFAULT: String = TEXTURED"
mutate sets-name-case-sensitive                     scripts/presentation/visual_sets.gd "	var id: String = requested.strip_edges().to_lower()" "	var id: String = requested"
mutate sets-unknown-set-kept                        scripts/presentation/visual_sets.gd "	return id if _SCENES.has(id) else DEFAULT" "	return id if _SCENES.has(id) or not requested.is_empty() else DEFAULT"
mutate sets-actor-not-swapped                       scripts/presentation/visual_sets.gd "	main.actor_visual = load(scene_path(id, \"actor\")) as PackedScene" "	pass"
mutate sets-sword-not-swapped                       scripts/presentation/visual_sets.gd "	main.sword_visual = load(scene_path(id, \"sword\")) as PackedScene" "	pass"
mutate sets-textured-enemy-replaced                 scripts/presentation/visual_sets.gd "		\"enemy\": \"res://scenes/placeholder_enemy.tscn\",
	},
}" "		\"enemy\": \"res://tests/alt_enemy.tscn\",
	},
}"
mutate sets-textured-actor-is-drawn                 scripts/presentation/visual_sets.gd "		\"actor\": \"res://scenes/textured_actor.tscn\"," "		\"actor\": \"res://scenes/placeholder_actor.tscn\","
mutate sets-default-overrides-what-is-set           scripts/presentation/visual_sets.gd "	if id == DEFAULT:
		return
" ""
mutate launch-visuals-option-renamed                scripts/launch_options.gd "const VISUALS_ARGUMENT_PREFIX: String = \"--visuals=\"" "const VISUALS_ARGUMENT_PREFIX: String = \"--visual=\""
mutate launch-visuals-query-renamed                 scripts/launch_options.gd "const VISUALS_QUERY: String = \"visuals\"" "const VISUALS_QUERY: String = \"visual\""
mutate main-visuals-setting-ignored                 scripts/main.gd "VisualSets.apply(visuals if not visuals.is_empty() else LaunchOptions.requested_visuals(), self)" "VisualSets.apply(LaunchOptions.requested_visuals(), self)"
mutate art-fang-pivot-on-its-centre                 art/placeholder/sword_settings.tres "pivot = Vector2(12, 68)" "pivot = Vector2(12, 48)"
mutate art-fang-orientation-lost                    art/placeholder/sword_settings.tres "frame_count = 4
pivot = Vector2(12, 68)
visual_scale = Vector2(0.5, 0.5)
orientation_degrees = 90" "frame_count = 4
pivot = Vector2(12, 68)
visual_scale = Vector2(0.5, 0.5)
orientation_degrees = 0"
mutate art-windup-shows-an-idle-frame               art/placeholder/sword_settings.tres "frames = PackedInt32Array(2)" "frames = PackedInt32Array(0)"
mutate art-sword-sheets-same-size                   art/placeholder/sword_settings.tres "[ext_resource type=\"Texture2D\" path=\"res://art/placeholder/sword_warden.png\" id=\"warden_png\"]" "[ext_resource type=\"Texture2D\" path=\"res://art/placeholder/sword_fang.png\" id=\"warden_png\"]"
mutate art-ice-tint-is-fire                         scripts/presentation/sword_sprite_settings.gd "@export var ice_tint: Color = Color(0.47, 0.80, 1.0)" "@export var ice_tint: Color = Color(1.0, 0.46, 0.17)"
mutate art-attack-lift-equals-idle                  scripts/presentation/sword_sprite_settings.gd "@export var lift_attack: float = 14.0" "@export var lift_attack: float = 34.0"
mutate art-actor-orientation-lost                   art/placeholder/actor_settings.tres "orientation_degrees = -90" "orientation_degrees = 0"
mutate art-actor-pivot-on-its-centre                art/placeholder/actor_settings.tres "pivot = Vector2(32, 44)" "pivot = Vector2(32, 40)"
mutate art-actor-never-fades                        scripts/presentation/actor_sprite_settings.gd "@export_range(0.0, 1.0) var invulnerable_alpha: float = 0.45" "@export_range(0.0, 1.0) var invulnerable_alpha: float = 1.0"
# --- Touch controls (slice #20)
mutate touch-tap-window-short                        scripts/input/touch_pointers.gd "const TAP_SECONDS: float = 0.3" "const TAP_SECONDS: float = 0.1"
mutate touch-tap-window-long                         scripts/input/touch_pointers.gd "const TAP_SECONDS: float = 0.3" "const TAP_SECONDS: float = 0.9"
mutate touch-tap-travel-small                        scripts/input/touch_pointers.gd "const TAP_TRAVEL: float = 18.0" "const TAP_TRAVEL: float = 10.0"
mutate touch-tap-travel-large                        scripts/input/touch_pointers.gd "const TAP_TRAVEL: float = 18.0" "const TAP_TRAVEL: float = 30.0"
mutate touch-tap-ignores-time                        scripts/input/touch_pointers.gd " and _now() - contact.since <= TAP_SECONDS and" " and"
mutate touch-tap-ignores-travel                      scripts/input/touch_pointers.gd " and contact.travel <= TAP_TRAVEL:" ":"
mutate touch-cancel-taps                             scripts/input/touch_pointers.gd "if not cancelled and _now()" "if _now()"
mutate touch-travel-not-max                          scripts/input/touch_pointers.gd "contact.travel = maxf(contact.travel, drag.position.distance_to(contact.start))" "contact.travel = drag.position.distance_to(contact.start)"
mutate touch-ui-landing-not-consumed                 scripts/input/touch_pointers.gd "	if _is_blocked(touch.position):
		contact.owner = Owner.UI
	elif" "	if false:
		contact.owner = Owner.UI
	elif"
mutate touch-arena-landing-silent                    scripts/input/touch_pointers.gd "		contact.owner = Owner.ARENA
		commands.append(GameCommand.converge(_world(touch.position)))" "		contact.owner = Owner.ARENA"
mutate touch-arena-point-not-world                   scripts/input/touch_pointers.gd "commands.append(GameCommand.converge(_world(touch.position)))" "commands.append(GameCommand.converge(touch.position))"
mutate touch-tap-point-lost                          scripts/input/touch_pointers.gd "commands.append(GameCommand.converge(_world(contact.start)))" "commands.append(GameCommand.converge(_world(Vector2.ZERO)))"
mutate touch-stale-contact-kept                      scripts/input/touch_pointers.gd "			if _contacts.has(touch.index):
				_end(touch.index, true)
" "			if _contacts.has(touch.index):
				pass
"
mutate touch-lift-keeps-stick                        scripts/input/touch_pointers.gd "		if event != null:
			joystick.handle_event(event)
		elif" "		if event != null:
			pass
		elif"
mutate touch-release-all-keeps-contacts              scripts/input/touch_pointers.gd "	_contacts.clear()
	joystick.release()" "	joystick.release()"
mutate touch-release-all-keeps-stick                 scripts/input/touch_pointers.gd "	_contacts.clear()
	joystick.release()" "	_contacts.clear()"
mutate touch-blocked-provider-ignored                scripts/input/touch_pointers.gd "	if blocked_provider.is_valid():
		rects = blocked_provider.call()" "	if false:
		rects = blocked_provider.call()"
mutate touch-translator-bypasses-pointers            scripts/input/input_translator.gd "		commands.append_array(touch.handle_event(event))" "		joystick.handle_event(event)"
mutate touch-translator-release-all-keeps-fingers    scripts/input/input_translator.gd "	_held.clear()
	touch.release_all()" "	_held.clear()
	joystick.release()"
mutate touch-layout-swap-too-small                   scripts/input/touch_layout.gd "const SWAP_SIZE: Vector2 = Vector2(96.0, 80.0)" "const SWAP_SIZE: Vector2 = Vector2(96.0, 50.0)"
mutate touch-layout-no-lift                          scripts/input/touch_layout.gd "var lift: float = 0.0 if view.x >= WIDE_VIEW else LIFT" "var lift: float = 0.0"
mutate touch-layout-no-shove-room                    scripts/input/touch_layout.gd "const SHOVE_ROOM: float = 120.0" "const SHOVE_ROOM: float = 0.0"
mutate touch-layout-ignores-insets                   scripts/input/touch_layout.gd "	anchor.position = Vector2(minf(anchor.position.x, right - MARGIN - anchor.size.x), minf(anchor.position.y, bottom - MARGIN - anchor.size.y))
" ""
mutate touch-zone-ignores-left-inset                 scripts/input/touch_layout.gd "	var left: float = insets.x
	var right: float = view.x * JOYSTICK_WIDTH_SHARE" "	var left: float = 0.0
	var right: float = view.x * JOYSTICK_WIDTH_SHARE"
mutate touch-zone-ignores-bottom-inset               scripts/input/touch_layout.gd "	var bottom: float = view.y - insets.w
	return Rect2(left" "	var bottom: float = view.y
	return Rect2(left"
mutate touch-zone-share                              scripts/input/touch_layout.gd "const JOYSTICK_WIDTH_SHARE: float = 0.55" "const JOYSTICK_WIDTH_SHARE: float = 0.7"
mutate touch-square-window-is-portrait               scripts/input/touch_layout.gd "window_size.y > window_size.x else LANDSCAPE_BASE" "window_size.y >= window_size.x else LANDSCAPE_BASE"
mutate touch-always-landscape-base                   scripts/input/touch_layout.gd "return PORTRAIT_BASE if window_size.y > window_size.x else LANDSCAPE_BASE" "return LANDSCAPE_BASE"
mutate touch-css-insets-order                        scripts/input/touch_layout.gd "Vector4(maxf(css.w, 0.0) * scale, maxf(css.x, 0.0) * scale, maxf(css.y, 0.0) * scale, maxf(css.z, 0.0) * scale)" "Vector4(maxf(css.x, 0.0) * scale, maxf(css.y, 0.0) * scale, maxf(css.z, 0.0) * scale, maxf(css.w, 0.0) * scale)"
mutate touch-css-insets-unscaled                     scripts/input/touch_layout.gd "var scale: float = maxf(logical_per_css, 0.0)" "var scale: float = 1.0"
mutate touch-ultimate-row-reversed                   scripts/input/touch_layout.gd "var x: float = row_right - float(3 - slot) * BUTTON - float(2 - slot) * GAP" "var x: float = row_right - float(slot + 1) * BUTTON - float(slot) * GAP"
mutate touch-converge-button-point                   scripts/touch/touch_controls.gd "command_requested.emit(GameCommand.converge_at_nearest())" "command_requested.emit(GameCommand.converge(Vector2.ZERO))"
mutate touch-ultimate-button-slot                    scripts/touch/touch_controls.gd "GameCommand.ultimate_at_nearest(slot)" "GameCommand.ultimate_at_nearest(0)"
mutate touch-ultimate-button-point                   scripts/touch/touch_controls.gd "GameCommand.ultimate_at_nearest(slot)" "GameCommand.ultimate(slot, Vector2.ZERO)"
mutate touch-swap-button-slot                        scripts/touch/touch_controls.gd "command_requested.emit(GameCommand.swap(slot))" "command_requested.emit(GameCommand.swap(0))"
mutate touch-ranges-button-command                   scripts/touch/touch_controls.gd "command_requested.emit(GameCommand.toggle_ranges())" "command_requested.emit(GameCommand.dash())"
mutate touch-resume-button-pauses                    scripts/touch/touch_controls.gd "command_requested.emit(GameCommand.resume())" "command_requested.emit(GameCommand.pause())"
mutate touch-restart-button-resumes                  scripts/touch/touch_controls.gd "command_requested.emit(GameCommand.restart())" "command_requested.emit(GameCommand.resume())"
mutate touch-fullscreen-button-commands              scripts/touch/touch_controls.gd "func() -> void: fullscreen_pressed.emit(), true)" "func() -> void: command_requested.emit(GameCommand.dash()), true)"
mutate touch-hidden-buttons-block                    scripts/touch/touch_controls.gd "		if button.visible:
			rects.append(" "		if true:
			rects.append("
mutate touch-inactive-layer-blocks                   scripts/touch/touch_controls.gd "	if not _active:
		return rects
	for id" "	for id"
mutate touch-swaps-always-lit                        scripts/touch/touch_controls.gd "swap.modulate = LIT if live and pickup_near else DIM" "swap.modulate = LIT"
mutate touch-ultimates-always-lit                    scripts/touch/touch_controls.gd "ultimate.modulate = LIT if live and sword.ultimate_ready() else DIM" "ultimate.modulate = LIT"
mutate touch-converge-never-dim                      scripts/touch/touch_controls.gd "converge.modulate = LIT if live and run.converge_cooldown_left <= 0.0 else DIM" "converge.modulate = LIT"
mutate touch-ultimate-text-lost                      scripts/touch/touch_controls.gd "ultimate.text = \"%s\\n%s\" % [Hud.ULT_KEYS[slot], status]" "ultimate.text = \"%s\" % Hud.ULT_KEYS[slot]"
mutate touch-resume-never-shown                      scripts/touch/touch_controls.gd "_want(TouchLayout.RESUME, run.paused and not over)" "_want(TouchLayout.RESUME, false)"
mutate touch-restart-while-alive                     scripts/touch/touch_controls.gd "_want(TouchLayout.RESTART, restartable)" "_want(TouchLayout.RESTART, true)"
mutate touch-held-button-hides                       scripts/touch/touch_controls.gd "_buttons[id].visible = wanted or _held.get(id, false)" "_buttons[id].visible = wanted"
mutate touch-first-touch-ignored                     scripts/main.gd "	if event is InputEventScreenTouch and not touch_mode:
		set_touch_mode(true)
" ""
mutate touch-buttons-not-blocking                    scripts/main.gd "	rects.append_array(_touch.blocked_rects())
" "	pass
"
mutate touch-hud-buttons-not-blocking                scripts/main.gd "	var rects: Array[Rect2] = _hud.button_rects()
	rects.append_array" "	var rects: Array[Rect2] = []
	rects.append_array"
mutate touch-orientation-ignored                     scripts/main.gd "	if window.content_scale_size != base:
		window.content_scale_size = base" "	if false:
		window.content_scale_size = base"
mutate touch-orientation-on-desktop                  scripts/main.gd "	if not touch_mode:
		return
	var window: Window = get_window()" "	var window: Window = get_window()"
mutate touch-pickup-card-ignores-touch               scripts/main.gd "	_hud.extra_avoid_rects = _touch.blocked_rects()


func _is_user_gesture" "	pass


func _is_user_gesture"
mutate touch-commands-not-routed                     scripts/main.gd "	_touch.command_requested.connect(_submit)
" "	pass
"
mutate touch-hud-hidden-button-blocks                scripts/hud.gd "		if button.is_visible_in_tree():
			rects.append(button.get_global_rect().grow(8.0))" "		if true:
			rects.append(button.get_global_rect().grow(8.0))"
mutate touch-hud-keeps-keyboard-hint                 scripts/hud.gd "	_hint_label.visible = not on" "	_hint_label.visible = true"
mutate touch-hud-avoid-ignores-touch                 scripts/hud.gd "	for extra: Rect2 in extra_avoid_rects:
		rects.append(extra.grow(PICKUP_CARD_GAP))
" "	pass
"
mutate touch-safe-override-count                     scripts/launch_options.gd "	if parts.size() != 4:" "	if parts.size() != 5:"
mutate touch-safe-override-negative                  scripts/launch_options.gd "values.append(maxf(part.strip_edges().to_float(), 0.0))" "values.append(part.strip_edges().to_float())"

mutate touch-bridge-number-is-no                     scripts/input/touch_platform.gd "	if value is int or value is float:
		return float(value) != 0.0" "	if value is int or value is float:
		return false"
mutate touch-bridge-text-true-only                   scripts/input/touch_platform.gd "in [\"true\", \"1\", \"yes\"]" "in [\"true\"]"
mutate touch-bridge-bool-inverted                    scripts/input/touch_platform.gd "	if value is bool:
		return value
	if value is int" "	if value is bool:
		return not value
	if value is int"
mutate touch-bridge-text-drops-numbers               scripts/input/touch_platform.gd "		return str(value)" "		return \"\""
mutate touch-safe-conversion-unscaled                scripts/input/touch_platform.gd "	var per_unit: float = 1.0 if page_width <= 0.0 else view_width / page_width" "	var per_unit: float = 1.0"
mutate touch-safe-probe-count                        scripts/input/touch_platform.gd "	if parts.size() != 5:
		return values" "	if parts.size() != 4:
		return values"
mutate touch-suspend-keeps-buttons                   scripts/main.gd "func release_input_and_pause() -> void:
	_release_touch_state()" "func release_input_and_pause() -> void:
	input.release_all()"
mutate touch-cancel-keeps-buttons                    scripts/main.gd "		if input.touch.owner_of(taken) == TouchPointers.Owner.UI:
			_lift_on_buttons([taken])" "		if input.touch.owner_of(taken) == TouchPointers.Owner.UI:
			pass"
mutate touch-restart-keeps-buttons                   scripts/main.gd "		_lift_then_release_buttons.call_deferred(held)" "		pass"
mutate touch-lift-not-quiet                          scripts/main.gd "	_touch.quiet = true
" "	_touch.quiet = false
"
mutate touch-lift-wrong-finger                       scripts/main.gd "		lift.index = index
" "		lift.index = 0
"
mutate touch-ui-fingers-forgotten                    scripts/input/touch_pointers.gd "		if _contacts[index].owner == Owner.UI:" "		if false:"
mutate touch-fullscreen-on-press                     scripts/touch/touch_controls.gd "		if not on_release:
			on_action.call())" "		on_action.call())"
mutate touch-portrait-base-narrow                    scripts/input/touch_layout.gd "const PORTRAIT_BASE: Vector2i = Vector2i(740, 1280)" "const PORTRAIT_BASE: Vector2i = Vector2i(720, 1280)"
echo
echo "shard $SHARD of $SHARDS: $ran mutation(s) run, $caught caught"
if ((survived)); then echo "$survived mutation(s) survived"; fi
if ((inconclusive)); then echo "$inconclusive mutation(s) were inconclusive (crash, timeout or script error instead of a check verdict)"; fi
if ((not_applied)); then echo "$not_applied mutation(s) were NOT APPLIED (stale search text: nothing was tested)"; fi
((caught == ran && survived + inconclusive + not_applied == 0)) || exit 1
echo "all mutations were caught as behavioural rejections by the headless checks (0 inconclusive, 0 not applied)"
