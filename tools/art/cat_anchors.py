#!/usr/bin/env python3
"""Per-frame anatomy for the HD cat, and the nanotech map it drives.

Each frame of every cat sheet (assets/sprites/cat/cat_*.png, 75x75 frames)
is analysed on its own silhouette, so new frames or sheets only need a rerun:

  eye    the yellow eye pixels (#e8d82a); the rightmost cluster in a front
         view; a blink borrows the previous frame's eye
  ear    the ear tip above the eye (the back edge is where the implant sits)
  tail   the thin limb left after a radius-2 morphological opening that is
         not a leg; base, tip and centreline
  back   top contour of the torso between the tail base and the neck
  feet   the lowest interior runs

The vein network is a tree grown inside the fur (never on the outline): the
first branches run from each foot to the eye, then the farthest interior
point is joined to the tree until no fur pixel is more than SPACING px from
a vein. Routing is Dijkstra on (pixel, heading) with turn penalties, so the
traces are long straight runs with 45 degree jogs: circuit-like, one pixel
wide. Each frame is biased toward the previous frame's veins so the network
holds still while the cat breathes.

Outputs
  assets/sprites/cat/augments/anchors.json   per sheet, per frame anchors
  assets/fx/cat_nano/veins.json              per frame: the vein tree as
      chains ({"p" points, "a" arrival, "t" trunk}), the silhouette's row
      spans, bbox, eye and ear, for the HD layer (scripts/fx/nano_hd.gd)
  assets/fx/cat_nano/nano_<sheet>.png        same layout as the cat sheet:
      R  height inside the frame's opaque bounds (0 = feet, 255 = top)
      G  vein arrival 1..255 (0 = no vein): when a vein pixel lights as the
         flood climbs from the feet; the eye is always 255 (last)
      B  0 none, 100 branch vein, 170 trunk vein (feet to eye), 255 eye
      A  255 silhouette, 128 the one-pixel coat ring around it, 0 outside

Usage: cat_anchors.py [--debug sheet.png]
"""
import heapq
import json
import sys
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import cat_hd  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
CAT_DIR = ROOT / "assets" / "sprites" / "cat"
NANO_DIR = ROOT / "assets" / "fx" / "cat_nano"
ANCHORS = CAT_DIR / "augments" / "anchors.json"
VEINS = NANO_DIR / "veins.json"
FRAME = cat_hd.FRAME
SPACING = 4          # max fur distance from a vein, px (the cat is 1.5x its 1x art)
MAX_LEAVES = 14

INK = (0x16, 0x16, 0x30)   # the HD cat's outline (palette.md cat_outline)
EYE = (0xE8, 0xD8, 0x2A)

N4 = [(1, 0), (-1, 0), (0, 1), (0, -1)]
N8 = N4 + [(1, 1), (1, -1), (-1, 1), (-1, -1)]
DIRS = [(1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1), (1, -1)]
TURN_COST = (0.0, 0.7, 1.6)  # 0, 45 and 90 degree turns; sharper is forbidden


# ---- small morphology kit (numpy only) -----------------------------------

def shift(m, dx, dy):
    """out[y, x] = m[y - dy, x - dx], zero filled."""
    out = np.zeros_like(m)
    h, w = m.shape
    out[max(dy, 0):h + min(dy, 0), max(dx, 0):w + min(dx, 0)] = \
        m[max(-dy, 0):h + min(-dy, 0), max(-dx, 0):w + min(-dx, 0)]
    return out


def dilate(m, nb=N8):
    r = m.copy()
    for dx, dy in nb:
        r |= shift(m, dx, dy)
    return r


def erode(m, nb=N8):
    r = m.copy()
    for dx, dy in nb:
        r &= shift(m, dx, dy)
    return r


def components(m, nb=N8):
    h, w = m.shape
    seen = np.zeros(m.shape, bool)
    comps = []
    for y, x in zip(*np.nonzero(m)):
        if seen[y, x]:
            continue
        seen[y, x] = True
        stack, pts = [(x, y)], []
        while stack:
            cx, cy = stack.pop()
            pts.append((cx, cy))
            for dx, dy in nb:
                nx, ny = cx + dx, cy + dy
                if 0 <= nx < w and 0 <= ny < h and m[ny, nx] and not seen[ny, nx]:
                    seen[ny, nx] = True
                    stack.append((nx, ny))
        comps.append(pts)
    return comps


def geodesic(mask, sources, nb=N8):
    """BFS step distance inside `mask` from the (x, y) sources."""
    h, w = mask.shape
    dist = np.full(mask.shape, np.inf)
    q = deque()
    for x, y in sources:
        if mask[y, x] and dist[y, x] > 0:
            dist[y, x] = 0
            q.append((x, y))
    while q:
        x, y = q.popleft()
        for dx, dy in nb:
            nx, ny = x + dx, y + dy
            if 0 <= nx < w and 0 <= ny < h and mask[ny, nx] and dist[ny, nx] == np.inf:
                dist[ny, nx] = dist[y, x] + 1
                q.append((nx, ny))
    return dist


# ---- anatomy ---------------------------------------------------------------

def masks(rgba):
    a = rgba[..., 3] > 0
    rgb = rgba[..., :3]
    ink = a & np.all(rgb == INK, axis=2)
    eye = a & np.all(rgb == EYE, axis=2)
    return a, ink, eye, a & ~ink


def find_eye(eye, inner, prev):
    clusters = components(eye)
    if clusters:
        best = max(clusters, key=lambda c: sum(p[0] for p in c) / len(c))
        view = "front" if len(clusters) > 1 else "side"
        return best, view, False
    # Blink: borrow the previous frame's eye if it still lands on fur.
    if prev and prev.get("eye_px"):
        px = [tuple(p) for p in prev["eye_px"] if inner[p[1], p[0]]]
        if px:
            return px, prev["view"], True
    return None, "none", False


def find_ear(a, inner, eye_px, view, bbox):
    if eye_px:
        ex = round(sum(p[0] for p in eye_px) / len(eye_px))
        ey = min(p[1] for p in eye_px)
        cols = range(ex - 2, ex + 5) if view == "front" else range(ex - 5, ex + 3)
    else:
        ex, ey = bbox[2], bbox[3]
        cols = range((bbox[0] + bbox[2]) // 2, bbox[2] + 1)
    best = None
    for x in cols:
        ys = np.nonzero(a[:ey, x])[0] if 0 <= x < a.shape[1] else []
        if len(ys) and (best is None or ys[0] < best[1]):
            best = (x, int(ys[0]))
    if best is None:
        return None
    x, y = best
    for dy in range(1, 4):
        for dx in (0, -1, 1):
            if inner[y + dy, x + dx]:
                return (x + dx, y + dy)
    return None


def find_tail(a, inner, bbox, eye_px):
    core = erode(erode(a))
    body = dilate(dilate(core)) & a
    thin = a & ~body
    ex = sum(p[0] for p in eye_px) / len(eye_px) if eye_px else None
    best = None
    for c in components(thin):
        if len(c) < 6:
            continue
        xs = [p[0] for p in c]
        ys = [p[1] for p in c]
        w, h = max(xs) - min(xs) + 1, max(ys) - min(ys) + 1
        if max(ys) >= bbox[3] - 1 and h >= w:
            continue  # a leg
        if ex is not None and sum(xs) / len(xs) > ex - 3:
            continue  # tails trail behind the head
        if best is None or len(c) > len(best):
            best = c
    if best is None:
        return None
    tail = np.zeros_like(a)
    for x, y in best:
        tail[y, x] = True
    touch = tail & dilate(body)
    tys, txs = np.nonzero(touch)
    if not len(txs):
        return None
    cx, cy = txs.mean(), tys.mean()
    base = min(zip(txs, tys), key=lambda p: (p[0] - cx) ** 2 + (p[1] - cy) ** 2)
    base = (int(base[0]), int(base[1]))
    walk = tail & inner if (tail & inner)[base[1], base[0]] else tail
    dist = geodesic(walk, [base])
    if not np.isfinite(dist).any() or dist[np.isfinite(dist)].max() < 4:
        walk = tail
        dist = geodesic(walk, [base])
    fin = np.where(np.isfinite(dist), dist, -1)
    ty, tx = np.unravel_index(np.argmax(fin), fin.shape)
    # Centreline: walk downhill from the tip to the base.
    line = [(int(tx), int(ty))]
    while dist[line[-1][1], line[-1][0]] > 0:
        x, y = line[-1]
        nxt = min(((x + dx, y + dy) for dx, dy in N8
                   if walk[y + dy, x + dx]), key=lambda p: (dist[p[1], p[0]], abs(p[0] - x) + abs(p[1] - y)))
        line.append(nxt)
    line.reverse()  # base first
    return {"mask": tail, "base": base, "tip": (int(tx), int(ty)), "line": line}


def find_back(a, tail, eye_px, view):
    """Top contour (outline row) of the torso, as {x: y}."""
    if view != "side" or tail is None or not eye_px:
        return {}
    ex = min(p[0] for p in eye_px)
    x0 = max(tail["base"][0], min(p[0] for p in tail["line"][:4])) + 2
    x1 = ex - 7
    body = a & ~dilate(tail["mask"])
    back = {}
    for x in range(x0, x1 + 1):
        ys = np.nonzero(body[:, x])[0]
        if len(ys):
            back[x] = int(ys[0])
    return back


def find_feet(inner, bbox):
    low = inner.copy()
    low[:bbox[3] - 2, :] = False
    leaves = []
    for c in components(low, N4):
        my = max(p[1] for p in c)
        bottom = sorted(int(p[0]) for p in c if p[1] == my)
        leaves.append((bottom[len(bottom) // 2], int(my)))
    return sorted(leaves)


# ---- veins -------------------------------------------------------------------

def route(start, tree, allowed, cost, body):
    """Cheapest heading-aware path from start into the tree (inclusive).
    Diagonal steps may cut a corner only where the corner is still cat
    (`body`), so a one-pixel tail joined at a diagonal stays reachable."""
    h, w = allowed.shape
    sx, sy = start
    heap = [(0.0, sx, sy, -1)]
    best = {(sx, sy, -1): 0.0}
    parent = {}
    while heap:
        c, x, y, d = heapq.heappop(heap)
        if best.get((x, y, d), np.inf) < c:
            continue
        if tree[y, x] and (x, y) != start:
            path, key = [], (x, y, d)
            while key in parent or key == (sx, sy, -1):
                path.append((key[0], key[1]))
                if key == (sx, sy, -1):
                    break
                key = parent[key]
            return path[::-1]
        for nd, (dx, dy) in enumerate(DIRS):
            tc = 0.0
            if d >= 0:
                turn = min((nd - d) % 8, (d - nd) % 8)
                if turn > 2:
                    continue
                tc = TURN_COST[turn]
            nx, ny = x + dx, y + dy
            if not (0 <= nx < w and 0 <= ny < h) or not allowed[ny, nx]:
                continue
            if dx and dy and not (body[y, nx] or body[ny, x]):
                continue
            nc = c + (1.0 if not (dx and dy) else 1.414) * cost[ny, nx] + tc
            key = (nx, ny, nd)
            if nc < best.get(key, np.inf):
                best[key] = nc
                parent[key] = (x, y, d)
                heapq.heappush(heap, (nc, nx, ny, nd))
    return None


def grow_veins(inner, body, eye_px, feet, prev_veins):
    h, w = inner.shape
    tree = np.zeros_like(inner)
    for x, y in eye_px:
        tree[y, x] = True
    edges = {p: set() for p in eye_px}
    for i, p in enumerate(eye_px):
        for q in eye_px[i + 1:]:
            if abs(p[0] - q[0]) <= 1 and abs(p[1] - q[1]) <= 1:
                edges[p].add(q)
                edges[q].add(p)
    # Fur next to the outline costs more, so traces keep a pixel of fur
    # between them and the ink; the previous frame's veins cost less.
    edge = inner & ~erode(inner, N4)
    base = np.where(edge, 1.8, 1.0)
    if prev_veins is not None:
        base = np.where(prev_veins & inner, base * 0.55, base)
    trunk = set()

    def add(path, is_trunk):
        for p, q in zip(path, path[1:]):
            edges.setdefault(p, set()).add(q)
            edges.setdefault(q, set()).add(p)
        for p in path:
            tree[p[1], p[0]] = True
            if is_trunk:
                trunk.add(p)

    def cost_now():
        near = dilate(tree) & ~tree
        return base + np.where(near, 1.4, 0.0)

    for f in sorted(feet, key=lambda p: -abs(p[0] - eye_px[0][0]) - abs(p[1] - eye_px[0][1])):
        if tree[f[1], f[0]]:
            continue
        path = route(f, tree, inner, cost_now(), body)
        if path:
            add(path, True)
    skip = np.zeros_like(inner)
    leaves = 0
    for _ in range(MAX_LEAVES * 3):
        dist = geodesic(inner, list(zip(*np.nonzero(tree)[::-1])))
        dist = np.where(np.isfinite(dist) & ~skip, dist, -1)
        if dist.max() < SPACING or leaves >= MAX_LEAVES:
            break
        y, x = np.unravel_index(np.argmax(dist), dist.shape)
        path = route((int(x), int(y)), tree, inner, cost_now(), body)
        if not path:
            skip[max(y - 1, 0):y + 2, max(x - 1, 0):x + 2] = True
            continue
        add(path, False)
        leaves += 1
    # Arrival: flood from the feet along the tree; the eye lights last.
    df = {}
    heap = [(0.0, f) for f in feet if f in edges]
    for _, f in heap:
        df[f] = 0.0
    heapq.heapify(heap)
    while heap:
        c, p = heapq.heappop(heap)
        if df.get(p, np.inf) < c:
            continue
        for q in edges.get(p, ()):
            nc = c + (1.414 if q[0] != p[0] and q[1] != p[1] else 1.0)
            if nc < df.get(q, np.inf):
                df[q] = nc
                heapq.heappush(heap, (nc, q))
    dmax = max([v for p, v in df.items() if p not in eye_px] + [1.0])
    arrival = {}
    for p in edges:
        if p in eye_px:
            arrival[p] = 1.0
        else:
            arrival[p] = 0.02 + 0.93 * min(df.get(p, dmax) / dmax, 1.0)
    return tree, arrival, trunk, edges


# ---- per frame ---------------------------------------------------------------

def analyse(rgba, prev):
    a, ink, eye, inner = masks(rgba)
    ys, xs = np.nonzero(a)
    bbox = (int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max()))
    eye_px, view, blink = find_eye(eye, inner, prev)
    ear = find_ear(a, inner, eye_px, view, bbox)
    tail = find_tail(a, inner, bbox, eye_px if view == "side" else None)
    back = find_back(a, tail, eye_px, view)
    feet = find_feet(inner, bbox)
    root = eye_px
    if not root:
        # No eye (back view, asleep): the veins converge on the ear base.
        root = [ear] if ear else [feet[-1]]
    prev_veins = prev["_veins"] if prev else None
    veins, arrival, trunk, edges = grow_veins(inner, a, [tuple(map(int, p)) for p in root], feet, prev_veins)
    info = {
        "bbox": list(bbox),
        "view": view,
        "eye": [round(sum(p[0] for p in eye_px) / len(eye_px) + 0.5, 1),
                round(sum(p[1] for p in eye_px) / len(eye_px) + 0.5, 1)] if eye_px else None,
        "eye_px": [list(map(int, p)) for p in eye_px] if eye_px and not blink else [],
        "ear": list(ear) if ear else None,
        "tail_base": list(tail["base"]) if tail else None,
        "tail_tip": list(tail["tip"]) if tail else None,
        "tail_line": [list(p) for p in tail["line"]] if tail else [],
        "back": [[x, y] for x, y in sorted(back.items())],
        "feet": [list(f) for f in feet],
        "_veins": veins,
        "_arrival": arrival,
        "_trunk": trunk,
        "_edges": edges,
        "_masks": (a, ink, eye, inner),
    }
    if blink:
        info["eye_px_virtual"] = [list(map(int, p)) for p in eye_px]
    return info


def vein_chains(info):
    """The vein tree as chains between junctions and ends, each ordered so
    arrival rises along it: [{"p": [[x, y]...], "a": [...], "t": trunk}]."""
    edges, arrival, trunk = info["_edges"], info["_arrival"], info["_trunk"]
    deg = {p: len(n) for p, n in edges.items()}
    seen = set()
    chains = []
    for start in edges:
        if deg[start] == 2:
            continue
        for nxt in edges[start]:
            if (start, nxt) in seen:
                continue
            line = [start, nxt]
            seen.update({(start, nxt), (nxt, start)})
            prev, cur = start, nxt
            while deg.get(cur, 0) == 2:
                step = [q for q in edges[cur] if q != prev][0]
                if (cur, step) in seen:
                    break
                seen.update({(cur, step), (step, cur)})
                line.append(step)
                prev, cur = cur, step
            chains.append(line)
    out = []
    for line in chains:
        if arrival.get(line[0], 0) > arrival.get(line[-1], 0):
            line.reverse()
        inner = line[1:-1] or line
        out.append({
            "p": [[int(x), int(y)] for x, y in line],
            "a": [round(arrival.get(q, 0.0), 3) for q in line],
            "t": int(all(q in trunk for q in inner)),
        })
    return out


def row_spans(info):
    """Outer silhouette extent per row of the frame's bounds: [x0, x1]."""
    a = info["_masks"][0]
    x0, y0, x1, y1 = info["bbox"]
    rows = []
    for y in range(y0, y1 + 1):
        xs = np.nonzero(a[y])[0]
        rows.append([int(xs.min()), int(xs.max())] if len(xs) else [])
    return rows


def nano_frame(info):
    a, _ink, eye, _inner = info["_masks"]
    x0, y0, x1, y1 = info["bbox"]
    out = np.zeros((FRAME, FRAME, 4), np.uint8)
    ring = dilate(a, N4) & ~a
    rows = np.arange(FRAME, dtype=float)[:, None]
    h = np.clip((y1 - rows) / max(y1 - y0, 1), 0.0, 1.0)
    coat = a | ring
    out[..., 0] = np.where(coat, np.round(h * 255), 0).astype(np.uint8)
    out[..., 3] = np.where(a, 255, np.where(ring, 128, 0)).astype(np.uint8)
    for (x, y), t in info["_arrival"].items():
        out[y, x, 1] = 1 + round(t * 254)
        out[y, x, 2] = 170 if (x, y) in info["_trunk"] else 100
    for y, x in zip(*np.nonzero(eye)):
        out[y, x, 1] = 255
        out[y, x, 2] = 255
    return out


def sheets():
    for path in sorted(CAT_DIR.glob("cat_*.png")):
        name = path.stem[4:]
        img = np.asarray(Image.open(path).convert("RGBA"))
        if img.shape[0] != FRAME or img.shape[1] % FRAME:
            continue
        yield name, img


def run(debug=None):
    NANO_DIR.mkdir(parents=True, exist_ok=True)
    ANCHORS.parent.mkdir(parents=True, exist_ok=True)
    data = {"frame": FRAME, "sheets": {}}
    veins = {"frame": FRAME, "sheets": {}}
    debug_rows = []
    for name, img in sheets():
        n = img.shape[1] // FRAME
        frames = [img[:, i * FRAME:(i + 1) * FRAME] for i in range(n)]
        # Two passes over the loop so frame 0 is also biased by the last
        # frame: the network is stable across the wrap as well.
        prev = None
        infos = []
        for p in range(2 if n > 1 else 1):
            infos = []
            for f in frames:
                prev = analyse(f, prev)
                infos.append(prev)
        nano = np.zeros((FRAME, n * FRAME, 4), np.uint8)
        for i, info in enumerate(infos):
            nano[:, i * FRAME:(i + 1) * FRAME] = nano_frame(info)
        Image.fromarray(nano).save(NANO_DIR / f"nano_{name}.png")
        data["sheets"][name] = [{k: v for k, v in info.items() if not k.startswith("_")} for info in infos]
        veins["sheets"][name] = [{
            "c": vein_chains(info), "bbox": info["bbox"], "rows": row_spans(info),
            "eye": info["eye"], "ear": info["ear"],
        } for info in infos]
        debug_rows.append((name, frames, infos))
        print(f"{name}: {n} frames, views {[i['view'][0] for i in infos]}, "
              f"tail {sum(1 for i in infos if i['tail_base'])}/{n}, back {sum(1 for i in infos if i['back'])}/{n}")
    ANCHORS.write_text(json.dumps(data, separators=(",", ":")) + "\n")
    VEINS.write_text(json.dumps(veins, separators=(",", ":")) + "\n")
    if debug:
        write_debug(debug_rows, debug)


def write_debug(rows, out_path, z=4):
    """Contact sheet: veins coloured by arrival (blue early, green late),
    eye red, ear magenta, tail base/tip orange, back contour white."""
    cols = max(len(r[1]) for r in rows)
    cell = 48
    sheet = Image.new("RGBA", (cols * cell, len(rows) * cell), (40, 44, 60, 255))
    for r, (name, frames, infos) in enumerate(rows):
        for c, (f, info) in enumerate(zip(frames, infos)):
            fr = f.copy()
            fr[..., :3] = (fr[..., :3] * 0.45).astype(np.uint8)
            for (x, y), t in info["_arrival"].items():
                fr[y, x] = (int(40 + 60 * t), int(90 + 160 * t), int(255 - 120 * t), 255)
            for x, y in info["back"]:
                fr[y, x] = (255, 255, 255, 255)
            for key, col in (("ear", (255, 0, 255)), ("tail_base", (255, 140, 0)), ("tail_tip", (255, 200, 0))):
                if info[key]:
                    x, y = info[key]
                    fr[y, x] = (*col, 255)
            for x, y in info["eye_px"]:
                fr[y, x] = (255, 40, 40, 255)
            x0, y0 = 13, 16
            sheet.alpha_composite(Image.fromarray(fr).crop((x0, y0, x0 + cell, y0 + cell)), (c * cell, r * cell))
    sheet.resize((sheet.width * z, sheet.height * z), Image.NEAREST).save(out_path)


if __name__ == "__main__":
    dbg = None
    if "--debug" in sys.argv:
        dbg = sys.argv[sys.argv.index("--debug") + 1]
    run(dbg)
