import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import TelegramCore
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
                let peerId = EnginePeer.Id(namespace: Namespaces.Peer.CloudUser, id: EnginePeer.Id.Id._internalFromInt64Value(author.telegramUserId))
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

private struct MomentsRelationState {
    var people: [MomentsAuthor] = []
    var peers: [String: EnginePeer] = [:]
    var cursor: String?
    var loaded = false
    var loading = false
    var failed = false
    var hidden = false
}

private final class MomentsRelationArguments {
    let presentationData: PresentationData
    let context: AccountContext
    let open: (MomentsAuthor) -> Void
    let retry: () -> Void

    init(presentationData: PresentationData, context: AccountContext, open: @escaping (MomentsAuthor) -> Void, retry: @escaping () -> Void) {
        self.presentationData = presentationData
        self.context = context
        self.open = open
        self.retry = retry
    }
}

private enum MomentsRelationEntry: ItemListNodeEntry {
    case status(String, Bool)
    case person(Int32, MomentsAuthor, EnginePeer?)

    var section: ItemListSectionId {
        return 0
    }

    var stableId: Int32 {
        switch self {
        case .status:
            return 0
        case let .person(index, _, _):
            return index + 1
        }
    }

    static func <(lhs: MomentsRelationEntry, rhs: MomentsRelationEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    static func ==(lhs: MomentsRelationEntry, rhs: MomentsRelationEntry) -> Bool {
        switch lhs {
        case let .status(text, retry):
            if case .status(text, retry) = rhs {
                return true
            }
            return false
        case let .person(index, author, peer):
            if case .person(index, author, peer) = rhs {
                return true
            }
            return false
        }
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! MomentsRelationArguments
        switch self {
        case let .status(text, retry):
            if retry {
                return ItemListActionItem(presentationData: presentationData, title: text, kind: .generic, alignment: .center, sectionId: self.section, style: .blocks, action: arguments.retry)
            }
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .person(_, author, peer):
            if let peer {
                return ItemListPeerItem(presentationData: presentationData, dateTimeFormat: arguments.presentationData.dateTimeFormat, nameDisplayOrder: arguments.presentationData.nameDisplayOrder, context: arguments.context, peer: peer, presence: nil, text: .none, label: .none, editing: ItemListPeerItemEditing(editable: false, editing: false, revealed: false), switchValue: nil, enabled: true, selectable: true, sectionId: self.section, action: {
                    arguments.open(author)
                }, setPeerIdWithRevealedOptions: { _, _ in
                }, removePeer: { _ in
                })
            }
            let title = author.displayName.isEmpty ? (author.username ?? "") : author.displayName
            return ItemListActionItem(presentationData: presentationData, title: title, kind: .neutral, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.open(author)
            })
        }
    }
}

private final class MomentsRelationModel {
    let context: AccountContext
    let profileId: String
    let followers: Bool
    var openPeer: ((EnginePeer.Id) -> Void)?
    weak var controller: ViewController?
    var state = MomentsRelationState()
    let promise = Promise<MomentsRelationState>()
    private var query = MomentsQueryGeneration()
    private var disposable: Disposable?

    init(context: AccountContext, profileId: String, followers: Bool, openPeer: ((EnginePeer.Id) -> Void)?) {
        self.context = context
        self.profileId = profileId
        self.followers = followers
        self.openPeer = openPeer
        self.promise.set(.single(self.state))
    }

    deinit {
        self.disposable?.dispose()
    }

    func load(refresh: Bool) {
        guard momentsShouldLoadFeedPage(loaded: self.state.loaded, cursor: self.state.cursor, refresh: refresh, loading: self.state.loading) else {
            return
        }
        let generation = self.query.begin()
        self.state.loading = true
        let requestCursor = refresh ? nil : self.state.cursor
        let context = self.context
        let page: Signal<MomentsPeoplePage, MomentsAPIError>
        if self.followers {
            page = context.engine.moments.followers(id: self.profileId, cursor: requestCursor)
        } else {
            page = context.engine.moments.following(id: self.profileId, cursor: requestCursor)
        }
        self.disposable?.dispose()
        self.disposable = (page
        |> mapToSignal { page -> Signal<(MomentsPeoplePage, [(MomentsAuthor, EnginePeer?)]), MomentsAPIError> in
            return momentsResolvedAuthors(context: context, people: page.people)
            |> map { (page, $0) }
            |> castError(MomentsAPIError.self)
        }
        |> deliverOnMainQueue).start(next: { [weak self] value in
            let (page, resolved) = value
            guard let self, self.query.accepts(generation) else {
                return
            }
            let refreshing = refresh || requestCursor == nil
            if refreshing {
                var seen = Set<String>()
                self.state.people = page.people.filter { seen.insert($0.id).inserted }
                self.state.peers = [:]
                self.state.cursor = page.people.isEmpty ? nil : page.nextCursor
            } else if page.people.isEmpty {
                self.state.cursor = nil
            } else {
                var seen = Set(self.state.people.map(\.id))
                for person in page.people where seen.insert(person.id).inserted {
                    self.state.people.append(person)
                }
                self.state.cursor = page.nextCursor
            }
            for (author, peer) in resolved {
                if let peer {
                    self.state.peers[author.id] = peer
                }
            }
            self.state.loading = false
            self.state.loaded = true
            self.state.failed = false
            self.state.hidden = false
            self.promise.set(.single(self.state))
        }, error: { [weak self] error in
            guard let self, self.query.accepts(generation) else {
                return
            }
            switch momentsListLoadResult(error) {
            case .ignore:
                self.state.loading = false
            case .hidden:
                self.state.loading = false
                self.state.loaded = true
                self.state.hidden = true
                self.state.failed = false
                if refresh {
                    self.state.people = []
                    self.state.cursor = nil
                }
                self.promise.set(.single(self.state))
            case .failed:
                self.state.loading = false
                self.state.loaded = true
                self.state.failed = true
                self.promise.set(.single(self.state))
            }
        })
    }

    func open(_ author: MomentsAuthor) {
        guard let peerId = momentsPeerId(author.telegramUserId), let openPeer = self.openPeer else {
            let presentationData = self.context.sharedContext.currentPresentationData.with { $0 }
            self.controller?.present(textAlertController(context: self.context, title: nil, text: presentationData.strings.Moments_Unavailable, actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_Cancel, action: {})]), in: .window(.root))
            return
        }
        openPeer(peerId)
    }
}

private func momentsResolvedAuthors(context: AccountContext, people: [MomentsAuthor]) -> Signal<[(MomentsAuthor, EnginePeer?)], NoError> {
    if people.isEmpty {
        return .single([])
    }
    return combineLatest(people.map { author -> Signal<(MomentsAuthor, EnginePeer?), NoError> in
        guard let peerId = momentsPeerId(author.telegramUserId) else {
            return .single((author, nil))
        }
        return context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId))
        |> map { (author, $0) }
    })
}

func momentsRelationController(context: AccountContext, profileId: String, followers: Bool, openPeer: ((EnginePeer.Id) -> Void)?) -> ViewController {
    let model = MomentsRelationModel(context: context, profileId: profileId, followers: followers, openPeer: openPeer)
    let signal = combineLatest(context.sharedContext.presentationData, model.promise.get())
    |> deliverOnMainQueue
    |> map { presentationData, state -> (ItemListControllerState, (ItemListNodeState, MomentsRelationArguments)) in
        let arguments = MomentsRelationArguments(presentationData: presentationData, context: context, open: { author in
            model.open(author)
        }, retry: {
            model.state.loaded = false
            model.state.loading = false
            model.load(refresh: true)
        })
        var entries: [MomentsRelationEntry] = []
        if state.hidden {
            entries = [.status(presentationData.strings.Moments_ListPrivate, false)]
        } else if state.failed && state.people.isEmpty {
            entries = [.status(presentationData.strings.Moments_LoadFailed, true)]
        } else if state.loaded && state.people.isEmpty {
            entries = [.status(presentationData.strings.Moments_EmptyPeople, false)]
        } else {
            for (index, author) in state.people.enumerated() {
                entries.append(.person(Int32(index), author, state.peers[author.id]))
            }
            if state.failed {
                entries.append(.status(presentationData.strings.Moments_LoadFailed, true))
            }
        }
        let title = followers ? presentationData.strings.Moments_Followers : presentationData.strings.Moments_Segment_Following
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(title), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks)
        return (controllerState, (listState, arguments))
    }
    let controller = ItemListController(context: context, state: signal)
    model.controller = controller
    controller.visibleBottomContentOffsetChanged = { [weak model] offset in
        if case let .known(value) = offset, value < 200.0 {
            model?.load(refresh: false)
        }
    }
    model.load(refresh: true)
    return controller
}
