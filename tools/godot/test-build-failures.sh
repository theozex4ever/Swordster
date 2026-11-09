#!/usr/bin/env bash
# Exercises representative build failures against the real build-godot.sh in
# throwaway sandbox copies. Each case must exit with its specific non-zero code
# and leave no new artifact pair behind (an older, unrelated pair must survive
# untouched). Also covers retry hygiene (a failed attempt must never leak into a
# retried step) and overlapping invocations (artifact identity must stay
# consistent). Requires the pinned Godot in the cache for the cases that run
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
case " $* " in *" --export-release Windows "*) key=win;; *" --script "*) key=checks;; *" --import "*) key=import;; esac
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

echo
if ((failures)); then echo "$failures failure case(s) misbehaved"; exit 1; fi
echo "all failure cases failed as required, and none produced or disturbed an artifact pair"
