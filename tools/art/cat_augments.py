#!/usr/bin/env python3
"""Draw the cat's nanotech augments as overlay sheets, one per cat sheet.

Reads assets/sprites/cat/augments/anchors.json (cat_anchors.py) and draws
small, sleek pieces into each frame, clipped to that frame's silhouette, so
they stay attached on every frame of every animation:

  ear     a one-pixel metal edge up the back of the ear, emitter at the tip
  spine   2-3 slim plates on the back contour with glowing seams; they sit
          one pixel proud of the fur and carry their own ink edge
  tail    a band around the tail, 40 % of the way from the base, with an
          emitter in the middle
  eye     a faint emissive ring round one eye (glow only, no metal)

A piece is drawn only where its anchor was found, so front views (sitting,
licking) show the ear piece and the band but no plates, as the back is
turned away from us.

Palette-locked (tools/art/palette.py): gunmetal is the bulkhead ramp's
shadow and light stops with steel light and high on top; the outline is the
cat's own ink; emitter sockets are teal ink.

Each output sheet is twice the cat sheet's height:
  top half     metal art (RGBA), drawn lit
  bottom half  emitter and reveal data, read by the shaders at UV + (0, 0.5):
      R  emitter strength (255 emitter, 200 seam, 70 eye ring, 0 metal)
      G  pulse phase (0..255 = 0..1 of a cycle)
      B  reveal order (0 = first, 255 = last): pieces grow out of their emitter
      A  255 on every augment pixel

Usage: cat_augments.py [--preview out.png]
"""
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import cat_anchors as A  # noqa: E402
import palette as P  # noqa: E402

OUT = A.CAT_DIR / "augments"
FRAME = A.FRAME

INK = P.hex_to_rgb(P.SINGLES["cat_outline"])
SHADOW = P.hex_to_rgb(P.RAMPS["bulkhead"]["shadow"])
FACE = P.hex_to_rgb(P.RAMPS["bulkhead"]["light"])
LIGHT = P.hex_to_rgb(P.RAMPS["steel"]["light"])
HIGH = P.hex_to_rgb(P.RAMPS["steel"]["high"])
LENS = P.hex_to_rgb(P.RAMPS["teal"]["ink"])

PLATE = 4   # plate length, px
SEAM = 1


class Canvas:
    def __init__(self, frame_rgba):
        self.a, self.ink, self.eye, self.inner = A.masks(frame_rgba)
        self.metal = np.zeros((FRAME, FRAME, 4), np.uint8)
        self.data = np.zeros((FRAME, FRAME, 4), np.uint8)

    def put(self, x, y, rgb, order, emit=0, phase=0.0):
        if not (0 <= x < FRAME and 0 <= y < FRAME):
            return
        self.metal[y, x] = (*rgb, 255)
        self.data[y, x] = (emit, round(phase * 255) % 256, int(np.clip(order * 255, 0, 255)), 255)

    def glow_only(self, x, y, emit, phase):
        self.data[y, x] = (emit, round(phase * 255) % 256, 255, 255)


def ear_piece(cv, info):
    if not info["ear"]:
        return
    ex, ey = info["ear"]
    front = info["view"] == "front"
    pts = [(ex, ey)]
    for dy in (1, 2, 3):
        row = [x for x in range(ex - 3, ex + 4) if cv.inner[ey + dy, x]]
        if not row:
            break
        pts.append((max(row) if front else min(row), ey + dy))
    if len(pts) < 3:
        return
    n = len(pts) - 1
    cv.put(*pts[0], LENS, 0.0, 255, 0.0)
    for i, (x, y) in enumerate(pts[1:]):
        cv.put(x, y, LIGHT if i == 0 else FACE, (i + 1) / n, 0, 0.0)


def eye_ring(cv, info):
    if info["view"] != "side" or not info["eye_px"]:
        return
    eye = {tuple(p) for p in info["eye_px"]}
    for x, y in eye:
        for dx, dy in A.N8:
            q = (x + dx, y + dy)
            if q not in eye and cv.inner[q[1], q[0]] and cv.metal[q[1], q[0], 3] == 0:
                cv.glow_only(q[0], q[1], 70, 0.0)


def spine_plates(cv, info, prev_start):
    back = {x: y for x, y in info["back"]}
    if len(back) < 12:
        return None
    xs = sorted(back)
    span = xs[-1] - xs[0]
    n = 3 if span >= 22 else 2
    total = n * PLATE + (n - 1) * SEAM
    start = round(xs[0] + 0.55 * span - total / 2)
    if prev_start is not None and abs(start - prev_start) <= 1:
        start = prev_start  # hold still while the cat breathes
    cols = list(range(start, start + total))
    if any(x not in back for x in cols):
        return None
    seam_cols = {start + (i + 1) * PLATE + i * SEAM for i in range(n - 1)}
    for x in cols:
        y0 = back[x]
        k = x - start
        order = abs(k - total / 2) / (total / 2)
        if not cv.a[y0 - 1, x]:
            cv.put(x, y0 - 1, INK, order)
        if x in seam_cols:
            seam = sorted(seam_cols).index(x)
            cv.put(x, y0, LENS, order, 200, 0.18 + 0.12 * seam)
            cv.put(x, y0 + 1, LENS, order, 200, 0.18 + 0.12 * seam)
            continue
        edge = x == start or x == start + total - 1 or (x - 1) in seam_cols or (x + 1) in seam_cols
        cv.put(x, y0, FACE if edge else LIGHT, order)
        cv.put(x, y0 + 1, SHADOW if edge else FACE, order)
    # One specular glint on the middle plate's leading edge.
    mid = start + (n // 2) * (PLATE + SEAM) + 1
    if mid in back:
        cv.put(mid, back[mid], HIGH, 0.0)
    return start


def tail_band(cv, info):
    line = [tuple(p) for p in info["tail_line"]]
    if len(line) < 8:
        return
    k = max(3, min(round(len(line) * 0.4), len(line) - 3))
    core = line[k - 1:k + 2]
    band = set()
    for cx, cy in core:
        for dx, dy in [(0, 0)] + A.N8:
            x, y = cx + dx, cy + dy
            if cv.inner[y, x]:
                band.add((x, y))
    ex, ey = line[k]
    if (ex, ey) not in band:
        return
    top = min(y for _, y in band)
    for x, y in band:
        if (x, y) == (ex, ey):
            continue
        d = max(abs(x - ex), abs(y - ey))
        cv.put(x, y, LIGHT if y == top else FACE, d / 2, 0, 0.55)
    cv.put(ex, ey, LENS, 0.0, 255, 0.55)


def draw_sheet(img, infos):
    n = img.shape[1] // FRAME
    out = np.zeros((FRAME * 2, n * FRAME, 4), np.uint8)
    prev_start = None
    for i in range(n):
        cv = Canvas(img[:, i * FRAME:(i + 1) * FRAME])
        info = infos[i]
        ear_piece(cv, info)
        prev_start = spine_plates(cv, info, prev_start)
        tail_band(cv, info)
        eye_ring(cv, info)
        out[:FRAME, i * FRAME:(i + 1) * FRAME] = cv.metal
        out[FRAME:, i * FRAME:(i + 1) * FRAME] = cv.data
    return out


def run(preview=None):
    data = json.loads(A.ANCHORS.read_text())
    previews = []
    for name, img in A.sheets():
        infos = data["sheets"].get(name)
        if not infos:
            continue
        sheet = draw_sheet(img, infos)
        Image.fromarray(sheet).save(OUT / f"aug_{name}.png")
        previews.append((name, img, sheet))
        print(f"{name}: aug_{name}.png ({sheet.shape[1]}x{sheet.shape[0]})")
    if preview:
        write_preview(previews, preview)


def write_preview(rows, out_path, z=4, cell=64):
    """Cat + metal, emitters painted SURGE blue, at z x zoom."""
    cols = max(r[1].shape[1] // FRAME for r in rows)
    sheet = Image.new("RGBA", (cols * cell, len(rows) * cell), (40, 44, 60, 255))
    for r, (name, img, aug) in enumerate(rows):
        for c in range(img.shape[1] // FRAME):
            fr = Image.fromarray(img[:, c * FRAME:(c + 1) * FRAME].copy())
            metal = aug[:FRAME, c * FRAME:(c + 1) * FRAME]
            dat = aug[FRAME:, c * FRAME:(c + 1) * FRAME]
            em = dat[..., 0] > 0
            glow = np.zeros_like(metal)
            glow[em, :3] = (np.outer(dat[em, 0] / 255.0, [70, 150, 255])).astype(np.uint8)
            glow[em, 3] = 255
            fr.alpha_composite(Image.fromarray(metal))
            fr.alpha_composite(Image.fromarray(glow))
            sheet.alpha_composite(fr.crop((18, 22, 18 + cell, 22 + cell)), (c * cell, r * cell))
    sheet.resize((sheet.width * z, sheet.height * z), Image.NEAREST).save(out_path)


if __name__ == "__main__":
    pv = None
    if "--preview" in sys.argv:
        pv = sys.argv[sys.argv.index("--preview") + 1]
    run(pv)
