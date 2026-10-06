#!/usr/bin/env python3
"""Scale study: comparison sheet, detail crops and the motion strip from the
shots that tools/scale/shoot.sh wrote.  sheets.py <scale_dir>  (expects raw/ inside)."""
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
D = Path(sys.argv[1])
RAW = D / "raw"
FONT = ImageFont.truetype(str(ROOT / "assets/fonts/monogram.ttf"), 48)
FONT_S = ImageFont.truetype(str(ROOT / "assets/fonts/monogram.ttf"), 32)
BG = (18, 18, 26)
FG = (230, 228, 220)
MUTED = (150, 150, 165)

TITLES = {
    "A": ("A  as is", "640x360 integer"),
    "B": ("B  tighter sprites", "640x360 integer, cat 1.5x, robots+props 2/3"),
    "C": ("C  more world", "800x450 fractional, current sprites"),
    "D": ("D  B + C", "800x450 fractional, tighter sprites"),
    "Cs": ("C'  sharp present", "800x450, sharp-bilinear blit (simulated)"),
}


def sharp_bilinear(img, size):
    """Sharp-bilinear upscale (the CineZoom sampling): nearest inside each texel,
    a one-screen-pixel blend across texel edges, so every art pixel gets the same width."""
    a = np.asarray(img.convert("RGB")).astype(np.float32)
    h, w, _ = a.shape
    W, H = size
    kx, ky = W / w, H / h

    def axis(n_out, n_in, k):
        t = (np.arange(n_out) + 0.5) / k - 0.5
        i = np.floor(t).astype(int)
        f = np.clip((t - i - 0.5) * k + 0.5, 0.0, 1.0)
        return np.clip(i, 0, n_in - 1), np.clip(i + 1, 0, n_in - 1), f

    x0, x1, fx = axis(W, w, kx)
    y0, y1, fy = axis(H, h, ky)
    rows = a[y0] * (1 - fy)[:, None, None] + a[y1] * fy[:, None, None]
    out = rows[:, x0] * (1 - fx)[None, :, None] + rows[:, x1] * fx[None, :, None]
    return Image.fromarray(np.clip(out + 0.5, 0, 255).astype(np.uint8))


def label(img, title, sub, pad=64):
    out = Image.new("RGB", (img.width, img.height + pad + 8), BG)
    out.paste(img, (0, pad + 8))
    d = ImageDraw.Draw(out)
    d.text((12, 4), title, font=FONT, fill=FG)
    d.text((12 + d.textlength(title, font=FONT) + 24, 18), sub, font=FONT_S, fill=MUTED)
    return out


def grid(cells, cols, gap=16):
    w = max(c.width for c in cells)
    h = max(c.height for c in cells)
    rows = (len(cells) + cols - 1) // cols
    out = Image.new("RGB", (cols * w + (cols - 1) * gap, rows * h + (rows - 1) * gap), BG)
    for i, c in enumerate(cells):
        out.paste(c, ((i % cols) * (w + gap), (i // cols) * (h + gap)))
    return out


def comparison(size):
    cells = [label(Image.open(RAW / f"{v}_{size}_window.png").convert("RGB"), *TITLES[v]) for v in "ABCD"]
    g = grid(cells, 2)
    g.save(D / f"compare_{size}.png", optimize=True)
    print("compare", size, g.size)


def offset_from_a(v):
    """Where A's internal (x, y) lands in variant v's internal frame (template match on wall and floor)."""
    a = np.asarray(Image.open(RAW / "A_1080_internal.png").convert("L")).astype(int)
    b = np.asarray(Image.open(RAW / f"{v}_1080_internal.png").convert("L")).astype(int)
    t = a[290:330, 20:180]
    best = None
    for y in range(0, b.shape[0] - 40):
        for x in range(0, 140):
            d = np.abs(b[y:y + 40, x:x + 160] - t).mean()
            if best is None or d < best[0]:
                best = (d, x - 20, y - 290)
    return best[1], best[2]


def details():
    """Same world rect around the cat, the walker and the drone, at true 1080p screen size."""
    x0, y0, x1, y1 = 230, 176, 500, 330  # in A's internal frame
    cells = []
    for v in "ABCD":
        img = Image.open(RAW / f"{v}_1080_window.png").convert("RGB")
        k = img.width / Image.open(RAW / f"{v}_1080_internal.png").width
        dx, dy = offset_from_a(v)
        cells.append(label(img.crop((round((x0 + dx) * k), round((y0 + dy) * k), round((x1 + dx) * k), round((y1 + dy) * k))), *TITLES[v]))
    g = grid(cells, 2)
    g.save(D / "detail_1080.png", optimize=True)
    print("detail", g.size)


def shift_of(prefix, n, base_n=50):
    base = np.asarray(Image.open(f"{prefix}_{base_n:04d}_internal.png").convert("L")).astype(int)
    im = np.asarray(Image.open(f"{prefix}_{n:04d}_internal.png").convert("L")).astype(int)
    h, w = base.shape
    band = slice(int(h * 0.1), int(h * 0.55))
    errs = [np.abs(base[band, dx + 100:w - 150] - im[band, 100:w - 150 - dx]).mean() for dx in range(120)]
    return int(np.argmin(errs))


def world_crop(prefix, n, rect, k):
    dx = shift_of(prefix, n)
    x0, y0, x1, y1 = rect
    img = Image.open(f"{prefix}_{n:04d}_window.png").convert("RGB")
    ox = (img.width - round(img.width / k) * k) / 2  # letterbox (none at 16:9)
    return img.crop((round((x0 - dx) * k + ox), round(y0 * k), round((x1 - dx) * k + ox), round(y1 * k)))


def motion():
    strip = RAW / "strip"
    for n in range(50, 74):
        for size, wh in (("1080", (1920, 1080)), ("720", (1280, 720))):
            src = Image.open(strip / f"C_{size}_{n:04d}_internal.png")
            src.save(strip / f"Cs_{size}_{n:04d}_internal.png")
            sharp_bilinear(src, wh).save(strip / f"Cs_{size}_{n:04d}_window.png")
    rect_a, rect_c = (110, 250, 214, 330), (190, 318, 294, 398)  # computer desk and floor, at frame 50
    rows = [("A_1080", 3.0, rect_a, "A  1080p, 3x integer"),
            ("C_1080", 2.4, rect_c, "C  1080p, 2.4x nearest"),
            ("Cs_1080", 2.4, rect_c, "C' 1080p, 2.4x sharp-bilinear (sim)"),
            ("A_720", 2.0, rect_a, "A  720p, 2x integer"),
            ("C_720", 1.6, rect_c, "C  720p, 1.6x nearest"),
            ("Cs_720", 1.6, rect_c, "C' 720p, 1.6x sharp-bilinear (sim)")]
    frames = list(range(60, 65))
    zoom = 2
    lines = []
    gifs = []
    for prefix, k, rect, title in rows:
        crops = [world_crop(RAW / "strip" / prefix, n, rect, k) for n in frames]
        cw = max(c.width for c in crops) * zoom
        ch = max(c.height for c in crops) * zoom
        row = Image.new("RGB", (len(crops) * (cw + 12), ch), BG)
        for i, c in enumerate(crops):
            row.paste(c.resize((c.width * zoom, c.height * zoom), Image.NEAREST), (i * (cw + 12), 0))
        lines.append(label(row, title, "frames 60-64, same world rect, camera scrolling, shown 2x"))
        seq = [world_crop(RAW / "strip" / prefix, n, rect, k) for n in range(58, 74)]
        gw, gh = max(c.width for c in seq), max(c.height for c in seq)
        gifs.append([Image.new("RGB", (gw, gh), BG) for _ in seq])
        for g, c in zip(gifs[-1], seq):
            g.paste(c, (0, 0))
    out = Image.new("RGB", (max(l.width for l in lines), sum(l.height + 16 for l in lines)), BG)
    y = 0
    for l in lines:
        out.paste(l, (0, y))
        y += l.height + 16
    out.save(D / "motion_strip.png", optimize=True)
    print("motion", out.size)
    # One GIF: 1080p panels on the top row, 720p below, each at its real screen size x2.
    z = 2
    pw = max(g[0].width for g in gifs) * z + 16
    ph = max(g[0].height for g in gifs) * z + 16
    anim = []
    for i in range(len(gifs[0])):
        f = Image.new("RGB", (pw * 3, ph * 2), BG)
        for j, g in enumerate(gifs):
            f.paste(g[i].resize((g[i].width * z, g[i].height * z), Image.NEAREST), ((j % 3) * pw, (j // 3) * ph))
        anim.append(f)
    anim[0].save(D / "motion.gif", save_all=True, append_images=anim[1:], duration=100, loop=0)


def main():
    comparison("1080")
    comparison("720")
    details()
    motion()
    for v in "ABCD":
        for s in ("1080", "720"):
            Image.open(RAW / f"{v}_{s}_window.png").convert("RGB").save(D / f"{v}_{s}.png", optimize=True)
    for s, wh in (("1080", (1920, 1080)), ("720", (1280, 720))):
        sharp_bilinear(Image.open(RAW / f"C_{s}_internal.png"), wh).save(D / f"C_sharp_{s}.png", optimize=True)


if __name__ == "__main__":
    main()
