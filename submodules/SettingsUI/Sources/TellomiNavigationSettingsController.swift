import AccountContext
import Display
import Foundation
import ItemListUI
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences
import UIKit

private final class TellomiNavigationSettingsArguments {
    let toggleFeed: (Bool) -> Void
    let toggleCalls: (Bool) -> Void
    let toggleContacts: (Bool) -> Void
    let toggleHideTitles: (Bool) -> Void

    init(toggleFeed: @escaping (Bool) -> Void, toggleCalls: @escaping (Bool) -> Void, toggleContacts: @escaping (Bool) -> Void, toggleHideTitles: @escaping (Bool) -> Void) {
        self.toggleFeed = toggleFeed
        self.toggleCalls = toggleCalls
        self.toggleContacts = toggleContacts
        self.toggleHideTitles = toggleHideTitles
    }
}

private enum TellomiNavigationSettingsEntry: ItemListNodeEntry {
    case feed(String, Bool)
    case chats(String)
    case calls(String, Bool)
    case contacts(String, Bool)
    case settings(String)
    case hideTitles(String, Bool)
    case footer(String)

    var section: ItemListSectionId {
        return 0
    }

    var stableId: Int32 {
        switch self {
        case .feed:
            return 0
        case .chats:
            return 1
        case .calls:
            return 2
        case .contacts:
            return 3
        case .settings:
            return 4
        case .hideTitles:
            return 5
        case .footer:
            return 6
        }
    }

    static func ==(lhs: TellomiNavigationSettingsEntry, rhs: TellomiNavigationSettingsEntry) -> Bool {
        switch lhs {
        case let .feed(text, value):
            if case let .feed(rhsText, rhsValue) = rhs, text == rhsText, value == rhsValue {
                return true
            }
        case let .chats(text):
            if case let .chats(rhsText) = rhs, text == rhsText {
                return true
            }
        case let .calls(text, value):
            if case let .calls(rhsText, rhsValue) = rhs, text == rhsText, value == rhsValue {
                return true
            }
        case let .contacts(text, value):
            if case let .contacts(rhsText, rhsValue) = rhs, text == rhsText, value == rhsValue {
                return true
            }
        case let .settings(text):
            if case let .settings(rhsText) = rhs, text == rhsText {
                return true
            }
        case let .hideTitles(text, value):
            if case let .hideTitles(rhsText, rhsValue) = rhs, text == rhsText, value == rhsValue {
                return true
            }
        case let .footer(text):
            if case let .footer(rhsText) = rhs, text == rhsText {
                return true
            }
        }
        return false
    }

    static func <(lhs: TellomiNavigationSettingsEntry, rhs: TellomiNavigationSettingsEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! TellomiNavigationSettingsArguments
        switch self {
        case let .feed(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: { updated in
                arguments.toggleFeed(updated)
            })
        case let .chats(title):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: true, enableInteractiveChanges: false, enabled: false, sectionId: self.section, style: .blocks, updated: { _ in
            })
        case let .calls(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: { updated in
                arguments.toggleCalls(updated)
            })
        case let .contacts(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: { updated in
                arguments.toggleContacts(updated)
            })
        case let .settings(title):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: true, enableInteractiveChanges: false, enabled: false, sectionId: self.section, style: .blocks, updated: { _ in
            })
        case let .hideTitles(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: { updated in
                arguments.toggleHideTitles(updated)
            })
        case let .footer(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private func tellomiNavigationSettingsEntries(presentationData: PresentationData, tabs: TellomiTabSettings, calls: CallListSettings) -> [TellomiNavigationSettingsEntry] {
    let copy = TellomiTabCopy.resolve(languageCode: presentationData.strings.primaryComponent.languageCode, pack: tellomiStringPack(primary: presentationData.strings.primaryComponent.dict, secondary: presentationData.strings.secondaryComponent?.dict))
    return [
        .feed(copy.feed, tabs.showFeedTab),
        .chats(presentationData.strings.DialogList_Title),
        .calls(presentationData.strings.Calls_TabTitle, calls.showTab),
        .contacts(presentationData.strings.Contacts_Title, tabs.showContactsTab),
        .settings(presentationData.strings.Settings_Title),
        .hideTitles(presentationData.strings.Tellomi_Tabs_HideLabels, tabs.hideTabTitles),
        .footer(copy.navigationFooter)
    ]
}

public func tellomiNavigationSettingsController(context: AccountContext) -> ViewController {
    let arguments = TellomiNavigationSettingsArguments(toggleFeed: { value in
        let _ = updateTellomiTabSettingsInteractively(accountManager: context.sharedContext.accountManager, { settings in
            return settings.withUpdatedShowFeedTab(value)
        }).start()
    }, toggleCalls: { value in
        let _ = updateCallListSettingsInteractively(accountManager: context.sharedContext.accountManager, { settings in
            return settings.withUpdatedShowTab(value)
        }).start()
    }, toggleContacts: { value in
        let _ = updateTellomiTabSettingsInteractively(accountManager: context.sharedContext.accountManager, { settings in
            return settings.withUpdatedShowContactsTab(value)
        }).start()
    }, toggleHideTitles: { value in
        let _ = updateTellomiTabSettingsInteractively(accountManager: context.sharedContext.accountManager, { settings in
            return settings.withUpdatedHideTabTitles(value)
        }).start()
    })

    let signal = combineLatest(
        context.sharedContext.presentationData,
        context.sharedContext.accountManager.sharedData(keys: [
            ApplicationSpecificSharedDataKeys.tellomiTabSettings,
            ApplicationSpecificSharedDataKeys.callListSettings
        ])
    )
    |> deliverOnMainQueue
    |> map { presentationData, sharedData -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let tabs = sharedData.entries[ApplicationSpecificSharedDataKeys.tellomiTabSettings]?.get(TellomiTabSettings.self) ?? .defaultSettings
        let calls = sharedData.entries[ApplicationSpecificSharedDataKeys.callListSettings]?.get(CallListSettings.self) ?? .defaultSettings
        let copy = TellomiTabCopy.resolve(languageCode: presentationData.strings.primaryComponent.languageCode, pack: tellomiStringPack(primary: presentationData.strings.primaryComponent.dict, secondary: presentationData.strings.secondaryComponent?.dict))
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(copy.navigationTitle), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: tellomiNavigationSettingsEntries(presentationData: presentationData, tabs: tabs, calls: calls), style: .blocks, animateChanges: false)
        return (controllerState, (listState, arguments))
    }

    return ItemListController(context: context, state: signal)
}
