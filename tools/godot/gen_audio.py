#!/usr/bin/env python3
"""Regenerates godot/audio/*.wav: the four interface sounds the port added (unlock, pause, resume,
restart) and the prototype's fourteen sounds, baked from its own synthesizer. Deterministic (every
noise stream is seeded; running it twice writes identical bytes), standard library only.

Usage: python3 -I tools/godot/gen_audio.py [output_dir]
The committed WAVs are the runtime assets (the game neither needs Python nor synthesizes anything
while playing); this file is their recipe. tools/godot/test-audio-recipe.sh proves the bytes match.
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


UI_SOUNDS = {
    "sfx_unlock": [(660, 660, 0.09, 0.5), (990, 990, 0.16, 0.5)],
    "sfx_pause": [(520, 330, 0.12, 0.5)],
    "sfx_resume": [(330, 520, 0.12, 0.5)],
    "sfx_restart": [(300, 700, 0.10, 0.45), (700, 300, 0.10, 0.35)],
}


# The prototype's fourteen sounds (game/main.py `synth` and `SOUND_DEFS`), ported line for line. The
# prototype synthesizes them at run time with Python's global random stream; the port bakes them here,
# once, with a stream of its own per sound (`seed`), so the committed WAVs are reproducible byte for byte
# and nothing at play time needs Python or any synthesis. Each file is the prototype's samples times its
# volume (the `vol` of `SOUND_DEFS`, which the prototype applies with `Sound.set_volume`), mono, 16-bit, at
# the prototype's own rate (it renders at half of a 44.1 kHz mixer: 22050 Hz).
PROTOTYPE_RATE = 22050
TAU = 2 * math.pi


def synth(sr, dur, rnd, f0=0.0, f1=0.0, fdecay=10.0, adecay=10.0, tone=1.0, wave="sin",
          noise=0.0, nlp=0.3, ndecay=20.0, click=0.0, attack=0.0, drive=1.0):
    n = int(sr * dur)
    out = [0.0] * n
    ph = 0.0
    lp = 0.0
    exp = math.exp
    sin = math.sin
    ncomp = 1 / math.sqrt(max(nlp, 0.03))
    for i in range(n):
        t = i / sr
        v = 0.0
        if tone:
            f = f1 + (f0 - f1) * exp(-t * fdecay)
            ph += TAU * f / sr
            s = sin(ph)
            if wave == "tri":
                s = 2 / math.pi * math.asin(s)
            elif wave == "sq":
                s = 0.6 if s >= 0 else -0.6
            v = tone * s * exp(-t * adecay)
        if noise:
            lp += nlp * ((rnd() * 2 - 1) - lp)
            v += noise * lp * ncomp * 0.5 * exp(-t * ndecay)
        if click:
            v += click * (rnd() * 2 - 1) * exp(-t * 160)
        if attack:
            v *= min(1.0, t / attack)
        out[i] = math.tanh(v * drive)
    fade = min(n, int(sr * 0.006))
    for i in range(fade):
        out[n - 1 - i] *= i / fade
    return out


# name: (synth parameters, volume). The order is the prototype's, and each sound's noise stream is seeded
# with its position in it.
PROTOTYPE_SOUNDS = {
    "tick": (dict(dur=0.09, f0=2600, f1=1100, fdecay=40, adecay=45, wave="tri", noise=0.7, nlp=0.6, ndecay=60), 0.35),
    "slash": (dict(dur=0.2, f0=900, f1=240, fdecay=25, adecay=20, noise=0.9, nlp=0.35, ndecay=20, drive=1.6), 0.45),
    "pierce": (dict(dur=0.24, f0=620, f1=160, fdecay=18, adecay=13, noise=0.7, nlp=0.25, ndecay=24, click=0.6, drive=1.4), 0.5),
    "boom": (dict(dur=0.95, f0=160, f1=34, fdecay=7, adecay=3.6, noise=1.3, nlp=0.06, ndecay=7, click=0.9, drive=2.4), 0.9),
    "thud": (dict(dur=0.14, f0=200, f1=60, fdecay=30, adecay=24, noise=0.5, nlp=0.15, ndecay=40, drive=1.8), 0.4),
    "whoosh": (dict(dur=0.18, tone=0, noise=1.0, nlp=0.12, ndecay=14, attack=0.05), 0.25),
    "heave": (dict(dur=0.45, f0=70, f1=150, fdecay=-1.5, adecay=2, tone=0.4, noise=0.9, nlp=0.05, ndecay=3, attack=0.3), 0.4),
    "hurt": (dict(dur=0.3, f0=240, f1=70, fdecay=10, adecay=9, wave="sq", noise=0.4, nlp=0.2, ndecay=12, drive=2.0), 0.5),
    "pop": (dict(dur=0.16, f0=900, f1=160, fdecay=30, adecay=20, noise=0.5, nlp=0.3, ndecay=30), 0.35),
    "chime": (dict(dur=0.55, f0=1320, f1=880, fdecay=25, adecay=6, wave="tri", noise=0.2, nlp=0.8, ndecay=40), 0.4),
    "dash": (dict(dur=0.2, tone=0, noise=1.0, nlp=0.25, ndecay=12, attack=0.03), 0.3),
    "gong": (dict(dur=1.3, f0=96, f1=88, fdecay=1, adecay=2.4, noise=0.3, nlp=0.04, ndecay=5, click=0.3, drive=1.4), 0.55),
    "parry": (dict(dur=0.18, f0=3200, f1=2400, fdecay=8, adecay=18, wave="tri", click=0.5), 0.3),
    "shot": (dict(dur=0.15, f0=500, f1=200, fdecay=20, adecay=18, noise=0.3, nlp=0.2, ndecay=25), 0.25),
}


def prototype_sound(index, params, volume):
    rnd = random.Random(index + 1).random
    return [v * volume for v in synth(PROTOTYPE_RATE, rnd=rnd, **params)]


def write(path, samples, rate=RATE, peak=32000):
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s)) * peak)) for s in samples))


def main():
    out_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[2] / "godot" / "audio"
    out_dir.mkdir(parents=True, exist_ok=True)
    for name, segs in UI_SOUNDS.items():
        write(out_dir / f"{name}.wav", tone(segs))
        print(f"wrote {out_dir / (name + '.wav')}")
    for index, (name, (params, volume)) in enumerate(PROTOTYPE_SOUNDS.items()):
        write(out_dir / f"sfx_{name}.wav", prototype_sound(index, params, volume), PROTOTYPE_RATE, 32767)
        print(f"wrote {out_dir / ('sfx_' + name + '.wav')}")


if __name__ == "__main__":
    main()
