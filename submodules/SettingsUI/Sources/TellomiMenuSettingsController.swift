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
    case hideTitles
    case tabs
}

private enum TellomiMenuSettingsEntry: ItemListNodeEntry {
    case hideTitles(PresentationTheme, String, Bool)
    case navigationHeader(PresentationTheme, String)
    case tab(Int32, TellomiRootTab, PresentationTheme, String, Bool, Bool)

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
        case let .tab(index, _, _, _, _, _):
            return 10 + index
        }
    }

    static func ==(lhs: TellomiMenuSettingsEntry, rhs: TellomiMenuSettingsEntry) -> Bool {
        switch lhs {
        case let .hideTitles(lhsTheme, lhsTitle, lhsValue):
            if case let .hideTitles(rhsTheme, rhsTitle, rhsValue) = rhs, lhsTheme === rhsTheme, lhsTitle == rhsTitle, lhsValue == rhsValue {
                return true
            } else {
                return false
            }
        case let .navigationHeader(lhsTheme, lhsTitle):
            if case let .navigationHeader(rhsTheme, rhsTitle) = rhs, lhsTheme === rhsTheme, lhsTitle == rhsTitle {
                return true
            } else {
                return false
            }
        case let .tab(lhsIndex, lhsTab, lhsTheme, lhsTitle, lhsValue, lhsEnabled):
            if case let .tab(rhsIndex, rhsTab, rhsTheme, rhsTitle, rhsValue, rhsEnabled) = rhs, lhsIndex == rhsIndex, lhsTab == rhsTab, lhsTheme === rhsTheme, lhsTitle == rhsTitle, lhsValue == rhsValue, lhsEnabled == rhsEnabled {
                return true
            } else {
                return false
            }
        }
    }

    static func <(lhs: TellomiMenuSettingsEntry, rhs: TellomiMenuSettingsEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! TellomiMenuSettingsArguments
        switch self {
        case let .hideTitles(_, title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: { updated in
                arguments.setHideTitles(updated)
            })
        case let .navigationHeader(_, title):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: title, sectionId: self.section)
        case let .tab(_, tab, _, title, value, enabled):
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

private func tellomiMenuSettingsEntries(presentationData: PresentationData, preferences: TellomiTabBarPreferences, newsAvailable: Bool) -> [TellomiMenuSettingsEntry] {
    var available: Set<TellomiRootTab> = [.moments, .chats, .contacts, .calls, .settings]
    if newsAvailable {
        available.insert(.news)
    }
    let theme = presentationData.theme
    let strings = presentationData.strings
    var entries: [TellomiMenuSettingsEntry] = [
        .hideTitles(theme, strings.Tellomi_MenuSettings_HideButtonTitles, preferences.hideButtonTitles),
        .navigationHeader(theme, strings.Tellomi_MenuSettings_NavigationButtons)
    ]
    for (offset, tab) in TellomiRootTab.displayOrder.enumerated() where available.contains(tab) {
        let locked = tab.switchLocked
        entries.append(.tab(Int32(offset), tab, theme, tellomiRootTabTitle(tab, strings: strings), locked || preferences.isShown(tab), !locked))
    }
    return entries
}

public func tellomiMenuSettingsController(context: AccountContext) -> ViewController {
    let accountManager = context.sharedContext.accountManager
    let preferences = accountManager.sharedData(keys: [ApplicationSpecificSharedDataKeys.tellomiTabBarPreferences])
    |> map { sharedData -> TellomiTabBarPreferences in
        return resolvedTellomiTabBarPreferences(sharedData.entries[ApplicationSpecificSharedDataKeys.tellomiTabBarPreferences])
    }

    let arguments = TellomiMenuSettingsArguments(setHideTitles: { value in
        let _ = updateTellomiTabBarPreferencesInteractively(accountManager: accountManager, { current in
            var current = current
            current.hideButtonTitles = value
            return current
        }).start()
    }, setVisible: { tab, shown in
        let _ = updateTellomiTabBarPreferencesInteractively(accountManager: accountManager, { current in
            return current.updating(tab, shown: shown)
        }).start()
        if tab == .calls {
            let _ = updateCallListSettingsInteractively(accountManager: accountManager, { settings in
                return settings.withUpdatedShowTab(shown)
            }).start()
        }
    })

    let signal = combineLatest(context.sharedContext.presentationData, preferences)
    |> deliverOnMainQueue
    |> map { presentationData, preferences -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let newsAvailable = isNewsFeedEnabled(appConfiguration: context.currentAppConfiguration.with { $0 })
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(presentationData.strings.Tellomi_MenuSettings_Title), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back), animateChanges: true)
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: tellomiMenuSettingsEntries(presentationData: presentationData, preferences: preferences, newsAvailable: newsAvailable), style: .blocks, emptyStateItem: nil, animateChanges: true)
        return (controllerState, (listState, arguments))
    }
    return ItemListController(context: context, state: signal)
}
