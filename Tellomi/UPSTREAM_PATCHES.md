# Upstream patches

## Moments feed contract, list and comments — 2026-11-10

Branch `cursor/moments-feed-f01-f04-7ea6`, based on `release/ios` (`1d7c541ee9`).

- `POST /v1/feed/posts` is built by `momentsEncodePost`. The body is `kind=post`, `visibility`, `media_keys`, root `city` / `allow_nearby` / `place_id`, `quote_of` and a UUID `client_nonce`. It does not send `media`, `location`, `comment_policy` or `link_preview`. Include and exclude send `audience.audience_token` from `discover.getAudienceToken` (`#dc5213c2` / `#da177181`). A token failure leaves the picked audience in place. The nonce is fixed for retries of that draft.
- Tapping a post body or the comment button presents `MomentsCommentSheet` over the list. Closing it does not push or pop, so the tab and scroll position stay. Tab taps and pager swipes share `commitSelection`. `MomentsDetailScreen` remains the route for profile, search and a post deep link.
- The list loads the next page near the bottom and dedupes by id. Pulling down refreshes from a nil cursor and cancels the previous page request. A failed page can be retried. Following, friends and nearby probe the first page on an interval while the feed is on screen and only raise the new-posts pill. Recommend does not poll. The probe pauses while the feed is off screen or the comment sheet is covering it.
- The comment sheet keeps separate hot and latest cursors, sends `parent_id` for a reply, opens an author from the avatar or name, and long-presses for reply, copy, report and delete where that action is allowed. `canComment` and `commentPolicy` disable the field. The text, reply target and attachment clear only after a successful send. A failed send shows `Moments_Comment_SendFailed`. A failed audience token shows `Moments_Audience_Kept` and leaves the selection in place. Both are read from the strings table. A retry uses the same nonce. Comments that are turned off still use `Moments.Comment.Closed`.

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
