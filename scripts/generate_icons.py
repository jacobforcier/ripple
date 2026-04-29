#!/usr/bin/env python3
"""Generate Ripple icons at every size needed for the app and extensions."""

from PIL import Image, ImageDraw, ImageFilter
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

    print('Extension toolbar icons:')
    for size in [16, 48, 128]:
        write_resized(light, f'{base}/extension/icons/icon{size}.png', size)
        write_resized(light, f'{base}/Ripple/Shared (Extension)/Resources/icons/icon{size}.png', size)

    print('\nDone.')

if __name__ == '__main__':
    main()
