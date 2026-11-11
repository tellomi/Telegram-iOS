import Foundation

/// A root tab the tab bar can show.
///
/// Chats and Settings stay reachable: their switches are locked on, and a saved
/// value that tries to hide them is ignored.
public enum TellomiRootTab: String, CaseIterable, Codable, Equatable {
    case moments
    case chats
    case contacts
    case calls
    case news
    case settings

    /// Left to right on a fresh install, then the tabs a person can turn back on.
    public static let displayOrder: [TellomiRootTab] = [.moments, .chats, .contacts, .calls, .news, .settings]

    /// The tab bar always keeps these. The menu shows their switches on and disabled.
    public var switchLocked: Bool {
        switch self {
        case .chats, .settings:
            return true
        case .moments, .contacts, .calls, .news:
            return false
        }
    }
}

public struct TellomiTabBarPreferences: Equatable {
    public var hideButtonTitles: Bool
    /// Tabs the person has turned on. Locked tabs are always treated as on.
    public var shown: Set<TellomiRootTab>

    public init(hideButtonTitles: Bool, shown: Set<TellomiRootTab>) {
        self.hideButtonTitles = hideButtonTitles
        self.shown = shown
    }

    /// Moments, Chats, Settings. Contacts, Calls and News are off until turned on.
    public static let freshInstall = TellomiTabBarPreferences(
        hideButtonTitles: false,
        shown: [.moments, .chats, .settings]
    )

    public func normalized() -> TellomiTabBarPreferences {
        var shown = self.shown
        for tab in TellomiRootTab.allCases where tab.switchLocked {
            shown.insert(tab)
        }
        return TellomiTabBarPreferences(hideButtonTitles: self.hideButtonTitles, shown: shown)
    }

    public func isShown(_ tab: TellomiRootTab) -> Bool {
        if tab.switchLocked {
            return true
        }
        return self.normalized().shown.contains(tab)
    }

    /// Locked tabs ignore `shown: false`.
    public func updating(_ tab: TellomiRootTab, shown: Bool) -> TellomiTabBarPreferences {
        var next = self.normalized()
        if tab.switchLocked {
            return next
        }
        if shown {
            next.shown.insert(tab)
        } else {
            next.shown.remove(tab)
        }
        return next.normalized()
    }
}

extension TellomiTabBarPreferences: Codable {
    private struct Key: CodingKey {
        var stringValue: String
        init(_ stringValue: String) {
            self.stringValue = stringValue
        }
        init?(stringValue: String) {
            self.stringValue = stringValue
        }
        var intValue: Int? {
            return nil
        }
        init?(intValue: Int) {
            return nil
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        self.hideButtonTitles = (try container.decodeIfPresent(Int32.self, forKey: Key("hideButtonTitles")) ?? 0) != 0
        let raw = try container.decodeIfPresent([String].self, forKey: Key("shownTabs")) ?? []
        var shown = Set<TellomiRootTab>()
        for value in raw {
            if let tab = TellomiRootTab(rawValue: value) {
                shown.insert(tab)
            }
        }
        self.shown = shown
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        let normalized = self.normalized()
        try container.encode((normalized.hideButtonTitles ? 1 : 0) as Int32, forKey: Key("hideButtonTitles"))
        let shown = TellomiRootTab.displayOrder.filter { normalized.shown.contains($0) }.map { $0.rawValue }
        try container.encode(shown, forKey: Key("shownTabs"))
    }
}

/// What the existing Calls "show tab" preference said the first time this menu was opened.
public struct TellomiCallsTabMigration: Equatable {
    public var showTab: Bool
    /// True when the person had already moved the Calls switch. A missing value is not a choice.
    public var explicit: Bool

    public init(showTab: Bool, explicit: Bool) {
        self.showTab = showTab
        self.explicit = explicit
    }
}

/// Fresh install hides Calls. An explicit earlier choice is kept.
public func tellomiPreferencesForFirstLaunch(calls: TellomiCallsTabMigration) -> TellomiTabBarPreferences {
    var preferences = TellomiTabBarPreferences.freshInstall
    if calls.explicit {
        preferences = preferences.updating(.calls, shown: calls.showTab)
    }
    return preferences
}

/// Whether the settings tab draws the signed-in account instead of the gear.
///
/// A profile photo is enough on its own: that is the icon once the account has an avatar.
/// Another signed-in account also is, which is when the gear is replaced by the letter
/// placeholder so the accounts can be told apart. The gear, and its selection animation,
/// stay when neither is true.
public func tellomiSettingsTabShowsAccountAvatar(hasProfilePhoto: Bool, hasOtherAccounts: Bool) -> Bool {
    return hasProfilePhoto || hasOtherAccounts
}

/// Tabs that are both available in this build and turned on, in `displayOrder`.
/// Chats and Settings are included even when `available` forgets them.
public func tellomiVisibleRootTabs(preferences: TellomiTabBarPreferences, available: Set<TellomiRootTab>) -> [TellomiRootTab] {
    let preferences = preferences.normalized()
    return TellomiRootTab.displayOrder.filter { tab in
        if tab.switchLocked {
            return true
        }
        return available.contains(tab) && preferences.isShown(tab)
    }
}

/// The `UserDefaults` suite written by the first menu-settings build, before this moved into shared account data.
public let tellomiTabBarPreferencesLegacySuiteName = "app.tellomi.chat.tab-bar"

public enum TellomiLegacyTabBarPreferenceKey {
    public static let saved = "saved"
    public static let hideButtonTitles = "hideButtonTitles"
    public static let shownTabs = "shownTabs"
}

public func tellomiLegacyTabBarPreferences(defaults: UserDefaults) -> TellomiTabBarPreferences? {
    guard defaults.bool(forKey: TellomiLegacyTabBarPreferenceKey.saved) else {
        return nil
    }
    let hide = defaults.bool(forKey: TellomiLegacyTabBarPreferenceKey.hideButtonTitles)
    let raw = defaults.stringArray(forKey: TellomiLegacyTabBarPreferenceKey.shownTabs) ?? []
    var shown = Set<TellomiRootTab>()
    for value in raw {
        if let tab = TellomiRootTab(rawValue: value) {
            shown.insert(tab)
        }
    }
    return TellomiTabBarPreferences(hideButtonTitles: hide, shown: shown).normalized()
}

public func tellomiLegacyTabBarPreferencesFromSuite() -> TellomiTabBarPreferences? {
    guard let defaults = UserDefaults(suiteName: tellomiTabBarPreferencesLegacySuiteName) else {
        return nil
    }
    return tellomiLegacyTabBarPreferences(defaults: defaults)
}

public func tellomiClearLegacyTabBarPreferences() {
    guard let defaults = UserDefaults(suiteName: tellomiTabBarPreferencesLegacySuiteName) else {
        return
    }
    defaults.removeObject(forKey: TellomiLegacyTabBarPreferenceKey.saved)
    defaults.removeObject(forKey: TellomiLegacyTabBarPreferenceKey.hideButtonTitles)
    defaults.removeObject(forKey: TellomiLegacyTabBarPreferenceKey.shownTabs)
}

/// One reading of the shared tab-bar record and the Calls "show tab" record.
public struct TellomiTabBarSnapshot: Equatable {
    public var preferences: TellomiTabBarPreferences?
    public var callsShowTab: Bool
    public var callsExplicit: Bool

    public init(preferences: TellomiTabBarPreferences?, callsShowTab: Bool, callsExplicit: Bool) {
        self.preferences = preferences
        self.callsShowTab = callsShowTab
        self.callsExplicit = callsExplicit
    }
}

/// What to show, and which shared records to write, after one snapshot.
public struct TellomiTabBarStep: Equatable {
    public var preferences: TellomiTabBarPreferences
    public var persistPreferences: Bool
    public var persistCallsShowTab: Bool?
    public var appliedCallsShowTab: Bool

    public init(preferences: TellomiTabBarPreferences, persistPreferences: Bool, persistCallsShowTab: Bool?, appliedCallsShowTab: Bool) {
        self.preferences = preferences
        self.persistPreferences = persistPreferences
        self.persistCallsShowTab = persistCallsShowTab
        self.appliedCallsShowTab = appliedCallsShowTab
    }
}

/// Resolves the tab bar from the shared records.
///
/// A missing record is the first launch: Calls stays hidden unless that switch was already moved.
/// `legacy` is the previous `UserDefaults` suite, used only when the shared record is missing.
/// After that, a Calls switch that moved since `appliedCallsShowTab` updates the menu, and a menu
/// that moved while Calls has not updates the Calls switch. A stale Calls value does not undo a menu change.
public func tellomiTabBarStep(snapshot: TellomiTabBarSnapshot, appliedCallsShowTab: Bool, legacy: TellomiTabBarPreferences?) -> TellomiTabBarStep {
    if let stored = snapshot.preferences {
        var preferences = stored.normalized()
        var persistPreferences = preferences != stored
        var persistCalls: Bool?
        var applied = appliedCallsShowTab
        if snapshot.callsShowTab != applied {
            if preferences.isShown(.calls) != snapshot.callsShowTab {
                preferences = preferences.updating(.calls, shown: snapshot.callsShowTab)
                persistPreferences = true
            }
            applied = snapshot.callsShowTab
        } else if preferences.isShown(.calls) != snapshot.callsShowTab {
            persistCalls = preferences.isShown(.calls)
            applied = preferences.isShown(.calls)
        }
        return TellomiTabBarStep(preferences: preferences, persistPreferences: persistPreferences, persistCallsShowTab: persistCalls, appliedCallsShowTab: applied)
    }

    let calls = TellomiCallsTabMigration(showTab: snapshot.callsShowTab, explicit: snapshot.callsExplicit)
    let preferences = (legacy ?? tellomiPreferencesForFirstLaunch(calls: calls)).normalized()
    let persistCalls: Bool? = snapshot.callsShowTab == preferences.isShown(.calls) ? nil : preferences.isShown(.calls)
    return TellomiTabBarStep(preferences: preferences, persistPreferences: true, persistCallsShowTab: persistCalls, appliedCallsShowTab: preferences.isShown(.calls))
}
