"""Actor-kit art sheet: every kit actor at 1x and 3x on the game background,
beside the HD cat at its current size and at the B' size (1.5x art).

    python3 tools/art/kit_sheet.py OUT_DIR [B_PRIME_CAT_SHEET]

Reads what the game loads (assets/sprites/kit/kit_manifest.json and its PNGs).
The stage is built from the room's own layers (back wall, ansimuz machinery,
steel floor tiles) and everything on it, cats included, is multiplied by the
ambient measured on Room 1's floor in a game frame (0.52, 0.56, 0.75), so the
values are the unlit in-game values; lamps and the moon only add to them.

B_PRIME_CAT_SHEET is the scale study's 1.5x idle sheet (75 px frames,
tools/scale/art/cat15_idle.png on feat/scale); without it the B' cat is left out.

Writes lineup_1x.png, lineup_3x.png, frames_3x.png and kit_sheet.png (all three).
"""
import json
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
MAN = json.load(open(os.path.join(ROOT, "assets/sprites/kit/kit_manifest.json")))
AMB = (0.52, 0.56, 0.75)
WALL = (15, 25, 48)
FONT = os.path.join(ROOT, "assets/fonts/monogram.ttf")
TEXT = (255, 226, 150)
DIM = (150, 160, 190)

_strips = {}


def strip_of(aid, part):
    key = (aid, part)
    if key not in _strips:
        p = MAN["actors"][aid]["parts"][part]
        _strips[key] = Image.open(os.path.join(ROOT, p["file"])).convert("RGBA")
    return _strips[key]


def frame(aid, part=None, anim=None, i=0):
    a = MAN["actors"][aid]
    part = part or a["main"]
    p = a["parts"][part]
    if anim is None:
        idx = i
    else:
        fr = p["anims"][anim]["frames"]
        idx = fr[min(i, len(fr) - 1)]
    cw, ch = p["cell"]
    return strip_of(aid, part).crop((idx * cw, 0, (idx + 1) * cw, ch)), tuple(p["pivot"]), tuple(p["offset"])


def tint(im, k=AMB):
    r, g, b, a = im.split()
    r = r.point(lambda v: int(v * k[0]))
    g = g.point(lambda v: int(v * k[1]))
    b = b.point(lambda v: int(v * k[2]))
    return Image.merge("RGBA", (r, g, b, a))


def put(stage, im, pivot, at, flip_v=False, rot=0.0):
    """Draw `im` so its pivot lands on `at` (stage px)."""
    if flip_v:
        im = im.transpose(Image.FLIP_TOP_BOTTOM)
        pivot = (pivot[0], im.size[1] - pivot[1])
    if rot:
        # rotate about the pivot with nearest sampling: pad so the pivot is centred
        w, h = im.size
        R = int(math.ceil(math.hypot(max(pivot[0], w - pivot[0]), max(pivot[1], h - pivot[1])))) + 1
        big = Image.new("RGBA", (R * 2, R * 2), (0, 0, 0, 0))
        big.paste(im, (R - pivot[0], R - pivot[1]))
        im = big.rotate(-rot, resample=Image.NEAREST, center=(R, R))
        pivot = (R, R)
    stage.alpha_composite(tint(im), (int(at[0] - pivot[0]), int(at[1] - pivot[1])))


# ---- the stage -------------------------------------------------------------------

TILES = Image.open(os.path.join(ROOT, "assets/art_hd/tiles_wake_hd.png")).convert("RGBA")
MACH = Image.open(os.path.join(ROOT, "assets/art_hd/bg/wall_machinery.png")).convert("RGBA")


def tile(col, row, block):
    return TILES.crop((col * 32, (row + 10 * block) * 32, col * 32 + 32, (row + 10 * block) * 32 + 32))


def stage(w, h, floor_y, ceiling=True):
    s = Image.new("RGBA", (w, h), WALL + (255,))
    m = tint(MACH, (AMB[0] * 0.7, AMB[1] * 0.7, AMB[2] * 0.7))
    for x in range(0, w, MACH.size[0]):
        s.alpha_composite(m, (x, floor_y - MACH.size[1]))
    floor = tint(tile(0, 2, 0))
    under = tint(tile(4, 3, 3), (AMB[0] * 0.6, AMB[1] * 0.6, AMB[2] * 0.6))
    for x in range(0, w, 32):
        s.alpha_composite(floor, (x, floor_y))
        for y in range(floor_y + 32, h, 32):
            s.alpha_composite(under, (x, y))
    if ceiling:
        ceil = tint(tile(4, 3, 1))
        for x in range(0, w, 32):
            s.alpha_composite(ceil, (x, 0))
    return s


# ---- cats --------------------------------------------------------------------------

def cat_hd():
    im = Image.open(os.path.join(ROOT, "assets/sprites/cat/cat_idle.png")).convert("RGBA").crop((0, 0, 100, 100))
    return im, (50, 65)   # Sprite at (0, -15), centred: the feet are 15 px under the frame centre


def cat_bprime(path):
    if not path or not os.path.exists(path):
        return None
    im = Image.open(path).convert("RGBA").crop((0, 0, 75, 75))
    bb = im.getbbox()
    return im, ((bb[0] + bb[2]) // 2, bb[3])


# ---- lineups -----------------------------------------------------------------------

def label(d, xy, text, font, col=TEXT):
    d.text(xy, text, font=font, fill=col)


def lineup_rows(bcat):
    """Three 640 px stages, each with the two cats at the left for scale."""
    rows = []
    F = 112  # floor y on a 150 px stage (ceiling row 0..31)
    H = 150

    def cats(st, x):
        im, pv = cat_hd()
        put(st, im, pv, (x, F))
        if bcat:
            put(st, bcat[0], bcat[1], (x + 44, F))
        return x + 74

    # 1 enemies
    st = stage(640, H, F)
    x = cats(st, 26)
    for aid, anim, w in (("sentry_turret", "idle", 40), ("patrol_bot", "walk", 42), ("hopper_bot", "idle", 32),
                         ("crawler", "crawl", 40), ("heavy_mech", "walk", 48)):
        x += w // 2
        im, pv, _ = frame(aid, None, anim)
        put(st, im, pv, (x, F))
        if aid == "sentry_turret":
            hi, hp, off = frame(aid, "head", "idle")
            put(st, hi, hp, (x + off[0], F + off[1]))
        x += w // 2 + 8
    # drone hovering, crawler and camera on the ceiling
    im, pv, _ = frame("hover_drone", None, "fly")
    put(st, im, pv, (x + 22, F - 50))
    x += 52
    im, pv, _ = frame("crawler", None, "crawl")
    put(st, im, pv, (x + 18, 32), flip_v=True)
    x += 44
    mi, mp, _ = frame("security_camera", "mount", "idle")
    hi, hp, off = frame("security_camera", "head", "idle")
    put(st, mi, mp, (x + 10, 32))
    put(st, hi, hp, (x + 10 + off[0], 32 + off[1]), rot=55)
    x += 40
    im, pv, _ = frame("hover_drone", None, "arm")
    put(st, im, pv, (x + 22, F - 50))
    rows.append(("enemies", st))

    # 2 destructibles
    st = stage(640, H, F)
    x = cats(st, 26)
    for aid in ("barrel_plain", "barrel_explosive", "barrel_acid"):
        im, pv, _ = frame(aid, None, "idle")
        put(st, im, pv, (x + 13, F))
        x += 30
    x += 6
    for aid in ("wall_cracked", "wall_reinforced", "wall_blast"):
        im, pv, _ = frame(aid, None, "idle")
        put(st, im, pv, (x + 16, F))
        put(st, im, pv, (x + 16, F - 32))
        x += 40
    im, pv, _ = frame("barrel_acid", None, "leak")
    put(st, im, pv, (x + 13, F))
    x += 30
    im, pv, _ = frame("barrel_explosive", None, "lit", 1)
    put(st, im, pv, (x + 13, F))
    x += 36
    for k in range(4):
        im, pv, _ = frame("platform", None, ["left", "mid", "mid", "right"][k])
        put(st, im, pv, (x + 16 + k * 32, F - 44))
    rows.append(("destructibles + platform", st))

    # 3 hazards
    st = stage(640, H, F)
    x = cats(st, 26)
    for k in range(3):
        im, pv, _ = frame("electric_floor", None, "live", k)
        put(st, im, pv, (x + 16 + k * 32, F))
    x += 104
    for k in range(2):
        im, pv, _ = frame("spike_trap", None, "up")
        put(st, im, pv, (x + 16 + k * 32, F))
    x += 72
    # crusher mid-stroke from the ceiling
    rod = frame("crusher", "rod", "idle")[0]
    for y in range(32, 32 + 40, 8):
        put(st, rod, (4, 0), (x + 16, y))
    im, pv, _ = frame("crusher", "head", "warn", 1)
    put(st, im, pv, (x + 16, 32 + 40))
    x += 40
    for aid in ("vent_steam", "vent_flame"):
        im, pv, _ = frame(aid)
        put(st, im, pv, (x + 12, F))
        x += 30
    for k in range(2):
        im, pv, _ = frame("acid_pool", None, "bubble", k)
        put(st, im, pv, (x + 16 + k * 32, F))
    x += 70
    im, pv, _ = frame("falling_debris", "crack", "idle")
    put(st, im, pv, (x + 16, 32))
    im, pv, _ = frame("falling_debris", "rock", "idle")
    put(st, im, pv, (x + 16, 32 + 40))
    x += 36
    for k in range(3):
        im, pv, _ = frame("conveyor", None, "run", k)
        put(st, im, pv, (x + 16 + k * 32, F))
    rows.append(("hazards", st))

    # 4 pickups + projectiles
    st = stage(640, H, F)
    x = cats(st, 26)
    for name in ("fish", "yarn", "bell", "mouse", "chip", "bone", "memory"):
        im, pv, _ = frame("pickup_" + name, None, "idle")
        put(st, im, pv, (x + 12, F - 14))
        x += 34
    x += 10
    for aid, anim, y in (("bolt", "fly", F - 20), ("bomb", "fall", F - 40), ("spark", "fly", F - 20)):
        im, pv, _ = frame(aid, None, anim)
        put(st, im, pv, (x + 12, y))
        x += 30
    for k, an in enumerate(("a", "b", "c")):
        im, pv, _ = frame("debris_chunk", None, an)
        put(st, im, pv, (x + 6 + k * 12, F - 6))
    rows.append(("pickups + projectiles", st))
    return rows


# ---- every frame, 3x ------------------------------------------------------------------

def frames_panel(font, zoom=3):
    blocks = []
    for aid, a in MAN["actors"].items():
        for pname, p in a["parts"].items():
            st = strip_of(aid, pname)
            cw, ch = p["cell"]
            n = st.size[0] // cw
            pad = 4
            w = n * (cw + pad) * zoom + 8
            h = ch * zoom + 26
            b = Image.new("RGBA", (w, h), WALL + (255,))
            for i in range(n):
                fr = tint(st.crop((i * cw, 0, (i + 1) * cw, ch)))
                b.alpha_composite(fr.resize((cw * zoom, ch * zoom), Image.NEAREST), (4 + i * (cw + pad) * zoom, 22))
            d = ImageDraw.Draw(b)
            anims = ", ".join("%s %s" % (k, v["frames"]) for k, v in p["anims"].items())
            label(d, (4, 2), "%s / %s" % (aid, pname), font)
            label(d, (4 + len("%s / %s" % (aid, pname)) * 6 + 14, 2), anims[:150], font, DIM)
            blocks.append(b)
    # pack blocks into rows up to 1920 wide
    W = 1920
    rows, cur, cw = [], [], 0
    for b in blocks:
        if cur and cw + b.size[0] > W:
            rows.append(cur)
            cur, cw = [], 0
        cur.append(b)
        cw += b.size[0] + 6
    rows.append(cur)
    H = sum(max(b.size[1] for b in r) + 6 for r in rows)
    out = Image.new("RGBA", (W, H), (8, 10, 18, 255))
    y = 0
    for r in rows:
        x = 0
        for b in r:
            out.alpha_composite(b, (x, y))
            x += b.size[0] + 6
        y += max(b.size[1] for b in r) + 6
    return out


def palette_panel(d, x, y, font):
    """The kit's ramps as swatches (albedo, as drawn)."""
    sys.path.insert(0, os.path.dirname(__file__))
    from palette import ACTOR_RAMPS, RAMPS
    label(d, (x, y), "palette (albedo)", font)
    y += 18
    groups = [(n, v) for n, v in ACTOR_RAMPS.items()]
    groups += [(n, [RAMPS[n][k] for k in ("ink", "shadow", "face", "light", "high", "spec")])
               for n in ("steel", "bulkhead", "hazard", "maroon")]
    for name, hexes in groups:
        label(d, (x, y + 1), name, font, DIM)
        for i, h in enumerate(hexes):
            h = h.lstrip("#")
            c = tuple(int(h[j:j + 2], 16) for j in (0, 2, 4))
            d.rectangle([x + 70 + i * 18, y + 2, x + 70 + i * 18 + 15, y + 14], fill=c)
        y += 17


def main():
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    bcat = cat_bprime(sys.argv[2] if len(sys.argv) > 2 else "")
    font = ImageFont.truetype(FONT, 16)
    big = ImageFont.truetype(FONT, 32)
    rows = lineup_rows(bcat)
    W1 = 640
    one = Image.new("RGBA", (W1, sum(r[1].size[1] + 14 for r in rows)), (8, 10, 18, 255))
    y = 0
    d = ImageDraw.Draw(one)
    for name, st in rows:
        label(d, (4, y), name + "  (1x, game px)", font)
        one.alpha_composite(st, (0, y + 14))
        y += st.size[1] + 14
    one.save(os.path.join(out, "lineup_1x.png"))
    three = Image.new("RGBA", (W1 * 3, sum(r[1].size[1] * 3 + 30 for r in rows)), (8, 10, 18, 255))
    d3 = ImageDraw.Draw(three)
    y = 0
    for name, st in rows:
        label(d3, (8, y), name + "  (3x)", big)
        three.alpha_composite(st.resize((st.size[0] * 3, st.size[1] * 3), Image.NEAREST), (0, y + 30))
        y += st.size[1] * 3 + 30
    three.save(os.path.join(out, "lineup_3x.png"))
    fp = frames_panel(font)
    fp.save(os.path.join(out, "frames_3x.png"))
    head_h = 120
    # 1x stages two by two, the palette beside them
    grid = Image.new("RGBA", (1920, 2 * (rows[0][1].size[1] + 14)), (8, 10, 18, 255))
    dg = ImageDraw.Draw(grid)
    for k, (name, st) in enumerate(rows):
        gx, gy = (k % 2) * (W1 + 16), (k // 2) * (st.size[1] + 14)
        label(dg, (gx + 4, gy), name + "  (1x, game px)", font)
        grid.alpha_composite(st, (gx, gy + 14))
    palette_panel(dg, 2 * (W1 + 16) + 8, 0, font)
    sheet = Image.new("RGBA", (1920, head_h + grid.size[1] + 20 + three.size[1] + 20 + fp.size[1]), (8, 10, 18, 255))
    ds = ImageDraw.Draw(sheet)
    label(ds, (16, 10), "WAKE CYCLE  actor kit art pass", big)
    notes = ("Left of every stage: the HD cat as it ships (2x art), then the B' cat (1.5x art). Enemies 1-1.35 tiles, "
             "hazards and destructibles on the 32 px grid, pickups 12-20 px.",
             "All actors and cats multiplied by the in-game ambient (0.52, 0.56, 0.75) measured on Room 1's floor; "
             "lamps, the moon and glow add to this in the game.")
    label(ds, (16, 50), notes[0], font, DIM)
    label(ds, (16, 70), notes[1], font, DIM)
    sheet.alpha_composite(grid, (16, head_h))
    sheet.alpha_composite(three, (0, head_h + grid.size[1] + 20))
    sheet.alpha_composite(fp, (0, head_h + grid.size[1] + 20 + three.size[1] + 20))
    sheet.save(os.path.join(out, "kit_sheet.png"))
    for f in ("lineup_1x.png", "lineup_3x.png", "frames_3x.png", "kit_sheet.png"):
        print(os.path.join(out, f), Image.open(os.path.join(out, f)).size)


if __name__ == "__main__":
    main()
