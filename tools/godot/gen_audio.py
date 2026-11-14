#!/usr/bin/env python3
"""Regenerates godot/audio/*.wav. Deterministic, stdlib only.

Usage: python3 -I tools/godot/gen_audio.py [output_dir]
The committed WAVs are the runtime assets; this file is their recipe.
"""
import math
import random
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


def noise(dur, vol, smooth, decay, seed):
    """Low-passed noise burst. `smooth` in (0, 1]: smaller is darker."""
    rnd = random.Random(seed)
    out = []
    lp = 0.0
    for i in range(int(RATE * dur)):
        t = i / RATE
        lp += smooth * ((rnd.random() * 2 - 1) - lp)
        out.append(lp * vol * math.exp(-t * decay) * min(1.0, i / (RATE * 0.003)))
    return out


def blend(*layers):
    n = max(len(layer) for layer in layers)
    return [sum(layer[i] for layer in layers if i < len(layer)) for i in range(n)]


SOUNDS = {
    "sfx_unlock": [(660, 660, 0.09, 0.5), (990, 990, 0.16, 0.5)],
    "sfx_pause": [(520, 330, 0.12, 0.5)],
    "sfx_resume": [(330, 520, 0.12, 0.5)],
    "sfx_restart": [(300, 700, 0.10, 0.45), (700, 300, 0.10, 0.35)],
}


# Combat sounds (slice #8): synthesized stand-ins for the prototype's tick, whoosh,
# hurt, dash, pop and gong effects. Character, not waveform, parity.
COMBAT = {
    "sfx_hit": blend(tone([(1900, 700, 0.08, 0.35)]), noise(0.09, 0.9, 0.6, 55, 1)),
    "sfx_strike": noise(0.16, 0.8, 0.12, 14, 2),
    "sfx_kill": blend(tone([(900, 160, 0.16, 0.4)]), noise(0.16, 0.5, 0.3, 28, 3)),
    "sfx_hurt": blend(tone([(240, 70, 0.28, 0.5)]), noise(0.25, 0.4, 0.2, 12, 4)),
    "sfx_dash": noise(0.2, 0.7, 0.25, 12, 5),
    "sfx_wave": blend(tone([(96, 88, 0.7, 0.5)]), noise(0.5, 0.3, 0.04, 5, 6)),
    # Spitters and parries (slice #10): stand-ins for the prototype's "shot" (a short
    # falling blip with a breath of noise) and "parry" (a bright, high ring).
    "sfx_shot": blend(tone([(500, 200, 0.14, 0.35)]), noise(0.12, 0.3, 0.2, 25, 7)),
    "sfx_parry": blend(tone([(3200, 2400, 0.16, 0.3)]), noise(0.03, 0.5, 0.9, 80, 8)),
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
    for name, samples in COMBAT.items():
        write(out_dir / f"{name}.wav", samples)
        print(f"wrote {out_dir / (name + '.wav')}")


if __name__ == "__main__":
    main()
