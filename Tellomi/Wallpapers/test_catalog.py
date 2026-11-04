#!/usr/bin/env python3
"""Cross-check WallpaperCatalog.json, the Swift catalog, and the bundled tiles."""

import gzip
import json
import os
import re
import unittest

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
JSON_PATH = os.path.join(ROOT, "Tellomi", "Wallpapers", "WallpaperCatalog.json")
SWIFT_PATH = os.path.join(ROOT, "submodules", "TellomiWallpapers", "Sources", "TellomiWallpapers.swift")
TGV_DIR = os.path.join(ROOT, "submodules", "TelegramUI", "Resources")

ACCENTS = [
    ("蓝", "3390EC"),
    ("天青", "2AABEE"),
    ("青", "00A8A8"),
    ("绿", "31B545"),
    ("薄荷", "25D366"),
    ("黄", "F5A623"),
    ("橙", "FF8A3D"),
    ("红", "E5484D"),
    ("粉", "EC4899"),
    ("紫", "8B5CF6"),
    ("靛", "5B5BD6"),
    ("石墨", "5F6B7A"),
]


def signed_intensity(entry):
    percent = entry["intensityPercent"]
    if percent is None:
        return None
    if entry["patternTone"] == "light":
        return -percent
    if entry["patternTone"] == "dark":
        return percent
    raise AssertionError(entry["id"])


class CatalogTests(unittest.TestCase):
    def test_json_matches_the_plan(self):
        catalog = json.load(open(JSON_PATH, encoding="utf-8"))
        accents = [(item["name"], item["hex"]) for item in catalog["accentColors"]]
        self.assertEqual(accents, ACCENTS)
        self.assertTrue(catalog["accentColors"][0]["isDefault"])
        self.assertEqual(catalog["solid"], {"light": "F0F2F5", "dark": "101418"})
        self.assertEqual(catalog["bubbles"]["incomingLight"], "FFFFFF")
        self.assertEqual(catalog["bubbles"]["incomingDark"], "202C33")
        self.assertEqual(catalog["bubbles"]["solidShadowRadiusPt"], 0.5)
        self.assertEqual(len(catalog["wallpapers"]), 10)
        light = catalog["wallpapers"][0]
        dark = catalog["wallpapers"][1]
        self.assertEqual(light["id"], "tm_doodle_light")
        self.assertEqual(light["colors"], ["EFE7DD"])
        self.assertEqual(signed_intensity(light), 12)
        self.assertEqual(dark["id"], "tm_doodle_dark")
        self.assertEqual(dark["colors"], ["0B141A", "16232B"])
        self.assertEqual(signed_intensity(dark), -8)
        self.assertIsNone(catalog["wallpapers"][6]["pattern"])
        self.assertIsNone(catalog["wallpapers"][9]["pattern"])

    def test_swift_catalog_matches_json(self):
        catalog = json.load(open(JSON_PATH, encoding="utf-8"))
        source = open(SWIFT_PATH, encoding="utf-8").read()
        accents = re.findall(r'TellomiAccentColor\(name: "([^"]+)", rgb: 0x([0-9A-Fa-f]{6})\)', source)
        self.assertEqual([(name, rgb.upper()) for name, rgb in accents], ACCENTS)
        ids = re.findall(r'id: "(tm_[a-z0-9_]+)"', source)
        self.assertEqual(ids, [item["id"] for item in catalog["wallpapers"]])
        for entry in catalog["wallpapers"]:
            colors = ", ".join("0x" + color for color in entry["colors"])
            self.assertIn(f'id: "{entry["id"]}"', source)
            self.assertIn(f"colors: [{colors}]", source)
            intensity = signed_intensity(entry)
            if intensity is None:
                self.assertIn(f'id: "{entry["id"]}", name: "{entry["name"]}", pattern: nil', source)
            else:
                self.assertIn(f"intensity: {intensity}", source)
        self.assertIn("lightSolid: UInt32 = 0xF0F2F5", source)
        self.assertIn("darkSolid: UInt32 = 0x101418", source)
        self.assertIn("incomingLight: UInt32 = 0xFFFFFF", source)
        self.assertIn("incomingDark: UInt32 = 0x202C33", source)
        self.assertIn("radius: Double = 0.5", source)
        for phrase in ("Tabler Icons", "MIT", "Lucide", "ISC", "Steve Schoger", "CC BY 4.0", "Topography", "Polka Dots"):
            self.assertIn(phrase, source)

    def test_bundled_tiles_are_original_gzipped_svg(self):
        for name in ("doodle", "dots", "waves"):
            path = os.path.join(TGV_DIR, f"tm_{name}.tgv")
            raw = open(path, "rb").read()
            svg = gzip.decompress(raw).decode("utf-8")
            self.assertIn("<svg", svg)
            lowered = svg.lower()
            self.assertNotIn("whatsapp", lowered)
            self.assertNotIn("telegram", lowered)
            svg_copy = open(os.path.join(ROOT, "Tellomi", "Wallpapers", f"{name}.svg"), encoding="utf-8").read()
            self.assertEqual(svg, svg_copy)
        doodle = gzip.decompress(open(os.path.join(TGV_DIR, "tm_doodle.tgv"), "rb").read()).decode("utf-8")
        self.assertIn('id="lucide-', doodle)
        self.assertIn('id="tabler-', doodle)
        self.assertGreaterEqual(doodle.count("<g id="), 60)
        dots = gzip.decompress(open(os.path.join(TGV_DIR, "tm_dots.tgv"), "rb").read()).decode("utf-8")
        self.assertGreater(dots.count("<circle "), 1000)

    def test_new_swift_does_not_import_postbox(self):
        for path in (
            SWIFT_PATH,
            os.path.join(ROOT, "submodules", "TellomiWallpapers", "Tests", "TellomiWallpapersTests.swift"),
            os.path.join(ROOT, "submodules", "SettingsUI", "Sources", "TellomiOpenSourceLicensesController.swift"),
        ):
            text = open(path, encoding="utf-8").read()
            self.assertNotIn("import Postbox", text)


if __name__ == "__main__":
    unittest.main()
