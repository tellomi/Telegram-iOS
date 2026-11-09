# Upstream patches

## Moments feed (动态) — 2026-11-09

Branch `cursor/moments-feed-v1-b405`, based on `de22e3ff` (official restore, PR #138). This is not part of the 14.0.5 release candidate.

The feed is new client code. It does not revive the cancelled Discover/Feed work from iOS PRs #124–#137.

- Root tabs: Contacts, Calls, Moments, Chats, Settings. Search stays the native tab-bar search, with a Moments filter.
- News stays behind `isNewsFeedEnabled` (off while the channel feed API is parked).
- `TelegramEngine.Moments` calls content-engine `/v1/feed` with a bearer token. `discover.getEngineCredential` is not in the layer-232 schema, so the token is installed from app config (`moments_engine_base_url`, `moments_engine_token`) until that MTProto method exists.
- Feed pages, hides and the one-page cache live in the account Postbox item-cache collection `moments` (id 63), which is cleaned with the rest of the account database.
