#!/usr/bin/env python3
"""Scale study (scratch, not game art): repixel the cat, robots and props for
Mock B ("tighter sprites") at clean sizes. Nothing here is scaled by a
fractional factor at run time; every output pixel is a whole game pixel.

Cat: the shipped 100 px frames are Scale2x of the 50 px pack plus a 1 px INK
outline (tools/art/cat_hd.py). EPX keeps the source colour in the majority of
each 2x2 block, so the 1x art comes back exactly: peel the outline ring, take
the block mode. Then Scale3x (AdvMAME3x) and a nearest /2 give 1.5x (75 px
frames), and the 4-connected INK outline goes back on at that size.

Robots and props (ansimuz, drawn at 1x): Scale2x, then a 3x3 block reduction
(coverage decides alpha, the mode of the opaque pixels decides colour) gives
2/3 size, and the silhouette's edge pixels are re-inked so the outline stays
one clean pixel.

Usage: repixel.py <out_dir>
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
INK = np.array([0x16, 0x16, 0x30, 255], np.uint8)


def rgba(path):
    a = np.asarray(Image.open(path).convert("RGBA")).copy()
    a[a[..., 3] == 0] = 0
    return a


def neigh4(m):
    n = np.zeros_like(m)
    n[1:, :] |= m[:-1, :]
    n[:-1, :] |= m[1:, :]
    n[:, 1:] |= m[:, :-1]
    n[:, :-1] |= m[:, 1:]
    return n


def scale2x(a):
    h, w, _ = a.shape
    p = np.pad(a, ((1, 1), (1, 1), (0, 0)), mode="edge")
    B, D, E, F, H = p[0:h, 1:w + 1], p[1:h + 1, 0:w], p[1:h + 1, 1:w + 1], p[1:h + 1, 2:w + 2], p[2:h + 2, 1:w + 1]
    eq = lambda x, y: (x == y).all(axis=2)
    pick = lambda c, s: np.where(c[..., None], s, E)
    o = np.zeros((h * 2, w * 2, 4), np.uint8)
    o[0::2, 0::2] = pick(eq(D, B) & ~eq(B, F) & ~eq(D, H), D)
    o[0::2, 1::2] = pick(eq(B, F) & ~eq(B, D) & ~eq(F, H), F)
    o[1::2, 0::2] = pick(eq(D, H) & ~eq(D, B) & ~eq(H, F), D)
    o[1::2, 1::2] = pick(eq(H, F) & ~eq(D, H) & ~eq(B, F), F)
    return o


def scale3x(a):
    """AdvMAME3x / Scale3x."""
    h, w, _ = a.shape
    p = np.pad(a, ((1, 1), (1, 1), (0, 0)), mode="edge")
    A, B, C = p[0:h, 0:w], p[0:h, 1:w + 1], p[0:h, 2:w + 2]
    D, E, F = p[1:h + 1, 0:w], p[1:h + 1, 1:w + 1], p[1:h + 1, 2:w + 2]
    G, H, I = p[2:h + 2, 0:w], p[2:h + 2, 1:w + 1], p[2:h + 2, 2:w + 2]
    eq = lambda x, y: (x == y).all(axis=2)
    pick = lambda c, s: np.where(c[..., None], s, E)
    core = ~eq(B, H) & ~eq(D, F)
    o = np.zeros((h * 3, w * 3, 4), np.uint8)
    o[0::3, 0::3] = pick(core & eq(D, B), D)
    o[0::3, 1::3] = pick(core & ((eq(D, B) & ~eq(E, C)) | (eq(B, F) & ~eq(E, A))), B)
    o[0::3, 2::3] = pick(core & eq(B, F), F)
    o[1::3, 0::3] = pick(core & ((eq(D, B) & ~eq(E, G)) | (eq(D, H) & ~eq(E, A))), D)
    o[1::3, 1::3] = E
    o[1::3, 2::3] = pick(core & ((eq(B, F) & ~eq(E, I)) | (eq(H, F) & ~eq(E, C))), F)
    o[2::3, 0::3] = pick(core & eq(D, H), D)
    o[2::3, 1::3] = pick(core & ((eq(D, H) & ~eq(E, I)) | (eq(H, F) & ~eq(E, G))), H)
    o[2::3, 2::3] = pick(core & eq(H, F), F)
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


def outline_outside(a):
    solid = a[..., 3] > 0
    edge = neigh4(solid) & ~solid
    o = a.copy()
    o[edge] = INK
    return o


def ink_edges(a, ink):
    """Re-ink the silhouette's own edge pixels (keeps the size)."""
    solid = a[..., 3] > 0
    edge = solid & neigh4(~solid)
    o = a.copy()
    o[edge] = ink
    return o


def cat_1x(frame100):
    a = frame100.copy()
    solid = a[..., 3] > 0
    ring = solid & neigh4(~solid) & (a == INK).all(axis=2)
    a[ring] = 0
    return block_mode(a, 2, cover=0.5)


def cat_sheets(out):
    for src in sorted((ROOT / "assets/sprites/cat").glob("cat_*.png")):
        sheet = rgba(src)
        n = sheet.shape[1] // 100
        frames = []
        for i in range(n):
            one = cat_1x(sheet[:, i * 100:(i + 1) * 100])
            big = scale3x(one)[0::2, 0::2]  # 150 -> 75, nearest
            frames.append(outline_outside(big))
        Image.fromarray(np.concatenate(frames, axis=1)).save(out / src.name.replace("cat_", "cat15_"))
        if src.name == "cat_idle.png":
            Image.fromarray(np.concatenate([cat_1x(sheet[:, i * 100:(i + 1) * 100]) for i in range(n)], axis=1)).save(out / "cat1x_idle.png")


def dark_ink(a):
    op = a[a[..., 3] > 0][:, :3].astype(int)
    lum = op @ np.array([299, 587, 114])
    return np.array([*op[lum.argmin()], 255], np.uint8)


def two_thirds(a):
    ink = dark_ink(a)
    return ink_edges(block_mode(scale2x(a), 3, cover=0.45), ink)


def sheet_two_thirds(src, cell, out_name, out):
    a = rgba(src)
    cw, ch = cell
    n = a.shape[1] // cw
    frames = [two_thirds(a[:, i * cw:(i + 1) * cw]) for i in range(n)]
    Image.fromarray(np.concatenate(frames, axis=1)).save(out / out_name)
    print(out_name, frames[0].shape[1], "x", frames[0].shape[0], "cell,", n, "frames")


def main():
    out = Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    cat_sheets(out)
    r = ROOT / "assets/art_hd/robots"
    sheet_two_thirds(r / "bipedal.png", (80, 64), "bipedal_23.png", out)
    sheet_two_thirds(r / "mech.png", (96, 80), "mech_23.png", out)
    for d in ["drone_1.png"]:
        sheet_two_thirds(r / d, (55, 52), d.replace(".png", "_23.png"), out)
    for p in sorted((ROOT / "assets/art_hd/props").glob("*.png")):
        a = rgba(p)
        sheet_two_thirds(p, (a.shape[1], a.shape[0]), p.stem + "_23.png", out)


if __name__ == "__main__":
    main()
