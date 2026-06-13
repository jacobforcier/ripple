#!/usr/bin/env python3
"""
Reel 002 — overlay layer for the Veo water hero shot.

Renders TRANSPARENT PNG frames (1080x1920, 30fps) that get composited over
marketing/raw/veo_water.mp4 by build_reel002.sh. The video brings the (real)
water + (real) audio; this layer brings the on-brand story:
  - hook (0–2s)
  - a running earnings counter, top-right, ticking through the month
  - floating purchase labels near the splashes (+$1.20 blender …)
  - end card (8.2s+): dark settle scrim → total → "word of mouth, finally
    rewarded." → ripple

Also writes a short end-chord WAV (music, not a fake water sound).
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

TEXT   = (240, 240, 255)
ACCENT = (91, 138, 245)
CYAN   = (120, 210, 255)
GREEN  = (74, 222, 168)

_fc = {}
def F(size, weight="Bold"):
    if (size, weight) not in _fc:
        f = ImageFont.truetype(INTER, size); f.set_variation_by_name(weight)
        _fc[(size, weight)] = f
    return _fc[(size, weight)]

def ease_out(x): return 1 - (1 - x) ** 3
def clamp01(x): return max(0.0, min(1.0, x))
def tsize(d, s, f):
    b = d.textbbox((0, 0), s, font=f); return b[2] - b[0], b[3] - b[1]

# Counter ticks through all 11; labels shown for the starred subset.
# (impact time, label, cents, x-fraction, show_label)
DROPS = [
    (2.2, "dog toy",        40, 0.28, True),
    (2.7, "book",           25, 0.62, False),
    (3.4, "blender",       120, 0.62, True),
    (3.9, "sunscreen",      45, 0.70, False),
    (4.5, "board game",     80, 0.28, False),
    (5.1, "running shoes", 190, 0.36, True),
    (5.7, "coffee maker",  145, 0.66, False),
    (6.3, "dog bed",        95, 0.30, False),
    (6.9, "stroller",      210, 0.60, True),
    (7.3, "water bottle",   50, 0.40, False),
    (7.7, "desk lamp",     180, 0.34, True),
]
TOTAL = sum(c for _, _, c, _, _ in DROPS)   # 1180 = $11.80
END = 8.2                                    # end card begins

def total_at(t):
    return sum(c for tt, _, c, _, _ in DROPS if t >= tt)

def glow_text(img, s, font, center, color, alpha=255):
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    tw, th = tsize(d, s, font)
    d.text((center[0] - tw/2, center[1] - th/2), s, font=font, fill=(*color, alpha))
    img.alpha_composite(layer.filter(ImageFilter.GaussianBlur(26)))
    img.alpha_composite(layer.filter(ImageFilter.GaussianBlur(8)))
    img.alpha_composite(layer)

def draw_hook(d, t):
    if t >= 2.3: return
    fade = clamp01(t / 0.4) * (1 - clamp01((t - 1.9) / 0.4))
    a = int(255 * fade)
    if a <= 0: return
    y = 250
    f = F(52, "Black")
    for ln in ["my friends don't buy", "anything without", "asking me first"]:
        tw = tsize(d, ln, f)[0]
        d.rounded_rectangle((W/2 - tw/2 - 30, y - 12, W/2 + tw/2 + 30, y + 70),
                            radius=22, fill=(8, 10, 16, int(200 * fade)))
        d.text((W/2 - tw/2, y), ln, font=f, fill=(*TEXT, a))
        y += 100

def draw_counter(d, t):
    if t < DROPS[0][0] or t >= END: return
    bump = 0.0
    for tt, *_ in DROPS:
        if 0 <= t - tt < 0.3:
            bump = (1 - (t - tt) / 0.3) * 0.16
    f = F(int(46 * (1 + bump)), "Black")
    s = f"${total_at(t)/100:.2f}"
    tw = tsize(d, s, f)[0]
    appear = clamp01((t - DROPS[0][0]) / 0.4)
    a = int(255 * appear)
    d.rounded_rectangle((W - tw - 122, 64, W - 48, 146), radius=24,
                        fill=(8, 10, 16, int(170 * appear)))
    d.rounded_rectangle((W - tw - 122, 64, W - 48, 146), radius=24,
                        outline=(*CYAN, int(120 * appear)), width=2)
    d.text((W - tw - 86, 82), s, font=f, fill=(*GREEN, a))

def draw_labels(d, t):
    for tt, label, cents, xf, show in DROPS:
        if not show or not (tt <= t < tt + 1.15) or t >= END: continue
        p = (t - tt) / 1.15
        a = int(255 * min(1, p * 6) * (1 - clamp01((p - 0.65) / 0.35)))
        rise = 26 * ease_out(min(1, p * 2.5))
        cx = min(max(xf * W, 170), W - 170)
        cy = 350 + (int(xf * 1000) % 150) - rise       # scatter in dark band
        s1, s2 = f"+${cents/100:.2f}", label
        f1, f2 = F(54, "Black"), F(32, "Medium")
        w1, w2 = tsize(d, s1, f1)[0], tsize(d, s2, f2)[0]
        d.text((cx - w1/2 + 2, cy + 2), s1, font=f1, fill=(0, 0, 0, a))
        d.text((cx - w1/2, cy), s1, font=f1, fill=(*GREEN, a))
        d.text((cx - w2/2, cy + 64), s2, font=f2, fill=(*TEXT, int(a * 0.85)))

def render():
    os.makedirs(OUT, exist_ok=True)
    for fi in range(N):
        t = fi / FPS
        img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        d = ImageDraw.Draw(img, "RGBA")
        draw_hook(d, t)
        draw_counter(d, t)
        draw_labels(d, t)

        if t >= END - 0.2:
            # settle scrim — dark vertical gradient fades in to calm the water
            sa = ease_out(clamp01((t - (END - 0.2)) / 0.7))
            scrim = Image.new("RGBA", (W, H), (0, 0, 0, 0))
            sd = ImageDraw.Draw(scrim)
            for y in range(0, H, 8):
                edge = min(y, H - y) / (H / 2)         # darker center band
                aa = int(205 * sa * (0.45 + 0.55 * (1 - abs(0.5 - y / H) * 2)))
                sd.rectangle((0, y, W, y + 8), fill=(6, 9, 18, max(0, aa)))
            img.alpha_composite(scrim)
            p = ease_out(clamp01((t - END) / 0.6))
            glow_text(img, f"${TOTAL/100:.2f}", F(150, "Black"),
                      (W/2, 720), GREEN, int(255 * p))
            d = ImageDraw.Draw(img, "RGBA")
            a2 = int(255 * ease_out(clamp01((t - (END + 0.6)) / 0.5)))
            s = "word of mouth, finally rewarded."
            f = F(48, "Bold"); tw = tsize(d, s, f)[0]
            d.text((W/2 - tw/2, 910), s, font=f, fill=(*TEXT, a2))
            if t >= END + 1.2:
                glow_text(img, "ripple", F(56, "Black"), (W/2, 1050), ACCENT,
                          int(255 * ease_out(clamp01((t - (END + 1.2)) / 0.5))))
        img.save(os.path.join(OUT, f"{fi:04d}.png"))
        if fi % 90 == 0: print(f"  {fi}/{N}")
    print(f"✓ {N} overlay frames → {OUT}")

def render_chord():
    sr = 44100
    n = int(2.6 * sr)
    buf = []
    for i in range(n):
        tt = i / sr
        v = 0.0
        for k, fq in enumerate([392.0, 523.25, 659.25]):   # G–C–E
            if tt >= k * 0.10:
                t2 = tt - k * 0.10
                v += math.sin(2 * math.pi * fq * t2) * 0.16 * math.exp(-t2 * 1.7)
        buf.append(v)
    peak = max(abs(v) for v in buf) or 1
    with wave.open(CHORD, "w") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(sr)
        w.writeframes(b"".join(struct.pack("<h", int(v / peak * 22000)) for v in buf))
    print(f"✓ end chord → {CHORD}")

if __name__ == "__main__":
    render_chord()
    render()
