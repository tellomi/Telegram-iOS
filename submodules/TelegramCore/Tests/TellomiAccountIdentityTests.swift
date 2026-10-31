import XCTest
import Postbox
@testable import TelegramCore

final class TellomiAccountIdentityTests: XCTestCase {
    func testEmailMaskKeepsTheDomain() {
        XCTAssertEqual(tellomiMaskedEmail("alice@x.com"), "a***@x.com")
        XCTAssertEqual(tellomiMaskedEmail(" A@Example.COM "), "A***@Example.COM")
        XCTAssertEqual(tellomiMaskedEmail("ab@cd.co"), "a***@cd.co")
    }

    func testContactSplitsPhoneAndStoredEmail() {
        let peerId = PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(4242))
        UserDefaults.standard.removeObject(forKey: "TellomiLoginEmail.\(peerId.toInt64())")
        tellomiRememberLoginEmail(peerId: peerId, login: "owner@tellomi.cn")

        let both = tellomiAccountContact(phone: "8613800138000", peerId: peerId)
        XCTAssertEqual(both.phone, "8613800138000")
        XCTAssertEqual(both.email, "owner@tellomi.cn")

        let emailInPhoneField = tellomiAccountContact(phone: "owner@tellomi.cn", peerId: peerId)
        XCTAssertNil(emailInPhoneField.phone)
        XCTAssertEqual(emailInPhoneField.email, "owner@tellomi.cn")

        XCTAssertEqual(tellomiAccountSwitcherLabel(phone: "8613800138000", peerId: peerId), "8613800138000")
        XCTAssertEqual(tellomiAccountSwitcherLabel(phone: nil, peerId: peerId), "o***@tellomi.cn")

        UserDefaults.standard.removeObject(forKey: "TellomiLoginEmail.\(peerId.toInt64())")
    }

    func testIdentifierMatchCoversPhoneAndEmail() {
        XCTAssertTrue(tellomiLoginIdentifiersMatch("+86 138 0013 8000", "8613800138000"))
        XCTAssertTrue(tellomiLoginIdentifiersMatch("Owner@Tellomi.cn", "owner@tellomi.cn"))
        XCTAssertFalse(tellomiLoginIdentifiersMatch(" ", "8613800138000"))
        XCTAssertFalse(tellomiLoginIdentifiersMatch("owner@tellomi.cn", "8613800138000"))
        XCTAssertFalse(tellomiLoginIdentifiersMatch("", "a@b.co"))
    }

    func testWelcomeIsOnlyTheSignedOutRoot() {
        XCTAssertTrue(tellomiAuthorizationShowsWelcome(existingAccountCount: 0))
        XCTAssertFalse(tellomiAuthorizationShowsWelcome(existingAccountCount: 1))
        XCTAssertFalse(tellomiAuthorizationShowsWelcome(existingAccountCount: 3))
    }

    func testLangPackFollowsTheFirstPreferredLanguage() {
        XCTAssertEqual(tellomiLangPackCode(preferredLanguages: ["zh-Hans-CN", "en"]), "zh-hans")
        XCTAssertEqual(tellomiLangPackCode(preferredLanguages: ["zh-Hant-TW"]), "zh-hant")
        XCTAssertEqual(tellomiLangPackCode(preferredLanguages: ["zh-HK"]), "zh-hant")
        XCTAssertEqual(tellomiLangPackCode(preferredLanguages: ["en-US", "zh-Hans"]), nil)
        XCTAssertNil(tellomiLangPackCode(preferredLanguages: []))
    }
}
