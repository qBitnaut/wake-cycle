#!/usr/bin/env python3
"""Recolour the Cat-6 (grey tabby) sheets of luizmelo's "Pet Cats Pack" (CC0)
into a brown tabby using a luminance gradient map.

Eye (yellow) and nose (brown) pixels are left untouched. Stripes survive
because the map is monotonic: the darker grey stripes land on darker browns.

Usage: recolor_cat.py <path to "Pet Cats Pack"> [out_dir]
"""
import re
import sys
from pathlib import Path

from PIL import Image

# (luminance, (r, g, b)) stops, dark to light.
GRADIENT = [
    (0, (34, 20, 12)),
    (79, (62, 36, 20)),      # stripes
    (100, (92, 55, 28)),
    (132, (134, 84, 42)),    # body
    (160, (166, 108, 54)),
    (168, (178, 120, 62)),
    (192, (206, 148, 84)),   # belly / cheeks
    (214, (232, 188, 128)),
    (255, (250, 226, 180)),
]
KEEP = {(232, 216, 42), (101, 57, 27)}  # eyes, nose
ANIMS = ["Idle", "Walk", "Run", "Sitting", "Sleeping1", "Sleeping2", "Laying",
         "Stretching", "Licking 1", "Licking 2", "Meow", "Itch"]


def ramp(lum):
    for (l0, c0), (l1, c1) in zip(GRADIENT, GRADIENT[1:]):
        if lum <= l1:
            t = (lum - l0) / (l1 - l0)
            return tuple(round(a + (b - a) * t) for a, b in zip(c0, c1))
    return GRADIENT[-1][1]


def recolor(img):
    img = img.convert("RGBA")
    px = img.load()
    for y in range(img.height):
        for x in range(img.width):
            r, g, b, a = px[x, y]
            if a == 0 or (r, g, b) in KEEP:
                continue
            px[x, y] = (*ramp(round(0.299 * r + 0.587 * g + 0.114 * b)), a)
    return img


def main():
    pack = Path(sys.argv[1])
    out = Path(sys.argv[2] if len(sys.argv) > 2 else "assets/sprites/cat")
    out.mkdir(parents=True, exist_ok=True)
    for anim in ANIMS:
        name = re.sub(r"[ ]+", "_", anim).lower()
        recolor(Image.open(pack / "Cat-6" / f"Cat-6-{anim}.png")).save(out / f"cat_{name}.png")
    vfx = pack / "Meow-VFX" / "Meow-VFX.png"
    Image.open(vfx).convert("RGBA").save(out / "meow_vfx.png")


if __name__ == "__main__":
    main()
