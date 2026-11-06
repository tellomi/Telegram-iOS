# Upstream patches for the Tellomi fork

Edits under `Telegram/` and `BUILD.bazel` that exist so Tellomi assets can ship. The artwork itself stays in `Tellomi/Brand/`.

| File | Change |
| --- | --- |
| `BUILD.bazel` | Exports `Tellomi/version`. Adds `//:TellomiAppIcon` (the `AppIcon.xcassets` size set, including iPad 152 and 167) and `//:TellomiAlternate_*` filegroups over `Tellomi/Brand`. |
| `Telegram/BUILD` | `app_icons` is `//:TellomiAppIcon` instead of `Telegram-iOS/TellomiPlaceholder.icon`. `alternate_icons` read `Tellomi/Brand/Alternates` instead of `Telegram-iOS/*.alticon`. The Info.plist fragment includes `NSLocationAlwaysAndWhenInUseUsageDescription` and does not register `AremacFS` fonts. |
| `Telegram/BUILD` `VersionInfoPlist` | `CFBundleShortVersionString` is read from `Tellomi/version`, not `versions.json`. |
| `versions.json` | `app` matches `Tellomi/version` (`1.0.1`) so the watch patch script and the plist agree. |

`AppIcons.xcassets`, `DefaultAppIcon.xcassets`, and `TellomiPlaceholder.icon` are still in the tree and are not the icons the Bazel app packages. The upstream `Telegram-iOS/*.alticon` originals are removed. `Tellomi/Brand/generate_icons.py` resizes from `Tellomi/Brand/Alternates`. `Tellomi/Brand/AppIcon.icon` is the Icon Composer document for the same glyph and is also not compiled: this rules_apple pin fails the build if an `.appiconset` is assigned next to an `.icon`, and the `.icon` compile does not emit the iPad 152×152 and 167×167 icons App Store still checks. Those two sizes ship inside `Tellomi/Brand/AppIcon.xcassets` (76pt @2x and 83.5pt @2x), rasterized from `logo.svg`.

`Tellomi/Brand/AppIcon.icon/icon.json` layer fills are `{ "solid": "srgb:…" }` (and `"automatic"` for the tinted appearance). A bare `srgb:` string is not a fill, and actool rejects it with `A fill should be one of: "orientation", "solid", "linear-gradient" or "automatic-gradient"`. The glyph is a PNG, not an SVG, so actool does not convert the traced path into a PDF.

## Login country code

The stock login default is the device region (`Locale.current` country code) with a fallback of +1. It does not read the SIM, and it does not read `help.getNearestDc`. `help.getConfig` `suggested_lang_code` is a language suggestion only.

| File | Change |
| --- | --- |
| `submodules/CountrySelectionUI/Sources/AuthorizationSequenceCountrySelectionController.swift` `defaultCountryCode()` | Always returns 86. The country picker is unchanged. |
| `submodules/AuthorizationUI/Sources/AuthorizationSequenceController.swift` | The duplicate helper forwards to that function. Restoring a phone-entry state with an empty number uses 86, so an update replaces a stored +1. A number the user already typed keeps its code. |

The same helper is what New Contact and Change Phone Number open with, so those fields also start at +86.

## Chinese system language

The app ships only `en.lproj`. Start Messaging used to call `downloadAndApplyLocalization` with `"en"`. The welcome pages themselves are Tellomi copy now (see Welcome copy below); they do not wait for that download. The welcome does not show a second language button. The saved pack lives in the account manager under `SharedDataKeys.localizationSettings`. `help.getConfig`'s suggestion is `PreferencesKeys.suggestedLocalization`. The language list cache is `Namespaces.CachedItemCollection.cachedAvailableLocalizations`. An update keeps all three. Reinstalling clears them. `UserDefaults` key `TellomiDidApplySystemLangPack` records that the automatic pack was applied, so a later choice in Settings is kept; reinstalling clears that key too. `tellomiSystemLangPackCode()` reads the global `AppleLanguages` list, because `Locale.preferredLanguages` is `en` when the bundle has no Chinese localization.

| File | Change |
| --- | --- |
| `submodules/AuthorizationUI/Sources/TellomiLoginLocale.swift` | `zh-Hans` / `zh-CN` / `zh` map to server langpack `zh-hans`. `zh-Hant` / `zh-TW` / `zh-HK` / `zh-MO` map to `zh-hant`. |
| `submodules/AuthorizationUI/Sources/AuthorizationSequenceSplashController.swift` | Start downloads that pack instead of `"en"` until the key above is set. |
| `submodules/AuthorizationUI/Sources/AuthorizationSequenceController.swift` | The login flow downloads the pack before it builds the splash or the phone screen, so a saved English pack from the old Start button is replaced. |
| `submodules/AuthorizationUI/Sources/TellomiIntroCopy.swift` | Welcome pages and the start button. Chinese when the system language is `zh*`, otherwise Tellomi English. Not the bundled Telegram tour. |
| `submodules/RMIntro/PublicHeaders/RMIntro/RMIntroViewController.h`, `Sources/platform/ios/RMIntroViewController.m`, `RMIntroPageView.m` | `setIntroHeadlines:descriptions:` replaces the six pages, including after the view has loaded. |
| `submodules/AuthorizationUI/Sources/TellomiLoginLocale.swift` `tellomiChromeLanguageCode` | Login chrome uses the system language until the automatic pack has been applied. A later choice in Settings is kept. `tellomiLoginCopy`, `tellomiEmailLoginCopy`, and the agreement follow it, so a Chinese device is not stuck on the bundled English pack. |
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
| `submodules/AuthorizationUI/Sources/TellomiSignUpAgreement.swift` | New. Builds the checkbox text. A single-tap recognizer on the label toggles the box or opens a link in Safari. The stock text-node recognizer waits for a double tap and only hits the glyph, so the ☐ box did not register, and setting the string did not redraw it. The hit rect grows past the label (leading edge and below). |
| `submodules/AuthorizationUI/Sources/AuthorizationSequenceSignUpControllerNode.swift` | Adds `tellomiAgreement` / `tellomiOpenUrl`; end of `init` disables Continue and installs the checkbox on `termsNode`; `updateData` always shows `termsNode`. |
| `submodules/AuthorizationUI/Sources/AuthorizationSequenceSignUpController.swift` | Wires `tellomiOpenUrl` to `openUrl`; `nextPressed()` refuses (haptic error) until the box is checked, which also covers the small-screen Next bar button. |

Email registration uses this same screen. The links stay `https://tellomi.cn/legal/terms/` and `https://tellomi.cn/legal/privacy/`, opened with `UIApplication.shared.open` (no in-app terms modal).

## iPad icons 152 and 167

App Store still asks for an iPad icon of exactly 152×152 pixels and an iPad Pro icon of exactly 167×167, for the primary icon and for every alternate. The Icon Composer document does not emit those sizes, and `app_icons` cannot list both `AppIcon.icon` and the size set. `//:TellomiAppIcon` is `Tellomi/Brand/AppIcon.xcassets`, whose 76pt @2x and 83.5pt @2x slots are those pixels, rasterized from the same `logo.svg`.

Alternate icons are loose PNGs. `alticonstool` puts every filename in `CFBundleIcons~ipad` `CFBundleAlternateIcons`, so each slot also needs those two sizes on disk. They were already present for the classic, filled, Water, and Sunset slots. Premium, Premium Black, Premium Turbo, and White Filled only had the 120 and 180 iPhone files; `generate_icons.py` now renders `*Ipad@2x.png` (152) and `*LargeIpad@2x.png` (167) from the same slot artwork. Removing those slots from the iPad list would also remove them from the iPhone list, and Settings still offers them.

The primary 152 and 167 renders are copied to `Tellomi/Brand/LooseIpadIcons` and bundled at the app root. `Telegram/ensure_ipad_home_icons.sh` (`ipa_post_processor`) appends `TellomiHomeIpad76` and `TellomiHomeIpad83` to `CFBundleIcons~ipad` `CFBundlePrimaryIcon` `CFBundleIconFiles` and fails the build if any listed alternate icon has no 152 or 167 PNG. The Info.plist fragment cannot declare `CFBundleIcons~ipad` itself: actool already writes that key, and plisttool rejects the duplicate.

The traced bubble fills the viewBox. `Tellomi/Brand/generate_icons.py` scales it so the painted mark stays inside 75–80% of the square: 78% on the home-screen set (light, dark, tinted), on `AppIcon.icon/Assets/Logo.png`, and on Default, Water, and Sunset. Classic is 76% inside a round base. Filled is 79.5% on a color that runs to the edge of the square. Water is a teal-to-cyan gradient and Sunset is a pink-to-purple gradient. Premium is a star field; Turbo and Black add a gold star. None of those PNGs replace the upstream `Telegram-iOS/*.alticon` files. The Settings names stay the existing slots (`BlueIcon`, `New2`, `New1`, `BlackIcon`, `BlueClassicIcon`, `BlackClassicIcon`, `BlueFilledIcon`, `BlackFilledIcon`, `Premium`, `PremiumTurbo`, `PremiumBlack`).

## Location purpose string

`UIBackgroundModes` includes `location`, so the main Info.plist must contain `NSLocationAlwaysAndWhenInUseUsageDescription`. The shipping string is the Bazel fragment in `Telegram/BUILD`. `en.lproj` is English for that key. `zh-Hans.lproj` and `zh-Hant.lproj` carry the Chinese sentences. Both languages already ship a real `Localizable.strings` from `AppStringResources`, so they stay out of `empty_languages`. `InfoPlistStringResources` globs every `*.lproj/InfoPlist.strings`, which is how the Traditional permission file is bundled.

| File | Change |
| --- | --- |
| `Telegram/BUILD` `TelegramInfoPlist` | Adds the key. The app name is `{telegram_app_name}`. |
| `Telegram/Telegram-iOS/Info.plist`, `InfoBazel.plist` | Same key, with Tellomi written out. These are not the plist the Bazel app links. |
| `Telegram/Telegram-iOS/en.lproj/InfoPlist.strings` | English for `NSLocationAlwaysAndWhenInUseUsageDescription`. |
| `Telegram/Telegram-iOS/zh-Hant.lproj/InfoPlist.strings` | Traditional Chinese for every key in `zh-Hans`. |
| `Telegram/BUILD` `InfoPlistStringResources` | The glob includes `zh-Hant.lproj/InfoPlist.strings`. `zh-Hant` stays out of `empty_languages` because `AppStringResources` already lists its `Localizable.strings`. |

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

The login home stays phone, country +86 (mockups that show +66 are not the default). Email is its own screen, reached from「邮箱登录」. Continue on a code screen calls the existing `sendAuthorizationCode`, which sends `auth.sendCode` with that address in `phone_number`. Phone and email password screens are in the flow. `auth.signIn` still needs a code, so submitting a password shows「账号或密码错误，请重试。」

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

Owner mockups in `login-ui-ref/owner-2026-10-31/` are the layout. Primary buttons are not the pink in those shots. Brand buttons are black `#111111` with white text. Disabled buttons are `#E5E5E5` with gray `#8E8E93` text. Links are `#3478F6`. Errors are `#FF3B30`. A checked agreement circle is black.

The login home, email step, password step, code step, nickname step, and the existing cloud-password step share that chrome and the gray rounded field. Sign in with Apple on the code screen stays off even if the server sets `apple_signin_allowed`. Apple, Google,「其他登录方式」,「找回账号」, and the round social buttons present「暂未开放」. They do not start a sign-in.「邮箱登录」opens the email screen.

「密码登录」is a screen, not a second protocol. There is no password sign-in RPC, so 登录 on the phone and email password screens shows the same「暂未开放」notice as Apple, Google, 其他登录方式, and 找回账号. It does not show「账号或密码错误，请重试。」. A cloud password (`SESSION_PASSWORD_NEEDED`) is still the existing 2FA screen after a code.

The phone field stays country +86. OTP length is whatever the server sends (the dev code is five digits); SMS and phone codes use filled digit boxes, email uses one field. The black button is gray until the field is filled. Tapping it without the checkbox opens the agreement card (「同意并登录」/「不同意」) and does not send the code. The circle is a 44pt control. `ImmediateTextNode` now keeps the tap recognizer it adds, so the sentence links receive the tap as well.

Copy follows the system language. Chinese (and an empty preferred-language list) uses the bundled Chinese strings. Anything else uses English. The welcome carousel does the same, and its titles say Tellomi.

Links open in Safari through the existing `openUrl`: 用户协议 `https://tellomi.cn/legal/terms/`, 隐私政策 `https://tellomi.cn/legal/privacy/`, 运营商服务协议 `https://tellomi.cn/legal`, 帮助 and「收不到验证码?」`https://tellomi.cn/faq`. Login errors that used to mail `recover@telegram.org` or `sms@telegram.org` open that FAQ instead.

| File | Change |
| --- | --- |
| `submodules/AuthorizationUI/Sources/TellomiLoginChrome.swift` | Black / gray / blue chrome, copy, legal and help URLs, login surface enum. |
| `submodules/AuthorizationUI/Sources/TellomiLoginSurfaces.swift` | New. Agreement row, social rows, circle buttons, password field, agreement card. |
| `submodules/AuthorizationUI/Sources/TellomiSignUpAgreement.swift` | Phone, email, and sign-up wording. The circle is a real control. Sentence taps use the single-tap recognizer from the checkbox fix. |
| `submodules/AuthorizationUI/Sources/TellomiEmailLogin.swift` | Email title, subtitle, and placeholder. Chinese follows `tellomiChromeLanguageCode`. |
| `submodules/AuthorizationUI/Sources/AuthorizationSequencePhoneEntryControllerNode.swift` | Phone home, phone password, email, email password. Hides the sticker and the contact-sync row. |
| `submodules/AuthorizationUI/Sources/AuthorizationSequencePhoneEntryController.swift` | Help, agreement card,「暂未开放」for Apple, Google, other methods, account recovery, and password 登录. X on the phone home. |
| `submodules/AuthorizationUI/Sources/AuthorizationSequenceCodeEntryControllerNode.swift` | Code titles, sent-to line, black「登录」, resend countdown,「收不到验证码?」, sent toast, sticky email error. |
| `submodules/AuthorizationUI/Sources/AuthorizationSequenceCodeEntryController.swift` | Help on the code screen and on「收不到验证码?」. Sign in with Apple is not shown. |
| `submodules/AuthorizationUI/Sources/AuthorizationSequenceSignUpControllerNode.swift` | Black continue, gray name field, tappable agreement circle. |
| `submodules/AuthorizationUI/Sources/AuthorizationSequencePasswordEntryControllerNode.swift` | The 2FA cloud-password screen uses the same black button and gray field. |
| `submodules/AuthorizationUI/Sources/AuthorizationSequenceController.swift` | Login help no longer mails `recover@telegram.org` or `sms@telegram.org`. |
| `submodules/AuthorizationUI/Sources/AuthorizationSequenceSplashController.swift` | Start button is black. Welcome pages stay `tellomiIntroCopy()`. |
| `submodules/CodeInputView/Sources/CodeInputView.swift` | Optional box fill and a width that spans the row, used by the SMS code screen. |

## Login fixes after TestFlight 14.0.1

Owner reports on 14.0.1. The welcome, login, and code screens follow the system language even when the bundle only ships `en.lproj` (`Locale.preferredLanguages` is then `en`). `UserDefaults` global `AppleLanguages` is the unfiltered list. `tellomiLangPackCode(preferredLanguages:)` maps `zh-Hans` / `zh-CN` / `zh` to `zh-hans` and `zh-Hant` / `zh-TW` / `zh-HK` / `zh-MO` to `zh-hant`. Anything else stays English. The welcome no longer asks `help.getConfig` for a second button, so 「使用英文继续」/ "Continue with English" is gone. The only button is 「开始使用」/ "Get Started".

An in-app code (`sentCodeTypeApp`) uses the same code screen as SMS. After a code is accepted, the window waits until the signed-in root is ready (the chat list ready signal is capped at 2s) and installs that root before dismissing the code screen. A later language-pack callback cannot rebuild the welcome on top of a finished sign-in.

Add Account never pushes the welcome. A signed-in account with no phone used to look like a fresh install (`otherAccountPhoneNumbers` dropped it), which opened the intro with no back. Every existing account stays in that list, with a placeholder when it has neither a phone nor an email. Back/Close leaves the flow. Typing a number or address that is already on the device shows 「该账号已登录」and switches to it. If a second session for the same peer is created anyway, it is dropped and the existing account stays current.

Settings → Logout no longer requires `user.phone`, so an email session can log out. Settings → Account shows the phone when there is one and the email when there is one (phone above email). The account switcher subtitle prefers the phone, otherwise `a***@x.com`. The login address is stored on the device because it is not a user field. 「绑定手机号」opens the existing +86 change-number flow; the button says 「绑定」.

Login fields and buttons follow light and dark. Light keeps `#111111` / white, disabled `#E5E5E5` / `#8E8E93`, links `#3478F6`, error red, checkbox black. Dark uses a white button and a dark field so typed text and the button stay readable. The authorization flow applies a theme change while it is on screen.

| File | Change |
| --- | --- |
| `submodules/TelegramCore/Sources/TellomiAccountIdentity.swift` | Email/phone split, mask, stored login email, identifier match, welcome-vs-add-account, langpack code. |
| `submodules/TelegramCore/Sources/Authorization.swift` | Remembers an email login on the user id. |
| `submodules/AuthorizationUI/Sources/TellomiLoginLocale.swift` | System language from the global language list. |
| `submodules/AuthorizationUI/Sources/AuthorizationSequenceSplashController.swift` | No second language button. |
| `submodules/AuthorizationUI/Sources/AuthorizationSequenceController.swift` | No welcome under Add Account. Do not rebuild login after authorization. Theme updates. |
| `submodules/AuthorizationUI/Sources/AuthorizationSequencePhoneEntryController.swift` | 「该账号已登录」for phone and email. Bind-phone flag. |
| `submodules/AuthorizationUI/Sources/AuthorizationSequenceCodeEntryControllerNode.swift` | In-app codes use the SMS code screen. Dark field text. |
| `submodules/AuthorizationUI/Sources/TellomiLoginChrome.swift` | Light and dark palettes. Bind and account strings. |
| `submodules/TelegramUI/Sources/AppDelegate.swift` | Every signed-in account is listed. Root is installed before the code screen is dismissed. |
| `submodules/TelegramUI/Sources/ApplicationContext.swift` | Chat-list ready is capped so the first sign-in can show the main UI. |
| `submodules/TelegramUI/Sources/SharedAccountContext.swift` | A second session for a peer already on the device is dropped. |
| `submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoScreenSettingsActions.swift` | Logout without a phone. Bind vs change number. |
| `submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoSettingsItems.swift` | Phone row, email row, 「绑定手机号」. |
| `submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoHeaderNode.swift` | Header subtitle: phone, else masked email. |
| `submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/ListItems/PeerInfoScreenMemberItem.swift` | Switcher subtitle. |
| `submodules/SettingsUI/Sources/ChangePhoneNumberController.swift` | Bind copy on the existing send-code flow. |
| `submodules/TelegramPresentationData/Sources/PresentationData.swift` | `withTheme`. |

## TestFlight 14.0.2 login

Owner reports on 14.0.2 (build 58). The login screens stay the existing Tellomi chrome. These edits put that chrome back on the stock Telegram paths.

| Owner item | File |
| --- | --- |
| Phone OTP crash after the code is accepted | `submodules/TelegramCore/Sources/Authorization.swift` `tellomiStoreAuthorizedUser`. `auth.signIn` built a `TelegramUser` and never wrote it into the peer table. The first signed-in screen reads that peer. Email sign-up reached the name screen first, so the peer arrived later; a phone code that logged straight in did not. The same write is on the password, sign-up, passkey, and recovery paths. |
| Phone string indexes that trap only when a number is formatted | `submodules/PhoneNumberFormat/Sources/PhoneNumbers.swift` `formatPhoneNumberToMask`. `submodules/PhoneInputNode/Sources/PhoneInputNode.swift` no longer slices one string with another string's `endIndex` (the broken country-code edit). |
| Login / OTP / sign-up Chinese, while 「开始使用」 already was | `submodules/AuthorizationUI/Sources/TellomiLoginLocale.swift` `tellomiInterfaceLanguageCode`. Callers were passing `baseLanguageCode`. After zh-hans is applied that value is the pack's English fallback, so the login copy stayed English. |
| iOS Settings lists 简体中文 | `Telegram/Telegram-iOS/zh-Hans.lproj` is a real localization. `InfoPlist.strings` is the permission copy. `Localizable.strings` holds the APNs `loc-key` fallback (see Push localization below). `CFBundleDevelopmentRegion` stays `en`, which is the bundled string fallback for every other key. |
| Welcome mark is Tellomi, not the paper plane | `Telegram/Telegram-iOS/Resources/intro/telegram_sphere@2x.png` is the Tellomi glyph. `telegram_plane1@2x.png` is empty, so the OpenGL intro does not draw the plane. The same two files under `submodules/RMIntro/Sources/platform/ios/Resources/` match. The page layout is unchanged. |
| Wrong code on its own line | `AuthorizationSequenceCodeEntryControllerNode` puts the red line in the stack between the field and Log in. It reads 「请输入正确的验证码」 from `tellomiLoginCopy`. |
| Code field stays put when the keyboard dismisses | The same node keeps the keyboard inset after `inputHeight` goes to zero. The stack is centered in that inset, which is where it sat while the keyboard was up. |
| Country code opens the list | `PhoneAndCountryNode` in the login chrome disables the code field. A tap on that column is the existing `AuthorizationSequenceCountrySelectionController`. |
| Apple / Google / Email / Other stay on the phone home | `layoutTellomiHome` no longer hides those rows when `inputHeight` is set. Apple, Google, and Other still present 「暂未开放」. Email still opens the email screen. |
| Icons and password alignment | `TellomiSocialRowNode` / `TellomiCircleButtonNode` scale the glyph inside the slot. The phone password field uses the same 78pt column as the country code, so the password text lines up with the number. |
| 绑定手机号 / 绑定邮箱 / change email | `PeerInfoSettingsItems` draws both as disclosure rows (icon, title, chevron), the same row as change phone. No phone → 绑定手机号 and the existing change-phone flow. No email → 绑定邮箱. An email row opens `loginEmailSetupController` (the stock login-email change: address, then code, `account.sendVerifyEmailCode` / `account.verifyEmail` with `emailVerifyPurposeLoginChange`). The address is stored with `tellomiRememberLoginEmail` because it is not a user field. |

## Chat list, settings, and login chrome (14.0.3对照)

The server langpacks (`ios` `zh-hans` / `en`) already say Tellomi. The bundled `en.lproj` fallback and any string `getSingle` still reads do not. Official service user `777000` and notification user `333000` with no photo draw a letter from the name (T when the name is Telegram or Tellomi). Login confirmations still read `baseLanguageCode`, which stays `en` after zh-hans is applied, so the email dialog body stayed English next to Chinese chrome. Choosing a language in Settings did not set `TellomiDidApplySystemLangPack`, so the login chrome kept the system language after that choice.

No version bump. The formal 14.0.3 build is not cut here.

| File | Change |
| --- | --- |
| `build-system/GenerateStrings/GenerateStrings.py` | `getSingle` rewrites Telegram, 电报, and the other brand tokens, then the public hosts (`telegram.org`, `t.me`, `telegram.me`, `telegram.dog`). `t.me` is replaced only as its own host, so `not.me` stays. |
| `submodules/TelegramPresentationData/Sources/TellomiBrandRewrite.swift` | The same rewrite for dictionaries and for a service account's display name. |
| `submodules/TelegramPresentationData/Sources/PresentationData.swift` | `dictFromLocalization` runs that rewrite, so a downloaded pack is covered even when a key is read from the dict. |
| `submodules/TelegramPresentationData/Sources/DefaultPresentationStrings.swift` | The bundled English dictionary is rewritten before it becomes the fallback pack. |
| `submodules/LocalizedPeerData/Sources/PeerTitle.swift` | `777000` and `333000` display names replace a Telegram token with Tellomi. A service account with no name is Tellomi. |
| `submodules/AvatarNode/Sources/AvatarNode.swift` | Those two peers, when they have no photo, draw `Avatar/TellomiMark` (the QR logo PDF) in white on `#17171A` instead of a letter. A photo from the server is kept. |
| `submodules/TelegramUI/Images.xcassets/Avatar/TellomiMark.imageset` | That PDF. |
| `submodules/AuthorizationUI/Sources/TellomiLoginChrome.swift` | Chinese confirm, edit, yes, and sign-up labels used when the chrome language is Chinese. `tellomiBundledChineseLoginCopy` takes `PresentationStrings`, so this file imports `TelegramPresentationData`. The other imports do not bring that type into scope. |
| `submodules/AuthorizationUI/Sources/AuthorizationSequencePhoneEntryController.swift` | The email confirm dialog uses `tellomiInterfaceLanguageCode`, not `baseLanguageCode`. |
| `submodules/AuthorizationUI/Sources/AuthorizationSequencePhoneEntryControllerNode.swift` | The phone confirmation card uses the bundled Chinese labels on a Chinese chrome. |
| `submodules/AuthorizationUI/Sources/AuthorizationSequenceSignUpControllerNode.swift` | Sign-up title, help, and name placeholders do the same. |
| `submodules/AuthorizationUI/Sources/TellomiLoginLocale.swift` | Built-in rows: 简体中文, 繁體中文, English. |
| `submodules/SettingsUI/Sources/Language Selection/LocalizationListControllerNode.swift` | Those rows are added when the server list does not already contain them, including while the list is still empty. Applying a language sets `TellomiDidApplySystemLangPack`, so the login chrome follows the choice. |
| `submodules/SettingsUI/Sources/Search/SettingsSearchableItems.swift` | Settings search applies a language the same way. |

Already in place, not changed: 绑定邮箱 uses `PresentationResourcesSettings.email` (`Item List/Icons/Email`). The login-home 邮箱登录 row uses the envelope symbol. Contact address label `Telegram` is the match key for saved contacts and is not a title.

## Welcome copy

The intro used to read `en.lproj` (`Tour.Title1` = "Telegram", `Tour.StartButton` = "Start Messaging") and ignore the system language. A Chinese device stayed on that English tour until Start downloaded a langpack, and the carousel itself never changed. The six pages and the button now come from `tellomiIntroCopy()`: Simplified Chinese when `tellomiSystemLangPackCode()` is set, otherwise Tellomi English ("Get Started", not "Start Messaging"). The OpenGL page layout is unchanged. The center mark is the Tellomi glyph (see TestFlight 14.0.2 login). The Start button uses the black login chrome.

## Last seen year

`stringForTimestamp` and `stringForMediumDate` showed a two-digit year as `tm_year - 100`. `tm_year` is years since 1900, so 2026 is 26 and 1970 is **-30**. A profile whose `userStatusOffline.was_online` is 0 (stored as presence `.present(until: 0)`, the Unix epoch) rendered as `01/01/-30`. Years before 2000 now print in full (`calendarDisplayYear`). A presence timestamp of 0 or less is "last seen a long time ago" instead of that date. The value still comes from the server; this only changes how 0 and pre-2000 dates are drawn.

## Open in Chinese map apps

A shared location or a venue opens `OpenInOptionsScreen`. The list was Apple Maps, then whatever `canOpenURL` said was installed (Google Maps, Yandex, and the rest). Mainland users need 高德, 百度, and 腾讯. Google Maps stays in that installed check. Apple Maps stays first and is always listed.

Telegram stores WGS-84. 高德 is opened with `dev=1`, so the app converts. 百度 is opened with `coord_type=wgs84`. 腾讯's `qqmap://` marker and routeplan calls are GCJ-02 and do not take a coordinate type (that parameter is on the web URI), so those coordinates are converted here. Apple Maps is given the stored WGS-84 point. In China it applies the offset itself. The place name is the venue title. Directions start at the current location.

Labels follow the same language rule as the login chrome. `zh-hans` / `zh-cn` / `zh` use 高德地图, 百度地图, 腾讯地图, 地图, and 谷歌地图. Anything else, including `zh-hant`, uses the English names. The server langpack has no keys for these, and the bundled strings are English, so the names are not `Localizable.strings` entries. `TellomiDidApplySystemLangPack` still decides whether the saved pack or the system language wins.

`canOpenURL` only answers for schemes in `LSApplicationQueriesSchemes`. The plist the Bazel app links is the `TelegramInfoPlist` fragment in `Telegram/BUILD`. `Info.plist` and `InfoBazel.plist` are updated to match and are not that fragment.

| File | Change |
| --- | --- |
| `submodules/OpenInExternalAppUI/Sources/TellomiMapOpenIn.swift` | New. Labels, order, GCJ-02, and the three URL builders. |
| `submodules/OpenInExternalAppUI/Sources/OpenInOptions.swift` | Apple Maps, then 高德 / 百度 / 腾讯, then the existing apps. Google Maps is still hidden when it is not installed. |
| `submodules/OpenInExternalAppUI/Sources/OpenInOptionsScreen.swift` | Apple Maps receives the venue name with the WGS-84 point. |
| `submodules/LocationUI/Sources/LocationViewController.swift` | The open-in item carries the peer name used for a live location. The single-app Apple Maps path still prefers the venue title, then that name. |
| `submodules/TelegramUI/Components/PeerInfo/PeerInfoStoryGridScreen/Sources/StorySearchGridScreen.swift` | A venue opened from stories keeps its `MapVenue`, so the place name and address reach the sheet. |
| `Telegram/BUILD` `TelegramInfoPlist` | `iosamap`, `baidumap`, `qqmap`. |
| `Telegram/Telegram-iOS/Info.plist`, `InfoBazel.plist` | The same three schemes. |
| `submodules/OpenInExternalAppUI/Tests/TellomiMapOpenInTests.swift` | Host test of the URLs, the conversion, the labels, and the order. |

## Teamgram on screen

There is no client string "Teamgram" in the auth, login, session, or profile UI. The word appears in comments and in `Tellomi/tellomi-server.json`.

| What the owner sees | Where it comes from |
| --- | --- |
| Active session named Teamgram | `authorization.appName` from `account.getAuthorizations`, drawn in `ItemListRecentSessionItem` / `RecentSessionScreen`. `initConnection` has no app-name field. The server names the session from `api_id` (this client sends `100001`). |
| Profile title Teamgram and @teamgram | `user.first_name` and `user.username` on the user the server returns. The client does not invent a display name for that peer. |

Replacing those on the client would disagree with the account the server stores. "Didn't get a code" opens `https://tellomi.cn/help/` instead of mailing `sms@telegram.org`.

## Login code screen, pending code, and narrow digits

Checked against the Android reports (mixed English on a Chinese phone, keyboard covering the login header, sixth code box clipped, untranslated Bind phone number, stale SMS number). The phone home, the agreement card, email entry, and Settings → Account already take Simplified Chinese from `tellomiLoginCopy` / `tellomiEmailLoginCopy` when `tellomiChromeLanguageCode` resolves to `zh*`. That reads `AppleLanguages`, not `Locale.preferredLanguages`, so an English-only bundle does not force English. Apple, Google, other methods, account recovery, and password login already present 「暂未开放」. Settings → Account draws 绑定手机号 / 绑定邮箱 as the same disclosure row as a phone number (icon, title, chevron). The phone home is top-pinned under the navigation bar and does not move when the keyboard opens (`disableAutomaticKeyboardHandling`), so Help stays above the title.

The code screen did not. It centered in a region that started at the status bar and reserved a full keyboard, so on a short phone the title sat under Help. Six digit boxes used `max(preferred, fitted)` and kept the preferred width when the row was narrower than that, so the last box crossed the row on a 320pt width. Back asked "cancel verification?" and left `.confirmationCodeEntry` stored; the next launch opened that screen again. A `sendCode` that finished after Back, or after a newer number was submitted, wrote its own `phone_code_hash` and the code screen showed the earlier number.

| File | Change |
| --- | --- |
| `submodules/TelegramCore/Sources/Authorization.swift` | `TellomiLoginAttempt`. `sendAuthorizationCode` and `resendAuthorizationCode` write the code state only while that attempt is still current. The check and the write hold the same lock. |
| `submodules/TelegramCore/Sources/TelegramEngine/Auth/TelegramEngineAuth.swift` | `TelegramEngineUnauthorized.Auth.replaceConfirmationCodeEntryWithPhoneEntry` writes phone entry only while the stored contents are still `.confirmationCodeEntry`. Password, payment, and any other state stay. The check and the write are one transaction. |
| `submodules/AuthorizationUI/Sources/AuthorizationSequenceController.swift` | Each send takes an attempt. Back, close, and a new number retire it and cancel the in-flight request. A code state that is not the current attempt (including one restored at launch) is replaced with phone entry through that method. The number is kept in the field; the hash is not. The push-token wait is `pushConfigurationDisposable`. It is not `actionDisposable`: `authorizationPushConfiguration` already has a value and `deliverOnMainQueue` delivers it inline, so one shared `set` disposed `auth.sendCode` before the request was sent. Phone and email both use `loginWithNumber`. |
| `submodules/AuthorizationUI/Sources/AuthorizationSequenceCodeEntryController.swift` | SMS, email, call, firebase, and other-session back returns immediately. The cancel dialog stays for word and phrase. |
| `submodules/AuthorizationUI/Sources/AuthorizationSequenceCodeEntryControllerNode.swift` | The Tellomi code stack is centered under the navigation bar. When that band is shorter than the stack, the stack stays top-aligned there instead of moving up under Help. |
| `submodules/CodeInputView/Sources/CodeInputView.swift` | Expanded digit boxes shrink, spacing first down to 4pt, so six boxes stay inside the width they were given. |

## Default wallpaper and accent

New installs, and accounts that never stored a wallpaper, use a solid chat background. Light built-in themes (`.dayClassic`, the default, and `.day`) are `#F2F2F2`. Dark built-in themes (`.night` and `.nightAccent`) are `#000000`. A wallpaper written into `themeSpecificChatWallpapers` is an explicit choice and is left alone. The historical `.builtin` token used to expand to the legacy pattern; it now expands to the same solid color. Accent editing no longer suggests the green Telegram gradient as the fallback wallpaper.

The light theme accent (`defaultDayAccentColor`) is black. System night mode no longer forces the blue accent onto `.night`, so that theme keeps the white controls it is built with. Someone who already picked a color, including blue, keeps it.

Left as they are, because they are not the default chrome accent: message link blue (`0x004bad`), the night theme's outgoing bubble gradient (`0x61BCF9` / `0x0088ff`), the tinted theme's accent (`0x2ea6ff`) and the wallpapers bundled with its color presets, `defaultDarkColorPresentationTheme` (`0x3e88f7`, used by the camera, gallery, stories, and calls), the intro start button (`0x2ca5e0`), and the passcode gradient.

| File | Change |
| --- | --- |
| `submodules/TelegramPresentationData/Sources/DefaultDayPresentationTheme.swift` | Solid light wallpaper. Accent is black. Day-theme outgoing bubbles are solid black so the white text still has a fill. Suggested accent wallpaper is the solid color. |
| `submodules/TelegramPresentationData/Sources/DefaultDarkPresentationTheme.swift` | Solid black wallpaper. |
| `submodules/TelegramPresentationData/Sources/DefaultDarkTintedPresentationTheme.swift` | Solid black wallpaper. |
| `submodules/TelegramPresentationData/Sources/PresentationData.swift` | `.builtin` resolves to the solid color. Auto night does not inject blue. |
| `submodules/SettingsUI/Sources/ThemePickerController.swift` | Night preview matches that. The Day swatch defaults to black. Removing a theme does not fall back to blue. |
| `submodules/SettingsUI/Sources/Themes/ThemeSettingsController.swift` | Removing a theme does not fall back to blue. |
| `submodules/TelegramUI/Components/Settings/WallpaperGridScreen/Sources/ThemeGridControllerNode.swift` | The gallery's built-in slot is the solid color. |
| `submodules/HashtagSearchUI/Sources/HashtagSearchControllerNode.swift` | The forced dark search background is solid black. |

## MingCute icons, phase 1

The most visible template icons are MingCute outlines (and fills where a
selected state is a different drawing). `Tellomi/Icons/generate_icons.py`
writes a black PDF at the old point size. The catalog still tints it.
`TabChats`, `TabContacts`, `TabCalls`, `TabSettings`, and `TabNews` are not
played. The selected tab is the fill image and scales from 0.86 to 1.
Attach-menu tabs and chat-list swipes are static images too. Login screens
are unchanged.

| File | Change |
| --- | --- |
| `Tellomi/Icons/mapping.csv`, `generate_icons.py`, `MingCute/` | The mapping, the converter, and the Apache-2.0 SVGs it reads. |
| `submodules/TelegramUI/Images.xcassets` | The imagesets named in the csv. |
| `submodules/ChatListUI/Sources/ChatListController.swift`, `ContactListUI`, `CallListUI`, `News/NewsScreen`, `PeerInfo/PeerInfoScreen` | Line icon, fill icon, no tab Lottie. |
| `submodules/TabBarUI/Sources/TabBarNode.swift` | Selection scale when the item has no Lottie name. |
| `submodules/AttachmentUI/Sources/AttachmentPanel.swift` | Attach tabs use the line or fill image. |
| `submodules/ChatListUI/Sources/Node/ChatListItem.swift` | Swipe actions use `Chat List/Swipe`. |
| `submodules/TelegramUI/Resources/Animations/Tab*` | The sixteen tab Lottie files nothing references anymore are deleted. `ForumTabs.tgs` stays. |

## Login language, sent-code copy, duplicate session

Mirrors Android `tellomi/Telegram` #31 on the phone and code screens. The top-right control is no longer Help. It is the current language plus ▾ (`简体中文 ▾`, `繁體中文 ▾`, `English ▾`). The card is the same centered login card as the agreement prompt, titled「选择语言 / Language」, with those three built-in rows, a check on the current one, and Cancel. There is no Other row and no `langpack.getStrings` call. Upstream language screens need a logged-in account.

The choice is stored in `UserDefaults` `TellomiPreferredInterfaceLanguage`, and `TellomiDidApplySystemLangPack` is set so the automatic Chinese pack does not replace it. Login chrome reads that key first. The phone number, email, password, and code already typed stay in the fields. Settings ▸ Language writes the same `UserDefaults` key when a pack finishes downloading. Applying a language no longer stores an empty pack; see "Language pack download" below.

Help moved to「收不到验证码？」on the code screen (SMS, call, in-app, Firebase, and email). The card's Help row opens `https://tellomi.cn/help/` (`TellomiLoginChrome.helpURL`; `/faq` 404s). SMS, call, and Firebase also offer Resend on that card once the countdown has finished. An in-app code (`sentCodeTypeApp`, `.otherSession`) says「验证码已发送到你在其他设备上登录的 Tellomi」and shows「改用短信接收」, which calls `auth.resendCode` through `TelegramEngineUnauthorized.Auth.resendLoginCode`. SMS, call, and email keep their own lines. Traditional copy is bundled too; Android could not ship `zh-rTW`.

Signing in an account that is already on the device sends `auth.logOut` on the new `Account` (`TelegramEngine.Auth.logOut`) before the local record is removed. The engine is held until that RPC finishes.

| File | Change |
| --- | --- |
| `submodules/AuthorizationUI/Sources/TellomiLoginLocale.swift` | Preferred-language key, script (hans / hant / en), button title, apply. |
| `submodules/AuthorizationUI/Sources/TellomiLoginChrome.swift` | Help URL is `https://tellomi.cn/help/`. Sent-code, language, and cancel strings in zh-Hans, zh-Hant, and English. |
| `submodules/AuthorizationUI/Sources/TellomiEmailLogin.swift`, `TellomiSignUpAgreement.swift` | Traditional login and agreement sentences. |
| `submodules/AuthorizationUI/Sources/TellomiChoicePrompt.swift` | New. Language card and the code-not-received card. |
| `submodules/AuthorizationUI/Sources/AuthorizationSequencePhoneEntryController.swift` | Language button. Redraw keeps the typed number. |
| `submodules/AuthorizationUI/Sources/AuthorizationSequencePhoneEntryControllerNode.swift` | Relabels the home when the language changes. |
| `submodules/AuthorizationUI/Sources/AuthorizationSequenceCodeEntryController.swift` | Language button. Code-not-received card. |
| `submodules/AuthorizationUI/Sources/AuthorizationSequenceCodeEntryControllerNode.swift` | App / SMS / call / email lines.「改用短信接收」. |
| `submodules/AuthorizationUI/Sources/AuthorizationSequenceController.swift` | Resend goes through the engine, including an app code with no `next_type`. |
| `submodules/TelegramCore/Sources/Authorization.swift` | `auth.resendCode` is sent even when `next_type` is empty. |
| `submodules/TelegramCore/Sources/TelegramEngine/Auth/TelegramEngineAuth.swift` | `resendLoginCode`, `logOut`. |
| `submodules/TelegramCore/Sources/TellomiInterfaceLanguage.swift` | Was an empty version-0 pack with no network. That write is no longer how a language is applied. |
| `submodules/TelegramUI/Sources/SharedAccountContext.swift` | `auth.logOut` on a duplicate login before the record is dropped. |
| `submodules/SettingsUI/Sources/Language Selection/LocalizationListControllerNode.swift`, `Search/SettingsSearchableItems.swift` | A Settings language writes the same preference key. |

## Push localization fallback

APNs `alert.loc-key` is resolved by the system from the main app bundle. The Notification Service extension does not ship `Localizable.strings`, and when it times out Apple shows the outer payload. That payload's keys are `MESSAGE_AUDIO`, `CHAT_MESSAGE_*`, `CHANNEL_MESSAGE_*`, `PINNED_TEXT`, not the `PUSH_*` names in `en.lproj`. `zh-Hans` used to be an empty generated file, so a Chinese device had nothing to look up.

`loc-args` follow `pkg/push` on the server: a private message is the sender name (and the text, for `MESSAGE_TEXT` / `PINNED_TEXT`); a group is sender, chat title, then text; a channel is the channel title, then text. `PINNED_*` is not prefixed. The format string includes the name, because a loc-key alert has no separate title when the extension does not run.

| File | Change |
| --- | --- |
| `Telegram/Telegram-iOS/en.lproj/Localizable.strings` | The APNs key names, in addition to `PUSH_*`. |
| `Telegram/Telegram-iOS/zh-Hans.lproj/Localizable.strings` | New. Simplified sentences, for example `MESSAGE_AUDIO` = `%1$@ 发来一条语音消息`. |
| `Telegram/Telegram-iOS/zh-Hant.lproj/Localizable.strings` | New. Traditional sentences. |
| `Telegram/BUILD` | `zh-Hans` leaves `empty_languages`. Both Chinese files are in `AppStringResources`. |

## Monochrome day and night

Stacked on the solid-wallpaper change. Day and dayClassic outgoing bubbles are white (`#FFFFFF`, pressed `#E9E9EB`) with black text. Night accent is white and outgoing bubbles are `#2C2C2E`. Links, checks, switches, and unread badges follow black in day and white at night. The accent picker, tinted night theme, and theme editor are not offered. The send control draws an up arrow in the button’s foreground color and does not use the paper-plane imageset.

`NSLocationAlwaysAndWhenInUseUsageDescription` in `en.lproj` is English. `zh-Hant.lproj/InfoPlist.strings` is Traditional Chinese for every `zh-Hans` key. The localization is the real `Localizable.strings` from the push-string change, not an empty generated file.

| File | Change |
| --- | --- |
| `DefaultDayPresentationTheme.swift` | White outgoing bubbles, black links and checks, black switch, black start button, gray passcode. |
| `DefaultDarkPresentationTheme.swift` | White accent, `#2C2C2E` outgoing bubbles. |
| `DefaultDarkTintedPresentationTheme.swift` | Accent white. The theme is not in the picker. |
| `PresentationResourcesChat.swift` | Send glyph is the existing up-arrow path. |
| Theme settings | Day and night only. No accent row, no tinted theme. |
| `en.lproj/InfoPlist.strings` | `NSLocationAlwaysAndWhenInUseUsageDescription` is English. |
| `zh-Hant.lproj/InfoPlist.strings` | Traditional Chinese for every `zh-Hans` permission key. Bundled by the InfoPlist glob. |

## Hidden Telegram features

Teamgram does not implement Premium, Stars, gifts, TON, Fragment, channel ads, Business, Boosts, Passport, AI compose, translation/Cocoon, or AI summary. Those entry points stay hidden unless `help.getAppConfig` turns them on. Stories stay. A missing key is off. `premium_purchase_blocked` and `stars_purchase_blocked` keep their official names and default to blocked. The other switches are `tellomi_*_enabled`.

| File | Change |
| --- | --- |
| `submodules/TelegramCore/Sources/TellomiFeatureGate.swift` | The one reader. `aiComposeEnabled` also keeps the secret-chat ban and the `ios_disable_ai_*` kill switch. |
| `submodules/AccountContext/Sources/Premium.swift` | Premium and Stars follow that reader. Gift flags stay off unless `tellomi_gifts_enabled` is true and `stargifts_blocked` is false. The built-in default treats Premium as blocked. |
| `submodules/WalletContext/Sources/WalletContext.swift` | `wallet_available` is not enough. `tellomi_wallet_enabled` must also be true. |
| Chat composer, attachment panel, legacy input | The four `isAIEnabled = true` sites read `tellomi_ai_compose_enabled`. |
| `TranslateUI` | `canTranslateText` / `canTranslateChats` return false unless `tellomi_translate_enabled`. That drops the translation header, including Cocoon. |
| Settings, profiles, attach menu, chat input, search, deep links | Premium, Stars, gifts, wallet/TON, Business, Passport, Boosts, channel revenue, and AI summary rows and links are omitted. Fragment auction, anonymous-number, and ads top-up URLs are not opened unless `tellomi_fragment_enabled`. |

## Welcome art and empty states

The six-page OpenGL tour still pages with the same scroll. Page 1 draws the Tellomi logo. Pages 2-6 each draw one MingCute mark (location, cellphone, chat-3, pic, lock) at the logo's ink size, sliding with `scroll_offset`. The old per-page Telegram scenes are not drawn.

Empty chat, empty folder, no-results, calls placeholder, two-factor intro, and the phone-entry sticker are one monochrome mark instead of the duck. Other bundled stickers are still the upstream files.

| File | Change |
| --- | --- |
| `submodules/AuthorizationUI/Sources/TellomiIntroCopy.swift` | Dating copy. Traditional is its own set. |
| `Tellomi/Brand/Intro/*.svg` | MingCute sources for the five later pages. |
| `Telegram-iOS/Resources/intro/intro_page_*.png` | Logo plus those five marks. The same files are under `RMIntro`. |
| `animations.c`, `RMIntroViewController.m` | Draw the six marks and slide them with the page. |
| `ChatListEmpty.tgs`, `ChatListFilterEmpty.tgs`, `ChatListNoResults.tgs`, `CallsPlaceholder.tgs`, `TwoFactorSetupIntro.tgs`, `IntroPhone.tgs` | Monochrome mark. |
| `Telegram/Telegram-iOS/*.alticon` | Deleted. Not packaged. |

## Transcription letter

The voice-transcription button draws a stroked A that trims into the collapse chevron. When the app language (`primaryComponent.languageCode`, not `baseLanguageCode`) is zh, ja, ko, ar, fa, he, hi, or th, that letter is 文, あ, 가, ع, ا, א, अ, or ก. Latin, Cyrillic, and Greek stay A. The button is forced left-to-right so an RTL layout does not mirror the glyph. The same centerlines are in `Tellomi/assets/transcribe-glyph-paths.json` (文 is also `transcribe-wen-paths.json`).

| File | Change |
| --- | --- |
| `AudioTranscriptionButtonComponent.swift` | Picks `voiceToText_<lang>` / `textToVoice_<lang>` and `TranscriptionLocked_<lang>`. |
| `voiceToText_*.json`, `textToVoice_*.json` | Same layer and group names and the same trim. The A centerlines are the character. |
| `TranscriptionLocked_*.imageset` | The locked icon's A is the same character. The arrow and the lock stay. |

## Login screens matched to the 2026-11-03 spec

The phone screen is the login home. Primary buttons stay black (white in dark mode), disabled gray. The agreement sentence is only 已阅读并同意 用户协议 和 隐私政策. The carrier sentence is gone. SMS boxes use the length in `sentCode`. The top-right control is still the language name plus ▾ and the three-language card. It is not 帮助.

Apple, Google, 其他登录方式, 找回账号, and 密码登录 have no working sign-in, so those controls are not on the phone or email screens. The phone page keeps the field, 验证并登录, the 或 divider, 邮箱登录, and the agreement at the bottom. The email page is the address field, 验证并登录, and the agreement under the button. Back returns to the phone page. The password screen and the other-methods sheet are not in the login controller.

Phone and email open with no keyboard. A tap on the field opens it; a tap on blank space or the title, or a downward drag, dismisses it. The phone field uses the number pad. The intro fade still runs: Telegram used to release it when the keyboard's input height arrived, and login releases that same fade on the turn after `activateInput` because that call does not focus a field. The screens follow the system appearance (`UIScreen` style, black page and white button in dark mode), including the welcome OpenGL clear color. Switching language rewrites every label, including 或. The SMS code subtitle's accessibility label is the same Chinese line that is drawn. The agreement sentence is a wrapping label measured at the row width minus the checkbox on every layout, including a language change, with that full sentence as its accessibility label, and it sits above the keyboard. A tap on the checkbox or the sentence does not dismiss the keyboard. Agreement links open in an in-app Safari view. 验证并登录 stays under the field through the intro. The country button's accessibility name follows the login language. Server error alerts use the `Login_*` mapping and, when that pack is still English, the bundled Chinese sentence; the alert is `Auth.Login.ErrorAlert`. The 或 divider is an accessibility element.

| File | Change |
| --- | --- |
| `submodules/AuthorizationUI/Sources/TellomiSignUpAgreement.swift` | Carrier sentence removed. |
| `submodules/AuthorizationUI/Sources/TellomiLoginChrome.swift` | SMS error copy. Phone home still pins the agreement. |
| `submodules/AuthorizationUI/Sources/TellomiLoginSurfaces.swift` | Clear button and dark agreement card. Password field and round social buttons removed. |
| `submodules/AuthorizationUI/Sources/AuthorizationSequencePhoneEntryController.swift` | Language button identifier. No unavailable alert and no other-methods sheet. |
| `submodules/AuthorizationUI/Sources/AuthorizationSequencePhoneEntryControllerNode.swift` | Phone home is field, verify, divider, email, agreement. Email is field, verify, agreement. |
| `submodules/AuthorizationUI/Sources/AuthorizationSequenceCodeEntryControllerNode.swift` | SMS error stays until the code changes. Email code has no 收不到验证码? row. |
| `Telegram/Tests/Sources/TellomiLoginUITests.swift` | Phone-default checks. |

## Login transitions, languages, short screens, settings badges

Phone + SMS + two-step verification failing on a first login was not an iOS window race. The server treated an unbound temporary auth key as key 0, so `account.getPassword` returned no `current_algo` and no `srp_B` (tellomi/teamgram-server#119). This client does not invent those fields or skip the check. `verifyPassword` still fails with `INTERNAL_NO_PASSWORD` when the derivation or the SRP session is missing. The only added tolerance is the one Android uses: `srp_id` is single-use, so `SRP_ID_INVALID` fetches `account.getPassword` once more and retries `auth.checkPassword` a single time. A second `SRP_ID_INVALID` is returned to the caller.

Welcome → login keeps Telegram's snapshot fade. The login form (verify, divider, email, agreement) was left at alpha 1, so the headline drew on top of it. Those nodes now fade in with the rest, the snapshots sit above the form, and the live intro pages are hidden once the snapshots exist. The intro spring damping was 1.2, which UIKit drops; it is 0.9. Phones taller than the Plus sizes no longer use the Inch55 headline position.

Phone ↔ email slides horizontally (0.35s ease-in-out), the same direction as a navigation push. Code, password, and sign-up still use `AuthorizationSequenceController.setViewControllers`, which already asks the navigation container for a slide.

The language control is a template globe with the current language as its accessibility label. The card lists every bundled `*.lproj` (zh-hans, zh-hant, en, plus the empty stubs ar, be, ca, de, es, fa, fr, id, it, ko, ms, nl, pl, pt, ru, tr, uk, uz) and scrolls when the list is taller than the screen. The agreement sentence follows that code, including Simplified and Traditional. Links stay `https://tellomi.cn/legal/terms/` and `https://tellomi.cn/legal/privacy/`. Link color is black on a light page and white on a dark page, not blue.

The “code sent” toast sits above the title, under the status bar. If that gap is shorter than the toast, it is not shown; the subtitle already names the address. The two-step screen title, notice, and forgot label come from the login copy (两步验证 / 兩步驟驗證 / Two-step verification), not the English pack.

The phone home, the code page, the password page, and sign-up each put the column in a scroll view whose bottom inset is the keyboard (or the home indicator). Text uses `UIFontMetrics` capped at 1.35× so a wrapped agreement or title can scroll clear on a 4-inch phone. Titles and help lines are not limited to one line. The password and sign-up buttons stay at the bottom when the column fits, and follow the fields when it does not. iPhone login stays portrait-locked, the same as Telegram (`compactSize: .portrait`). Code digit boxes stay a fixed size.

The home-screen icon and the alternate icons are unchanged. Settings row badges that use the shared circle colors in `PresentationResourcesSettings` are black, white, and gray. Rows that pass their own colors (business, reactions, tips, and the Premium, Stars, and gift artwork) are unchanged.

| File | Change |
| --- | --- |
| `submodules/TelegramCore/Sources/Account/Account.swift` | One `SRP_ID_INVALID` refetch. Missing `current_algo` still fails. |
| `submodules/RMIntro/Sources/platform/ios/RMIntroViewController.m` | Damping, tall-phone layout, hide live pages. |
| `submodules/AuthorizationUI/Sources/AuthorizationSequencePhoneEntryControllerNode.swift` | Intro fade covers the whole form. Phone ↔ email slide. Form scroll. |
| `submodules/AuthorizationUI/Sources/TellomiLoginLocale.swift` | All bundled languages. |
| `submodules/AuthorizationUI/Sources/TellomiSignUpAgreement.swift` | Agreement copy for each bundled language. Scaled body. |
| `submodules/AuthorizationUI/Sources/TellomiChoicePrompt.swift` | Scroll when the card is taller than the screen. |
| `submodules/AuthorizationUI/Sources/AuthorizationSequenceCodeEntryControllerNode.swift` | Toast above the title. Column scrolls above the keyboard. |
| `submodules/AuthorizationUI/Sources/AuthorizationSequencePasswordEntryControllerNode.swift` | Wrapping copy. Button stays above the keyboard or scrolls with the column. |
| `submodules/AuthorizationUI/Sources/AuthorizationSequenceSignUpControllerNode.swift` | Same short-screen rule. Continue stays on a 320-pt width. |
| `submodules/AuthorizationUI/Sources/TellomiLoginChrome.swift` | Capped Dynamic Type font. Shared form scroll. |
| `submodules/TelegramPresentationData/Sources/Resources/PresentationResourcesSettings.swift` | Gray settings badges. |

## Login language card, country list, agreement contrast

The language card keeps its centered shape. On a notch or Dynamic Island the top stays below the status bar (`statusBarHeight` / safe area, at least the old 24pt margin). SE and iPad, where 24pt already clears the status bar, stay centered.

The login country list takes `AuthorizationCountryListLocalization`: names from `Locale(identifier:).localizedString(forRegionCode:)`, sort and section index in that locale, title and search placeholder from the login language. The section index uses the primary text color. The search field is not focused until it is tapped. Other country lists keep the previous strings, accent index, and automatic focus.

Agreement links are semibold and underlined. The confirm card uses the dark theme when the page is dark, so the links are white on the dark card and black on a light card. The email agreement sentence is left-aligned against the checkbox, and the email title and notice are centered like the phone page.

## Empty country list, notification language, private-chat titles

`help.getCountriesList` has returned zero countries. `loadServerCountryCodes` and `setupCountryCodes` used that array in place of the bundled `PhoneCountries` list, so the picker and the prefix lookup were empty. An empty result (including a parse that yields nothing) is ignored. `AccountContext` does not publish an empty configuration over the bundled one either. A later non-empty response still replaces the list.

Chinese country names are grouped by pinyin initial (A–Z), the same shape as the system Contacts index. Other languages still use the first character of the localized name.

The notification extension's `standaloneStateManager` read the shared account manager and then passed `nil` for the language pack, so `initializedNetwork` sent `lang_code` `"en"` and the server stored that over the account's language (teamgram-server#122 is the server half). It now passes `SharedDataKeys.localizationSettings`, the same record the app writes from Settings and from the login language button. `Network.swift` is unchanged: a missing pack still falls back to `"en"`.

A private or secret chat notification no longer appends `→ <this account>`. Official Telegram does not. Groups and channels still do when more than one account is signed in. A one-to-one call does not; a group call still does. The peer id on that helper is `EnginePeer.Id` (a `PeerId` typealias). The file does not import Postbox.

The bundled list has both `1;US` and `1;CA`. The prefix map kept the last writer, so a pasted +1 number resolved to Canada. A calling code with no longer prefix keeps the United States when that row is present. Other shared codes (7, 599) stay last-writer.

## Send mark, folder names, icon size

The media-preview send control used `Media Editor/Send` (`attachlogo.pdf`), the Telegram paper plane, on a `#0088ff` disc. That file, `Chat/Input/Text/SendIcon`, and `IconForwardSend` are now an up arrow. The send disc is `#111111` with a white arrow. The chat composer's generated arrow is unchanged. Launcher icons and the QR mark are unchanged.

The media-preview back control used `Navigation/Back`, whose glyph is about 8pt inside a 30pt box, so it looked lost in the 44pt circle. It now uses `Media Editor/Back` (a chevron that fills a 28pt box) at 1.35×. Attachment-tray tab icons in the glass bar are 36pt instead of 30pt. Media-editor tool icons cap at 32pt instead of 28pt.

Suggested folders arrive from `messages.getSuggestedDialogFilters` with English titles. On a Chinese interface, Unread / Personal / Groups / Channels / Bots and their descriptions are shown in Chinese. A few folder and People Nearby keys that the Chinese pack omits are filled locally and do not replace a translation the pack already has.

## Channel intro placeholder

`Telegram/Telegram-iOS/Resources/Channel.tgs` is the 「频道是什么？」illustration (`PermissionController` icon `.animation("Channel")`). The original is a gzip Lottie with the duck sticker and the blue “Channel / 55k members” bubble. It is now a one-frame black-and-white phone and three bars. No duck, no blue.

The same one-frame shape style (gzip Lottie, or plain JSON where the file was already `.json`) replaces these, without a code change. Each drawing is only rectangles and ellipses in black, white, and gray:

| File | Mark |
| --- | --- |
| `Telegram/Telegram-iOS/Resources/BroadcastGroup.tgs` | Megaphone. |
| `submodules/TelegramUI/Resources/Animations/DiscussionGroupSetup.tgs` | Two speech bubbles. |
| `submodules/TelegramUI/Resources/Animations/ChannelMessages.tgs` | Three text bars. |
| `…/ChatListFolders.tgs` | Folder. |
| `…/ChatListNewFolder.tgs` | Folder with a plus. |
| `…/ChatListCloudFolderLink.tgs` | Folder with two rings. |
| `…/ChatListFoldersTooltip.json` | Folder. Left as JSON; the tooltip loader asks for that extension. |
| `Telegram/Telegram-iOS/Resources/PlaneLogo.tgs`, `PlaneLogoPlain.tgs` | Up arrow. |
| `submodules/PasswordSetupUI/Resources/TwoFactorSetupMonkeyIdle.tgs`, `…Idle1.tgs` | Closed lock, and a lock with the shackle raised. |
| `…MonkeyIdle2.tgs`, `…MonkeyCloseAndPeek.tgs` | Key. |
| `…MonkeyTracking.tgs`, `…MonkeyClose.tgs` | Closed lock. |

The two-step monkey player still asks for frames up to 41, and the round-video atlas still asks `PlaneLogoPlain` for 53 frames. A one-frame file has no later frames. The atlas path is already switched off (`RoundVideoDecorationProvider.isEnabled` is false) and returns nil when the frame count is short, so it does not draw the old plane. The other intro `.tgs` files are unchanged.

## Auth layout back to upstream, precise location, leftover planes

The nickname screen and the two-step screen again use Telegram's authorization layout: `layout.inputHeight` is the keyboard, the continue button is pinned to `height - inputHeight - button - 24`, and the column is measured in the band above that inset (`additionalBottomInset` 90 / 110). The custom form scroll and the slack test that moved the button under the keyboard are gone. Copy, the black button, the agreement checkbox, and email nickname-only stay. The two-step monkey sticker stays hidden; it is not part of the inset math. The signup avatar tap is the same `presentLegacyAvatarPicker(signup: true)` as upstream (`TGMediaAvatarMenuMixin`: camera tile, recent photos, 打开相册, crop). It was not a separate picker.

Phone, email, and code screens still differ from upstream. Those differences are listed in the pull request. A cleared unauthorized state no longer replaces the code screen with the welcome carousel while that login attempt is still current.

Gallery and Location in the attach tray were given the same 30×30 canvas as File and Poll, because fitting them into the old ink box drew them smaller. That canvas is removed by the icon-size fix below. File and Poll still use the 30×30 canvas: they had no upstream icon.

`DeviceLocationManager` asks for `kCLLocationAccuracyBest` and `requestTemporaryFullAccuracyAuthorization(withPurposeKey: "PreciseLocation")`. `DeviceAccess.authorizeAccess` asks through `LocationManager.requestPreciseLocationIfReduced()` (the helper is on that wrapper, not on `CLLocationManager`). `Info.plist` / `InfoBazel.plist` carry `NSLocationTemporaryUsageDescriptionDictionary`. The current-location row sends `accuracy_radius` from `CLLocation.horizontalAccuracy`. Apple Maps is still given WGS-84; MapKit applies the China offset. 高德 uses `dev=1`, 百度 `coord_type=wgs84`, 腾讯 is converted to GCJ-02 in `TellomiMapOpenIn`.

Paper-plane artwork replaced with `Avatar/TellomiMark`: the unsupported-message badge, Call title, CallKit, the context-menu Telegram icon, the Shortcuts icon, and Wallet InfoSend. QR marks were already the Tellomi mark. `PlaneLogo.tgs` is already an arrow. The welcome intro mesh (`RMIntro`, `telegram_plane1.png`) is still a paper-plane model.

## Location picker locale and nearby places

Tellomi langpacks set `base_lang_code` to `en`, so `PresentationStrings.baseLanguageCode` is the English fallback even when the UI language is Chinese. `localeWithStrings` used that code for `CLGeocoder` and `MKDistanceFormatter`, which produced pinyin addresses and `miles` / `feet`. Nearby places and venue search call the inline venue bot (`venue_search_username`, default `foursquare`). This server does not have that bot, so the list was empty (`Map_NoPlacesNearby`) and search showed only the geocoded address.

| File | Change |
| --- | --- |
| `submodules/TelegramStringFormatting/Sources/Locale.swift` `localeIdentifierLanguageCode` | When the base code is English and the primary (UI) code is not, the locale uses the primary code. An English UI keeps the base code. A pack whose base is already not English keeps that base, which is what upstream official packs do. The device region suffix is unchanged, so a US region still measures in miles and feet, with Chinese unit names. |
| `submodules/LocationUI/Sources/LocationUtils.swift` `nearbyVenues` | The bot result is still used when it contains venues. Otherwise the same signal is filled from MapKit. The `accuracyRadius` argument on `TelegramMediaMap.init(coordinate:)` stays; that is the precise-location row, not the venue fallback. |
| `submodules/LocationUI/Sources/AppleMapVenueSearch.swift` | Nearby: `MKLocalPointsOfInterestRequest` (2.5 km). If that is empty, one `MKLocalSearch` whose query follows the UI language (`餐饮` / `餐飲` / `restaurant`). Text search: `MKLocalSearch` within 100 km of the coordinate. Each hit is a `TelegramMediaMap` venue (`provider` `apple`, foursquare-style `type` so the existing category color and icon path run). No attribution row, no API key. Sending still posts that media; `queryId` is not a bot result. |

## Language pack download

The login language button used to call `tellomiStoreInterfaceLanguage`, which wrote `localizationSettings` with an empty pack at version 0 and no English base. `tellomiLoginCopy` only has 简体, 繁體, and English, so every other language left the phone, code, and sign-up labels in that English copy. The agreement sentence has its own table, which is why that line was the only one that changed. Missing keys fall back to bundled `en.lproj`.

The button now uses the same call as upstream's splash "Continue in …": `TelegramEngineUnauthorized.localization.downloadAndApplyLocalization`. That is `langpack.getLanguage` plus `langpack.getLangPack` for the language and its `base_lang_code`. The `lang_pack` argument stays `""`; the session fills it from `initConnection` (`languagesCategory` `"ios"`). The preference key is written only after that download succeeds, so a failed request does not replace a pack that is already stored. A pack already saved with no strings (the old button) is downloaded again when the phone screen opens.

For a language other than 简体, 繁體, and English, login labels that exist in the pack (`Login.PhoneTitle`, `Login.Continue`, `Login.Code`, `LoginPassword.*`, `Login.Info*`, and the same family) are read from the downloaded strings. Tellomi-only lines (email login, bind phone) stay the English product copy. 简体 and 繁體 keep the bundled product copy. The welcome carousel stays that product copy too: the six pages are not langpack keys, and the pack's `Tour.*` strings are the Telegram tour.

Settings ▸ Language already calls `downloadAndApplyLocalization` on the signed-in engine (`LocalizationListControllerNode`, and the same call from Settings search) and then writes the preference key. It does not write an empty pack.

The `ios` packs on the server are full for the languages this picker lists (on the order of 12k strings). `hi`, `th`, and `el` are near-empty in the official iOS export and are hidden on the server; the client does not special-case them.

| File | Change |
| --- | --- |
| `submodules/AuthorizationUI/Sources/TellomiLoginLocale.swift` | Download and apply through `downloadAndApplyLocalization`. Notes the applied pack for the login labels. |
| `submodules/AuthorizationUI/Sources/TellomiLoginChrome.swift` | Non-Chinese, non-English login labels come from that pack. |
| `submodules/AuthorizationUI/Sources/AuthorizationSequencePhoneEntryController.swift` | The language row downloads before the labels change. |
| `submodules/AuthorizationUI/Sources/AuthorizationSequenceCodeEntryController.swift` | Same, using the unauthorized account from the login flow. |
| `submodules/AuthorizationUI/Sources/AuthorizationSequencePhoneEntryControllerNode.swift`, `AuthorizationSequenceCodeEntryControllerNode.swift` | Replace the strings and lay out again. |
| `submodules/AuthorizationUI/Sources/AuthorizationSequenceController.swift` | Passes the unauthorized account. A strings-only presentation update reaches the phone and code screens. |
| `submodules/TelegramCore/Sources/TellomiInterfaceLanguage.swift` | The empty-pack helper is not how a language is applied. |

## Country picker open

Tapping the country code on the phone login screen built the whole list on the main thread before the controller could appear. For a Chinese locale that includes a `CFStringTransform` to pinyin on every name, so the section index is A–Z instead of one dot per character. Upstream sorts with `localizedString` only and opens immediately. The tap does not call `help.getCountriesList`; that request already runs when the phone screen loads.

The list is built on a background queue and cached. The phone screen starts that build when it appears, and again when the server country list replaces the bundled one. The tap reads the cache. If the cache is not ready yet, the controller still pushes immediately and fills the table when the build finishes.

| File | Change |
| --- | --- |
| `submodules/CountrySelectionUI/Sources/TellomiCountryListPreparation.swift` | New. Background build and cache. Same pinyin index and the same sort as the controller had. |
| `submodules/CountrySelectionUI/Sources/AuthorizationSequenceCountrySelectionControllerNode.swift` | Init uses the cache. A miss does not sort on the main thread. |
| `submodules/AuthorizationUI/Sources/AuthorizationSequencePhoneEntryController.swift` | Starts the build when the phone screen loads, and again after `help.getCountriesList`. `tellomiWarmCountryList` is public so that module can call it. |

## Bottom navigation (M2)

Fresh install shows Discover, Chats, and Settings (D-5). Calls and Contacts start hidden. Chats and Settings cannot be hidden (D-7). The app opens on Chats (D-8). There is no migration. `ios_killswitch_disable_tellomi_tabs` = `1` puts the upstream tab order back. The Calls nil-default below is not behind that switch: a missing `CallListSettings` hides Calls either way. `getContactsController` only returns a controller that already exists; it does not push. `openContacts` pushes a contacts page when that tab is hidden. A `tell.cc/m#<id>` link is handled only while the Tellomi bar is on. The kill switch returns it to the normal opener. A tap in a chat resolves that address before the external opener: the path `/m` is the username `m`, so Discover stayed hidden and the post never opened (D-57). `resolveUrlImpl` now returns that address as an external URL when the bar is on, before autologin can rewrite the fragment, and the existing opener turns Discover back on and opens the post. If the feed screen is not in a navigation stack yet (the chat is still closing), the post stays pending and is presented again for about a second.

The Calls tab already hides from a long-press on its icon (`CallListController.tabBarItemContextAction`, `Calls_HideCallsTab`). The calls list opened from Settings still has the Show Calls Tab switch (`showSettings` on `.navigation`). Both write `CallListSettings`. New Message uses `ContactSelectionController`, not the Contacts tab, so hiding Contacts leaves that list in place.

| File | Change |
| --- | --- |
| `submodules/TelegramUIPreferences/Sources/CallListSettings.swift` | `showTab` is false when `_showTab` is nil (one line). An explicit true or false is unchanged. |
| `submodules/TelegramUIPreferences/Sources/PostboxKeys.swift` | `ApplicationSpecificSharedDataKeyValues.tellomiTabSettings = 100`, stored with `applicationSpecificSharedDataKey` (the stored id is 1100). Upstream's highest shared-data id here is 22. |
| `submodules/TelegramUIPreferences/Sources/TellomiTabSettings.swift` | New. `showFeedTab` defaults true, `showContactsTab` defaults false. Tab order and the kill switch. |
| `submodules/TelegramUIPreferences/Sources/TellomiTabNavigationDecisions.swift` | New. Tab copy, the `tell.cc/m#` post id, and the two rules the root controller calls. A post link is not consumed when the kill switch is on. The contacts getter never pushes. `tellomiFeedPostLinkEscapesPeerResolution` is the chat-tap rule: that address must not become the user `m`. |
| `submodules/TelegramUIPreferences/Tests/TellomiTabNavigationDecisionsTests.swift` | Host tests for that copy, the post-link kill switch, the contacts lookup, and the chat-tap rule. |
| `submodules/UrlHandling/Sources/UrlHandling.swift` | `resolveUrlImpl` returns a post link as an external URL when the bar is on, before autologin. The external opener already reopens Discover (D-57). `/m/<slug>` is unchanged. |
| `submodules/TelegramUI/Sources/AppDelegate.swift` | The existing calls-settings transaction also calls `tellomiCaptureLaunchTabs` (one line) so the first tab bar matches the saved record. |
| `submodules/TelegramUI/Sources/ApplicationContext.swift` | `tellomiStartTabObservation` / `tellomiStopTabObservation`, same shape as the calls-tab subscription at the lines above it. |
| `submodules/TelegramUI/Sources/TelegramRootController.swift` | `addRootControllers` and `updateRootControllers` call `tellomiAppendRootTabs`. When that returns false the original appends run. `getContactsController` looks up a contacts page and does not push. `openContacts` pushes one when the tab is hidden. |
| `submodules/TelegramUI/Sources/OpenUrl.swift` | `continueHandling` returns early on `tell.cc/m#<id>` (`tellomiHandleFeedPostLink`). The kill switch makes that function return false, so the link is not swallowed. A `/m/<slug>` path is still a message link. |
| `submodules/TelegramUI/Sources/TellomiBottomNavigation.swift` | New. Order, observation, the hidden-contacts push from `openContacts`, and re-enabling Discover for a post link (D-57). The observation compares `TellomiTabSettings`. A `(Bool, Bool)` does not satisfy `Equatable`, so `distinctUntilChanged` does not accept it. |
| `submodules/ContactListUI/Sources/ContactsController.swift` | One call, `tellomiAppendHideContactsTabItem`, on the existing tab-icon long-press. |
| `submodules/ContactListUI/Sources/TellomiContactsTabMenu.swift` | New. Hide Contacts, same menu as Hide Calls. |
| `submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoSettingsItems.swift` | One call, `tellomiAppendNavigationSettingsEntry`, after Language. |
| `submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/TellomiNavigationSettingsEntry.swift` | New. Settings row that pushes the navigation page. |
| `submodules/SettingsUI/Sources/TellomiNavigationSettingsController.swift` | New. Discover, Calls, and Contacts switches. Chats and Settings are on and disabled (D-7). Calls uses `CallListSettings`, so the old Show Calls Tab switch still works. |
| `submodules/TelegramUI/Components/Tellomi/FeedScreen/` | New module `TellomiFeedScreen`. Empty Discover tab (D-37). Not `NewsScreen`. Long-press hides it (D-38). `TellomiFeedScreenNode` imports `TelegramUIPreferences` so it can read `TellomiTabCopy`. Opening a post from a link retries for about a second when the screen is not in a navigation stack yet. |
| `submodules/TelegramUI/BUILD` | Depends on that module. |

## DC addresses from help.getConfig (M7 / D-33)

`Tellomi/tellomi-server.json` is a seed, not a lock. `setSeedAddressSetForDatacenterWithId` writes memory only. The keychain list wins when it is non-empty, and nothing copies the seed back over it. There is no `TELLOMI_LOCK_DC_ADDRESSES` flag. Android #52 turned that flag off and then refused any `dc_options` entry `inet_pton` rejects. iOS already applied `dc_options`, including hostnames. A hostname in the server config would have replaced a saved IP. Both writers now use the Android rule: port 1–65535, and `inet_pton` of the family selected by the IPv6 flag. An empty result does not call `updateAddressSetForDatacenter`, so the seed or the last saved list stays. Login and the session are unchanged. `UnauthorizedAccount` still does not poll `help.getConfig`; the signed-in `Account` does, on launch and then hourly. The seed hostname `api.tellomi.cn` is still dialed with `getaddrinfo` when no persistent list exists. It is not written by this filter.

| File | Change |
| --- | --- |
| `submodules/TelegramCore/Sources/Network/TellomiDcAddress.swift` | New. `tellomiAcceptDcAddress` and `tellomiAcceptedDatacenterAddresses`. |
| `submodules/TelegramCore/Sources/Network/TellomiDcOptionInputs.swift` | New. Reads `Api.DcOption` into that filter. |
| `submodules/TelegramCore/Sources/State/ManagedConfigurationUpdates.swift` | The signed-in `help.getConfig` path writes only the addresses the filter keeps. |
| `submodules/TelegramCore/Sources/State/Serialization.swift` | `requestDatacenterAddress` (datacenter discovery) uses the same filter. |
| `submodules/TelegramCore/Tests/TellomiDcAddressTests.swift` | The literals from Android `check_dc_address.cpp`, plus empty, hostname-only, mixed, and duplicate cases. |

## Discover feed (M3 / C-M3a)

The Discover tab stays on the M2 empty state until app config `tellomi_discover_feed_enabled` is true. A missing key is off. Logged-out sessions do not call `discover.getEngineCredential` and do not call content-engine. The credential is `discover.getEngineCredential#a80a7f76` (teamgram #152), not Signal-Server. Neither call is in the generated Telegram schema; `TelegramApi` boxes the constructor, and `TelegramCore` sends it on the logged-in account. Feed routes follow content-engine's client API: `GET /v1/capabilities` (no credential), `GET /v1/feed/status`, `GET /v1/feed/config`, `GET /v1/feed/recommend` and `/following` (ids only), then `POST /v1/feed/cards`. A text post is `POST /v1/feed/posts` with `kind`, `text`, `visibility` (`public`, `contacts`, or `close_friends`), and `client_nonce`. `include` and `exclude` call `discover.getAudienceToken#dc5213c2` (`kind` plus `user_ids`, 1–500, not the caller) and put the returned JWT in `audience.audience_token`. The token lasts 10 minutes; the client fetches another before `expires`. `DISCOVER_DISABLED`, `AUDIENCE_INVALID`, `USER_ID_INVALID`, and `USER_IS_BLOCKED` stay on the client. The home bar is always 推荐 / 关注 / 同城, including when `GET /v1/feed/config` omits `nearby` (see Discover nearby tab). `GET /v1/feed/nearby?city=<code>&cursor=` loads it, ten posts a page, newest first; the card body still comes from `POST /v1/feed/cards`. Unknown tab names are ignored.

Visibility is Stories' `EngineStoryPrivacy` and `ShareWithPeersScreen` (editing, so the story screenshot / pin rows stay hidden). Everyone, contacts, and close friends post without an audience token. Close friends still go through `contacts.editCloseFriends`. Selected people (`include`) and exclusion lists (`exclude`) call `discover.getAudienceToken` with the cloud-user id, then post that JWT unchanged. A list that is empty, longer than 500, contains the caller, a duplicate, or a non-user is not sent. A post may include `city`, a `<country>:<slug>` code such as `cn:chengdu`. It is omitted when the user has not chosen one, and it is not edited after send. A bad code is `400 invalid_city` and is not sent. Hong Kong, Macau, and Taiwan use the `cn:` prefix (`cn:hong-kong`, `cn:macau`, `cn:taipei`). The code comes from `CLPlacemark.locality` or the manual city list. Location permission is requested the first time the nearby tab is opened, with When In Use and kilometer accuracy, because `DeviceLocationManager` asks for Always and full accuracy. A denial stays on the list. Street, state, latitude, and longitude are not query parameters.

The bottom bar is on master (Telegram-iOS #60).

| File | Change |
| --- | --- |
| `submodules/TellomiDiscover/` | New. Flag, credential bytes, feed and post URLs, city and Stories visibility mapping, JSON parse, loader. Host tests in `TellomiDiscoverTests`. |
| `submodules/TelegramApi/Sources/TellomiDiscoverCredentialRPC.swift` | New. Builds `discover.getEngineCredential` and the boxed `discover.getAudienceToken` query. The schema file is unchanged. |
| `submodules/TelegramCore/Sources/Tellomi/TellomiDiscoverCredential.swift` | New. Sends both on `Account.network`. Audience errors map to `DISCOVER_DISABLED`, `AUDIENCE_INVALID`, `USER_ID_INVALID`, and `USER_IS_BLOCKED`. |
| `submodules/TelegramCore/BUILD` | Depends on `TellomiDiscover`. |
| `submodules/TelegramUI/Components/Tellomi/FeedScreen/` | Recommend, Following, and Nearby, post detail, text compose, and the Stories privacy screen. The M2 empty state remains when the flag is off. |
| `submodules/TelegramUI/Components/Tellomi/FeedScreen/BUILD` | Depends on `TellomiDiscover`, `Geocoding`, and `ShareWithPeersScreen`. Cloud user ids go through `EnginePeer.Id.tellomiCloudUserId`. |

## Public username minimum length

Teamgram #182 accepts a public username of 4 characters. Upstream iOS already rejected a name shorter than 4 in `_internal_checkAddressNameFormat` (2022-11-08, both the final length check and a name that ends in `_`). The bundled English strings, and the Create Bot field's own minimum, still said 5. Settings ▸ Username, a channel public link, and a group public link all call `validateAddressNameInteractive`, which uses that one check. A sticker-set short name uses it too. A theme link stays 5–64; that gate is `EditThemeController`'s own `slug.count < 5` and is not this rule. Login and the session are unchanged. `zh-Hans` and `zh-Hant` do not ship these keys; a downloaded language pack can still say 5 until that pack is updated.

| File | Change |
| --- | --- |
| `submodules/TelegramCore/Sources/TelegramEngine/Peers/AddressNames.swift` | `addressNameMinimumLength` is 4. Both comparisons use it. |
| `Telegram/Telegram-iOS/en.lproj/Localizable.strings` | Username, channel, group, and Create Bot copy that said 5 characters now says 4. Both copies of `Group.Username.InvalidTooShort` are updated. |
| `submodules/TelegramUI/Components/CreateBotScreen/Sources/CreateBotUsername.swift` | `minLength` is 4, the same minimum, counted on the full username including the `bot` suffix. |
| `submodules/TelegramCore/Tests/AddressNameFormatTests.swift` | 4 characters pass. 3 characters, including one that ends in `_`, are `.tooShort`. |
| `submodules/TelegramUI/Components/CreateBotScreen/Tests/CreateBotUsernameTests.swift` | `abot` (4) passes. `bot` (3) does not. |

## Chat wallpaper and accent colors

`account.getWallPapers` stays empty. Wallpapers are bundled. The default chat background is a pattern on a gradient: light `tm_doodle_light` is `#EFE7DD` with the doodle at 12% (dark strokes); dark `tm_doodle_dark` is `#0B141A` → `#16232B` with the doodle at 8% (light strokes, negative intensity). The wallpaper grid injects the 10 built-in entries when the server list is empty. The color grid keeps one solid, `#F0F2F5` in light and `#101418` in dark. A wallpaper stored in `themeSpecificChatWallpapers` is a choice and is left as stored, including pure black and the previous solids `#F2F2F2` and `#000000`: those values cannot be told apart from a color the user picked. Only an account with no saved wallpaper for that theme, or the historical `.builtin` token (the built-in default, not a chosen color), reads the new doodle. Night mode does not swap a saved wallpaper for the night doodle. Incoming bubbles are `#FFFFFF` / `#202C33`. The bubble shadow is the same 0.5 pt spec on every wallpaper, not only a solid color: merged bubbles stay 0 pt apart, and the outline plus that shadow are what separates them. Stroke colors are the ones the theme already had. Date and service capsules use the custom-wallpaper fill; `tm_` patterns ask for blur even when the intensity is negative. The accent swatches are the 12 hex values, default `#3390EC`. A builtin theme with no saved accent uses that blue. Pattern tiles are Lucide (ISC), Tabler Icons (MIT), and Hero Patterns (CC BY 4.0, Steve Schoger). Settings ▸ Open Source Licenses names them. Login and the session are unchanged.

| File | Change |
| --- | --- |
| `submodules/TellomiWallpapers/` | Color table, wallpaper catalog, bubble colors, shadow spec, license text. Host tests in `TellomiWallpapersTests`. |
| `Tellomi/Wallpapers/` | `WallpaperCatalog.json`, the SVG tiles, `generate_patterns.py`, `LICENSES.md`, `test_catalog.py`. |
| `submodules/TelegramUI/Resources/tm_{doodle,dots,waves}.tgv` | Gzipped SVG the pattern renderer already accepts. |
| `submodules/TelegramPresentationData/Sources/DefaultDayPresentationTheme.swift` | `tellomiDefaultWallpaper`, stock list, solid presets, bubble shadow. `.builtin` still becomes the doodle. A saved color does not. Day classic's suggested wallpaper is the light doodle. |
| `submodules/TelegramPresentationData/Sources/DefaultDarkPresentationTheme.swift`, `DefaultDarkTintedPresentationTheme.swift` | Default wallpaper is the dark doodle. Dark incoming fill is `#202C33`. |
| `submodules/TelegramPresentationData/Sources/PresentationData.swift` | The doodle is used when that theme has no saved wallpaper. A saved wallpaper, including black, stays, including when night mode turns on. |
| `submodules/TelegramPresentationData/Sources/MakePresentationTheme.swift` | A builtin theme with no accent uses `#3390EC`. |
| `submodules/TelegramUI/Components/Settings/WallpaperGridScreen/` | Empty server list gets the 10 built-ins. Color presets are the one solid. |
| `submodules/TelegramUI/Components/TelegramAccountAuxiliaryMethods/` | `tm_doodle`, `tm_dots`, and `tm_waves` are read from the app bundle. |
| `submodules/SettingsUI/Sources/Themes/ThemeColorPresets.swift`, `ThemePickerController.swift` | The accent row is the 12 colors. |
| `submodules/SettingsUI/Sources/TellomiOpenSourceLicensesController.swift` | The license page. |
| `submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/` | Settings row that opens it. |
| `submodules/TelegramUI/Components/Chat/ChatMessageBubbleItemNode/` | Draws the bubble shadow whenever the chat has a wallpaper. |
| `submodules/TellomiWallpapers/` `TellomiReactionCapsules` | Reaction capsule backgrounds. Day Classic outgoing is green `#3FC33B` (12% / solid). Day outgoing is white (12% / solid). Night incoming is white at 7%, night outgoing is white at 10% (12% once an accent is applied) and solid white when selected. The tinted theme's selected incoming capsule follows the accent. The accent itself stays `#3390EC`. |

## Icon ink size

`Tellomi/Icons/generate_icons.py` used to place MingCute's whole 24×24 viewBox inside the original ink box, using the shorter side of that box. The viewBox already has padding, so the glyph was shrunk twice. Of the icons that had an upstream PDF, 69 measured under 0.8 of the old long side (pin 0.57, back 0.44).

The generator now crops each MingCute path to its own ink, scales it uniformly so the long side equals the upstream long side, and centers it on the upstream ink. MingCute outlines are filled paths, so that scale is also the stroke compensation: the outline weight changes with the glyph. `upstream_ink.json` holds the pre-replacement boxes (commit `599d6869aa^`), which is what a later run reads. `Chat/Input/Text/SendIcon` stays the up arrow from the send-mark change and is not in the mapping, so a regenerate does not draw the paper plane again. `IconForwardSend` is the right-pointing forward arrow; see "Icon meaning" below. Login screens are unchanged.

`Tellomi/Icons/check_sizes.py` fails when a replaced icon's long ink side is under 0.9 of that upstream box. `Make.py build` and `Make.py test` run it. An explicit `WxH` canvas with no upstream icon is not compared.

| File | Change |
| --- | --- |
| `Tellomi/Icons/generate_icons.py` | Fit the MingCute ink to the upstream ink. |
| `Tellomi/Icons/upstream_ink.json` | Page size and ink box from before the replacement. |
| `Tellomi/Icons/pdf_ink.py`, `check_sizes.py` | Path ink, and the 0.9 check. |
| `Tellomi/Icons/mapping.csv` | Gallery and Location use the upstream ink again. `SendIcon` is not generated. |
| `build-system/Make/IconSizeCheck.py`, `Make.py` | The check runs with the Postbox import check. |
| `submodules/TelegramUI/Images.xcassets` | The regenerated imagesets. |

## Icon meaning

The MingCute swap kept the old ink box and changed the drawing. These rows pointed at a glyph with a different meaning. Each one is either another MingCute file, a MingCute drawing with a slash, a lock, or letters added under `Tellomi/Icons/semantic/`, or the upstream PDF put back. `generate_icons.py` still scales them with `upstream_ink.json`. `check_sizes.py` passed (204 compared). Login screens are unchanged.

Left as they were, on purpose:

- Sticker and the settings GIF stay `sticker` and `film` in `mapping.csv`. #68 did not point those rows at a different glyph. The buttons and badges read the face and the GIF letters from the imagesets in the next section.
- `Chat/Input/Text/IconVideo` stays `video-camera`. The round record button stays the camcorder. The play-in-a-frame glyph was `Chat/Attach Menu/Video` and `Item List/Icons/Video`; those are the camcorder now.
- `Chat/Input/Text/SendIcon` stays the up arrow and is not generated.
- Location was already MingCute's map pin (a teardrop with a hole). It is not the crosshair (`target`). The three location imagesets are unchanged.

Reverted to the upstream PDF, because the MingCute camcorder's viewfinder reads as a play triangle:

- `Chat/Context Menu/VideoCall` (`ic_menuvideocall.pdf`). It is still a template image.

`MingCute/svg/regular/clock.svg` was MingCute's icon named clock, which is a map pin with a check. The file is now MingCute `time`, a clock face. `Item List/Icons/Clock` and `Chat/Context Menu/Schedule` both use it.

Other substitutions: forward arrows are `share-forward` (the hook points right), including `IconForwardSend`, which is no longer the same up arrow as Send. Unpin is `pin-2` plus a slash. The stealth eye is `eye-off`; the locked one adds a padlock. Mute for notifications is a bell, and "mute for" is that bell plus a Z. Business is a storefront, devices are a phone and a tablet, cellular is signal bars, stories is the dotted ring, Stars is a star inside a circle, data is a cylinder, select-all is a checklist, read-all is an inbox plus one check, mark-as-read is a bubble plus one check. Share is the box with an arrow. Topics is a bulleted list. Proxy is a shield with two arrows. The account-switch chevron points up and down. Poll is a bar chart. Report is a circle with an exclamation point. Members is two people, the group icon stays three. Trending stickers use the flame, not the drop-shaped `flame` glyph. AI tools are the letters AI.

`Tellomi/Icons/test_icon_pairs.py` fails if pin and unpin, Eye and EyeLocked, Read and ReadAll and SelectAll, Business and a channel, or Devices and Cellular resolve to the same SVG.

| File | Change |
| --- | --- |
| `Tellomi/Icons/mapping.csv` | The rows above. `SendIcon` is still absent. |
| `Tellomi/Icons/generate_icons.py` | `semantic/` names read from `Tellomi/Icons/semantic`. |
| `Tellomi/Icons/semantic/` | Slash, lock, letters, and the other composed glyphs. |
| `Tellomi/Icons/MingCute/svg/` | The additional MingCute files, and `clock.svg` replaced with `time`. |
| `Tellomi/Icons/test_icon_pairs.py` | The pair check. |
| `Chat/Context Menu/VideoCall.imageset` | Upstream camera PDF. |
| `Images.xcassets` | The regenerated imagesets whose source changed. |

## Sticker and GIF glyphs

MingCute's `sticker` is a blank note with a folded corner, and `film` is a film strip with no letters. The composer sticker button, the attach-menu sticker, the sticker rows in context menus, the settings sticker badge, and the settings GIF badge used those two. The emoji keyboard's own sticker and GIF tabs were never in `mapping.csv` and already show a face and the letters GIF. #68 left `AccessoryIconStickers`, `Chat/Attach Menu/Sticker`, `Chat/Context Menu/Sticker`, `Item List/Icons/Sticker`, and `Item List/Icons/Gif` mapped to `sticker` and `film`. It did not substitute another drawing. Those call sites use the face and the GIF letters below instead of those mapped files.

The round video button stays `Chat/Input/Text/IconVideo`, the MingCute camcorder (`video-camera`). It is not the play-in-a-square `video` glyph. Chat-list sent and read marks are still drawn in `generateStatusCheckImage`: one check when the message is sent, and a second stroke only when it is read. The composer send arrow is `actionControlForegroundColor` (white in day) on `actionControlFillColor` (the accent, default `#3390EC`). The media-picker send disc is `#111111` with the arrow tinted white. This change does not edit `generate_icons.py` or `mapping.csv`. The face and GIF imagesets are not rows in the mapping, so a size pass does not rewrite them. The other files in `Tellomi/Icons/semantic/` are #68's compositions.

| File | Change |
| --- | --- |
| `Tellomi/Icons/semantic/sticker.svg` | MingCute note outline plus two eyes and a smile. |
| `Tellomi/Icons/semantic/gif.svg` | Rounded rectangle with the letters GIF. |
| `Tellomi/Icons/draw_semantic_icons.py` | Writes the three sticker page sizes and the GIF page. Not `mapping.csv`. |
| `Chat/Input/Text/TellomiSticker` | 24pt. Composer button and context menus. |
| `Chat/Attach Menu/TellomiSticker`, `Item List/Icons/TellomiSticker` | 30pt. Attach menu, settings badges, Premium stickers. |
| `Item List/Icons/TellomiGif` | 30pt. Settings GIF badge. |
| `Tellomi/Icons/test_semantic_icons.py` | Face, GIF letters, call sites, camcorder, drawn checks, send contrast. |

## Discover copy, Discover reports, sign-up avatar

Discover and the tab bar read `Tellomi.Discover.*` from the active language pack (`presentationData.strings` primary, then secondary). A missing key falls back to traditional Chinese for `zh-Hant` / `zh-TW` / `zh-HK` / `zh-MO`, simplified Chinese for other `zh*`, and English otherwise. City names use `Tellomi.Discover.City.<country>_<slug>` (the code's `:` and `-` are `_`, so `cn:hong-kong` is `Tellomi.Discover.City.cn_hong_kong`). The English, simplified, and traditional strings are in the three `Localizable.strings` files. The server langpack is unchanged.

A post and a comment have a "…" menu whose Report row opens Telegram's report sheet (`peerReportOptionsController`). The sheet's official ids are `spam`, `violence`, `pornography`, `child`, `drugs`, `personal`, and `other`. Other still asks for a comment. That choice is `POST /v1/feed/reports` with `target_type`, `post_id`, `option`, `reason` (the same id), `detail`, and `comment_id` when the target is a comment. It does not call `messages.report`. A logged-out session does not build the request. Success uses the existing report toast.

`photos.uploadProfilePhoto` keeps its RPC code. If that upload fails during sign-up, the account is still stored and the alert is `头像上传失败（500 …）` with the real code and text. Retry uploads the photo again and does not call `auth.signUp`. The same alert is used when a profile photo upload fails. Login and the session are otherwise unchanged.

| File | Change |
| --- | --- |
| `submodules/TellomiDiscover/Sources/TellomiDiscoverStrings.swift` | Pack lookup and count/id formatting. |
| `submodules/TellomiDiscover/Sources/TellomiDiscoverLoader.swift`, `TellomiDiscoverCity.swift` | Copy and city names take the pack. |
| `submodules/TelegramUIPreferences/Sources/TellomiTabNavigationDecisions.swift` | Tab copy takes the pack. `tellomiStringPack` merges primary over secondary. |
| `Telegram/Telegram-iOS/{en,zh-Hans,zh-Hant}.lproj/Localizable.strings` | The new keys. |
| `submodules/TellomiDiscover/Sources/TellomiDiscoverReport.swift`, `TellomiDiscoverFeed.swift`, `TellomiDiscoverParse.swift` | Report body, `POST /v1/feed/reports`, comment rows on a card. |
| `submodules/TelegramUI/Components/PeerReportScreen/Sources/PeerReportScreen.swift` | Optional `submitLocally` so the sheet does not call the report RPC. |
| `submodules/TelegramUI/Components/Tellomi/FeedScreen/` | "…" on a post and a comment. The feed list has the same button. |
| `submodules/TelegramCore/Sources/TelegramEngine/Peers/PeerPhotoUpdater.swift` | `UploadPeerPhotoError.server` keeps the RPC code and text. |
| `submodules/TelegramCore/Sources/Tellomi/TellomiSignUpAvatar.swift`, `Sources/Authorization.swift` | A failed avatar upload still creates the account. Retry does not sign up again. |
| `submodules/AuthorizationUI/Sources/AuthorizationSequenceController.swift` | The alert and the retry button. |
| `submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/TellomiAvatarUploadFailure.swift` | The same alert on the profile photo screen. |
| Tests | `TellomiDiscoverFeedTests`, `TellomiTabNavigationDecisionsTests`, `TellomiSignUpAvatarTests`. |

## Settings home (M1)

The settings tab is still `PeerInfoScreen` in settings mode. The home list and the About / bindings / more pages are Tellomi types. The header is Telegram's collapsing profile header (centered avatar, name under it, one Edit in the navigation bar). Upstream keeps the old `settingsItems` builder so badges, session counts, and feature gates stay there; the screen asks `tellomiSettingsHomeItems` instead.

| File | Change |
| --- | --- |
| `submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoScreen.swift` | Settings mode calls `tellomiSettingsHomeItems`. |
| `submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoSettingsItems.swift` | The Premium grace banner is hidden unless Premium is enabled, and its copy is no longer hard-coded English. |
| `submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoHeaderNode.swift` | Settings keeps Telegram's collapsing header. The subtitle is `tellomiSettingsIdentityLine` (phone, or else the full email, then `@username`). There is no second Edit and no profile card. |
| `submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/TellomiNavigationSettingsEntry.swift` | `tellomiPushSettingsPage` is the shared push used by the home rows. |
| `submodules/SettingsUI/Sources/Privacy and Security/PrivacyAndSecurityController.swift` | Adds the personalized-recommendation switch in a Discover section after the privacy block and before auto-archive. The value is `TellomiRecommendationSettings`. |
| `submodules/TelegramUIPreferences/Sources/PostboxKeys.swift` | Account preference key `tellomiRecommendationSettings` (id 100). |
| `submodules/TelegramUI/Components/Tellomi/FeedScreen/Sources/TellomiFeedScreen.swift` | The recommend request sends `personalized=false` when the switch is off, and reloads that tab when the switch changes. |
| `Telegram/Telegram-iOS/{en,zh-Hans,zh-Hant}.lproj/Localizable.strings` | `Tellomi.Settings.*`. |

New files, not in the table above: `TellomiSettingsDecisions.swift`, `TellomiRecommendationSettings.swift`, `TellomiSettingsLayout.swift`, `TellomiSettingsPages.swift`. Tips and Apple Watch are not on the home or the More page. Saved messages, recent calls, chat folders, power saving, and open-source licenses are on More. A configured proxy stays on the General group. Help Center opens `https://tellomi.cn/help`. About Tellomi shows the version row only. `TellomiAboutDisclosure` still reads `help.getAppConfig` keys (`tellomi_ai_model_name`, `tellomi_generative_ai_registration_number` or `tellomi_ai_registration_number`, `tellomi_algorithm_filing_number`) and still falls back to 「通义千问 Qwen」 and 「待公示」 / Pending, but that block is not drawn. Discover profile photo and bio stay the existing Privacy & Security rows (`privacyKeyProfilePhoto`, `privacyKeyAbout`). The personalized-recommendation switch is its own Discover section on that screen, not a second photo or bio row.

Help-center rows use different settings glyphs: Help Center is the question mark, Support is the chat icon, Terms and Privacy is the file icon, About is the info icon. Navigation uses the topics glyph (not Appearance). More uses the dots glyph (not Data & Storage).

The Discover tab uses `Chat List/Tabs/IconDiscover` and `IconDiscoverFilled`, a compass drawn on the same 30 pt page and ink box as Settings. Line is resting, fill is selected. It is not a hand-drawn 28 pt image.

## Discover polls, forwards, and notification switch (M3)

The feed client already posted text, listed recommend / following / nearby, and showed quote-deleted copy. It did not create or vote in a poll, did not offer the four forward actions, and Notifications had no Discover switch.

| File | Change |
| --- | --- |
| `submodules/SettingsUI/Sources/Notifications/NotificationsAndSoundsController.swift` | Adds the Discover activity switch and its footer after message categories. Off writes the local preference and `account.updateNotifySettings` for user 777005 (`mute_until = Int32.max`). On writes `mute_until = 0`. Opening the screen reads that peer's settings once, unless the switch was already moved. Reset all notifications turns the switch back on and clears the mute. |
| `submodules/SettingsUI/BUILD` | Depends on `TellomiDiscover` for the switch copy. |
| `submodules/TelegramUIPreferences/Sources/PostboxKeys.swift` | Account preference id 101, `tellomiDiscoverNotificationSettings`. |
| `Telegram/Telegram-iOS/{en,zh-Hans,zh-Hant}.lproj/Localizable.strings` | Poll, forward, and notification keys. |

The push filter is the one already in teamgram `pkg/push`: muting user 777005 (`@faxian`) suppresses like, comment, reply, mention, follow, and repost pushes. Private-chat mute does not. The in-app notification list (`GET /v1/feed/me/notifications`) is still not a screen.

## Document hash before upload (ADR-0082)

Before the byte upload of a GIF, an ordinary document, or a video no larger than 100 MiB, the client hashes the exact bytes it would upload and calls `messages.getDocumentByHash` (`#b1f2061f`, sha256 + size + mime). A reusable document (non-zero id, dc id > 0, same size and mime) is sent as `inputMediaDocument` and the bytes are not uploaded. `documentEmpty`, an RPC error, a short read, a size mismatch, or an incomplete local file falls through to the existing multipart upload. Secret chats are not probed: the uploaded bytes are ciphertext. Voice, music, round video, and stickers are not probed, matching TDLib's `allow_get_by_hash` (animations and documents only). Videos above 100 MiB start uploading immediately; the server still deduplicates those bytes after the upload. A forced re-upload skips the probe so a rejected file reference does not reuse the same document.

| File | Change |
| --- | --- |
| `submodules/TelegramCore/Sources/Tellomi/TellomiDocumentByHash.swift` | New. Which files are probed, the video size cap, and what counts as a reusable document. |
| `submodules/TelegramCore/Sources/Tellomi/TellomiDocumentByHashUpload.swift` | New. SHA-256 of the local bytes and the RPC, with fail-open. The fail-open log is `error.errorDescription ?? ""`: the property is an unannotated Objective-C string, so a bare interpolation does not type-check. A present description is logged as written. The RPC error still returns no document. |
| `submodules/TelegramCore/Sources/PendingMessages/PendingMessageUploadedContent.swift` | Chat send probes before `multipartUpload`. A hit reuses the document, including a video cover when one is attached. |
| `submodules/TelegramCore/Sources/PendingMessages/UploadMediaToCloud.swift` | Composer pre-upload uses the same probe. |
| `submodules/TelegramCore/Sources/PendingMessages/StandaloneUploadedMedia.swift` | Share-sheet file and video upload uses the same probe. |
| `submodules/TelegramCore/Sources/PendingMessages/StandaloneSendMessage.swift` | In-memory file send uses the same probe. |
| `submodules/TelegramCore/Tests/TellomiDocumentByHashTests.swift` | Role selection, the video cap, attribute mapping, the reusable-document check, and the SHA-256 vector. |

## Document hash kill switch (ADR-0083 B1 / D4)

Extends the section above. The #82 send sites stay as they are: a GIF, an ordinary document (including a file sent as `image/jpeg` or `image/png`), or a video no larger than 100 MiB still calls `messages.getDocumentByHash` before the byte upload. Secret chats, voice, music, round video, stickers, videos above 100 MiB, and a forced re-upload still skip it. Compressed photos stay on `uploadedMediaImageContent` / `inputMediaUploadedPhoto`. This RPC returns a document, and those bytes are a generated JPEG, so that path is not hooked. A later photo lookup needs an RPC that returns `InputPhoto`.

Account 0 `mainconfig` on Android is `MessagesController.getGlobalMainSettings()`, key `tellomi_get_document_by_hash`, boolean, default true (`getBoolean(key, true)`). iOS reads the same key from the sending account's persisted `help.getAppConfig` (`AppConfiguration` under `PreferencesKeys.appConfiguration`), which is where that JSON boolean is stored. A missing key, `true`, or a non-boolean keeps the lookup. `false` makes `tellomiLookupExistingDocument` return before SHA-256 and before the RPC, and the caller runs the existing upload. The value is read on each send. There is no new user-visible copy.

| File | Change |
| --- | --- |
| `submodules/TelegramCore/Sources/Tellomi/TellomiDocumentByHash.swift` | `tellomi_get_document_by_hash`, default on. |
| `submodules/TelegramCore/Sources/Tellomi/TellomiDocumentByHashUpload.swift` | A disabled switch returns before the hash and `messages.getDocumentByHash`. |
| `submodules/TelegramCore/Sources/PendingMessages/StandaloneSendMessage.swift` | The in-memory file lookup takes the same postbox so it can read the key. |
| `submodules/TelegramCore/Tests/TellomiDocumentByHashTests.swift` | Default on. `false`, and a forced-off override, return the miss without running the lookup. |

## Download file hashes (ADR-0083 B2)

After a full plaintext `upload.getFile` download is about to become the finished file, the client calls `upload.getFileHashes#9156982a` (`location:InputFileLocation`, `offset:long`). Parts are SHA-256 of 128 KiB, the same split as `upload.getCdnFileHashes` / teamgram `cdn.PartHashes` (teamgram #215, `59922c63`). `offset` drops parts that start before it. The last part is shorter. A later page is requested when the returned parts do not cover the file.

A miss (empty vector), an RPC error, or 12 seconds without a result after the file is ready to finish leaves the file in place. A part whose bytes differ, or a confirmed end shorter than the file, deletes the partial file and fails the download. CDN downloads already check ciphertext hashes. Web files, legacy `inputFileLocation`, secret-chat decryption, and a download that never fills the file (a prefix, a video preload, a file already on disk) do not call this method. iOS does not encrypt the media cache, so that skip stays false. `messages.getDocumentByHash` is unchanged. The schema already names the long-offset method; nothing generated is edited.

Account 0 `mainconfig` on Android is `MessagesController.getGlobalMainSettings()`, key `tellomi_get_file_hashes`, boolean, default true. iOS reads the same key from the account's persisted `help.getAppConfig` (`AppConfiguration`), the same place B1 reads `tellomi_get_document_by_hash`. A missing key, `true`, or a non-boolean runs the check. `false` does not send the RPC. The value is read when the file is ready to finish.

| File | Change |
| --- | --- |
| `submodules/TelegramCore/Sources/Tellomi/TellomiFileHashes.swift` | Part rules, fail-open, and the kill switch. `tellomiGetFileHashesConstructor` is `Int32(bitPattern: 0x9156982a)`, the same spelling as other constructor ids above `Int32.max`. The bits stay `upload.getFileHashes#9156982a`. |
| `submodules/TelegramCore/Sources/Tellomi/TellomiFileHashDownload.swift` | The long-offset RPC, paging, and the commit decision. `network.download` is `Signal<Download, NoError>`, so the page request uses `mapToSignalPromotingError`. The inner `upload.getFileHashes` error is still `TellomiFileHashPageError.rpc`, and that error still fail-opens. |
| `submodules/TelegramCore/Sources/Network/MultipartFetch.swift` | Notes the location and CDN, and observes a plaintext download. |
| `submodules/TelegramCore/Sources/Network/FetchV2.swift` | Notes the location, a CDN redirect, and a fallback to the datacenter. |
| `submodules/Postbox/Sources/MediaBox.swift` | `beforeCompleteCommit`, read when a partial file would be linked. |
| `submodules/Postbox/Sources/MediaBoxFileContextV2Impl.swift` | Holds that link. A refusal deletes the partial and fails the fetch. |
| `submodules/TelegramCore/Tests/TellomiFileHashesTests.swift` | 128 KiB parts, mismatch versus miss, the switch, legacy location. The constructor check compares the unsigned bits with `0x9156982a`. |
| `submodules/Postbox/Tests/MediaBoxFileContextV2FileHashGateTests.swift` | The link waits. Allow keeps the file. Refuse deletes it and fails the fetch. |

## Discover nearby tab (D-11 / D-12)

The Discover bar always shows 推荐, 关注, and 同城, in that order. `GET /v1/feed/config` may omit `nearby`; the tab stays. An unknown config name is still not added.

The first open of 同城 with no saved city asks for When In Use at kilometer accuracy. The coordinate is used once for reverse geocoding and then dropped. Only `CLPlacemark.locality` can become a catalog code such as `cn:chengdu`. A street, a province, or a coordinate does not. If permission is denied, or geocoding returns nothing, the city list stays up and the user picks by hand. Nothing is stored until they pick. Picking does not require permission.

Publishing still uses `POST /v1/feed/posts` and the existing `city` field. The value is that catalog code. There is no latitude, longitude, or address field. The line above the feed (`Posting in Chengdu` / `发布到 成都`) is the city the next post will carry. `这条不标注城市` clears the saved city so the next body omits `city`. The compose screen is unchanged, so it does not collide with the mention and link-preview composers.

`GET /v1/feed/nearby?city=` is the nearby read. `content-engine` was not readable from this tree. A 404, 405, or 501 on that route is shown as 「同城暂时还不能刷新」, not as a generic load failure. `404` with `feed_hidden` stays hidden. An empty 200 is 「这个城市还没有帖子」. The client does not invent another path. Simplified Chinese is what zh-Hans and zh-Hant (including zh-TW and zh-HK) both read for these new lines. A separate traditional translation is not added.

| File | Change |
| --- | --- |
| `submodules/TellomiDiscover/Sources/TellomiDiscoverNearby.swift` | Home tabs, the publish city code, the compose line, and the missing-route check. |
| `submodules/TellomiDiscover/Sources/TellomiDiscoverLoader.swift` | A missing nearby route is `nearbyUnavailable`, not a generic load failure. English and simplified Chinese for those lines. zh-Hant uses the same simplified sentences. |
| `submodules/TelegramUI/Components/Tellomi/FeedScreen/Sources/TellomiFeedScreen.swift` | The three tabs stay fixed. The first coarse-location ask, the city list, the line above the feed, and the degraded empty state. Publish still passes the saved catalog code. |
| `submodules/TelegramUI/Components/Tellomi/FeedScreen/Sources/TellomiFeedScreenNode.swift` | Draws the city line, the change-city action, and the "no city" row. The compose controller is not edited. |
| `Telegram/Telegram-iOS/{en,zh-Hans,zh-Hant}.lproj/Localizable.strings` | The same lines. zh-Hant keeps this simplified pack for them. |
| `submodules/TellomiDiscover/Tests/TellomiDiscoverNearbyTests.swift` | City normalize, tab order, the nearby query, and the publish keys. |

## Personalized recommendations (D-58)

Privacy and Security has a Discover section (「发现」) after the privacy block and before auto-archive, the same place as Android #87 (`5063c69e`). The section is a header, the 「个性化推荐」 switch, and a footer. A missing account preference is on. The value is `TellomiRecommendationSettings` under account preference id 100, the iOS equivalent of Android `mainconfig` key `tellomi_discover_personalized`: per account, local, default on. English, simplified, and traditional strings are `Tellomi.Settings.PersonalizedRecommendationSection`, `PersonalizedRecommendation`, and `PersonalizedRecommendationFooter`. The footer matches Android: 「关闭后，推荐不再根据你的浏览记录排序。」

The row is always shown. `GET /v1/feed/config` still parses `personalization_toggle_visible`, and `tellomiPersonalizedRecommendationRowVisible` ignores it. The parser stores false both when the key is omitted and when it is false, so gating on it would hide the only control that can send `personalized=false` for configs this client already accepts. teamgram's `tellomi_personalized_recommend_default` is the same kind of hide signal and is not read here. teamgram does not store the per-user choice and does not rank the feed.

The recommend request:

| Switch | Request |
| --- | --- |
| On, or no stored value | `GET /v1/feed/recommend` (no query) |
| Off | `GET /v1/feed/recommend?personalized=false` |
| On again | The query is omitted again |

Following and nearby ignore the switch (`tellomiDiscoverFeedRequestPersonalized`). The first read of the preference does not throw away a page. A later change drops `posts[.recommend]` and its cursor immediately. If Recommend is the open tab, that tab reloads in the same turn and shows the empty list while the new page loads. The feed generation moves first, so an older in-flight page cannot write itself back. Another tab keeps what it is showing; Recommend fetches again the next time it opens. The Discover screen does not request Recommend until that preference has been read once, so a stored off applies to the first request.

`recommend_mode` is still parsed and does not decide the switch or the query. The example payload in the feed tests uses `recommend_mode=editorial_chronological` and `personalization_toggle_visible=false`.

**Engine gap.** content-engine is private (`tellomi/content-engine`); this checkout cannot read it. iOS and Android already send `personalized=false`. Nothing in teamgram applies that query. Until content-engine treats `personalized=false` as an order that is not based on the person and treats a missing query as the personalized order, turning the switch off changes the request and clears the cached page, and the returned order can stay the same. This change does not edit content-engine or the Android repo.

## Discover mention candidates

Compose `@` suggestions are still the local contacts plus every peer in any chat-list group. The screen used to read that set with `account.postbox.transaction` (`getContactPeerIds` and `chatListGetAllPeerIds()`). A release build rejects that file: `PostboxImportCheck` runs before `Make.py` compiles, and the file is not on `AllowedImporters.txt` or `AllowedPostboxAccess.txt`. The read is now `TelegramEngine.Contacts.peersFromContactsAndChatList`, one local transaction inside TelegramCore. It is not `messages.chatListPeers`, which stops at a count and goes through the view tracker. A missing peer record is still skipped. The account, a non-user, a deleted user, and a name that fails `validUsername` are still left out of the list. That choice is `TellomiDiscoverMention.mentionPerson`, including the trimmed first-and-last display name. A leading `@` on the input is stored without it; `addressName` does not have one. A mention is still only characters inside `text` on `POST /v1/feed/posts`. The allowlists are not extended. `FeedScreen` no longer depends on `//submodules/Postbox` (that package is not in Postbox's `clients` group).

| File | Change |
| --- | --- |
| `submodules/TelegramCore/Sources/TelegramEngine/Contacts/TelegramEngineContacts.swift` | `peersFromContactsAndChatList`. |
| `submodules/TelegramUI/Components/Tellomi/FeedScreen/Sources/TellomiDiscoverComposeController.swift` | Loads the list through that method and `mentionPerson`. Drops `import Postbox`. |
| `submodules/TelegramUI/Components/Tellomi/FeedScreen/BUILD` | Drops the Postbox dependency. |
| `submodules/TellomiDiscover/Sources/TellomiDiscoverMention.swift` | `mentionPerson`. |
| `submodules/TellomiDiscover/Tests/TellomiDiscoverMentionTests.swift` | Self, non-users, deleted users, invalid names, and the display name. |

## Discover feed compile

Master CI on `8aee720666` failed `//submodules/TelegramUI/Components/Tellomi/FeedScreen:FeedScreen` while building `//Telegram:Telegram`. The share menu called `tellomiStringPack` without importing `TelegramUIPreferences`. The compose bar's `#selector(self.composePressed)` was ambiguous with `composePressed(quoteOf:quotePreview:)`. That quote path is `presentCompose(quoteOf:quotePreview:)`. The bar button still calls `composePressed()`. The file-hash constructor id is unchanged.

| File | Change |
| --- | --- |
| `submodules/TelegramUI/Components/Tellomi/FeedScreen/Sources/TellomiDiscoverShareMenu.swift` | Imports `TelegramUIPreferences` so `tellomiStringPack` is in scope. |
| `submodules/TelegramUI/Components/Tellomi/FeedScreen/Sources/TellomiFeedScreen.swift` | Quote compose is `presentCompose`. The selector names only the bar-button method. |

## Chat list index compile

Master CI on `969315d5df` failed `//submodules/ChatListUI:ChatListUI` while building `//Telegram:Telegram`. `ChatListNodeViewScrollPosition` carries `EngineChatList.Item.Index`. The scroll location shadowed that value with the inner `ChatListIndex` and passed the inner value into the scroll position. The transition then wrapped the engine index in `.chatList`, which expects `ChatListIndex`. `aroundChatListView` still takes the inner `ChatListIndex`. A peer entry's sort index is already `.index` of the engine index, so the scroll comparison uses that same value. The Discover feed compile fix is unchanged.

| File | Change |
| --- | --- |
| `submodules/ChatListUI/Sources/Node/ChatListNodeLocation.swift` | The scroll position keeps the engine index. The view tracker still receives the unwrapped `ChatListIndex`. |
| `submodules/ChatListUI/Sources/Node/ChatListViewTransition.swift` | Both scroll comparisons use the engine index directly. |

## Discover image publish

D-10 multi-image publish now follows the content-engine contract verified at `99fb6ce` on 2026-11-06. No upstream file is edited.

Limits, from that contract and not from the Android client: `media_keys` accepts at most 10 keys, in order, and `OPTIONS /v1/feed/media/uploads` advertises `Tus-Max-Size: 20971520`. The picker stays closed unless `GET /v1/capabilities` includes `media_upload`. A post with no images still sends the previous text, quote, and poll body and does not wait on an upload.

Upload is tus 1.0.0. `OPTIONS` is sent without the discover credential. `POST`, `PATCH`, `HEAD`, and `DELETE` use the existing Bearer credential and only after the URL is checked as this feed origin's `/v1/feed/media/uploads` path. `Location` on another host, an `http` URL, a URL with a user, or a path that escapes the upload prefix is refused and the credential is not attached. JPEG, PNG, and WebP keep their compressed image data. GPS IFDs and XMP GPS fields are removed before upload; a file with no location metadata is not rewritten. Orientation tag `0x0112` stays. HEIC is transcoded to JPEG without copying source properties. `415` voids the upload. `409` reads the offset with `HEAD` and resumes. `429` waits for `Retry-After` (60 when the header is missing). `DELETE` cancels an upload that is not attached to a post.

The post detail lays text, images, link, poll, and comments out in one scrollable stack, so ten images stay reachable. Closing the composer cancels the in-flight URLSession task, drops the in-memory bytes, and deletes a known unattached Location. It does not write a temporary image file. Background cancels the socket and waits with backoff before `HEAD`. A lost create response and an uncertain publish response do not invent a delete. Logout calls `signOut`, which cancels image tasks and stops a later `performImage`, and clears the preview book. Previews are keyed by account and post id. Removing a finished image before the post is sent deletes that unattached upload. After the post is sent, or when the publish response was lost, the local row can be dropped without deleting the server key. A missing or unknown card state is not treated as `ok`. `pending` stays distinct from `unavailable` and does not fetch remote media.

`URLSession` redirects go through `TellomiDiscoverRedirectGate`. Any target off the original https origin or outside the original path prefix is refused, so the Bearer token is not forwarded. EXIF IFD walks stop at depth 8, 256 entries, a seen-offset set, and checked lengths, so a cycle or a deep chain is rejected. `signOut` stays set until `noteSignedIn(account:)`. `run(loggedIn: true)` from an already-open detail does not clear it. This client does not switch Discover picking over to `MediaEditorScreen` or `TGMediaAssetsController`: those own story editing and re-encode to JPEG. `ImageCompression.compressImageToJPEG` is not used: it always writes JPEG and would change PNG and WebP. Video upload stays out of this change.

`POST /v1/feed/posts` adds `media_keys`. Text may be empty when keys are present. `client_nonce` is unchanged across retries. `operation_id` is not sent: `write_idempotency` is recognized, and this contract does not define a value for that field. `400 invalid_media` fails the whole post and does not rotate the nonce. `401 credential_expired` is the existing unauthorized refresh.

Visibility is not rewritten. This client still sends `public`, `contacts`, `close_friends`, `include`, and `exclude`. The server enum is `public`, `friends`, `include`, `exclude`, and `only_me`. `contacts` and `close_friends` are sent as those strings and work only when `ENGINE_DISCOVER_RELATIONS` is on. They are not mapped to `friends` or `only_me`. `include` and `exclude` still require `audience`.

Before review, cards are not `ok`. The author's pending post has no `media_keys` in the card, so the compose screen keeps the local bytes on the post id and the detail shows that preview. After review, `media[]` is `{type:image,key,w,h}` and an optional `url`. A present https `url` is used. Otherwise `feed/config` `media_base_url` is joined with the key. No public host is invented. Video is still not uploaded.

| File | Change |
| --- | --- |
| `submodules/TellomiDiscover/Sources/TellomiDiscoverImagePublish.swift` | Selection, upload phases, cancel, retry, and the publish gate. |
| `submodules/TellomiDiscover/Tests/TellomiDiscoverImagePublishTests.swift` | Caps, incomplete send, cancel, nonce, and the unchanged text body. |
| `submodules/TellomiDiscover/Sources/TellomiDiscoverImagePrivacy.swift` | Strips GPS from JPEG, PNG, and WebP without re-encoding the image. |
| `submodules/TellomiDiscover/Sources/TellomiDiscoverDetailLayout.swift` | Scroll stack so ten images stay reachable above the poll and link. |
| `submodules/TelegramUI/Components/Tellomi/FeedScreen/Sources/TellomiDiscoverComposeController.swift` | Picker, upload, and release on close, background, and cancel. |

## Lock-screen sender avatar

A message notification on the lock screen and in Notification Center was drawing the Tellomi app icon. Upstream Telegram draws the sender's photo there, or the colored letter avatar when the peer has no photo. The notification service already does the same work as upstream: `peerAvatar` builds an `INImage` from the cached profile photo (or the letter avatar), `addSenderInfo` puts it on an `INSendMessageIntent`, and `generate` calls `UNNotificationContent.updating(from:)`. `Avatar/TellomiMark` is not on this path. It is only the in-app fallback for service users 777000 and 333000 when they have no photo.

iOS uses that intent image as the row icon only for a communication notification. That presentation requires `com.apple.developer.usernotifications.communication` on the main app. `Telegram/BUILD` used to emit the key only for `ph.telegra.Telegraph` and `org.telegram.Telegram-iOS`. Tellomi's bundle id is `app.tellomi.chat`, so the signed app never had the key, `updating(from:)` did not change the icon, and iOS kept the app icon. The notification service extension does not need the key. Upstream puts it on the app only. The extension Info.plist already lists `INSendMessageIntent`, and the app Info.plist already lists it under `NSUserActivityTypes`.

The key is now signed when the main provisioning profile contains it. `prepare_appstore_signing.py` enables App ID capability `USERNOTIFICATIONS_COMMUNICATION` before creating the profile. If the API refuses the capability, the script warns and continues, and the profile check decides the binary: a profile without the key omits the entitlement so codesign still succeeds, and that build still shows the app icon. An unsigned simulator build includes the entitlement. CarPlay, unrestricted VoIP, and the other official-only entitlements are unchanged.

| File | Change |
| --- | --- |
| `Telegram/BUILD` | Communication notifications follow `telegram_communication_notifications` as well as the official bundle ids. |
| `build-system/Make/BuildConfiguration.py`, `build-system/Make/Make.py` | The flag is true when the main profile grants the entitlement, and on `--disableProvisioningProfiles`. |
| `build-system/example-configuration/variables.bzl` | The checked-in example sets the flag true. |
| `Tellomi/extension-suffixes.json`, `Tellomi/prepare_appstore_signing.py` | The main App ID requests `USERNOTIFICATIONS_COMMUNICATION`. A downloaded profile without the entitlement is reported and does not fail the signing run. |
| `docs/TELLOMI.md` | The entitlement is no longer listed as absent. |

## Chat list swipe buttons

Checked against TelegramMessenger/Telegram-iOS `279f89e4d4f63f17227bf877dc3d8990f22ecd58` (master, "Bump version", 2026-10-28). `ItemListRevealOptionsNode.swift` and `ItemListRevealMotion.swift` match that tree. The circle-or-capsule choice is `ItemListRevealOptionLayoutMetrics.metrics` (upstream since `c64653ed`, merged here as `91eb779ae2` on 2026-05-14). A row at least `50 + 4 + ceil(11pt line height)` tall, with an icon, draws a 50×50 circle, corner radius 25. A shorter row, or an action with no icon, draws a 60×32 capsule, corner radius 16, and an iconless action puts the title inside the capsule. That capsule is the upstream iconless branch. It is not an iOS version of `UISwipeActionsConfiguration`, and it is not a Tellomi theme.

`ChatListItem.swift` differs from that upstream file only in the swipe icons. Upstream plays `anim_mute`, `anim_delete`, `anim_archive`, `anim_unread`, and the other reveal Lotties. Tellomi keeps the MingCute PDFs from the icon pass (`599d6869aa`). Those imagesets sit in `Chat List/Swipe`. Every other imageset folder in `Images.xcassets` sets `provides-namespace`. `Swipe` did not, so the compiled name was `Chat List/Mute` (and the same for the other fourteen) while `swipeIcon` asks for `Chat List/Swipe/Mute`. `imageNamed` returned nil, `swipeIcon` returned `.none`, and `metrics(for:hasVisualIcons:)` took the capsule at every row height. Mute, delete, archive, unread, and pin all went through that one lookup.

The actions are the upstream ones. On the main list, the leading side is read/unread and pin/unpin, and the trailing side is mute/unmute, delete, and archive. The archive list's trailing side is pin/unpin, delete, and unarchive, and its leading side is empty. A folder that excludes archived chats still offers archive. Full-swipe distance, the destructive confirmation (`width - 29`), the other confirmation (`width * 0.525`), the arming threshold (`width * 0.75`), and the 414/375 edge zones are the upstream `ItemListRevealMotion` values. The leading side uses `leftInset` and the trailing side uses `rightInset`. Light and dark still use `theme.list.itemDisclosureActions`. The MingCute drawings stay; the Lottie clips are not put back. The glyph page stays 30×30, which is under the circle's 40pt icon cap. Upstream's Lottie is scaled by an extra 1.5 and draws larger than the circle. That is the remaining difference.

| File | Change |
| --- | --- |
| `submodules/TelegramUI/Images.xcassets/Chat List/Swipe/Contents.json` | `provides-namespace`, same as `Chat List/Search` and `Chat List/Tabs`. |
| `submodules/ChatListUI/Sources/Node/ChatListItem.swift` | Comment on the nil lookup. The MingCute names are unchanged. |
| `Tellomi/Icons/test_chat_list_swipe.py` | Catalog name, circle-versus-capsule, actions, and the upstream gesture thresholds. |
| `build-system/Make/ChatListSwipeCheck.py`, `Make.py` | `build` and `test` run that check next to the icon-size check. |
