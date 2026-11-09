#!/usr/bin/env python3
"""Archive helpers for build-godot.sh (stdlib only, so no zip/unzip needed).

  pack.py extract-editor ARCHIVE DEST            extract the editor binary
  pack.py extract-templates ARCHIVE DEST         extract only the windows/web templates
  pack.py zip-dir SRC OUT_ZIP TOP               stable-order zip with SRC under TOP/
  pack.py list-zip ZIP                          list members
  pack.py json KEY=VALUE ...                    JSON object (true/false become booleans)
  pack.py manifest DIR OUT                       write sha256sum-style manifest
  pack.py verify-manifest MANIFEST ROOT          verify a manifest
"""
import hashlib
import json
import os
import stat
import sys
import zipfile
from pathlib import Path

WANTED_TEMPLATES = (
    "templates/version.txt",
    "templates/windows_release_x86_64.exe",
    "templates/web_nothreads_release.zip",
)
FIXED_TIME = (2020, 1, 1, 0, 0, 0)


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def safe_member(dest: Path, name: str) -> Path:
    target = (dest / name).resolve()
    if dest.resolve() not in target.parents and target != dest.resolve():
        raise SystemExit(f"refusing unsafe archive member: {name}")
    return target


def extract_editor(archive: Path, dest: Path) -> None:
    with zipfile.ZipFile(archive) as z:
        names = [n for n in z.namelist() if not n.endswith("/")]
        binaries = [n for n in names if n.endswith("_linux.x86_64")]
        if len(binaries) != 1:
            raise SystemExit(f"editor archive has {len(binaries)} linux binaries, expected 1")
        dest.mkdir(parents=True, exist_ok=True)
        out = dest / "godot"
        with z.open(binaries[0]) as src, open(out, "wb") as dst:
            while chunk := src.read(1 << 20):
                dst.write(chunk)
        out.chmod(out.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
        # Self-contained mode: editor settings and templates live next to the binary.
        (dest / "._sc_").write_text("")


def extract_templates(archive: Path, dest: Path) -> None:
    with zipfile.ZipFile(archive) as z:
        have = set(z.namelist())
        missing = [n for n in WANTED_TEMPLATES if n not in have]
        if missing:
            raise SystemExit("templates archive is missing: " + ", ".join(missing))
        dest.mkdir(parents=True, exist_ok=True)
        for name in WANTED_TEMPLATES:
            out = dest / Path(name).name
            with z.open(name) as src, open(out, "wb") as dst:
                while chunk := src.read(1 << 20):
                    dst.write(chunk)


def write_manifest(root: Path, out: Path, exclude=()) -> None:
    lines = []
    for path in sorted(p for p in root.rglob("*") if p.is_file()):
        rel = path.relative_to(root).as_posix()
        if rel in exclude or path == out:
            continue
        lines.append(f"{sha256(path)}  {rel}")
    out.write_text("\n".join(lines) + "\n")


def verify_manifest(manifest: Path, root: Path) -> int:
    bad = 0
    listed = set()
    for line in manifest.read_text().splitlines():
        digest, _, rel = line.partition("  ")
        listed.add(rel)
        target = root / rel
        if not target.is_file():
            print(f"MISSING  {rel}")
            bad += 1
        elif sha256(target) != digest:
            print(f"MISMATCH {rel}")
            bad += 1
    for path in root.rglob("*"):
        rel = path.relative_to(root).as_posix()
        if path.is_file() and rel not in listed and path != manifest:
            print(f"UNLISTED {rel}")
            bad += 1
    print(f"{len(listed)} files listed, {bad} problems")
    return 1 if bad else 0


def zip_dir(src: Path, out_zip: Path, top: str) -> None:
    """Zip `src` as `top/...` with stable ordering and timestamps."""
    with zipfile.ZipFile(out_zip, "w", zipfile.ZIP_DEFLATED) as z:
        for path in sorted(p for p in src.rglob("*") if p.is_file()):
            info = zipfile.ZipInfo(f"{top}/{path.relative_to(src).as_posix()}", FIXED_TIME)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = (0o755 if path.suffix == ".exe" else 0o644) << 16
            z.writestr(info, path.read_bytes())


def main(argv) -> int:
    cmd = argv[1] if len(argv) > 1 else ""
    if cmd == "extract-editor":
        extract_editor(Path(argv[2]), Path(argv[3]))
    elif cmd == "extract-templates":
        extract_templates(Path(argv[2]), Path(argv[3]))
    elif cmd == "manifest":
        write_manifest(Path(argv[2]), Path(argv[3]))
    elif cmd == "verify-manifest":
        return verify_manifest(Path(argv[2]), Path(argv[3]))
    elif cmd == "zip-dir":
        zip_dir(Path(argv[2]), Path(argv[3]), argv[4])
    elif cmd == "list-zip":
        with zipfile.ZipFile(argv[2]) as z:
            for i in z.infolist():
                print(f"{i.file_size:>10}  {i.filename}")
    elif cmd == "json":
        pairs = dict(a.split("=", 1) for a in argv[2:])
        typed = {k: {"true": True, "false": False}.get(v, v) for k, v in pairs.items()}
        print(json.dumps(typed, indent=2, sort_keys=True))
    else:
        print(__doc__)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
