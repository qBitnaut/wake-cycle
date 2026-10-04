#!/usr/bin/env python3
"""Light harmonisation of the ansimuz back layers toward the Wake Cycle HD
palette.

These layers use tiny palettes (4 to 13 colours), so the honest tool is the
same one as for the tiles: an explicit colour-for-colour swap, written by
hand, not a filter. Three goals only:

  1. Push the back wall a step darker than the source, so the steel
     foreground separates by value (the source was paired with orange
     platforms, which separated by hue instead).
  2. Calm the electric cyan indicators (00c9ea is within a hair of the cyan
     PHASE power glow) to a dimmer aqua, so nothing on the wall reads as a
     power pickup.
  3. Bring the Warped City night sky's candy reds and magentas down to the
     maroon/rust family, keeping the moon and the warm city glow.

Anything not listed is left as is. Output goes to ./bg/.

Usage: harmonize_bg.py <dl_dir> [out_dir]   (out_dir default: assets/art_hd)

Subfolders of out_dir: bg/ (back layers), props/, robots/.
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent
LEG = "legacy/Legacy Collection/Assets/Warped/Environments/"
WC = "wcity/warped city files/Assets/ENVIRONMENT/"

JOBS = {
    # Warped sci-fi interior machinery wall (the Mock A wall).
    "wall_machinery.png": (LEG + "sci-fi-interior-platform/PNG/background.png", {
        "293445": "202d3a",   # wall body
        "2f3f53": "263646",
        "354f67": "2b4152",
        "365068": "2d4757",
        "406078": "395766",   # top-lit edges
        "00c9ea": "41b5c0",   # indicator lights, calmed
    }),
    # Structural column from the Scifi lab (was saturated lab blue).
    "column.png": (LEG + "Scifi lab Files/layers/Props/support.png", {
        "04131a": "0f1620",
        "083247": "1f2d3b",
        "0b4a75": "2a3e4f",
        "085f8a": "3a5667",
    }),
    # Server cabinets (already on-palette teal; nudged to the wall family).
    "servers.png": (LEG + "cyberpunk-detective-props/PNG/server-gabinetes.png", {
        "020a17": "0e1420",
        "111b27": "18222f",
        "17303b": "223443",
        "2d5b61": "355a62",
    }),
    # Small terminal: keep its amber screen (a tiny warm accent).
    "terminal.png": (LEG + "cyberpunk-detective-props/PNG/small-terminal.png", {
        "020a17": "0e1420",
        "111b27": "18222f",
        "17303b": "223443",
        "2d5b61": "355a62",
        "301f43": "2d1d3c",
        "502e61": "4a2f58",
    }),
    # Warped City night sky with moon (seen through the window).
    "sky.png": (WC + "background/skyline-b.png", {
        "00003c": "0c1030",   # deep sky, a touch less pure blue
        "010350": "121845",
        "040c5a": "182252",
        "031b70": "1e2c62",
        "0b347f": "2c4479",
        "177daa": "5a86ac",   # moon and stars: silver-blue, matches MOON
        "21004b": "1c1240",
        "540052": "3c1a4a",   # magenta haze -> plum
        "880c4f": "6a2448",   # -> maroon
        "ec1e44": "963a48",   # candy red -> rust-rose
        "fc583a": "b45a46",   # -> rust light
        "f07c36": "c87844",   # city glow: sodium family, kept warm but dimmer than the moon
        "de9a41": "d8964e",
    }),
    # Distant towers (seen through the window).
    "towers.png": (WC + "background/buildings-bg.png", {
        "00003c": "0c1030",
        "21004b": "1a1238",
        "031b70": "1a2858",
        "040c5a": "141e4a",
        "0b347f": "26386a",
        "177daa": "6a9ab8",   # cool lit windows
        "540052": "3c1a4a",
        "9b0c8e": "c8804a",   # magenta windows -> warm sodium windows
    }),
}

# Warped City drone (enemy): cool lavender body kept, ink unified, and the
# cyan eye turned laser red, so "red = hostile" and cyan stays a power hue.
DRONE = {
    "050912": "161630",
    "442b61": "3a2c5e",
    "a096d1": "9a98c8",
    "fcfcfc": "e8ecf2",
    "00fff0": "ff4a3a",
}
for _i in range(1, 5):
    JOBS[f"robots/drone_{_i}.png"] = ("wcity/warped city files/Assets/SPRITES/misc/drone/drone-%d.png" % _i, DRONE)


# Props: one wall-family nudge shared by every Legacy cyberpunk prop. The
# lab tank's saturated cyan glass is a power hue, so it becomes muted teal.
LP = LEG.replace("sci-fi-interior-platform/PNG/", "")
PROP = {
    "020a17": "0e1420", "111b27": "18222f", "17303b": "223443",
    "2d5b61": "355a62", "301f43": "2d1d3c", "502e61": "4a2f58",
}
for _n, _extra in (("big-computer", {}), ("hanging-terminal", {}),
                   ("elevator", {}), ("cryo-pod", {"3abdb8": "2f6a72"})):
    JOBS[f"props/{_n}.png"] = (LP + f"cyberpunk-detective-props/PNG/{_n}.png", {**PROP, **_extra})
JOBS["props/servers.png"] = JOBS.pop("servers.png")
JOBS["props/terminal.png"] = JOBS.pop("terminal.png")

# Robots: warm bodies stay (warm = danger), the green/cyan glow becomes
# laser red (red = hostile), and the ink is unified.
CH = "legacy/Legacy Collection/Assets/Warped/Characters/"
RED_GLOW = {"006d81": "5a1c2c", "00967f": "a8302e", "009382": "a8302e", "00c172": "d8403a",
            "00e089": "ff4a3a", "00f7ad": "ff7a5a", "140102": "161630"}
JOBS["robots/bipedal.png"] = (CH + "bipedal-Unit/spritesheet.png", RED_GLOW)
JOBS["robots/mech.png"] = (CH + "mech-unit/spritesheet/mech-unit.png", RED_GLOW)
for _i in range(1, 7):
    JOBS[f"robots/turret_{_i}.png"] = ("wcity/warped city files/Assets/SPRITES/misc/turret/turret-%d.png" % _i, {
        "050912": "161630", "ec7809": "ff4a3a", "ff2245": "ff4a3a", "ffd800": "eda63a"})
JOBS["bg/near_buildings.png"] = (WC + "background/near-buildings-bg.png", JOBS["towers.png"][1])


def hx(s):
    return tuple(int(s[i:i + 2], 16) for i in (0, 2, 4))


def swap(img, table):
    a = np.asarray(img.convert("RGBA")).copy()
    rgb = a[..., :3]
    out = rgb.copy()
    for src, dst in table.items():
        out[(rgb == hx(src)).all(axis=2)] = hx(dst)
    a[..., :3] = out
    return Image.fromarray(a)


def main():
    dl = Path(sys.argv[1])
    out = Path(sys.argv[2]) if len(sys.argv) > 2 else HERE.parent.parent / "assets" / "art_hd"
    out.mkdir(parents=True, exist_ok=True)
    for name, (src, table) in JOBS.items():
        img = Image.open(dl / src)
        dest = out / (name if "/" in name else "bg/" + name)
        dest.parent.mkdir(parents=True, exist_ok=True)
        swap(img, table).save(dest)
        print(f"{name}: {img.width}x{img.height}, {len(table)} colours swapped")


if __name__ == "__main__":
    main()
