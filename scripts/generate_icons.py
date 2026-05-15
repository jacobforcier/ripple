#!/usr/bin/env python3
"""Generate Ripple icons at every size needed for the app and extensions."""

from PIL import Image, ImageDraw, ImageFilter, ImageFont
import os
import math

# ── Brand colors (match sharewithripple.com) ──────────────────────
BG_COLOR   = (7, 7, 15)        # #07070f  — site background
ACCENT_1   = (91, 138, 245)    # #5b8af5  — blue
ACCENT_2   = (56, 189, 248)    # #38bdf8  — sky blue

# ── Master icon (1024×1024) ───────────────────────────────────────

def make_master(size: int, *, dark: bool = False, tinted: bool = False) -> Image.Image:
    """Concentric-ring icon on the dark site background."""
    SS = 4  # supersample factor
    W = size * SS

    # ── Background ────────────────────────────────────────────────
    if tinted:
        img = Image.new('RGBA', (size, size), (128, 128, 128, 255))
        # Tinted variant: grey bg + grey rings so system tint reads cleanly
        _draw_rings(img, size, ring_rgb=(200, 200, 200))
        return img

    bg = BG_COLOR if not dark else (5, 5, 12)
    img = Image.new('RGBA', (W, W), (*bg, 255))

    # ── Soft center glow ──────────────────────────────────────────
    glow = Image.new('RGBA', (W, W), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    cx = cy = W // 2
    glow_r = int(W * 0.28)
    # Four concentric filled circles, each step more transparent
    for i in range(8, 0, -1):
        r = int(glow_r * i / 8)
        alpha = int(55 * (i / 8) ** 2)   # quadratic fade
        color = _lerp_color(ACCENT_1, ACCENT_2, i / 8)
        gd.ellipse([cx - r, cy - r, cx + r, cy + r],
                   fill=(*color, alpha))
    glow = glow.filter(ImageFilter.GaussianBlur(radius=W * 0.04))
    img = Image.alpha_composite(img, glow)

    # ── Concentric rings ──────────────────────────────────────────
    # 5 rings, matching the site's expanding-rings motif
    ring_layer = Image.new('RGBA', (W, W), (0, 0, 0, 0))
    rd = ImageDraw.Draw(ring_layer)
    line_w = max(2, int(W * 0.018))

    ring_defs = [
        # (radius_fraction, alpha)  — innermost first
        (0.18, 210),
        (0.30, 170),
        (0.42, 130),
        (0.55, 90),
        (0.68, 55),
        (0.82, 28),
    ]
    for frac, alpha in ring_defs:
        r = int(W * frac)
        color = _lerp_color(ACCENT_1, ACCENT_2, frac)
        bbox = [cx - r, cy - r, cx + r, cy + r]
        rd.ellipse(bbox, outline=(*color, alpha), width=line_w)

    # Downsample for antialiasing
    ring_layer = ring_layer.resize((size, size), Image.LANCZOS)
    img = img.resize((size, size), Image.LANCZOS)
    img = Image.alpha_composite(img, ring_layer)

    return img


def _lerp_color(c1, c2, t):
    t = max(0.0, min(1.0, t))
    return tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(3))


# ── Launch screen logo (transparent rings, no canvas edge) ────────
# The app icon's outermost ring overshoots the 1024-pixel canvas — fine for
# the home-screen icon (rounded-square mask hides it) but UILaunchScreen
# renders the raw rectangle with no mask, so the clipped curves show. This
# variant: transparent background (no edge to clip against), rings sized so
# the outer ring sits well inside the canvas with breathing room. Pairs with
# the LaunchBackground color asset (#07070f).

def make_launch_logo(size: int) -> Image.Image:
    SS = 4
    W = size * SS
    img = Image.new('RGBA', (W, W), (0, 0, 0, 0))  # fully transparent

    cx = cy = W // 2

    # Soft center glow
    glow = Image.new('RGBA', (W, W), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    glow_r = int(W * 0.10)
    for i in range(8, 0, -1):
        r = int(glow_r * i / 8)
        alpha = int(45 * (i / 8) ** 2)
        color = _lerp_color(ACCENT_1, ACCENT_2, i / 8)
        gd.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(*color, alpha))
    glow = glow.filter(ImageFilter.GaussianBlur(radius=W * 0.025))
    img = Image.alpha_composite(img, glow)

    # 6 concentric rings — outer ring at 43% radius (= 86% diameter), so the
    # full ring fits inside the canvas with ~7% padding on every side.
    rings = Image.new('RGBA', (W, W), (0, 0, 0, 0))
    rd = ImageDraw.Draw(rings)
    line_w = max(2, int(W * 0.011))

    ring_defs = [
        # (radius_fraction_of_canvas, alpha)
        (0.08, 235),
        (0.16, 195),
        (0.24, 150),
        (0.32, 105),
        (0.39, 65),
        (0.45, 32),
    ]
    for frac, alpha in ring_defs:
        r = int(W * frac)
        color = _lerp_color(ACCENT_1, ACCENT_2, min(1.0, frac * 1.7))
        rd.ellipse([cx - r, cy - r, cx + r, cy + r],
                   outline=(*color, alpha), width=line_w)

    rings = rings.resize((size, size), Image.LANCZOS)
    img = img.resize((size, size), Image.LANCZOS)
    img = Image.alpha_composite(img, rings)

    return img


# ── Open Graph image (1200×630) ──────────────────────────────────
# Rendered into Ripple link bubbles in iMessage, X, Slack, etc.

def make_og_image() -> Image.Image:
    """Branded 1200×630 image: dark bg, concentric rings, wordmark + tagline."""
    W, H = 1200, 630
    SS = 4
    sw, sh = W * SS, H * SS

    img = Image.new('RGBA', (sw, sh), (*BG_COLOR, 255))

    # Centered glow + rings — circular, sized to the image height.
    cx, cy = sw // 2, sh // 2

    glow = Image.new('RGBA', (sw, sh), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    base_r = int(sh * 0.30)
    for i in range(8, 0, -1):
        r = int(base_r * i / 8)
        alpha = int(50 * (i / 8) ** 2)
        color = _lerp_color(ACCENT_1, ACCENT_2, i / 8)
        gd.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(*color, alpha))
    glow = glow.filter(ImageFilter.GaussianBlur(radius=sw * 0.015))
    img = Image.alpha_composite(img, glow)

    rings = Image.new('RGBA', (sw, sh), (0, 0, 0, 0))
    rd = ImageDraw.Draw(rings)
    line_w = max(2, int(sh * 0.006))
    ring_defs = [
        (0.10, 210), (0.18, 170), (0.28, 130),
        (0.40, 90),  (0.55, 55),  (0.72, 28),
    ]
    for frac, alpha in ring_defs:
        r = int(sh * frac)
        color = _lerp_color(ACCENT_1, ACCENT_2, frac)
        rd.ellipse([cx - r, cy - r, cx + r, cy + r],
                   outline=(*color, alpha), width=line_w)

    rings = rings.resize((W, H), Image.LANCZOS)
    img = img.resize((W, H), Image.LANCZOS)
    img = Image.alpha_composite(img, rings)

    # Text — wordmark + tagline, centered.
    draw = ImageDraw.Draw(img)
    wordmark_font = _load_font(180)
    tagline_font = _load_font(40)

    wordmark = "ripple"
    wb = draw.textbbox((0, 0), wordmark, font=wordmark_font)
    ww, wh = wb[2] - wb[0], wb[3] - wb[1]
    wx = (W - ww) // 2 - wb[0]
    wy = (H - wh) // 2 - wb[1] - 40
    draw.text((wx, wy), wordmark, font=wordmark_font, fill=(*ACCENT_2, 255))

    tagline = "Word of mouth, finally rewarded."
    tb = draw.textbbox((0, 0), tagline, font=tagline_font)
    tw_, th_ = tb[2] - tb[0], tb[3] - tb[1]
    tx = (W - tw_) // 2 - tb[0]
    ty = wy + wh + 30
    draw.text((tx, ty), tagline, font=tagline_font, fill=(200, 200, 220, 255))

    return img


def _load_font(size: int) -> ImageFont.FreeTypeFont:
    """Best-effort system font load with sensible fallbacks."""
    candidates = [
        "/System/Library/Fonts/HelveticaNeue.ttc",
        "/System/Library/Fonts/Helvetica.ttc",
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
    ]
    for path in candidates:
        try:
            return ImageFont.truetype(path, size)
        except (OSError, IOError):
            continue
    return ImageFont.load_default()


def _draw_rings(img: Image.Image, size: int, ring_rgb):
    """Draw rings directly on img (for tinted variant)."""
    SS = 4
    W = size * SS
    layer = Image.new('RGBA', (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    cx = cy = W // 2
    line_w = max(2, int(W * 0.018))
    fracs = [0.18, 0.30, 0.42, 0.55, 0.68, 0.82]
    alphas = [210, 170, 130, 90, 55, 28]
    for frac, alpha in zip(fracs, alphas):
        r = int(W * frac)
        bbox = [cx - r, cy - r, cx + r, cy + r]
        d.ellipse(bbox, outline=(*ring_rgb, alpha), width=line_w)
    layer = layer.resize((size, size), Image.LANCZOS)
    img.paste(Image.alpha_composite(img.convert('RGBA'), layer))


# ── Output helpers ────────────────────────────────────────────────

def write_resized(master: Image.Image, path: str, size: int):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if master.size != (size, size):
        master.resize((size, size), Image.LANCZOS).save(path, 'PNG')
    else:
        master.save(path, 'PNG')
    print(f'  {size:>4}px  {path}')


def main():
    base = '/Users/jacobforcier/Library/Mobile Documents/com~apple~CloudDocs/Ripple'

    print('Generating master icons...')
    light  = make_master(1024)
    dark   = make_master(1024, dark=True)
    tinted = make_master(1024, tinted=True)

    appicon   = f'{base}/Ripple/Shared (App)/Assets.xcassets/AppIcon.appiconset'
    largeicon = f'{base}/Ripple/Shared (App)/Assets.xcassets/LargeIcon.imageset'

    print('iOS 1024 variants:')
    write_resized(light,  f'{appicon}/icon-ios-light.png',  1024)
    write_resized(dark,   f'{appicon}/icon-ios-dark.png',   1024)
    write_resized(tinted, f'{appicon}/icon-ios-tinted.png', 1024)

    print('macOS sizes:')
    mac_sizes = [
        ('icon_16x16.png',     16),
        ('icon_16x16@2x.png',  32),
        ('icon_32x32.png',     32),
        ('icon_32x32@2x.png',  64),
        ('icon_128x128.png',   128),
        ('icon_128x128@2x.png',256),
        ('icon_256x256.png',   256),
        ('icon_256x256@2x.png',512),
        ('icon_512x512.png',   512),
        ('icon_512x512@2x.png',1024),
    ]
    for name, sz in mac_sizes:
        write_resized(light, f'{appicon}/{name}', sz)

    print('LargeIcon imageset:')
    write_resized(light, f'{largeicon}/icon.png',    256)
    write_resized(light, f'{largeicon}/icon@2x.png', 512)
    write_resized(light, f'{largeicon}/icon@3x.png', 768)

    # ── Container app in-app icon (referenced by Main.html) ──────
    print('Container app Icon.png:')
    write_resized(light, f'{base}/Ripple/Shared (App)/Resources/Icon.png', 512)

    # ── Launch screen logo (transparent rings) ───────────────────
    # Rendered on top of the LaunchBackground color asset (#07070f) by
    # UILaunchScreen in iOS (App)/Info.plist.
    print('Launch screen logo:')
    launch_set = f'{base}/Ripple/Shared (App)/Assets.xcassets/LaunchLogo.imageset'
    write_resized(make_launch_logo(200), f'{launch_set}/launch.png',    200)
    write_resized(make_launch_logo(400), f'{launch_set}/launch@2x.png', 400)
    write_resized(make_launch_logo(600), f'{launch_set}/launch@3x.png', 600)

    # ── Open Graph image (link previews in iMessage, X, Slack, …) ──
    print('Open Graph image:')
    og = make_og_image()
    og_path = f'{base}/og-image.png'
    og.save(og_path, 'PNG')
    print(f'  1200×630  {og_path}')

    print('Extension toolbar icons:')
    for size in [16, 48, 128]:
        write_resized(light, f'{base}/extension/icons/icon{size}.png', size)
        write_resized(light, f'{base}/Ripple/Shared (Extension)/Resources/icons/icon{size}.png', size)

    print('\nDone.')

if __name__ == '__main__':
    main()
