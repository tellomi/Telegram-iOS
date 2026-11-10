# Upstream patches

## Login language, sign-up root, and pre-login crashes — 2026-11-10

TestFlight 14.0.5 (79) on an iPhone 12 set to zh-Hans stayed in English, then died after the first `auth.signUp` while the logged-in root was still coming up. `release/ios` commit `fc420b8589` had dropped the Tellomi login-locale files that `master` still has. The Moments feed from #155 is unchanged.

`NSLocale.preferredLanguages` is filtered to localizations the bundle ships. With only `en.lproj` it is `en` on a Chinese phone, so `initConnection.system_lang_code` and the welcome tour were English. The system list is the global `AppleLanguages` domain. `zh-Hans` / `zh-CN` / `zh` download langpack `zh-hans`. `zh-Hant` / `zh-TW` / `zh-HK` / `zh-MO` download `zh-hant`. The server already suggests that pack. `TellomiDidApplySystemLangPack` records that the automatic pack was applied, so a later choice in Settings is kept. The welcome pages are bundled copy (`tellomiIntroCopy`) and do not wait on the download. `FLOOD_WAIT_N` on the login screens says to try again in N seconds.

After `auth.signUp`, the window waits for the authorized root's `isReady`, installs that controller, and only then dismisses the authorization controller. A nil video converter or a photo without a `CGImage` no longer traps on the sign-up screen.

Crashes before login are written from a signal handler (`SIGABRT`, `SIGSEGV`, `SIGBUS`, `SIGILL`, `SIGFPE`, `SIGTRAP`) and from the uncaught-exception handler into `Library/Application Support/CrashReports/incoming`. The next launch imports those files into the same store MetricKit uses. The existing prompt sends the report to `tellomi_crash_report_bot` once an account is authorized, and still falls back to Saved Messages.

| File | Change |
| --- | --- |
| `submodules/MtProtoKit/Sources/MTApiEnvironment.m` | `system_lang_code` reads `AppleLanguages`. |
| `submodules/AuthorizationUI/Sources/TellomiLoginLocale.swift` | System language, langpack code, flood-wait sentence. |
| `submodules/AuthorizationUI/Sources/TellomiIntroCopy.swift` | Welcome copy for zh-Hans, zh-Hant, and English. |
| `submodules/AuthorizationUI/Sources/AuthorizationSequenceSplashController.swift` | One button, bundled welcome copy, downloads zh-hans / zh-hant instead of `en`. |
| `submodules/AuthorizationUI/Sources/AuthorizationSequenceController.swift` | Applies the pack before the login screens. Does not rebuild login after authorization. |
| `submodules/TelegramUI/Sources/ApplicationContext.swift` | Applies the same pack after sign-in if it is still pending. |
| `submodules/TelegramUI/Sources/AppDelegate.swift` | Sets the ready logged-in root before dismissing authorization. |
| `Telegram/Telegram-iOS/zh-Hans.lproj/Localizable.strings`, `zh-Hant.lproj` | Restored from `master`, plus the flood-wait and crash-report sentences. |
| `submodules/CrashReporting/Sources/TellomiCrashSignalHandler.m` | Immediate signal and exception handler. |

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
