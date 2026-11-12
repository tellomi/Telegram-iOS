#!/usr/bin/env python3
"""Seed list, RSA fingerprint order, and the dial-address checker.

    python3 Tellomi/test_server_config.py
"""

import contextlib
import copy
import io
import json
import pathlib
import sys
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "Tellomi"))

import check_server_config as checker  # noqa: E402


def load_config() -> dict:
    return json.loads(checker.JSON_PATH.read_text(encoding="utf-8"))


class SeedContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.config = load_config()

    def test_dial_order_is_the_eight_android_endpoints(self) -> None:
        self.assertEqual(
            checker.EXPECTED_DIAL,
            [
                "1:8.137.198.240:10443",
                "1:8.137.198.240:443",
                "1:api.tellomi.cn:10443",
                "1:api.tellomi.cn:443",
                "2:8.137.198.240:10443",
                "2:8.137.198.240:443",
                "2:api.tellomi.cn:10443",
                "2:api.tellomi.cn:443",
            ],
        )
        for environment in ("production", "testing"):
            entries = checker.dial_entries(
                self.config["seeds"][environment],
                self.config["seed_port"],
                self.config["seed_fallback_ports"],
            )
            self.assertEqual(entries, checker.EXPECTED_DIAL)
        stored = checker.stored_address_list(checker.SEED_HOSTS, checker.SEED_PORTS)
        self.assertEqual(stored[-1], "8.137.198.240:10443")
        self.assertEqual(
            list(reversed(stored)),
            [entry.split(":", 1)[1] for entry in checker.EXPECTED_DIAL if entry.startswith("1:")],
        )
        checker.check_seed_contract(self.config)
        checker.check_seed_implementation()
        checker.check_json_and_header()
        header = checker.HEADER_PATH.read_text(encoding="utf-8")
        self.assertIn("8.137.198.240", header)
        self.assertIn("api.tellomi.cn", header)
        self.assertNotIn("8.156.40.105", header)
        self.assertNotIn("8.137.39.82", header)

    def test_rsa_fingerprint_order_is_unchanged(self) -> None:
        littles = [item["little_endian"] for item in self.config["rsa_fingerprints"]]
        self.assertEqual(littles, ["4381149949997195609", "12240908862933197005"])
        checker.check_rsa_fingerprint_order(self.config)
        swapped = copy.deepcopy(self.config)
        swapped["rsa_fingerprints"] = list(reversed(swapped["rsa_fingerprints"]))
        with self.assertRaises(checker.TellomiConfigError) as caught:
            self._quiet(lambda: checker.check_rsa_fingerprint_order(swapped))
        self.assertIn("4381149949997195609", str(caught.exception))
        self.assertIn("12240908862933197005", str(caught.exception))

    def test_real_surfaces_have_no_forbidden_dial_token(self) -> None:
        checker.check_dial_surfaces()

    def _quiet(self, call) -> None:
        with contextlib.redirect_stderr(io.StringIO()):
            call()

    def _reject(self, config: dict, token: str) -> None:
        with self.assertRaises(checker.TellomiConfigError) as caught:
            self._quiet(lambda: checker.check_seed_contract(config))
        self.assertIn(token, str(caught.exception))

    def test_origin_105_is_rejected(self) -> None:
        config = copy.deepcopy(self.config)
        config["seeds"]["production"]["1"] = ["8.156.40.105", "api.tellomi.cn"]
        self._reject(config, "8.156.40.105")

    def test_retired_82_is_rejected_as_a_seed_and_as_the_a_record(self) -> None:
        seeded = copy.deepcopy(self.config)
        seeded["seeds"]["testing"]["2"] = ["8.137.39.82", "api.tellomi.cn"]
        self._reject(seeded, "8.137.39.82")
        documented = copy.deepcopy(self.config)
        documented["seed_address_a_record"] = "8.137.39.82"
        self._reject(documented, "8.137.39.82")

    def test_port_5222_is_rejected(self) -> None:
        config = copy.deepcopy(self.config)
        config["seed_fallback_ports"] = [443, 5222]
        self._reject(config, "5222")

    def test_incomplete_or_reordered_seed_is_rejected(self) -> None:
        missing_dc2 = copy.deepcopy(self.config)
        del missing_dc2["seeds"]["production"]["2"]
        with self.assertRaises(checker.TellomiConfigError):
            self._quiet(lambda: checker.check_seed_contract(missing_dc2))
        reversed_hosts = copy.deepcopy(self.config)
        reversed_hosts["seeds"]["production"]["1"] = ["api.tellomi.cn", "8.137.198.240"]
        with self.assertRaises(checker.TellomiConfigError):
            self._quiet(lambda: checker.check_seed_contract(reversed_hosts))
        no_443 = copy.deepcopy(self.config)
        no_443["seed_fallback_ports"] = []
        with self.assertRaises(checker.TellomiConfigError):
            self._quiet(lambda: checker.check_seed_contract(no_443))


if __name__ == "__main__":
    unittest.main()
