import AccountContext
import AsyncDisplayKit
import Display
import Foundation
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences
import TellomiDiscover
import UIKit
import ShareWithPeersScreen

struct TellomiDiscoverComposeRequest {
    var text: String
    var visibility: TellomiDiscoverVisibility
    var userIds: [Int64]
    var nonce: String
    var quoteOf: String?
    var pollOptions: [String]?
}

final class TellomiDiscoverComposeController: ViewController, UITextViewDelegate {
    private let context: AccountContext
    private let textLimit: Int
    private let quoteOf: String?
    private let quotePreview: String
    private let nonce = UUID().uuidString
    private let publish: (TellomiDiscoverComposeRequest, @escaping (Result<TellomiDiscoverDecoded, TellomiDiscoverClientError>) -> Void) -> Void
    private let published: () -> Void
    private var presentationData: PresentationData
    private var presentationDataDisposable: Disposable?
    private var privacyDisposable: Disposable?
    private var privacy = EngineStoryPrivacy(base: .everyone, additionallyIncludePeers: [])
    private let textView = UITextView()
    private let quoteLabel = UILabel()
    private let pollButton = UIButton(type: .system)
    private let addOptionButton = UIButton(type: .system)
    private let visibilityButton = UIButton(type: .system)
    private let hintLabel = UILabel()
    private var optionFields: [UITextField] = []
    private var pollOn = false
    private var sending = false
    private var sendError: TellomiDiscoverClientError?

    init(context: AccountContext, textLimit: Int, quoteOf: String? = nil, quotePreview: String = "", publish: @escaping (TellomiDiscoverComposeRequest, @escaping (Result<TellomiDiscoverDecoded, TellomiDiscoverClientError>) -> Void) -> Void, published: @escaping () -> Void) {
        self.context = context
        self.textLimit = textLimit
        self.quoteOf = quoteOf.flatMap(tellomiDiscoverPostId)
        self.quotePreview = quotePreview
        self.publish = publish
        self.published = published
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }
        super.init(navigationBarPresentationData: NavigationBarPresentationData(presentationData: self.presentationData))
        let copy = TellomiDiscoverCopy.resolve(languageCode: self.presentationData.strings.primaryComponent.languageCode, pack: tellomiStringPack(primary: self.presentationData.strings.primaryComponent.dict, secondary: self.presentationData.strings.secondaryComponent?.dict))
        self.title = self.quoteOf == nil ? copy.compose : copy.quote
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
        self.quoteLabel.numberOfLines = 3
        self.quoteLabel.font = Font.regular(14.0)
        self.pollButton.contentHorizontalAlignment = .left
        self.pollButton.addTarget(self, action: #selector(self.pollPressed), for: .touchUpInside)
        self.pollButton.accessibilityIdentifier = "tellomi.discover.poll"
        self.addOptionButton.contentHorizontalAlignment = .left
        self.addOptionButton.addTarget(self, action: #selector(self.addOptionPressed), for: .touchUpInside)
        self.visibilityButton.contentHorizontalAlignment = .left
        self.visibilityButton.addTarget(self, action: #selector(self.visibilityPressed), for: .touchUpInside)
        self.hintLabel.numberOfLines = 2
        self.displayNode.view.addSubview(self.quoteLabel)
        self.displayNode.view.addSubview(self.textView)
        self.displayNode.view.addSubview(self.pollButton)
        self.displayNode.view.addSubview(self.addOptionButton)
        self.displayNode.view.addSubview(self.visibilityButton)
        self.displayNode.view.addSubview(self.hintLabel)
        if self.quoteOf == nil {
            self.ensureOptionFields(2)
        }
        self.apply()
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        guard self.isNodeLoaded else {
            return
        }
        let side: CGFloat = 16.0
        let width = max(1, layout.size.width - side * 2.0)
        var cursor = self.navigationLayout(layout: layout).navigationFrame.maxY + 8.0
        if self.quoteOf != nil {
            self.quoteLabel.frame = CGRect(x: side, y: cursor, width: width, height: 52)
            cursor = self.quoteLabel.frame.maxY + 8.0
        } else {
            self.quoteLabel.frame = .zero
        }
        self.textView.frame = CGRect(x: side, y: cursor, width: width, height: 120)
        cursor = self.textView.frame.maxY + 8.0
        let showPoll = self.pollOn && self.quoteOf == nil
        for field in self.optionFields {
            field.isHidden = !showPoll
            if showPoll {
                field.frame = CGRect(x: side, y: cursor, width: width, height: 36)
                cursor = field.frame.maxY + 8.0
            }
        }
        self.addOptionButton.isHidden = !showPoll || self.optionFields.count >= tellomiDiscoverPollOptionLimit
        if !self.addOptionButton.isHidden {
            self.addOptionButton.frame = CGRect(x: side, y: cursor, width: width, height: 32)
            cursor = self.addOptionButton.frame.maxY + 4.0
        }
        self.pollButton.isHidden = self.quoteOf != nil
        if !self.pollButton.isHidden {
            self.pollButton.frame = CGRect(x: side, y: cursor, width: width, height: 36)
            cursor = self.pollButton.frame.maxY + 4.0
        }
        self.visibilityButton.frame = CGRect(x: side, y: cursor, width: width, height: 36)
        self.hintLabel.frame = CGRect(x: side, y: self.visibilityButton.frame.maxY + 4, width: width, height: 40)
    }

    func textViewDidChange(_ textView: UITextView) {
        let _ = textView
        self.apply()
    }

    @objc private func visibilityPressed() {
        self.presentPrivacy(self.privacy)
    }

    @objc private func pollPressed() {
        self.pollOn = !self.pollOn
        if let layout = self.currentlyAppliedLayout {
            self.containerLayoutUpdated(layout, transition: .immediate)
        }
        self.apply()
    }

    @objc private func addOptionPressed() {
        guard self.optionFields.count < tellomiDiscoverPollOptionLimit else {
            return
        }
        self.ensureOptionFields(self.optionFields.count + 1)
        if let layout = self.currentlyAppliedLayout {
            self.containerLayoutUpdated(layout, transition: .immediate)
        }
        self.apply()
    }

    @objc private func sendPressed() {
        guard !self.sending, let choice = self.choice(), choice.publishable else {
            return
        }
        let options = self.pollOptions()
        if self.pollOn, options == nil {
            return
        }
        self.sending = true
        self.sendError = nil
        self.apply()
        let request = TellomiDiscoverComposeRequest(text: self.textView.text ?? "", visibility: choice.visibility, userIds: choice.userIds, nonce: self.nonce, quoteOf: self.quoteOf, pollOptions: self.pollOn ? options : nil)
        self.publish(request) { [weak self] result in
            guard let self else {
                return
            }
            self.sending = false
            switch result {
            case .success:
                self.published()
                self.navigationController?.popViewController(animated: true)
            case let .failure(error):
                self.sendError = error
                self.apply()
            }
        }
    }

    private func pollOptions() -> [String]? {
        guard self.pollOn, self.quoteOf == nil else {
            return nil
        }
        return tellomiDiscoverNormalizedPollOptions(self.optionFields.map { $0.text ?? "" })
    }

    private func ensureOptionFields(_ count: Int) {
        while self.optionFields.count < count {
            let field = UITextField()
            field.borderStyle = .roundedRect
            field.font = Font.regular(16.0)
            field.accessibilityIdentifier = "tellomi.discover.poll.option.\(self.optionFields.count)"
            field.addTarget(self, action: #selector(self.optionChanged), for: .editingChanged)
            self.optionFields.append(field)
            if self.isNodeLoaded {
                self.displayNode.view.addSubview(field)
            }
        }
    }

    @objc private func optionChanged() {
        self.apply()
    }

    private func choice() -> TellomiDiscoverAudienceChoice? {
        var ids: [Int64] = []
        for peerId in self.privacy.additionallyIncludePeers {
            guard let id = peerId.tellomiCloudUserId else {
                return TellomiDiscoverAudienceChoice(visibility: .include, publishable: false, reason: "audience_invalid", userIds: [])
            }
            ids.append(id)
        }
        guard let selfUserId = self.context.account.peerId.tellomiCloudUserId else {
            return nil
        }
        return tellomiDiscoverAudience(base: self.privacy.base.tellomiDiscoverBase, includePeerIds: ids, selfUserId: selfUserId)
    }

    private func apply() {
        let copy = TellomiDiscoverCopy.resolve(languageCode: self.presentationData.strings.primaryComponent.languageCode, pack: tellomiStringPack(primary: self.presentationData.strings.primaryComponent.dict, secondary: self.presentationData.strings.secondaryComponent?.dict))
        let choice = self.choice()
        let title = choice.map { copy.visibilityTitle($0.visibility) } ?? copy.everyone
        self.visibilityButton.setTitle(copy.visibility + " · " + title, for: .normal)
        self.visibilityButton.setTitleColor(self.presentationData.theme.list.itemAccentColor, for: .normal)
        self.pollButton.setTitle(copy.poll, for: .normal)
        self.pollButton.setTitleColor(self.pollOn ? self.presentationData.theme.list.itemAccentColor : self.presentationData.theme.list.itemSecondaryTextColor, for: .normal)
        self.addOptionButton.setTitle(copy.pollAdd, for: .normal)
        self.addOptionButton.setTitleColor(self.presentationData.theme.list.itemAccentColor, for: .normal)
        let index = 1
        for (offset, field) in self.optionFields.enumerated() {
            field.placeholder = copy.pollOption + " \(offset + index)"
            field.textColor = self.presentationData.theme.list.itemPrimaryTextColor
        }
        if self.quoteOf != nil {
            self.quoteLabel.text = self.quotePreview.isEmpty ? copy.quote : self.quotePreview
        }
        self.quoteLabel.textColor = self.presentationData.theme.list.itemSecondaryTextColor
        let errorText = self.sendError.flatMap { copy.failureText($0) }
        if self.pollOn, self.pollOptions() == nil, errorText == nil {
            self.hintLabel.text = copy.pollHint
        } else {
            self.hintLabel.text = errorText ?? copy.reasonText(choice?.reason)
        }
        self.hintLabel.textColor = self.presentationData.theme.list.itemSecondaryTextColor
        self.hintLabel.font = Font.regular(13.0)
        self.textView.textColor = self.presentationData.theme.list.itemPrimaryTextColor
        self.displayNode.backgroundColor = self.presentationData.theme.list.plainBackgroundColor
        let text = self.textView.text ?? ""
        let pollReady = !self.pollOn || self.pollOptions() != nil
        let canSend = !self.sending && choice?.publishable == true && pollReady && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.count <= self.textLimit && tellomiDiscoverClientNonce(self.nonce)
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
