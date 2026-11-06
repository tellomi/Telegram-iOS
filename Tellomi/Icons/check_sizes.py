#!/usr/bin/env python3
"""Fail when a replaced icon's ink is below 0.9 of the upstream icon.

The long side is the one that is compared. Upstream boxes are
upstream_ink.json, measured from the icons that were in the tree before
the MingCute replacement. An imageset with an explicit WxH canvas and no
upstream icon is not compared: that canvas is the inset, not an old glyph.

The measurement reads the PDF paths, so it does not need poppler. Run:

    python3 Tellomi/Icons/check_sizes.py
"""

import csv
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import pdf_ink

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
XCASSETS = ROOT / "submodules/TelegramUI/Images.xcassets"
MAPPING = HERE / "mapping.csv"
UPSTREAM = HERE / "upstream_ink.json"
MINIMUM_RATIO = 0.9


def read_mapping():
    rows = []
    with MAPPING.open(newline="") as handle:
        for raw in csv.reader(handle):
            if not raw or raw[0].startswith("#") or raw[0] == "asset":
                continue
            canvas = raw[3].strip() if len(raw) > 3 else ""
            rows.append((raw[0].strip(), canvas))
    return rows


def load_upstream():
    data = json.loads(UPSTREAM.read_text())
    icons = {}
    for asset, spec in data["icons"].items():
        ink = spec["ink"]
        icons[asset] = (float(ink[2]), float(ink[3]))
    return icons


def target_asset(asset, canvas, upstream):
    if asset in upstream:
        return asset
    if canvas.startswith("match:"):
        target = canvas.split(":", 1)[1]
        if target in upstream:
            return target
    return None


def main():
    upstream = load_upstream()
    failures = []
    checked = 0
    skipped = 0
    for asset, canvas in read_mapping():
        target = target_asset(asset, canvas, upstream)
        if target is None:
            skipped += 1
            continue
        pdf = XCASSETS / f"{asset}.imageset" / "icon.pdf"
        if not pdf.is_file():
            failures.append(f"{asset}: icon.pdf is missing")
            continue
        box = pdf_ink.ink_box_pdf(pdf)
        if box is None:
            failures.append(f"{asset}: no ink in {pdf.name}")
            continue
        width, height = box[4], box[5]
        old_w, old_h = upstream[target]
        old = max(old_w, old_h)
        if old <= 0:
            failures.append(f"{asset}: upstream ink is empty")
            continue
        ratio = max(width, height) / old
        checked += 1
        if ratio < MINIMUM_RATIO:
            failures.append(
                f"{asset}: ink {width:.1f}x{height:.1f} is {ratio:.2f} of upstream {old_w:.1f}x{old_h:.1f}"
            )
    if failures:
        print(f"icon size check: {len(failures)} failure(s), {checked} compared, {skipped} without an upstream icon")
        for line in failures:
            print(line)
        return 1
    print(f"icon size check: {checked} icons at or above {MINIMUM_RATIO:.1f} of upstream, {skipped} without an upstream icon")
    return 0


if __name__ == "__main__":
    sys.exit(main())
