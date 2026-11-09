#!/usr/bin/env bash
# One-command Linux build for the Godot port of Swordster.
#
#   ./build-godot.sh                 full build: checks, import, tests, exports, packages
#   ./build-godot.sh --checks-only   stop after the automated headless checks
#   ./build-godot.sh --bootstrap-only  only download/verify/install the pinned Godot
#
# Produces dist/<build-id>/ with the Windows ZIP, the Web bundle, BUILD-INFO.json
# and a SHA256SUMS manifest. Details and environment overrides: godot/README.md.
#
# Concurrency: every run works in its own staging directory under the work
# directory, so overlapping runs (full, --checks-only, any mix) cannot touch each
# other's files. Each run holds a kernel flock(1) on its own staging directory for
# its whole lifetime, and pruning only removes old directories whose lock it can
# take: the kernel drops a lock when its holder exits or crashes, so there are no
# stale lock files to clean up and a paused-but-live run is never pruned.
# Toolchain bootstrapping is serialized with the same kind of lock.
#
# Exit codes (stable, so CI and tests can tell failures apart):
#   0 ok   2 usage   10 missing base utility   11 download failed
#   12 checksum mismatch (download, installed tool or pin)   13 Godot version mismatch
#   14 asset import failed   15 automated checks failed   16 export failed
#   17 expected output missing/invalid   18 source commit unknown or build id already exists
set -Eeuo pipefail

REPO="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
PROJECT_SRC="$REPO/godot"
TOOLS_SRC="$REPO/tools/godot"
CACHE_ROOT="${SWORDSTER_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/swordster}"
WORK="${SWORDSTER_WORK_DIR:-$REPO/.build-godot}"
DIST="${SWORDSTER_DIST_DIR:-$REPO/dist}"
DOWNLOAD_BASE_OVERRIDE="${SWORDSTER_DOWNLOAD_BASE:-}"

MODE="full"
case "${1:-}" in
  "") ;;
  --checks-only) MODE="checks" ;;
  --bootstrap-only) MODE="bootstrap" ;;
  *) echo "usage: $0 [--checks-only|--bootstrap-only]" >&2; exit 2 ;;
esac

log() { printf '==> %s\n' "$*"; }
die() {
  local code="$1"; shift
  printf '\nbuild-godot: FAILED (exit %s): %s\n' "$code" "$*" >&2
  printf 'build-godot: no artifacts were produced; %s was not modified by this run.\n' "$DIST" >&2
  [[ -z "$STAGE" ]] || printf 'build-godot: logs and partial output kept in %s\n' "$STAGE" >&2
  exit "$code"
}
trap 'die 1 "unexpected error at line $LINENO"' ERR
# A successful run leaves nothing behind in the work directory; a failed run keeps
# its staging directory (and logs) for inspection.
STAGE=""
cleanup() { local rc=$?; if ((rc == 0)) && [[ -n "$STAGE" ]]; then rm -rf "$STAGE"; fi; }
trap cleanup EXIT

# shellcheck source=tools/godot/godot.lock
source "$TOOLS_SRC/godot.lock"

# ---------------------------------------------------------------- prerequisites
log "Checking base utilities"
REQUIRED_UTILS=(curl python3 sha512sum flock timeout sleep date grep sed cp mv rm mkdir mktemp touch find sort xargs cut tr head tail cat env)
if [[ -z "${SWORDSTER_SOURCE_COMMIT:-}" ]]; then REQUIRED_UTILS+=(git); fi
missing=()
for util in "${REQUIRED_UTILS[@]}"; do
  command -v "$util" >/dev/null 2>&1 || missing+=("$util")
done
if ((${#missing[@]})); then
  die 10 "missing required utilities: ${missing[*]} (install them with your system package manager; this script never installs packages)"
fi
python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)' || die 10 "python3 >= 3.8 is required (stdlib only)"
PACK=(python3 -I "$TOOLS_SRC/pack.py")

# ---------------------------------------------------------------- source identity
if [[ -n "${SWORDSTER_SOURCE_COMMIT:-}" ]]; then
  SOURCE_COMMIT="$SWORDSTER_SOURCE_COMMIT"; SOURCE_DIRTY="unknown"
else
  SOURCE_COMMIT="$(git -C "$REPO" rev-parse HEAD 2>/dev/null)" || die 18 "cannot determine the source commit (not a git checkout?); set SWORDSTER_SOURCE_COMMIT"
  if [[ -n "$(git -C "$REPO" status --porcelain --untracked-files=normal -- godot tools/godot build-godot.sh 2>/dev/null)" ]]; then
    SOURCE_DIRTY="true"; else SOURCE_DIRTY="false"; fi
fi
[[ "$SOURCE_COMMIT" =~ ^[0-9a-fA-F]{7,64}$ ]] || die 18 "source commit '$SOURCE_COMMIT' is not a hex commit id"
BUILT_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
BUILD_ID="${SWORDSTER_BUILD_ID:-$(date -u +%Y%m%d-%H%M%S)-${SOURCE_COMMIT:0:9}}"
[[ "$SOURCE_DIRTY" == "true" && -z "${SWORDSTER_BUILD_ID:-}" ]] && BUILD_ID="$BUILD_ID-dirty"
# A build id never starts with '.', so a published pair can never be mistaken for
# (or collide with) a hidden .incoming-* directory left behind by a killed run.
[[ "$BUILD_ID" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || die 18 "build id '$BUILD_ID' must start with a letter or digit and may only contain letters, digits, '.', '_' and '-'"
if [[ "$MODE" == "full" && -e "$DIST/$BUILD_ID" ]]; then
  die 18 "$DIST/$BUILD_ID already exists; refusing to overwrite or reuse a previous artifact pair"
fi
log "Build $BUILD_ID (commit ${SOURCE_COMMIT:0:12}, dirty=$SOURCE_DIRTY)"

# ---------------------------------------------------------------- pinned Godot
TOOL_DIR="$CACHE_ROOT/godot-$GODOT_VERSION"
DOWNLOADS="$CACHE_ROOT/downloads"
GODOT_BIN="$TOOL_DIR/editor/godot"
PIN_STAMP="$GODOT_EDITOR_SHA512 $GODOT_TEMPLATES_SHA512"
BASE_URL="${DOWNLOAD_BASE_OVERRIDE:-$GODOT_BASE_URL}"

fetch_verified() { # name sha512
  local name="$1" want="$2" dest="$DOWNLOADS/$1" got
  mkdir -p "$DOWNLOADS"
  if [[ ! -f "$dest" ]]; then
    log "Downloading $name"
    curl --fail --location --silent --show-error --retry 3 --connect-timeout 20 \
      --continue-at - --output "$dest.part" "$BASE_URL/$name" \
      || die 11 "download of $BASE_URL/$name failed (partial data kept at $dest.part for resume)"
    mv "$dest.part" "$dest.unverified"
  else
    log "Verifying cached $name"
    mv "$dest" "$dest.unverified"
  fi
  got="$(sha512sum "$dest.unverified" | cut -d' ' -f1)"
  if [[ "$got" != "$want" ]]; then
    rm -f "$dest.unverified"
    die 12 "checksum mismatch for $name: expected $want, got $got (file discarded)"
  fi
  mv "$dest.unverified" "$dest"
}

install_toolchain() {
  local stage="$CACHE_ROOT/.installing-$$"
  rm -rf "$CACHE_ROOT"/.installing-*   # leftovers from an interrupted install (we hold the bootstrap lock)
  mkdir -p "$stage/editor"
  fetch_verified "$GODOT_EDITOR_FILE" "$GODOT_EDITOR_SHA512"
  fetch_verified "$GODOT_TEMPLATES_FILE" "$GODOT_TEMPLATES_SHA512"
  log "Installing Godot $GODOT_VERSION into the cache"
  "${PACK[@]}" extract-editor "$DOWNLOADS/$GODOT_EDITOR_FILE" "$stage/editor" || die 12 "editor archive could not be extracted"
  "${PACK[@]}" extract-templates "$DOWNLOADS/$GODOT_TEMPLATES_FILE" \
    "$stage/editor/editor_data/export_templates/$GODOT_TEMPLATES_DIRNAME" || die 12 "templates archive could not be extracted"
  local tpl_version
  tpl_version="$(tr -d '\r\n' < "$stage/editor/editor_data/export_templates/$GODOT_TEMPLATES_DIRNAME/version.txt")"
  [[ "$tpl_version" == "$GODOT_TEMPLATES_DIRNAME" || "$tpl_version" == "$GODOT_TEMPLATES_DIRNAME.official" ]] \
    || die 13 "export templates report version '$tpl_version', expected '$GODOT_TEMPLATES_DIRNAME'"
  (cd "$stage" && find editor -type f -print0 | sort -z | xargs -0 sha512sum > INSTALLED.sha512)
  printf '%s\n' "$PIN_STAMP" > "$stage/INSTALLED.pin"
  rm -rf "$TOOL_DIR"
  mv "$stage" "$TOOL_DIR"
}

log "Preparing pinned Godot $GODOT_VERSION (cache: $CACHE_ROOT)"
mkdir -p "$CACHE_ROOT"
# Bootstrapping shares downloads/ and the install directory between runs, so it is
# serialized. flock locks die with their process: a crash cannot leave a stale lock.
exec 9>"$CACHE_ROOT/.bootstrap.lock"
flock -n 9 || { log "Another build is bootstrapping the toolchain; waiting"; flock 9; }
if [[ ! -f "$TOOL_DIR/INSTALLED.sha512" ]]; then
  install_toolchain
else
  [[ "$(cat "$TOOL_DIR/INSTALLED.pin" 2>/dev/null)" == "$PIN_STAMP" ]] \
    || die 12 "cached toolchain in $TOOL_DIR was installed from a different pin; remove it to reinstall"
  log "Cached toolchain found; verifying installed files"
fi
(cd "$TOOL_DIR" && sha512sum --quiet -c INSTALLED.sha512 >/dev/null 2>&1) \
  || die 12 "installed Godot files in $TOOL_DIR do not match their recorded checksums (corrupted or modified); remove that directory to reinstall"
[[ -x "$GODOT_BIN" ]] || die 12 "$GODOT_BIN is not executable"
exec 9>&-   # bootstrap done; the lock must not leak into Godot processes

# ---------------------------------------------------------------- invocation-private staging
prune_abandoned() { # parent name-glob min-age-days: remove old directories no live run holds
  # Old failed runs are kept for inspection but not forever. A directory is removed
  # only if it is older than the limit AND its flock can be taken, i.e. no running
  # build (however long it has been paused) holds it. -mtime +N means "at least N+1
  # days"; the age floor also covers the instant between a run's mktemp -d and its
  # flock.
  local parent="$1" glob="$2" days="$3" d
  for d in "$parent"/$glob; do
    [[ -d "$d" && ! -L "$d" ]] || continue
    [[ -n "$(find "$d" -maxdepth 0 -mtime "+$days" 2>/dev/null)" ]] || continue
    ( flock -n 7 && rm -rf -- "$d" ) 7<"$d" 2>/dev/null || true
  done
}
mkdir -p "$WORK"
prune_abandoned "$WORK" 'staging.*' 7
STAGE="$(mktemp -d "$WORK/staging.XXXXXX")"
exec 8<"$STAGE"   # held until this process (and anything it started) is gone
flock -n 8 || die 1 "cannot lock the new staging directory $STAGE"
godot() { # isolated from any user/system Godot configuration and templates
  XDG_DATA_HOME="$STAGE/home/data" XDG_CONFIG_HOME="$STAGE/home/config" XDG_CACHE_HOME="$STAGE/home/cache" \
    "$GODOT_BIN" "$@"
}
reported="$(godot --version 2>/dev/null | head -n1 | tr -d '\r')" || reported=""
[[ "$reported" == "$GODOT_VERSION_PREFIX".* ]] \
  || die 13 "installed Godot reports '$reported', expected '$GODOT_VERSION_PREFIX.*'"
log "Godot $reported"
[[ "$MODE" == "bootstrap" ]] && { log "Bootstrap complete"; exit 0; }

# ---------------------------------------------------------------- staging contents
mkdir -p "$STAGE/home" "$STAGE/project" "$STAGE/out/windows" "$STAGE/out/web" "$STAGE/logs" "$STAGE/final"
cp -a "$PROJECT_SRC/." "$STAGE/project/"
rm -rf "$STAGE/project/.godot"
cat > "$STAGE/project/scripts/build_info.gd" <<GD
class_name BuildInfo
extends RefCounted
## Generated by build-godot.sh in the staging copy.

const BUILD_ID: String = "$BUILD_ID"
const SOURCE_COMMIT: String = "$SOURCE_COMMIT"
GD
touch "$STAGE/.started"
sleep 0.05

# Godot's headless editor occasionally aborts or segfaults at shutdown (about 1
# in 25 runs observed with 4.7.2) even after finishing its work. Only a process
# killed by a signal (status > 128) is retried, up to 3 attempts; ordinary
# failures and timeouts are never retried. A retry must stand on its own:
#   * every attempt writes its own log (<name>.attemptN.log) and a script error
#     or failed check in ANY attempt fails the step, even in one that was killed;
#   * before every attempt the step's output directory (STEP_DIR, an export
#     directory) is emptied and recreated, and any other expected output
#     (STEP_OUTPUTS) is deleted, so whatever a failed attempt left behind cannot
#     be packaged; after the final attempt every expected output must exist, be
#     non-empty and be newer than the build start (else 17), and an export
#     directory may hold nothing but the expected outputs (else 17);
#   * the final attempt's log is copied to <name>.log for later inspection.
STEP_OUTPUTS=()
STEP_DIR=""
FAILURE_PATTERN='SCRIPT ERROR|Parse Error|Failed to load script|^CHECKS FAILED|^  FAIL '
run_godot() { # logname timeout code description args...   (expected outputs: STEP_OUTPUTS)
  local name="$1" limit="$2" code="$3" what="$4"; shift 4
  local logfile="$STAGE/logs/$name.log" attempt_log status attempt out
  log "$what"
  for attempt in 1 2 3; do
    for out in "${STEP_OUTPUTS[@]}"; do rm -rf -- "$out"; done
    # Godot does not create the export directory itself, so recreate it empty.
    if [[ -n "$STEP_DIR" ]]; then rm -rf -- "$STEP_DIR"; mkdir -p -- "$STEP_DIR"; fi
    attempt_log="$STAGE/logs/$name.attempt$attempt.log"
    status=0
    timeout "$limit" env \
      XDG_DATA_HOME="$STAGE/home/data" XDG_CONFIG_HOME="$STAGE/home/config" XDG_CACHE_HOME="$STAGE/home/cache" \
      "$GODOT_BIN" "$@" >"$attempt_log" 2>&1 || status=$?
    if grep -Eq "$FAILURE_PATTERN" "$attempt_log"; then
      grep -E "$FAILURE_PATTERN" "$attempt_log" | head -n 10 >&2
      die "$code" "$what reported errors in attempt $attempt (full log: $attempt_log)"
    fi
    ((status > 128 && attempt < 3)) || break
    echo "    attempt $attempt: Godot was killed by signal $((status - 128)); retrying" >&2
  done
  cp "$attempt_log" "$logfile"
  if ((status != 0)); then
    tail -n 25 "$logfile" >&2 || true
    die "$code" "$what failed with status $status (full log: $attempt_log)"
  fi
  for out in "${STEP_OUTPUTS[@]}"; do
    [[ -s "$out" ]] || die 17 "$what did not produce ${out#"$STAGE"/} (missing or empty after the final attempt)"
    [[ "$out" -nt "$STAGE/.started" ]] || die 17 "${out#"$STAGE"/} predates this build (stale file)"
  done
  if [[ -n "$STEP_DIR" ]]; then
    local entry known
    while IFS= read -r -d '' entry; do
      known=0; for out in "${STEP_OUTPUTS[@]}"; do [[ "$entry" == "$out" ]] && known=1; done
      ((known)) || die 17 "$what produced unexpected ${entry#"$STAGE"/} (the export must contain exactly: ${STEP_OUTPUTS[*]##*/})"
    done < <(find "$STEP_DIR" -mindepth 1 -print0)
  fi
  STEP_OUTPUTS=(); STEP_DIR=""
}

# ---------------------------------------------------------------- import + checks
STEP_OUTPUTS=("$STAGE/project/.godot/global_script_class_cache.cfg")
run_godot import 300 14 "Importing assets" --headless --path "$STAGE/project" --import
run_godot checks 300 15 "Running automated headless checks" --headless --path "$STAGE/project" --script res://tests/run_checks.gd
grep -Eq '^CHECKS PASSED: [1-9][0-9]*$' "$STAGE/logs/checks.log" || die 15 "checks did not report success (missing 'CHECKS PASSED' line; log: $STAGE/logs/checks.log)"
log "$(grep -E '^CHECKS PASSED' "$STAGE/logs/checks.log")"
[[ "$MODE" == "checks" ]] && { log "Checks complete (no exports requested)"; exit 0; }

# ---------------------------------------------------------------- exports
# The exact file sets the pinned Godot 4.7.2 exports (see tools/godot/godot.lock).
# Windows: the executable and its pack. Web (single-thread, no PWA): the page, the
# engine loader/wasm/pack named by index.html's config, the splash and the two
# icons index.html links, and the two AudioWorklet scripts the engine fetches
# beside index.js (audio.worklet.js, audio.position.worklet.js). Adding a thread
# worker, side module, manifest or service worker changes this list on purpose.
WINDOWS_EXPORT_FILES=(Swordster.exe Swordster.pck)
WEB_EXPORT_FILES=(index.html index.js index.wasm index.pck index.png index.icon.png index.apple-touch-icon.png
                  index.audio.worklet.js index.audio.position.worklet.js)
STEP_DIR="$STAGE/out/windows"; STEP_OUTPUTS=(); for f in "${WINDOWS_EXPORT_FILES[@]}"; do STEP_OUTPUTS+=("$STEP_DIR/$f"); done
run_godot export-windows 600 16 "Exporting Windows (release)" \
  --headless --path "$STAGE/project" --export-release Windows "$STAGE/out/windows/Swordster.exe"
STEP_DIR="$STAGE/out/web"; STEP_OUTPUTS=(); for f in "${WEB_EXPORT_FILES[@]}"; do STEP_OUTPUTS+=("$STEP_DIR/$f"); done
run_godot export-web 600 16 "Exporting Web (release, single-thread, no extensions)" \
  --headless --path "$STAGE/project" --export-release Web "$STAGE/out/web/index.html"

# Web must be single-thread without extensions: no isolation requirement and no
# GDExtension libraries listed.
grep -Eq '"ensureCrossOriginIsolationHeaders":false' "$STAGE/out/web/index.html" \
  || die 17 "web export does not declare ensureCrossOriginIsolationHeaders:false"
grep -Eq '"gdextensionLibs":\[\]' "$STAGE/out/web/index.html" \
  || die 17 "web export lists GDExtension libraries; extensions must stay disabled"
# (A thread worker or GDExtension side module would also be rejected as an
# unexpected file by run_godot's exact-set check above.)

# ---------------------------------------------------------------- packaging
log "Packaging"
INFO_JSON="$("${PACK[@]}" json \
  build_id="$BUILD_ID" source_commit="$SOURCE_COMMIT" source_dirty="$SOURCE_DIRTY" \
  built_at_utc="$BUILT_AT" godot_version="$GODOT_VERSION" web_threads=false web_extensions=false)"

WIN_NAME="Swordster-$BUILD_ID-windows"
WEB_NAME="Swordster-$BUILD_ID-web"
FINAL="$STAGE/final/$BUILD_ID"
mkdir -p "$FINAL/$WEB_NAME" "$STAGE/pkg/$WIN_NAME"

cp "$STAGE/out/windows/Swordster.exe" "$STAGE/out/windows/Swordster.pck" "$STAGE/pkg/$WIN_NAME/"
cp "$PROJECT_SRC/icon.ico" "$STAGE/pkg/$WIN_NAME/Swordster.ico"
sed -e "s|@BUILD_ID@|$BUILD_ID|g" -e "s|@SOURCE_COMMIT@|$SOURCE_COMMIT|g" \
  "$TOOLS_SRC/windows-READ-ME-FIRST.txt" > "$STAGE/pkg/$WIN_NAME/READ-ME-FIRST.txt"
printf '%s\n' "$INFO_JSON" > "$STAGE/pkg/$WIN_NAME/BUILD-INFO.json"
"${PACK[@]}" manifest "$STAGE/pkg/$WIN_NAME" "$STAGE/pkg/SHA256SUMS.inner"
mv "$STAGE/pkg/SHA256SUMS.inner" "$STAGE/pkg/$WIN_NAME/SHA256SUMS"
"${PACK[@]}" zip-dir "$STAGE/pkg/$WIN_NAME" "$FINAL/$WIN_NAME.zip" "$WIN_NAME"

cp -a "$STAGE/out/web/." "$FINAL/$WEB_NAME/"
printf '%s\n' "$INFO_JSON" > "$FINAL/$WEB_NAME/BUILD-INFO.json"
"${PACK[@]}" manifest "$FINAL/$WEB_NAME" "$STAGE/pkg/web.sums"
mv "$STAGE/pkg/web.sums" "$FINAL/$WEB_NAME/SHA256SUMS"

printf '%s\n' "$INFO_JSON" > "$FINAL/BUILD-INFO.json"
"${PACK[@]}" manifest "$FINAL" "$STAGE/pkg/outer.sums"
mv "$STAGE/pkg/outer.sums" "$FINAL/SHA256SUMS"

# ---------------------------------------------------------------- validate the pair
log "Validating the artifact pair"
zip_listing="$("${PACK[@]}" list-zip "$FINAL/$WIN_NAME.zip")"
for member in "${WINDOWS_EXPORT_FILES[@]}" Swordster.ico READ-ME-FIRST.txt BUILD-INFO.json SHA256SUMS; do
  grep -q "$WIN_NAME/$member\$" <<<"$zip_listing" || die 17 "Windows ZIP is missing $member"
done
"${PACK[@]}" verify-manifest "$FINAL/SHA256SUMS" "$FINAL" >/dev/null || die 17 "final manifest does not verify"
"${PACK[@]}" verify-manifest "$FINAL/$WEB_NAME/SHA256SUMS" "$FINAL/$WEB_NAME" >/dev/null || die 17 "web manifest does not verify"
grep -q "\"build_id\": \"$BUILD_ID\"" "$FINAL/$WEB_NAME/BUILD-INFO.json" || die 17 "web BUILD-INFO.json build id mismatch"

# ---------------------------------------------------------------- publish to dist
mkdir -p "$DIST"
[[ ! -e "$DIST/$BUILD_ID" ]] || die 18 "$DIST/$BUILD_ID appeared during the build; refusing to overwrite it"
# Hidden .incoming-* directories only ever exist for the instant of a publication
# (published pairs never start with '.'); one left by a killed run is removed here
# once it is a day old and no live run holds it. It is never reused: every
# publication reserves its own fresh, empty directory.
prune_abandoned "$DIST" '.incoming-*' 0
# BEGIN publish-move
INCOMING="$(mktemp -d "$DIST/.incoming-$BUILD_ID.XXXXXX")"   # unique and empty: nothing can be merged into it
exec 7<"$INCOMING"; flock -n 7 || true
mv -T "$FINAL" "$INCOMING/pair" || { rm -rf "$INCOMING"; die 17 "could not move the finished pair into $DIST"; }
# rename(2) onto an existing non-empty directory fails, so a concurrent run that
# published the same id first is never merged into or overwritten.
mv -T "$INCOMING/pair" "$DIST/$BUILD_ID" 2>/dev/null || { rm -rf "$INCOMING"; die 18 "$DIST/$BUILD_ID appeared during the build; refusing to overwrite it"; }
rmdir "$INCOMING" 2>/dev/null || true
exec 7<&-
# END publish-move

# Re-check what is actually at the published location. This is the check that
# counts: it looks at the published root itself, not at the staging copy.
verify_published() { # prints a reason and fails if the published pair is not exactly ours
  local pub="$DIST/$BUILD_ID" entries want f listing member
  entries="$(ls -A "$pub" | sort | tr '\n' ' ')"
  want="$(printf '%s\n' BUILD-INFO.json SHA256SUMS "$WEB_NAME" "$WIN_NAME.zip" | sort | tr '\n' ' ')"
  [[ "$entries" == "$want" ]] || { echo "published root holds [${entries% }], expected [${want% }]"; return 1; }
  grep -q "\"build_id\": \"$BUILD_ID\"" "$pub/BUILD-INFO.json" 2>/dev/null || { echo "published BUILD-INFO.json is not for $BUILD_ID"; return 1; }
  grep -q "\"build_id\": \"$BUILD_ID\"" "$pub/$WEB_NAME/BUILD-INFO.json" 2>/dev/null || { echo "published web BUILD-INFO.json is not for $BUILD_ID"; return 1; }
  [[ -s "$pub/$WIN_NAME.zip" ]] || { echo "advertised $WIN_NAME.zip is missing or empty"; return 1; }
  listing="$("${PACK[@]}" list-zip "$pub/$WIN_NAME.zip" 2>/dev/null)" || { echo "published ZIP is unreadable"; return 1; }
  for member in "${WINDOWS_EXPORT_FILES[@]}" Swordster.ico READ-ME-FIRST.txt BUILD-INFO.json SHA256SUMS; do
    grep -q "$WIN_NAME/$member\$" <<<"$listing" || { echo "published ZIP is missing $member"; return 1; }
  done
  for f in "${WEB_EXPORT_FILES[@]}" BUILD-INFO.json SHA256SUMS; do
    [[ -s "$pub/$WEB_NAME/$f" ]] || { echo "advertised web file $WEB_NAME/$f is missing or empty"; return 1; }
  done
  "${PACK[@]}" verify-manifest "$pub/SHA256SUMS" "$pub" >/dev/null || { echo "published SHA256SUMS does not verify"; return 1; }
  "${PACK[@]}" verify-manifest "$pub/$WEB_NAME/SHA256SUMS" "$pub/$WEB_NAME" >/dev/null || { echo "published web SHA256SUMS does not verify"; return 1; }
}
if ! problem="$(verify_published)"; then
  rm -rf -- "$DIST/$BUILD_ID"   # ours: we just created it by an atomic rename of a path that did not exist
  die 17 "published pair failed its post-publication check ($problem); the published directory was removed"
fi

log "BUILD OK: $BUILD_ID"
echo "  windows: $DIST/$BUILD_ID/$WIN_NAME.zip"
echo "  web:     $DIST/$BUILD_ID/$WEB_NAME/"
echo "  manifest: $DIST/$BUILD_ID/SHA256SUMS"
