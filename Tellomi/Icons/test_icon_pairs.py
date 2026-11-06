#!/usr/bin/env python3
"""Paired icons must not be the same source drawing.

Pin and unpin, the stealth eye and its locked form, read / read-all /
select-all, business and channel, and devices and cellular each had been
pointed at one MingCute file. This checks the mapping, not the pixels.
"""

import csv
import os
import unittest

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
MAPPING = os.path.join(ROOT, "Tellomi", "Icons", "mapping.csv")
SVG_ROOT = os.path.join(ROOT, "Tellomi", "Icons", "MingCute", "svg")
SEMANTIC = os.path.join(ROOT, "Tellomi", "Icons", "semantic")

# Each group is a set of imagesets whose drawings must differ.
PAIRS = [
    [
        "Chat/Context Menu/Pin",
        "Chat/Context Menu/Unpin",
    ],
    [
        "Chat List/Swipe/Pin",
        "Chat List/Swipe/Unpin",
    ],
    [
        "Chat List/PeerPinnedIcon",
        "Chat/Context Menu/Unpin",
    ],
    [
        "Chat/Context Menu/Eye",
        "Chat/Context Menu/EyeLocked",
    ],
    [
        "Chat/Context Menu/Read",
        "Chat/Context Menu/ReadAll",
        "Chat/Context Menu/SelectAll",
    ],
    [
        "Item List/Icons/Business",
        "Item List/Icons/Channel",
    ],
    [
        "Item List/Icons/Business",
        "Chat List/Filters/Channel",
    ],
    [
        "Item List/Icons/Devices",
        "Item List/Icons/Cellular",
    ],
]

STYLE_DIR = {"line": "regular", "fill": "filled"}


def read_mapping():
    rows = {}
    with open(MAPPING, newline="", encoding="utf-8") as handle:
        for raw in csv.reader(handle):
            if not raw or raw[0].startswith("#") or raw[0] == "asset":
                continue
            asset, name, style = raw[0].strip(), raw[1].strip(), raw[2].strip()
            rows[asset] = (name, style)
    return rows


def source_path(name, style):
    if name.startswith("semantic/"):
        base = name.split("/", 1)[1]
        filename = f"{base}-fill.svg" if style == "fill" else f"{base}.svg"
        return os.path.join(SEMANTIC, filename)
    return os.path.join(SVG_ROOT, STYLE_DIR[style], f"{name}.svg")


class IconPairTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.rows = read_mapping()

    def test_paired_icons_do_not_share_a_source_svg(self):
        for group in PAIRS:
            paths = []
            for asset in group:
                self.assertIn(asset, self.rows, asset)
                path = source_path(*self.rows[asset])
                self.assertTrue(os.path.isfile(path), path)
                paths.append(os.path.realpath(path))
            self.assertEqual(len(paths), len(set(paths)), group)

    def test_send_arrow_stays_out_of_the_generator(self):
        self.assertNotIn("Chat/Input/Text/SendIcon", self.rows)
        name, _style = self.rows["Chat/Input/Text/IconForwardSend"]
        self.assertEqual(name, "share-forward")
        self.assertNotEqual(name, "send")

    def test_round_video_button_stays_the_camera_glyph(self):
        # PR #67 pins this. The play-in-a-frame glyph is Attach Menu/Video.
        self.assertEqual(self.rows["Chat/Input/Text/IconVideo"], ("video-camera", "line"))
        self.assertEqual(self.rows["Chat/Attach Menu/Video"][0], "video-camera")
        self.assertNotIn("Chat/Context Menu/VideoCall", self.rows)

    def test_sticker_and_gif_rows_are_left_for_the_other_branch(self):
        # cursor/semantic-icons-f5af draws these outside the mapping.
        self.assertEqual(self.rows["Item List/Icons/Gif"], ("film", "line"))
        for asset in (
            "Chat/Input/Text/AccessoryIconStickers",
            "Chat/Attach Menu/Sticker",
            "Chat/Context Menu/Sticker",
            "Item List/Icons/Sticker",
        ):
            self.assertEqual(self.rows[asset][0], "sticker", asset)

    def test_clock_file_is_a_clock_face(self):
        path = os.path.join(SVG_ROOT, "regular", "clock.svg")
        with open(path, encoding="utf-8") as handle:
            text = handle.read()
        self.assertNotIn("m10.835 12.227", text)
        self.assertIn("11.586", text)


if __name__ == "__main__":
    unittest.main()
