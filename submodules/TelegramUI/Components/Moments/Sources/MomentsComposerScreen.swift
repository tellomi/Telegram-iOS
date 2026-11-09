import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import AccountContext
import MediaPickerUI

public final class MomentsComposerScreen: ViewController {
    private let context: AccountContext
    private let quoteId: String?
    private var presentationData: PresentationData
    private let textView = UITextView()
    private let audienceButton = UIButton(type: .system)
    private let publishButton = UIButton(type: .system)
    private let nearbySwitch = UISwitch()
    private var audience: MomentsAudienceKind?
    private var allowNearby = false
    private var linkRemoved = false
    private var imageCount = 0
    private var videoCount = 0
    private var hasVoice = false
    private var hasPoll = false

    public init(context: AccountContext, quoteId: String?) {
        self.context = context
        self.quoteId = quoteId
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }
        super.init(navigationBarPresentationData: NavigationBarPresentationData(presentationData: self.presentationData))
        self.title = momentsText(self.presentationData.strings, .composerTitle)
        self.navigationItem.setLeftBarButton(UIBarButtonItem(title: momentsText(self.presentationData.strings, .cancel), style: .plain, target: self, action: #selector(self.cancelPressed)), animated: false)
        self.navigationItem.setRightBarButton(UIBarButtonItem(title: momentsText(self.presentationData.strings, .publish), style: .done, target: self, action: #selector(self.publishPressed)), animated: false)
    }

    required init(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override public func loadDisplayNode() {
        self.displayNode = ASDisplayNode()
        self.displayNode.view.addSubview(self.textView)
        self.displayNode.view.addSubview(self.audienceButton)
        self.displayNode.view.addSubview(self.publishButton)
        self.displayNode.view.addSubview(self.nearbySwitch)
        self.textView.font = Font.regular(self.presentationData.listsFontSize.baseDisplaySize)
        self.textView.backgroundColor = .clear
        self.textView.delegate = self
        self.audienceButton.addTarget(self, action: #selector(self.chooseAudience), for: .touchUpInside)
        self.publishButton.addTarget(self, action: #selector(self.publishPressed), for: .touchUpInside)
        let photos = UIButton(type: .system)
        photos.setTitle(momentsText(self.presentationData.strings, .publish), for: .normal)
        photos.addTarget(self, action: #selector(self.pickImages), for: .touchUpInside)
        photos.accessibilityLabel = momentsText(self.presentationData.strings, .publish)
        self.displayNode.view.addSubview(photos)
        photos.tag = 41
        self.refresh()
        self.displayNodeDidLoad()
    }

    override public func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        let top = self.navigationLayout(layout: layout).navigationFrame.maxY
        self.audienceButton.frame = CGRect(x: 16, y: top + 8, width: layout.size.width - 32, height: 36)
        self.textView.frame = CGRect(x: 12, y: top + 48, width: layout.size.width - 24, height: 180)
        self.nearbySwitch.frame = CGRect(x: layout.size.width - 67, y: top + 236, width: 51, height: 31)
        if let photos = self.displayNode.view.viewWithTag(41) {
            photos.frame = CGRect(x: 16, y: top + 236, width: 120, height: 36)
        }
    }

    private func refresh() {
        let strings = self.presentationData.strings
        let title = self.audience.map { momentsAudienceTitle(strings, $0) } ?? momentsText(strings, .audienceChoose)
        self.audienceButton.setTitle(title, for: .normal)
        let state = MomentsComposerAttachmentState(imageCount: self.imageCount, videoCount: self.videoCount, hasVoice: self.hasVoice, hasPoll: self.hasPoll, hasLinkPreview: !self.linkRemoved && momentsScanText(self.textView.text ?? "").firstURL != nil)
        let hasBody = !(self.textView.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !state.isEmpty
        self.navigationItem.rightBarButtonItem?.isEnabled = hasBody && self.audience != nil
        self.publishButton.isEnabled = hasBody && self.audience != nil
        self.nearbySwitch.isHidden = self.audience != .everyone
        self.nearbySwitch.isOn = self.allowNearby
    }

    @objc private func chooseAudience() {
        let strings = self.presentationData.strings
        let sheet = ActionSheetController(theme: ActionSheetControllerTheme(presentationData: self.presentationData))
        let kinds: [MomentsAudienceKind] = [.everyone, .contacts, .closeFriends, .selected, .mutualFollowers]
        let buttons: [ActionSheetItem] = kinds.map { kind in
            ActionSheetButtonItem(title: momentsAudienceTitle(strings, kind), color: .accent, action: { [weak self, weak sheet] in
                sheet?.dismissAnimated()
                self?.audience = kind
                if kind != .everyone { self?.allowNearby = false }
                self?.refresh()
            })
        }
        sheet.setItemGroups([
            ActionSheetItemGroup(items: buttons),
            ActionSheetItemGroup(items: [ActionSheetButtonItem(title: momentsText(strings, .cancel), color: .accent, action: { [weak sheet] in sheet?.dismissAnimated() })])
        ])
        self.present(sheet, in: .window(.root))
    }

    @objc private func pickImages() {
        let state = MomentsComposerAttachmentState(imageCount: self.imageCount, videoCount: self.videoCount, hasVoice: self.hasVoice, hasPoll: self.hasPoll)
        if let rejection = momentsCanAdd(kind: .image, to: state) {
            self.presentRejection(rejection)
            return
        }
        let picker = MediaPickerScreenImpl(context: self.context, peer: nil, threadTitle: nil, chatLocation: nil, bannedSendVideos: self.imageCount > 0 ? (Int32(0), true) : nil, selectionLimit: MomentsLimits.standard.imageLimit - self.imageCount, subject: .assets(nil, .default))
        picker.legacyCompletion = { [weak self] _, signals, _, _, _, _, done in
            self?.imageCount += signals.count
            self?.refresh()
            done()
        }
        self.push(picker)
    }

    private func presentRejection(_ rejection: MomentsAttachmentRejection) {
        let text: String
        switch rejection {
        case .imageLimit, .videoLimit:
            text = momentsText(self.presentationData.strings, .loadFailed)
        case .videoTooLong, .voiceTooLong:
            text = momentsText(self.presentationData.strings, .loadFailed)
        default:
            text = momentsText(self.presentationData.strings, .loadFailed)
        }
        self.present(textAlertController(context: self.context, title: nil, text: text, actions: [TextAlertAction(type: .defaultAction, title: momentsText(self.presentationData.strings, .cancel), action: {})]), in: .window(.root))
    }

    @objc private func cancelPressed() {
        let dirty = !(self.textView.text ?? "").isEmpty || self.imageCount > 0 || self.audience != nil
        guard dirty else {
            self.navigationController?.popViewController(animated: true)
            return
        }
        let strings = self.presentationData.strings
        self.present(textAlertController(context: self.context, title: momentsText(strings, .draftTitle), text: momentsText(strings, .friendsHint), actions: [
            TextAlertAction(type: .defaultAction, title: momentsText(strings, .draftSave), action: { [weak self] in self?.navigationController?.popViewController(animated: true) }),
            TextAlertAction(type: .destructiveAction, title: momentsText(strings, .draftDiscard), action: { [weak self] in self?.navigationController?.popViewController(animated: true) }),
            TextAlertAction(type: .genericAction, title: momentsText(strings, .draftContinue), action: {})
        ], actionLayout: .vertical), in: .window(.root))
    }

    @objc private func publishPressed() {
        guard let audience = self.audience else { return }
        let text = self.textView.text ?? ""
        let scan = momentsScanText(text)
        let send = { [weak self] in
            guard let self else { return }
            var body: [String: Any] = [
                "text": text,
                "audience": ["kind": audience.rawValue],
                "comment_policy": MomentsCommentPolicy.everyoneWhoCanView.rawValue,
                "client_nonce": UUID().uuidString
            ]
            if self.allowNearby && audience == .everyone {
                body["location"] = ["allow_nearby": true]
            }
            if let quoteId = self.quoteId {
                body["quote_of"] = quoteId
            }
            if let url = scan.firstURL, !self.linkRemoved, momentsShowsLinkPreview(MomentsComposerAttachmentState(imageCount: self.imageCount, videoCount: self.videoCount, hasPoll: self.hasPoll, hasLinkPreview: true)) {
                body["link_preview"] = ["url": url]
            }
            let _ = (self.context.engine.moments.publish(body) |> deliverOnMainQueue).start(next: { [weak self] _ in
                self?.navigationController?.popViewController(animated: true)
            }, error: { [weak self] _ in
                guard let self else { return }
                self.present(textAlertController(context: self.context, title: nil, text: momentsText(self.presentationData.strings, .failedRetry), actions: [TextAlertAction(type: .defaultAction, title: momentsText(self.presentationData.strings, .retry), action: { [weak self] in self?.publishPressed() })]), in: .window(.root))
            })
        }
        if !scan.mentions.isEmpty && audience != .everyone {
            self.present(textAlertController(context: self.context, title: nil, text: momentsText(self.presentationData.strings, .mentionWarning) + "\n" + scan.mentions.joined(separator: ", "), actions: [
                TextAlertAction(type: .genericAction, title: momentsText(self.presentationData.strings, .cancel), action: {}),
                TextAlertAction(type: .defaultAction, title: momentsText(self.presentationData.strings, .publish), action: send)
            ]), in: .window(.root))
        } else {
            send()
        }
    }
}

extension MomentsComposerScreen: UITextViewDelegate {
    public func textViewDidChange(_ textView: UITextView) {
        if textView.text.count > MomentsLimits.standard.textLimit {
            textView.text = String(textView.text.prefix(MomentsLimits.standard.textLimit))
        }
        self.refresh()
    }
}
