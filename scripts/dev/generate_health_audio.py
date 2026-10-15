#!/usr/bin/env python3
"""Generate the health-system SFX as small 16-bit mono WAV files.

Run from the repo root:  python3 scripts/dev/generate_health_audio.py
Writes into assets/audio/. Kept in-repo so sounds can be regenerated/tweened
without any external asset pipeline. All sounds are synthesized from
oscillators + noise envelopes - lo-fi but clean, fitting the garden tone.
"""

import math
import random
import struct
import wave
import os

SR = 22050
OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "audio")


def write_wav(name: str, samples: list[float]) -> None:
    path = os.path.join(OUT_DIR, name)
    with wave.open(path, "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        frames = b"".join(
            struct.pack("<h", max(-32767, min(32767, int(s * 32767)))) for s in samples
        )
        w.writeframes(frames)
    print(f"wrote {path} ({len(samples) / SR:.2f}s)")


def env(i: int, n: int, attack: float = 0.01, release: float = 0.5) -> float:
    """Simple linear attack / exponential-ish release envelope."""
    t = i / SR
    total = n / SR
    if t < attack:
        return t / attack
    return math.exp(-(t - attack) / (release * total))


def sine(freq: float, t: float) -> float:
    return math.sin(2 * math.pi * freq * t)


def gen_hurt() -> None:
    """Contact hit: low woody thud + short grit. Reads as 'ouch', not gore."""
    dur = 0.25
    n = int(SR * dur)
    out = []
    random.seed(7)
    for i in range(n):
        t = i / SR
        f = 140.0 - 90.0 * (t / dur)  # pitch drops like an impact
        s = 0.85 * sine(f, t) * env(i, n, 0.002, 0.35)
        grit = random.uniform(-1, 1) * 0.25 * math.exp(-t / 0.04)
        out.append(0.8 * s + grit)
    write_wav("hurt.wav", out)


def gen_death() -> None:
    """Death: sad descending pollen-puff whoosh. Melancholy, not harsh."""
    dur = 0.9
    n = int(SR * dur)
    out = []
    random.seed(3)
    phase = 0.0
    for i in range(n):
        t = i / SR
        f = 420.0 * math.exp(-2.2 * t) + 55.0  # gliss down to a low sigh
        phase += 2 * math.pi * f / SR
        s = 0.7 * math.sin(phase) * env(i, n, 0.005, 0.8)
        shimmer = 0.18 * sine(f * 2.01, t) * math.exp(-t / 0.3)
        air = random.uniform(-1, 1) * 0.06 * math.exp(-((t - 0.1) ** 2) / 0.05)
        out.append(s + shimmer + air)
    write_wav("death.wav", out)


def gen_respawn() -> None:
    """Respawn: soft rising bloom chime - 'freshly bloomed again'."""
    dur = 0.7
    n = int(SR * dur)
    out = []
    for i in range(n):
        t = i / SR
        f = 392.0 + 196.0 * min(1.0, t / 0.35)  # G4 slides up to G5
        s = 0.45 * sine(f, t) * env(i, n, 0.01, 0.6)
        s += 0.2 * sine(f * 1.5, t) * math.exp(-t / 0.35)
        out.append(s * math.exp(-t / 0.5))
    write_wav("respawn.wav", out)


def gen_checkpoint() -> None:
    """Checkpoint bloom: warm two-note chime (D5 -> A5), like a struck flower."""
    dur = 0.8
    n = int(SR * dur)
    out = []
    for i in range(n):
        t = i / SR
        s = 0.0
        if t < 0.35:
            s += 0.4 * sine(587.33, t) * math.exp(-t / 0.16)
        if t >= 0.12:
            ts = t - 0.12
            s += 0.45 * sine(880.0, ts) * math.exp(-ts / 0.3)
        s += 0.08 * sine(1760.0, t) * math.exp(-t / 0.25)  # sparkle overtone
        out.append(s)
    write_wav("checkpoint.wav", out)


def gen_heartbeat() -> None:
    """Low-health pulse: two muffled thumps, 'dub-dub', loops at ~85 bpm."""
    dur = 0.7
    n = int(SR * dur)
    out = []

    def thump(t: float) -> float:
        if t < 0:
            return 0.0
        return 0.9 * math.sin(2 * math.pi * 58.0 * t) * math.exp(-t / 0.07)

    for i in range(n):
        t = i / SR
        out.append(0.85 * thump(t) + 0.7 * thump(t - 0.22))
    write_wav("heartbeat.wav", out)


def main() -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    gen_hurt()
    gen_death()
    gen_respawn()
    gen_checkpoint()
    gen_heartbeat()


if __name__ == "__main__":
    main()
