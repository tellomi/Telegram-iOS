import XCTest

final class TellomiNativeBatchTests: XCTestCase {
    func testTranslationIsEnglishToChineseOnTheServerOnly() {
        XCTAssertEqual(tellomiTranslationRoute(from: "en", to: "zh-Hans", enabled: true, healthy: true), .server)
        XCTAssertEqual(tellomiTranslationRoute(from: nil, to: "zh", enabled: true, healthy: true), .server)
        XCTAssertEqual(tellomiTranslationRoute(from: "ja", to: "zh", enabled: true, healthy: true), .refused)
        XCTAssertEqual(tellomiTranslationRoute(from: "en", to: "fr", enabled: true, healthy: true), .refused)
        XCTAssertEqual(tellomiTranslationRoute(from: "en", to: "zh", enabled: false, healthy: true), .refused)
        XCTAssertEqual(tellomiTranslationRoute(from: "en", to: "zh", enabled: true, healthy: false), .unavailable)
        XCTAssertEqual(tellomiTranslationRoute(from: "en", to: "zh-cn", enabled: true, healthy: true), .server)
        XCTAssertEqual(tellomiTranslationRoute(from: "en", to: "zh-hant", enabled: true, healthy: true), .refused)
        XCTAssertFalse(tellomiManualTranslationAvailable(manual: nil, flag: nil))
        XCTAssertTrue(tellomiManualTranslationAvailable(manual: "enabled", flag: nil))
        XCTAssertFalse(tellomiManualTranslationAvailable(manual: "disabled", flag: true))
        XCTAssertTrue(tellomiManualTranslationAvailable(manual: nil, flag: true))
        XCTAssertFalse(tellomiAutoTranslationAvailable(auto: nil))
        XCTAssertTrue(tellomiAutoTranslationAvailable(auto: "enabled"))
        XCTAssertEqual(tellomiTranslateFailure("TO_LANG_INVALID"), .invalidLanguage)
        XCTAssertEqual(tellomiTranslateFailure("TRANSLATE_REQ_FAILED"), .unavailable)
        XCTAssertEqual(tellomiTranslateFailure("AICOMPOSE_TIMEOUT"), .unavailable)
        XCTAssertFalse(tellomiTranslationAllowsLocalEngine())
        XCTAssertFalse(tellomiTranslationAllowsAlternativeEngine())
        XCTAssertFalse(tellomiTranslationExplicitlyDisabled(nil))
        XCTAssertTrue(tellomiTranslationExplicitlyDisabled("disabled"))
    }

    func testPhoneNumberFloodIsDailyAndFloodWaitIsShort() {
        XCTAssertEqual(tellomiCodeRequestLimit("PHONE_NUMBER_FLOOD"), .daily)
        XCTAssertEqual(tellomiCodeRequestLimit("FLOOD_WAIT_30"), .shortWait)
        XCTAssertEqual(tellomiCodeRequestLimit("PHONE_CODE_FLOOD"), .none)
        XCTAssertEqual(tellomiCodeRequestLimit("PHONE_NUMBER_INVALID"), .none)
    }

    func testDictationFillsTheDraftAndDoesNotSendVoice() {
        XCTAssertEqual(tellomiDictationOutcome(transcript: " 你好 ", healthy: true), .insertDraft("你好"))
        XCTAssertEqual(tellomiDictationOutcome(transcript: "   ", healthy: true), .unavailable)
        XCTAssertEqual(tellomiDictationOutcome(transcript: "你好", healthy: false), .unavailable)
        XCTAssertFalse(tellomiDictationSendsVoice())
        XCTAssertEqual(tellomiDraftAudioDecision(byteCount: 0, fileExtension: "ogg"), .empty)
        XCTAssertEqual(tellomiDraftAudioDecision(byteCount: tellomiDraftAudioByteLimit + 1, fileExtension: "ogg"), .tooLong)
        XCTAssertEqual(tellomiDraftAudioDecision(byteCount: 32, fileExtension: "mp3"), .unsupported)
        XCTAssertEqual(tellomiDraftAudioDecision(byteCount: 32, fileExtension: "OGG"), .accepted)
        XCTAssertEqual(tellomiDraftTranscriptionError("USER_ID_INVALID"), .notLoggedIn)
        XCTAssertEqual(tellomiDraftTranscriptionError("MEDIA_EMPTY"), .empty)
        XCTAssertEqual(tellomiDraftTranscriptionError("AUDIO_TOO_LONG"), .tooLong)
        XCTAssertEqual(tellomiDraftTranscriptionError("TRANSCRIPTION_FAILED"), .failed)
        XCTAssertEqual(tellomiDraftTranscriptionError("TRANSCRIPTION_UNAVAILABLE"), .unavailable)
        XCTAssertEqual(tellomiDraftTranscriptionError("METHOD_INVALID"), .unavailable)
    }

    func testSideTranslateButtonStaysOffTheBubbleLayout() {
        XCTAssertEqual(tellomiSideTranslateButton(isIncoming: true, isSecret: false, isSelecting: false, showTranslate: true, manualAvailable: true, detectedLanguage: "en", isShowingThisMessage: false, wholeChatTranslation: false), .translate)
        XCTAssertEqual(tellomiSideTranslateButton(isIncoming: true, isSecret: false, isSelecting: false, showTranslate: true, manualAvailable: true, detectedLanguage: "en", isShowingThisMessage: true, wholeChatTranslation: false), .restore)
        XCTAssertEqual(tellomiSideTranslateButton(isIncoming: true, isSecret: false, isSelecting: false, showTranslate: true, manualAvailable: true, detectedLanguage: "zh", isShowingThisMessage: false, wholeChatTranslation: false), .hidden)
        XCTAssertEqual(tellomiSideTranslateButton(isIncoming: false, isSecret: false, isSelecting: false, showTranslate: true, manualAvailable: true, detectedLanguage: "en", isShowingThisMessage: false, wholeChatTranslation: false), .hidden)
        XCTAssertEqual(tellomiSideTranslateButton(isIncoming: true, isSecret: false, isSelecting: true, showTranslate: true, manualAvailable: true, detectedLanguage: "en", isShowingThisMessage: false, wholeChatTranslation: false), .hidden)
        XCTAssertEqual(tellomiSideTranslateButton(isIncoming: true, isSecret: false, isSelecting: false, showTranslate: false, manualAvailable: true, detectedLanguage: "en", isShowingThisMessage: false, wholeChatTranslation: false), .hidden)
        XCTAssertEqual(tellomiSideTranslateButton(isIncoming: true, isSecret: false, isSelecting: false, showTranslate: true, manualAvailable: false, detectedLanguage: "en", isShowingThisMessage: false, wholeChatTranslation: false), .hidden)
        XCTAssertEqual(tellomiSideTranslateButton(isIncoming: true, isSecret: false, isSelecting: false, showTranslate: true, manualAvailable: true, detectedLanguage: "en", isShowingThisMessage: false, wholeChatTranslation: true), .hidden)

        let alone = tellomiSideTranslateOrigin(bubbleX: 40, bubbleY: 10, bubbleWidth: 180, bubbleHeight: 60, buttonSide: 30, shareMinY: nil, incoming: true)
        XCTAssertEqual(alone.x, 228)
        XCTAssertEqual(alone.y, 39)
        let stacked = tellomiSideTranslateOrigin(bubbleX: 40, bubbleY: 10, bubbleWidth: 180, bubbleHeight: 60, buttonSide: 30, shareMinY: 40, incoming: true)
        XCTAssertEqual(stacked.x, 228)
        XCTAssertLessThan(stacked.y + 30, 40)
    }
}
