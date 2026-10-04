#!/usr/bin/env python3
"""HD cat frames for 640x360: luizmelo Cat-6 -> Scale2x (EPX) -> brown tabby
recolour -> 1 px dark outline.

Order matters:
  1. Scale2x runs on the artist's original colours, so its edge decisions
     see every distinct shade (the tabby map could merge two greys of equal
     luminance and change which corners get rounded).
  2. The recolour is the repo's own gradient map (tools/recolor_cat.py,
     imported read-only), so the HD cat and the game cat stay one coat.
  3. The outline goes on last, at the 2x resolution, so it is exactly one
     screen pixel at 640x360: crisp, never a chunky 2 px border.

The outline is 4-connected (orthogonal neighbours only). An 8-connected
outline fattens every diagonal step of the silhouette by a pixel; the
4-connected one keeps the ears and tail tip sharp.

Usage: cat_hd.py <pack_dir> [out_dir]   (out_dir default: assets/sprites/cat_hd)
"""
import importlib.util
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import palette as P  # noqa: E402

HERE = Path(__file__).resolve().parent
RECOLOR = HERE.parent / "recolor_cat.py"
FRAME = 50
ANIMS = ["Idle", "Walk", "Run", "Sitting", "Sleeping1", "Sleeping2", "Laying",
         "Stretching", "Licking 1", "Licking 2", "Meow", "Itch"]


def load_recolor():
    spec = importlib.util.spec_from_file_location("recolor_cat", RECOLOR)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod.recolor


def scale2x(img):
    a = np.asarray(img.convert("RGBA")).copy()
    a[a[..., 3] == 0] = 0  # one canonical "empty" so EPX treats it as one colour
    h, w, _ = a.shape
    p = np.pad(a, ((1, 1), (1, 1), (0, 0)), mode="edge")
    B, D, E, F, H = p[0:h, 1:w + 1], p[1:h + 1, 0:w], p[1:h + 1, 1:w + 1], p[1:h + 1, 2:w + 2], p[2:h + 2, 1:w + 1]

    def eq(x, y):
        return (x == y).all(axis=2)

    def pick(cond, src):
        return np.where(cond[..., None], src, E)

    e0 = pick(eq(D, B) & ~eq(B, F) & ~eq(D, H), D)
    e1 = pick(eq(B, F) & ~eq(B, D) & ~eq(F, H), F)
    e2 = pick(eq(D, H) & ~eq(D, B) & ~eq(H, F), D)
    e3 = pick(eq(H, F) & ~eq(D, H) & ~eq(B, F), F)
    o = np.zeros((h * 2, w * 2, 4), np.uint8)
    o[0::2, 0::2], o[0::2, 1::2], o[1::2, 0::2], o[1::2, 1::2] = e0, e1, e2, e3
    return Image.fromarray(o)


def outline(img):
    rgb = P.hex_to_rgb(P.SINGLES["cat_outline"])
    a = np.asarray(img.convert("RGBA")).copy()
    solid = a[..., 3] > 0
    n = np.zeros_like(solid)
    n[1:, :] |= solid[:-1, :]
    n[:-1, :] |= solid[1:, :]
    n[:, 1:] |= solid[:, :-1]
    n[:, :-1] |= solid[:, 1:]
    edge = n & ~solid
    a[edge] = (*rgb, 255)
    return Image.fromarray(a)


def hd_frame(frame, recolor):
    return outline(recolor(scale2x(frame)))


def main():
    pack = Path(sys.argv[1])
    out = Path(sys.argv[2]) if len(sys.argv) > 2 else HERE.parent.parent / "assets" / "sprites" / "cat_hd"
    out.mkdir(parents=True, exist_ok=True)
    recolor = load_recolor()
    for anim in ANIMS:
        sheet = Image.open(pack / "Cat-6" / f"Cat-6-{anim}.png").convert("RGBA")
        n = sheet.width // FRAME
        frames = [hd_frame(sheet.crop((i * FRAME, 0, (i + 1) * FRAME, FRAME)), recolor) for i in range(n)]
        strip = Image.new("RGBA", (n * FRAME * 2, FRAME * 2))
        for i, f in enumerate(frames):
            strip.alpha_composite(f, (i * FRAME * 2, 0))
        name = anim.lower().replace(" ", "_")
        strip.save(out / f"cat_{name}.png")
        print(f"{anim}: {n} frames -> cat_{name}.png ({strip.width}x{strip.height})")


if __name__ == "__main__":
    main()
