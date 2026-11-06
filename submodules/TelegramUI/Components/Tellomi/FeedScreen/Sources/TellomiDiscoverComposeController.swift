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

/// Text, visibility, and an optional poll, quote, or finished image keys.
/// A picked video is still not a field. `mediaKeys` is set only after every
/// selected image has a `m/<uuid>` key. No images leaves it nil.
struct TellomiDiscoverComposeRequest {
    var text: String
    var visibility: TellomiDiscoverVisibility
    var userIds: [Int64]
    var nonce: String
    var quoteOf: String?
    var pollOptions: [String]?
    var linkPreview: TellomiDiscoverLink.Preview?
    var mediaKeys: [String]?
}

final class TellomiDiscoverComposeController: ViewController, UITextViewDelegate {
    private let context: AccountContext
    private let textLimit: Int
    private let quoteOf: String?
    private let quotePreview: String
    private let nonce = UUID().uuidString
    /// Stays closed unless this compose was opened with `media_upload`.
    private var imagePublish = TellomiDiscoverImagePublish()
    private let mediaUpload: Bool
    private let feedConfiguration: TellomiDiscoverConfiguration?
    private let loader: TellomiDiscoverLoader?
    private let previews: TellomiDiscoverLocalPreviewBook?
    private var imageBytes: [String: Data] = [:]
    private var imageSessions: [String: TellomiDiscoverImageUploadSession] = [:]
    private var imagePictures: [String: UIImage] = [:]
    private var imageGeneration: [String: Int] = [:]
    private var imageFlight: String?
    private var imageNotice: String?
    private let imageButton = UIButton(type: .system)
    private var imageRows: [TellomiDiscoverImageRow] = []
    private var photoPicker: NSObject?
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
    private let scrollView = UIScrollView()
    private let videoButton = UIButton(type: .system)
    private let videoRemoveButton = UIButton(type: .system)
    private let videoHintLabel = UILabel()
    private let videoStatusLabel = UILabel()
    private let videoPreviewView = UIImageView()
    private var optionFields: [UITextField] = []
    private var pollOn = false
    private var sending = false
    private var sendError: TellomiDiscoverClientError?
    private var videoPicker: AnyObject?
    private var pendingPickGeneration = 0
    private var videoURL: URL?
    private var videoDurationMs: Int64 = 0
    private var videoPreview: UIImage?
    private var videoBusy = false
    private var videoGeneration = 0
    private var videoDecision: TellomiDiscoverVideo.Decision = .none
    private let placeholderLabel = UILabel()
    private let mentionButton = UIButton(type: .system)
    private let suggestionStack = UIStackView()
    private let linkCard = TellomiDiscoverLinkCardView()
    private var people: [TellomiDiscoverMention.Person] = []
    private var peopleDisposable: Disposable?
    private var activeQuery: TellomiDiscoverMention.Query?
    private var editingMention = false
    private var paintingMentions = false
    private var linkWork: DispatchWorkItem?
    private var linkGeneration = 0
    private var linkURL: String?
    private var linkPreview: TellomiDiscoverLink.Preview?
    private var linkSettled = false
    private var linkHolding = false

    init(context: AccountContext, textLimit: Int, quoteOf: String? = nil, quotePreview: String = "", publish: @escaping (TellomiDiscoverComposeRequest, @escaping (Result<TellomiDiscoverDecoded, TellomiDiscoverClientError>) -> Void) -> Void, published: @escaping () -> Void, mediaUpload: Bool = false, configuration: TellomiDiscoverConfiguration? = nil, loader: TellomiDiscoverLoader? = nil, previews: TellomiDiscoverLocalPreviewBook? = nil) {
        self.context = context
        self.textLimit = textLimit
        self.quoteOf = quoteOf.flatMap(tellomiDiscoverPostId)
        self.quotePreview = quotePreview
        self.publish = publish
        self.published = published
        self.mediaUpload = mediaUpload
        self.feedConfiguration = configuration
        self.loader = loader
        self.previews = previews
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
            self.relayout()
        })
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.presentationDataDisposable?.dispose()
        self.privacyDisposable?.dispose()
        self.peopleDisposable?.dispose()
        self.linkWork?.cancel()
        TellomiDiscoverLocalVideo.discard(self.videoURL)
    }

    override func loadDisplayNode() {
        self.displayNode = ASDisplayNode()
        self.displayNodeDidLoad()
        self.textView.font = Font.regular(17.0)
        self.textView.backgroundColor = .clear
        self.textView.delegate = self
        self.textView.accessibilityIdentifier = "tellomi.discover.compose"
        self.placeholderLabel.font = Font.regular(17.0)
        self.placeholderLabel.numberOfLines = 2
        self.placeholderLabel.isUserInteractionEnabled = false
        self.mentionButton.contentHorizontalAlignment = .left
        self.mentionButton.addTarget(self, action: #selector(self.mentionPressed), for: .touchUpInside)
        self.mentionButton.accessibilityIdentifier = "tellomi.discover.mention"
        self.suggestionStack.axis = .vertical
        self.suggestionStack.alignment = .fill
        self.suggestionStack.distribution = .fillEqually
        self.suggestionStack.isHidden = true
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
        self.scrollView.alwaysBounceVertical = true
        self.scrollView.delaysContentTouches = false
        self.scrollView.keyboardDismissMode = .interactive
        self.scrollView.backgroundColor = .clear
        self.scrollView.contentInsetAdjustmentBehavior = .never
        self.scrollView.showsHorizontalScrollIndicator = false
        self.videoButton.contentHorizontalAlignment = .left
        self.videoButton.addTarget(self, action: #selector(self.videoPressed), for: .touchUpInside)
        self.videoButton.accessibilityIdentifier = "tellomi.discover.video"
        self.videoRemoveButton.contentHorizontalAlignment = .left
        self.videoRemoveButton.addTarget(self, action: #selector(self.videoRemovePressed), for: .touchUpInside)
        self.videoRemoveButton.accessibilityIdentifier = "tellomi.discover.video.remove"
        self.videoHintLabel.numberOfLines = 0
        self.videoHintLabel.font = Font.regular(13.0)
        self.videoHintLabel.accessibilityIdentifier = "tellomi.discover.video.hint"
        self.videoStatusLabel.numberOfLines = 0
        self.videoStatusLabel.font = Font.regular(14.0)
        self.videoStatusLabel.accessibilityIdentifier = "tellomi.discover.video.status"
        self.videoPreviewView.contentMode = .scaleAspectFit
        self.videoPreviewView.clipsToBounds = true
        self.videoPreviewView.layer.cornerRadius = 8.0
        self.videoPreviewView.isUserInteractionEnabled = false
        self.videoPreviewView.isHidden = true
        self.imageButton.contentHorizontalAlignment = .left
        self.imageButton.addTarget(self, action: #selector(self.imagePressed), for: .touchUpInside)
        self.imageButton.accessibilityIdentifier = "tellomi.discover.images"
        if self.imagesEnabled {
            _ = self.imagePublish.useVerifiedContract()
        }
        self.displayNode.view.addSubview(self.scrollView)
        self.scrollView.addSubview(self.quoteLabel)
        self.scrollView.addSubview(self.textView)
        self.scrollView.addSubview(self.placeholderLabel)
        self.scrollView.addSubview(self.linkCard)
        self.scrollView.addSubview(self.mentionButton)
        self.scrollView.addSubview(self.suggestionStack)
        self.scrollView.addSubview(self.pollButton)
        self.scrollView.addSubview(self.addOptionButton)
        self.scrollView.addSubview(self.videoButton)
        self.scrollView.addSubview(self.videoRemoveButton)
        self.scrollView.addSubview(self.videoHintLabel)
        self.scrollView.addSubview(self.videoStatusLabel)
        self.scrollView.addSubview(self.videoPreviewView)
        self.scrollView.addSubview(self.imageButton)
        self.scrollView.addSubview(self.visibilityButton)
        self.scrollView.addSubview(self.hintLabel)
        if self.quoteOf == nil {
            self.ensureOptionFields(2)
        }
        self.reloadPeople()
        self.apply()
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        guard self.isNodeLoaded else {
            return
        }
        let navigationHeight = self.navigationLayout(layout: layout).navigationFrame.maxY
        self.scrollView.frame = CGRect(x: 0, y: navigationHeight, width: layout.size.width, height: max(1, layout.size.height - navigationHeight))
        let side: CGFloat = 16.0
        let width = max(1, layout.size.width - side * 2.0)
        var cursor: CGFloat = 8.0
        if self.quoteOf != nil {
            self.quoteLabel.frame = CGRect(x: side, y: cursor, width: width, height: 52)
            cursor = self.quoteLabel.frame.maxY + 8.0
        } else {
            self.quoteLabel.frame = .zero
        }
        self.textView.frame = CGRect(x: side, y: cursor, width: width, height: 120)
        self.placeholderLabel.frame = CGRect(x: side + 5, y: cursor + 8, width: width - 10, height: 44)
        cursor = self.textView.frame.maxY + 8.0
        if self.linkCard.isHidden {
            self.linkCard.frame = .zero
        } else {
            let cardHeight = self.linkCard.sizeThatFits(CGSize(width: width, height: 200)).height
            self.linkCard.frame = CGRect(x: side, y: cursor, width: width, height: cardHeight)
            cursor = self.linkCard.frame.maxY + 8.0
        }
        self.mentionButton.frame = CGRect(x: side, y: cursor, width: width, height: 36)
        cursor = self.mentionButton.frame.maxY + 2.0
        if self.suggestionStack.isHidden {
            self.suggestionStack.frame = .zero
        } else {
            let suggestionHeight = self.suggestionStack.systemLayoutSizeFitting(CGSize(width: width, height: 0), withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height
            let rows = CGFloat(max(self.suggestionStack.arrangedSubviews.count, 1)) * 36.0
            let height = max(suggestionHeight, rows)
            self.suggestionStack.frame = CGRect(x: side, y: cursor, width: width, height: height)
            cursor = self.suggestionStack.frame.maxY + 4.0
        }
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
        self.videoRemoveButton.sizeToFit()
        let removeWidth = self.videoRemoveButton.isHidden ? 0 : max(44, self.videoRemoveButton.bounds.width + 8)
        let videoGap: CGFloat = removeWidth > 0 ? 8 : 0
        self.videoButton.frame = CGRect(x: side, y: cursor, width: max(1, width - removeWidth - videoGap), height: 36)
        self.videoRemoveButton.frame = CGRect(x: side + width - removeWidth, y: cursor, width: removeWidth, height: 36)
        cursor = self.videoButton.frame.maxY + 2.0
        self.videoHintLabel.preferredMaxLayoutWidth = width
        self.videoStatusLabel.preferredMaxLayoutWidth = width
        let hintSize = self.videoHintLabel.sizeThatFits(CGSize(width: width, height: 80))
        self.videoHintLabel.frame = CGRect(x: side, y: cursor, width: width, height: max(18, hintSize.height))
        cursor = self.videoHintLabel.frame.maxY + 4.0
        if self.videoStatusLabel.isHidden {
            self.videoStatusLabel.frame = .zero
        } else {
            let statusSize = self.videoStatusLabel.sizeThatFits(CGSize(width: width, height: 160))
            self.videoStatusLabel.frame = CGRect(x: side, y: cursor, width: width, height: max(18, statusSize.height))
            cursor = self.videoStatusLabel.frame.maxY + 8.0
        }
        let imageSize = self.videoPreview?.size ?? .zero
        if self.videoURL != nil, imageSize.width > 1, imageSize.height > 1 {
            let previewWidth = min(width, 200)
            let previewHeight = min(200, max(48, previewWidth * imageSize.height / imageSize.width))
            self.videoPreviewView.isHidden = false
            self.videoPreviewView.image = self.videoPreview
            self.videoPreviewView.frame = CGRect(x: side, y: cursor, width: previewWidth, height: previewHeight)
            cursor = self.videoPreviewView.frame.maxY + 8.0
        } else {
            self.videoPreviewView.isHidden = true
            self.videoPreviewView.image = nil
            self.videoPreviewView.frame = .zero
        }
        self.imageButton.isHidden = !self.imagesEnabled
        if self.imageButton.isHidden {
            self.imageButton.frame = .zero
        } else {
            self.imageButton.frame = CGRect(x: side, y: cursor, width: width, height: 36)
            cursor = self.imageButton.frame.maxY + 4.0
        }
        for row in self.imageRows {
            row.isHidden = !self.imagesEnabled
            if row.isHidden {
                row.frame = .zero
            } else {
                row.frame = CGRect(x: side, y: cursor, width: width, height: 64.0)
                cursor = row.frame.maxY + 8.0
            }
        }
        self.visibilityButton.frame = CGRect(x: side, y: cursor, width: width, height: 36)
        self.hintLabel.frame = CGRect(x: side, y: self.visibilityButton.frame.maxY + 4, width: width, height: 40)
        let bottom = max(layout.intrinsicInsets.bottom, layout.safeInsets.bottom) + 16.0
        self.scrollView.contentSize = CGSize(width: layout.size.width, height: self.hintLabel.frame.maxY + bottom)
    }

    func textViewDidChange(_ textView: UITextView) {
        let _ = textView
        if self.editingMention || self.paintingMentions {
            return
        }
        self.refreshCompose()
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        let _ = textView
        if self.editingMention || self.paintingMentions {
            return
        }
        self.showSuggestions()
        self.relayout()
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
        if case .blocked = self.imagePublish.posting {
            return
        }
        switch TellomiDiscoverVideo.publishGate(hasVideo: self.videoURL != nil, busy: self.videoBusy, durationMs: self.videoDurationMs) {
        case .wait:
            return
        case .hold:
            self.recheckAttachedVideo()
            return
        case .sendText:
            break
        }
        let text = self.textView.text ?? ""
        guard TellomiDiscoverMention.invalid(text).isEmpty else {
            return
        }
        let options = self.pollOptions()
        if self.pollOn, options == nil {
            return
        }
        if let url = TellomiDiscoverLink.firstUrl(text), TellomiDiscoverLink.fetchable(url), url != self.linkURL || !self.linkSettled {
            if let cached = TellomiDiscoverLinkClient.peek(url) {
                self.linkURL = url
                self.linkPreview = cached
                self.linkSettled = true
            } else {
                self.linkHolding = true
                self.apply()
                self.requestLink(url, immediate: true)
                return
            }
        }
        self.linkHolding = false
        let preview = (TellomiDiscoverLink.firstUrl(text) == self.linkURL && self.linkSettled) ? self.linkPreview : nil
        let readyKeys: [String]?
        switch self.imagePublish.posting {
        case let .ready(keys):
            readyKeys = keys
        case .textOnly, .blocked:
            readyKeys = nil
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty, readyKeys == nil {
            return
        }
        if text.count > self.textLimit {
            return
        }
        self.sending = true
        self.sendError = nil
        self.apply()
        let request = TellomiDiscoverComposeRequest(text: text, visibility: choice.visibility, userIds: choice.userIds, nonce: self.nonce, quoteOf: self.quoteOf, pollOptions: self.pollOn ? options : nil, linkPreview: preview, mediaKeys: readyKeys)
        self.publish(request) { [weak self] result in
            guard let self else {
                return
            }
            self.sending = false
            switch result {
            case let .success(decoded):
                if case let .created(created) = decoded, created.state != "ok" {
                    let datas = self.imagePublish.items.compactMap { self.imageBytes[$0.localId] }
                    self.previews?.keep(postId: created.id, images: datas)
                }
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
                self.scrollView.addSubview(field)
            }
        }
    }

    @objc private func optionChanged() {
        self.apply()
    }

    @objc private func videoPressed() {
        guard !self.videoBusy, !self.sending else {
            return
        }
        guard #available(iOS 14.0, *) else {
            self.dropVideo(decision: .unknown, revealStatus: true)
            return
        }
        let picker = TellomiDiscoverVideoPicker()
        picker.onBegin = { [weak self] in
            guard let self else {
                return
            }
            self.videoGeneration += 1
            self.pendingPickGeneration = self.videoGeneration
            self.videoBusy = true
            self.videoDecision = .none
            self.applyVideoChrome()
        }
        picker.onPick = { [weak self] url in
            guard let self, self.pendingPickGeneration == self.videoGeneration else {
                TellomiDiscoverLocalVideo.discard(url)
                return
            }
            self.adoptPickedFile(url)
        }
        picker.onUnreadable = { [weak self] in
            guard let self, self.pendingPickGeneration == self.videoGeneration else {
                return
            }
            self.dropVideo(decision: .unknown, revealStatus: true)
        }
        self.videoPicker = picker
        picker.present(from: self)
    }

    @objc private func videoRemovePressed() {
        self.clearVideo()
    }

    private func adoptPickedFile(_ url: URL) {
        let previous = self.videoURL
        let generation = self.bumpVideoGeneration()
        self.videoBusy = true
        self.videoDecision = .none
        self.applyVideoChrome()
        TellomiDiscoverLocalVideo.milliseconds(at: url) { [weak self] duration in
            guard let self else {
                TellomiDiscoverLocalVideo.discard(url)
                return
            }
            guard generation == self.videoGeneration else {
                if self.videoURL != url {
                    TellomiDiscoverLocalVideo.discard(url)
                }
                return
            }
            self.videoBusy = false
            let decision = TellomiDiscoverVideo.select(durationMs: duration)
            if previous != url {
                TellomiDiscoverLocalVideo.discard(previous)
            }
            if decision == .accept {
                self.videoURL = url
                self.videoDurationMs = duration
                self.videoPreview = nil
                self.videoDecision = .accept
                self.applyVideoChrome(revealStatus: true)
                TellomiDiscoverLocalVideo.preview(at: url) { [weak self] image in
                    guard let self, generation == self.videoGeneration, self.videoURL == url else {
                        return
                    }
                    self.videoPreview = image
                    self.applyVideoChrome()
                }
            } else {
                TellomiDiscoverLocalVideo.discard(url)
                self.videoURL = nil
                self.videoDurationMs = 0
                self.videoPreview = nil
                self.videoDecision = decision
                self.applyVideoChrome(revealStatus: true)
            }
        }
    }

    /// Reads the length again, then refuses the file. A text post is not sent instead.
    private func recheckAttachedVideo() {
        guard let url = self.videoURL, !self.videoBusy, !self.sending else {
            return
        }
        let stored = self.videoDurationMs
        let generation = self.bumpVideoGeneration()
        self.videoBusy = true
        self.applyVideoChrome()
        TellomiDiscoverLocalVideo.milliseconds(at: url) { [weak self] fresh in
            guard let self, generation == self.videoGeneration else {
                return
            }
            self.videoBusy = false
            let duration = TellomiDiscoverVideo.measuredDuration(freshMs: fresh, storedMs: stored)
            let decision = TellomiDiscoverVideo.beforeUpload(durationMs: duration)
            switch decision {
            case .tooLong, .unknown:
                self.dropVideo(decision: decision, revealStatus: true)
            case .notUploaded, .accept, .none:
                if fresh > 0 {
                    self.videoDurationMs = fresh
                }
                self.videoDecision = .notUploaded
                self.applyVideoChrome(revealStatus: true)
            }
        }
    }

    private func clearVideo() {
        self.videoGeneration += 1
        TellomiDiscoverLocalVideo.discard(self.videoURL)
        self.videoURL = nil
        self.videoDurationMs = 0
        self.videoPreview = nil
        self.videoBusy = false
        self.videoDecision = .none
        self.applyVideoChrome()
    }

    private func dropVideo(decision: TellomiDiscoverVideo.Decision, revealStatus: Bool = true) {
        self.videoGeneration += 1
        TellomiDiscoverLocalVideo.discard(self.videoURL)
        self.videoURL = nil
        self.videoDurationMs = 0
        self.videoPreview = nil
        self.videoBusy = false
        self.videoDecision = decision
        self.applyVideoChrome(revealStatus: revealStatus)
    }

    private func bumpVideoGeneration() -> Int {
        self.videoGeneration += 1
        return self.videoGeneration
    }

    private func applyVideoChrome(revealStatus: Bool = false) {
        self.apply()
        self.relayout()
        if revealStatus, !self.videoStatusLabel.isHidden {
            self.scrollView.scrollRectToVisible(self.videoStatusLabel.frame.insetBy(dx: 0, dy: -8), animated: true)
        }
    }

    private func relayout() {
        guard self.isNodeLoaded, let layout = self.currentlyAppliedLayout else {
            return
        }
        self.containerLayoutUpdated(layout, transition: .immediate)
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
        let videoEnabled = !self.videoBusy && !self.sending
        let imageTitles = self.imageTitles()
        self.imageButton.setTitle(imageTitles.add, for: .normal)
        self.imageButton.setTitleColor(self.presentationData.theme.list.itemAccentColor, for: .normal)
        self.imageButton.isEnabled = self.imagesEnabled && !self.sending && self.imagePublish.items.count < TellomiDiscoverImageContract.maxCount
        self.syncImageRows(titles: imageTitles)
        self.videoButton.setTitle(self.videoURL == nil ? copy.videoAdd : copy.videoReplace, for: .normal)
        self.videoButton.setTitleColor(self.presentationData.theme.list.itemAccentColor, for: .normal)
        self.videoButton.isEnabled = videoEnabled
        self.videoRemoveButton.setTitle(copy.videoRemove, for: .normal)
        self.videoRemoveButton.setTitleColor(self.presentationData.theme.list.itemDestructiveColor, for: .normal)
        self.videoRemoveButton.isHidden = self.videoURL == nil
        self.videoRemoveButton.isEnabled = videoEnabled
        self.videoHintLabel.text = copy.videoHint
        self.videoHintLabel.textColor = self.presentationData.theme.list.itemSecondaryTextColor
        if let status = TellomiDiscoverVideo.statusText(busy: self.videoBusy, decision: self.videoDecision, hasVideo: self.videoURL != nil, durationMs: self.videoDurationMs, copy: copy) {
            self.videoStatusLabel.isHidden = false
            self.videoStatusLabel.text = status.text
            self.videoStatusLabel.textColor = status.isError ? self.presentationData.theme.list.itemDestructiveColor : self.presentationData.theme.list.itemSecondaryTextColor
        } else {
            self.videoStatusLabel.isHidden = true
            self.videoStatusLabel.text = nil
        }
        let index = 1
        for (offset, field) in self.optionFields.enumerated() {
            field.placeholder = copy.pollOption + " \(offset + index)"
            field.textColor = self.presentationData.theme.list.itemPrimaryTextColor
        }
        if self.quoteOf != nil {
            self.quoteLabel.text = self.quotePreview.isEmpty ? copy.quote : self.quotePreview
        }
        self.quoteLabel.textColor = self.presentationData.theme.list.itemSecondaryTextColor
        let text = self.textView.text ?? ""
        let invalid = TellomiDiscoverMention.invalid(text)
        let mentionText = invalid.first.map { TellomiDiscoverMention.invalidLine(template: copy.mentionInvalid, username: $0) }
        let errorText = self.sendError.flatMap { copy.failureText($0) }
        if let errorText {
            self.hintLabel.text = errorText
        } else if let imageNotice = self.imageNotice {
            self.hintLabel.text = imageNotice
        } else if let mentionText {
            self.hintLabel.text = mentionText
        } else if self.pollOn, self.pollOptions() == nil {
            self.hintLabel.text = copy.pollHint
        } else {
            self.hintLabel.text = copy.reasonText(choice?.reason)
        }
        self.hintLabel.textColor = (mentionText != nil || self.imageNotice != nil) && errorText == nil ? self.presentationData.theme.list.itemDestructiveColor : self.presentationData.theme.list.itemSecondaryTextColor
        self.hintLabel.font = Font.regular(13.0)
        self.placeholderLabel.text = copy.mentionHint
        self.placeholderLabel.textColor = self.presentationData.theme.list.itemSecondaryTextColor
        self.placeholderLabel.isHidden = !text.isEmpty
        self.mentionButton.setTitle(copy.mention, for: .normal)
        self.mentionButton.setTitleColor(self.presentationData.theme.list.itemAccentColor, for: .normal)
        self.linkCard.apply(primary: self.presentationData.theme.list.itemPrimaryTextColor, secondary: self.presentationData.theme.list.itemSecondaryTextColor, accent: self.presentationData.theme.list.itemAccentColor, background: self.presentationData.theme.list.itemHighlightedBackgroundColor)
        self.displayNode.backgroundColor = self.presentationData.theme.list.plainBackgroundColor
        self.textView.typingAttributes = [
            NSAttributedString.Key.font: Font.regular(17.0),
            NSAttributedString.Key.foregroundColor: self.presentationData.theme.list.itemPrimaryTextColor
        ]
        self.paintMentions()
        let pollReady = !self.pollOn || self.pollOptions() != nil
        let readyKeys: [String]?
        switch self.imagePublish.posting {
        case let .ready(keys):
            readyKeys = keys
        case .textOnly, .blocked:
            readyKeys = nil
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let textReady = text.count <= self.textLimit && (!trimmed.isEmpty || readyKeys != nil)
        let canSend = self.imagePublish.posting != .blocked && !self.sending && !self.videoBusy && !self.linkHolding && invalid.isEmpty && choice?.publishable == true && pollReady && textReady && tellomiDiscoverClientNonce(self.nonce)
        let item = UIBarButtonItem(title: copy.publish, style: .done, target: self, action: #selector(self.sendPressed))
        item.isEnabled = canSend
        self.navigationItem.setRightBarButton(item, animated: false)
    }

    private func refreshCompose() {
        self.showSuggestions()
        self.refreshLink()
        self.apply()
        self.relayout()
    }

    private func paintMentions() {
        guard self.isNodeLoaded, !self.paintingMentions, self.textView.markedTextRange == nil else {
            return
        }
        self.paintingMentions = true
        defer { self.paintingMentions = false }
        let storage = self.textView.textStorage
        let selected = self.textView.selectedRange
        let full = NSRange(location: 0, length: storage.length)
        guard full.length > 0 else {
            return
        }
        let primary = self.presentationData.theme.list.itemPrimaryTextColor
        let accent = self.presentationData.theme.list.itemAccentColor
        storage.beginEditing()
        storage.addAttribute(.font, value: Font.regular(17.0), range: full)
        storage.addAttribute(.foregroundColor, value: primary, range: full)
        let text = self.textView.text ?? ""
        for mention in TellomiDiscoverMention.parse(text) {
            let range = NSRange(location: mention.start, length: mention.end - mention.start)
            if range.location >= 0, NSMaxRange(range) <= storage.length {
                storage.addAttribute(.foregroundColor, value: accent, range: range)
            }
        }
        storage.endEditing()
        if selected.location <= storage.length {
            self.textView.selectedRange = selected
        }
    }

    @objc private func mentionPressed() {
        self.textView.becomeFirstResponder()
        let text = self.textView.text ?? ""
        var start = self.textView.selectedRange.location
        var end = self.textView.selectedRange.location + self.textView.selectedRange.length
        let length = (text as NSString).length
        if start > length {
            start = length
        }
        if end > length || end < start {
            end = start
        }
        if start == end, TellomiDiscoverMention.queryAt(text, caret: end) != nil {
            self.showSuggestions(force: true)
            return
        }
        let ns = text as NSString
        let updated = ns.replacingCharacters(in: NSRange(location: start, length: end - start), with: "@")
        self.editingMention = true
        self.textView.text = updated
        let caret = min(start + 1, (updated as NSString).length)
        self.textView.selectedRange = NSRange(location: caret, length: 0)
        self.editingMention = false
        self.refreshCompose()
    }

    private func showSuggestions(force: Bool = false) {
        guard self.isNodeLoaded else {
            return
        }
        let text = self.textView.text ?? ""
        let caret = self.textView.selectedRange.location
        let query = TellomiDiscoverMention.queryAt(text, caret: caret)
        if !force, query == self.activeQuery, !self.suggestionStack.isHidden || query == nil {
            return
        }
        self.activeQuery = query
        for view in self.suggestionStack.arrangedSubviews {
            self.suggestionStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        guard let query else {
            self.suggestionStack.isHidden = true
            return
        }
        let copy = TellomiDiscoverCopy.resolve(languageCode: self.presentationData.strings.primaryComponent.languageCode, pack: tellomiStringPack(primary: self.presentationData.strings.primaryComponent.dict, secondary: self.presentationData.strings.secondaryComponent?.dict))
        let people = TellomiDiscoverMention.suggestions(self.people, prefix: query.prefix, limit: TellomiDiscoverMention.suggestionLimit)
        if people.isEmpty {
            self.suggestionStack.addArrangedSubview(self.suggestionRow(copy.mentionEmpty, username: nil))
        } else {
            for person in people {
                let label = person.name.isEmpty ? "@" + person.username : "@" + person.username + "  " + person.name
                self.suggestionStack.addArrangedSubview(self.suggestionRow(label, username: person.username))
            }
        }
        self.suggestionStack.isHidden = false
    }

    private func suggestionRow(_ title: String, username: String?) -> UIButton {
        let button = TellomiDiscoverMentionRowButton(type: .system)
        button.contentHorizontalAlignment = .left
        button.titleLabel?.font = Font.regular(16.0)
        button.setTitle(title, for: .normal)
        let color = username == nil ? self.presentationData.theme.list.itemSecondaryTextColor : self.presentationData.theme.list.itemPrimaryTextColor
        button.setTitleColor(color, for: .normal)
        button.isEnabled = username != nil
        button.username = username
        if username != nil {
            button.accessibilityIdentifier = "tellomi.discover.mention.row"
            button.addTarget(self, action: #selector(self.suggestionPressed(_:)), for: .touchUpInside)
        }
        return button
    }

    @objc private func suggestionPressed(_ sender: UIButton) {
        guard let username = (sender as? TellomiDiscoverMentionRowButton)?.username else {
            return
        }
        self.applyInsertion(username)
    }

    private func applyInsertion(_ username: String) {
        guard let query = self.activeQuery else {
            return
        }
        let text = self.textView.text ?? ""
        guard let insertion = TellomiDiscoverMention.insert(text, query: query, username: username) else {
            return
        }
        self.editingMention = true
        self.textView.text = insertion.text
        let length = (insertion.text as NSString).length
        let caret = min(max(insertion.caret, 0), length)
        self.textView.selectedRange = NSRange(location: caret, length: 0)
        self.editingMention = false
        self.refreshCompose()
    }

    private func reloadPeople() {
        let selfId = self.context.account.peerId
        self.peopleDisposable?.dispose()
        self.peopleDisposable = (self.context.engine.contacts.peersFromContactsAndChatList()
        |> deliverOnMainQueue).start(next: { [weak self] peers in
            guard let self else {
                return
            }
            var people: [TellomiDiscoverMention.Person] = []
            for peer in peers {
                let firstName: String?
                let lastName: String?
                let isUser: Bool
                if case let .user(user) = peer {
                    firstName = user.firstName
                    lastName = user.lastName
                    isUser = true
                } else {
                    firstName = nil
                    lastName = nil
                    isUser = false
                }
                if let person = TellomiDiscoverMention.mentionPerson(
                    username: peer.addressName,
                    firstName: firstName,
                    lastName: lastName,
                    isUser: isUser,
                    isDeleted: peer.isDeleted,
                    isSelf: peer.id == selfId
                ) {
                    people.append(person)
                }
            }
            self.people = people
            self.showSuggestions(force: true)
            self.relayout()
        })
    }

    private func refreshLink() {
        guard self.isNodeLoaded else {
            return
        }
        let url = TellomiDiscoverLink.firstUrl(self.textView.text ?? "")
        guard let url, TellomiDiscoverLink.fetchable(url) else {
            self.linkGeneration += 1
            self.linkWork?.cancel()
            self.linkURL = nil
            self.linkPreview = nil
            self.linkSettled = false
            self.linkHolding = false
            self.linkCard.hide()
            return
        }
        if url == self.linkURL {
            if self.linkSettled, let preview = self.linkPreview {
                self.linkCard.show(preview, opens: false)
            }
            return
        }
        if let cached = TellomiDiscoverLinkClient.peek(url) {
            self.linkURL = url
            self.linkPreview = cached
            self.linkSettled = true
            self.linkCard.show(cached, opens: false)
            return
        }
        self.linkURL = url
        self.linkPreview = nil
        self.linkSettled = false
        let copy = TellomiDiscoverCopy.resolve(languageCode: self.presentationData.strings.primaryComponent.languageCode, pack: tellomiStringPack(primary: self.presentationData.strings.primaryComponent.dict, secondary: self.presentationData.strings.secondaryComponent?.dict))
        self.linkCard.showLoading(copy.linkPreviewLoading)
        self.requestLink(url, immediate: false)
    }

    private func requestLink(_ url: String, immediate: Bool) {
        self.linkWork?.cancel()
        let generation = self.linkGeneration
        let work = DispatchWorkItem { [weak self] in
            TellomiDiscoverLinkClient.load(url) { preview in
                guard let self, generation == self.linkGeneration, self.linkURL == url else {
                    return
                }
                self.linkSettled = true
                self.linkPreview = preview
                if let preview {
                    self.linkCard.show(preview, opens: false)
                } else {
                    self.linkCard.hide()
                }
                let resume = self.linkHolding
                self.linkHolding = false
                self.apply()
                self.relayout()
                if resume {
                    self.sendPressed()
                }
            }
        }
        self.linkWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (immediate ? 0 : 0.45), execute: work)
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

    private var imagesEnabled: Bool {
        return self.mediaUpload && self.feedConfiguration?.enabled == true && self.feedConfiguration?.baseURL != nil && self.loader != nil
    }

    private func imageTitles() -> (add: String, cancel: String, retry: String, failed: String, rejected: String, progress: String, uploaded: String) {
        let code = self.presentationData.strings.primaryComponent.languageCode
        if code.hasPrefix("zh") {
            return ("添加图片", "取消", "重试", "上传失败", "这张图不能上传", "上传中", "已上传")
        }
        return ("Add photos", "Cancel", "Retry", "Upload failed", "This photo can't be uploaded", "Uploading", "Uploaded")
    }

    @objc private func imagePressed() {
        guard self.imagesEnabled, !self.sending else {
            return
        }
        guard #available(iOS 14.0, *) else {
            return
        }
        let remaining = TellomiDiscoverImageContract.maxCount - self.imagePublish.items.count
        guard remaining > 0 else {
            return
        }
        let picker = TellomiDiscoverPhotoPicker()
        picker.onData = { [weak self] datas in
            self?.acceptImages(datas)
        }
        self.photoPicker = picker
        picker.present(from: self, limit: remaining)
    }

    private func acceptImages(_ datas: [Data]) {
        let titles = self.imageTitles()
        var rejected = false
        for data in datas {
            guard self.imagePublish.items.count < TellomiDiscoverImageContract.maxCount else {
                break
            }
            guard let prepared = TellomiDiscoverImageEncode.prepared(data) else {
                rejected = true
                continue
            }
            let localId = UUID().uuidString
            guard self.imagePublish.select(localId: localId, byteCount: prepared.bytes.count) == nil else {
                rejected = true
                continue
            }
            guard self.imagePublish.beginUpload(localId: localId) == nil else {
                _ = self.imagePublish.cancel(localId: localId)
                continue
            }
            self.imageBytes[localId] = prepared.bytes
            self.imagePictures[localId] = UIImage(data: prepared.bytes)
            self.imageSessions[localId] = TellomiDiscoverImageUploadSession(length: prepared.bytes.count)
        }
        self.imageNotice = rejected ? titles.rejected : nil
        self.syncImageRows(titles: titles)
        self.apply()
        self.relayout()
        self.pumpImages()
    }

    private func syncImageRows(titles: (add: String, cancel: String, retry: String, failed: String, rejected: String, progress: String, uploaded: String)) {
        guard self.isNodeLoaded else {
            return
        }
        while self.imageRows.count < self.imagePublish.items.count {
            let row = TellomiDiscoverImageRow()
            self.imageRows.append(row)
            self.scrollView.addSubview(row)
        }
        while self.imageRows.count > self.imagePublish.items.count {
            self.imageRows.removeLast().removeFromSuperview()
        }
        let color = self.presentationData.theme.list.itemSecondaryTextColor
        let destructive = self.presentationData.theme.list.itemDestructiveColor
        for (row, item) in zip(self.imageRows, self.imagePublish.items) {
            let failed: Bool
            let text: String
            switch item.phase {
            case .failed:
                failed = true
                text = titles.failed
            case .uploaded:
                failed = false
                text = titles.uploaded
            case .selected, .uploading:
                failed = false
                text = "\(titles.progress) \(item.sent)/\(item.byteCount)"
            }
            let localId = item.localId
            row.onCancel = { [weak self] in
                self?.cancelImage(localId)
            }
            row.onRetry = { [weak self] in
                self?.retryImage(localId)
            }
            row.apply(image: self.imagePictures[item.localId], text: text, failed: failed, cancelTitle: titles.cancel, retryTitle: titles.retry, color: color, destructive: destructive)
        }
    }

    private func pumpImages() {
        guard self.imageFlight == nil else {
            return
        }
        guard let item = self.imagePublish.items.first(where: { item in
            switch item.phase {
            case .uploaded, .failed:
                return false
            case .selected, .uploading:
                return self.imageSessions[item.localId] != nil
            }
        }) else {
            return
        }
        self.imageFlight = item.localId
        self.advanceImage(item.localId)
    }

    private func advanceImage(_ localId: String) {
        guard var session = self.imageSessions[localId], let bytes = self.imageBytes[localId], let configuration = self.feedConfiguration, let base = configuration.baseURL, let loader = self.loader else {
            self.imageFlight = nil
            return
        }
        if case let .wait(seconds) = session.step {
            self.imageSessions[localId] = session
            self.imageGeneration[localId, default: 0] += 1
            let generation = self.imageGeneration[localId] ?? 0
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(max(1, seconds))) { [weak self] in
                guard let self, self.imageGeneration[localId] == generation else {
                    return
                }
                self.imageSessions[localId]?.waited()
                self.advanceImage(localId)
            }
            return
        }
        guard let call = session.call(base: base, bytes: bytes) else {
            self.imageSessions[localId] = session
            self.finishImage(localId)
            return
        }
        self.imageSessions[localId] = session
        _ = self.imagePublish.noteSent(localId: localId, sent: session.offset)
        self.imageGeneration[localId, default: 0] += 1
        let generation = self.imageGeneration[localId] ?? 0
        loader.performImage(loggedIn: true, configuration: configuration, call: call) { [weak self] result in
            guard let self, self.imageGeneration[localId] == generation else {
                return
            }
            var session = self.imageSessions[localId] ?? session
            switch result {
            case .failure:
                session.transportFailed()
            case let .success(response):
                session.receive(response, base: base)
            }
            self.imageSessions[localId] = session
            _ = self.imagePublish.noteSent(localId: localId, sent: session.offset)
            self.syncImageRows(titles: self.imageTitles())
            self.relayout()
            self.advanceImage(localId)
        }
    }

    private func finishImage(_ localId: String) {
        let session = self.imageSessions[localId]
        switch session?.step {
        case let .done(key):
            _ = self.imagePublish.complete(localId: localId, key: key)
        case .cancelled:
            _ = self.imagePublish.cancel(localId: localId)
            self.imageBytes[localId] = nil
            self.imagePictures[localId] = nil
            self.imageSessions[localId] = nil
        case .voided, .failed:
            _ = self.imagePublish.fail(localId: localId)
        default:
            _ = self.imagePublish.fail(localId: localId)
        }
        if self.imageFlight == localId {
            self.imageFlight = nil
        }
        self.syncImageRows(titles: self.imageTitles())
        self.apply()
        self.relayout()
        self.pumpImages()
    }

    private func cancelImage(_ localId: String) {
        guard var session = self.imageSessions[localId] else {
            _ = self.imagePublish.cancel(localId: localId)
            self.imageBytes[localId] = nil
            self.imagePictures[localId] = nil
            self.syncImageRows(titles: self.imageTitles())
            self.apply()
            self.relayout()
            return
        }
        session.cancel()
        self.imageSessions[localId] = session
        self.imageGeneration[localId, default: 0] += 1
        if session.step == .cancelled {
            if self.imageFlight == localId {
                self.imageFlight = nil
            }
            self.finishImage(localId)
            return
        }
        if self.imageFlight == nil || self.imageFlight == localId {
            self.imageFlight = localId
            self.advanceImage(localId)
        }
    }

    private func retryImage(_ localId: String) {
        guard var session = self.imageSessions[localId] else {
            return
        }
        session.retry()
        self.imageSessions[localId] = session
        _ = self.imagePublish.retry(localId: localId)
        self.syncImageRows(titles: self.imageTitles())
        if self.imageFlight == nil {
            self.imageFlight = localId
            self.advanceImage(localId)
        }
        self.apply()
    }
}

private final class TellomiDiscoverMentionRowButton: UIButton {
    var username: String?
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
