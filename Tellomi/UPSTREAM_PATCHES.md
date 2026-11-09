# Upstream patches

## Moments feed (动态) — 2026-11-09

Branch `cursor/moments-feed-v1-b405`, based on `de22e3ff` (official restore, PR #138). This is not part of the 14.0.5 release candidate.

The feed is new client code. It does not revive the cancelled Discover/Feed work from iOS PRs #124–#137.

- Root tabs: Contacts, Calls, Moments, Chats, Settings. Search stays the native tab-bar search, with a Moments filter.
- News stays behind `isNewsFeedEnabled` (off while the channel feed API is parked).
- `TelegramEngine.Moments` calls content-engine `/v1/feed`. The host comes only from `help.getAppConfig` (`tellomi_discover_feed_enabled` and `tellomi_discover_feed_base_url`). If either is missing, the tab stays hidden. The bearer token is `discover.getEngineCredential` (`#a80a7f76` / `#0578ccaa`, appended to `swift_scheme.tl` the same way as the other Tellomi constructors) and is sent as `Authorization: Bearer`, refreshed before `expires`. `region` is `cn` or `global` and is not a host. Image URLs are joined onto `media_base_url` from `GET /v1/feed/config`.
- Feed pages, hides, the remembered audience and the one-page cache live in the account Postbox item-cache collection `moments` (id 63), which is cleaned with the rest of the account database.
- Audience reuses `ShareWithPeersScreen` with a mutual-followers category. Story-only rows stay off. Exclude lists stay in the story peer-list cache.
- Gallery media goes through `legacyAssetPickerEnqueueMessages` and tus `POST /v1/feed/media/uploads`.
- A visible video uses `UniversalVideoNode` only when autoplay is on and Reduce Motion is off.
- Comment stickers and GIFs use `StickerPickerScreen` (`hasGifs`). Likes and poll votes open an `ItemListPeerItem` list filled from `/v1/feed`.
