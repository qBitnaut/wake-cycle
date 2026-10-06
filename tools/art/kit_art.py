"""Actor-kit placeholder art: scripted pixel art in the Wake Cycle palette.

    python3 tools/art/kit_art.py

Writes assets/sprites/kit/<actor>/<part>.png (horizontal strips) and the
manifest assets/sprites/kit/kit_manifest.json that the game loads (KitArt).
The manifest is the contract with the art pass: replace a PNG, keep its cell
size, pivot and animation frame lists (or edit the manifest) and the actor
picks it up; colliders are derived from the alpha bounds recorded here, so a
new sprite size needs only a re-run of this script's `bounds` step (or edit
"bounds" by hand).

Parts that reuse existing CC0 art (ansimuz Legacy Collection / Warped City,
already harmonised in assets/art_hd) point at it with "file" instead of being
drawn.
"""
import json
import os
import sys

from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(__file__))
from palette import INK, RAMPS, hex_to_rgb  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "sprites", "kit")


def C(ramp, key, a=255):
    return hex_to_rgb(RAMPS[ramp][key]) + (a,)


INKC = hex_to_rgb(INK) + (255,)
RED = hex_to_rgb("#ff4a3a") + (255,)
HOT = hex_to_rgb("#fff0e0") + (255,)
SODIUM = hex_to_rgb("#ff8c29") + (255,)
AQUA = hex_to_rgb("#41b5c0") + (255,)
GOLD = hex_to_rgb("#ffd23f") + (255,)
CLEAR = (0, 0, 0, 0)


class Cv:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.im = Image.new("RGBA", (w, h), CLEAR)
        self.d = ImageDraw.Draw(self.im)

    def rect(self, x0, y0, x1, y1, c):
        self.d.rectangle([x0, y0, x1, y1], fill=c)

    def ell(self, x0, y0, x1, y1, c):
        self.d.ellipse([x0, y0, x1, y1], fill=c)

    def poly(self, pts, c):
        self.d.polygon(pts, fill=c)

    def line(self, pts, c, w=1):
        self.d.line(pts, fill=c, width=w)

    def px(self, x, y, c):
        if 0 <= x < self.w and 0 <= y < self.h:
            self.im.putpixel((x, y), c)

    def outline(self, c=INKC):
        src = self.im.copy()
        for y in range(self.h):
            for x in range(self.w):
                if src.getpixel((x, y))[3] == 0:
                    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        nx, ny = x + dx, y + dy
                        if 0 <= nx < self.w and 0 <= ny < self.h and src.getpixel((nx, ny))[3] > 0:
                            self.im.putpixel((x, y), c)
                            break
        return self

    def box(self, x0, y0, x1, y1, ramp):
        """Bevelled panel: face, lit top/left, shaded bottom/right."""
        self.rect(x0, y0, x1, y1, C(ramp, "face"))
        self.line([(x0, y0), (x1, y0)], C(ramp, "light"))
        self.line([(x0, y0), (x0, y1)], C(ramp, "light"))
        self.line([(x0, y1), (x1, y1)], C(ramp, "shadow"))
        self.line([(x1, y0), (x1, y1)], C(ramp, "shadow"))


def strip(frames):
    w = sum(f.w for f in frames)
    im = Image.new("RGBA", (w, frames[0].h), CLEAR)
    x = 0
    for f in frames:
        im.paste(f.im, (x, 0))
        x += f.w
    return im


# ---------------------------------------------------------------- actors

def sentry_body():
    out = []
    for stun in (0, 1):
        c = Cv(32, 24)
        c.box(6, 14, 25, 22, "steel")
        c.box(10, 9, 21, 14, "bulkhead")
        c.rect(4, 21, 27, 22, C("steel", "shadow"))
        for x in (8, 23):
            c.px(x, 18, C("steel", "ink"))
        if stun:
            c.px(15, 11, C("bulkhead", "ink"))
        else:
            c.px(15, 11, RED)
        out.append(c.outline())
    return out


def sentry_head():
    out = []
    # 0 idle, 1-3 charge, 4 fire, 5-6 stun
    for i in range(7):
        c = Cv(32, 32)
        face = "steel" if i < 5 else "bulkhead"
        c.box(8, 11, 22, 20, face)
        c.box(21, 14, 29, 17, "bulkhead")  # barrel
        c.rect(26, 15, 29, 16, C("bulkhead", "ink"))
        eye = [C("rust", "shadow"), C("rust", "face"), SODIUM, RED, HOT, C("rust", "ink"), C("rust", "ink")][i]
        c.rect(11, 14, 14, 17, eye)
        if i in (1, 2, 3):
            glow = [C("rust", "light"), SODIUM, HOT][i - 1]
            c.rect(28, 14, 30, 17, glow)
            if i == 3:
                c.px(31, 15, HOT)
                c.px(31, 16, HOT)
        if i == 4:
            c.rect(29, 13, 31, 18, HOT)
        if i >= 5:
            c.px(14 + i, 10, AQUA)
            c.px(10 + i, 21, SODIUM)
        out.append(c.outline())
    return out


def hover_drone():
    out = []
    # 0-2 fly (rotor phases), 3 telegraph (bomb armed, red), 4 stun
    for i in range(5):
        c = Cv(40, 32)
        c.box(9, 10, 30, 22, "violet")
        c.ell(13, 6, 26, 14, C("violet", "light"))
        c.rect(15, 13, 24, 18, C("bulkhead", "ink"))
        c.px(17, 15, RED if i != 4 else C("bulkhead", "shadow"))
        c.px(22, 15, RED if i != 4 else C("bulkhead", "shadow"))
        c.rect(18, 22, 21, 25, C("steel", "face"))  # bomb bay
        bomb = [C("steel", "shadow")] * 3 + [RED, C("steel", "shadow")][0:2]
        c.rect(17, 25, 22, 28, bomb[i] if i < 5 else C("steel", "shadow"))
        spans = [(1, 12), (3, 10), (0, 13)][i % 3] if i < 3 else (3, 10)
        for ox in (0, 1):
            ax = 4 if ox == 0 else 27
            c.line([(ax + 1, 6), (ax + 8, 6)], C("steel", "high"))
            c.px(ax + (spans[0] if ox == 0 else 8 - spans[0] % 8), 5, C("steel", "spec"))
        c.line([(8, 14), (4, 12)], C("steel", "face"))
        c.line([(31, 14), (35, 12)], C("steel", "face"))
        if i == 4:
            c.px(12, 8, AQUA)
            c.px(30, 9, SODIUM)
        out.append(c.outline())
    return out


def hopper():
    out = []
    # 0 idle, 1 squat (telegraph), 2 up, 3 fall, 4 stun
    for i in range(5):
        c = Cv(32, 32)
        sq = 4 if i == 1 else 0
        stretch = 3 if i == 2 else 0
        top = 10 + sq - stretch
        c.box(7, top, 24, 25 - 0, "maroon")
        c.rect(8, 22 + 0, 23, 25, C("maroon", "shadow"))
        c.rect(9, top + 3, 22, top + 8, C("bulkhead", "ink"))  # visor
        eye = RED if i != 4 else C("bulkhead", "shadow")
        c.rect(11, top + 4, 13, top + 6, eye)
        c.rect(18, top + 4, 20, top + 6, eye)
        # spring legs
        ly = 26 + sq // 2
        for x in (9, 20):
            if i == 2:
                c.line([(x, 25), (x - 1, 30)], C("steel", "light"), 2)
                c.line([(x - 3, 30), (x + 2, 30)], C("steel", "high"), 2)
            elif i == 1:
                c.line([(x, 25), (x + 3, 27), (x, 29)], C("steel", "light"))
                c.line([(x - 3, 30), (x + 5, 30)], C("steel", "high"), 2)
            else:
                for k, yy in enumerate(range(25, 30, 2)):
                    c.line([(x - 1 + (k % 2) * 3, yy), (x + 2 - (k % 2) * 3, yy + 1)], C("steel", "light"))
                c.line([(x - 3, 30), (x + 4, 30)], C("steel", "high"), 2)
        c.rect(14, top - 3, 17, top - 1, C("steel", "face"))  # antenna
        c.px(15, top - 4, RED if i == 1 else SODIUM)
        if i == 4:
            c.px(5, 12, AQUA)
            c.px(26, 14, SODIUM)
        out.append(c.outline())
    return out


def crawler():
    out = []
    # 0-3 crawl on a floor (flipped on a ceiling), 4-7 roll, 8 stun, 9 telegraph
    for i in range(10):
        c = Cv(32, 32)
        if 4 <= i <= 7:
            r = 10
            c.ell(16 - r, 16 - r, 16 + r, 16 + r, C("rust", "face"))
            c.ell(16 - r + 3, 16 - r + 3, 16 + r - 3, 16 + r - 3, C("rust", "shadow"))
            import math
            ph = (i - 4) * math.pi / 8
            for k in range(8):
                a = ph + k * math.pi / 4
                x1, y1 = 16 + math.cos(a) * (r + 3), 16 + math.sin(a) * (r + 3)
                x0, y0 = 16 + math.cos(a) * (r - 2), 16 + math.sin(a) * (r - 2)
                c.line([(x0, y0), (x1, y1)], C("hazard", "high"), 2)
            c.rect(14, 14, 18, 18, RED)
        else:
            lift = [0, 1, 0, 1][i % 4] if i < 4 else 0
            c.box(8, 18, 24, 27, "rust")
            c.ell(10, 15, 22, 22, C("rust", "light"))
            c.rect(12, 20, 20, 22, C("bulkhead", "ink"))
            eye = RED if i != 8 else C("bulkhead", "shadow")
            if i == 9:
                eye = HOT
            c.px(13, 21, eye)
            c.px(19, 21, eye)
            for k, x in enumerate((8, 12, 20, 24)):
                up = lift if k % 2 == 0 else 1 - lift
                c.line([(x, 27), (x + (-2 if x < 16 else 2), 29 + (0 if up else 1))], C("steel", "high"))
            for x in (10, 16, 22):
                c.px(x, 14 if i != 9 else 13, C("hazard", "high"))
            if i == 8:
                c.px(6, 17, AQUA)
                c.px(26, 16, SODIUM)
        out.append(c.outline())
    return out


def cam_body():
    c = Cv(16, 16)
    c.box(1, 11, 14, 14, "steel")
    c.rect(6, 6, 9, 11, C("steel", "shadow"))
    c.ell(5, 3, 10, 8, C("bulkhead", "face"))
    return [c.outline()]


def cam_head():
    out = []
    # 0 idle, 1 alarm, 2 stun; faces right, pivot at the mount
    for i in range(3):
        c = Cv(32, 24)
        c.box(4, 7, 22, 16, "bulkhead")
        c.box(21, 9, 28, 14, "steel")
        lens = [C("teal", "high"), RED, C("bulkhead", "ink")][i]
        c.rect(25, 10, 27, 13, lens)
        if i == 1:
            c.rect(6, 5, 20, 6, RED)
        if i == 2:
            c.px(10, 5, AQUA)
            c.px(18, 18, SODIUM)
        out.append(c.outline())
    return out


def barrel(kind):
    out = []
    for i in range(3):  # 0 idle, 1 lit (pre-blast flash), 2 leak / dent
        c = Cv(32, 36)
        body = {"plain": "steel", "explosive": "hazard", "acid": "teal"}[kind]
        c.box(6, 4, 25, 33, body)
        c.rect(7, 4, 24, 5, C(body, "light"))
        for y in (10, 27):
            c.rect(6, y, 25, y + 2, C(body, "shadow"))
            c.rect(6, y, 25, y, C(body, "light"))
        if kind == "explosive":
            c.rect(11, 15, 20, 22, C("hazard", "ink"))
            c.poly([(16, 15), (19, 20), (13, 20)], SODIUM if i != 1 else HOT)
            for k in range(0, 10, 4):
                c.rect(7 + k, 29, 9 + k, 32, C("hazard", "ink"))
        elif kind == "acid":
            c.ell(11, 14, 20, 23, C("hazard", "high"))
            c.px(15, 18, C("teal", "ink"))
            c.px(15, 15, C("teal", "ink"))
            c.px(13, 20, C("teal", "ink"))
            c.px(18, 20, C("teal", "ink"))
            if i == 2:
                c.rect(10, 32, 21, 35, AQUA)
        else:
            c.rect(11, 16, 20, 20, C("steel", "shadow"))
        out.append(c.outline())
    return out


def wall_tile(kind):
    out = []
    ramp = {"cracked": "maroon", "reinforced": "steel", "blast": "rust"}[kind]
    for i in range(2):  # 0 intact, 1 struck
        c = Cv(32, 32)
        c.box(0, 0, 31, 31, ramp)
        for x in (8, 24):
            c.line([(x, 0), (x, 31)], C(ramp, "shadow"))
        for y in (10, 21):
            c.line([(0, y), (31, y)], C(ramp, "shadow"))
        if kind == "cracked":
            ink = C(ramp, "ink")
            c.line([(15, 3), (11, 11), (17, 17), (12, 24), (14, 30)], ink)
            c.line([(11, 11), (5, 13)], ink)
            c.line([(17, 17), (24, 20)], ink)
        elif kind == "reinforced":
            for (x, y) in ((3, 3), (28, 3), (3, 28), (28, 28)):
                c.rect(x - 1, y - 1, x + 1, y + 1, C("steel", "spec"))
            c.rect(6, 13, 25, 18, C("hazard", "face"))
            for x in range(6, 26, 6):
                c.poly([(x, 13), (x + 3, 13), (x + 1, 18), (x - 2, 18)], C("hazard", "ink"))
        else:
            c.ell(10, 10, 21, 21, C("hazard", "face"))
            c.ell(12, 12, 19, 19, C("hazard", "ink"))
            c.poly([(16, 12), (18, 17), (14, 17)], SODIUM)
        out.append(c)
    return out


def electric_panel():
    out = []
    for i in range(3):  # 0 off, 1 warning (spark), 2 live
        c = Cv(32, 10)
        c.box(0, 4, 31, 9, "steel")
        col = [C("steel", "shadow"), SODIUM, AQUA][i]
        for x in range(3, 29, 6):
            c.rect(x, 5, x + 2, 6, col)
        if i == 2:
            c.rect(0, 3, 31, 3, HOT)
        out.append(c)
    return out


def crusher():
    out = []
    # head (32x24, pivot top-centre), 0 idle 1 warn
    for i in range(2):
        c = Cv(32, 24)
        c.box(0, 4, 31, 19, "steel")
        for x in range(2, 30, 6):
            c.poly([(x, 20), (x + 5, 20), (x + 2, 23)], C("steel", "high"))
        c.rect(0, 4, 31, 8, C("hazard", "face"))
        for x in range(0, 32, 8):
            c.poly([(x, 4), (x + 4, 4), (x + 2, 8), (x - 2, 8)], C("hazard", "ink"))
        if i == 1:
            c.rect(2, 11, 29, 13, RED)
        c.rect(12, 0, 19, 4, C("bulkhead", "shadow"))
        out.append(c.outline())
    return out


def piston_rod():
    c = Cv(8, 8)
    c.rect(1, 0, 6, 7, C("steel", "face"))
    c.rect(1, 0, 2, 7, C("steel", "light"))
    c.rect(5, 0, 6, 7, C("steel", "shadow"))
    c.rect(1, 3, 6, 3, C("steel", "ink"))
    return [c]


def spike_trap():
    out = []
    for i in range(3):  # 0 retracted, 1 warning (tips peek), 2 up
        c = Cv(32, 24)
        c.box(0, 16, 31, 23, "steel")
        for x in range(2, 30, 7):
            c.rect(x + 1, 17, x + 4, 19, C("steel", "ink"))
        h = [0, 4, 14][i]
        for x in range(3, 30, 7):
            if h:
                c.poly([(x, 17), (x + 5, 17), (x + 2, 17 - h)], C("steel", "high") if i == 2 else C("hazard", "light"))
                c.line([(x + 2, 17), (x + 2, 17 - h)], C("steel", "spec") if i == 2 else C("hazard", "spec"))
        out.append(c.outline())
    return out


def vent_nozzle(kind):
    c = Cv(24, 10)
    ramp = "steel" if kind == "steam" else "rust"
    c.box(1, 4, 22, 9, ramp)
    c.rect(5, 1, 18, 4, C(ramp, "shadow"))
    c.rect(7, 0, 16, 1, C(ramp, "light"))
    c.rect(8, 2, 15, 3, C("bulkhead", "ink"))
    return [c.outline()]


def acid_pool():
    out = []
    for i in range(3):
        c = Cv(32, 14)
        c.rect(0, 5, 31, 13, C("teal", "high", 220))
        c.rect(0, 5, 31, 6, AQUA)
        for x in range(2 + i * 3, 30, 9):
            c.px(x, 4, AQUA)
            c.px(x + 1, 3 - (i % 2), AQUA)
        c.rect(0, 11, 31, 13, C("teal", "face", 230))
        out.append(c)
    return out


def debris_rock():
    out = []
    for i in range(2):  # 0 rock, 1 crack plate (ceiling)
        c = Cv(32, 20) if i else Cv(20, 20)
        if i == 0:
            c.poly([(3, 12), (6, 3), (14, 2), (18, 9), (15, 17), (6, 18)], C("bulkhead", "light"))
            c.poly([(8, 8), (14, 6), (15, 15), (8, 16)], C("bulkhead", "shadow"))
            c.outline()
        else:
            c.rect(0, 0, 31, 7, C("bulkhead", "face"))
            ink = C("bulkhead", "ink")
            c.line([(14, 0), (17, 5), (13, 9), (18, 15)], ink)
            c.line([(17, 5), (23, 7)], ink)
        out.append(c)
    return out


def conveyor():
    out = []
    for i in range(4):
        c = Cv(32, 14)
        c.box(0, 3, 31, 12, "bulkhead")
        c.rect(0, 3, 31, 5, C("bulkhead", "ink"))
        for x in range(-8 + i * 2, 32, 8):
            if x + 2 >= 0:
                c.rect(max(x, 0), 3, min(x + 2, 31), 5, C("hazard", "face"))
        c.ell(0, 9, 5, 14, C("steel", "face"))
        c.ell(26, 9, 31, 14, C("steel", "face"))
        out.append(c)
    return out


def platform():
    out = []
    for i in range(3):  # left cap, mid, right cap
        c = Cv(32, 14)
        c.box(0, 0, 31, 9, "steel")
        c.rect(0, 0, 31, 1, C("steel", "high"))
        c.rect(0, 8, 31, 9, C("steel", "ink"))
        for x in range(4, 28, 8):
            c.rect(x, 4, x + 3, 5, C("steel", "shadow"))
        if i == 0:
            c.rect(0, 0, 1, 9, C("steel", "ink"))
        if i == 2:
            c.rect(30, 0, 31, 9, C("steel", "ink"))
        c.rect(12, 10, 19, 13, C("hazard", "shadow"))  # thruster
        out.append(c)
    return out


def bolt():
    out = []
    for i in range(2):
        c = Cv(20, 12)
        c.ell(6, 2, 17, 9, C("rust", "high"))
        c.ell(9, 3, 17, 8, SODIUM)
        c.ell(12, 4, 17, 7, HOT)
        c.rect(0 + i, 5, 7, 6, C("rust", "face"))
        c.rect(2 - i, 4, 4, 7, (255, 140, 41, 120))
        out.append(c)
    return out


def bomb():
    out = []
    for i in range(2):
        c = Cv(16, 16)
        c.ell(2, 3, 13, 14, C("steel", "shadow"))
        c.ell(3, 4, 11, 11, C("steel", "face"))
        c.rect(7, 0, 8, 3, C("steel", "light"))
        c.px(7, 0, SODIUM if i else HOT)
        c.rect(6, 8, 9, 10, RED if i else C("rust", "face"))
        out.append(c.outline())
    return out


def spark_ball():
    out = []
    for i in range(2):
        c = Cv(12, 12)
        c.ell(2, 2, 9, 9, AQUA if i else C("teal", "high"))
        c.ell(4, 4, 7, 7, HOT)
        c.px(0, 6, AQUA)
        c.px(11, 5, AQUA)
        c.px(6, 0 + i, AQUA)
        c.px(5, 11, AQUA)
        out.append(c)
    return out


# collectibles: each 24x24, one idle frame + one glint frame
def _item(drawfn):
    out = []
    for g in (0, 1):
        c = Cv(24, 24)
        drawfn(c)
        if g:
            for (x, y) in ((4, 4), (19, 8)):
                c.line([(x - 2, y), (x + 2, y)], HOT)
                c.line([(x, y - 2), (x, y + 2)], HOT)
        out.append(c.outline())
    return out


def i_fish(c):
    f = hex_to_rgb("#e89a7a") + (255,)
    c.poly([(3, 12), (9, 6), (17, 8), (20, 12), (17, 16), (9, 18)], f)
    c.poly([(19, 12), (23, 7), (23, 17)], C("maroon", "high"))
    c.rect(6, 12, 15, 13, C("maroon", "high"))
    c.rect(6, 9, 13, 9, hex_to_rgb("#f7c8b0") + (255,))
    c.px(7, 11, INKC)
    c.px(12, 10, C("maroon", "light"))
    c.px(12, 14, C("maroon", "light"))


def i_yarn(c):
    r = C("maroon", "high")
    c.ell(3, 3, 20, 20, r)
    c.ell(3, 3, 20, 20, r)
    c.arc = None
    for (a, b) in (((5, 9), (17, 6)), ((4, 13), (19, 11)), ((6, 17), (17, 17)), ((8, 5), (11, 19))):
        c.line([a, b], C("maroon", "shadow"))
    c.line([(14, 5), (19, 3), (22, 6)], r)
    c.rect(7, 6, 9, 7, C("maroon", "spec"))


def i_bell(c):
    g = GOLD
    c.poly([(5, 17), (6, 9), (12, 3), (18, 9), (19, 17)], g)
    c.rect(4, 16, 19, 18, hex_to_rgb("#e0a82e") + (255,))
    c.rect(8, 6, 9, 14, hex_to_rgb("#fff0a8") + (255,))
    c.ell(10, 17, 14, 21, hex_to_rgb("#a8741e") + (255,))
    c.rect(11, 1, 12, 3, C("maroon", "high"))


def i_mouse(c):
    b = hex_to_rgb("#b9b6c2") + (255,)
    pink = hex_to_rgb("#e8a0a8") + (255,)
    c.ell(5, 9, 19, 19, b)
    c.poly([(16, 12), (22, 14), (16, 18)], b)
    c.ell(14, 5, 19, 10, pink)
    c.ell(9, 5, 13, 9, pink)
    c.px(20, 14, INKC)
    c.px(21, 14, pink)
    c.line([(5, 15), (2, 12), (1, 8)], pink)
    c.rect(11, 12, 12, 13, C("steel", "shadow"))


def i_bone(c):
    g = GOLD
    c.line([(6, 16), (17, 8)], g, 4)
    for (x, y) in ((4, 15), (6, 19), (17, 5), (20, 9)):
        c.ell(x - 2, y - 2, x + 2, y + 2, g)
    c.line([(7, 14), (15, 9)], hex_to_rgb("#fff0a8") + (255,))


def i_chip(c):
    c.box(5, 5, 18, 18, "steel")
    c.rect(8, 8, 15, 15, C("bulkhead", "ink"))
    c.rect(10, 10, 13, 13, AQUA)
    for k in range(6, 18, 3):
        c.rect(k, 3, k + 1, 4, C("hazard", "high"))
        c.rect(k, 19, k + 1, 20, C("hazard", "high"))
        c.rect(3, k, 4, k + 1, C("hazard", "high"))
        c.rect(19, k, 20, k + 1, C("hazard", "high"))


def i_memory(c):
    w = hex_to_rgb("#f4e8ff") + (255,)
    c.poly([(12, 1), (19, 8), (16, 20), (8, 22), (4, 11)], w)
    c.poly([(12, 1), (16, 12), (8, 22), (4, 11)], hex_to_rgb("#c9b6e8") + (255,))
    c.line([(12, 4), (11, 18)], HOT)
    c.px(8, 9, AQUA)
    c.px(15, 15, AQUA)


def debris_chunk():
    out = []
    for i in range(3):
        c = Cv(8, 8)
        pts = [[(1, 5), (3, 1), (6, 2), (6, 6)], [(1, 2), (6, 1), (5, 6), (2, 6)], [(2, 1), (6, 3), (4, 6), (1, 4)]][i]
        c.poly(pts, C("steel", "face"))
        c.px(3, 2, C("steel", "light"))
        out.append(c)
    return out


# ---------------------------------------------------------------- manifest

def part(frames, anims, pivot, offset=(0, 0), file=None, cell=None):
    return dict(frames=frames, anims=anims, pivot=pivot, offset=offset, file=file, cell=cell)


def A(frames, fps=8.0, loop=True):
    return {"frames": frames, "fps": fps, "loop": loop}


ACTORS = {
    "sentry_turret": dict(scale=1.0, main="body", parts={
        "body": part(sentry_body(), {"idle": A([0], 1), "stun": A([1], 1)}, (16, 24)),
        "head": part(sentry_head(), {"idle": A([0], 1), "charge": A([1, 2, 3], 5, False), "fire": A([4], 1),
                                     "stun": A([5, 6], 10)}, (16, 16), (0, -17)),
    }),
    "patrol_bot": dict(scale=0.7, main="body", parts={
        "body": part(None, {"walk": A([0, 1, 2, 3, 4, 5, 6], 9), "stun": A([3], 1), "aim": A([3], 1)}, (40, 64),
                     file="assets/art_hd/robots/bipedal.png", cell=(80, 64)),
    }),
    "hover_drone": dict(scale=1.0, main="body", pivot="center", parts={
        "body": part(hover_drone(), {"fly": A([0, 1, 2, 1], 14), "arm": A([3], 1), "stun": A([4], 1)}, (20, 16)),
    }),
    "hopper_bot": dict(scale=1.0, main="body", parts={
        "body": part(hopper(), {"idle": A([0], 1), "squat": A([1], 1), "up": A([2], 1), "fall": A([3], 1),
                                "stun": A([4], 1)}, (16, 32)),
    }),
    "crawler": dict(scale=1.0, main="body", parts={
        "body": part(crawler(), {"crawl": A([0, 1, 2, 3], 7), "roll": A([4, 5, 6, 7], 16), "stun": A([8], 1),
                                 "tell": A([9], 1)}, (16, 32)),
    }),
    "security_camera": dict(scale=1.0, main="mount", pivot="center", parts={
        "mount": part(cam_body(), {"idle": A([0], 1)}, (8, 8)),
        "head": part(cam_head(), {"idle": A([0], 1), "alarm": A([1], 1), "stun": A([2], 1)}, (8, 12)),
    }),
    "heavy_mech": dict(scale=0.75, main="body", parts={
        "body": part(None, {"walk": A([0, 1, 2, 3, 4, 5, 6, 7, 8, 9], 9), "stun": A([4], 1), "charge": A([2, 7], 12)},
                     (48, 80), file="assets/art_hd/robots/mech.png", cell=(96, 80)),
    }),
    "barrel_plain": dict(scale=1.0, main="body", parts={
        "body": part(barrel("plain"), {"idle": A([0], 1), "hit": A([1], 1)}, (16, 36))}),
    "barrel_explosive": dict(scale=1.0, main="body", parts={
        "body": part(barrel("explosive"), {"idle": A([0], 1), "lit": A([0, 1], 10)}, (16, 36))}),
    "barrel_acid": dict(scale=1.0, main="body", parts={
        "body": part(barrel("acid"), {"idle": A([0], 1), "leak": A([2], 1)}, (16, 36))}),
    "wall_cracked": dict(scale=1.0, main="tile", parts={
        "tile": part(wall_tile("cracked"), {"idle": A([0], 1), "hit": A([1], 1)}, (16, 32))}),
    "wall_reinforced": dict(scale=1.0, main="tile", parts={
        "tile": part(wall_tile("reinforced"), {"idle": A([0], 1), "hit": A([1], 1)}, (16, 32))}),
    "wall_blast": dict(scale=1.0, main="tile", parts={
        "tile": part(wall_tile("blast"), {"idle": A([0], 1), "hit": A([1], 1)}, (16, 32))}),
    "electric_floor": dict(scale=1.0, main="panel", parts={
        "panel": part(electric_panel(), {"off": A([0], 1), "warn": A([1], 1), "live": A([2], 1)}, (16, 8))}),
    "crusher": dict(scale=1.0, main="head", parts={
        "head": part(crusher(), {"idle": A([0], 1), "warn": A([1], 1)}, (16, 0)),
        "rod": part(piston_rod(), {"idle": A([0], 1)}, (4, 0))}),
    "spike_trap": dict(scale=1.0, main="body", parts={
        "body": part(spike_trap(), {"down": A([0], 1), "warn": A([1], 1), "up": A([2], 1)}, (16, 17))}),
    "vent_steam": dict(scale=1.0, main="nozzle", parts={
        "nozzle": part(vent_nozzle("steam"), {"idle": A([0], 1)}, (12, 10))}),
    "vent_flame": dict(scale=1.0, main="nozzle", parts={
        "nozzle": part(vent_nozzle("flame"), {"idle": A([0], 1)}, (12, 10))}),
    "acid_pool": dict(scale=1.0, main="pool", parts={
        "pool": part(acid_pool(), {"bubble": A([0, 1, 2], 4)}, (16, 14))}),
    "falling_debris": dict(scale=1.0, main="rock", parts={
        "rock": part(debris_rock()[:1], {"idle": A([0], 1)}, (10, 10)),
        "crack": part(debris_rock()[1:], {"idle": A([0], 1)}, (16, 0))}),
    "conveyor": dict(scale=1.0, main="belt", parts={
        "belt": part(conveyor(), {"run": A([0, 1, 2, 3], 10)}, (16, 3))}),
    "platform": dict(scale=1.0, main="plate", parts={
        "plate": part(platform(), {"left": A([0], 1), "mid": A([1], 1), "right": A([2], 1)}, (16, 0))}),
    "bolt": dict(scale=1.0, main="body", pivot="center", parts={
        "body": part(bolt(), {"fly": A([0, 1], 14)}, (10, 6))}),
    "bomb": dict(scale=1.0, main="body", pivot="center", parts={
        "body": part(bomb(), {"fall": A([0, 1], 6)}, (8, 8))}),
    "spark": dict(scale=1.0, main="body", pivot="center", parts={
        "body": part(spark_ball(), {"fly": A([0, 1], 16)}, (6, 6))}),
    "debris_chunk": dict(scale=1.0, main="body", pivot="center", parts={
        "body": part(debris_chunk(), {"a": A([0], 1), "b": A([1], 1), "c": A([2], 1)}, (4, 4))}),
}
for _n, _d, _fn in (("fish", "heals", i_fish), ("yarn", "100", i_yarn), ("bell", "250", i_bell),
                    ("mouse", "500", i_mouse), ("bone", "2000", i_bone), ("chip", "1000", i_chip),
                    ("memory", "5000", i_memory)):
    ACTORS["pickup_" + _n] = dict(scale=1.0, main="body", pivot="center", parts={
        "body": part(_item(_fn), {"idle": A([0], 1), "glint": A([0, 1], 3)}, (12, 12))})


def alpha_bounds(im, cell, pivot, offset):
    """Union of opaque pixels over all frames, relative to the pivot (px)."""
    cw, ch = cell
    x0, y0, x1, y1 = 10 ** 6, 10 ** 6, -10 ** 6, -10 ** 6
    for i in range(im.size[0] // cw):
        fr = im.crop((i * cw, 0, (i + 1) * cw, ch))
        bb = fr.getchannel("A").point(lambda v: 255 if v > 24 else 0).getbbox()
        if bb:
            x0, y0, x1, y1 = min(x0, bb[0]), min(y0, bb[1]), max(x1, bb[2]), max(y1, bb[3])
    ox, oy = offset
    return [x0 - pivot[0] + ox, y0 - pivot[1] + oy, x1 - x0, y1 - y0]


def main():
    manifest = {"version": 1, "tile": 32,
                "note": "Generated by tools/art/kit_art.py. Replace PNGs keeping cell/pivot/anims, or edit here.",
                "actors": {}}
    for aid, spec in ACTORS.items():
        folder = os.path.join(OUT, aid)
        os.makedirs(folder, exist_ok=True)
        parts_out = {}
        for pname, p in spec["parts"].items():
            if p["file"]:
                rel = p["file"]
                im = Image.open(os.path.join(ROOT, rel)).convert("RGBA")
                cell = list(p["cell"])
            else:
                frames = p["frames"]
                im = strip(frames)
                cell = [frames[0].w, frames[0].h]
                rel = "assets/sprites/kit/%s/%s.png" % (aid, pname)
                im.save(os.path.join(ROOT, rel))
            bounds = alpha_bounds(im, cell, p["pivot"], p["offset"])
            parts_out[pname] = {"file": rel, "cell": cell, "pivot": list(p["pivot"]), "offset": list(p["offset"]),
                                "anims": p["anims"], "bounds": bounds}
        main_p = parts_out[spec["main"]]
        b = list(main_p["bounds"])
        if aid == "sentry_turret":  # the head sits above the base: the actor box covers both
            hb = parts_out["head"]["bounds"]
            x0, y0 = min(b[0], hb[0]), min(b[1], hb[1])
            x1, y1 = max(b[0] + b[2], hb[0] + hb[2]), max(b[1] + b[3], hb[1] + hb[3])
            b = [x0, y0, x1 - x0, y1 - y0]
        manifest["actors"][aid] = {"scale": spec["scale"], "main": spec["main"],
                                   "pivot": spec.get("pivot", "bottom"), "bounds": b, "parts": parts_out}
    # Existing CC0 explosion frames (ansimuz Warped City, CC0): one strip for ExplosionFX.
    src = os.environ.get("EXPLOSION_SRC", "")
    exp = os.path.join(OUT, "fx", "explosion.png")
    if src and os.path.isdir(src):
        os.makedirs(os.path.dirname(exp), exist_ok=True)
        fr = [Image.open(os.path.join(src, "enemy-explosion-%d.png" % i)).convert("RGBA") for i in range(1, 7)]
        im = Image.new("RGBA", (55 * 6, 52), CLEAR)
        for i, f in enumerate(fr):
            im.paste(f, (i * 55, 0))
        im.save(exp)
    if os.path.exists(exp):
        manifest["fx"] = {"explosion": {"file": "assets/sprites/kit/fx/explosion.png", "cell": [55, 52],
                                        "frames": 6, "fps": 14.0,
                                        "credit": "ansimuz Warped City (CC0)"}}
    with open(os.path.join(OUT, "kit_manifest.json"), "w") as f:
        json.dump(manifest, f, indent=1)
    print("kit art:", len(manifest["actors"]), "actors")


if __name__ == "__main__":
    main()
