import Foundation

/// A root tab the Tellomi tab bar can show.
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

enum TellomiTabBarPreferencesKeys {
    static let saved = "saved"
    static let hideButtonTitles = "hideButtonTitles"
    static let shownTabs = "shownTabs"
    static let callsMigrationApplied = "callsMigrationApplied"
}

/// Per-device tab bar choices. The suite is not iCloud and not an account record.
public final class TellomiTabBarPreferencesStore {
    public static let shared = TellomiTabBarPreferencesStore()
    public static let didChangeNotification = Notification.Name("TellomiTabBarPreferencesDidChange")
    public static let suiteName = "app.tellomi.chat.tab-bar"

    public let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public convenience init() {
        let defaults = UserDefaults(suiteName: TellomiTabBarPreferencesStore.suiteName) ?? .standard
        self.init(defaults: defaults)
    }

    public var hasStoredValue: Bool {
        return self.defaults.bool(forKey: TellomiTabBarPreferencesKeys.saved)
    }

    public var hasAppliedCallsMigration: Bool {
        return self.defaults.bool(forKey: TellomiTabBarPreferencesKeys.callsMigrationApplied)
    }

    public func markCallsMigrationApplied() {
        self.defaults.set(true, forKey: TellomiTabBarPreferencesKeys.callsMigrationApplied)
    }

    public func load() -> TellomiTabBarPreferences {
        guard self.hasStoredValue else {
            return .freshInstall
        }
        let hide = self.defaults.bool(forKey: TellomiTabBarPreferencesKeys.hideButtonTitles)
        let raw = self.defaults.stringArray(forKey: TellomiTabBarPreferencesKeys.shownTabs) ?? []
        var shown = Set<TellomiRootTab>()
        for value in raw {
            if let tab = TellomiRootTab(rawValue: value) {
                shown.insert(tab)
            }
        }
        return TellomiTabBarPreferences(hideButtonTitles: hide, shown: shown).normalized()
    }

    public func save(_ preferences: TellomiTabBarPreferences) {
        let normalized = preferences.normalized()
        if self.hasStoredValue && self.load() == normalized {
            return
        }
        self.defaults.set(true, forKey: TellomiTabBarPreferencesKeys.saved)
        self.defaults.set(normalized.hideButtonTitles, forKey: TellomiTabBarPreferencesKeys.hideButtonTitles)
        let shown = TellomiRootTab.displayOrder.filter { normalized.shown.contains($0) }.map { $0.rawValue }
        self.defaults.set(shown, forKey: TellomiTabBarPreferencesKeys.shownTabs)
        NotificationCenter.default.post(name: TellomiTabBarPreferencesStore.didChangeNotification, object: self)
    }

    public func update(_ body: (TellomiTabBarPreferences) -> TellomiTabBarPreferences) {
        self.save(body(self.load()))
    }
}
