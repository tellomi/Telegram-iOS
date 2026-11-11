#!/usr/bin/env python3
"""Render the URL types and entitlements Telegram/BUILD generates.

    python3 Tellomi/check_link_launch.py

A pass means the Tellomi configuration's generated Info.plist registers that
configuration's URL scheme, and the generated entitlements for
app.tellomi.chat include applinks:tell.cc. Official Telegram bundle ids keep
the URL schemes and associated domains they already had. This does not sign
an IPA and it does not download the TestFlight provisioning profile.
"""

import json
import pathlib
import plistlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
BUILD = ROOT / "Telegram" / "BUILD"

BUILTIN_SCHEMES = ["telegram", "tg", "tonsite", "ton", "tc"]
OFFICIAL_BUNDLE_IDS = ["ph.telegra.Telegraph", "org.telegram.Telegram-iOS"]
OFFICIAL_DOMAINS = [
    "applinks:tell.cc",
    "applinks:*.tell.cc",
    "applinks:telegram.me",
    "applinks:t.me",
    "applinks:*.t.me",
    "webcredentials:t.me",
    "webcredentials:telegram.org",
]
TELLOMI_DOMAINS = [
    "applinks:tell.cc",
    "applinks:*.tell.cc",
    "webcredentials:tell.cc",
]
PLIST_HEAD = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>"""
PLIST_TAIL = """</dict>
</plist>"""


def fail(message):
    print("FAIL: {}".format(message), file=sys.stderr)
    raise SystemExit(1)


def skip_string(source, index):
    quote = source[index]
    if source.startswith(quote * 3, index):
        end = source.find(quote * 3, index + 3)
        if end < 0:
            fail("unterminated string in Telegram/BUILD")
        return end + 3
    index += 1
    while index < len(source):
        if source[index] == "\\":
            index += 2
            continue
        if source[index] == quote:
            return index + 1
        index += 1
    fail("unterminated string in Telegram/BUILD")


def call_end(source, open_paren):
    depth = 0
    index = open_paren
    while index < len(source):
        char = source[index]
        if char in ("'", '"'):
            index = skip_string(source, index)
            continue
        if char == "#":
            newline = source.find("\n", index)
            index = len(source) if newline < 0 else newline + 1
            continue
        if char == "(":
            depth += 1
        elif char == ")":
            depth -= 1
            if depth == 0:
                return index + 1
        index += 1
    fail("unbalanced plist_fragment call in Telegram/BUILD")


def extract(source, start_marker, rule_name):
    start = source.find(start_marker)
    if start < 0:
        fail("Telegram/BUILD is missing {}".format(start_marker))
    name_at = source.find('name = "{}"'.format(rule_name), start)
    if name_at < 0:
        fail("Telegram/BUILD is missing {}".format(rule_name))
    call_at = source.rfind("plist_fragment(", start, name_at)
    if call_at < 0:
        fail("Telegram/BUILD is missing the {} rule".format(rule_name))
    end = call_end(source, call_at + len("plist_fragment"))
    return source[start:end]


def render(source, variables):
    captured = {}

    def plist_fragment(name, extension, template, defaults=None):
        del extension, defaults
        if "{" in template or "}" in template:
            fail("{} still has a placeholder; the plist rule would look for --define".format(name))
        text = PLIST_HEAD + template + PLIST_TAIL
        try:
            captured[name] = plistlib.loads(text.encode("utf-8"))
        except plistlib.InvalidFileException as error:
            fail("{} is not a plist ({})".format(name, error))

    namespace = dict(variables)
    namespace["plist_fragment"] = plist_fragment
    exec(extract(source, "app_specific_url_scheme_entry =", "UrlTypesInfoPlist"), namespace)
    exec(extract(source, "official_apple_pay_merchants =", "TelegramEntitlements"), namespace)
    if "UrlTypesInfoPlist" not in captured or "TelegramEntitlements" not in captured:
        fail("BUILD did not generate UrlTypesInfoPlist and TelegramEntitlements")
    return captured["UrlTypesInfoPlist"], captured["TelegramEntitlements"]


def url_schemes(plist):
    schemes = []
    for item in plist["CFBundleURLTypes"]:
        schemes.extend(item["CFBundleURLSchemes"])
    return schemes


def domains_of(plist):
    return plist.get("com.apple.developer.associated-domains")


def expect_schemes(plist, scheme, label):
    types = plist["CFBundleURLTypes"]
    if len(types) != 2:
        fail("{} URL types has {} entries".format(label, len(types)))
    if types[0]["CFBundleURLSchemes"] != ["telegram"]:
        fail("{} dropped the telegram scheme".format(label))
    if scheme not in BUILTIN_SCHEMES:
        expected = ["tg", "tonsite", "ton", "tc", scheme]
    else:
        expected = ["tg", "tonsite", "ton", "tc"]
    if types[1]["CFBundleURLSchemes"] != expected:
        fail("{} compatibility schemes are {}".format(label, types[1]["CFBundleURLSchemes"]))
    if url_schemes(plist) != ["telegram"] + expected:
        fail("{} scheme list is {}".format(label, url_schemes(plist)))


def configuration_variables(path):
    config = json.loads(path.read_text(encoding="utf-8"))
    return {
        "telegram_bundle_id": config["bundle_id"],
        "telegram_app_specific_url_scheme": config["app_specific_url_scheme"],
        "telegram_team_id": config["team_id"],
        "telegram_aps_environment": "production",
        "telegram_enable_icloud": config["enable_icloud"],
        "telegram_enable_siri": config["enable_siri"],
    }, config


def check_configuration(source, relative):
    variables, config = configuration_variables(ROOT / relative)
    if config["bundle_id"] != "app.tellomi.chat":
        fail("{} bundle id is {}".format(relative, config["bundle_id"]))
    scheme = config["app_specific_url_scheme"]
    if not scheme or scheme in BUILTIN_SCHEMES:
        fail("{} app_specific_url_scheme is {}".format(relative, scheme))
    urls, entitlements = render(source, variables)
    expect_schemes(urls, scheme, relative)
    if urls["CFBundleURLTypes"][0]["CFBundleURLName"] != config["bundle_id"]:
        fail("{} URL name is not the bundle id".format(relative))
    if domains_of(entitlements) != TELLOMI_DOMAINS:
        fail("{} associated domains are {}".format(relative, domains_of(entitlements)))
    if "applinks:tell.cc" not in domains_of(entitlements):
        fail("{} entitlements do not contain applinks:tell.cc".format(relative))
    sentinel = dict(variables)
    sentinel["telegram_app_specific_url_scheme"] = "zz-from-config"
    sentinel_urls, sentinel_entitlements = render(source, sentinel)
    expect_schemes(sentinel_urls, "zz-from-config", relative + " sentinel")
    if "tellomi" in url_schemes(sentinel_urls):
        fail("{} hardcodes the tellomi scheme".format(relative))
    if domains_of(sentinel_entitlements) != TELLOMI_DOMAINS:
        fail("changing the scheme changed associated domains")
    print("{} {} scheme {}".format(relative, config["bundle_id"], scheme))
    print("  CFBundleURLSchemes: {}".format(", ".join(url_schemes(urls))))
    print("  associated-domains: {}".format(", ".join(domains_of(entitlements))))


def check_official(source):
    example = {}
    exec((ROOT / "build-system/example-configuration/variables.bzl").read_text(encoding="utf-8"), example)
    if example["telegram_bundle_id"] != "ph.telegra.Telegraph":
        fail("example variables bundle id changed")
    if example["telegram_app_specific_url_scheme"] != "tg":
        fail("example variables scheme is not tg")
    for bundle_id in OFFICIAL_BUNDLE_IDS:
        variables = {
            "telegram_bundle_id": bundle_id,
            "telegram_app_specific_url_scheme": example["telegram_app_specific_url_scheme"],
            "telegram_team_id": example["telegram_team_id"],
            "telegram_aps_environment": example["telegram_aps_environment"],
            "telegram_enable_icloud": example["telegram_enable_icloud"],
            "telegram_enable_siri": example["telegram_enable_siri"],
        }
        urls, entitlements = render(source, variables)
        expect_schemes(urls, "tg", bundle_id)
        if domains_of(entitlements) != OFFICIAL_DOMAINS:
            fail("{} associated domains are {}".format(bundle_id, domains_of(entitlements)))
        print("official {} scheme tg".format(bundle_id))
        print("  CFBundleURLSchemes: {}".format(", ".join(url_schemes(urls))))
        print("  associated-domains: {}".format(", ".join(domains_of(entitlements))))


def check_other_bundle(source):
    urls, entitlements = render(source, {
        "telegram_bundle_id": "org.example.App",
        "telegram_app_specific_url_scheme": "example",
        "telegram_team_id": "TEAMID",
        "telegram_aps_environment": "production",
        "telegram_enable_icloud": False,
        "telegram_enable_siri": False,
    })
    expect_schemes(urls, "example", "org.example.App")
    if domains_of(entitlements) is not None:
        fail("a non-Tellomi bundle gained associated domains: {}".format(domains_of(entitlements)))
    print("other org.example.App scheme example")
    print("  CFBundleURLSchemes: {}".format(", ".join(url_schemes(urls))))
    print("  associated-domains: (none)")


def check_loaded_symbol(source):
    marker = 'load(\n    "@build_configuration//:variables.bzl",'
    start = source.find(marker)
    if start < 0:
        fail("Telegram/BUILD does not load variables.bzl")
    block = source[start:source.find(")", start)]
    if '"telegram_app_specific_url_scheme"' not in block:
        fail("Telegram/BUILD does not load telegram_app_specific_url_scheme")


def decode_profile(path):
    data = subprocess.check_output(
        ["openssl", "smime", "-inform", "der", "-verify", "-noverify", "-in", str(path)],
        stderr=subprocess.DEVNULL,
    )
    return plistlib.loads(data)


def check_signing_source():
    suffixes = json.loads((ROOT / "Tellomi/extension-suffixes.json").read_text(encoding="utf-8"))
    main = next(item for item in suffixes["targets"] if item["suffix"] == "")
    if main["profile_file"] != "Telegram":
        fail("main profile file is {}".format(main["profile_file"]))
    if "ASSOCIATED_DOMAINS" not in main["capabilities"]:
        fail("the TestFlight main app does not request ASSOCIATED_DOMAINS")
    signing = (ROOT / "Tellomi/prepare_appstore_signing.py").read_text(encoding="utf-8")
    if "optional=(capability == COMMUNICATION_NOTIFICATIONS_CAPABILITY)" not in signing:
        fail("capability enablement is no longer required")
    prepare = signing.split("def prepare(", 1)[1].split("\ndef ", 1)[0]
    if prepare.find("ensure_capability(") < 0 or prepare.find("ensure_capability(") > prepare.find("create_profile("):
        fail("the profile is created before capabilities are enabled")
    build = BUILD.read_text(encoding="utf-8")
    if 'entitlements = ":TelegramEntitlements.entitlements"' not in build:
        fail("the app no longer signs TelegramEntitlements")
    if "disableProvisioningProfiles" in build and "build_setting_default = True" in build.split("disableProvisioningProfiles", 1)[1][:200]:
        fail("provisioning profiles are disabled by default")
    profile = ROOT / "build-system/fake-codesigning/profiles/Telegram.mobileprovision"
    decoded = decode_profile(profile)
    entitlements = decoded.get("Entitlements") or {}
    print("signing: extension-suffixes.json requests ASSOCIATED_DOMAINS for the main app")
    print("signing: prepare_appstore_signing.py enables that capability before creating the profile, and the enablement is not optional")
    print(
        "signing: {} application-identifier={} associated-domains={!r}".format(
            profile.relative_to(ROOT),
            entitlements.get("application-identifier"),
            entitlements.get("com.apple.developer.associated-domains"),
        )
    )
    print("signing: that checked-in profile is not the TestFlight profile for app.tellomi.chat")


def main():
    source = BUILD.read_text(encoding="utf-8")
    check_loaded_symbol(source)
    check_configuration(source, "build-system/appstore-configuration.json")
    check_configuration(source, "build-system/appcenter-configuration.json")
    check_official(source)
    check_other_bundle(source)
    check_signing_source()
    print("PASS")


if __name__ == "__main__":
    main()
