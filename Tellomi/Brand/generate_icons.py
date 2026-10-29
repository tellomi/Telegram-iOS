#!/usr/bin/env python3
"""Rasterize Tellomi/Brand/logo.svg into the app icon set and alternate-icon slots.

The path data is the traced logo. This only scales it and paints #111113 or
#FFFFFF. It does not edit the outline.
"""

import json
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent
LOGO = ROOT / "logo.svg"
LIGHT = "#111113"
DARK = "#FFFFFF"
DARK_BG = "#111113"
LIGHT_BG = "#FFFFFF"

DARK_SLOTS = {
    "BlackIcon",
    "BlackClassicIcon",
    "BlackFilledIcon",
    "PremiumBlack",
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


def colored_svg(fill, background):
    text = LOGO.read_text(encoding="utf-8")
    text = text.replace('fill="currentColor"', 'fill="{}"'.format(fill))
    # Opaque home-screen icons. The traced file has no background of its own.
    text = text.replace(
        "<g ",
        '<rect width="1024" height="1024" fill="{}"/>\n  <g '.format(background),
        1,
    )
    return text


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


def write_appiconset():
    out = ROOT / "AppIcon.appiconset"
    if out.exists():
        shutil.rmtree(out)
    out.mkdir()
    light = colored_svg(LIGHT, LIGHT_BG)
    dark = colored_svg(DARK, DARK_BG)
    tinted = colored_svg("#000000", "#FFFFFF")
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


def write_alternates():
    upstream = Path(__file__).resolve().parents[2] / "Telegram" / "Telegram-iOS"
    light = colored_svg(LIGHT, LIGHT_BG)
    dark = colored_svg(DARK, DARK_BG)
    dest_root = ROOT / "Alternates"
    if dest_root.exists():
        shutil.rmtree(dest_root)
    dest_root.mkdir()
    from PIL import Image

    for folder in sorted(upstream.glob("*.alticon")):
        name = folder.name[: -len(".alticon")]
        svg = dark if name in DARK_SLOTS else light
        out = dest_root / folder.name
        out.mkdir()
        for png in folder.glob("*.png"):
            with Image.open(png) as image:
                pixels = image.size[0]
            render(svg, pixels, out / png.name)


def main():
    write_appiconset()
    write_alternates()
    print("wrote", ROOT)


if __name__ == "__main__":
    main()
