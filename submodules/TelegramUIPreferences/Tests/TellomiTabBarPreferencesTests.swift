import Foundation
import XCTest

final class TellomiTabBarPreferencesTests: XCTestCase {
    func testFreshInstallShowsMomentsChatsAndSettings() {
        let tabs = tellomiVisibleRootTabs(preferences: .freshInstall, available: Set(TellomiRootTab.allCases))
        XCTAssertEqual(tabs, [.moments, .chats, .settings])
    }

    func testChatsAndSettingsStayWhenEveryOtherTabIsHidden() {
        var preferences = TellomiTabBarPreferences.freshInstall
        for tab in TellomiRootTab.allCases {
            preferences = preferences.updating(tab, shown: false)
        }
        let tabs = tellomiVisibleRootTabs(preferences: preferences, available: Set(TellomiRootTab.allCases))
        XCTAssertEqual(tabs, [.chats, .settings])
        XCTAssertTrue(preferences.isShown(.chats))
        XCTAssertTrue(preferences.isShown(.settings))
        XCTAssertTrue(TellomiRootTab.chats.switchLocked)
        XCTAssertTrue(TellomiRootTab.settings.switchLocked)
        XCTAssertFalse(TellomiRootTab.moments.switchLocked)
        XCTAssertFalse(TellomiRootTab.contacts.switchLocked)
        XCTAssertFalse(TellomiRootTab.calls.switchLocked)
    }

    func testReenabledTabsKeepDisplayOrderAndSettingsLast() {
        var preferences = TellomiTabBarPreferences.freshInstall
        preferences = preferences.updating(.calls, shown: true)
        preferences = preferences.updating(.contacts, shown: true)
        preferences = preferences.updating(.news, shown: true)
        let tabs = tellomiVisibleRootTabs(preferences: preferences, available: Set(TellomiRootTab.allCases))
        XCTAssertEqual(tabs, [.moments, .chats, .contacts, .calls, .news, .settings])
    }

    func testNewsStaysOutUntilTheFeatureIsAvailable() {
        let preferences = TellomiTabBarPreferences.freshInstall.updating(.news, shown: true)
        let hidden = tellomiVisibleRootTabs(preferences: preferences, available: [.moments, .chats, .contacts, .calls, .settings])
        XCTAssertFalse(hidden.contains(.news))
        let shown = tellomiVisibleRootTabs(preferences: preferences, available: Set(TellomiRootTab.allCases))
        XCTAssertEqual(shown, [.moments, .chats, .news, .settings])
    }

    func testLockedTabsAreInsertedWhenTheAvailableSetForgetsThem() {
        let tabs = tellomiVisibleRootTabs(preferences: .freshInstall, available: [.moments])
        XCTAssertEqual(tabs, [.moments, .chats, .settings])
    }

    func testFirstLaunchHidesCallsUnlessThePersonAlreadyChose() {
        let fresh = tellomiPreferencesForFirstLaunch(calls: TellomiCallsTabMigration(showTab: true, explicit: false))
        XCTAssertFalse(fresh.isShown(.calls))
        XCTAssertTrue(fresh.isShown(.moments))

        let keptOn = tellomiPreferencesForFirstLaunch(calls: TellomiCallsTabMigration(showTab: true, explicit: true))
        XCTAssertTrue(keptOn.isShown(.calls))

        let keptOff = tellomiPreferencesForFirstLaunch(calls: TellomiCallsTabMigration(showTab: false, explicit: true))
        XCTAssertFalse(keptOff.isShown(.calls))
    }

    func testCodableRoundTripRepairsAnAttemptToHideChats() {
        var preferences = TellomiTabBarPreferences.freshInstall
        preferences.hideButtonTitles = true
        preferences = preferences.updating(.contacts, shown: true)
        let data = try! JSONEncoder().encode(preferences)
        let loaded = try! JSONDecoder().decode(TellomiTabBarPreferences.self, from: data).normalized()
        XCTAssertTrue(loaded.hideButtonTitles)
        XCTAssertTrue(loaded.isShown(.contacts))
        XCTAssertFalse(loaded.isShown(.calls))
        XCTAssertTrue(loaded.isShown(.chats))
        XCTAssertTrue(loaded.isShown(.settings))

        let object = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual((object["hideButtonTitles"] as? NSNumber)?.intValue, 1)
        XCTAssertEqual(object["shownTabs"] as? [String], ["moments", "chats", "contacts", "settings"])

        let broken = try! JSONSerialization.data(withJSONObject: ["hideButtonTitles": 0, "shownTabs": ["moments"]])
        let repaired = try! JSONDecoder().decode(TellomiTabBarPreferences.self, from: broken).normalized()
        XCTAssertTrue(repaired.isShown(.chats))
        XCTAssertTrue(repaired.isShown(.settings))
        XCTAssertTrue(repaired.isShown(.moments))
        XCTAssertFalse(repaired.isShown(.contacts))
    }

    func testLegacyDefaultsImportAndAMissingRecord() {
        let name = "tellomi-tab-bar-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer {
            defaults.removePersistentDomain(forName: name)
        }
        XCTAssertNil(tellomiLegacyTabBarPreferences(defaults: defaults))

        defaults.set(true, forKey: TellomiLegacyTabBarPreferenceKey.saved)
        defaults.set(true, forKey: TellomiLegacyTabBarPreferenceKey.hideButtonTitles)
        defaults.set(["moments"], forKey: TellomiLegacyTabBarPreferenceKey.shownTabs)
        guard let imported = tellomiLegacyTabBarPreferences(defaults: defaults) else {
            XCTFail("legacy record missing")
            return
        }
        XCTAssertTrue(imported.hideButtonTitles)
        XCTAssertTrue(imported.isShown(.moments))
        XCTAssertTrue(imported.isShown(.chats))
        XCTAssertTrue(imported.isShown(.settings))
        XCTAssertFalse(imported.isShown(.contacts))
    }

    func testFirstLaunchWithoutARecordHidesCallsAndPersistsBothRecords() {
        let step = tellomiTabBarStep(
            snapshot: TellomiTabBarSnapshot(preferences: nil, callsShowTab: true, callsExplicit: false),
            appliedCallsShowTab: true,
            legacy: nil
        )
        XCTAssertEqual(step.preferences, .freshInstall)
        XCTAssertFalse(step.preferences.isShown(.calls))
        XCTAssertTrue(step.persistPreferences)
        XCTAssertEqual(step.persistCallsShowTab, false)
        XCTAssertEqual(step.appliedCallsShowTab, false)
    }

    func testExplicitCallsChoiceIsKeptOnFirstLaunch() {
        let step = tellomiTabBarStep(
            snapshot: TellomiTabBarSnapshot(preferences: nil, callsShowTab: true, callsExplicit: true),
            appliedCallsShowTab: true,
            legacy: nil
        )
        XCTAssertTrue(step.preferences.isShown(.calls))
        XCTAssertTrue(step.preferences.isShown(.moments))
        XCTAssertNil(step.persistCallsShowTab)
    }

    func testLegacyRecordIsUsedOnlyWhenTheSharedRecordIsMissing() {
        let legacy = TellomiTabBarPreferences(hideButtonTitles: true, shown: [.moments, .chats, .contacts, .settings])
        let step = tellomiTabBarStep(
            snapshot: TellomiTabBarSnapshot(preferences: nil, callsShowTab: true, callsExplicit: false),
            appliedCallsShowTab: true,
            legacy: legacy
        )
        XCTAssertTrue(step.preferences.hideButtonTitles)
        XCTAssertTrue(step.preferences.isShown(.contacts))
        XCTAssertFalse(step.preferences.isShown(.calls))

        let stored = TellomiTabBarPreferences.freshInstall
        let ignored = tellomiTabBarStep(
            snapshot: TellomiTabBarSnapshot(preferences: stored, callsShowTab: false, callsExplicit: true),
            appliedCallsShowTab: false,
            legacy: legacy
        )
        XCTAssertFalse(ignored.preferences.hideButtonTitles)
        XCTAssertFalse(ignored.persistPreferences)
        XCTAssertNil(ignored.persistCallsShowTab)
    }

    func testMenuChangePushesCallsAndAStaleCallsValueDoesNotUndoIt() {
        let menu = TellomiTabBarPreferences.freshInstall.updating(.calls, shown: true)
        let step = tellomiTabBarStep(
            snapshot: TellomiTabBarSnapshot(preferences: menu, callsShowTab: false, callsExplicit: true),
            appliedCallsShowTab: false,
            legacy: nil
        )
        XCTAssertTrue(step.preferences.isShown(.calls))
        XCTAssertFalse(step.persistPreferences)
        XCTAssertEqual(step.persistCallsShowTab, true)
        XCTAssertEqual(step.appliedCallsShowTab, true)

        let caughtUp = tellomiTabBarStep(
            snapshot: TellomiTabBarSnapshot(preferences: menu, callsShowTab: true, callsExplicit: true),
            appliedCallsShowTab: step.appliedCallsShowTab,
            legacy: nil
        )
        XCTAssertFalse(caughtUp.persistPreferences)
        XCTAssertNil(caughtUp.persistCallsShowTab)
    }

    func testCallsSwitchUpdatesTheMenu() {
        let step = tellomiTabBarStep(
            snapshot: TellomiTabBarSnapshot(preferences: .freshInstall, callsShowTab: true, callsExplicit: true),
            appliedCallsShowTab: false,
            legacy: nil
        )
        XCTAssertTrue(step.preferences.isShown(.calls))
        XCTAssertTrue(step.persistPreferences)
        XCTAssertNil(step.persistCallsShowTab)
        XCTAssertEqual(step.appliedCallsShowTab, true)
    }

    func testSettingsTabUsesTheAccountPhotoWithoutAnotherAccount() {
        XCTAssertTrue(tellomiSettingsTabShowsAccountAvatar(hasProfilePhoto: true, hasOtherAccounts: false))
        XCTAssertTrue(tellomiSettingsTabShowsAccountAvatar(hasProfilePhoto: true, hasOtherAccounts: true))
        XCTAssertTrue(tellomiSettingsTabShowsAccountAvatar(hasProfilePhoto: false, hasOtherAccounts: true))
        XCTAssertFalse(tellomiSettingsTabShowsAccountAvatar(hasProfilePhoto: false, hasOtherAccounts: false))
    }

    func testUnchangedSnapshotDoesNotWrite() {
        let preferences = TellomiTabBarPreferences.freshInstall.updating(.contacts, shown: true)
        let step = tellomiTabBarStep(
            snapshot: TellomiTabBarSnapshot(preferences: preferences, callsShowTab: false, callsExplicit: true),
            appliedCallsShowTab: false,
            legacy: nil
        )
        XCTAssertEqual(step.preferences, preferences)
        XCTAssertFalse(step.persistPreferences)
        XCTAssertNil(step.persistCallsShowTab)
    }
}
