#!/usr/bin/env python3
"""Cat poses the Cat-6 pack does not have, derived from its walk cycle:

  crawl        a low, belly-to-the-ground stalk: the walk squashed down and
               stretched long, legs bent under a low belly, ears pinned,
               head low and level with the back, tail level
  crouch_idle  the crawl's pose at rest: paws planted, the tail tip
               flicking, a slow blink
  push         leaning into a crate: shoulders and head low, the brow at
               the crate's face, hind legs driving back, short steps

The poses are built at 1x out of the walk's parts (head, torso, legs, tail),
read from its 1x master (tools/art/cat_src/cat_walk.png, see cat_hd.py),
then run through the same 1.5x and outline as every other sheet (cat_hd.hd),
so they share the HD cat's pixel scale, palette (the brown tabby, untouched)
and #161630 ink. Frames are 75x75 with the same baseline (paws on row 47,
ink on 48) and the same anchor (the sprite's origin is the frame centre).

The push frames sit back in the frame so the brow meets the cat's
collision edge (11 px ahead of its origin, where a crate's face is),
instead of the walk's head reaching into the crate: the brow's fur ends
on column 48 of the HD frame, x 11 in front of the origin (facing right),
with its ink one pixel further, as the 100 px frames had it.

Run cat_anchors.py and then cat_augments.py afterwards: they pick up every
cat_*.png, so the nano maps, veins and augments cover these sheets too.

Usage: cat_poses.py [--preview out.png]
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import cat_hd  # noqa: E402

F1 = cat_hd.F1               # source frame, px
FRAME = cat_hd.FRAME         # HD frame, px
FEET = 31                    # the paws' row at 1x (47 at 1.5x)

# The coat as the HD sheets carry it (tools/recolor_cat.py's gradient map).
TAIL = (134, 84, 42, 255)    # mid fur
TAIL_TIP = (179, 121, 63, 255)
SHADE = (62, 36, 20, 255)    # stripes and the darkest fur

# Walk anatomy at 1x (the cat faces +x).
SHOULDER = 31                # the neck: the stretch and the shear pivot here
REAR = 20                    # the rump's column


# ---- the walk at 1x -------------------------------------------------------

def walk_1x():
    """The walk's 1x frames, from its master."""
    return cat_hd.frames_1x(cat_hd.SRC / "cat_walk.png")


def parts(f):
    """Split a walk frame into head, torso, legs and tail masks."""
    solid = f[..., 3] > 0
    ys, xs = np.nonzero(np.all(f[..., :3] == (232, 216, 42), axis=2))
    eye_y = int(ys.min()) if len(ys) else 21
    yy, xx = np.mgrid[0:F1, 0:F1]
    head = solid & (xx >= SHOULDER + 1) & (yy <= eye_y + 3)
    tail = solid & (((yy <= 21) & (xx < SHOULDER)) | ((yy == 22) & (xx < REAR)))
    legs = solid & (yy >= 28) & ~head
    torso = solid & ~head & ~tail & ~legs
    return head, torso, legs, tail


def leg_blobs(mask):
    """Connected leg pieces (8-connected), each a list of (x, y)."""
    seen = np.zeros_like(mask)
    blobs = []
    for y, x in zip(*np.nonzero(mask)):
        if seen[y, x]:
            continue
        seen[y, x] = True
        stack, pts = [(x, y)], []
        while stack:
            cx, cy = stack.pop()
            pts.append((cx, cy))
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    nx, ny = cx + dx, cy + dy
                    if 0 <= nx < F1 and 0 <= ny < F1 and mask[ny, nx] and not seen[ny, nx]:
                        seen[ny, nx] = True
                        stack.append((nx, ny))
        blobs.append(pts)
    return blobs


def put(out, x, y, rgba):
    if 0 <= x < F1 and 0 <= y < F1:
        out[y, x] = rgba


def draw_tail(out, x0, y0, dys, tip=3):
    """A one-pixel tail running back (-x) from (x0, y0): dys[i] is the row
    offset of its i-th pixel; the last `tip` pixels are the light tip."""
    n = len(dys)
    for i, dy in enumerate(dys):
        put(out, x0 - i, y0 + dy, TAIL_TIP if i >= n - tip else TAIL)


def bridge(out):
    """Join every piece that meets the body only at a corner with one pixel:
    Scale2x does not join corner contacts, so at 2x such a paw floats. (The
    tail is drawn afterwards: its corner steps are the art's own stairs.)"""
    while True:
        solid = out[..., 3] > 0
        label = np.zeros(solid.shape, int)
        n = 0
        for y, x in zip(*np.nonzero(solid)):
            if label[y, x]:
                continue
            n += 1
            label[y, x] = n
            stack = [(x, y)]
            while stack:
                cx, cy = stack.pop()
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = cx + dx, cy + dy
                    if 0 <= nx < F1 and 0 <= ny < F1 and solid[ny, nx] and not label[ny, nx]:
                        label[ny, nx] = n
                        stack.append((nx, ny))
        if n <= 1:
            return
        main = np.bincount(label[solid]).argmax()
        joined = False
        for y, x in zip(*np.nonzero(solid & (label != main))):
            for dx, dy in ((1, -1), (-1, -1), (1, 1), (-1, 1)):
                qx, qy = x + dx, y + dy
                if 0 <= qx < F1 and 0 <= qy < F1 and label[qy, qx] == main:
                    out[qy, x] = out[y, x]  # beside the body, over the piece
                    joined = True
                    break
            if joined:
                break
        if not joined:
            return  # truly loose: check_whole reports it


def shift(out, dx, dy):
    """Move the whole frame by whole pixels (empty fill)."""
    res = np.zeros_like(out)
    h, w, _ = out.shape
    res[max(dy, 0):h + min(dy, 0), max(dx, 0):w + min(dx, 0)] = \
        out[max(-dy, 0):h + min(-dy, 0), max(-dx, 0):w + min(-dx, 0)]
    return res


# ---- crawl -------------------------------------------------------------------

STRETCH = 1.3
# Torso rows: walk row -> crawl row. The back drops 2 px and one of the six
# body rows goes (the squash); the legs keep their lowest three rows, so
# they read as bent limbs stepping under a low belly.
TORSO_ROWS = {22: 24, 23: 25, 24: 26, 26: 27, 27: 28}
LEG_ROWS = (29, 30, 31)
HEAD_DROP = 5
# The tail's row per pixel below where it leaves the rump: level, a slight
# droop, and on the flick frames the tip lifting.
TAIL_LOW = [0, 0, 0, 1, 1, 1, 1, 1, 1, 1]
TAIL_FLICK = [0, 0, 0, 1, 1, 1, 1, 1, 0, -1]


def stretch_x(x):
    """Crawl column of walk column x (behind the shoulder only)."""
    if x >= SHOULDER:
        return x
    return int(round(SHOULDER - (SHOULDER - x) * STRETCH))


def attached(out, blob, dx, belly):
    """True if the leg piece moved by dx touches the body's lowest row."""
    for x, y in blob:
        if y != LEG_ROWS[0]:
            continue
        for ax in range(x + dx - 1, x + dx + 2):
            if 0 <= ax < F1 and out[belly, ax, 3]:
                return True
    return False


def crawl_frame(f, flick=False, blink=False):
    head, torso, legs, _tail = parts(f)
    out = np.zeros_like(f)
    # Torso, stretched back from the shoulder (inverse map: no holes).
    for y_src, y_dst in TORSO_ROWS.items():
        for x_dst in range(stretch_x(REAR), SHOULDER + 6):
            x_src = x_dst if x_dst >= SHOULDER else int(round(SHOULDER - (SHOULDER - x_dst) / STRETCH))
            if torso[y_src, x_src]:
                out[y_dst, x_dst] = f[y_src, x_src]
    # Legs: the lowest rows of each leg, carried back with the stretch but
    # never off the body (a trailing paw stays on its leg).
    belly = max(TORSO_ROWS.values())
    low = np.zeros_like(legs)
    for y in LEG_ROWS:
        low[y] = legs[y]
    for blob in leg_blobs(low):
        cx = int(round(sum(p[0] for p in blob) / len(blob)))
        want = stretch_x(cx) - cx
        step = 1 if want < 0 else -1
        dx = next((d for d in range(want, 0, step) if attached(out, blob, d, belly)), 0)
        for x, y in blob:
            put(out, x + dx, y, f[y, x])
    # Head: ears pinned back (the ear tip row goes), low and level with the
    # back, the chin just off the floor.
    top = int(np.nonzero(head.any(axis=1))[0].min())
    for y, x in zip(*np.nonzero(head)):
        if y != top:
            put(out, x, y + HEAD_DROP, f[y, x])
    if blink:
        eye = np.all(out[..., :3] == (232, 216, 42), axis=2) & (out[..., 3] > 0)
        out[eye] = SHADE
    bridge(out)
    # Tail: level and low behind the rump.
    rump = [x for x in range(F1) if out[25, x, 3]]
    if rump:
        draw_tail(out, min(rump) - 1, 25, TAIL_FLICK if flick else TAIL_LOW)
    return out


# ---- crouch_idle ------------------------------------------------------------

# A planted walk frame held still: [tail flick, blink] per frame. The tip
# flicks twice, then a slow blink.
CROUCH_IDLE = [(False, False), (False, False), (True, False), (False, False),
               (True, False), (False, False), (False, False), (False, True)]


# ---- push --------------------------------------------------------------------

PUSH_FRONT = 30              # the brow's column at 1x (the HD frame is then set by PUSH_FRONT_HD)
PUSH_FRONT_HD = 48           # the brow's last fur column in the 75 px frame: x 11, the crate face
LEAN = 3                     # how much lower the shoulders sit than the rump, px
PUSH_TAIL = [0, 0, 0, 0, -1, -1, -1, -2, -2]
PUSH_FLICK = [0, 0, 0, 0, -1, -1, -2, -2, -3]


def push_frame(f, flick=False):
    head, torso, legs, _tail = parts(f)
    out = np.zeros_like(f)

    def lean(x):
        # The back slopes down from the rump to the shoulders.
        return int(round(LEAN * min(max((x - REAR - 1) / (SHOULDER - REAR - 1), 0.0), 1.0)))

    # Hind legs drive back; front legs fold under the lowered chest.
    for y, x in zip(*np.nonzero(legs)):
        if x <= SHOULDER - 6:
            put(out, x - int(round((y - 27) * 0.4)), y, f[y, x])
        else:
            put(out, x, y, f[y, x])
    for y, x in zip(*np.nonzero(torso)):
        put(out, x, y + lean(x), f[y, x])
    # Head: down past the shoulders, ears pinned (the ear tip row goes).
    top = int(np.nonzero(head.any(axis=1))[0].min())
    for y, x in zip(*np.nonzero(head)):
        if y != top:
            put(out, x, y + LEAN + 1, f[y, x])
    bridge(out)
    # Tail straight out behind, lifting a little toward the tip.
    solid = out[..., 3] > 0
    rx = int(np.nonzero(solid.any(axis=0))[0].min())
    for x in range(rx, F1):
        col = np.nonzero(solid[:26, x])[0]
        if len(col):
            draw_tail(out, x - 1, int(col.min()) + 1, PUSH_FLICK if flick else PUSH_TAIL)
            break
    # Sit back in the frame so the brow is at the crate's face.
    xs = np.nonzero(out[..., 3].any(axis=0))[0]
    return shift(out, PUSH_FRONT - int(xs.max()), 0)


# ---- sheets --------------------------------------------------------------------

def push_sheet(frames):
    """HD push frames, each moved so the brow's fur ends on PUSH_FRONT_HD."""
    out = []
    for f in frames:
        h = cat_hd.hd(f)
        fur = (h[..., 3] > 0) & ~np.all(h == cat_hd.INK, axis=2)
        front = int(np.nonzero(fur.any(axis=0))[0].max())
        out.append(shift(h, PUSH_FRONT_HD - front, 0))
    return np.concatenate(out, axis=1)


def build():
    walk = walk_1x()
    n = len(walk)
    crawl = [crawl_frame(w, flick=i in (3, 4)) for i, w in enumerate(walk)]
    rest = walk[7]  # all four paws gathered under the body
    crouch = [crawl_frame(rest, flick=fl, blink=bl) for fl, bl in CROUCH_IDLE]
    push = [push_frame(w, flick=i in (2, 3, 6, 7)) for i, w in enumerate(walk)]
    print(f"walk: {n} frames at 1x")
    for name, frames in (("crawl", crawl), ("crouch_idle", crouch), ("push", push)):
        check_whole(frames, name)
    return {"crawl": cat_hd.sheet(crawl), "crouch_idle": cat_hd.sheet(crouch), "push": push_sheet(push)}


def check_whole(frames, name):
    """Every frame is one piece: nothing floats free of the body (corner
    contacts count, the ink outline joins them, as on the walk's tail)."""
    for i, f in enumerate(frames):
        solid = f[..., 3] > 0
        seen = np.zeros_like(solid)
        y0, x0 = map(int, np.argwhere(solid)[0])
        stack = [(x0, y0)]
        seen[y0, x0] = True
        while stack:
            x, y = stack.pop()
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < F1 and 0 <= ny < F1 and solid[ny, nx] and not seen[ny, nx]:
                    seen[ny, nx] = True
                    stack.append((nx, ny))
        loose = int((solid & ~seen).sum())
        assert loose == 0, f"{name} frame {i}: {loose} px not joined to the body"


def check_baseline(strip):
    """Every frame stands on row 47 with its ink on row 48."""
    for i in range(strip.shape[1] // FRAME):
        a = strip[:, i * FRAME:(i + 1) * FRAME, 3] > 0
        rows = np.nonzero(a.any(axis=1))[0]
        assert rows.max() == cat_hd.FEET + 1, (i, rows.max())


def write_preview(sheets, path, z=4, cell=(60, 33)):
    rows = list(sheets.items())
    cols = max(s.shape[1] // FRAME for _, s in rows)
    w, h = cell
    img = Image.new("RGBA", (cols * w, len(rows) * h), (64, 72, 96, 255))
    for r, (_name, s) in enumerate(rows):
        for c in range(s.shape[1] // FRAME):
            fr = Image.fromarray(s[:, c * FRAME:(c + 1) * FRAME])
            img.alpha_composite(fr.crop((8, 18, 8 + w, 18 + h)), (c * w, r * h))
    img.resize((img.width * z, img.height * z), Image.NEAREST).save(path)


def main():
    sheets = build()
    for name, s in sheets.items():
        check_baseline(s)
        cat_hd.write_sheet(name, s)
    if "--preview" in sys.argv:
        write_preview(sheets, sys.argv[sys.argv.index("--preview") + 1])


if __name__ == "__main__":
    main()
