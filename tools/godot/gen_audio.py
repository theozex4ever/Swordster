#!/usr/bin/env python3
"""Regenerates godot/audio/*.wav. Deterministic, stdlib only.

Usage: python3 -I tools/godot/gen_audio.py [output_dir]
The committed WAVs are the runtime assets; this file is their recipe.
"""
import math
import struct
import sys
import wave
from pathlib import Path

RATE = 22050


def tone(segments):
    """segments: (start_hz, end_hz, seconds, volume) played back to back."""
    out = []
    phase = 0.0
    for f0, f1, dur, vol in segments:
        n = int(RATE * dur)
        for i in range(n):
            t = i / n
            freq = f0 + (f1 - f0) * t
            phase += 2 * math.pi * freq / RATE
            env = min(1.0, i / (RATE * 0.004)) * (1.0 - t) ** 1.6
            out.append(math.sin(phase) * vol * env)
    return out


SOUNDS = {
    "sfx_unlock": [(660, 660, 0.09, 0.5), (990, 990, 0.16, 0.5)],
    "sfx_pause": [(520, 330, 0.12, 0.5)],
    "sfx_resume": [(330, 520, 0.12, 0.5)],
    "sfx_restart": [(300, 700, 0.10, 0.45), (700, 300, 0.10, 0.35)],
}


def write(path, samples):
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s)) * 32000)) for s in samples))


def main():
    out_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[2] / "godot" / "audio"
    out_dir.mkdir(parents=True, exist_ok=True)
    for name, segs in SOUNDS.items():
        write(out_dir / f"{name}.wav", tone(segs))
        print(f"wrote {out_dir / (name + '.wav')}")


if __name__ == "__main__":
    main()
