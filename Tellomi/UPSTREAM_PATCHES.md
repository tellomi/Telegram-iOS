# Upstream patches

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
- Feed list endpoints return `{items:[{id,reason}],cursor}`. The client hydrates with `POST /v1/feed/cards`. Notifications use `?tab=interactions|follows|system`. Top tabs come from config `tabs`. `friends` is still omitted because that path is not an engine endpoint. The composer stops at 500 characters and 10 images.
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
