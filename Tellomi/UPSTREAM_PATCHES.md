# Upstream patches for the Tellomi fork

Edits under `Telegram/` and `BUILD.bazel` that exist so Tellomi assets can ship. The artwork itself stays in `Tellomi/Brand/`.

| File | Change |
| --- | --- |
| `BUILD.bazel` | Exports `Tellomi/version`. Adds `//:TellomiAppIcon` (the `AppIcon.xcassets` size set, including iPad 152 and 167) and `//:TellomiAlternate_*` filegroups over `Tellomi/Brand`. |
| `Telegram/BUILD` | `app_icons` is `//:TellomiAppIcon` instead of `Telegram-iOS/TellomiPlaceholder.icon`. `alternate_icons` read `Tellomi/Brand/Alternates` instead of `Telegram-iOS/*.alticon`. The Info.plist fragment includes `NSLocationAlwaysAndWhenInUseUsageDescription` and does not register `AremacFS` fonts. |
| `Telegram/BUILD` `VersionInfoPlist` | `CFBundleShortVersionString` is read from `Tellomi/version`, not `versions.json`. |
| `versions.json` | `app` matches `Tellomi/version` (`1.0.1`) so the watch patch script and the plist agree. |

`Telegram-iOS/*.alticon`, `AppIcons.xcassets`, `DefaultAppIcon.xcassets`, and `TellomiPlaceholder.icon` are still in the tree and are not the icons the Bazel app packages. `Tellomi/Brand/AppIcon.icon` is the Icon Composer document for the same glyph and is also not compiled: this rules_apple pin fails the build if an `.appiconset` is assigned next to an `.icon`, and the `.icon` compile does not emit the iPad 152×152 and 167×167 icons App Store still checks. Those two sizes ship inside `Tellomi/Brand/AppIcon.xcassets` (76pt @2x and 83.5pt @2x), rasterized from `logo.svg`.

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

## QR center mark

The profile QR is `QrStudioScreen`. Its center used to play `PlaneLogoPlain.tgs`. Invite and username QR sheets draw `Chat/Links/QrLogo` or `Share/QrPlaneIcon`, both the same paper-plane PDF. Those two PDFs are now a black render of `Tellomi/Brand/logo.svg` (the traced mark, same source as the app icon). Qr Studio tints that image white, which is what the paper plane used to do. The round-video camera overlay still uses the plane sticker.

| File | Change |
| --- | --- |
| `submodules/TelegramUI/Images.xcassets/Chat/Links/QrLogo.imageset/ic_qrlogo.pdf` | Replaced with the traced logo. |
| `submodules/TelegramUI/Images.xcassets/Share/QrPlaneIcon.imageset/ic_qrlogo.pdf` | Same PDF. |
| `submodules/TelegramUI/Components/QrStudioScreen/Sources/QrStudioExportStickers.swift` `qrStudioDecodeExportPlane` | One white frame of `Share/QrPlaneIcon` instead of the Lottie plane. |
| `submodules/TelegramUI/Components/Chat/ChatQrCodeScreen/Sources/ChatQrCodeScreen.swift` | The center icon is that image on the static and animated paths. |

## Public links and help pages

New links are generated with `TellomiLinks.host` (`tell.cc`). Parsing still accepts `t.me`, `telegram.me`, and `telegram.dog` via `TellomiLinks.legacyHosts`. Help, FAQ, privacy, and terms pages use `TellomiLinks.siteHost` (`tellomi.cn`). `localizedSiteURL` keeps a langpack URL's path and fragment and swaps a `telegram.org` host for `siteHost`.

| File | Change |
| --- | --- |
| `submodules/TellomiLinks/Sources/TellomiLinks.swift` | `host`, `legacyHosts`, `siteHost`, `linkHosts`, `localizedSiteURL`. |
| `submodules/UrlHandling/Sources/UrlHandling.swift` | Public-link and short-link host lists read `TellomiLinks`. |
| `submodules/TelegramUI/Sources/OpenUrl.swift` | Same host list. |
| `submodules/UrlWhitelist/Sources/UrlWhitelist.swift` | Same host list. `telegram.org/blog` and `/tour` stay. |
| `submodules/TextFormat/Sources/GenerateTextEntities.swift` | Same host list, plus `telegram.org` so remaining site links still highlight. |
| `Telegram/Telegram-iOS/en.lproj/Localizable.strings` | Bundled `t.me` display links are `tell.cc`. Bundled FAQ, terms, privacy, and `/terms` URLs are `tellomi.cn`. |
| Settings, passport, stars, wallet, and mini-app screens that open those URL keys | Call `TellomiLinks.localizedSiteURL`. |
| `submodules/TelegramUI/Components/Wallet/WalletInfoScreen/BUILD` | Depends on `TellomiLinks` so the wallet terms URL can use that helper. |
| `submodules/PeerInfoUI/Sources/SecretChatKeyControllerNode.swift` | The "learn more" link goes to `tellomi.cn/faq#secret-chats`. The visible host in the bundled string is `tellomi.cn`. |

## Home-screen icon

Build 50 (`v13.1.2-tf13`, commit `687be56242`) uploaded an IPA whose Icon Composer document is `Logo.png` with solid fills. `v13.1.2-tf14` (commit `80bb22dbdd`) pointed the same document at `Logo.svg` and actool failed with `Failed to create a catalog from the Icon Studio document`. The branch tip keeps `"image-name" : "Logo.png"`. `Tellomi/check_server_config.py` rejects an `.svg` image name so the next tag cannot repeat that document.

## Sign-up agreement checkbox

No in-app terms popup (the server returns `help.termsOfServiceUpdateEmpty` and `popup=false`). The sign-up (name) screen shows `☐ 我已阅读并同意《用户服务协议》和《隐私政策》`; the links open https://tellomi.cn/legal/terms/ and https://tellomi.cn/legal/privacy/, tapping the rest toggles the box, and Continue is disabled until it is checked.

| File | Change |
| --- | --- |
| `submodules/AuthorizationUI/Sources/TellomiSignUpAgreement.swift` | New. Builds the checkbox text and installs its tap/highlight handlers on the stock terms label. |
| `submodules/AuthorizationUI/Sources/AuthorizationSequenceSignUpControllerNode.swift` | Adds `tellomiAgreement` / `tellomiOpenUrl`; end of `init` disables Continue and installs the checkbox on `termsNode`; `updateData` always shows `termsNode`. |
| `submodules/AuthorizationUI/Sources/AuthorizationSequenceSignUpController.swift` | Wires `tellomiOpenUrl` to `openUrl`; `nextPressed()` refuses (haptic error) until the box is checked, which also covers the small-screen Next bar button. |

Email registration uses this same screen. The links stay `https://tellomi.cn/legal/terms/` and `https://tellomi.cn/legal/privacy/`, opened with `UIApplication.shared.open` (no in-app terms modal).

## iPad icons 152 and 167

App Store still asks for an iPad icon of exactly 152×152 pixels and an iPad Pro icon of exactly 167×167. The Icon Composer document does not emit those sizes, and `app_icons` cannot list both `AppIcon.icon` and the size set. `//:TellomiAppIcon` is `Tellomi/Brand/AppIcon.xcassets`, whose 76pt @2x and 83.5pt @2x slots are those pixels, rasterized from the same `logo.svg`.

The traced bubble fills the viewBox. `Tellomi/Brand/generate_icons.py` scales it so the painted mark stays inside 75–80% of the square: 78% on the home-screen set (light, dark, tinted), on `AppIcon.icon/Assets/Logo.png`, and on Default, Water, and Sunset. Classic is 76% inside a round base. Filled is 79.5% on a color that runs to the edge of the square. Water is a teal-to-cyan gradient and Sunset is a pink-to-purple gradient. Premium is a star field; Turbo and Black add a gold star. None of those PNGs replace the upstream `Telegram-iOS/*.alticon` files. The Settings names stay the existing slots (`BlueIcon`, `New2`, `New1`, `BlackIcon`, `BlueClassicIcon`, `BlackClassicIcon`, `BlueFilledIcon`, `BlackFilledIcon`, `Premium`, `PremiumTurbo`, `PremiumBlack`).

## Location purpose string

`UIBackgroundModes` includes `location`, so the main Info.plist must contain `NSLocationAlwaysAndWhenInUseUsageDescription`. The key was already translated in `InfoPlist.strings` and missing from the plist, which is what App Store checks. The shipping string is the Bazel fragment in `Telegram/BUILD`. `en.lproj` is the development language, so that file carries the same Simplified Chinese sentence; otherwise it would replace the plist value. Other bundled languages still describe live location shared with friends.

| File | Change |
| --- | --- |
| `Telegram/BUILD` `TelegramInfoPlist` | Adds the key. The app name is `{telegram_app_name}`. |
| `Telegram/Telegram-iOS/Info.plist`, `InfoBazel.plist` | Same key, with Tellomi written out. These are not the plist the Bazel app links. |
| `Telegram/Telegram-iOS/en.lproj/InfoPlist.strings` | The English-locale override is the same sentence. |

## SF Camera fonts

`AremacFS-Regular.otf` and `AremacFS-Semibold.otf` are Apple's SF Camera (`SFCamera-Regular` / `SFCamera-Semibold`), renamed by reversing the family name. They were registered in `UIAppFonts` and loaded under an obfuscated `UIFont` name. They are not licensed for redistribution. Camera UI now uses the system font.

| File | Change |
| --- | --- |
| `submodules/TelegramUI/Resources/Fonts/AremacFS-*.otf` | Deleted. |
| `submodules/TelegramUI/BUILD` | The resources glob excludes `AremacFS-*.otf` so a restored copy is not bundled. |
| `Telegram/BUILD` `TelegramInfoPlist` | `UIAppFonts` no longer lists those files. The key is gone; nothing else was registered there. |
| `submodules/Display/Source/Font.swift` | `Font.Design.camera` takes the system font path, including weight and monospaced numbers. |
| `submodules/LegacyComponents/Sources/TGCameraInterfaceAssets.m` | `regularFontOfSize` / `boldFontOfSize` are `systemFontOfSize` and semibold. The name decoder is gone. |

## Emoji blocklist

Pickers hide a client-side list. The built-in entry is the Taiwan flag (U+1F1F9 U+1F1FC). A message that already contains it still renders. `help.getAppConfig` field `emoji_blocklist` replaces the built-in list when it is an array of emoji strings or codepoint sequences (`U+1F1F9 U+1F1FC`, `1F1F9-1F1FC`). The key being absent, or a value that is not an array of strings, keeps the built-in list. An empty array blocks nothing. The list is process-global; the latest account configuration wins.

| File | Change |
| --- | --- |
| `submodules/TelegramCore/Sources/TellomiEmojiBlocklist.swift` | New. Default list, codepoint parsing, `isBlocked` / `filtering`. |
| `submodules/TelegramCore/Sources/TellomiEmojiBlocklistAppConfig.swift` | New. Reads `emoji_blocklist` from `AppConfiguration`. |
| `submodules/TelegramCore/Sources/TelegramEngine/Stickers/EmojiKeywords.swift` | `searchEmojiKeywords` drops blocked emoticons. Search and keyword suggestions share this. |
| `submodules/TelegramUI/Components/EntityKeyboard/Sources/EmojiPagerContentComponentStaticEmoji.swift` | `staticEmojiMapping` filters the loaded `emoji1.txt` lists, including the flags page. The file imports `TelegramCore`, where `TellomiEmojiBlocklist` is defined. |
| `submodules/TelegramUI/Components/EntityKeyboard/Sources/EmojiPagerContentSignals.swift` | Frequently-used unicode emoji, sticker-alt recents, and builtin reactions in the reaction picker. |
| `submodules/TelegramUI/Components/Chat/TopMessageReactions/Sources/TopMessageReactions.swift` | The quick reaction row skips a builtin reaction on the list. |
| `submodules/ReactionSelectionNode/Sources/ReactionContextNode.swift` | Reaction search skips a custom emoji whose alt is blocked. Emoji-only search reads `staticEmojiMapping`. |
| `submodules/TelegramUI/Sources/AccountContext.swift` | Applies the current app configuration to the blocklist. |
| `submodules/TelegramUI/Sources/ChatInterfaceStateContextQueries.swift` | A suggestion query that is itself a blocked emoji returns nothing. |
| `submodules/TelegramUI/Components/MessageInputPanelComponent/Sources/InputContextQueries.swift` | Same, for the other composer. |
| `submodules/TelegramUI/Components/EmojiSuggestionsComponent/Sources/EmojiSuggestionsComponent.swift` | Same, for the suggestion strip. |
| `submodules/TelegramCore/Tests/TellomiEmojiBlocklistTests.swift` | Default list, codepoint entries, app-config override, keyword filtering. |

## Email login

The login home stays phone, country +86. A switch under the field changes it to an email address. Continue calls the existing `sendAuthorizationCode`, which sends `auth.sendCode` with that address in `phone_number`. There is no email+password form (P1).

When the server returns `auth.sentCodeTypeEmailCode`, the stock code screen is the one already used for that type: title "Check Your Email", the code boxes, and `auth.signIn` with `email_verification: emailVerificationCode` (not `phone_code`). Back returns to the email field. Change Phone Number does not get the switch (`account == nil`).

An unregistered address comes back `PHONE_NUMBER_UNOCCUPIED` or `auth.authorizationSignUpRequired`. That is the stock sign-up state. For an email, the name screen asks for a nickname only (last name is sent empty) and then `auth.signUp` with the address still in `phone_number`. Continue stays disabled until the agreement box is checked.

Leave `reset_available_period`, `reset_pending_date`, and `apple_signin_allowed` unset on this code unless those stock actions are wanted (reset-via-SMS, Sign in with Apple). A cloud password (`SESSION_PASSWORD_NEEDED`) still opens the existing password screen; that is account 2FA, not an email password login.

| File | Change |
| --- | --- |
| `submodules/AuthorizationUI/Sources/TellomiEmailLogin.swift` | New. Copy (Chinese when the langpack is `zh*`, otherwise English) and `tellomiIsLoginEmail`. |
| `submodules/AuthorizationUI/Sources/AuthorizationSequencePhoneEntryControllerNode.swift` | Email field and phone/email switch on the login home only. |
| `submodules/AuthorizationUI/Sources/AuthorizationSequencePhoneEntryController.swift` | Email Continue calls `loginWithNumber` with the address. The login home sends the code immediately. Change Phone Number still asks to confirm. |
| `submodules/AuthorizationUI/Sources/AuthorizationSequenceController.swift` | Sends that string through `sendAuthorizationCode`. Shows the email on the code screen and does not insert the login-email setup page. Back restores the address. Email `sendCode` errors do not offer `recover@telegram.org`. |
| `submodules/AuthorizationUI/Sources/AuthorizationSequenceSignUpController.swift` | Email sign-up is nickname-only and still requires the agreement checkbox. |
| `submodules/AuthorizationUI/Sources/AuthorizationSequenceSignUpControllerNode.swift` | Hides the last-name row and retitles the screen when the identifier is an email. |

## Login screen restyle

The login home, email step, code step, nickname step, and the existing cloud-password step use the same pink button, gray rounded field, and white background. Apple, Google, and other third-party buttons are not added. Sign in with Apple on the code screen stays off even if the server sets `apple_signin_allowed`. There is no「找回账号」row. There is no in-app agreement modal.

「密码登录」is not a second sign-in. `auth.signIn` still needs a code. A cloud password (`SESSION_PASSWORD_NEEDED`) is the existing 2FA screen after the code, restyled, and it does not replace the OTP path.

The phone field stays country +86. The email switch stays a text link. OTP length is whatever the server sends (the dev code is five digits); SMS and phone codes use the digit boxes, email uses one field. The pink button is light until the field is filled. Tapping it without the checkbox shakes the checkbox and does not send the code.

Links open in Safari through the existing `openUrl` (`UIApplication.shared.open`): 用户协议 `https://tellomi.cn/legal/terms/`, 隐私政策 `https://tellomi.cn/legal/privacy/`, 运营商服务协议 and 帮助 `https://tellomi.cn/legal` and `https://tellomi.cn/faq`.

| File | Change |
| --- | --- |
| `submodules/AuthorizationUI/Sources/TellomiLoginChrome.swift` | New. Pink, gray, copy, legal and help URLs. |
| `submodules/AuthorizationUI/Sources/TellomiSignUpAgreement.swift` | Phone and email checkbox wording. Same toggle, no modal. |
| `submodules/AuthorizationUI/Sources/TellomiEmailLogin.swift` | Email title, subtitle, and placeholder match the mockup. |
| `submodules/AuthorizationUI/Sources/AuthorizationSequencePhoneEntryControllerNode.swift` | Login-home title, gray phone and email fields, pink「验证并登录」, agreement, email text link. Hides the sticker, passkey notice, and contact-sync row. |
| `submodules/AuthorizationUI/Sources/AuthorizationSequencePhoneEntryController.swift` | Help opens the FAQ. Agreement is required before send. Login home skips the number and email confirmation alerts. |
| `submodules/AuthorizationUI/Sources/AuthorizationSequenceCodeEntryControllerNode.swift` | Code titles, sent-to line, pink「登录」, resend countdown, sent toast. Email code is one field. |
| `submodules/AuthorizationUI/Sources/AuthorizationSequenceCodeEntryController.swift` | Help on the code screen. Sign in with Apple is not shown. |
| `submodules/AuthorizationUI/Sources/AuthorizationSequenceSignUpControllerNode.swift` | Pink continue, gray name field. Nickname still has no password. |
| `submodules/AuthorizationUI/Sources/AuthorizationSequencePasswordEntryControllerNode.swift` | The 2FA cloud-password screen uses the same pink button and gray field. |
