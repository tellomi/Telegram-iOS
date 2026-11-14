#!/usr/bin/env python3
"""Host checks for backlog classification and result merging. No simulator."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(Path(__file__).resolve().parent))

from tellomi_ui_results import (  # noqa: E402
    DEDICATED_TEST_PHONE_A,
    DEDICATED_TEST_PHONE_B,
    classify,
    counts_by_status,
    device_only_reason,
    load_backlog,
    load_coverage,
    merge,
    parse_result_log,
    test_phone_code,
    ui_test_phone,
)


class PhoneCodeTests(unittest.TestCase):
    def test_server_examples(self):
        self.assertEqual(test_phone_code("9996612345"), "11111")
        self.assertEqual(test_phone_code("9996620001"), "22222")
        self.assertEqual(test_phone_code("9996639999"), "33333")
        self.assertIsNone(test_phone_code("999661234"))
        self.assertIsNone(test_phone_code("9996712345"))
        self.assertIsNone(test_phone_code("8613800138000"))

    def test_99966170xx_is_datacenter_one(self):
        for suffix in ("00", "01", "99"):
            digits = f"99966170{suffix}"
            self.assertEqual(len(digits), 10)
            self.assertEqual(test_phone_code(digits), "11111")
        self.assertNotEqual(test_phone_code("9996617001"), "12345")

    def test_ui_run_accepts_only_99966170xx(self):
        self.assertEqual(ui_test_phone(DEDICATED_TEST_PHONE_A), "9996617090")
        self.assertEqual(ui_test_phone("+999 661 7091"), DEDICATED_TEST_PHONE_B)
        self.assertEqual(ui_test_phone("9996617001"), "9996617001")
        self.assertIsNone(ui_test_phone("9996612345"))
        self.assertIsNone(ui_test_phone("9996620001"))
        self.assertIsNone(ui_test_phone("8613800138000"))
        self.assertIsNone(ui_test_phone("999661709"))
        self.assertIsNone(ui_test_phone("99966170900"))
        for dedicated in (DEDICATED_TEST_PHONE_A, DEDICATED_TEST_PHONE_B):
            suffix = int(dedicated[-4:])
            self.assertFalse(7001 <= suffix <= 7089)


class ClassifyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.rows = load_backlog(ROOT / "backlog.csv")
        cls.coverage = load_coverage(ROOT / "Sources")
        cls.manifest = classify(cls.rows, cls.coverage)

    def test_backlog_size(self):
        self.assertEqual(len(self.rows), 928)
        self.assertEqual(len({row["id"] for row in self.rows}), 928)
        self.assertEqual(len(self.manifest), 928)

    def test_every_id_once(self):
        self.assertEqual(set(self.manifest), {row["id"] for row in self.rows})

    def test_device_only_examples(self):
        by_id = {row["id"]: row for row in self.rows}
        self.assertIsNotNone(device_only_reason(by_id["I-PERMISSIONS-001"]))
        self.assertIsNotNone(device_only_reason(by_id["I-PERMISSIONS-007"]))
        self.assertIsNotNone(device_only_reason(by_id["I-PERMISSIONS-009"]))
        self.assertIsNotNone(device_only_reason(by_id["I-PERMISSIONS-010"]))
        self.assertEqual(self.manifest["I-PERMISSIONS-001"]["status"], "device_only")
        self.assertEqual(self.manifest["I-PERMISSIONS-007"]["status"], "device_only")
        notifications = [row["id"] for row in self.rows if row["区域"] == "Notifications"]
        self.assertEqual(len(notifications), 51)
        for backlog_id in notifications:
            self.assertEqual(self.manifest[backlog_id]["status"], "device_only", backlog_id)

    def test_calls_tab_toggle_is_not_device_only(self):
        self.assertEqual(self.manifest["I-SETTINGS-449"]["status"], "automated")
        self.assertNotEqual(self.manifest["I-IDX-BRAND-010"]["status"], "device_only")
        self.assertNotEqual(self.manifest["I-DISCOVER-048"]["status"], "device_only")
        self.assertNotEqual(self.manifest["I-PERMISSIONS-002"]["status"], "device_only")
        self.assertNotEqual(self.manifest["I-PERMISSIONS-005"]["status"], "device_only")

    def test_automated_ids_match_swift(self):
        automated = {backlog_id for backlog_id, entry in self.manifest.items() if entry["status"] == "automated"}
        declared = {backlog_id for ids in self.coverage.values() for backlog_id in ids}
        self.assertEqual(automated, declared)
        self.assertIn("I-LOGIN-191", automated)
        self.assertIn("I-DEEPLINKS-017", automated)
        self.assertIn("I-DISCOVER-070", automated)
        self.assertIn("I-SETTINGS-500", automated)
        self.assertNotIn("I-TRANSLATION-014", automated)

    def test_counts_cover_the_backlog(self):
        counts = counts_by_status(self.manifest)
        self.assertEqual(sum(counts.values()), 928)
        self.assertGreater(counts["device_only"], 51)
        self.assertGreater(counts["automated"], 20)
        self.assertGreater(counts["blocked"], counts["automated"])


class MergeTests(unittest.TestCase):
    def test_overlay_and_device_only_stick(self):
        rows = load_backlog(ROOT / "backlog.csv")
        manifest = classify(rows, load_coverage(ROOT / "Sources"))
        shard = {
            "results": {
                "I-LOGIN-191": {"status": "pass", "test": "phoneEntry", "screenshot": "screenshots/phone.png", "error": None},
                "I-LOGIN-121": {"status": "fail", "test": "phoneField", "screenshot": "screenshots/phone.png", "error": "label is Next"},
            }
        }
        merged = merge(manifest, [shard])
        self.assertEqual(merged["results"]["I-LOGIN-191"]["status"], "pass")
        self.assertEqual(merged["results"]["I-LOGIN-121"]["status"], "fail")
        self.assertEqual(merged["results"]["I-LOGIN-121"]["error"], "label is Next")
        self.assertEqual(merged["results"]["I-PERMISSIONS-007"]["status"], "device_only")
        self.assertEqual(merged["results"]["I-LOGIN-005"]["status"], "blocked")
        self.assertEqual(sum(merged["counts"].values()), 928)

    def test_missing_automated_report_stays_blocked(self):
        rows = load_backlog(ROOT / "backlog.csv")
        manifest = classify(rows, load_coverage(ROOT / "Sources"))
        merged = merge(manifest, [{"results": {}}])
        self.assertEqual(merged["results"]["I-LOGIN-191"]["status"], "blocked")
        self.assertIn("did not report", merged["results"]["I-LOGIN-191"]["error"])

    def test_device_only_cannot_be_overwritten(self):
        rows = load_backlog(ROOT / "backlog.csv")
        manifest = classify(rows, load_coverage(ROOT / "Sources"))
        with self.assertRaises(SystemExit):
            merge(manifest, [{"results": {"I-PERMISSIONS-010": {"status": "pass"}}}])

    def test_log_parser(self):
        text = '2026-11-14 Tellomi[1:1] TELLOMI_UI_RESULT\tI-LOGIN-191\tpass\t\nnoise\nTELLOMI_UI_RESULT\tI-LOGIN-121\tfail\tlabel is Next\n'
        parsed = parse_result_log(text)
        self.assertEqual(parsed["I-LOGIN-191"]["status"], "pass")
        self.assertEqual(parsed["I-LOGIN-121"]["error"], "label is Next")


class ProjectTests(unittest.TestCase):
    def test_sources_are_in_the_xcode_project(self):
        project = (ROOT / "TellomiClientUITests.xcodeproj" / "project.pbxproj").read_text(encoding="utf-8")
        for path in sorted((ROOT / "Sources").glob("*.swift")):
            self.assertIn(path.name, project, path.name)


if __name__ == "__main__":
    unittest.main(verbosity=2)
