"""Pixel helpers for the actor kit art (tools/art/kit_art.py).

A Spr is an RGBA numpy canvas with palette-locked drawing: every colour comes
from a ramp (dark to light) so shading stays in 4-5 stops. Light comes from the
upper left, as on the bart tiles and the ansimuz robots.

    s = Spr(32, 32)
    s.sphere(16, 16, 8, 7, AMBER)          # lit ellipsoid, quantised to the ramp
    s.box(4, 20, 27, 27, STEEL)            # bevelled panel
    s.outline()                            # 1 px INK ring outside the silhouette
    s.glow(...)                            # emissive bits go on after the outline
"""
import math

import numpy as np
from PIL import Image, ImageDraw

INK = (0x16, 0x16, 0x30, 255)
CLEAR = (0, 0, 0, 0)
LIGHT = np.array([-0.55, -0.72, 0.62])
LIGHT = LIGHT / np.linalg.norm(LIGHT)


def rgb(h, a=255):
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)


def ramp(*hexes):
    return [rgb(h) for h in hexes]


def quant(i, n, bias=0.0, gamma=1.6):
    """Lighting 0..1 to a ramp index (dark to light). The gamma keeps a surface
    facing the viewer on the middle stop, so the lit stops stay small."""
    v = max(0.0, min(1.0, i + bias)) ** gamma
    return int(max(0, min(n - 1, math.floor(v * n))))


class Spr:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.a = np.zeros((h, w, 4), np.uint8)

    # ---- basics ---------------------------------------------------------
    def copy(self):
        s = Spr(self.w, self.h)
        s.a = self.a.copy()
        return s

    def px(self, x, y, c):
        x, y = int(round(x)), int(round(y))
        if 0 <= x < self.w and 0 <= y < self.h and c is not None:
            self.a[y, x] = c

    def pxs(self, pts, c):
        for x, y in pts:
            self.px(x, y, c)

    def get(self, x, y):
        if 0 <= x < self.w and 0 <= y < self.h:
            return tuple(int(v) for v in self.a[y, x])
        return CLEAR

    def opaque(self, x, y):
        return 0 <= x < self.w and 0 <= y < self.h and self.a[y, x, 3] > 0

    def rect(self, x0, y0, x1, y1, c):
        x0, x1 = sorted((int(x0), int(x1)))
        y0, y1 = sorted((int(y0), int(y1)))
        x0, y0 = max(x0, 0), max(y0, 0)
        x1, y1 = min(x1, self.w - 1), min(y1, self.h - 1)
        if x1 >= x0 and y1 >= y0:
            self.a[y0:y1 + 1, x0:x1 + 1] = c

    def hline(self, x0, x1, y, c):
        self.rect(x0, y, x1, y, c)

    def vline(self, x, y0, y1, c):
        self.rect(x, y0, x, y1, c)

    def _mask(self, fn):
        im = Image.new("L", (self.w, self.h), 0)
        fn(ImageDraw.Draw(im))
        return np.asarray(im) > 0

    def poly_mask(self, pts):
        return self._mask(lambda d: d.polygon([tuple(p) for p in pts], fill=255, outline=255))

    def ell_mask(self, x0, y0, x1, y1):
        return self._mask(lambda d: d.ellipse([x0, y0, x1, y1], fill=255))

    def fill(self, mask, c):
        self.a[mask] = c

    def poly(self, pts, c):
        self.fill(self.poly_mask(pts), c)

    def ell(self, x0, y0, x1, y1, c):
        self.fill(self.ell_mask(x0, y0, x1, y1), c)

    def line(self, pts, c, w=1):
        m = self._mask(lambda d: d.line([tuple(p) for p in pts], fill=255, width=w))
        self.fill(m, c)

    def mask(self):
        return self.a[..., 3] > 0

    def paste(self, other, ox=0, oy=0):
        """Alpha-over another Spr (opaque pixels win)."""
        for y in range(other.h):
            ty = y + oy
            if not 0 <= ty < self.h:
                continue
            for x in range(other.w):
                tx = x + ox
                if 0 <= tx < self.w and other.a[y, x, 3] > 0:
                    self.a[ty, tx] = other.a[y, x]

    def recolor(self, src, dst):
        m = (self.a == np.array(src, np.uint8)).all(axis=2)
        self.a[m] = dst

    # ---- lit volumes ------------------------------------------------------
    def shade(self, mask, normal_fn, rmp, bias=0.0, amb=0.18):
        ys, xs = np.nonzero(mask)
        for x, y in zip(xs, ys):
            n = normal_fn(x + 0.5, y + 0.5)
            i = amb + (1.0 - amb) * max(0.0, float(np.dot(n, LIGHT)))
            self.a[y, x] = rmp[quant(i, len(rmp), bias)]

    def sphere(self, cx, cy, rx, ry, rmp, bias=0.0, clip=None):
        m = self.ell_mask(cx - rx, cy - ry, cx + rx - 1, cy + ry - 1)
        if clip is not None:
            m &= clip

        def nf(x, y):
            nx, ny = (x - cx) / rx, (y - cy) / ry
            nz = math.sqrt(max(0.0, 1.0 - nx * nx - ny * ny))
            v = np.array([nx, ny, nz])
            return v / (np.linalg.norm(v) + 1e-9)
        self.shade(m, nf, rmp, bias)
        return m

    def cyl_v(self, x0, y0, x1, y1, rmp, bias=0.0, mask=None):
        """Upright cylinder: shading runs across x."""
        m = np.zeros((self.h, self.w), bool)
        m[max(y0, 0):y1 + 1, max(x0, 0):x1 + 1] = True
        if mask is not None:
            m &= mask
        cx, r = (x0 + x1 + 1) / 2.0, (x1 - x0 + 1) / 2.0

        def nf(x, y):
            nx = (x - cx) / r
            return np.array([nx, -0.25, math.sqrt(max(0.0, 1 - nx * nx))])
        self.shade(m, nf, rmp, bias)
        return m

    def cyl_h(self, x0, y0, x1, y1, rmp, bias=0.0, mask=None):
        """Lying cylinder: shading runs across y."""
        m = np.zeros((self.h, self.w), bool)
        m[max(y0, 0):y1 + 1, max(x0, 0):x1 + 1] = True
        if mask is not None:
            m &= mask
        cy, r = (y0 + y1 + 1) / 2.0, (y1 - y0 + 1) / 2.0

        def nf(x, y):
            ny = (y - cy) / r
            return np.array([-0.25, ny, math.sqrt(max(0.0, 1 - ny * ny))])
        self.shade(m, nf, rmp, bias)
        return m

    def box(self, x0, y0, x1, y1, rmp, face=None, bevel=1):
        """Bevelled panel from a ramp (dark..light): lit top/left, shaded bottom/right."""
        n = len(rmp)
        f = rmp[face if face is not None else n // 2]
        lit = rmp[min(n - 1, (face if face is not None else n // 2) + 1)]
        dark = rmp[max(0, (face if face is not None else n // 2) - 1)]
        self.rect(x0, y0, x1, y1, f)
        for k in range(bevel):
            self.hline(x0 + k, x1 - k, y0 + k, lit)
            self.vline(x0 + k, y0 + k, y1 - k, lit)
            self.hline(x0 + k, x1 - k, y1 - k, dark)
            self.vline(x1 - k, y0 + k + 1, y1 - k, dark)

    def panel(self, mask, rmp, face, lit=None, dark=None):
        """Flat-shaded shape from a mask: face colour, lit top/left rim, dark bottom/right rim."""
        n = len(rmp)
        lit = min(n - 1, face + 1) if lit is None else lit
        dark = max(0, face - 1) if dark is None else dark
        m = mask
        self.a[m] = rmp[face]
        up = np.zeros_like(m)
        up[1:, :] = m[:-1, :]
        left = np.zeros_like(m)
        left[:, 1:] = m[:, :-1]
        down = np.zeros_like(m)
        down[:-1, :] = m[1:, :]
        right = np.zeros_like(m)
        right[:, :-1] = m[:, 1:]
        self.a[m & (~down | ~right)] = rmp[dark]
        self.a[m & (~up | ~left)] = rmp[lit]
        return m

    def ppanel(self, pts, rmp, face, lit=None, dark=None):
        return self.panel(self.poly_mask(pts), rmp, face, lit, dark)

    def rpanel(self, x0, y0, x1, y1, rmp, face, lit=None, dark=None):
        m = np.zeros((self.h, self.w), bool)
        m[max(y0, 0):y1 + 1, max(x0, 0):x1 + 1] = True
        return self.panel(m, rmp, face, lit, dark)

    # ---- outline and finishing --------------------------------------------
    def outline(self, c=INK, diagonal=False):
        """1 px ring outside the opaque silhouette."""
        m = self.mask()
        n = np.zeros_like(m)
        n[1:, :] |= m[:-1, :]
        n[:-1, :] |= m[1:, :]
        n[:, 1:] |= m[:, :-1]
        n[:, :-1] |= m[:, 1:]
        if diagonal:
            n[1:, 1:] |= m[:-1, :-1]
            n[1:, :-1] |= m[:-1, 1:]
            n[:-1, 1:] |= m[1:, :-1]
            n[:-1, :-1] |= m[1:, 1:]
        ring = n & ~m
        self.a[ring] = c
        return self

    def to_image(self):
        return Image.fromarray(self.a, "RGBA")


def strip(frames):
    w = sum(f.w for f in frames)
    h = frames[0].h
    out = np.zeros((h, w, 4), np.uint8)
    x = 0
    for f in frames:
        out[:, x:x + f.w] = f.a
        x += f.w
    return Image.fromarray(out, "RGBA")
