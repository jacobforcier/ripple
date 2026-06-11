#!/usr/bin/env python3
"""
Reel 001 — "Everyone got paid except you" (1080x1920, 30fps, ~14s)

Renders the full reel as a PNG frame sequence + synthesizes the one missing
SFX (thud). All text is drawn with PIL (no ffmpeg drawtext/libass needed).
Assembly is a single ffmpeg command printed at the end.

Scenes
  S1 0.0–4.0   iMessage thread: ask → product card → "SOLD"
  S2 4.0–6.0   black: "so who made money on that?"
  S3 6.0–10.0  receipt ledger: everyone paid ✓ … you $0.00 (thud)
  S4 10.0–13.0 $0.00 flips → rolls to $1.80 green, ripple rings, tagline
  S5 13.0–14.0 thread again: "ok wait which coffee maker" (loop point)

Usage: python3 scripts/generate_reel001.py
"""

import math
import os
import struct
import wave
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FRAMES_DIR = os.path.join(ROOT, "marketing", "output", "reel001_frames")
SFX_DIR = os.path.join(ROOT, "marketing", "sfx")
FONT_PATH = os.path.join(ROOT, "scripts", "fonts", "Inter-wght.ttf")

W, H = 1080, 1920
FPS = 30
DURATION = 14.0
N_FRAMES = int(DURATION * FPS)

# ── Brand palette ─────────────────────────────────────────────────────────────
BG        = (7, 7, 15)        # #07070f
TEXT      = (238, 238, 255)   # #eeeeff
MUTED     = (140, 140, 170)
ACCENT    = (91, 138, 245)    # #5b8af5
ACCENT2   = (56, 189, 248)    # #38bdf8
GREEN     = (52, 211, 153)    # #34d399
RED       = (248, 113, 113)   # #f87171
BUBBLE_IN = (44, 44, 50)      # incoming gray (dark mode)
BUBBLE_OUT= (10, 100, 240)    # outgoing blue

_font_cache = {}
def font(size, weight="Bold"):
    key = (size, weight)
    if key not in _font_cache:
        f = ImageFont.truetype(FONT_PATH, size)
        f.set_variation_by_name(weight)
        _font_cache[key] = f
    return _font_cache[key]

# ── Easing ────────────────────────────────────────────────────────────────────
def ease_out_back(x):
    c1, c3 = 1.70158, 2.70158
    return 1 + c3 * (x - 1) ** 3 + c1 * (x - 1) ** 2

def ease_out_cubic(x):
    return 1 - (1 - x) ** 3

def clamp01(x):
    return max(0.0, min(1.0, x))

# ── Drawing helpers ───────────────────────────────────────────────────────────
def rounded(draw, box, radius, fill):
    draw.rounded_rectangle(box, radius=radius, fill=fill)

def text_size(d, s, f):
    box = d.textbbox((0, 0), s, font=f)
    return box[2] - box[0], box[3] - box[1]

def make_bubble(lines, incoming=True, weight="Bold", size=44,
                color=None, pad=(38, 30)):
    """Prerender a chat bubble as RGBA."""
    f = font(size, weight)
    tmp = Image.new("RGBA", (10, 10))
    d = ImageDraw.Draw(tmp)
    widths = [text_size(d, ln, f)[0] for ln in lines]
    line_h = size + 14
    w = int(max(widths)) + pad[0] * 2
    h = line_h * len(lines) + pad[1] * 2 - 8
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    rounded(d, (0, 0, w - 1, h - 1), 40, (*(BUBBLE_IN if incoming else BUBBLE_OUT), 255))
    y = pad[1] - 4
    for ln in lines:
        d.text((pad[0], y), ln, font=f, fill=(*(color or TEXT), 255))
        y += line_h
    return img

def make_product_card():
    """Outgoing 'link' bubble with a generic product card. No retailer branding."""
    w, h = 620, 250
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    rounded(d, (0, 0, w - 1, h - 1), 40, (*BUBBLE_OUT, 255))
    # product thumbnail placeholder
    rounded(d, (28, 28, 28 + 194, 28 + 194), 28, (235, 238, 245, 255))
    # a little abstract "air fryer" doodle on the thumbnail
    d.rounded_rectangle((68, 62, 182, 188), radius=24, fill=(45, 45, 60, 255))
    d.ellipse((92, 86, 158, 152), fill=(235, 238, 245, 255))
    d.rectangle((104, 166, 146, 176), fill=(120, 200, 255, 255))
    # text
    d.text((258, 52), "the one I have", font=font(42, "Bold"), fill=(255, 255, 255, 255))
    d.text((258, 116), "$89 · 4.8 stars", font=font(36, "Regular"), fill=(214, 226, 255, 255))
    d.text((258, 172), "tap to view", font=font(30, "Regular"), fill=(170, 196, 255, 255))
    return img

def paste_scaled(canvas, img, center, scale, alpha=1.0):
    if scale <= 0 or alpha <= 0:
        return
    w = max(1, int(img.width * scale))
    h = max(1, int(img.height * scale))
    s = img.resize((w, h), Image.LANCZOS)
    if alpha < 1.0:
        a = s.getchannel("A").point(lambda p: int(p * alpha))
        s.putalpha(a)
    canvas.alpha_composite(s, (int(center[0] - w / 2), int(center[1] - h / 2)))

def pop_in(canvas, img, center, t0, t, dur=0.28):
    """Bubble pop animation: scale overshoot + fade."""
    if t < t0:
        return
    p = clamp01((t - t0) / dur)
    paste_scaled(canvas, img, center, 0.6 + 0.4 * ease_out_back(p), clamp01(p * 2.5))

def draw_check(d, x, y, size=34, color=GREEN, width=9):
    d.line([(x, y + size * 0.55), (x + size * 0.35, y + size * 0.95)], fill=color, width=width)
    d.line([(x + size * 0.35, y + size * 0.95), (x + size, y + size * 0.1)], fill=color, width=width)

def draw_centered(d, s, y, f, fill, x_center=W // 2):
    w, _ = text_size(d, s, f)
    d.text((x_center - w / 2, y), s, font=f, fill=fill)
    return w

# ── Prerendered components ────────────────────────────────────────────────────
BUBBLE_ASK   = make_bubble(["ok which air fryer", "do I buy"], incoming=True)
CARD         = make_product_card()
BUBBLE_SOLD  = make_bubble(["SOLD. buying it", "right now"], incoming=True)
BUBBLE_LOOP  = make_bubble(["ok wait which", "coffee maker"], incoming=True)

def make_typing():
    img = Image.new("RGBA", (170, 96), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    rounded(d, (0, 0, 169, 95), 40, (*BUBBLE_IN, 255))
    return img

TYPING = make_typing()

HOOK_LINES = ["being the friend with", "good taste doesn't pay"]

LEDGER = [
    ("Amazon",                          "$89.00", "check"),
    ("the shipping company",            "paid",   "check"),
    ("the ad industry",                 "paid",   "check"),
    ("you (the reason they bought it)", "$0.00",  "zero"),
]
LEDGER_TIMES = [6.4, 7.2, 8.0, 8.9]

# ── Scene painters ────────────────────────────────────────────────────────────
def draw_hook(canvas, t, t0=0.0):
    d = ImageDraw.Draw(canvas)
    p = clamp01((t - t0) / 0.3)
    if p <= 0:
        return
    a = int(255 * p)
    y = 210
    for ln in HOOK_LINES:
        f = font(72, "Black")
        w, _ = text_size(d, ln, f)
        d.text(((W - w) / 2 + 3, y + 3), ln, font=f, fill=(0, 0, 0, a))   # shadow
        d.text(((W - w) / 2, y), ln, font=f, fill=(*TEXT, a))
        y += 92

def scene_thread(canvas, t):
    draw_hook(canvas, t)
    pop_in(canvas, BUBBLE_ASK, (110 + BUBBLE_ASK.width / 2, 760), 0.30, t)
    # outgoing card slides in from right with the whoosh
    if t >= 1.6:
        p = clamp01((t - 1.6) / 0.30)
        x = W - 90 - CARD.width / 2 + (1 - ease_out_cubic(p)) * 320
        paste_scaled(canvas, CARD, (x, 1020), 1.0, clamp01(p * 2.5))
    # typing dots 2.0–2.72
    if 2.0 <= t < 2.72:
        cx, cy = 110 + TYPING.width / 2, 1300
        pop_in(canvas, TYPING, (cx, cy), 2.0, t, dur=0.2)
        d = ImageDraw.Draw(canvas)
        for i in range(3):
            phase = (t * 4 - i * 0.55) % 3
            lift = 6 * math.sin(min(math.pi, max(0.0, phase) * math.pi))
            r = 9
            d.ellipse((cx - 44 + i * 36 - r, cy - lift - r, cx - 44 + i * 36 + r, cy - lift + r),
                      fill=(160, 160, 175, 255))
    pop_in(canvas, BUBBLE_SOLD, (110 + BUBBLE_SOLD.width / 2, 1320), 2.78, t)

def scene_question(canvas, t):
    d = ImageDraw.Draw(canvas)
    p = clamp01((t - 4.15) / 0.4)
    a = int(255 * ease_out_cubic(p))
    f = font(74, "Black")
    lines = ["so who made money", "on that?"]
    y = 850
    for ln in lines:
        w, _ = text_size(d, ln, f)
        d.text(((W - w) / 2, y), ln, font=f, fill=(*TEXT, a))
        y += 96

def scene_ledger(canvas, t):
    d = ImageDraw.Draw(canvas)
    draw_centered(d, "the $89 air fryer your friend bought:", 430, font(44, "Bold"), (*MUTED, 255))
    y = 640
    for i, (label, amount, kind) in enumerate(LEDGER):
        t0 = LEDGER_TIMES[i]
        if t < t0:
            break
        p = ease_out_cubic(clamp01((t - t0) / 0.27))
        a = int(255 * p)
        yy = y + (1 - p) * 26
        big = kind == "zero"
        lf = font(50 if big else 46, "Black" if big else "Bold")
        lcol = (*RED, a) if big else (*TEXT, a)
        d.text((90, yy), label if not big else "you", font=lf, fill=lcol)
        if big:
            d.text((90, yy + 64), "(the reason they bought it)", font=font(34, "Regular"),
                   fill=(*MUTED, a))
        if kind == "check":
            amt_f = font(46, "Bold")
            w, _ = text_size(d, amount, amt_f)
            d.text((W - 170 - w, yy), amount, font=amt_f, fill=(*MUTED, a))
            if p > 0.6:
                draw_check(d, W - 140, yy + 4, color=(*GREEN, a))
        else:
            amt_f = font(64, "Black")
            w, _ = text_size(d, amount, amt_f)
            d.text((W - 100 - w, yy), amount, font=amt_f, fill=(*RED, a))
        d.line([(90, y + (170 if big else 120)), (W - 90, y + (170 if big else 120))],
               fill=(40, 40, 55, 255), width=2)
        y += 200 if big else 150

def scene_flip(canvas, t):
    d = ImageDraw.Draw(canvas)
    # ripple rings behind the counter once green
    CY = 660  # counter / ring center — high enough that rings never hit the text
    roll = ease_out_cubic(clamp01((t - 10.2) / 1.0))
    if roll >= 1.0:
        for i in range(3):
            ring_t = ((t - 11.2) * 0.7 + i * 0.33) % 1.0
            r = 120 + ring_t * 210   # max 330 → bottom edge ~990, clear of tagline
            a = int(110 * (1 - ring_t))
            if a > 0:
                col = (
                    int(ACCENT[0] + (ACCENT2[0] - ACCENT[0]) * ring_t),
                    int(ACCENT[1] + (ACCENT2[1] - ACCENT[1]) * ring_t),
                    int(ACCENT[2] + (ACCENT2[2] - ACCENT[2]) * ring_t),
                    a,
                )
                d.ellipse((W / 2 - r, CY - r, W / 2 + r, CY + r), outline=col, width=5)
    value = 1.80 * roll
    col = (
        int(RED[0] + (GREEN[0] - RED[0]) * roll),
        int(RED[1] + (GREEN[1] - RED[1]) * roll),
        int(RED[2] + (GREEN[2] - RED[2]) * roll),
        255,
    )
    settle = 1.0 + (0.06 * math.sin((t - 11.2) * 18) * math.exp(-(t - 11.2) * 6)
                    if t > 11.2 else 0)
    f = font(int(170 * settle), "Black")
    fw, fh = text_size(d, f"${value:.2f}", f)
    d.text((W / 2 - fw / 2, CY - fh / 2 - 20), f"${value:.2f}", font=f, fill=col)
    # tagline (kept below the rings' max reach)
    p = clamp01((t - 11.0) / 0.4)
    a = int(255 * ease_out_cubic(p))
    draw_centered(d, "unless your link says thank you.", 1120, font(54, "Black"), (*TEXT, a))
    draw_centered(d, "ripple — when friends buy what you recommend,", 1250,
                  font(34, "Regular"), (*MUTED, a))
    draw_centered(d, "a little comes back. honestly small. honestly disclosed.", 1300,
                  font(34, "Regular"), (*MUTED, a))
    draw_centered(d, "ripple", 1700, font(44, "Black"), (*ACCENT, a))

def scene_loop(canvas, t):
    draw_hook(canvas, t, t0=13.05)
    pop_in(canvas, BUBBLE_LOOP, (110 + BUBBLE_LOOP.width / 2, 800), 13.3, t)

# ── Render ────────────────────────────────────────────────────────────────────
def render():
    os.makedirs(FRAMES_DIR, exist_ok=True)
    for f_i in range(N_FRAMES):
        t = f_i / FPS
        canvas = Image.new("RGBA", (W, H), (*BG, 255))
        if t < 4.0:
            scene_thread(canvas, t)
        elif t < 6.0:
            scene_question(canvas, t)
        elif t < 10.0:
            scene_ledger(canvas, t)
        elif t < 13.0:
            scene_flip(canvas, t)
        else:
            scene_loop(canvas, t)
        canvas.convert("RGB").save(os.path.join(FRAMES_DIR, f"{f_i:04d}.png"))
        if f_i % 60 == 0:
            print(f"  frame {f_i}/{N_FRAMES}")
    print(f"✓ {N_FRAMES} frames → {FRAMES_DIR}")

def synth_thud():
    """Low 110Hz decaying sine — the '$0.00' comedic thud."""
    path = os.path.join(SFX_DIR, "thud.wav")
    if os.path.exists(path):
        return
    sr, dur = 44100, 0.35
    n = int(sr * dur)
    with wave.open(path, "w") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(sr)
        frames = b""
        for i in range(n):
            t = i / sr
            env = math.exp(-t * 14)
            s = (math.sin(2 * math.pi * 95 * t) * 0.8 +
                 math.sin(2 * math.pi * 60 * t) * 0.5) * env
            frames += struct.pack("<h", int(max(-1, min(1, s)) * 32767 * 0.9))
        w.writeframes(frames)
    print(f"✓ synthesized {path}")

if __name__ == "__main__":
    synth_thud()
    render()
    print("\nAssemble with:")
    print("  (see scripts/build_reel001.sh)")
