#!/usr/bin/env python3
"""Build the bundled chat-wallpaper patterns.

Doodle icons are Lucide (ISC) and Tabler Icons (MIT). The wave tile is Hero
Patterns "Topography" and the dot tile is Hero Patterns "Polka Dots", both
CC BY 4.0, Steve Schoger. Nothing here is a WhatsApp or Telegram asset.

Outputs:
  Tellomi/Wallpapers/{doodle,dots,waves}.svg
  submodules/TelegramUI/Resources/tm_{doodle,dots,waves}.tgv   (gzip of the svg)
"""

import gzip
import os
import re
import urllib.request

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT_DIR = os.path.dirname(os.path.abspath(__file__))
TGV_DIR = os.path.join(ROOT, "submodules", "TelegramUI", "Resources")

LUCIDE = "https://raw.githubusercontent.com/lucide-icons/lucide/main/icons/{name}.svg"
TABLER = "https://raw.githubusercontent.com/tabler/tabler-icons/master/icons/outline/{name}.svg"

LUCIDE_NAMES = [
    "message-circle", "coffee", "music", "star", "sprout", "plane", "heart", "sun",
    "moon", "cloud", "camera", "book-open", "gift", "bell", "bike", "flower-2",
    "headphones", "map-pin", "smile", "zap", "umbrella", "anchor", "feather", "fish",
    "bird", "cat", "dog", "apple", "cake", "palette", "leaf", "trees",
]
TABLER_NAMES = [
    "message", "mug", "music", "star", "plant", "plane", "heart", "sun",
    "moon", "cloud", "camera", "book", "gift", "bell", "bike", "flower",
    "headphones", "map-pin", "mood-smile", "bolt", "umbrella", "anchor", "feather", "fish",
    "bird", "cat", "dog", "apple", "cake", "palette", "leaf", "trees",
]

HERO_JS = "https://heropatterns.com/js/app.js"


def fetch(url):
    request = urllib.request.Request(url, headers={"User-Agent": "tellomi-wallpaper-generator"})
    with urllib.request.urlopen(request, timeout=30) as response:
        return response.read()


def inner_svg(svg_text):
    svg_text = re.sub(r"<!--.*?-->", "", svg_text, flags=re.S)
    match = re.search(r"<svg\b[^>]*>(.*)</svg>", svg_text, flags=re.S)
    body = match.group(1) if match else svg_text
    body = body.replace("currentColor", "#000")
    body = re.sub(r'\sstroke="[^"]*"', "", body)
    body = re.sub(r'\sfill="none"', "", body)
    return body.strip()


def load_icons():
    icons = []
    for source, names, url in (
        ("lucide", LUCIDE_NAMES, LUCIDE),
        ("tabler", TABLER_NAMES, TABLER),
    ):
        for name in names:
            try:
                text = fetch(url.format(name=name)).decode("utf-8")
            except Exception as error:
                print(f"skip {source}:{name} ({error})")
                continue
            icons.append((source, name, inner_svg(text)))
            print(f"icon {source}:{name}")
    if len(icons) < 40:
        raise SystemExit(f"only {len(icons)} icons downloaded")
    return icons


def doodle_svg(icons):
    size = 1024
    columns = 8
    cell = size // columns
    # 56px icon rotated 45 degrees stays inside a 128px cell, so the tile is seamless.
    scale = 56.0 / 24.0
    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" viewBox="0 0 {size} {size}" fill="none" stroke="#000" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">'
    ]
    for index in range(columns * columns):
        source, name, body = icons[index % len(icons)]
        column = index % columns
        row = index // columns
        cx = column * cell + cell / 2.0
        cy = row * cell + cell / 2.0
        angle = ((index * 47) % 12) * 30  # 0, 30, ... 330, deterministic
        transform = f"translate({cx:.1f},{cy:.1f}) rotate({angle}) scale({scale:.4f}) translate(-12,-12)"
        parts.append(f'<g id="{source}-{name}-{index}" transform="{transform}">{body}</g>')
    parts.append("</svg>")
    return "\n".join(parts)


def hero_image(name):
    text = fetch(HERO_JS).decode("utf-8")
    match = re.search(r"name: '%s',\s*image: '(.*?)',\s*download:" % re.escape(name), text)
    if not match:
        raise SystemExit(f"hero pattern {name} not found")
    return match.group(1)


def waves_svg():
    tile = hero_image("Topography")
    inner = inner_svg(tile)
    # Tile the 600px contour drawing so a phone aspect-fill still shows several repeats.
    parts = [
        '<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="1200" viewBox="0 0 1200 1200" fill="#000">'
    ]
    for dx in (0, 600):
        for dy in (0, 600):
            parts.append(f'<g transform="translate({dx},{dy})">{inner}</g>')
    parts.append("</svg>")
    return "\n".join(parts)


def dots_svg():
    # Hero Patterns "Polka Dots": two r=3 circles in a 20px cell, repeated.
    cell = 20
    tiles = 48  # 960px
    size = cell * tiles
    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" viewBox="0 0 {size} {size}">',
        '<g fill="#000" fill-rule="evenodd">',
    ]
    for row in range(tiles):
        for column in range(tiles):
            ox = column * cell
            oy = row * cell
            parts.append(f'<circle cx="{ox + 3}" cy="{oy + 3}" r="3"/>')
            parts.append(f'<circle cx="{ox + 13}" cy="{oy + 13}" r="3"/>')
    parts.append("</g></svg>")
    return "\n".join(parts)


def write_pair(name, svg):
    svg_path = os.path.join(OUT_DIR, f"{name}.svg")
    tgv_path = os.path.join(TGV_DIR, f"tm_{name}.tgv")
    with open(svg_path, "w", encoding="utf-8") as handle:
        handle.write(svg)
    payload = gzip.compress(svg.encode("utf-8"), mtime=0)
    with open(tgv_path, "wb") as handle:
        handle.write(payload)
    print(f"wrote {svg_path} ({len(svg)} bytes) and {tgv_path} ({len(payload)} bytes)")


def main():
    icons = load_icons()
    write_pair("doodle", doodle_svg(icons))
    write_pair("dots", dots_svg())
    write_pair("waves", waves_svg())


if __name__ == "__main__":
    main()
