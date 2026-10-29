# Tellomi

Tellomi is an open-source dating app built on the Telegram iOS client (TelegramMessenger/Telegram-iOS, layer 232). Every Telegram feature stays, including Stories. Nothing is compiled out. The server is a Teamgram fork brought up to layer 232 ([tellomi/teamgram-server#1](https://github.com/tellomi/teamgram-server/pull/1)). A development login on that server accepts the fixed SMS code `12345`; the client just submits whatever code the user types.

The fork is a thin layer on top of upstream so later merges stay small. Product copy inside chats, settings and the login screens still comes from Telegram's localization database. The changes below are the ones that decide the name on the home screen and which server the app opens.

## Configure the server

Edit **`Tellomi/tellomi-server.json`**. That file is the only copy of the seed addresses, the TCP port and the server RSA public key. Then regenerate the header the app compiles in:

```sh
python3 Tellomi/generate_server_config.py
python3 Tellomi/check_server_config.py
```

`submodules/MtProtoKit/Sources/TellomiServerConfigJSON.h` is generated. Do not edit it. MtProtoKit has no app bundle to read the JSON from at runtime, so the generator turns the file into one Objective-C string.

### Defaults (local Teamgram docker)

| Field | Default | Why |
| --- | --- | --- |
| `seeds.production` / `seeds.testing` | datacenter `1` → `127.0.0.1` | Teamgram docker publishes one datacenter. The iOS Simulator shares the Mac's network, so `127.0.0.1` is the host. A phone needs that machine's LAN address. |
| `seed_port` | `10443` | gnetway's published TCP port (`docker-compose.yaml` maps `10443:10443`). Not 443. |
| `default_datacenter_id` | `1` | The first connection, including release builds. Upstream opened datacenter 2 in release; Teamgram does not have that datacenter. |
| `public_keys` | one PKCS#1 PEM, production and testing | The public half of the development key Teamgram ships as `teamgramd/bin/server_pkcs1.key`. |
| `disable_telegram_backup_discovery` | `true` | See below. |

Replace the hosts before pointing the app at a deployed server. Replace the PEM when the deployment is not using Teamgram's development key. The JSON takes several keys; list every PEM the server might announce.

The two fingerprint fields are checks, not configuration. `python3 Tellomi/check_server_config.py` recomputes them from the PEM and fails if they disagree. After a new key, put the numbers the script prints into those fields.

### Why there are two fingerprints

Telegram iOS (`MTRsaFingerprint`) reads the last eight bytes of SHA1(TL(n) + TL(e)) as a **big-endian** integer. For Teamgram's development key that is `14798846482072068265`.

Teamgram does not compute the fingerprint. `app/interface/gnetway/internal/server/gnet/handshake.go` parses `KeyFingerprint` from `gnetway.yaml` and sends that decimal in `resPQ`. The value shipped with the development key is `12240908862933197005`, which is the **same eight bytes read little-endian** (`binary.LittleEndian.Uint64` in Teamgram's fingerprint tool). The server then looks up `req_DH_params.public_key_fingerprint` against that same decimal.

The handshake therefore accepts either byte order, and it sends back the value the server announced rather than the big-endian value this client computes. An exact (Telegram) match still wins over a byte-swap of a different key. Encrypting still uses the PEM; the fingerprint only selects it.

### What the client no longer asks Telegram for

With `disable_telegram_backup_discovery` true, `initializedNetwork` does not install `MTBackupAddressSignals`. That signal resolves `apv3.stel.com` (or `tapv3.stel.com` on the test backend) through Google DNS and would replace the seed list with Telegram's datacenters. Login push-code and reCAPTCHA callbacks are unchanged; only the backup-address fetch is skipped.

`decrypt_TL_data` in `MTEncryption.m` still contains Telegram's key for decoding those DNS records. Nothing calls it while discovery is off.

## App name, bundle id, API credentials

`build-system/appstore-configuration.json` is what `Make.py` reads. The same values are in `build-system/appcenter-configuration.json`, `build-system/template_minimal_development_configuration.json` and `build-system/example-configuration/variables.bzl`. `BuildConfiguration.py` writes `telegram_app_name` into the generated Bazel `variables.bzl`.

| JSON field | Value | Notes |
| --- | --- | --- |
| `app_name` | `Tellomi` | `CFBundleDisplayName` / `CFBundleName` on the app and its extensions. |
| `bundle_id` | `com.tellomi.app` | Extensions are `com.tellomi.app.Share`, `.NotificationService`, and so on. The app group is `group.com.tellomi.app`. |
| `api_id` | `100001` | Placeholder. Not Telegram's `8`. |
| `api_hash` | `74656c6c6f6d69000000000000000000` | Placeholder: the ASCII bytes of `tellomi`, padded with zeros to 32 hex digits. Not a secret. |
| `team_id` | `TELL0MIDEV` | Placeholder. Not an Apple team. Signing fails until this is replaced. |
| `app_center_id` | empty | So a non-App-Store build does not start App Center with a fake secret. |
| `is_appstore_build` | `false` | |
| `is_internal_build` | `true` | |
| `appstore_id` | `0` | No App Store listing yet. |
| `app_specific_url_scheme` | `tellomi` | Also registered next to `telegram://` and `tg://`. |
| `premium_iap_product_id` | `com.tellomi.app.premium.monthly` | No App Store product exists for this id. |
| `enable_siri` / `enable_icloud` | `false` | Those entitlements need a real provisioning profile. |

Teamgram's server does not check `api_id` or `api_hash` ([teamgram-server#120](https://github.com/teamgram/teamgram-server/issues/120)). They are still sent on `initConnection`. Replace the placeholders if a later server build starts checking them.

The legacy Xcode configs `Telegram/Telegram-iOS/Config-AppStoreLLC.xcconfig` and `Config-Fork.xcconfig` carry the same name, bundle id and placeholders. Bazel is the build that ships.

Because the bundle id is not `ph.telegra.Telegraph`, `Telegram/BUILD` already drops the entitlements that exist only for the official client: associated domains (`t.me`), CarPlay, Apple Pay merchant ids, unrestricted VoIP, communication notifications, Sign in with Apple, and the continued-processing GPU entitlement. Siri and iCloud are off via the flags above.

System permission prompts (the `InfoPlist.strings` files, plus the English strings in the plist) say Tellomi, including the Arabic, Persian and Korean product names that override the home-screen title. That was a name swap in those files only.

## Icons

The home-screen icon is `Telegram/Telegram-iOS/TellomiPlaceholder.icon`: a plum circle and a white **T**, not the paper plane. `TellomiPlaceholder-ICON-PLACEHOLDER.txt` says so. `composer_icon_folders` in `Telegram/BUILD` points at it.

The alternate icons (`*.alticon`, `AppIcons.xcassets`, `DefaultAppIcon.xcassets`) are still Telegram's artwork and can still be chosen in Settings. `ALTERNATE-ICONS-ARE-STILL-TELEGRAM.txt` marks them. Replace those files before a public release; they were left in place so an upstream icon update does not conflict with a binary rewrite of every PNG.

## Files touched

| Change | Where |
| --- | --- |
| Server JSON and the generator / checker | `Tellomi/` |
| Embedded JSON and the readers (`TellomiSeedAddresses`, `TellomiSeedPort`, `TellomiDefaultDatacenterId`, `TellomiDisablesTelegramBackupDiscovery`, `TellomiServerPublicKeys`) | `submodules/MtProtoKit/Sources/TellomiServerConfig.m`, `PublicHeaders/MtProtoKit/TellomiServerConfig.h`, generated `TellomiServerConfigJSON.h` |
| Handshake uses those keys and echoes the server's fingerprint | `MTDatacenterAuthMessageService.m` |
| Seed list and backup-discovery gate | `submodules/TelegramCore/Sources/Network/Network.swift` |
| First datacenter | `submodules/TelegramCore/Sources/Account/Account.swift` |
| Display name, bundle id, `tellomi://` | `Telegram/BUILD`, the configuration JSON files, `BuildConfiguration.py` |
| Permission-prompt name | `Telegram/Telegram-iOS/*.lproj/InfoPlist.strings`, `Info.plist`, `InfoBazel.plist` |
| Placeholder icon | `Telegram/Telegram-iOS/TellomiPlaceholder.icon` |
| YouTube embed base URL | `YoutubeEmbedImplementation.swift` uses `https://tellomi.app` as the web view's base URL. It is not a host the app fetches. |
| Watch bundle id default | `Telegram/prebuilt_watchos.bzl` defaults to `com.tellomi.app.watchkitapp`. The app target still passes `{bundle id}.watchkitapp`, so a different host bundle id still flows through. |

## Build and sign

This repository builds with Bazel through `Make.py`, on a Mac with the Xcode version in `versions.json`. A Linux checkout cannot run that build.

Simulator, no provisioning profile (signing material is not in this repo):

```sh
python3 build-system/Make/Make.py --overrideXcodeVersion \
  --cacheDir ~/telegram-bazel-cache \
  build \
  --configurationPath build-system/appstore-configuration.json \
  --disableProvisioningProfiles \
  --buildNumber=1 \
  --configuration=debug_sim_arm64
```

Device or distribution signing comes from the team later. Do not commit certificates, `.p12` files, `.mobileprovision` files, or `TELEGRAM_CODESIGNING_GIT_PASSWORD`. When they arrive:

1. Put the Apple team id in `team_id` in the configuration JSON. `TELL0MIDEV` will not match a real profile.
2. Create provisioning profiles for `com.tellomi.app` and each extension suffix the build expects (`.Share`, `.NotificationContent`, `.NotificationService`, `.SiriIntents`, `.Widget`, `.BroadcastUpload`, and `.watchkitapp` if the watch app is embedded). `BuildConfiguration.py` maps those suffixes onto profile file names.
3. Point `Make.py` at that profile directory with `--codesigningInformationPath`, or at the team's encrypted git repo with the existing `--gitCodesigning*` flags. The password stays in the environment.
4. Turn `enable_siri` and `enable_icloud` back on only after the profiles contain those entitlements.
5. Push notifications need an APNs key configured on the Teamgram server. The client already registers its device token over MTProto; it does not talk to a Telegram push gateway.

`Make.py` writes `build-input/configuration-repository/variables.bzl` from the JSON. That directory is local build state, not a source file.

## What was checked here

`python3 Tellomi/check_server_config.py` (no Xcode):

- The JSON and the generated header are the same document.
- OpenSSL accepts the PEM as an RSA public key.
- Its fingerprint is `14798846482072068265` big-endian and `12240908862933197005` little-endian, and those are byte swaps of each other. The little-endian value is the decimal in Teamgram's `gnetway.yaml`.
- The three configuration JSON files load through `BuildConfiguration` as `com.tellomi.app` / `Tellomi` / the placeholder api id, with Siri and iCloud off.
- `Network.swift` installs `TellomiSeedAddresses` and no longer contains Telegram's production seed `149.154.175.50`.
- The first connection uses `TellomiDefaultDatacenterId`.
- The handshake reads `TellomiServerPublicKeys` and applies the fingerprint byte swap. Telegram's production modulus prefix is not the default key.
- The Bazel app icon list points at `TellomiPlaceholder`.

A full Xcode or Bazel compile was not run. This machine has no Xcode, no iOS SDK and no simulator.

## What remains

These still say Telegram, or still call a Telegram host. They do not choose the datacenter, and they were left so an upstream merge does not rewrite the localization database or every call site.

- **In-app copy.** Login titles, settings rows and message text come from the generated `PresentationStrings` database. The home screen and the system permission dialogs say Tellomi; most screens inside the app still say Telegram.
- **Alternate icons.** See above.
- **`https://t.me/...` links** the app builds for usernames, invites, stickers, themes and QR codes. They open Telegram's public site, not the Teamgram deployment. There is no Tellomi domain wired through those call sites.
- **User-tapped pages** on `telegram.org` (FAQ, privacy, terms), `translations.telegram.org`, `fragment.com`, `web.telegram.org` and `getdesktop.telegram.org`. They open in a browser. They are not required to log in.
- **Apple Pay** code still names `merchant.ph.telegra.Telegraph`. The entitlement is omitted for this bundle id, so the system will not offer it.
- **Theme file UTI** `org.telegram.Telegram-iOS.theme` is unchanged so existing `.tgios-theme` files still match. The type's display name says Tellomi.
- **Watch app** under `Telegram/WatchApp` is a synced snapshot. It was not edited. Its API id is separate from `BuildConfig`.
- **App Store updates and Premium.** `appstore_id` is `0`, and the Premium product id has no App Store product. `openAppStorePage` would open `itms-apps://…/id0` if something called it.
- **Push, Stars, Fragment payments, wallet.** The client features are still compiled. They need the Teamgram server (and, for payments, a backend this client does not have) before they do anything.
- **Signing.** Placeholder team id only, until the team provides profiles and certificates.
