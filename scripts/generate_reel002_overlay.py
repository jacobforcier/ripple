#!/usr/bin/env python3
"""
Reel 002 — overlay layer for the Veo water hero shot (v2: editorial cut).

The water has a slow, meditative rhythm — three real splashes at ~2.0s, 5.0s,
7.5s (measured from the clip's brightness, not guessed). This overlay matches
that calm instead of fighting it:
  - lowercase, letter-spaced type, NO boxes — text rests in the dark band with
    a soft shadow, fades in slowly with a subtle drift
  - exactly three text moments, each synced to a splash
  - one elegant total that counts up smoothly (no HUD pill)
  - a settled end card: total → "word of mouth, finally rewarded." → ripple

Composited over marketing/raw/veo_water.mp4 by build_reel002.sh.
"""

import math
import os
import struct
import wave
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "marketing", "output", "reel002_overlay")
CHORD = os.path.join(ROOT, "marketing", "output", "reel002_endchord.wav")
INTER = os.path.join(ROOT, "scripts", "fonts", "Inter-wght.ttf")

W, H = 1080, 1920
FPS = 30
DUR = 12.0
N = int(DUR * FPS)
END = 8.2

WHITE = (238, 242, 252)
MINT  = (150, 235, 190)
ACCENT = (120, 165, 255)

_fc = {}
def F(size, weight="Medium"):
    if (size, weight) not in _fc:
        f = ImageFont.truetype(INTER, size); f.set_variation_by_name(weight)
        _fc[(size, weight)] = f
    return _fc[(size, weight)]

def clamp01(x): return max(0.0, min(1.0, x))
def ease_out(x): return 1 - (1 - x) ** 3
def smooth(x): x = clamp01(x); return x * x * (3 - 2 * x)

# ── premium text: lowercase, letter-spaced, soft shadow, no box ──────────────
def tracked_w(d, text, font, tr):
    return sum(d.textlength(c, font=font) for c in text) + tr * (len(text) - 1)

def draw_line(img, text, font, cx, y, color, alpha, tr=3, shadow=0.55):
    if alpha <= 1: return
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    x = cx - tracked_w(d, text, font, tr) / 2
    for c in text:
        d.text((x, y), c, font=font, fill=(*color, 255))
        x += d.textlength(c, font=font) + tr
    if alpha < 255:
        layer.putalpha(layer.getchannel("A").point(lambda v: int(v * alpha / 255)))
    if shadow > 0:
        sh = Image.new("RGBA", img.size, (0, 0, 0, 0))
        sh.paste((0, 0, 0, 255), (0, 0), layer.getchannel("A"))
        sh = sh.filter(ImageFilter.GaussianBlur(9))
        sh.putalpha(sh.getchannel("A").point(lambda v: int(v * shadow)))
        img.alpha_composite(sh)
    img.alpha_composite(layer)

def fade_drift(t, t0, t1, fin=0.75, fout=0.6):
    """Returns (alpha 0-255, y-offset). Slow fade-in with upward drift."""
    if t < t0 or t > t1: return 0, 0
    ain = clamp01((t - t0) / fin)
    aout = 1 - clamp01((t - (t1 - fout)) / fout)
    alpha = 255 * ease_out(ain) * aout
    yoff = (1 - ease_out(ain)) * 14 - clamp01((t - (t1 - fout)) / fout) * 8
    return alpha, yoff

# ── the cut: three lines, synced to splashes at ~2.0 / 5.0 / 7.5 ─────────────
LINES = [
    ("you're the one they ask.",        0.5, 2.9, 430),
    ("a drop for every friend.",         3.6, 6.1, 430),
]
TOTAL = 11.80
CT0, CT1 = 2.0, 7.8           # counter climb window

def counter_val(t):
    return TOTAL * smooth((t - CT0) / (CT1 - CT0))

# settle scrim — smooth vertical gradient, darkest through the text band
def build_scrim():
    g = Image.new("L", (1, H))
    px = g.load()
    for y in range(H):
        c = 1 - abs(0.5 - y / H) * 2
        px[0, y] = int(150 + 95 * c)
    g = g.resize((W, H))
    scrim = Image.new("RGBA", (W, H), (6, 9, 20, 0))
    scrim.putalpha(g)
    return scrim
SCRIM = build_scrim()

def glow_line(img, text, font, cx, y, color, alpha, tr=4):
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    x = cx - tracked_w(d, text, font, tr) / 2
    for c in text:
        d.text((x, y), c, font=font, fill=(*color, 255))
        x += d.textlength(c, font=font) + tr
    if alpha < 255:
        layer.putalpha(layer.getchannel("A").point(lambda v: int(v * alpha / 255)))
    img.alpha_composite(layer.filter(ImageFilter.GaussianBlur(28)))
    img.alpha_composite(layer.filter(ImageFilter.GaussianBlur(9)))
    img.alpha_composite(layer)

def render():
    os.makedirs(OUT, exist_ok=True)
    fnar = F(54, "Medium")
    fcount = F(40, "Medium")
    for fi in range(N):
        t = fi / FPS
        img = Image.new("RGBA", (W, H), (0, 0, 0, 0))

        if t < END:
            for text, t0, t1, y in LINES:
                a, yo = fade_drift(t, t0, t1)
                draw_line(img, text, fnar, W/2, y + yo, WHITE, a, tr=3)
            # smooth-counting total, top-center, no box
            ca = 255 * clamp01((t - CT0) / 0.4) * (1 - clamp01((t - 7.9) / 0.2))
            if ca > 1:
                draw_line(img, f"${counter_val(t):.2f}", fcount, W/2, 150,
                          MINT, ca, tr=2, shadow=0.5)
        else:
            sa = ease_out(clamp01((t - END) / 0.7))
            img.alpha_composite(SCRIM.point(lambda v: 0) if False else _scaled(SCRIM, sa))
            p = clamp01((t - (END + 0.1)) / 0.6)
            glow_line(img, f"${TOTAL:.2f}", F(132, "SemiBold"), W/2, 660,
                      MINT, int(255 * ease_out(p)), tr=2)
            a2 = 255 * ease_out(clamp01((t - (END + 0.7)) / 0.5))
            draw_line(img, "word of mouth, finally rewarded.", F(46, "Regular"),
                      W/2, 870, WHITE, a2, tr=2)
            a3 = ease_out(clamp01((t - (END + 1.3)) / 0.5))
            if a3 > 0:
                glow_line(img, "ripple", F(58, "SemiBold"), W/2, 1010,
                          ACCENT, int(255 * a3), tr=3)
        img.save(os.path.join(OUT, f"{fi:04d}.png"))
        if fi % 90 == 0: print(f"  {fi}/{N}")
    print(f"✓ {N} overlay frames → {OUT}")

def _scaled(scrim, factor):
    if factor >= 1: return scrim
    out = scrim.copy()
    out.putalpha(scrim.getchannel("A").point(lambda v: int(v * factor)))
    return out

def render_chord():
    sr = 44100
    n = int(2.6 * sr)
    buf = []
    for i in range(n):
        tt = i / sr
        v = 0.0
        for k, fq in enumerate([392.0, 523.25, 659.25]):   # G–C–E, warm
            if tt >= k * 0.11:
                t2 = tt - k * 0.11
                v += math.sin(2 * math.pi * fq * t2) * 0.15 * math.exp(-t2 * 1.6)
        buf.append(v)
    peak = max(abs(v) for v in buf) or 1
    with wave.open(CHORD, "w") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(sr)
        w.writeframes(b"".join(struct.pack("<h", int(v / peak * 20000)) for v in buf))
    print(f"✓ end chord → {CHORD}")

if __name__ == "__main__":
    render_chord()
    render()
