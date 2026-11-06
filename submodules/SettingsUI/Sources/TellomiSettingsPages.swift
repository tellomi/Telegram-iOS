import AccountContext
import Display
import Foundation
import ItemListUI
import SwiftSignalKit
import TelegramPresentationData
import TelegramUIPreferences
import UIKit

public struct TellomiSettingsLink: Equatable {
    public var id: String
    public var title: String
    public var label: String
    public var destructive: Bool

    public init(id: String, title: String, label: String = "", destructive: Bool = false) {
        self.id = id
        self.title = title
        self.label = label
        self.destructive = destructive
    }
}

private final class TellomiSettingsLinksArguments {
    let open: (String) -> Void

    init(open: @escaping (String) -> Void) {
        self.open = open
    }
}

private enum TellomiSettingsLinksEntry: ItemListNodeEntry {
    case row(Int32, TellomiSettingsLink)

    var section: ItemListSectionId {
        return 0
    }

    var stableId: Int32 {
        switch self {
        case let .row(index, _):
            return index
        }
    }

    static func ==(lhs: TellomiSettingsLinksEntry, rhs: TellomiSettingsLinksEntry) -> Bool {
        switch lhs {
        case let .row(index, link):
            if case let .row(rhsIndex, rhsLink) = rhs, index == rhsIndex, link == rhsLink {
                return true
            }
        }
        return false
    }

    static func <(lhs: TellomiSettingsLinksEntry, rhs: TellomiSettingsLinksEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! TellomiSettingsLinksArguments
        switch self {
        case let .row(_, link):
            if link.destructive {
                return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: link.title, kind: .destructive, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                    arguments.open(link.id)
                })
            }
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: link.title, label: link.label, sectionId: self.section, style: .blocks, action: {
                arguments.open(link.id)
            })
        }
    }
}

public func tellomiSettingsLinksController(context: AccountContext, title: String, links: [TellomiSettingsLink], open: @escaping (String) -> Void) -> ViewController {
    let arguments = TellomiSettingsLinksArguments(open: open)
    let entries = links.enumerated().map { index, link in
        TellomiSettingsLinksEntry.row(Int32(index), link)
    }
    let signal = context.sharedContext.presentationData
    |> deliverOnMainQueue
    |> map { presentationData -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(title), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: false)
        return (controllerState, (listState, arguments))
    }
    return ItemListController(context: context, state: signal)
}

private enum TellomiAboutEntry: ItemListNodeEntry {
    case version(String, String)

    var section: ItemListSectionId {
        return 0
    }

    var stableId: Int32 {
        return 0
    }

    static func ==(lhs: TellomiAboutEntry, rhs: TellomiAboutEntry) -> Bool {
        switch lhs {
        case let .version(title, value):
            if case let .version(rhsTitle, rhsValue) = rhs, title == rhsTitle, value == rhsValue {
                return true
            }
        }
        return false
    }

    static func <(lhs: TellomiAboutEntry, rhs: TellomiAboutEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        switch self {
        case let .version(title, value):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: value, sectionId: self.section, style: .blocks, disclosureStyle: .none, action: nil)
        }
    }
}

private func tellomiAboutVersionLabel() -> String {
    let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
    let shortTrimmed = short.trimmingCharacters(in: .whitespacesAndNewlines)
    let buildTrimmed = build.trimmingCharacters(in: .whitespacesAndNewlines)
    if shortTrimmed.isEmpty {
        return buildTrimmed
    }
    if buildTrimmed.isEmpty || buildTrimmed == shortTrimmed {
        return shortTrimmed
    }
    return "\(shortTrimmed) (\(buildTrimmed))"
}

public func tellomiAboutController(context: AccountContext) -> ViewController {
    let signal = context.sharedContext.presentationData
    |> deliverOnMainQueue
    |> map { presentationData -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let copy = TellomiSettingsCopy.resolve(languageCode: presentationData.strings.primaryComponent.languageCode, pack: tellomiStringPack(primary: presentationData.strings.primaryComponent.dict, secondary: presentationData.strings.secondaryComponent?.dict))
        var entries: [TellomiAboutEntry] = []
        let version = tellomiAboutVersionLabel()
        if !version.isEmpty {
            entries.append(.version(copy.version, version))
        }
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(copy.about), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: false)
        return (controllerState, (listState, ()))
    }
    return ItemListController(context: context, state: signal)
}
