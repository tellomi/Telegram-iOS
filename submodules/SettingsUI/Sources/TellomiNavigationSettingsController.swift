import AccountContext
import Display
import Foundation
import ItemListUI
import SwiftSignalKit
import TelegramPresentationData
import TelegramUIPreferences
import UIKit

private enum TellomiNavigationSettingsEntry: ItemListNodeEntry {
    case feed(String)
    case chats(String)
    case me(String)
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
        case .me:
            return 2
        case .footer:
            return 3
        }
    }

    static func ==(lhs: TellomiNavigationSettingsEntry, rhs: TellomiNavigationSettingsEntry) -> Bool {
        switch lhs {
        case let .feed(text):
            if case let .feed(rhsText) = rhs, text == rhsText {
                return true
            }
        case let .chats(text):
            if case let .chats(rhsText) = rhs, text == rhsText {
                return true
            }
        case let .me(text):
            if case let .me(rhsText) = rhs, text == rhsText {
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
        let _ = arguments
        switch self {
        case let .feed(title), let .chats(title), let .me(title):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: true, enableInteractiveChanges: false, enabled: false, sectionId: self.section, style: .blocks, updated: { _ in
            })
        case let .footer(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private func tellomiNavigationSettingsEntries(presentationData: PresentationData) -> [TellomiNavigationSettingsEntry] {
    let copy = TellomiTabCopy.resolve(languageCode: presentationData.strings.primaryComponent.languageCode, pack: tellomiStringPack(primary: presentationData.strings.primaryComponent.dict, secondary: presentationData.strings.secondaryComponent?.dict))
    return [
        .feed(copy.feed),
        .chats(copy.chats),
        .me(copy.me),
        .footer(copy.navigationFooter)
    ]
}

public func tellomiNavigationSettingsController(context: AccountContext) -> ViewController {
    let signal = context.sharedContext.presentationData
    |> deliverOnMainQueue
    |> map { presentationData -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let copy = TellomiTabCopy.resolve(languageCode: presentationData.strings.primaryComponent.languageCode, pack: tellomiStringPack(primary: presentationData.strings.primaryComponent.dict, secondary: presentationData.strings.secondaryComponent?.dict))
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(copy.navigationTitle), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: tellomiNavigationSettingsEntries(presentationData: presentationData), style: .blocks, animateChanges: false)
        return (controllerState, (listState, ()))
    }

    return ItemListController(context: context, state: signal)
}
