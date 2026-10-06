"""Stitch the frames kit_shots.gd renders into labelled strips.

    python3 tools/art/kit_strips.py <dir_with_frames> [columns]

Every <scenario>_NN.png group becomes <scenario>_strip.png (frames at half size,
numbered) and <scenario>_zoom.png (the action around the cat, 1:1, 3 columns), and a
contact sheet of all strips is written as _sheet.png.
"""
import glob
import os
import re
import sys

from PIL import Image, ImageDraw

d = sys.argv[1]
cols = int(sys.argv[2]) if len(sys.argv) > 2 else 4
groups = {}
for f in sorted(glob.glob(os.path.join(d, "*_[0-9][0-9].png"))):
    m = re.match(r"(.*)_(\d\d)\.png$", os.path.basename(f))
    groups.setdefault(m.group(1), []).append(f)
strips = []
for name, files in groups.items():
    ims = [Image.open(f).convert("RGB") for f in files]
    w, h = ims[0].size
    sw, sh = w // 2, h // 2
    rows = (len(ims) + cols - 1) // cols
    out = Image.new("RGB", (sw * cols, sh * rows), (20, 24, 32))
    dr = ImageDraw.Draw(out)
    for i, im in enumerate(ims):
        x, y = (i % cols) * sw, (i // cols) * sh
        out.paste(im.resize((sw, sh), Image.LANCZOS), (x, y))
        dr.text((x + 4, y + 3), "%s %d" % (name, i), fill=(255, 230, 120))
    p = os.path.join(d, name + "_strip.png")
    out.save(p)
    strips.append(out)
    print(p, out.size)
    box = (110, 120, 530, 340)
    zw, zh = box[2] - box[0], box[3] - box[1]
    zc = 3
    zr = (len(ims) + zc - 1) // zc
    zoom = Image.new("RGB", (zw * zc, zh * zr), (20, 24, 32))
    zd = ImageDraw.Draw(zoom)
    for i, im in enumerate(ims):
        x, y = (i % zc) * zw, (i // zc) * zh
        zoom.paste(im.crop(box), (x, y))
        zd.text((x + 4, y + 3), "%s %d" % (name, i), fill=(255, 230, 120))
    zoom.save(os.path.join(d, name + "_zoom.png"))
if strips:
    W = max(s.size[0] for s in strips)
    H = sum(s.size[1] for s in strips)
    sheet = Image.new("RGB", (W, H), (0, 0, 0))
    y = 0
    for s in strips:
        sheet.paste(s, (0, y))
        y += s.size[1]
    sheet.save(os.path.join(d, "_sheet.png"))
