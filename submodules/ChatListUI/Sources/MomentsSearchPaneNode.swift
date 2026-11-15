import Foundation
import UIKit
import AsyncDisplayKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import AccountContext
import MomentsUI

final class MomentsSearchPaneNode: ASDisplayNode, ChatListSearchPaneNode {
    private let content: MomentsSearchContentNode
    private let ready = Promise<Bool>(true)
    private var disposable: Disposable?
    private var presentationData: PresentationData
    private var query = ""
    var isReady: Signal<Bool, NoError> { self.ready.get() }
    var isCurrent: Bool = false
    var searchCurrentMessages: [EngineMessage]? { nil }

    init(context: AccountContext, presentationData: PresentationData, searchQuery: Signal<String?, NoError>, interaction: ChatListSearchInteraction) {
        self.content = MomentsSearchContentNode(context: context)
        self.presentationData = presentationData
        super.init()
        self.addSubnode(self.content)
        self.content.openPost = { card in
            interaction.present(MomentsDetailScreen(context: context, card: card), nil)
        }
        self.content.openTopic = { name in
            let screen = MomentsTopicScreen(context: context, name: name)
            screen.openPeer = { peerId in
                let _ = (context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId))
                |> deliverOnMainQueue).start(next: { peer in
                    if let peer {
                        interaction.openPeer(peer, nil, nil, false)
                    }
                })
            }
            interaction.present(screen, nil)
        }
        self.content.openPeer = { peerId in
            let _ = (context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId))
            |> deliverOnMainQueue).start(next: { peer in
                if let peer {
                    interaction.openPeer(peer, nil, nil, false)
                }
            })
        }
        self.disposable = (searchQuery |> deliverOnMainQueue).start(next: { [weak self] query in
            guard let self else { return }
            self.query = query ?? ""
            self.content.update(size: self.bounds.size, presentationData: self.presentationData, query: self.query)
        })
    }

    deinit {
        self.disposable?.dispose()
    }

    func update(size: CGSize, sideInsets: UIEdgeInsets, topInset: CGFloat, bottomInset: CGFloat, visibleHeight: CGFloat, presentationData: PresentationData, synchronous: Bool, transition: ContainedViewLayoutTransition) {
        self.presentationData = presentationData
        transition.updateFrame(node: self.content, frame: CGRect(origin: .zero, size: size))
        self.content.update(size: size, presentationData: presentationData, query: self.query)
    }

    func scrollToTop() -> Bool { return false }
    func cancelPreviewGestures() {}
    func transitionNodeForGallery(messageId: EngineMessage.Id, media: EngineMedia) -> (ASDisplayNode, CGRect, () -> (UIView?, UIView?))? { return nil }
    func addToTransitionSurface(view: UIView) {}
    func updateHiddenMedia() {}
    func updateSelectedMessages(animated: Bool) {}
    func previewViewAndActionAtLocation(_ location: CGPoint) -> (UIView, CGRect, Any)? { return nil }
    func didBecomeFocused() {}
    func removeAds() {}
}
