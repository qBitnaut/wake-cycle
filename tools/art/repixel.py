#!/usr/bin/env python3
"""Whole-pixel rescaling for the B' scale (cat at 1.5x of its 1x art, room
robots at 2/3), shared by the cat pipeline and the room robots. Nothing is
scaled by a fractional factor at run time: every output pixel is a whole
game pixel.

1.5x (the cat): Scale3x (AdvMAME3x) and a nearest /2. Scale3x rounds the
diagonals the way Scale2x does at 2x, and the /2 keeps the source colours
(no blending), so the art stays in the pack's pixel language. The 1 px ink
outline goes on afterwards, at the new size (cat_hd.py).

2/3 (the robots): Scale2x, then a 3x3 block reduction (coverage decides
alpha, the mode of the opaque pixels decides colour), the silhouette's edge
re-inked, and the small accents (red sensors, visors, lamps) that a block
vote drops in some frames and keeps in others stamped back where they
belong: a dot as one pixel at its scaled centre, a line (a visor) as its
scaled run with the ink slit above it, so nothing flickers along a walk.
The block vote loses the drones' thin struts and rings, so the two room
drones are hand-drawn at 2/3 here instead (DRONES), on the source's palette.

Room robots written here (the kit has its own, tools/art/kit_art.py; the
room PatrolBot uses the kit's 2/3 patrol bot as is):
    assets/art_hd/robots/mech_23.png     MirrorBot and DockBot, 64x53 cells
    assets/art_hd/robots/drone_1_23.png  GuardDrone, 36x34
    assets/art_hd/robots/drone_3_23.png  SearchDrone, 36x34

Usage: repixel.py [--preview out.png]
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
ROBOTS = ROOT / "assets" / "art_hd" / "robots"
INK = np.array([0x16, 0x16, 0x30, 255], np.uint8)

# The ansimuz robots' sensor reds (harmonised): the accents that get stamped.
ACCENTS = [(0xd8, 0x40, 0x3a), (0xff, 0x4a, 0x3a), (0xff, 0x7a, 0x5a)]


def rgba(path):
    a = np.asarray(Image.open(path).convert("RGBA")).copy()
    a[a[..., 3] == 0] = 0  # one canonical "empty" so the scalers see one colour
    return a


def neigh4(m):
    n = np.zeros_like(m)
    n[1:, :] |= m[:-1, :]
    n[:-1, :] |= m[1:, :]
    n[:, 1:] |= m[:, :-1]
    n[:, :-1] |= m[:, 1:]
    return n


def _eq(x, y):
    return (x == y).all(axis=2)


def scale2x(a):
    """EPX / Scale2x."""
    h, w, _ = a.shape
    p = np.pad(a, ((1, 1), (1, 1), (0, 0)), mode="edge")
    B, D, E, F, H = p[0:h, 1:w + 1], p[1:h + 1, 0:w], p[1:h + 1, 1:w + 1], p[1:h + 1, 2:w + 2], p[2:h + 2, 1:w + 1]

    def pick(c, s):
        return np.where(c[..., None], s, E)
    o = np.zeros((h * 2, w * 2, 4), np.uint8)
    o[0::2, 0::2] = pick(_eq(D, B) & ~_eq(B, F) & ~_eq(D, H), D)
    o[0::2, 1::2] = pick(_eq(B, F) & ~_eq(B, D) & ~_eq(F, H), F)
    o[1::2, 0::2] = pick(_eq(D, H) & ~_eq(D, B) & ~_eq(H, F), D)
    o[1::2, 1::2] = pick(_eq(H, F) & ~_eq(D, H) & ~_eq(B, F), F)
    return o


def scale3x(a):
    """AdvMAME3x / Scale3x."""
    h, w, _ = a.shape
    p = np.pad(a, ((1, 1), (1, 1), (0, 0)), mode="edge")
    A, B, C = p[0:h, 0:w], p[0:h, 1:w + 1], p[0:h, 2:w + 2]
    D, E, F = p[1:h + 1, 0:w], p[1:h + 1, 1:w + 1], p[1:h + 1, 2:w + 2]
    G, H, I = p[2:h + 2, 0:w], p[2:h + 2, 1:w + 1], p[2:h + 2, 2:w + 2]

    def pick(c, s):
        return np.where(c[..., None], s, E)
    core = ~_eq(B, H) & ~_eq(D, F)
    o = np.zeros((h * 3, w * 3, 4), np.uint8)
    o[0::3, 0::3] = pick(core & _eq(D, B), D)
    o[0::3, 1::3] = pick(core & ((_eq(D, B) & ~_eq(E, C)) | (_eq(B, F) & ~_eq(E, A))), B)
    o[0::3, 2::3] = pick(core & _eq(B, F), F)
    o[1::3, 0::3] = pick(core & ((_eq(D, B) & ~_eq(E, G)) | (_eq(D, H) & ~_eq(E, A))), D)
    o[1::3, 1::3] = E
    o[1::3, 2::3] = pick(core & ((_eq(B, F) & ~_eq(E, I)) | (_eq(H, F) & ~_eq(E, C))), F)
    o[2::3, 0::3] = pick(core & _eq(D, H), D)
    o[2::3, 1::3] = pick(core & ((_eq(D, H) & ~_eq(E, I)) | (_eq(H, F) & ~_eq(E, G))), H)
    o[2::3, 2::3] = pick(core & _eq(H, F), F)
    return o


def up15(a):
    """1.5x with whole pixels: Scale3x, then every other row and column.
    Pixel k of the result shows source pixel floor(2k / 3), so a 50 px frame
    becomes 75 px. An even source row or column keeps only the outer thirds
    of its Scale3x block, which Scale3x may hand to the neighbours, so a
    lone pixel (an eye, a glint) could vanish on some frames and not
    others: every source pixel that differs from all four neighbours is put
    back on the pixel holding its centre, (3r + 1) // 2, when none of its
    footprint kept it."""
    o = scale3x(a)[0::2, 0::2]
    h, w, _ = a.shape
    p = np.pad(a, ((1, 1), (1, 1), (0, 0)))
    E = p[1:h + 1, 1:w + 1]
    lone = (E[..., 3] > 0) & ~_eq(E, p[0:h, 1:w + 1]) & ~_eq(E, p[2:h + 2, 1:w + 1]) \
        & ~_eq(E, p[1:h + 1, 0:w]) & ~_eq(E, p[1:h + 1, 2:w + 2])
    span = [(3 * i + 1) // 2 for i in range(max(h, w) + 1)]
    for r, c in zip(*np.nonzero(lone)):
        foot = o[span[r]:span[r + 1], span[c]:span[c + 1]]
        if not _eq(foot, a[r, c][None, None, :]).any():
            o[(3 * r + 1) // 2, (3 * c + 1) // 2] = a[r, c]
    return o


def outline(a, ink=INK):
    """A one-pixel, 4-connected ring outside the silhouette (keeps diagonal
    steps sharp; an 8-connected ring fattens them)."""
    solid = a[..., 3] > 0
    o = a.copy()
    o[neigh4(solid) & ~solid] = ink
    return o


def block_mode(a, k, cover=0.5):
    """k x k reduction: opaque when coverage >= cover, colour = mode of the opaque pixels."""
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


def _at23(i):
    """Source pixel i (its centre) -> the 2/3 pixel it lands in."""
    return int((i + 0.5) * 2 / 3)


def accent_clusters(f, max_size=14):
    """4-connected clusters of accent pixels: [(pixels, colours)]."""
    h, w, _ = f.shape
    acc = np.zeros((h, w), bool)
    for c in ACCENTS:
        acc |= (f[..., :3] == np.array(c, np.uint8)).all(axis=2) & (f[..., 3] > 0)
    seen = np.zeros_like(acc)
    out = []
    for y, x in zip(*np.nonzero(acc)):
        if seen[y, x]:
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
            out.append(pts)
    return out


def stamp_accents(src, r):
    """Put the source's small accents back on its 2/3 frame `r` (in place).
    A cluster one row tall and 3+ wide is a visor: its run is stamped at the
    scaled columns, colour sampled from the source, with the ink slit the
    source has above it. Anything else is a lamp: one pixel at its centre,
    in its most common colour."""
    H, W, _ = r.shape
    for pts in accent_clusters(src):
        ys = [p[0] for p in pts]
        xs = [p[1] for p in pts]
        if min(ys) == max(ys) and max(xs) - min(xs) >= 2:
            y = ys[0]
            oy = _at23(y)
            for ox in range(_at23(min(xs)), _at23(max(xs)) + 1):
                sx = min(max(int(round((ox + 0.5) * 1.5 - 0.5)), min(xs)), max(xs))
                if 0 <= oy < H and 0 <= ox < W and r[oy, ox, 3]:
                    r[oy, ox] = src[y, sx]
                    if oy > 0 and y > 0 and (src[y - 1, sx] == INK).all() and r[oy - 1, ox, 3]:
                        r[oy - 1, ox] = INK
            continue
        cy = sum(ys) / len(ys)
        cx = sum(xs) / len(xs)
        ox, oy = int(cx * 2 / 3 + 1 / 3), int(cy * 2 / 3 + 1 / 3)
        cols = [tuple(src[y, x]) for y, x in pts]
        if 0 <= oy < H and 0 <= ox < W and r[oy, ox, 3]:
            r[oy, ox] = max(set(cols), key=cols.count)


def two_thirds(f, ink=INK):
    """One 1x frame -> 2/3 with whole pixels, a clean 1 px ink edge and its accents."""
    r = block_mode(scale2x(f), 3, cover=0.45)
    solid = r[..., 3] > 0
    r[solid & neigh4(~solid)] = ink
    stamp_accents(f, r)
    return r


def sheet_two_thirds(src, cell):
    a = rgba(src)
    cw, _ch = cell
    frames = [two_thirds(a[:, i * cw:(i + 1) * cw]) for i in range(a.shape[1] // cw)]
    return np.concatenate(frames, axis=1)


# ---- the room drones, drawn by hand at 2/3 ------------------------------------------
# On the ansimuz drones' own five colours. Each row is {column: run}; "." is
# empty. Both are 36x34; drone_3 is symmetric about x = 18 (its antenna and
# body are an even number of pixels wide, so the sprite centres on its axis).

DRONE_PAL = {
    "#": (0x16, 0x16, 0x30, 255),   # ink
    "b": (0x3a, 0x2c, 0x5e, 255),   # dark violet
    "c": (0x9a, 0x98, 0xc8, 255),   # lavender
    "d": (0xe8, 0xec, 0xf2, 255),   # light
    "e": (0xff, 0x4a, 0x3a, 255),   # sensor red
}

# The guard drone: a strut up to the right, the eye pod (left) with its red
# lens in a dark socket (kept 2x2 like the source's: it is the hostile read),
# the axle to the rotor hub, the rotor ring (right) under its cover, a strut
# down to the left.
DRONE_1 = {
    3: {21: "bb"},
    4: {20: "bdcb"},
    5: {19: "bdc#"},
    6: {18: "bdc#"},
    7: {17: "bdc#"},
    8: {16: "bddc#"},
    9: {15: "bdddcb"},
    10: {15: "dddcb#"},
    11: {14: "bcccbb#", 25: "bbbbbb"},
    12: {14: "bbbbb#", 22: "bbccddddddbb"},
    13: {13: "bbdddb", 21: "bcdddddddddcb"},
    14: {12: "bddddb#", 20: "bcddbbbbbbccdb"},
    15: {12: "bddccb", 19: "bcdddddddddddb"},
    16: {11: "bccbbb#", 19: "bccccddddddbb"},
    17: {10: "cdddd##", 17: "##b##bbbbbb##b"},
    18: {10: "cddddd##", 18: "#############cb"},
    19: {9: "cddddd###", 18: "####bbbb#####cdb"},
    20: {9: "cdddd#ee#", 18: "###bbbbbc####cdb"},
    21: {9: "cbbbc#ee#", 18: "###bbbbbc####cdb"},
    22: {9: "cdddd#bb#", 18: "####bbbb####cddb"},
    23: {9: "cdddddd###", 19: "############cddb"},
    24: {9: "ccdddcccc", 18: "b#########cdddb#"},
    25: {10: "bcccccccbb", 20: "##bccccdddddb"},
    26: {10: "bbbbcbbb#", 19: "bb#bcddddddcb#"},
    27: {11: "#####", 16: "bdcb#bbbbbbbb##"},
    28: {16: "bdcb", 21: "#######"},
    29: {15: "bdcb"},
    30: {15: "bdc#"},
    31: {14: "bdcb"},
    32: {14: "bdc#"},
    33: {14: "bcb"},
}

# The search drone: antenna, knob and neck, the shoulder pods, the face plate
# with its seam and the two red lamps (the searchlight shines from just under
# them), and the two legs.
DRONE_3 = {
    2: {17: "cb"},
    3: {17: "db"},
    4: {17: "db"},
    5: {17: "db"},
    6: {16: "bddb"},
    7: {16: "bccb"},
    8: {16: "cddc"},
    9: {16: "cddc"},
    10: {16: "bccb"},
    11: {16: "bbbb"},
    12: {15: "bcddcb"},
    13: {14: "cbddddbc"},
    14: {13: "dcbddddbcd"},
    15: {13: "dcb#dd#bcd"},
    16: {12: "cdcb#cc#bcdc"},
    17: {12: "bcb######bcb"},
    18: {12: "#b#cccccc#b#"},
    19: {12: "##cddccddc##"},
    20: {12: "#c#ddccdd#c#"},
    21: {12: "b#e#dccd#e#b"},
    22: {12: "b#e#cbbc#e#b"},
    23: {12: "#b#ddccdd#b#"},
    24: {12: "#bcddccddcb#"},
    25: {12: "##bccccccb##"},
    26: {13: "##bbccbb##"},
    27: {14: "dd#bb#dd"},
    28: {13: "dcb", 20: "bcd"},
    29: {12: "dcb", 21: "bcd"},
    30: {11: "dcb", 22: "bcd"},
    31: {10: "db", 24: "bd"},
    32: {9: "cb", 25: "bc"},
    33: {8: "cb", 26: "bc"},
}


def draw(rows, w=36, h=34):
    a = np.zeros((h, w, 4), np.uint8)
    for y, runs in rows.items():
        for x0, run in runs.items():
            for i, ch in enumerate(run):
                if ch != ".":
                    a[y, x0 + i] = DRONE_PAL[ch]
    return a


def build():
    return {
        "mech_23.png": sheet_two_thirds(ROBOTS / "mech.png", (96, 80)),
        "drone_1_23.png": draw(DRONE_1),
        "drone_3_23.png": draw(DRONE_3),
    }


def write_preview(sheets, path, z=4):
    rows = list(sheets.values())
    w = max(s.shape[1] for s in rows)
    h = sum(s.shape[0] + 4 for s in rows)
    img = Image.new("RGBA", (w, h), (52, 58, 80, 255))
    y = 0
    for s in rows:
        img.alpha_composite(Image.fromarray(s), (0, y))
        y += s.shape[0] + 4
    img.resize((w * z, h * z), Image.NEAREST).save(path)


def main():
    sheets = build()
    for name, s in sheets.items():
        Image.fromarray(s).save(ROBOTS / name)
        print(f"{name}: {s.shape[1]}x{s.shape[0]}")
    if "--preview" in sys.argv:
        write_preview(sheets, sys.argv[sys.argv.index("--preview") + 1])


if __name__ == "__main__":
    main()
