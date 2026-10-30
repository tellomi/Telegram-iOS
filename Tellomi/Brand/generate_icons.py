#!/usr/bin/env python3
"""Rasterize Tellomi/Brand/logo.svg into the app icon set and alternate-icon slots.

The path data is the traced logo. This scales that outline into the icon frame
and paints it. It does not edit the path.
"""

import json
import shutil
import subprocess
import tempfile
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent
LOGO = ROOT / "logo.svg"
LIGHT = "#111113"
DARK = "#FFFFFF"
DARK_BG = "#111113"
LIGHT_BG = "#FFFFFF"

# The mark should occupy this fraction of the icon square. The traced paths
# already run to the viewBox edges, so the transform scale is smaller than this.
SUBJECT_OF_FRAME = 0.78

# Black-background Appearance icons (Default X, Classic X, Filled X, Black).
# Same padding as the home-screen icon; the mark stays white.
DARK_SLOTS = {
    "BlackIcon": (DARK, DARK_BG),
    "BlackClassicIcon": (DARK, DARK_BG),
    "BlackFilledIcon": (DARK, DARK_BG),
    "PremiumBlack": (DARK, DARK_BG),
}

# Settings slots that are not the light default and not a black plate.
# Each value is (mark, background). Kept apart from #111113 / #FFFFFF
# so Sunset, Aqua, and the rest are not copies of the monochrome icons.
COLOR_SLOTS = {
    "BlueClassicIcon": ("#FFFFFF", "#2F80ED"),
    "BlueFilledIcon": ("#FFFFFF", "#3B5BDB"),
    "New1": ("#FFFFFF", "#F15A24"),
    "New2": ("#FFFFFF", "#0AA1B5"),
    "Premium": ("#FFFFFF", "#7C3AED"),
    "PremiumTurbo": ("#111113", "#F5B301"),
}

SIZES = [
    ("iphone", "20x20", "2x", 40),
    ("iphone", "20x20", "3x", 60),
    ("iphone", "29x29", "2x", 58),
    ("iphone", "29x29", "3x", 87),
    ("iphone", "40x40", "2x", 80),
    ("iphone", "40x40", "3x", 120),
    ("iphone", "60x60", "2x", 120),
    ("iphone", "60x60", "3x", 180),
    ("ipad", "20x20", "1x", 20),
    ("ipad", "20x20", "2x", 40),
    ("ipad", "29x29", "1x", 29),
    ("ipad", "29x29", "2x", 58),
    ("ipad", "40x40", "1x", 40),
    ("ipad", "40x40", "2x", 80),
    ("ipad", "76x76", "1x", 76),
    ("ipad", "76x76", "2x", 152),
    ("ipad", "83.5x83.5", "2x", 167),
    ("ios-marketing", "1024x1024", "1x", 1024),
]


def icon_svg(fill, background, scale):
    text = LOGO.read_text(encoding="utf-8")
    text = text.replace('fill="currentColor"', 'fill="{}"'.format(fill), 1)
    prefix = ""
    if background is not None:
        prefix += '<rect width="1024" height="1024" fill="{}"/>\n  '.format(background)
    prefix += '<g transform="translate(512 512) scale({}) translate(-512 -512)">\n  '.format(scale)
    text = text.replace("<g ", prefix + "<g ", 1)
    text = text.replace("</svg>", "</g>\n</svg>", 1)
    return text


def mark_fraction(scale):
    """Largest axis of the painted mark, as a fraction of a 1024 frame."""
    dest = Path(tempfile.mkdtemp()) / "mark.png"
    render(icon_svg("#000000", "#FFFFFF", scale), 1024, dest)
    image = Image.open(dest).convert("RGB")
    pixels = image.load()
    min_x, min_y, max_x, max_y = 1024, 1024, 0, 0
    for y in range(1024):
        for x in range(1024):
            red, green, blue = pixels[x, y]
            if red < 250 or green < 250 or blue < 250:
                min_x = min(min_x, x)
                min_y = min(min_y, y)
                max_x = max(max_x, x + 1)
                max_y = max(max_y, y + 1)
    return max(max_x - min_x, max_y - min_y) / 1024.0


def subject_scale():
    full = mark_fraction(1)
    if full <= 0:
        raise SystemExit("the traced logo painted nothing")
    return SUBJECT_OF_FRAME / full


def render(svg, size, dest):
    with tempfile.NamedTemporaryFile("w", suffix=".svg", delete=False) as handle:
        handle.write(svg)
        path = handle.name
    try:
        subprocess.check_call(
            ["rsvg-convert", "-w", str(size), "-h", str(size), path, "-o", str(dest)],
            stdout=subprocess.DEVNULL,
        )
    finally:
        Path(path).unlink(missing_ok=True)


def write_appiconset(mark_scale):
    catalog = ROOT / "AppIcon.xcassets"
    out = catalog / "AppIcon.appiconset"
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)
    (catalog / "Contents.json").write_text(
        '{\n  "info" : {\n    "author" : "xcode",\n    "version" : 1\n  }\n}\n',
        encoding="utf-8",
    )
    stale = ROOT / "AppIcon.appiconset"
    if stale.exists():
        shutil.rmtree(stale)
    light = icon_svg(LIGHT, LIGHT_BG, mark_scale)
    dark = icon_svg(DARK, DARK_BG, mark_scale)
    tinted = icon_svg("#000000", "#FFFFFF", mark_scale)
    images = []
    for idiom, size_name, scale, pixels in SIZES:
        for suffix, svg, appearances in (
            ("", light, None),
            ("-dark", dark, [{"appearance": "luminosity", "value": "dark"}]),
            ("-tinted", tinted, [{"appearance": "luminosity", "value": "tinted"}]),
        ):
            filename = "AppIcon-{}-{}@{}{}.png".format(
                idiom, size_name.replace(".", "_"), scale, suffix
            )
            render(svg, pixels, out / filename)
            entry = {
                "filename": filename,
                "idiom": idiom,
                "scale": scale,
                "size": size_name,
            }
            if appearances:
                entry["appearances"] = appearances
            images.append(entry)
    (out / "Contents.json").write_text(
        json.dumps({"images": images, "info": {"author": "xcode", "version": 1}}, indent=2) + "\n",
        encoding="utf-8",
    )


def slot_colors(name):
    if name in DARK_SLOTS:
        return DARK_SLOTS[name]
    if name in COLOR_SLOTS:
        return COLOR_SLOTS[name]
    if name in ("BlueIcon", "WhiteFilledIcon"):
        return (LIGHT, LIGHT_BG)
    raise SystemExit("no color for alternate icon " + name)


def write_alternates(mark_scale):
    upstream = Path(__file__).resolve().parents[2] / "Telegram" / "Telegram-iOS"
    dest_root = ROOT / "Alternates"
    if dest_root.exists():
        shutil.rmtree(dest_root)
    dest_root.mkdir()
    cache = {}

    for folder in sorted(upstream.glob("*.alticon")):
        name = folder.name[: -len(".alticon")]
        fill, background = slot_colors(name)
        key = (fill, background)
        if key not in cache:
            cache[key] = icon_svg(fill, background, mark_scale)
        svg = cache[key]
        out = dest_root / folder.name
        out.mkdir()
        for png in folder.glob("*.png"):
            with Image.open(png) as image:
                pixels = image.size[0]
            render(svg, pixels, out / png.name)


def write_composer_glyph(mark_scale):
    """White glyph on transparency, for AppIcon.icon. Same scale as the size set."""
    dest = ROOT / "AppIcon.icon" / "Assets" / "Logo.png"
    render(icon_svg("#FFFFFF", None, mark_scale), 1024, dest)


def main():
    mark_scale = subject_scale()
    painted = mark_fraction(mark_scale)
    print("mark scale {:.4f}, painted fraction {:.3f}".format(mark_scale, painted))
    if not 0.75 <= painted <= 0.80:
        raise SystemExit("painted mark {:.3f} is outside 75–80% of the frame".format(painted))
    write_appiconset(mark_scale)
    write_alternates(mark_scale)
    write_composer_glyph(mark_scale)
    print("wrote", ROOT)


if __name__ == "__main__":
    main()
