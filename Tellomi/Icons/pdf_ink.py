"""Visible ink box of a single-page icon PDF, in points, y down.

Template icons from the upstream catalog often paint through a calibrated
color space that a rasterizer turns into a blank white page. The paths are
still the glyph. This walks those paths (and the clip that masks a solid
fill) so the box does not depend on the renderer.

Generated MingCute PDFs are the same kind of path stream, so the size check
uses this and does not need poppler.
"""

import re
import zlib
from pathlib import Path


def _mat_mul(left, right):
    a1, b1, c1, d1, e1, f1 = left
    a2, b2, c2, d2, e2, f2 = right
    return (
        a1 * a2 + c1 * b2,
        b1 * a2 + d1 * b2,
        a1 * c2 + c1 * d2,
        b1 * c2 + d1 * d2,
        a1 * e2 + c1 * f2 + e1,
        b1 * e2 + d1 * f2 + f1,
    )


def _apply(matrix, x, y):
    a, b, c, d, e, f = matrix
    return (a * x + c * y + e, b * x + d * y + f)


def _cubic_range(p0, p1, p2, p3):
    a = -p0 + 3 * p1 - 3 * p2 + p3
    b = 2 * p0 - 4 * p1 + 2 * p2
    c = -p0 + p1
    samples = [0.0, 1.0]
    if abs(a) < 1e-12:
        if abs(b) > 1e-12:
            t = -c / b
            if 0.0 < t < 1.0:
                samples.append(t)
    else:
        disc = b * b - 4 * a * c
        if disc >= 0.0:
            root = disc ** 0.5
            for t in ((-b + root) / (2 * a), (-b - root) / (2 * a)):
                if 0.0 < t < 1.0:
                    samples.append(t)
    values = []
    for t in samples:
        u = 1.0 - t
        values.append((u * u * u) * p0 + 3 * (u * u) * t * p1 + 3 * u * (t * t) * p2 + (t * t * t) * p3)
    return min(values), max(values)


def _tokenize(source):
    tokens = []
    i = 0
    n = len(source)
    while i < n:
        ch = source[i]
        if ch.isspace():
            i += 1
            continue
        if ch == "%":
            i = source.find("\n", i)
            if i < 0:
                break
            continue
        if ch == "/":
            j = i + 1
            while j < n and not source[j].isspace() and source[j] not in "[]()<>{}/%":
                j += 1
            tokens.append(("name", source[i:j]))
            i = j
            continue
        if ch == "[":
            depth = 1
            j = i + 1
            while j < n and depth:
                if source[j] == "[":
                    depth += 1
                elif source[j] == "]":
                    depth -= 1
                j += 1
            tokens.append(("array", source[i:j]))
            i = j
            continue
        if ch == "(":
            j = i + 1
            depth = 1
            while j < n and depth:
                if source[j] == "\\":
                    j += 2
                    continue
                if source[j] == "(":
                    depth += 1
                elif source[j] == ")":
                    depth -= 1
                j += 1
            tokens.append(("string", source[i:j]))
            i = j
            continue
        if ch == "<":
            j = source.find(">", i)
            if j < 0:
                break
            tokens.append(("hex", source[i:j + 1]))
            i = j + 1
            continue
        j = i
        while j < n and not source[j].isspace() and source[j] not in "[]()<>{}/%":
            j += 1
        if j == i:
            i += 1
            continue
        word = source[i:j]
        try:
            tokens.append(("num", float(word)))
        except ValueError:
            tokens.append(("op", word))
        i = j
    return tokens


def _empty_box():
    return [1e18, 1e18, -1e18, -1e18]


def _add_point(box, x, y):
    box[0] = min(box[0], x)
    box[1] = min(box[1], y)
    box[2] = max(box[2], x)
    box[3] = max(box[3], y)


def _add_curve(box, pts):
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    x0, x1 = _cubic_range(*xs)
    y0, y1 = _cubic_range(*ys)
    _add_point(box, x0, y0)
    _add_point(box, x1, y1)


def _valid(box):
    return box[2] >= box[0] and box[3] >= box[1]


def _intersect(a, b):
    if a is None:
        return b
    if b is None or not _valid(b):
        return a
    out = [max(a[0], b[0]), max(a[1], b[1]), min(a[2], b[2]), min(a[3], b[3])]
    if out[2] < out[0] or out[3] < out[1]:
        return [0, 0, -1, -1]
    return out


def _union(a, b):
    if not _valid(b):
        return a
    if a is None:
        return list(b)
    return [min(a[0], b[0]), min(a[1], b[1]), max(a[2], b[2]), max(a[3], b[3])]


_FIXED = {
    "q": 0, "Q": 0, "h": 0, "n": 0, "f": 0, "F": 0, "f*": 0,
    "S": 0, "s": 0, "B": 0, "b": 0, "B*": 0, "b*": 0,
    "W": 0, "W*": 0, "EMC": 0, "BT": 0, "ET": 0, "T*": 0,
    "cm": 6, "m": 2, "l": 2, "c": 6, "v": 4, "y": 4, "re": 4,
    "w": 1, "J": 1, "j": 1, "M": 1, "i": 1, "gs": 1, "ri": 1,
    "cs": 1, "CS": 1, "Do": 1, "BMC": 1, "MP": 1,
    "rg": 3, "RG": 3, "g": 1, "G": 1, "k": 4, "K": 4,
    "Tm": 6, "Td": 2, "TD": 2, "Tf": 2, "Tc": 1, "Tw": 1, "Tz": 1, "TL": 1, "Tr": 1, "Ts": 1,
    "d": 2, "BDC": 2, "DP": 2,
}


class _Walker:
    def __init__(self, resources, forms):
        self.resources = resources
        self.forms = forms
        self.ctm = (1, 0, 0, 1, 0, 0)
        self.clip = None
        self.stack = []
        self.path = _empty_box()
        self.point = None
        self.start = None
        self.clip_pending = False
        self.ink = None

    def run(self, source):
        operands = []
        for kind, value in _tokenize(source):
            if kind != "op":
                operands.append(value)
                continue
            if value in ("scn", "SCN", "sc", "SC"):
                operands = []
                continue
            arity = _FIXED.get(value)
            if arity is None:
                operands = []
                continue
            if len(operands) < arity:
                operands = []
                continue
            args = operands[-arity:]
            operands = []
            self._op(value, args)

    def _op(self, op, args):
        if op == "q":
            self.stack.append((self.ctm, self.clip))
            return
        if op == "Q":
            if self.stack:
                self.ctm, self.clip = self.stack.pop()
            return
        if op == "cm":
            self.ctm = _mat_mul(tuple(args), self.ctm)
            return
        if op == "m":
            self.point = _apply(self.ctm, args[0], args[1])
            self.start = self.point
            _add_point(self.path, *self.point)
            return
        if op == "l":
            self.point = _apply(self.ctm, args[0], args[1])
            _add_point(self.path, *self.point)
            return
        if op == "c":
            pts = [_apply(self.ctm, args[i], args[i + 1]) for i in range(0, 6, 2)]
            if self.point is not None:
                _add_curve(self.path, [self.point] + pts)
            self.point = pts[-1]
            return
        if op == "v" and self.point is not None:
            c2 = _apply(self.ctm, args[0], args[1])
            end = _apply(self.ctm, args[2], args[3])
            _add_curve(self.path, [self.point, self.point, c2, end])
            self.point = end
            return
        if op == "y":
            c1 = _apply(self.ctm, args[0], args[1])
            end = _apply(self.ctm, args[2], args[3])
            if self.point is not None:
                _add_curve(self.path, [self.point, c1, end, end])
            self.point = end
            return
        if op == "h":
            self.point = self.start
            return
        if op == "re":
            x, y, w, h = args
            for px, py in ((x, y), (x + w, y), (x, y + h), (x + w, y + h)):
                _add_point(self.path, *_apply(self.ctm, px, py))
            self.point = _apply(self.ctm, x, y)
            self.start = self.point
            return
        if op in ("W", "W*"):
            self.clip_pending = True
            return
        if op == "n":
            self._finish_path(paint=False)
            return
        if op in ("f", "F", "f*", "S", "s", "B", "b", "B*", "b*"):
            self._finish_path(paint=True)
            return
        if op == "Do":
            self._do(args[0])

    def _finish_path(self, paint):
        if self.clip_pending and _valid(self.path):
            self.clip = _intersect(self.clip, self.path) if self.clip else list(self.path)
        if paint:
            painted = _intersect(self.clip, self.path) if self.clip else list(self.path)
            self.ink = _union(self.ink, painted)
        self.path = _empty_box()
        self.point = None
        self.start = None
        self.clip_pending = False

    def _do(self, name):
        form = self.forms.get((id(self.resources), name))
        if form is None:
            return
        saved = (self.ctm, self.clip, self.resources)
        matrix, bbox, contents, resources = form
        if matrix is not None:
            self.ctm = _mat_mul(matrix, self.ctm)
        if bbox is not None:
            box = _empty_box()
            x, y, w, h = bbox
            for px, py in ((x, y), (x + w, y), (x, y + h), (x + w, y + h)):
                _add_point(box, *_apply(self.ctm, px, py))
            self.clip = _intersect(self.clip, box) if self.clip else box
        self.resources = resources
        self.run(contents)
        self.ctm, self.clip, self.resources = saved


def _inflate(raw):
    """Inflate a PDF stream body. The byte before endstream may be a real
    compressed CR, or the end-of-line the spec puts before endstream."""
    candidates = [raw]
    if raw.endswith(b"\r\n"):
        candidates.append(raw[:-2])
    elif raw.endswith(b"\n") or raw.endswith(b"\r"):
        candidates.append(raw[:-1])
    for candidate in candidates:
        try:
            return zlib.decompress(candidate)
        except zlib.error:
            continue
    return None


def _streams(data):
    found = []
    for match in re.finditer(br"stream\r?\n", data):
        start = match.end()
        end = data.find(b"endstream", start)
        if end < 0:
            continue
        raw = data[start:end]
        if raw.startswith(b"<?") or raw.startswith(b"<x"):
            continue
        decoded = _inflate(raw)
        if decoded is None:
            continue
        found.append(decoded.decode("latin1"))
    return found


_MEDIABOX = re.compile(br"/MediaBox\s*\[\s*([\d.\-]+)\s+([\d.\-]+)\s+([\d.\-]+)\s+([\d.\-]+)\s*\]")


def _page_size_in(blob):
    match = _MEDIABOX.search(blob)
    if not match:
        return None
    x0, y0, x1, y1 = (float(match.group(i)) for i in range(1, 5))
    return x1 - x0, y1 - y0


def _page_size(data):
    found = _page_size_in(data)
    if found:
        return found
    for source in _streams(data):
        found = _page_size_in(source.encode("latin1", "ignore"))
        if found:
            return found
    return None


def ink_box_structured(path):
    """Page-tree ink box. Follows form XObjects. Needs pypdf.

    Use this for upstream PDFs whose glyph is a form. Generated cairo
    PDFs use ink_box_pdf, which does not need pypdf.
    """
    from pypdf import PdfReader

    page = PdfReader(str(path)).pages[0]
    page_w = float(page.mediabox.width)
    page_h = float(page.mediabox.height)
    walker = _Walker(resources=None, forms={})

    def bind(resources):
        def _do(name):
            res = resources.get_object() if hasattr(resources, "get_object") else resources
            xobjects = res.get("/XObject") if res is not None else None
            if xobjects is None:
                return
            xobjects = xobjects.get_object()
            if name not in xobjects:
                return
            obj = xobjects[name].get_object()
            if str(obj.get("/Subtype")) != "/Form":
                return
            saved = (walker.ctm, walker.clip, walker._do)
            matrix = obj.get("/Matrix")
            if matrix is not None:
                walker.ctm = _mat_mul(tuple(float(value) for value in matrix), walker.ctm)
            bbox = obj.get("/BBox")
            if bbox is not None:
                x, y, width, height = (float(value) for value in bbox)
                box = _empty_box()
                for px, py in ((x, y), (x + width, y), (x, y + height), (x + width, y + height)):
                    _add_point(box, *_apply(walker.ctm, px, py))
                walker.clip = _intersect(walker.clip, box) if walker.clip else box
            sub = obj.get("/Resources")
            if sub is not None:
                walker._do = bind(sub)
            walker.run(obj.get_data().decode("latin1"))
            walker.ctm, walker.clip, walker._do = saved
        return _do

    resources = page.get("/Resources")
    if resources is not None:
        walker._do = bind(resources)
    contents = page.get_contents()
    if contents is None:
        return None
    walker.run(contents.get_data().decode("latin1"))
    if not walker.ink or not _valid(walker.ink):
        return None
    x0, y0, x1, y1 = walker.ink
    x0 = max(0.0, x0)
    y0 = max(0.0, y0)
    x1 = min(page_w, x1)
    y1 = min(page_h, y1)
    if x1 <= x0 or y1 <= y0:
        return None
    return page_w, page_h, x0, page_h - y1, x1 - x0, y1 - y0


def ink_box_pdf(path):
    """Return (page_w, page_h, x, y, w, h) with y growing down, or None."""
    data = Path(path).read_bytes()
    page = _page_size(data)
    if page is None:
        return None
    page_w, page_h = page
    walker = _Walker(resources=None, forms={})
    for source in _streams(data):
        if len(source) > 200000 or not re.search(r"(?:^|\s)(?:m|l|c|re)(?:\s)", source):
            continue
        walker.run(source)
    if not walker.ink or not _valid(walker.ink):
        return None
    x0, y0, x1, y1 = walker.ink
    x0 = max(0.0, x0)
    y0 = max(0.0, y0)
    x1 = min(page_w, x1)
    y1 = min(page_h, y1)
    if x1 <= x0 or y1 <= y0:
        return None
    return page_w, page_h, x0, page_h - y1, x1 - x0, y1 - y0
