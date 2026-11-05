import Foundation
import SwiftSignalKit
import TelegramCore

/// Per-account Discover activity pushes (D-18). Missing means on.
/// The same value is written to `account.updateNotifySettings` for user 777005,
/// which is the filter `pkg/push` already applies.
public struct TellomiDiscoverNotificationSettings: Equatable, Codable {
    public var enabled: Bool

    public static var defaultSettings: TellomiDiscoverNotificationSettings {
        return TellomiDiscoverNotificationSettings(enabled: true)
    }

    public init(enabled: Bool) {
        self.enabled = enabled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: StringCodingKey.self)
        if let value = try container.decodeIfPresent(Int32.self, forKey: "enabled") {
            self.enabled = value != 0
        } else {
            self.enabled = true
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringCodingKey.self)
        try container.encode((self.enabled ? 1 : 0) as Int32, forKey: "enabled")
    }
}

public func tellomiDiscoverNotificationSettings(entry: EnginePreferencesEntry?) -> TellomiDiscoverNotificationSettings {
    if let value = entry?.get(TellomiDiscoverNotificationSettings.self) {
        return value
    }
    return .defaultSettings
}

public func updateTellomiDiscoverNotificationSettings(engine: TelegramEngine, _ f: @escaping (TellomiDiscoverNotificationSettings) -> TellomiDiscoverNotificationSettings) -> Signal<Never, NoError> {
    return engine.preferences.update(id: ApplicationSpecificPreferencesKeys.tellomiDiscoverNotificationSettings, { entry in
        let current = tellomiDiscoverNotificationSettings(entry: entry)
        return SharedPreferencesEntry(f(current))
    })
}
