#!/usr/bin/env bash
# Build Swordster.exe for Windows testers from Linux, using PyInstaller under Wine.
#
# One-time setup (Ubuntu): sudo apt-get install wine64 unzip
# The script installs Windows Python into its own Wine prefix on first run.
#
# Output: Swordster-Windows-Tester/ (exe + tester readme) and a matching .zip,
# both at the repository root.
set -euo pipefail

PY_VERSION=3.12.10
PYGAME_VERSION=2.5.8

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_NAME=Swordster-Windows-Tester
OUT="$ROOT/$OUT_NAME"
WORK="$ROOT/windows/.build"

export WINEPREFIX="${WINEPREFIX:-$HOME/.wine-swordster}"
export WINEDEBUG=-all

# Windows Python needs stdin redirected and output piped, or it fails to
# initialise its standard streams under Wine.
winpy() { wine 'C:\Python312\python.exe' "$@" </dev/null 2>&1 | cat; }

if [ ! -f "$WINEPREFIX/drive_c/Python312/python.exe" ]; then
    echo "Installing Windows Python $PY_VERSION into $WINEPREFIX..."
    # The NuGet package is a plain 64-bit zip; the official installer is a
    # 32-bit bootstrapper that needs wine32.
    mkdir -p "$WORK"
    curl -sSLo "$WORK/python.nupkg" "https://www.nuget.org/api/v2/package/python/$PY_VERSION"
    rm -rf "$WORK/python"
    unzip -q "$WORK/python.nupkg" -d "$WORK/python"
    wineboot -i >/dev/null 2>&1 || true
    cp -r "$WORK/python/tools" "$WINEPREFIX/drive_c/Python312"
    chmod -R u+x "$WINEPREFIX/drive_c/Python312"
    winpy -m pip install --no-warn-script-location "pygame-ce==$PYGAME_VERSION" pyinstaller
fi

mkdir -p "$WORK"

# Render the SVG icon into a PNG-compressed .ico with the usual sizes.
"$ROOT/.venv/bin/python" - "$ROOT/assets/icon.svg" "$WORK/icon.ico" <<'EOF'
import io, struct, sys
import pygame

sizes = (16, 24, 32, 48, 64, 128, 256)
images = []
for s in sizes:
    surf = pygame.image.load_sized_svg(sys.argv[1], (s, s))
    buf = io.BytesIO()
    pygame.image.save(surf, buf, "icon.png")
    images.append(buf.getvalue())

header = struct.pack("<HHH", 0, 1, len(images))
offset = len(header) + 16 * len(images)
entries = b""
for s, data in zip(sizes, images):
    dim = 0 if s == 256 else s
    entries += struct.pack("<BBBBHHII", dim, dim, 0, 0, 1, 32, len(data), offset)
    offset += len(data)
with open(sys.argv[2], "wb") as f:
    f.write(header + entries + b"".join(images))
EOF

echo "Building Swordster.exe..."
cp "$ROOT/game/main.py" "$WORK/Swordster.py"
(
    cd "$WORK"
    winpy -m PyInstaller --noconfirm --clean --onefile --windowed \
        --name Swordster --icon icon.ico \
        --distpath dist --workpath pyi-work --specpath . \
        Swordster.py | grep -E "ERROR|completed successfully" || true
)
[ -f "$WORK/dist/Swordster.exe" ] || { echo "Build failed: Swordster.exe not produced" >&2; exit 1; }

rm -rf "$OUT" "$OUT.zip"
mkdir -p "$OUT"
cp "$WORK/dist/Swordster.exe" "$OUT/"
sed 's/$/\r/' "$ROOT/windows/READ-ME-FIRST.txt" > "$OUT/READ ME FIRST.txt"
(cd "$ROOT" && zip -qr "$OUT_NAME.zip" "$OUT_NAME")

echo "Done:"
echo "  $OUT/"
echo "  $OUT.zip  (send this to testers)"
