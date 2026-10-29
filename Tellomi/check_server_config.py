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
    for environment in ("production", "testing"):
        hosts = config["seeds"][environment]["1"]
        if hosts != ["8.137.39.82"]:
            fail(f"{environment} seeds are not the Tellomi dev server")
    if config.get("local_docker_seed") != "127.0.0.1":
        fail("local docker seed option is not 127.0.0.1")
    if "127.0.0.1" in json.dumps(config["seeds"]):
        fail("127.0.0.1 is documented only and must not be an active seed")
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
        if config.bundle_id != "com.tellomi.app":
            fail(f"{name} bundle id is {config.bundle_id}")
        if config.app_name != "Tellomi":
            fail(f"{name} app name is {config.app_name}")
        if config.api_id != "100001" or config.api_hash != "74656c6c6f6d69000000000000000000":
            fail(f"{name} is not using the placeholder api id and hash")
        if config.api_id == "8":
            fail(f"{name} still uses Telegram's api_id")
        if config.team_id != "TELL0MIDEV":
            fail(f"{name} team id is not the placeholder")
        if config.enable_siri or config.enable_icloud:
            fail(f"{name} enables Siri or iCloud before signing entitlements exist")
        if config.is_appstore_build != "false":
            fail(f"{name} is still marked as an App Store build")
        if config.app_specific_url_scheme != "tellomi":
            fail(f"{name} url scheme is {config.app_specific_url_scheme}")


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
    if 'composer_icon_folders = ["TellomiPlaceholder"]' not in build:
        fail("the home-screen icon is not the placeholder")
    if build.count('entitlements = ":ExtensionAppGroupEntitlements.entitlements"') != 6:
        fail("every extension that opens the app group must sign that entitlement")
    if 'telegram_app_name' not in build:
        fail("the Bazel app name is not wired")
    variables = (ROOT / "build-system/example-configuration/variables.bzl").read_text(encoding="utf-8")
    if 'telegram_bundle_id = "com.tellomi.app"' not in variables or 'telegram_app_name = "Tellomi"' not in variables:
        fail("example variables.bzl is not Tellomi")
    icon = ROOT / "Telegram/Telegram-iOS/TellomiPlaceholder.icon/Assets/Plane.svg"
    if "Placeholder-T" not in icon.read_text(encoding="utf-8"):
        fail("placeholder icon is missing the T mark")
    if "PLACEHOLDER" not in (ROOT / "Telegram/Telegram-iOS/TellomiPlaceholder-ICON-PLACEHOLDER.txt").read_text(encoding="utf-8"):
        fail("placeholder icon is not marked")


def main() -> None:
    config = check_json_and_header()
    check_keys(config)
    check_build_configuration()
    check_wiring()
    print("Tellomi server config checks passed")


if __name__ == "__main__":
    main()
