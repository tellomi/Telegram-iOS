import XCTest
@testable import TelegramCore

final class MomentsRulesTests: XCTestCase {
    func testAttachmentExclusivity() {
        let limits = MomentsLimits.standard
        var state = MomentsComposerAttachmentState()
        XCTAssertNil(momentsCanAdd(kind: .image, to: state, limits: limits))
        state.imageCount = 12
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
        XCTAssertEqual(limits.voiceMaxDuration, MomentsLimits.standard.voiceMaxDuration)
        XCTAssertTrue(limits.newsStaysOff)
        XCTAssertTrue(limits.tabEnabled)
        XCTAssertFalse(MomentsFeedKind.recommend.probesForNewPosts)
        XCTAssertTrue(MomentsFeedKind.following.probesForNewPosts)
    }

    func testDraftCapKeepsNewest() {
        let kept = momentsTrimDrafts([1, 2, 3, 4], limit: 2, newer: >)
        XCTAssertEqual(kept, [4, 3])
    }
}
