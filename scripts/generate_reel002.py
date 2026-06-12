#!/usr/bin/env python3
"""
Reel 002 — "A drop for every friend" (1080x1920, 30fps, 16s, loops)

Oddly-satisfying visual: glowing droplets fall into rising water — one per
friend purchase, each labeled (+$0.40 dog toy …) — plink pitch rises with the
level, ending calm on the month's total. Identity: the one they ask.

Outputs frames + a single composed audio bed (all plinks + end chime), so
assembly is one ffmpeg call (scripts/build_reel002.sh).
"""

import math
import os
import random
import struct
import wave
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FRAMES = os.path.join(ROOT, "marketing", "output", "reel002_frames")
AUDIO = os.path.join(ROOT, "marketing", "output", "reel002_audio.wav")
INTER = os.path.join(ROOT, "scripts", "fonts", "Inter-wght.ttf")

W, H = 1080, 1920
FPS = 30
DUR = 16.0
N = int(DUR * FPS)

BG      = (8, 9, 15)
TEXT    = (240, 240, 255)
MUTED   = (150, 150, 180)
ACCENT  = (91, 138, 245)
ACCENT2 = (56, 189, 248)
GREEN   = (62, 220, 160)

_fc = {}
def F(size, weight="Bold"):
    if (size, weight) not in _fc:
        f = ImageFont.truetype(INTER, size)
        f.set_variation_by_name(weight)
        _fc[(size, weight)] = f
    return _fc[(size, weight)]

def ease_out(x): return 1 - (1 - x) ** 3
def clamp01(x): return max(0.0, min(1.0, x))
def tsize(d, s, f):
    b = d.textbbox((0, 0), s, font=f); return b[2] - b[0], b[3] - b[1]

# ── The month of drops: (impact time, label, cents, x position) ──────────────
DROPS = [
    (1.0,  "dog toy",        40, 0.30),
    (2.2,  "book",           25, 0.66),
    (3.3,  "blender",       120, 0.42),
    (4.3,  "sunscreen",      45, 0.72),
    (5.2,  "board game",     80, 0.26),
    (6.0,  "running shoes", 190, 0.58),
    (6.8,  "coffee maker",  145, 0.38),
    (7.5,  "dog bed",        95, 0.70),
    (8.2,  "stroller",      210, 0.30),
    (8.9,  "water bottle",   50, 0.62),
    (9.6,  "desk lamp",     180, 0.46),
]
TOTAL = sum(c for _, _, c, _ in DROPS)          # 1180 = $11.80
FALL = 0.55                                      # seconds of fall before impact
LVL0, LVL1 = 0.14, 0.52                          # water fill: start → end

def level_at(t):
    """Water fill fraction — steps up smoothly at each impact."""
    done = sum(1 for tt, *_ in DROPS if t >= tt + 0.4)
    partial = 0.0
    for tt, *_ in DROPS:
        if tt <= t < tt + 0.4:
            partial = ease_out((t - tt) / 0.4)
    return LVL0 + (LVL1 - LVL0) * (done + partial) / len(DROPS)

def total_at(t):
    return sum(c for tt, _, c, _ in DROPS if t >= tt)

# ── Water (v2 craft: layered waves, crest glow, bubbles) ─────────────────────
def draw_water(d, t, surface_y):
    def wavey(x, amp, freq, speed, phase=0.0):
        u = x / W
        return surface_y + amp * math.sin(u * math.pi * freq + t * speed + phase)
    for amp, freq, speed, phase, col in [
        (14, 2, 1.0, 1.8, (*ACCENT, 64)),
        (10, 2, 1.6, 0.0, None),
    ]:
        pts = [(0, H)] + [(x, wavey(x, amp, freq, speed, phase)) for x in range(0, W + 8, 8)] + [(W, H)]
        if col:
            d.polygon(pts, fill=col)
        else:
            d.polygon(pts, fill=None)
    # gradient body: draw bands from surface to bottom
    band = 26
    y = int(surface_y)
    while y < H:
        p = (y - surface_y) / max(1, H - surface_y)
        deep = (16, 34, 86)
        r = int(ACCENT2[0] + (deep[0] - ACCENT2[0]) * p)
        g = int(ACCENT2[1] + (deep[1] - ACCENT2[1]) * p)
        b = int(ACCENT2[2] + (deep[2] - ACCENT2[2]) * p)
        a = int(165 - 55 * p)
        d.rectangle((0, y, W, min(H, y + band)), fill=(r, g, b, a))
        y += band
    # crest line
    crest = [(x, wavey(x, 10, 2, 1.6) ) for x in range(0, W + 4, 4)]
    d.line(crest, fill=(*ACCENT2, 235), width=3)
    # bubbles
    for i in range(7):
        seed = i * 1.7 + 1
        cyc = 5.0 + (i % 3)
        ph = (t / cyc + seed * 0.37) % 1.0
        bx = ((seed * 137.5) % 1.0) * W * 0.9 + W * 0.05 + math.sin(t * 1.1 + seed) * 8
        depth = H - surface_y
        if depth < 60: continue
        by = H - ph * (depth - 30)
        r = 2 + (i % 3)
        d.ellipse((bx - r, by - r, bx + r, by + r), fill=(255, 255, 255, int(70 * (1 - ph))))

def draw_drop(d, t):
    """Falling droplets + impact ripples + splash."""
    for tt, _, _, xf in DROPS:
        x = xf * W
        # fall
        if tt - FALL <= t < tt:
            p = (t - (tt - FALL)) / FALL
            y = -80 + (level_y(t) + 6 + 80) * (p * p)   # gravity-ish
            r = 22
            # trail
            for k in range(3):
                ty = y - (k + 1) * 26
                d.ellipse((x - r*0.5, ty - r*0.9, x + r*0.5, ty + r*0.9),
                          fill=(*ACCENT2, int(60 - k * 18)))
            d.ellipse((x - r - 8, y - r * 1.4, x + r + 8, y + r + 8),
                      fill=(*ACCENT2, 60))
            d.ellipse((x - r, y - r * 1.25, x + r, y + r),
                      fill=(*ACCENT2, 255))
            d.ellipse((x - r*0.45, y - r*0.8, x + r*0.05, y - r*0.25),
                      fill=(255, 255, 255, 130))
        # impact ripples + splash
        if tt <= t < tt + 0.9:
            p = (t - tt) / 0.9
            sy = level_y(t)
            for k in range(2):
                rp = clamp01(p * 1.3 - k * 0.25)
                if rp <= 0: continue
                rw = 30 + 150 * ease_out(rp)
                a = int(170 * (1 - rp))
                d.ellipse((x - rw, sy - rw * 0.22, x + rw, sy + rw * 0.22),
                          outline=(*ACCENT2, a), width=4)
            if p < 0.4:
                for k in range(5):
                    ang = math.pi * (0.25 + 0.5 * k / 4)
                    pr = ease_out(p / 0.4)
                    px = x + math.cos(ang) * 46 * pr * (1 if k % 2 else -1)
                    py = sy - abs(math.sin(ang)) * 60 * pr * (1 - p)
                    d.ellipse((px - 4, py - 4, px + 4, py + 4),
                              fill=(*ACCENT2, int(200 * (1 - p / 0.4))))

def level_y(t):
    return H * (1 - level_at(t))

def draw_labels(d, t):
    for tt, label, cents, xf in DROPS:
        if not (tt <= t < tt + 1.7): continue
        p = (t - tt) / 1.7
        a = int(255 * min(1, p * 5) * (1 - clamp01((p - 0.75) / 0.25)))
        rise = 26 * ease_out(min(1, p * 2))
        x = xf * W
        sy = level_y(tt) - 290 - rise
        s1 = f"+${cents/100:.2f}"
        s2 = label
        f1, f2 = F(48, "Black"), F(30, "Medium")
        w1 = tsize(d, s1, f1)[0]; w2 = tsize(d, s2, f2)[0]
        cxx = min(max(x, 130), W - 130)
        d.text((cxx - w1/2 + 2, sy + 2), s1, font=f1, fill=(0, 0, 0, a))
        d.text((cxx - w1/2, sy), s1, font=f1, fill=(*GREEN, a))
        d.text((cxx - w2/2, sy + 58), s2, font=f2, fill=(*TEXT, int(a * 0.85)))

def draw_counter(d, t):
    if t < DROPS[0][0]: return
    cents = total_at(t)
    s = f"${cents/100:.2f}"
    f = F(44, "Black")
    tw = tsize(d, s, f)[0]
    # bump scale just after each impact
    bump = 0.0
    for tt, *_ in DROPS:
        if 0 <= t - tt < 0.3:
            bump = (1 - (t - tt) / 0.3) * 0.18
    f = F(int(44 * (1 + bump)), "Black")
    tw = tsize(d, s, f)[0]
    d.rounded_rectangle((W - tw - 120, 64, W - 48, 140), radius=22, fill=(14, 15, 22, 215))
    d.rounded_rectangle((W - tw - 120, 64, W - 48, 140), radius=22, outline=(*ACCENT2, 120), width=2)
    d.text((W - tw - 84, 78), s, font=f, fill=(*GREEN, 255))

def caption_pill(d, lines, y, size=50):
    f = F(size, "Black")
    for ln in lines:
        tw = tsize(d, ln, f)[0]
        d.rounded_rectangle((W/2 - tw/2 - 30, y - 12, W/2 + tw/2 + 30, y + size + 16),
                            radius=22, fill=(12, 12, 18, 235))
        d.text((W/2 - tw/2, y), ln, font=f, fill=TEXT)
        y += size + 36
    return y

def glow_text(img, s, font, center, color, alpha=255):
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    tw, th = tsize(d, s, font)
    d.text((center[0] - tw/2, center[1] - th/2), s, font=font, fill=(*color, alpha))
    for L in (layer.filter(ImageFilter.GaussianBlur(24)),
              layer.filter(ImageFilter.GaussianBlur(7)), layer):
        img.paste(L, (0, 0), L)

# ── Post: vignette + grain ───────────────────────────────────────────────────
_vig = None
def vignette():
    global _vig
    if _vig is None:
        m = Image.new("L", (W, H), 0)
        ImageDraw.Draw(m).ellipse((-W*0.35, -H*0.25, W*1.35, H*1.25), fill=255)
        _vig = m.filter(ImageFilter.GaussianBlur(180)).point(lambda p: 255 - p)
    return _vig

def post(img):
    rgb = img.convert("RGB")
    rgb.paste(Image.new("RGB", (W, H), (0, 0, 0)), (0, 0),
              vignette().point(lambda p: int(p * 0.5)))
    noise = Image.effect_noise((W // 2, H // 2), 13).resize((W, H))
    return Image.composite(rgb, Image.merge("RGB", (noise,)*3),
                           Image.new("L", (W, H), 244))

# ── Frames ───────────────────────────────────────────────────────────────────
def render():
    os.makedirs(FRAMES, exist_ok=True)
    random.seed(7)
    for fi in range(N):
        t = fi / FPS
        img = Image.new("RGB", (W, H), BG)
        glow_y = level_y(t)
        # ambient glow above the waterline (blurred layer — draw-with-alpha
        # doesn't blend in PIL; it stamps opaque)
        gl = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        ImageDraw.Draw(gl).ellipse((W/2 - 380, glow_y - 200, W/2 + 380, glow_y + 120),
                                   fill=(*ACCENT, 60))
        gl = gl.filter(ImageFilter.GaussianBlur(130))
        img.paste(gl, (0, 0), gl)
        d = ImageDraw.Draw(img, "RGBA")
        draw_water(d, t, glow_y)
        draw_drop(d, t)
        draw_labels(d, t)
        draw_counter(d, t)

        if t < 3.4:
            a = 1 - clamp01((t - 2.8) / 0.6)
            if a > 0:
                caption_pill(d, ["what a month of", "“send me the link” looks like"], 320)
        if 11.4 <= t:
            p = ease_out(clamp01((t - 11.4) / 0.6))
            glow_text(img, f"${TOTAL/100:.2f}", F(150, "Black"),
                      (W/2, 500), GREEN, int(255 * p))
            d = ImageDraw.Draw(img, "RGBA")
            a = int(255 * ease_out(clamp01((t - 12.0) / 0.5)))
            for s, f, yy, fill in [
                ("a month of friends asking you.", F(46, "Bold"), 680, (*TEXT, a)),
                ("word of mouth, rewarded.", F(46, "Bold"), 748, (*ACCENT2, a)),
            ]:
                tw = tsize(d, s, f)[0]
                d.text((W/2 - tw/2, yy), s, font=f, fill=fill)
            if t >= 12.6:
                glow_text(img, "ripple", F(54, "Black"), (W/2, 870), ACCENT,
                          int(255 * ease_out(clamp01((t - 12.6) / 0.5))))
        post(img).save(os.path.join(FRAMES, f"{fi:04d}.png"))
        if fi % 120 == 0: print(f"  {fi}/{N}")
    print(f"✓ {N} frames")

# ── Audio bed: rising-pitch plinks + end chime, one WAV ──────────────────────
def render_audio():
    sr = 44100
    buf = [0.0] * int(DUR * sr)
    def add(t0, gen):
        i0 = int(t0 * sr)
        for j, v in enumerate(gen):
            if i0 + j < len(buf): buf[i0 + j] += v
    def plink(freq):
        n = int(0.28 * sr)
        for i in range(n):
            tt = i / sr
            f = freq * (1 + 0.35 * math.exp(-tt * 30))     # pitch droop = waterdrop
            yield (math.sin(2 * math.pi * f * tt) * 0.55 +
                   math.sin(4 * math.pi * f * tt) * 0.12) * math.exp(-tt * 16)
    def chime():
        n = int(1.6 * sr)
        for i in range(n):
            tt = i / sr
            yield (math.sin(2*math.pi*523.25*tt) * 0.30 +
                   math.sin(2*math.pi*659.25*tt) * 0.22 +
                   math.sin(2*math.pi*783.99*tt) * 0.18) * math.exp(-tt * 2.6)
    for k, (tt, *_ ) in enumerate(DROPS):
        add(tt, plink(430 + k * 38))                       # rising scale
    add(11.4, chime())
    peak = max(abs(v) for v in buf) or 1
    with wave.open(AUDIO, "w") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(sr)
        w.writeframes(b"".join(struct.pack("<h", int(v / peak * 30000)) for v in buf))
    print(f"✓ audio bed → {AUDIO}")

if __name__ == "__main__":
    render_audio()
    render()
