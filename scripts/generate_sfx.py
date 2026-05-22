#!/usr/bin/env python3
"""Generate three SFX as WAV files using only Python stdlib.

  - pop.wav    — iMessage-style chirp for the bubble appearing  (~80ms)
  - whoosh.wav — short noise sweep for the hook→title transition (~250ms)
  - ding.wav   — bright chime for the $40 reveal                  (~600ms)

These are mixed under the VO + BGM in build.sh at specific timestamps.
"""

import math
import os
import struct
import wave

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.join(HERE, '..', 'marketing', 'sfx')
os.makedirs(OUT_DIR, exist_ok=True)

SR = 44100  # sample rate


def write_wav(path, samples, sr=SR):
    """Write mono 16-bit PCM WAV."""
    with wave.open(path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        max_s = max(1e-9, max(abs(s) for s in samples))
        # Normalize to ~0.9 to leave a touch of headroom
        gain = 0.9 / max_s
        frames = b''.join(
            struct.pack('<h', int(max(-32768, min(32767, s * gain * 32767))))
            for s in samples
        )
        w.writeframes(frames)
    print(f"  wrote {path}  ({len(samples)/sr:.3f}s)")


def adsr(n, attack=0.005, decay=0.1, sustain=0.6, release=0.2, sr=SR):
    """Simple ADSR envelope, length n samples."""
    a = int(attack * sr); d = int(decay * sr); r = int(release * sr)
    s_len = max(0, n - a - d - r)
    env = []
    for i in range(a):
        env.append(i / max(1, a))
    for i in range(d):
        env.append(1.0 + (sustain - 1.0) * i / max(1, d))
    for _ in range(s_len):
        env.append(sustain)
    for i in range(r):
        env.append(sustain * (1 - i / max(1, r)))
    return env[:n]


def sine(freq, n, sr=SR):
    return [math.sin(2 * math.pi * freq * i / sr) for i in range(n)]


# ── 1) iMessage pop — short ascending chirp, two tones ──────────────────────

def make_pop():
    dur = 0.10
    n = int(dur * SR)
    # Frequency sweeps from 480→900 Hz (the classic Apple "send" chirp shape)
    samples = []
    for i in range(n):
        t = i / SR
        # Exponential pitch rise
        f = 480 * (900 / 480) ** (t / dur)
        s = math.sin(2 * math.pi * f * t)
        # Quick exponential decay
        env = math.exp(-t * 18)
        samples.append(s * env * 0.7)
    write_wav(os.path.join(OUT_DIR, 'pop.wav'), samples)


# ── 2) Whoosh — bandpass-shifted noise burst ────────────────────────────────

def make_whoosh():
    dur = 0.30
    n = int(dur * SR)
    # Pink-ish noise (simple low-passed white)
    import random
    rnd = random.Random(42)
    raw = [rnd.uniform(-1, 1) for _ in range(n)]
    # Simple lowpass for warmth
    a = 0.6
    filt = [raw[0]]
    for i in range(1, n):
        filt.append(a * filt[i-1] + (1-a) * raw[i])
    # Envelope: fast attack, exponential tail, sweep in volume
    samples = []
    for i in range(n):
        t = i / SR
        # Envelope shape: bell-curve, peaks at ~30% through
        peak = 0.30 * dur
        env = math.exp(-((t - peak) ** 2) / (0.02))
        samples.append(filt[i] * env * 0.55)
    write_wav(os.path.join(OUT_DIR, 'whoosh.wav'), samples)


# ── 3) Ding — bright two-partial chime, slow decay ──────────────────────────

def make_ding():
    dur = 0.7
    n = int(dur * SR)
    f1 = 1320   # E6
    f2 = 1980   # B6 (perfect fifth)
    samples = []
    for i in range(n):
        t = i / SR
        s = (math.sin(2 * math.pi * f1 * t) +
             0.6 * math.sin(2 * math.pi * f2 * t))
        # Sharp attack, exponential decay
        env = math.exp(-t * 4.5)
        if t < 0.005:
            env *= t / 0.005
        samples.append(s * env * 0.45)
    write_wav(os.path.join(OUT_DIR, 'ding.wav'), samples)


# ── 4) Cha-ching — two-tone coin clink for "+$X earned" stamps ──────────────

def make_chaching():
    """Quick ka-ching: low tone → high tone, metallic resonance."""
    dur = 0.45
    n = int(dur * SR)
    samples = []
    # Two coin "hits" — first at t=0 (low), second at t=0.08 (high)
    hit_times = [(0.000, 660),   # low coin
                 (0.080, 990)]   # high coin

    for i in range(n):
        t = i / SR
        s = 0.0
        for ht, f in hit_times:
            if t >= ht:
                local = t - ht
                # Two overlapping partials per hit for "metallic" timbre
                tone = (math.sin(2 * math.pi * f * local) +
                        0.5 * math.sin(2 * math.pi * f * 1.8 * local) +
                        0.3 * math.sin(2 * math.pi * f * 2.6 * local))
                env = math.exp(-local * 8)
                if local < 0.003:
                    env *= local / 0.003   # avoid click
                s += tone * env * 0.4
        samples.append(s)
    write_wav(os.path.join(OUT_DIR, 'chaching.wav'), samples)


if __name__ == '__main__':
    make_pop()
    make_whoosh()
    make_ding()
    make_chaching()
    print(f"\nDone. SFX in {OUT_DIR}/")
