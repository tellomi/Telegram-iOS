#!/usr/bin/env python3
"""Static checks for the Tellomi server config and the rebrand wiring.

No Xcode or Bazel required:

    python3 Tellomi/check_server_config.py
"""

import base64
import hashlib
import json
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "Tellomi"))
sys.path.insert(0, str(ROOT / "build-system" / "Make"))

from generate_server_config import HEADER_PATH, JSON_PATH, header_text  # noqa: E402


def fail(message: str) -> None:
    print(f"FAIL: {message}", file=sys.stderr)
    raise SystemExit(1)


def der_len(n: int) -> bytes:
    if n < 128:
        return bytes([n])
    raw = n.to_bytes((n.bit_length() + 7) // 8, "big")
    return bytes([0x80 | len(raw)]) + raw


def der_int(value: int) -> bytes:
    raw = value.to_bytes((value.bit_length() + 7) // 8, "big")
    if raw[0] & 0x80:
        raw = b"\x00" + raw
    return b"\x02" + der_len(len(raw)) + raw


def pkcs1_public_key(pem: str):
    body = "".join(
        line for line in pem.splitlines()
        if line and not line.startswith("-----")
    )
    der = base64.b64decode(body)
    # RSAPublicKey ::= SEQUENCE { n INTEGER, e INTEGER }
    if der[0] != 0x30:
        fail("public key is not a DER sequence")
    # Skip the sequence header; the two integers follow.
    index = 1
    length = der[index]
    index += 1
    if length & 0x80:
        count = length & 0x7F
        index += count

    def read_int(data: bytes, at: int):
        if data[at] != 0x02:
            fail("expected INTEGER in the public key")
        at += 1
        size = data[at]
        at += 1
        if size & 0x80:
            count = size & 0x7F
            size = int.from_bytes(data[at:at + count], "big")
            at += count
        raw = data[at:at + size]
        at += size
        if raw[:1] == b"\x00":
            raw = raw[1:]
        return int.from_bytes(raw, "big"), at

    modulus, index = read_int(der, index)
    exponent, index = read_int(der, index)
    if index != len(der):
        fail("trailing bytes in the public key")
    return modulus, exponent


def tl_bytes(data: bytes) -> bytes:
    length = len(data)
    if length == 0:
        return b"\x00\x00\x00\x00"
    out = bytearray()
    if length >= 254:
        out.append(254)
        out.extend(length.to_bytes(4, "little")[:3])
        pad = (4 - (length % 4)) % 4
    else:
        out.append(length)
        pad = (4 - ((length + 1) % 4)) % 4
    out.extend(data)
    out.extend(b"\x00" * pad)
    return bytes(out)


def fingerprints(pem: str):
    modulus, exponent = pkcs1_public_key(pem)
    n = modulus.to_bytes((modulus.bit_length() + 7) // 8, "big")
    e = exponent.to_bytes((exponent.bit_length() + 7) // 8, "big")
    digest = hashlib.sha1(tl_bytes(n) + tl_bytes(e)).digest()
    big = int.from_bytes(digest[12:20], "big")
    little = int.from_bytes(digest[12:20], "little")
    return big, little


def objc_unescape(literal: str) -> str:
    out = []
    i = 0
    while i < len(literal):
        ch = literal[i]
        if ch != "\\":
            out.append(ch)
            i += 1
            continue
        nxt = literal[i + 1]
        if nxt == "n":
            out.append("\n")
        elif nxt == "r":
            out.append("\r")
        elif nxt == "\\":
            out.append("\\")
        elif nxt == '"':
            out.append('"')
        else:
            fail(f"unexpected ObjC escape \\{nxt}")
        i += 2
    return "".join(out)


def check_json_and_header() -> dict:
    json_text = JSON_PATH.read_text(encoding="utf-8")
    config = json.loads(json_text)
    canonical = json.dumps(config, indent=2, ensure_ascii=True) + "\n"
    if json_text != canonical:
        fail("tellomi-server.json is not canonical; rerun generate_server_config.py")
    expected = header_text(json_text)
    actual = HEADER_PATH.read_text(encoding="utf-8")
    if actual != expected:
        fail("TellomiServerConfigJSON.h is stale; rerun generate_server_config.py")
    prefix = '#define TELLOMI_SERVER_CONFIG_JSON @"'
    line = [row for row in actual.splitlines() if row.startswith(prefix)]
    if len(line) != 1 or not line[0].endswith('"'):
        fail("generated header is not one ObjC string")
    embedded = objc_unescape(line[0][len(prefix):-1])
    if json.loads(embedded) != config:
        fail("embedded JSON does not parse back to the file")
    return config


def check_keys(config: dict) -> None:
    if config["default_datacenter_id"] != 1:
        fail("default datacenter is not 1")
    if config["seed_port"] != 10443:
        fail("seed port is not Teamgram's published 10443")
    if config["disable_telegram_backup_discovery"] is not True:
        fail("Telegram backup discovery must stay disabled for the Teamgram default")
    if config.get("local_docker_seed") != "127.0.0.1":
        fail("local docker seed option is not 127.0.0.1")
    if config.get("seed_address_a_record") != "8.137.39.82":
        fail("documented A record is not 8.137.39.82")
    seed_text = json.dumps(config["seeds"])
    if "127.0.0.1" in seed_text or "8.137.39.82" in seed_text:
        fail("the IP literals are documented only and must not be active seeds")
    for environment in ("production", "testing"):
        hosts = config["seeds"][environment]["1"]
        if hosts != ["api.tellomi.cn"]:
            fail(f"{environment} seeds are not api.tellomi.cn")
        pems = config["public_keys"][environment]
        if len(pems) != 1:
            fail(f"{environment} must ship one public key")
        big, little = fingerprints(pems[0])
        if str(big) != config["rsa_fingerprint_sha1_tail_big_endian"]:
            fail(f"big-endian fingerprint is {big}, JSON says {config['rsa_fingerprint_sha1_tail_big_endian']}")
        if str(little) != config["rsa_fingerprint_sha1_tail_little_endian"]:
            fail(f"little-endian fingerprint is {little}, JSON says {config['rsa_fingerprint_sha1_tail_little_endian']}")
        if little != 12240908862933197005:
            fail("key is not Teamgram's development public key")
        if big != 14798846482072068265:
            fail("client fingerprint of the Teamgram key changed")
        # The handshake accepts either orientation. They are byte swaps of each other.
        swapped = int.from_bytes(big.to_bytes(8, "big"), "little")
        if swapped != little:
            fail("fingerprint byte swap is not the inverse of the two readings")
        with open("/tmp/tellomi-check-pub.pem", "w", encoding="utf-8") as handle:
            handle.write(pems[0] if pems[0].endswith("\n") else pems[0] + "\n")
        result = subprocess.run(
            ["openssl", "rsa", "-RSAPublicKey_in", "-in", "/tmp/tellomi-check-pub.pem", "-pubin", "-noout"],
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            fail("openssl rejected the public key: " + result.stderr)


def check_build_configuration() -> None:
    from BuildConfiguration import build_configuration_from_json

    for name in (
        "build-system/appstore-configuration.json",
        "build-system/appcenter-configuration.json",
        "build-system/template_minimal_development_configuration.json",
    ):
        config = build_configuration_from_json(str(ROOT / name))
        if config.bundle_id != "app.tellomi.chat":
            fail(f"{name} bundle id is {config.bundle_id}")
        if config.app_name != "Tellomi":
            fail(f"{name} app name is {config.app_name}")
        if config.api_id != "100001" or config.api_hash != "74656c6c6f6d69000000000000000000":
            fail(f"{name} is not using the placeholder api id and hash")
        if config.api_id == "8":
            fail(f"{name} still uses Telegram's api_id")
        if config.team_id != "CB7KP6GBAR":
            fail(f"{name} team id is {config.team_id}")
        if config.enable_siri or config.enable_icloud:
            fail(f"{name} enables Siri or iCloud before signing entitlements exist")
        if config.is_appstore_build != "false":
            fail(f"{name} is still marked as an App Store build")
        if config.app_specific_url_scheme != "tellomi":
            fail(f"{name} url scheme is {config.app_specific_url_scheme}")


def check_public_links() -> None:
    source = (ROOT / "submodules/TellomiLinks/Sources/TellomiLinks.swift").read_text(encoding="utf-8")
    if 'public static let host = "tell.cc"' not in source:
        fail("TellomiLinks.host is not tell.cc")
    if 'public static let urlScheme = "tellomi"' not in source:
        fail("TellomiLinks.urlScheme is not tellomi")
    build = (ROOT / "Telegram/BUILD").read_text(encoding="utf-8")
    if "applinks:tell.cc" not in build or "webcredentials:tell.cc" not in build:
        fail("associated domains do not name tell.cc")
    if "applinks:t.me" in build or "applinks:telegram" in build or "webcredentials:t.me" in build or "webcredentials:telegram.org" in build:
        fail("Telegram associated domains are still in the entitlements")
    association = json.loads((ROOT / "Tellomi/well-known/apple-app-site-association").read_text(encoding="utf-8"))
    app_ids = []
    for detail in association["applinks"]["details"]:
        if "appID" in detail:
            app_ids.append(detail["appID"])
        app_ids.extend(detail.get("appIDs") or [])
    if app_ids != ["CB7KP6GBAR.app.tellomi.chat", "CB7KP6GBAR.app.tellomi.chat"]:
        fail(f"apple-app-site-association app ids are {app_ids}")
    if association["webcredentials"]["apps"] != ["CB7KP6GBAR.app.tellomi.chat"]:
        fail("webcredentials app id is wrong")
    config = json.loads((ROOT / "build-system/appstore-configuration.json").read_text(encoding="utf-8"))
    if config.get("app_specific_url_scheme") != "tellomi":
        fail("app_specific_url_scheme is not tellomi")
    leftover = []
    for path in (ROOT / "submodules").rglob("*.swift"):
        rel = str(path.relative_to(ROOT))
        if "/Tests/" in rel or rel.endswith("TellomiLinks.swift"):
            continue
        text = path.read_text(encoding="utf-8", errors="replace")
        if "https://t.me" in text or "://t.me/" in text or '"t.me/' in text or '"t.me"' in text or "telegram.me" in text or "telegram.dog" in text:
            leftover.append(rel)
    if leftover:
        fail("telegram public-link hosts remain in " + ", ".join(leftover[:12]))


def check_extension_suffixes(build: str, variables: str) -> None:
    from BuildConfiguration import BuildConfiguration, extension_profile_mapping
    from extension_suffixes import bazel_suffix_lines, profile_name_mapping, targets
    from prepare_appstore_signing import capability_settings, signing_targets

    if capability_settings("APP_GROUPS", "group.app.tellomi.chat") != []:
        fail("APP_GROUPS capability settings must be an empty list")
    if capability_settings("SIRIKIT", "group.app.tellomi.chat") != []:
        fail("capability settings must be an empty list")
    if extension_profile_mapping() != profile_name_mapping():
        fail("profile suffix mapping does not read extension-suffixes.json")

    signed = signing_targets()
    expected = [
        (item["suffix"], item["name"], item["asc_profile_name"], list(item["capabilities"]))
        for item in targets()
        if item.get("register")
    ]
    if signed != expected:
        fail("signing targets do not match extension-suffixes.json")
    for item in targets():
        if item.get("register") and "APP_GROUPS" not in item["capabilities"]:
            fail("registered target {} is missing APP_GROUPS".format(item["suffix"] or "(main)"))
    siri = next(item for item in targets() if item.get("profile_file") == "Intents")
    if "SIRIKIT" not in siri["capabilities"]:
        fail("SiriIntents must enable SiriKit")
    main = next(item for item in targets() if item["suffix"] == "")
    if main["capabilities"] != ["PUSH_NOTIFICATIONS", "APP_GROUPS", "ASSOCIATED_DOMAINS"]:
        fail("main app capabilities changed")

    for line in bazel_suffix_lines().splitlines():
        if line not in variables:
            fail("example variables.bzl is missing " + line)
        variable = line.split(" = ", 1)[0]
        if variable not in build:
            fail("Telegram/BUILD does not use " + variable)

    configuration = BuildConfiguration(
        bundle_id="app.tellomi.chat",
        api_id="100001",
        api_hash="74656c6c6f6d69000000000000000000",
        team_id="CB7KP6GBAR",
        app_center_id="",
        is_internal_build="true",
        is_appstore_build="false",
        appstore_id="0",
        app_specific_url_scheme="tellomi",
        premium_iap_product_id="app.tellomi.chat.premium.monthly",
        enable_siri=False,
        enable_icloud=False,
        app_name="Tellomi",
    )
    written_path = "/tmp/tellomi-variables-check.bzl"
    configuration.write_to_variables_file("bazel", False, "production", written_path)
    written = pathlib.Path(written_path).read_text(encoding="utf-8")
    for line in bazel_suffix_lines().splitlines():
        if line not in written:
            fail("variables.bzl writer dropped " + line)


def check_wiring() -> None:
    network = (ROOT / "submodules/TelegramCore/Sources/Network/Network.swift").read_text(encoding="utf-8")
    if "149.154.175.50" in network or "TellomiSeedAddresses" not in network:
        fail("Network.swift is not using Tellomi seed addresses")
    if "TellomiDisablesTelegramBackupDiscovery" not in network:
        fail("backup discovery is not gated")
    account = (ROOT / "submodules/TelegramCore/Sources/Account/Account.swift").read_text(encoding="utf-8")
    if "TellomiDefaultDatacenterId" not in account or "initialDatacenterId: Int = 2" in account:
        fail("the first connection still prefers Telegram datacenter 2")
    auth = (ROOT / "submodules/MtProtoKit/Sources/MTDatacenterAuthMessageService.m").read_text(encoding="utf-8")
    if "TellomiServerPublicKeys" not in auth or "MTDatacenterAuthFingerprintByteSwap" not in auth:
        fail("the handshake is not using the Tellomi key or the fingerprint byte swap")
    if "MIIBCgKCAQEA6LszBcC1" in auth:
        fail("Telegram's production RSA key is still the default")
    build = (ROOT / "Telegram/BUILD").read_text(encoding="utf-8")
    if 'app_icons = ["//:TellomiAppIcon"]' not in build:
        fail("the home-screen icon is not the Tellomi brand icon")
    if build.count('entitlements = ":ExtensionAppGroupEntitlements.entitlements"') != 6:
        fail("every extension that opens the app group must sign that entitlement")
    if 'telegram_app_name' not in build:
        fail("the Bazel app name is not wired")
    variables = (ROOT / "build-system/example-configuration/variables.bzl").read_text(encoding="utf-8")
    if 'telegram_bundle_id = "app.tellomi.chat"' not in variables or 'telegram_app_name = "Tellomi"' not in variables:
        fail("example variables.bzl is not Tellomi")
    if 'telegram_team_id = "CB7KP6GBAR"' not in variables:
        fail("example variables.bzl team id is not CB7KP6GBAR")
    check_extension_suffixes(build, variables)
    logo = (ROOT / "Tellomi/Brand/logo.svg").read_text(encoding="utf-8")
    asset = (ROOT / "Tellomi/Brand/AppIcon.icon/Assets/Logo.svg").read_text(encoding="utf-8")
    if "M485.73 20.63" not in logo or "M481.88 248.76" not in logo:
        fail("Tellomi/Brand/logo.svg is not the traced logo")
    if "M485.73 20.63" not in asset or "M481.88 248.76" not in asset:
        fail("the app icon SVG does not use the traced logo paths")
    icon_json = (ROOT / "Tellomi/Brand/AppIcon.icon/icon.json").read_text(encoding="utf-8")
    if "0.06667,0.06667,0.07451" not in icon_json or '"appearance" : "tinted"' not in icon_json:
        fail("the icon composer file is missing the light color or the tinted variant")


def check_marketing_version() -> None:
    version = (ROOT / "Tellomi" / "version").read_text(encoding="utf-8").strip()
    versions = json.loads((ROOT / "versions.json").read_text(encoding="utf-8"))
    if version != versions.get("app"):
        fail(f"Tellomi/version {version} does not match versions.json app {versions.get('app')}")
    if version == "13.1.1":
        fail("marketing version is still Telegram 13.1.1")
    build = (ROOT / "Telegram/BUILD").read_text(encoding="utf-8")
    if "Tellomi/version" not in build:
        fail("VersionInfoPlist does not read Tellomi/version")


def main() -> None:
    config = check_json_and_header()
    check_keys(config)
    check_build_configuration()
    check_public_links()
    check_wiring()
    check_marketing_version()
    print("Tellomi server config checks passed")


if __name__ == "__main__":
    main()
