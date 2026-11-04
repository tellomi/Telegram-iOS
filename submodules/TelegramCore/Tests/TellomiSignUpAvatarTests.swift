import XCTest

final class TellomiSignUpAvatarTests: XCTestCase {
    func testAFailedUploadStillCreatesTheAccount() {
        let failure = TellomiSignUpAvatarFailure(code: 500, description: "INTERNAL_SERVER_ERROR")
        XCTAssertEqual(tellomiSignUpAvatarDecision(.working), .wait)
        XCTAssertEqual(tellomiSignUpAvatarDecision(.uploaded), .createAccount)
        XCTAssertEqual(tellomiSignUpAvatarDecision(.failed(failure)), .createAccountAndShowError(failure))
    }

    func testTheAlertShowsTheRealErrorCode() {
        XCTAssertEqual(tellomiSignUpAvatarErrorLabel(code: 500, description: "INTERNAL_SERVER_ERROR"), "500 INTERNAL_SERVER_ERROR")
        XCTAssertEqual(tellomiSignUpAvatarErrorLabel(code: 400, description: "  PHOTO_CROP_SIZE_SMALL  "), "400 PHOTO_CROP_SIZE_SMALL")
        XCTAssertEqual(tellomiSignUpAvatarErrorLabel(code: 500, description: ""), "500")

        let chinese = tellomiSignUpAvatarFailureText(code: 500, description: "INTERNAL_SERVER_ERROR", languageCode: "zh-Hans")
        XCTAssertEqual(chinese, "头像上传失败（500 INTERNAL_SERVER_ERROR）")
        XCTAssertTrue(chinese.contains("头像上传失败"))
        XCTAssertTrue(chinese.contains("500"))
        XCTAssertTrue(chinese.contains("INTERNAL_SERVER_ERROR"))

        XCTAssertEqual(
            tellomiSignUpAvatarFailureText(code: 500, description: "INTERNAL_SERVER_ERROR", languageCode: "zh-Hant"),
            "頭像上傳失敗（500 INTERNAL_SERVER_ERROR）"
        )
        XCTAssertEqual(
            tellomiSignUpAvatarFailureText(code: 500, description: "INTERNAL_SERVER_ERROR", languageCode: "en"),
            "Couldn't upload the profile photo (500 INTERNAL_SERVER_ERROR)"
        )
        XCTAssertEqual(tellomiSignUpAvatarRetryTitle(languageCode: "zh"), "重试")
        XCTAssertEqual(tellomiSignUpAvatarRetryTitle(languageCode: "ja"), "Retry")
    }

    func testALanguagePackReplacesTheFallback() {
        let pack = [
            "Tellomi.SignUp.AvatarFailed": "写真をアップロードできません（%@）",
            "Tellomi.SignUp.AvatarRetry": "再試行"
        ]
        XCTAssertEqual(
            tellomiSignUpAvatarFailureText(code: 500, description: "INTERNAL_SERVER_ERROR", languageCode: "ja", pack: pack),
            "写真をアップロードできません（500 INTERNAL_SERVER_ERROR）"
        )
        XCTAssertEqual(tellomiSignUpAvatarRetryTitle(languageCode: "ja", pack: pack), "再試行")
    }
}
