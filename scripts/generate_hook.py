#!/usr/bin/env python3
"""Render the opening iMessage-bubble hook segment as an MP4.

A stylized iMessage conversation snippet pops in: an iMessage bubble that
reads "Here's a link to that airfryer", then a Ripple link-preview card slides
in beneath it. Lives in the first ~1.6s before the VO starts — its job is to
stop the scroll by showing exactly what Ripple does.

Output: marketing/cards/00_hook_imessage.mp4
"""

import os
import subprocess
import tempfile
import shutil
import math
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, '..', 'marketing', 'cards', '00_hook_imessage.mp4')
FONT_PATH = os.path.join(HERE, 'fonts', 'Inter-wght.ttf')

W, H = 1080, 1920
FPS = 30
DURATION = 1.6           # short — pattern interrupt, not a full beat

BG = (7, 7, 15)
ACCENT_1 = (91, 138, 245)
ACCENT_2 = (56, 189, 248)
IMSG_BLUE = (40, 132, 248)     # iMessage blue
TEXT = (255, 255, 255)
MUTED = (160, 160, 190)


def inter(size, weight='Regular'):
    f = ImageFont.truetype(FONT_PATH, size)
    try:
        f.set_variation_by_name(weight)
    except Exception:
        pass
    return f


def ease_out_back(t):
    """Overshoot-on-arrival easing for the bubble pop-in."""
    c1, c3 = 1.70158, 2.70158
    return 1 + c3 * (t - 1) ** 3 + c1 * (t - 1) ** 2


def ease_out_cubic(t):
    return 1 - (1 - t) ** 3


def draw_background():
    """Dark base — minimal, lets the bubble pop. No rings here."""
    img = Image.new('RGBA', (W, H), (*BG, 255))
    return img


def draw_imessage_bubble(canvas, scale, opacity, y_offset=0):
    """Composite an iMessage blue bubble onto canvas with scale & alpha.

    The bubble holds the text "Here's a link to that airfryer".
    Origin: right-aligned (sender's message style), upper-middle.
    """
    text = "Here's a link to that airfryer"
    font = inter(60, weight='SemiBold')

    # Measure
    tmp = ImageDraw.Draw(Image.new('RGBA', (10, 10)))
    bb = tmp.textbbox((0, 0), text, font=font)
    tw, th = bb[2] - bb[0], bb[3] - bb[1]

    pad_x, pad_y = 44, 32
    bubble_w = tw + 2 * pad_x
    bubble_h = th + 2 * pad_y

    # Render bubble layer at its natural size
    layer = Image.new('RGBA', (bubble_w + 80, bubble_h + 40), (0, 0, 0, 0))
    ld = ImageDraw.Draw(layer)
    radius = bubble_h // 2
    ld.rounded_rectangle(
        [40, 20, 40 + bubble_w, 20 + bubble_h],
        radius=radius,
        fill=(*IMSG_BLUE, 255),
    )
    # Tail (lower-right curl, schematic — a small triangle off the lower-right)
    tail = [
        (40 + bubble_w - 20, 20 + bubble_h - 4),
        (40 + bubble_w + 18, 20 + bubble_h + 6),
        (40 + bubble_w - 30, 20 + bubble_h - 24),
    ]
    ld.polygon(tail, fill=(*IMSG_BLUE, 255))

    # Text
    ld.text((40 + pad_x - bb[0], 20 + pad_y - bb[1]),
            text, font=font, fill=(*TEXT, 255))

    # Scale (around center) and adjust opacity
    if scale != 1.0:
        new_w = max(1, int(layer.width * scale))
        new_h = max(1, int(layer.height * scale))
        layer = layer.resize((new_w, new_h), Image.LANCZOS)
    if opacity < 1.0:
        a = layer.split()[3].point(lambda p: int(p * opacity))
        layer.putalpha(a)

    # Place on canvas — center horizontally, vertical y_offset from top of upper-third
    base_y = int(H * 0.32)
    cx = W // 2 - layer.width // 2
    cy = base_y - layer.height // 2 + y_offset

    canvas.alpha_composite(layer, (cx, cy))


def draw_link_preview_card(canvas, scale, opacity, y_offset=0):
    """A stylized Ripple link-preview card (the kind iMessage shows below a URL)."""
    card_w = 720
    card_h = 220

    layer = Image.new('RGBA', (card_w + 40, card_h + 40), (0, 0, 0, 0))
    ld = ImageDraw.Draw(layer)

    # Card with soft shadow
    ld.rounded_rectangle(
        [20, 20, 20 + card_w, 20 + card_h],
        radius=18,
        fill=(28, 28, 38, 255),
        outline=(60, 60, 80, 255),
        width=2,
    )

    # Thumbnail: tiny ripple logo on a darker patch
    thumb_w = 180
    ld.rounded_rectangle(
        [38, 38, 38 + thumb_w, 38 + card_h - 36],
        radius=12,
        fill=(*BG, 255),
    )
    # Mini rings
    cx, cy = 38 + thumb_w // 2, 38 + (card_h - 36) // 2
    for r, alpha in [(60, 220), (44, 180), (28, 140), (14, 100)]:
        ld.ellipse([cx - r, cy - r, cx + r, cy + r],
                   outline=(*ACCENT_2, alpha), width=3)

    # Right side: title + domain
    title_font = inter(38, weight='SemiBold')
    domain_font = inter(28, weight='Regular')
    title = "Ninja Air Fryer AF101"
    domain = "sharewithripple.com"
    ld.text((38 + thumb_w + 28, 60), title, font=title_font, fill=(*TEXT, 255))
    ld.text((38 + thumb_w + 28, 130), domain, font=domain_font, fill=(*MUTED, 255))

    # Scale + alpha
    if scale != 1.0:
        layer = layer.resize(
            (max(1, int(layer.width * scale)), max(1, int(layer.height * scale))),
            Image.LANCZOS,
        )
    if opacity < 1.0:
        a = layer.split()[3].point(lambda p: int(p * opacity))
        layer.putalpha(a)

    base_y = int(H * 0.55)
    cx = W // 2 - layer.width // 2
    cy = base_y - layer.height // 2 + y_offset
    canvas.alpha_composite(layer, (cx, cy))


def render_frame(t):
    """Compose one frame at time t (seconds, 0..DURATION)."""
    img = draw_background()

    # Phase 1 (0.00 - 0.45): bubble pops in with overshoot
    # Phase 2 (0.45 - 0.85): link-preview card slides up + fades in
    # Phase 3 (0.85 - 1.60): hold (slight settle, no motion)

    if t < 0.45:
        p = ease_out_back(t / 0.45)
        bubble_scale = 0.20 + 0.80 * p   # 0.2 → 1.0 with overshoot
        bubble_opacity = min(1.0, t / 0.20)
        draw_imessage_bubble(img, bubble_scale, bubble_opacity)
    else:
        draw_imessage_bubble(img, 1.0, 1.0)

    if t > 0.45:
        local = (t - 0.45) / 0.40
        local = max(0.0, min(1.0, local))
        p = ease_out_cubic(local)
        # Slide from y_offset=+40 → 0; opacity 0 → 1
        y_off = int(40 * (1 - p))
        opacity = p
        draw_link_preview_card(img, 1.0, opacity, y_offset=y_off)

    return img


def main():
    n_frames = int(DURATION * FPS)
    tmp = tempfile.mkdtemp(prefix='ripple_hook_')
    try:
        for i in range(n_frames):
            t = i / FPS
            frame = render_frame(t)
            frame.convert('RGB').save(os.path.join(tmp, f"f_{i:04d}.png"), 'PNG')

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
