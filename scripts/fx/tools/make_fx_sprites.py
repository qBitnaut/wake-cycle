#!/usr/bin/env python3
"""Author the small pixel-art sprites the FX kit needs, into assets/fx/.

Run from the project root:  python3 scripts/fx/tools/make_fx_sprites.py

- beacon_base.png / beacon_glass.png: the Kenney industrial beacon (tile 0,4)
  split into its housing and a greyscale glass mask, so the glass can be
  tinted and pushed into HDR while the housing stays lit by the scene.
- pad_base.png / pad_glow.png: enhancement pad plate and its emissive strip.
- window_broken.png: a 3x2-tile warehouse window, two panes smashed.
- goo_circuit.png: horizontally tileable PCB trace mask for the goo pool.
"""
import math
import random
from pathlib import Path

from PIL import Image

OUT = Path("assets/fx")
KENNEY_IND = Path("assets/tiles/kenney-industrial-expansion/tilemap_packed.png")

OUTLINE = (40, 44, 60, 255)
STEEL_D = (67, 74, 95, 255)
STEEL = (110, 117, 140, 255)
STEEL_L = (149, 154, 177, 255)
STEEL_H = (196, 201, 218, 255)


def beacon():
    tile = Image.open(KENNEY_IND).convert("RGBA").crop((0, 72, 18, 90))
    base = Image.new("RGBA", tile.size, (0, 0, 0, 0))
    glass = Image.new("RGBA", tile.size, (0, 0, 0, 0))
    lum = {(176, 50, 32): 150, (212, 87, 52): 200, (244, 130, 67): 255, (220, 225, 231): 255}
    for y in range(18):
        for x in range(18):
            r, g, b, a = tile.getpixel((x, y))
            if a == 0:
                continue
            # Glass: the red dome pixels above the base band (rows 7-14).
            if (r, g, b) in lum and y < 15:
                v = lum[(r, g, b)]
                glass.putpixel((x, y), (v, v, v, 255))
            else:
                base.putpixel((x, y), (r, g, b, a))
    base.save(OUT / "beacon_base.png")
    glass.save(OUT / "beacon_glass.png")


def pad():
    """24x7 floor plate: a recessed emitter lens on top (glow mask), a bright
    steel lip, a body with two side status lights, dark outline."""
    w, h = 24, 7
    base = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    glow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    bp, gp = base.load(), glow.load()
    for x in range(2, 22):                      # bezel top edge
        bp[x, 0] = OUTLINE
    for y in (1, 2):                            # bezel sides around the lens
        bp[2, y] = OUTLINE
        bp[21, y] = OUTLINE
        for x in range(3, 21):
            bp[x, y] = (18, 20, 28, 255)        # lens bed (dark when unlit)
            v = 255 if y == 1 else 140
            if y == 2 and x % 3 == 0:
                v = 200
            gp[x, y] = (v, v, v, 255)
    for x in range(0, 24):                      # lip and body
        bp[x, 3] = OUTLINE if x in (0, 23) else STEEL_H
        bp[x, 4] = OUTLINE if x in (0, 23) else STEEL
        bp[x, 5] = OUTLINE if x in (0, 23) else STEEL_D
        bp[x, 6] = OUTLINE
    for x in range(5, 19, 3):                   # vents
        bp[x, 5] = OUTLINE
    for x in (2, 21):                           # side status lights
        bp[x, 4] = (18, 20, 28, 255)
        gp[x, 4] = (255, 255, 255, 255)
    base.save(OUT / "pad_base.png")
    glow.save(OUT / "pad_glow.png")


def window():
    rnd = random.Random(7)
    w, h = 54, 36
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    px = img.load()
    glass = (150, 176, 222, 70)
    glint = (205, 222, 255, 130)
    panes = [(2, 2, 25, 16), (28, 2, 51, 16), (2, 19, 25, 33), (28, 19, 51, 33)]
    broken = {0: "shattered", 3: "gone"}
    spikes = [rnd.uniform(0.25, 0.85) for _ in range(11)]
    for i, (x0, y0, x1, y1) in enumerate(panes):
        kind = broken.get(i, "intact")
        cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                if kind == "intact":
                    on_glint = (x - x0) - (y - y0) in (3, 4, 11)
                    px[x, y] = glint if on_glint else glass
                elif kind == "shattered":
                    # Star-shaped hole: shards point inward from the frame.
                    dx, dy = (x - cx) / ((x1 - x0) / 2), (y - cy) / ((y1 - y0) / 2)
                    ang = math.atan2(dy, dx) / (2 * math.pi) + 0.5
                    k = ang * len(spikes)
                    i0 = int(k) % len(spikes)
                    f = k - int(k)
                    tri = 1 - abs(f * 2 - 1)
                    reach = 1.08 - tri * spikes[i0]
                    if math.hypot(dx, dy) > reach:
                        px[x, y] = glint if (x + y) % 9 == 0 else glass
                else:
                    # Gone: jagged teeth left along the bottom and left edges.
                    tb = [0, 2, 4, 1, 0, 3, 1, 0, 2, 5, 2, 0][(x - x0) % 12]
                    tl = [0, 3, 1, 0, 2, 0][(y - y0) % 6]
                    if y > y1 - tb or x < x0 + tl:
                        px[x, y] = glass
    # Frame and mullions.
    for y in range(h):
        for x in range(w):
            outer = x < 2 or x >= w - 2 or y < 2 or y >= h - 2
            mull = x in (26, 27) or y in (17, 18)
            if outer or mull:
                face = x in (1, w - 2) or y in (1, h - 2) or (mull and (x == 26 or y == 17))
                px[x, y] = STEEL if face else OUTLINE
    # Sill: a lighter top edge on the bottom frame.
    for x in range(1, w - 1):
        px[x, h - 2] = STEEL_L
    img.save(OUT / "window_broken.png")


def goo_circuit():
    """PCB-style traces: runs on three rows, 45-degree jogs between rows and
    2x2 vias at the ends. White on transparent; wraps horizontally. Nets stop
    a pixel short of each other so the pattern keeps its gaps."""
    w, h = 64, 14
    rows = [3, 7, 11]
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    rnd = random.Random(5)
    used = set()

    def free(x, y):
        return all(((x + dx) % w, y + dy) not in used for dx in (-1, 0, 1) for dy in (-1, 0, 1))

    def put(x, y):
        used.add((x % w, y))
        img.putpixel((x % w, y), (255, 255, 255, 255))

    def via(x, y):
        for dx in (0, 1):
            for dy in (-1, 0):
                img.putpixel(((x + dx) % w, y + dy), (255, 255, 255, 255))
                used.add(((x + dx) % w, y + dy))

    for _ in range(30):
        x = rnd.randrange(w)
        r = rnd.randrange(len(rows))
        if not free(x, rows[r]) or not free(x + 2, rows[r]):
            continue
        start = x
        length = rnd.randrange(6, 18)
        path = []
        y = rows[r]
        ok = True
        while length > 0 and ok:
            run = rnd.randrange(3, 7)
            for _ in range(run):
                if not free(x + 2, y):
                    ok = False
                    break
                x += 1
                path.append((x, y))
            length -= run
            if ok and length > 0 and rnd.random() < 0.6:
                nr = r + rnd.choice([-1, 1])
                if 0 <= nr < len(rows):
                    step = 1 if nr > r else -1
                    while y != rows[nr]:
                        if not free(x + 2, y + step):
                            ok = False
                            break
                        x += 1
                        y += step
                        path.append((x, y))
                    r = nr
        if len(path) < 4:
            continue
        via(start, rows[[3, 7, 11].index(path[0][1])] if path[0][1] in rows else path[0][1])
        for px, py in path:
            put(px, py)
        via(path[-1][0], path[-1][1])
    img.save(OUT / "goo_circuit.png")


def moon():
    """9x9 moon: a 7 px disc with a slightly darker limb and two maria."""
    img = Image.new("RGBA", (9, 9), (0, 0, 0, 0))
    for y in range(9):
        for x in range(9):
            if math.hypot(x - 4, y - 4) <= 3.6:
                limb = math.hypot(x - 5.2, y - 3.4) > 3.4
                v = 205 if limb else 255
                if (x, y) in ((3, 3), (5, 5), (4, 5)):
                    v = 220
                img.putpixel((x, y), (v, v, v, 255))
    img.save(OUT / "moon.png")


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    beacon()
    pad()
    window()
    goo_circuit()
    moon()
    print("sprites written to", OUT)
