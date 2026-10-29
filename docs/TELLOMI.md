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

### Defaults (Tellomi dev server)

| Field | Default | Why |
| --- | --- | --- |
| `seeds.production` / `seeds.testing` | datacenter `1` → `api.tellomi.cn` | DNS-only name for the Tellomi dev Teamgram server. TCP port stays `10443`. Dev login SMS code is `12345`. The direct seed dial passes this string to `GCDAsyncSocket` `connectToHost:`, which resolves it with `getaddrinfo`. |
| `seed_address_a_record` | `8.137.39.82` | Not dialed. The address `api.tellomi.cn` currently resolves to. A SOCKS proxy encodes the destination with `inet_aton` (`MTTcpConnection` `requestSocksConnection`) and needs this literal instead of the hostname. |
| `local_docker_seed` | `127.0.0.1` | Not dialed. For Teamgram docker on the same machine, put this host in `seeds` instead and regenerate the header. The iOS Simulator reaches the host at `127.0.0.1`. |
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
| `bundle_id` | `app.tellomi.chat` | Extensions append the suffixes in `Tellomi/extension-suffixes.json` (`.Share`, `.NotificationContent`, `.NotificationService`, `.SiriIntents`, `.Widget`, `.BroadcastUpload`). The app group is `group.app.tellomi.chat`. |
| `api_id` | `100001` | Placeholder. Not Telegram's `8`. |
| `api_hash` | `74656c6c6f6d69000000000000000000` | Placeholder: the ASCII bytes of `tellomi`, padded with zeros to 32 hex digits. Not a secret. |
| `team_id` | `CB7KP6GBAR` | Default Apple team. Still a JSON field. The TestFlight workflow overwrites the temporary configuration with the team id inside the profile it downloads. |
| `app_center_id` | empty | So a non-App-Store build does not start App Center with a fake secret. |
| `is_appstore_build` | `false` | |
| `is_internal_build` | `true` | |
| `appstore_id` | `0` | No App Store listing yet. |
| `app_specific_url_scheme` | `tellomi` | Also registered next to `telegram://` and `tg://`. |
| `premium_iap_product_id` | `app.tellomi.chat.premium.monthly` | No App Store product exists for this id. |
| `enable_siri` / `enable_icloud` | `false` | Those entitlements need a real provisioning profile. |

Teamgram's server does not check `api_id` or `api_hash` ([teamgram-server#120](https://github.com/teamgram/teamgram-server/issues/120)). They are still sent on `initConnection`. Replace the placeholders if a later server build starts checking them.

The legacy Xcode configs `Telegram/Telegram-iOS/Config-AppStoreLLC.xcconfig` and `Config-Fork.xcconfig` carry the same name, bundle id and placeholders. Bazel is the build that ships.

Because the bundle id is not `ph.telegra.Telegraph`, `Telegram/BUILD` drops the entitlements that exist only for the official client: CarPlay, Apple Pay merchant ids, unrestricted VoIP, communication notifications, Sign in with Apple, and the continued-processing GPU entitlement. Siri and iCloud are off via the flags above. Associated domains are `applinks:tell.cc` and `webcredentials:tell.cc` (see Public links).

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
| Watch bundle id default | `Telegram/prebuilt_watchos.bzl` defaults to `app.tellomi.chat.watchkitapp`. The app target still passes `{bundle id}.watchkitapp`, so a different host bundle id still flows through. |

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

Do not commit certificates, `.p12` files, `.mobileprovision` files, or `TELEGRAM_CODESIGNING_GIT_PASSWORD`. The TestFlight workflow creates the Apple Distribution certificate and the App Store profiles through the App Store Connect API. A local device build can instead point `Make.py` at a profile directory with `--codesigningInformationPath`.

`team_id` in the configuration JSON is `CB7KP6GBAR`. Change that field if the Apple team changes. Extension suffixes live in `Tellomi/extension-suffixes.json`. `prepare_appstore_signing.py` registers those bundle ids, and `BuildConfiguration.py` maps each suffix onto the profile file name Bazel expects (`.Share` → `Share.mobileprovision`, `.SiriIntents` → `Intents.mobileprovision`, and so on). `.watchkitapp` is in that file and is not registered unless the watch app is embedded.

Turn `enable_siri` and `enable_icloud` on only after the profiles contain those entitlements. Push notifications need an APNs key configured on the Teamgram server. The client already registers its device token over MTProto; it does not talk to a Telegram push gateway.

`Make.py` writes `build-input/configuration-repository/variables.bzl` from the JSON, including the extension suffix variables from `Tellomi/extension-suffixes.json`. That directory is local build state, not a source file. The checked-in copy is `build-system/example-configuration/variables.bzl`.

## Public links

`tell.cc` is the public link host. It replaces `t.me`, `telegram.me`, and `telegram.dog`. The definition is `TellomiLinks.host` in `submodules/TellomiLinks/Sources/TellomiLinks.swift` (`TelegramCore` re-exports it). The legacy watch controller `Telegram/Watch/Extension/TGUserInfoController.m` repeats the same host because that Objective-C target does not import Swift. Paths are unchanged (`/username`, `/+hash`, `/joinchat`, `/c/`, `/s/`, `/addstickers`, `/addemoji`, `/proxy`, `/socks`, `/share`, stories, `?start`, and the rest). `tg://` is still accepted. `tellomi://` uses the same routes (`TellomiLinks.urlScheme`, also `app_specific_url_scheme` in the build configuration, registered next to `tg` in the URL types).

The main app's associated-domains entitlement is `applinks:tell.cc` and `webcredentials:tell.cc`. Telegram domains are not in that entitlement. Ops uploads `Tellomi/well-known/apple-app-site-association` to `https://tell.cc/.well-known/apple-app-site-association`. The app id in that file is `CB7KP6GBAR.app.tellomi.chat`.

## TestFlight

`.github/workflows/testflight.yml` runs on the `xcode-27` GitHub-hosted image (Xcode 27.1, the version in `versions.json`). It runs when a `v*` tag is pushed, when a GitHub Release is published, and on manual dispatch. It does not run on every pull request.

`CFBundleShortVersionString` for the app and every extension is `Tellomi/version` (also `versions.json` key `app`). A tag `v0.1.0-tf9` is marketing version `0.1.0`; the workflow refuses to build when that does not match `Tellomi/version`. `CFBundleVersion` stays the auto-incremented build number.

The workflow calls `Tellomi/prepare_appstore_signing.py`, which uses the App Store Connect API key to register the bundle ids below, turn on the capabilities the signed entitlements require, and download App Store profiles. The distribution certificate is the PKCS#12 in `APPLE_DIST_CERT_P12_BASE64` (password `APPLE_DIST_CERT_P12_PASSWORD`). Each profile must include that certificate's serial. How ops creates the certificate is [`Tellomi/README.md`](../Tellomi/README.md). Certificates and profiles are not committed. `Make.py` then does a Bazel `release_arm64` build. `xcrun altool` uploads `bazel-bin/Telegram/Telegram.ipa`. The build number is one higher than the highest build already on TestFlight for this app, and at least `github.run_number`.

Enabling a capability sends an empty `settings` list. `APP_GROUPS` in particular must not name the group in that request; the API rejects it. The script still checks that each downloaded profile contains `group.app.tellomi.chat`. SiriIntents is registered with SiriKit enabled. The signed binary does not include `com.apple.developer.siri`, because `enable_siri` is false.

Repository secrets, none of which are printed:

- `APP_STORE_CONNECT_KEY_ID`
- `APP_STORE_CONNECT_ISSUER_ID`
- `APP_STORE_CONNECT_KEY_P8_BASE64` (base64 of the AuthKey `.p8`)
- `APPLE_DIST_CERT_P12_BASE64` (base64 of the Apple Distribution `.p12`)
- `APPLE_DIST_CERT_P12_PASSWORD` (that `.p12`'s export password)

The `.p8` is only an API credential. The distribution private key stays in the `.p12` secret, not in git. Minting a certificate and caching it (`TELLOMI_MINT_DISTRIBUTION_CERT=1`, or the workflow_dispatch input `mint_distribution_cert`) is opt-in. A cache saved on one tag is not visible to the next tag. The committed `team_id` default is `CB7KP6GBAR`. The workflow writes a temporary configuration whose team id is the one in the downloaded profile.

The watch app is not in this IPA. Embedding it needs `--embedWatchApp` plus watch API credentials, which this workflow does not have.

## Identifiers to create

Base id `app.tellomi.chat`, from `build-system/appstore-configuration.json`. Extension suffixes are `Tellomi/extension-suffixes.json`, and `Telegram/BUILD` interpolates the variables that file writes into `variables.bzl`. `{TEAMID}` is `CB7KP6GBAR` unless the downloaded profile names a different team.

These seven ids are what `Make.py build --configuration=release_arm64` signs. The workflow registers them. Each needs an App Store profile.

| Bundle id | Signed entitlements | App Group | Capabilities on the App ID |
| --- | --- | --- | --- |
| `app.tellomi.chat` | `aps-environment` = `production` (Make.py copies this out of the profile and refuses to build if it is missing), `com.apple.security.application-groups` = `group.app.tellomi.chat`, `application-identifier` = `{TEAMID}.app.tellomi.chat`, associated domains `applinks:tell.cc` and `webcredentials:tell.cc` | `group.app.tellomi.chat` | Push Notifications, App Groups, Associated Domains |
| `app.tellomi.chat.Share` | App Group only | `group.app.tellomi.chat` | App Groups |
| `app.tellomi.chat.NotificationContent` | App Group only | `group.app.tellomi.chat` | App Groups |
| `app.tellomi.chat.NotificationService` | App Group only | `group.app.tellomi.chat` | App Groups |
| `app.tellomi.chat.SiriIntents` | App Group only | `group.app.tellomi.chat` | App Groups, SiriKit (the extension point is an Intents extension; the signed entitlements do not include `com.apple.developer.siri`, because `enable_siri` is false) |
| `app.tellomi.chat.Widget` | App Group only | `group.app.tellomi.chat` | App Groups |
| `app.tellomi.chat.BroadcastUpload` | App Group only | `group.app.tellomi.chat` | App Groups |

One App Group id: `group.app.tellomi.chat`. Share, the notification content and service extensions, Siri intents, the widget and broadcast upload all open `group.` plus the main bundle id. The main app's entitlements declare the same group.

Keychain group used by `BuildConfig.keychainAccessGroup`: `{TEAMID}.app.tellomi.chat`. The project does not set a `keychain-access-groups` entitlement. That string is the main app's default keychain group, because it is the `application-identifier`. Extensions do not call that API.

iCloud container: none. `enable_icloud` is false, so `TelegramEntitlements` does not contain `com.apple.developer.icloud-container-identifiers`. Turning the flag on would add container `iCloud.app.tellomi.chat` and ubiquity key-value store `{TEAMID}.app.tellomi.chat`.

Also absent with this bundle id and these flags: Siri on the main app, Sign in with Apple, Apple Pay, CarPlay, unrestricted VoIP, communication notifications, notification filtering, and the continued-processing GPU entitlement. Those fragments in `Telegram/BUILD` are empty unless the bundle id is an official Telegram id or the JSON flag is turned on. Associated domains are present and name `tell.cc` only.

The main app's Info.plist background modes, which are not separate App IDs, are `audio`, `fetch`, `location`, `remote-notification`, `voip`, and `processing`.

Not registered as App Store Connect apps, and not given profiles. They are frameworks inside the IPA:

- `app.tellomi.chat.MtProtoKit`
- `app.tellomi.chat.SwiftSignalKit`
- `app.tellomi.chat.Postbox`
- `app.tellomi.chat.TelegramCore`
- `app.tellomi.chat.TelegramUI`

Not in the TestFlight IPA. Create it only when embedding the watch app (`--embedWatchApp`):

- `app.tellomi.chat.watchkitapp`

`BuildConfiguration.py` also accepts a profile whose id is `app.tellomi.chat.watchkitapp.watchkitextension`. Nothing in the current watch target uses that id.

## What was checked here

`python3 Tellomi/check_server_config.py` (no Xcode):

- The JSON and the generated header are the same document.
- OpenSSL accepts the PEM as an RSA public key.
- Its fingerprint is `14798846482072068265` big-endian and `12240908862933197005` little-endian, and those are byte swaps of each other. The little-endian value is the decimal in Teamgram's `gnetway.yaml`.
- The three configuration JSON files load through `BuildConfiguration` as `app.tellomi.chat` / `Tellomi` / team `CB7KP6GBAR` / the placeholder api id, with Siri and iCloud off.
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
- **Signing material in git.** Certificates and profiles are not committed. TestFlight CI builds profiles from the API key and signs with the distribution PKCS#12 in repository secrets. See [`Tellomi/README.md`](../Tellomi/README.md).
