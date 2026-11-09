import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import TelegramCore
import Postbox
import TelegramPresentationData
import TelegramUIPreferences
import AccountContext
import ItemListUI
import ItemListPeerItem
import PresentationDataUtils

struct MomentsPeopleSection: Equatable {
    var title: String?
    var people: [MomentsAuthor]
}

private enum MomentsPeopleEntry: ItemListNodeEntry {
    case header(Int32, String)
    case peer(Int32, Int32, EnginePeer, String?)
    case name(Int32, Int32, String)

    var section: ItemListSectionId { return 0 }

    var stableId: Int32 {
        switch self {
        case let .header(section, _):
            return section * 1000
        case let .peer(section, index, _, _):
            return section * 1000 + index + 1
        case let .name(section, index, _):
            return section * 1000 + index + 1
        }
    }

    static func <(lhs: MomentsPeopleEntry, rhs: MomentsPeopleEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    static func ==(lhs: MomentsPeopleEntry, rhs: MomentsPeopleEntry) -> Bool {
        switch lhs {
        case let .header(section, text):
            if case .header(section, text) = rhs { return true } else { return false }
        case let .peer(section, index, peer, subtitle):
            if case .peer(section, index, peer, subtitle) = rhs { return true } else { return false }
        case let .name(section, index, text):
            if case .name(section, index, text) = rhs { return true } else { return false }
        }
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! MomentsPeopleArguments
        switch self {
        case let .header(_, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .name(_, _, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .peer(_, _, peer, _):
            return ItemListPeerItem(presentationData: presentationData, dateTimeFormat: arguments.dateTimeFormat, nameDisplayOrder: arguments.nameDisplayOrder, context: arguments.context, peer: peer, presence: nil, text: .none, label: .none, editing: ItemListPeerItemEditing(editable: false, editing: false, revealed: false), switchValue: nil, enabled: true, selectable: true, sectionId: self.section, action: {
                arguments.open(peer)
            }, setPeerIdWithRevealedOptions: { _, _ in
            }, removePeer: { _ in
            })
        }
    }
}

private final class MomentsPeopleArguments {
    let context: AccountContext
    let dateTimeFormat: PresentationDateTimeFormat
    let nameDisplayOrder: PresentationPersonNameOrder
    let open: (EnginePeer) -> Void

    init(context: AccountContext, dateTimeFormat: PresentationDateTimeFormat, nameDisplayOrder: PresentationPersonNameOrder, open: @escaping (EnginePeer) -> Void) {
        self.context = context
        self.dateTimeFormat = dateTimeFormat
        self.nameDisplayOrder = nameDisplayOrder
        self.open = open
    }
}

func momentsPeopleController(context: AccountContext, title: String, load: Signal<[MomentsPeopleSection], MomentsAPIError>) -> ViewController {
    let state = Promise<[(MomentsPeopleSection, [EnginePeer?])]>()
    let resolved = load
    |> `catch` { _ -> Signal<[MomentsPeopleSection], NoError> in
        return .single([])
    }
    |> mapToSignal { sections -> Signal<[(MomentsPeopleSection, [EnginePeer?])], NoError> in
        if sections.isEmpty {
            return .single([])
        }
        let signals = sections.map { section -> Signal<(MomentsPeopleSection, [EnginePeer?]), NoError> in
            if section.people.isEmpty {
                return .single((section, []))
            }
            let people = section.people.map { author -> Signal<EnginePeer?, NoError> in
                guard author.telegramUserId != 0 else {
                    return .single(nil)
                }
                let peerId = PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(author.telegramUserId))
                return context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId))
            }
            return combineLatest(people) |> map { (section, $0) }
        }
        return combineLatest(signals)
    }
    state.set(resolved)

    var pushController: ((ViewController) -> Void)?
    let arguments = MomentsPeopleArguments(context: context, dateTimeFormat: PresentationDateTimeFormat(), nameDisplayOrder: .firstLast, open: { peer in
        if let controller = context.sharedContext.makePeerInfoController(context: context, updatedPresentationData: nil, peer: peer, mode: .generic, avatarInitiallyExpanded: false, fromChat: false, requestsContext: nil) {
            pushController?(controller)
        }
    })
    let signal = combineLatest(context.sharedContext.presentationData, state.get())
    |> map { presentationData, sections -> (ItemListControllerState, (ItemListNodeState, MomentsPeopleArguments)) in
        var entries: [MomentsPeopleEntry] = []
        for (sectionIndex, section) in sections.enumerated() {
            let sectionId = Int32(sectionIndex)
            if let title = section.0.title, !title.isEmpty {
                entries.append(.header(sectionId, title))
            }
            for (index, author) in section.0.people.enumerated() {
                if let peer = section.1[index] {
                    entries.append(.peer(sectionId, Int32(index), peer, author.displayName))
                } else {
                    entries.append(.name(sectionId, Int32(index), author.displayName))
                }
            }
        }
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(title), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks)
        return (controllerState, (listState, arguments))
    }
    let controller = ItemListController(context: context, state: signal)
    pushController = { [weak controller] next in
        (controller?.navigationController as? NavigationController)?.pushViewController(next)
    }
    return controller
}
