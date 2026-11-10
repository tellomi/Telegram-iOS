import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences
import ItemListUI
import PresentationDataUtils
import AccountContext
import NewsFeedSupport

private final class TellomiMenuSettingsArguments {
    let setHideTitles: (Bool) -> Void
    let setVisible: (TellomiRootTab, Bool) -> Void

    init(setHideTitles: @escaping (Bool) -> Void, setVisible: @escaping (TellomiRootTab, Bool) -> Void) {
        self.setHideTitles = setHideTitles
        self.setVisible = setVisible
    }
}

private enum TellomiMenuSettingsSection: Int32 {
    case hideTitles = 0
    case tabs = 1
}

private enum TellomiMenuSettingsEntry: ItemListNodeEntry {
    case hideTitles(String, Bool)
    case navigationHeader(String)
    case tab(Int32, TellomiRootTab, String, Bool, Bool)

    var section: ItemListSectionId {
        switch self {
        case .hideTitles:
            return TellomiMenuSettingsSection.hideTitles.rawValue
        case .navigationHeader, .tab:
            return TellomiMenuSettingsSection.tabs.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .hideTitles:
            return 0
        case .navigationHeader:
            return 1
        case let .tab(index, _, _, _, _):
            return 10 + index
        }
    }

    static func <(lhs: TellomiMenuSettingsEntry, rhs: TellomiMenuSettingsEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    static func ==(lhs: TellomiMenuSettingsEntry, rhs: TellomiMenuSettingsEntry) -> Bool {
        switch lhs {
        case let .hideTitles(title, value):
            if case .hideTitles(title, value) = rhs {
                return true
            } else {
                return false
            }
        case let .navigationHeader(title):
            if case .navigationHeader(title) = rhs {
                return true
            } else {
                return false
            }
        case let .tab(index, tab, title, value, enabled):
            if case .tab(index, tab, title, value, enabled) = rhs {
                return true
            } else {
                return false
            }
        }
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! TellomiMenuSettingsArguments
        switch self {
        case let .hideTitles(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: { updated in
                arguments.setHideTitles(updated)
            })
        case let .navigationHeader(title):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: title, sectionId: self.section)
        case let .tab(_, tab, title, value, enabled):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, enableInteractiveChanges: enabled, enabled: enabled, sectionId: self.section, style: .blocks, updated: { updated in
                arguments.setVisible(tab, updated)
            })
        }
    }
}

private func tellomiRootTabTitle(_ tab: TellomiRootTab, strings: PresentationStrings) -> String {
    switch tab {
    case .moments:
        return strings.Moments_Title
    case .chats:
        return strings.DialogList_Title
    case .contacts:
        return strings.Contacts_Title
    case .calls:
        return strings.Calls_TabTitle
    case .news:
        return strings.News_Title
    case .settings:
        return strings.Settings_Title
    }
}

private func tellomiMenuSettingsEntries(strings: PresentationStrings, preferences: TellomiTabBarPreferences, newsAvailable: Bool) -> [TellomiMenuSettingsEntry] {
    var available: Set<TellomiRootTab> = [.moments, .chats, .contacts, .calls, .settings]
    if newsAvailable {
        available.insert(.news)
    }
    var entries: [TellomiMenuSettingsEntry] = [
        .hideTitles(strings.Tellomi_MenuSettings_HideButtonTitles, preferences.hideButtonTitles),
        .navigationHeader(strings.Tellomi_MenuSettings_NavigationButtons)
    ]
    var index: Int32 = 0
    for tab in TellomiRootTab.displayOrder where available.contains(tab) {
        let locked = tab.switchLocked
        entries.append(.tab(index, tab, tellomiRootTabTitle(tab, strings: strings), locked ? true : preferences.isShown(tab), !locked))
        index += 1
    }
    return entries
}

private final class TellomiMenuSettingsObserver {
    var token: NSObjectProtocol?
    deinit {
        if let token = self.token {
            NotificationCenter.default.removeObserver(token)
        }
    }
}

public func tellomiMenuSettingsController(context: AccountContext) -> ViewController {
    let store = TellomiTabBarPreferencesStore.shared
    let preferences = ValuePromise<TellomiTabBarPreferences>(store.load(), ignoreRepeated: false)
    let observer = TellomiMenuSettingsObserver()
    observer.token = NotificationCenter.default.addObserver(forName: TellomiTabBarPreferencesStore.didChangeNotification, object: store, queue: .main, using: { _ in
        preferences.set(store.load())
    })

    let arguments = TellomiMenuSettingsArguments(setHideTitles: { value in
        var next = store.load()
        next.hideButtonTitles = value
        store.save(next)
    }, setVisible: { tab, value in
        let next = store.load().updating(tab, shown: value)
        store.save(next)
        if tab == .calls {
            let _ = updateCallListSettingsInteractively(accountManager: context.sharedContext.accountManager, { settings in
                return settings.withUpdatedShowTab(next.isShown(.calls))
            }).start()
        }
    })

    let signal = combineLatest(context.sharedContext.presentationData, preferences.get())
    |> map { [observer] presentationData, preferences -> (ItemListControllerState, (ItemListNodeState, TellomiMenuSettingsArguments)) in
        let _ = observer
        let newsAvailable = isNewsFeedEnabled(appConfiguration: context.currentAppConfiguration.with { $0 })
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(presentationData.strings.Tellomi_MenuSettings_Title), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back), animateChanges: true)
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: tellomiMenuSettingsEntries(strings: presentationData.strings, preferences: preferences, newsAvailable: newsAvailable), style: .blocks, animateChanges: true)
        return (controllerState, (listState, arguments))
    }
    return ItemListController(context: context, state: signal)
}
