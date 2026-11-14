import AccountContext
import Display
import Foundation
import ItemListUI
import SwiftSignalKit
import TelegramPresentationData
import TellomiWallpapers
import UIKit

private enum TellomiOpenSourceLicensesEntry: ItemListNodeEntry {
    case notice(String)

    var section: ItemListSectionId {
        return 0
    }

    var stableId: Int32 {
        return 0
    }

    static func ==(lhs: TellomiOpenSourceLicensesEntry, rhs: TellomiOpenSourceLicensesEntry) -> Bool {
        if case let .notice(lhsText) = lhs, case let .notice(rhsText) = rhs {
            return lhsText == rhsText
        }
        return false
    }

    static func <(lhs: TellomiOpenSourceLicensesEntry, rhs: TellomiOpenSourceLicensesEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        switch self {
        case let .notice(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

public func tellomiOpenSourceLicensesController(context: AccountContext) -> ViewController {
    let signal = context.sharedContext.presentationData
    |> deliverOnMainQueue
    |> map { presentationData -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let title = presentationData.strings.Tellomi_Settings_OpenSource
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(title), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: [TellomiOpenSourceLicensesEntry.notice(TellomiOpenSourceNotices.text)], style: .blocks, animateChanges: false)
        return (controllerState, (listState, ()))
    }
    return ItemListController(context: context, state: signal)
}
