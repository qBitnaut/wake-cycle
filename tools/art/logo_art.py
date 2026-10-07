#!/usr/bin/env python3
"""The Wake Cycle logo: the end title's monogram wordmark, made into a mark.

  * "Wake Cycle" in monogram (the game's font, the end title card's words),
    Scale2x'd so the diagonals round off, at the in-game 2x: 14 px capitals,
    one pixel grid with the B' cat.
  * Warm letters (cream down to the cat's light fur, lit on their top
    edges, shaded on their bottom edges) on a 2 px dusk violet-navy
    extrusion, a 1 px ink outline: warm things in a cool night.
  * The cat itself, asleep (the ending's loaf, the HD sleeping1 frame), in
    the nook "Cycle" makes between its capital C and its l, lying on the y
    and the c like on its cushion: the cat's half of the theme.
  * The robot's half: the y the cat lies on is a nanotech vein, pale blue
    under the cat to mint at the end of its hook (the game's veins run blue
    to green; lifted to the letters' value so the word still reads), its
    tip a lit node, with a soft stepped halo kept out of its counter; the
    cat's ear implant glows.

Palette-locked: every colour is named below (the game's INK, the coat, the
FX palette's nanotech blue and green). Everything is drawn on whole pixels.

Outputs (assets/art_hd/logo/):
  logo.png            the mark at its native pixel scale, transparent
  logo_x2/3/4/6.png   clean integer upscales (nearest)
  splash.png          the boot splash: the mark at 4x (the end title card's
                      size in a 1280x720 window), transparent; Godot draws it
                      unscaled (stretch mode Disabled, no filter) on
                      NIGHT_BG, and the web shell shows the same image 1:1
  icon.png            the window and page icon: the sleeping cat on a lit
                      vein bar on night navy, 32x32 (icon_x4.png, 128x128,
                      is the project icon: window, taskbar, web favicon)

Usage: logo_art.py [out_dir]
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, str(Path(__file__).resolve().parent))
import repixel  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
FONT = ROOT / "assets" / "fonts" / "monogram.ttf"
CAT = ROOT / "assets" / "sprites" / "cat" / "cat_sleeping1.png"
OUT = ROOT / "assets" / "art_hd" / "logo"
WORD = "Wake Cycle"


def hexc(h, a=255):
    h = h.lstrip("#")
    return np.array([int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a], np.uint8)


INK = hexc("#161630")          # the global outline ink (palette.INK)
NIGHT_BG = "#0d0e1e"           # the splash and the web shell: INK, a step towards black
LETTER = [hexc("#fff5db"), hexc("#f8e3b8"), hexc("#ebc690")]   # top to bottom (WARM_WHITE down to the coat's light fur)
EXTRUDE = [hexc("#3c3870"), hexc("#2a2752")]                    # dusk violet-navy: warm letters in a cool night
VEIN = [hexc("#9cc8ff"), hexc("#7fd9ff"), hexc("#6ee8f0"), hexc("#72f5cf"), hexc("#7dffae")]  # NANO_BLUE .. NANO_GREEN, lifted to the letters' value
NODE = hexc("#e8fff2")         # the vein tip, lit
HALO = (0x21, 0xa6, 0xd1)      # the augments' idle blue-green
EMITTER = hexc("#5fe3ff")      # the ear implant, glowing


def glyphs():
    """The wordmark at 1x as a mask, from monogram at its 16 px design size."""
    f = ImageFont.truetype(str(FONT), 16)
    im = Image.new("L", (80, 20), 0)
    d = ImageDraw.Draw(im)
    d.fontmode = "1"
    d.text((2, 0), WORD, font=f, fill=255)
    a = np.array(im) > 127
    ys, xs = np.nonzero(a)
    return a[ys.min():ys.max() + 1, xs.min():xs.max() + 1]


def epx_mask(m):
    rgba = np.zeros((*m.shape, 4), np.uint8)
    rgba[m] = (255, 255, 255, 255)
    return repixel.scale2x(rgba)[..., 3] > 0


def column_spans(m):
    """[x0, x1] of each letter (runs of non-empty columns) in a mask."""
    cols = m.any(axis=0)
    spans, x = [], 0
    while x < len(cols):
        if cols[x]:
            x0 = x
            while x < len(cols) and cols[x]:
                x += 1
            spans.append((x0, x - 1))
        else:
            x += 1
    return spans


def sleeping_cat():
    """The ending's sleeping loaf, cropped to its pixels (HD, outlined)."""
    a = np.asarray(Image.open(CAT).convert("RGBA")).copy()
    ys, xs = np.nonzero(a[..., 3])
    return a[ys.min():ys.max() + 1, xs.min():xs.max() + 1]


def paste(dst, src, x, y):
    h, w = src.shape[:2]
    m = src[..., 3] > 0
    dst[y:y + h, x:x + w][m] = src[m]


def letter_mask(g1, span):
    """The 2x mask of one letter of the 1x wordmark."""
    m = np.zeros_like(g1)
    m[:, span[0]:span[1] + 1] = g1[:, span[0]:span[1] + 1]
    return epx_mask(m)


def build(extrude=EXTRUDE):
    g1 = glyphs()                      # 1x: cap 7, x-height 5, descender 2
    g = epx_mask(g1)                   # 2x
    gh, gw = g.shape
    xh = 4                             # 2x row of the x-height top
    spans = column_spans(g1)
    letters = dict(zip(["W", "a", "k", "e", "C", "y", "c", "l", "e2"], spans))
    ym = letter_mask(g1, letters["y"])
    cat = sleeping_cat()
    ch, cw = cat.shape[:2]
    pad_top = ch - xh + 1              # room above the capitals for the cat
    PAD = 3                            # outline + halo margin
    H = pad_top + gh + 2 + PAD * 2     # + the extrusion
    W = gw + PAD * 2
    oy, ox = PAD + pad_top, PAD
    out = np.zeros((H, W, 4), np.uint8)
    ys, xs = np.nonzero(g)
    # The extrusion: the letters pushed down 2 px.
    for k, col in ((2, extrude[1]), (1, extrude[0])):
        out[ys + oy + k, xs + ox] = col
    # The letters: cream, lit along their top edges, shaded along their
    # bottom edges (no bands across the strokes).
    for y, x in zip(ys, xs):
        top = y == 0 or not g[y - 1, x]
        bottom = y == gh - 1 or not g[y + 1, x]
        out[y + oy, x + ox] = LETTER[0] if top else LETTER[2] if bottom else LETTER[1]
    # The y is the vein: lit blue at the top, where the cat lies on it,
    # to green at the end of its hook, the tip a bright node.
    yy, yx = np.nonzero(ym)
    order = np.argsort(yy * 1000 + (1000 - yx), kind="stable")
    n = len(order)
    for i, k in enumerate(order):
        out[yy[k] + oy, yx[k] + ox] = VEIN[min(i * len(VEIN) // n, len(VEIN) - 1)]
    tip = (yy[order[-1]] + oy, yx[order[-1]] + ox)
    out[tip] = NODE
    out = repixel.outline(out, INK)
    # The cat, asleep in the nook between the C and the l, lying on the y and c.
    c0 = letters["C"][1] * 2 + 2
    c1 = letters["l"][0] * 2 - 1
    cx = ox + (c0 + c1 + 1) // 2 - cw // 2
    cy = oy + xh - ch                   # its ink row on the letters' top ink row
    paste(out, cat, cx, cy)
    # The augment emitter on its ear: under the topmost fur pixel of the head.
    hy, hx = np.nonzero(cat[..., 3] > 0)
    ear = (cy + hy.min() + 2, cx + hx[hy == hy.min()].max())
    out[ear] = EMITTER
    # A stepped halo round the y and the emitter, where nothing is drawn,
    # kept out of the y's counter (a filled counter reads as a blob).
    lit = np.zeros((H, W), bool)
    lit[yy + oy, yx + ox] = True
    lit[ear] = True
    ring1 = repixel.neigh4(lit) | repixel.neigh4(repixel.neigh4(lit))
    ring2 = repixel.neigh4(ring1) & ~ring1
    counter = (slice(oy + xh, oy + 14), slice(ox + letters["y"][0] * 2 + 2, ox + letters["y"][1] * 2))
    ring1[counter] = False
    ring2[counter] = False
    empty = out[..., 3] == 0
    out[ring1 & empty] = (*HALO, 64)
    out[ring2 & empty] = (*HALO, 24)
    return out


def icon():
    """32x32: the sleeping cat on a lit bar (the y's vein, blue to green)
    on night navy, the ear implant glowing; corners rounded by a pixel."""
    S = 32
    out = np.zeros((S, S, 4), np.uint8)
    out[:] = hexc(NIGHT_BG)
    for (y, x) in ((0, 0), (0, S - 1), (S - 1, 0), (S - 1, S - 1)):
        out[y, x] = 0
    cat = sleeping_cat()
    ch, cw = cat.shape[:2]
    cx, cy = (S - cw) // 2, 20 - ch + 1
    bar_y, x0, x1 = 21, cx + 1, cx + cw - 2
    for x in range(x0, x1 + 1):
        t = (x - x0) / max(x1 - x0, 1)
        out[bar_y, x] = VEIN[min(int(t * len(VEIN)), len(VEIN) - 1)]
        out[bar_y + 1, x] = EXTRUDE[0]
    paste(out, cat, cx, cy)
    hy, hx = np.nonzero(cat[..., 3] > 0)
    out[cy + hy.min() + 2, cx + hx[hy == hy.min()].max()] = EMITTER
    for x in range(x0, x1 + 1):  # the bar's soft glow below it
        for k, a in ((2, 0.30), (3, 0.14)):
            c = out[bar_y + k, x, :3].astype(float)
            out[bar_y + k, x, :3] = (c * (1 - a) + np.array(HALO) * a).astype(np.uint8)
    return out


def up(a, k):
    return np.repeat(np.repeat(a, k, axis=0), k, axis=1)


def save(a, path):
    Image.fromarray(a).save(path)
    print(f"{path.name}: {a.shape[1]}x{a.shape[0]}")


def main():
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else OUT
    out.mkdir(parents=True, exist_ok=True)
    logo = build()
    save(logo, out / "logo.png")
    for k in (2, 3, 4, 6):
        save(up(logo, k), out / f"logo_x{k}.png")
    save(up(logo, 4), out / "splash.png")
    ic = icon()
    save(ic, out / "icon.png")
    save(up(ic, 4), out / "icon_x4.png")


if __name__ == "__main__":
    main()
