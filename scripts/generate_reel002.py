#!/usr/bin/env python3
"""
Reel 002 v2 — "A drop for every friend" (1080x1920, 30fps, 16s, loops)

Visual-first pass (v1 notes from Jake: electronic plink, banded water,
amateur animation, unnatural hook):
  - Water: per-pixel vertical gradient body (no bands), parallax wave layers,
    blurred crest glow, drifting underwater light blobs, bubbles
  - God rays from the top; deep navy→black background gradient
  - Sculpted teardrop droplet w/ radial glow + stretch, crown splash
  - Audio: physical waterdrop "bloop" (rising bubble pitch + soft noise tap)
    through a feedback-delay reverb; soft chord at the end. Zen, quiet.
  - Hook: "my friends don't buy anything without asking me first"
  - End card: total + "word of mouth, finally rewarded."
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

TEXT    = (240, 240, 255)
ACCENT  = (91, 138, 245)
ACCENT2 = (56, 189, 248)
GREEN   = (74, 222, 168)
DEEP    = (10, 22, 58)       # deepest water
SKY_TOP = (5, 5, 10)
SKY_BOT = (10, 14, 30)

_fc = {}
def F(size, weight="Bold"):
    if (size, weight) not in _fc:
        f = ImageFont.truetype(INTER, size)
        f.set_variation_by_name(weight)
        _fc[(size, weight)] = f
    return _fc[(size, weight)]

def ease_out(x): return 1 - (1 - x) ** 3
def clamp01(x): return max(0.0, min(1.0, x))
def lerp(a, b, p): return tuple(int(a[i] + (b[i] - a[i]) * p) for i in range(3))
def tsize(d, s, f):
    b = d.textbbox((0, 0), s, font=f); return b[2] - b[0], b[3] - b[1]

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
TOTAL = sum(c for _, _, c, _ in DROPS)
FALL = 0.55
LVL0, LVL1 = 0.16, 0.50

def level_at(t):
    done = sum(1 for tt, *_ in DROPS if t >= tt + 0.4)
    partial = 0.0
    for tt, *_ in DROPS:
        if tt <= t < tt + 0.4:
            partial = ease_out((t - tt) / 0.4)
    return LVL0 + (LVL1 - LVL0) * (done + partial) / len(DROPS)

def level_y(t): return H * (1 - level_at(t))
def total_at(t): return sum(c for tt, _, c, _ in DROPS if t >= tt)

# ── Prebuilt layers ──────────────────────────────────────────────────────────
def v_gradient(w, h, top, bottom):
    strip = Image.new("RGB", (1, h))
    px = strip.load()
    for y in range(h):
        px[0, y] = lerp(top, bottom, y / max(1, h - 1))
    return strip.resize((w, h))

BACKDROP = v_gradient(W, H, SKY_TOP, SKY_BOT)
WATER_GRAD = v_gradient(W, H, (40, 120, 200), DEEP)   # crest → deep, per-pixel

def build_rays():
    """Soft god rays fanning from above the frame."""
    L = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(L)
    cx = W * 0.5
    for ang, wdt, a in [(-0.30, 90, 60), (-0.12, 130, 80), (0.06, 100, 66),
                        (0.24, 150, 52), (0.40, 80, 46)]:
        x1 = cx + math.tan(ang) * H * 1.2
        d.polygon([(cx - wdt * 0.4, -200), (cx + wdt * 0.4, -200),
                   (x1 + wdt * 1.6, H + 100), (x1 - wdt * 1.6, H + 100)], fill=a)
    return L.filter(ImageFilter.GaussianBlur(60))

RAYS = build_rays()
RAYS_RGBA = Image.merge("RGBA", (*Image.new("RGB", (W, H), ACCENT2).split(), RAYS))

_vig = None
def vignette():
    global _vig
    if _vig is None:
        m = Image.new("L", (W, H), 0)
        ImageDraw.Draw(m).ellipse((-W*0.35, -H*0.25, W*1.35, H*1.25), fill=255)
        _vig = m.filter(ImageFilter.GaussianBlur(180)).point(lambda p: 255 - p)
    return _vig

# ── Water ────────────────────────────────────────────────────────────────────
def surface_pts(t, surf, amp, freq, speed, phase=0.0, step=6):
    pts = []
    for x in range(0, W + step, step):
        u = x / W
        y = surf + amp * math.sin(u * math.pi * freq + t * speed + phase) \
                 + amp * 0.4 * math.sin(u * math.pi * freq * 2.3 + t * speed * 1.7 + phase)
        pts.append((x, y))
    return pts

def draw_water(img, t, surf):
    # back parallax layers (translucent, slightly higher)
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ld = ImageDraw.Draw(layer)
    for off, amp, speed, phase, col in [(-26, 16, 0.9, 2.2, (*ACCENT, 60)),
                                        (-12, 13, 1.2, 1.1, (*ACCENT2, 55))]:
        pts = surface_pts(t, surf + off, amp, 2, speed, phase)
        ld.polygon([(0, H)] + pts + [(W, H)], fill=col)
    layer = layer.filter(ImageFilter.GaussianBlur(5))
    img.paste(layer, (0, 0), layer)

    # main body: per-pixel gradient masked by the front wave shape; gradient
    # is pinned to the surface so crest color always rides the waterline
    front = surface_pts(t, surf, 11, 2, 1.5)
    mask = Image.new("L", (W, H), 0)
    ImageDraw.Draw(mask).polygon([(0, H)] + front + [(W, H)], fill=255)
    shift = max(0, min(H - 2, int(surf * 0.85)))
    body = WATER_GRAD.crop((0, 0, W, H - shift)).resize((W, H))
    img.paste(body, (0, 0), mask)

    # drifting underwater light blobs (caustic feel)
    cl = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    cd = ImageDraw.Draw(cl)
    for i in range(3):
        bx = (0.2 + 0.3 * i) * W + math.sin(t * 0.35 + i * 2.1) * 130
        by = surf + 200 + 140 * i + math.sin(t * 0.5 + i) * 40
        r = 200 + 40 * i
        cd.ellipse((bx - r, by - r * 0.5, bx + r, by + r * 0.5),
                   fill=(120, 190, 255, 60))
    cl = cl.filter(ImageFilter.GaussianBlur(70))
    img.paste(cl, (0, 0), cl)

    # crest: soft luminous edge — the wave-shape mask minus itself shifted
    # down gives a thin surface band; blur it so nothing reads as a stroke
    shifted = Image.new("L", (W, H), 0)
    shifted.paste(mask, (0, 34))
    from PIL import ImageChops
    band = ImageChops.subtract(mask, shifted)
    edge = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    edge.paste(Image.new("RGBA", (W, H), (170, 225, 255, 190)), (0, 0), band)
    edge = edge.filter(ImageFilter.GaussianBlur(7))
    img.paste(edge, (0, 0), edge)
    # faint foam sparkles drifting along the surface
    d = ImageDraw.Draw(img, "RGBA")
    for i in range(14):
        u = ((i * 79.3 + t * 14) % 100) / 100
        fx = u * W
        fy = surf + 11 * math.sin(u * math.pi * 2 + t * 1.5)              + 11 * 0.4 * math.sin(u * math.pi * 4.6 + t * 2.55) - 3
        a = int(90 + 70 * math.sin(t * 2.0 + i * 1.3))
        rr = 1.6 + (i % 3) * 0.7
        d.ellipse((fx - rr, fy - rr, fx + rr, fy + rr),
                  fill=(225, 245, 255, max(0, a)))

    # bubbles
    for i in range(8):
        seed = i * 1.7 + 1
        cyc = 5.0 + (i % 3)
        ph = (t / cyc + seed * 0.37) % 1.0
        bx = ((seed * 137.5) % 1.0) * W * 0.9 + W * 0.05 + math.sin(t * 1.1 + seed) * 9
        depth = H - surf
        if depth < 80: continue
        by = H - ph * (depth - 40)
        r = 2 + (i % 3)
        d.ellipse((bx - r, by - r, bx + r, by + r),
                  fill=(220, 240, 255, int(60 * (1 - ph))))

# ── Droplet ──────────────────────────────────────────────────────────────────
def radial_glow(d, x, y, base_r, color, steps=5, a0=70):
    for k in range(steps, 0, -1):
        rr = base_r * (1 + k * 0.55)
        d.ellipse((x - rr, y - rr, x + rr, y + rr),
                  fill=(*color, int(a0 / (k + 1))))

def draw_drops(d, t):
    for tt, _, _, xf in DROPS:
        x = xf * W
        if tt - FALL <= t < tt:
            p = (t - (tt - FALL)) / FALL
            y = -90 + (level_y(t) + 90) * (p * p)
            stretch = 1.0 + 0.6 * p                      # elongate as it speeds
            r = 19
            radial_glow(d, x, y, r, ACCENT2)
            d.ellipse((x - r, y - r * stretch, x + r, y + r),
                      fill=(120, 205, 255, 255))
            for k in range(4):                            # tapering tail
                ty = y - r * stretch - k * 12
                tr = r * (0.55 - k * 0.12)
                if tr <= 1: break
                d.ellipse((x - tr, ty - tr, x + tr, ty + tr),
                          fill=(120, 205, 255, int(220 - k * 50)))
            d.ellipse((x - r * 0.45, y - r * 0.75, x - r * 0.02, y - r * 0.18),
                      fill=(255, 255, 255, 170))         # specular
        if tt <= t < tt + 1.0:
            p = (t - tt) / 1.0
            sy = level_y(t)
            # impact light bloom on the water
            if p < 0.5:
                ba = int(90 * (1 - p / 0.5))
                radial_glow(d, x, sy, 26, (170, 225, 255), steps=4, a0=ba)
            # soft expanding rings: filled bands on a tile, blurred (no strokes)
            tile_w, tile_h = 560, 200
            tile = Image.new("RGBA", (tile_w, tile_h), (0, 0, 0, 0))
            td = ImageDraw.Draw(tile)
            cx0, cy0 = tile_w // 2, tile_h // 2
            for k in range(2):
                rp = clamp01(p * 1.3 - k * 0.22)
                if rp <= 0: continue
                rw = 26 + 180 * ease_out(rp)
                a = int(120 * (1 - rp))
                td.ellipse((cx0 - rw, cy0 - rw * 0.20, cx0 + rw, cy0 + rw * 0.20),
                           fill=(190, 232, 255, a))
                inner = rw * 0.72
                td.ellipse((cx0 - inner, cy0 - inner * 0.20,
                            cx0 + inner, cy0 + inner * 0.20),
                           fill=(0, 0, 0, 0))
            tile = tile.filter(ImageFilter.GaussianBlur(5))
            d._image.paste(tile, (int(x - tile_w / 2), int(sy - tile_h / 2)), tile)
            if p < 0.35:                                  # crown splash
                pr = ease_out(p / 0.35)
                for k in range(7):
                    ang = math.pi * (0.15 + 0.7 * k / 6)
                    px = x + math.cos(ang) * 60 * pr * (1 if k % 2 else -1)
                    py = sy - abs(math.sin(ang)) * 85 * pr * (1 - p * 1.6)
                    rr = 5 - 3 * pr
                    d.ellipse((px - rr, py - rr, px + rr, py + rr),
                              fill=(200, 235, 255, int(220 * (1 - pr))))

def draw_labels(d, t):
    for tt, label, cents, xf in DROPS:
        if not (tt <= t < tt + 1.7): continue
        p = (t - tt) / 1.7
        a = int(255 * min(1, p * 5) * (1 - clamp01((p - 0.72) / 0.28)))
        rise = 30 * ease_out(min(1, p * 2))
        sy = level_y(tt) - 300 - rise
        cxx = min(max(xf * W, 150), W - 150)
        s1, s2 = f"+${cents/100:.2f}", label
        f1, f2 = F(52, "Black"), F(31, "Medium")
        w1, w2 = tsize(d, s1, f1)[0], tsize(d, s2, f2)[0]
        d.text((cxx - w1/2 + 2, sy + 2), s1, font=f1, fill=(0, 0, 0, a))
        d.text((cxx - w1/2, sy), s1, font=f1, fill=(*GREEN, a))
        d.text((cxx - w2/2, sy + 62), s2, font=f2, fill=(*TEXT, int(a * 0.85)))

def draw_counter(d, t):
    if t < DROPS[0][0]: return
    bump = 0.0
    for tt, *_ in DROPS:
        if 0 <= t - tt < 0.3:
            bump = (1 - (t - tt) / 0.3) * 0.16
    f = F(int(44 * (1 + bump)), "Black")
    s = f"${total_at(t)/100:.2f}"
    tw = tsize(d, s, f)[0]
    d.rounded_rectangle((W - tw - 122, 64, W - 48, 142), radius=24, fill=(10, 12, 20, 200))
    d.rounded_rectangle((W - tw - 122, 64, W - 48, 142), radius=24,
                        outline=(*ACCENT2, 110), width=2)
    d.text((W - tw - 86, 80), s, font=f, fill=(*GREEN, 255))

def glow_text(img, s, font, center, color, alpha=255):
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    tw, th = tsize(d, s, font)
    d.text((center[0] - tw/2, center[1] - th/2), s, font=font, fill=(*color, alpha))
    for L in (layer.filter(ImageFilter.GaussianBlur(26)),
              layer.filter(ImageFilter.GaussianBlur(8)), layer):
        img.paste(L, (0, 0), L)

def post(img):
    img.paste(Image.new("RGB", (W, H), (0, 0, 0)), (0, 0),
              vignette().point(lambda p: int(p * 0.5)))
    noise = Image.effect_noise((W // 2, H // 2), 12).resize((W, H))
    return Image.composite(img, Image.merge("RGB", (noise,)*3),
                           Image.new("L", (W, H), 245))

# ── Render ───────────────────────────────────────────────────────────────────
HOOK = ["my friends don't buy anything", "without asking me first"]

def render():
    os.makedirs(FRAMES, exist_ok=True)
    random.seed(7)
    for fi in range(N):
        t = fi / FPS
        img = BACKDROP.copy()
        # god rays, slowly breathing
        ra = RAYS_RGBA.copy()
        a = ra.getchannel("A").point(lambda v: int(v * (0.5 + 0.2 * math.sin(t * 0.5))))
        ra.putalpha(a)
        img.paste(ra, (int(math.sin(t * 0.18) * 30), 0), ra)

        surf = level_y(t)
        draw_water(img, t, surf)
        d = ImageDraw.Draw(img, "RGBA")
        draw_drops(d, t)
        draw_labels(d, t)
        draw_counter(d, t)

        if t < 3.4:
            fade = 1 - clamp01((t - 2.8) / 0.6)
            ap = int(235 * fade)
            y = 320
            f = F(50, "Black")
            for ln in HOOK:
                tw = tsize(d, ln, f)[0]
                d.rounded_rectangle((W/2 - tw/2 - 30, y - 12, W/2 + tw/2 + 30, y + 66),
                                    radius=22, fill=(10, 11, 17, ap))
                d.text((W/2 - tw/2, y), ln, font=f, fill=(*TEXT, int(255 * fade)))
                y += 96
        if t >= 11.4:
            p = ease_out(clamp01((t - 11.4) / 0.6))
            glow_text(img, f"${TOTAL/100:.2f}", F(150, "Black"), (W/2, 500),
                      GREEN, int(255 * p))
            d = ImageDraw.Draw(img, "RGBA")
            a2 = int(255 * ease_out(clamp01((t - 12.0) / 0.5)))
            s = "word of mouth, finally rewarded."
            f = F(48, "Bold")
            tw = tsize(d, s, f)[0]
            d.text((W/2 - tw/2, 690), s, font=f, fill=(*TEXT, a2))
            if t >= 12.6:
                glow_text(img, "ripple", F(54, "Black"), (W/2, 830), ACCENT,
                          int(255 * ease_out(clamp01((t - 12.6) / 0.5))))
        post(img).save(os.path.join(FRAMES, f"{fi:04d}.png"))
        if fi % 120 == 0: print(f"  {fi}/{N}")
    print(f"✓ {N} frames")

# ── Audio: physical waterdrop bloops + reverb ────────────────────────────────
def render_audio():
    sr = 44100
    buf = [0.0] * int(DUR * sr)
    def add(t0, samples):
        i0 = int(t0 * sr)
        for j, v in enumerate(samples):
            if i0 + j < len(buf): buf[i0 + j] += v
    def bloop(f0):
        """Kitchen-sink plop: low thump + filtered noise splash + a VERY short
        rising bubble chirp. Length is what reads as 'space' — keep it tight."""
        n = int(0.11 * sr)
        out = [0.0] * n
        # low water thump
        for i in range(int(0.045 * sr)):
            tt = i / sr
            out[i] += math.sin(2 * math.pi * 165 * tt) * 0.5 * math.exp(-tt * 70)
        # band-limited noise splash (differenced noise ≈ high-pass, then smooth)
        prev_n, lp = 0.0, 0.0
        for i in range(int(0.05 * sr)):
            tt = i / sr
            rn = random.uniform(-1, 1)
            hp = rn - prev_n; prev_n = rn
            lp += 0.25 * (hp - lp)
            out[i] += lp * 1.4 * math.exp(-tt * 90)
        # short rising bubble chirp (the 'plip'), ~45ms only
        phase = 0.0
        for i in range(int(0.045 * sr)):
            tt = i / sr
            f = f0 * (0.8 + 1.1 * (1 - math.exp(-tt * 60)))
            phase += 2 * math.pi * f / sr
            out[i + int(0.008 * sr)] += math.sin(phase) * 0.38 * math.exp(-tt * 48)
        return out
    def chord():
        n = int(2.4 * sr)
        out = []
        for i in range(n):
            tt = i / sr
            v = 0.0
            for k, fq in enumerate([392.0, 523.25, 659.25]):   # G–C–E, soft
                if tt >= k * 0.12:
                    t2 = tt - k * 0.12
                    v += math.sin(2 * math.pi * fq * t2) * 0.16 * math.exp(-t2 * 1.8)
            out.append(v)
        return out
    random.seed(3)
    for k, (tt, *_ ) in enumerate(DROPS):
        add(tt, bloop(420 + k * 22 + random.uniform(-20, 20)))  # subtle rise, natural variance
    add(11.4, chord())
    # simple feedback-delay reverb → roomy, zen
    for delay_s, g in [(0.047, 0.22), (0.067, 0.16), (0.097, 0.11)]:
        ds = int(delay_s * sr)
        for i in range(ds, len(buf)):
            buf[i] += buf[i - ds] * g
    peak = max(abs(v) for v in buf) or 1
    with wave.open(AUDIO, "w") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(sr)
        w.writeframes(b"".join(struct.pack("<h", int(v / peak * 26000)) for v in buf))
    print(f"✓ audio bed → {AUDIO}")

if __name__ == "__main__":
    render_audio()
    render()
