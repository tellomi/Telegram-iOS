import XCTest

final class EphemeralMediaLifecycleTests: XCTestCase {
    func testKindsStayDistinct() {
        XCTAssertEqual(ephemeralMediaKind(chat: .cloud, timeout: ephemeralViewOnceTimeout, shape: .photo), .viewOncePhotoOrVideo)
        XCTAssertEqual(ephemeralMediaKind(chat: .cloud, timeout: ephemeralViewOnceTimeout, shape: .video), .viewOncePhotoOrVideo)
        XCTAssertEqual(ephemeralMediaKind(chat: .cloud, timeout: ephemeralViewOnceTimeout, shape: .voice), .viewOnceVoice)
        XCTAssertEqual(ephemeralMediaKind(chat: .cloud, timeout: ephemeralViewOnceTimeout, shape: .roundVideo), .viewOnceRoundVideo)
        XCTAssertEqual(ephemeralMediaKind(chat: .cloud, timeout: 10, shape: .video), .mediaSelfDestruct)
        XCTAssertEqual(ephemeralMediaKind(chat: .cloud, timeout: 60, shape: .photo), .mediaSelfDestruct)
        XCTAssertEqual(ephemeralMediaKind(chat: .cloud, timeout: 86_400, shape: .other), .conversationTtl)
        XCTAssertEqual(ephemeralMediaKind(chat: .secret, timeout: 86_400, shape: .photo), .secretChat)
        XCTAssertEqual(ephemeralMediaKind(chat: .secret, timeout: ephemeralViewOnceTimeout, shape: .voice), .secretChat)
    }

    func testConversationTtlIsNotSecretMedia() {
        XCTAssertFalse(ephemeralCountsAsSecretMedia(chat: .cloud, timeout: 86_400, shape: .photo))
        XCTAssertTrue(ephemeralCountsAsSecretMedia(chat: .cloud, timeout: 15, shape: .roundVideo))
        XCTAssertTrue(ephemeralCountsAsSecretMedia(chat: .cloud, timeout: ephemeralViewOnceTimeout, shape: .voice))
        XCTAssertFalse(ephemeralCountsAsSecretMedia(chat: .cloud, timeout: 15, shape: .other))
        XCTAssertTrue(ephemeralCountsAsSecretMedia(chat: .secret, timeout: 86_400, shape: .other))
    }

    func testViewOnceDoesNotGrowWithDuration() {
        XCTAssertEqual(ephemeralCountdownTimeout(storedTimeout: ephemeralViewOnceTimeout, mediaDuration: 30, attributeIsAutoclear: true), ephemeralViewOnceTimeout)
        XCTAssertEqual(ephemeralCountdownTimeout(storedTimeout: 5, mediaDuration: 12, attributeIsAutoclear: true), 12)
        XCTAssertEqual(ephemeralDueTimestamp(timeout: ephemeralViewOnceTimeout, countdownBegin: 1_000), 1_000)
        XCTAssertEqual(ephemeralDueTimestamp(timeout: 5, countdownBegin: 1_000), 1_005)
    }

    func testRecipientOpenReportsReadWithoutHidingOrDeleting() {
        for kind in [EphemeralMediaKind.viewOncePhotoOrVideo, .viewOnceVoice, .viewOnceRoundVideo, .mediaSelfDestruct] {
            let effect = ephemeralOpenEffect(kind: kind, side: .recipient, countdownAlreadyStarted: false)
            XCTAssertTrue(effect.startsCountdown)
            XCTAssertEqual(effect.readReport, .cloudReadMessageContents)
            XCTAssertFalse(effect.replacesMediaWithPlaceholder)
            XCTAssertFalse(effect.removesCacheBytes)
        }
        let secret = ephemeralOpenEffect(kind: .secretChat, side: .recipient, countdownAlreadyStarted: false)
        XCTAssertEqual(secret.readReport, .secretReadMessagesContent)
        XCTAssertFalse(secret.removesCacheBytes)
        let ttl = ephemeralOpenEffect(kind: .conversationTtl, side: .recipient, countdownAlreadyStarted: true)
        XCTAssertEqual(ttl.readReport, .none)
        XCTAssertFalse(ttl.startsCountdown)
        let ttlNotStarted = ephemeralOpenEffect(kind: .conversationTtl, side: .recipient, countdownAlreadyStarted: false)
        XCTAssertTrue(ttlNotStarted.startsCountdown)
        XCTAssertEqual(ttlNotStarted.readReport, .none)
        XCTAssertFalse(ttlNotStarted.replacesMediaWithPlaceholder)
        XCTAssertFalse(ttlNotStarted.removesCacheBytes)
    }

    func testSenderOpenDoesNothing() {
        let effect = ephemeralOpenEffect(kind: .viewOnceRoundVideo, side: .sender, countdownAlreadyStarted: false)
        XCTAssertFalse(effect.startsCountdown)
        XCTAssertEqual(effect.readReport, .none)
        XCTAssertFalse(effect.replacesMediaWithPlaceholder)
        XCTAssertFalse(effect.removesCacheBytes)
    }

    func testExpiryLayersAreNotTheSame() {
        let viewed = ephemeralExpiryEffect(kind: .viewOncePhotoOrVideo)
        XCTAssertTrue(viewed.keepsMessageRow)
        XCTAssertTrue(viewed.showsExpiredPlaceholder)
        XCTAssertFalse(viewed.removesCacheBytes)
        XCTAssertFalse(viewed.invalidatesServerAccess)

        let voice = ephemeralExpiryEffect(kind: .viewOnceVoice)
        XCTAssertEqual(voice, viewed)
        XCTAssertEqual(ephemeralExpiryEffect(kind: .viewOnceRoundVideo), viewed)
        XCTAssertEqual(ephemeralExpiryEffect(kind: .mediaSelfDestruct), viewed)

        let ttl = ephemeralExpiryEffect(kind: .conversationTtl)
        XCTAssertTrue(ttl.removesMessageRow)
        XCTAssertFalse(ttl.showsExpiredPlaceholder)
        XCTAssertFalse(ttl.removesCacheBytes)
        XCTAssertFalse(ttl.invalidatesServerAccess)

        let secret = ephemeralExpiryEffect(kind: .secretChat)
        XCTAssertTrue(secret.removesMessageRow)
        XCTAssertTrue(secret.removesCacheBytes)
        XCTAssertFalse(secret.showsExpiredPlaceholder)
        XCTAssertFalse(secret.invalidatesServerAccess)
    }

    func testRemoteViewOnceHidesWithoutDeletingCache() {
        XCTAssertTrue(ephemeralRemoteConsumeReplacesMedia(kind: .viewOncePhotoOrVideo, timeout: ephemeralViewOnceTimeout, now: 0, countdownBegin: 50))
        XCTAssertFalse(ephemeralRemoteConsumeReplacesMedia(kind: .mediaSelfDestruct, timeout: 10, now: 1_000, countdownBegin: 1_000))
        XCTAssertTrue(ephemeralRemoteConsumeReplacesMedia(kind: .mediaSelfDestruct, timeout: 10, now: 1_010, countdownBegin: 1_000))
        XCTAssertFalse(ephemeralRemoteConsumeReplacesMedia(kind: .conversationTtl, timeout: 86_400, now: 10_000, countdownBegin: 1))
        XCTAssertFalse(ephemeralRemoteConsumeReplacesMedia(kind: .secretChat, timeout: 10, now: 10_000, countdownBegin: 1))
    }

    func testFailedCloudReadReportIsNotRetried() {
        XCTAssertFalse(ephemeralCloudReadReportRetriedAfterError())
    }

    func testStaleResourceCanBeFetchedAgain() {
        let cloud = ephemeralStaleReference(after: ephemeralExpiryEffect(kind: .viewOnceRoundVideo))
        XCTAssertFalse(cloud.messageStillNamesResource)
        XCTAssertTrue(cloud.cacheMayStillHoldBytes)
        XCTAssertFalse(cloud.clientMarksResourceInvalid)

        let deleted = ephemeralStaleReference(after: ephemeralExpiryEffect(kind: .conversationTtl))
        XCTAssertTrue(deleted.cacheMayStillHoldBytes)
        XCTAssertFalse(deleted.clientMarksResourceInvalid)

        let secret = ephemeralStaleReference(after: ephemeralExpiryEffect(kind: .secretChat))
        XCTAssertFalse(secret.cacheMayStillHoldBytes)
        XCTAssertFalse(secret.clientMarksResourceInvalid)
    }
}
