#!/usr/bin/env bash
# Exercises representative build failures against the real build-godot.sh in
# throwaway sandbox copies. Each case must exit with its specific non-zero code
# and leave no new artifact pair behind (an older, unrelated pair must survive
# untouched). Also covers retry hygiene (a failed attempt must never leak into a
# retried step), export completeness (every runtime file of both platforms present,
# nothing unexpected), publication into dist (leftover incoming directories,
# post-publication verification), pruning that spares live runs, overlapping
# invocations (artifact identity must stay consistent) and the mutation checker's
# treatment of crashes. Requires the pinned Godot in the cache for the cases that run
# the toolchain: ./build-godot.sh --bootstrap-only (or any earlier build).
set -Eeuo pipefail
REPO="$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd)"
# shellcheck source=tools/godot/godot.lock
source "$REPO/tools/godot/godot.lock"
REAL_CACHE="${SWORDSTER_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/swordster}"
REAL_TOOL="$REAL_CACHE/godot-$GODOT_VERSION"
[[ -x "$REAL_TOOL/editor/godot" ]] || { echo "pinned Godot missing; run ./build-godot.sh --bootstrap-only" >&2; exit 1; }
COMMIT="0123456789abcdef0123456789abcdef01234567"
ROOT="$(mktemp -d)"; trap 'rm -rf "$ROOT"' EXIT
failures=0

new_sandbox() { # name -> prints sandbox dir (repo copy with its own cache/work/dist)
  local sb="$ROOT/$1"
  # Finished cases never run again; drop their ~250 MB toolchain copies so the
  # sandboxes (often on a tmpfs) do not pile up. Logs and dist directories stay.
  find "$ROOT" -mindepth 2 -maxdepth 2 -type d -name cache -exec rm -rf {} + 2>/dev/null || true
  mkdir -p "$sb/repo/tools" "$sb/dist/20200101-000000-oldpair"
  cp "$REPO/build-godot.sh" "$sb/repo/"
  cp -a "$REPO/tools/godot" "$sb/repo/tools/godot"
  cp -a "$REPO/godot" "$sb/repo/godot"; rm -rf "$sb/repo/godot/.godot"
  echo "old successful pair" > "$sb/dist/20200101-000000-oldpair/marker"
  echo "$sb"
}
copy_cache() { # sandbox: installed toolchain only (no 1.3 GB downloads)
  mkdir -p "$1/cache"; cp -a "$REAL_TOOL" "$1/cache/"
}
regen_manifest() { # sandbox: re-record installed checksums after a deliberate edit
  (cd "$1/cache/godot-$GODOT_VERSION" && find editor -type f -print0 | sort -z | xargs -0 sha512sum > INSTALLED.sha512)
}
make_shim() { # sandbox shim-body: wrap the real binary
  local dir="$1/cache/godot-$GODOT_VERSION/editor"
  mv "$dir/godot" "$dir/godot.real"
  printf '#!/usr/bin/env bash\nREAL="%s/godot.real"\n%s\n' "$dir" "$2" > "$dir/godot"
  chmod +x "$dir/godot"; regen_manifest "$1"
}
run_case() { # name expected-exit sandbox [extra env...] -- [PATH override via PATH_OVERRIDE]
  local name="$1" want="$2" sb="$3"; shift 3
  local status=0 log="$sb/run.log"
  env -i HOME="$sb/home" PATH="${PATH_OVERRIDE:-$PATH}" \
    SWORDSTER_CACHE_DIR="${CASE_CACHE:-$sb/cache}" SWORDSTER_WORK_DIR="$sb/work" SWORDSTER_DIST_DIR="$sb/dist" \
    SWORDSTER_SOURCE_COMMIT="$COMMIT" "$@" \
    "$sb/repo/build-godot.sh" ${BUILD_ARGS:-} >"$log" 2>&1 || status=$?
  local entries; entries="$(ls -A "$sb/dist" | tr '\n' ' ')"
  local verdict="PASS"
  [[ "$status" == "$want" ]] || verdict="FAIL(exit $status, wanted $want)"
  [[ "$entries" == "20200101-000000-oldpair " ]] || verdict="FAIL(dist now holds: $entries)"
  [[ "$(cat "$sb/dist/20200101-000000-oldpair/marker")" == "old successful pair" ]] || verdict="FAIL(old pair modified)"
  printf '%-44s exit=%-3s %s\n    %s\n' "$name" "$status" "$verdict" "$(grep -m1 'FAILED' "$log" | cut -c1-170)"
  [[ "$verdict" == "PASS" ]] || { failures=$((failures + 1)); tail -n 15 "$log"; }
  unset CASE_CACHE PATH_OVERRIDE BUILD_ARGS
}

# 1. missing base utility: a PATH that has everything but sha512sum
sb="$(new_sandbox missing-utility)"; bin="$sb/bin"; mkdir -p "$bin"
for u in bash curl python3 sha256sum flock mktemp timeout sleep date grep sed cp mv rm mkdir touch find sort xargs cut tr head tail cat env git ls; do
  ln -s "$(command -v "$u")" "$bin/$u"
done
PATH_OVERRIDE="$bin" run_case "missing base utility (sha512sum)" 10 "$sb"

# 2. download failure: mirror lacks the files
sb="$(new_sandbox download-failed)"; mkdir -p "$sb/mirror"
run_case "download failure (file not on mirror)" 11 "$sb" SWORDSTER_DOWNLOAD_BASE="file://$sb/mirror"

# 3. checksum mismatch on a downloaded archive
sb="$(new_sandbox checksum-mismatch)"; mkdir -p "$sb/mirror"
head -c 4096 /dev/urandom > "$sb/mirror/$GODOT_EDITOR_FILE"; cp "$sb/mirror/$GODOT_EDITOR_FILE" "$sb/mirror/$GODOT_TEMPLATES_FILE"
run_case "download checksum mismatch" 12 "$sb" SWORDSTER_DOWNLOAD_BASE="file://$sb/mirror"
[[ ! -e "$sb/cache/downloads/$GODOT_EDITOR_FILE" ]] && echo "    (corrupt download was discarded, not cached)" || { echo "    corrupt download remained cached"; failures=$((failures + 1)); }

# 4. corrupted installed tool
sb="$(new_sandbox corrupted-tool)"; copy_cache "$sb"
printf 'x' >> "$sb/cache/godot-$GODOT_VERSION/editor/godot"
run_case "corrupted installed Godot binary" 12 "$sb"

# 5. version mismatch (checksums consistent, wrong engine version)
sb="$(new_sandbox version-mismatch)"; copy_cache "$sb"
make_shim "$sb" 'if [[ "${1:-}" == "--version" ]]; then echo "4.6.3.stable.official.deadbeef"; exit 0; fi; exec "$REAL" "$@"'
run_case "Godot reports a different version" 13 "$sb"

# 6. failed import/script errors (broken script in the project)
sb="$(new_sandbox bad-script)"; copy_cache "$sb"
printf 'class_name GameRun\nextends RefCounted\nthis is not gdscript (\n' > "$sb/repo/godot/scripts/sim/game_run.gd"
run_case "script error in the project" 14 "$sb"

# 7. failed automated check (behaviour broken)
sb="$(new_sandbox failing-check)"; copy_cache "$sb"
sed -i 's/PLAYER_SPEED: float = 285.0/PLAYER_SPEED: float = 0.0/' "$sb/repo/godot/scripts/sim/game_run.gd"
run_case "behavioural check fails (speed 0)" 15 "$sb"

# 8. failed export (unknown preset)
sb="$(new_sandbox bad-export)"; copy_cache "$sb"
sed -i '0,/^name="Windows"/s//name="Windowz"/' "$sb/repo/godot/export_presets.cfg"
run_case "export fails (preset missing)" 16 "$sb"

# 9. export "succeeds" with exit 0 but writes nothing
sb="$(new_sandbox missing-output)"; copy_cache "$sb"
make_shim "$sb" 'for a in "$@"; do if [[ "$a" == --export-release ]]; then echo "pretend export"; exit 0; fi; done; exec "$REAL" "$@"'
run_case "export exits 0 but produces no files" 17 "$sb"

# 10. web preset asking for threads: the threaded template is deliberately not installed
sb="$(new_sandbox threaded-web-preset)"; copy_cache "$sb"
sed -i 's/variant\/thread_support=false/variant\/thread_support=true/' "$sb/repo/godot/export_presets.cfg"
run_case "web preset requests threads (no such template)" 16 "$sb"

# 10b. a web export that nevertheless contains a thread worker is rejected
sb="$(new_sandbox threaded-web-output)"; copy_cache "$sb"
make_shim "$sb" '"$REAL" "$@"; rc=$?; for a in "$@"; do [[ "$a" == */web/index.html ]] && echo "// worker" > "$(dirname "$a")/index.worker.js"; done; exit $rc'
run_case "web output contains a thread worker script" 17 "$sb"

# 11. build id collision with an existing pair
sb="$(new_sandbox id-collision)"; copy_cache "$sb"
run_case "build id already exists in dist" 18 "$sb" SWORDSTER_BUILD_ID=20200101-000000-oldpair

# ---- retry hygiene: the shim distinguishes steps and attempts. It kills itself with
# SIGSEGV (like Godot's rare shutdown crash) so that build-godot.sh retries the step.
SHIM_STEPS='D="$(dirname "$0")"; key=none
case " $* " in *" --export-release Windows "*) key=win;; *" --export-release Web "*) key=web;; *" --script "*) key=checks;; *" --import "*) key=import;; esac
n=0; if [[ $key != none ]]; then n=$(( $(cat "$D/n.$key" 2>/dev/null || echo 0) + 1 )); echo $n > "$D/n.$key"; fi'

# 12. an export attempt finishes its files, prints a script error, then crashes; the
# retry exits 0 without writing anything. The first attempt's files must not be packaged.
sb="$(new_sandbox retry-script-error-export)"; copy_cache "$sb"
make_shim "$sb" "$SHIM_STEPS"'
if [[ $key == win && $n == 1 ]]; then "$REAL" "$@"; echo "SCRIPT ERROR: injected failure in the first attempt"; kill -SEGV $$; fi
if [[ $key == win ]]; then exit 0; fi
exec "$REAL" "$@"'
run_case "script error in a crashed export attempt" 16 "$sb"

# 13. same, without any error text: the retry simply produced nothing
sb="$(new_sandbox retry-no-output-export)"; copy_cache "$sb"
make_shim "$sb" "$SHIM_STEPS"'
if [[ $key == win && $n == 1 ]]; then "$REAL" "$@"; kill -SEGV $$; fi
if [[ $key == win ]]; then exit 0; fi
exec "$REAL" "$@"'
run_case "retried export exits 0 but writes no files" 17 "$sb"

# 14. a crashed checks attempt printed a script error; the retry passes cleanly
sb="$(new_sandbox retry-script-error-checks)"; copy_cache "$sb"
make_shim "$sb" "$SHIM_STEPS"'
if [[ $key == checks && $n == 1 ]]; then "$REAL" "$@"; echo "SCRIPT ERROR: injected failure in the first attempt"; kill -SEGV $$; fi
exec "$REAL" "$@"'
BUILD_ARGS=--checks-only run_case "script error in a crashed checks attempt" 15 "$sb"

# 15. a crashed import attempt printed a parse error; the retry passes cleanly
sb="$(new_sandbox retry-script-error-import)"; copy_cache "$sb"
make_shim "$sb" "$SHIM_STEPS"'
if [[ $key == import && $n == 1 ]]; then "$REAL" "$@"; echo "Parse Error: injected failure in the first attempt"; kill -SEGV $$; fi
exec "$REAL" "$@"'
BUILD_ARGS=--checks-only run_case "parse error in a crashed import attempt" 14 "$sb"

# 16. control: a crash with no errors and a good retry is still accepted
sb="$(new_sandbox retry-clean)"; copy_cache "$sb"
make_shim "$sb" "$SHIM_STEPS"'
if [[ $key == import && $n == 1 ]]; then kill -SEGV $$; fi
if [[ $key == checks && $n == 1 ]]; then "$REAL" "$@"; kill -SEGV $$; fi
exec "$REAL" "$@"'
BUILD_ARGS=--checks-only run_case "clean crash then clean retry still succeeds" 0 "$sb"
grep -q 'retrying' "$sb/run.log" && echo "    (the retries really happened)" || { echo "    retry control never retried"; failures=$((failures + 1)); }

# ---- overlapping invocations
sb_build() { # sandbox [env...]: direct invocation with the sandbox's cache/work/dist
  local sb="$1"; shift
  env -i HOME="$sb/home" PATH="$PATH" \
    SWORDSTER_CACHE_DIR="$sb/cache" SWORDSTER_WORK_DIR="$sb/work" SWORDSTER_DIST_DIR="$sb/dist" \
    SWORDSTER_SOURCE_COMMIT="$COMMIT" "$@" "$sb/repo/build-godot.sh" ${BUILD_ARGS:-}
}
pck_ids() { # zip -> prints the build id the packaged PCK itself reports at runtime
  local zip="$1" dir; dir="$(mktemp -d "$ROOT/pck.XXXXXX")"
  python3 -I -c 'import sys, zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])' "$zip" "$dir/x"
  printf 'extends SceneTree\nfunc _init() -> void:\n\tprint("PACKAGED_BUILD_ID=", BuildInfo.BUILD_ID)\n\tquit(0)\n' > "$dir/probe.gd"
  XDG_DATA_HOME="$dir/h/d" XDG_CONFIG_HOME="$dir/h/c" XDG_CACHE_HOME="$dir/h/k" \
    timeout 60 "$REAL_TOOL/editor/godot" --headless --main-pack "$dir"/x/*/Swordster.pck -s "$dir/probe.gd" 2>/dev/null \
    | sed -n 's/^PACKAGED_BUILD_ID=//p' | head -n1
}

# 17. full build A pauses before its export; a checks-only build B with the same work
# directory runs to completion; A resumes. A's ZIP, PCK and manifest must all be A's.
sb="$(new_sandbox overlapping-builds)"; copy_cache "$sb"; mkdir -p "$sb/pause"
make_shim "$sb" 'if [[ -n "${SHIM_PAUSE:-}" ]]; then for a in "$@"; do if [[ "$a" == --export-release ]]; then touch "$SHIM_PAUSE/paused"; while [[ ! -e "$SHIM_PAUSE/go" ]]; do sleep 0.2; done; break; fi; done; fi; exec "$REAL" "$@"'
sb_build "$sb" SWORDSTER_BUILD_ID=overlap-build-A SHIM_PAUSE="$sb/pause" >"$sb/a.log" 2>&1 & a_pid=$!
for _ in $(seq 150); do [[ -e "$sb/pause/paused" ]] && break; sleep 0.2; done
b_status=0; BUILD_ARGS=--checks-only sb_build "$sb" SWORDSTER_BUILD_ID=overlap-build-B >"$sb/b.log" 2>&1 || b_status=$?
touch "$sb/pause/go"; a_status=0; wait "$a_pid" || a_status=$?
verdict=PASS; detail=""
[[ -e "$sb/pause/paused" ]] || { verdict=FAIL; detail="build A never reached its export"; }
((a_status == 0 && b_status == 0)) || { verdict=FAIL; detail="$detail A exit $a_status, B exit $b_status;"; }
zip="$(ls "$sb"/dist/overlap-build-A/*.zip 2>/dev/null || true)"
if [[ -n "$zip" ]]; then
  ids="$(pck_ids "$zip")"; [[ "$ids" == "overlap-build-A" ]] || { verdict=FAIL; detail="$detail packaged PCK reports: ${ids:-nothing};"; }
else verdict=FAIL; detail="$detail build A produced no ZIP;"; fi
[[ -z "$(ls "$sb/dist" | grep -v -e overlap-build-A -e 20200101-000000-oldpair)" ]] || { verdict=FAIL; detail="$detail unexpected dist entries;"; }
printf '%-44s %s\n    A exit=%s B(checks-only) exit=%s PCK build ids=[%s] %s\n' "overlapping builds, one work dir" "$verdict" "$a_status" "$b_status" "${ids:-}" "$detail"
[[ "$verdict" == PASS ]] || { failures=$((failures + 1)); tail -n 8 "$sb/a.log"; }

# 18. two cold starts racing to bootstrap the toolchain into one empty cache. The
# second must wait for the first (not delete its half-installed files) and both succeed.
sb="$(new_sandbox overlapping-bootstrap)"; mkdir -p "$sb/cache"
mirror="file://$REAL_CACHE/downloads"; [[ -f "$REAL_CACHE/downloads/$GODOT_EDITOR_FILE" ]] || mirror=""
if [[ -z "$mirror" ]]; then
  echo "overlapping toolchain bootstrap               SKIPPED (no cached downloads to mirror)"
else
  BUILD_ARGS=--bootstrap-only sb_build "$sb" SWORDSTER_DOWNLOAD_BASE="$mirror" >"$sb/a.log" 2>&1 & a_pid=$!
  for _ in $(seq 100); do compgen -G "$sb/cache/.installing-*" >/dev/null && break; sleep 0.1; done
  sleep 1
  b_status=0; BUILD_ARGS=--bootstrap-only sb_build "$sb" SWORDSTER_DOWNLOAD_BASE="$mirror" >"$sb/b.log" 2>&1 || b_status=$?
  a_status=0; wait "$a_pid" || a_status=$?
  verdict=PASS; detail=""
  ((a_status == 0 && b_status == 0)) || { verdict=FAIL; detail="A exit $a_status, B exit $b_status;"; }
  (cd "$sb/cache/godot-$GODOT_VERSION" && sha512sum --quiet -c INSTALLED.sha512 >/dev/null 2>&1) || { verdict=FAIL; detail="$detail installed tool does not verify;"; }
  compgen -G "$sb/cache/.installing-*" >/dev/null && { verdict=FAIL; detail="$detail leftover .installing dir;"; }
  printf '%-44s %s\n    A exit=%s B exit=%s %s\n' "overlapping toolchain bootstrap" "$verdict" "$a_status" "$b_status" "$detail"
  [[ "$verdict" == PASS ]] || { failures=$((failures + 1)); tail -n 8 "$sb/a.log" "$sb/b.log"; }
fi

# ---- export completeness and per-attempt clearing of the export directories.
# 19. an export exits 0 but a required runtime companion (the AudioWorklet scripts)
# is missing: the bundle would load but have no audio.
sb="$(new_sandbox missing-worklets)"; copy_cache "$sb"
make_shim "$sb" 'if [[ " $* " == *" --export-release Web "* ]]; then "$REAL" "$@"; rc=$?; OUT="$(dirname "${@: -1}")"; rm -f "$OUT/index.audio.worklet.js" "$OUT/index.audio.position.worklet.js"; exit $rc; fi; exec "$REAL" "$@"'
run_case "web export lacks both audio worklets" 17 "$sb"

# 20. attempt 1 produced a full export, replaced the worklets with partial ones and
# crashed; attempt 2 refreshes only index.html/js/wasm/pck. The first attempt's files
# (the partial worklets above all) must not survive into the bundle.
sb="$(new_sandbox stale-worklets)"; copy_cache "$sb"
make_shim "$sb" "$SHIM_STEPS"'
OUT="$(dirname "${@: -1}")"
if [[ $key == web && $n == 1 ]]; then
  "$REAL" "$@"; for w in index.audio.worklet.js index.audio.position.worklet.js; do echo "// PARTIAL_FROM_ATTEMPT_1" > "$OUT/$w"; done; kill -SEGV $$
fi
if [[ $key == web && $n == 2 ]]; then
  tmp="$(mktemp -d)"; "$REAL" "${@:1:$#-1}" "$tmp/index.html" >/dev/null 2>&1
  for f in index.html index.js index.wasm index.pck; do cp "$tmp/$f" "$OUT/$f"; done; exit 0
fi
exec "$REAL" "$@"'
run_case "retry refreshes only part of the web bundle" 17 "$sb"

# 21. positive control for the clearing itself: attempt 1 of each export leaves
# partial and junk files and crashes; the retry must start in an EMPTY directory and
# the finished bundle must contain only the real export (no partial worklets).
sb="$(new_sandbox export-dirs-cleared)"; copy_cache "$sb"
make_shim "$sb" "$SHIM_STEPS"'
OUT="$(dirname "${@: -1}")"
if [[ $key == web || $key == win ]]; then ls -A "$OUT" > "$D/seen.$key.$n"; fi
if [[ $key == web && $n == 1 ]]; then
  "$REAL" "$@"; for w in index.audio.worklet.js index.audio.position.worklet.js; do echo "// PARTIAL_FROM_ATTEMPT_1" > "$OUT/$w"; done; echo junk > "$OUT/junk.txt"; kill -SEGV $$
fi
if [[ $key == win && $n == 1 ]]; then echo junk > "$OUT/Swordster.console.exe"; kill -SEGV $$; fi
exec "$REAL" "$@"'
status=0; sb_build "$sb" SWORDSTER_BUILD_ID=cleared-dirs >"$sb/run.log" 2>&1 || status=$?
verdict=PASS; detail=""
((status == 0)) || verdict="FAIL(exit $status)"
for k in web win; do
  [[ -f "$sb/cache/godot-$GODOT_VERSION/editor/seen.$k.2" && ! -s "$sb/cache/godot-$GODOT_VERSION/editor/seen.$k.2" ]] \
    || { verdict=FAIL; detail="$detail $k retry did not start in an empty directory;"; }
done
if grep -rq PARTIAL_FROM_ATTEMPT_1 "$sb"/dist/cleared-dirs/ 2>/dev/null; then verdict=FAIL; detail="$detail partial worklet was published;"; fi
for w in index.audio.worklet.js index.audio.position.worklet.js; do
  [[ -s "$sb/dist/cleared-dirs/Swordster-cleared-dirs-web/$w" ]] || { verdict=FAIL; detail="$detail $w missing from the bundle;"; }
done
printf '%-44s exit=%-3s %s\n    %s\n' "retried exports start from empty directories" "$status" "$verdict" "$detail"
[[ "$verdict" == PASS ]] || { failures=$((failures + 1)); tail -n 12 "$sb/run.log"; }

# ---- publication into dist.
# 22. a hidden .incoming-<id>.<pid> left by a killed run (here seeded under the old,
# predictable name using the build's real PID) must not be reused or merged into: the
# published root must be this build's and the advertised ZIP must exist.
SEED_INCOMING='
if [[ $key == win && $n == 1 ]]; then
  SP="$(sed -n "s/^PPid:[[:space:]]*//p" /proc/$PPID/status | head -n1)"   # shim <- timeout <- build-godot.sh
  L="$SHIM_DIST/.incoming-$SHIM_ID.$SP"; mkdir -p "$L/Swordster-old-web"
  echo "{\"build_id\": \"review-cold\"}" > "$L/BUILD-INFO.json"; echo old > "$L/SHA256SUMS"; echo old > "$L/Swordster-old-web/index.html"
fi'
sb="$(new_sandbox incoming-residue)"; copy_cache "$sb"
make_shim "$sb" "$SHIM_STEPS$SEED_INCOMING"'
exec "$REAL" "$@"'
status=0; sb_build "$sb" SWORDSTER_BUILD_ID=residue-build SHIM_ID=residue-build SHIM_DIST="$sb/dist" >"$sb/run.log" 2>&1 || status=$?
verdict=PASS; detail=""
((status == 0)) || verdict="FAIL(exit $status)"
pub="$sb/dist/residue-build"
grep -q '"build_id": "residue-build"' "$pub/BUILD-INFO.json" 2>/dev/null || { verdict=FAIL; detail="$detail published root metadata is not this build's;"; }
[[ -s "$pub/Swordster-residue-build-windows.zip" ]] || { verdict=FAIL; detail="$detail advertised ZIP missing;"; }
[[ -s "$pub/Swordster-residue-build-web/index.audio.worklet.js" ]] || { verdict=FAIL; detail="$detail web bundle not at the published root;"; }
[[ "$(ls -A "$pub" | tr '\n' ' ')" == "BUILD-INFO.json SHA256SUMS Swordster-residue-build-web Swordster-residue-build-windows.zip " ]] || { verdict=FAIL; detail="$detail unexpected entries in the published root: $(ls -A "$pub" | tr '\n' ' ');"; }
compgen -G "$sb/dist/.incoming-residue-build.*" >/dev/null || { verdict=FAIL; detail="$detail the seeded leftover was not left alone;"; }
printf '%-44s exit=%-3s %s\n    %s\n' "leftover incoming dir is never reused" "$status" "$verdict" "$detail"
[[ "$verdict" == PASS ]] || { failures=$((failures + 1)); tail -n 12 "$sb/run.log"; }

# 23. if a regression made the publication merge into a leftover again (emulated by
# restoring the old move logic in the sandbox copy), the post-publication check must
# refuse: non-zero exit, and no successful-looking pair at the published path.
sb="$(new_sandbox incoming-merge-detected)"; copy_cache "$sb"
python3 -I -c '
import re, sys
p = sys.argv[1]; s = open(p).read()
new = ("INCOMING=\"$DIST/.incoming-$BUILD_ID.$$\"\nmv \"$FINAL\" \"$INCOMING\"\n"
       "mv -T \"$INCOMING\" \"$DIST/$BUILD_ID\" 2>/dev/null || { rm -rf \"$INCOMING\"; die 18 \"appeared\"; }\n")
s, n = re.subn(r"# BEGIN publish-move\n.*?# END publish-move\n", lambda m: new, s, flags=re.S)
if n != 1: raise SystemExit("could not restore the old publish logic")
open(p, "w").write(s)
' "$sb/repo/build-godot.sh"
make_shim "$sb" "$SHIM_STEPS$SEED_INCOMING"'
exec "$REAL" "$@"'
status=0; sb_build "$sb" SWORDSTER_BUILD_ID=merge-build SHIM_ID=merge-build SHIM_DIST="$sb/dist" >"$sb/run.log" 2>&1 || status=$?
verdict=PASS; detail=""
((status == 17)) || verdict="FAIL(exit $status, wanted 17)"
grep -q 'post-publication check' "$sb/run.log" || { verdict=FAIL; detail="$detail no post-publication refusal;"; }
[[ ! -e "$sb/dist/merge-build" ]] || { verdict=FAIL; detail="$detail a pair was left at the published path;"; }
if grep -q 'BUILD OK' "$sb/run.log"; then verdict=FAIL; detail="$detail printed BUILD OK;"; fi
printf '%-44s exit=%-3s %s\n    %s %s\n' "merged publication is detected and removed" "$status" "$verdict" "$(grep -m1 'FAILED' "$sb/run.log" | cut -c1-170)" "$detail"
[[ "$verdict" == PASS ]] || { failures=$((failures + 1)); tail -n 12 "$sb/run.log"; }

# 24. a build id that starts with '.' could collide with hidden incoming directories.
sb="$(new_sandbox dotted-build-id)"
run_case "build id starting with '.' is refused" 18 "$sb" SWORDSTER_BUILD_ID=.incoming-x.abc123

# ---- pruning must spare live runs and remove abandoned ones.
# 25. build A pauses before its export while its staging directory is made to look nine
# days old; build B (same work dir) then runs. A must survive and finish; an abandoned
# (unlocked) nine-day-old staging directory and a two-day-old abandoned .incoming-*
# directory must be removed.
sb="$(new_sandbox aged-live-staging)"; copy_cache "$sb"; mkdir -p "$sb/pause"
make_shim "$sb" 'if [[ -n "${SHIM_PAUSE:-}" ]]; then for a in "$@"; do if [[ "$a" == --export-release ]]; then touch "$SHIM_PAUSE/paused"; while [[ ! -e "$SHIM_PAUSE/go" ]]; do sleep 0.2; done; break; fi; done; fi; exec "$REAL" "$@"'
sb_build "$sb" SWORDSTER_BUILD_ID=aged-build-A SHIM_PAUSE="$sb/pause" >"$sb/a.log" 2>&1 & a_pid=$!
for _ in $(seq 150); do [[ -e "$sb/pause/paused" ]] && break; sleep 0.2; done
live_stage="$(ls -d "$sb"/work/staging.* | head -n1)"
touch -d '9 days ago' "$live_stage"
mkdir -p "$sb/work/staging.abandoned/logs" "$sb/dist/.incoming-dead.abc123"; echo x > "$sb/work/staging.abandoned/logs/x"
touch -d '9 days ago' "$sb/work/staging.abandoned"; touch -d '2 days ago' "$sb/dist/.incoming-dead.abc123"
b_status=0; BUILD_ARGS=--checks-only sb_build "$sb" SWORDSTER_BUILD_ID=aged-build-B >"$sb/b.log" 2>&1 || b_status=$?
verdict=PASS; detail=""
[[ -d "$live_stage" ]] || { verdict=FAIL; detail="$detail the paused build's staging directory was pruned;"; }
[[ ! -e "$sb/work/staging.abandoned" ]] || { verdict=FAIL; detail="$detail abandoned staging directory was not pruned;"; }
touch "$sb/pause/go"; a_status=0; wait "$a_pid" || a_status=$?
((a_status == 0 && b_status == 0)) || { verdict=FAIL; detail="$detail A exit $a_status, B exit $b_status;"; }
[[ -s "$sb/dist/aged-build-A/Swordster-aged-build-A-windows.zip" ]] || { verdict=FAIL; detail="$detail build A produced no ZIP;"; }
[[ ! -e "$sb/dist/.incoming-dead.abc123" ]] || { verdict=FAIL; detail="$detail abandoned incoming directory was not pruned;"; }
printf '%-44s %s\n    A exit=%s B exit=%s %s\n' "aged live staging survives, abandoned goes" "$verdict" "$a_status" "$b_status" "$detail"
[[ "$verdict" == PASS ]] || { failures=$((failures + 1)); tail -n 8 "$sb/a.log" "$sb/b.log"; }

# ---- the mutation checker must not count a crash as detection.
# 26. a Godot that prints failure verdicts and then dies (signal, or an unexpected exit
# status) on every mutated project: every mutation must be INCONCLUSIVE, none caught.
for crash in 'kill -SEGV $$' 'exit 3'; do
  sb="$(new_sandbox "mutation-shim-${crash//[^a-z0-9]/}")"; copy_cache "$sb"
  make_shim "$sb" 'if [[ " $* " == *" --script "* && "$*" == *"/m-"* ]]; then echo "CHECKS FAILED: 1 of 1"; echo "  FAIL injected failure"; '"$crash"'; fi; exec "$REAL" "$@"'
  status=0
  env -i HOME="$sb/home" PATH="$PATH" SWORDSTER_CACHE_DIR="$sb/cache" "$sb/repo/tools/godot/mutation-check.sh" >"$sb/run.log" 2>&1 || status=$?
  verdict=PASS
  ((status == 1)) || verdict="FAIL(exit $status, wanted 1)"
  if grep -q '^caught ' "$sb/run.log"; then verdict="FAIL(a crash counted as caught)"; fi
  [[ "$(grep -c '^INCONCLUSIVE ' "$sb/run.log")" == 14 ]] || verdict="FAIL(not all 14 mutations inconclusive)"
  printf '%-44s exit=%-3s %s\n    %s\n' "mutation checker, print-then-'$crash'" "$status" "$verdict" "$(grep -m1 '^INCONCLUSIVE' "$sb/run.log" | cut -c1-120)"
  [[ "$verdict" == PASS ]] || { failures=$((failures + 1)); tail -n 12 "$sb/run.log"; }
done

echo
if ((failures)); then echo "$failures failure case(s) misbehaved"; exit 1; fi
echo "all failure cases failed as required, and none produced or disturbed an artifact pair"
