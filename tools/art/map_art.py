#!/usr/bin/env python3
"""Pixel art for the world map (scenes/ui/world_map.tscn): the district from
the warehouse to the cat's home, side-on, as a diorama the cat walks across.

Everything is drawn at 1x for the 640x360 view, in ALBEDO: the map tints it
per screen column by time of day (shaders/map_layer.gdshader), night at the
warehouse end, pre-dawn at the fence, morning at home. So the art is painted
as if under flat daylight, with a little rim light on top edges (the moon at
night, the sun by day both come from above), and every lamp or window that
glows lives in a separate *_glow.png that the map draws unshaded and additive.

The landmarks stand around their node (data/levels.json "pos"); their canvas
placement is written to assets/art_hd/map/map_art.json, which the map reads.
Stairs, ladders and walkways along the paths are drawn by the map itself from
the path data, so moving a node never leaves a staircase behind.

Ramps come from palette.py (the rooms' materials) and home_art.py (the day
street), so the map is the same family as the levels.

Usage: map_art.py [out_dir]   (default: assets/art_hd/map)
"""
import json
import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import home_art as H  # noqa: E402
from home_art import Canvas, quantize, value_noise, rgb, mixc, B4  # noqa: E402
from palette import RAMPS, INK  # noqa: E402

ROOT = HERE.parent.parent
LEVELS = json.loads((ROOT / "data" / "levels.json").read_text())

STEEL = [RAMPS["steel"][k] for k in ("ink", "shadow", "face", "light", "high", "spec")]
BULK = [RAMPS["bulkhead"][k] for k in ("ink", "shadow", "face", "light", "high", "spec")]
RUST = [RAMPS["rust"][k] for k in ("ink", "shadow", "face", "light", "high", "spec")]
MAROON = [RAMPS["maroon"][k] for k in ("ink", "shadow", "face", "light", "high", "spec")]
TEAL = [RAMPS["teal"][k] for k in ("ink", "shadow", "face", "light", "high", "spec")]
VIOLET = [RAMPS["violet"][k] for k in ("ink", "shadow", "face", "light", "high", "spec")]
HAZARD = [RAMPS["hazard"][k] for k in ("ink", "shadow", "face", "light", "high", "spec")]

# Map-only ramps (albedo). Concrete and brick lean warm grey; glass is the
# night-blue that reads as "dark window" once the lamps are off.
CONC = ["#2c2f3e", "#4b4f60", "#6c6f7c", "#8d8e96", "#aeadb0", "#cfccc8"]
BRICKR = ["#2a1626", "#5a2c34", "#7e4240", "#9c5c4c", "#b87a5e", "#d49c76"]
TAR = ["#1c1e2a", "#2a2d3c", "#3a3e50", "#4c5164", "#62687c"]
GLASSN = ["#121a30", "#1c2a48", "#2a3e62", "#3e587e", "#5d7a9c"]
GRASS = ["#1f3a2e", "#2c5038", "#3f6a42", "#57864c", "#78a458"]
GRAVEL = ["#3a3640", "#514c54", "#6a646a", "#857e80"]

# Emissive colours for the *_glow sheets (the map multiplies them up).
WARM_WIN = "#ffb35c"
WARM_DIM = "#c86f2c"
SODIUM = "#ff8c29"
COOL_LAMP = "#bfe6f0"
GATE_LAMP = "#7fe8e0"

# World layout (must match data/levels.json and WorldMap).
BASE_Y = 296          # where buildings stand: the back edge of the sidewalk
PATH_Y = 302          # the cat's feet on the street
MAP_W, MAP_H = LEVELS["size"]


def node_pos(i):
    for lv in LEVELS["levels"] + LEVELS["junctions"]:
        if lv["id"] == i:
            return lv["pos"]
    raise KeyError(i)


# ---- helpers -----------------------------------------------------------------

def shade_rect(c, x, y, w, h, ramp, light_left=False, top_lit=True):
    """A box face: flat face, lit top edge, shaded right (or left) edge."""
    c.rect(x, y, w, h, ramp[2])
    if top_lit:
        c.hline(x, x + w - 1, y, ramp[4])
    if light_left:
        c.vline(x, y, y + h - 1, ramp[3])
        c.vline(x + w - 1, y, y + h - 1, ramp[1])
    else:
        c.vline(x + w - 1, y, y + h - 1, ramp[3])
        c.vline(x, y, y + h - 1, ramp[1])


def ribs(c, x, y, w, h, ramp, step=3, start=0):
    """Vertical corrugation: a lit rib every `step` px with a shadow beside it."""
    for k in range(start, w, step):
        c.vline(x + k, y, y + h - 1, ramp[3])
        if k + 1 < w:
            c.vline(x + k + 1, y, y + h - 1, ramp[2])
        if k + 2 < w:
            c.vline(x + k + 2, y, y + h - 1, ramp[1] if step > 2 else ramp[2])


def container(c, x, y, w, h, ramp, doors=False, label=None):
    """A shipping container side: ribbed panel, top and bottom rails, corner
    castings. `doors` draws the end doors (locking bars) instead of ribs."""
    c.rect(x, y, w, h, ramp[2])
    if doors:
        mid = x + w // 2
        c.vline(mid, y + 2, y + h - 3, ramp[1])
        for bx in (x + 3, mid - 3, mid + 3, x + w - 4):
            c.vline(bx, y + 2, y + h - 3, ramp[4])
            c.vline(bx + 1, y + 2, y + h - 3, ramp[1])
        for hy in (y + h // 3, y + 2 * h // 3):
            c.hline(x + 2, x + w - 3, hy, ramp[1])
    else:
        for k in range(2, w - 2, 4):
            c.vline(x + k, y + 2, y + h - 3, ramp[3])
            c.vline(x + k + 1, y + 2, y + h - 3, ramp[1])
    c.hline(x, x + w - 1, y, ramp[4])
    c.hline(x, x + w - 1, y + 1, ramp[3])
    c.hline(x, x + w - 1, y + h - 2, ramp[1])
    c.hline(x, x + w - 1, y + h - 1, ramp[0])
    for cx in (x, x + w - 2):
        c.rect(cx, y, 2, 2, ramp[1])
        c.rect(cx, y + h - 2, 2, 2, ramp[0])
    if label:
        lx, ly, lw, col = label
        c.rect(x + lx, y + ly, lw, 3, col)


def lattice(c, x0, y0, x1, y1, col, hi, step=8):
    """A vertical lattice column between two rails: X bracing every `step`."""
    for x in (x0, x1):
        c.vline(x, y0, y1, col)
    c.vline(x1, y0, y1, hi)
    y = y0
    while y + step <= y1:
        for i in range(step + 1):
            t = i / step
            c.px(round(x0 + (x1 - x0) * t), y + i, col)
            c.px(round(x1 - (x1 - x0) * t), y + i, col)
        c.hline(x0, x1, y, col)
        y += step
    c.hline(x0, x1, y1, col)


def line(c, x0, y0, x1, y1, col):
    n = int(max(abs(x1 - x0), abs(y1 - y0)))
    for i in range(n + 1):
        t = i / max(n, 1)
        c.px(round(x0 + (x1 - x0) * t), round(y0 + (y1 - y0) * t), col)


def stain(c, x, y, h, col, seed):
    """Rust streak: a 1-2 px trickle down a wall, broken up by noise."""
    rng = np.random.default_rng(seed)
    for k in range(h):
        if rng.random() < 0.8:
            c.px(x + (1 if rng.random() < 0.15 else 0), y + k, col)


class Sheet:
    """A landmark: albedo canvas plus its glow canvas, at a world origin."""

    def __init__(self, name, x0, y0, w, h):
        self.name = name
        self.x0, self.y0 = x0, y0
        self.c = Canvas(w, h)
        self.g = Canvas(w, h)

    def lx(self, wx):
        return wx - self.x0

    def ly(self, wy):
        return wy - self.y0

    def glow(self, x, y, w, h, col):
        self.g.rect(x, y, w, h, col)


# ---- the warehouse -------------------------------------------------------------

def warehouse():
    nx, ny = node_pos("warehouse")
    s = Sheet("warehouse", nx - 124, BASE_Y - 140, 252, 141)
    c = s.c
    base = s.ly(BASE_Y)
    x0, x1 = 12, 240          # the shed's front wall
    eave = base - 74
    # Sawtooth roof: four teeth, each a lit slope rising right and a glazed
    # north-light face dropping back down.
    teeth = 4
    tw = (x1 - x0) // teeth
    for i in range(teeth):
        ax = x0 + i * tw
        bx = ax + tw
        top = eave - 34
        slope = c.mask_poly([(ax, eave), (bx - 9, top), (bx - 9, eave)])
        yy, xx = np.mgrid[0:c.h, 0:c.w]
        v = 0.55 + (xx - ax) / tw * 0.25 + (value_noise(c.w, c.h, 6, 3 + i, 1) - 0.5) * 0.12
        c.a[slope] = quantize(v, BULK[1:5], slope, dither=0.3)[slope]
        line(c, ax, eave, bx - 9, top, BULK[4])
        # Glazed face: a strip of panes, mostly dark, a few lit inside.
        c.rect(bx - 9, top, 9, eave - top, BULK[1])
        for gy in range(top + 3, eave - 2, 6):
            c.rect(bx - 7, gy, 5, 4, GLASSN[2])
            c.px(bx - 7, gy, GLASSN[4])
        c.vline(bx - 9, top, eave - 1, BULK[3])
        c.vline(bx - 1, top, eave - 1, BULK[0])
    # One pane is broken: the moon's way in (Room 1's skylight).
    bx = x0 + 2 * tw
    c.rect(bx - 7, eave - 25, 5, 4, INK)
    c.px(bx - 6, eave - 25, GLASSN[3])
    c.px(bx - 3, eave - 22, GLASSN[3])
    # Front wall: corrugated steel, darker low down with grime.
    c.rect(x0, eave, x1 - x0, base - eave, STEEL[2])
    ribs(c, x0, eave + 3, x1 - x0, base - eave - 9, STEEL, step=3)
    yy, xx = np.mgrid[0:c.h, 0:c.w]
    rng = np.random.default_rng(41)
    streak_h = rng.integers(4, 18, size=c.w)
    low = (yy > base - 6 - streak_h[None, :]) & (yy < base - 6) & (xx >= x0) & (xx < x1) & (xx % 3 == 2)
    c.fill(low & (rng.random((c.h, c.w)) < 0.8), STEEL[1])
    c.rect(x0, eave, x1 - x0, 3, BULK[2])          # eave flashing
    c.hline(x0, x1 - 1, eave, BULK[4])
    c.hline(x0 - 2, x1 + 1, eave + 3, BULK[0])
    c.rect(x0 - 1, base - 6, x1 - x0 + 2, 6, CONC[2])  # concrete plinth
    c.hline(x0 - 1, x1, base - 6, CONC[4])
    c.hline(x0 - 1, x1, base - 1, CONC[1])
    # Side wall in shadow at the right end (a sliver: 3/4 view).
    c.poly([(x1, eave + 3), (x1 + 8, eave - 2), (x1 + 8, base - 4), (x1, base)], STEEL[1])
    c.vline(x1 + 8, eave - 2, base - 4, STEEL[0])
    # The loading door, centred on the node: a roller shutter part raised,
    # the dark inside under it, a hood, hazard stripes on the jambs.
    dx = s.lx(nx)
    dw, dh = 46, 50
    d0 = dx - dw // 2
    c.rect(d0 - 4, base - dh - 6, dw + 8, dh + 6, BULK[1])
    c.rect(d0, base - dh, dw, dh, BULK[0])
    for sy in range(base - dh, base - 22, 3):
        c.hline(d0, d0 + dw - 1, sy, STEEL[3])
        c.hline(d0, d0 + dw - 1, sy + 1, STEEL[2])
        c.hline(d0, d0 + dw - 1, sy + 2, STEEL[1])
    c.hline(d0, d0 + dw - 1, base - 22, STEEL[4])     # the shutter's bottom bar
    c.rect(d0, base - 21, dw, 21, "#0b0d18")           # the dark inside
    for jx in (d0 - 4, d0 + dw):
        for k in range(0, dh + 2, 4):
            c.rect(jx, base - dh - 2 + k, 4, 2, HAZARD[2])
            c.rect(jx, base - dh + k, 4, 2, HAZARD[0])
    c.rect(d0 - 8, base - dh - 10, dw + 16, 4, BULK[2])
    c.hline(d0 - 8, d0 + dw + 7, base - dh - 10, BULK[4])
    # A sodium lamp over the door (its glow is in the glow sheet).
    c.rect(dx - 4, base - dh - 16, 8, 4, BULK[1])
    c.rect(dx - 3, base - dh - 12, 6, 2, "#ffcf8a")
    s.glow(dx - 3, base - dh - 12, 6, 2, SODIUM)
    s.glow(dx - 2, base - dh - 13, 4, 1, WARM_DIM)
    # Spill on the threshold under the shutter (warm, from the lamp).
    s.glow(d0 + 4, base - 2, dw - 8, 1, WARM_DIM)
    # The office lean-to on the left with a lit window and a small door.
    c.rect(x0 + 6, base - 40, 46, 34, CONC[3])
    c.hline(x0 + 6, x0 + 51, base - 40, CONC[5])
    c.vline(x0 + 51, base - 40, base - 7, CONC[4])
    c.vline(x0 + 6, base - 40, base - 7, CONC[1])
    c.rect(x0 + 12, base - 33, 18, 12, BULK[1])
    c.rect(x0 + 13, base - 32, 16, 10, GLASSN[1])
    s.glow(x0 + 13, base - 32, 16, 10, WARM_WIN)
    c.vline(x0 + 21, base - 32, base - 23, BULK[1])
    s.g.rect(x0 + 21, base - 32, 1, 10, "#000000")
    c.rect(x0 + 36, base - 30, 11, 24, BULK[2])
    c.vline(x0 + 46, base - 30, base - 7, BULK[3])
    c.px(x0 + 38, base - 18, HAZARD[3])
    # Stencilled bay number on a hazard plate, right of the door: "07".
    px0, py0 = dx + 36, base - 46
    c.rect(px0, py0, 26, 16, HAZARD[2])
    c.hline(px0, px0 + 25, py0, HAZARD[4])
    c.hline(px0, px0 + 25, py0 + 15, HAZARD[0])
    c.vline(px0 + 25, py0, py0 + 15, HAZARD[1])
    ink = BULK[0]
    # 0
    c.rect(px0 + 4, py0 + 3, 7, 10, ink)
    c.rect(px0 + 6, py0 + 5, 3, 6, HAZARD[2])
    # 7
    c.rect(px0 + 14, py0 + 3, 8, 2, ink)
    line(c, px0 + 21, py0 + 5, px0 + 17, py0 + 12, ink)
    line(c, px0 + 20, py0 + 5, px0 + 16, py0 + 12, ink)
    wear = (value_noise(c.w, c.h, 2, 77, 1) > 0.7) & (c.a[..., :3] == rgb(HAZARD[2])).all(-1)
    c.fill(wear, HAZARD[3])
    # Pipes: a downpipe at the right, a vent pipe up through the roof.
    c.rect(x1 - 8, eave + 3, 3, base - eave - 9, BULK[2])
    c.vline(x1 - 6, eave + 3, base - 7, BULK[4])
    c.rect(x0 + 36, eave - 52, 5, 54, BULK[2])
    c.vline(x0 + 40, eave - 52, eave, BULK[4])
    c.rect(x0 + 34, eave - 55, 9, 3, BULK[3])
    # Rust streaks under the eave.
    for k, sx in enumerate((x0 + 64, x0 + 101, x0 + 148, x0 + 205)):
        stain(c, sx, eave + 3, 18 + k * 5, RUST[1], 90 + k)
    # A floodlight on a bracket at the left corner (cold, for contrast).
    c.rect(x0 - 2, eave + 8, 6, 3, BULK[1])
    c.rect(x0 - 4, eave + 6, 4, 6, BULK[2])
    s.glow(x0 - 4, eave + 7, 2, 4, COOL_LAMP)
    c.outline(INK)
    return s


# ---- the yard --------------------------------------------------------------------

def yard():
    nx, ny = node_pos("yard")
    s = Sheet("yard", nx - 182, BASE_Y - 182, 366, 183)
    c = s.c
    base = s.ly(BASE_Y)
    cx = s.lx(nx)
    # Container stacks either side of the lane the node sits in.
    cols = [RUST, TEAL, MAROON, STEEL, RUST, TEAL]
    ch, cw = 22, 58
    stacks_l = [(cx - 132, 3), (cx - 70, 2)]
    stacks_r = [(cx + 26, 2), (cx + 86, 3)]
    k = 0
    for sx, n in stacks_l + stacks_r:
        for j in range(n):
            ramp = cols[(k + j * 2) % len(cols)]
            off = (2 if j % 2 else 0) * (1 if sx < cx else -1)
            container(c, sx + off, base - (j + 1) * ch, cw, ch, ramp, doors=(j == 0 and sx in (cx - 70, cx + 26)))
            k += 1
    # A container hanging from the spreader, mid-lift.
    hang_y = base - 112
    container(c, cx - 30, hang_y, 60, 20, MAROON)
    # The gantry crane: two A-frame legs on rails, a long top girder, the
    # trolley and its cables. Painted hazard orange like the room's cranes.
    top = 16
    gl, gr = cx - 162, cx + 160
    for lx in (gl, gr):
        for side in (-1, 1):
            fx, fy = lx + side * 14, base - 5
            hx, hy = lx + side * 4, top + 17
            n = fy - hy
            for k in range(n + 1):
                x = round(fx + (hx - fx) * k / n)
                y = fy - k
                c.px(x - 1, y, HAZARD[3])
                c.px(x, y, HAZARD[2])
                c.px(x + 1, y, HAZARD[2])
                c.px(x + 2, y, HAZARD[1])
        # Sill and cross beams between the two members.
        for yb, hw in ((base - 34, 12), (top + 70, 8), (top + 40, 6)):
            c.rect(lx - hw, yb, hw * 2 + 1, 3, HAZARD[2])
            c.hline(lx - hw, lx + hw, yb, HAZARD[4])
            c.hline(lx - hw, lx + hw, yb + 2, HAZARD[0])
        # X bracing in the bottom bay.
        line(c, lx - 11, base - 31, lx + 10, base - 6, HAZARD[1])
        line(c, lx + 11, base - 31, lx - 10, base - 6, HAZARD[1])
        c.rect(lx - 17, base - 5, 35, 5, BULK[1])       # bogie and wheels
        c.hline(lx - 17, lx + 17, base - 5, BULK[3])
        for wx in (lx - 13, lx - 4, lx + 5, lx + 13):
            c.rect(wx - 1, base - 2, 3, 2, BULK[0])
            c.px(wx, base - 2, BULK[4])
    # Top girder (a truss), overhanging to the right like a boom.
    g0, g1 = gl - 12, gr + 18
    c.rect(g0, top + 6, g1 - g0, 12, HAZARD[2])
    c.hline(g0, g1 - 1, top + 6, HAZARD[4])
    c.hline(g0, g1 - 1, top + 17, HAZARD[0])
    c.rect(g0 + 2, top + 9, g1 - g0 - 4, 6, HAZARD[1])
    for k2 in range(g0 + 4, g1 - 4, 8):
        line(c, k2, top + 9, k2 + 4, top + 14, HAZARD[3])
        line(c, k2 + 4, top + 14, k2 + 8, top + 9, HAZARD[3])
    # Machinery house on the girder, with a lit cab window.
    c.rect(gl - 8, top - 6, 30, 12, BULK[2])
    c.hline(gl - 8, gl + 21, top - 6, BULK[4])
    c.rect(gl + 10, top - 3, 8, 5, GLASSN[1])
    s.glow(gl + 10, top - 3, 8, 5, WARM_WIN)
    # Amber warning beacons on the girder ends.
    for bx in (g0 + 2, g1 - 4):
        c.rect(bx, top + 3, 3, 3, HAZARD[4])
        s.glow(bx, top + 3, 3, 3, SODIUM)
    # Trolley over the lane, cables to the spreader.
    c.rect(cx - 12, top + 18, 24, 7, BULK[2])
    c.hline(cx - 12, cx + 11, top + 18, BULK[4])
    for kx in (cx - 8, cx + 7):
        c.vline(kx, top + 25, hang_y - 6, BULK[1])
    c.rect(cx - 32, hang_y - 6, 64, 4, HAZARD[2])        # spreader
    c.hline(cx - 32, cx + 31, hang_y - 6, HAZARD[4])
    c.vline(cx - 32, hang_y - 2, hang_y, HAZARD[1])
    c.vline(cx + 31, hang_y - 2, hang_y, HAZARD[1])
    # A floodlight mast behind the left stacks.
    mx = cx - 92
    c.rect(mx, base - 150, 3, 150 - 3 * ch, BULK[2])
    c.vline(mx + 2, base - 150, base - 3 * ch, BULK[4])
    c.rect(mx - 6, base - 154, 15, 5, BULK[1])
    for lx in (mx - 5, mx, mx + 5):
        c.rect(lx, base - 153, 4, 3, "#e8f0f0")
        s.glow(lx, base - 153, 4, 3, COOL_LAMP)
    c.outline(INK)
    return s


# ---- the stacks ------------------------------------------------------------------

def stacks():
    nx, ny = node_pos("stacks")
    fx, fy = node_pos("fork_tower")
    s = Sheet("stacks", nx - 152, BASE_Y - 250, 360, 251)
    c = s.c
    base = s.ly(BASE_Y)
    roof = s.ly(ny) + 2                  # block A's roof under the node
    a0, a1 = s.lx(nx - 128), s.lx(fx - 8)  # block A: a stack of containers
    # Block A: containers stacked five high on a concrete podium, staggered.
    c.rect(a0 - 4, base - 26, a1 - a0 + 8, 26, CONC[2])
    c.hline(a0 - 4, a1 + 3, base - 26, CONC[4])
    for wx in range(a0 + 6, a1 - 10, 22):
        c.rect(wx, base - 20, 12, 10, BULK[0])
        c.rect(wx + 1, base - 19, 10, 8, GLASSN[1])
        s.glow(wx + 1, base - 19, 10, 8, WARM_DIM if (wx // 22) % 3 else WARM_WIN)
    rows = (base - 26 - roof) // 21
    cols = [TEAL, RUST, MAROON, STEEL, VIOLET, RUST, TEAL, MAROON]
    k = 0
    for j in range(rows):
        y = base - 26 - (j + 1) * 21
        x = a0 + (3 if j % 2 else -2)
        while x < a1 - 8:
            w = min(56 if (k % 3) else 40, a1 - x + (0 if j % 2 else 3))
            if w < 20:
                break
            container(c, x, y, w, 21, cols[(k * 3 + j) % len(cols)], doors=(k % 5 == 2))
            x += w
            k += 1
    # The top course (the roof the node stands on): a flat container row with
    # a parapet rail.
    c.rect(a0 - 2, roof - 2, a1 - a0 + 4, 3, STEEL[2])
    c.hline(a0 - 2, a1 + 1, roof - 2, STEEL[4])
    for px in range(a0, a1, 8):
        c.vline(px, roof - 8, roof - 3, STEEL[1])
    c.hline(a0 - 2, a1 + 1, roof - 8, STEEL[3])
    # A rooftop shed and the lattice mast with its lamp (Room 3's tower).
    c.rect(a0 + 10, roof - 24, 30, 22, BULK[2])
    c.hline(a0 + 10, a0 + 39, roof - 24, BULK[4])
    c.rect(a0 + 14, roof - 18, 8, 16, BULK[1])
    c.rect(a0 + 28, roof - 19, 8, 6, GLASSN[1])
    s.glow(a0 + 28, roof - 19, 8, 6, WARM_WIN)
    mx = s.lx(nx + 38)
    lattice(c, mx - 5, roof - 150, mx + 5, roof - 3, STEEL[1], STEEL[3], step=10)
    c.rect(mx - 8, roof - 156, 17, 6, BULK[2])
    c.hline(mx - 8, mx + 8, roof - 156, BULK[4])
    c.rect(mx - 5, roof - 153, 11, 3, "#ffd9a0")
    s.glow(mx - 5, roof - 153, 11, 3, SODIUM)
    c.vline(mx, roof - 172, roof - 157, STEEL[2])
    c.px(mx, roof - 173, HAZARD[4])
    s.glow(mx, roof - 173, 1, 1, SODIUM)
    # Block B: a taller brick tenement to the right; the water tower stands on
    # it (the bonus node), its fire escape is the way down.
    tx, ty = node_pos("water_tower")
    b0, b1 = s.lx(fx - 8), s.lx(fx + 104)
    broof = s.ly(ty) + 2
    c.rect(b0, broof, b1 - b0, base - broof, BRICKR[2])
    yy, xx = np.mgrid[0:c.h, 0:c.w]
    wall = (xx >= b0) & (xx < b1) & (yy >= broof) & (yy < base)
    course = ((yy - broof) % 4 == 3) & wall
    c.fill(course, BRICKR[1])
    joint = wall & ((yy - broof) % 4 != 3) & (((xx - b0) + ((yy - broof) // 4 % 2) * 4) % 8 == 0)
    c.fill(joint, BRICKR[1])
    n = value_noise(c.w, c.h, 6, 55, 2)
    c.fill(wall & (n > 0.66) & ~course, BRICKR[3])
    c.rect(b0 - 2, broof - 4, b1 - b0 + 4, 5, CONC[3])     # cornice
    c.hline(b0 - 2, b1 + 1, broof - 4, CONC[5])
    c.hline(b0 - 2, b1 + 1, broof, CONC[1])
    c.vline(b1 - 1, broof, base - 1, BRICKR[3])
    # Windows in rows, some lit (people still asleep, a few awake).
    rng = np.random.default_rng(12)
    for wy in range(broof + 12, base - 20, 26):
        for wx in range(b0 + 10, b1 - 14, 22):
            c.rect(wx - 1, wy - 1, 12, 16, CONC[3])
            c.rect(wx, wy, 10, 14, GLASSN[1])
            c.hline(wx, wx + 9, wy + 7, CONC[2])
            c.hline(wx - 2, wx + 11, wy + 15, CONC[4])
            if rng.random() < 0.35:
                s.glow(wx, wy, 10, 14, WARM_WIN if rng.random() < 0.6 else WARM_DIM)
                s.g.hline(wx, wx + 9, wy + 7, "#000000")
    # Ground floor: a shuttered shop front.
    c.rect(b0 + 6, base - 24, b1 - b0 - 12, 24, BULK[1])
    for sy in range(base - 22, base - 2, 3):
        c.hline(b0 + 8, b1 - 9, sy, STEEL[2])
    c.rect(b0 + 4, base - 28, b1 - b0 - 8, 4, MAROON[2])
    c.hline(b0 + 4, b1 - 5, base - 28, MAROON[4])
    c.outline(INK)
    return s


def water_tower():
    tx, ty = node_pos("water_tower")
    s = Sheet("water_tower", tx - 40, ty - 96, 84, 98)
    c = s.c
    base = s.ly(ty) + 2
    cx = s.lx(tx) + 8
    # Steel legs with cross bracing.
    legs = [cx - 20, cx - 7, cx + 6, cx + 19]
    leg_top = base - 30
    for lx in legs:
        c.rect(lx, leg_top, 2, base - leg_top, STEEL[1])
        c.vline(lx + 1, leg_top, base - 1, STEEL[3])
    for i in range(3):
        line(c, legs[i], leg_top + 2, legs[i + 1], base - 4, STEEL[1])
        line(c, legs[i + 1], leg_top + 2, legs[i], base - 4, STEEL[1])
    c.rect(cx - 22, leg_top - 3, 45, 3, STEEL[2])
    c.hline(cx - 22, cx + 22, leg_top - 3, STEEL[4])
    # The wooden barrel tank: staves, two hoops, a conical roof with a finial.
    t0, t1 = cx - 20, cx + 21
    ttop = leg_top - 42
    yy, xx = np.mgrid[0:c.h, 0:c.w]
    tank = (xx >= t0) & (xx < t1) & (yy >= ttop) & (yy < leg_top - 3)
    u = (xx - t0) / (t1 - t0)
    v = 0.25 + np.sin(np.clip(u, 0, 1) * np.pi * 0.9 + 0.25) * 0.55 + (value_noise(c.w, c.h, 4, 8, 1) - 0.5) * 0.15
    wood = ["#3a2a2c", "#5e4034", "#7e5a40", "#9c7650", "#b8946a"]
    c.a[tank] = quantize(v, wood, tank, dither=0.0)[tank]
    for sx in range(t0 + 3, t1, 4):
        c.vline(sx, ttop, leg_top - 4, wood[1])
    for hy in (ttop + 9, ttop + 26):
        c.hline(t0, t1 - 1, hy, STEEL[1])
        c.hline(t0, t1 - 1, hy + 1, STEEL[3])
    roof = c.mask_poly([(t0 - 3, ttop + 1), (cx, ttop - 14), (t1 + 3, ttop + 1)])
    c.fill(roof, BULK[2])
    rlit = roof & (xx >= cx)
    c.fill(rlit, BULK[3])
    line(c, cx, ttop - 14, t1 + 3, ttop + 1, BULK[4])
    c.hline(t0 - 3, t1 + 2, ttop + 1, BULK[1])
    c.vline(cx, ttop - 19, ttop - 15, STEEL[2])
    c.px(cx, ttop - 20, HAZARD[4])
    s.glow(cx, ttop - 20, 1, 1, SODIUM)
    # Ladder up the tank's side.
    for lx in (t1 + 1, t1 + 5):
        c.vline(lx, ttop + 2, base - 1, STEEL[2])
    for ly in range(ttop + 4, base, 4):
        c.hline(t1 + 1, t1 + 5, ly, STEEL[3])
    c.outline(INK)
    return s


# ---- the perimeter ---------------------------------------------------------------

def perimeter():
    nx, ny = node_pos("perimeter")
    s = Sheet("perimeter", nx - 150, BASE_Y - 166, 302, 167)
    c = s.c
    base = s.ly(BASE_Y)
    cx = s.lx(nx)
    # Chain-link fence along the whole front, with barbed coil on top.
    f0, f1 = 4, 298
    ftop = base - 58
    yy, xx = np.mgrid[0:c.h, 0:c.w]
    mesh = (xx >= f0) & (xx < f1) & (yy >= ftop) & (yy < base - 2)
    gate = (xx >= cx - 26) & (xx < cx + 26)
    mesh &= ~gate
    diag = (((xx + yy) % 6 == 0) | ((xx - yy) % 6 == 0)) & mesh
    c.fill(diag, STEEL[2])
    for px in range(f0, f1, 32):
        if abs(px - cx) < 30:
            continue
        c.rect(px, ftop - 4, 3, base - ftop + 4, STEEL[2])
        c.vline(px + 2, ftop - 4, base - 1, STEEL[4])
        line(c, px, ftop - 4, px - 6, ftop - 10, STEEL[2])
    for ry in (ftop, base - 3):
        for x in range(f0, f1):
            if not gate[0, x]:
                c.px(x, ry, STEEL[3])
    # Barbed coil: a row of loops.
    for x in range(f0, f1, 7):
        if abs(x - cx) < 30:
            continue
        for a in range(0, 360, 30):
            r = 3.5
            px = round(x + 3 + np.cos(np.radians(a)) * r)
            py = round(ftop - 12 + np.sin(np.radians(a)) * r)
            c.px(px, py, STEEL[3] if a < 180 else STEEL[1])
    # Guard towers at both ends: lattice legs, a cabin with lit windows, a roof.
    for tx in (30, 272):
        lattice(c, tx - 9, base - 108, tx + 9, base - 1, STEEL[1], STEEL[3], step=12)
        cab = base - 132
        c.rect(tx - 16, cab, 33, 24, BULK[2])
        c.hline(tx - 16, tx + 16, cab, BULK[4])
        c.rect(tx - 13, cab + 5, 27, 10, GLASSN[1])
        s.glow(tx - 13, cab + 5, 27, 10, WARM_WIN)
        for mx in (tx - 4, tx + 5):
            c.vline(mx, cab + 5, cab + 14, BULK[1])
            s.g.vline(mx, cab + 5, cab + 14, "#000000")
        c.rect(tx - 19, cab + 22, 39, 3, BULK[1])
        c.poly([(tx - 21, cab), (tx, cab - 13), (tx + 21, cab)], BULK[1])
        c.poly([(tx, cab - 13), (tx + 21, cab), (tx, cab)], BULK[3])
        line(c, tx, cab - 13, tx + 21, cab, BULK[4])
    # The master gate: two concrete posts, a header with three lamps, the
    # supervisors' sign, the slid-open gate leaf behind the right post.
    p0, p1 = cx - 34, cx + 26
    for px in (p0, p1):
        c.rect(px, base - 92, 9, 92, CONC[2])
        c.vline(px, base - 92, base - 1, CONC[1])
        c.vline(px + 8, base - 92, base - 1, CONC[4])
        for sy in range(base - 84, base - 6, 10):
            c.rect(px + 3, sy, 3, 4, TEAL[2])
    hy = base - 104
    c.rect(p0 - 6, hy, p1 - p0 + 21, 14, BULK[2])
    c.hline(p0 - 6, p1 + 14, hy, BULK[4])
    c.hline(p0 - 6, p1 + 14, hy + 13, BULK[0])
    for i in range(3):
        lx = cx - 18 + i * 14
        c.rect(lx - 1, hy + 3, 10, 7, BULK[0])
        c.rect(lx, hy + 4, 8, 5, "#cfeeea")
        s.glow(lx, hy + 4, 8, 5, GATE_LAMP)
    # Sign board above the header.
    c.rect(cx - 30, hy - 18, 60, 13, BULK[0])
    c.rect(cx - 28, hy - 16, 56, 9, "#1a2230")
    for k in range(cx - 24, cx + 22, 4):
        c.rect(k, hy - 13, 2, 3, HAZARD[3])
    s.glow(cx - 24, hy - 13, 46, 3, WARM_DIM)
    c.vline(cx - 20, hy - 5, hy - 1, BULK[1])
    c.vline(cx + 19, hy - 5, hy - 1, BULK[1])
    # The gate leaf, slid open behind the right post.
    lx0 = p1 + 9
    c.rect(lx0, base - 60, 46, 58, STEEL[1])
    for k in range(lx0 + 2, lx0 + 46, 5):
        c.vline(k, base - 58, base - 4, STEEL[3])
    c.hline(lx0, lx0 + 45, base - 60, STEEL[4])
    # A searchlight on the right tower (its beam is drawn by the map).
    c.rect(272 + 13, base - 140, 7, 6, BULK[1])
    c.rect(272 + 14, base - 139, 4, 4, "#f4fbff")
    s.glow(272 + 14, base - 139, 4, 4, COOL_LAMP)
    c.outline(INK)
    return s


# ---- the signal box ----------------------------------------------------------------

def signal_box():
    bx, by = node_pos("signal_box")
    s = Sheet("signal_box", bx - 92, by - 70, 180, BASE_Y - by + 71)
    c = s.c
    base = s.ly(BASE_Y)
    floor = s.ly(by) + 2
    cx = s.lx(bx)
    # The railway embankment: a long grassy bank with the track on top.
    yy, xx = np.mgrid[0:c.h, 0:c.w]
    bank = c.mask_poly([(0, base), (20, floor), (160, floor), (179, base)])
    n = value_noise(c.w, c.h, 5, 61, 2)
    v = 0.35 + (n - 0.5) * 0.5 + (yy - floor) / 120.0
    c.a[bank] = quantize(np.clip(v, 0, 1), GRASS, bank, dither=0.4)[bank]
    c.rect(18, floor - 3, 144, 4, GRAVEL[1])
    c.hline(18, 161, floor - 3, GRAVEL[3])
    c.rect(16, floor - 5, 148, 2, STEEL[3])           # the rail
    c.hline(16, 163, floor - 5, STEEL[5])
    for k in range(18, 162, 6):
        c.rect(k, floor - 3, 3, 1, "#4a3428")         # sleepers' ends
    # The cabin: brick base, glazed upper storey, a hipped roof, steps.
    c0, c1 = cx - 22, cx + 24
    ctop = floor - 48
    c.rect(c0, floor - 22, c1 - c0, 20, BRICKR[2])
    for ky in range(floor - 21, floor - 2, 4):
        c.hline(c0, c1 - 1, ky, BRICKR[1])
    c.rect(c0 - 2, floor - 25, c1 - c0 + 4, 3, CONC[4])
    c.rect(c0, ctop, c1 - c0, 23, "#7e2f30")
    c.rect(c0 + 2, ctop + 4, c1 - c0 - 4, 13, GLASSN[1])
    for mx in range(c0 + 2, c1 - 2, 7):
        c.vline(mx, ctop + 4, ctop + 16, "#efe6d4")
    c.hline(c0 + 2, c1 - 3, ctop + 4, "#efe6d4")
    s.glow(c0 + 3, ctop + 5, c1 - c0 - 6, 11, WARM_DIM)
    c.poly([(c0 - 5, ctop + 1), (cx + 1, ctop - 12), (c1 + 5, ctop + 1)], BULK[2])
    c.poly([(cx + 1, ctop - 12), (c1 + 5, ctop + 1), (cx + 1, ctop + 1)], BULK[3])
    c.hline(c0 - 5, c1 + 4, ctop + 1, BULK[1])
    c.rect(cx + 6, ctop - 16, 4, 6, BRICKR[2])        # stove pipe
    # A semaphore signal post on the bank.
    sx = c1 + 30
    c.rect(sx, floor - 62, 2, 58, STEEL[2])
    c.vline(sx + 1, floor - 62, floor - 5, STEEL[4])
    c.rect(sx + 2, floor - 58, 14, 4, "#c83c3c")
    c.rect(sx + 12, floor - 58, 2, 4, "#efe6d4")
    c.rect(sx - 3, floor - 57, 3, 3, BULK[1])
    s.glow(sx - 3, floor - 57, 2, 2, "#ff9a3c")
    c.outline(INK)
    return s


# ---- home ----------------------------------------------------------------------------

def home():
    nx, ny = node_pos("home")
    s = Sheet("home", nx - 128, BASE_Y - 150, 262, 151)
    c = s.c
    base = s.ly(BASE_Y)
    cx = s.lx(nx)
    # A tree first (behind the fence, left of the house).
    t = H.tree(110, 140, 41, trunk_h=0.45)
    c.blit(t, 0, base - 140 + 2)
    # The house: dusty-blue clapboard, a terracotta gable, white trim.
    x0, x1 = cx - 52, cx + 92
    wall_top = base - 70
    H.siding(c, x0, wall_top, x1 - x0, 62, H.DUSTY, board=4)
    c.rect(x0, base - 8, x1 - x0, 8, "#8c8790")
    c.hline(x0, x1 - 1, base - 8, "#aaa5ae")
    c.vline(x1 - 1, wall_top, base - 9, H.DUSTY[4])
    c.vline(x0, wall_top, base - 9, H.DUSTY[0])
    H.roof(c, x0, x1, wall_top, wall_top - 48, H.TERRACOTTA, overhang=7)
    H.eave_shadow(c, x0, x1, wall_top + 2, 4)
    # Door with the cat flap, on the node.
    c.rect(cx - 10, base - 44, 22, 36, H.TRIM[3])
    c.rect(cx - 8, base - 42, 18, 34, "#9c5040")
    c.vline(cx + 9, base - 42, base - 9, "#ba6c50")
    c.rect(cx - 5, base - 39, 12, 7, H.GLASS[3])
    c.rect(cx - 4, base - 17, 10, 8, "#5a2c30")        # the flap
    c.hline(cx - 4, cx + 5, base - 17, "#d08a64")
    c.rect(cx + 6, base - 27, 2, 2, "#f0cc4a")
    c.rect(cx - 14, base - 48, 30, 4, H.TERRACOTTA[3])  # hood
    c.hline(cx - 14, cx + 15, base - 48, H.TERRACOTTA[4])
    # Windows: two sashes with curtains; warm inside at dawn.
    for wx in (cx + 26, cx + 58):
        H.window(c, wx, wall_top + 14, 20, 24, panes=(2, 2), curtains=["#c0a080", "#e8d4b0", "#f8ecd0"])
        s.glow(wx + 4, wall_top + 14, 12, 24, "#6a4a2a")
    # Round gable window.
    gx = (x0 + x1) // 2
    c.ellipse(gx, wall_top - 18, 6, 6, H.TRIM[3])
    c.ellipse(gx, wall_top - 18, 4, 4, H.GLASS[2])
    # Gutter and downpipe.
    c.rect(x0 - 7, wall_top + 1, x1 - x0 + 14, 2, "#9aa2b0")
    c.rect(x1 + 2, wall_top + 3, 2, 58, "#9aa2b0")
    # Step under the door.
    c.rect(cx - 14, base - 8, 30, 4, H.CONCRETE[4])
    c.hline(cx - 14, cx + 15, base - 8, H.CONCRETE[5])
    c.outline(H.INK_SOFT)
    # A low picket fence in front, with a gap at the path to the door.
    f = H.picket_fence(80, 46)
    fh = 26
    small = Canvas(f.w, fh)
    small.a = f.a[46 - fh:, :]
    for fx in range(0, c.w, 80):
        part = Canvas(80, fh)
        part.a = small.a.copy()
        gap0, gap1 = cx - 14 - fx, cx + 16 - fx
        if gap1 > 0 and gap0 < 80:
            part.a[:, max(gap0, 0):min(gap1, 80)] = 0
        c.blit(part, fx, base - fh + 1)
    # Flowers along the fence foot.
    fb = H.flower_bed(96, 22, 3)
    c.blit(fb, cx + 30, base - 14)
    c.blit(H.bush(40, 26, 6, flowers="pink"), cx - 64, base - 24)
    return s


# ---- the storm drain ---------------------------------------------------------------

def drain():
    dx, dy = node_pos("drain")
    s = Sheet("drain", dx - 26, dy - 30, 52, 32)
    c = s.c
    floor = s.ly(dy) + 1
    cx = s.lx(dx)
    # A round culvert mouth in the ditch wall, behind a bent grate.
    c.ellipse(cx, floor - 12, 15, 13, CONC[3])
    c.ellipse(cx, floor - 12, 12, 11, "#05070d")
    yy, xx = np.mgrid[0:c.h, 0:c.w]
    ring = c.mask_ellipse(cx, floor - 12, 15, 13) & ~c.mask_ellipse(cx, floor - 12, 12, 11)
    c.fill(ring & (yy < floor - 16), CONC[4])
    c.rect(0, floor - 1, c.w, 2, CONC[2])
    for gx in range(cx - 10, cx + 11, 4):
        top = floor - 12 - int(np.sqrt(max(0, 121 - (gx - cx) ** 2)) * 0.95)
        c.vline(gx, top, floor - 2, STEEL[1])
        c.vline(gx + 1, top + 1, floor - 2, STEEL[3])
    c.hline(cx - 11, cx + 11, floor - 14, STEEL[3])
    # One bar bent aside: a gap a cat could slip through.
    c.a[floor - 12:floor - 2, cx + 2:cx + 4] = (*rgb("#05070d"), 255)
    line(c, cx + 2, floor - 12, cx + 6, floor - 4, STEEL[3])
    # A trickle of water from the mouth.
    c.hline(cx - 6, cx + 6, floor - 2, "#6f8fb8")
    s.glow(cx - 5, floor - 2, 10, 1, "#24405a")
    c.outline(INK)
    return s


# ---- the street (scroll 1) ----------------------------------------------------------

STRIP_Y = 284


def street():
    """The ground band the whole map stands on: a strip of yard behind the
    sidewalk, the sidewalk (the main path), the kerb, the road. Its materials
    change from the industrial end (concrete apron, rail lines) to the suburbs
    (pale paving, a lawn strip); a ditch crosses it at the storm drain."""
    w, h = MAP_W, 360 - STRIP_Y
    c = Canvas(w, h)
    yy, xx = np.mgrid[0:h, 0:w]
    n = value_noise(w, h, 8, 5, 2)
    p = np.clip((xx - 200) / 1670.0, 0, 1)            # 0 warehouse .. 1 home
    sub = p > 0.86                                       # the suburbs
    by = BASE_Y - STRIP_Y                                # 12: the back edge
    py = PATH_Y - STRIP_Y                                # 18: the walking line
    # Behind the sidewalk: gravel (industrial) or lawn (suburbs).
    back = yy < by
    c.a[back & ~sub] = quantize(0.4 + (n - 0.5) * 0.5, GRAVEL, back & ~sub, dither=0.4)[back & ~sub]
    c.a[back & sub] = quantize(0.5 + (n - 0.5) * 0.6, GRASS, back & sub, dither=0.4)[back & sub]
    # Sidewalk slab.
    walk = (yy >= by) & (yy < py + 5)
    sv = 0.55 + (yy - by) / 12.0 * 0.15 + (n - 0.5) * 0.2
    pale = np.where(sub, 0.18, 0.0)
    c.a[walk] = quantize(np.clip(sv + pale, 0, 1), CONC, walk, dither=0.3)[walk]
    c.a[by, :] = (*rgb(CONC[4]), 255)
    for sx in range(0, w, 48):
        c.vline(sx, by + 1, py + 4, CONC[2])
    c.a[py + 5, :] = (*rgb(CONC[5]), 255)                # the kerb's lit lip
    kerb = (yy >= py + 6) & (yy < py + 12)
    c.a[kerb] = quantize(0.42 - (yy - py - 6) / 6.0 * 0.25 + (n - 0.5) * 0.1, CONC, kerb, dither=0.3)[kerb]
    c.a[py + 12:py + 14, :] = (*rgb(TAR[0]), 255)          # gutter
    c.a[py + 13, :] = (*rgb("#5a7aa0"), 255)
    road = yy >= py + 14
    rv = 0.4 + (n - 0.5) * 0.4 + (yy - py - 14) / 60.0 * 0.15
    c.a[road] = quantize(np.clip(rv, 0, 1), TAR, road, dither=0.6)[road]
    # Lane dashes on the road (pale, worn), rail lines in the yard stretch.
    for lx in range(10, w, 56):
        c.rect(lx, py + 34, 26, 2, "#8c8c8a")
    for rx0, rx1 in ((420, 790),):
        for ry in (py + 22, py + 28):
            c.rect(rx0, ry, rx1 - rx0, 1, STEEL[3])
            c.rect(rx0, ry + 1, rx1 - rx0, 1, STEEL[1])
    rng = np.random.default_rng(9)
    for _ in range(260):
        x, y = rng.integers(0, w), rng.integers(py + 15, h)
        c.px(int(x), int(y), TAR[3])
    # Puddles on the road (they read as sky at night: a lighter blue-grey).
    for px, pw in ((140, 46), (330, 30), (560, 54), (980, 40), (1250, 36), (1500, 50)):
        m = c.mask_ellipse(px, py + 30, pw / 2, 3)
        c.fill(m, "#3c4c6a")
        c.fill(m & (xx < px - pw / 4) & (yy == py + 29), "#6a82a8")
    # The ditch at the storm drain: the walkway becomes a little bridge.
    dx, dy = node_pos("drain")
    d0, d1 = dx - 48, dx + 34
    ditch = (xx >= d0) & (xx < d1) & (yy > py + 5)
    c.a[ditch] = (*rgb("#0d1018"), 255)
    floor = dy - STRIP_Y + 1
    wallm = ditch & (yy < floor)
    wv = 0.25 + (n - 0.5) * 0.2 + (yy - py) / 80.0
    c.a[wallm] = quantize(np.clip(wv, 0, 1), CONC[:4], wallm, dither=0.3)[wallm]
    c.a[floor:floor + 3, d0:d1] = (*rgb(CONC[2]), 255)
    c.a[floor, d0:d1] = (*rgb(CONC[3]), 255)
    c.a[floor + 3:, d0:d1] = (*rgb("#1e2a3c"), 255)      # standing water
    c.a[floor + 4, d0 + 4:d1 - 4:3] = (*rgb("#4e6688"), 255)
    for bx in (d0 - 2, d1 - 1):
        c.rect(bx, py + 4, 3, h, CONC[1])
    c.rect(d0 - 2, py + 4, d1 - d0 + 4, 3, CONC[3])     # the bridge deck edge
    c.hline(d0 - 2, d1 + 1, py + 4, CONC[5])
    return c


# ---- far and mid layers ---------------------------------------------------------------

def mid_layer():
    """Mid distance (scroll 0.45): the industrial district's sheds, gas holders,
    chimneys and far cranes at the left, the suburbs' roofs and trees at the
    right. Low contrast, a haze ramp. Layer x 0 = WorldMap.MID_X0."""
    w, h = 1320, 150
    c = Canvas(w, h)
    rng = np.random.default_rng(31)
    haze = ["#1e2638", "#2a3448", "#38445a", "#4a566c", "#5e6a80"]
    roofh = ["#2a3448", "#3a465c"]
    x = 0
    while x < 980:
        kind = rng.choice(["shed", "tank", "chimney", "block", "crane"], p=[0.35, 0.15, 0.15, 0.25, 0.10])
        if kind == "shed":
            sw = int(rng.integers(60, 110))
            sh = int(rng.integers(28, 46))
            c.rect(x, h - sh, sw, sh, haze[1])
            for k in range(x, x + sw - 10, 14):
                c.poly([(k, h - sh), (k + 10, h - sh - 8), (k + 10, h - sh)], haze[2])
                c.vline(k + 10, h - sh - 8, h - sh, haze[0])
            for k in range(x + 6, x + sw - 6, 9):
                if rng.random() < 0.3:
                    c.rect(k, h - sh + 10, 4, 3, haze[3])
            x += sw + int(rng.integers(-6, 10))
        elif kind == "tank":
            r = int(rng.integers(20, 30))
            th = int(rng.integers(36, 56))
            c.rect(x, h - th, r * 2, th, haze[2])
            c.ellipse(x + r, h - th, r, 5, haze[3])
            for k in range(x, x + r * 2, 6):
                c.vline(k, h - th, h - 1, haze[1])
            c.vline(x + r * 2 - 2, h - th, h - 1, haze[3])
            x += r * 2 + int(rng.integers(4, 16))
        elif kind == "chimney":
            ch = int(rng.integers(70, 110))
            c.rect(x, h - ch, 8, ch, haze[2])
            c.vline(x + 7, h - ch, h - 1, haze[3])
            c.rect(x - 1, h - ch, 10, 3, haze[3])
            for k in range(h - ch + 8, h, 18):
                c.hline(x, x + 7, k, haze[4])
            x += 22
        elif kind == "block":
            bw = int(rng.integers(34, 60))
            bh = int(rng.integers(50, 90))
            c.rect(x, h - bh, bw, bh, haze[1])
            c.vline(x + bw - 1, h - bh, h - 1, haze[2])
            for wy in range(h - bh + 6, h - 6, 8):
                for wx in range(x + 4, x + bw - 6, 7):
                    if rng.random() < 0.18:
                        c.rect(wx, wy, 3, 4, haze[3])
            x += bw + int(rng.integers(0, 8))
        else:
            # A far container crane: a leg and a boom.
            c.rect(x + 10, h - 80, 4, 80, haze[2])
            c.rect(x + 34, h - 80, 4, 80, haze[2])
            c.rect(x, h - 84, 70, 5, haze[2])
            c.hline(x, x + 69, h - 84, haze[3])
            x += 60
    # The suburbs: rooftops among trees, warm windows.
    rx = 940
    while rx < w:
        rw = int(rng.integers(44, 70))
        top = h - int(rng.integers(40, 56))
        col = rng.choice(["#4a4a66", "#5a4048"])
        c.poly([(rx, h), (rx, top + 14), (rx + rw / 2, top), (rx + rw, top + 14), (rx + rw, h)], str(col))
        c.poly([(rx + rw / 2, top), (rx + rw, top + 14), (rx + rw, h), (rx + rw / 2, h)], mixc(str(col), "#8890a8", 0.25))
        c.rect(rx + 6, top + 14, rw - 12, h - top - 14, "#6a7088")
        if rng.random() < 0.5:
            c.rect(rx + rw // 2 - 3, top + 22, 6, 6, "#c08850")
        rx += rw + int(rng.integers(10, 40))
    trees = H.treeline(w - 900, 120)
    c.blit(trees, 900, h - 120)
    # Fade the seam between the districts with a short gap of scrub.
    return c


# ---- foreground (scroll 1.3) -------------------------------------------------------------

def foreground():
    """The nearest layer, passing faster than the map: utility poles with
    sagging cables across the top of the view, and low scrub, bollards and a
    hydrant along the bottom edge. Layer x 0 = WorldMap.FG_X0."""
    w, h = 2720, 360
    c = Canvas(w, h)
    rng = np.random.default_rng(71)
    poles = list(range(60, w, 330))
    pole_col = ["#141420", "#22222e", "#30303e"]
    tops = []
    for px in poles:
        top = int(rng.integers(-40, -10))
        tops.append(top)
        # Only the top of the pole is in view: it comes down from above.
        c.rect(px, 0, 6, 46 + top + 40, pole_col[1])
        c.vline(px + 5, 0, 46 + top + 39, pole_col[2])
        y = 22 + top + 40
        c.rect(px - 18, y, 42, 3, pole_col[1])
        c.hline(px - 18, px + 23, y, pole_col[2])
        for ix in (px - 16, px - 6, px + 10, px + 20):
            c.rect(ix, y - 3, 2, 3, "#3a3a48")
    # Cables between neighbouring poles: sagging catenaries.
    for i in range(len(poles) - 1):
        a, b = poles[i], poles[i + 1]
        ya = 22 + tops[i] + 40
        yb = 22 + tops[i + 1] + 40
        for j, (ox, sag) in enumerate(((-16, 26), (-6, 34), (10, 30), (20, 22))):
            x0, x1 = a + ox + 1, b + ox + 1
            for x in range(x0, x1 + 1):
                t = (x - x0) / (x1 - x0)
                y = ya + (yb - ya) * t - 2 + sag * 4 * t * (1 - t)
                c.px(x, round(y), pole_col[0] if j % 2 else pole_col[1])
    # Bottom edge: weeds, bollards, a hydrant.
    x = 20
    while x < w:
        kind = rng.choice(["weed", "bollard", "weed", "nothing", "hydrant"], p=[0.35, 0.2, 0.2, 0.2, 0.05])
        if kind == "weed":
            for k in range(int(rng.integers(4, 9))):
                bx = x + int(rng.integers(0, 14))
                bh = int(rng.integers(6, 14))
                line(c, bx, h, bx + int(rng.integers(-3, 4)), h - bh, pole_col[1] if k % 2 else pole_col[0])
            x += int(rng.integers(30, 80))
        elif kind == "bollard":
            c.rect(x, h - 14, 6, 14, pole_col[1])
            c.rect(x - 1, h - 15, 8, 2, pole_col[2])
            c.hline(x, x + 5, h - 10, "#5a4a2a")
            x += int(rng.integers(40, 100))
        elif kind == "hydrant":
            c.rect(x, h - 16, 8, 16, "#2e1a20")
            c.rect(x - 2, h - 12, 12, 3, "#2e1a20")
            c.rect(x + 1, h - 19, 6, 3, "#3a2228")
            x += 70
        else:
            x += int(rng.integers(40, 120))
    return c


# ---- markers -----------------------------------------------------------------------------

def markers():
    """Node marker plates (3/4 view ellipses) and small icons, one sheet."""
    out = {}
    # 0: available (bright ring), 1: done (filled), 2: locked (dark).
    for name, ring, fill, hi in (("plate_open", "#ffe0a0", "#7a5a2c", "#fff4d8"),
                                 ("plate_done", "#e8dcc4", "#a89a80", "#ffffff"),
                                 ("plate_locked", "#4a4e60", "#2a2c3a", "#5e6276")):
        c = Canvas(26, 10)
        c.ellipse(13, 5, 12.5, 4.5, ring)
        c.ellipse(13, 5, 10, 3, fill)
        c.hline(5, 20, 1, hi)
        c.outline(INK)
        out[name] = c
    # Icons get a 1 px margin so the outline has room.
    lock = Canvas(11, 12)
    lock.rect(3, 1, 5, 1, "#8a8ea0")
    lock.vline(2, 2, 4, "#8a8ea0")
    lock.vline(8, 2, 4, "#8a8ea0")
    lock.rect(1, 5, 9, 6, "#9aa0b4")
    lock.hline(1, 9, 5, "#c4c8d6")
    lock.rect(5, 7, 1, 2, "#2a2c3a")
    lock.outline(INK)
    out["padlock"] = lock
    star = Canvas(11, 11)
    pts = []
    for i in range(10):
        a = -np.pi / 2 + i * np.pi / 5
        r = 4.4 if i % 2 == 0 else 1.9
        pts.append((5.5 + np.cos(a) * r, 5.6 + np.sin(a) * r))
    star.poly(pts, "#ffd23f")
    star.outline(INK)
    out["star"] = star
    gem = Canvas(9, 9)
    gem.poly([(4.5, 1), (8, 4.5), (4.5, 8), (1, 4.5)], "#c3d8cf")
    gem.poly([(4.5, 1), (8, 4.5), (4.5, 4.5)], "#f1f5e6")
    gem.outline(INK)
    out["gem"] = gem
    arrow = Canvas(9, 10)
    arrow.poly([(4.5, 1), (8, 5), (5.5, 5), (5.5, 9), (3.5, 9), (3.5, 5), (1, 5)], "#ffe9b8")
    arrow.outline(INK)
    out["arrow"] = arrow
    return out


def main():
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "assets" / "art_hd" / "map"
    out.mkdir(parents=True, exist_ok=True)
    meta = {"strip_y": STRIP_Y, "landmarks": {}}
    for fn in (warehouse, yard, stacks, water_tower, perimeter, signal_box, home, drain):
        s = fn()
        s.c.save(out / f"{s.name}.png")
        has_glow = bool((s.g.a[..., 3] > 0).any() and (s.g.a[..., :3] > 0).any())
        if has_glow:
            s.g.save(out / f"{s.name}_glow.png")
        meta["landmarks"][s.name] = {"origin": [s.x0, s.y0], "size": [s.c.w, s.c.h], "glow": has_glow}
        print(f"{s.name}: {s.c.w}x{s.c.h} at {s.x0},{s.y0}")
    street().save(out / "street.png")
    mid_layer().save(out / "mid.png")
    foreground().save(out / "foreground.png")
    for name, c in markers().items():
        c.save(out / f"{name}.png")
    (out / "map_art.json").write_text(json.dumps(meta, indent=2) + "\n")
    print("ok")


if __name__ == "__main__":
    main()
