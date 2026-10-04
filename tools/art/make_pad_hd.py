#!/usr/bin/env python3
"""HD enhancement-pad plate for PadFX at art_scale 1: a 56x12 steel plate with
an ink outline, bevel, rivets and a recessed slot. Writes pad_base.png (the
lit plate) and pad_glow.png (white mask of the slot, tinted by the pad's
power colour in game). Colours come from palette.py (steel ramp).

Usage: make_pad_hd.py [out_dir]   (default: assets/art_hd)
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parent))
import palette as P  # noqa: E402

W, H = 56, 12


def main():
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent.parent / "assets" / "art_hd"
    r = {k: P.hex_to_rgb(v) for k, v in P.RAMPS["steel"].items()}
    ink = P.hex_to_rgb(P.INK)
    base = Image.new("RGBA", (W, H))
    d = ImageDraw.Draw(base)
    # Trapezoid-ish plate: sloped ends, flat deck.
    d.rectangle([2, 0, W - 3, H - 1], fill=(*ink, 255))
    d.rectangle([0, H - 2, W - 1, H - 1], fill=(*ink, 255))
    d.rectangle([3, 1, W - 4, H - 3], fill=(*r["face"], 255))
    d.line([(3, 1), (W - 4, 1)], fill=(*r["high"], 255))
    d.line([(3, 2), (W - 4, 2)], fill=(*r["light"], 255))
    d.line([(3, H - 3), (W - 4, H - 3)], fill=(*r["shadow"], 255))
    for x in (5, W - 6):
        d.point((x, 3), fill=(*r["spec"], 255))
        d.point((x, 6), fill=(*r["shadow"], 255))
    # Recessed slot where the glow strip sits.
    d.rectangle([9, 4, W - 10, 7], fill=(*r["ink"], 255))
    glow = Image.new("RGBA", (W, H))
    g = ImageDraw.Draw(glow)
    g.rectangle([10, 5, W - 11, 6], fill=(255, 255, 255, 255))
    out.mkdir(parents=True, exist_ok=True)
    base.save(out / "pad_base.png")
    glow.save(out / "pad_glow.png")
    print("wrote pad_base.png, pad_glow.png", W, "x", H)


if __name__ == "__main__":
    main()
