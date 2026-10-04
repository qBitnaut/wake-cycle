#!/usr/bin/env python3
"""Gum Bot (GrafxKid, CC0) ships on an opaque pink background. This keys the
background out and writes assets/sprites/robots/gum_bot_keyed.png (RGBA).

Usage: key_gum_bot.py [src] [dst]
"""
import sys
from PIL import Image

src = sys.argv[1] if len(sys.argv) > 1 else "assets/sprites/robots/gum_bot.png"
dst = sys.argv[2] if len(sys.argv) > 2 else "assets/sprites/robots/gum_bot_keyed.png"
im = Image.open(src).convert("RGBA")
bg = im.getpixel((0, 0))
px = im.load()
for y in range(im.height):
    for x in range(im.width):
        if px[x, y][:3] == bg[:3]:
            px[x, y] = (0, 0, 0, 0)
im.save(dst)
