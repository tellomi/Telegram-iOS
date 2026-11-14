import XCTest

final class TellomiBundledLocalizationsTests: XCTestCase {
    func testEveryLangPackLanguageHasTheSameKeys() {
        XCTAssertEqual(tellomiLangPackLanguageCodes.count, 32)
        let english = tellomiBundledStrings(languageCode: "en")
        XCTAssertGreaterThan(english.count, 150)
        for code in tellomiLangPackLanguageCodes {
            let strings = tellomiBundledStrings(languageCode: code)
            XCTAssertEqual(Set(strings.keys), Set(english.keys), code)
            for (key, value) in strings {
                XCTAssertFalse(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "\(code) \(key)")
                XCTAssertEqual(placeholders(value), placeholders(english[key] ?? ""), "\(code) \(key)")
            }
        }
    }

    func testOfficialWordingAndCanonicalCodes() {
        XCTAssertEqual(tellomiBundledString(languageCode: "de", key: "Tellomi.Settings.Privacy"), "Privatsphäre und Sicherheit")
        XCTAssertEqual(tellomiBundledString(languageCode: "zh-Hans", key: "Tellomi.Discover.ConfirmCity"), "确定")
        XCTAssertEqual(tellomiBundledString(languageCode: "zh-Hant", key: "Tellomi.Discover.ChangeCity"), "更換城市")
        XCTAssertEqual(tellomiBundledString(languageCode: "ja", key: "Tellomi.Tabs.Me"), "自分")
        XCTAssertEqual(tellomiCanonicalLangPackCode("pt-PT"), "pt-br")
        XCTAssertEqual(tellomiCanonicalLangPackCode("zh-HK"), "zh-hant")
        XCTAssertEqual(tellomiCanonicalLangPackCode("en-US"), "en")
    }

    private func placeholders(_ value: String) -> [String] {
        guard let expression = try? NSRegularExpression(pattern: "%(?:\\d+\\$)?[@ds]", options: []) else {
            return []
        }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return expression.matches(in: value, options: [], range: range).compactMap { match in
            Range(match.range, in: value).map { String(value[$0]) }
        }
    }
}
