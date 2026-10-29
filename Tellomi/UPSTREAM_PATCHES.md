# Upstream patches for the Tellomi fork

Edits under `Telegram/` and `BUILD.bazel` that exist so Tellomi assets can ship. The artwork itself stays in `Tellomi/Brand/`.

| File | Change |
| --- | --- |
| `BUILD.bazel` | Exports `Tellomi/version`. Adds `//:TellomiAppIcon` and `//:TellomiAlternate_*` filegroups over `Tellomi/Brand`. |
| `Telegram/BUILD` | `app_icons` is `//:TellomiAppIcon` instead of `Telegram-iOS/TellomiPlaceholder.icon`. `alternate_icons` read `Tellomi/Brand/Alternates` instead of `Telegram-iOS/*.alticon`. |
| `Telegram/BUILD` `VersionInfoPlist` | `CFBundleShortVersionString` is read from `Tellomi/version`, not `versions.json`. |
| `versions.json` | `app` matches `Tellomi/version` (`13.1.2`) so the watch patch script and the plist agree. |

`Telegram-iOS/*.alticon`, `AppIcons.xcassets`, `DefaultAppIcon.xcassets`, and `TellomiPlaceholder.icon` are still in the tree and are not the icons the Bazel app packages.

`Tellomi/Brand/AppIcon.icon/icon.json` layer fills are `{ "solid": "srgb:…" }` (and `"automatic"` for the tinted appearance). A bare `srgb:` string is not a fill, and actool rejects it with `A fill should be one of: "orientation", "solid", "linear-gradient" or "automatic-gradient"`. The glyph is a PNG, not an SVG, so actool does not convert the traced path into a PDF.

## Login country code

The stock login default is the device region (`Locale.current` country code) with a fallback of +1. It does not read the SIM, and it does not read `help.getNearestDc`. `help.getConfig` `suggested_lang_code` is a language suggestion only.

| File | Change |
| --- | --- |
| `submodules/CountrySelectionUI/Sources/AuthorizationSequenceCountrySelectionController.swift` `defaultCountryCode()` | Always returns 86. The country picker is unchanged. |
| `submodules/AuthorizationUI/Sources/AuthorizationSequenceController.swift` | The duplicate helper forwards to that function. Restoring a phone-entry state with an empty number uses 86, so an update replaces a stored +1. A number the user already typed keeps its code. |

The same helper is what New Contact and Change Phone Number open with, so those fields also start at +86.

## Chinese system language

The app ships only `en.lproj`. Start Messaging called `downloadAndApplyLocalization` with `"en"`. `suggested_lang_code` adds a second button; it is not applied on its own. The saved pack lives in the account manager under `SharedDataKeys.localizationSettings`. `help.getConfig`'s suggestion is `PreferencesKeys.suggestedLocalization`. The language list cache is `Namespaces.CachedItemCollection.cachedAvailableLocalizations`. An update keeps all three. Reinstalling clears them. `UserDefaults` key `TellomiDidApplySystemLangPack` records that the automatic pack was applied, so a later choice in Settings is kept; reinstalling clears that key too.

| File | Change |
| --- | --- |
| `submodules/AuthorizationUI/Sources/TellomiLoginLocale.swift` | `zh-Hans` / `zh-CN` / `zh` map to server langpack `zh-hans`. `zh-Hant` / `zh-TW` / `zh-HK` / `zh-MO` map to `zh-hant`. |
| `submodules/AuthorizationUI/Sources/AuthorizationSequenceSplashController.swift` | Start downloads that pack instead of `"en"` until the key above is set. |
| `submodules/AuthorizationUI/Sources/AuthorizationSequenceController.swift` | The login flow downloads the pack before it builds the splash or the phone screen, so a saved English pack from the old Start button is replaced. The intro carousel stays the bundled English strings. |
| `submodules/TelegramUI/Sources/ApplicationContext.swift` | A signed-in account whose saved language is not the matching pack downloads it once. The running UI follows `localizationSettings`, the same path as Settings ▸ Language. |
