# Upstream patches

## Moments composer send task — 2026-11-11

Branch `cursor/moments-composer-outbox-5d88`, based on `release/ios`.

The composer keeps one `client_nonce` for a submission and stores that task in the account Postbox (`moments` cache, outbox). A retry sends the same nonce through `momentsEncodePost`. Cancel, the back button and swipe-back share `momentsComposerLeave`. No upstream navigation code was changed: `ViewController.attemptNavigation` already covers the back button and the interactive pop. New strings are keys added to `en.lproj` only.

content-engine dedupes `client_nonce`. `posts.go` returns the first post on a retry (`a retry gets the first post back`). `interactions.go` looks the nonce up and falls back to the unique index. `uploads_bind_test.go` asserts a repeated nonce returns the first post and the count stays 1. The HTTP result is 200 with the original `{id, state, version}`. The client treats that body as success: the outbox entry is removed and Following shows that post.

| File | Change |
| --- | --- |
| `submodules/TelegramCore/Sources/TelegramEngine/Moments/MomentsComposerSession.swift` | Publish gate, nonce, draft restore, pending-send disposition. |
| `submodules/TelegramCore/Sources/TelegramEngine/Moments/MomentsModels.swift` | Draft keeps audience, quote, local files and the nonce. |
| `submodules/TelegramCore/Sources/TelegramEngine/Moments/TelegramEngineMoments.swift` | Outbox read and write. |
| `submodules/TelegramUI/Components/Moments/Sources/MomentsComposerScreen.swift` | Gate, shared leave, persisted send. |
| `submodules/TelegramUI/Components/Moments/Sources/MomentsScreen.swift` | Offers a restored send. |
| `Telegram/Telegram-iOS/en.lproj/Localizable.strings` | New Moments draft and outbox keys. |

## Root tab menu (选单设定) — 2026-11-10

A fresh install shows 动态, 聊天, 设置. Contacts, Calls and News stay off until the person turns them on. Chats and Settings cannot be hidden. The choice is per device (`UserDefaults` suite `app.tellomi.chat.tab-bar`), not an account record. Hiding button titles shortens the phone tab bar; an iPad or vertical bar is unchanged. The bar rebuilds when the switches move.

The screen is Settings → a Tools card → 选单设定. iMe's public iOS tree (only `master`, pushed 2019-10-31, no tags) does not contain this screen. Swiftgram's tab settings (`CallListSettings.showContactsTab`, `SGSimpleSettings.showTabNames`, `addRootControllers`) are the pattern: optional tabs are left out of the controller list, and chats and settings are always appended. Swiftgram asks for a restart to hide titles. This build applies that immediately. No Swiftgram or iMe source was copied.

| File | Change |
| --- | --- |
| `submodules/TelegramUI/Sources/TelegramRootController.swift` | Builds the root tabs from `TellomiTabBarPreferences`. |
| `submodules/TelegramUI/Sources/ApplicationContext.swift` | Applies a saved menu immediately, and keeps the old Calls "show tab" switch in step with it. |
| `submodules/TelegramPresentationData/Sources/PresentationData.swift` | Fills menu strings the active language pack does not have yet. |
| `submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoScreen.swift` | Settings row that opens the screen. |
| `submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoSettingsItems.swift` | Tools card. |
| `submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoScreenSettingsActions.swift` | Pushes the screen. |
| `submodules/TelegramUI/Components/TabBarComponent/Sources/TabBarComponent.swift` | Hides phone tab titles and shortens the bar. |
| `submodules/TabBarUI/Sources/TabBarController.swift` | `showsItemTitles`, applied on the next layout. |
| `submodules/TabBarUI/Sources/TabBarContollerNode.swift` | Passes that flag into the bar. |
| `Telegram/Telegram-iOS/en.lproj/Localizable.strings` | English keys for the generated string accessors. |

## Login language, sign-up handoff, upstream crash logs — 2026-11-10

Build 80 on a Chinese phone showed the English tour plus "Continue in 简体中文", and `initConnection` sent `system_lang_code=zh-Hans-US` with `lang_code=en`. `AppleLanguages` is the system list. `zh-Hans-US`, `zh-Hans-CN`, `zh-CN` and `zh` resolve to bundled `zh-Hans`. `zh-Hant-TW`, `zh-Hant-HK`, `zh-TW` and `zh-HK` resolve to `zh-Hant`. Anything else is English. A language stored with `tellomiRememberExplicitLanguage` wins. The welcome pages are the bundled `Tour.*` strings, so they do not wait for a langpack, and the suggested-language button is not shown.

`auth.signUp` returned `auth.authorization` (`auth.authorization#2ea2c0d4`, layer 232). About 49ms later the client closed the connection and opened a new unauthorized session (new temp keys, no `updates.getState`). `signUp` used to write the authorized state and switch the account record as two later signals. The record could leave the auth slot while the postbox still looked unauthorized, `SharedAccountContext` deleted that record, and `beginNewAuth` showed the welcome screen. `signUp` now writes `AuthorizedAccountState` and switches the record in the same order as `auth.signIn`. A following nil state does not rebuild the welcome on that controller. If the open still races, a postbox that already holds `AuthorizedAccountState` is opened again instead of being deleted.

Crash logs are the upstream Telegram-iOS screen again (MetricKit store, debug Settings list, prompt that resolves `@iOSCrashReportsBot` and gives up after 15 seconds). The Tellomi prompt that waited on `networkState` and never called `contacts.resolveUsername`, the `tellomi_crash_report_bot` upload, the Saved Messages fallback, and the pre-login signal handler are gone. `CrashReport.*` strings were removed from every `Localizable.strings`.

| File | Change |
| --- | --- |
| `submodules/TelegramCore/Sources/TellomiBuiltinLanguage.swift` | Resolves `zh-Hans-US` and the other variants. Sets `lang_code`. |
| `submodules/AuthorizationUI/Sources/TellomiBundledWelcome.swift` | Welcome and pre-login strings from the bundled lproj. |
| `submodules/AuthorizationUI/Sources/AuthorizationSequenceSplashController.swift` | No second language button. |
| `submodules/TelegramCore/Sources/Authorization.swift` | `signUp` persists the account the same way `signIn` does. |
| `submodules/DebugSettingsUI/Sources/CrashReportsController.swift` | Restored from upstream Telegram-iOS. |
| `submodules/CrashReporting/Sources/*` | Restored from upstream. The signal handler is deleted. |

## MTProto port 443 fallback — 2026-11-10

Overseas networks drop TCP 10443 and pass 443. The seed for datacenter 1 is `api.tellomi.cn` on 10443, then 443. 10443 is last in the address list, so a client that never sees 10443 fail still dials 10443 first. An endpoint that has never received a response uses a 5 second TCP handshake timeout; after it has answered once, the handshake timeout stays 12 seconds. The failure is recorded before the reconnect is queued, including before login, and the first reconnect is immediate, so the next dial is 443. A saved datacenter list and a `help.getConfig` `dc_options` list that omit 443 get it added back. The server does not have to return 443 for this client to keep the fallback.

| File | Change |
| --- | --- |
| `Tellomi/tellomi-server.json` | `seed_fallback_ports` is `[443]`. `seed_port` stays 10443. |
| `submodules/MtProtoKit/Sources/TellomiServerConfig.m` | Builds one `thisPortOnly` address per port, preferred port last. |
| `submodules/MtProtoKit/Sources/MTContext.m` | Merges those seed addresses into a saved or server-supplied list. |
| `submodules/MtProtoKit/Sources/MTTcpConnection.m` | 5s handshake until the endpoint has answered, then 12s. |
| `submodules/MtProtoKit/Sources/MTTcpTransport.m` | Records the failed scheme before asking for the next connection. |
| `submodules/MtProtoKit/Sources/MTProto.m` | A pre-login TCP failure counts toward that rotation. |
| `submodules/TelegramCore/Sources/Network/Network.swift` | Installs the seed address sets. |
| `submodules/MtProtoKit/Tests/MTSeedFallbackTests.m` | Seed order, saved-list merge, dc_options merge, and the 10443-then-443 choice. |

## Moments feed contract, list and comments — 2026-11-10

Branch `cursor/moments-feed-f01-f04-7ea6`, based on `release/ios` (`043a05bd55`).

- `POST /v1/feed/posts` is built by `momentsEncodePost`. The body is `kind=post`, `visibility`, `media_keys`, root `city` / `allow_nearby` / `place_id`, `quote_of` and a UUID `client_nonce`. It does not send `media`, `location`, `comment_policy` or `link_preview`. Include and exclude send `audience.audience_token` from `discover.getAudienceToken` (`#dc5213c2` / `#da177181`). A token failure leaves the picked audience in place. The nonce is fixed for retries of that draft.
- Tapping the post body opens `MomentsDetailScreen`. The comment button presents `MomentsCommentSheet` over the list. Closing the sheet does not push or pop, so the tab and scroll position stay. A photo or video opens the gallery. Tab taps and pager swipes share `commitSelection`. Profile, search and a post deep link keep the detail screen.
- The list loads the next page near the bottom and dedupes by id. Pulling down refreshes from a nil cursor and cancels the previous page request. A failed page can be retried. Following, friends and nearby probe the first page on an interval while the feed is on screen and only raise the new-posts pill. Recommend does not poll. The probe pauses while the feed is off screen or the comment sheet is covering it.
- The comment sheet keeps separate hot and latest cursors, sends `parent_id` for a reply, opens an author from the avatar or name, and long-presses for reply, copy, report and delete where that action is allowed. `canComment` and `commentPolicy` disable the field. The text, reply target and attachment clear only after a successful send. A failed send shows `Moments_Comment_SendFailed`. A failed audience token shows `Moments_Audience_Kept` and leaves the selection in place. Both keys are in every built-in lproj: en, zh-Hans, zh-Hant, ar, be, ca, de, es, fa, fr, id, it, ko, ms, nl, pl, pt, ru, tr, uk and uz. Languages Android already translated use that wording. be, ca, fa, fr, id, ms, pl, tr and uz have their own native sentences, not English. `momentsText` uses that lproj when the langpack has no translation of its own. A repeated tab change cancels the previous page before its callback can render. A like updates only that row. Feed photos are bound to the cell that requested them. The post body opens the detail screen, and a photo or video opens the gallery. Relative times use the shared timer strings. A retry uses the same nonce. Comments that are turned off still use `Moments.Comment.Closed`.

## Moments feed (动态) — 2026-11-09

Branch `cursor/moments-feed-v1-b405`, based on `de22e3ff` (official restore, PR #138). This is not part of the 14.0.5 release candidate.

The feed is new client code. It does not revive the cancelled Discover/Feed work from iOS PRs #124–#137.

- Root tabs: Contacts, Calls, Moments, Chats, Settings. Search stays the native tab-bar search, with a Moments filter.
- News stays behind `isNewsFeedEnabled` (off while the channel feed API is parked).
- `TelegramEngine.Moments` calls content-engine `/v1/feed`. The host is `https://feed.tellomi.cn` unless `help.getAppConfig` supplies a valid `tellomi_discover_feed_base_url`. `tellomi_discover_feed_enabled` does not show or hide the tab. The bearer token is `discover.getEngineCredential` (`#a80a7f76` / `#0578ccaa`, appended to `swift_scheme.tl` the same way as the other Tellomi constructors) and is sent as `Authorization: Bearer`, refreshed before `expires`. `region` is `cn` or `global` and is not a host. Image URLs are joined onto `media_base_url` from `GET /v1/feed/config`. Photos are fetched with `HttpReferenceMediaResource` into `MediaBox` and decoded as an ImageIO thumbnail at the view size. `MomentsPrefetchManager` starts that fetch for the visible rows and the next 8.
- The Moments tab is created with the other root tabs and is not removed when `GET /v1/feed/status` fails or reports `visible: false`. An unreachable engine is an error row inside the feed.
- Feed pages, hides and the one-page cache live in the account Postbox item-cache collection `moments` (id 63), which is cleaned with the rest of the account database. The composer does not restore the previous audience; each post asks again.
- Audience reuses `ShareWithPeersScreen` with a mutual-followers category. Story-only rows stay off. Exclude lists stay in the story peer-list cache.
- Gallery media goes through `legacyAssetPickerEnqueueMessages` and tus `POST /v1/feed/media/uploads`.
- A visible video uses `UniversalVideoNode` only when autoplay is on and Reduce Motion is off.
- Comment stickers and GIFs use `StickerPickerScreen` (`hasGifs`) and are uploaded with tus. Likes and poll votes open an `ItemListPeerItem` list filled from `/v1/feed`.
- Feed list endpoints return `{items:[{id,reason}],cursor}`. The client hydrates with `POST /v1/feed/cards`. Notifications use `?tab=interactions|follows|system`. Home tabs are always 推荐 / 关注 / 好友 / 同城 (`recommend`, `following`, `friends`, `nearby`). `GET /v1/capabilities` does not hide 好友. `GET /v1/feed/friends` uses the same cursor as following; following list reasons are `self`, `following` and `repost`, and friends items use `reason=friend`. A failed friends request is an in-feed retry, not a hidden tab. The composer stops at 500 characters and 10 images. Image `renditions` (largest first) supply the feed bitmap: 1080 for a single image, 360 for a carousel cell, original only in the gallery. A missing tier uses the original key/url. Video cells show `poster`, then `cover_key`. An absolute `url` is used as-is; a key is `media_base_url` + key. ImageIO still downsamples whatever bytes arrive.
- `prepareMediaBase()` emits one `Void` so the requests chained after it actually run.
- There is no city catalog (`/v1/feed/cities` is empty). 同城 is `GET /v1/feed/nearby` with no city picker. A card's city name is shown only when the card includes it.
- Voice posts are capped at 60 seconds, or `voice_max_seconds` from `GET /v1/feed/config`.
- Comment stickers and GIFs are uploaded with tus and sent as `{type,key,...}`. They are not Telegram document ids.
- Relative media keys use `media_base_url`, or `https://media.tellomi.app/feed` when that is missing. Absolute https URLs (signed R2) are left as returned. Image versus video follows the card `type`, not the HTTP content-type.

## On-device MapKit venues

Nearby places and the location search box call `nearbyVenues`. That asks `help.getConfig`'s `venue_search_username` (otherwise `foursquare`), resolves the bot, then calls `messages.getInlineBotResults`. This server's venue bot returns an empty list, and a mainland Apple developer account cannot get a MapKit JS key, so the list stays empty unless the device asks MapKit itself.

The bot request still runs. It runs beside MapKit and is dropped after 1.5 seconds. MapKit nearby is `MKLocalPointsOfInterestRequest` at 2.5 km, then one `MKLocalSearch` (`餐饮` / `餐飲` / `restaurant`, from the UI language) when that list is empty. A text query is `MKLocalSearch` within 100 km. Rows are `TelegramMediaMap` venues with `provider` `apple`, a foursquare-style `type`, and the title and address the message sends. Bot rows and MapKit rows are merged, the same place is kept once (the bot row wins), and the list is nearest first.

A disposed signal cancels `MKLocalSearch`. Starts are at least 0.4 seconds apart. `MKError.loadingThrottled` does not start the second search and opens an 8 second cooldown. The same query within 200 meters is reused from memory for 3 minutes (20 seconds when the list was empty). The cache is not written to disk. The search does not call anyone except Apple and the existing bot RPC. Coordinates are stored as MapKit returns them (WGS-84). The China offset stays in the map renderer, which is the same value a shared location and the Apple Maps open-in URL already use.

| File | Change |
| --- | --- |
| `submodules/LocationUI/Sources/LocationUtils.swift` | `nearbyVenues` forwards to the MapKit signal. |
| `submodules/LocationUI/Sources/AppleMapVenueSearch.swift` | Bot request, MapKit requests, cancel, cache, merge. |
| `submodules/LocationUI/Sources/AppleMapVenueMapping.swift` | Venue fields, dedup, distance order, cache and throttle rules. |
| `submodules/LocationUI/Tests/AppleMapVenueMappingTests.swift` | Those rules. |
| `submodules/LocationUI/BUILD` | Host test `AppleMapVenueMappingTests`. |
