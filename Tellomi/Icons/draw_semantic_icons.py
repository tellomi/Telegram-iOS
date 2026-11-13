#!/usr/bin/env python3
"""Write the sticker and GIF imagesets the MingCute names do not cover.

These imagesets are not rows in mapping.csv. generate_icons.py does not
see them, so a size pass over the mapped MingCute set leaves them alone.
"""

import json
import re
from pathlib import Path

import cairosvg

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
XCASSETS = ROOT / "submodules/TelegramUI/Images.xcassets"
SEMANTIC = HERE / "semantic"

# asset path under Images.xcassets, page size in points, source svg.
TARGETS = [
    ("Chat/Input/Text/TellomiSticker", 24.0, "sticker.svg"),
    ("Chat/Attach Menu/TellomiSticker", 30.0, "sticker.svg"),
    ("Item List/Icons/TellomiSticker", 30.0, "sticker.svg"),
    ("Item List/Icons/TellomiGif", 30.0, "gif.svg"),
]


def inner_svg(name):
    text = (SEMANTIC / name).read_text()
    match = re.search(r"<svg\b([^>]*)>(.*)</svg>", text, re.DOTALL)
    if not match:
        raise SystemExit(f"not an svg: {name}")
    return match.group(2)


def compose(page, inner):
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{page}pt" height="{page}pt" '
        f'viewBox="0 0 {page} {page}">'
        f'<svg x="0" y="0" width="{page}" height="{page}" viewBox="0 0 24 24">{inner}</svg>'
        f"</svg>"
    )


def write_imageset(asset, pdf_path):
    directory = XCASSETS / f"{asset}.imageset"
    directory.mkdir(parents=True, exist_ok=True)
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
    for asset, page, source in TARGETS:
        svg = compose(page, inner_svg(source))
        pdf_path = XCASSETS / f"{asset}.imageset" / "icon.pdf"
        pdf_path.parent.mkdir(parents=True, exist_ok=True)
        cairosvg.svg2pdf(bytestring=svg.encode(), write_to=str(pdf_path))
        write_imageset(asset, pdf_path)
        print(f"{asset}  {page:.0f}pt  {source}")


if __name__ == "__main__":
    main()
