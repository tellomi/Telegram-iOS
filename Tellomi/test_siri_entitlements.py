#!/usr/bin/env python3
"""SiriIntents launch crash: the signed entitlement must follow the profile.

    python3 Tellomi/test_siri_entitlements.py
"""

import json
import pathlib
import sys
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "Tellomi"))

import check_server_config as checker  # noqa: E402
import siri_entitlements as siri  # noqa: E402
from extension_suffixes import siri_intents_suffix, targets  # noqa: E402


class SiriEntitlementDecisionTests(unittest.TestCase):
    def test_only_a_real_true_grants_siri(self) -> None:
        self.assertTrue(siri.profile_grants_siri({"com.apple.developer.siri": True}))
        self.assertFalse(siri.profile_grants_siri({}))
        self.assertFalse(siri.profile_grants_siri(None))
        self.assertFalse(siri.profile_grants_siri({"com.apple.developer.siri": False}))
        self.assertFalse(siri.profile_grants_siri({"com.apple.developer.siri": "true"}))

    def test_signed_build_requests_siri_only_when_the_profile_grants_it(self) -> None:
        self.assertTrue(siri.signed_siri_entitlement(True, provisioning_disabled=False))
        self.assertFalse(siri.signed_siri_entitlement(False, provisioning_disabled=False))
        self.assertFalse(siri.signed_siri_entitlement(None, provisioning_disabled=False))

    def test_unsigned_build_includes_the_key(self) -> None:
        self.assertTrue(siri.signed_siri_entitlement(False, provisioning_disabled=True))
        self.assertTrue(siri.signed_siri_entitlement(None, provisioning_disabled=True))


class HostBundleIdTests(unittest.TestCase):
    def test_siri_extension_strips_to_the_tellomi_host_and_app_group(self) -> None:
        config = json.loads((ROOT / "build-system/appstore-configuration.json").read_text(encoding="utf-8"))
        host = config["bundle_id"]
        extension = host + siri_intents_suffix()
        self.assertEqual(extension, "app.tellomi.chat.SiriIntents")
        self.assertEqual(siri.host_bundle_id(extension), host)
        self.assertEqual(siri.app_group_identifier(host), "group.app.tellomi.chat")

    def test_a_bundle_id_without_a_suffix_is_not_treated_as_an_extension(self) -> None:
        self.assertIsNone(siri.host_bundle_id("app"))
        self.assertIsNone(siri.host_bundle_id(""))
        self.assertIsNone(siri.host_bundle_id(None))

    def test_intent_handler_uses_that_strip(self) -> None:
        source = (ROOT / "Telegram/SiriIntents/IntentHandler.swift").read_text(encoding="utf-8")
        self.assertIn("String(appBundleIdentifier[..<lastDotRange.lowerBound])", source)
        self.assertIn('let appGroupName = "group.\\(baseAppBundleId)"', source)

    def test_siri_targets_keep_the_app_group_and_sirikit(self) -> None:
        by_suffix = {item["suffix"]: item for item in targets()}
        main = by_suffix[""]
        intents = by_suffix[".SiriIntents"]
        self.assertIn("APP_GROUPS", main["capabilities"])
        self.assertIn("SIRIKIT", main["capabilities"])
        self.assertIn("APP_GROUPS", intents["capabilities"])
        self.assertIn("SIRIKIT", intents["capabilities"])
        for item in targets():
            if not item.get("register"):
                continue
            self.assertIn("APP_GROUPS", item["capabilities"])


class BuildWiringTests(unittest.TestCase):
    def test_siri_intents_signs_its_own_entitlements(self) -> None:
        checker.check_wiring()


if __name__ == "__main__":
    unittest.main()
