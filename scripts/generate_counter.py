#!/usr/bin/env python3
"""Render a $0 → $40 counter as an MP4 clip.

Used in the spot where the VO says "Conservatively, forty bucks I would've
earned." The number rolls up over ~1.0s with an ease-out, then holds (with a
tiny color pulse on landing) for the remainder of the slot.

Inputs: none (constants below).
Output: marketing/cards/05_total_counter.mp4
"""

import math
import os
import subprocess
import tempfile
import shutil
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, '..', 'marketing', 'cards', '05_total_counter.mp4')
FONT_PATH = os.path.join(HERE, 'fonts', 'Inter-wght.ttf')

W, H = 1080, 1920
FPS = 30
DURATION = 6.05            # match slot_total in build.sh

# Phase boundaries (seconds, relative to slot start). Master t = slot + 18.80.
T_ROLL_END   = 1.00        # 0.00–1.00: count up 0 → 40 in cyan
T_PULSE_END  = 1.25        # 1.00–1.25: gold landing pulse
T_GREEN_END  = 1.60        # 1.25–1.60: gold → green transition
T_DROP_START = 4.20        # 1.60–4.20: HOLD $40 in green
T_DROP_END   = 4.90        # 4.20–4.90: SLOW deflate 40 → 0 (0.70s), green → red
T_SHAKE_END  = 5.10        # 4.90–5.10: tiny shake on $0 landing
                           # 5.10–6.05: HOLD $0 dead-still in red (~0.95s emphasis)

BG = (7, 7, 15)
ACCENT_1 = (91, 138, 245)
ACCENT_2 = (56, 189, 248)        # cyan
HIGHLIGHT = (255, 230, 120)      # gold flash on landing
GREEN = (74, 222, 128)           # tailwind green-400
RED = (239, 68, 68)              # tailwind red-500
TEXT = (238, 238, 255)
MUTED = (160, 160, 190)


def inter(size, weight='Black'):
    f = ImageFont.truetype(FONT_PATH, size)
    try:
        f.set_variation_by_name(weight)
    except Exception:
        pass
    return f


def ease_out_cubic(t):
    return 1 - (1 - t) ** 3


def ease_in_cubic(t):
    return t ** 3


def lerp(a, b, t):
    return a + (b - a) * t


def lerp_color(c1, c2, t):
    t = max(0.0, min(1.0, t))
    return tuple(int(lerp(c1[i], c2[i], t)) for i in range(3))


def render_background():
    """Single static background image (rings + glow). Same as total card."""
    SS = 2
    sw, sh = W * SS, H * SS
    img = Image.new('RGBA', (sw, sh), (*BG, 255))
    cx, cy = sw // 2, sh // 2

    glow = Image.new('RGBA', (sw, sh), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    base_r = int(sw * 0.32)
    for i in range(8, 0, -1):
        r = int(base_r * i / 8)
        alpha = int(40 * (i / 8) ** 2)
        c = tuple(int(ACCENT_1[k] + (ACCENT_2[k] - ACCENT_1[k]) * (i / 8)) for k in range(3))
        gd.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(*c, alpha))
    glow = glow.filter(ImageFilter.GaussianBlur(radius=sw * 0.02))
    img = Image.alpha_composite(img, glow)

    rings = Image.new('RGBA', (sw, sh), (0, 0, 0, 0))
    rd = ImageDraw.Draw(rings)
    line_w = max(2, int(sw * 0.003))
    for frac, alpha in [(0.16, 200), (0.26, 160), (0.38, 120),
                         (0.52, 80), (0.68, 50), (0.86, 25)]:
        r = int(sw * frac)
        c = tuple(int(ACCENT_1[k] + (ACCENT_2[k] - ACCENT_1[k]) * frac) for k in range(3))
        rd.ellipse([cx - r, cy - r, cx + r, cy + r],
                   outline=(*c, alpha), width=line_w)
    img = Image.alpha_composite(img, rings)
    return img.resize((W, H), Image.LANCZOS)


def render_frame(bg, value, color, scale=1.0):
    """Just the $value, centered and huge. Captions carry the explanation."""
    img = bg.copy()
    draw = ImageDraw.Draw(img)

    amount_size = int(420 * scale)
    amount_font = inter(amount_size, weight='Black')
    amount = f"${value}"

    ab = draw.textbbox((0, 0), amount, font=amount_font)
    aw, ah = ab[2] - ab[0], ab[3] - ab[1]
    top = (H - ah) // 2
    ax = (W - aw) // 2 - ab[0]
    draw.text((ax, top - ab[1]), amount, font=amount_font, fill=(*color, 255))

    return img


def main():
    bg = render_background()
    n_frames = int(DURATION * FPS)

    tmp = tempfile.mkdtemp(prefix='ripple_counter_')
    try:
        for i in range(n_frames):
            t = i / FPS

            if t < T_ROLL_END:
                # Phase 1 — roll up 0 → 40 in cyan
                p = ease_out_cubic(t / T_ROLL_END)
                value = int(round(p * 40))
                color = ACCENT_2
                scale = 1.0

            elif t < T_PULSE_END:
                # Phase 2 — gold landing pulse w/ tiny bounce
                p = (t - T_ROLL_END) / (T_PULSE_END - T_ROLL_END)
                value = 40
                color = lerp_color(HIGHLIGHT, ACCENT_2, p)
                scale = 1.0 + 0.05 * (1 - p)

            elif t < T_GREEN_END:
                # Phase 3 — fade cyan → green
                p = (t - T_PULSE_END) / (T_GREEN_END - T_PULSE_END)
                value = 40
                color = lerp_color(ACCENT_2, GREEN, p)
                scale = 1.0

            elif t < T_DROP_START:
                # Phase 4 — hold $40 in green ("If I were anyone's affiliate.")
                value = 40
                color = GREEN
                scale = 1.0

            elif t < T_DROP_END:
                # Phase 5 — SLOW deflate 40 → 0 (0.70s). Linear decrement so
                # the integer ticks visibly through every value, not blowing
                # through 35-30-20-10 unseen. Color slides green → red.
                p = (t - T_DROP_START) / (T_DROP_END - T_DROP_START)
                value = int(round(40 * (1 - p)))
                color = lerp_color(GREEN, RED, p)
                scale = 1.0 - 0.03 * p

            elif t < T_SHAKE_END:
                # Phase 6 — landing shake. Tiny horizontal jitter on $0 to
                # punctuate the arrival. Color settled to red.
                value = 0
                color = RED
                rebound_t = (t - T_DROP_END) / (T_SHAKE_END - T_DROP_END)
                scale = 0.97 + 0.06 * (1 - rebound_t) * math.sin(rebound_t * 22)
                scale = max(0.92, scale)

            else:
                # Phase 7 — HOLD $0 dead-still. This is the emphasis beat.
                value = 0
                color = RED
                scale = 1.0

            frame = render_frame(bg, value, color, scale=scale)
            frame.convert('RGB').save(os.path.join(tmp, f"f_{i:04d}.png"), 'PNG')

        # Encode as MP4
        subprocess.run([
            'ffmpeg', '-y', '-loglevel', 'error',
            '-framerate', str(FPS),
            '-i', os.path.join(tmp, 'f_%04d.png'),
            '-c:v', 'libx264', '-preset', 'medium', '-crf', '18',
            '-pix_fmt', 'yuv420p',
            '-r', str(FPS),
            OUT,
        ], check=True)
        print(f"  wrote {OUT}  ({n_frames} frames, {DURATION}s @ {FPS}fps)")
    finally:
        shutil.rmtree(tmp)


if __name__ == '__main__':
    main()
