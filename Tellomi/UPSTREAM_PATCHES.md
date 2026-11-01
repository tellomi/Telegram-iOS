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
| iOS Settings lists 简体中文 | `Telegram/BUILD` `empty_languages` includes `zh-Hans` (empty `Localizable.strings`, same as the other bundled languages). `Telegram/Telegram-iOS/zh-Hans.lproj/InfoPlist.strings` is the permission copy. A phone set to Chinese can select that localization. `CFBundleDevelopmentRegion` stays `en`, which is the bundled string fallback. |
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

## Teamgram on screen

There is no client string "Teamgram" in the auth, login, session, or profile UI. The word appears in comments and in `Tellomi/tellomi-server.json`.

| What the owner sees | Where it comes from |
| --- | --- |
| Active session named Teamgram | `authorization.appName` from `account.getAuthorizations`, drawn in `ItemListRecentSessionItem` / `RecentSessionScreen`. `initConnection` has no app-name field. The server names the session from `api_id` (this client sends `100001`). |
| Profile title Teamgram and @teamgram | `user.first_name` and `user.username` on the user the server returns. The client does not invent a display name for that peer. |

Replacing those on the client would disagree with the account the server stores. "Didn't get a code" opens `https://tellomi.cn/faq` instead of mailing `sms@telegram.org`.

## Login code screen, pending code, and narrow digits

Checked against the Android reports (mixed English on a Chinese phone, keyboard covering the login header, sixth code box clipped, untranslated Bind phone number, stale SMS number). The phone home, the agreement card, email entry, and Settings → Account already take Simplified Chinese from `tellomiLoginCopy` / `tellomiEmailLoginCopy` when `tellomiChromeLanguageCode` resolves to `zh*`. That reads `AppleLanguages`, not `Locale.preferredLanguages`, so an English-only bundle does not force English. Apple, Google, other methods, account recovery, and password login already present 「暂未开放」. Settings → Account draws 绑定手机号 / 绑定邮箱 as the same disclosure row as a phone number (icon, title, chevron). The phone home is top-pinned under the navigation bar and does not move when the keyboard opens (`disableAutomaticKeyboardHandling`), so Help stays above the title.

The code screen did not. It centered in a region that started at the status bar and reserved a full keyboard, so on a short phone the title sat under Help. Six digit boxes used `max(preferred, fitted)` and kept the preferred width when the row was narrower than that, so the last box crossed the row on a 320pt width. Back asked "cancel verification?" and left `.confirmationCodeEntry` stored; the next launch opened that screen again. A `sendCode` that finished after Back, or after a newer number was submitted, wrote its own `phone_code_hash` and the code screen showed the earlier number.

| File | Change |
| --- | --- |
| `submodules/TelegramCore/Sources/Authorization.swift` | `TellomiLoginAttempt`. `sendAuthorizationCode` and `resendAuthorizationCode` write the code state only while that attempt is still current. The check and the write hold the same lock. |
| `submodules/AuthorizationUI/Sources/AuthorizationSequenceController.swift` | Each send takes an attempt. Back, close, and a new number retire it and cancel the in-flight request. A code state that is not the current attempt (including one restored at launch) is replaced with phone entry. The number is kept in the field; the hash is not. |
| `submodules/AuthorizationUI/Sources/AuthorizationSequenceCodeEntryController.swift` | SMS, email, call, firebase, and other-session back returns immediately. The cancel dialog stays for word and phrase. |
| `submodules/AuthorizationUI/Sources/AuthorizationSequenceCodeEntryControllerNode.swift` | The Tellomi code stack is centered under the navigation bar. When that band is shorter than the stack, the stack stays top-aligned there instead of moving up under Help. |
| `submodules/CodeInputView/Sources/CodeInputView.swift` | Expanded digit boxes shrink, spacing first down to 4pt, so six boxes stay inside the width they were given. |
