import Foundation
import Postbox

/// Tellomi hides Telegram features the Teamgram server does not implement, plus
/// purchase, Fragment, and TON.
///
/// Official keys keep their names: `premium_purchase_blocked` and `stars_purchase_blocked`.
/// A missing key is treated as blocked. `tellomi_business_enabled`,
/// `tellomi_passport_enabled`, and `tellomi_boosts_enabled` default on: teamgram-server
/// implements those methods and does not send the keys. Sending `false` still hides them.
/// The other Tellomi keys stay off until the server sends `true`. Stories are not gated here.
public struct TellomiFeatureGate: Equatable {
    public static let aiComposeKey = "tellomi_ai_compose_enabled"
    public static let translateKey = "tellomi_translate_enabled"
    public static let giftsKey = "tellomi_gifts_enabled"
    public static let walletKey = "tellomi_wallet_enabled"
    public static let fragmentKey = "tellomi_fragment_enabled"
    public static let channelAdsKey = "tellomi_channel_ads_enabled"
    public static let businessKey = "tellomi_business_enabled"
    public static let boostsKey = "tellomi_boosts_enabled"
    public static let passportKey = "tellomi_passport_enabled"
    public static let aiSummaryKey = "tellomi_ai_summary_enabled"

    public static let premiumPurchaseBlockedKey = "premium_purchase_blocked"
    public static let starsPurchaseBlockedKey = "stars_purchase_blocked"
    public static let starGiftsBlockedKey = "stargifts_blocked"

    public let aiComposeEnabled: Bool
    public let translateEnabled: Bool
    public let premiumEnabled: Bool
    public let starsEnabled: Bool
    public let giftsEnabled: Bool
    public let walletEnabled: Bool
    public let fragmentEnabled: Bool
    public let channelAdsEnabled: Bool
    public let businessEnabled: Bool
    public let boostsEnabled: Bool
    public let passportEnabled: Bool
    public let aiSummaryEnabled: Bool

    public static func with(appConfiguration: AppConfiguration) -> TellomiFeatureGate {
        return with(data: appConfiguration.data)
    }

    public static func with(data: JSON?) -> TellomiFeatureGate {
        let fields: [String: JSON]
        if case let .dictionary(dictionary)? = data {
            fields = dictionary
        } else {
            fields = [:]
        }
        let premiumBlocked = flag(fields[premiumPurchaseBlockedKey], default: true)
        let starsBlocked = flag(fields[starsPurchaseBlockedKey], default: true)
        let starGiftsBlocked = flag(fields[starGiftsBlockedKey], default: true)
        let giftsRequested = flag(fields[giftsKey], default: false)
        return TellomiFeatureGate(
            aiComposeEnabled: flag(fields[aiComposeKey], default: false),
            translateEnabled: flag(fields[translateKey], default: false),
            premiumEnabled: !premiumBlocked,
            starsEnabled: !starsBlocked,
            giftsEnabled: giftsRequested && !starGiftsBlocked,
            walletEnabled: flag(fields[walletKey], default: false),
            fragmentEnabled: flag(fields[fragmentKey], default: false),
            channelAdsEnabled: flag(fields[channelAdsKey], default: false),
            businessEnabled: flag(fields[businessKey], default: true),
            boostsEnabled: flag(fields[boostsKey], default: true),
            passportEnabled: flag(fields[passportKey], default: true),
            aiSummaryEnabled: flag(fields[aiSummaryKey], default: false)
        )
    }

    /// AI compose stays off in secret chats and when the upstream kill switch is 1.
    /// `tellomi_ai_compose_enabled` missing is off, which replaces the four hardcoded `true`s.
    public static func aiComposeEnabled(appConfiguration: AppConfiguration, peerId: PeerId?, killSwitchKey: String) -> Bool {
        guard self.with(appConfiguration: appConfiguration).aiComposeEnabled else {
            return false
        }
        guard let peerId, peerId.namespace != Namespaces.Peer.SecretChat else {
            return false
        }
        // Read the dictionary directly. `JSON.subscript` lives in Utils/JSON.swift and
        // imports TelegramApi, which this file's host test does not compile.
        if case let .dictionary(fields)? = appConfiguration.data, case let .number(value)? = fields[killSwitchKey], value == 1.0 {
            return false
        }
        return true
    }

    static func flag(_ value: JSON?, default defaultValue: Bool) -> Bool {
        guard let value else {
            return defaultValue
        }
        switch value {
        case let .bool(bool):
            return bool
        case let .number(number):
            return number != 0
        case let .string(string):
            switch string.lowercased() {
            case "1", "true", "yes", "enabled":
                return true
            case "0", "false", "no", "disabled":
                return false
            default:
                return defaultValue
            }
        default:
            return defaultValue
        }
    }
}
