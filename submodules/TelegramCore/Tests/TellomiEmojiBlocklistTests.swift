import XCTest
import Postbox
@testable import TelegramCore

final class TellomiEmojiBlocklistTests: XCTestCase {
    private let taiwan = TellomiEmojiBlocklist.taiwanFlag
    private let china = "\u{1F1E8}\u{1F1F3}"
    private let grin = "\u{1F600}"

    override func tearDown() {
        TellomiEmojiBlocklist.apply(entries: nil)
        super.tearDown()
    }

    func testTheBuiltInListBlocksTheTaiwanFlagOnly() {
        TellomiEmojiBlocklist.apply(entries: nil)
        XCTAssertTrue(TellomiEmojiBlocklist.isBlocked(self.taiwan))
        XCTAssertTrue(TellomiEmojiBlocklist.isBlocked(self.taiwan + "\u{FE0F}"))
        XCTAssertFalse(TellomiEmojiBlocklist.isBlocked(self.china))
        XCTAssertFalse(TellomiEmojiBlocklist.isBlocked(self.grin))
        XCTAssertFalse(TellomiEmojiBlocklist.isBlocked("TW"))
        XCTAssertFalse(TellomiEmojiBlocklist.isBlocked("台湾"))
        XCTAssertFalse(TellomiEmojiBlocklist.isBlocked("Taiwan"))
        XCTAssertFalse(TellomiEmojiBlocklist.isBlocked("1F1F9-1F1FC"))
    }

    func testACodepointSequenceBlocksTheSameFlag() {
        TellomiEmojiBlocklist.apply(entries: ["U+1F1F9 U+1F1FC", "1F602"])
        XCTAssertTrue(TellomiEmojiBlocklist.isBlocked(self.taiwan))
        XCTAssertTrue(TellomiEmojiBlocklist.isBlocked("\u{1F602}"))
        XCTAssertFalse(TellomiEmojiBlocklist.isBlocked(self.grin))
        XCTAssertFalse(TellomiEmojiBlocklist.isBlocked(self.china))

        TellomiEmojiBlocklist.apply(entries: ["1F1F9-1F1FC"])
        XCTAssertTrue(TellomiEmojiBlocklist.isBlocked(self.taiwan))
        XCTAssertFalse(TellomiEmojiBlocklist.isBlocked("\u{1F602}"))
    }

    func testAnOverrideReplacesTheDefaultAndAnEmptyListClearsIt() {
        TellomiEmojiBlocklist.apply(entries: [self.grin])
        XCTAssertFalse(TellomiEmojiBlocklist.isBlocked(self.taiwan))
        XCTAssertTrue(TellomiEmojiBlocklist.isBlocked(self.grin))

        TellomiEmojiBlocklist.apply(entries: [])
        XCTAssertFalse(TellomiEmojiBlocklist.isBlocked(self.taiwan))
        XCTAssertFalse(TellomiEmojiBlocklist.isBlocked(self.grin))

        TellomiEmojiBlocklist.apply(entries: nil)
        XCTAssertTrue(TellomiEmojiBlocklist.isBlocked(self.taiwan))
        XCTAssertFalse(TellomiEmojiBlocklist.isBlocked(self.grin))
    }

    func testFilteringDropsBlockedEmojiAndKeepsOrder() {
        TellomiEmojiBlocklist.apply(entries: nil)
        XCTAssertEqual(TellomiEmojiBlocklist.filtering([self.grin, self.taiwan, self.china, "x" + self.taiwan]), [self.grin, self.china])
    }

    func testAppConfigReplacesTheListWhenTheKeyIsAnArrayOfStrings() {
        TellomiEmojiBlocklist.apply(entries: nil)
        TellomiEmojiBlocklist.apply(appConfiguration: AppConfiguration(data: JSON.dictionary([
            TellomiEmojiBlocklist.appConfigKey: .array([.string(self.grin), .string("U+1F1F9 U+1F1FC")])
        ]), hash: 1))
        XCTAssertTrue(TellomiEmojiBlocklist.isBlocked(self.taiwan))
        XCTAssertTrue(TellomiEmojiBlocklist.isBlocked(self.grin))
        XCTAssertFalse(TellomiEmojiBlocklist.isBlocked(self.china))

        TellomiEmojiBlocklist.apply(appConfiguration: AppConfiguration(data: JSON.dictionary([
            TellomiEmojiBlocklist.appConfigKey: .array([])
        ]), hash: 2))
        XCTAssertFalse(TellomiEmojiBlocklist.isBlocked(self.taiwan))

        TellomiEmojiBlocklist.apply(appConfiguration: AppConfiguration(data: JSON.dictionary([
            "unrelated": .bool(true)
        ]), hash: 3))
        XCTAssertTrue(TellomiEmojiBlocklist.isBlocked(self.taiwan))
        XCTAssertFalse(TellomiEmojiBlocklist.isBlocked(self.grin))

        TellomiEmojiBlocklist.apply(entries: [self.grin])
        TellomiEmojiBlocklist.apply(appConfiguration: AppConfiguration(data: JSON.dictionary([
            TellomiEmojiBlocklist.appConfigKey: .number(1)
        ]), hash: 4))
        XCTAssertFalse(TellomiEmojiBlocklist.isBlocked(self.grin))
        XCTAssertTrue(TellomiEmojiBlocklist.isBlocked(self.taiwan))
    }

    func testKeywordResultsDropBlockedEmoticons() {
        TellomiEmojiBlocklist.apply(entries: nil)
        let mixed = EmojiKeywordItem(index: ItemCollectionItemIndex(index: 0, id: 1), collectionId: 2, keyword: "taiwan", emoticons: [self.taiwan, self.grin], indexKeys: [])
        let onlyFlag = EmojiKeywordItem(index: ItemCollectionItemIndex(index: 1, id: 2), collectionId: 2, keyword: "tw", emoticons: [self.taiwan], indexKeys: [])
        let kept = EmojiKeywordItem(index: ItemCollectionItemIndex(index: 2, id: 3), collectionId: 2, keyword: "smile", emoticons: [self.grin], indexKeys: [])

        let filtered = tellomiFilteredEmojiKeywords([mixed, onlyFlag, kept])
        XCTAssertEqual(filtered.count, 2)
        XCTAssertEqual(filtered[0].keyword, "taiwan")
        XCTAssertEqual(filtered[0].emoticons, [self.grin])
        XCTAssertEqual(filtered[1].emoticons, [self.grin])
        XCTAssertTrue(filtered[1] === kept)
    }
}
