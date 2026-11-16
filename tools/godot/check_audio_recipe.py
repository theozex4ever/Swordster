#!/usr/bin/env python3
"""Proves godot/audio/*.wav is exactly what tools/godot/gen_audio.py produces, and that the recipe is deterministic.

Usage: python3 -I tools/godot/check_audio_recipe.py
Runs the recipe twice into scratch directories, requires the two runs to be byte-identical and
the committed files to equal them (no missing, extra or different file). Exit status 1 otherwise.
"""
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
COMMITTED = HERE.parents[1] / "godot" / "audio"


def generate(out: Path) -> dict:
    subprocess.run([sys.executable, "-I", str(HERE / "gen_audio.py"), str(out)], check=True, stdout=subprocess.DEVNULL)
    return {p.name: p.read_bytes() for p in sorted(out.glob("*.wav"))}


def main() -> int:
    with tempfile.TemporaryDirectory() as first, tempfile.TemporaryDirectory() as second:
        a = generate(Path(first))
        b = generate(Path(second))
    problems = []
    if a != b:
        problems.append("two runs of the recipe differ: " + ", ".join(sorted(k for k in a if a[k] != b.get(k))))
    committed = {p.name: p.read_bytes() for p in sorted(COMMITTED.glob("*.wav"))}
    for name in sorted(set(a) | set(committed)):
        if name not in committed:
            problems.append(f"{name} is generated but not committed")
        elif name not in a:
            problems.append(f"{name} is committed but the recipe does not generate it")
        elif a[name] != committed[name]:
            problems.append(f"{name} differs from what the recipe generates")
    if problems:
        print("audio recipe check FAILED:\n  " + "\n  ".join(problems), file=sys.stderr)
        return 1
    print(f"audio recipe check: {len(a)} WAVs, byte-identical on re-run and equal to the committed files")
    return 0


if __name__ == "__main__":
    sys.exit(main())
