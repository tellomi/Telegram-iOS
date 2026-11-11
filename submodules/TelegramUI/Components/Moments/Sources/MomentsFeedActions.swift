import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import AccountContext
import ContextUI
import PeerReportScreen
import PresentationDataUtils

enum MomentsFeedMutation {
    case notInterested(String)
    case hide(String)
    case undo(String)
    case mute(String)
    case reported(String)
}

/// The post actions the home feed, a profile, a topic and a collection all call.
final class MomentsFeedActions {
    let context: AccountContext
    var controller: () -> ViewController? = { nil }
    var presentationData: PresentationData
    var openPeer: ((EnginePeer.Id) -> Void)?
    var onReplace: ((String, @escaping (MomentsCard) -> MomentsCard) -> Void)?
    var onExpand: ((String) -> Void)?
    var onTopic: ((String) -> Void)?
    var onSheet: ((Bool) -> Void)?
    var onMutation: ((MomentsFeedMutation) -> Void)?
    var beforeOpen: ((MomentsFeedPlace) -> Void)?

    init(context: AccountContext, presentationData: PresentationData) {
        self.context = context
        self.presentationData = presentationData
    }

    func handlers() -> MomentsPostHandlers {
        return MomentsPostHandlers(open: { [weak self] card in
            self?.openDetail(card, focusCommentId: nil)
        }, author: { [weak self] card in
            self?.openAuthor(card)
        }, like: { [weak self] card in
            self?.toggleLike(card)
        }, comment: { [weak self] card in
            self?.openComments(card)
        }, repost: { [weak self] card in
            self?.repost(card)
        }, share: { [weak self] card in
            self?.share(card)
        }, save: { [weak self] card in
            self?.toggleSave(card)
        }, more: { [weak self] card, view in
            self?.more(card, view)
        }, follow: { [weak self] card in
            self?.follow(card)
        }, undo: { [weak self] id in
            self?.undo(id)
        }, fullText: { [weak self] card in
            self?.onExpand?(card.id)
        }, topic: { [weak self] name in
            self?.openTopic(name)
        }, link: { [weak self] url in
            self?.openURL(url)
        }, likers: { [weak self] card in
            self?.openLikers(card)
        }, voters: { [weak self] card in
            self?.openVoters(card)
        }, openMedia: { [weak self] card, index in
            self?.openMedia(card, index: index)
        })
    }

    func openDetail(_ card: MomentsCard, focusCommentId: String?) {
        guard let controller = self.controller() else {
            return
        }
        if card.isUnavailable {
            self.presentUnavailable(controller)
            return
        }
        self.beforeOpen?(.post(id: card.id))
        let detail = MomentsDetailScreen(context: self.context, card: card, focusCommentId: focusCommentId)
        detail.openPeer = self.openPeer
        (controller.navigationController as? NavigationController)?.pushViewController(detail)
    }

    func openTopic(_ raw: String) {
        guard let controller = self.controller() else {
            return
        }
        guard let name = momentsTopicName(raw) else {
            self.presentUnavailable(controller)
            return
        }
        self.beforeOpen?(.topic(name: name, offset: 0))
        if let onTopic = self.onTopic {
            onTopic(name)
            return
        }
        let screen = MomentsTopicScreen(context: self.context, name: name)
        screen.openPeer = self.openPeer
        (controller.navigationController as? NavigationController)?.pushViewController(screen)
    }

    private func openAuthor(_ card: MomentsCard) {
        guard let controller = self.controller() else {
            return
        }
        guard let id = card.author?.telegramUserId, let peerId = momentsPeerId(id) else {
            self.presentUnavailable(controller)
            return
        }
        guard let openPeer = self.openPeer else {
            self.presentUnavailable(controller)
            return
        }
        self.beforeOpen?(.author(telegramUserId: id))
        openPeer(peerId)
    }

    private func openComments(_ card: MomentsCard) {
        guard let controller = self.controller() else {
            return
        }
        if card.isUnavailable {
            self.presentUnavailable(controller)
            return
        }
        let sheet = MomentsCommentSheet(context: self.context, card: card)
        sheet.openPeer = self.openPeer
        self.onSheet?(true)
        sheet.onDismiss = { [weak self] in
            self?.onSheet?(false)
        }
        controller.present(sheet, in: .window(.root))
    }

    private func openMedia(_ card: MomentsCard, index: Int) {
        guard let controller = self.controller() else {
            return
        }
        let hasMedia = card.media.contains { momentsPresentsAsImage($0.type) || momentsPresentsAsVideo($0.type) }
        if hasMedia {
            self.beforeOpen?(.media(postId: card.id, index: index))
        }
        momentsPresentGallery(context: self.context, card: card, index: index, controller: controller)
    }

    private func toggleLike(_ card: MomentsCard) {
        self.onReplace?(card.id) { item in
            var copy = item
            copy.viewer.liked.toggle()
            copy.counts.likes += copy.viewer.liked ? 1 : -1
            if copy.counts.likes < 0 {
                copy.counts.likes = 0
            }
            return copy
        }
        let _ = self.context.engine.moments.setLiked(card.id, liked: !card.viewer.liked).start(error: { [weak self] _ in
            self?.onReplace?(card.id) { _ in card }
        })
    }

    private func toggleSave(_ card: MomentsCard) {
        self.onReplace?(card.id) { item in
            var copy = item
            copy.viewer.saved.toggle()
            return copy
        }
        let _ = self.context.engine.moments.setSaved(card.id, saved: !card.viewer.saved).start(error: { [weak self] _ in
            self?.onReplace?(card.id) { _ in card }
        })
    }

    private func follow(_ card: MomentsCard) {
        guard let author = card.author else {
            return
        }
        let next = !author.followed
        self.onReplace?(card.id) { item in
            var copy = item
            if var author = copy.author {
                author.followed = next
                copy.author = author
            }
            return copy
        }
        let _ = self.context.engine.moments.setFollow(authorId: author.id, follow: next).start(error: { [weak self] _ in
            self?.onReplace?(card.id) { _ in card }
        })
    }

    private func repost(_ card: MomentsCard) {
        guard let controller = self.controller() else {
            return
        }
        guard momentsCanRepostOrQuote(audience: card.audience?.kind) else {
            controller.present(textAlertController(context: self.context, title: nil, text: self.presentationData.strings.Moments_RepostPublicOnly, actions: [TextAlertAction(type: .defaultAction, title: self.presentationData.strings.Common_Cancel, action: {})]), in: .window(.root))
            return
        }
        let sheet = ActionSheetController(theme: ActionSheetControllerTheme(presentationData: self.presentationData))
        sheet.setItemGroups([
            ActionSheetItemGroup(items: [
                ActionSheetButtonItem(title: self.presentationData.strings.Moments_Repost, color: .accent, action: { [weak self, weak sheet] in
                    sheet?.dismissAnimated()
                    let _ = self?.context.engine.moments.setRepost(card.id, repost: true).start()
                }),
                ActionSheetButtonItem(title: self.presentationData.strings.Moments_Quote, color: .accent, action: { [weak self, weak sheet] in
                    sheet?.dismissAnimated()
                    self?.presentComposer(quoteId: card.id)
                })
            ]),
            ActionSheetItemGroup(items: [ActionSheetButtonItem(title: self.presentationData.strings.Common_Cancel, color: .accent, action: { [weak sheet] in
                sheet?.dismissAnimated()
            })])
        ])
        controller.present(sheet, in: .window(.root))
    }

    private func share(_ card: MomentsCard) {
        guard let controller = self.controller() else {
            return
        }
        let link = momentsPostLink(id: card.id)
        let share = self.context.sharedContext.makeShareController(context: self.context, params: ShareControllerParams(subject: .url(link)))
        controller.present(share, in: .window(.root))
    }

    private func more(_ card: MomentsCard, _ source: UIView) {
        guard let controller = self.controller() else {
            return
        }
        let strings = self.presentationData.strings
        let mine = card.author?.telegramUserId == self.context.account.peerId.toInt64()
        var items: [ContextMenuItem] = []
        if mine {
            items.append(.action(ContextMenuActionItem(text: strings.Common_Delete, textColor: .destructive, icon: { _ in nil }, action: { [weak self] _, f in
                f(.default)
                let _ = self?.context.engine.moments.deletePost(id: card.id).start()
            })))
        } else {
            items.append(.action(ContextMenuActionItem(text: strings.Moments_NotInterested, icon: { _ in nil }, action: { [weak self] _, f in
                f(.default)
                let _ = self?.context.engine.moments.notInterested(postId: card.id).start()
                self?.onMutation?(.notInterested(card.id))
            })))
            items.append(.action(ContextMenuActionItem(text: strings.Moments_HidePost, icon: { _ in nil }, action: { [weak self] _, f in
                f(.default)
                let _ = self?.context.engine.moments.hide(postId: card.id, undo: false).start()
                self?.onMutation?(.hide(card.id))
            })))
            if let author = card.author {
                items.append(.action(ContextMenuActionItem(text: strings.Moments_Mute, icon: { _ in nil }, action: { [weak self] _, f in
                    f(.default)
                    let _ = self?.context.engine.moments.setMuted(profileId: author.id, muted: true).start()
                    self?.onMutation?(.mute(author.id))
                })))
            }
            items.append(.action(ContextMenuActionItem(text: strings.Moments_Report, textColor: .destructive, icon: { _ in nil }, action: { [weak self] _, f in
                f(.default)
                self?.report(card)
            })))
        }
        items.append(.action(ContextMenuActionItem(text: strings.Moments_CopyLink, icon: { _ in nil }, action: { _, f in
            f(.default)
            UIPasteboard.general.string = momentsPostLink(id: card.id)
        })))
        let contextController = makeContextController(presentationData: self.presentationData, source: .reference(MomentsContextSource(controller: controller, sourceView: source)), items: .single(ContextController.Items(content: .list(items))), gesture: nil)
        controller.presentInGlobalOverlay(contextController)
    }

    private func undo(_ id: String) {
        let _ = self.context.engine.moments.hide(postId: id, undo: true).start()
        self.onMutation?(.undo(id))
    }

    private func report(_ card: MomentsCard) {
        guard let controller = self.controller(), let authorId = card.author?.telegramUserId, let peerId = momentsPeerId(authorId) else {
            return
        }
        presentPeerReportOptions(context: self.context, parent: controller, contextController: nil, subject: .peer(peerId), passthrough: true, completion: { [weak self] reason, _ in
            guard let self, let reason else {
                return
            }
            let _ = self.context.engine.moments.report(targetType: "post", targetId: card.id, reason: momentsReportReasonCode(reason), detail: nil).start()
            self.onMutation?(.reported(card.id))
        })
    }

    private func presentComposer(quoteId: String?) {
        guard let controller = self.controller() else {
            return
        }
        let composer = MomentsComposerScreen(context: self.context, quoteId: quoteId)
        (controller.navigationController as? NavigationController)?.pushViewController(composer)
    }

    private func openURL(_ url: String) {
        guard let controller = self.controller() else {
            return
        }
        self.context.sharedContext.openExternalUrl(context: self.context, urlContext: .generic, url: url, forceExternal: false, presentationData: self.presentationData, navigationController: controller.navigationController as? NavigationController, dismissInput: {})
    }

    private func openLikers(_ card: MomentsCard) {
        guard let controller = self.controller() else {
            return
        }
        (controller.navigationController as? NavigationController)?.pushViewController(momentsPeopleController(context: self.context, title: self.presentationData.strings.Moments_Like, load: self.context.engine.moments.likers(postId: card.id) |> map { authors in
            [MomentsPeopleSection(title: nil, people: authors)]
        }))
    }

    private func openVoters(_ card: MomentsCard) {
        guard let controller = self.controller(), card.poll != nil else {
            return
        }
        (controller.navigationController as? NavigationController)?.pushViewController(momentsPeopleController(context: self.context, title: self.presentationData.strings.Moments_EndPoll, load: self.context.engine.moments.pollVoters(postId: card.id) |> map { options in
            options.map { MomentsPeopleSection(title: $0.text, people: $0.voters) }
        }))
    }

    func presentUnavailable(_ controller: ViewController) {
        controller.present(textAlertController(context: self.context, title: nil, text: self.presentationData.strings.Moments_Unavailable, actions: [TextAlertAction(type: .defaultAction, title: self.presentationData.strings.Common_Cancel, action: {})]), in: .window(.root))
    }
}

func momentsPeerId(_ telegramUserId: Int64) -> EnginePeer.Id? {
    guard telegramUserId != 0 else {
        return nil
    }
    return EnginePeer.Id(namespace: Namespaces.Peer.CloudUser, id: EnginePeer.Id.Id._internalFromInt64Value(telegramUserId))
}

final class MomentsReturnAnchor {
    private var covered = false
    private var cover: MomentsFeedPlace?
    private(set) var liveOffset: CGFloat = 0
    private var returnOffset: CGFloat = 0

    func noteOffset(_ offset: CGFloat) {
        if !self.covered {
            self.liveOffset = offset
        }
    }

    func willOpen(_ place: MomentsFeedPlace) {
        self.returnOffset = self.liveOffset
        self.covered = true
        self.cover = place
    }

    func returned(root: (CGFloat) -> MomentsFeedPlace, restore: (MomentsFeedPlace) -> Void) {
        guard self.covered, let cover = self.cover else {
            return
        }
        let stack = [root(self.returnOffset), cover]
        self.covered = false
        self.cover = nil
        guard momentsListAnchorSurvives(stack), let restored = momentsFeedPlaceAfterBack(stack) else {
            return
        }
        restore(restored)
    }
}
