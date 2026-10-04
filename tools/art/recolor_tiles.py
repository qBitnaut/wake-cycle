#!/usr/bin/env python3
"""Recolour bart's "Sci-fi platformer tiles 32x32" (+ rubberduck's CC0
extension) into the Wake Cycle HD palette.

How the source is built
-----------------------
The extension sheet is 512x3520: eleven 512x320 blocks, each the same
16x10-tile layout in a different colour variant. Every block uses exactly
16 colours, and pixel for pixel the blocks are palette swaps of one another
(this script verifies that). So the art is really one 16-index image with
eleven palettes, and the honest way to recolour it is to write new palettes,
not to quantise pixels.

How the remap works
-------------------
Each of the 16 source slots has a role in the original shading (outline,
shadow, face, bevel light, highlight, specular, plus a few in-between detail
tones). Each slot is mapped to a stop of a hand-designed six-stop material
ramp (palette.py), or to a fixed blend of two stops for the in-between
tones. The blend weights were fitted to the artist's own block 0, so the
original relationships (how far a vent slit sits between shadow and light,
for instance) carry over to every new material. Hue is chosen per ramp, so
nothing is lost to nearest-colour matching, and the 4-5 shade ramps and
specular glints survive intact.

Every block is a palette swap, so block 0 is used as the index source; any
block would give the same indices (checked below).

Output: one sheet with one 512x320 block per material, in MATERIALS order,
so a tile keeps the same (col, row) inside every block and a material is a
block offset: atlas y = block * 320 + row * 32.

Usage: recolor_tiles.py [--selftest] [src_sheet] [out_dir]
"""
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parent))
import palette as P  # noqa: E402

HERE = Path(__file__).resolve().parent
DEFAULT_SRC = HERE.parent / "dl/oga32/extension-for-sci-fi-platformer-tiles-32x32-sci-fi-platformer-tiles-32x32-extension.png"
BLOCK_W, BLOCK_H, TILE = 512, 320, 32

# Block 0 colours by slot (dark to light) and the rule that rebuilds each
# slot from a six-stop ramp: a stop name, or (stop_a, stop_b, t) = blend.
SLOTS = [
    ("0d0d0d", ("ink", "#000000", 0.60)),   # near-black pinholes
    ("222034", "ink"),                       # outline
    ("306082", "shadow"),                    # shadow side, hue-shifted
    ("656472", ("ink", "face", 0.67)),       # rare dark detail
    ("47718e", ("shadow", "light", 0.25)),   # rare shadow detail
    ("767676", ("face", "ink", 0.10)),       # rare face detail
    ("847e87", "face"),                      # main face
    ("6f90a8", ("shadow", "light", 0.55)),   # vent slits, grille bars
    ("a9a5ab", ("face", "high", 0.40)),      # small panel lamps, plus marks
    ("9badb7", "light"),                     # bevel light, pipe body light
    ("9caeb8", "light"),                     # (near duplicate of light)
    ("b9c6cd", ("light", "high", 0.50)),     # vent highlights
    ("d3d3d8", ("light", "high", 0.85)),     # rare highlight
    ("d9d9de", "high"),                      # rare highlight
    ("dedede", "high"),                      # decal overlays, slats
    ("ffffff", "spec"),                      # specular glint
]

MATERIALS = ["steel", "bulkhead", "rust", "maroon", "teal", "violet", "hazard"]

# Block 0's own ramp, for the self-test: the rules should rebuild block 0.
BLOCK0_RAMP = {"ink": "#222034", "shadow": "#306082", "face": "#847e87",
               "light": "#9badb7", "high": "#dedede", "spec": "#ffffff"}


def stop(ramp, s):
    return P.hex_to_rgb(s) if s.startswith("#") else ramp[s]


def build_palette(ramp_hex):
    ramp = {k: P.hex_to_rgb(v) for k, v in ramp_hex.items()}
    out = []
    for _, rule in SLOTS:
        if isinstance(rule, str):
            out.append(ramp[rule])
        else:
            a, b, t = rule
            out.append(P.mix(stop(ramp, a), stop(ramp, b), t))
    return np.array(out, np.uint8)


def index_map(sheet):
    """Slot index per pixel of block 0 (-1 where transparent), and a check
    that every block is a pure palette swap of block 0."""
    a = np.asarray(sheet.convert("RGBA"))
    blocks = a.shape[0] // BLOCK_H
    b0 = a[:BLOCK_H]
    idx = np.full(b0.shape[:2], -1, np.int16)
    for i, (hx, _) in enumerate(SLOTS):
        idx[(b0[..., :3] == P.hex_to_rgb(hx)).all(axis=2) & (b0[..., 3] > 0)] = i
    opaque = b0[..., 3] > 0
    if (idx[opaque] < 0).any():
        raise SystemExit("block 0 has colours outside the 16 known slots")
    for k in range(1, blocks):
        bk = a[k * BLOCK_H:(k + 1) * BLOCK_H]
        if not np.array_equal(bk[..., 3], b0[..., 3]):
            raise SystemExit(f"block {k}: alpha differs from block 0")
        for i in range(len(SLOTS)):
            cols = np.unique(bk[idx == i][:, :3], axis=0)
            if len(cols) > 1:
                raise SystemExit(f"block {k}: slot {i} maps to {len(cols)} colours")
    return idx, b0[..., 3], blocks


def recolour_block(idx, alpha, pal):
    out = np.zeros(idx.shape + (4,), np.uint8)
    m = idx >= 0
    out[m, :3] = pal[idx[m]]
    out[..., 3] = alpha
    return out


def selftest():
    pal = build_palette(BLOCK0_RAMP)
    want = np.array([P.hex_to_rgb(h) for h, _ in SLOTS], np.int16)
    err = np.abs(pal.astype(np.int16) - want).max(axis=1)
    for (hx, rule), e, got in zip(SLOTS, err, pal):
        print(f"  slot {hx} rule {rule!s:32} -> {'%02x%02x%02x' % tuple(got)}  max err {e}")
    print("  worst slot error (0-255):", int(err.max()))


def swatches(path):
    names = MATERIALS
    sw, gap = 28, 4
    img = Image.new("RGB", (110 + 6 * (sw + gap), 16 + len(names) * (sw + gap)), P.hex_to_rgb(P.INK))
    d = ImageDraw.Draw(img)
    for j, n in enumerate(names):
        y = 8 + j * (sw + gap)
        d.text((6, y + 8), n, fill=(230, 230, 230))
        for i, k in enumerate(("ink", "shadow", "face", "light", "high", "spec")):
            x = 104 + i * (sw + gap)
            d.rectangle([x, y, x + sw - 1, y + sw - 1], fill=P.hex_to_rgb(P.RAMPS[n][k]))
    img.save(path)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    src = Path(args[0]) if args else DEFAULT_SRC
    out_dir = Path(args[1]) if len(args) > 1 else HERE
    sheet = Image.open(src)
    idx, alpha, blocks = index_map(sheet)
    print(f"{src.name}: {blocks} blocks, all palette swaps of block 0 (16 slots)")
    if "--selftest" in sys.argv:
        selftest()
    out = np.zeros((BLOCK_H * len(MATERIALS), BLOCK_W, 4), np.uint8)
    for k, name in enumerate(MATERIALS):
        out[k * BLOCK_H:(k + 1) * BLOCK_H] = recolour_block(idx, alpha, build_palette(P.RAMPS[name]))
    out_dir.mkdir(parents=True, exist_ok=True)
    Image.fromarray(out).save(out_dir / "tiles_wake_hd.png")
    manifest = {
        "source": src.name,
        "tile_size": TILE,
        "block_size": [BLOCK_W, BLOCK_H],
        "materials": {n: {"block": k, "y_offset": k * BLOCK_H} for k, n in enumerate(MATERIALS)},
        "note": "Same 16x10 tile layout in every block: atlas (col, row + block*10).",
    }
    (out_dir / "tiles_wake_hd.json").write_text(json.dumps(manifest, indent=2) + "\n")
    swatches(out_dir / "palette_swatches.png")
    print("wrote", out_dir / "tiles_wake_hd.png", out.shape[1], "x", out.shape[0])


if __name__ == "__main__":
    main()
