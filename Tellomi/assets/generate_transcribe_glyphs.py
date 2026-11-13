#!/usr/bin/env python3
"""Rebuild the transcription-letter Lottie files from Noto Sans Medium skeletons.

The English button draws an arrow plus a stroked "A", then trims the letter away
while a separate chevron grows into the collapse icon. Variants keep every layer
and group name. The letter centerlines are the medial axis of Noto Sans Medium
(Simplified Chinese, Japanese, Korean, Arabic, Hebrew, Devanagari, Thai), fitted
into the A's box and stroked at the A's width. The collapse chevron is the
original path; it is not resampled (a dense resample hatches the left leg).

Fonts are read from $TELLOMI_NOTO_FONTS (default /tmp/fonts):
sc-medium.ttf, jp-medium.ttf, kr-medium.ttf, ar-medium.ttf,
he-medium.ttf, hi-medium.ttf, th-medium.ttf. They are Noto Sans at weight 500.
"""

import json
import math
import os
import re
import shutil
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
ANIM = ROOT / "submodules/TelegramUI/Resources/Animations"
LOCKED = ROOT / "submodules/TelegramUI/Images.xcassets/Chat/Message/TranscriptionLocked.imageset/lockedaudiototext.pdf"
ASSETS = ROOT / "Tellomi/assets"
FONT_DIR = Path(os.environ.get("TELLOMI_NOTO_FONTS", "/tmp/fonts"))

# A's centerline box in the 300x300 Lottie canvas, y down.
BOX = (163.3, 100.4, 70.0, 89.6)
STROKE = 13.3
# Drop medial-axis spikes shorter than this many stroke-radii.
SPUR = 1.6
# These three come from the Android client's Noto centerlines. The others are
# this repo's own skeletons, which read more clearly for those letters.
ANDROID_CODES = {"ar", "he", "th"}
OFFS = [(-1, 0), (-1, 1), (0, 1), (1, 1), (1, 0), (1, -1), (0, -1), (-1, -1)]

GLYPHS = [
    ("zh", "文", "sc-medium.ttf"),
    ("ja", "あ", "jp-medium.ttf"),
    ("ko", "가", "kr-medium.ttf"),
    ("ar", "ع", "ar-medium.ttf"),
    ("fa", "ا", "ar-medium.ttf"),
    ("he", "א", "he-medium.ttf"),
    ("hi", "अ", "hi-medium.ttf"),
    ("th", "ก", "th-medium.ttf"),
]


def render_mask(font_path, ch, size=300):
    font = ImageFont.truetype(font_path, size)
    probe = Image.new("L", (size * 3, size * 3), 0)
    bbox = ImageDraw.Draw(probe).textbbox((0, 0), ch, font=font)
    pad = 4
    w, h = max(bbox[2] - bbox[0], 1), max(bbox[3] - bbox[1], 1)
    im = Image.new("L", (w + pad * 2, h + pad * 2), 0)
    ImageDraw.Draw(im).text((pad - bbox[0], pad - bbox[1]), ch, font=font, fill=255)
    arr = np.array(im) > 140
    ys, xs = np.where(arr)
    if len(ys) == 0:
        raise SystemExit("font drew nothing for " + ch)
    return arr[ys.min():ys.max() + 1, xs.min():xs.max() + 1]


def zhang_suen(img):
    img = img.astype(np.uint8).copy()
    h, w = img.shape
    changed = True
    while changed:
        changed = False
        for step in (0, 1):
            p2 = img[0:h - 2, 1:w - 1]
            p3 = img[0:h - 2, 2:w]
            p4 = img[1:h - 1, 2:w]
            p5 = img[2:h, 2:w]
            p6 = img[2:h, 1:w - 1]
            p7 = img[2:h, 0:w - 2]
            p8 = img[1:h - 1, 0:w - 2]
            p9 = img[0:h - 2, 0:w - 2]
            center = img[1:h - 1, 1:w - 1]
            nb = np.stack([p2, p3, p4, p5, p6, p7, p8, p9], 0)
            count = nb.sum(0)
            seq = np.concatenate([nb, nb[:1]], 0)
            trans = ((seq[:-1] == 0) & (seq[1:] == 1)).sum(0)
            cond = (center == 1) & (count >= 2) & (count <= 6) & (trans == 1)
            if step == 0:
                cond = cond & (p2 * p4 * p6 == 0) & (p4 * p6 * p8 == 0)
            else:
                cond = cond & (p2 * p4 * p8 == 0) & (p2 * p6 * p8 == 0)
            ys, xs = np.where(cond)
            if len(ys):
                changed = True
                img[ys + 1, xs + 1] = 0
    return img.astype(bool)


def transitions(present):
    seq = present + [present[0]]
    return sum(1 for i in range(8) if (not seq[i]) and seq[i + 1])


def rdp(pts, eps):
    if len(pts) < 3:
        return pts

    def dist(p, a, b):
        ax, ay = a
        bx, by = b
        px, py = p
        vx, vy = bx - ax, by - ay
        length = vx * vx + vy * vy or 1.0
        t = max(0.0, min(1.0, ((px - ax) * vx + (py - ay) * vy) / length))
        return math.hypot(px - (ax + t * vx), py - (ay + t * vy))

    def rec(points):
        if len(points) < 3:
            return points
        farthest, index = 0.0, 0
        for i in range(1, len(points) - 1):
            d = dist(points[i], points[0], points[-1])
            if d > farthest:
                farthest, index = d, i
        if farthest > eps:
            return rec(points[:index + 1])[:-1] + rec(points[index:])
        return [points[0], points[-1]]

    return rec(pts)


def chamfer(mask):
    h, w = mask.shape
    dist = np.where(mask, 10 ** 9, 0).astype(np.int32)
    for y in range(h):
        for x in range(w):
            if dist[y, x] == 0:
                continue
            v = dist[y, x]
            if y:
                v = min(v, dist[y - 1, x] + 1)
            if x:
                v = min(v, dist[y, x - 1] + 1)
            dist[y, x] = v
    for y in range(h - 1, -1, -1):
        for x in range(w - 1, -1, -1):
            if dist[y, x] == 0:
                continue
            v = dist[y, x]
            if y + 1 < h:
                v = min(v, dist[y + 1, x] + 1)
            if x + 1 < w:
                v = min(v, dist[y, x + 1] + 1)
            dist[y, x] = v
    return dist


def skeleton_strokes(font_path, ch):
    """Medial-axis strokes of one glyph, in the mask's pixel space (x right, y down).

    Segments run from junction to junction. Pieces shorter than SPUR stroke-radii
    are the spikes the medial axis grows into outline corners, and are dropped.
    """
    mask = render_mask(font_path, ch)
    skel = zhang_suen(mask)
    pixels = set(map(tuple, np.argwhere(skel)))

    def neighbors(p):
        y, x = p
        return [(y + dy, x + dx) for dy, dx in OFFS if (y + dy, x + dx) in pixels]

    stops = set()
    for p in pixels:
        y, x = p
        present = [(y + dy, x + dx) in pixels for dy, dx in OFFS]
        count = sum(present)
        if count <= 1 or transitions(present) >= 3:
            stops.add(p)
    used = set()
    segments = []

    def key(a, b):
        return (a, b) if a < b else (b, a)

    for start in list(stops):
        for nxt in neighbors(start):
            if key(start, nxt) in used:
                continue
            path = [start, nxt]
            used.add(key(start, nxt))
            prev, cur = start, nxt
            while cur not in stops:
                options = [n for n in neighbors(cur) if n != prev and key(cur, n) not in used]
                if not options:
                    break
                nxt = options[0]
                used.add(key(cur, nxt))
                path.append(nxt)
                prev, cur = cur, nxt
            segments.append(path)
    dist = chamfer(mask)
    radius = float(np.median([dist[p] for p in pixels])) or 6.0
    strokes = []
    for path in segments:
        if len(path) < radius * SPUR:
            continue
        simple = rdp([(p[1], p[0]) for p in path], 2.2)
        if len(simple) >= 2:
            strokes.append(simple)
    if not strokes:
        raise SystemExit("no strokes for " + ch)
    return strokes


def fit_box(strokes):
    """Uniform-fit strokes into the A's centerline box.

    Each stroke is ``{"v": [[x, y], ...], "i": [...], "o": [...]}`` or a bare
    point list. Handles are offsets and scale with the points.
    """
    normalized = []
    for stroke in strokes:
        if isinstance(stroke, dict):
            normalized.append(stroke)
        else:
            normalized.append({"v": [list(p) for p in stroke], "i": None, "o": None})
    xs = [p[0] for s in normalized for p in s["v"]]
    ys = [p[1] for s in normalized for p in s["v"]]
    minx, maxx, miny, maxy = min(xs), max(xs), min(ys), max(ys)
    bw, bh = max(maxx - minx, 1.0), max(maxy - miny, 1.0)
    x0, y0, tw, th = BOX
    scale = min(tw / bw, th / bh)
    ox = x0 + (tw - bw * scale) / 2.0
    oy = y0 + (th - bh * scale) / 2.0

    def pt(x, y):
        return [round(ox + (x - minx) * scale, 3), round(oy + (y - miny) * scale, 3)]

    def handle(pair):
        if not pair:
            return [0, 0]
        return [round(pair[0] * scale, 3), round(pair[1] * scale, 3)]

    fitted = []
    for stroke in normalized:
        n = len(stroke["v"])
        inn = stroke.get("i") or [[0, 0]] * n
        out = stroke.get("o") or [[0, 0]] * n
        fitted.append({
            "v": [pt(x, y) for x, y in stroke["v"]],
            "i": [handle(h) for h in inn],
            "o": [handle(h) for h in out],
        })
    return fitted


def android_letter(code):
    """Group 3 plus Group 4 at frame 19, in Android layer space (y down)."""
    path = ASSETS / "android-transcribe" / ("transcribe_in_" + code + ".json")
    data = json.loads(path.read_text())
    strokes = []
    for group in data["layers"][0]["shapes"]:
        if group.get("nm") not in ("Group 3", "Group 4"):
            continue
        origin = next(it for it in group["it"] if it["ty"] == "tr")["p"]["k"]
        for item in group["it"]:
            if item.get("ty") != "sh":
                continue
            raw = item["ks"]["k"]
            if isinstance(raw, list):
                body = raw[-1]["s"][0]
            else:
                body = raw
            strokes.append({
                "v": [[v[0] + origin[0], v[1] + origin[1]] for v in body["v"]],
                "i": body.get("i"),
                "o": body.get("o"),
            })
    return strokes


def shape(points):
    zeros = [[0, 0] for _ in points]
    return {"i": zeros, "o": zeros, "v": points, "c": False}


def path_item(points, inn=None, out=None):
    zeros = [[0, 0] for _ in points]
    body = {
        "i": inn or zeros,
        "o": out or zeros,
        "v": points,
        "c": False,
    }
    return {
        "ind": 0, "ty": "sh", "ix": 1,
        "ks": {"a": 0, "k": body, "ix": 2},
        "nm": "Path 1", "mn": "ADBE Vector Shape - Group", "hd": False,
    }


def replace_paths(group, strokes):
    items = group["it"]
    kept = [it for it in items if it.get("ty") != "sh"]
    for it in kept:
        if it.get("ty") == "st":
            it["lj"] = 2
        if it.get("ty") == "tr":
            it["p"] = {"a": 0, "k": [0, 0], "ix": 2}
    group["it"] = [path_item(s["v"], s.get("i"), s.get("o")) for s in strokes] + kept


def hide_group(group):
    for it in group["it"]:
        if it.get("ty") == "st":
            it["w"] = {"a": 0, "k": 0, "ix": it.get("w", {}).get("ix", 5)}


def fade_chevron(group):
    """Keep the original chevron vertices. Hide it by the end of the morph."""
    stroke = next(it for it in group["it"] if it.get("ty") == "st")
    widths = stroke.get("w", {}).get("k")
    if isinstance(widths, list) and widths and isinstance(widths[-1], dict):
        widths[-1]["s"] = [0]


def build_lottie(kind, suffix, strokes):
    src = "voiceToText.json" if kind == "voice" else "textToVoice.json"
    data = json.loads((ANIM / src).read_text())
    if kind == "voice":
        groups = {g["nm"]: g for g in data["layers"][0]["shapes"]}
        replace_paths(groups["Group 2"], strokes)
        hide_group(groups["Group 1"])
    else:
        morph_layer = next(layer for layer in data["layers"] if layer["nm"] == "Artboard Copy Outlines")
        trim_layer = next(layer for layer in data["layers"] if layer["nm"] == "Artboard Copy 2 Outlines")
        morph = next(g for g in morph_layer["shapes"] if g["nm"] == "Group 1")
        cross = next(g for g in trim_layer["shapes"] if g["nm"] == "Group 1")
        fade_chevron(morph)
        replace_paths(cross, strokes)
    dest = ANIM / (("voiceToText" if kind == "voice" else "textToVoice") + suffix + ".json")
    dest.write_text(json.dumps(data, ensure_ascii=False, separators=(",", ":")))


def write_path_files(glyphs):
    common = {
        "coordinateSpace": "lottie-canvas",
        "yAxis": "down",
        "unmirrored": True,
        "canvas": [300, 300],
        "strokeWidth": STROKE,
        "lineCap": "round",
        "lineJoin": "round",
        "letterBox": {"x": BOX[0], "y": BOX[1], "width": BOX[2], "height": BOX[3]},
        "source": "Medial axis of Noto Sans Medium, fitted to the transcription A.",
        "note": "Centerlines. Same paths feed the iOS Lottie files. Draw unmirrored in RTL.",
    }
    (ASSETS / "transcribe-glyph-paths.json").write_text(
        json.dumps({"glyphs": glyphs, **common}, ensure_ascii=False, indent=2) + "\n"
    )
    (ASSETS / "transcribe-wen-paths.json").write_text(
        json.dumps({"character": "文", "language": "zh", "strokes": glyphs["zh"]["strokes"], **common}, ensure_ascii=False, indent=2) + "\n"
    )


def parse_pdf_fills(pdf_path):
    stream = Path(pdf_path).read_text(errors="replace").split("stream", 1)[1].split("endstream", 1)[0]
    ctm = [1, 0, 0, 1, 0, 0]
    stack = []
    fills, subpaths, path = [], [], []
    start = cur = None

    def mul(m, x, y):
        return (m[0] * x + m[2] * y + m[4], m[1] * x + m[3] * y + m[5])

    def bez(p0, p1, p2, p3, t):
        u = 1 - t
        return (
            u*u*u*p0[0] + 3*u*u*t*p1[0] + 3*u*t*t*p2[0] + t*t*t*p3[0],
            u*u*u*p0[1] + 3*u*u*t*p1[1] + 3*u*t*t*p2[1] + t*t*t*p3[1],
        )

    tokens = re.findall(r"[A-Za-z*]+|[-+]?\d*\.?\d+(?:[eE][-+]?\d+)?", stream)
    i, nums = 0, []
    while i < len(tokens):
        tok = tokens[i]
        if re.fullmatch(r"[-+]?\d*\.?\d+(?:[eE][-+]?\d+)?", tok):
            nums.append(float(tok))
            i += 1
            continue
        op = tok
        if op == "q":
            stack.append(ctm[:])
        elif op == "Q":
            ctm = stack.pop()
        elif op == "cm" and len(nums) >= 6:
            a, b, c, d, e, f = nums[-6:]
            ctm = [a*ctm[0]+b*ctm[2], a*ctm[1]+b*ctm[3], c*ctm[0]+d*ctm[2], c*ctm[1]+d*ctm[3], e*ctm[0]+f*ctm[2]+ctm[4], e*ctm[1]+f*ctm[3]+ctm[5]]
        elif op == "m" and len(nums) >= 2:
            if path:
                subpaths.append(path)
            cur = mul(ctm, nums[-2], nums[-1])
            start, path = cur, [cur]
        elif op == "l" and len(nums) >= 2:
            cur = mul(ctm, nums[-2], nums[-1])
            path.append(cur)
        elif op == "c" and len(nums) >= 6:
            x1, y1, x2, y2, x3, y3 = nums[-6:]
            p0, p1, p2, p3 = cur, mul(ctm, x1, y1), mul(ctm, x2, y2), mul(ctm, x3, y3)
            for step in range(1, 12):
                path.append(bez(p0, p1, p2, p3, step / 11))
            cur = p3
        elif op == "h" and start is not None:
            path.append(start)
        elif op in ("f", "f*"):
            if path:
                subpaths.append(path)
                path = []
            fills.append(subpaths)
            subpaths, start = [], None
        elif op == "n":
            path, subpaths, start = [], [], None
        nums, i = [], i + 1
    return fills


def pdf_strokes(strokes):
    """Map Lottie-canvas strokes into the locked icon's A ink box. PDF y is up."""
    ink = (13.84, 10.34, 20.49, 20.67)
    ink_h = ink[3] - ink[1]
    sw = STROKE / BOX[3] * ink_h
    inset = sw / 2.0
    box = (ink[0] + inset, ink[1] + inset, ink[2] - inset, ink[3] - inset)
    bw, bh = box[2] - box[0], box[3] - box[1]
    lines = ["q", "0 0 0 RG", "{:.3f} w".format(sw), "1 J", "1 j"]
    x0, y0, tw, th = BOX
    for stroke in strokes:
        pts = []
        for x, y in stroke["v"]:
            u = (x - x0) / tw
            v = (y - y0) / th
            pts.append((box[0] + u * bw, box[3] - v * bh))
        lines.append("{:.3f} {:.3f} m".format(pts[0][0], pts[0][1]))
        for px, py in pts[1:]:
            lines.append("{:.3f} {:.3f} l".format(px, py))
        lines.append("S")
    lines.append("Q")
    return "\n".join(lines)


def arrow_and_lock_stream():
    stream = LOCKED.read_text(errors="replace").split("stream", 1)[1].split("endstream", 1)[0]
    marker = "3.694774 8.723195 m"
    idx = stream.find(marker)
    if idx < 0:
        raise SystemExit("locked PDF arrow path not found")
    header = "q\n1.000000 0.000000 -0.000000 1.000000 3.834961 10.247070 cm\n0.000000 0.000000 0.000000 scn\n"
    return header + stream[idx:]


def write_pdf(stream, dest):
    data = stream.encode("latin1")
    objects = [
        b"1 0 obj\n<< >>\nendobj\n",
        b"2 0 obj\n<< /Length %d >>\nstream\n" % len(data) + data + b"\nendstream\nendobj\n",
        b"3 0 obj\n<< /Type /Page /MediaBox [0 0 30 30] /Contents 2 0 R /Parent 4 0 R /Resources << >> >>\nendobj\n",
        b"4 0 obj\n<< /Type /Pages /Count 1 /Kids [3 0 R] >>\nendobj\n",
        b"5 0 obj\n<< /Type /Catalog /Pages 4 0 R >>\nendobj\n",
    ]
    out = bytearray(b"%PDF-1.7\n")
    offsets = [0]
    for obj in objects:
        offsets.append(len(out))
        out += obj
    xref = len(out)
    out += ("xref\n0 %d\n" % (len(objects) + 1)).encode()
    out += b"0000000000 65535 f \n"
    for off in offsets[1:]:
        out += ("%010d 00000 n \n" % off).encode()
    out += ("trailer\n<< /Size %d /Root 5 0 R >>\nstartxref\n%d\n%%%%EOF\n" % (len(objects) + 1, xref)).encode()
    dest.write_bytes(out)


def write_imageset(suffix, pdf_path):
    folder = LOCKED.parent.parent / ("TranscriptionLocked" + suffix + ".imageset")
    if folder.exists():
        shutil.rmtree(folder)
    folder.mkdir(parents=True)
    (folder / pdf_path.name).write_bytes(pdf_path.read_bytes())
    contents = {
        "images": [{"filename": pdf_path.name, "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1},
        "properties": {"template-rendering-intent": "template"},
    }
    (folder / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")


def lerp(a, b, t):
    return a + (b - a) * t


def scalar_at(prop, t):
    if prop.get("a", 0) == 0:
        return prop["k"]
    keys = prop["k"]
    if t <= keys[0]["t"]:
        return keys[0]["s"]
    for i in range(len(keys) - 1):
        t0, t1 = keys[i]["t"], keys[i + 1]["t"]
        if t0 <= t <= t1:
            v0, v1 = keys[i]["s"], keys[i + 1]["s"]
            u = 0 if t1 == t0 else (t - t0) / (t1 - t0)
            if isinstance(v0, list):
                return [lerp(a, b, u) for a, b in zip(v0, v1)]
            return lerp(v0, v1, u)
    return keys[-1]["s"]


def num(value):
    return value[0] if isinstance(value, list) else value


def shape_at(ks, t):
    if ks.get("a", 0) == 0:
        return ks["k"]
    keys = ks["k"]
    if t <= keys[0]["t"]:
        return keys[0]["s"][0]
    for i in range(len(keys) - 1):
        t0, t1 = keys[i]["t"], keys[i + 1]["t"]
        if t0 <= t <= t1:
            a, b = keys[i]["s"][0], keys[i + 1]["s"][0]
            u = 0 if t1 == t0 else (t - t0) / (t1 - t0)
            n = min(len(a["v"]), len(b["v"]))
            return {
                "v": [[lerp(a["v"][j][0], b["v"][j][0], u), lerp(a["v"][j][1], b["v"][j][1], u)] for j in range(n)],
                "i": [[lerp(a["i"][j][0], b["i"][j][0], u), lerp(a["i"][j][1], b["i"][j][1], u)] for j in range(n)],
                "o": [[lerp(a["o"][j][0], b["o"][j][0], u), lerp(a["o"][j][1], b["o"][j][1], u)] for j in range(n)],
                "c": a.get("c", False),
            }
    return keys[-1]["s"][0]


def path_points(shp):
    v, inn, out = shp["v"], shp["i"], shp["o"]
    if len(v) < 2:
        return [tuple(p) for p in v]
    pts = []
    for idx in range(len(v) - 1):
        p0, p3 = v[idx], v[idx + 1]
        c1 = (p0[0] + out[idx][0], p0[1] + out[idx][1])
        c2 = (p3[0] + inn[idx + 1][0], p3[1] + inn[idx + 1][1])
        samples = 8
        for step in range(0 if not pts else 1, samples + 1):
            t = step / samples
            u = 1 - t
            pts.append((
                u*u*u*p0[0] + 3*u*u*t*c1[0] + 3*u*t*t*c2[0] + t*t*t*p3[0],
                u*u*u*p0[1] + 3*u*u*t*c1[1] + 3*u*t*t*c2[1] + t*t*t*p3[1],
            ))
    return pts


def trim_points(pts, start_pct, end_pct):
    if len(pts) < 2:
        return []
    seg = [math.hypot(b[0] - a[0], b[1] - a[1]) for a, b in zip(pts, pts[1:])]
    total = sum(seg)
    if total <= 0.01:
        return []
    a = max(0.0, min(total, start_pct / 100.0 * total))
    b = max(0.0, min(total, end_pct / 100.0 * total))
    if b < a:
        a, b = b, a
    if b - a < 0.2:
        return []

    def at(dist):
        acc = 0.0
        for i, d in enumerate(seg):
            if acc + d >= dist or i == len(seg) - 1:
                u = 0 if d == 0 else max(0.0, min(1.0, (dist - acc) / d))
                p, q = pts[i], pts[i + 1]
                return (lerp(p[0], q[0], u), lerp(p[1], q[1], u)), i
            acc += d
        return pts[-1], len(seg) - 1

    p0, i0 = at(a)
    p1, i1 = at(b)
    return [p0, *pts[i0 + 1:i1 + 1], p1]


def stamp(draw, pts, width, fill):
    if len(pts) < 2 or width <= 0:
        return
    radius = width / 2.0
    samples = [pts[0]]
    for a, b in zip(pts, pts[1:]):
        dist = math.hypot(b[0] - a[0], b[1] - a[1])
        steps = max(1, int(dist))
        for k in range(1, steps + 1):
            t = k / steps
            samples.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
    for x, y in samples:
        draw.ellipse((x - radius, y - radius, x + radius, y + radius), fill=fill)


def render_lottie(path, frame, ink, bg, scale=2):
    data = json.loads(Path(path).read_text())
    im = Image.new("RGB", (int(data["w"] * scale), int(data["h"] * scale)), bg)
    dr = ImageDraw.Draw(im)
    for layer in data["layers"]:
        ks = layer["ks"]
        rot = num(scalar_at(ks["r"], frame))
        pos = scalar_at(ks["p"], frame)
        anchor = ks["a"]["k"]
        for group in layer["shapes"]:
            if group.get("ty") != "gr":
                continue
            items = group["it"]
            shapes = [it for it in items if it.get("ty") == "sh"]
            tr = next(it for it in items if it.get("ty") == "tr")
            tm = next((it for it in items if it.get("ty") == "tm"), None)
            st = next((it for it in items if it.get("ty") == "st"), None)
            if st is None:
                continue
            gpos = scalar_at(tr["p"], frame) if tr["p"].get("a") else tr["p"]["k"]
            width = num(scalar_at(st["w"], frame))
            if width <= 0.05:
                continue
            start, end = 0, 100
            if tm:
                start = num(scalar_at(tm["s"], frame))
                end = num(scalar_at(tm["e"], frame))
            for sh in shapes:
                pts = path_points(shape_at(sh["ks"], frame))
                pts = [(p[0] + gpos[0], p[1] + gpos[1]) for p in pts]
                if tm:
                    pts = trim_points(pts, start, end)
                if len(pts) < 2:
                    continue
                rad = math.radians(rot)
                c, s = math.cos(rad), math.sin(rad)
                placed = []
                for p in pts:
                    x, y = p[0] - anchor[0], p[1] - anchor[1]
                    placed.append(((x * c - y * s + pos[0]) * scale, (x * s + y * c + pos[1]) * scale))
                stamp(dr, placed, width * scale, ink)
    return im.crop((int(40 * scale), int(70 * scale), int(270 * scale), int(230 * scale)))


def render_locked_icon(pdf_path, ink, bg, scale=8):
    fills = parse_pdf_fills(pdf_path)
    im = Image.new("RGB", (30 * scale, 30 * scale), bg)
    dr = ImageDraw.Draw(im)

    def poly(sp, color):
        pts = [(p[0] * scale, (30 - p[1]) * scale) for p in sp]
        if len(pts) >= 3:
            dr.polygon(pts, fill=color)

    if fills:
        first = fills[0]
        if len(first) >= 3:
            poly(first[0], ink)
            poly(first[1], bg)
            for sp in first[2:]:
                poly(sp, ink)
        else:
            for sp in first:
                poly(sp, ink)
        for fill in fills[1:]:
            for sp in fill:
                poly(sp, ink)
    stream = Path(pdf_path).read_text(errors="replace").split("stream", 1)[1].split("endstream", 1)[0]
    tokens = re.findall(r"[A-Za-z*]+|[-+]?\d*\.?\d+(?:[eE][-+]?\d+)?", stream)
    i, nums, path, width = 0, [], [], 1.0
    while i < len(tokens):
        tok = tokens[i]
        if re.fullmatch(r"[-+]?\d*\.?\d+(?:[eE][-+]?\d+)?", tok):
            nums.append(float(tok))
            i += 1
            continue
        if tok == "w" and nums:
            width = nums[-1]
        elif tok == "m" and len(nums) >= 2:
            path = [(nums[-2], nums[-1])]
        elif tok == "l" and len(nums) >= 2 and path:
            path.append((nums[-2], nums[-1]))
        elif tok == "S" and len(path) >= 2:
            stamp(dr, [(p[0] * scale, (30 - p[1]) * scale) for p in path], width * scale, ink)
            path = []
        nums, i = [], i + 1
    return im


def render_sheets():
    out = Path("/opt/cursor/artifacts/transcribe")
    out.mkdir(parents=True, exist_ok=True)
    themes = {"light": ((17, 17, 19), (255, 255, 255)), "dark": ((255, 255, 255), (28, 28, 30))}
    labels = [("en", "")] + [(code, "_" + code) for code, _ch, _font in GLYPHS]
    frames = [("voice", 0), ("voice", 10), ("voice", 19), ("text", 0), ("text", 10), ("text", 19)]
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 22)
    for theme, (ink, bg) in themes.items():
        cell_w, cell_h = 280, 200
        header, label_w = 36, 48
        actual = 30
        actual_h = 56
        cols = len(frames) + 1
        sheet = Image.new("RGB", (label_w + cell_w * cols, header + cell_h * len(labels) + actual_h), bg)
        sd = ImageDraw.Draw(sheet)
        for col, (kind, frame) in enumerate(frames):
            sd.text((label_w + col * cell_w + 8, 6), "{} f{}".format("v" if kind == "voice" else "t", frame), fill=ink, font=font)
        sd.text((label_w + len(frames) * cell_w + 8, 6), "locked", fill=ink, font=font)
        for row, (code, suffix) in enumerate(labels):
            y = header + row * cell_h
            sd.text((6, y + 80), code, fill=ink, font=font)
            for col, (kind, frame) in enumerate(frames):
                name = ("voiceToText" if kind == "voice" else "textToVoice") + suffix + ".json"
                cell = render_lottie(ANIM / name, frame, ink, bg, scale=2)
                cell = cell.resize((cell_w - 12, cell_h - 12), Image.Resampling.LANCZOS)
                sheet.paste(cell, (label_w + col * cell_w + 6, y + 6))
            pdf = LOCKED if not suffix else LOCKED.parent.parent / ("TranscriptionLocked" + suffix + ".imageset") / ("lockedaudiototext" + suffix + ".pdf")
            locked = render_locked_icon(pdf, ink, bg, scale=10)
            locked = locked.resize((cell_h - 36, cell_h - 36), Image.Resampling.LANCZOS)
            sheet.paste(locked, (label_w + len(frames) * cell_w + 40, y + 18))
        # Actual on-screen size: the control is 30x30 pt.
        y = header + cell_h * len(labels)
        sd.text((6, y + 16), "1x", fill=ink, font=font)
        for col, (code, suffix) in enumerate(labels):
            name = "voiceToText" + suffix + ".json"
            icon = render_lottie(ANIM / name, 0, ink, bg, scale=1)
            # The crop above is 230x160 of the 300 canvas. Draw the whole control at 30 px.
            full = render_full(ANIM / name, 0, ink, bg, 30)
            sheet.paste(full, (label_w + col * (actual + 18), y + 12))
        sheet.save(out / ("contact-" + theme + ".png"))
        print("sheet", theme, sheet.size)


def render_full(path, frame, ink, bg, px):
    """Whole 300-unit animation scaled to px pixels, which is the button's size at 1x."""
    data = json.loads(Path(path).read_text())
    scale = px / float(data["w"])
    im = Image.new("RGB", (px, px), bg)
    dr = ImageDraw.Draw(im)
    for layer in data["layers"]:
        ks = layer["ks"]
        rot = num(scalar_at(ks["r"], frame))
        pos = scalar_at(ks["p"], frame)
        anchor = ks["a"]["k"]
        for group in layer["shapes"]:
            if group.get("ty") != "gr":
                continue
            items = group["it"]
            shapes = [it for it in items if it.get("ty") == "sh"]
            tr = next(it for it in items if it.get("ty") == "tr")
            tm = next((it for it in items if it.get("ty") == "tm"), None)
            st = next((it for it in items if it.get("ty") == "st"), None)
            if st is None:
                continue
            gpos = scalar_at(tr["p"], frame) if tr["p"].get("a") else tr["p"]["k"]
            width = num(scalar_at(st["w"], frame))
            if width <= 0.05:
                continue
            start, end = 0, 100
            if tm:
                start = num(scalar_at(tm["s"], frame))
                end = num(scalar_at(tm["e"], frame))
            for sh in shapes:
                pts = path_points(shape_at(sh["ks"], frame))
                pts = [(p[0] + gpos[0], p[1] + gpos[1]) for p in pts]
                if tm:
                    pts = trim_points(pts, start, end)
                if len(pts) < 2:
                    continue
                rad = math.radians(rot)
                c, s = math.cos(rad), math.sin(rad)
                placed = []
                for p in pts:
                    x, y = p[0] - anchor[0], p[1] - anchor[1]
                    placed.append(((x * c - y * s + pos[0]) * scale, (x * s + y * c + pos[1]) * scale))
                stamp(dr, placed, max(1.0, width * scale), ink)
    return im


def main():
    missing = [name for code, _ch, name in GLYPHS if code not in ANDROID_CODES and not (FONT_DIR / name).exists()]
    if missing:
        raise SystemExit("missing fonts in {}: {}".format(FONT_DIR, ", ".join(missing)))
    glyphs = {}
    cache = {}
    for code, ch, font_name in GLYPHS:
        if code in ANDROID_CODES:
            strokes = fit_box(android_letter(code))
            source = "android-pr-39 transcribe_in_" + code + ".json groups 3 and 4 (frame 19)"
        else:
            font_path = str(FONT_DIR / font_name)
            cache.setdefault(font_path, {})
            if ch not in cache[font_path]:
                cache[font_path][ch] = fit_box(skeleton_strokes(font_path, ch))
            strokes = cache[font_path][ch]
            source = "ios Noto Sans Medium medial axis"
        print(code, ch, source, "strokes", len(strokes))
        glyphs[code] = {
            "character": ch,
            "source": source,
            "strokes": [{"points": line["v"], "in": line["i"], "out": line["o"]} for line in strokes],
        }
        for kind in ("voice", "text"):
            build_lottie(kind, "_" + code, strokes)
        pdf_path = ASSETS / ("lockedaudiototext_" + code + ".pdf")
        write_pdf(pdf_strokes(strokes) + "\n" + arrow_and_lock_stream(), pdf_path)
        write_imageset("_" + code, pdf_path)
        pdf_path.unlink()
    write_path_files(glyphs)
    render_sheets()


if __name__ == "__main__":
    main()
