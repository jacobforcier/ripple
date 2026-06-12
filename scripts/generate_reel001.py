#!/usr/bin/env python3
"""
Reel 001 v2 — "Everyone got paid except you" (1080x1920, 30fps, ~14s)

Production-quality pass (v1 read as flat/AI-made):
  - Real iMessage chrome: status bar, contact header w/ avatar, bubble TAILS
  - Receipt-paper ledger (Menlo, jagged edge, prints upward) instead of text-on-black
  - Film grain + vignette on every frame; per-scene camera push-in
  - Screen shake on the $0.00 thud; glow pass on the $1.80 payoff
Same beat map + SFX timeline as v1 → scripts/build_reel001.sh works unchanged.
"""

import math
import os
import random
import struct
import wave
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FRAMES_DIR = os.path.join(ROOT, "marketing", "output", "reel001_frames")
SFX_DIR = os.path.join(ROOT, "marketing", "sfx")
INTER = os.path.join(ROOT, "scripts", "fonts", "Inter-wght.ttf")
MENLO = "/System/Library/Fonts/Menlo.ttc"

W, H = 1080, 1920
FPS = 30
N_FRAMES = int(14.0 * FPS)

BG      = (10, 10, 16)
TEXT    = (238, 238, 255)
MUTED   = (148, 148, 178)
ACCENT  = (91, 138, 245)
ACCENT2 = (56, 189, 248)
GREEN   = (52, 211, 153)
RED     = (244, 96, 96)
IN_BUB  = (44, 44, 48)      # iOS dark incoming
OUT_BUB = (10, 132, 255)    # iOS blue

_fc = {}
def F(size, weight="Bold", mono=False):
    key = (size, weight, mono)
    if key not in _fc:
        if mono:
            f = ImageFont.truetype(MENLO, size)
        else:
            f = ImageFont.truetype(INTER, size)
            f.set_variation_by_name(weight)
        _fc[key] = f
    return _fc[key]

def ease_out_back(x):
    c1, c3 = 1.70158, 2.70158
    return 1 + c3 * (x - 1) ** 3 + c1 * (x - 1) ** 2

def ease_out_cubic(x): return 1 - (1 - x) ** 3
def clamp01(x): return max(0.0, min(1.0, x))

def tsize(d, s, f):
    b = d.textbbox((0, 0), s, font=f)
    return b[2] - b[0], b[3] - b[1]

# ── Post pass: camera push-in + vignette + grain ─────────────────────────────
_vignette = None
def vignette():
    global _vignette
    if _vignette is None:
        m = Image.new("L", (W, H), 0)
        dm = ImageDraw.Draw(m)
        dm.ellipse((-W * 0.35, -H * 0.25, W * 1.35, H * 1.25), fill=255)
        m = m.filter(ImageFilter.GaussianBlur(180))
        _vignette = m.point(lambda p: 255 - p)
    return _vignette

def post(canvas, scene_t, shake=0.0):
    # camera push-in: 1.00 → 1.045 across the scene
    z = 1.0 + 0.045 * clamp01(scene_t)
    zw, zh = int(W * z), int(H * z)
    img = canvas.resize((zw, zh), Image.LANCZOS)
    ox = (zw - W) // 2 + int(random.uniform(-shake, shake))
    oy = (zh - H) // 2 + int(random.uniform(-shake, shake))
    img = img.crop((ox, oy, ox + W, oy + H))
    # vignette
    img.paste(Image.new("RGB", (W, H), (0, 0, 0)), (0, 0),
              vignette().point(lambda p: int(p * 0.55)))
    # film grain
    noise = Image.effect_noise((W // 2, H // 2), 14).resize((W, H))
    img = Image.composite(img, Image.merge("RGB", (noise, noise, noise)),
                          Image.new("L", (W, H), 243))
    return img

# ── iMessage chrome ──────────────────────────────────────────────────────────
def chrome(d):
    # status bar
    d.text((92, 36), "10:09", font=F(40, "SemiBold"), fill=TEXT)
    d.rounded_rectangle((W - 132, 44, W - 70, 74), radius=8, outline=MUTED, width=3)
    d.rounded_rectangle((W - 126, 50, W - 88, 68), radius=4, fill=TEXT)
    d.rectangle((W - 68, 52, W - 62, 66), fill=MUTED)
    for i in range(4):  # wifi arcs approximated as bars
        d.rounded_rectangle((W - 220 + i * 16, 70 - i * 8, W - 210 + i * 16, 72),
                            radius=3, fill=TEXT)
    # contact header
    cx, cy = W // 2, 178
    d.ellipse((cx - 56, cy - 56, cx + 56, cy + 56), fill=(72, 84, 116))
    d.text((cx - tsize(d, "M", F(52, "SemiBold"))[0] / 2, cy - 36), "M",
           font=F(52, "SemiBold"), fill=TEXT)
    nm = "Maddie"
    d.text((cx - tsize(d, nm, F(34, "Regular"))[0] / 2, cy + 66), nm,
           font=F(34, "Regular"), fill=MUTED)
    d.line((0, 300, W, 300), fill=(34, 34, 42), width=2)

def bubble(lines, incoming=True, size=46):
    f = F(size, "SemiBold" if not incoming else "Medium")
    tmp = ImageDraw.Draw(Image.new("RGB", (8, 8)))
    wmax = max(tsize(tmp, ln, f)[0] for ln in lines)
    lh = size + 16
    bw, bh = int(wmax) + 76, lh * len(lines) + 44
    img = Image.new("RGBA", (bw + 16, bh + 14), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    col = IN_BUB if incoming else OUT_BUB
    x0 = 14 if incoming else 2
    d.rounded_rectangle((x0, 0, x0 + bw, bh), radius=40, fill=(*col, 255))
    # tail
    tx = x0 + 8 if incoming else x0 + bw - 8
    d.ellipse((tx - 26, bh - 34, tx + 26, bh + 12), fill=(*col, 255))
    d.ellipse((tx - 52, bh - 28, tx - 8, bh + 14) if incoming
              else (tx + 8, bh - 28, tx + 52, bh + 14), fill=(0, 0, 0, 0))
    y = 22
    for ln in lines:
        d.text((x0 + 38, y), ln, font=f, fill=(255, 255, 255, 255))
        y += lh
    sh = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle((x0 + 4, 8, x0 + bw + 4, bh + 8),
                                         radius=40, fill=(0, 0, 0, 110))
    return Image.alpha_composite(sh.filter(ImageFilter.GaussianBlur(10)), img)

def product_card():
    w, h = 660, 270
    img = Image.new("RGBA", (w + 16, h + 16), (0, 0, 0, 0))
    sh = ImageDraw.Draw(img)
    sh.rounded_rectangle((8, 12, w + 8, h + 12), radius=40, fill=(0, 0, 0, 110))
    img = img.filter(ImageFilter.GaussianBlur(10))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((2, 0, w, h), radius=40, fill=(*OUT_BUB, 255))
    d.rounded_rectangle((26, 26, 244, 244), radius=26, fill=(244, 246, 250, 255))
    # nicer air-fryer doodle
    d.rounded_rectangle((68, 56, 202, 216), radius=30, fill=(38, 40, 52, 255))
    d.ellipse((92, 86, 178, 172), fill=(244, 246, 250, 255))
    d.ellipse((114, 108, 156, 150), fill=(38, 40, 52, 255))
    d.rounded_rectangle((104, 186, 166, 200), radius=7, fill=(120, 200, 255, 255))
    d.text((272, 48), "the one I have", font=F(44, "Bold"), fill=(255, 255, 255, 255))
    d.text((272, 116), "$89 · 4.8 stars", font=F(38, "Regular"), fill=(212, 226, 255, 255))
    d.rounded_rectangle((272, 178, 470, 232), radius=27, fill=(255, 255, 255, 46))
    d.text((300, 188), "View item", font=F(32, "SemiBold"), fill=(255, 255, 255, 255))
    return img

def paste_pop(canvas, img, topleft, t0, t, dur=0.3):
    if t < t0: return
    p = clamp01((t - t0) / dur)
    s = 0.7 + 0.3 * ease_out_back(p)
    w, h = int(img.width * s), int(img.height * s)
    im = img.resize((w, h), Image.LANCZOS)
    if p < 1:
        a = im.getchannel("A").point(lambda v: int(v * min(1, p * 2.2)))
        im.putalpha(a)
    canvas.alpha_composite(im, (int(topleft[0] + (img.width - w) / 2),
                                int(topleft[1] + (img.height - h))))

BUB_ASK  = bubble(["ok which air fryer", "do I buy"], incoming=True)
CARD     = product_card()
BUB_SOLD = bubble(["SOLD. buying it", "right now"], incoming=True)
BUB_LOOP = bubble(["ok wait which", "coffee maker"], incoming=True)
TYPING   = bubble(["• • •"], incoming=True, size=40)

# ── Scenes ───────────────────────────────────────────────────────────────────
def scene_thread(c, t, loop=False):
    d = ImageDraw.Draw(c)
    chrome(d)
    if loop:
        paste_pop(c, BUB_LOOP, (70, 430), 13.3, t)
        return
    # hook caption pill (bottom-style, like burned captions)
    hook = "being the friend with good taste doesn't pay"
    f = F(50, "Black")
    wmax = 880
    words, lines, cur = hook.split(), [], ""
    for wd in words:
        trial = (cur + " " + wd).strip()
        if tsize(d, trial, f)[0] > wmax and cur: lines.append(cur); cur = wd
        else: cur = trial
    lines.append(cur)
    y = 1500
    for ln in lines:
        tw = tsize(d, ln, f)[0]
        d.rounded_rectangle((W/2 - tw/2 - 30, y - 12, W/2 + tw/2 + 30, y + 64),
                            radius=22, fill=(12, 12, 18))
        d.text((W/2 - tw/2, y), ln, font=f, fill=TEXT)
        y += 84
    paste_pop(c, BUB_ASK, (70, 430), 0.30, t)
    if t >= 1.6:
        p = ease_out_cubic(clamp01((t - 1.6) / 0.35))
        x = W - 90 - CARD.width + (1 - p) * 360
        im = CARD if p >= 1 else CARD.copy()
        if p < 1:
            a = im.getchannel("A").point(lambda v: int(v * p)); im.putalpha(a)
        c.alpha_composite(im, (int(x), 700))
    if 2.0 <= t < 2.72:
        paste_pop(c, TYPING, (70, 1050), 2.0, t, dur=0.2)
    paste_pop(c, BUB_SOLD, (70, 1050), 2.78, t)

def scene_question(c, t):
    d = ImageDraw.Draw(c)
    p = ease_out_cubic(clamp01((t - 4.15) / 0.4))
    a = int(255 * p)
    y = 850
    for ln in ["so who made money", "on that?"]:
        f = F(78, "Black")
        tw = tsize(d, ln, f)[0]
        d.text((W/2 - tw/2 + 4, y + 4), ln, font=f, fill=(0, 0, 0, a))
        d.text((W/2 - tw/2, y), ln, font=f, fill=(*TEXT, a))
        y += 100

LEDGER = [("AMAZON", "$89.00", "ok"), ("SHIPPING CO.", "PAID", "ok"),
          ("AD INDUSTRY", "PAID", "ok"), ("YOU", "$0.00", "zero")]
LEDGER_T = [6.4, 7.2, 8.0, 8.9]

def receipt(t):
    """White receipt paper, printing upward as lines appear."""
    pw = 850
    rows = sum(1 for tt in LEDGER_T if t >= tt)
    ph = 330 + rows * 130 + (60 if rows == 4 else 0)
    img = Image.new("RGBA", (pw + 30, ph + 40), (0, 0, 0, 0))
    sh = ImageDraw.Draw(img)
    sh.rounded_rectangle((18, 24, pw + 18, ph + 24), radius=6, fill=(0, 0, 0, 130))
    img = img.filter(ImageFilter.GaussianBlur(12))
    d = ImageDraw.Draw(img)
    # paper with jagged bottom
    pts = [(10, 10), (pw + 10, 10), (pw + 10, ph)]
    x = pw + 10
    while x > 10:
        pts.append((x - 22, ph + 16)); pts.append((x - 44, ph)); x -= 44
    pts.append((10, ph))
    d.polygon(pts, fill=(246, 244, 238, 255))
    mono = lambda s: F(s, mono=True)
    title = "* WHO GOT PAID *"
    d.text(((pw + 20 - tsize(d, title, mono(44))[0]) / 2, 56), title,
           font=mono(44), fill=(28, 28, 32, 255))
    sub = "the $89 air fryer your friend bought"
    d.text(((pw + 20 - tsize(d, sub, mono(28))[0]) / 2, 124), sub,
           font=mono(28), fill=(110, 110, 116, 255))
    d.text((60, 180), "-" * 34, font=mono(36), fill=(150, 150, 156, 255))
    y = 240
    for i, (label, amt, kind) in enumerate(LEDGER):
        if t < LEDGER_T[i]: break
        p = ease_out_cubic(clamp01((t - LEDGER_T[i]) / 0.25))
        a = int(255 * p)
        big = kind == "zero"
        ink = (200, 38, 38, a) if big else (28, 28, 32, a)
        fL = mono(46 if big else 38)
        d.text((60, y), label, font=fL, fill=ink)
        wA = tsize(d, amt, fL)[0]
        d.text((pw - 50 - wA, y), amt, font=fL, fill=ink)
        dots = "." * max(2, (pw - 170 - tsize(d, label, fL)[0] - wA) // 22)
        d.text((80 + tsize(d, label, fL)[0], y + (8 if big else 4)), dots,
               font=mono(30), fill=(170, 170, 176, a))
        if big and p > 0.5:  # red double-underline stamp energy
            d.line((60, y + 64, pw - 50, y + 64), fill=(200, 38, 38, a), width=5)
            d.line((60, y + 76, pw - 50, y + 76), fill=(200, 38, 38, a), width=3)
        y += 130
    if rows == 4 and t >= LEDGER_T[3] + 0.4:
        n = "(the reason they bought it)"
        d.text(((pw + 20 - tsize(d, n, mono(28))[0]) / 2, y + 4), n,
               font=mono(28), fill=(140, 140, 146, 255))
    return img

def scene_ledger(c, t):
    r = receipt(t)
    slide = ease_out_cubic(clamp01((t - 6.0) / 0.5))
    c.alpha_composite(r, (int((W - r.width) / 2), int(420 + (1 - slide) * 120)))

def glow_text(c, s, font, center, color, alpha=255):
    layer = Image.new("RGBA", c.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    tw, th = tsize(d, s, font)
    d.text((center[0] - tw / 2, center[1] - th / 2), s, font=font, fill=(*color, alpha))
    c.alpha_composite(layer.filter(ImageFilter.GaussianBlur(26)))
    c.alpha_composite(layer.filter(ImageFilter.GaussianBlur(8)))
    c.alpha_composite(layer)

def scene_flip(c, t):
    d = ImageDraw.Draw(c)
    CY = 700
    roll = ease_out_cubic(clamp01((t - 10.2) / 1.0))
    if roll >= 1.0:
        for i in range(3):
            rt = ((t - 11.2) * 0.7 + i * 0.33) % 1.0
            r = 150 + rt * 240
            a = int(120 * (1 - rt))
            if a > 0:
                col = tuple(int(ACCENT[k] + (ACCENT2[k] - ACCENT[k]) * rt) for k in range(3))
                d.ellipse((W/2 - r, CY - r, W/2 + r, CY + r), outline=(*col, a), width=6)
    val = 1.80 * roll
    col = tuple(int(RED[k] + (GREEN[k] - RED[k]) * roll) for k in range(3))
    settle = 1.0 + (0.06 * math.sin((t - 11.2) * 18) * math.exp(-(t - 11.2) * 6)
                    if t > 11.2 else 0)
    glow_text(c, f"${val:.2f}", F(int(180 * settle), "Black"), (W/2, CY), col)
    p = clamp01((t - 11.0) / 0.4); a = int(255 * ease_out_cubic(p))
    y = 1150
    for s, f, fill in [("unless your link says thank you.", F(56, "Black"), (*TEXT, a)),
                       ("ripple — when friends buy what you recommend,", F(34, "Regular"), (*MUTED, a)),
                       ("a little comes back. honestly small. honestly disclosed.", F(34, "Regular"), (*MUTED, a))]:
        tw = tsize(d, s, f)[0]
        d.text((W/2 - tw/2, y), s, font=f, fill=fill)
        y += 120 if y == 1150 else 52
    glow_text(c, "ripple", F(46, "Black"), (W/2, 1730), ACCENT, a)

# ── Render ───────────────────────────────────────────────────────────────────
def render():
    os.makedirs(FRAMES_DIR, exist_ok=True)
    random.seed(11)
    for fi in range(N_FRAMES):
        t = fi / FPS
        c = Image.new("RGBA", (W, H), (*BG, 255))
        if t < 4.0:
            scene_thread(c, t); st = t / 4.0; shake = 0
        elif t < 6.0:
            scene_question(c, t); st = (t - 4) / 2; shake = 0
        elif t < 10.0:
            scene_ledger(c, t); st = (t - 6) / 4
            shake = 7 * math.exp(-(t - 8.9) * 7) if t >= 8.9 else 0
        elif t < 13.0:
            scene_flip(c, t); st = (t - 10) / 3; shake = 0
        else:
            scene_thread(c, t, loop=True); st = (t - 13); shake = 0
        post(c.convert("RGB"), st, shake).save(os.path.join(FRAMES_DIR, f"{fi:04d}.png"))
        if fi % 90 == 0: print(f"  {fi}/{N_FRAMES}")
    print(f"✓ {N_FRAMES} frames")

def synth_thud():
    path = os.path.join(SFX_DIR, "thud.wav")
    if os.path.exists(path): return
    sr, dur = 44100, 0.35
    with wave.open(path, "w") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(sr)
        fr = b""
        for i in range(int(sr * dur)):
            tt = i / sr
            s = (math.sin(2*math.pi*95*tt)*0.8 + math.sin(2*math.pi*60*tt)*0.5) * math.exp(-tt*14)
            fr += struct.pack("<h", int(max(-1, min(1, s)) * 29000))
        w.writeframes(fr)

if __name__ == "__main__":
    synth_thud()
    render()
