import XCTest

/// Discover compose @mentions. The post body stays the existing text field.
final class TellomiDiscoverMentionTests: XCTestCase {
    private let nonce = "11111111-1111-4111-8111-111111111111"

    func testUsernameRulesMatchTheLocalClientCheck() {
        XCTAssertTrue(TellomiDiscoverMention.validUsername("abcd"))
        XCTAssertTrue(TellomiDiscoverMention.validUsername("A_b1"))
        XCTAssertTrue(TellomiDiscoverMention.validUsername("@abcd"))
        XCTAssertTrue(TellomiDiscoverMention.validUsername(String(repeating: "a", count: 32)))
        XCTAssertFalse(TellomiDiscoverMention.validUsername("abc"))
        XCTAssertFalse(TellomiDiscoverMention.validUsername("_abcd"))
        XCTAssertFalse(TellomiDiscoverMention.validUsername("abcd_"))
        XCTAssertFalse(TellomiDiscoverMention.validUsername("1abcd"))
        XCTAssertFalse(TellomiDiscoverMention.validUsername("ab-cd"))
        XCTAssertFalse(TellomiDiscoverMention.validUsername(String(repeating: "a", count: 33)))
        XCTAssertFalse(TellomiDiscoverMention.validUsername(nil))
        XCTAssertFalse(TellomiDiscoverMention.validUsername(""))
        XCTAssertEqual(TellomiDiscoverMention.minLength, 4)
        XCTAssertEqual(TellomiDiscoverMention.maxLength, 32)
    }

    func testParseKeepsOnlyRealMentions() {
        let mentions = TellomiDiscoverMention.parse("hi @abcd, (@efgh)\n@@ijkl mail a@mnop.com")
        XCTAssertEqual(mentions.count, 3)
        XCTAssertEqual(mentions[0].username, "abcd")
        XCTAssertEqual(mentions[1].username, "efgh")
        XCTAssertEqual(mentions[2].username, "ijkl")
        XCTAssertTrue(TellomiDiscoverMention.parse("@abc @_no @1no").isEmpty)
        XCTAssertEqual(TellomiDiscoverMention.invalid("see @abc."), ["abc"])
        XCTAssertTrue(TellomiDiscoverMention.invalid("just @").isEmpty)
        XCTAssertTrue(TellomiDiscoverMention.invalid("价格 @ 100").isEmpty)
    }

    func testInsertReplacesTheOpenToken() {
        let query = TellomiDiscoverMention.queryAt("hi @ab", caret: 6)
        XCTAssertEqual(query?.prefix, "ab")
        XCTAssertEqual(query?.at, 3)
        let insertion = TellomiDiscoverMention.insert("hi @ab", query: query, username: "alice")
        XCTAssertEqual(insertion?.text, "hi @alice ")
        XCTAssertEqual(insertion?.caret, ("hi @alice " as NSString).length)
        XCTAssertNil(TellomiDiscoverMention.queryAt(insertion?.text, caret: insertion?.caret ?? 0))
        XCTAssertNil(TellomiDiscoverMention.insert("hi @ab", query: query, username: "ab"))
        XCTAssertNil(TellomiDiscoverMention.queryAt("mail a@abcd", caret: 11))
        let typed = TellomiDiscoverMention.queryAt("@", caret: 1)
        XCTAssertEqual(typed?.prefix, "")
        let at = TellomiDiscoverMention.insert("@", query: typed, username: "abcd")
        XCTAssertEqual(at?.text, "@abcd ")
    }

    func testMentionPersonKeepsTheComposeCandidate() {
        let person = TellomiDiscoverMention.mentionPerson(username: "Alice", firstName: " 李 ", lastName: " 雷 ", isUser: true, isDeleted: false, isSelf: false)
        XCTAssertEqual(person, TellomiDiscoverMention.Person(username: "Alice", name: "李 雷"))
        let prefixed = TellomiDiscoverMention.mentionPerson(username: "@bobby", firstName: "Bob", lastName: nil, isUser: true, isDeleted: false, isSelf: false)
        XCTAssertEqual(prefixed?.username, "bobby")
        XCTAssertEqual(prefixed?.name, "Bob")
        XCTAssertEqual(TellomiDiscoverMention.mentionPerson(username: "cara", firstName: nil, lastName: " 娜 ", isUser: true, isDeleted: false, isSelf: false)?.name, "娜")
        XCTAssertEqual(TellomiDiscoverMention.mentionPerson(username: "dana", firstName: "  ", lastName: " ", isUser: true, isDeleted: false, isSelf: false)?.name, "")
        XCTAssertNil(TellomiDiscoverMention.mentionPerson(username: "alice", firstName: "自己", lastName: nil, isUser: true, isDeleted: false, isSelf: true))
        XCTAssertNil(TellomiDiscoverMention.mentionPerson(username: "groupname", firstName: nil, lastName: nil, isUser: false, isDeleted: false, isSelf: false))
        XCTAssertNil(TellomiDiscoverMention.mentionPerson(username: "gone", firstName: "已", lastName: "删", isUser: true, isDeleted: true, isSelf: false))
        XCTAssertNil(TellomiDiscoverMention.mentionPerson(username: "ab", firstName: "短", lastName: nil, isUser: true, isDeleted: false, isSelf: false))
        XCTAssertNil(TellomiDiscoverMention.mentionPerson(username: nil, firstName: "无", lastName: nil, isUser: true, isDeleted: false, isSelf: false))
        XCTAssertNil(TellomiDiscoverMention.mentionPerson(username: "_abcd", firstName: "线", lastName: nil, isUser: true, isDeleted: false, isSelf: false))
    }

    func testSuggestionsUseLocalUsernames() {
        let people = [
            TellomiDiscoverMention.Person(username: "Alice", name: "李雷"),
            TellomiDiscoverMention.Person(username: "alice", name: "重复"),
            TellomiDiscoverMention.Person(username: "bobby", name: "Bob"),
            TellomiDiscoverMention.Person(username: "ab", name: "太短"),
            TellomiDiscoverMention.Person(username: "cara", name: "李娜")
        ]
        let matched = TellomiDiscoverMention.suggestions(people, prefix: "al", limit: 6)
        XCTAssertEqual(matched.count, 1)
        XCTAssertEqual(matched[0].username, "Alice")
        XCTAssertEqual(matched[0].name, "李雷")
        let byName = TellomiDiscoverMention.suggestions(people, prefix: "李", limit: 6)
        XCTAssertEqual(byName.map(\.username), ["Alice", "cara"])
        XCTAssertEqual(TellomiDiscoverMention.suggestions(people, prefix: "", limit: 6).count, 3)
        XCTAssertTrue(TellomiDiscoverMention.suggestions(nil, prefix: "a", limit: 6).isEmpty)
    }

    func testPublishKeepsMentionsInsideText() {
        let body = tellomiDiscoverPublishBody(text: "hi @abcd", visibility: .everyone, audienceToken: nil, clientNonce: self.nonce, textLimit: 500)
        let object = try! JSONSerialization.jsonObject(with: body!) as! [String: Any]
        XCTAssertEqual(Set(object.keys), Set(["kind", "text", "visibility", "client_nonce"]))
        XCTAssertEqual(object["text"] as? String, "hi @abcd")
        XCTAssertNil(object["mentions"])
        XCTAssertNil(object["entities"])
        XCTAssertNil(object["link_preview"])
        XCTAssertNil(object["media"])
    }

    func testCopyUsesTheDiscoverPack() {
        let hans = TellomiDiscoverCopy.resolve(languageCode: "zh-Hans")
        XCTAssertEqual(hans.mention, "提及")
        XCTAssertEqual(hans.mentionHint, "写点什么，用 @ 提及用户")
        XCTAssertEqual(hans.mentionInvalid, "%s 不是有效用户名，对方收不到提及。")
        XCTAssertEqual(TellomiDiscoverCopy.resolve(languageCode: "en").mentionEmpty, "No matching username")
        XCTAssertEqual(TellomiDiscoverMention.invalidLine(template: hans.mentionInvalid, username: "abc"), "@abc 不是有效用户名，对方收不到提及。")
        let traditional = TellomiDiscoverCopy.resolve(languageCode: "zh-Hant")
        XCTAssertEqual(traditional.mentionHint, "寫點什麼，用 @ 提及使用者")
    }
}
