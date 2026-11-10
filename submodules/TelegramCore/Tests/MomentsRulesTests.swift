import XCTest
import Postbox
@testable import TelegramCore

final class MomentsRulesTests: XCTestCase {
    func testAttachmentExclusivity() {
        let limits = MomentsLimits.standard
        var state = MomentsComposerAttachmentState()
        XCTAssertNil(momentsCanAdd(kind: .image, to: state, limits: limits))
        state.imageCount = MomentsLimits.standard.imageLimit
        XCTAssertEqual(momentsCanAdd(kind: .image, to: state, limits: limits), .imageLimit)
        XCTAssertEqual(momentsCanAdd(kind: .video, to: state, limits: limits), .imagesAndVideos)

        state = MomentsComposerAttachmentState(videoCount: 1)
        XCTAssertEqual(momentsCanAdd(kind: .voice, to: state, limits: limits), .voiceWithVideo)
        XCTAssertEqual(momentsCanAdd(kind: .video, to: state, limits: limits, duration: 75), .videoTooLong)
        XCTAssertNil(momentsCanAdd(kind: .video, to: state, limits: limits, duration: 60))

        state = MomentsComposerAttachmentState(hasPoll: true)
        XCTAssertEqual(momentsCanAdd(kind: .image, to: state, limits: limits), .pollWithMedia)

        state = MomentsComposerAttachmentState(hasVoice: true, hasLinkPreview: true)
        XCTAssertTrue(momentsShowsLinkPreview(state))
        state.imageCount = 1
        XCTAssertFalse(momentsShowsLinkPreview(state))
    }

    func testOnlyPublicPostsCanBeReposted() {
        XCTAssertTrue(momentsCanRepostOrQuote(audience: .everyone))
        XCTAssertFalse(momentsCanRepostOrQuote(audience: .mutualFollowers))
        XCTAssertFalse(momentsCanRepostOrQuote(audience: .contacts))
        XCTAssertFalse(momentsCanRepostOrQuote(audience: nil))
    }

    func testFriendsAndNearbyMembership() {
        XCTAssertTrue(momentsBelongsInFriendsFeed(audience: .everyone))
        XCTAssertTrue(momentsBelongsInFriendsFeed(audience: .mutualFollowers))
        XCTAssertFalse(momentsBelongsInFriendsFeed(audience: .contacts))
        XCTAssertFalse(momentsBelongsInFriendsFeed(audience: .closeFriends))
        XCTAssertFalse(momentsBelongsInFriendsFeed(audience: .selected))

        XCTAssertTrue(momentsBelongsInNearbyFeed(audience: .everyone, allowNearby: true))
        XCTAssertFalse(momentsBelongsInNearbyFeed(audience: .everyone, allowNearby: false))
        XCTAssertFalse(momentsBelongsInNearbyFeed(audience: .mutualFollowers, allowNearby: true))
    }

    func testLineFoldAndScan() {
        XCTAssertFalse(momentsTextExceedsLineLimit(fullHeight: 90, lineHeight: 18, limit: 5))
        XCTAssertTrue(momentsTextExceedsLineLimit(fullHeight: 91, lineHeight: 18, limit: 5))
        XCTAssertEqual(momentsRemainingCharacters(count: 1799, limit: 2000, counterFrom: 1800), nil)
        XCTAssertEqual(momentsRemainingCharacters(count: 1800, limit: 2000, counterFrom: 1800), 200)

        let scan = momentsScanText("hi @ada @ada #City https://tell.cc/a https://example.com #x")
        XCTAssertEqual(scan.mentions, ["ada"])
        XCTAssertEqual(scan.topics, ["City"])
        XCTAssertEqual(scan.firstURL, "https://tell.cc/a")
    }

    func testPlaybackIsExclusive() {
        var playback = momentsNextPlayback(current: .none, event: .videoBecameVisible(postId: "a", index: 0))
        XCTAssertEqual(playback, .video(postId: "a", index: 0))
        playback = momentsNextPlayback(current: playback, event: .voiceStarted(postId: "b"))
        XCTAssertEqual(playback, .voice(postId: "b"))
        playback = momentsNextPlayback(current: playback, event: .videoBecameVisible(postId: "c", index: 1))
        XCTAssertEqual(playback, .voice(postId: "b"))
        playback = momentsNextPlayback(current: playback, event: .manualVideo(postId: "c", index: 0))
        XCTAssertEqual(playback, .video(postId: "c", index: 0))
        playback = momentsNextPlayback(current: playback, event: .reduceMotion)
        XCTAssertEqual(playback, .none)
    }

    func testHidesRespectSurface() {
        var hides = MomentsLocalHides()
        hides.mutedAuthors = ["author"]
        hides.hiddenPosts = ["hidden"]
        hides.reportedPosts = ["reported"]
        let author = MomentsAuthor(id: "author", telegramUserId: 1, displayName: "A")
        let muted = MomentsCard(id: "m", author: author)
        let hidden = MomentsCard(id: "hidden", author: MomentsAuthor(id: "other", telegramUserId: 2, displayName: "B"))
        let reported = MomentsCard(id: "reported")
        XCTAssertFalse(hides.allows(muted, surface: .following))
        XCTAssertTrue(hides.allows(muted, surface: .profile))
        XCTAssertFalse(hides.allows(hidden, surface: .recommend))
        XCTAssertTrue(hides.allows(hidden, surface: .search))
        XCTAssertFalse(hides.allows(reported, surface: .profile))
        XCTAssertFalse(hides.allows(reported, surface: .link))
    }

    func testUnavailableCardDropsAuthorAndLinkCardRules() {
        let data = #"{"items":[{"id":"x","state":"unavailable"},{"id":"y","text":"hi","media":[{"type":"image","key":"k"}],"link_preview":{"url":"https://tell.cc"},"location":{"city":"CN:chengdu","distance_band":"1–5 km"},"poll":null}]}"#.data(using: .utf8)!
        let page = momentsPage(data: data)
        XCTAssertEqual(page?.items.count, 2)
        XCTAssertTrue(page?.items[0].isUnavailable == true)
        XCTAssertNil(page?.items[0].author)
        XCTAssertEqual(page?.items[0].text, "")
        XCTAssertNil(page?.items[1].visibleLinkPreview)
        XCTAssertNil(page?.items[1].visibleDistanceBand)
    }

    func testNotificationDefaultsAndLink() {
        let settings = MomentsNotificationSettings.defaults
        XCTAssertTrue(settings.comments && settings.replies && settings.mentions && settings.follows)
        XCTAssertFalse(settings.likes || settings.reposts || settings.newPosts)
        XCTAssertEqual(momentsPostLink(id: "abc"), "https://tell.cc/m#abc")
        XCTAssertEqual(momentsDistanceBandRank("<1 km"), 0)
        XCTAssertEqual(momentsDistanceBandRank(">50 km"), 4)
    }

    func testConfigOverridesAreExplicit() {
        let remote = MomentsRemoteConfig(textLimit: 500, imageLimit: 10, videoMaxDuration: 30)
        let limits = MomentsLimits.standard.applying(config: remote)
        XCTAssertEqual(limits.textLimit, 500)
        XCTAssertEqual(limits.imageLimit, 10)
        XCTAssertEqual(limits.videoMaxDuration, 30)
        XCTAssertEqual(MomentsLimits.standard.voiceMaxDuration, 60)
        XCTAssertEqual(limits.voiceMaxDuration, 60)
        XCTAssertEqual(MomentsLimits.standard.applying(config: MomentsRemoteConfig(voiceMaxDuration: 45)).voiceMaxDuration, 45)
        XCTAssertTrue(limits.newsStaysOff)
        XCTAssertTrue(limits.tabEnabled)
        XCTAssertFalse(MomentsFeedKind.recommend.probesForNewPosts)
        XCTAssertTrue(MomentsFeedKind.following.probesForNewPosts)
    }

    func testFeedOriginComesOnlyFromAppConfig() {
        XCTAssertEqual(momentsFeedEndpoint(appConfiguration: .defaultValue)?.baseURL, momentsProductionFeedBaseURL)
        XCTAssertTrue(isMomentsFeedEnabled(appConfiguration: .defaultValue))

        let disabled = AppConfiguration(data: JSON(dictionary: [
            "tellomi_discover_feed_enabled": false,
            "tellomi_discover_feed_base_url": "https://feed.example"
        ]), hash: 0)
        XCTAssertEqual(momentsFeedEndpoint(appConfiguration: disabled)?.baseURL, "https://feed.example")
        XCTAssertTrue(isMomentsFeedEnabled(appConfiguration: disabled))

        let missingHost = AppConfiguration(data: JSON(dictionary: [
            "tellomi_discover_feed_enabled": true
        ]), hash: 0)
        XCTAssertEqual(momentsFeedEndpoint(appConfiguration: missingHost)?.baseURL, momentsProductionFeedBaseURL)
        XCTAssertTrue(isMomentsFeedEnabled(appConfiguration: missingHost))

        let enabled = AppConfiguration(data: JSON(dictionary: [
            "tellomi_discover_feed_enabled": false,
            "tellomi_discover_feed_base_url": "https://feed.example:8443/"
        ]), hash: 0)
        XCTAssertEqual(momentsFeedEndpoint(appConfiguration: enabled)?.baseURL, "https://feed.example:8443")
        XCTAssertTrue(isMomentsFeedEnabled(appConfiguration: enabled))
    }

    func testFeedOriginRejectsAnythingButAnHttpsHost() {
        XCTAssertEqual(momentsFeedBaseURL("https://feed.example"), "https://feed.example")
        XCTAssertEqual(momentsFeedBaseURL(" https://feed.example:443 "), "https://feed.example:443")
        XCTAssertNil(momentsFeedBaseURL("http://feed.example"))
        XCTAssertNil(momentsFeedBaseURL("https://feed.example/v1/feed"))
        XCTAssertNil(momentsFeedBaseURL("https://feed.example?x=1"))
        XCTAssertNil(momentsFeedBaseURL("https://feed.example#frag"))
        XCTAssertNil(momentsFeedBaseURL("https://user:pass@feed.example"))
        XCTAssertNil(momentsFeedBaseURL("cn"))
        XCTAssertNil(momentsFeedBaseURL("global"))
        XCTAssertNil(momentsFeedBaseURL("https://cn"))
        XCTAssertNil(momentsFeedBaseURL("https://global"))
        XCTAssertNil(momentsFeedBaseURL(""))
    }

    func testMediaUrlsComeFromConfigBase() {
        XCTAssertEqual(momentsMediaURL(base: "https://cdn.example/media/", key: "a/b.jpg"), "https://cdn.example/media/a/b.jpg")
        XCTAssertEqual(momentsMediaURL(base: "https://cdn.example", key: "https://other.example/a.jpg"), "https://other.example/a.jpg")
        XCTAssertEqual(momentsMediaURL(base: nil, key: "a/b.jpg"), "https://media.tellomi.app/feed/a/b.jpg")
        XCTAssertEqual(momentsMediaURL(base: "http://cdn.example", key: "a/b.jpg"), "https://media.tellomi.app/feed/a/b.jpg")
        XCTAssertNil(momentsMediaURL(base: momentsPublicMediaBaseURL, key: "http://cdn.example/a.jpg"))
        let signed = "https://r2.example/obj?X-Amz-Signature=abc"
        XCTAssertEqual(momentsMediaURL(base: momentsPublicMediaBaseURL, key: signed), signed)
        XCTAssertTrue(momentsPresentsAsVideo(.video))
        XCTAssertTrue(momentsPresentsAsVideo(.gif))
        XCTAssertTrue(momentsPresentsAsImage(.image))
        XCTAssertTrue(momentsPresentsAsImage(.sticker))
        XCTAssertFalse(momentsPresentsAsVideo(.image))
        XCTAssertEqual(momentsPlaybackMimeType(.video), "video/mp4")
        XCTAssertEqual(momentsPlaybackFileName(.image), "media.jpg")

        let raw = #"{"media_base_url":"https://cdn.example/media/"}"#.data(using: .utf8)!
        XCTAssertEqual(momentsConfigMediaBase(raw), "https://cdn.example/media")
        let page = #"{"items":[{"id":"p","media":[{"type":"image","key":"pic.jpg"}]}]}"#.data(using: .utf8)!
        let card = momentsPage(data: page, mediaBaseURL: momentsConfigMediaBase(raw))?.items.first
        XCTAssertEqual(card?.media.first?.remoteURL, "https://cdn.example/media/pic.jpg")
    }

    func testCredentialRefreshesBeforeExpiryAndKeepsRegionOffTheHost() {
        let credential = MomentsCredential(token: "abc", baseURL: "https://feed.example", expiresAt: 1_000, region: "cn")
        XCTAssertFalse(credential.needsRefresh(now: 1_000 - MomentsCredential.refreshMargin - 1))
        XCTAssertTrue(credential.needsRefresh(now: 1_000 - MomentsCredential.refreshMargin))
        XCTAssertEqual(credential.region, "cn")
        XCTAssertNotEqual(credential.baseURL, credential.region)
        XCTAssertTrue(MomentsCredential(token: "abc", baseURL: "https://feed.example", expiresAt: nil, region: "global").needsRefresh(now: 0))
    }

    func testAudienceMapsOntoStoryPrivacy() {
        let everyone = momentsAudience(from: EngineStoryPrivacy(base: .everyone, additionallyIncludePeers: [PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(7))]))
        XCTAssertEqual(everyone.kind, .everyone)
        XCTAssertEqual(everyone.exclude, [7])
        let selected = momentsStoryPrivacy(MomentsAudience(kind: .selected, include: [9]))
        XCTAssertEqual(selected.base, .nobody)
        XCTAssertEqual(selected.additionallyIncludePeers.map { $0.toInt64() }, [9])
        XCTAssertEqual(momentsAudience(from: EngineStoryPrivacy(base: .mutualFollowers, additionallyIncludePeers: [])).kind, .mutualFollowers)
    }

    func testTusUploadKeyAndMetadata() {
        let metadata = momentsTusUploadMetadata(filename: "a.jpg", mimeType: "image/jpeg")
        XCTAssertTrue(metadata.hasPrefix("filename "))
        XCTAssertTrue(metadata.contains("filetype "))
        let body = #"{"key":"media/1"}"#.data(using: .utf8)!
        XCTAssertEqual(momentsMediaUploadKey(body: body, headerFields: [:], location: nil), "media/1")
        let headers: [AnyHashable: Any] = ["Upload-Key": "abc"]
        XCTAssertEqual(momentsMediaUploadKey(body: Data(), headerFields: headers, location: nil), "abc")
        XCTAssertEqual(momentsMediaUploadKey(body: Data(), headerFields: [:], location: "https://feed.example/v1/feed/media/uploads/xyz"), "xyz")
        XCTAssertEqual(momentsResolvedUploadLocation(base: "https://feed.example", location: "/v1/feed/media/uploads/xyz"), "https://feed.example/v1/feed/media/uploads/xyz")
        XCTAssertNil(momentsResolvedUploadLocation(base: "https://feed.example", location: "http://other.example/x"))
    }

    func testFeedListIsIdsUntilCardsHydrate() {
        let raw = #"{"items":[{"id":"a","reason":"recommend"},{"id":"b","reason":"following"}],"cursor":"n"}"#.data(using: .utf8)!
        let page = momentsFeedRefPage(data: raw)
        XCTAssertEqual(page?.ids, ["a", "b"])
        XCTAssertEqual(page?.cursor, "n")
        XCTAssertEqual(momentsCapabilityTabs(#"{"tabs":["recommend","friends","following"]}"#.data(using: .utf8)!), ["recommend", "following"])
    }

    func testProdCardsUnwrapAndLastPageDoesNotDuplicate() {
        let recommend = #"{"items":[{"id":"p1","reason":"recommend"},{"id":"p2","reason":"hot"}],"cursor":"c1"}"#.data(using: .utf8)!
        let refs = momentsFeedRefPage(data: recommend)
        XCTAssertEqual(refs?.ids, ["p1", "p2"])
        let cards = #"{"items":[{"id":"p1","card":{"id":"p1","text":"hello from prod","author":{"id":"a1","name":"Ada","user_id":7},"counts":{"likes":4,"comments":2,"reposts":1},"created_at":1700000000,"media":[{"type":"image","key":"pic","url":"https://media.tellomi.app/feed/pic"}],"viewer":{"liked":true,"following":true}}},{"id":"missing","reason":"hot"}]}"#.data(using: .utf8)!
        let hydrated = momentsHydratedCards(ids: refs?.ids ?? [], cardsData: cards, mediaBaseURL: "https://media.tellomi.app/feed")
        XCTAssertEqual(hydrated.count, 2)
        XCTAssertEqual(hydrated[0].text, "hello from prod")
        XCTAssertEqual(hydrated[0].author?.displayName, "Ada")
        XCTAssertEqual(hydrated[0].author?.telegramUserId, 7)
        XCTAssertTrue(hydrated[0].author?.followed == true)
        XCTAssertEqual(hydrated[0].counts.likes, 4)
        XCTAssertEqual(hydrated[0].counts.comments, 2)
        XCTAssertTrue(hydrated[0].viewer.liked)
        XCTAssertEqual(hydrated[0].media.first?.remoteURL, "https://media.tellomi.app/feed/pic")
        XCTAssertFalse(hydrated[0].isUnavailable)
        XCTAssertTrue(hydrated[1].isUnavailable)
        XCTAssertEqual(hydrated[1].text, "")

        let first = momentsMergeFeed(existing: [], pageItems: hydrated, cursor: "c1", refreshing: true)
        XCTAssertEqual(first.items.map(\.id), ["p1", "p2"])
        XCTAssertEqual(first.cursor, "c1")
        let repeated = momentsMergeFeed(existing: first.items, pageItems: hydrated, cursor: "c1", refreshing: false)
        XCTAssertEqual(repeated.items.map(\.id), ["p1", "p2"])
        let last = momentsMergeFeed(existing: first.items, pageItems: [], cursor: nil, refreshing: false)
        XCTAssertEqual(last.items.map(\.id), ["p1", "p2"])
        XCTAssertNil(last.cursor)

        let same = momentsListEdit(previousIds: ["p1", "p2"], nextIds: ["p1", "p2"])
        XCTAssertTrue(same.deletes.isEmpty)
        XCTAssertEqual(same.updates, [0, 1])
        let replaced = momentsListEdit(previousIds: ["status"], nextIds: ["p1", "p2"])
        XCTAssertEqual(replaced.deletes, [0])
        XCTAssertEqual(replaced.inserts, [0, 1])
        XCTAssertTrue(replaced.deletes.allSatisfy { $0 < 1 })
        let appended = momentsListEdit(previousIds: ["p1", "p2"], nextIds: ["p1", "p2", "p3"])
        XCTAssertTrue(appended.deletes.isEmpty)
        XCTAssertEqual(appended.inserts, [2])
        let firstPage = momentsListEdit(previousIds: [], nextIds: ["p1", "p2", "p3"])
        XCTAssertTrue(firstPage.deletes.isEmpty)
        XCTAssertEqual(firstPage.inserts, [0, 1, 2])
        var count = 0
        for index in firstPage.inserts {
            XCTAssertLessThanOrEqual(index, count)
            count += 1
        }
        let switched = momentsListEdit(previousIds: ["a", "b", "c"], nextIds: ["a", "d", "c"])
        XCTAssertEqual(switched.deletes, [1])
        XCTAssertEqual(switched.inserts, [1])
        XCTAssertEqual(momentsChangedRowIndexes(previous: ["a:0", "b:0", "c:0"], next: ["a:0", "b:1", "c:0"]), [1])
        XCTAssertTrue(momentsChangedRowIndexes(previous: ["a:0", "b:0"], next: ["a:0", "b:0"]).isEmpty)
    }

    func testDouyinCommentThreadContract() {
        let raw = #"{"comments":[{"id":"c1","state":"published","is_author":true,"reply_count":2,"card":{"kind":"comment","text":"hello","root_id":"p1","author":{"id":"a1","display_name":"Ada","handle":"ada","avatar_key":"av"},"ip_region_label":"陕西","media":[{"type":"image","key":"pic","w":64,"h":64}]},"stats":{"likes":3,"comments":2,"reposts":0},"me":{"liked":true,"disliked":false,"author":false}}],"total":12}"#.data(using: .utf8)!
        let page = momentsCommentPage(data: raw, mediaBaseURL: "https://media.tellomi.app/feed")
        XCTAssertEqual(page.total, 12)
        XCTAssertEqual(page.comments.count, 1)
        let comment = page.comments[0]
        XCTAssertEqual(comment.text, "hello")
        XCTAssertTrue(comment.isAuthor)
        XCTAssertEqual(comment.ipRegionLabel, "陕西")
        XCTAssertEqual(comment.likeCount, 3)
        XCTAssertTrue(comment.liked)
        XCTAssertFalse(comment.disliked)
        XCTAssertEqual(comment.replyCount, 2)
        XCTAssertEqual(comment.author?.displayName, "Ada")
        XCTAssertEqual(comment.author?.avatarKey, "https://media.tellomi.app/feed/av")
        XCTAssertEqual(comment.attachment?.type, .image)
        XCTAssertEqual(comment.attachment?.remoteURL, "https://media.tellomi.app/feed/pic")

        let replies = #"{"replies":[{"id":"r1","reply_count":0,"card":{"text":"back","parent_id":"c1","reply_to":{"id":"a1","display_name":"Ada","handle":"ada"},"author":{"id":"a2","display_name":"Bo"}}}],"total":2,"cursor":"n1"}"#.data(using: .utf8)!
        let replyPage = momentsReplyPage(data: replies, rootId: "c1", mediaBaseURL: nil)
        XCTAssertEqual(replyPage.total, 2)
        XCTAssertEqual(replyPage.cursor, "n1")
        XCTAssertEqual(replyPage.replies.first?.text, "back")
        XCTAssertEqual(replyPage.replies.first?.replyToName, "Ada")
    }

    func testDraftCapKeepsNewest() {
        let kept = momentsTrimDrafts([1, 2, 3, 4], limit: 2, newer: >)
        XCTAssertEqual(kept, [4, 3])
    }
}
