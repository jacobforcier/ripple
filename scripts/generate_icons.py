#!/usr/bin/env python3
"""Generate Ripple icons at every size needed for the app and extensions."""

from PIL import Image, ImageDraw
import os
import sys

# ── Brand colors ─────────────────────────────────────────────────
ACCENT_1 = (91, 138, 245)   # #5b8af5
ACCENT_2 = (56, 189, 248)   # #38bdf8

# ── Master icon (1024×1024) ──────────────────────────────────────

def make_master(size: int, *, dark: bool = False, tinted: bool = False) -> Image.Image:
    """Render the Ripple master icon at the given size."""
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))

    # Diagonal gradient background using a bytearray for speed
    if tinted:
        # Mid-grey single color so the system tint can apply
        data = bytearray([128, 128, 128, 255] * size * size)
    else:
        c1 = ACCENT_1 if not dark else (40, 70, 150)
        c2 = ACCENT_2 if not dark else (20, 110, 165)
        data = bytearray()
        denom = max(1, 2 * (size - 1))
        for y in range(size):
            for x in range(size):
                t = (x + y) / denom
                data.extend([
                    int(c1[0] + (c2[0] - c1[0]) * t),
                    int(c1[1] + (c2[1] - c1[1]) * t),
                    int(c1[2] + (c2[2] - c1[2]) * t),
                    255,
                ])
    img.frombytes(bytes(data))

    # Draw ripple arcs — render on a 4× canvas then downsample for crisp edges
    SS = 4
    overlay = Image.new('RGBA', (size * SS, size * SS), (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)

    cx = size * SS / 2
    cy = size * SS * 0.78           # ripple origin slightly below center

    arcs = [
        (size * SS * 0.20, 235),    # (radius, alpha) — innermost is most opaque
        (size * SS * 0.36, 195),
        (size * SS * 0.54, 145),
        (size * SS * 0.74, 95),
    ]
    width = int(size * SS * 0.030)

    for radius, alpha in arcs:
        bbox = [cx - radius, cy - radius, cx + radius, cy + radius]
        draw.arc(bbox, start=200, end=340, fill=(255, 255, 255, alpha), width=width)

    overlay = overlay.resize((size, size), Image.LANCZOS)
    img = Image.alpha_composite(img, overlay)

    return img

# ── Output mapping ────────────────────────────────────────────────

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

    appicon = f'{base}/Ripple/Shared (App)/Assets.xcassets/AppIcon.appiconset'
    largeicon = f'{base}/Ripple/Shared (App)/Assets.xcassets/LargeIcon.imageset'

    # ── iOS 1024×1024 (light / dark / tinted) ────────────────────
    print('iOS 1024 variants:')
    write_resized(light,  f'{appicon}/icon-ios-light.png',  1024)
    write_resized(dark,   f'{appicon}/icon-ios-dark.png',   1024)
    write_resized(tinted, f'{appicon}/icon-ios-tinted.png', 1024)

    # ── macOS sizes ──────────────────────────────────────────────
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

    # ── In-app large icon ────────────────────────────────────────
    print('LargeIcon imageset:')
    write_resized(light, f'{largeicon}/icon.png',    256)
    write_resized(light, f'{largeicon}/icon@2x.png', 512)
    write_resized(light, f'{largeicon}/icon@3x.png', 768)

    # ── Extension toolbar icons (Chrome + Safari) ────────────────
    print('Extension toolbar icons:')
    for size in [16, 48, 128]:
        write_resized(light, f'{base}/extension/icons/icon{size}.png', size)
        write_resized(light, f'{base}/Ripple/Shared (Extension)/Resources/icons/icon{size}.png', size)

    print('\nDone.')

if __name__ == '__main__':
    main()
