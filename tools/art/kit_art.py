"""Actor-kit art: scripted pixel art in the Wake Cycle HD palette.

    python3 tools/art/kit_art.py                     # sprites + manifest
    python3 tools/art/kit_art.py --preview DIR [ids] # 4x contact sheets only

Writes assets/sprites/kit/<actor>/<part>.png (horizontal strips) and the
manifest assets/sprites/kit/kit_manifest.json that the game loads (KitArt).
This script IS the art source: every sprite is drawn here, palette-locked to
tools/art/palette.py (RAMPS for world materials, ACTOR_RAMPS for robots and
pickups), lit from the upper left, 1 px INK outline on actors and pickups. Edit
a drawing and re-run; the output is deterministic.

The patrol bot and heavy mech are the ansimuz Legacy robots (CC0), re-pixelled
to 2/3 here (Scale2x, then a 3x3 block-mode reduction and a re-inked edge), so
they sit at the target size at scale 1 with whole pixels. The explosion
fireball is ansimuz Warped City (CC0), packed once from EXPLOSION_SRC.

Sizes (the B' scale study): enemies 1 to 1.35 tiles (32 to 44 px) tall,
destructibles and hazards on the 32 px grid, pickups 12 to 20 px. Every actor
is drawn at its in-game pixel size, so every manifest scale is 1.0.

The manifest is the contract with the game: cell, pivot (origin inside a
cell), animations, and bounds (opaque pixels relative to the pivot; colliders
derive from them).
"""
import json
import math
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(__file__))
from kit_pix import INK, Spr, rgb, strip  # noqa: E402
from palette import ACTOR_RAMPS, RAMPS  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "sprites", "kit")
CLEAR = (0, 0, 0, 0)


def R(name):
    """A ramp as RGBA tuples, dark to light."""
    if name in ACTOR_RAMPS:
        return [rgb(h) for h in ACTOR_RAMPS[name]]
    r = RAMPS[name]
    return [rgb(r[k]) for k in ("ink", "shadow", "face", "light", "high", "spec")]


AMB = R("amber")          # deep, shadow, dark face, face, light, high
AM = AMB[1:]              # 5 lit stops
JT = R("joint")
SN = R("sensor")
SH = R("shell")
ST6 = R("steel")          # ink, shadow, face, light, high, spec
BH6 = R("bulkhead")
BH = BH6[1:5]
HZ6 = R("hazard")
RU6 = R("rust")
INKC = INK
LASER = rgb("#ff4a3a")
HOT = rgb("#fff0e0")
SODIUM = rgb("#ff8c29")
SPARKC = rgb("#ffc866")    # FXPalette.SPARK
LENS = rgb("#3c4a78")
LENS_HI = rgb("#9fb0e0")
WHITE = rgb("#ffffff")


# =========================================================================
# Enemies
# =========================================================================

# ---- sentry turret: body (pedestal) + head (rotates, mirrors) -------------

TURRET_HEAD_Y = -22   # head pivot above the foot (manifest head offset)


def sentry_body():
    out = []
    for stun in (0, 1):
        s = Spr(32, 24)
        # amber foot: a low truncated cone
        s.ppanel([(2, 23), (6, 18), (25, 18), (29, 23)], AM, 2, lit=3, dark=0)
        s.hline(6, 25, 18, AM[4])
        s.line([(3, 22), (6, 19)], AM[3])
        # dark skirt with bolts
        s.rect(3, 21, 28, 23, JT[1])
        s.hline(3, 28, 21, JT[2])
        for x in (6, 12, 19, 25):
            s.px(x, 22, JT[3])
        # violet column with an amber band
        s.cyl_v(10, 10, 21, 17, JT, bias=0.05)
        s.rect(10, 13, 21, 14, AM[2])
        s.hline(10, 21, 13, AM[3])
        s.px(11, 13, AM[4])
        # turntable ring under the head
        s.cyl_h(7, 8, 24, 11, JT, bias=0.1)
        s.hline(8, 23, 8, AM[3])
        s.px(7, 8, CLEAR)
        s.px(24, 8, CLEAR)
        s.outline()
        # status lamp on the column
        s.px(15, 16, SN[0] if stun else LASER)
        s.px(16, 16, SN[0] if stun else SN[3])
        out.append(s)
    return out


def _turret_head(eye, tip, recoil=0, stun=0, flash=0, glow_n=0):
    # cell 32x24, pivot (11, 12); the barrel points +x
    s = Spr(32, 24)
    bx = 16 - recoil
    # barrel behind the housing: violet tube with an amber sleeve
    s.cyl_h(bx, 10, bx + 10, 14, JT, bias=0.05)
    s.rect(bx + 3, 9, bx + 5, 15, AM[2])
    s.vline(bx + 3, 9, 15, AM[3])
    s.hline(bx + 3, bx + 5, 9, AM[4])
    s.hline(bx + 3, bx + 5, 15, AMB[0])
    s.rect(bx + 11, 9, bx + 12, 15, SH[1])
    s.vline(bx + 11, 9, 15, SH[3])
    # housing: armoured dome and jaw
    s.sphere(11, 12, 9, 8, AM, bias=-0.06)
    s.rpanel(4, 15, 17, 19, AM, 1, lit=2, dark=0)
    s.hline(5, 16, 15, AM[3])
    s.line([(5, 8), (8, 6)], AM[4])
    s.px(6, 12, AMB[0])
    s.px(6, 17, AM[0])
    s.px(14, 17, AM[0])
    # visor slit
    s.rect(10, 9, 17, 12, JT[0])
    s.hline(10, 17, 13, AM[1])
    s.hline(11, 16, 8, AM[4])
    s.outline()
    if eye == "red":
        s.rect(14, 10, 16, 11, LASER)
        s.px(16, 10, HOT)
        s.px(13, 11, SN[1])
    elif eye == "hot":
        s.rect(13, 10, 16, 11, HOT)
        s.px(12, 10, LASER)
        s.px(12, 11, LASER)
    elif eye == "dim":
        s.rect(14, 10, 16, 11, SN[0])
    tx = bx + 13
    if tip == "off":
        s.rect(tx, 11, tx, 13, SN[0])
    elif tip == "dim":
        s.rect(tx, 11, tx, 13, SN[1])
    elif tip == "warm":
        s.rect(tx, 10, tx, 14, SN[2])
        s.rect(tx, 11, tx + 1, 13, LASER)
    elif tip == "hot":
        s.rect(tx, 10, tx + 1, 14, LASER)
        s.rect(tx, 11, tx + 2, 13, HOT)
    for (dx, dy) in [(3, 0), (2, -3), (2, 3), (4, -1), (4, 1)][:glow_n]:
        s.px(tx + dx, 12 + dy, LASER)
    if flash:
        for k in range(0, 5):
            s.px(tx + 1 + k, 12, HOT if k < 3 else LASER)
        for (dx, dy) in [(2, -2), (3, -3), (2, 2), (3, 3), (1, -1), (1, 1)]:
            s.px(tx + dx, 12 + dy, LASER)
        s.px(tx + 1, 11, HOT)
        s.px(tx + 1, 13, HOT)
    if stun:
        for (x, y) in ([(4, 3), (19, 6)] if stun == 1 else [(7, 2), (2, 9)]):
            s.px(x, y, SPARKC)
            s.px(x + 1, y + 1, HOT)
    return s


def sentry_head():
    return [
        _turret_head("red", "off"),                       # 0 idle
        _turret_head("red", "dim"),                       # 1 charge
        _turret_head("hot", "warm", glow_n=2),            # 2 charge
        _turret_head("hot", "hot", glow_n=5),             # 3 charge (locked)
        _turret_head("hot", "hot", recoil=2, flash=1),    # 4 fire
        _turret_head("dim", "off", stun=1),               # 5 stun
        _turret_head("off", "off", stun=2),               # 6 stun
    ]


# ---- hover drone ----------------------------------------------------------

def _drone(rotor, bay="shut", eye="red", stun=False):
    # cell 40x32, pivot (20, 16); faces right. Two ducted fans on struts.
    s = Spr(40, 32)
    for (x0, x1) in ((12, 8), (26, 30)):
        s.line([(x0, 12), (x1, 7)], JT[1], 2)
        s.line([(x0, 11), (x1, 6)], JT[2])
    for hx in (7, 31):
        s.ell(hx - 6, 1, hx + 6, 7, SH[1])
        s.hline(hx - 4, hx + 4, 1, SH[3])
        s.hline(hx - 5, hx + 5, 6, JT[1])
        s.ell(hx - 4, 2, hx + 4, 5, JT[0])
    s.sphere(19, 15, 11, 9, SH)
    s.rect(12, 20, 26, 22, SH[1])
    s.hline(13, 25, 20, SH[2])
    s.rect(15, 23, 23, 25, JT[1])
    s.hline(15, 23, 23, JT[2])
    s.px(15, 25, CLEAR)
    s.px(23, 25, CLEAR)
    s.ell(20, 10, 30, 19, JT[0])
    s.rect(22, 11, 29, 17, JT[0])
    s.hline(22, 28, 10, SH[4])
    s.rect(15, 4, 17, 6, SH[2])
    s.hline(15, 17, 4, SH[3])
    s.px(16, 3, SH[1])
    s.line([(11, 13), (11, 17)], SH[1])
    s.line([(13, 12), (13, 17)], SH[1])
    s.outline()
    # fan blades inside the ducts: three angles, the previous one as a ghost
    angles = {0: ((-3, 2), (3, 5)), 1: ((-4, 3), (4, 4)), 2: ((-3, 5), (3, 2))}
    for hx in (7, 31):
        if rotor is None:
            s.line([(hx - 3, 4), (hx + 3, 3)], SH[2])
            continue
        g = angles[(rotor + 2) % 3]
        s.line([(hx + g[0][0], g[0][1]), (hx + g[1][0], g[1][1])], SH[1])
        a = angles[rotor]
        s.line([(hx + a[0][0], a[0][1]), (hx + a[1][0], a[1][1])], SH[3])
        s.px(hx, 3, SH[4])
    if eye == "red":
        s.rect(25, 13, 27, 15, LASER)
        s.px(26, 13, HOT)
        s.px(24, 14, SN[1])
    elif eye == "hot":
        s.rect(24, 12, 28, 15, LASER)
        s.rect(25, 13, 27, 14, HOT)
    else:
        s.rect(25, 13, 27, 15, SN[0])
    if bay == "open":
        s.rect(16, 24, 22, 25, SN[1])
        s.rect(17, 25, 21, 26, LASER)
        s.rect(18, 26, 20, 27, HOT)
        s.px(19, 28, LASER)
    elif bay == "glow":
        s.rect(17, 25, 21, 25, SN[2])
    if stun:
        s.px(9, 9, SPARKC)
        s.px(10, 8, HOT)
        s.px(30, 20, SPARKC)
        s.px(31, 21, HOT)
    return s


def hover_drone():
    return [
        _drone(0), _drone(1), _drone(2),                 # 0-2 fly
        _drone(2, bay="open", eye="hot"),                # 3 arm
        _drone(None, bay="shut", eye="off", stun=True),  # 4 stun
        _drone(0, bay="glow", eye="hot"),                # 5 arm (pulse)
    ]


# ---- hopper bot --------------------------------------------------------------

def _spring(s, x, y0, y1, bend=0):
    """Coil spring from y0 (hip) to y1 (ankle); bend bows the middle."""
    n = y1 - y0
    for k in range(n + 1):
        y = y0 + k
        xx = int(round(x + bend * math.sin(math.pi * k / max(n, 1))))
        if k % 2 == 0:
            s.hline(xx - 1, xx + 1, y, JT[3])
            s.px(xx + 1, y, JT[2])
        else:
            s.hline(xx - 1, xx + 1, y, JT[1])


def _hopper(pose):
    # cell 32x40, pivot (16, 40); faces right
    s = Spr(32, 40)
    eye = "red"
    if pose == "idle":
        cy, rx, ry, hip, foot, bend = 20, 10, 9, 27, 37, 0
    elif pose == "squat":
        cy, rx, ry, hip, foot, bend = 27, 11, 8, 33, 37, 2
        eye = "hot"
    elif pose == "up":
        cy, rx, ry, hip, foot, bend = 17, 9, 10, 25, 38, 0
    elif pose == "fall":
        cy, rx, ry, hip, foot, bend = 17, 10, 9, 24, 35, -1
    else:  # stun
        cy, rx, ry, hip, foot, bend = 26, 11, 8, 32, 37, 2
        eye = "off"
    for lx, ph in ((11, 0), (21, 1)):
        fx = lx + (2 if pose == "fall" else 0)
        _spring(s, lx, hip, foot - 2, bend if ph == 0 else -bend)
        s.rpanel(fx - 3, foot - 1, fx + 3, foot + 1, AM, 2, lit=3, dark=0)
        s.hline(fx - 2, fx + 2, foot - 1, AM[4])
    tilt = 2 if pose == "stun" else 0
    s.sphere(16, cy, rx, ry, AM, bias=-0.06)
    s.rect(16 - rx + 3, cy + ry - 4, 16 + rx - 3, cy + ry - 2, JT[1])
    s.hline(16 - rx + 3, 16 + rx - 3, cy + ry - 4, JT[2])
    for lx in (11, 21):
        s.rect(lx - 1, hip - 2, lx + 1, hip, JT[1])
        s.px(lx - 1, hip - 2, JT[3])
    vy = cy - 2 + tilt
    s.rect(16 - rx + 6, vy, 16 + rx - 1, vy + 4, JT[0])
    s.hline(16 - rx + 7, 16 + rx - 2, vy - 1, AM[4])
    s.line([(16 - rx + 3, cy - 4), (16 - 3, cy - ry + 1)], AM[4])
    ax = 13
    top = cy - ry
    s.vline(ax, top - 5, top - 1, JT[2])
    s.outline()
    lamp = LASER if pose == "squat" else (SN[0] if pose == "stun" else SODIUM)
    s.rect(ax - 1, top - 7, ax, top - 6, lamp)
    if pose == "squat":
        s.px(ax + 1, top - 7, LASER)
    ex = 16 + rx - 5
    if eye == "red":
        s.rect(ex, vy + 1, ex + 2, vy + 2, LASER)
        s.px(ex + 2, vy + 1, HOT)
    elif eye == "hot":
        s.rect(ex - 2, vy + 1, ex + 3, vy + 3, LASER)
        s.rect(ex - 1, vy + 1, ex + 2, vy + 2, HOT)
    else:
        s.rect(ex, vy + 1, ex + 2, vy + 2, SN[0])
        s.px(4, cy - 4, SPARKC)
        s.px(5, cy - 5, HOT)
        s.px(27, cy - 1, SPARKC)
    return s


def hopper():
    return [_hopper(p) for p in ("idle", "squat", "up", "fall", "stun")]


# ---- crawler -----------------------------------------------------------------

# Leg poses (hip, knee, foot) for the near side; the far side is the same
# shifted 2 px and drawn darker behind the body. Tripod gait over 4 frames.
_CRAWL_LEGS = {
    "a": [((11, 19), (6, 16), (4, 27)), ((17, 20), (15, 23), (13, 27)), ((23, 19), (28, 16), (30, 27))],
    "b": [((11, 19), (7, 15), (7, 25)), ((17, 20), (19, 22), (19, 25)), ((23, 19), (29, 15), (32, 25))],
    "ab": [((11, 19), (6, 16), (5, 26)), ((17, 20), (17, 22), (16, 26)), ((23, 19), (28, 16), (31, 26))],
}


def _crawler_leg_set(s, pose, cols, dx=0, splay=0):
    for i, (h, k, f) in enumerate(_CRAWL_LEGS[pose]):
        sp = (-splay if i == 0 else (splay if i == 2 else 0))
        hh = (h[0] + dx, h[1])
        kk = (k[0] + dx + sp, k[1])
        ff = (f[0] + dx + sp * 2, f[1])
        s.line([hh, kk], cols[0])
        s.line([kk, ff], cols[1])
        s.px(kk[0], kk[1], cols[2])


def _crawler_body(phase, eye="red", splay=0):
    s = Spr(34, 28)
    near = ["a", "ab", "b", "ab"][phase]
    far = ["b", "ab", "a", "ab"][phase]
    _crawler_leg_set(s, far, (JT[1], JT[1], JT[2]), dx=-2, splay=splay)
    m = s.sphere(17, 18, 12, 10, JT, bias=0.08)
    clip = np.zeros_like(m)
    clip[20:, :] = True
    s.a[m & clip] = 0
    # amber armour segments
    for bx in (11, 17, 23):
        for y in range(9, 19):
            if s.opaque(bx, y) and s.opaque(bx + 1, y) and s.get(bx, y)[3]:
                s.px(bx, y, AM[3] if y < 13 else AM[2])
                s.px(bx + 1, y, AM[2] if y < 13 else AM[1])
    s.rect(7, 19, 27, 20, JT[0])
    s.hline(8, 26, 19, JT[1])
    # head with mandibles
    s.rect(26, 14, 30, 19, JT[1])
    s.hline(26, 30, 14, JT[2])
    s.px(31, 18, AM[2])
    s.px(31, 19, AM[1])
    # spikes along the back, normal to the dome
    for ang in (-155, -125, -90, -55, -25):
        a = math.radians(ang)
        bx, by = 17.5 + math.cos(a) * 11.0, 18.5 + math.sin(a) * 9.0
        tx, ty = 17.5 + math.cos(a) * 16.5, 18.5 + math.sin(a) * 14.0
        nx, ny = -math.sin(a) * 1.5, math.cos(a) * 1.5
        s.poly([(bx + nx, by + ny), (bx - nx, by - ny), (tx, ty)], ST6[3])
        s.line([(bx - nx * 0.6, by - ny * 0.6), (tx, ty)], ST6[4])
    _crawler_leg_set(s, near, (JT[2], JT[3], JT[3]), splay=splay)
    s.outline()
    if eye == "red":
        s.pxs([(28, 16), (30, 16), (29, 17)], LASER)
        s.px(29, 16, HOT)
    elif eye == "hot":
        s.rect(27, 16, 31, 17, HOT)
        s.px(26, 16, LASER)
        s.px(26, 17, LASER)
    else:
        s.pxs([(28, 16), (30, 16), (29, 17)], SN[0])
    return s


def _crawler_ball(deg):
    s = Spr(34, 28)
    cx, cy, r = 17, 15, 9
    ball = Spr(34, 28)
    ball.sphere(cx, cy, r + 1, r + 1, JT, bias=0.08)
    for k in range(2):
        a = math.radians(deg + k * 90)
        for t in range(-r, r + 1):
            x = cx + 0.5 + math.cos(a) * t
            y = cy + 0.5 + math.sin(a) * t
            if ball.opaque(int(x), int(y)):
                ball.px(int(x), int(y), AM[2])
    s.paste(ball)
    for k in range(8):
        a = math.radians(deg + k * 45 + 22.5)
        bx, by = cx + 0.5 + math.cos(a) * (r + 0.5), cy + 0.5 + math.sin(a) * (r + 0.5)
        tx, ty = cx + 0.5 + math.cos(a) * (r + 4.5), cy + 0.5 + math.sin(a) * (r + 4.5)
        nx, ny = -math.sin(a) * 1.6, math.cos(a) * 1.6
        s.poly([(bx + nx, by + ny), (bx - nx, by - ny), (tx, ty)], ST6[3])
        s.px(tx, ty, ST6[4])
    s.outline()
    s.px(cx - 4, cy - 6, JT[3])
    s.px(cx - 5, cy - 5, JT[3])
    s.px(cx - 6, cy - 4, JT[2])
    a = math.radians(deg)
    s.px(cx + math.cos(a) * 5, cy + math.sin(a) * 5, LASER)
    return s


def _crawler_flipped():
    s = Spr(34, 28)
    m = s.sphere(17, 18, 12, 9, JT, bias=0.08)
    clip = np.zeros_like(m)
    clip[:17, :] = True
    s.a[m & clip] = 0
    s.rect(6, 16, 28, 17, JT[0])
    for bx in (11, 17, 23):
        for y in range(18, 27):
            if s.opaque(bx, y) and s.opaque(bx + 1, y):
                s.px(bx, y, AM[2])
                s.px(bx + 1, y, AM[1])
    for (hx, kx, ky, fx, fy) in ((10, 8, 12, 11, 10), (17, 16, 11, 18, 9), (24, 26, 12, 23, 10)):
        s.line([(hx, 16), (kx, ky)], JT[2])
        s.line([(kx, ky), (fx, fy)], JT[1])
    s.rect(27, 18, 30, 21, JT[1])
    s.outline()
    s.pxs([(28, 19), (30, 19)], SN[0])
    s.px(6, 12, SPARKC)
    s.px(5, 11, HOT)
    s.px(29, 13, SPARKC)
    return s


def crawler():
    frames = [_crawler_body(p) for p in range(4)]
    frames += [_crawler_ball(d) for d in (0, 11.25, 22.5, 33.75)]
    frames.append(_crawler_flipped())                     # 8 stun
    frames.append(_crawler_body(1, eye="hot", splay=2))    # 9 tell
    return frames


# ---- security camera -----------------------------------------------------------

def cam_mount():
    # cell 16x14, pivot (8, 0): hangs from the ceiling surface; the swivel ball
    # at (8, 9) is the head's pivot (manifest head offset)
    s = Spr(16, 14)
    s.rpanel(3, 0, 12, 2, BH, 1)
    s.hline(4, 11, 0, BH[2])
    s.px(4, 1, BH[3])
    s.px(11, 1, BH[3])
    s.rect(7, 3, 8, 7, SH[1])
    s.vline(7, 3, 7, SH[2])
    s.sphere(8, 9, 3, 3, SH)
    s.outline()
    return [s]


def _cam_head(mode):
    # cell 24x12, pivot (5, 6): the housing points +x from the swivel
    s = Spr(24, 12)
    s.rect(3, 4, 7, 8, SH[1])
    s.cyl_h(5, 3, 17, 9, SH, bias=0.02)
    s.rect(6, 1, 20, 2, SH[2])
    s.hline(6, 20, 1, SH[3])
    s.vline(20, 1, 3, SH[1])
    s.vline(8, 4, 8, SH[1])
    s.vline(10, 4, 8, SH[1])
    s.rect(17, 3, 19, 9, JT[1])
    s.vline(17, 3, 9, JT[2])
    s.outline()
    lens = [(20, 4), (20, 5), (20, 6), (20, 7), (20, 8), (19, 5), (19, 6), (19, 7)]
    if mode in ("idle", "idle_off"):
        s.pxs(lens, LENS)
        s.px(19, 5, LENS_HI)
        s.px(20, 8, JT[0])
    elif mode in ("alarm", "alarm2"):
        s.pxs(lens, SODIUM if mode == "alarm" else HOT)
        s.px(21, 6, SODIUM)
        s.px(21, 7, SODIUM)
        if mode == "alarm2":
            s.px(22, 6, LASER)
            s.px(22, 7, LASER)
    else:
        s.pxs(lens, JT[0])
        s.px(19, 7, SH[2])
        s.px(20, 5, SH[2])
    on = {"idle": LASER, "idle_off": SN[0], "alarm": LASER, "alarm2": HOT, "stun": SN[0]}[mode]
    s.px(8, 0, on)
    s.px(9, 0, on)
    if mode == "stun":
        s.px(12, 10, SPARKC)
        s.px(13, 11, HOT)
        s.px(22, 2, SPARKC)
    return s


def cam_head():
    return [_cam_head(m) for m in ("idle", "idle_off", "alarm", "alarm2", "stun")]


# =========================================================================
# Destructibles
# =========================================================================

AC6 = R("acid")
PR = R("paint_red")


# Drum shading across its 20 px width (ramp index, 0 = darkest): a narrow
# highlight a third in from the lit edge, a broad face, a core shadow and a
# faint bounce light on the far rim.
DRUM = [2, 3, 3, 4, 3, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 0, 0, 1, 0]
HOOPS = (9, 26)


def _barrel_shape(s, rmp, dark=0):
    """20 px upright drum, x 2..21, y 2..32: lid, two hoops, chimes."""
    for k, v in enumerate(DRUM):
        s.vline(2 + k, 5, 31, rmp[max(0, v - dark)])
    s.px(2, 31, CLEAR)
    s.px(21, 31, CLEAR)
    for y in HOOPS:
        for k, v in enumerate(DRUM):
            s.px(2 + k, y, rmp[min(len(rmp) - 1, max(0, v - dark) + 1)])
            s.px(2 + k, y + 1, rmp[0])
    s.hline(3, 20, 31, rmp[0])
    # lid seen from slightly above
    s.ell(2, 2, 21, 7, rmp[1])
    s.ell(3, 2, 20, 6, rmp[2])
    s.hline(5, 18, 2, rmp[3])
    s.ell(5, 3, 18, 5, rmp[1])
    s.rect(14, 3, 16, 4, rmp[3])
    s.hline(14, 16, 5, rmp[0])


def barrel(kind):
    out = []
    for i in range(3):  # 0 idle, 1 lit (pre-blast flash) / hit, 2 leak
        s = Spr(24, 34)
        if kind == "plain":
            _barrel_shape(s, ST6[1:6], dark=1)
            # stencil plate
            s.rect(6, 15, 15, 20, ST6[1])
            s.hline(6, 15, 15, ST6[0])
            s.hline(8, 13, 17, ST6[3])
            s.hline(8, 11, 19, ST6[3])
            if i == 1:  # dent
                s.pxs([(17, 16), (18, 17), (18, 18), (17, 19)], ST6[0])
                s.pxs([(16, 17), (16, 18)], ST6[3])
        elif kind == "explosive":
            _barrel_shape(s, PR)
            # hazard bands under the top hoop and over the bottom hoop
            for y0 in (11, 23):
                for y in range(y0, y0 + 3):
                    for x in range(2, 22):
                        on = ((x + y) // 2) % 2 == 0
                        s.px(x, y, (HZ6[3] if x < 12 else HZ6[2]) if on else HZ6[0])
            # flame pictogram in a white diamond
            for dy in range(-4, 5):
                w = 4 - abs(dy)
                s.hline(10 - w, 10 + w, 18 + dy, rgb("#f4ecd8"))
            s.pxs([(10, 15), (9, 16), (10, 16), (11, 17), (9, 18), (10, 18), (11, 18), (9, 19), (10, 19),
                   (11, 19), (10, 20)], HZ6[0])
            s.pxs([(10, 18), (10, 19)], PR[2])
        else:  # acid
            _barrel_shape(s, AC6[1:6], dark=1)
            # dark label band with a drip glyph
            s.rect(2, 14, 21, 21, AC6[0])
            s.hline(3, 20, 14, AC6[1])
            s.pxs([(10, 15), (9, 16), (10, 16), (11, 16), (8, 17), (9, 17), (10, 17), (11, 17), (12, 17),
                   (8, 18), (9, 18), (10, 18), (11, 18), (12, 18), (9, 19), (10, 19), (11, 19)], AC6[3])
            s.px(9, 17, AC6[5])
            for x in (4, 6, 15, 17):
                s.px(x, 20, AC6[2])
        s.outline()
        if kind == "explosive" and i == 1:
            # fuse lit: spark at the bung, the paint glows hot
            s.px(15, 1, HOT)
            s.px(16, 0, SPARKC)
            s.px(14, 0, SPARKC)
            s.px(17, 1, SODIUM)
            s.recolor(PR[3], PR[4])
        if kind == "acid" and i == 2:
            # split seam leaking down the side
            s.pxs([(17, 11), (18, 12), (17, 13)], AC6[0])
            for y in range(13, 33):
                s.px(18, y, AC6[4] if y % 5 else AC6[5])
            s.rect(16, 32, 21, 33, AC6[3])
            s.hline(17, 20, 32, AC6[4])
        out.append(s)
    return out


def _brick_tile(s, rmp):
    """Four staggered courses of masonry on a 32 px tile (tiles seamlessly)."""
    s.rect(0, 0, 31, 31, rmp[1])
    for row in range(4):
        y0 = row * 8
        off = 0 if row % 2 == 0 else 8
        for bx in range(-16, 32, 16):
            x0 = bx + off
            x1 = x0 + 14
            xa, xb = max(x0, 0), min(x1, 31)
            if xb < xa:
                continue
            s.rect(xa, y0, xb, y0 + 6, rmp[2])
            s.hline(xa, xb, y0, rmp[3])
            if x0 >= 0:
                s.vline(x0, y0, y0 + 6, rmp[3])
            s.hline(xa, xb, y0 + 6, rmp[1])
            if x1 <= 31:
                s.vline(x1, y0 + 1, y0 + 6, rmp[1])
        s.hline(0, 31, y0 + 7, rmp[0])
        for x in range(0, 32):
            if (x - off) % 16 == 15:
                s.vline(x, y0, y0 + 6, rmp[0])


def _crack(s, pts, dark, lit, branch=()):
    for a, b in zip(pts, pts[1:]):
        s.line([a, b], dark)
    for a, b in zip(pts, pts[1:]):
        s.line([(a[0] + 1, a[1]), (b[0] + 1, b[1])], lit)
    for a, b in zip(pts, pts[1:]):
        s.line([a, b], dark)
    for br in branch:
        for a, b in zip(br, br[1:]):
            s.line([a, b], dark)


def wall_tile(kind):
    out = []
    for i in range(2):  # 0 intact, 1 struck
        s = Spr(32, 32)
        if kind == "cracked":
            _brick_tile(s, R("maroon")[0:5])
            ink = R("maroon")[0]
            lit = R("maroon")[4]
            # the crack enters the top and leaves the bottom at x 15, so stacked tiles join
            _crack(s, [(15, 0), (13, 5), (16, 10), (12, 15), (17, 21), (14, 26), (15, 31)], ink, lit,
                   branch=[[(16, 10), (22, 12), (26, 9)], [(12, 15), (6, 17), (3, 21)], [(17, 21), (23, 24)]])
            # chipped corners showing the dark core
            s.pxs([(0, 8), (1, 8), (0, 9), (30, 23), (31, 23), (31, 22)], ink)
            if i:
                _crack(s, [(22, 12), (27, 16), (30, 15)], ink, lit)
                _crack(s, [(6, 17), (5, 26), (8, 30)], ink, lit)
        elif kind == "reinforced":
            st = ST6
            s.rect(0, 0, 31, 31, st[2])
            s.hline(0, 31, 0, st[3])
            s.vline(0, 0, 31, st[3])
            s.hline(0, 31, 31, st[1])
            s.vline(31, 0, 31, st[1])
            s.hline(1, 30, 1, st[4])
            # X brace in heavy flat bar
            for k in range(-1, 2):
                s.line([(3, 3 + k), (28 + k, 28)], st[1])
                s.line([(3, 28 + k), (28 + k, 3)], st[1])
            s.line([(3, 3), (28, 28)], st[3])
            s.line([(3, 28), (28, 3)], st[3])
            # bolts
            for (bx, by) in ((3, 3), (28, 3), (3, 28), (28, 28), (15, 15)):
                s.rect(bx - 1, by - 1, bx + 1, by + 1, st[1])
                s.px(bx - 1, by - 1, st[5])
                s.px(bx, by - 1, st[4])
            # hairline cracks: breakable, but it takes a pound
            _crack(s, [(9, 0), (11, 5), (8, 9)], st[0], st[4])
            _crack(s, [(22, 31), (20, 26), (24, 22)], st[0], st[4])
            if i:
                _crack(s, [(8, 9), (12, 13), (10, 18)], st[0], st[4])
                _crack(s, [(24, 22), (21, 18)], st[0], st[4])
        else:  # blast-only
            bh = BH6
            s.rect(0, 0, 31, 31, bh[2])
            s.hline(0, 31, 0, bh[3])
            s.vline(0, 0, 31, bh[3])
            s.hline(0, 31, 31, bh[1])
            s.vline(31, 0, 31, bh[1])
            # hazard stripe band
            for y in range(11, 21):
                for x in range(1, 31):
                    on = ((x + y) // 4) % 2 == 0
                    s.px(x, y, HZ6[2] if on else HZ6[0])
            s.hline(1, 30, 10, bh[0])
            s.hline(1, 30, 11, HZ6[3])
            s.hline(1, 30, 21, bh[0])
            # bolted corners and edge bolts
            for (bx, by) in ((3, 3), (28, 3), (3, 28), (28, 28), (15, 4), (16, 27)):
                s.rect(bx - 1, by - 1, bx + 1, by + 1, bh[1])
                s.px(bx - 1, by - 1, bh[5])
                s.px(bx, by - 1, bh[4])
            # a blast crack across the stripes
            _crack(s, [(6, 6), (10, 13), (8, 18), (13, 25)], bh[0], bh[4],
                   branch=[[(10, 13), (16, 15)]])
            if i:
                _crack(s, [(16, 15), (23, 17), (26, 24)], bh[0], bh[4])
        if i:
            # struck: dust at the crack mouths
            s.pxs([(4, 1), (27, 2), (2, 29)], rgb("#c9b8b0"))
        out.append(s)
    return out


# =========================================================================
# Hazards
# =========================================================================

ARC = rgb("#f4f8ff")       # hostile electricity: silver-white core
ARC_HALO = rgb("#9fb4ff")  # pale moon-blue halo (well off the PHASE cyan)


def electric_panel():
    # cell 32x10, pivot (16, 8): rows 0-7 above the floor, 8-9 in the floor's lip
    def base():
        s = Spr(32, 10)
        s.rect(0, 5, 31, 9, BH6[1])
        s.hline(0, 31, 5, BH6[3])
        s.hline(0, 31, 9, BH6[0])
        for x in range(0, 32):
            for y in (6, 7):
                if ((x + y) // 2) % 2 == 0:
                    s.px(x, y, HZ6[2] if y == 6 else HZ6[1])
        # insulator posts with copper caps
        for x in (4, 12, 20, 28):
            s.rect(x - 1, 2, x + 1, 4, BH6[2])
            s.vline(x - 1, 2, 4, BH6[3])
        # conductor rail
        s.hline(0, 31, 4, RU6[1])
        return s
    out = []
    # 0 off
    s = base()
    for x in (4, 12, 20, 28):
        s.rect(x - 1, 1, x + 1, 1, RU6[2])
    out.append(s)
    # 1-2 warn: posts heat in turn, a spark spits
    for k in range(2):
        s = base()
        for j, x in enumerate((4, 12, 20, 28)):
            hot = (j + k) % 2 == 0
            s.rect(x - 1, 1, x + 1, 1, SODIUM if hot else RU6[3])
            if hot:
                s.px(x, 0, HZ6[4])
        s.px(8 + k * 16, 0, SPARKC)
        out.append(s)
    # 3-5 live: white posts, arcs jump post to post along the plate
    arcs = [
        [(4, 1), (6, 0), (8, 2), (10, 0), (12, 1), (14, 3), (16, 0), (18, 2), (20, 1)],
        [(12, 1), (14, 0), (15, 3), (17, 1), (20, 1), (22, 0), (24, 3), (26, 0), (28, 1)],
        [(28, 1), (30, 3), (31, 2), (0, 2), (2, 0), (4, 1), (6, 3), (9, 1), (12, 1)],
    ]
    for k in range(3):
        s = base()
        for x in (4, 12, 20, 28):
            s.rect(x - 1, 1, x + 1, 1, ARC)
            s.hline(x - 1, x + 1, 2, ARC_HALO)
        pts = arcs[k]
        segs = [(a, b) for a, b in zip(pts, pts[1:]) if abs(a[0] - b[0]) < 8]
        for a, b in segs:
            s.line([(a[0], a[1] + 1), (b[0], b[1] + 1)], ARC_HALO)
        for a, b in segs:
            s.line([a, b], ARC)
        out.append(s)
    return out


def crusher():
    # head 32x24, pivot (16, 0) at the rod's foot; 0 idle, 1 warn
    out = []
    for i in range(2):
        s = Spr(32, 24)
        # collar
        s.rect(11, 0, 20, 3, ST6[1])
        s.vline(11, 0, 3, ST6[2])
        # hazard band
        for y in range(4, 9):
            for x in range(1, 31):
                on = ((x + y) // 3) % 2 == 0
                s.px(x, y, HZ6[2] if on else HZ6[0])
        s.hline(1, 30, 4, HZ6[3])
        # heavy block
        s.rpanel(1, 9, 30, 18, BH6[1:6], 2)
        s.hline(2, 29, 9, BH6[4])
        for (bx, by) in ((4, 12), (27, 12), (4, 16), (27, 16)):
            s.px(bx, by, BH6[5])
            s.px(bx + 1, by + 1, BH6[0])
        # warning lamp
        s.rect(13, 11, 18, 15, BH6[0])
        lamp = LASER if i else SN[0]
        s.rect(14, 12, 17, 14, lamp)
        if i:
            s.px(14, 12, HOT)
        # teeth
        for x in range(1, 31, 6):
            s.poly([(x, 19), (x + 5, 19), (x + 4, 22), (x + 1, 22)], ST6[3])
            s.vline(x, 19, 21, ST6[4])
            s.hline(x + 1, x + 4, 22, ST6[1])
        s.outline()
        out.append(s)
    return out


def piston_rod():
    s = Spr(8, 8)
    s.cyl_v(1, 0, 6, 7, ST6[1:6], bias=0.05)
    s.vline(0, 0, 7, INKC)
    s.vline(7, 0, 7, INKC)
    return [s]


def spike_trap():
    # cell 32x28, pivot (16, 21): rows 21-24 are the plate set into the floor
    out = []
    for i in range(3):  # 0 retracted, 1 warning (tips peek), 2 up
        s = Spr(32, 28)
        h = [0, 4, 18][i]
        for x0 in (1, 9, 17, 25):
            if h:
                tip = 21 - h
                s.poly([(x0, 21), (x0 + 3, tip), (x0 + 3, 21)], ST6[3])
                s.poly([(x0 + 3, tip), (x0 + 6, 21), (x0 + 3, 21)], ST6[1])
                s.vline(x0 + 3, tip, 20, ST6[2])
                s.line([(x0 + 1, 20), (x0 + 3, tip + 2)], ST6[4])
                s.px(x0 + 3, tip, ST6[5])
        if h:
            s.outline()
        # floor plate with slots
        s.rect(0, 21, 31, 24, BH6[1])
        s.hline(0, 31, 21, BH6[3])
        s.hline(0, 31, 24, BH6[0])
        for x0 in (1, 9, 17, 25):
            s.rect(x0, 22, x0 + 6, 23, BH6[0])
            if i == 1:
                s.hline(x0 + 2, x0 + 4, 22, HZ6[2])
        if i == 1:
            for x0 in (1, 9, 17, 25):
                s.px(x0 + 3, 16, HOT)
        out.append(s)
    return out


def vent_nozzle(kind):
    s = Spr(24, 10)
    if kind == "steam":
        s.rpanel(1, 4, 22, 9, BH6[1:6], 2)
        s.hline(2, 21, 4, BH6[4])
        s.rect(4, 1, 19, 4, ST6[1])
        s.hline(4, 19, 1, ST6[3])
        for x in range(5, 19, 2):
            s.vline(x, 2, 3, ST6[0])
        s.px(3, 7, BH6[5])
        s.px(20, 7, BH6[5])
    else:
        s.rpanel(1, 5, 22, 9, BH6[1:6], 1)
        s.hline(2, 21, 5, BH6[3])
        s.rect(5, 1, 18, 5, RU6[1])
        s.hline(5, 18, 1, RU6[2])
        s.rect(6, 2, 17, 3, BH6[0])
        for x in range(7, 17, 3):
            s.px(x, 2, RU6[4])
        s.px(11, 1, RU6[3])
        # soot
        s.pxs([(4, 4), (19, 4), (5, 3), (18, 3)], BH6[1])
    s.outline()
    if kind == "flame":
        s.px(12, 2, SODIUM)
    return [s]


def acid_pool():
    # cell 32x14, pivot (16, 14); tiles horizontally; liquid from row 6 down
    out = []
    bubbles = [[(5, 4, 2), (19, 3, 1), (27, 5, 1)], [(5, 2, 1), (13, 4, 2), (27, 3, 2)], [(13, 2, 1), (21, 4, 2), (29, 5, 1)]]
    for i in range(3):
        s = Spr(32, 14)
        s.rect(0, 6, 31, 13, AC6[2])
        s.rect(0, 10, 31, 13, AC6[1])
        s.hline(0, 31, 13, AC6[0])
        # surface: a bright film with travelling glints
        s.hline(0, 31, 6, AC6[4])
        s.hline(0, 31, 7, AC6[3])
        for x in range(0, 32):
            if (x + i * 3) % 11 in (0, 1, 2):
                s.px(x, 6, AC6[5])
            if (x + i * 5) % 9 == 4:
                s.px(x, 9, AC6[3])
            if (x * 7 + i * 3) % 13 == 2:
                s.px(x, 11, AC6[2])
        for (bx, by, r) in bubbles[i]:
            if r == 2:
                s.rect(bx - 1, by - 1, bx + 1, by + 1, AC6[3])
                s.px(bx - 1, by - 1, AC6[5])
                s.px(bx, by, AC6[2])
            else:
                s.px(bx, by, AC6[4])
        out.append(s)
    return out


def debris_rock():
    # rock: 20x20, centre pivot
    r = Spr(20, 20)
    r.ppanel([(3, 11), (5, 4), (11, 2), (16, 5), (17, 12), (13, 17), (6, 17)], BH6[1:6], 2)
    r.ppanel([(9, 7), (14, 6), (15, 12), (10, 14)], BH6[1:6], 1, lit=2, dark=0)
    r.pxs([(6, 6), (7, 5), (12, 3)], BH6[4])
    r.line([(15, 4), (18, 1)], RU6[2])
    r.px(18, 1, RU6[3])
    r.outline()
    # crack: 32x24, pivot (16, 10); rows 0-9 on the ceiling tile's face, 10+ a bulge
    c = Spr(32, 24)
    c.ppanel([(8, 10), (12, 13), (16, 15), (21, 13), (24, 10)], BH6[1:6], 2)
    c.hline(9, 23, 10, BH6[1])
    ink = BH6[0]
    lit = BH6[4]
    _crack(c, [(16, 15), (15, 11), (17, 7), (14, 3), (15, 0)], ink, lit,
           branch=[[(15, 11), (10, 9), (6, 10)], [(17, 7), (22, 5), (26, 6)], [(14, 3), (10, 2)]])
    c.pxs([(11, 16), (19, 17), (14, 18)], BH6[2])
    return [r], [c]


def conveyor():
    # cell 32x14, pivot (16, 3); belt top at row 3; tiles horizontally
    out = []
    for i in range(4):
        s = Spr(32, 14)
        # housing
        s.rect(0, 7, 31, 13, BH6[2])
        s.hline(0, 31, 7, BH6[3])
        s.hline(0, 31, 13, BH6[0])
        # rollers (spokes turn with the belt)
        for cx in (4, 12, 20, 28):
            s.ell(cx - 3, 7, cx + 3, 13, ST6[1])
            s.ell(cx - 2, 8, cx + 2, 12, ST6[2])
            ang = math.radians(i * 22.5)
            for k in range(2):
                a = ang + k * math.pi / 2
                s.line([(cx - math.cos(a) * 2, 10 - math.sin(a) * 2), (cx + math.cos(a) * 2, 10 + math.sin(a) * 2)],
                       ST6[0])
            s.px(cx, 10, ST6[4])
        # belt: dark rubber with cleats every 8 px, moving +x 2 px a frame
        s.rect(0, 3, 31, 6, BH6[0])
        s.hline(0, 31, 3, BH6[1])
        s.hline(0, 31, 6, INKC)
        for x in range(0, 32):
            if (x - i * 2) % 8 in (0, 1):
                s.px(x, 3, ST6[3])
                s.px(x, 4, ST6[1])
        out.append(s)
    return out


def platform():
    # 3 frames: left cap, mid, right cap; cell 32x14, pivot (16, 0)
    out = []
    for i in range(3):
        s = Spr(32, 14)
        x0 = 1 if i == 0 else 0
        x1 = 30 if i == 2 else 31
        s.rect(x0, 0, x1, 7, ST6[2])
        s.hline(x0, x1, 0, ST6[4])
        s.hline(x0, x1, 1, ST6[3])
        s.hline(x0, x1, 7, ST6[1])
        s.rect(x0, 8, x1, 9, BH6[1])
        for x in range(4, 30, 8):
            s.px(x, 4, ST6[1])
            s.px(x, 3, ST6[5])
        # thruster pod under each tile
        s.rect(12, 10, 19, 12, BH6[2])
        s.hline(12, 19, 10, BH6[3])
        s.rect(14, 13, 17, 13, BH6[1])
        s.hline(15, 16, 13, ARC_HALO)
        if i != 1:
            # hazard-striped end cap
            ex = x0 if i == 0 else x1 - 3
            for y in range(0, 8):
                for x in range(ex, ex + 4):
                    on = ((x + y) // 2) % 2 == 0
                    s.px(x, y, HZ6[3] if on else HZ6[0])
        if i == 0:
            s.vline(0, 0, 9, INKC)
        if i == 2:
            s.vline(31, 0, 9, INKC)
        out.append(s)
    return out


# =========================================================================
# Projectiles and FX
# =========================================================================

def bolt():
    # 20x12, centre pivot; flies +x
    out = []
    for i in range(2):
        s = Spr(20, 12)
        s.ell(5, 3, 17, 8, SN[1])
        s.ell(8, 3, 17, 8, LASER)
        s.ell(11, 4, 17, 7, SN[3])
        s.ell(13, 4, 16, 7, HOT)
        # tail streaks
        s.hline(1 + i, 6, 5, SN[1])
        s.hline(2 - i, 5, 6, SN[0])
        s.px(0 + i * 2, 5, SN[0])
        out.append(s)
    return out


def bomb():
    out = []
    for i in range(2):
        s = Spr(16, 16)
        # tail fins (it falls nose down)
        s.poly([(3, 0), (7, 3), (7, 5), (3, 3)], JT[1])
        s.poly([(12, 0), (8, 3), (8, 5), (12, 3)], JT[1])
        s.hline(3, 6, 0, JT[2])
        s.rect(6, 0, 9, 4, JT[2])
        s.vline(6, 0, 4, JT[3])
        # body
        s.sphere(8, 9, 4, 6, BH6[1:6], bias=0.02)
        s.hline(5, 10, 8, BH6[0])
        s.hline(5, 10, 7, BH6[4])
        s.outline()
        s.rect(7, 10, 8, 11, LASER if i else SN[0])
        if i:
            s.px(7, 10, HOT)
        out.append(s)
    return out


def spark_ball():
    out = []
    rays = [[(6, 0), (11, 5), (6, 11), (0, 6), (2, 2), (9, 9)], [(1, 4), (10, 1), (11, 8), (4, 11), (6, 0), (0, 7)]]
    for i in range(2):
        s = Spr(12, 12)
        for (x, y) in rays[i]:
            s.line([(5.5, 5.5), (x, y)], ARC_HALO)
        s.ell(3, 3, 8, 8, ARC_HALO)
        s.ell(4, 4, 7, 7, ARC)
        s.px(5, 5, WHITE)
        s.px(6, 6, WHITE)
        out.append(s)
    return out


def debris_chunk():
    out = []
    # an amber plate shard, a violet strut, a steel bolt
    a = Spr(8, 8)
    a.poly([(1, 5), (3, 1), (6, 2), (6, 6)], AM[2])
    a.line([(2, 4), (3, 2)], AM[4])
    a.px(5, 5, AM[0])
    a.outline()
    out.append(a)
    b = Spr(8, 8)
    b.line([(1, 6), (6, 1)], JT[2], 2)
    b.px(2, 5, JT[3])
    b.outline()
    out.append(b)
    c = Spr(8, 8)
    c.rect(2, 2, 5, 5, ST6[2])
    c.px(2, 2, ST6[4])
    c.px(5, 5, ST6[1])
    c.rect(3, 3, 4, 4, ST6[1])
    c.outline()
    out.append(c)
    return out


# =========================================================================
# Collectibles: 24x24 cells, centre pivot; idle = rest frames, then a glint
# sweeps across (frames 1-3). Every item has its own hue and silhouette.
# =========================================================================

CO = R("coral")
RO = R("rose")
BR = R("brass")
GO = R("gold")
MO = R("mouse")
CR = R("crystal")
PINK = rgb("#e8a0a8")
PINK_D = rgb("#b86a7a")


def i_fish(s):
    # facing left, 18x9
    s.ell(4, 8, 17, 15, CO[2])
    s.sphere(10, 11, 7, 4, CO[1:])
    s.ell(6, 12, 15, 15, CO[3])
    s.hline(7, 14, 14, CO[4])
    s.poly([(16, 11), (20, 7), (19, 11), (20, 15)], CO[2])
    s.line([(17, 11), (19, 8)], CO[3])
    s.poly([(9, 8), (13, 6), (13, 9)], CO[1])
    s.vline(8, 9, 14, CO[1])
    s.px(6, 10, INKC)
    s.px(6, 9, CO[4])
    s.pxs([(11, 10), (13, 11), (14, 10)], CO[3])


def i_yarn(s):
    s.sphere(11, 12, 7, 7, RO[1:], bias=0.0)
    for (a, b) in (((6, 8), (15, 6)), ((5, 12), (17, 9)), ((6, 16), (17, 13)), ((9, 18), (16, 17))):
        s.line([a, b], RO[1])
    s.line([(8, 7), (10, 18)], RO[2])
    s.line([(17, 15), (20, 17), (21, 20), (19, 21)], RO[2])
    s.px(7, 9, RO[4])
    s.px(8, 8, RO[4])


def i_bell(s):
    s.ell(9, 3, 14, 7, BR[1])
    s.ell(10, 4, 13, 6, CLEAR)
    m = s.poly_mask([(6, 16), (7, 10), (9, 7), (14, 7), (16, 10), (17, 16)])
    m |= s.ell_mask(6, 8, 17, 18)
    s.a[m] = BR[2]

    def nf(x, y):
        nx = (x - 11.5) / 6.0
        return np.array([nx, -0.3, math.sqrt(max(0.0, 1 - nx * nx))])
    s.shade(m, nf, BR[1:], bias=-0.02)
    s.rect(5, 16, 18, 17, BR[1])
    s.hline(6, 17, 16, BR[3])
    s.hline(9, 14, 13, BR[0])
    s.rect(11, 13, 12, 15, BR[0])
    s.ell(10, 17, 13, 20, BR[1])
    s.px(11, 18, BR[3])


def i_mouse(s):
    # toy mouse facing left, 19x11
    s.sphere(12, 14, 7, 5, MO[1:], bias=0.0)
    s.poly([(3, 16), (9, 10), (9, 18)], MO[2])
    s.line([(4, 15), (8, 11)], MO[3])
    s.px(2, 16, PINK_D)
    s.ell(9, 7, 13, 11, MO[2])
    s.ell(10, 8, 12, 10, PINK)
    s.px(7, 13, INKC)
    s.px(6, 13, MO[0])
    s.hline(9, 17, 18, MO[1])
    s.line([(19, 14), (21, 12), (21, 9), (19, 8)], PINK_D)
    s.px(14, 11, MO[4])
    s.px(15, 11, MO[4])


def i_chip(s):
    for k in range(7, 17, 3):
        s.rect(k, 5, k + 1, 6, ST6[4])
        s.rect(k, 17, k + 1, 18, ST6[3])
        s.rect(5, k, 6, k + 1, ST6[4])
        s.rect(17, k, 18, k + 1, ST6[3])
    s.rpanel(7, 7, 16, 16, BH6[1:5], 1)
    s.rect(9, 9, 14, 14, BH6[0])
    s.rect(10, 10, 13, 13, rgb("#2b6f78"))
    s.rect(10, 10, 12, 12, rgb("#41b5c0"))
    s.px(10, 10, rgb("#bff0ee"))


def i_bone(s):
    # a golden fish skeleton facing left, 18x10
    s.poly([(3, 12), (6, 8), (8, 8), (8, 16), (6, 16)], GO[2])
    s.line([(4, 12), (6, 9)], GO[3])
    s.px(5, 11, GO[0])
    s.rect(8, 11, 17, 12, GO[2])
    s.hline(8, 17, 11, GO[3])
    for x in (10, 12, 14):
        s.line([(x, 11), (x + 1, 8)], GO[2])
        s.line([(x, 12), (x + 1, 15)], GO[1])
        s.px(x + 1, 8, GO[3])
    s.poly([(17, 12), (21, 8), (20, 12), (21, 16)], GO[2])
    s.line([(18, 11), (20, 9)], GO[4])


def i_memory(s):
    # a crystalline shard, 10x17, faceted: lit left facet, cool right facet
    s.poly([(12, 4), (16, 9), (15, 17), (11, 20), (7, 15), (8, 8)], CR[2])
    s.poly([(12, 4), (8, 8), (7, 15), (11, 13)], CR[3])
    s.poly([(12, 4), (16, 9), (15, 17), (11, 13)], CR[1])
    s.poly([(11, 13), (15, 17), (11, 20), (7, 15)], CR[2])
    s.line([(12, 5), (11, 13)], CR[4])
    s.line([(8, 9), (8, 14)], CR[4])


def _item(drawfn, glint_at):
    frames = []
    base = Spr(24, 24)
    drawfn(base)
    base.outline()
    frames.append(base)
    gx, gy = glint_at
    for k in range(3):
        f = base.copy()
        x, y = gx + k * 2, gy + k * 2
        if k == 1:
            f.px(x, y, WHITE)
            for d in (1, 2):
                f.px(x - d, y, HOT)
                f.px(x + d, y, HOT)
                f.px(x, y - d, HOT)
                f.px(x, y + d, HOT)
        else:
            f.px(x, y, WHITE)
            f.px(x - 1, y, HOT)
            f.px(x + 1, y, HOT)
            f.px(x, y - 1, HOT)
            f.px(x, y + 1, HOT)
        frames.append(f)
    return frames


def i_memory_frames():
    frames = _item(i_memory, (9, 7))
    # the inner glow breathes: a soft core brightens on the glint frames
    for k, f in enumerate(frames):
        core = [rgb("#c8d8ff"), rgb("#dfe8ff"), WHITE, rgb("#dfe8ff")][k]
        f.pxs([(11, 10), (10, 11), (11, 11), (12, 11), (10, 12), (11, 12), (12, 12), (11, 13), (11, 14)],
              rgb("#b8c8f0"))
        f.pxs([(11, 11), (11, 12), (12, 12)], core)
    return frames


# ---- ansimuz robots re-pixelled to 2/3 ------------------------------------------

def _neigh4(m):
    n = np.zeros_like(m)
    n[1:, :] |= m[:-1, :]
    n[:-1, :] |= m[1:, :]
    n[:, 1:] |= m[:, :-1]
    n[:, :-1] |= m[:, 1:]
    return n


def _scale2x(a):
    h, w, _ = a.shape
    p = np.pad(a, ((1, 1), (1, 1), (0, 0)), mode="edge")
    B, D, E, F, H = p[0:h, 1:w + 1], p[1:h + 1, 0:w], p[1:h + 1, 1:w + 1], p[1:h + 1, 2:w + 2], p[2:h + 2, 1:w + 1]

    def eq(x, y):
        return (x == y).all(axis=2)

    def pick(c, src):
        return np.where(c[..., None], src, E)
    o = np.zeros((h * 2, w * 2, 4), np.uint8)
    o[0::2, 0::2] = pick(eq(D, B) & ~eq(B, F) & ~eq(D, H), D)
    o[0::2, 1::2] = pick(eq(B, F) & ~eq(B, D) & ~eq(F, H), F)
    o[1::2, 0::2] = pick(eq(D, H) & ~eq(D, B) & ~eq(H, F), D)
    o[1::2, 1::2] = pick(eq(H, F) & ~eq(D, H) & ~eq(B, F), F)
    return o


def _block_mode(a, k, cover):
    h, w, _ = a.shape
    H, W = h // k, w // k
    o = np.zeros((H, W, 4), np.uint8)
    for y in range(H):
        for x in range(W):
            blk = a[y * k:(y + 1) * k, x * k:(x + 1) * k].reshape(-1, 4)
            op = blk[blk[:, 3] > 0]
            if len(op) < cover * k * k:
                continue
            vals, counts = np.unique(op, axis=0, return_counts=True)
            o[y, x] = vals[counts.argmax()]
    return o


# Small bright accents (eyes, chest lamps) that a block vote can drop in some
# frames and keep in others, which flickers: every small cluster of these in the
# source is stamped back as one pixel at its scaled centroid.
ACCENTS = [rgb("#d8403a")[:3], rgb("#ff4a3a")[:3], rgb("#ff7a5a")[:3]]


def _accent_spots(f, max_size=14):
    h, w, _ = f.shape
    acc = np.zeros((h, w), bool)
    for c in ACCENTS:
        acc |= (f[..., :3] == np.array(c, np.uint8)).all(axis=2) & (f[..., 3] > 0)
    seen = np.zeros_like(acc)
    spots = []
    for y in range(h):
        for x in range(w):
            if not acc[y, x] or seen[y, x]:
                continue
            stack, pts = [(y, x)], []
            seen[y, x] = True
            while stack:
                cy, cx = stack.pop()
                pts.append((cy, cx))
                for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    ny, nx = cy + dy, cx + dx
                    if 0 <= ny < h and 0 <= nx < w and acc[ny, nx] and not seen[ny, nx]:
                        seen[ny, nx] = True
                        stack.append((ny, nx))
            if len(pts) <= max_size:
                cy = sum(p[0] for p in pts) / len(pts)
                cx = sum(p[1] for p in pts) / len(pts)
                vals = [tuple(f[p[0], p[1]]) for p in pts]
                spots.append((cx, cy, max(set(vals), key=vals.count)))
    return spots


def two_thirds(src_rel, cell):
    """ansimuz sheet -> 2/3 size with whole pixels and a clean 1 px INK edge."""
    a = np.asarray(Image.open(os.path.join(ROOT, src_rel)).convert("RGBA")).copy()
    a[a[..., 3] == 0] = 0
    cw, ch = cell
    frames = []
    for i in range(a.shape[1] // cw):
        f = a[:, i * cw:(i + 1) * cw]
        r = _block_mode(_scale2x(f), 3, 0.45)
        solid = r[..., 3] > 0
        r[solid & _neigh4(~solid)] = INKC
        for (sx, sy, col) in _accent_spots(f):
            ox, oy = int(sx * 2 / 3 + 1 / 3), int(sy * 2 / 3 + 1 / 3)
            if 0 <= oy < r.shape[0] and 0 <= ox < r.shape[1] and r[oy, ox, 3] > 0:
                r[oy, ox] = col
        s = Spr(r.shape[1], r.shape[0])
        s.a = r
        frames.append(s)
    return frames


# =========================================================================
# Manifest
# =========================================================================

def part(frames, anims, pivot, offset=(0, 0)):
    return dict(frames=frames, anims=anims, pivot=pivot, offset=offset)


def A(frames, fps=8.0, loop=True):
    return {"frames": frames, "fps": fps, "loop": loop}


def build_actors(only=None):
    acts = {}

    def add(aid, fn):
        if only is None or aid in only:
            acts[aid] = fn()

    add("sentry_turret", lambda: dict(scale=1.0, main="body", parts={
        "body": part(sentry_body(), {"idle": A([0], 1), "stun": A([1], 1)}, (16, 24)),
        "head": part(sentry_head(), {"idle": A([0], 1), "charge": A([1, 2, 3], 5, False), "fire": A([4], 1),
                                     "stun": A([5, 6], 10)}, (11, 12), (0, TURRET_HEAD_Y)),
    }))
    add("patrol_bot", lambda: dict(scale=1.0, main="body", parts={
        "body": part(two_thirds("assets/art_hd/robots/bipedal.png", (80, 64)),
                     {"walk": A([0, 1, 2, 3, 4, 5, 6], 9), "stun": A([3], 1), "aim": A([3], 1)}, (26, 42)),
    }))
    add("hover_drone", lambda: dict(scale=1.0, main="body", pivot="center", parts={
        "body": part(hover_drone(), {"fly": A([0, 1, 2], 18), "arm": A([3, 5], 10), "stun": A([4], 1)}, (20, 16)),
    }))
    add("hopper_bot", lambda: dict(scale=1.0, main="body", parts={
        "body": part(hopper(), {"idle": A([0], 1), "squat": A([1], 1), "up": A([2], 1), "fall": A([3], 1),
                                "stun": A([4], 1)}, (16, 40)),
    }))
    add("crawler", lambda: dict(scale=1.0, main="body", parts={
        "body": part(crawler(), {"crawl": A([0, 1, 2, 3], 8), "roll": A([4, 5, 6, 7], 16), "stun": A([8], 1),
                                 "tell": A([9], 1)}, (17, 28)),
    }))
    add("security_camera", lambda: dict(scale=1.0, main="mount", pivot="center", parts={
        "mount": part(cam_mount(), {"idle": A([0], 1)}, (8, 0)),
        "head": part(cam_head(), {"idle": A([0, 0, 0, 1], 2), "alarm": A([2, 3], 8), "stun": A([4], 1)},
                     (5, 6), (0, 9)),
    }))
    add("heavy_mech", lambda: dict(scale=1.0, main="body", parts={
        "body": part(two_thirds("assets/art_hd/robots/mech.png", (96, 80)),
                     {"walk": A([0, 1, 2, 3, 4, 5, 6, 7, 8, 9], 9), "stun": A([4], 1), "charge": A([2, 7], 12)},
                     (32, 53)),
    }))
    for kind in ("plain", "explosive", "acid"):
        anims = {"plain": {"idle": A([0], 1), "hit": A([1], 1)},
                 "explosive": {"idle": A([0], 1), "lit": A([0, 1], 10)},
                 "acid": {"idle": A([0], 1), "leak": A([2], 1)}}[kind]
        add("barrel_" + kind, lambda kind=kind, anims=anims: dict(scale=1.0, main="body", parts={
            "body": part(barrel(kind), anims, (12, 34))}))
    for kind in ("cracked", "reinforced", "blast"):
        add("wall_" + kind, lambda kind=kind: dict(scale=1.0, main="tile", parts={
            "tile": part(wall_tile(kind), {"idle": A([0], 1), "hit": A([1], 1)}, (16, 32))}))
    add("electric_floor", lambda: dict(scale=1.0, main="panel", parts={
        "panel": part(electric_panel(), {"off": A([0], 1), "warn": A([1, 2], 10), "live": A([3, 4, 5], 18)},
                      (16, 8))}))
    add("crusher", lambda: dict(scale=1.0, main="head", parts={
        "head": part(crusher(), {"idle": A([0], 1), "warn": A([0, 1], 10)}, (16, 0)),
        "rod": part(piston_rod(), {"idle": A([0], 1)}, (4, 0))}))
    add("spike_trap", lambda: dict(scale=1.0, main="body", parts={
        "body": part(spike_trap(), {"down": A([0], 1), "warn": A([1], 1), "up": A([2], 1)}, (16, 21))}))
    for kind in ("steam", "flame"):
        add("vent_" + kind, lambda kind=kind: dict(scale=1.0, main="nozzle", parts={
            "nozzle": part(vent_nozzle(kind), {"idle": A([0], 1)}, (12, 10))}))
    add("acid_pool", lambda: dict(scale=1.0, main="pool", parts={
        "pool": part(acid_pool(), {"bubble": A([0, 1, 2], 4)}, (16, 14))}))

    def _debris():
        rock, crack = debris_rock()
        return dict(scale=1.0, main="rock", parts={
            "rock": part(rock, {"idle": A([0], 1)}, (10, 10)),
            "crack": part(crack, {"idle": A([0], 1)}, (16, 10))})
    add("falling_debris", _debris)
    add("conveyor", lambda: dict(scale=1.0, main="belt", parts={
        "belt": part(conveyor(), {"run": A([0, 1, 2, 3], 10)}, (16, 3))}))
    add("platform", lambda: dict(scale=1.0, main="plate", parts={
        "plate": part(platform(), {"left": A([0], 1), "mid": A([1], 1), "right": A([2], 1)}, (16, 0))}))
    add("bolt", lambda: dict(scale=1.0, main="body", pivot="center", parts={
        "body": part(bolt(), {"fly": A([0, 1], 14)}, (10, 6))}))
    add("bomb", lambda: dict(scale=1.0, main="body", pivot="center", parts={
        "body": part(bomb(), {"fall": A([0, 1], 6)}, (8, 8))}))
    add("spark", lambda: dict(scale=1.0, main="body", pivot="center", parts={
        "body": part(spark_ball(), {"fly": A([0, 1], 16)}, (6, 6))}))
    add("debris_chunk", lambda: dict(scale=1.0, main="body", pivot="center", parts={
        "body": part(debris_chunk(), {"a": A([0], 1), "b": A([1], 1), "c": A([2], 1)}, (4, 4))}))
    # Each pickup rests for a different number of frames, so a row of them glints out of step.
    items = (("fish", i_fish, (7, 9), 17), ("yarn", i_yarn, (7, 7), 19), ("bell", i_bell, (8, 9), 15),
             ("mouse", i_mouse, (10, 10), 21), ("bone", i_bone, (9, 8), 13), ("chip", i_chip, (8, 6), 18),
             ("memory", None, None, 14))
    for name, fn, at, rest in items:
        def mk(name=name, fn=fn, at=at, rest=rest):
            frames = i_memory_frames() if name == "memory" else _item(fn, at)
            seq = [0] * rest + [1, 2, 3]
            return dict(scale=1.0, main="body", pivot="center", parts={
                "body": part(frames, {"idle": A(seq, 10), "glint": A([1, 2, 3], 10)}, (12, 12))})
        add("pickup_" + name, mk)
    return acts


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


def assemble(spec, idx):
    """The actor as the game builds it: the main part's first frame with every
    other part's frame `idx` at its offset. Returns (image, origin)."""
    mp = spec["parts"][spec["main"]]
    items = [(mp["frames"][0], mp["pivot"], (0, 0))]
    for name, p in spec["parts"].items():
        if name != spec["main"]:
            f = p["frames"][min(idx, len(p["frames"]) - 1)]
            items.append((f, p["pivot"], p["offset"]))
    x0 = min(-pv[0] + off[0] for f, pv, off in items)
    y0 = min(-pv[1] + off[1] for f, pv, off in items)
    x1 = max(-pv[0] + off[0] + f.w for f, pv, off in items)
    y1 = max(-pv[1] + off[1] + f.h for f, pv, off in items)
    im = Image.new("RGBA", (x1 - x0, y1 - y0), CLEAR)
    for f, pv, off in items:
        im.alpha_composite(f.to_image(), (-pv[0] + off[0] - x0, -pv[1] + off[1] - y0))
    return im, (-x0, -y0)


def preview(outdir, acts, zoom=4):
    """Each actor's parts as strips on a mid-dark ground, enlarged."""
    os.makedirs(outdir, exist_ok=True)
    for aid, spec in acts.items():
        rows = [strip(p["frames"]) for p in spec["parts"].values()]
        if len(spec["parts"]) > 1:
            n = max(len(p["frames"]) for p in spec["parts"].values())
            ims = [assemble(spec, i)[0] for i in range(n)]
            row = Image.new("RGBA", (sum(i.size[0] + 2 for i in ims), max(i.size[1] for i in ims)), CLEAR)
            x = 0
            for i in ims:
                row.alpha_composite(i, (x, row.size[1] - i.size[1]))
                x += i.size[0] + 2
            rows.append(row)
        W = max(r.size[0] for r in rows) + 8
        H = sum(r.size[1] + 4 for r in rows) + 4
        sheet = Image.new("RGBA", (W, H), (34, 42, 58, 255))
        y = 4
        for r in rows:
            sheet.alpha_composite(r, (4, y))
            y += r.size[1] + 4
        sheet.resize((W * zoom, H * zoom), Image.NEAREST).save(os.path.join(outdir, aid + ".png"))


def main():
    args = sys.argv[1:]
    if args and args[0] == "--preview":
        preview(args[1], build_actors(set(args[2:]) or None))
        return
    manifest = {"version": 2, "tile": 32,
                "note": "Generated by tools/art/kit_art.py (the art source). Edit the drawings there and re-run.",
                "actors": {}}
    for aid, spec in build_actors().items():
        os.makedirs(os.path.join(OUT, aid), exist_ok=True)
        parts_out = {}
        for pname, p in spec["parts"].items():
            frames = p["frames"]
            im = strip(frames)
            cell = [frames[0].w, frames[0].h]
            rel = "assets/sprites/kit/%s/%s.png" % (aid, pname)
            im.save(os.path.join(ROOT, rel))
            parts_out[pname] = {"file": rel, "cell": cell, "pivot": list(p["pivot"]), "offset": list(p["offset"]),
                                "anims": p["anims"], "bounds": alpha_bounds(im, cell, p["pivot"], p["offset"])}
        b = list(parts_out[spec["main"]]["bounds"])
        if aid in ("sentry_turret", "security_camera"):  # the head sits on the mount: the actor box covers both
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
