#!/usr/bin/env python3
"""Contract for the official iOS restore against the released 14.0.4 identity.

Runs with the system Python. It does not compile, sign, or open a socket.

    python3 Tellomi/check_restore_contract.py

What a pass means: the source still has the Tellomi seed, layer 232, the
14.0.4 bundle and database-key inputs, and the login error handling below.
It does not mean a device logged in, sent a message, or kept a 14.0.4 database.
"""

import json
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
RELEASE_BUILD_CONFIG = "3c5c3c71586ba09fe151c32f2142cbd9a2b35350"
# build-system/appstore-configuration.json on release/ios c75e2177 (14.0.4 build 73).
RELEASE_IDENTITY = {
    "bundle_id": "app.tellomi.chat",
    "api_id": "100001",
    "api_hash": "74656c6c6f6d69000000000000000000",
    "team_id": "CB7KP6GBAR",
    "app_specific_url_scheme": "tellomi",
}


def fail(message: str) -> None:
    print(f"FAIL: {message}", file=sys.stderr)
    raise SystemExit(1)


def read(relative: str) -> str:
    path = ROOT / relative
    if not path.is_file():
        fail(f"missing {relative}")
    return path.read_text(encoding="utf-8")


def check_server() -> None:
    config = json.loads(read("Tellomi/tellomi-server.json"))
    if config["default_datacenter_id"] != 1 or config["seed_port"] != 10443:
        fail("seed is not datacenter 1 port 10443")
    if config["disable_telegram_backup_discovery"] is not True:
        fail("Telegram backup discovery is not disabled")
    for environment in ("production", "testing"):
        if config["seeds"][environment]["1"] != ["api.tellomi.cn"]:
            fail(f"{environment} seed is not api.tellomi.cn")
    fingerprints = [item["little_endian"] for item in config["rsa_fingerprints"]]
    if fingerprints != ["4381149949997195609", "12240908862933197005"]:
        fail(f"RSA fingerprints are {fingerprints}")
    header = read("submodules/MtProtoKit/Sources/TellomiServerConfigJSON.h")
    if "api.tellomi.cn" not in header or "149.154." in header:
        fail("generated handshake header does not carry only the Tellomi seed")
    network = read("submodules/TelegramCore/Sources/Network/Network.swift")
    if "TellomiSeedAddresses" not in network or "149.154.175.50" in network:
        fail("Network.swift is not installing the Tellomi seed")
    if "TellomiDisablesTelegramBackupDiscovery" not in network:
        fail("backup discovery is not gated")
    account = read("submodules/TelegramCore/Sources/Account/Account.swift")
    if "TellomiDefaultDatacenterId" not in account or "initialDatacenterId: Int = 2" in account:
        fail("the first connection still prefers Telegram datacenter 2")
    auth = read("submodules/MtProtoKit/Sources/MTDatacenterAuthMessageService.m")
    if "TellomiServerPublicKeys" not in auth or "MIIBCgKCAQEA6LszBcC1" in auth:
        fail("the handshake is not using the Tellomi key")
    serialization = read("submodules/TelegramCore/Sources/State/Serialization.swift")
    if "return 232" not in serialization:
        fail("MTProto layer is not 232")


def check_login_errors() -> None:
    account = read("submodules/TelegramCore/Sources/Account/Account.swift")
    if "allowSrpRefresh: false" not in account or 'error.errorDescription == "SRP_ID_INVALID"' not in account:
        fail("a stale SRP id is not refreshed once")
    if account.count("allowSrpRefresh: false") != 1:
        fail("SRP refresh is not a single retry")
    authorization = read("submodules/TelegramCore/Sources/Authorization.swift")
    for code in ("PHONE_CODE_INVALID", "SESSION_PASSWORD_NEEDED", "PHONE_NUMBER_INVALID", "FLOOD_WAIT"):
        if code not in authorization:
            fail(f"authorization no longer handles {code}")
    stores = authorization.count("storeAuthorizedUser(transaction: transaction") + account.count("storeAuthorizedUser(transaction: transaction")
    if stores != 7:
        fail(f"login stores the authorized user in {stores} places, expected 7")
    if "func storeAuthorizedUser(" not in authorization:
        fail("storeAuthorizedUser is missing")
    if "transaction.getSharedData(SharedDataKeys.localizationSettings)" not in account:
        fail("the notification extension does not read the stored language")


def check_released_identity() -> None:
    config = json.loads(read("build-system/appstore-configuration.json"))
    for key, expected in RELEASE_IDENTITY.items():
        if config.get(key) != expected:
            fail(f"{key} is {config.get(key)}, 14.0.4 used {expected}")
    version = read("Tellomi/version").strip()
    versions = json.loads(read("versions.json"))
    if version != "14.0.5" or versions.get("app") != "14.0.5":
        fail(f"marketing version is {version} / {versions.get('app')}, expected 14.0.5")
    blob = subprocess.check_output(
        ["git", "hash-object", "submodules/BuildConfig/Sources/BuildConfig.m"],
        cwd=ROOT,
        text=True,
    ).strip()
    if blob != RELEASE_BUILD_CONFIG:
        fail("BuildConfig.m no longer matches 14.0.4, so the database key derivation changed")
    build = read("Telegram/BUILD")
    if "group.{telegram_bundle_id}" not in build:
        fail("the app group is not group.{bundle id}")
    if "<key>CFBundleDisplayName</key>\n    <string>Tellomi</string>" not in build:
        fail("the packaged display name is not Tellomi")
    delegate = read("submodules/TelegramUI/Sources/AppDelegate.swift")
    if 'let appGroupName = "group.\\(baseAppBundleId)"' not in delegate:
        fail("the running app does not open group.<bundle id>")
    if "rootPathForBasePath(appGroupUrl.path)" not in delegate:
        fail("the database root is not the app-group container")
    if "deviceSpecificEncryptionParameters" not in delegate:
        fail("the database is not opened with the device key")


def check_known_gap() -> None:
    serialization = read("submodules/TelegramCore/Sources/State/Serialization.swift")
    discover = read("submodules/MtProtoKit/Sources/MTDiscoverConnectionSignals.m")
    if "this_port_only" in serialization or "thisPortOnly" in serialization:
        fail("this_port_only is now parsed; remove the known-gap note")
    if "return @[@80, @5222];" not in discover:
        fail("discovery no longer probes ports 80 and 5222")
    print(
        "KNOWN GAP: dcOption this_port_only is not applied. "
        "Discovery still probes 80 and 5222 after the declared port. "
        "This is not a login, send, or upgrade pass."
    )


def main() -> None:
    check_server()
    check_login_errors()
    check_released_identity()
    check_known_gap()
    print("restore contract passed")
    print("not claimed: device login, media send, or a 14.0.4 database opened by this build")


if __name__ == "__main__":
    main()
