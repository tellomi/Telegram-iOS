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

# Daily marks sit at SUBJECT_OF_FRAME. Classic is the low end of 75–80% so the
# bubble stays inside its round base. Filled is the high end, still clear of
# the squircle, on a color that runs to the edge of the square.
CLASSIC_OF_FRAME = 0.76
FILLED_OF_FRAME = 0.795
CLASSIC_BLUE = "#2F80ED"

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
    # 76x76@1x is the non-Retina iPad home icon. actool rejects it when the
    # deployment target is iOS 10 or later ("only apply to iPad apps targeting
    # releases of iOS prior to 10.0"). 76x76@2x (152 px) stays; App Store still
    # checks that size and 83.5@2x.
    ("ipad", "76x76", "2x", 152),
    ("ipad", "83.5x83.5", "2x", 167),
    ("ios-marketing", "1024x1024", "1x", 1024),
]


def icon_svg(fill, scale, plate="", defs=""):
    text = LOGO.read_text(encoding="utf-8")
    text = text.replace('fill="currentColor"', 'fill="{}"'.format(fill), 1)
    newline = text.find("\n")
    head, rest = text[: newline + 1], text[newline + 1 :]
    if defs:
        rest = defs + "\n" + rest
    prefix = plate
    if prefix and not prefix.endswith("\n"):
        prefix += "\n  "
    prefix += '<g transform="translate(512 512) scale({}) translate(-512 -512)">\n  '.format(scale)
    rest = rest.replace("<g ", prefix + "<g ", 1)
    rest = rest.replace("</svg>", "</g>\n</svg>", 1)
    return head + rest


def solid_plate(color):
    return '<rect width="1024" height="1024" fill="{}"/>'.format(color)


def linear_gradient(name, stops, x2="1", y2="1"):
    body = "".join(
        '<stop offset="{}" stop-color="{}"/>'.format(offset, color) for offset, color in stops
    )
    return (
        '<linearGradient id="{}" gradientUnits="objectBoundingBox" x1="0" y1="0" x2="{}" y2="{}">{}</linearGradient>'
    ).format(name, x2, y2, body)


def gradient_plate(name, stops, x2="1", y2="1"):
    defs = "<defs>{}</defs>".format(linear_gradient(name, stops, x2, y2))
    return defs, solid_plate("url(#{})".format(name))


def round_base(field, disc):
    return solid_plate(field) + '<circle cx="512" cy="512" r="470" fill="{}"/>'.format(disc)


def star_points(cx, cy, outer, inner):
    import math

    points = []
    for index in range(10):
        radius = outer if index % 2 == 0 else inner
        angle = -math.pi / 2 + index * math.pi / 5
        points.append("{:.1f},{:.1f}".format(cx + radius * math.cos(angle), cy + radius * math.sin(angle)))
    return " ".join(points)


def starry_background():
    defs, plate = gradient_plate(
        "sky",
        (("0%", "#312E81"), ("100%", "#0B1026")),
        x2="0.15",
        y2="1",
    )
    state = 7

    def rnd():
        nonlocal state
        state = (1103515245 * state + 12345) & 0x7FFFFFFF
        return state / float(0x7FFFFFFF)

    parts = [plate]
    for _ in range(64):
        x = rnd() * 1024
        y = rnd() * 1024
        radius = 1.1 + rnd() * 2.8
        opacity = 0.4 + rnd() * 0.6
        parts.append(
            '<circle cx="{:.1f}" cy="{:.1f}" r="{:.2f}" fill="#FFFFFF" opacity="{:.2f}"/>'.format(
                x, y, radius, opacity
            )
        )
    for _ in range(9):
        x = 48 + rnd() * 928
        y = 48 + rnd() * 928
        outer = 9 + rnd() * 16
        parts.append('<polygon points="{}" fill="#FDE68A"/>'.format(star_points(x, y, outer, outer * 0.38)))
    return defs, "\n".join(parts)


def mark_fraction(scale):
    """Largest axis of the painted mark, as a fraction of a 1024 frame."""
    dest = Path(tempfile.mkdtemp()) / "mark.png"
    render(icon_svg("#000000", scale, plate=solid_plate("#FFFFFF")), 1024, dest)
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
    light = icon_svg(LIGHT, mark_scale, plate=solid_plate(LIGHT_BG))
    dark = icon_svg(DARK, mark_scale, plate=solid_plate(DARK_BG))
    tinted = icon_svg("#000000", mark_scale, plate=solid_plate("#FFFFFF"))
    images = []
    for idiom, size_name, scale, pixels in SIZES:
        filename = "AppIcon-{}-{}@{}.png".format(
            idiom, size_name.replace(".", "_"), scale
        )
        render(light, pixels, out / filename)
        images.append(
            {
                "filename": filename,
                "idiom": idiom,
                "scale": scale,
                "size": size_name,
            }
        )
        if idiom != "ios-marketing":
            continue
        # Dark and tinted are one 1024 slot (idiom universal, platform ios).
        # The same attributes on an iphone/ipad size, or on idiom ios-marketing,
        # are not slots actool assigns, so those PNGs were "unassigned children".
        images.append(
            {
                "filename": filename,
                "idiom": "universal",
                "platform": "ios",
                "size": size_name,
            }
        )
        for suffix, svg, value in (
            ("-dark", dark, "dark"),
            ("-tinted", tinted, "tinted"),
        ):
            appearance_name = "AppIcon-ios-marketing-1024x1024@1x{}.png".format(suffix)
            render(svg, pixels, out / appearance_name)
            images.append(
                {
                    "filename": appearance_name,
                    "idiom": "universal",
                    "platform": "ios",
                    "size": size_name,
                    "appearances": [{"appearance": "luminosity", "value": value}],
                }
            )
    (out / "Contents.json").write_text(
        json.dumps({"images": images, "info": {"author": "xcode", "version": 1}}, indent=2) + "\n",
        encoding="utf-8",
    )


def frame_scale(mark_scale, fraction):
    return mark_scale * (fraction / SUBJECT_OF_FRAME)


def slot_svg(name, mark_scale):
    """One SVG per Settings slot. The traced bubble is the symbol in every slot."""
    daily = mark_scale
    classic = frame_scale(mark_scale, CLASSIC_OF_FRAME)
    filled = frame_scale(mark_scale, FILLED_OF_FRAME)
    if name == "BlueIcon":
        return icon_svg(LIGHT, daily, plate=solid_plate(LIGHT_BG))
    if name == "BlackIcon":
        return icon_svg(DARK, daily, plate=solid_plate(DARK_BG))
    if name == "New2":
        defs, plate = gradient_plate(
            "water",
            (("0%", "#0F766E"), ("46%", "#14B8A6"), ("100%", "#67E8F9")),
        )
        return icon_svg(DARK, daily, plate=plate, defs=defs)
    if name == "New1":
        defs, plate = gradient_plate(
            "sunset",
            (("0%", "#F9A8D4"), ("40%", "#E879F9"), ("100%", "#6D28D9")),
        )
        return icon_svg(DARK, daily, plate=plate, defs=defs)
    if name == "BlueClassicIcon":
        return icon_svg(DARK, classic, plate=round_base("#F4F4F5", CLASSIC_BLUE))
    if name == "BlackClassicIcon":
        return icon_svg(
            DARK,
            classic,
            plate=solid_plate(DARK_BG)
            + '<circle cx="512" cy="512" r="468" fill="none" stroke="#FFFFFF" stroke-width="22"/>',
        )
    if name == "BlueFilledIcon":
        return icon_svg(DARK, filled, plate=solid_plate(CLASSIC_BLUE))
    if name == "BlackFilledIcon":
        return icon_svg(DARK, filled, plate=solid_plate(DARK_BG))
    if name == "WhiteFilledIcon":
        return icon_svg(LIGHT, filled, plate=solid_plate(LIGHT_BG))
    if name == "Premium":
        defs, plate = starry_background()
        return icon_svg(DARK, daily, plate=plate, defs=defs)
    if name == "PremiumTurbo":
        defs, plate = gradient_plate(
            "metal",
            (("0%", "#FDE68A"), ("48%", "#F59E0B"), ("100%", "#B45309")),
            x2="0",
            y2="1",
        )
        plate += '<polygon points="{}" fill="#7C2D12"/>'.format(star_points(214, 196, 78, 32))
        return icon_svg(LIGHT, daily, plate=plate, defs=defs)
    if name == "PremiumBlack":
        plate = solid_plate(DARK_BG) + '<polygon points="{}" fill="#F5C451"/>'.format(star_points(214, 196, 78, 32))
        return icon_svg(DARK, daily, plate=plate)
    raise SystemExit("no artwork for alternate icon " + name)


def write_alternates(mark_scale):
    upstream = Path(__file__).resolve().parents[2] / "Telegram" / "Telegram-iOS"
    dest_root = ROOT / "Alternates"
    if dest_root.exists():
        shutil.rmtree(dest_root)
    dest_root.mkdir()

    for folder in sorted(upstream.glob("*.alticon")):
        name = folder.name[: -len(".alticon")]
        svg = slot_svg(name, mark_scale)
        out = dest_root / folder.name
        out.mkdir()
        for png in folder.glob("*.png"):
            with Image.open(png) as image:
                pixels = image.size[0]
            render(svg, pixels, out / png.name)


def write_composer_glyph(mark_scale):
    """White glyph on transparency, for AppIcon.icon. Same scale as the size set."""
    dest = ROOT / "AppIcon.icon" / "Assets" / "Logo.png"
    render(icon_svg("#FFFFFF", mark_scale), 1024, dest)


def main():
    mark_scale = subject_scale()
    painted = mark_fraction(mark_scale)
    print("mark scale {:.4f}, painted fraction {:.3f}".format(mark_scale, painted))
    if not 0.75 <= painted <= 0.80:
        raise SystemExit("painted mark {:.3f} is outside 75–80% of the frame".format(painted))
    for fraction in (CLASSIC_OF_FRAME, FILLED_OF_FRAME):
        got = mark_fraction(frame_scale(mark_scale, fraction))
        print("fraction target {:.2f}, painted {:.3f}".format(fraction, got))
        if not 0.75 <= got <= 0.80:
            raise SystemExit("painted mark {:.3f} is outside 75–80% of the frame".format(got))
    write_appiconset(mark_scale)
    write_alternates(mark_scale)
    write_composer_glyph(mark_scale)
    print("wrote", ROOT)


if __name__ == "__main__":
    main()
