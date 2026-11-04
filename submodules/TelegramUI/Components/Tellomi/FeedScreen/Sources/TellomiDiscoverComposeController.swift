import AccountContext
import AsyncDisplayKit
import Display
import Foundation
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import TellomiDiscover
import UIKit
import ShareWithPeersScreen

final class TellomiDiscoverComposeController: ViewController, UITextViewDelegate {
    private let context: AccountContext
    private let publish: (String, TellomiDiscoverVisibility, @escaping (Result<TellomiDiscoverDecoded, TellomiDiscoverClientError>) -> Void) -> Void
    private let published: () -> Void
    private var presentationData: PresentationData
    private var presentationDataDisposable: Disposable?
    private var privacyDisposable: Disposable?
    private var privacy = EngineStoryPrivacy(base: .everyone, additionallyIncludePeers: [])
    private let textView = UITextView()
    private let visibilityButton = UIButton(type: .system)
    private let hintLabel = UILabel()
    private var sending = false

    init(context: AccountContext, publish: @escaping (String, TellomiDiscoverVisibility, @escaping (Result<TellomiDiscoverDecoded, TellomiDiscoverClientError>) -> Void) -> Void, published: @escaping () -> Void) {
        self.context = context
        self.publish = publish
        self.published = published
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }
        super.init(navigationBarPresentationData: NavigationBarPresentationData(presentationData: self.presentationData))
        let copy = TellomiDiscoverCopy.resolve(languageCode: self.presentationData.strings.primaryComponent.languageCode)
        self.title = copy.compose
        self.presentationDataDisposable = (context.sharedContext.presentationData
        |> deliverOnMainQueue).start(next: { [weak self] presentationData in
            guard let self else {
                return
            }
            self.presentationData = presentationData
            self.apply()
        })
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.presentationDataDisposable?.dispose()
        self.privacyDisposable?.dispose()
    }

    override func loadDisplayNode() {
        self.displayNode = ASDisplayNode()
        self.displayNodeDidLoad()
        self.textView.font = Font.regular(17.0)
        self.textView.backgroundColor = .clear
        self.textView.delegate = self
        self.textView.accessibilityIdentifier = "tellomi.discover.compose"
        self.visibilityButton.contentHorizontalAlignment = .left
        self.visibilityButton.addTarget(self, action: #selector(self.visibilityPressed), for: .touchUpInside)
        self.hintLabel.numberOfLines = 2
        self.displayNode.view.addSubview(self.textView)
        self.displayNode.view.addSubview(self.visibilityButton)
        self.displayNode.view.addSubview(self.hintLabel)
        self.apply()
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        guard self.isNodeLoaded else {
            return
        }
        let top = self.navigationLayout(layout: layout).navigationFrame.maxY + 8.0
        let side: CGFloat = 16.0
        let width = max(1, layout.size.width - side * 2.0)
        self.textView.frame = CGRect(x: side, y: top, width: width, height: 160)
        self.visibilityButton.frame = CGRect(x: side, y: self.textView.frame.maxY + 12, width: width, height: 36)
        self.hintLabel.frame = CGRect(x: side, y: self.visibilityButton.frame.maxY + 4, width: width, height: 40)
    }

    func textViewDidChange(_ textView: UITextView) {
        let _ = textView
        self.apply()
    }

    @objc private func visibilityPressed() {
        self.presentPrivacy(self.privacy)
    }

    @objc private func sendPressed() {
        guard !self.sending, let choice = self.choice(), choice.publishable else {
            return
        }
        self.sending = true
        self.apply()
        self.publish(self.textView.text ?? "", choice.visibility) { [weak self] result in
            guard let self else {
                return
            }
            self.sending = false
            switch result {
            case .success:
                self.published()
                self.navigationController?.popViewController(animated: true)
            case .failure:
                self.apply()
            }
        }
    }

    private func choice() -> TellomiDiscoverAudienceChoice? {
        return tellomiDiscoverAudience(base: self.privacy.base.tellomiDiscoverBase, includePeerIds: self.privacy.additionallyIncludePeers.map { $0.toInt64() })
    }

    private func apply() {
        let copy = TellomiDiscoverCopy.resolve(languageCode: self.presentationData.strings.primaryComponent.languageCode)
        let choice = self.choice()
        let title = choice.map { copy.visibilityTitle($0.visibility) } ?? copy.everyone
        self.visibilityButton.setTitle(copy.visibility + " · " + title, for: .normal)
        self.visibilityButton.setTitleColor(self.presentationData.theme.list.itemAccentColor, for: .normal)
        self.hintLabel.text = copy.reasonText(choice?.reason)
        self.hintLabel.textColor = self.presentationData.theme.list.itemSecondaryTextColor
        self.hintLabel.font = Font.regular(13.0)
        self.textView.textColor = self.presentationData.theme.list.itemPrimaryTextColor
        self.displayNode.backgroundColor = self.presentationData.theme.list.plainBackgroundColor
        let canSend = !self.sending && choice?.publishable == true && tellomiDiscoverPublishBody(text: self.textView.text ?? "", visibility: choice?.visibility ?? .everyone) != nil
        let item = UIBarButtonItem(title: copy.publish, style: .done, target: self, action: #selector(self.sendPressed))
        item.isEnabled = canSend
        self.navigationItem.setRightBarButton(item, animated: false)
    }

    private func presentPrivacy(_ privacy: EngineStoryPrivacy) {
        let context = self.context
        let stateContext = ShareWithPeersScreen.StateContext(
            context: context,
            subject: .stories(editing: true, count: 1),
            editing: true,
            initialSelectedPeers: [privacy.base: privacy.additionallyIncludePeers],
            closeFriends: context.engine.data.get(TelegramEngine.EngineData.Item.Contacts.CloseFriends())
        )
        self.privacyDisposable?.dispose()
        self.privacyDisposable = (stateContext.ready
        |> filter { $0 }
        |> take(1)
        |> deliverOnMainQueue).start(next: { [weak self] _ in
            guard let self else {
                return
            }
            let controller = ShareWithPeersScreen(
                context: context,
                initialPrivacy: privacy,
                stateContext: stateContext,
                completion: { [weak self] _, result, _, _, peers, _, completed in
                    guard let self, completed else {
                        return
                    }
                    if result.base == .closeFriends {
                        let _ = self.context.engine.privacy.updateCloseFriends(peerIds: result.additionallyIncludePeers).start()
                        self.privacy = EngineStoryPrivacy(base: .closeFriends, additionallyIncludePeers: [])
                        let _ = peers
                    } else {
                        self.privacy = result
                    }
                    self.apply()
                },
                editCategory: { [weak self] privacy, _, _, _ in
                    self?.presentCategory(privacy)
                }
            )
            self.push(controller)
        })
    }

    private func presentCategory(_ privacy: EngineStoryPrivacy) {
        let context = self.context
        let subject: ShareWithPeersScreen.StateContext.Subject
        if privacy.base == .nobody {
            subject = .chats(blocked: false)
        } else {
            subject = .contacts(base: privacy.base)
        }
        let stateContext = ShareWithPeersScreen.StateContext(
            context: context,
            subject: subject,
            editing: true,
            initialPeerIds: Set(privacy.additionallyIncludePeers)
        )
        self.privacyDisposable?.dispose()
        self.privacyDisposable = (stateContext.ready
        |> filter { $0 }
        |> take(1)
        |> deliverOnMainQueue).start(next: { [weak self] _ in
            guard let self else {
                return
            }
            let controller = ShareWithPeersScreen(
                context: context,
                initialPrivacy: privacy,
                stateContext: stateContext,
                completion: { [weak self] _, result, _, _, peers, _, completed in
                    guard let self, completed else {
                        return
                    }
                    if result.base == .closeFriends {
                        let _ = context.engine.privacy.updateCloseFriends(peerIds: result.additionallyIncludePeers).start()
                        let _ = peers
                        self.privacy = EngineStoryPrivacy(base: .closeFriends, additionallyIncludePeers: [])
                    } else {
                        self.privacy = result
                    }
                    self.presentPrivacy(self.privacy)
                }
            )
            self.push(controller)
        })
    }
}

private extension Stories.Item.Privacy.Base {
    var tellomiDiscoverBase: TellomiDiscoverStoryBase {
        switch self {
        case .everyone:
            return .everyone
        case .contacts:
            return .contacts
        case .closeFriends:
            return .closeFriends
        case .nobody:
            return .nobody
        }
    }
}
