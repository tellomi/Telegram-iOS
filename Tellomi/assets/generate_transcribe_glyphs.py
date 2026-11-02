#!/usr/bin/env python3
"""Build the voice-to-text letter variants from one set of stroke paths.

The English Lottie files draw an arrow and a stroked "A", then trim the letter
away into the collapse chevron. Each variant keeps those layer and group names
and that trim, and swaps the "A" centerlines for one character.

Coordinates below are centerlines in the A's box (x right, y down, 0..70 by
0..90). They are written to Tellomi/assets so the Android client can stroke the
same paths. Glyphs are drawn unmirrored; the button forces left-to-right.
"""

import json
import math
import re
import shutil
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
ANIM = ROOT / "submodules/TelegramUI/Resources/Animations"
LOCKED = ROOT / "submodules/TelegramUI/Images.xcassets/Chat/Message/TranscriptionLocked.imageset/lockedaudiototext.pdf"
ASSETS = ROOT / "Tellomi/assets"

# A's centerline box in the 300x300 Lottie canvas (y down).
BOX = (163.3, 100.4, 70.0, 89.6)  # x, y, w, h
STROKE = 13.3

# Local design space matches that box: x 0..70, y 0..90.
# "primary" is the stroke the collapse chevron morphs into.
GLYPHS = {
    "zh": {
        "character": "文",
        # Legs meet the bar from below. A peak that crosses the bar reads as 大.
        "primary": [
            [(6, 88), (35, 44), (64, 88)],
        ],
        "secondary": [
            [(30, 0), (40, 8)],
            [(4, 26), (66, 26)],
        ],
    },
    "ja": {
        "character": "あ",
        "primary": [
            [(18, 30), (6, 50), (12, 72), (30, 86)],
        ],
        "secondary": [
            [(4, 12), (28, 4), (52, 8), (60, 20)],
            [(36, 34), (58, 42), (60, 60), (44, 74), (32, 60)],
        ],
    },
    "ko": {
        "character": "가",
        "primary": [
            [(2, 18), (32, 18), (32, 80)],
        ],
        "secondary": [
            [(48, 4), (48, 88)],
            [(48, 42), (66, 42)],
        ],
    },
    "ar": {
        "character": "ع",
        "primary": [
            [(60, 10), (44, 2), (28, 12), (32, 24), (48, 26), (60, 16)],
        ],
        "secondary": [
            [(46, 28), (38, 44), (26, 60), (18, 74), (36, 88), (58, 84), (66, 70)],
        ],
    },
    "fa": {
        "character": "ا",
        "primary": [
            [(35, 4), (35, 88)],
        ],
        "secondary": [],
    },
    "he": {
        "character": "א",
        "primary": [
            [(58, 8), (12, 84)],
        ],
        "secondary": [
            [(4, 28), (50, 14)],
            [(22, 50), (62, 76)],
        ],
    },
    "hi": {
        "character": "अ",
        "primary": [
            [(6, 8), (66, 8), (58, 86)],
        ],
        "secondary": [
            [(46, 22), (18, 30), (14, 48), (34, 54), (16, 70), (32, 82)],
        ],
    },
    "th": {
        "character": "ก",
        "primary": [
            [(18, 78), (16, 34), (30, 16), (52, 14), (66, 22), (68, 78)],
        ],
        "secondary": [],
    },
}

# Collapse chevron at the start of textToVoice, in that group's local space.
CHEVRON = [(-60.0, 30.0), (0.0, -30.0), (60.0, 30.0)]
MORPH_POINTS = 16


def lerp(a, b, t):
    return a + (b - a) * t


def to_canvas(points):
    x0, y0, w, h = BOX
    return [[round(x0 + x / 70.0 * w, 3), round(y0 + y / 90.0 * h, 3)] for x, y in points]


def resample(points, count):
    if count < 2 or len(points) < 2:
        return [list(points[0]) for _ in range(max(count, 1))]
    lengths = [0.0]
    for a, b in zip(points, points[1:]):
        lengths.append(lengths[-1] + math.hypot(b[0] - a[0], b[1] - a[1]))
    total = lengths[-1] or 1.0
    out = []
    seg = 0
    for i in range(count):
        dist = total * i / (count - 1)
        while seg < len(lengths) - 2 and lengths[seg + 1] < dist:
            seg += 1
        span = lengths[seg + 1] - lengths[seg]
        u = 0.0 if span == 0 else (dist - lengths[seg]) / span
        a, b = points[seg], points[seg + 1]
        out.append([lerp(a[0], b[0], u), lerp(a[1], b[1], u)])
    return out


def shape(points, closed=False):
    zeros = [[0, 0] for _ in points]
    return {"i": zeros, "o": zeros, "v": [[round(p[0], 3), round(p[1], 3)] for p in points], "c": closed}


def path_item(points):
    return {
        "ind": 0,
        "ty": "sh",
        "ix": 1,
        "ks": {"a": 0, "k": shape(points), "ix": 2},
        "nm": "Path 1",
        "mn": "ADBE Vector Shape - Group",
        "hd": False,
    }


def group_items(group):
    return group["it"]


def replace_static_paths(group, polylines):
    items = group_items(group)
    kept = [it for it in items if it.get("ty") != "sh"]
    paths = [path_item(line) for line in polylines] or [path_item([[0, 0], [0, 0]])]
    # A zero-length stand-in would still paint a round cap. Hide an unused group.
    if not polylines:
        for it in kept:
            if it.get("ty") == "st":
                it["w"] = {"a": 0, "k": 0, "ix": it.get("w", {}).get("ix", 5)}
    else:
        for it in kept:
            if it.get("ty") == "st":
                it["lj"] = 2
    group["it"] = paths + kept


def replace_morph(group, start_local, end_local):
    items = group_items(group)
    shape_item = next(it for it in items if it.get("ty") == "sh")
    keys = shape_item["ks"]["k"]
    keys[0]["s"] = [shape(start_local)]
    keys[-1]["s"] = [shape(end_local)]
    for it in items:
        if it.get("ty") == "st":
            it["lj"] = 2


def local_offset(group):
    tr = next(it for it in group["it"] if it.get("ty") == "tr")
    pos = tr["p"]["k"]
    return pos[0], pos[1]


def shift(points, origin):
    return [[p[0] - origin[0], p[1] - origin[1]] for p in points]


def build_lottie(kind, suffix, primary, secondary):
    src_name = "voiceToText.json" if kind == "voice" else "textToVoice.json"
    data = json.loads((ANIM / src_name).read_text())
    if kind == "voice":
        groups = {g["nm"]: g for g in data["layers"][0]["shapes"]}
        origin = local_offset(groups["Group 2"])
        replace_static_paths(groups["Group 2"], [shift(line, origin) for line in primary])
        replace_static_paths(groups["Group 1"], [shift(line, (0, 0)) for line in secondary])
    else:
        morph_layer = next(layer for layer in data["layers"] if layer["nm"] == "Artboard Copy Outlines")
        trim_layer = next(layer for layer in data["layers"] if layer["nm"] == "Artboard Copy 2 Outlines")
        morph = next(g for g in morph_layer["shapes"] if g["nm"] == "Group 1")
        cross = next(g for g in trim_layer["shapes"] if g["nm"] == "Group 1")
        origin = local_offset(morph)
        # One open path. The chevron and the letter share a vertex count so the
        # existing 20-frame morph still runs.
        end = resample(shift(primary[0], origin), MORPH_POINTS)
        start = resample(CHEVRON, MORPH_POINTS)
        replace_morph(morph, start, end)
        replace_static_paths(cross, secondary)
        # Any primary strokes after the first draw in with the crossbar.
        if len(primary) > 1:
            replace_static_paths(cross, secondary + primary[1:])
    dest = ANIM / "{}{}.json".format("voiceToText" if kind == "voice" else "textToVoice", suffix)
    dest.write_text(json.dumps(data, ensure_ascii=False, separators=(",", ":")))
    return dest


def write_path_files(canvas_glyphs):
    ASSETS.mkdir(parents=True, exist_ok=True)
    common = {
        "coordinateSpace": "lottie-canvas",
        "yAxis": "down",
        "unmirrored": True,
        "canvas": [300, 300],
        "strokeWidth": STROKE,
        "lineCap": "round",
        "lineJoin": "round",
        "letterBox": {"x": BOX[0], "y": BOX[1], "width": BOX[2], "height": BOX[3]},
        "note": "Centerlines of the transcription letter. Same paths feed the iOS Lottie files. Draw unmirrored in RTL.",
    }
    all_glyphs = {"glyphs": canvas_glyphs, **common}
    (ASSETS / "transcribe-glyph-paths.json").write_text(json.dumps(all_glyphs, ensure_ascii=False, indent=2) + "\n")
    wen = {"character": "文", "language": "zh", "strokes": canvas_glyphs["zh"]["strokes"], **common}
    (ASSETS / "transcribe-wen-paths.json").write_text(json.dumps(wen, ensure_ascii=False, indent=2) + "\n")


def parse_pdf_fills(pdf_path):
    stream = pdf_path.read_text(errors="replace").split("stream", 1)[1].split("endstream", 1)[0]
    ctm = [1, 0, 0, 1, 0, 0]
    stack = []
    fills = []
    subpaths = []
    path = []
    start = None
    cur = None

    def mul(m, x, y):
        return (m[0] * x + m[2] * y + m[4], m[1] * x + m[3] * y + m[5])

    def bez(p0, p1, p2, p3, t):
        u = 1 - t
        return (
            u * u * u * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t * t * t * p3[0],
            u * u * u * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t * t * t * p3[1],
        )

    tokens = re.findall(r"[A-Za-z*]+|[-+]?\d*\.?\d+(?:[eE][-+]?\d+)?", stream)
    i = 0
    nums = []
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
            ctm = [
                a * ctm[0] + b * ctm[2],
                a * ctm[1] + b * ctm[3],
                c * ctm[0] + d * ctm[2],
                c * ctm[1] + d * ctm[3],
                e * ctm[0] + f * ctm[2] + ctm[4],
                e * ctm[1] + f * ctm[3] + ctm[5],
            ]
        elif op == "m" and len(nums) >= 2:
            if path:
                subpaths.append(path)
            cur = mul(ctm, nums[-2], nums[-1])
            start = cur
            path = [cur]
        elif op == "l" and len(nums) >= 2:
            cur = mul(ctm, nums[-2], nums[-1])
            path.append(cur)
        elif op == "c" and len(nums) >= 6:
            x1, y1, x2, y2, x3, y3 = nums[-6:]
            p0 = cur
            p1, p2, p3 = mul(ctm, x1, y1), mul(ctm, x2, y2), mul(ctm, x3, y3)
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
            subpaths = []
            start = None
        elif op == "n":
            path = []
            subpaths = []
            start = None
        nums = []
        i += 1
    return fills


def pdf_glyph_commands(strokes):
    # Fit the design box into the filled A's ink box (page space, y up).
    ink = (13.84, 10.34, 20.49, 20.67)  # minx, miny, maxx, maxy
    sw = 1.35
    inset = sw / 2
    box = (ink[0] + inset, ink[1] + inset, ink[2] - inset, ink[3] - inset)
    bw, bh = box[2] - box[0], box[3] - box[1]
    scale = min(bw / 70.0, bh / 90.0)
    dw, dh = 70.0 * scale, 90.0 * scale
    ox = box[0] + (bw - dw) / 2
    oy = box[3] - (bh - dh) / 2  # top of the fitted box, y up
    lines = ["q", "0 0 0 RG", "{:.3f} w".format(sw), "1 J", "1 j"]
    for stroke in strokes:
        pts = []
        for x, y in stroke:
            px = ox + (x / 70.0) * dw
            py = oy - (y / 90.0) * dh
            pts.append((px, py))
        lines.append("{:.3f} {:.3f} m".format(pts[0][0], pts[0][1]))
        for px, py in pts[1:]:
            lines.append("{:.3f} {:.3f} l".format(px, py))
        lines.append("S")
    lines.append("Q")
    return "\n".join(lines)


def original_stream_from_arrow():
    stream = LOCKED.read_text(errors="replace").split("stream", 1)[1].split("endstream", 1)[0]
    marker = "3.694774 8.723195 m"
    idx = stream.find(marker)
    if idx < 0:
        raise SystemExit("locked PDF arrow path not found")
    header = "q\n1.000000 0.000000 -0.000000 1.000000 3.834961 10.247070 cm\n0.000000 0.000000 0.000000 scn\n"
    return header + stream[idx:]


def write_pdf(stream, dest):
    data = stream.encode("latin1")
    objects = []
    objects.append(b"1 0 obj\n<< >>\nendobj\n")
    objects.append(b"2 0 obj\n<< /Length %d >>\nstream\n" % len(data) + data + b"\nendstream\nendobj\n")
    objects.append(
        b"3 0 obj\n<< /Type /Page /MediaBox [0 0 30 30] /Contents 2 0 R /Parent 4 0 R /Resources << >> >>\nendobj\n"
    )
    objects.append(b"4 0 obj\n<< /Type /Pages /Count 1 /Kids [3 0 R] >>\nendobj\n")
    objects.append(b"5 0 obj\n<< /Type /Catalog /Pages 4 0 R >>\nendobj\n")
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
    name = pdf_path.name
    (folder / name).write_bytes(pdf_path.read_bytes())
    # The imageset lives next to the generated pdf; copy the bytes in place.
    contents = {
        "images": [{"filename": name, "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1},
        "properties": {"template-rendering-intent": "template"},
    }
    (folder / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")


def draw_chrome(draw, fills, color, scale):
    # First fill is arrow + A. Drop the two A subpaths. Later fills are the lock.
    chrome = [fills[0][2]] + [sp for fill in fills[1:] for sp in fill]
    for sp in chrome:
        pts = [(p[0] * scale, (30 - p[1]) * scale) for p in sp]
        if len(pts) >= 3:
            draw.polygon(pts, fill=color)


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


def path_points(shp, samples=8):
    v, inn, out = shp["v"], shp["i"], shp["o"]
    if len(v) < 2:
        return [tuple(p) for p in v]
    pts = []
    for idx in range(len(v) - 1):
        p0, p3 = v[idx], v[idx + 1]
        c1 = (p0[0] + out[idx][0], p0[1] + out[idx][1])
        c2 = (p3[0] + inn[idx + 1][0], p3[1] + inn[idx + 1][1])
        seg = []
        for step in range(samples + 1):
            u = 1 - step / samples
            tt = step / samples
            seg.append((
                u*u*u*p0[0] + 3*u*u*tt*c1[0] + 3*u*tt*tt*c2[0] + tt*tt*tt*p3[0],
                u*u*u*p0[1] + 3*u*u*tt*c1[1] + 3*u*tt*tt*c2[1] + tt*tt*tt*p3[1],
            ))
        if pts:
            seg = seg[1:]
        pts.extend(seg)
    return pts


def trim_points(pts, start_pct, end_pct):
    if len(pts) < 2:
        return []
    seg = [math.hypot(b[0] - a[0], b[1] - a[1]) for a, b in zip(pts, pts[1:])]
    total = sum(seg)
    if total <= 0.01:
        return []
    a = max(0, min(total, start_pct / 100 * total))
    b = max(0, min(total, end_pct / 100 * total))
    if b < a:
        a, b = b, a
    if b - a < 0.2:
        return []

    def at(dist):
        acc = 0
        for i, d in enumerate(seg):
            if acc + d >= dist or i == len(seg) - 1:
                u = 0 if d == 0 else max(0, min(1, (dist - acc) / d))
                p, q = pts[i], pts[i + 1]
                return (lerp(p[0], q[0], u), lerp(p[1], q[1], u)), i
            acc += d
        return pts[-1], len(seg) - 1

    p0, i0 = at(a)
    p1, i1 = at(b)
    out = [p0]
    out.extend(pts[i0 + 1:i1 + 1])
    out.append(p1)
    return out


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
            if width <= 0:
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
                transformed = []
                rad = math.radians(rot)
                c, s = math.cos(rad), math.sin(rad)
                for p in pts:
                    x, y = p[0] - anchor[0], p[1] - anchor[1]
                    transformed.append(((x * c - y * s + pos[0]) * scale, (x * s + y * c + pos[1]) * scale))
                wpx = max(1, int(round(width * scale)))
                dr.line(transformed, fill=ink, width=wpx, joint="curve")
                r = wpx / 2
                for p in (transformed[0], transformed[-1]):
                    dr.ellipse((p[0] - r, p[1] - r, p[0] + r, p[1] + r), fill=ink)
    # The letter and arrow sit in the middle of the 300 canvas.
    return im.crop((int(30 * scale), int(70 * scale), int(270 * scale), int(230 * scale)))


def render_locked(pdf_path, ink, bg, scale=10):
    fills = parse_pdf_fills(pdf_path)
    im = Image.new("RGB", (30 * scale, 30 * scale), bg)
    dr = ImageDraw.Draw(im)
    draw_chrome(dr, fills, ink, scale)
    # English keeps the filled A. Variants only have the arrow and the lock in
    # the PDF fills; the letter is stroked on top by the content stream, which
    # this rasterizer does not replay. Stroke it from the path file instead.
    return im


def render_locked_icon(pdf_path, ink, bg, scale=8):
    """Rasterize the template PDF. The English file's first fill is the A (outer, counter, arrow)."""
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
    # Stroke operators are the replacement letter. Replay those on top.
    stream = Path(pdf_path).read_text(errors="replace").split("stream", 1)[1].split("endstream", 1)[0]
    tokens = re.findall(r"[A-Za-z*]+|[-+]?\d*\.?\d+(?:[eE][-+]?\d+)?", stream)
    i = 0
    nums = []
    path = []
    width = 1.0
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
            pts = [(p[0] * scale, (30 - p[1]) * scale) for p in path]
            wpx = max(1, int(round(width * scale)))
            dr.line(pts, fill=ink, width=wpx, joint="curve")
            r = wpx / 2
            for p in (pts[0], pts[-1]):
                dr.ellipse((p[0] - r, p[1] - r, p[0] + r, p[1] + r), fill=ink)
            path = []
        nums = []
        i += 1
    return im


def render_sheets():
    out = Path("/opt/cursor/artifacts/transcribe")
    out.mkdir(parents=True, exist_ok=True)
    themes = {
        "light": ((17, 17, 19), (255, 255, 255)),
        "dark": ((255, 255, 255), (28, 28, 30)),
    }
    labels = [("en", "A", "")] + [(code, spec["character"], "_" + code) for code, spec in GLYPHS.items()]
    frames = [("voice", 0), ("voice", 10), ("voice", 19), ("text", 0), ("text", 10), ("text", 19)]
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 16)
    for theme, (ink, bg) in themes.items():
        cell_w, cell_h = 160, 110
        header = 28
        cols = len(frames) + 1
        sheet = Image.new("RGB", (28 + cell_w * cols, header + cell_h * len(labels)), bg)
        sd = ImageDraw.Draw(sheet)
        for col, (kind, frame) in enumerate(frames):
            sd.text((28 + col * cell_w + 8, 4), "{} f{}".format("v" if kind == "voice" else "t", frame), fill=ink, font=font)
        sd.text((28 + len(frames) * cell_w + 8, 4), "locked", fill=ink, font=font)
        for row, (code, char, suffix) in enumerate(labels):
            y = header + row * cell_h
            sd.text((4, y + 40), code, fill=ink, font=font)
            for col, (kind, frame) in enumerate(frames):
                name = ("voiceToText" if kind == "voice" else "textToVoice") + suffix + ".json"
                cell = render_lottie(ANIM / name, frame, ink, bg, scale=1)
                cell = cell.resize((cell_w - 8, cell_h - 8), Image.Resampling.LANCZOS)
                sheet.paste(cell, (28 + col * cell_w + 4, y + 4))
            if suffix:
                pdf = LOCKED.parent.parent / ("TranscriptionLocked" + suffix + ".imageset") / ("lockedaudiototext" + suffix + ".pdf")
            else:
                pdf = LOCKED
            locked = render_locked_icon(pdf, ink, bg)
            locked = locked.resize((cell_h - 16, cell_h - 16), Image.Resampling.LANCZOS)
            sheet.paste(locked, (28 + len(frames) * cell_w + 24, y + 8))
        sheet.save(out / ("contact-" + theme + ".png"))
        print("sheet", theme, sheet.size)


def main():
    canvas_glyphs = {}
    for code, spec in GLYPHS.items():
        primary = [to_canvas(line) for line in spec["primary"]]
        secondary = [to_canvas(line) for line in spec["secondary"]]
        strokes = [{"role": "primary", "points": line} for line in primary] + [
            {"role": "secondary", "points": line} for line in secondary
        ]
        canvas_glyphs[code] = {"character": spec["character"], "strokes": strokes}
        for kind in ("voice", "text"):
            build_lottie(kind, "_" + code, primary, secondary)
        stream = pdf_glyph_commands(spec["primary"] + spec["secondary"]) + "\n" + original_stream_from_arrow()
        pdf_path = ASSETS / ("lockedaudiototext_" + code + ".pdf")
        write_pdf(stream, pdf_path)
        write_imageset("_" + code, pdf_path)
        pdf_path.unlink()
    write_path_files(canvas_glyphs)
    print("wrote", len(GLYPHS), "variants")
    render_sheets()


if __name__ == "__main__":
    main()
