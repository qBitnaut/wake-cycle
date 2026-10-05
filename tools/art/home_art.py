#!/usr/bin/env python3
"""Pixel art for the Home ending: the morning after the storm.

Everything here is drawn by code at 1x for the 640x360 view (the same pixel
density as the 32 px tiles and the ansimuz layers), in a warm day palette
kept in the Wake Cycle family: navy-plum ink for the nearest outlines, hue
shifted ramps (shadows lean violet-blue, lights lean warm yellow), and the
reserved power hues left alone (no glowing blue, green, cyan or violet).

The sun is low on the right (morning, ahead of the cat), so lit edges face
right and up, and cast shadows fall down and to the left.

No generative art and no source pack: shapes, ramps and noise only.

Usage: home_art.py [out_dir]   (default: assets/art_hd/home)
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parent

# ---- palette ---------------------------------------------------------------

INK = "#2a2238"        # day ink: the night INK (#161630) warmed and lifted
INK_SOFT = "#5a5068"   # outlines on light, far things

SKY = ["#3d7bcc", "#4a88d6", "#5a97de", "#6da6e4", "#82b5e9", "#99c4ec", "#b2d2ee", "#cadfee", "#dde8ea"]
SUN_HAZE = "#fbeed0"

CLOUD = ["#a9b2d2", "#c3cae1", "#dcdeea", "#efece9", "#fffaf0"]

HILL_FAR = ["#a8c4d6", "#b6cfdc"]
HILL_NEAR = ["#86aeb4", "#96bcbc", "#a9c9c2"]

LEAF = ["#22402f", "#2f5a3c", "#3f7346", "#578c4c", "#7aa955", "#a6c867", "#d8eb9a"]
LEAF_FAR = ["#5f8f80", "#6f9f88", "#85b294", "#a2c6a6"]
BARK = ["#2e2230", "#4a3328", "#6b4a35", "#8c6545", "#a9825a"]

CONCRETE = ["#7d7682", "#948c90", "#aaa29f", "#bfb7ae", "#d4cdc1", "#e7e1d3", "#f7f1e2"]
ASPHALT = ["#3b3d4c", "#45485a", "#505467", "#5b6074", "#697088"]

TRIM = ["#8d8a9e", "#bdbcc9", "#dedbe0", "#f2efe9", "#fffcf4"]

SAGE = ["#4f6b66", "#6a8a80", "#86a693", "#a2bea4", "#c4d8b8"]
BUTTER = ["#8f7556", "#b89a68", "#d8bb7c", "#ecd496", "#f8e8b6"]
DUSTY = ["#4f5f7c", "#66799a", "#8197b6", "#9fb3cc", "#c2d2e2"]
CREAM = ["#9a8a80", "#c0ae9c", "#dccbb4", "#efe2cc", "#fbf4e4"]
ROSE = ["#7a5058", "#9a6a72", "#b8888e", "#d2a6a8", "#ead0cc"]

TERRACOTTA = ["#5e2e34", "#7f3c3a", "#a24f43", "#c06a50", "#da8c66", "#f0b58a"]
SLATE = ["#373a52", "#474c68", "#5a6182", "#717a9c", "#8f99b8", "#b7c0d6"]
BRICK = ["#5a2c30", "#7c3a38", "#9c5040", "#ba6c50"]

GLASS = ["#33405e", "#4f6a92", "#7ea4cc", "#a9cbe8", "#e6f4ff"]
DOOR_BLUE = ["#2f3d5e", "#405482", "#56709e", "#7491b8", "#9fb9d6"]
DOOR_GREEN = ["#2f4a40", "#3f6252", "#527c66", "#6c9a7e"]

FLOWER = {"pink": ["#b85878", "#e8829c", "#ffb6c4"], "red": ["#9c3440", "#d8524e", "#f08a74"],
          "yellow": ["#b8902c", "#f0cc4a", "#fff09a"], "white": ["#b8b8c8", "#eceaf0", "#ffffff"],
          "peach": ["#c06a50", "#f0a070", "#ffd0a0"]}

# Interior: warm, a step darker than outside (indoor light), cosy.
WALLPAPER = ["#6e4a50", "#8a5f5c", "#a6776a", "#c09078", "#d8ab8c"]
WOOD = ["#3a2428", "#5a3830", "#7a5038", "#9a6a44", "#b88656", "#d4a46c"]
RUG = ["#5e2e40", "#8a3e4a", "#b25a54", "#d07c5c", "#e8a676"]
CUSHION = ["#6e5a8a", "#8a74a8", "#a690c0", "#c4b0d8"]  # dusty heather, warm enough to read as fabric, never IMPACT violet
FABRIC_GOLD = ["#8a6030", "#b88440", "#dcaa58", "#f0cc7c"]

B4 = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]], float) / 16.0


def rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def mixc(a, b, t):
    a, b = rgb(a), rgb(b)
    return "#%02x%02x%02x" % tuple(round(x + (y - x) * t) for x, y in zip(a, b))


# ---- canvas ----------------------------------------------------------------

class Canvas:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.a = np.zeros((h, w, 4), np.uint8)

    # Plain drawing ----------------------------------------------------------
    def px(self, x, y, col, alpha=255):
        if 0 <= x < self.w and 0 <= y < self.h:
            self.a[y, x] = (*rgb(col), alpha)

    def rect(self, x, y, w, h, col, alpha=255):
        x0, y0 = max(int(x), 0), max(int(y), 0)
        x1, y1 = min(int(x + w), self.w), min(int(y + h), self.h)
        if x1 > x0 and y1 > y0:
            self.a[y0:y1, x0:x1] = (*rgb(col), alpha)

    def hline(self, x0, x1, y, col):
        self.rect(x0, y, x1 - x0 + 1, 1, col)

    def vline(self, x, y0, y1, col):
        self.rect(x, y0, 1, y1 - y0 + 1, col)

    def mask_poly(self, pts):
        m = Image.new("L", (self.w, self.h), 0)
        ImageDraw.Draw(m).polygon([tuple(p) for p in pts], fill=255)
        return np.asarray(m) > 0

    def mask_ellipse(self, cx, cy, rx, ry):
        yy, xx = np.mgrid[0:self.h, 0:self.w]
        return ((xx + 0.5 - cx) / rx) ** 2 + ((yy + 0.5 - cy) / ry) ** 2 <= 1.0

    def fill(self, mask, col, alpha=255):
        self.a[mask] = (*rgb(col), alpha)

    def poly(self, pts, col):
        self.fill(self.mask_poly(pts), col)

    def ellipse(self, cx, cy, rx, ry, col):
        self.fill(self.mask_ellipse(cx, cy, rx, ry), col)

    def blit(self, other, x, y):
        src = other.a
        h, w = src.shape[:2]
        x0, y0 = max(x, 0), max(y, 0)
        x1, y1 = min(x + w, self.w), min(y + h, self.h)
        if x1 <= x0 or y1 <= y0:
            return
        s = src[y0 - y:y1 - y, x0 - x:x1 - x]
        d = self.a[y0:y1, x0:x1]
        sa = s[..., 3:4].astype(float) / 255.0
        d[..., :3] = (s[..., :3] * sa + d[..., :3] * (1 - sa)).astype(np.uint8)
        d[..., 3] = np.maximum(d[..., 3], s[..., 3])

    def opaque(self):
        return self.a[..., 3] > 0

    def outline(self, col, mask=None, diag=False):
        """1 px outline just outside the opaque pixels (or `mask`)."""
        m = self.opaque() if mask is None else mask
        n = np.zeros_like(m)
        n[1:, :] |= m[:-1, :]
        n[:-1, :] |= m[1:, :]
        n[:, 1:] |= m[:, :-1]
        n[:, :-1] |= m[:, 1:]
        if diag:
            n[1:, 1:] |= m[:-1, :-1]
            n[1:, :-1] |= m[:-1, 1:]
            n[:-1, 1:] |= m[1:, :-1]
            n[:-1, :-1] |= m[1:, 1:]
        edge = n & ~m
        self.fill(edge, col)
        return edge

    def save(self, path):
        Image.fromarray(self.a, "RGBA").save(path)


def quantize(field, ramp, mask, dither=0.35, ox=0, oy=0):
    """Map a 0..1 field onto a colour ramp with narrow ordered-dither seams.
    Returns an RGBA array for the masked pixels (others transparent)."""
    h, w = field.shape
    n = len(ramp)
    v = np.clip(field, 0.0, 1.0) * (n - 1)
    i = np.floor(v)
    f = v - i
    if dither > 0:
        # Only the middle of each seam dithers: bands stay flat, edges mesh.
        f = np.clip((f - 0.5) / max(dither, 1e-3) + 0.5, 0.0, 1.0)
    else:
        f = (f >= 0.5).astype(float)
    yy, xx = np.mgrid[0:h, 0:w]
    th = B4[(yy + oy) % 4, (xx + ox) % 4]
    idx = np.clip(i + (f > th), 0, n - 1).astype(int)
    lut = np.array([(*rgb(c), 255) for c in ramp], np.uint8)
    out = lut[idx]
    out[~mask] = 0
    return out


def value_noise(w, h, cell, seed, octaves=2):
    """Smooth value noise in 0..1, tileable horizontally when w % cell == 0."""
    rng = np.random.default_rng(seed)
    out = np.zeros((h, w))
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        c = max(int(cell / (2 ** o)), 1)
        gw, gh = w // c + 2, h // c + 2
        g = rng.random((gh, gw))
        if w % c == 0:
            g[:, w // c] = g[:, 0]
            g[:, w // c + 1] = g[:, 1]
        yy, xx = np.mgrid[0:h, 0:w]
        fx, fy = xx / c, yy / c
        x0, y0 = np.floor(fx).astype(int), np.floor(fy).astype(int)
        tx, ty = fx - x0, fy - y0
        tx, ty = tx * tx * (3 - 2 * tx), ty * ty * (3 - 2 * ty)
        a = g[y0, x0] * (1 - tx) + g[y0, x0 + 1] * tx
        b = g[y0 + 1, x0] * (1 - tx) + g[y0 + 1, x0 + 1] * tx
        out += (a * (1 - ty) + b * ty) * amp
        tot += amp
        amp *= 0.5
    return out / tot


SUN_DIR = np.array([0.62, -0.50, 0.60])   # x right, y down, z to the viewer
SUN_DIR = SUN_DIR / np.linalg.norm(SUN_DIR)


def blob_light(w, h, balls, light=SUN_DIR, wrap=False):
    """Union of spheres (cx, cy, r): returns (mask, lambert 0..1, rim 0..1).
    The topmost sphere at each pixel gives the normal."""
    yy, xx = np.mgrid[0:h, 0:w]
    best = np.full((h, w), -1e9)
    nx = np.zeros((h, w))
    ny = np.zeros((h, w))
    nz = np.zeros((h, w))
    for cx, cy, r in balls:
        for shift in ((-w, 0, w) if wrap else (0,)):
            dx = (xx + 0.5 - cx - shift) / r
            dy = (yy + 0.5 - cy) / r
            d2 = dx * dx + dy * dy
            inside = d2 <= 1.0
            z = np.sqrt(np.clip(1.0 - d2, 0.0, 1.0))
            height = z * r + cy * -0.0  # taller spheres win
            take = inside & (height > best)
            best[take] = height[take]
            nx[take], ny[take], nz[take] = dx[take], dy[take], z[take]
    mask = best > -1e8
    lam = np.clip(nx * light[0] + ny * light[1] + nz * light[2], 0.0, 1.0)
    rim = np.clip(nx * light[0] + ny * light[1], 0.0, 1.0) * (1.0 - nz)
    return mask, lam, rim


# ---- sky and distance --------------------------------------------------------

def sky(w=640, h=330):
    c = Canvas(w, h)
    yy, xx = np.mgrid[0:h, 0:w]
    t = (yy / (h * 0.92)) ** 1.15
    # Brighter and warmer towards the sun (upper right) and the horizon.
    sun = np.exp(-(((xx - 520) / 260.0) ** 2 + ((yy - 70) / 200.0) ** 2))
    t = np.clip(t + sun * 0.18, 0, 1)
    c.a = quantize(t, SKY, np.ones((h, w), bool), dither=0.45)
    # Warm haze low on the right, over the band near the horizon.
    haze = np.clip((yy - h * 0.62) / (h * 0.38), 0, 1) * (0.35 + 0.65 * np.clip(xx / w, 0, 1))
    hz = haze + (B4[yy % 4, xx % 4] - 0.5) * 0.3 > 0.55
    c.fill(hz, mixc(SKY[-1], SUN_HAZE, 0.55))
    hz2 = haze + (B4[yy % 4, xx % 4] - 0.5) * 0.3 > 0.85
    c.fill(hz2, SUN_HAZE)
    return c


def sun_disc(d=23):
    c = Canvas(d, d)
    r = d / 2.0
    c.ellipse(r, r, r, r, "#fff1c2")
    c.ellipse(r, r, r - 1.5, r - 1.5, "#fffbea")
    c.ellipse(r + 2, r - 2, r - 6, r - 6, "#ffffff")
    return c


def cloud(w, h, seed, flat=0.62):
    rng = np.random.default_rng(seed)
    balls = []
    n = max(int(w / 14), 4)
    base = h * flat
    for i in range(n):
        x = w * (0.12 + 0.76 * i / (n - 1)) + rng.uniform(-4, 4)
        mid = 1.0 - abs(i / (n - 1) - 0.5) * 2.0
        r = h * (0.22 + 0.30 * mid) * rng.uniform(0.85, 1.12)
        balls.append((x, base - r * 0.35, r))
    for _ in range(max(n // 2, 2)):
        x = rng.uniform(w * 0.3, w * 0.7)
        r = h * rng.uniform(0.28, 0.40)
        balls.append((x, base - r * 0.75, r))
    mask, lam, rim = blob_light(w, h, balls)
    yy, xx = np.mgrid[0:h, 0:w]
    mask &= yy < base + 2
    under = np.clip((yy - (base - h * 0.18)) / (h * 0.25), 0, 1)
    v = lam * 0.85 + rim * 0.35 - under * 0.45 + value_noise(w, h, 8, seed + 7, 2) * 0.12
    c = Canvas(w, h)
    c.a = quantize(np.clip(v, 0, 1), CLOUD, mask, dither=0.5)
    return c


def rainbow(w=420, h=230):
    """Faint arc: six 2 px bands, fading at both feet and at the crown."""
    c = Canvas(w, h)
    yy, xx = np.mgrid[0:h, 0:w]
    cx, cy = w / 2.0, h + 40.0
    d = np.sqrt((xx + 0.5 - cx) ** 2 + (yy + 0.5 - cy) ** 2)
    bands = ["#e86a6a", "#f0a060", "#f2dc78", "#8fcf86", "#7aa8e0", "#a48ad0"]
    r0 = 250.0
    fade = np.clip((h - yy) / 60.0, 0, 1) * np.clip(yy / 30.0 + 0.4, 0, 1)
    for i, col in enumerate(bands):
        m = (d >= r0 - (i + 1) * 3) & (d < r0 - i * 3)
        a = (fade * 255).astype(np.uint8)
        c.a[m, :3] = rgb(col)
        c.a[m, 3] = a[m]
    return c


def ridge(w, h, ramp, base, amps, seed, bumps=0.0):
    """A tileable ridge line: sum of sines with whole periods over w."""
    rng = np.random.default_rng(seed)
    x = np.arange(w)
    top = np.full(w, float(base))
    for k, a in amps:
        top -= a * np.sin(2 * np.pi * k * x / w + rng.uniform(0, 6.28))
    if bumps:
        top -= np.abs(np.sin(2 * np.pi * 40 * x / w)) * bumps
    yy, xx = np.mgrid[0:h, 0:w]
    mask = yy >= top[None, :]
    depth = np.clip((yy - top[None, :]) / 30.0, 0, 1)
    c = Canvas(w, h)
    c.a = quantize(1.0 - depth * 0.9, ramp, mask, dither=0.4)
    return c


def hills(w=640, h=110):
    c = Canvas(w, h)
    far = ridge(w, h, HILL_FAR, 40, [(1, 14), (3, 6), (7, 2)], 3)
    c.blit(far, 0, 0)
    near = ridge(w, h, HILL_NEAR, 70, [(2, 12), (5, 5), (11, 2)], 9, bumps=2.0)
    c.blit(near, 0, 0)
    return c


def treeline(w=512, h=120):
    """Mid-distance: hazy tree clumps and a few rooftops with chimneys."""
    c = Canvas(w, h)
    rng = np.random.default_rng(21)
    # Rooftops first (behind the trees), slate and terracotta, hazed.
    roofs = [(40, 70, 64, "#8d9ab4", "#a4b0c6"), (196, 76, 78, "#c09a92", "#d4b2a6"),
             (330, 68, 58, "#8d9ab4", "#a4b0c6"), (430, 80, 70, "#c09a92", "#d4b2a6")]
    for x, top, rw, col, lit in roofs:
        pts = [(x, h), (x, top + 18), (x + rw / 2, top), (x + rw, top + 18), (x + rw, h)]
        c.poly(pts, col)
        c.poly([(x + rw / 2, top), (x + rw, top + 18), (x + rw, h), (x + rw / 2 + 2, h)], lit)
        cx = x + rw * 0.72
        c.rect(cx, top + 2, 6, 14, "#b49890")
        c.rect(cx, top + 1, 7, 2, "#c8b0a8")
        # A wall strip under the eaves.
        c.rect(x + 4, top + 18, rw - 8, h, "#c8d0d8")
    balls = []
    x = 0.0
    while x < w:
        r = rng.uniform(12, 24)
        balls.append((x, h - rng.uniform(20, 46), r))
        if rng.random() < 0.5:
            balls.append((x + rng.uniform(-6, 6), h - rng.uniform(42, 60), r * 0.7))
        x += rng.uniform(14, 26)
    balls.append((x, h, 1))
    mask, lam, rim = blob_light(w, h, balls, wrap=True)
    yy, _ = np.mgrid[0:h, 0:w]
    v = lam * 0.8 + rim * 0.4 + value_noise(w, h, 8, 33, 2) * 0.25 - 0.1
    trees = Canvas(w, h)
    trees.a = quantize(np.clip(v, 0, 1), LEAF_FAR, mask, dither=0.4)
    trees.rect(0, h - 26, w, 26, LEAF_FAR[0])
    c.blit(trees, 0, 0)
    return c


# ---- ground --------------------------------------------------------------------

def ground(w=128, h=72):
    """Tileable street section, from the sidewalk's back edge (y 0 = world 312)
    down: the sidewalk top (8 px), the lit lip, the slab and curb face, the
    gutter, then wet asphalt. The cat walks on y 8 (world 320)."""
    c = Canvas(w, h)
    n = value_noise(w, h, 8, 5, 2)
    yy, xx = np.mgrid[0:h, 0:w]
    top = yy < 8
    v = 0.66 + (yy / 8.0) * 0.12 + (n - 0.5) * 0.18
    wet = value_noise(w, h, 16, 11, 2) > 0.58
    v = np.where(wet, v - 0.16, v)
    c.a = quantize(v, CONCRETE, top, dither=0.3)
    c.hline(0, w - 1, 0, CONCRETE[2])
    for sx in (0, 64):
        c.vline(sx, 1, 7, CONCRETE[2])
        c.vline(sx + 1, 1, 7, CONCRETE[5])
    c.hline(0, w - 1, 8, CONCRETE[6])          # lit lip (the walking line)
    face = (yy >= 9) & (yy < 22)
    fv = 0.42 - (yy - 9) / 13.0 * 0.22 + (n - 0.5) * 0.12
    c.a[face] = quantize(fv, CONCRETE, face, dither=0.3)[face]
    c.hline(0, w - 1, 9, CONCRETE[4])
    c.hline(0, w - 1, 15, CONCRETE[1])          # slab / curb joint
    c.hline(0, w - 1, 16, CONCRETE[3])
    for sx in (0, 64):
        c.vline(sx, 9, 15, CONCRETE[1])
    c.rect(0, 22, w, 3, ASPHALT[0])             # gutter
    c.hline(0, w - 1, 23, "#8fb0d4")             # a thread of water in it
    road = yy >= 25
    rv = 0.35 + (n - 0.5) * 0.35 + (yy - 25) / 47.0 * 0.15
    c.a[road] = quantize(rv, ASPHALT, road, dither=0.6)[road]
    rng = np.random.default_rng(4)
    for _ in range(40):
        x, y = rng.integers(0, w), rng.integers(27, h)
        c.px(x, y, ASPHALT[3])
    return c


# ---- garden and street furniture --------------------------------------------------

def picket_fence(w=80, h=46):
    """Tileable white picket fence: two rails behind pointed pickets, lit
    from the right. Origin bottom-left; posts are separate (fence_post)."""
    c = Canvas(w, h)
    for ry in (12, 32):
        c.rect(0, ry, w, 4, TRIM[2])
        c.hline(0, w - 1, ry, TRIM[3])
        c.hline(0, w - 1, ry + 3, TRIM[1])
    for i in range(8):
        x = i * 10 + 2
        top = 4
        c.rect(x, top + 3, 6, h - top - 3, TRIM[3])
        c.poly([(x, top + 3), (x + 3, top), (x + 6, top + 3)], TRIM[3])
        c.px(x + 2, top + 1, TRIM[3])
        c.vline(x, top + 3, h - 1, TRIM[1])
        c.vline(x + 5, top + 2, h - 1, TRIM[4])
        c.vline(x + 4, top + 4, h - 1, TRIM[3])
        c.px(x + 4, top + 1, TRIM[4])
        c.rect(x + 1, h - 6, 4, 6, TRIM[2])     # splashback grime at the foot
        c.rect(x + 1, h - 3, 5, 3, TRIM[1])
    c.outline(INK_SOFT)
    return c


def fence_post(h=52):
    c = Canvas(10, h)
    c.rect(1, 4, 8, h - 4, TRIM[3])
    c.vline(1, 4, h - 1, TRIM[1])
    c.vline(8, 4, h - 1, TRIM[4])
    c.rect(0, 2, 10, 3, TRIM[4])
    c.rect(2, 0, 6, 2, TRIM[3])
    c.rect(1, h - 5, 8, 5, TRIM[1])
    c.outline(INK_SOFT)
    return c


def leafy(w, h, balls, seed, ramp=LEAF, wet=0.012, wrap=False, light_bias=0.0):
    mask, lam, rim = blob_light(w, h, balls, wrap=wrap)
    n = value_noise(w, h, 5, seed, 2)
    v = lam * 0.85 + rim * 0.5 + (n - 0.5) * 0.55 + light_bias
    c = Canvas(w, h)
    c.a = quantize(np.clip(v, 0, 1), ramp[:-1], mask, dither=0.0)
    # Wet glints: the brightest leaves catch the sun.
    rng = np.random.default_rng(seed + 1)
    hot = mask & (v > 0.86)
    ys, xs = np.nonzero(hot)
    for k in rng.choice(len(ys), size=int(len(ys) * wet * 6) if len(ys) else 0, replace=False):
        c.px(xs[k], ys[k], ramp[-1])
    return c


def hedge(w=96, h=40):
    """A clipped box hedge, tileable: flat top, rounded shoulders, leafy face."""
    masses = [(x, h * 0.62, 30, h * 0.52) for x in range(-48, w + 49, 24)]
    c = canopy(w, h, masses, 41, clump=(3, 6), density=1.3, wet=0.03)
    yy, xx = np.mgrid[0:h, 0:w]
    c.a[yy < 5] = 0
    c.a[yy >= h - 1] = c.a[h - 2]
    for x in range(w):
        col = c.a[:, x, 3] > 0
        if col.any():
            top = int(np.argmax(col))
            c.a[top, x, :3] = rgb(LEAF[5]) if (x * 7 + top) % 5 else rgb(LEAF[6])
    c.outline(INK)
    c.a[:, 0] = c.a[:, 1]
    c.a[:, -1] = c.a[:, -2]
    return c


def bush(w, h, seed, flowers=None):
    rng = np.random.default_rng(seed)
    masses = [(w / 2, h * 0.62, w * 0.46, h * 0.58), (w * 0.3, h * 0.72, w * 0.26, h * 0.4), (w * 0.7, h * 0.7, w * 0.27, h * 0.42)]
    c = canopy(w, h, masses, seed, clump=(3, 6), density=1.2, wet=0.03)
    if flowers:
        ramp = FLOWER[flowers]
        m = c.opaque()
        ys, xs = np.nonzero(m)
        for k in rng.choice(len(ys), size=len(ys) // 22, replace=False):
            x, y = xs[k], ys[k]
            if y < h - 3:
                c.px(x, y, ramp[1])
                c.px(x + 1, y, ramp[2] if x % 2 else ramp[1])
                c.px(x, y + 1, ramp[0])
    c.outline(INK)
    return c


def lawn(w=128, h=22):
    """Tileable front-lawn strip seen over the fences: wet grass with tufts
    along the top edge, a few daisies and dew."""
    c = Canvas(w, h)
    yy, xx = np.mgrid[0:h, 0:w]
    n = value_noise(w, h, 8, 13, 2)
    v = 0.62 - yy / h * 0.35 + (n - 0.5) * 0.3
    body = yy >= 3
    c.a = quantize(np.clip(v, 0, 1), LEAF[1:6], body, dither=0.4)
    rng = np.random.default_rng(14)
    for x in range(w):
        t = int(rng.integers(0, 4))
        for k in range(t):
            c.px(x, 3 - k - 1, LEAF[4] if k == t - 1 else LEAF[3])
    for _ in range(9):
        x, y = int(rng.integers(2, w - 2)), int(rng.integers(5, h - 4))
        c.px(x, y, "#ffffff")
        c.px(x - 1, y, "#eceaf0")
        c.px(x + 1, y, "#eceaf0")
        c.px(x, y + 1, "#f0cc4a")
    for _ in range(14):
        c.px(int(rng.integers(0, w)), int(rng.integers(4, h)), LEAF[6])
    return c


def flower_bed(w=96, h=22, seed=3, colors=("pink", "yellow", "white")):
    rng = np.random.default_rng(seed)
    c = Canvas(w, h)
    # Soil and leaves.
    c.rect(0, h - 4, w, 4, "#4a3330")
    c.hline(0, w - 1, h - 4, "#6b4a3c")
    balls = [(x, h - 6, rng.uniform(4, 7)) for x in np.arange(2, w, 6)]
    leaves = leafy(w, h, balls, seed + 3)
    c.blit(leaves, 0, 0)
    for x in range(3, w - 3, 5):
        x += int(rng.integers(-1, 2))
        col = FLOWER[colors[int(rng.integers(0, len(colors)))]]
        top = int(rng.integers(2, 8))
        c.vline(x, top + 2, h - 5, LEAF[2])
        c.px(x - 1, top, col[1])
        c.px(x + 1, top, col[1])
        c.px(x, top - 1, col[2])
        c.px(x, top + 1, col[0])
        c.px(x, top, "#fff3a0")
    c.outline(INK)
    return c


def canopy(w, h, masses, seed, ramp=LEAF, clump=(5, 9), density=1.0, wet=0.02):
    """Foliage: a few big lit masses (ellipses: cx, cy, rx, ry) carved into
    many small leaf clumps. Shade = big-volume light (the form) plus clump
    light (the texture), with dark seams between clumps, then a ragged edge."""
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:h, 0:w]
    big = np.full((h, w), -1.0)
    bnx = np.zeros((h, w))
    bny = np.zeros((h, w))
    bnz = np.zeros((h, w))
    for cx, cy, rx, ry in masses:
        dx = (xx + 0.5 - cx) / rx
        dy = (yy + 0.5 - cy) / ry
        d2 = dx * dx + dy * dy
        z = np.sqrt(np.clip(1.0 - d2, 0, 1))
        take = (d2 <= 1.0) & (z > big)
        big[take] = z[take]
        bnx[take], bny[take], bnz[take] = dx[take], dy[take], z[take]
    inside = big >= 0
    # Clumps: scattered over the masses, denser at the rim so the edge is leafy.
    ys, xs = np.nonzero(inside)
    n = int(len(ys) / (np.mean(clump) ** 2) * 1.6 * density)
    balls = []
    for k in rng.choice(len(ys), size=min(n, len(ys)), replace=False):
        balls.append((xs[k] + 0.5, ys[k] + 0.5, rng.uniform(*clump)))
    mask, lam, _ = blob_light(w, h, balls)
    seam = np.zeros((h, w))
    # Seams: where the winning clump's sphere is low (its edge), darken.
    _, _, rimc = blob_light(w, h, balls, light=np.array([0.0, 0.0, 1.0]))
    lamb_big = np.clip(bnx * SUN_DIR[0] + bny * SUN_DIR[1] + bnz * SUN_DIR[2], 0, 1)
    edge_lit = np.clip(bnx * SUN_DIR[0] + bny * SUN_DIR[1], 0, 1) * (1 - bnz)
    noise = value_noise(w, h, 3, seed + 5, 1)
    v = lamb_big * 0.62 + lam * 0.38 + edge_lit * 0.35 + (noise - 0.5) * 0.18 - 0.08
    v = np.where(lam < 0.22, v - 0.18, v)   # clump undersides and seams
    c = Canvas(w, h)
    c.a = quantize(np.clip(v, 0, 1), ramp[:-1], mask, dither=0.0)
    hot = mask & (v > 0.84)
    hy, hx = np.nonzero(hot)
    if len(hy):
        for k in rng.choice(len(hy), size=max(int(len(hy) * wet), 1), replace=False):
            c.px(hx[k], hy[k], ramp[-1])
    return c


def tree(w, h, seed, canopy_ramp=LEAF, trunk_h=0.42, lean=0.0):
    """A broad deciduous tree, origin bottom centre. Canopy of leafy masses lit
    from the right, a trunk with two limbs, wet glints."""
    rng = np.random.default_rng(seed)
    c = Canvas(w, h)
    cx = w / 2
    th = int(h * trunk_h)
    tw = max(int(w * 0.07), 6)
    trunk = c.mask_poly([(cx - tw - 5, h), (cx - tw / 2, h - 12), (cx - tw / 2 + lean, h - th - 20),
                         (cx + tw / 2 + lean, h - th - 20), (cx + tw / 2, h - 12), (cx + tw + 5, h)])
    limb1 = c.mask_poly([(cx - 2 + lean, h - th + 4), (cx - w * 0.24, h - th - 44), (cx - w * 0.24 + 5, h - th - 46), (cx + 3 + lean, h - th - 6)])
    limb2 = c.mask_poly([(cx + lean, h - th + 2), (cx + w * 0.21, h - th - 50), (cx + w * 0.21 + 5, h - th - 48), (cx + 5 + lean, h - th - 2)])
    tm = trunk | limb1 | limb2
    yy, xx = np.mgrid[0:h, 0:w]
    bark_n = value_noise(w, h, 3, seed + 9, 1)
    bv = 0.45 + ((xx - cx) / (tw * 1.5)) * 0.35 + (bark_n - 0.5) * 0.35
    c.a[tm] = quantize(np.clip(bv, 0, 1), BARK[1:], tm, dither=0.0)[tm]
    ch = h - th
    masses = [(cx, ch * 0.50, w * 0.40, ch * 0.36)]
    for _ in range(5):
        a = rng.uniform(np.pi * 0.9, np.pi * 2.1)
        masses.append((cx + np.cos(a) * w * 0.24, ch * 0.50 + np.sin(a) * ch * 0.22,
                       w * rng.uniform(0.16, 0.24), ch * rng.uniform(0.16, 0.22)))
    can = canopy(w, h, masses, seed + 2, ramp=canopy_ramp, clump=(5, 9))
    c.blit(can, 0, 0)
    c.outline(INK)
    return c


def lamp_post(h=150):
    c = Canvas(26, h)
    c.rect(11, 18, 4, h - 18, "#4a5468")
    c.vline(14, 18, h - 1, "#6f7c94")
    c.rect(9, h - 8, 8, 8, "#3c4558")
    c.rect(7, 2, 12, 4, "#3c4558")
    c.rect(8, 6, 10, 10, "#cfd8e0")
    c.rect(9, 7, 4, 8, "#eef4f6")
    c.rect(8, 16, 10, 2, "#3c4558")
    c.outline(INK)
    return c


def mailbox():
    c = Canvas(22, 46)
    c.rect(9, 16, 4, 30, BARK[2])
    c.vline(12, 16, 45, BARK[3])
    c.rect(1, 4, 20, 13, "#3f6aa8")
    c.ellipse(11, 5, 10, 4, "#3f6aa8")
    c.rect(1, 4, 20, 1, "#5f88c0")
    c.ellipse(11, 4.5, 9, 3, "#6a92c8")
    c.vline(20, 4, 16, "#8fb0d8")
    c.rect(18, 1, 2, 9, "#d8524e")              # the flag, up: post's come
    c.rect(2, 15, 19, 2, "#2f4f80")
    c.outline(INK)
    return c


def street_sign():
    c = Canvas(42, 120)
    c.rect(19, 8, 4, 112, "#6f7c8c")
    c.vline(22, 8, 119, "#9aa6b4")
    c.rect(2, 8, 38, 11, "#3f7a54")
    c.rect(3, 9, 36, 9, "#4f9064")
    for x in range(6, 36, 4):
        c.rect(x, 12, 2, 3, "#e8f0e8")
    c.outline(INK)
    return c


def flower_pot(col=TERRACOTTA, flowers="red", seed=1):
    c = Canvas(22, 30)
    c.poly([(3, 14), (19, 14), (17, 29), (5, 29)], col[2])
    c.rect(2, 13, 18, 3, col[3])
    c.vline(17, 16, 28, col[3])
    c.vline(5, 16, 28, col[1])
    b = bush(22, 16, seed, flowers=flowers)
    c.blit(b, 0, 0)
    c.outline(INK)
    return c


def birds():
    """Three 9x7 frames: perched, wings up, wings down. Small brown sparrows."""
    c = Canvas(27, 7)
    body, dark, belly = "#7a5a48", "#4a3430", "#d8c0a0"
    # perched
    c.rect(2, 3, 5, 3, body)
    c.rect(6, 2, 2, 2, body)
    c.px(8, 3, "#e0a040")
    c.px(7, 2, INK)
    c.rect(3, 5, 3, 1, belly)
    c.px(1, 3, dark)
    c.px(0, 2, dark)
    c.px(4, 6, dark)
    # wings up
    o = 9
    c.rect(o + 2, 3, 5, 2, body)
    c.rect(o + 6, 2, 2, 2, body)
    c.px(o + 8, 3, "#e0a040")
    c.rect(o + 3, 0, 2, 3, dark)
    c.px(o + 2, 0, dark)
    c.px(o + 1, 3, dark)
    # wings down
    o = 18
    c.rect(o + 2, 2, 5, 2, body)
    c.rect(o + 6, 1, 2, 2, body)
    c.px(o + 8, 2, "#e0a040")
    c.rect(o + 3, 4, 2, 2, dark)
    c.px(o + 2, 5, dark)
    c.px(o + 1, 2, dark)
    return c


# ---- houses ------------------------------------------------------------------------

def siding(c, x0, y0, w, h, ramp, board=6):
    """Clapboard: each board a lit face with a shadow line under its lip."""
    c.rect(x0, y0, w, h, ramp[2])
    for y in range(y0, y0 + h, board):
        c.hline(x0, x0 + w - 1, y, ramp[3])
        c.hline(x0, x0 + w - 1, y + board - 1, ramp[1])


def window(c, x, y, w, h, frame=TRIM, glass=GLASS, shutters=None, curtains=None, panes=(2, 2)):
    """A sash window: trim, sky-reflecting glass, muntins, sill, shutters."""
    if shutters:
        for sx in (x - 9, x + w + 2):
            c.rect(sx, y + 1, 7, h - 2, shutters[1])
            c.vline(sx + 6, y + 1, y + h - 2, shutters[2])
            for yy in range(y + 4, y + h - 3, 4):
                c.hline(sx + 1, sx + 5, yy, shutters[0])
    c.rect(x - 3, y - 3, w + 6, h + 6, frame[3])
    c.vline(x + w + 2, y - 3, y + h + 2, frame[4])
    c.vline(x - 3, y - 3, y + h + 2, frame[1])
    gl = np.zeros((c.h, c.w), bool)
    gl[y:y + h, x:x + w] = True
    yy, xx = np.mgrid[0:c.h, 0:c.w]
    t = 0.85 - (yy - y) / max(h, 1) * 0.6
    streak = ((xx - x) - (yy - y) * 0.7) % 23
    t = t + np.where((streak > 2) & (streak < 6), 0.35, 0.0)
    c.a[gl] = quantize(np.clip(t, 0, 1), glass[1:], gl, dither=0.0)[gl]
    if curtains:
        cw = max(w // 5, 3)
        c.rect(x, y, cw, h, curtains[1])
        c.rect(x + w - cw, y, cw, h, curtains[1])
        c.vline(x + cw - 1, y, y + h - 1, curtains[0])
        c.vline(x + w - cw, y, y + h - 1, curtains[2])
    px, py = panes
    for i in range(1, px):
        c.vline(x + i * w // px, y, y + h - 1, frame[3])
    for j in range(1, py):
        c.rect(x, y + j * h // py - 1, w, 2, frame[3])
    c.hline(x, x + w - 1, y, frame[1])           # head shadow on the glass
    c.rect(x - 5, y + h + 3, w + 10, 3, frame[3])  # sill
    c.hline(x - 5, x + w + 4, y + h + 3, frame[4])
    c.hline(x - 4, x + w + 3, y + h + 6, frame[0])


def roof(c, x0, x1, eave_y, ridge_y, ramp, overhang=10, style="gable"):
    """A pitched roof over [x0, x1] with fascia trim and shingle courses."""
    mid = (x0 + x1) / 2.0
    pts = [(x0 - overhang, eave_y), (mid, ridge_y), (x1 + overhang, eave_y)]
    m = c.mask_poly([(x0 - overhang, eave_y + 1), (mid, ridge_y), (x1 + overhang, eave_y + 1)])
    yy, xx = np.mgrid[0:c.h, 0:c.w]
    # The right slope faces the sun.
    lit = xx >= mid
    v = np.where(lit, 0.72, 0.42) + (yy - ridge_y) / max(eave_y - ridge_y, 1) * 0.12
    c.a[m] = quantize(v, ramp[1:], m, dither=0.0)[m]
    for y in range(int(ridge_y) + 5, int(eave_y), 5):
        row = m[y] if 0 <= y < c.h else None
        if row is None:
            continue
        xs = np.nonzero(row)[0]
        if len(xs) == 0:
            continue
        for x in xs:
            c.px(x, y, ramp[0] if x < mid else ramp[2])
        off = (y // 5) % 2 * 6
        for x in range(xs[0] + off, xs[-1], 12):
            if m[min(y + 1, c.h - 1), x]:
                for k in range(1, 5):
                    if 0 <= y + k < c.h and m[y + k, x]:
                        c.px(x, y + k, ramp[1] if x < mid else ramp[2])
    # Fascia and ridge cap.
    for (ax, ay), (bx, by) in ((pts[0], pts[1]), (pts[1], pts[2])):
        n = int(max(abs(bx - ax), abs(by - ay)))
        for i in range(n + 1):
            px = round(ax + (bx - ax) * i / n)
            py = round(ay + (by - ay) * i / n)
            c.px(px, py, TRIM[3])
            c.px(px, py - 1, TRIM[4] if px >= mid else TRIM[2])
            c.px(px, py + 1, TRIM[1])
    c.hline(int(x0 - overhang), int(x1 + overhang), int(eave_y), TRIM[3])
    c.hline(int(x0 - overhang), int(x1 + overhang), int(eave_y) + 1, TRIM[2])
    return m


def eave_shadow(c, x0, x1, y, depth, shift=-4):
    """Soft cast shadow under an eave, falling down and to the left."""
    region = c.a[y:y + depth, x0:x1]
    m = region[..., 3] > 0
    for k in range(depth):
        row = c.a[y + k, max(x0 + shift, 0):x1 + shift]
        dark = (k < depth - 2) or ((k + np.arange(row.shape[0])) % 2 == 0)
        sel = (row[..., 3] > 0) & dark
        row[sel, :3] = (row[sel, :3] * 0.80 + np.array([40, 30, 70]) * 0.20 * 0.5).astype(np.uint8)
    return m


def chimney(c, x, top, h, ramp=BRICK):
    c.rect(x, top, 18, h, ramp[2])
    for y in range(top + 3, top + h, 4):
        c.hline(x, x + 17, y, ramp[1])
        off = 0 if (y // 4) % 2 else 4
        for bx in range(x + off, x + 18, 8):
            c.vline(bx, y + 1, min(y + 3, top + h - 1), ramp[1])
    c.vline(x + 17, top, top + h - 1, ramp[3])
    c.rect(x - 2, top - 3, 22, 4, TRIM[2])
    c.hline(x - 2, x + 19, top - 3, TRIM[3])


def house(kind):
    """A neighbour's cottage, set back behind its fence. Origin bottom-left."""
    if kind == "sage":
        wall, roof_r, door, w, wall_h, shut = SAGE, SLATE, DOOR_GREEN, 300, 128, DOOR_BLUE
    elif kind == "butter":
        wall, roof_r, door, w, wall_h, shut = BUTTER, TERRACOTTA, DOOR_BLUE, 280, 120, SAGE
    elif kind == "rose":
        wall, roof_r, door, w, wall_h, shut = ROSE, SLATE, DOOR_GREEN, 300, 124, CREAM
    else:
        wall, roof_r, door, w, wall_h, shut = DUSTY, TERRACOTTA, ["#7c3a38", "#9c5040", "#ba6c50", "#d08a64"], 320, 132, None
    roof_h = 84
    H = wall_h + roof_h + 24
    c = Canvas(w + 40, H)
    x0, x1 = 20, 20 + w
    base = H - 1
    top = base - wall_h
    # Foundation, walls.
    siding(c, x0, top, w, wall_h - 8, wall)
    c.rect(x0, base - 8, w, 9, "#8c8790")
    c.hline(x0, x1 - 1, base - 8, "#aaa5ae")
    c.vline(x1 - 1, top, base, wall[4])
    c.vline(x0, top, base, wall[0])
    if kind in ("sage", "rose"):
        chimney(c, x0 + (40 if kind == "sage" else w - 70), top - roof_h + 10, roof_h, BRICK)
    roof(c, x0, x1, top, top - roof_h, roof_r)
    eave_shadow(c, x0, x1, top + 2, 6)
    # Door with a small porch hood and step.
    dx = x0 + {"sage": w * 0.62, "butter": w * 0.62, "rose": w * 0.42, "dusty": w * 0.18}[kind]
    dx = int(dx)
    dh = 70
    c.rect(dx - 4, base - 8 - dh - 4, 40, dh + 4, TRIM[3])
    c.rect(dx, base - 8 - dh, 32, dh, door[2])
    c.vline(dx + 31, base - 8 - dh, base - 9, door[3])
    for py in (base - 8 - dh + 6, base - 8 - dh + 38):
        c.rect(dx + 5, py, 22, 26, door[1])
        c.rect(dx + 6, py + 1, 20, 24, door[2])
        c.vline(dx + 26, py, py + 25, door[3])
    c.rect(dx + 8, base - 8 - dh + 8, 16, 10, GLASS[3])
    c.rect(dx + 25, base - 8 - dh / 2, 3, 3, "#f0cc4a")
    c.rect(dx - 10, base - 8 - dh - 12, 52, 6, roof_r[3])
    c.hline(dx - 10, dx + 41, base - 8 - dh - 12, roof_r[4])
    c.hline(dx - 10, dx + 41, base - 8 - dh - 7, TRIM[1])
    c.rect(dx - 6, base - 8, 44, 5, CONCRETE[4])
    c.hline(dx - 6, dx + 37, base - 8, CONCRETE[5])
    # Windows.
    wins = []
    if kind == "sage":
        wins = [(x0 + 30, top + 30, 44, 52), (x0 + 100, top + 30, 44, 52)]
    elif kind == "butter":
        wins = [(x0 + 28, top + 28, 56, 48), (x0 + 228, top + 28, 32, 48)]
    elif kind == "rose":
        wins = [(x0 + 30, top + 30, 52, 56), (x0 + 210, top + 30, 52, 56)]
    else:
        wins = [(x0 + 120, top + 30, 48, 54), (x0 + 200, top + 30, 48, 54), (x0 + 270, top + 34, 30, 40)]
    for wx, wy, ww, wh in wins:
        window(c, int(wx), int(wy), ww, wh, shutters=shut, curtains=["#c0a080", "#e8d4b0", "#f8ecd0"] if ww > 40 else None)
    # A window box with flowers on the butter house.
    if kind == "butter":
        wx, wy, ww, wh = wins[0]
        c.rect(wx - 4, wy + wh + 7, ww + 8, 7, BARK[3])
        fb = flower_bed(ww + 8, 14, seed=12, colors=("red", "white"))
        c.blit(fb, wx - 4, wy + wh - 4)
    # A gable vent / round window in the roof.
    gx = (x0 + x1) // 2
    c.ellipse(gx, top - 30, 9, 9, TRIM[3])
    c.ellipse(gx, top - 30, 7, 7, GLASS[2])
    c.hline(gx - 6, gx + 6, top - 30, TRIM[3])
    c.vline(gx, top - 37, top - 23, TRIM[3])
    # Gutter and downpipe (dripping, in game).
    c.rect(x0 - 10, top + 1, w + 20, 3, "#9aa2b0")
    c.hline(x0 - 10, x1 + 9, top + 1, "#c8d0dc")
    c.rect(x1 + 4, top + 3, 3, wall_h - 10, "#9aa2b0")
    c.vline(x1 + 6, top + 3, base - 8, "#c8d0dc")
    c.outline(INK_SOFT)
    return c


# ---- the cat's home ---------------------------------------------------------------

HOME_W = 480          # footprint width (world px)
HOME_WALL = 150       # floor (local y 260) to ceiling
HOME_RIDGE = 110      # ceiling to ridge
HOME_H = 276          # canvas height: ridge (y 4) to the foundation (y 275)
FLOOR_Y = 260         # interior floor line in the canvas (world y 304)
DOOR_X = 52           # door left edge in the canvas
DOOR_W, DOOR_H = 36, 80
FLAP_W, FLAP_H = 20, 18
HOME_OX = 52          # canvas x of the footprint's left edge (room for the porch)
HOME_CW = HOME_W + HOME_OX + 12


def gable(c, x0, x1, eave_y, ridge_y, ramp, thick=7):
    """Front-facing gable: two roof bands with fascia, over the wall."""
    mid = (x0 + x1) / 2.0
    for side in (-1, 1):
        ex = x0 - 10 if side < 0 else x1 + 10
        pts = [(ex, eave_y + 2), (mid, ridge_y), (mid, ridge_y + thick), (ex, eave_y + 2 + thick)]
        m = c.mask_poly(pts)
        c.fill(m, ramp[2] if side < 0 else ramp[4])
        # Tile ends along the band.
        ys, xs = np.nonzero(m)
        for x, y in zip(xs, ys):
            if (x // 6) % 2 == 0 and y == ys[xs == x].max():
                c.px(x, y, ramp[1] if side < 0 else ramp[3])
        n = int(abs(ex - mid))
        for i in range(n + 1):
            px = round(mid + (ex - mid) * i / n)
            py = round(ridge_y + (eave_y + 2 - ridge_y) * i / n)
            c.px(px, py - 1, ramp[5] if side > 0 else ramp[3])
            c.px(px, py + thick, TRIM[3])
            c.px(px, py + thick + 1, TRIM[1])


def home_front():
    """The facade of the cat's house: cream clapboard under a front gable,
    a dusty blue door with the cat flap (cut out: flap.png fills it), a hood
    on brackets, two windows with flower boxes, a lantern, the number 7."""
    W, H = HOME_CW, HOME_H
    ox = HOME_OX
    c = Canvas(W, H)
    x0, x1 = ox, ox + HOME_W
    eave = FLOOR_Y - HOME_WALL
    ridge = eave - HOME_RIDGE
    mid = (x0 + x1) // 2
    # Main wall in cream clapboard; the gable in sage fish-scale shingles.
    body = c.mask_poly([(x0, FLOOR_Y), (x0, eave), (x1, eave), (x1, FLOOR_Y)])
    tmp = Canvas(W, H)
    siding(tmp, 0, 0, W, H, CREAM)
    c.a[body] = tmp.a[body]
    gab = c.mask_poly([(x0, eave), (mid, ridge + 6), (x1, eave)])
    yy, xx = np.mgrid[0:H, 0:W]
    row = (yy - ridge) // 6
    sx = (xx + (row % 2) * 4) % 8
    sy = (yy - ridge) % 6
    scale_edge = (sy == 5) & (sx > 0) & (sx < 7) | (sy == 4) & ((sx == 0) | (sx == 7))
    light = np.clip((xx - x0) / HOME_W, 0, 1)
    tone = np.where(scale_edge, 0, np.where(sy < 2, 3, 2))
    tone = np.where((sx >= 5) & ~scale_edge & (sy < 4), 3, tone)
    tone = np.where((light > 0.5) & (tone == 2) & (sx > 3), 3, tone)
    lut = np.array([(*rgb(v), 255) for v in SAGE], np.uint8)
    c.a[gab] = lut[np.clip(tone + 1, 0, 4)][gab]
    c.a[gab & scale_edge] = (*rgb(SAGE[1]), 255)
    # Frieze board between gable and wall.
    c.rect(x0, eave - 1, HOME_W, 7, TRIM[3])
    c.hline(x0, x1 - 1, eave - 1, TRIM[4])
    c.hline(x0, x1 - 1, eave + 5, TRIM[1])
    c.vline(x1 - 1, eave, FLOOR_Y, CREAM[4])
    c.vline(x0, eave, FLOOR_Y, CREAM[1])
    # Corner boards.
    for cx in (x0, x1 - 6):
        c.rect(cx, eave, 6, FLOOR_Y - eave, TRIM[3])
        c.vline(cx + 5, eave, FLOOR_Y, TRIM[4])
        c.vline(cx, eave, FLOOR_Y, TRIM[1])
    # Foundation below the floor line.
    c.rect(x0 - 2, FLOOR_Y, HOME_W + 4, H - FLOOR_Y, "#8c8790")
    for y in range(FLOOR_Y + 3, H, 5):
        c.hline(x0 - 2, x1 + 1, y, "#79747e")
        off = 0 if (y // 5) % 2 else 9
        for bx in range(x0 + off, x1, 18):
            c.vline(bx, y + 1, min(y + 4, H - 1), "#79747e")
    c.hline(x0 - 2, x1 + 1, FLOOR_Y, "#aaa5ae")
    gable(c, x0, x1, eave, ridge, TERRACOTTA, thick=9)
    # Attic window: round, catching the sky.
    c.ellipse(mid, ridge + 52, 15, 15, TRIM[3])
    c.ellipse(mid, ridge + 52, 12, 12, GLASS[2])
    c.ellipse(mid + 3, ridge + 49, 6, 6, GLASS[3])
    c.hline(mid - 11, mid + 11, ridge + 52, TRIM[3])
    c.vline(mid, ridge + 41, ridge + 63, TRIM[3])
    # Door.
    dx, dy = ox + DOOR_X, FLOOR_Y - DOOR_H
    c.rect(dx - 5, dy - 5, DOOR_W + 10, DOOR_H + 5, TRIM[3])
    c.vline(dx + DOOR_W + 4, dy - 5, FLOOR_Y - 1, TRIM[4])
    c.vline(dx - 5, dy - 5, FLOOR_Y - 1, TRIM[1])
    c.rect(dx, dy, DOOR_W, DOOR_H, DOOR_BLUE[2])
    c.vline(dx + DOOR_W - 1, dy, FLOOR_Y - 1, DOOR_BLUE[3])
    c.vline(dx, dy, FLOOR_Y - 1, DOOR_BLUE[1])
    for py, ph in ((dy + 6, 30), (dy + 40, 14)):
        c.rect(dx + 5, py, DOOR_W - 10, ph, DOOR_BLUE[1])
        c.rect(dx + 6, py + 1, DOOR_W - 12, ph - 2, DOOR_BLUE[2])
        c.vline(dx + DOOR_W - 6, py, py + ph - 1, DOOR_BLUE[3])
    # A little window in the door, glinting.
    c.rect(dx + 9, dy + 9, DOOR_W - 18, 18, GLASS[2])
    c.rect(dx + 9, dy + 9, DOOR_W - 18, 3, GLASS[3])
    c.px(dx + DOOR_W - 11, dy + 13, GLASS[4])
    c.rect(dx + DOOR_W - 9, dy + 44, 3, 3, "#f0cc4a")
    c.px(dx + DOOR_W - 8, dy + 44, "#fff09a")
    # The cat flap: a framed opening at the foot (the flap sprite sits in it).
    fx = dx + (DOOR_W - FLAP_W) // 2
    fy = FLOOR_Y - FLAP_H - 3
    c.rect(fx - 2, fy - 2, FLAP_W + 4, FLAP_H + 4, "#8a92a4")
    c.hline(fx - 2, fx + FLAP_W + 1, fy - 2, "#b8c0cc")
    c.rect(fx, fy, FLAP_W, FLAP_H, "#2a2238")
    # Step and doormat in front.
    c.rect(dx - 8, FLOOR_Y - 2, DOOR_W + 16, 2, "#b85a48")
    # Porch: a shed roof over the steps and the door on two posts.
    p0, p1 = x0 - 44, dx + DOOR_W + 52
    py = dy - 22
    for k in range(6):                       # shadow on the wall under it
        row_ = c.a[py + 12 + k, p0 + 40:p1 - 4]
        sel = (row_[..., 3] > 0) & (((np.arange(row_.shape[0]) + k) % 2 == 0) | (k < 4))
        row_[sel, :3] = (row_[sel, :3] * 0.82).astype(np.uint8)
    c.poly([(p0, py + 12), (p0 + 6, py), (p1 + 4, py), (p1 + 4, py + 12)], TERRACOTTA[3])
    for x in range(p0 + 4, p1 + 4, 6):
        c.vline(x, py + 2, py + 10, TERRACOTTA[2])
    c.hline(p0 + 6, p1 + 4, py, TERRACOTTA[5])
    c.hline(p0 + 5, p1 + 4, py + 1, TERRACOTTA[4])
    c.rect(p0, py + 11, p1 - p0 + 5, 4, TRIM[3])
    c.hline(p0, p1 + 4, py + 11, TRIM[4])
    c.hline(p0, p1 + 4, py + 14, TRIM[1])
    for px_ in (x0 + 1, p1 - 4):
        c.rect(px_, py + 15, 7, FLOOR_Y - py - 15, TRIM[3])
        c.vline(px_ + 6, py + 15, FLOOR_Y - 1, TRIM[4])
        c.vline(px_, py + 15, FLOOR_Y - 1, TRIM[1])
        c.rect(px_ - 1, py + 15, 9, 3, TRIM[2])
        c.rect(px_ - 1, FLOOR_Y - 6, 9, 6, TRIM[2])
    # A hanging basket from the porch beam.
    hb = bush(22, 14, 31, flowers="pink")
    c.vline(p0 + 40, py + 15, py + 26, "#8a92a4")
    c.blit(hb, p0 + 30, py + 24)
    # Lantern to the right of the door.
    lx = dx + DOOR_W + 14
    c.rect(lx, dy + 14, 8, 12, "#3c4558")
    c.rect(lx + 1, dy + 16, 6, 8, "#f6e7b0")
    c.rect(lx + 2, dy + 12, 4, 2, "#3c4558")
    # House number.
    c.rect(lx - 1, dy + 34, 10, 12, TRIM[3])
    c.rect(lx + 2, dy + 36, 4, 1, INK)
    c.vline(lx + 5, dy + 37, dy + 39, INK)
    c.vline(lx + 4, dy + 40, dy + 43, INK)
    # Windows with flower boxes.
    for wx, ww in ((ox + 190, 64), (ox + 330, 64)):
        wy = eave + 34
        window(c, wx, wy, ww, 62, shutters=SAGE, curtains=["#c08a58", "#e8c890", "#f8e4b8"])
        c.rect(wx - 6, wy + 66, ww + 12, 9, BARK[3])
        c.hline(wx - 6, wx + ww + 5, wy + 66, BARK[4])
        fb = flower_bed(ww + 12, 16, seed=wx, colors=("pink", "white", "peach"))
        c.blit(fb, wx - 6, wy + 52)
    # Eave shadow on the wall under the gable band.
    for k in range(5):
        row = c.a[eave + 2 + k]
        sel = (row[..., 3] > 0) & ((np.arange(W) + k) % (1 if k < 3 else 2) == 0)
        row[sel, :3] = (row[sel, :3] * 0.84).astype(np.uint8)
    # Downpipe on the right corner.
    c.rect(x1 - 14, eave + 2, 3, FLOOR_Y - eave - 4, "#9aa2b0")
    c.vline(x1 - 12, eave + 2, FLOOR_Y - 3, "#c8d0dc")
    c.outline(INK)
    return c


def flap():
    """The flap itself: smoked plastic in a hinge bar (swings in game)."""
    c = Canvas(FLAP_W, FLAP_H)
    c.rect(0, 0, FLAP_W, 3, "#8a92a4")
    c.hline(0, FLAP_W - 1, 0, "#c8d0dc")
    c.rect(1, 3, FLAP_W - 2, FLAP_H - 3, "#56607a")
    c.rect(2, 4, FLAP_W - 4, FLAP_H - 6, "#6a7690")
    c.vline(FLAP_W - 4, 5, FLAP_H - 4, "#9aa6c0")
    c.px(FLAP_W - 5, 5, "#e6f4ff")
    c.rect(1, FLAP_H - 2, FLAP_W - 2, 2, "#3a4258")
    return c


def home_inside():
    """The cutaway: the attic under the rafters, the living room with its
    window and the sunbeam's landing place, the floor in slight perspective.
    The sunbeam itself is light in game; the art leaves the room a step dim."""
    W, H = HOME_CW, HOME_H
    ox = HOME_OX
    c = Canvas(W, H)
    x0, x1 = ox, ox + HOME_W
    eave = FLOOR_Y - HOME_WALL
    ridge = eave - HOME_RIDGE
    mid = (x0 + x1) // 2
    yy, xx = np.mgrid[0:H, 0:W]
    # Attic: warm dark wood under the roof, rafters and a collar tie.
    attic = c.mask_poly([(x0 + 4, eave), (mid, ridge + 14), (x1 - 4, eave)])
    c.fill(attic, "#3a2830")
    for rx in range(x0 + 30, x1 - 20, 44):
        top = ridge + 14 + abs(rx - mid) * (eave - ridge - 14) / (mid - x0)
        c.rect(rx, int(top), 5, int(eave - top), "#4e3634")
        c.vline(rx + 4, int(top), eave - 1, "#5e443c")
    c.rect(mid - 70, ridge + 52, 140, 5, WOOD[2])
    c.hline(mid - 70, mid + 69, ridge + 52, WOOD[3])
    # Boxes and a suitcase in the attic, in silhouette.
    c.rect(x0 + 70, eave - 22, 30, 22, "#5a4038")
    c.rect(x0 + 104, eave - 14, 22, 14, "#6a4c40")
    c.hline(x0 + 70, x0 + 99, eave - 22, "#7a5a48")
    c.rect(x1 - 120, eave - 16, 40, 16, "#4e3a44")
    c.rect(x1 - 104, eave - 19, 8, 3, "#4e3a44")
    # The round attic window from inside, with a little light.
    c.ellipse(mid, ridge + 52 - 2, 13, 13, "#5e443c")
    c.ellipse(mid, ridge + 50, 11, 11, "#f4e2b0")
    c.hline(mid - 10, mid + 10, ridge + 50, "#5e443c")
    c.vline(mid, ridge + 40, ridge + 60, "#5e443c")
    # Ceiling joist band.
    c.rect(x0, eave, HOME_W, 8, WOOD[1])
    c.hline(x0, x1 - 1, eave + 7, WOOD[0])
    c.hline(x0, x1 - 1, eave, WOOD[2])
    # Roof section (the cut through the tiles), drawn over the attic edge.
    gable(c, x0, x1, eave, ridge, TERRACOTTA, thick=9)
    # Back wall: warm wallpaper with a fine stripe and tiny sprigs.
    wall = (yy >= eave + 8) & (yy < FLOOR_Y - 8) & (xx >= x0) & (xx < x1)
    wv = 0.55 + ((xx - x0) / HOME_W) * 0.28 - ((yy - eave) / HOME_WALL) * 0.10
    c.a[wall] = quantize(np.clip(wv, 0, 1), WALLPAPER[1:], wall, dither=0.0)[wall]
    stripe = wall & ((xx - x0) % 12 == 0)
    c.a[stripe, :3] = (c.a[stripe, :3] * 0.9).astype(np.uint8)
    for sy in range(eave + 18, FLOOR_Y - 60, 16):
        for sx in range(x0 + 6 + (sy // 16 % 2) * 6, x1, 12):
            if wall[sy, sx]:
                c.px(sx, sy, mixc(WALLPAPER[3], "#f0d8b0", 0.4))
                c.px(sx, sy + 1, WALLPAPER[1])
    # Wainscot below a dado rail.
    dado = FLOOR_Y - 58
    c.rect(x0, dado, HOME_W, FLOOR_Y - 8 - dado, WOOD[2])
    for px_ in range(x0 + 4, x1 - 4, 40):
        c.rect(px_ + 3, dado + 8, 34, FLOOR_Y - 8 - dado - 16, WOOD[1])
        c.rect(px_ + 4, dado + 9, 32, FLOOR_Y - 8 - dado - 18, WOOD[2])
        c.hline(px_ + 4, px_ + 35, dado + 9, WOOD[3])
    c.rect(x0, dado - 3, HOME_W, 4, WOOD[3])
    c.hline(x0, x1 - 1, dado - 3, WOOD[4])
    c.rect(x0, FLOOR_Y - 10, HOME_W, 3, WOOD[3])   # skirting
    # Floor: boards in slight perspective, then the floor's front edge.
    floor = (yy >= FLOOR_Y - 7) & (yy < FLOOR_Y) & (xx >= x0) & (xx < x1)
    fv = 0.5 + (yy - (FLOOR_Y - 7)) / 7.0 * 0.25
    c.a[floor] = quantize(fv, WOOD[1:], floor, dither=0.0)[floor]
    floor_seams(c, x0, x1, FLOOR_Y - 7, FLOOR_Y - 1, (x0 + x1) / 2.0)
    c.hline(x0, x1 - 1, FLOOR_Y - 1, WOOD[5])
    c.rect(x0, FLOOR_Y, HOME_W, 6, WOOD[2])
    c.hline(x0, x1 - 1, FLOOR_Y, WOOD[4])
    c.hline(x0, x1 - 1, FLOOR_Y + 5, WOOD[0])
    # Under the floor in section: joists on a sill beam, warm and dark, so the
    # room sits on its own base (no grey band in the close-up).
    c.rect(x0 - 2, FLOOR_Y + 6, HOME_W + 4, H - FLOOR_Y - 6, "#3a2628")
    for jx in range(x0 + 6, x1 - 4, 24):
        c.rect(jx, FLOOR_Y + 6, 8, 7, WOOD[1])
        c.hline(jx, jx + 7, FLOOR_Y + 6, WOOD[2])
    c.rect(x0 - 2, H - 4, HOME_W + 4, 4, WOOD[1])
    c.hline(x0 - 2, x1 + 1, H - 4, WOOD[2])
    # Side walls in section.
    for sx in (x0, x1 - 8):
        c.rect(sx, eave, 8, FLOOR_Y - eave, CREAM[1])
        c.vline(sx + (7 if sx == x0 else 0), eave, FLOOR_Y - 1, CREAM[0])
    # The window on the back wall: the sun pours in (the glass is bright in
    # game, an emissive overlay), curtains tied back, a plant on the sill.
    wx, wy, ww, wh = WIN_X + ox, WIN_Y, WIN_W, WIN_H
    c.rect(wx - 5, wy - 5, ww + 10, wh + 10, TRIM[2])
    c.vline(wx + ww + 4, wy - 5, wy + wh + 4, TRIM[3])
    # The glass is left clear: the glowing panes sit behind the room in game.
    c.a[wy:wy + wh, wx:wx + ww] = 0
    c.rect(wx + ww // 2 - 1, wy, 3, wh, TRIM[2])
    c.rect(wx, wy + wh // 2 - 1, ww, 3, TRIM[2])
    c.rect(wx - 9, wy + wh + 3, ww + 18, 4, TRIM[3])
    c.hline(wx - 9, wx + ww + 8, wy + wh + 3, TRIM[4])
    for side in (-1, 1):
        cx = wx - 14 if side < 0 else wx + ww + 4
        cur = c.mask_poly([(cx, wy - 8), (cx + 10, wy - 8), (cx + 10 - side * 2, wy + wh * 0.55),
                           (cx + 5, wy + wh + 2), (cx + 2 * side, wy + wh * 0.55)])
        c.fill(cur, FABRIC_GOLD[1])
        c.a[cur & ((xx - cx) % 4 == 1)] = (*rgb(FABRIC_GOLD[2]), 255)
        c.rect(cx + 1, int(wy + wh * 0.5), 9, 3, FABRIC_GOLD[0])
    c.rect(wx - 16, wy - 10, ww + 32, 3, WOOD[1])   # curtain rod
    # Plant on the sill.
    c.rect(wx + ww - 18, wy + wh - 7, 12, 10, TERRACOTTA[2])
    c.hline(wx + ww - 18, wx + ww - 7, wy + wh - 7, TERRACOTTA[4])
    pl = leafy(26, 22, [(9, 12, 7), (17, 10, 7), (13, 6, 6)], 77)
    c.blit(pl, wx + ww - 25, wy + wh - 27)
    # A radiator under the window.
    c.rect(wx + 6, dado + 6, ww - 12, 30, "#c8c4c8")
    for rx in range(wx + 8, wx + ww - 8, 5):
        c.vline(rx, dado + 7, dado + 34, "#a8a4ac")
    # Bookshelf on the left.
    bx0, bw, btop = x0 + 22, 54, FLOOR_Y - 124
    c.rect(bx0, btop, bw, FLOOR_Y - 8 - btop, WOOD[1])
    c.rect(bx0 + 3, btop + 3, bw - 6, FLOOR_Y - 14 - btop, WOOD[0])
    rng = np.random.default_rng(5)
    books = ["#8a3e4a", "#3f6252", "#405482", "#b88440", "#6e5a8a", "#9a6a44", "#c06a50", "#7a8aa0"]
    for sy in range(btop + 3, FLOOR_Y - 20, 26):
        c.rect(bx0 + 3, sy + 22, bw - 6, 3, WOOD[2])
        x = bx0 + 4
        while x < bx0 + bw - 6:
            bwid = int(rng.integers(3, 6))
            bh = int(rng.integers(14, 21))
            col = books[int(rng.integers(0, len(books)))]
            c.rect(x, sy + 22 - bh, bwid, bh, col)
            c.vline(x, sy + 22 - bh, sy + 21, mixc(col, "#000000", 0.25))
            c.px(x + 1, sy + 22 - bh + 3, mixc(col, "#ffffff", 0.35))
            x += bwid + (1 if rng.random() < 0.2 else 0)
    c.rect(bx0 - 2, btop - 3, bw + 4, 4, WOOD[3])
    # Armchair, facing the window, with a knitted throw.
    ax = x0 + 112
    c.rect(ax, FLOOR_Y - 48, 58, 30, "#7a4a4c")           # back
    c.ellipse(ax + 29, FLOOR_Y - 48, 29, 7, "#8a5658")
    c.rect(ax - 4, FLOOR_Y - 30, 66, 18, "#8a5658")       # seat and arms
    c.rect(ax - 6, FLOOR_Y - 36, 12, 24, "#9a6466")
    c.rect(ax + 56, FLOOR_Y - 36, 12, 24, "#a8706e")
    c.hline(ax - 6, ax + 5, FLOOR_Y - 36, "#b88482")
    c.hline(ax + 56, ax + 67, FLOOR_Y - 36, "#c8948e")
    c.rect(ax + 14, FLOOR_Y - 44, 26, 26, FABRIC_GOLD[1])
    for ty in range(FLOOR_Y - 44, FLOOR_Y - 18, 3):
        c.hline(ax + 14, ax + 39, ty, FABRIC_GOLD[2])
    for lx_ in (ax - 2, ax + 60):
        c.rect(lx_, FLOOR_Y - 12, 4, 6, WOOD[1])
    # Side table with a lamp and the framed photo.
    tx = ax + 82
    c.rect(tx, FLOOR_Y - 44, 34, 4, WOOD[3])
    c.hline(tx, tx + 33, FLOOR_Y - 44, WOOD[4])
    c.rect(tx + 3, FLOOR_Y - 40, 3, 32, WOOD[2])
    c.rect(tx + 28, FLOOR_Y - 40, 3, 32, WOOD[2])
    c.rect(tx + 4, FLOOR_Y - 60, 2, 16, "#c8b8a0")
    c.poly([(tx - 2, FLOOR_Y - 60), (tx + 12, FLOOR_Y - 60), (tx + 9, FLOOR_Y - 74), (tx + 1, FLOOR_Y - 74)], "#e8d8b8")
    c.rect(tx + 1, FLOOR_Y - 48, 8, 4, "#a89880")
    # The photo: two people and a small tabby, in a gold frame.
    px0, py0 = tx + 15, FLOOR_Y - 62
    c.rect(px0, py0, 16, 18, FABRIC_GOLD[2])
    c.rect(px0 + 2, py0 + 2, 12, 14, "#a9cbe8")
    c.rect(px0 + 2, py0 + 11, 12, 5, "#7aa955")
    c.rect(px0 + 3, py0 + 5, 3, 7, "#c06a50")
    c.rect(px0 + 3, py0 + 4, 3, 2, "#f0c8a0")
    c.rect(px0 + 8, py0 + 6, 3, 6, "#56709e")
    c.rect(px0 + 8, py0 + 5, 3, 2, "#e0b090")
    c.rect(px0 + 10, py0 + 12, 4, 2, "#a06a40")
    c.px(px0 + 13, py0 + 11, "#a06a40")
    c.vline(px0 + 15, py0, py0 + 17, FABRIC_GOLD[3])
    # Wall art: a framed landscape and a clock.
    c.rect(ax + 10, eave + 34, 46, 32, FABRIC_GOLD[1])
    c.rect(ax + 13, eave + 37, 40, 26, "#99c4ec")
    c.rect(ax + 13, eave + 52, 40, 11, "#86aeb4")
    c.poly([(ax + 13, eave + 55), (ax + 30, eave + 46), (ax + 46, eave + 54), (ax + 52, eave + 52), (ax + 52, eave + 62), (ax + 13, eave + 62)], "#578c4c")
    c.ellipse(ax + 44, eave + 43, 3, 3, "#fff1c2")
    c.ellipse(tx + 17, eave + 40, 9, 9, WOOD[2])
    c.ellipse(tx + 17, eave + 40, 7, 7, "#f2efe9")
    c.vline(tx + 17, eave + 35, eave + 40, INK)
    c.hline(tx + 17, tx + 20, eave + 40, INK)
    # Food and water bowls near the door.
    for bx_, col, fill_ in ((x0 + 92, "#c06a50", "#8a5a38"), (x0 + 74, "#56709e", "#a9cbe8")):
        c.poly([(bx_, FLOOR_Y - 6), (bx_ + 14, FLOOR_Y - 6), (bx_ + 12, FLOOR_Y - 1), (bx_ + 2, FLOOR_Y - 1)], col)
        c.hline(bx_ + 1, bx_ + 13, FLOOR_Y - 7, fill_)
        c.hline(bx_, bx_ + 14, FLOOR_Y - 6, mixc(col, "#ffffff", 0.3))
    # The rug on the floor plane, under the beam.
    rx0, rx1 = RUG_X0 + ox, RUG_X1 + ox
    for k, y in enumerate(range(FLOOR_Y - 6, FLOOR_Y - 1)):
        inset = (5 - k)
        c.hline(rx0 + inset, rx1 - inset, y, RUG[2] if k % 2 == 0 else RUG[3])
    c.hline(rx0 + 1, rx1 - 1, FLOOR_Y - 2, RUG[1])
    for x in range(rx0 + 3, rx1 - 2, 4):
        c.px(x, FLOOR_Y - 4, RUG[4])
    for x in range(rx0, rx1 + 1, 2):
        c.px(x, FLOOR_Y - 1, "#e8d8b8")
    # A cat-flap view from inside: the door is in the (removed) front wall.
    return c


WIN_X, WIN_Y, WIN_W, WIN_H = 356, 150, 58, 56   # window on the back wall (canvas px, before ox)
RUG_X0, RUG_X1 = 230, 380


def cushion():
    """A round cat bed: back rim (behind the cat) and front rim (over it)."""
    back = Canvas(48, 16)
    back.ellipse(24, 9, 23, 7, CUSHION[1])
    back.ellipse(24, 8, 21, 5, CUSHION[2])
    back.ellipse(24, 10, 17, 4, CUSHION[0])
    back.hline(10, 38, 4, CUSHION[3])
    back.outline(INK)
    front = Canvas(48, 16)
    front.ellipse(24, 12, 23, 4, CUSHION[2])
    front.ellipse(24, 11, 21, 2, CUSHION[3])
    front.rect(0, 0, 48, 9, "#000000", 0)
    front.a[:9] = 0
    front.outline(INK)
    front.a[:8] = 0
    return back, front


def steps():
    """Two wooden porch steps up to the floor (16 px rise over 32 px)."""
    c = Canvas(44, 18)
    for k, (x, y, w) in enumerate(((0, 9, 44), (18, 1, 26))):
        c.rect(x, y, w, 8, WOOD[3])
        c.hline(x, x + w - 1, y, WOOD[5])
        c.hline(x, x + w - 1, y + 1, WOOD[4])
        c.hline(x, x + w - 1, y + 7, WOOD[1])
    c.outline(INK)
    return c


def garden_gate():
    """The home's gate, swung open towards the viewer (a foreshortened panel)."""
    c = Canvas(24, 50)
    c.rect(0, 4, 3, 46, TRIM[3])
    c.poly([(3, 10), (22, 6), (22, 44), (3, 48)], TRIM[2])
    for x in range(5, 22, 5):
        c.vline(x, 9 - x // 5, 46 - x // 5, TRIM[4])
    c.poly([(3, 14), (22, 10), (22, 13), (3, 17)], TRIM[3])
    c.poly([(3, 38), (22, 34), (22, 37), (3, 41)], TRIM[3])
    c.outline(INK_SOFT)
    return c


def floor_seams(c, x0, x1, y0, y1, vx, step=26):
    """Board seams on a floor seen from slightly above: lines that fan out
    from a vanishing point `vx` towards the viewer (one px per row)."""
    for bx in np.arange(x0 - 200, x1 + 200, step):
        for y in range(y0, y1 + 1):
            k = (y - y0) / max(y1 - y0, 1)
            x = int(round(vx + (bx - vx) * (1.0 + k * 0.18)))
            if x0 <= x < x1:
                c.px(x, y, WOOD[1])


def credits_room():
    """The credits backdrop (320x180, shown at 2x): a corner of the living room
    under the window, the floor and a plant. The window's light patch is a
    separate mask (credits_light.png) added in game, so it can glow."""
    W, H = 320, 180
    c = Canvas(W, H)
    yy, xx = np.mgrid[0:H, 0:W]
    dado, floor_y = 118, 160
    wall = yy < dado
    wv = 0.62 - (yy / dado) * 0.12 + (xx / W) * 0.06
    c.a = quantize(np.clip(wv, 0, 1), WALLPAPER[1:], np.ones((H, W), bool), dither=0.0)
    stripe = wall & (xx % 12 == 0)
    c.a[stripe, :3] = (c.a[stripe, :3] * 0.92).astype(np.uint8)
    for sy in range(10, dado - 8, 16):
        for sx in range(6 + (sy // 16 % 2) * 6, W, 12):
            c.px(sx, sy, mixc(WALLPAPER[3], "#f0d8b0", 0.4))
            c.px(sx, sy + 1, WALLPAPER[1])
    c.rect(0, dado, W, floor_y - 6 - dado, WOOD[2])
    for px_ in range(4, W, 40):
        c.rect(px_ + 3, dado + 8, 34, floor_y - dado - 20, WOOD[1])
        c.rect(px_ + 4, dado + 9, 32, floor_y - dado - 22, WOOD[2])
        c.hline(px_ + 4, px_ + 35, dado + 9, WOOD[3])
    c.rect(0, dado - 3, W, 4, WOOD[3])
    c.hline(0, W - 1, dado - 3, WOOD[4])
    c.rect(0, floor_y - 8, W, 3, WOOD[3])
    fl = yy >= floor_y - 5
    fv = 0.45 + (yy - floor_y) / 20.0 * 0.3
    c.a[fl] = quantize(np.clip(fv, 0, 1), WOOD[1:], fl, dither=0.0)[fl]
    floor_seams(c, 0, W, floor_y - 5, H - 1, 160.0)
    # The rug under the cushion.
    for k, y in enumerate(range(floor_y + 2, floor_y + 9)):
        inset = 8 - k
        c.hline(40 + inset, 200 - inset, y, RUG[2] if k % 2 == 0 else RUG[3])
    for x in range(44, 197, 4):
        c.px(x, floor_y + 5, RUG[4])
    for x in range(33, 208, 2):
        c.px(x, floor_y + 9, "#e8d8b8")
    # A tall plant in a pot on the left.
    c.poly([(8, 142), (30, 142), (27, 164), (11, 164)], TERRACOTTA[2])
    c.rect(7, 140, 24, 4, TERRACOTTA[3])
    pl = canopy(46, 70, [(23, 34, 18, 26), (14, 46, 10, 14), (32, 44, 11, 14)], 91, clump=(4, 7))
    c.vline(19, 120, 141, LEAF[1])
    c.blit(pl, -4, 74)
    return c


def credits_light():
    """White mask of the sun's patch through a four-pane window: on the wall,
    breaking over the dado, and onto the floor round the cushion."""
    W, H = 320, 180
    c = Canvas(W, H)
    def pane(x, y, w, h, skew):
        return c.mask_poly([(x, y), (x + w, y), (x + w + skew, y + h), (x + skew, y + h)])
    m = np.zeros((H, W), bool)
    for (x, y) in ((30, 18), (74, 18), (30, 64), (74, 64)):
        m |= pane(x + (y - 18) * 0.45, y, 40, 42, 19)
    floor = c.mask_poly([(60, 158), (190, 158), (214, 180), (66, 180)])
    m |= floor
    c.a[m] = (255, 255, 255, 255)
    # Soft one-pixel fringe.
    edge = c.outline("#ffffff")
    c.a[edge, 3] = 110
    return c


def main():
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else HERE.parent.parent / "assets" / "art_hd" / "home"
    out.mkdir(parents=True, exist_ok=True)
    jobs = {
        "sky.png": sky(),
        "sun.png": sun_disc(),
        "cloud_a.png": cloud(150, 54, 1),
        "cloud_b.png": cloud(96, 36, 2),
        "cloud_c.png": cloud(200, 62, 3),
        "cloud_d.png": cloud(64, 24, 4),
        "rainbow.png": rainbow(),
        "hills.png": hills(),
        "treeline.png": treeline(),
        "ground.png": ground(),
        "fence.png": picket_fence(),
        "fence_post.png": fence_post(),
        "hedge.png": hedge(),
        "bush_a.png": bush(56, 34, 5, flowers="pink"),
        "bush_b.png": bush(40, 26, 6),
        "bush_c.png": bush(64, 38, 8, flowers="white"),
        "flowers_a.png": flower_bed(96, 22, 3),
        "flowers_b.png": flower_bed(64, 22, 9, ("red", "peach", "yellow")),
        "tree_big.png": tree(200, 250, 11),
        "tree_small.png": tree(120, 170, 17, trunk_h=0.45),
        "lamp_post.png": lamp_post(),
        "mailbox.png": mailbox(),
        "street_sign.png": street_sign(),
        "pot_a.png": flower_pot(flowers="red", seed=1),
        "pot_b.png": flower_pot(flowers="yellow", seed=2),
        "birds.png": birds(),
        "lawn.png": lawn(),
        "house_sage.png": house("sage"),
        "house_butter.png": house("butter"),
        "house_dusty.png": house("dusty"),
        "house_rose.png": house("rose"),
        "home_front.png": home_front(),
        "home_inside.png": home_inside(),
        "flap.png": flap(),
        "steps.png": steps(),
        "gate.png": garden_gate(),
    }
    jobs["credits_room.png"] = credits_room()
    jobs["credits_light.png"] = credits_light()
    back, front = cushion()
    jobs["cushion_back.png"] = back
    jobs["cushion_front.png"] = front
    for name, c in jobs.items():
        c.save(out / name)
        print(f"{name}: {c.w}x{c.h}")


if __name__ == "__main__":
    main()
