import XCTest

final class TellomiDiscoverVideoTests: XCTestCase {
    private let nonce = "11111111-1111-4111-8111-111111111111"

    func testSixtySecondsIsTheInclusiveCap() {
        XCTAssertEqual(TellomiDiscoverVideo.maxSeconds, 60)
        XCTAssertEqual(TellomiDiscoverVideo.maxDurationMs, 60_000)
        XCTAssertEqual(TellomiDiscoverVideo.select(durationMs: 1), .accept)
        XCTAssertEqual(TellomiDiscoverVideo.select(durationMs: 60_000), .accept)
        XCTAssertEqual(TellomiDiscoverVideo.select(durationMs: 60_001), .tooLong)
        XCTAssertEqual(TellomiDiscoverVideo.select(durationMs: 120_000), .tooLong)
        XCTAssertEqual(TellomiDiscoverVideo.select(durationMs: 0), .unknown)
        XCTAssertEqual(TellomiDiscoverVideo.select(durationMs: -1), .unknown)
    }

    func testUploadIsBlockedBeforeAnyRequest() {
        XCTAssertEqual(TellomiDiscoverVideo.beforeUpload(durationMs: 60_001), .tooLong)
        XCTAssertEqual(TellomiDiscoverVideo.beforeUpload(durationMs: 0), .unknown)
        XCTAssertEqual(TellomiDiscoverVideo.beforeUpload(durationMs: 60_000), .notUploaded)
        XCTAssertEqual(TellomiDiscoverVideo.beforeUpload(durationMs: 42_000), .notUploaded)
        XCTAssertNotEqual(TellomiDiscoverVideo.beforeUpload(durationMs: 60_000), .accept)
    }

    func testAttachedVideoNeverFallsThroughToATextPost() {
        for duration: Int64 in [1, 60_000, 60_001, 0, -1, 120_000] {
            let gate = TellomiDiscoverVideo.publishGate(hasVideo: true, busy: false, durationMs: duration)
            guard case .hold = gate else {
                XCTFail("a video must not publish at \(duration)")
                return
            }
        }
        XCTAssertEqual(TellomiDiscoverVideo.publishGate(hasVideo: true, busy: false, durationMs: 60_000), .hold(.notUploaded))
        XCTAssertEqual(TellomiDiscoverVideo.publishGate(hasVideo: true, busy: false, durationMs: 60_001), .hold(.tooLong))
        XCTAssertEqual(TellomiDiscoverVideo.publishGate(hasVideo: true, busy: false, durationMs: 0), .hold(.unknown))
        XCTAssertEqual(TellomiDiscoverVideo.publishGate(hasVideo: true, busy: true, durationMs: 1_000), .wait)
        XCTAssertEqual(TellomiDiscoverVideo.publishGate(hasVideo: false, busy: true, durationMs: 0), .wait)
        XCTAssertEqual(TellomiDiscoverVideo.publishGate(hasVideo: false, busy: false, durationMs: 60_000), .sendText)

        let body = tellomiDiscoverPublishBody(text: "hi", visibility: .everyone, audienceToken: nil, clientNonce: self.nonce, textLimit: 500)
        let json = try! JSONSerialization.jsonObject(with: body!) as! [String: Any]
        XCTAssertNil(json["media"])
        XCTAssertNil(json["video"])
        XCTAssertEqual(json["kind"] as? String, "post")
        XCTAssertEqual(json["text"] as? String, "hi")
        XCTAssertEqual(Set(json.keys), Set(["kind", "text", "visibility", "client_nonce"]))
    }

    func testRecheckKeepsAStoredLengthWhenTheFreshReadFails() {
        XCTAssertEqual(TellomiDiscoverVideo.measuredDuration(freshMs: 60_001, storedMs: 1_000), 60_001)
        XCTAssertEqual(TellomiDiscoverVideo.measuredDuration(freshMs: 0, storedMs: 42_000), 42_000)
        XCTAssertEqual(TellomiDiscoverVideo.measuredDuration(freshMs: 60_000, storedMs: 1_000), 60_000)
        XCTAssertEqual(TellomiDiscoverVideo.beforeUpload(durationMs: TellomiDiscoverVideo.measuredDuration(freshMs: 0, storedMs: 60_000)), .notUploaded)
        XCTAssertEqual(TellomiDiscoverVideo.beforeUpload(durationMs: TellomiDiscoverVideo.measuredDuration(freshMs: 60_001, storedMs: 1_000)), .tooLong)
        XCTAssertEqual(TellomiDiscoverVideo.beforeUpload(durationMs: TellomiDiscoverVideo.measuredDuration(freshMs: 0, storedMs: 0)), .unknown)
    }

    func testGallerySecondsUseTheSameCap() {
        XCTAssertEqual(TellomiDiscoverVideo.selectPhotoEntrySeconds(60), .accept)
        XCTAssertEqual(TellomiDiscoverVideo.selectPhotoEntrySeconds(61), .tooLong)
        XCTAssertEqual(TellomiDiscoverVideo.selectPhotoEntrySeconds(0), .unknown)
        XCTAssertEqual(TellomiDiscoverVideo.selectPhotoEntrySeconds(-3), .unknown)
        XCTAssertEqual(TellomiDiscoverVideo.select(durationMs: 60_001), .tooLong)
    }

    func testMetadataDurationParsesMilliseconds() {
        XCTAssertEqual(TellomiDiscoverVideo.parseMillis("60000"), 60_000)
        XCTAssertEqual(TellomiDiscoverVideo.parseMillis(" 60000.9 "), 60_000)
        XCTAssertEqual(TellomiDiscoverVideo.parseMillis("60001"), 60_001)
        XCTAssertEqual(TellomiDiscoverVideo.parseMillis(nil), 0)
        XCTAssertEqual(TellomiDiscoverVideo.parseMillis(""), 0)
        XCTAssertEqual(TellomiDiscoverVideo.parseMillis("-5"), 0)
        XCTAssertEqual(TellomiDiscoverVideo.parseMillis("nope"), 0)
    }

    func testTimebaseConvertsToTruncatedMilliseconds() {
        XCTAssertEqual(TellomiDiscoverVideo.milliseconds(timeValue: 60, timescale: 1, numeric: true), 60_000)
        XCTAssertEqual(TellomiDiscoverVideo.milliseconds(timeValue: 36_000, timescale: 600, numeric: true), 60_000)
        XCTAssertEqual(TellomiDiscoverVideo.milliseconds(timeValue: 60_001, timescale: 1_000, numeric: true), 60_001)
        XCTAssertEqual(TellomiDiscoverVideo.milliseconds(timeValue: 1, timescale: 1_000, numeric: true), 1)
        XCTAssertEqual(TellomiDiscoverVideo.milliseconds(timeValue: 500, timescale: 1_000, numeric: true), 500)
        XCTAssertEqual(TellomiDiscoverVideo.milliseconds(timeValue: 1, timescale: 10_000, numeric: true), 0)
        XCTAssertEqual(TellomiDiscoverVideo.milliseconds(timeValue: 0, timescale: 600, numeric: true), 0)
        XCTAssertEqual(TellomiDiscoverVideo.milliseconds(timeValue: 60, timescale: 0, numeric: true), 0)
        XCTAssertEqual(TellomiDiscoverVideo.milliseconds(timeValue: 60, timescale: 1, numeric: false), 0)
        XCTAssertEqual(TellomiDiscoverVideo.milliseconds(timeValue: -5, timescale: 1, numeric: true), 0)
        XCTAssertEqual(TellomiDiscoverVideo.milliseconds(timeValue: Int64.max, timescale: 1, numeric: true), 60_001)
    }

    func testClockLabelsTheSelectedClip() {
        XCTAssertEqual(TellomiDiscoverVideo.clock(60_000), "1:00")
        XCTAssertEqual(TellomiDiscoverVideo.clock(59_000), "0:59")
        XCTAssertEqual(TellomiDiscoverVideo.clock(61_000), "1:01")
        XCTAssertEqual(TellomiDiscoverVideo.clock(500), "0:01")
        XCTAssertEqual(TellomiDiscoverVideo.clock(0), "0:00")
        XCTAssertEqual(TellomiDiscoverVideo.selectedLabel(template: "Selected · %s", clock: "1:00"), "Selected · 1:00")
        XCTAssertEqual(TellomiDiscoverVideo.selectedLabel(template: "已选择 · %@", clock: "0:59"), "已选择 · 0:59")
    }

    func testChineseCopyNamesTheSixtySecondCap() {
        let simplified = TellomiDiscoverCopy.resolve(languageCode: "zh-Hans")
        XCTAssertEqual(simplified.videoHint, "视频最长 60 秒。")
        XCTAssertEqual(simplified.videoTooLong, "这段视频超过 60 秒，请换一段更短的。")
        XCTAssertEqual(simplified.videoUnknown, "读不到这段视频的时长，请换一个。")
        XCTAssertEqual(simplified.videoSelected, "已选择 · %s")
        XCTAssertEqual(simplified.videoNotUploaded, "发现还不能上传视频，移除后可以发布文字。")
        XCTAssertEqual(simplified.videoAdd, "添加视频")
        XCTAssertEqual(simplified.videoReplace, "更换")
        XCTAssertEqual(simplified.videoRemove, "移除")
        XCTAssertEqual(simplified.videoReading, "正在读取时长…")
        XCTAssertEqual(TellomiDiscoverCopy.resolve(languageCode: "zh").videoUnknown, "读不到这段视频的时长，请换一个。")
        XCTAssertEqual(TellomiDiscoverCopy.resolve(languageCode: "zh-Hans-TW").videoHint, "视频最长 60 秒。")
        XCTAssertEqual(TellomiDiscoverCopy.resolve(languageCode: "zh-CN").videoSelected, "已选择 · %s")

        let traditional = TellomiDiscoverCopy.resolve(languageCode: "zh-Hant")
        XCTAssertEqual(traditional.videoTooLong, "這段影片超過 60 秒，請換一段更短的。")
        XCTAssertEqual(traditional.videoHint, "影片最長 60 秒。")
        XCTAssertEqual(traditional.videoNotUploaded, "發現還不能上傳影片，移除後可以發布文字。")

        let english = TellomiDiscoverCopy.resolve(languageCode: "en")
        XCTAssertEqual(english.videoHint, "Videos can be up to 60 seconds.")
        XCTAssertEqual(english.videoTooLong, "This video is longer than 60 seconds. Pick a shorter one.")
        XCTAssertEqual(english.videoUnknown, "Couldn't read how long this video is. Pick another.")
        XCTAssertEqual(english.videoNotUploaded, "Video upload isn't available yet. Remove it to post the text.")
        XCTAssertEqual(TellomiDiscoverCopy.resolve(languageCode: "ja").videoHint, "動画は60秒までです。")

        let kept = TellomiDiscoverVideo.statusText(busy: false, decision: .accept, hasVideo: true, durationMs: 60_000, copy: simplified)
        XCTAssertEqual(kept?.text, "已选择 · 1:00\n发现还不能上传视频，移除后可以发布文字。")
        XCTAssertEqual(kept?.isError, false)
        let rejected = TellomiDiscoverVideo.statusText(busy: false, decision: .tooLong, hasVideo: false, durationMs: 0, copy: simplified)
        XCTAssertEqual(rejected?.text, "这段视频超过 60 秒，请换一段更短的。")
        XCTAssertEqual(rejected?.isError, true)
        let unreadable = TellomiDiscoverVideo.statusText(busy: false, decision: .unknown, hasVideo: false, durationMs: 0, copy: english)
        XCTAssertEqual(unreadable?.text, "Couldn't read how long this video is. Pick another.")
        XCTAssertEqual(unreadable?.isError, true)
        XCTAssertEqual(TellomiDiscoverVideo.statusText(busy: true, decision: .none, hasVideo: false, durationMs: 0, copy: english)?.text, "Reading the length…")
        XCTAssertNil(TellomiDiscoverVideo.statusText(busy: false, decision: .none, hasVideo: false, durationMs: 0, copy: english))

        let overridden = TellomiDiscoverCopy.resolve(languageCode: "en", pack: ["Tellomi.Discover.VideoHint": "Max 60s"])
        XCTAssertEqual(overridden.videoHint, "Max 60s")
        XCTAssertEqual(overridden.videoAdd, "Add a video")
    }
}
