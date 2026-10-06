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
      B  reveal time (0 = first, 255 = last) on one schedule shared by every
         frame: the ear implant, then the spine plates one by one from the
         neck back, then the tail band, then the eye ring. Each piece grows
         out of its emitter inside its own window (WINDOWS below)
      A  255 on every augment pixel

Also writes augments/pieces.json: per sheet and frame, each piece drawn
with its kind, reveal start and centre (frame px), so the HD layer can flash
as each one lands.

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

PLATE = 3   # plate length, px
SEAM = 1

# Reveal windows on the shared 0..1 schedule; plates count from the neck.
WINDOWS = {
    "ear": (0.0, 0.12),
    "plate0": (0.17, 0.28),
    "plate1": (0.32, 0.43),
    "plate2": (0.47, 0.58),
    "tail": (0.64, 0.76),
    "eye": (0.84, 0.96),
}


class Canvas:
    def __init__(self, frame_rgba):
        self.a, self.ink, self.eye, self.inner = A.masks(frame_rgba)
        self.metal = np.zeros((FRAME, FRAME, 4), np.uint8)
        self.data = np.zeros((FRAME, FRAME, 4), np.uint8)
        self.win = (0.0, 1.0)
        self.pieces = []
        self._pts = []

    def piece(self, kind):
        """Start drawing piece `kind`: later puts use its reveal window."""
        self._close()
        self.win = WINDOWS[kind]
        self.pieces.append({"k": kind, "s": self.win[0]})
        self._pts = []

    def _close(self):
        if self.pieces and self._pts:
            xs, ys = zip(*self._pts)
            self.pieces[-1]["x"] = round(sum(xs) / len(xs) + 0.5, 1)
            self.pieces[-1]["y"] = round(sum(ys) / len(ys) + 0.5, 1)
        elif self.pieces and "x" not in self.pieces[-1]:
            self.pieces.pop()

    def done(self):
        self._close()
        return self.pieces

    def _when(self, order):
        s, e = self.win
        return int(np.clip((s + order * (e - s)) * 255, 0, 255))

    def put(self, x, y, rgb, order, emit=0, phase=0.0):
        if not (0 <= x < FRAME and 0 <= y < FRAME):
            return
        self.metal[y, x] = (*rgb, 255)
        self.data[y, x] = (emit, round(phase * 255) % 256, self._when(order), 255)
        self._pts.append((x, y))

    def glow_only(self, x, y, emit, phase, order=0.0):
        self.data[y, x] = (emit, round(phase * 255) % 256, self._when(order), 255)
        self._pts.append((x, y))


def ear_piece(cv, info):
    if not info["ear"]:
        return
    ex, ey = info["ear"]
    front = info["view"] == "front"
    pts = [(ex, ey)]
    for dy in (1, 2, 3):
        row = [x for x in range(ex - 2, ex + 3) if cv.inner[ey + dy, x]]
        if not row:
            break
        pts.append((max(row) if front else min(row), ey + dy))
    if len(pts) < 3:
        return
    cv.piece("ear")
    n = len(pts) - 1
    cv.put(*pts[0], LENS, 0.0, 255, 0.0)
    for i, (x, y) in enumerate(pts[1:]):
        cv.put(x, y, LIGHT if i == 0 else FACE, (i + 1) / n, 0, 0.0)


def eye_ring(cv, info):
    if info["view"] != "side" or not info["eye_px"]:
        return
    eye = {tuple(p) for p in info["eye_px"]}
    ring = []
    for x, y in eye:
        for dx, dy in A.N8:
            q = (x + dx, y + dy)
            if q not in eye and q not in ring and cv.inner[q[1], q[0]] and cv.metal[q[1], q[0], 3] == 0:
                ring.append(q)
    if not ring:
        return
    cv.piece("eye")
    # The ring closes round the eye: order by angle from the back of it.
    ex = sum(p[0] for p in eye) / len(eye)
    ey = sum(p[1] for p in eye) / len(eye)
    for q in ring:
        ang = (np.arctan2(q[1] - ey, -(q[0] - ex)) / (2 * np.pi)) % 1.0
        cv.glow_only(q[0], q[1], 70, 0.0, ang)


def spine_plates(cv, info, prev_start):
    back = {x: y for x, y in info["back"]}
    if len(back) < 9:
        return None
    xs = sorted(back)
    span = xs[-1] - xs[0]
    n = 3 if span >= 16 else 2
    total = n * PLATE + (n - 1) * SEAM
    start = round(xs[0] + 0.55 * span - total / 2)
    if prev_start is not None and abs(start - prev_start) <= 1:
        start = prev_start  # hold still while the cat breathes
    cols = list(range(start, start + total))
    if any(x not in back for x in cols):
        return None
    seam_cols = {start + (i + 1) * PLATE + i * SEAM for i in range(n - 1)}
    # Plates count from the neck (the cat faces +x). Each plate owns the seam
    # on its neck side, which lights first as the plate prints toward the tail.
    for j in range(n):
        k = n - 1 - j                       # 0 = nearest the neck
        x0 = start + j * (PLATE + SEAM)
        x1 = x0 + PLATE - 1
        cols = list(range(x0, x1 + 1))
        if j < n - 1:
            cols.append(x1 + 1)             # the seam toward the neck
        cv.piece(f"plate{k}")
        for x in cols:
            y0 = back[x]
            order = (x1 + 1 - x) / (PLATE + 1)
            if not cv.a[y0 - 1, x]:
                cv.put(x, y0 - 1, INK, order)
            if x in seam_cols:
                cv.put(x, y0, LENS, 0.0, 200, 0.18 + 0.12 * k)
                cv.put(x, y0 + 1, LENS, 0.0, 200, 0.18 + 0.12 * k)
                continue
            edge = x == x0 or x == x1
            cv.put(x, y0, FACE if edge else LIGHT, order)
            cv.put(x, y0 + 1, SHADOW if edge else FACE, order)
            if k == n // 2 and x == x0 + 1:
                cv.put(x, y0, HIGH, order)  # one specular glint, middle plate
    return start


def tail_band(cv, info):
    line = [tuple(p) for p in info["tail_line"]]
    if len(line) < 6:
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
    cv.piece("tail")
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
    pieces = []
    for i in range(n):
        cv = Canvas(img[:, i * FRAME:(i + 1) * FRAME])
        info = infos[i]
        ear_piece(cv, info)
        prev_start = spine_plates(cv, info, prev_start)
        tail_band(cv, info)
        eye_ring(cv, info)
        pieces.append(cv.done())
        out[:FRAME, i * FRAME:(i + 1) * FRAME] = cv.metal
        out[FRAME:, i * FRAME:(i + 1) * FRAME] = cv.data
    return out, pieces


def run(preview=None):
    data = json.loads(A.ANCHORS.read_text())
    previews = []
    all_pieces = {"frame": FRAME, "sheets": {}}
    for name, img in A.sheets():
        infos = data["sheets"].get(name)
        if not infos:
            continue
        sheet, pieces = draw_sheet(img, infos)
        all_pieces["sheets"][name] = pieces
        Image.fromarray(sheet).save(OUT / f"aug_{name}.png")
        previews.append((name, img, sheet))
        print(f"{name}: aug_{name}.png ({sheet.shape[1]}x{sheet.shape[0]})")
    (OUT / "pieces.json").write_text(json.dumps(all_pieces, separators=(",", ":")) + "\n")
    if preview:
        write_preview(previews, preview)


def write_preview(rows, out_path, z=4, cell=48):
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
            sheet.alpha_composite(fr.crop((13, 16, 13 + cell, 16 + cell)), (c * cell, r * cell))
    sheet.resize((sheet.width * z, sheet.height * z), Image.NEAREST).save(out_path)


if __name__ == "__main__":
    pv = None
    if "--preview" in sys.argv:
        pv = sys.argv[sys.argv.index("--preview") + 1]
    run(pv)
