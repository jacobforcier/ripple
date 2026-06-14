#!/usr/bin/env python3
"""Generate static cards + overlays for the Ripple short-form video.

Outputs go to `marketing/cards/` as 1080×1920 PNGs (9:16, Reels/Shorts).
Brand styling matches sharewithripple.com (rings, Inter, accent colors).

Run from repo root: `python3 scripts/generate_video_assets.py`
"""

from PIL import Image, ImageDraw, ImageFilter, ImageFont
import os

# ── Brand (matches generate_icons.py + the website) ──────────────────────────
BG_COLOR = (7, 7, 15)
ACCENT_1 = (91, 138, 245)
ACCENT_2 = (56, 189, 248)
TEXT     = (238, 238, 255)
MUTED    = (160, 160, 190)
STAMP_RED = (220, 60, 70)
STAMP_GREEN = (52, 197, 122)   # earned-stamp green — bold, readable on dark bg

W, H = 1080, 1920
SS = 2                     # supersample factor — keep modest, these are bulk renders

FONT_PATH = os.path.join(
    os.path.dirname(os.path.abspath(__file__)), 'fonts', 'Inter-wght.ttf'
)

OUT_DIR = os.path.join(
    os.path.dirname(os.path.abspath(__file__)), '..', 'marketing', 'cards'
)


def inter(size, weight='Regular'):
    font = ImageFont.truetype(FONT_PATH, size)
    try:
        font.set_variation_by_name(weight)
    except (OSError, ValueError, AttributeError):
        pass
    return font


def inter_fit(text, *, weight='Regular', max_width, start_size=160, min_size=40):
    """Largest Inter size at `weight` where `text` fits inside `max_width`."""
    size = start_size
    while size > min_size:
        f = inter(size, weight=weight)
        bb = f.getbbox(text)
        if (bb[2] - bb[0]) <= max_width:
            return f
        size -= 4
    return inter(min_size, weight=weight)


def lerp(c1, c2, t):
    t = max(0.0, min(1.0, t))
    return tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(3))


def draw_background(*, with_rings=True, ring_intensity=1.0):
    """Brand background — dark base + (optional) concentric rings centered."""
    sw, sh = W * SS, H * SS
    img = Image.new('RGBA', (sw, sh), (*BG_COLOR, 255))
    cx, cy = sw // 2, sh // 2

    # Soft center glow
    glow = Image.new('RGBA', (sw, sh), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    base_r = int(sw * 0.32)
    for i in range(8, 0, -1):
        r = int(base_r * i / 8)
        alpha = int(40 * (i / 8) ** 2 * ring_intensity)
        color = lerp(ACCENT_1, ACCENT_2, i / 8)
        gd.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(*color, alpha))
    glow = glow.filter(ImageFilter.GaussianBlur(radius=sw * 0.02))
    img = Image.alpha_composite(img, glow)

    if with_rings:
        rings = Image.new('RGBA', (sw, sh), (0, 0, 0, 0))
        rd = ImageDraw.Draw(rings)
        line_w = max(2, int(sw * 0.003))
        # Vertical canvas — rings sized to width so they extend off-canvas
        # top/bottom, giving a subtle "expanding" frame around the content.
        ring_defs = [
            (0.16, 200), (0.26, 160), (0.38, 120),
            (0.52, 80),  (0.68, 50),  (0.86, 25),
        ]
        for frac, alpha in ring_defs:
            r = int(sw * frac)
            color = lerp(ACCENT_1, ACCENT_2, frac)
            a = int(alpha * ring_intensity)
            rd.ellipse([cx - r, cy - r, cx + r, cy + r],
                       outline=(*color, a), width=line_w)
        img = Image.alpha_composite(img, rings)

    img = img.resize((W, H), Image.LANCZOS)
    return img


def center_text_block(draw, lines, *, top_y, fonts, fills, line_gap=20):
    """Draw a centered, multi-line text block. Returns the bottom-y."""
    y = top_y
    for line, font, fill in zip(lines, fonts, fills):
        bb = draw.textbbox((0, 0), line, font=font)
        w = bb[2] - bb[0]
        x = (W - w) // 2 - bb[0]
        draw.text((x, y - bb[1]), line, font=font, fill=fill)
        y += (bb[3] - bb[1]) + line_gap
    return y - line_gap


# ── Card builders ────────────────────────────────────────────────────────────

def hook_card():
    """Punchy thesis statement that pairs with the captions, doesn't duplicate.

    Just three words, big and centered. The captions will say the rest of the
    VO line — the card itself is the visual anchor.
    """
    img = draw_background()
    draw = ImageDraw.Draw(img)

    line = "Stuff I shared."
    font = inter_fit(line, weight='Black', max_width=W - 160, start_size=240)
    bb = draw.textbbox((0, 0), line, font=font)
    w, h = bb[2] - bb[0], bb[3] - bb[1]
    x = (W - w) // 2 - bb[0]
    y = (H - h) // 2 - bb[1]
    draw.text((x, y), line, font=font, fill=(*ACCENT_2, 255))
    return img


def product_card(product_name, story_line=None):
    """Per-product card: just the product name, centered, BIG.

    The story line used to render here but it overlapped with the burned-in
    captions saying essentially the same thing — splitting the viewer's eye
    between two reading jobs. Captions carry the narrative now; the card
    just brands the product visually.
    """
    img = draw_background(ring_intensity=0.85)
    draw = ImageDraw.Draw(img)

    # Bigger now that the story line is gone.
    name_font = inter_fit(product_name, weight='ExtraBold',
                          max_width=W - 160, start_size=240)

    nb = draw.textbbox((0, 0), product_name, font=name_font)
    nw, nh = nb[2] - nb[0], nb[3] - nb[1]
    top = (H - nh) // 2
    nx = (W - nw) // 2 - nb[0]
    draw.text((nx, top - nb[1]), product_name, font=name_font, fill=(*ACCENT_2, 255))

    return img


def earned_stamp(amount):
    """Green '+$X EARNED' stamp — slams onto the product card.

    Smaller than the $0 EARNED stamp; lives in the lower portion of the
    product slot. Same hand-stamped rotation feel.
    """
    text = f"+${amount} EARNED"
    font_size = 80
    stamp_font = inter(font_size, weight='Black')
    tmp = Image.new('RGBA', (10, 10), (0, 0, 0, 0))
    bb = ImageDraw.Draw(tmp).textbbox((0, 0), text, font=stamp_font)
    tw_, th_ = bb[2] - bb[0], bb[3] - bb[1]

    pad_x, pad_y = 36, 26
    border_w = 6
    sw = tw_ + 2 * pad_x + 2 * border_w
    sh = th_ + 2 * pad_y + 2 * border_w

    img = Image.new('RGBA', (sw, sh), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    draw.rectangle(
        [border_w // 2, border_w // 2, sw - border_w // 2, sh - border_w // 2],
        outline=(*STAMP_GREEN, 255), width=border_w,
    )
    inner = border_w + 10
    draw.rectangle(
        [inner, inner, sw - inner, sh - inner],
        outline=(*STAMP_GREEN, 255), width=2,
    )

    tx = (sw - tw_) // 2 - bb[0]
    ty = (sh - th_) // 2 - bb[1]
    draw.text((tx, ty), text, font=stamp_font, fill=(*STAMP_GREEN, 255))

    img = img.rotate(-7, resample=Image.BICUBIC, expand=True)
    return img


def zero_stamp():
    """Transparent PNG: angled '$0 EARNED' stamp. Overlaid on product clips."""
    text = "$0 EARNED"
    # Pick stamp font size, then size canvas to fit with breathing room.
    font_size = 200
    stamp_font = inter(font_size, weight='Black')
    tmp = Image.new('RGBA', (10, 10), (0, 0, 0, 0))
    bb = ImageDraw.Draw(tmp).textbbox((0, 0), text, font=stamp_font)
    tw_, th_ = bb[2] - bb[0], bb[3] - bb[1]

    pad_x, pad_y = 70, 50
    border_w = 10
    sw = tw_ + 2 * pad_x + 2 * border_w
    sh = th_ + 2 * pad_y + 2 * border_w

    img = Image.new('RGBA', (sw, sh), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Double-stroke border box
    draw.rectangle(
        [border_w // 2, border_w // 2, sw - border_w // 2, sh - border_w // 2],
        outline=(*STAMP_RED, 255), width=border_w,
    )
    inner = border_w + 14
    draw.rectangle(
        [inner, inner, sw - inner, sh - inner],
        outline=(*STAMP_RED, 255), width=3,
    )

    tx = (sw - tw_) // 2 - bb[0]
    ty = (sh - th_) // 2 - bb[1]
    draw.text((tx, ty), text, font=stamp_font, fill=(*STAMP_RED, 255))

    # Rotate -8° for that hand-stamped feel
    img = img.rotate(-8, resample=Image.BICUBIC, expand=True)
    return img


def total_card():
    """Just the $40 dollar amount — captions deliver the rest of the line."""
    img = draw_background()
    draw = ImageDraw.Draw(img)

    amount_font = inter(420, weight='Black')
    amount = "$40"
    ab = draw.textbbox((0, 0), amount, font=amount_font)
    aw, ah = ab[2] - ab[0], ab[3] - ab[1]
    top = (H - ah) // 2
    ax = (W - aw) // 2 - ab[0]
    draw.text((ax, top - ab[1]), amount, font=amount_font, fill=(*ACCENT_2, 255))

    return img


def hero_card():
    """Big "ripple" wordmark — the hero shot for 'that's why I built Ripple'.

    Just the wordmark, even bigger than the outro. Brighter rings. No tagline
    or CTA — that's the outro's job at the end. This card is the punchline
    visual that lands as the music swells back.
    """
    img = draw_background(ring_intensity=1.3)
    draw = ImageDraw.Draw(img)

    wordmark_font = inter(380, weight='ExtraBold')
    wordmark = "ripple"
    wb = draw.textbbox((0, 0), wordmark, font=wordmark_font)
    ww, wh = wb[2] - wb[0], wb[3] - wb[1]
    wx = (W - ww) // 2 - wb[0]
    wy = (H - wh) // 2 - wb[1]
    draw.text((wx, wy), wordmark, font=wordmark_font, fill=(*ACCENT_2, 255))
    return img


def outro_card():
    """Final card: ripple wordmark, tagline, CTA."""
    img = draw_background(ring_intensity=0.5)
    draw = ImageDraw.Draw(img)

    wordmark_font = inter(280, weight='ExtraBold')
    tagline_font = inter(52, weight='Regular')
    cta_font = inter(48, weight='SemiBold')

    wordmark = "ripple"
    tagline = "Word of mouth, finally rewarded."
    cta = "Link in bio →"

    wb = draw.textbbox((0, 0), wordmark, font=wordmark_font)
    ww, wh = wb[2] - wb[0], wb[3] - wb[1]
    tb = draw.textbbox((0, 0), tagline, font=tagline_font)
    tw_, th_ = tb[2] - tb[0], tb[3] - tb[1]
    cb = draw.textbbox((0, 0), cta, font=cta_font)
    cw, ch = cb[2] - cb[0], cb[3] - cb[1]

    gap1, gap2 = 40, 140
    block_h = wh + gap1 + th_ + gap2 + ch
    top = (H - block_h) // 2

    wx = (W - ww) // 2 - wb[0]
    draw.text((wx, top - wb[1]), wordmark, font=wordmark_font, fill=(*ACCENT_2, 255))

    y = top + wh + gap1
    tx = (W - tw_) // 2 - tb[0]
    draw.text((tx, y - tb[1]), tagline, font=tagline_font, fill=(*TEXT, 255))

    y += th_ + gap2
    # Pill behind CTA — measure text and pad outward
    pad_x, pad_y = 70, 32
    pill_w = cw + 2 * pad_x
    pill_h = ch + 2 * pad_y
    pill_left = (W - pill_w) // 2
    pill_top = y - pad_y
    draw.rounded_rectangle(
        [pill_left, pill_top, pill_left + pill_w, pill_top + pill_h],
        radius=pill_h // 2,
        fill=(*ACCENT_1, 230),
        outline=(*ACCENT_2, 255),
        width=4,
    )
    tx = (W - cw) // 2 - cb[0]
    draw.text((tx, y - cb[1]), cta, font=cta_font, fill=(*TEXT, 255))

    return img


# ── Main ─────────────────────────────────────────────────────────────────────

def main():
    os.makedirs(OUT_DIR, exist_ok=True)

    cards = {
        '01_hook.png':    hook_card(),
        '02_flip7.png':   product_card("Flip 7", "Taught my coworkers at lunch. Six bought it that week."),
        '03_airfryer.png': product_card("Air fryer", "I wouldn't shut up about it. Three friends ordered one."),
        '04_owala.png':   product_card("Owala", "Got my whole family hooked. Five in one weekend."),
        '05_total.png':   total_card(),
        '05b_hero.png':   hero_card(),
        '06_outro.png':   outro_card(),
        'stamp_zero.png':  zero_stamp(),
        'stamp_5.png':     earned_stamp(5),
        'stamp_25.png':    earned_stamp(25),
        'stamp_10.png':    earned_stamp(10),
    }
    for name, img in cards.items():
        path = os.path.join(OUT_DIR, name)
        img.save(path, 'PNG')
        print(f"  wrote {path}  ({img.width}×{img.height})")

    print(f"\nDone. {len(cards)} assets in {OUT_DIR}/")


if __name__ == '__main__':
    main()
