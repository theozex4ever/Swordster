#!/usr/bin/env bash
# Exercises representative build failures against the real build-godot.sh in
# throwaway sandbox copies. Each case must exit with its specific non-zero code
# and leave no new artifact pair behind (an older, unrelated pair must survive
# untouched). Requires the pinned Godot in the cache for the cases that run
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
    "$BASH" "$sb/repo/build-godot.sh" ${BUILD_ARGS:-} >"$log" 2>&1 || status=$?
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
for u in bash curl python3 sha256sum timeout sleep date grep sed cp mv rm mkdir touch find sort xargs cut tr head tail cat env git ls mktemp; do
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

echo
if ((failures)); then echo "$failures failure case(s) misbehaved"; exit 1; fi
echo "all failure cases failed as required, and none produced or disturbed an artifact pair"
