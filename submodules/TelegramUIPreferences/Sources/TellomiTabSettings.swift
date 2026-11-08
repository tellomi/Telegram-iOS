import Foundation
import SwiftSignalKit
import TelegramCore

/// Device-wide visibility for the Discover and Contacts tabs (M2 / D-5, D-6).
/// Chats and Settings are not stored: they stay in the bar (D-7).
/// Calls stay on `CallListSettings`. A missing record is the fresh-install default.
public struct TellomiTabSettings: Equatable, Codable {
    public var showFeedTab: Bool
    public var showContactsTab: Bool
    public var hideTabTitles: Bool

    public static var defaultSettings: TellomiTabSettings {
        return TellomiTabSettings(showFeedTab: true, showContactsTab: false, hideTabTitles: false)
    }

    public init(showFeedTab: Bool, showContactsTab: Bool, hideTabTitles: Bool = false) {
        self.showFeedTab = showFeedTab
        self.showContactsTab = showContactsTab
        self.hideTabTitles = hideTabTitles
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
        if let value = try container.decodeIfPresent(Int32.self, forKey: "hideTabTitles") {
            self.hideTabTitles = value != 0
        } else {
            self.hideTabTitles = false
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringCodingKey.self)
        try container.encode((self.showFeedTab ? 1 : 0) as Int32, forKey: "showFeedTab")
        try container.encode((self.showContactsTab ? 1 : 0) as Int32, forKey: "showContactsTab")
        try container.encode((self.hideTabTitles ? 1 : 0) as Int32, forKey: "hideTabTitles")
    }

    public func withUpdatedShowFeedTab(_ showFeedTab: Bool) -> TellomiTabSettings {
        return TellomiTabSettings(showFeedTab: showFeedTab, showContactsTab: self.showContactsTab, hideTabTitles: self.hideTabTitles)
    }

    public func withUpdatedShowContactsTab(_ showContactsTab: Bool) -> TellomiTabSettings {
        return TellomiTabSettings(showFeedTab: self.showFeedTab, showContactsTab: showContactsTab, hideTabTitles: self.hideTabTitles)
    }

    public func withUpdatedHideTabTitles(_ hideTabTitles: Bool) -> TellomiTabSettings {
        return TellomiTabSettings(showFeedTab: self.showFeedTab, showContactsTab: self.showContactsTab, hideTabTitles: hideTabTitles)
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

// Tab order, the startup index, and the bar labels live in TellomiTabNavigationDecisions.swift
// so the host test can compile them without TelegramCore.

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
