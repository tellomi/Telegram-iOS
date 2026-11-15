import XCTest
import Postbox
import SwiftSignalKit
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
        XCTAssertEqual(MomentsLimits.standard.textLimit, 2000)
        XCTAssertEqual(MomentsLimits.standard.imageLimit, 12)
        XCTAssertEqual(MomentsLimits.standard.videoLimit, 3)
        XCTAssertEqual(MomentsLimits.standard.videoMaxDuration, 60)
        XCTAssertEqual(MomentsLimits.standard.voicePostMaxDuration, 180)
        XCTAssertEqual(MomentsLimits.standard.voiceCommentMaxDuration, 180)
        XCTAssertEqual(MomentsLimits.standard.commentTextLimit, 1000)
        XCTAssertEqual(MomentsLimits.standard.pageSize, 20)
        XCTAssertEqual(MomentsLimits.standard.mentionLimit, 10)
        XCTAssertEqual(MomentsLimits.standard.topicLimit, 3)
        XCTAssertEqual(MomentsLimits.standard.newPostsProbeInterval, 60)
        XCTAssertEqual(MomentsLimits.standard.notificationRetentionDays, 90)
        XCTAssertEqual(limits.voicePostMaxDuration, 180)
        XCTAssertEqual(limits.voiceCommentMaxDuration, 180)
        let voiced = MomentsLimits.standard.applying(config: MomentsRemoteConfig(voicePostMaxDuration: 45, voiceCommentMaxDuration: 12))
        XCTAssertEqual(voiced.voicePostMaxDuration, 45)
        XCTAssertEqual(voiced.voiceCommentMaxDuration, 12)
        XCTAssertEqual(MomentsLimits.standard.applying(config: MomentsRemoteConfig(textLimit: 0, voicePostMaxDuration: -3, pageSize: 0)).textLimit, 2000)
        XCTAssertEqual(MomentsLimits.standard.applying(config: MomentsRemoteConfig(textLimit: 0, voicePostMaxDuration: -3, pageSize: 0)).voicePostMaxDuration, 180)
        XCTAssertEqual(MomentsLimits.standard.applying(config: MomentsRemoteConfig(textLimit: 0, voicePostMaxDuration: -3, pageSize: 0)).pageSize, 20)
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
        XCTAssertEqual(momentsCapabilityTabs(#"{"tabs":["recommend","friends","following"]}"#.data(using: .utf8)!), ["recommend", "friends", "following"])
        let following = #"{"items":[{"id":"a","reason":"following"},{"id":"b","reason":"friend"},{"id":"c","reason":"repost"},{"id":"d","reason":"self"}],"cursor":"n"}"#.data(using: .utf8)!
        XCTAssertEqual(momentsFeedRefPage(data: following, kind: .following)?.ids, ["a", "c", "d"])
        let friends = #"{"items":[{"id":"a","reason":"following"},{"id":"b","reason":"friend"}],"cursor":"f"}"#.data(using: .utf8)!
        XCTAssertEqual(momentsFeedRefPage(data: friends, kind: .friends)?.ids, ["b"])
        XCTAssertEqual(momentsVisibleFeedTabs(configTabs: ["recommend", "following"]), ["recommend", "following", "friends", "nearby"])
        XCTAssertEqual(momentsVisibleFeedTabs(configTabs: ["recommend", "following", "friends", "nearby"]), ["recommend", "following", "friends", "nearby"])
    }

    func testDisplayRenditions() {
        let base = "https://media.tellomi.app/feed"
        let imageJSON = #"{"type":"image","key":"orig.jpg","url":"https://cdn.example/orig.jpg","w":3000,"h":2000,"renditions":[{"key":"r1080.jpg","w":1080,"h":720},{"key":"r360.jpg","url":"https://cdn.example/r360.jpg","w":360,"h":240}]}"#
        let image = momentsMedia(try! JSONSerialization.jsonObject(with: imageJSON.data(using: .utf8)!) as! [String: Any], mediaBaseURL: base)!
        XCTAssertEqual(image.remoteURL, "https://cdn.example/orig.jpg")
        XCTAssertEqual(momentsFeedImageURL(image, targetPixels: momentsSingleImagePixels), "\(base)/r1080.jpg")
        XCTAssertEqual(momentsFeedImageURL(image, targetPixels: momentsCarouselImagePixels), "https://cdn.example/r360.jpg")
        XCTAssertEqual(momentsFeedImageTargetPixels(slideCount: 1), 1080)
        XCTAssertEqual(momentsFeedImageTargetPixels(slideCount: 3), 360)

        let onlySmallJSON = #"{"type":"image","key":"orig.jpg","w":2000,"h":2000,"renditions":[{"key":"r360.jpg","w":360,"h":360}]}"#
        let onlySmall = momentsMedia(try! JSONSerialization.jsonObject(with: onlySmallJSON.data(using: .utf8)!) as! [String: Any], mediaBaseURL: base)!
        XCTAssertEqual(momentsFeedImageURL(onlySmall, targetPixels: 1080), "\(base)/orig.jpg")
        XCTAssertEqual(momentsFeedImageURL(onlySmall, targetPixels: 360), "\(base)/r360.jpg")

        let plainJSON = #"{"type":"image","key":"orig.jpg","url":"https://cdn.example/orig.jpg"}"#
        let plain = momentsMedia(try! JSONSerialization.jsonObject(with: plainJSON.data(using: .utf8)!) as! [String: Any], mediaBaseURL: base)!
        XCTAssertEqual(momentsFeedImageURL(plain, targetPixels: 1080), "https://cdn.example/orig.jpg")

        let posterJSON = #"{"type":"video","key":"v.mp4","url":"https://cdn.example/v.mp4","cover_key":"cover.jpg","poster":{"key":"poster.jpg","w":1080,"h":720}}"#
        let video = momentsMedia(try! JSONSerialization.jsonObject(with: posterJSON.data(using: .utf8)!) as! [String: Any], mediaBaseURL: base)!
        XCTAssertEqual(video.remoteURL, "https://cdn.example/v.mp4")
        XCTAssertEqual(momentsVideoPosterURL(video), "\(base)/poster.jpg")
        XCTAssertNil(momentsFeedImageURL(video, targetPixels: 1080))

        let coverJSON = #"{"type":"video","key":"v.mp4","cover_key":"cover.jpg"}"#
        let cover = momentsMedia(try! JSONSerialization.jsonObject(with: coverJSON.data(using: .utf8)!) as! [String: Any], mediaBaseURL: base)!
        XCTAssertEqual(momentsVideoPosterURL(cover), "\(base)/cover.jpg")
        XCTAssertEqual(cover.remoteURL, "\(base)/v.mp4")

        let bareJSON = #"{"type":"video","key":"v.mp4","url":"https://cdn.example/v.mp4"}"#
        let bare = momentsMedia(try! JSONSerialization.jsonObject(with: bareJSON.data(using: .utf8)!) as! [String: Any], mediaBaseURL: base)!
        XCTAssertNil(momentsVideoPosterURL(bare))
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
        XCTAssertFalse(comment.viewerAuthored)
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

    func testPostRequestMatchesContentEngine() {
        let nonce = "11111111-1111-4111-8111-111111111111"
        let text = momentsTestPost(text: "hello", nonce: nonce)
        let textBody = momentsTestReady(momentsEncodePost(text, audienceToken: nil))
        XCTAssertEqual(textBody["kind"] as? String, "post")
        XCTAssertEqual(textBody["text"] as? String, "hello")
        XCTAssertEqual(textBody["visibility"] as? String, "public")
        XCTAssertEqual(textBody["client_nonce"] as? String, nonce)
        XCTAssertEqual(Set(textBody.keys), ["kind", "text", "visibility", "client_nonce"])
        momentsAssertNoLegacyPostKeys(textBody)

        let images = momentsTestPost(text: "", mediaKeys: ["m/a", "m/b", "m/c"], nonce: nonce)
        let imageBody = momentsTestReady(momentsEncodePost(images, audienceToken: nil))
        XCTAssertNil(imageBody["text"])
        XCTAssertEqual(imageBody["media_keys"] as? [String], ["m/a", "m/b", "m/c"])
        XCTAssertNil(imageBody["media"])

        let video = momentsTestPost(text: "clip", mediaKeys: ["m/video"], nonce: nonce)
        let videoBody = momentsTestReady(momentsEncodePost(video, audienceToken: nil))
        XCTAssertEqual(videoBody["media_keys"] as? [String], ["m/video"])
        XCTAssertNil(videoBody["media"])

        let nearby = momentsTestPost(text: "here", allowNearby: true, city: "cn:chengdu", placeId: "poi-1", nonce: nonce)
        let nearbyBody = momentsTestReady(momentsEncodePost(nearby, audienceToken: nil))
        XCTAssertEqual(nearbyBody["visibility"] as? String, "public")
        XCTAssertEqual(nearbyBody["allow_nearby"] as? Bool, true)
        XCTAssertEqual(nearbyBody["city"] as? String, "cn:chengdu")
        XCTAssertEqual(nearbyBody["place_id"] as? String, "poi-1")
        XCTAssertNil(nearbyBody["location"])

        let contacts = momentsTestPost(text: "contacts", audience: MomentsAudience(kind: .contacts), allowNearby: true, nonce: nonce)
        let contactsBody = momentsTestReady(momentsEncodePost(contacts, audienceToken: nil))
        XCTAssertEqual(contactsBody["visibility"] as? String, "contacts")
        XCTAssertNil(contactsBody["audience"])
        XCTAssertNil(contactsBody["allow_nearby"])

        let close = momentsTestPost(text: "close", audience: MomentsAudience(kind: .closeFriends), nonce: nonce)
        XCTAssertEqual(momentsTestReady(momentsEncodePost(close, audienceToken: nil))["visibility"] as? String, "close_friends")

        let friends = momentsTestPost(text: "friends", audience: MomentsAudience(kind: .mutualFollowers), nonce: nonce)
        XCTAssertEqual(momentsTestReady(momentsEncodePost(friends, audienceToken: nil))["visibility"] as? String, "friends")

        let selected = MomentsAudience(kind: .selected, include: [3, 4])
        let selectedDraft = momentsTestPost(text: "picked", audience: selected, nonce: nonce)
        guard case let .success(.needsAudienceToken(kind, userIds)) = momentsEncodePost(selectedDraft, audienceToken: nil) else {
            return XCTFail("selected people need a token")
        }
        XCTAssertEqual(kind, "include")
        XCTAssertEqual(userIds, [3, 4])
        let selectedBody = momentsTestReady(momentsEncodePost(selectedDraft, audienceToken: "signed-include"))
        XCTAssertEqual(selectedBody["visibility"] as? String, "include")
        XCTAssertEqual((selectedBody["audience"] as? [String: Any])?["audience_token"] as? String, "signed-include")
        XCTAssertNil(selectedBody["include"])
        XCTAssertNotEqual(selectedBody["visibility"] as? String, "public")
        XCTAssertEqual(momentsAudienceKeptAfterTokenFailure(selected), selected)

        let excluded = MomentsAudience(kind: .everyone, exclude: [8])
        let excludedDraft = momentsTestPost(text: "hidden", audience: excluded, nonce: nonce)
        guard case let .success(.needsAudienceToken(excludeKind, excludeIds)) = momentsEncodePost(excludedDraft, audienceToken: nil) else {
            return XCTFail("excluded people need a token")
        }
        XCTAssertEqual(excludeKind, "exclude")
        XCTAssertEqual(excludeIds, [8])
        let excludedBody = momentsTestReady(momentsEncodePost(excludedDraft, audienceToken: "signed-exclude"))
        XCTAssertEqual(excludedBody["visibility"] as? String, "exclude")
        XCTAssertEqual((excludedBody["audience"] as? [String: Any])?["audience_token"] as? String, "signed-exclude")
        XCTAssertNotEqual(excludedBody["visibility"] as? String, "public")
        XCTAssertEqual(momentsAudienceKeptAfterTokenFailure(excluded), excluded)

        let contactsExcept = momentsTestPost(text: "no", audience: MomentsAudience(kind: .contacts, exclude: [9]), nonce: nonce)
        guard case .failure(.audienceNotRepresentable) = momentsEncodePost(contactsExcept, audienceToken: "token") else {
            return XCTFail("contacts plus an exclude list must not be published")
        }

        let quote = momentsTestPost(text: "quoting", quoteOf: "quoted-id", nonce: nonce)
        XCTAssertEqual(momentsTestReady(momentsEncodePost(quote, audienceToken: nil))["quote_of"] as? String, "quoted-id")

        let again = momentsTestReady(momentsEncodePost(text, audienceToken: nil))
        XCTAssertEqual(again["client_nonce"] as? String, nonce)
        guard case .failure(.invalidClientNonce) = momentsEncodePost(momentsTestPost(text: "x", nonce: "not-a-uuid"), audienceToken: nil) else {
            return XCTFail("nonce must be a UUID")
        }
        guard case .failure(.audienceTokenRequired) = momentsEncodePost(momentsTestPost(text: "nobody", audience: MomentsAudience(kind: .selected), nonce: nonce), audienceToken: nil) else {
            return XCTFail("an empty include list is not public")
        }
    }

    func testCommentSendKeepsDraftAndNonceOnFailure() {
        let nonce = "22222222-2222-4222-8222-222222222222"
        let other = "33333333-3333-4333-8333-333333333333"
        let first = momentsCommentComposerForSend(previous: MomentsCommentComposerState(), text: "hello", parentId: "parent-1", mediaKey: "m/voice", sticker: false, makeNonce: { nonce })
        let retry = momentsCommentComposerForSend(previous: first, text: "hello", parentId: "parent-1", mediaKey: "m/voice", sticker: false, makeNonce: { other })
        XCTAssertEqual(retry.clientNonce, nonce)
        let kept = momentsCommentComposerAfterFailure(retry)
        XCTAssertEqual(kept, retry)
        XCTAssertEqual(kept.text, "hello")
        XCTAssertEqual(kept.parentId, "parent-1")
        XCTAssertEqual(kept.mediaKey, "m/voice")
        let body = try! momentsEncodeComment(kept).get()
        XCTAssertEqual(body["text"] as? String, "hello")
        XCTAssertEqual(body["parent_id"] as? String, "parent-1")
        XCTAssertEqual(body["media_keys"] as? [String], ["m/voice"])
        XCTAssertEqual(body["client_nonce"] as? String, nonce)
        XCTAssertNil(body["sticker"])
        let sticker = momentsCommentComposerForSend(previous: MomentsCommentComposerState(), text: "", parentId: nil, mediaKey: "m/sticker", sticker: true, makeNonce: { nonce })
        let stickerBody = try! momentsEncodeComment(sticker).get()
        XCTAssertEqual(stickerBody["sticker"] as? Bool, true)
        XCTAssertNil(stickerBody["text"])
        let edited = momentsCommentComposerForSend(previous: kept, text: "hello!", parentId: "parent-1", mediaKey: "m/voice", sticker: false, makeNonce: { other })
        XCTAssertEqual(edited.clientNonce, other)
        let cleared = momentsCommentComposerAfterSuccess()
        XCTAssertEqual(cleared.text, "")
        XCTAssertNil(cleared.parentId)
        XCTAssertNil(cleared.mediaKey)
        XCTAssertNotEqual(cleared.clientNonce, nonce)
        guard case .failure(.invalidClientNonce) = momentsEncodeComment(MomentsCommentComposerState(text: "x", clientNonce: "bad")) else {
            return XCTFail("a comment nonce has to be a UUID")
        }
    }

    func testFeedPagingProbeAndCommentCursors() {
        XCTAssertFalse(momentsShouldLoadFeedPage(loaded: true, cursor: nil, refresh: false, loading: false))
        XCTAssertFalse(momentsShouldLoadFeedPage(loaded: false, cursor: nil, refresh: false, loading: true))
        XCTAssertTrue(momentsShouldLoadFeedPage(loaded: true, cursor: nil, refresh: true, loading: false))
        XCTAssertTrue(momentsShouldLoadFeedPage(loaded: true, cursor: "next", refresh: false, loading: false))
        XCTAssertTrue(momentsProfilePaneReadyAtInit())
        XCTAssertEqual(momentsProfilePostsState(itemCount: 0, loading: true, loaded: false, failed: false), .loading)
        XCTAssertEqual(momentsProfilePostsState(itemCount: 0, loading: false, loaded: false, failed: false), .loading)
        XCTAssertEqual(momentsProfilePostsState(itemCount: 0, loading: false, loaded: true, failed: true), .failed)
        XCTAssertEqual(momentsProfilePostsState(itemCount: 0, loading: false, loaded: true, failed: false), .empty)
        XCTAssertEqual(momentsProfilePostsState(itemCount: 2, loading: true, loaded: false, failed: false), .posts)
        XCTAssertFalse(momentsFeedShouldProbe(kind: .recommend, screenVisible: true))
        XCTAssertTrue(momentsFeedShouldProbe(kind: .following, screenVisible: true))
        XCTAssertTrue(momentsFeedShouldProbe(kind: .friends, screenVisible: true))
        XCTAssertTrue(momentsFeedShouldProbe(kind: .nearby, screenVisible: true))
        XCTAssertFalse(momentsFeedShouldProbe(kind: .following, screenVisible: false))
        XCTAssertEqual(momentsUnseenHeadCount(visibleIds: ["a", "b"], probedIds: ["n1", "n2", "a", "b"]), 2)
        XCTAssertEqual(momentsUnseenHeadCount(visibleIds: ["a"], probedIds: ["a", "n1"]), 0)
        XCTAssertEqual(momentsUnseenHeadCount(visibleIds: ["a"], probedIds: ["n1", "n1", "a"]), 1)

        var cursors = MomentsCommentCursors()
        cursors = cursors.storing(sort: "hot", cursor: "hot-1")
        cursors = cursors.storing(sort: "latest", cursor: "new-1")
        XCTAssertEqual(cursors.cursor(sort: "hot"), "hot-1")
        XCTAssertEqual(cursors.cursor(sort: "latest"), "new-1")
        cursors = cursors.storing(sort: "hot", cursor: "hot-2")
        XCTAssertEqual(cursors.cursor(sort: "latest"), "new-1")
        XCTAssertNil(cursors.storing(sort: "latest", cursor: "").cursor(sort: "latest"))

        let refreshed = momentsMergeFeed(existing: [MomentsCard(id: "old")], pageItems: [MomentsCard(id: "new"), MomentsCard(id: "new")], cursor: nil, refreshing: true)
        XCTAssertEqual(refreshed.items.map(\.id), ["new"])
        XCTAssertNil(refreshed.cursor)
        let appended = momentsMergeFeed(existing: refreshed.items, pageItems: [MomentsCard(id: "new"), MomentsCard(id: "next")], cursor: "c2", refreshing: false)
        XCTAssertEqual(appended.items.map(\.id), ["new", "next"])

        let grant = MomentsAudienceGrant(token: "t", expiresAt: 1_000)
        XCTAssertFalse(grant.needsRefresh(now: 1_000 - MomentsCredential.refreshMargin - 1))
        XCTAssertTrue(grant.needsRefresh(now: 1_000 - MomentsCredential.refreshMargin))
    }

    func testSearchGenerationDropsAStaleResponse() {
        var generation = MomentsQueryGeneration()
        let first = generation.begin()
        let second = generation.begin()
        XCTAssertFalse(momentsSearchResultApplies(responseGeneration: first, latestGeneration: generation.current))
        XCTAssertTrue(generation.accepts(second))
        XCTAssertFalse(generation.accepts(first))
        XCTAssertFalse(MomentsQueryGeneration().accepts(0))
    }

    func testTopicAndNotificationBackRestoreTheList() {
        let topic = MomentsFeedPlace.topic(name: "City", offset: 240)
        XCTAssertEqual(momentsFeedPlaceAfterBack([topic, .post(id: "p")]), topic)
        XCTAssertEqual(momentsFeedPlaceAfterBack([topic, .media(postId: "p", index: 2)]), topic)
        XCTAssertEqual(momentsFeedPlaceAfterBack([topic, .author(telegramUserId: 7)]), topic)
        XCTAssertTrue(momentsListAnchorSurvives([topic, .post(id: "p")]))
        XCTAssertTrue(momentsListAnchorSurvives([topic, .media(postId: "p", index: 1)]))
        XCTAssertTrue(momentsListAnchorSurvives([topic, .author(telegramUserId: 7)]))
        XCTAssertTrue(momentsListAnchorSurvives([topic, .topic(name: "Next", offset: 0)]))
        XCTAssertFalse(momentsListAnchorSurvives([topic]))

        let notices = MomentsFeedPlace.notifications(filter: "interactions", offset: 96)
        XCTAssertEqual(momentsFeedPlaceAfterBack([notices, .post(id: "p")]), notices)
        let follows = MomentsFeedPlace.notifications(filter: "follows", offset: 40)
        XCTAssertEqual(momentsFeedPlaceAfterBack([follows, .author(telegramUserId: 3)]), follows)
        XCTAssertFalse(momentsListAnchorSurvives([notices, .following(profileId: "1", offset: 0)]))
    }

    func testNotificationDestinationAndCommentFocus() {
        let like = MomentsNotification(id: "n", kind: .like, postId: "p", commentId: "c")
        XCTAssertEqual(momentsNotificationDestination(like), .post(id: "p", commentId: "c"))
        let gone = MomentsNotification(id: "n2", kind: .comment, postId: "p", unavailable: true)
        XCTAssertEqual(momentsNotificationDestination(gone), .unavailable)
        XCTAssertEqual(momentsNotificationDestination(MomentsNotification(id: "n3", kind: .like)), .unavailable)
        let follow = MomentsNotification(id: "n4", kind: .follow, actors: [MomentsAuthor(id: "a", telegramUserId: 9, displayName: "A")])
        XCTAssertEqual(momentsNotificationDestination(follow), .peer(telegramUserId: 9))
        XCTAssertEqual(momentsNotificationDestination(MomentsNotification(id: "n5", kind: .follow)), .unavailable)
        XCTAssertEqual(momentsTopicName(" #City "), "City")
        XCTAssertNil(momentsTopicName(" # "))

        let reply = MomentsReply(id: "r1", postId: "p", rootId: "c1", text: "re")
        let comment = MomentsComment(id: "c1", postId: "p", text: "hi", replies: [reply])
        XCTAssertEqual(momentsCommentFocus(commentId: "r1", comments: [comment]), .located(id: "r1"))
        XCTAssertEqual(momentsCommentFocus(commentId: "gone", comments: [comment]), .missing)
        XCTAssertNil(momentsCommentFocus(commentId: nil, comments: [comment]))
        XCTAssertEqual(momentsNotificationReadBody(tab: nil), [:])
        XCTAssertEqual(momentsNotificationReadBody(tab: "follows"), ["tab": "follows"])
        XCTAssertEqual(momentsNotificationReadBody(tab: "  "), [:])
    }

    func testPeopleListParsesVisibilityAndCursor() {
        let hidden = #"{"error":"list_private"}"#.data(using: .utf8)!
        XCTAssertEqual(momentsPeopleListError(data: hidden), .listPrivate)
        XCTAssertEqual(momentsListLoadResult(.listPrivate), .hidden)
        XCTAssertEqual(momentsListLoadResult(.cancelled), .ignore)
        let page = #"{"items":[{"id":"a","telegram_user_id":3,"display_name":"Ada"}],"total":8,"next_cursor":"n"}"#.data(using: .utf8)!
        let parsed = momentsPeoplePage(data: page)
        XCTAssertEqual(parsed.people.first?.displayName, "Ada")
        XCTAssertEqual(parsed.people.first?.telegramUserId, 3)
        XCTAssertEqual(parsed.total, 8)
        XCTAssertEqual(parsed.nextCursor, "n")
        let missing = #"{"id":"p","state":"deleted"}"#.data(using: .utf8)!
        XCTAssertTrue(momentsLoadedPost(data: missing, fallbackId: "p").isUnavailable)
    }

    func testDeleteCommentPathIsTheCommentRoute() {
        XCTAssertEqual(momentsDeleteCommentPath(postId: "p1", commentId: "c1"), "/v1/feed/posts/p1/comments/c1")
        XCTAssertNotEqual(momentsDeleteCommentPath(postId: "p1", commentId: "c1"), "/v1/feed/posts/c1")
        XCTAssertEqual(momentsDeleteCommentPath(postId: "p/1", commentId: "c 2"), "/v1/feed/posts/p%2F1/comments/c%202")
    }

    func testRecommendPageTwoPutsTheCursorInTheURL() {
        let first = momentsFeedListQuery(kind: .recommend, cursor: nil, city: nil, sort: nil, pageSize: 20)
        XCTAssertNil(first["cursor"])
        XCTAssertEqual(first["limit"], "20")
        XCTAssertEqual(momentsRequestURL(base: "https://feed.example", path: "/v1/feed/recommend", query: first), "https://feed.example/v1/feed/recommend?limit=20")

        let raw = #"{"items":[{"id":"p1","reason":"recommend"}],"cursor":"c 1+"}"#.data(using: .utf8)!
        let refs = momentsFeedRefPage(data: raw, kind: .recommend)
        XCTAssertEqual(refs?.cursor, "c 1+")
        let merged = momentsMergeFeed(existing: [], pageItems: [MomentsCard(id: "p1")], cursor: refs?.cursor, refreshing: true)
        XCTAssertEqual(merged.cursor, "c 1+")
        let second = momentsFeedListQuery(kind: .recommend, cursor: merged.cursor, city: nil, sort: nil, pageSize: 20)
        XCTAssertEqual(second["cursor"], "c 1+")
        XCTAssertEqual(momentsRequestURL(base: "https://feed.example/", path: "/v1/feed/recommend", query: second), "https://feed.example/v1/feed/recommend?cursor=c%201%2B&limit=20")

        let numeric = #"{"items":[{"id":"p1","reason":"recommend"}],"cursor":42}"#.data(using: .utf8)!
        XCTAssertEqual(momentsFeedRefPage(data: numeric, kind: .recommend)?.cursor, "42")
        let numericQuery = momentsFeedListQuery(kind: .recommend, cursor: momentsFeedRefPage(data: numeric, kind: .recommend)?.cursor, city: nil, sort: nil, pageSize: 20)
        XCTAssertEqual(momentsRequestURL(base: "https://feed.example", path: "/v1/feed/recommend", query: numericQuery), "https://feed.example/v1/feed/recommend?cursor=42&limit=20")
    }

    func testServerFeedConfigUsesNestedLimitKeys() {
        let config = momentsRemoteConfig(data: Data(momentsServerConfigFixture.utf8))
        let limits = MomentsLimits.standard.applying(config: config)
        XCTAssertEqual(limits.textLimit, 420)
        XCTAssertEqual(limits.imageLimit, 4)
        XCTAssertEqual(limits.videoLimit, 2)
        XCTAssertEqual(limits.videoMaxDuration, 45)
        XCTAssertEqual(limits.voicePostMaxDuration, 30)
        XCTAssertEqual(limits.voiceCommentMaxDuration, 20)
        XCTAssertEqual(momentsVoiceMaxDuration(limits, comment: false), 30)
        XCTAssertEqual(momentsVoiceMaxDuration(limits, comment: true), 20)
        XCTAssertEqual(limits.commentTextLimit, 80)
        XCTAssertEqual(limits.pageSize, 15)
        XCTAssertEqual(limits.mentionLimit, 5)
        XCTAssertEqual(limits.topicLimit, 2)
        XCTAssertEqual(limits.newPostsProbeInterval, 30)
        XCTAssertEqual(limits.notificationRetentionDays, 14)
        XCTAssertTrue(config.personalizationToggleVisible)
        XCTAssertEqual(config.mediaBaseURL, "https://media.example/feed")
        XCTAssertEqual(config.tabs, ["recommend", "following", "friends", "nearby"])
        XCTAssertNotEqual(limits.textLimit, 900)
        XCTAssertNotEqual(limits.textLimit, 111)
        XCTAssertNotEqual(limits.commentTextLimit, 222)
        XCTAssertNotEqual(limits.voicePostMaxDuration, 180)
        XCTAssertNotEqual(limits.imageLimit, 9)
        XCTAssertNotEqual(limits.videoLimit, 8)
        XCTAssertNotEqual(limits.textLimit, 8000)

        let state = MomentsComposerAttachmentState()
        XCTAssertNil(momentsCanAdd(kind: .voice, to: state, limits: limits, duration: 30, voiceComment: false))
        XCTAssertEqual(momentsCanAdd(kind: .voice, to: state, limits: limits, duration: 31, voiceComment: false), .voiceTooLong)
        XCTAssertNil(momentsCanAdd(kind: .voice, to: state, limits: limits, duration: 20, voiceComment: true))
        XCTAssertEqual(momentsCanAdd(kind: .voice, to: state, limits: limits, duration: 21, voiceComment: true), .voiceTooLong)
    }

    func testOmittedOrMistypedLimitsKeepDefaults() {
        let missing = MomentsLimits.standard.applying(config: momentsRemoteConfig(data: Data(#"{"media_base_url":"https://media.example/feed","text_limit":900,"voice_max_seconds":180}"#.utf8)))
        XCTAssertEqual(missing.textLimit, MomentsLimits.standard.textLimit)
        XCTAssertEqual(missing.commentTextLimit, MomentsLimits.standard.commentTextLimit)
        XCTAssertEqual(missing.voicePostMaxDuration, 180)
        XCTAssertEqual(missing.voiceCommentMaxDuration, 180)
        XCTAssertFalse(momentsRemoteConfig(data: Data(#"{"media_base_url":"https://media.example/feed"}"#.utf8)).personalizationToggleVisible)

        let hidden = momentsRemoteConfig(data: Data(#"{"personalization_toggle_visible":false,"limits":{"post_text_chars":500}}"#.utf8))
        XCTAssertFalse(hidden.personalizationToggleVisible)
        XCTAssertEqual(MomentsLimits.standard.applying(config: hidden).textLimit, 500)

        let shown = momentsRemoteConfig(data: Data(#"{"personalization_toggle_visible":true}"#.utf8))
        XCTAssertTrue(shown.personalizationToggleVisible)
        XCTAssertEqual(MomentsLimits.standard.applying(config: shown).textLimit, 2000)

        let bad = momentsRemoteConfig(data: Data(#"{"personalization_toggle_visible":"true","limits":{"post_text_chars":"420","comment_text_chars":0,"voice_post_max_seconds":30.5,"voice_comment_max_seconds":-4,"post_images":4,"probe_interval_seconds":0,"notification_days":1.2}}"#.utf8))
        XCTAssertFalse(bad.personalizationToggleVisible)
        let badLimits = MomentsLimits.standard.applying(config: bad)
        XCTAssertEqual(badLimits.textLimit, MomentsLimits.standard.textLimit)
        XCTAssertEqual(badLimits.commentTextLimit, MomentsLimits.standard.commentTextLimit)
        XCTAssertEqual(badLimits.voicePostMaxDuration, MomentsLimits.standard.voicePostMaxDuration)
        XCTAssertEqual(badLimits.voiceCommentMaxDuration, MomentsLimits.standard.voiceCommentMaxDuration)
        XCTAssertEqual(badLimits.imageLimit, 4)
        XCTAssertEqual(badLimits.newPostsProbeInterval, MomentsLimits.standard.newPostsProbeInterval)
        XCTAssertEqual(badLimits.notificationRetentionDays, MomentsLimits.standard.notificationRetentionDays)

        let invented = MomentsLimits.standard.applying(config: momentsRemoteConfig(data: Data(#"{"limits":{"text_limit":100,"image_limit":4,"video_limit":2,"voice_max_seconds":30,"comment_text_limit":80,"page_size":7}}"#.utf8)))
        XCTAssertEqual(invented.textLimit, MomentsLimits.standard.textLimit)
        XCTAssertEqual(invented.imageLimit, MomentsLimits.standard.imageLimit)
        XCTAssertEqual(invented.videoLimit, MomentsLimits.standard.videoLimit)
        XCTAssertEqual(invented.voicePostMaxDuration, MomentsLimits.standard.voicePostMaxDuration)
        XCTAssertEqual(invented.commentTextLimit, MomentsLimits.standard.commentTextLimit)
        XCTAssertEqual(invented.pageSize, MomentsLimits.standard.pageSize)

        XCTAssertFalse(momentsRemoteConfig(data: Data(#"{"personalization_toggle_visible":1}"#.utf8)).personalizationToggleVisible)
        XCTAssertEqual(MomentsLimits.standard.applying(config: momentsRemoteConfig(data: Data("nope".utf8))).textLimit, 2000)
    }

    func testPreferenceAndRecommendRequestBodies() {
        let off = momentsPreferenceBody(current: [:], personalized: false)
        let offData = momentsJSONData(off)!
        let offObject = try! JSONSerialization.jsonObject(with: offData) as! [String: Any]
        XCTAssertEqual(offObject.count, 1)
        XCTAssertEqual(offObject["personalized"] as? Bool, false)
        XCTAssertFalse(String(data: offData, encoding: .utf8)!.contains("\"personalized\":\""))

        let kept = momentsPreferenceBody(current: ["locale": "zh"], personalized: true)
        let keptData = momentsJSONData(kept)!
        let keptObject = try! JSONSerialization.jsonObject(with: keptData) as! [String: Any]
        XCTAssertEqual(keptObject["locale"] as? String, "zh")
        XCTAssertEqual(keptObject["personalized"] as? Bool, true)
        XCTAssertFalse(String(data: keptData, encoding: .utf8)!.contains("\"personalized\":\""))

        XCTAssertNil(momentsPersonalizedFlag(data: Data(#"{"personalized":"false"}"#.utf8)))
        XCTAssertEqual(momentsPersonalizedFlag(data: Data(#"{"personalized":false}"#.utf8)), false)
        XCTAssertEqual(momentsPersonalizedFlag(data: Data(#"{"personalized":true,"locale":"zh"}"#.utf8)), true)
        XCTAssertNil(momentsPersonalizedFlag(data: Data(#"{}"#.utf8)))
        XCTAssertNil(momentsPersonalizedFlag(data: Data(#"{"personalized":1}"#.utf8)))

        let recommendOff = momentsFeedRequestQuery(kind: .recommend, cursor: nil, city: nil, sort: nil, pageSize: 15, personalized: false)
        XCTAssertEqual(recommendOff["limit"], "15")
        XCTAssertEqual(recommendOff["personalized"], "false")
        XCTAssertNil(recommendOff["cursor"])
        let recommendOn = momentsFeedRequestQuery(kind: .recommend, cursor: "next", city: nil, sort: nil, pageSize: 15, personalized: true)
        XCTAssertNil(recommendOn["personalized"])
        XCTAssertEqual(recommendOn["cursor"], "next")
        XCTAssertNil(momentsFeedRequestQuery(kind: .following, cursor: nil, city: nil, sort: nil, pageSize: 15, personalized: false)["personalized"])
        let nearby = momentsFeedRequestQuery(kind: .nearby, cursor: nil, city: "cn:chengdu", sort: nil, pageSize: 15, personalized: false)
        XCTAssertEqual(nearby["city"], "cn:chengdu")
        XCTAssertEqual(nearby["sort"], "latest")
        XCTAssertNil(nearby["personalized"])
    }

    /// A Moments row is measured on ListView's global queue and its UIKit node is created afterwards.
    /// `momentsOnMainQueue` is that hand-off: inline when the caller is already on the main queue,
    /// otherwise the next turn of the main queue. The feed crash was the node being created on the worker.
    func testMomentsViewWorkOnTheMainQueueRunsInline() {
        let exp = expectation(description: "main")
        Queue.mainQueue().async {
            var ran = false
            momentsOnMainQueue {
                ran = true
                XCTAssertTrue(Queue.mainQueue().isCurrent())
            }
            XCTAssertTrue(ran)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2)
    }

    func testMomentsViewWorkFromAWorkerQueueReachesMain() {
        let exp = expectation(description: "hop")
        DispatchQueue.global(qos: .userInteractive).async {
            XCTAssertFalse(Queue.mainQueue().isCurrent())
            momentsOnMainQueue {
                XCTAssertTrue(Queue.mainQueue().isCurrent())
                exp.fulfill()
            }
        }
        wait(for: [exp], timeout: 2)
    }

    func testGalleryKeepsTheTappedSlideWhenAnEarlierUrlIsMissing() {
        let dropped = MomentsMedia(type: .image, key: "http://insecure.example/a.jpg")
        let first = MomentsMedia(type: .image, key: "a", width: 400, height: 800, remoteURL: "https://cdn.example/a.jpg")
        let second = MomentsMedia(type: .image, key: "b", width: 1000, height: 500, remoteURL: "https://cdn.example/b.jpg", renditions: [
            MomentsRendition(key: "b-small", url: "https://cdn.example/b-360.jpg", width: 360, height: 180),
            MomentsRendition(key: "b-full", url: "https://cdn.example/b-1080.jpg", width: 1080, height: 540)
        ])
        let video = MomentsMedia(type: .video, key: "v", remoteURL: "https://cdn.example/v.mp4")
        let audio = MomentsMedia(type: .audio, key: "s", remoteURL: "https://cdn.example/a.mp3")
        let entries = momentsGalleryEntries(from: [dropped, first, audio, second, video], visibleAspectBySlide: [:])
        XCTAssertEqual(entries.map { $0.slideIndex }, [1, 2, 3])
        XCTAssertEqual(momentsGalleryEntryPosition(entries: entries, tappedSlide: 2), 1)
        XCTAssertEqual(momentsGalleryEntryPosition(entries: entries, tappedSlide: 0), 0)
        XCTAssertEqual(entries[1].url, "https://cdn.example/b-1080.jpg")
        XCTAssertEqual(entries[1].pixels, MomentsGalleryPixelSize(width: 1080, height: 540))
        XCTAssertEqual(entries[0].pixels, MomentsGalleryPixelSize(width: 400, height: 800))
        XCTAssertTrue(entries[2].isVideo)
        XCTAssertNil(momentsGalleryEntries(from: [audio]).first)

        let unknown = MomentsMedia(type: .image, key: "c", remoteURL: "https://cdn.example/c.jpg")
        XCTAssertEqual(momentsGalleryEntries(from: [unknown], visibleAspectBySlide: [0: 2])[0].pixels, MomentsGalleryPixelSize(width: 640, height: 1280))
        XCTAssertEqual(momentsGalleryEntries(from: [unknown])[0].pixels, MomentsGalleryPixelSize(width: 1280, height: 1280))

        let huge = MomentsMedia(type: .image, key: "h", width: 8000, height: 4000, remoteURL: "https://cdn.example/h.jpg")
        XCTAssertEqual(momentsGalleryEntries(from: [huge])[0].pixels, MomentsGalleryPixelSize(width: 4096, height: 2048))

        let onlySmall = MomentsMedia(type: .image, key: "s2", width: 2000, height: 1000, remoteURL: "https://cdn.example/original.jpg", renditions: [
            MomentsRendition(key: "small", url: "https://cdn.example/small.jpg", width: 360, height: 180)
        ])
        let smallEntry = momentsGalleryEntries(from: [onlySmall])[0]
        XCTAssertEqual(smallEntry.url, "https://cdn.example/original.jpg")
        XCTAssertEqual(smallEntry.pixels, MomentsGalleryPixelSize(width: 2000, height: 1000))
    }

    func testUserProfileKeepsStoriesAndNamesTheChineseTab() {
        let isStories: (String) -> Bool = { $0 == "stories" }
        let user: [String] = ["stories", "gifts", "media", "storyArchive"]
        let shown = momentsProfileTabs(user, isUserProfile: true, posts: .present, isStories: isStories, moments: "moments")
        XCTAssertEqual(shown, ["stories", "moments", "gifts", "media", "storyArchive"])

        let channel: [String] = ["stories", "media"]
        XCTAssertEqual(momentsProfileTabs(channel, isUserProfile: false, posts: .present, isStories: isStories, moments: "moments"), channel)

        let loading: [String]? = nil
        XCTAssertNil(momentsProfileTabs(loading, isUserProfile: true, posts: .present, isStories: isStories, moments: "moments"))

        let duplicate = momentsProfileTabs(["media", "moments", "stories"], isUserProfile: true, posts: .present, isStories: isStories, moments: "moments")
        XCTAssertEqual(duplicate, ["media", "stories", "moments"])

        XCTAssertEqual(momentsProfileStoriesTabTitle(resolved: "动态", languageCodes: ["zh-hans"]), "快拍")
        XCTAssertEqual(momentsProfileStoriesTabTitle(resolved: "Stories", languageCodes: ["zh-Hans-US"]), "快拍")
        XCTAssertEqual(momentsProfileStoriesTabTitle(resolved: "動態", languageCodes: ["zh-Hant"]), "快拍")
        XCTAssertEqual(momentsProfileStoriesTabTitle(resolved: "Stories", languageCodes: ["en"]), "Stories")
        XCTAssertNotEqual(momentsProfileStoriesTabTitle(resolved: "动态", languageCodes: ["zh-hans"]), "动态")

        let underCard = momentsProfileListInsets(topInset: 180, bottomInset: 0)
        XCTAssertEqual(underCard.top, 180)
        XCTAssertEqual(underCard.bottom, 24)
        let collapsed = momentsProfileListInsets(topInset: 40, bottomInset: 83)
        XCTAssertEqual(collapsed.top, 40)
        XCTAssertEqual(collapsed.bottom, 83)
    }

    func testMomentsPaneFollowsWhetherTheProfileHasPosts() {
        let isStories: (String) -> Bool = { $0 == "stories" }
        let base = ["stories", "media"]
        XCTAssertEqual(momentsProfilePostsPresence(cachedCount: nil, remoteCount: nil, failed: false), .unknown)
        XCTAssertEqual(momentsProfilePostsPresence(cachedCount: 0, remoteCount: nil, failed: false), .empty)
        XCTAssertEqual(momentsProfilePostsPresence(cachedCount: nil, remoteCount: 0, failed: false), .empty)
        XCTAssertEqual(momentsProfilePostsPresence(cachedCount: nil, remoteCount: 3, failed: false), .present)
        XCTAssertEqual(momentsProfilePostsPresence(cachedCount: 4, remoteCount: nil, failed: true), .present)
        XCTAssertEqual(momentsProfilePostsPresence(cachedCount: nil, remoteCount: nil, failed: true), .failed)
        XCTAssertEqual(momentsProfilePostsPresence(cachedCount: 0, remoteCount: nil, failed: true), .failed)
        XCTAssertEqual(momentsProfilePostsPresence(cachedCount: 4, remoteCount: 0, failed: false), .empty)
        XCTAssertEqual(momentsProfileTabs(base, isUserProfile: true, posts: .empty, isStories: isStories, moments: "moments"), base)
        XCTAssertEqual(momentsProfileTabs(base, isUserProfile: true, posts: .failed, isStories: isStories, moments: "moments"), base)
        XCTAssertEqual(momentsProfileTabs(base, isUserProfile: true, posts: .unknown, isStories: isStories, moments: "moments"), base)
        XCTAssertEqual(momentsProfilePostsFetch(refresh: false, cursor: nil), .sharedOpening)
        XCTAssertEqual(momentsProfilePostsFetch(refresh: true, cursor: nil), .page(cursor: nil))
        XCTAssertEqual(momentsProfilePostsFetch(refresh: false, cursor: "next"), .page(cursor: "next"))
        let present = momentsProfileTabs(base, isUserProfile: true, posts: .present, isStories: isStories, moments: "moments")
        XCTAssertEqual(present, ["stories", "moments", "media"])
        let labels = (present ?? []).map { pane -> String in
            if pane == "stories" {
                return momentsProfileStoriesTabTitle(resolved: "动态", languageCodes: ["zh-hans"])
            }
            if pane == "moments" {
                return "动态"
            }
            return pane
        }
        XCTAssertEqual(labels.filter { $0 == "动态" }, ["动态"])
        XCTAssertEqual(labels.filter { $0 == "快拍" }, ["快拍"])
        XCTAssertEqual(Array(labels.prefix(2)), ["快拍", "动态"])
        XCTAssertEqual(momentsProfileTabs(["media"], isUserProfile: true, posts: .present, isStories: isStories, moments: "moments"), ["moments", "media"])
        XCTAssertTrue(momentsProfilePaneReadyAtInit())
    }

    func testFailedProfileFetchThenSuccessShowsTheMomentsTab() {
        var store = MomentsProfileOpeningStore()
        let id = "7"
        let openedAt: Int64 = 1_000
        XCTAssertEqual(store.decision(id: id, now: openedAt, reason: .profileOpen), .refresh)
        let first = store.begin(id: id, now: openedAt)
        let failed = store.note(id: id, generation: first.generation, snapshot: momentsOpeningSnapshot(remoteCount: nil, failed: true), now: openedAt + 1)
        XCTAssertTrue(failed.applied)
        XCTAssertFalse(failed.confirmedEmpty)
        XCTAssertEqual(store.snapshot(id: id)?.presence, .failed)
        XCTAssertNotEqual(store.snapshot(id: id)?.presence, .empty)
        XCTAssertEqual(momentsOpeningTabs(store, id: id), ["stories", "media"])

        XCTAssertEqual(store.decision(id: id, now: openedAt + 2, reason: .profileOpen), .reuse)
        let retryAt = (openedAt + 1) + momentsProfileOpeningFailureThrottle
        XCTAssertEqual(store.decision(id: id, now: retryAt, reason: .profileOpen), .refresh)
        let second = store.begin(id: id, now: retryAt)
        XCTAssertTrue(store.note(id: id, generation: second.generation, snapshot: momentsOpeningSnapshot(remoteCount: 2, failed: false), now: retryAt + 1).applied)
        XCTAssertEqual(store.snapshot(id: id)?.presence, .present)
        XCTAssertEqual(momentsOpeningTabs(store, id: id), ["stories", "moments", "media"])
        XCTAssertFalse(store.note(id: id, generation: first.generation, snapshot: momentsOpeningSnapshot(remoteCount: nil, failed: true), now: retryAt + 2).applied)
        XCTAssertEqual(momentsOpeningTabs(store, id: id), ["stories", "moments", "media"])

        var offline = MomentsProfileOpeningStore()
        let offlineBegin = offline.begin(id: id, now: 50)
        XCTAssertTrue(offline.note(id: id, generation: offlineBegin.generation, snapshot: momentsOpeningSnapshot(remoteCount: nil, failed: true), now: 51).applied)
        XCTAssertEqual(momentsOpeningTabs(offline, id: id), ["stories", "media"])
        XCTAssertEqual(offline.decision(id: id, now: 51, reason: .reconnect), .reuse)
        XCTAssertEqual(offline.grantReconnectBypass(), [id])
        XCTAssertEqual(offline.decision(id: id, now: 51, reason: .reconnect), .refresh)
        let reconnected = offline.begin(id: id, now: 52)
        XCTAssertTrue(offline.note(id: id, generation: reconnected.generation, snapshot: momentsOpeningSnapshot(remoteCount: 1, failed: false), now: 53).applied)
        XCTAssertEqual(momentsOpeningTabs(offline, id: id), ["stories", "moments", "media"])

        var racing = MomentsProfileOpeningStore()
        let race = racing.begin(id: id, now: 1)
        XCTAssertEqual(racing.grantReconnectBypass(), [])
        let raced = racing.note(id: id, generation: race.generation, snapshot: momentsOpeningSnapshot(remoteCount: nil, failed: true), now: 2)
        XCTAssertTrue(raced.reconnectFollowUp)
        XCTAssertEqual(racing.decision(id: id, now: 2, reason: .reconnect), .refresh)
    }

    func testEmptyProfileThenPublishedPostShowsTheMomentsTab() {
        var store = MomentsProfileOpeningStore()
        let id = "9"
        let began = store.begin(id: id, now: 50)
        let settled = store.note(id: id, generation: began.generation, snapshot: momentsOpeningSnapshot(remoteCount: 0, failed: false), now: 51)
        XCTAssertTrue(settled.applied)
        XCTAssertTrue(settled.confirmedEmpty)
        XCTAssertEqual(store.snapshot(id: id)?.presence, .empty)
        XCTAssertEqual(momentsOpeningTabs(store, id: id), ["stories", "media"])

        XCTAssertEqual(store.decision(id: id, now: 51, reason: .viewerPublished), .refresh)
        XCTAssertEqual(store.decision(id: id, now: 51, reason: .ttl), .reuse)
        XCTAssertEqual(store.decision(id: id, now: 51 + momentsProfileOpeningEmptyTTL - 1, reason: .ttl), .reuse)
        XCTAssertEqual(store.decision(id: id, now: 51 + momentsProfileOpeningEmptyTTL, reason: .ttl), .refresh)
        XCTAssertEqual(store.decision(id: id, now: 51, reason: .profileOpen), .refresh)

        let published = store.begin(id: id, now: 51)
        XCTAssertNotEqual(published.generation, began.generation)
        XCTAssertFalse(store.note(id: id, generation: began.generation, snapshot: momentsOpeningSnapshot(remoteCount: 0, failed: false), now: 52).applied)
        XCTAssertTrue(store.note(id: id, generation: published.generation, snapshot: momentsOpeningSnapshot(remoteCount: 1, failed: false), now: 52).applied)
        XCTAssertEqual(store.snapshot(id: id)?.presence, .present)
        XCTAssertEqual(momentsOpeningTabs(store, id: id), ["stories", "moments", "media"])
        XCTAssertEqual(store.decision(id: id, now: 53, reason: .profileOpen), .reuse)

        var again = MomentsProfileOpeningStore()
        let empty = again.begin(id: id, now: 10)
        XCTAssertTrue(again.note(id: id, generation: empty.generation, snapshot: momentsOpeningSnapshot(remoteCount: 0, failed: false), now: 11).applied)
        XCTAssertEqual(again.decision(id: id, now: 12, reason: .profileOpen), .refresh)
        let nextOpen = again.begin(id: id, now: 12)
        XCTAssertTrue(again.note(id: id, generation: nextOpen.generation, snapshot: momentsOpeningSnapshot(remoteCount: 3, failed: false), now: 13).applied)
        XCTAssertEqual(momentsOpeningTabs(again, id: id), ["stories", "moments", "media"])
    }

    func testProfileOpeningMemoryIsBounded() {
        var store = MomentsProfileOpeningStore()
        for index in 0 ..< momentsProfileOpeningMemoryLimit {
            let began = store.begin(id: "p\(index)", now: Int64(index))
            XCTAssertTrue(began.evicted.isEmpty)
        }
        XCTAssertEqual(store.count, momentsProfileOpeningMemoryLimit)
        store.touch(id: "p0", now: Int64(momentsProfileOpeningMemoryLimit + 5))
        let overflow = store.begin(id: "overflow", now: Int64(momentsProfileOpeningMemoryLimit + 6))
        XCTAssertEqual(overflow.evicted, ["p1"])
        XCTAssertEqual(store.count, momentsProfileOpeningMemoryLimit)
        XCTAssertNil(store.snapshot(id: "p1"))
        XCTAssertEqual(store.decision(id: "p1", now: 1_000, reason: .profileOpen), .refresh)
        XCTAssertEqual(store.decision(id: "p0", now: 1_000, reason: .profileOpen), .reuse)
        XCTAssertEqual(store.decision(id: "gone", now: 1_000, reason: .reconnect), .reuse)
    }
}

private let momentsServerConfigFixture = """
{"tabs":["recommend","following","friends","nearby"],"recommend_mode":"personalized","personalization_toggle_visible":true,"hot_enabled":true,"ip_region_visible":true,"sensitive_more_available":false,"media_base_url":"https://media.example/feed","card_ttl_seconds":120,"text_limit":900,"limits":{"post_text_chars":420,"post_images":4,"post_videos":2,"article_chars":8000,"edit_window_seconds":900,"voice_comment_max_seconds":20,"voice_post_max_seconds":30,"video_max_seconds":45,"comment_text_chars":80,"page_size":15,"posts_per_hour":10,"comments_per_hour":40,"max_topics":2,"max_mentions":5,"probe_interval_seconds":30,"notification_days":14,"text_limit":111,"comment_text_limit":222,"voice_max_seconds":180,"image_limit":9,"video_limit":8}}
"""

private func momentsOpeningSnapshot(remoteCount: Int?, failed: Bool, cachedCount: Int? = nil) -> MomentsProfilePostsSnapshot {
    return MomentsProfilePostsSnapshot(items: [], nextCursor: nil, cachedCount: cachedCount, remoteCount: remoteCount, failed: failed)
}

private func momentsOpeningTabs(_ store: MomentsProfileOpeningStore, id: String) -> [String] {
    let posts = store.snapshot(id: id)?.presence ?? .unknown
    return momentsProfileTabs(["stories", "media"], isUserProfile: true, posts: posts, isStories: { $0 == "stories" }, moments: "moments") ?? []
}

private func momentsTestPost(text: String, audience: MomentsAudience = MomentsAudience(kind: .everyone), mediaKeys: [String] = [], allowNearby: Bool = false, city: String? = nil, placeId: String? = nil, quoteOf: String? = nil, nonce: String) -> MomentsPostDraft {
    return MomentsPostDraft(text: text, audience: audience, mediaKeys: mediaKeys, allowNearby: allowNearby, city: city, placeId: placeId, quoteOf: quoteOf, clientNonce: nonce)
}

private func momentsTestReady(_ result: Result<MomentsEncodedPost, MomentsPostEncodeError>) -> [String: Any] {
    guard case let .success(.ready(body)) = result else {
        XCTFail("expected a ready post body, got \(result)")
        return [:]
    }
    return body
}

private func momentsAssertNoLegacyPostKeys(_ body: [String: Any]) {
    for key in ["media", "location", "comment_policy", "link_preview", "include", "exclude", "user_ids"] {
        XCTAssertNil(body[key], key)
    }
    if let audience = body["audience"] as? [String: Any] {
        XCTAssertEqual(Set(audience.keys), ["audience_token"])
    }
}
