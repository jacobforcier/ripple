#!/usr/bin/env python3
"""
Reel 004 — "The receipt of your influence" (1080x1920, 30fps).

A thermal printer feeds a receipt itemizing a year of recommendations a person
DROVE for friends ($1,840 of purchases), ending on the tension line ("what came
back to you: $0.00"). Tear. Then a short second receipt prints the answer:
"with ripple: $36.80" ( = exactly 2% of $1,840 — internally honest).

This one is RENDERED, not Veo: a receipt is flat monospace typography on paper,
which renders authentically (the procedural ceiling was water physics + water
audio, not flat graphic design). Craft = real thermal type, warm paper texture,
printer bezel, cinematic light pool + vignette + grain.

STILLS mode renders a few key frames to check the look:
    python3 scripts/generate_reel004.py stills
"""

import math
import os
import random
import sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "marketing", "output", "reel004_frames")
INTER = os.path.join(ROOT, "scripts", "fonts", "Inter-wght.ttf")
MONO = "/System/Library/Fonts/Menlo.ttc"

W, H = 1080, 1920
FPS = 30

# paper + ink (warm thermal, never pure white/black)
PAPER = (244, 240, 230)
INK   = (38, 34, 30)
INK2  = (96, 90, 82)        # faded ink for secondary
ACCENT = (60, 110, 235)
GREEN  = (26, 140, 90)
RED    = (190, 60, 55)

PAPER_W = 640
INNER = 34                  # monospace chars across the paper
SLOT_Y = 360                # printer slot; paper emerges below
WIN_H = 980                 # visible paper window height

_fc = {}
def MF(size):
    k = ("mono", size)
    if k not in _fc: _fc[k] = ImageFont.truetype(MONO, size)
    return _fc[k]
def IF(size, weight="Bold"):
    k = (size, weight)
    if k not in _fc:
        f = ImageFont.truetype(INTER, size); f.set_variation_by_name(weight)
        _fc[k] = f
    return _fc[k]

def leader(label, value, width=INNER):
    pad = width - len(label) - len(value)
    return label + ("." * max(2, pad)) + value

# ── receipt content (lines printed top→bottom) ───────────────────────────────
ITEMS = [
    ("espresso machine", "$420"), ("standing desk", "$340"),
    ("kids bike", "$200"), ("running shoes", "$180"),
    ("air fryer", "$130"), ("headphones", "$100"),
    ("dog bed", "$95"), ("water filter", "$90"),
    ("weighted blanket", "$90"), ("coffee grinder", "$75"),
    ("skincare set", "$65"), ("board game", "$55"),
]
# line = (kind, *payload). kinds: logo, gap, rule, center, item, big, note
def receipt_one():
    L = [("logo",), ("center", "YOUR 2026 RECOMMENDATIONS"),
         ("center", "— ITEMIZED —"), ("rule",), ("gap",)]
    for name, price in ITEMS:
        L.append(("item", name, price))
    L += [("gap",), ("rule",),
          ("center", "VALUE YOUR WORD OF MOUTH DROVE"),
          ("big", "$1,840.00", INK), ("gap",), ("rule",),
          ("center", "WHAT CAME BACK TO YOU"),
          ("big", "$0.00", RED), ("rule",), ("gap",)]
    return L

def receipt_two():
    return [("rule",), ("center", "WITH RIPPLE, WHAT COMES"),
            ("center", "BACK TO YOU"),
            ("big", "$36.80", GREEN), ("gap",),
            ("center", "word of mouth, finally rewarded."),
            ("gap",), ("logo",), ("center", "join the waitlist"),
            ("center", "sharewithripple.com"), ("rule",)]

LH = 46                     # line height
def line_h(kind):
    return {"logo": 92, "gap": 26, "rule": 34, "big": 96}.get(kind, LH)

def draw_paper_line(d, x0, y, w, kind, payload):
    cx = x0 + w // 2
    if kind == "logo":
        f = IF(46, "Black")
        s = "ripple"
        tw = d.textlength(s, font=f)
        d.text((cx - tw/2, y + 18), s, font=f, fill=INK)
    elif kind == "gap":
        pass
    elif kind == "rule":
        d.text((x0 + 14, y + 8), "-" * INNER, font=MF(30), fill=INK2)
    elif kind == "center":
        f = MF(28)
        tw = d.textlength(payload[0], font=f)
        d.text((cx - tw/2, y + 8), payload[0], font=f, fill=INK)
    elif kind == "item":
        s = leader(payload[0], payload[1])
        d.text((x0 + 14, y + 8), s, font=MF(30), fill=INK)
    elif kind == "big":
        s, col = payload
        f = MF(72)
        tw = d.textlength(s, font=f)
        d.text((cx - tw/2, y + 12), s, font=f, fill=col)

def render_strip(lines):
    """Render the full paper strip (all lines) → returns RGBA image + height."""
    ys, y = [], 0
    for ln in lines:
        ys.append(y); y += line_h(ln[0])
    sh = y + 30
    strip = Image.new("RGBA", (PAPER_W, sh), (*PAPER, 255))
    # subtle thermal texture: faint horizontal bands + noise
    noise = Image.effect_noise((PAPER_W, sh), 6).convert("L")
    tint = Image.new("RGBA", (PAPER_W, sh), (0, 0, 0, 0))
    tint.putalpha(noise.point(lambda v: int(abs(v - 128) * 0.10)))
    strip.alpha_composite(tint)
    d = ImageDraw.Draw(strip)
    for ln, yy in zip(lines, ys):
        draw_paper_line(d, 0, yy, PAPER_W, ln[0], ln[1:])
    return strip, sh, ys

# ── cinematic backdrop (warm light pool on charcoal) ─────────────────────────
def build_backdrop():
    bg = Image.new("RGB", (W, H), (14, 14, 17))
    glow = Image.new("L", (W, H), 0)
    ImageDraw.Draw(glow).ellipse((W/2 - 420, 280, W/2 + 420, 1500), fill=255)
    glow = glow.filter(ImageFilter.GaussianBlur(220))
    warm = Image.new("RGB", (W, H), (40, 36, 30))
    bg = Image.composite(warm, bg, glow.point(lambda v: int(v * 0.55)))
    return bg
BACKDROP = build_backdrop()

def printer_bezel(img):
    d = ImageDraw.Draw(img, "RGBA")
    # dark mechanism slab across the top, slot at SLOT_Y
    d.rectangle((0, 0, W, SLOT_Y), fill=(20, 20, 24))
    d.rounded_rectangle((W/2 - 360, SLOT_Y - 120, W/2 + 360, SLOT_Y + 6),
                        radius=26, fill=(30, 31, 36))
    d.rounded_rectangle((W/2 - 360, SLOT_Y - 120, W/2 + 360, SLOT_Y + 6),
                        radius=26, outline=(55, 57, 64), width=2)
    # the slot (dark gap paper emerges from)
    d.rectangle((W/2 - PAPER_W/2 - 16, SLOT_Y - 10, W/2 + PAPER_W/2 + 16, SLOT_Y + 4),
                fill=(8, 8, 10))
    # soft shadow lip under the slot onto the paper
    sh = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(sh).rectangle((W/2 - PAPER_W/2, SLOT_Y, W/2 + PAPER_W/2, SLOT_Y + 70),
                                 fill=(0, 0, 0, 120))
    img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(22)))

_grain = None
def grain():
    global _grain
    if _grain is None:
        _grain = Image.effect_noise((W // 2, H // 2), 14).resize((W, H))
    return _grain
_vig = None
def vignette():
    global _vig
    if _vig is None:
        m = Image.new("L", (W, H), 0)
        ImageDraw.Draw(m).ellipse((-W*0.3, -H*0.2, W*1.3, H*1.2), fill=255)
        _vig = m.filter(ImageFilter.GaussianBlur(200)).point(lambda v: 255 - v)
    return _vig

def post(img):
    img.paste(Image.new("RGB", (W, H), (0, 0, 0)), (0, 0),
              vignette().point(lambda v: int(v * 0.6)))
    return Image.composite(img, Image.merge("RGB", (grain(),)*3),
                           Image.new("L", (W, H), 244))

def jagged(d, px, y, w, fill, down=True):
    pts = [(px, y)]
    for i in range(0, w + 1, 18):
        pts.append((px + i, y + ((9 if (i // 18) % 2 else -7) * (1 if down else -1))))
    if down:
        pts += [(px + w, y), (px + w, y + 18), (px, y + 18)]
    else:
        pts += [(px + w, y), (px + w, y - 18), (px, y - 18)]
    d.polygon(pts, fill=fill)

def compose(strip, sh, printed_px, drop=0, alpha=255, torn_top=False):
    """Place the visible window of the strip emerging from the slot.
    drop = px to translate the receipt downward (tear fall); alpha fades it."""
    img = BACKDROP.copy().convert("RGBA")
    win = min(int(printed_px), WIN_H)
    if win <= 0:
        printer_bezel(img); return post(img.convert("RGB"))
    top_src = max(0, int(printed_px) - WIN_H)
    crop = strip.crop((0, top_src, PAPER_W, top_src + win)).convert("RGBA")
    if alpha < 255:
        crop.putalpha(crop.getchannel("A").point(lambda v: int(v * alpha / 255)))
    px = int(W/2 - PAPER_W/2)
    py = SLOT_Y + int(drop)
    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rectangle((px + 12, py + 14, px + PAPER_W + 12, py + win + 14),
                                     fill=(0, 0, 0, int(130 * alpha / 255)))
    img.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(26)))
    img.alpha_composite(crop, (px, py))
    d = ImageDraw.Draw(img, "RGBA")
    edge_y = py + win
    d.rectangle((px, edge_y - 2, px + PAPER_W, edge_y + 3), fill=(*INK2, int(90 * alpha / 255)))
    if torn_top:
        jagged(d, px, py, PAPER_W, (*PAPER, alpha), down=False)
    printer_bezel(img)
    return post(img.convert("RGB"))

# ── timeline ─────────────────────────────────────────────────────────────────
T_P1 = (0.5, 6.0)      # print receipt one
T_HOLD1 = 7.3          # hold climax until
T_TEAR = (7.3, 7.9)    # tear + drop away
T_P2 = (8.2, 10.6)     # print receipt two
T_END = 13.6           # total duration
DUR = T_END

def ramp(t, t0, t1):
    if t <= t0: return 0.0
    if t >= t1: return 1.0
    return (t - t0) / (t1 - t0)

def render_frame(t, one, sh1, two, sh2):
    # mechanical jitter so the feed reads like a stepper, not a smooth slide
    jit = math.sin(t * 70) * 2.0
    if t < T_TEAR[0]:
        p = ramp(t, *T_P1)
        return compose(one, sh1, p * sh1 + (jit if 0 < p < 1 else 0))
    if t < T_TEAR[1]:
        # tear at slot: receipt drops away + fades, jagged top revealed
        q = ramp(t, *T_TEAR)
        return compose(one, sh1, sh1, drop=int(q * q * 1100),
                       alpha=int(255 * (1 - q)), torn_top=True)
    if t < T_P2[0]:
        return compose(two, sh2, 0)         # empty beat
    p = ramp(t, *T_P2)
    return compose(two, sh2, p * sh2 + (jit if 0 < p < 1 else 0))

def render_video():
    os.makedirs(OUT, exist_ok=True)
    one, sh1, _ = render_strip(receipt_one())
    two, sh2, _ = render_strip(receipt_two())
    n = int(DUR * FPS)
    for fi in range(n):
        render_frame(fi / FPS, one, sh1, two, sh2).save(os.path.join(OUT, f"{fi:04d}.png"))
        if fi % 60 == 0: print(f"  {fi}/{n}")
    print(f"✓ {n} frames → {OUT}")

# ── stills ───────────────────────────────────────────────────────────────────
def stills():
    os.makedirs("/tmp/r4", exist_ok=True)
    one, sh1, ys1 = render_strip(receipt_one())
    two, sh2, ys2 = render_strip(receipt_two())
    # mid-print (through ~half the items)
    compose(one, sh1, ys1[8]).save("/tmp/r4/a_midprint.png")
    # climax: $1,840 + $0.00 both in window (print to end)
    compose(one, sh1, sh1, torn=False).save("/tmp/r4/b_climax.png")
    # second receipt fully printed
    compose(two, sh2, sh2, torn=False).save("/tmp/r4/c_second.png")
    for n in ["a_midprint", "b_climax", "c_second"]:
        im = Image.open(f"/tmp/r4/{n}.png"); im.thumbnail((420, 760))
        im.save(f"/tmp/r4/t_{n}.png")
    print("✓ stills → /tmp/r4/t_*.png")

if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "video"
    if mode == "stills":
        stills()
    else:
        render_video()
