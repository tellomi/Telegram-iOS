#!/usr/bin/env python3
"""Rebuild Tellomi template icons from the vendored MingCute SVGs.

mapping.csv columns:

    asset,mingcute,style,canvas

asset
    Imageset path under submodules/TelegramUI/Images.xcassets, without
    the .imageset suffix. Example: Chat List/Tabs/IconChats

mingcute
    Icon file name without .svg. The file lives in
    Tellomi/Icons/MingCute/svg/regular or svg/filled.

style
    line  -> svg/regular (outline)
    fill  -> svg/filled

canvas
    Empty: keep the imageset's current page size and place the glyph in
    the original ink box, so the padding stays.
    WxH: page size in points. The glyph fills that page (MingCute's own
    viewBox padding is the inset).
    match:<asset>: copy the page size and ink box of another row's asset
    before it is replaced. Used for a new filled imageset next to a line
    one.

The PDF is a single black vector on a clear page. The app tints it.
"""

import csv
import json
import re
import subprocess
import tempfile
from io import BytesIO
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
XCASSETS = ROOT / "submodules/TelegramUI/Images.xcassets"
SVG_ROOT = Path(__file__).resolve().parent / "MingCute" / "svg"
MAPPING = Path(__file__).resolve().parent / "mapping.csv"

STYLE_DIR = {"line": "regular", "fill": "filled"}


def read_mapping():
    rows = []
    with MAPPING.open(newline="") as handle:
        for raw in csv.reader(handle):
            if not raw or raw[0].startswith("#") or raw[0] == "asset":
                continue
            if len(raw) < 3:
                raise SystemExit(f"short row: {raw}")
            asset, name, style = raw[0].strip(), raw[1].strip(), raw[2].strip()
            canvas = raw[3].strip() if len(raw) > 3 else ""
            if style not in STYLE_DIR:
                raise SystemExit(f"{asset}: style must be line or fill, got {style}")
            rows.append((asset, name, style, canvas))
    return rows


def imageset_dir(asset):
    return XCASSETS / f"{asset}.imageset"


def page_size_of_pdf(path):
    from pypdf import PdfReader

    box = PdfReader(str(path)).pages[0].mediabox
    return float(box.width), float(box.height)


def rasterize(path, dpi):
    if path.suffix.lower() == ".pdf":
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "page"
            subprocess.check_call(
                ["pdftoppm", "-png", "-r", str(dpi), "-f", "1", "-l", "1", str(path), str(out)],
                stdout=subprocess.DEVNULL,
            )
            pngs = list(Path(tmp).glob("*.png"))
            if not pngs:
                raise SystemExit(f"pdftoppm wrote nothing for {path}")
            return Image.open(pngs[0]).convert("RGBA")
    return Image.open(path).convert("RGBA")


def ink_box(image):
    pixels = image.load()
    width, height = image.size
    extrema = image.getextrema()
    alpha_varies = extrema[3][0] < 250
    min_x, min_y, max_x, max_y = width, height, -1, -1
    for y in range(height):
        for x in range(width):
            red, green, blue, alpha = pixels[x, y]
            if alpha_varies:
                ink = alpha > 16
            else:
                ink = alpha > 16 and not (red > 245 and green > 245 and blue > 245)
            if ink:
                min_x = min(min_x, x)
                min_y = min(min_y, y)
                max_x = max(max_x, x)
                max_y = max(max_y, y)
    if max_x < min_x:
        return None
    return min_x, min_y, max_x - min_x + 1, max_y - min_y + 1


def source_files(directory):
    return [path for path in directory.iterdir() if path.suffix.lower() in {".pdf", ".png", ".svg", ".jpg", ".jpeg"}]


def png_scale(path):
    name = path.name
    if "@3x" in name:
        return 3.0
    if "@2x" in name:
        return 2.0
    return 1.0


def measure_existing(asset):
    directory = imageset_dir(asset)
    if not directory.is_dir():
        raise SystemExit(f"{asset}: imageset does not exist and canvas was not given")
    files = source_files(directory)
    if not files:
        raise SystemExit(f"{asset}: imageset has no image")
    pdfs = [path for path in files if path.suffix.lower() == ".pdf"]
    pngs = [path for path in files if path.suffix.lower() == ".png"]
    svgs = [path for path in files if path.suffix.lower() == ".svg"]
    if pdfs:
        source = pdfs[0]
        page_w, page_h = page_size_of_pdf(source)
        dpi = 144
        raster = rasterize(source, dpi)
        scale = dpi / 72.0
    elif pngs:
        source = sorted(pngs, key=lambda path: png_scale(path))[0]
        scale = png_scale(source)
        raster = rasterize(source, 72)
        page_w = raster.size[0] / scale
        page_h = raster.size[1] / scale
    elif svgs:
        text = svgs[0].read_text()
        width = re.search(r'\bwidth="([0-9.]+)"', text)
        height = re.search(r'\bheight="([0-9.]+)"', text)
        if not width or not height:
            raise SystemExit(f"{asset}: svg has no width/height")
        page_w, page_h = float(width.group(1)), float(height.group(1))
        import cairosvg
        scale = 4.0
        png = cairosvg.svg2png(
            url=str(svgs[0]),
            output_width=int(page_w * scale),
            output_height=int(page_h * scale),
        )
        raster = Image.open(BytesIO(png)).convert("RGBA")
    else:
        raise SystemExit(f"{asset}: imageset has no pdf, png, or svg")
    box = ink_box(raster)
    if box is None:
        return page_w, page_h, (0.0, 0.0, page_w, page_h)
    x, y, w, h = box
    return page_w, page_h, (x / scale, y / scale, w / scale, h / scale)


def parse_canvas(spec, measured):
    if not spec:
        return None
    if spec.startswith("match:"):
        target = spec.split(":", 1)[1]
        if target not in measured:
            raise SystemExit(f"match target not measured yet: {target}")
        return measured[target]
    match = re.fullmatch(r"(\d+(?:\.\d+)?)x(\d+(?:\.\d+)?)", spec)
    if not match:
        raise SystemExit(f"bad canvas {spec}")
    width, height = float(match.group(1)), float(match.group(2))
    return width, height, (0.0, 0.0, width, height)


def black_svg(name, style):
    path = SVG_ROOT / STYLE_DIR[style] / f"{name}.svg"
    if not path.is_file():
        raise SystemExit(f"missing vendored SVG {path}")
    text = path.read_text()
    text = text.replace("currentColor", "#000000")
    text = re.sub(r'fill="(?!none)[^"]*"', 'fill="#000000"', text)
    text = re.sub(r'stroke="(?!none)[^"]*"', 'stroke="#000000"', text)
    inner = re.search(r"<svg\b([^>]*)>(.*)</svg>", text, re.DOTALL)
    if not inner:
        raise SystemExit(f"not an svg: {path}")
    return inner.group(2)


def compose_svg(page_w, page_h, ink, inner):
    x, y, w, h = ink
    # Keep the glyph square inside the ink box so a wide canvas does not stretch it.
    side = min(w, h)
    x += (w - side) / 2.0
    y += (h - side) / 2.0
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{page_w}pt" height="{page_h}pt" '
        f'viewBox="0 0 {page_w} {page_h}">'
        f'<svg x="{x}" y="{y}" width="{side}" height="{side}" viewBox="0 0 24 24">{inner}</svg>'
        f"</svg>"
    )


def write_pdf(svg_text, destination):
    import cairosvg

    destination.parent.mkdir(parents=True, exist_ok=True)
    cairosvg.svg2pdf(bytestring=svg_text.encode(), write_to=str(destination))


def write_imageset(asset, pdf_path):
    directory = imageset_dir(asset)
    directory.mkdir(parents=True, exist_ok=True)
    folder = directory.parent
    folder_contents = folder / "Contents.json"
    if not folder_contents.exists():
        folder_contents.write_text(json.dumps({"info": {"version": 1, "author": "xcode"}}, indent=2) + "\n")
    for old in source_files(directory):
        if old.resolve() != pdf_path.resolve():
            old.unlink()
    contents = {
        "images": [{"idiom": "universal", "filename": pdf_path.name}],
        "info": {"version": 1, "author": "xcode"},
        "properties": {
            "template-rendering-intent": "template",
            "preserves-vector-representation": True,
        },
    }
    (directory / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")


def main():
    rows = read_mapping()
    measured = {}
    explicit = {}
    for asset, _, _, canvas in rows:
        if re.fullmatch(r"\d+(?:\.\d+)?x\d+(?:\.\d+)?", canvas or ""):
            explicit[asset] = parse_canvas(canvas, {})
    needed = set()
    for asset, _, _, canvas in rows:
        if not canvas:
            needed.add(asset)
        elif canvas.startswith("match:"):
            needed.add(canvas.split(":", 1)[1])
    for asset in sorted(needed):
        if asset in explicit:
            measured[asset] = explicit[asset]
        else:
            measured[asset] = measure_existing(asset)

    written = 0
    for asset, name, style, canvas in rows:
        geometry = parse_canvas(canvas, measured)
        if geometry is None:
            geometry = measured[asset]
        page_w, page_h, ink = geometry
        svg = compose_svg(page_w, page_h, ink, black_svg(name, style))
        directory = imageset_dir(asset)
        pdf_path = directory / "icon.pdf"
        write_pdf(svg, pdf_path)
        write_imageset(asset, pdf_path)
        got_w, got_h = page_size_of_pdf(pdf_path)
        if abs(got_w - page_w) > 0.2 or abs(got_h - page_h) > 0.2:
            raise SystemExit(f"{asset}: wrote {got_w}x{got_h}, wanted {page_w}x{page_h}")
        written += 1
        print(f"{asset}  {name} {style}  {page_w:.1f}x{page_h:.1f}")
    print(f"replaced {written}")


if __name__ == "__main__":
    main()
