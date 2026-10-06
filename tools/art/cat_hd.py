#!/usr/bin/env python3
"""HD cat frames for 640x360 at the B' scale: luizmelo Cat-6 -> brown tabby
recolour -> 1.5x (Scale3x and a nearest /2) -> 1 px dark outline. 75 px
frames; the cat is about 31x23 game px, two thirds of a 32 px tile tall.

Two steps, so the frames can be rebuilt without the pack:
  1. With the pack: every animation is recoloured at 1x (the repo's own
     gradient map, tools/recolor_cat.py, imported read-only, so the HD cat
     and the game cat stay one coat) and saved as a 1x master in
     tools/art/cat_src/. cat_poses.py adds its derived poses there too.
  2. Every master becomes an HD sheet in assets/sprites/cat/: 1.5x
     (repixel.up15), each eye pixel held to one HD pixel so the eyes keep
     their size on every frame, then the outline, last, at the new size, so
     it is exactly one screen pixel at 640x360: crisp, never a chunky 2 px
     border.

The outline is 4-connected (orthogonal neighbours only). An 8-connected
outline fattens every diagonal step of the silhouette by a pixel; the
4-connected one keeps the ears and tail tip sharp.

Geometry (scripts/player/cat_frames.gd mirrors it): the 1x paws stand on row
31, so at 1.5x they are on row 47 with the ink on row 48. The Sprite sits at
y = -12 under the Cat (frame centred, drawn from -37), which puts the ink
row on the floor line, as the 100 px frames did at y = -15.

Run cat_poses.py, then cat_anchors.py and cat_augments.py afterwards: the
nano maps, veins and augments are read off these sheets.

Usage: cat_hd.py [pack_dir]   (pack_dir: "Pet Cats Pack"; without it the
       sheets are rebuilt from the masters)
"""
import importlib.util
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import palette as P  # noqa: E402
import repixel  # noqa: E402

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
RECOLOR = HERE.parent / "recolor_cat.py"
SRC = HERE / "cat_src"
OUT = ROOT / "assets" / "sprites" / "cat"
F1 = 50          # 1x frame, px
FRAME = 75       # HD frame, px (1.5x)
FEET = 47        # the paws' row in an HD frame (ink on 48)
INK = np.array([*P.hex_to_rgb(P.SINGLES["cat_outline"]), 255], np.uint8)
EYE = (0xE8, 0xD8, 0x2A)
ANIMS = ["Idle", "Walk", "Run", "Sitting", "Sleeping1", "Sleeping2", "Laying",
         "Stretching", "Licking 1", "Licking 2", "Meow", "Itch"]


def load_recolor():
    spec = importlib.util.spec_from_file_location("recolor_cat", RECOLOR)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod.recolor


def one_pixel_eyes(a, o):
    """Each 1x eye pixel becomes exactly one HD pixel, the one holding its
    centre. At 1.5x an even row or column covers two pixels and an odd one
    covers one, so the eyes would swell and shrink as the head bobs; extra
    eye pixels take the fur round that eye instead (its most common
    neighbour at 1x)."""
    eye = np.all(a[..., :3] == EYE, axis=2) & (a[..., 3] > 0)
    h, w = eye.shape
    span = [(3 * i + 1) // 2 for i in range(max(h, w) + 1)]
    for r, c in zip(*np.nonzero(eye)):
        near = [tuple(a[y, x]) for y, x in ((r - 1, c), (r + 1, c), (r, c - 1), (r, c + 1))
                if 0 <= y < h and 0 <= x < w and a[y, x, 3] > 0 and not eye[y, x]]
        fur = max(set(near), key=near.count) if near else tuple(a[r, c])
        for y in range(span[r], span[r + 1]):
            for x in range(span[c], span[c + 1]):
                o[y, x] = fur
        o[(3 * r + 1) // 2, (3 * c + 1) // 2] = a[r, c]
    return o


def hd(frame):
    """One 1x frame (50x50 RGBA array) -> its 75x75 HD frame."""
    a = np.asarray(frame).copy()
    a[a[..., 3] == 0] = 0
    return repixel.outline(one_pixel_eyes(a, repixel.up15(a)), INK)


def masters_from_pack(pack):
    """Recolour every pack animation at 1x into tools/art/cat_src."""
    SRC.mkdir(parents=True, exist_ok=True)
    recolor = load_recolor()
    for anim in ANIMS:
        sheet = recolor(Image.open(pack / "Cat-6" / f"Cat-6-{anim}.png").convert("RGBA"))
        name = anim.lower().replace(" ", "_")
        sheet.save(SRC / f"cat_{name}.png")
        print(f"{anim}: {sheet.width // F1} frames -> cat_src/cat_{name}.png")


def frames_1x(path):
    a = np.asarray(Image.open(path).convert("RGBA")).copy()
    a[a[..., 3] == 0] = 0
    return [a[:, i * F1:(i + 1) * F1] for i in range(a.shape[1] // F1)]


def sheet(frames):
    return np.concatenate([hd(f) for f in frames], axis=1)


def write_sheet(name, strip):
    Image.fromarray(strip).save(OUT / f"cat_{name}.png")
    print(f"{name}: {strip.shape[1] // FRAME} frames -> cat_{name}.png ({strip.shape[1]}x{strip.shape[0]})")


def main():
    if len(sys.argv) > 1:
        masters_from_pack(Path(sys.argv[1]))
    for anim in ANIMS:
        name = anim.lower().replace(" ", "_")
        write_sheet(name, sheet(frames_1x(SRC / f"cat_{name}.png")))


if __name__ == "__main__":
    main()
