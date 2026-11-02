import XCTest
import Postbox
@testable import TelegramCore

final class TellomiFeatureGateTests: XCTestCase {
    private func configuration(_ fields: [String: JSON]) -> AppConfiguration {
        return AppConfiguration(data: .dictionary(fields), hash: 0)
    }

    func testMissingKeysHideEveryGatedFeature() {
        let gate = TellomiFeatureGate.with(appConfiguration: AppConfiguration.defaultValue)
        XCTAssertFalse(gate.aiComposeEnabled)
        XCTAssertFalse(gate.translateEnabled)
        XCTAssertFalse(gate.premiumEnabled)
        XCTAssertFalse(gate.starsEnabled)
        XCTAssertFalse(gate.giftsEnabled)
        XCTAssertFalse(gate.walletEnabled)
        XCTAssertFalse(gate.fragmentEnabled)
        XCTAssertFalse(gate.channelAdsEnabled)
        XCTAssertFalse(gate.businessEnabled)
        XCTAssertFalse(gate.boostsEnabled)
        XCTAssertFalse(gate.passportEnabled)
        XCTAssertFalse(gate.aiSummaryEnabled)
    }

    func testOfficialPurchaseFlagsAndTellomiOptIns() {
        let blocked = TellomiFeatureGate.with(appConfiguration: configuration([
            "premium_purchase_blocked": .bool(true),
            "stars_purchase_blocked": .number(1),
            "tellomi_ai_compose_enabled": .bool(true),
            "tellomi_translate_enabled": .string("enabled"),
            "tellomi_gifts_enabled": .bool(true),
            "stargifts_blocked": .bool(true)
        ]))
        XCTAssertFalse(blocked.premiumEnabled)
        XCTAssertFalse(blocked.starsEnabled)
        XCTAssertTrue(blocked.aiComposeEnabled)
        XCTAssertTrue(blocked.translateEnabled)
        XCTAssertFalse(blocked.giftsEnabled)

        let open = TellomiFeatureGate.with(appConfiguration: configuration([
            "premium_purchase_blocked": .bool(false),
            "stars_purchase_blocked": .bool(false),
            "tellomi_gifts_enabled": .bool(true),
            "stargifts_blocked": .bool(false),
            "tellomi_wallet_enabled": .bool(true)
        ]))
        XCTAssertTrue(open.premiumEnabled)
        XCTAssertTrue(open.starsEnabled)
        XCTAssertTrue(open.giftsEnabled)
        XCTAssertTrue(open.walletEnabled)
    }

    func testAiComposeRespectsSecretChatsAndKillSwitch() {
        let configuration = configuration(["tellomi_ai_compose_enabled": .bool(true)])
        let user = PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(1))
        let secret = PeerId(namespace: Namespaces.Peer.SecretChat, id: PeerId.Id._internalFromInt64Value(2))
        XCTAssertTrue(TellomiFeatureGate.aiComposeEnabled(appConfiguration: configuration, peerId: user, killSwitchKey: "ios_disable_ai_chat"))
        XCTAssertFalse(TellomiFeatureGate.aiComposeEnabled(appConfiguration: configuration, peerId: secret, killSwitchKey: "ios_disable_ai_chat"))
        XCTAssertFalse(TellomiFeatureGate.aiComposeEnabled(appConfiguration: configuration, peerId: nil, killSwitchKey: "ios_disable_ai_chat"))

        let killed = configuration(["tellomi_ai_compose_enabled": .bool(true), "ios_disable_ai_chat": .number(1)])
        XCTAssertFalse(TellomiFeatureGate.aiComposeEnabled(appConfiguration: killed, peerId: user, killSwitchKey: "ios_disable_ai_chat"))
        XCTAssertFalse(TellomiFeatureGate.aiComposeEnabled(appConfiguration: AppConfiguration.defaultValue, peerId: user, killSwitchKey: "ios_disable_ai_chat"))
    }
}
