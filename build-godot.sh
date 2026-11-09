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
  exit "$code"
}
trap 'die 1 "unexpected error at line $LINENO"' ERR

# shellcheck source=tools/godot/godot.lock
source "$TOOLS_SRC/godot.lock"

# ---------------------------------------------------------------- prerequisites
log "Checking base utilities"
REQUIRED_UTILS=(curl python3 sha512sum timeout sleep date grep sed cp mv rm mkdir touch find sort xargs cut tr head tail cat env)
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
[[ "$BUILD_ID" =~ ^[A-Za-z0-9._-]+$ ]] || die 18 "build id '$BUILD_ID' may only contain letters, digits, '.', '_' and '-'"
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
  rm -rf "$stage"; mkdir -p "$stage/editor"
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

mkdir -p "$WORK/home"
godot() { # isolated from any user/system Godot configuration and templates
  XDG_DATA_HOME="$WORK/home/data" XDG_CONFIG_HOME="$WORK/home/config" XDG_CACHE_HOME="$WORK/home/cache" \
    "$GODOT_BIN" "$@"
}
reported="$(godot --version 2>/dev/null | head -n1 | tr -d '\r')" || reported=""
[[ "$reported" == "$GODOT_VERSION_PREFIX".* ]] \
  || die 13 "installed Godot reports '$reported', expected '$GODOT_VERSION_PREFIX.*'"
log "Godot $reported"
[[ "$MODE" == "bootstrap" ]] && { log "Bootstrap complete"; exit 0; }

# ---------------------------------------------------------------- fresh staging
STAGE="$WORK/staging"
rm -rf "$STAGE"
mkdir -p "$STAGE/project" "$STAGE/out/windows" "$STAGE/out/web" "$STAGE/logs" "$STAGE/final"
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

run_godot() { # logname timeout code description args...
  local name="$1" limit="$2" code="$3" what="$4"; shift 4
  local logfile="$STAGE/logs/$name.log" status=0
  log "$what"
  timeout "$limit" env \
    XDG_DATA_HOME="$WORK/home/data" XDG_CONFIG_HOME="$WORK/home/config" XDG_CACHE_HOME="$WORK/home/cache" \
    "$GODOT_BIN" "$@" >"$logfile" 2>&1 || status=$?
  if ((status != 0)); then
    tail -n 25 "$logfile" >&2 || true
    die "$code" "$what failed with status $status (full log: $logfile)"
  fi
  if grep -Eq 'SCRIPT ERROR|Parse Error|Failed to load script' "$logfile"; then
    grep -E 'SCRIPT ERROR|Parse Error|Failed to load script' "$logfile" | head -n 10 >&2
    die "$code" "$what reported script errors (full log: $logfile)"
  fi
}

# ---------------------------------------------------------------- import + checks
run_godot import 300 14 "Importing assets" --headless --path "$STAGE/project" --import
run_godot checks 300 15 "Running automated headless checks" --headless --path "$STAGE/project" --script res://tests/run_checks.gd
grep -Eq '^CHECKS PASSED: [1-9][0-9]*$' "$STAGE/logs/checks.log" || die 15 "checks did not report success (missing 'CHECKS PASSED' line; log: $STAGE/logs/checks.log)"
log "$(grep -E '^CHECKS PASSED' "$STAGE/logs/checks.log")"
[[ "$MODE" == "checks" ]] && { log "Checks complete (no exports requested)"; exit 0; }

# ---------------------------------------------------------------- exports
run_godot export-windows 600 16 "Exporting Windows (release)" \
  --headless --path "$STAGE/project" --export-release Windows "$STAGE/out/windows/Swordster.exe"
run_godot export-web 600 16 "Exporting Web (release, single-thread, no extensions)" \
  --headless --path "$STAGE/project" --export-release Web "$STAGE/out/web/index.html"

need_file() { # path
  [[ -s "$1" ]] || die 17 "expected export output is missing or empty: ${1#"$STAGE"/}"
  [[ "$1" -nt "$STAGE/.started" ]] || die 17 "export output ${1#"$STAGE"/} predates this build (stale file)"
}
for f in windows/Swordster.exe windows/Swordster.pck web/index.html web/index.js web/index.wasm web/index.pck; do
  need_file "$STAGE/out/$f"
done

# Web must be single-thread without extensions: no worker script, no isolation
# requirement, and no GDExtension libraries listed.
grep -Eq '"ensureCrossOriginIsolationHeaders":false' "$STAGE/out/web/index.html" \
  || die 17 "web export does not declare ensureCrossOriginIsolationHeaders:false"
grep -Eq '"gdextensionLibs":\[\]' "$STAGE/out/web/index.html" \
  || die 17 "web export lists GDExtension libraries; extensions must stay disabled"
[[ ! -e "$STAGE/out/web/index.worker.js" ]] || die 17 "web export contains a thread worker script"
[[ ! -e "$STAGE/out/web/index.side.wasm" ]] || die 17 "web export contains a GDExtension side module"

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
for member in Swordster.exe Swordster.pck Swordster.ico READ-ME-FIRST.txt BUILD-INFO.json SHA256SUMS; do
  grep -q "$WIN_NAME/$member\$" <<<"$zip_listing" || die 17 "Windows ZIP is missing $member"
done
"${PACK[@]}" verify-manifest "$FINAL/SHA256SUMS" "$FINAL" >/dev/null || die 17 "final manifest does not verify"
"${PACK[@]}" verify-manifest "$FINAL/$WEB_NAME/SHA256SUMS" "$FINAL/$WEB_NAME" >/dev/null || die 17 "web manifest does not verify"
grep -q "\"build_id\": \"$BUILD_ID\"" "$FINAL/$WEB_NAME/BUILD-INFO.json" || die 17 "web BUILD-INFO.json build id mismatch"

# ---------------------------------------------------------------- publish to dist
mkdir -p "$DIST"
[[ ! -e "$DIST/$BUILD_ID" ]] || die 18 "$DIST/$BUILD_ID appeared during the build; refusing to overwrite it"
mv "$FINAL" "$DIST/.incoming-$BUILD_ID"
mv "$DIST/.incoming-$BUILD_ID" "$DIST/$BUILD_ID"

log "BUILD OK: $BUILD_ID"
echo "  windows: $DIST/$BUILD_ID/$WIN_NAME.zip"
echo "  web:     $DIST/$BUILD_ID/$WEB_NAME/"
echo "  manifest: $DIST/$BUILD_ID/SHA256SUMS"
