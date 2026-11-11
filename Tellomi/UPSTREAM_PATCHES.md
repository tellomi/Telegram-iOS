# Upstream patches

## Moments tab animation — 2026-11-11

The Moments tab uses the same item contract as Chats, Contacts, Calls and News. The static template icon stays on `image` and `selectedImage`. `TabMoments` is set as `animationName` unless Reduce Motion is on, with the same one-pixel `animationOffset` as Chats and News. A theme, strings or Reduce Motion change sets or clears that name the way `ChatListController.updateThemeAndStrings` does. The asset is a Lottie JSON in `Resources/Animations`, the format of `TabChats` and `TabSettings`. Its last frame is the static feed icon. The settings tab avatar is unchanged: it still appears only when another account is signed in. iMe's public tree (`imemessenger/iMe-iOS`, `master`, pushed 2019-10-31) draws extra tabs as template images and does not play a Lottie.

| File | Change |
| --- | --- |
| `submodules/TelegramUI/Components/Moments/Sources/MomentsScreen.swift` | `TabMoments`, cleared while Reduce Motion is on. |
| `submodules/TelegramUI/Resources/Animations/TabMoments.json` | Selection animation. Rest frame matches the static icon. |

## Moments feed main-thread layout — 2026-11-11

Scrolling the feed asked `ListView` to build each new row on a global queue. `MomentsPostItemNode` and `MomentsStatusItemNode` are view-backed (`UIStackView`, labels, image views, content-hugging constraints). Creating them there opened an implicit `CATransaction`. When the GCD worker exited, Core Animation committed it and Auto Layout aborted (`_AssertAutoLayoutOnAllowedThreadsOnly`, TestFlight 14.0.5 (86)). Measurement still runs on that queue. The node, its frames and image assignment run on the main queue. Cached feed and hide reads, and like, save, follow and comment completions that touch views, are delivered on the main queue too. ImageIO thumbnails stay off the main queue; only `UIImageView.image` is set on it.

| File | Change |
| --- | --- |
| `submodules/TelegramCore/Sources/TelegramEngine/Moments/MomentsMainQueue.swift` | `momentsOnMainQueue`. |
| `submodules/TelegramUI/Components/Moments/Sources/MomentsPostItem.swift` | Row and status nodes are created on the main queue. |
| `submodules/TelegramUI/Components/Moments/Sources/MomentsRemoteImage.swift` | Bitmap decode stays in the background. The image view is updated on the main queue. |
| `submodules/TelegramUI/Components/Moments/Sources/MomentsScreen.swift` | Cached page and hides render on the main queue. |
| `submodules/TelegramUI/Components/Moments/Sources/MomentsFeedActions.swift` | Like, save and follow rollbacks render on the main queue. |
| `submodules/TelegramUI/Components/Moments/Sources/MomentsCommentSheet.swift` | Comment send, delete and report errors update the sheet on the main queue. |
| `submodules/TelegramUI/Components/Moments/Sources/MomentsDetailScreen.swift` | Comment send updates the field on the main queue. |

## Crash log prompt — 2026-11-11

The prompt after an unexpected quit used four English sentences, and it marked every pending report presented as soon as the alert appeared. Opening Apple's share sheet resigns the app, which dismissed the alert. The presented flag was never cleared, so Send Log did not come back. Send Log also resolved `@iOSCrashReportsBot` and wrapped the zip in an Instant Page, which this server does not collect.

The report stays pending until Not Now, or until the server accepts Send. Resigning active dismisses the alert and shows it again once the app can present. A later update while that alert is already up, or while a send is in flight, does not present a second copy. A refused send leaves the report pending and the prompt can show again. The zip is a normal document (`application/zip`, filename `Tellomi-iOS-<version>-crash.zip`, caption `app=<version> device=<device>`), sent with `messages.sendMedia`. The thank-you toast waits for that RPC to return. A transport acknowledgement is not success, and a refused send leaves the report pending. The bot username is `help.getAppConfig`'s `tellomi_crash_report_bot`, or `TellomiBot` when that value is missing or not a username.

The four sentences are `CrashReport.Prompt.*` in every built-in lproj. `PresentationStrings` is generated from `en.lproj`. The server langpack still wins when it has a translation that is not the English sentence. Until then, the lproj for the active language is used.

| File | Change |
| --- | --- |
| `submodules/DebugSettingsUI/Sources/CrashReportPrompt.swift` | Prompt state machine, bot name, document caption. |
| `submodules/DebugSettingsUI/Sources/CrashReportsController.swift` | Lang-pack prompt. Document send. Server confirmation. |
| `submodules/DebugSettingsUI/Tests/CrashReportPromptTests.swift` | Show, resign, confirm, failure, decline, document, bot name. |
| `Telegram/Telegram-iOS/*.lproj/Localizable.strings` | Prompt strings for every built-in language. |

## Moments feed limits and recommendation switch — 2026-11-11

`GET /v1/feed/config` puts the caps in a nested `limits` object. The client was reading invented names from the top of the document, so every server cap was ignored. The parser now reads only the engine's keys. A missing key, or a value that is not a positive whole number, keeps the client default. Those defaults are the content-engine constants: 2000 characters, 12 images, and 180 seconds for both voice caps. `personalization_toggle_visible` is a top-level boolean. Anything else, including `1` and `"true"`, hides the switch.

The recommendation switch is only on the Moments settings screen. Off sends `personalized=false` on recommend and reloads that feed. On leaves the recommend query unchanged. The choice is read again when the Moments tab is created, and an older read cannot overwrite a newer toggle.

| Server key | Client field |
| --- | --- |
| `limits.post_text_chars` | `textLimit` (2000, `posts.go` `MaxPostChars`) |
| `limits.post_images` | `imageLimit` (12) |
| `limits.post_videos` | `videoLimit` (3) |
| `limits.video_max_seconds` | `videoMaxDuration` (60) |
| `limits.voice_post_max_seconds` | `voicePostMaxDuration` (180, `media/audio.go` `MaxAudioSeconds`), composer |
| `limits.voice_comment_max_seconds` | `voiceCommentMaxDuration` (180), comment voice |
| `limits.comment_text_chars` | `commentTextLimit` (1000) |
| `limits.page_size` | `pageSize` (20) |
| `limits.max_mentions` | `mentionLimit` (10) |
| `limits.max_topics` | `topicLimit` (3) |
| `limits.probe_interval_seconds` | `newPostsProbeInterval` (60) |
| `limits.notification_days` | `notificationRetentionDays` (90) |

| File | Change |
| --- | --- |
| `submodules/TelegramCore/Sources/TelegramEngine/Moments/MomentsLimits.swift` | Nested `limits` parser, preference body, recommend query. |
| `submodules/TelegramCore/Sources/TelegramEngine/Moments/TelegramEngineMoments.swift` | Applies the config. `GET`/`PUT /v1/feed/me/preferences`. |
| `submodules/TelegramUI/Components/Moments/Sources/MomentsSettingsController.swift` | Switch and footer, only when the config flag is true. |
| `submodules/TelegramUI/Components/Moments/Sources/MomentsComposerScreen.swift` | Voice posts use `voice_post_max_seconds`. |
| `Telegram/Telegram-iOS/en.lproj/Localizable.strings` | Recommendations, the switch, and its footer. |

## Root tab menu (选单设定) — 2026-11-10

A fresh install shows 动态, 聊天, 设置. Contacts, Calls and News stay off until the person turns them on. Chats and Settings cannot be hidden. The choice is shared account-manager data (`ApplicationSpecificSharedDataKeys.tellomiTabBarPreferences`), the same store as `CallListSettings`, not an account postbox record and not `UserDefaults`. A value saved by the first build in the `app.tellomi.chat.tab-bar` suite is copied in once and then removed. Hiding button titles shortens the phone tab bar; an iPad or vertical bar is unchanged. The bar rebuilds when the switches move.

Hidden tabs are left out of the controller list, the same way Calls is. The phone capsule then hugs those tabs: 90pt for a titled tab, 56pt when titles are hidden. Two titled tabs are 188pt. It still takes the whole width when the leftover would be under 60pt. `tabBarItemsLayout` itself is unchanged and still shares the full length in the horizontal regular case; the phone bar replaces that result.

The screen is an `ItemListController`: Settings → a Tools card → 选单设定. Strings are `presentationData.strings` from `en.lproj` (`Tellomi.MenuSettings.*`). Other languages come from the server langpack. `dictFromLocalization` does not fill them. iMe's public iOS tree (only `master`, pushed 2019-10-31, no tags) does not contain this screen. Swiftgram's tab settings (`CallListSettings.showContactsTab`, `SGSimpleSettings.showTabNames`, `addRootControllers`) are the pattern: optional tabs are left out of the controller list, and chats and settings are always appended. Swiftgram asks for a restart to hide titles. This build applies that immediately. No Swiftgram or iMe source was copied.

| File | Change |
| --- | --- |
| `submodules/TelegramUI/Sources/TelegramRootController.swift` | Builds the root tabs from `tabBarPreferences`. |
| `submodules/TelegramUI/Sources/ApplicationContext.swift` | Follows the shared tab-bar record and keeps the Calls "show tab" switch in step with it. |
| `submodules/TelegramUI/Sources/AppDelegate.swift` | Loads that record with the other shared settings before the root tabs are built. |
| `submodules/TelegramUIPreferences/Sources/PostboxKeys.swift` | `tellomiTabBarPreferences` shared-data key. |
| `submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoScreen.swift` | Settings row that opens the screen. |
| `submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoSettingsItems.swift` | Tools card. |
| `submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoScreenSettingsActions.swift` | Pushes the screen. |
| `submodules/TelegramUI/Components/TabBarComponent/Sources/TabBarComponent.swift` | Hides phone tab titles, shortens the bar, and uses the hugged phone capsule. |
| `submodules/TelegramUI/Components/TabBarLayout/Sources/TellomiTabBarPhoneLayout.swift` | Phone capsule width from the visible tab count. |
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
- Audience reuses `ShareWithPeersScreen` with a mutual-followers category. The row title is `presentationData.strings.Story_Privacy_CategoryMutualFollowers` (`Story.Privacy.CategoryMutualFollowers` in `en.lproj`). Other languages, including 互相关注, come from the server langpack. Story-only rows stay off. Exclude lists stay in the story peer-list cache.
- Gallery media goes through `legacyAssetPickerEnqueueMessages` and tus `POST /v1/feed/media/uploads`.
- A visible video uses `UniversalVideoNode` only when autoplay is on and Reduce Motion is off.
- Comment stickers and GIFs use `StickerPickerScreen` (`hasGifs`) and are uploaded with tus. Likes and poll votes open an `ItemListPeerItem` list filled from `/v1/feed`.
- Feed list endpoints return `{items:[{id,reason}],cursor}`. The client hydrates with `POST /v1/feed/cards`. Notifications use `?tab=interactions|follows|system`. Home tabs are always 推荐 / 关注 / 好友 / 同城 (`recommend`, `following`, `friends`, `nearby`). `GET /v1/capabilities` does not hide 好友. `GET /v1/feed/friends` uses the same cursor as following; following list reasons are `self`, `following` and `repost`, and friends items use `reason=friend`. A failed friends request is an in-feed retry, not a hidden tab. The composer stops at 2000 characters and 12 images. Image `renditions` (largest first) supply the feed bitmap: 1080 for a single image, 360 for a carousel cell, original only in the gallery. A missing tier uses the original key/url. Video cells show `poster`, then `cover_key`. An absolute `url` is used as-is; a key is `media_base_url` + key. ImageIO still downsamples whatever bytes arrive.
- `prepareMediaBase()` emits one `Void` so the requests chained after it actually run.
- There is no city catalog (`/v1/feed/cities` is empty). 同城 is `GET /v1/feed/nearby` with no city picker. A card's city name is shown only when the card includes it.
- Voice posts and voice comments are capped at 180 seconds, unless `limits.voice_post_max_seconds` or `limits.voice_comment_max_seconds` says otherwise.
- Comment stickers and GIFs are uploaded with tus and sent as `{type,key,...}`. They are not Telegram document ids.
- Relative media keys use `media_base_url`, or `https://media.tellomi.app/feed` when that is missing. Absolute https URLs (signed R2) are left as returned. Image versus video follows the card `type`, not the HTTP content-type.

## Moments profile peer open — 2026-11-10

The profile Moments pane opens an author with the same peer navigation the rest of the profile uses. The pane is created in the shared pane container, so that one assignment lives next to the other panes.

| File | Change |
| --- | --- |
| `submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoPaneContainerNode.swift` | Sets `MomentsProfilePaneNode.openPeer` from `ChatControllerInteraction.openPeer`. |

## Moments comment focus and topic screen — 2026-11-10

`ListViewScrollPosition.center` takes `ListViewCenterScrollPositionOverflow`. A focused comment uses `.center(.bottom)`, the same unanimated scroll a chat uses to land on a message. A short row is centered either way; a row taller than the screen keeps its bottom in view. The topic screen is the shared post list with that topic's title, sort and loader. It does not subclass the list.

| File | Change |
| --- | --- |
| `submodules/TelegramUI/Components/Moments/Sources/MomentsDetailScreen.swift` | Comment focus scrolls with `.center(.bottom)`. |
| `submodules/TelegramUI/Components/Moments/Sources/MomentsRouteScreens.swift` | `MomentsTopicScreen` returns the shared post list. |

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
