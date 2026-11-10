import Foundation
import XCTest

private final class TellomiNote {
    var value = 0
}

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

    func testStoreRoundTripAndIgnoredAttemptToHideChats() {
        let name = "tellomi-tab-bar-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer {
            defaults.removePersistentDomain(forName: name)
        }
        let store = TellomiTabBarPreferencesStore(defaults: defaults)
        XCTAssertFalse(store.hasStoredValue)
        XCTAssertEqual(store.load(), .freshInstall)

        var preferences = TellomiTabBarPreferences.freshInstall
        preferences.hideButtonTitles = true
        preferences = preferences.updating(.contacts, shown: true)
        store.save(preferences)

        let loaded = store.load()
        XCTAssertTrue(store.hasStoredValue)
        XCTAssertTrue(loaded.hideButtonTitles)
        XCTAssertTrue(loaded.isShown(.contacts))
        XCTAssertFalse(loaded.isShown(.calls))
        XCTAssertTrue(loaded.isShown(.chats))
        XCTAssertTrue(loaded.isShown(.settings))

        defaults.set(["moments"], forKey: TellomiTabBarPreferencesKeys.shownTabs)
        let repaired = store.load()
        XCTAssertTrue(repaired.isShown(.chats))
        XCTAssertTrue(repaired.isShown(.settings))
        XCTAssertTrue(repaired.isShown(.moments))
        XCTAssertFalse(repaired.isShown(.contacts))
    }

    func testSavingTheSameValueDoesNotNotifyAgain() {
        let name = "tellomi-tab-bar-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer {
            defaults.removePersistentDomain(forName: name)
        }
        let store = TellomiTabBarPreferencesStore(defaults: defaults)
        store.save(.freshInstall)
        let notes = TellomiNote()
        let token = NotificationCenter.default.addObserver(forName: TellomiTabBarPreferencesStore.didChangeNotification, object: store, queue: nil) { _ in
            notes.value += 1
        }
        store.save(.freshInstall)
        NotificationCenter.default.removeObserver(token)
        XCTAssertEqual(notes.value, 0)
    }
}

final class TellomiMenuSettingsStringsTests: XCTestCase {
    func testEveryBuiltinLanguageHasEveryKey() {
        for language in tellomiBuiltinMenuLanguages {
            XCTAssertTrue(tellomiMenuSettingsCatalogHasCompleteTable(language), language)
            for key in TellomiMenuSettingsStringKey.allCases {
                let value = tellomiMenuSettingsString(languageCode: language, key: key)
                XCTAssertFalse(value.isEmpty, "\(language) \(key.rawValue)")
            }
            if language != "en" {
                XCTAssertNotEqual(tellomiMenuSettingsString(languageCode: language, key: .title), "Menu settings", language)
            }
        }
    }

    func testChineseAndEnglishProductStrings() {
        XCTAssertEqual(tellomiMenuSettingsString(languageCode: "en", key: .tools), "Tools")
        XCTAssertEqual(tellomiMenuSettingsString(languageCode: "en", key: .title), "Menu settings")
        XCTAssertEqual(tellomiMenuSettingsString(languageCode: "en", key: .hideButtonTitles), "Hide button titles")
        XCTAssertEqual(tellomiMenuSettingsString(languageCode: "en", key: .navigationButtons), "Navigation bar buttons")
        XCTAssertEqual(tellomiMenuSettingsString(languageCode: "zh-Hans-CN", key: .title), "选单设定")
        XCTAssertEqual(tellomiMenuSettingsString(languageCode: "zh-Hans-CN", key: .hideButtonTitles), "隐藏按钮文字")
        XCTAssertEqual(tellomiMenuSettingsString(languageCode: "zh-Hans-CN", key: .navigationButtons), "导航栏按钮")
        XCTAssertEqual(tellomiMenuSettingsString(languageCode: "zh-Hant-TW", key: .title), "選單設定")
        XCTAssertEqual(tellomiMenuSettingsString(languageCode: "zh_HK", key: .hideButtonTitles), "隱藏按鈕文字")
    }

    func testUnknownLanguageFallsBackToEnglish() {
        XCTAssertEqual(tellomiCanonicalMenuLanguage("ja-JP"), "en")
        XCTAssertEqual(tellomiMenuSettingsString(languageCode: "ja", key: .title), "Menu settings")
    }

    func testMergeFillsMissingKeysAndKeepsAPackTranslation() {
        var dict = ["Tellomi.MenuSettings.Title": "From pack"]
        tellomiMergeMenuSettingsStrings(&dict, languageCode: "ru")
        XCTAssertEqual(dict["Tellomi.MenuSettings.Title"], "From pack")
        XCTAssertEqual(dict["Tellomi.MenuSettings.HideButtonTitles"], "Скрыть подписи кнопок")
        XCTAssertEqual(dict["Tellomi.MenuSettings.Tools"], "Инструменты")
        XCTAssertEqual(dict["Tellomi.MenuSettings.NavigationButtons"], "Кнопки панели навигации")
    }
}
