import Foundation
import TelegramCore
import SwiftSignalKit

public func resolvedTellomiTabBarPreferences(_ entry: SharedPreferencesEntry?) -> TellomiTabBarPreferences {
    if let value = entry?.get(TellomiTabBarPreferences.self) {
        return value.normalized()
    }
    return .freshInstall
}

public func tellomiTabBarSnapshot<T: AccountManagerTypes>(sharedData: AccountSharedDataView<T>) -> TellomiTabBarSnapshot {
    let calls = sharedData.entries[ApplicationSpecificSharedDataKeys.callListSettings]?.get(CallListSettings.self) ?? CallListSettings.defaultSettings
    let stored = sharedData.entries[ApplicationSpecificSharedDataKeys.tellomiTabBarPreferences]?.get(TellomiTabBarPreferences.self)
    return TellomiTabBarSnapshot(preferences: stored, callsShowTab: calls.showTab, callsExplicit: calls._showTab != nil)
}

public struct TellomiPreparedTabBarPreferences: Equatable {
    public var calls: CallListSettings
    public var preferences: TellomiTabBarPreferences
    public var consumedLegacy: Bool

    public init(calls: CallListSettings, preferences: TellomiTabBarPreferences, consumedLegacy: Bool) {
        self.calls = calls
        self.preferences = preferences
        self.consumedLegacy = consumedLegacy
    }
}

/// Writes the shared tab-bar record the first time it is missing, including a value left in the old `UserDefaults` suite.
/// An existing record is kept. Calls is updated only when the resolved menu disagrees with it.
public func tellomiPrepareTabBarPreferences(transaction: AccountManagerModifier<TelegramAccountManagerTypes>) -> TellomiPreparedTabBarPreferences {
    let calls = transaction.getSharedData(ApplicationSpecificSharedDataKeys.callListSettings)?.get(CallListSettings.self) ?? CallListSettings.defaultSettings
    let stored = transaction.getSharedData(ApplicationSpecificSharedDataKeys.tellomiTabBarPreferences)?.get(TellomiTabBarPreferences.self)
    let legacy = stored == nil ? tellomiLegacyTabBarPreferencesFromSuite() : nil
    let step = tellomiTabBarStep(
        snapshot: TellomiTabBarSnapshot(preferences: stored, callsShowTab: calls.showTab, callsExplicit: calls._showTab != nil),
        appliedCallsShowTab: calls.showTab,
        legacy: legacy
    )
    if step.persistPreferences {
        transaction.updateSharedData(ApplicationSpecificSharedDataKeys.tellomiTabBarPreferences, { _ in
            return SharedPreferencesEntry(step.preferences)
        })
    }
    var resolvedCalls = calls
    if let showTab = step.persistCallsShowTab, calls.showTab != showTab || calls._showTab == nil {
        resolvedCalls = calls.withUpdatedShowTab(showTab)
        transaction.updateSharedData(ApplicationSpecificSharedDataKeys.callListSettings, { _ in
            return SharedPreferencesEntry(resolvedCalls)
        })
    }
    return TellomiPreparedTabBarPreferences(calls: resolvedCalls, preferences: step.preferences, consumedLegacy: stored == nil && legacy != nil)
}

public func updateTellomiTabBarPreferencesInteractively(accountManager: AccountManager<TelegramAccountManagerTypes>, _ f: @escaping (TellomiTabBarPreferences) -> TellomiTabBarPreferences) -> Signal<Void, NoError> {
    return accountManager.transaction { transaction -> Void in
        transaction.updateSharedData(ApplicationSpecificSharedDataKeys.tellomiTabBarPreferences, { entry in
            let current = resolvedTellomiTabBarPreferences(entry)
            let updated = f(current).normalized()
            if let entry, current == updated {
                return entry
            }
            return SharedPreferencesEntry(updated)
        })
    }
}
