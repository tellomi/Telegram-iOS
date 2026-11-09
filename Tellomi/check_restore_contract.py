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


def check_declared_port() -> None:
    serialization = read("submodules/TelegramCore/Sources/State/Serialization.swift")
    updates = read("submodules/TelegramCore/Sources/State/ManagedConfigurationUpdates.swift")
    discover = read("submodules/MtProtoKit/Sources/MTDiscoverConnectionSignals.m")
    network = read("submodules/TelegramCore/Sources/Network/Network.swift")
    for source, name in ((serialization, "Serialization.swift"), (updates, "ManagedConfigurationUpdates.swift")):
        if "(flags & (1 << 5)) != 0" not in source or "thisPortOnly:" not in source:
            fail(f"{name} does not apply dcOption.this_port_only")
        if "preferForMedia:" not in source:
            fail(f"{name} dropped the media address flag")
    if "thisPortOnly: true" not in network:
        fail("the Tellomi seed is not limited to its declared port")
    if "return @[@80, @5222];" not in discover:
        fail("an ordinary address no longer probes ports 80 and 5222")
    if "if (address.thisPortOnly)" not in discover or "other.thisPortOnly" not in discover:
        fail("discovery does not skip alternate ports for a locked address")
    print("dcOption.this_port_only skips ports 80 and 5222; other addresses still probe them")


# submodules/Postbox/Sources/Upgrades.swift is the same blob as release 14.0.4 (c75e2177).
RELEASE_UPGRADES = "c1fddb31635e736fd00ccce66784a53e00e24d26"
KEYCHAIN_KEYS = (
    "authTokenById",
    "cleanupSessionIdsByAuthKeyId",
    "datacenterAddressSetById",
    "datacenterAuthInfoById",
    "datacenterId",
    "datacenterManuallySelectedSchemeById_v1",
    "datacenterPublicKeysById",
    "globalTimeDifference",
    "isMedia",
    "isProxy",
    "transportSchemeStats_v1",
)


def check_upgrade_layout() -> None:
    postbox = read("submodules/Postbox/Sources/Postbox.swift")
    if "let currentUserVersion: Int32 = 25" not in postbox:
        fail("Postbox user version is not 25, the version stored by 14.0.4")
    upgrades = subprocess.check_output(
        ["git", "hash-object", "submodules/Postbox/Sources/Upgrades.swift"],
        cwd=ROOT,
        text=True,
    ).strip()
    if upgrades != RELEASE_UPGRADES:
        fail("Postbox upgrade table no longer matches 14.0.4")
    account = read("submodules/TelegramCore/Sources/Account/Account.swift")
    if 'return "account-\\(UInt64(bitPattern: id.int64))"' not in account:
        fail("account directory name changed")
    if 'basePath: path + "/postbox"' not in account:
        fail("account database is not under postbox/")
    manager = read("submodules/TelegramCore/Sources/Account/AccountManager.swift")
    if 'return appGroupPath + "/telegram-data"' not in manager:
        fail("the data root is not <app group>/telegram-data")
    delegate = read("submodules/TelegramUI/Sources/AppDelegate.swift")
    if 'rootPath + "/accounts-metadata"' not in delegate:
        fail("account metadata path changed")
    context = read("submodules/MtProtoKit/Sources/MTContext.m")
    for key in KEYCHAIN_KEYS:
        if f'forKey:@"{key}"' not in context:
            fail(f"keychain key {key} is gone")
    address = read("submodules/MtProtoKit/Sources/MTDatacenterAddress.m")
    if 'decodeBoolForKey:@"thisPortOnly"' not in address:
        fail("old datacenter archives are not decoded with a missing thisPortOnly key")
    build = read("Telegram/BUILD")
    if "group.{telegram_bundle_id}" not in build or "{telegram_team_id}.{telegram_bundle_id}" not in build:
        fail("app group or application identifier no longer follows the bundle id")
    config = read("submodules/BuildConfig/Sources/BuildConfig.m")
    if "stringByAppendingFormat:@\".%@\", baseAppBundleId" not in config:
        fail("keychain access group is not <team seed>.<bundle id>")
    print("upgrade layout matches 14.0.4 paths, Postbox version 25, and keychain key names")


def check_icons() -> None:
    root_build = read("BUILD.bazel")
    app_build = read("Telegram/BUILD")
    if 'name = "TellomiAppIcon"' not in root_build or 'app_icons = ["//:TellomiAppIcon"]' not in app_build:
        fail("the home icon target is not TellomiAppIcon")
    resources = app_build.split("resources = [", 1)[1].split("]", 1)[0]
    for line in resources.splitlines():
        stripped = line.strip()
        if stripped.startswith("#"):
            continue
        if "DefaultAppIcon" in stripped:
            fail("the Telegram DefaultAppIcon is still a packaged resource")
    catalog = json.loads(read("Tellomi/Brand/AppIcon.xcassets/AppIcon.appiconset/Contents.json"))
    icon_dir = ROOT / "Tellomi/Brand/AppIcon.xcassets/AppIcon.appiconset"
    names = []
    for image in catalog["images"]:
        filename = image.get("filename")
        if not filename:
            fail("an icon slot has no filename")
        if not (icon_dir / filename).is_file():
            fail(f"referenced icon {filename} is missing")
        names.append(filename)
    for required in (
        "AppIcon-ios-marketing-1024x1024@1x.png",
        "AppIcon-ios-marketing-1024x1024@1x-dark.png",
        "AppIcon-ios-marketing-1024x1024@1x-tinted.png",
        "AppIcon-ipad-76x76@2x.png",
        "AppIcon-ipad-83_5x83_5@2x.png",
    ):
        if required not in names:
            fail(f"the icon catalog does not reference {required}")
    folders = [
        "BlackIcon", "BlackClassicIcon", "BlackFilledIcon", "BlueIcon", "BlueClassicIcon",
        "BlueFilledIcon", "WhiteFilledIcon", "New1", "New2", "Premium", "PremiumBlack", "PremiumTurbo",
    ]
    if 'name = "TellomiAlternate_{}".format(name)' not in root_build:
        fail("alternate icons are not Bazel filegroups")
    if 'Tellomi/Brand/Alternates/{}.alticon/*.png' not in root_build:
        fail("alternate filegroups do not read the Tellomi alticon directories")
    if '"//:TellomiAlternate_{}".format(name)' not in app_build:
        fail("the app does not package the Tellomi alternate filegroups")
    for name in folders:
        if f'"{name}"' not in root_build or f'"{name}"' not in app_build:
            fail(f"alternate icon {name} is not in the packaged name list")
        folder = ROOT / "Tellomi/Brand/Alternates" / f"{name}.alticon"
        if not any(folder.glob("*.png")):
            fail(f"{name} has no PNGs")
    print(f"home icon slots {len(names)}; {len(folders)} alternate icon sets are packaged")


def main() -> None:
    check_server()
    check_login_errors()
    check_released_identity()
    check_declared_port()
    check_upgrade_layout()
    check_icons()
    print("restore contract passed")
    print("not claimed: device login, media send, or a 14.0.4 database opened by this build")


if __name__ == "__main__":
    main()
