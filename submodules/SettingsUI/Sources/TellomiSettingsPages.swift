import AccountContext
import Display
import Foundation
import ItemListUI
import SwiftSignalKit
import TelegramCore
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
    case facts(String)
    case footer(String)

    var section: ItemListSectionId {
        switch self {
        case .version:
            return 0
        case .facts:
            return 1
        case .footer:
            return 2
        }
    }

    var stableId: Int32 {
        switch self {
        case .version:
            return 0
        case .facts:
            return 1
        case .footer:
            return 2
        }
    }

    static func ==(lhs: TellomiAboutEntry, rhs: TellomiAboutEntry) -> Bool {
        switch lhs {
        case let .version(title, value):
            if case let .version(rhsTitle, rhsValue) = rhs, title == rhsTitle, value == rhsValue {
                return true
            }
        case let .facts(text):
            if case let .facts(rhsText) = rhs, text == rhsText {
                return true
            }
        case let .footer(text):
            if case let .footer(rhsText) = rhs, text == rhsText {
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
        case let .facts(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .footer(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

/// String fields from `help.getAppConfig` (`EngineData.Item.Configuration.App`).
/// `TellomiAboutDisclosure` reads `tellomi_ai_model_name`,
/// `tellomi_generative_ai_registration_number` (or `tellomi_ai_registration_number`),
/// and `tellomi_algorithm_filing_number`. Other types stay out so a number cannot replace the placeholder.
private func tellomiAboutConfiguration(_ data: JSON?) -> [String: Any]? {
    guard case let .dictionary(dictionary)? = data else {
        return nil
    }
    var result: [String: Any] = [:]
    for (key, value) in dictionary {
        if case let .string(string) = value {
            result[key] = string
        }
    }
    return result
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
    let signal = combineLatest(
        context.sharedContext.presentationData,
        context.engine.data.subscribe(TelegramEngine.EngineData.Item.Configuration.App())
    )
    |> deliverOnMainQueue
    |> map { presentationData, configuration -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let copy = TellomiSettingsCopy.resolve(languageCode: presentationData.strings.primaryComponent.languageCode, pack: tellomiStringPack(primary: presentationData.strings.primaryComponent.dict, secondary: presentationData.strings.secondaryComponent?.dict))
        let facts = TellomiAboutDisclosure.facts(configuration: tellomiAboutConfiguration(configuration.data), numberPlaceholder: copy.numberPlaceholder)
        let body = tellomiAboutDisclosureText(modelLabel: copy.modelLabel, registrationLabel: copy.registrationLabel, algorithmLabel: copy.algorithmLabel, facts: facts)
        var entries: [TellomiAboutEntry] = []
        let version = tellomiAboutVersionLabel()
        if !version.isEmpty {
            entries.append(.version(copy.version, version))
        }
        entries.append(.facts(body))
        entries.append(.footer(copy.aboutFooter))
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(copy.about), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: false)
        return (controllerState, (listState, ()))
    }
    return ItemListController(context: context, state: signal)
}
