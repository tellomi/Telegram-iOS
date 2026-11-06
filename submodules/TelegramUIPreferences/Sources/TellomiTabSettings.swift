import Foundation
import SwiftSignalKit
import TelegramCore

/// Device-wide visibility for the Discover and Contacts tabs (M2 / D-5, D-6).
/// Chats and Settings are not stored: they stay in the bar (D-7).
/// Calls stay on `CallListSettings`. A missing record is the fresh-install default.
public struct TellomiTabSettings: Equatable, Codable {
    public var showFeedTab: Bool
    public var showContactsTab: Bool

    public static var defaultSettings: TellomiTabSettings {
        return TellomiTabSettings(showFeedTab: true, showContactsTab: false)
    }

    public init(showFeedTab: Bool, showContactsTab: Bool) {
        self.showFeedTab = showFeedTab
        self.showContactsTab = showContactsTab
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: StringCodingKey.self)
        if let value = try container.decodeIfPresent(Int32.self, forKey: "showFeedTab") {
            self.showFeedTab = value != 0
        } else {
            self.showFeedTab = true
        }
        if let value = try container.decodeIfPresent(Int32.self, forKey: "showContactsTab") {
            self.showContactsTab = value != 0
        } else {
            self.showContactsTab = false
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringCodingKey.self)
        try container.encode((self.showFeedTab ? 1 : 0) as Int32, forKey: "showFeedTab")
        try container.encode((self.showContactsTab ? 1 : 0) as Int32, forKey: "showContactsTab")
    }

    public func withUpdatedShowFeedTab(_ showFeedTab: Bool) -> TellomiTabSettings {
        return TellomiTabSettings(showFeedTab: showFeedTab, showContactsTab: self.showContactsTab)
    }

    public func withUpdatedShowContactsTab(_ showContactsTab: Bool) -> TellomiTabSettings {
        return TellomiTabSettings(showFeedTab: self.showFeedTab, showContactsTab: showContactsTab)
    }
}

public func updateTellomiTabSettingsInteractively(accountManager: AccountManager<TelegramAccountManagerTypes>, _ f: @escaping (TellomiTabSettings) -> TellomiTabSettings) -> Signal<Void, NoError> {
    return accountManager.transaction { transaction -> Void in
        transaction.updateSharedData(ApplicationSpecificSharedDataKeys.tellomiTabSettings, { entry in
            let currentSettings: TellomiTabSettings
            if let entry = entry?.get(TellomiTabSettings.self) {
                currentSettings = entry
            } else {
                currentSettings = .defaultSettings
            }
            let updated = f(currentSettings)
            tellomiRememberTabVisibility(updated)
            return SharedPreferencesEntry(updated)
        })
    }
}

/// `1` / `true` restores the upstream tab bar. A missing key keeps the Tellomi bar (D-4).
public let tellomiBottomNavigationKillSwitchKey = "ios_killswitch_disable_tellomi_tabs"

public func tellomiBottomNavigationEnabled(appConfiguration: AppConfiguration) -> Bool {
    guard let data = appConfiguration.data else {
        return true
    }
    guard let value = data[tellomiBottomNavigationKillSwitchKey] else {
        return true
    }
    if let value = value as? Bool {
        return !value
    }
    if let value = value as? Double {
        return value == 0.0
    }
    if let value = value as? String {
        switch value.lowercased() {
        case "1", "true", "yes", "on":
            return false
        default:
            return true
        }
    }
    return true
}

public enum TellomiRootTab: Equatable {
    case feed
    case chats
    case calls
    case contacts
    /// Upstream News. Off unless the parked feed API and the dev flag both say so.
    /// It sits in front of Settings so `controllers.count - 1` is still Settings.
    case news
    case settings
}

/// D-4 / D-42. Chats and Settings are always present (D-7).
public func tellomiRootTabOrder(showFeedTab: Bool, showCallsTab: Bool, showContactsTab: Bool, showNewsTab: Bool) -> [TellomiRootTab] {
    var tabs: [TellomiRootTab] = []
    if showFeedTab {
        tabs.append(.feed)
    }
    tabs.append(.chats)
    if showCallsTab {
        tabs.append(.calls)
    }
    if showContactsTab {
        tabs.append(.contacts)
    }
    if showNewsTab {
        tabs.append(.news)
    }
    tabs.append(.settings)
    return tabs
}

/// D-8. Restoring an account switch still lands on Settings, which is last.
public func tellomiStartupTabIndex(order: [TellomiRootTab], restoreSettings: Bool) -> Int {
    if restoreSettings, let index = order.lastIndex(of: .settings) {
        return index
    }
    return order.firstIndex(of: .chats) ?? 0
}

private struct TellomiTabVisibility: Equatable {
    var showFeedTab: Bool
    var showContactsTab: Bool
}

private let tellomiTabVisibilityState = Atomic<TellomiTabVisibility?>(value: nil)

public func tellomiRememberTabVisibility(_ settings: TellomiTabSettings) {
    let _ = tellomiTabVisibilityState.swap(TellomiTabVisibility(showFeedTab: settings.showFeedTab, showContactsTab: settings.showContactsTab))
}

/// Reads the account-manager record the root controller is about to build from.
public func tellomiCaptureLaunchTabs(_ transaction: AccountManagerModifier<TelegramAccountManagerTypes>) {
    let settings = transaction.getSharedData(ApplicationSpecificSharedDataKeys.tellomiTabSettings)?.get(TellomiTabSettings.self) ?? .defaultSettings
    tellomiRememberTabVisibility(settings)
}

public func tellomiEffectiveTabVisibility() -> (showFeedTab: Bool, showContactsTab: Bool) {
    if let value = tellomiTabVisibilityState.with({ $0 }) {
        return (value.showFeedTab, value.showContactsTab)
    }
    let defaults = TellomiTabSettings.defaultSettings
    return (defaults.showFeedTab, defaults.showContactsTab)
}

public func tellomiSetShowFeedTab(_ showFeedTab: Bool) {
    let current = tellomiEffectiveTabVisibility()
    let _ = tellomiTabVisibilityState.swap(TellomiTabVisibility(showFeedTab: showFeedTab, showContactsTab: current.showContactsTab))
}
