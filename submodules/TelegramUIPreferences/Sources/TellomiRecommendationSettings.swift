import Foundation
import SwiftSignalKit
import TelegramCore

/// Per-account Discover recommendation switch (D-58). Missing means on.
public struct TellomiRecommendationSettings: Equatable, Codable {
    public var personalized: Bool

    public static var defaultSettings: TellomiRecommendationSettings {
        return TellomiRecommendationSettings(personalized: true)
    }

    public init(personalized: Bool) {
        self.personalized = personalized
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: StringCodingKey.self)
        if let value = try container.decodeIfPresent(Int32.self, forKey: "personalized") {
            self.personalized = value != 0
        } else {
            self.personalized = true
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringCodingKey.self)
        try container.encode((self.personalized ? 1 : 0) as Int32, forKey: "personalized")
    }

    public func withUpdatedPersonalized(_ personalized: Bool) -> TellomiRecommendationSettings {
        return TellomiRecommendationSettings(personalized: personalized)
    }
}

public func tellomiRecommendationSettings(entry: EnginePreferencesEntry?) -> TellomiRecommendationSettings {
    if let value = entry?.get(TellomiRecommendationSettings.self) {
        return value
    }
    return .defaultSettings
}

public func updateTellomiRecommendationSettings(engine: TelegramEngine, _ f: @escaping (TellomiRecommendationSettings) -> TellomiRecommendationSettings) -> Signal<Never, NoError> {
    return engine.preferences.update(id: ApplicationSpecificPreferencesKeys.tellomiRecommendationSettings, { entry in
        let current = tellomiRecommendationSettings(entry: entry)
        return SharedPreferencesEntry(f(current))
    })
}
