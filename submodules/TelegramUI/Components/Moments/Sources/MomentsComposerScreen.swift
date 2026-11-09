import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import AccountContext
import MediaPickerUI
import LegacyMediaPickerUI
import ShareWithPeersScreen
import PresentationDataUtils

public final class MomentsComposerScreen: ViewController {
    private let context: AccountContext
    private let quoteId: String?
    private var presentationData: PresentationData
    private let textView = UITextView()
    private let audienceButton = UIButton(type: .system)
    private let publishButton = UIButton(type: .system)
    private let nearbySwitch = UISwitch()
    private var privacy = EngineStoryPrivacy(base: .everyone, additionallyIncludePeers: [])
    private var didLoadPrivacy = false
    private var media: [MomentsMedia] = []
    private var allowNearby = false
    private var linkRemoved = false
    private var imageCount = 0
    private var videoCount = 0
    private var hasVoice = false
    private var hasPoll = false
    private var limits = MomentsLimits.standard
    private var audioRecorder: ManagedAudioRecorder?
    private var voiceDisposable: Disposable?
    private var voiceStateDisposable: Disposable?
    private var isRecordingVoice = false
    private var isFinishingVoice = false

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

    deinit {
        self.voiceDisposable?.dispose()
        self.voiceStateDisposable?.dispose()
        self.audioRecorder?.stop()
    }

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
        let voice = UIButton(type: .system)
        voice.tag = 42
        voice.setTitle(momentsText(self.presentationData.strings, .voice), for: .normal)
        voice.addTarget(self, action: #selector(self.voicePressed), for: .touchUpInside)
        voice.accessibilityLabel = momentsText(self.presentationData.strings, .voice)
        self.displayNode.view.addSubview(voice)
        self.refresh()
        let _ = (self.context.engine.moments.remoteConfig() |> deliverOnMainQueue).start(next: { [weak self] config in
            self?.limits = MomentsLimits.standard.applying(config: config)
            self?.refresh()
        })
        let _ = (self.context.engine.moments.storedDraft() |> deliverOnMainQueue).start(next: { [weak self] draft in
            guard let self, let draft else { return }
            self.textView.text = draft.text
            self.allowNearby = draft.allowNearby
            self.media = draft.media
            self.imageCount = draft.media.filter { $0.type == .image }.count
            self.videoCount = draft.media.filter { $0.type == .video }.count
            if let base = EngineStoryPrivacy.Base(rawValue: draft.privacyBase) {
                let peers = draft.peerIds.map { EnginePeer.Id(namespace: Namespaces.Peer.CloudUser, id: EnginePeer.Id.Id._internalFromInt64Value($0)) }
                self.privacy = EngineStoryPrivacy(base: base, additionallyIncludePeers: peers)
                self.didLoadPrivacy = true
            }
            self.refresh()
        })
        let _ = (self.context.engine.moments.storedAudience() |> deliverOnMainQueue).start(next: { [weak self] stored in
            guard let self, !self.didLoadPrivacy else { return }
            self.didLoadPrivacy = true
            if let stored {
                self.privacy = stored
                self.refresh()
            }
        })
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
        if let voice = self.displayNode.view.viewWithTag(42) {
            voice.frame = CGRect(x: 144, y: top + 236, width: 120, height: 36)
        }
    }

    private func refresh() {
        let strings = self.presentationData.strings
        let audience = momentsAudience(from: self.privacy)
        self.audienceButton.setTitle(momentsAudienceTitle(strings, audience.kind), for: .normal)
        let state = MomentsComposerAttachmentState(imageCount: self.imageCount, videoCount: self.videoCount, hasVoice: self.hasVoice, hasPoll: self.hasPoll, hasLinkPreview: !self.linkRemoved && momentsScanText(self.textView.text ?? "").firstURL != nil)
        let hasBody = !(self.textView.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !state.isEmpty || !self.media.isEmpty
        self.navigationItem.rightBarButtonItem?.isEnabled = hasBody && !self.isRecordingVoice
        self.publishButton.isEnabled = hasBody && !self.isRecordingVoice
        self.nearbySwitch.isHidden = audience.kind != .everyone
        self.nearbySwitch.isOn = self.allowNearby
    }

    @objc private func chooseAudience() {
        let privacy = self.privacy
        let stateContext = ShareWithPeersScreen.StateContext(
            context: self.context,
            subject: .stories(editing: false, count: 1),
            momentsAudience: true,
            initialSelectedPeers: [privacy.base: privacy.additionallyIncludePeers],
            closeFriends: self.context.engine.data.get(TelegramEngine.EngineData.Item.Contacts.CloseFriends())
        )
        let _ = (stateContext.ready |> filter { $0 } |> take(1) |> deliverOnMainQueue).start(next: { [weak self] _ in
            guard let self else { return }
            let controller = ShareWithPeersScreen(
                context: self.context,
                initialPrivacy: privacy,
                stateContext: stateContext,
                completion: { [weak self] _, result, _, _, _, _, completed in
                    guard let self, completed else { return }
                    self.privacy = result
                    if result.base != .everyone {
                        self.allowNearby = false
                    }
                    self.context.engine.moments.storeAudience(result)
                    self.refresh()
                }
            )
            (self.navigationController as? NavigationController)?.pushViewController(controller)
        })
    }

    @objc private func pickImages() {
        let state = MomentsComposerAttachmentState(imageCount: self.imageCount, videoCount: self.videoCount, hasVoice: self.hasVoice, hasPoll: self.hasPoll)
        if let rejection = momentsCanAdd(kind: .image, to: state, limits: self.limits) {
            self.presentRejection(rejection)
            return
        }
        let picker = MediaPickerScreenImpl(context: self.context, peer: nil, threadTitle: nil, chatLocation: nil, bannedSendVideos: self.imageCount > 0 ? (Int32(0), true) : nil, selectionLimit: max(1, self.limits.imageLimit - self.imageCount), subject: .assets(nil, .default))
        picker.legacyCompletion = { [weak self] _, signals, _, _, _, _, done in
            guard let self else {
                done()
                return
            }
            let _ = (legacyAssetPickerEnqueueMessages(context: self.context, account: self.context.account, signals: signals)
            |> deliverOnMainQueue).start(next: { [weak self] messages in
                self?.uploadPicked(messages.map(\.message))
            })
            done()
        }
        self.push(picker)
    }

    private func uploadPicked(_ messages: [EnqueueMessage]) {
        let imageCountBefore = self.imageCount
        let videoCountBefore = self.videoCount
        var nextImages = imageCountBefore
        var nextVideos = videoCountBefore
        var files: [Signal<MomentsUploadFile, NoError>] = []
        for (index, message) in messages.enumerated() {
            guard case let .message(_, _, _, mediaReference, _, _, _, _, _, _) = message, let mediaReference else {
                continue
            }
            let media = mediaReference.media
            let resource: TelegramMediaResource
            let type: MomentsMediaType
            let width: Int
            let height: Int
            let durationMs: Int
            let filename: String
            let mime: String
            if let image = media as? TelegramMediaImage, let representation = image.representations.max(by: { $0.dimensions.width < $1.dimensions.width }) {
                resource = representation.resource
                type = .image
                width = Int(representation.dimensions.width)
                height = Int(representation.dimensions.height)
                durationMs = 0
                filename = "photo-\(index).jpg"
                mime = "image/jpeg"
            } else if let file = media as? TelegramMediaFile {
                resource = file.resource
                type = .video
                let dimensions = file.dimensions
                width = Int(dimensions?.width ?? 0)
                height = Int(dimensions?.height ?? 0)
                durationMs = Int((file.duration ?? 0) * 1000)
                filename = file.fileName ?? "video-\(index).mp4"
                mime = file.mimeType
                if Double(durationMs) / 1000.0 > self.limits.videoMaxDuration {
                    self.presentRejection(.videoTooLong)
                    return
                }
            } else {
                continue
            }
            if let rejection = momentsCanAdd(kind: type == .image ? .image : .video, to: MomentsComposerAttachmentState(imageCount: nextImages, videoCount: nextVideos, hasVoice: self.hasVoice, hasPoll: self.hasPoll), limits: self.limits) {
                self.presentRejection(rejection)
                return
            }
            if type == .image {
                nextImages += 1
            } else {
                nextVideos += 1
            }
            let order = self.media.count + files.count
            let resolved: Signal<String, NoError>
            if let local = resource as? LocalFileReferenceMediaResource, FileManager.default.fileExists(atPath: local.localFilePath) {
                resolved = .single(local.localFilePath)
            } else {
                resolved = self.context.engine.resources.data(id: EngineMediaResource(resource).id)
                |> filter { $0.isComplete && !$0.path.isEmpty }
                |> take(1)
                |> map { $0.path }
            }
            files.append(resolved |> map { path in
                MomentsUploadFile(path: path, filename: filename, mimeType: mime, type: type, width: width, height: height, durationMs: durationMs, order: order)
            })
        }
        guard !files.isEmpty else { return }
        self.imageCount = nextImages
        self.videoCount = nextVideos
        let _ = (combineLatest(files)
        |> castError(MomentsAPIError.self)
        |> mapToSignal { [weak self] files -> Signal<[MomentsMedia], MomentsAPIError> in
            guard let self else { return .complete() }
            return self.uploadSequentially(files)
        }
        |> deliverOnMainQueue).start(next: { [weak self] uploaded in
            guard let self else { return }
            self.media.append(contentsOf: uploaded)
            self.refresh()
        }, error: { [weak self] _ in
            self?.imageCount = imageCountBefore
            self?.videoCount = videoCountBefore
            self?.presentRejection(.imageLimit)
        })
    }

    private func uploadSequentially(_ files: [MomentsUploadFile]) -> Signal<[MomentsMedia], MomentsAPIError> {
        if files.isEmpty {
            return .single([])
        }
        let tail = Array(files.dropFirst())
        return self.context.engine.moments.uploadFile(files[0])
        |> mapToSignal { first in
            return self.uploadSequentially(tail)
            |> map { rest in
                return [first] + rest
            }
        }
    }

    @objc private func voicePressed() {
        if let recorder = self.audioRecorder {
            self.finishVoice(recorder)
            return
        }
        let state = MomentsComposerAttachmentState(imageCount: self.imageCount, videoCount: self.videoCount, hasVoice: self.hasVoice, hasPoll: self.hasPoll)
        if let rejection = momentsCanAdd(kind: .voice, to: state, limits: self.limits) {
            self.presentRejection(rejection)
            return
        }
        self.voiceDisposable?.dispose()
        self.voiceDisposable = (self.context.sharedContext.mediaManager.audioRecorder(
            resumeData: nil,
            beginWithTone: false,
            pauseMusicOnRecording: self.context.sharedContext.currentMediaInputSettings.with { $0.pauseMusicOnRecording },
            applicationBindings: self.context.sharedContext.applicationBindings,
            beganWithTone: { _ in }
        ) |> deliverOnMainQueue).start(next: { [weak self] recorder in
            guard let self, let recorder else {
                self?.presentVoiceFailure()
                return
            }
            self.audioRecorder = recorder
            self.isRecordingVoice = true
            self.refresh()
            (self.displayNode.view.viewWithTag(42) as? UIButton)?.setTitle(momentsText(self.presentationData.strings, .voiceStop), for: .normal)
            recorder.start()
            self.voiceStateDisposable?.dispose()
            self.voiceStateDisposable = (recorder.recordingState |> deliverOnMainQueue).start(next: { [weak self, weak recorder] state in
                guard let self, let recorder else { return }
                if case let .recording(duration, _) = state, duration >= self.limits.voiceMaxDuration {
                    self.finishVoice(recorder)
                }
            })
        })
    }

    private func finishVoice(_ recorder: ManagedAudioRecorder) {
        guard !self.isFinishingVoice else { return }
        self.isFinishingVoice = true
        self.isRecordingVoice = false
        self.audioRecorder = nil
        recorder.stop()
        (self.displayNode.view.viewWithTag(42) as? UIButton)?.setTitle(momentsText(self.presentationData.strings, .voice), for: .normal)
        self.refresh()
        self.voiceStateDisposable?.dispose()
        self.voiceStateDisposable = (recorder.takenRecordedData() |> deliverOnMainQueue).start(next: { [weak self] data in
            guard let self else { return }
            self.isFinishingVoice = false
            guard let data, data.duration >= 0.5, !data.compressedData.isEmpty else {
                self.presentVoiceFailure()
                return
            }
            let duration = min(data.duration, self.limits.voiceMaxDuration)
            let state = MomentsComposerAttachmentState(imageCount: self.imageCount, videoCount: self.videoCount, hasVoice: self.hasVoice, hasPoll: self.hasPoll)
            if let rejection = momentsCanAdd(kind: .voice, to: state, limits: self.limits, duration: duration) {
                self.presentRejection(rejection)
                return
            }
            self.uploadVoice(data.compressedData, duration: duration)
        })
    }

    private func uploadVoice(_ data: Data, duration: Double) {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("moments-voice-\(UUID().uuidString).ogg")
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            self.presentVoiceFailure()
            return
        }
        self.hasVoice = true
        self.refresh()
        let file = MomentsUploadFile(
            path: url.path,
            filename: "voice.ogg",
            mimeType: "audio/ogg",
            type: .audio,
            width: 0,
            height: 0,
            durationMs: Int(duration * 1000),
            order: self.media.count
        )
        let _ = (self.context.engine.moments.uploadFile(file) |> deliverOnMainQueue).start(next: { [weak self] media in
            guard let self else { return }
            self.media.append(media)
            self.refresh()
        }, error: { [weak self] _ in
            guard let self else { return }
            self.hasVoice = false
            self.refresh()
            self.presentVoiceFailure()
        })
    }

    private func presentVoiceFailure() {
        momentsPresentErrorToast(controller: self, presentationData: self.presentationData, text: momentsText(self.presentationData.strings, .voiceFailed))
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

    private func saveDraft() {
        let draft = MomentsComposerDraft(
            text: self.textView.text ?? "",
            privacyBase: self.privacy.base.rawValue,
            peerIds: self.privacy.additionallyIncludePeers.map { $0.toInt64() },
            allowNearby: self.allowNearby,
            quoteId: self.quoteId,
            media: self.media
        )
        self.context.engine.moments.storeDraft(draft)
    }

    @objc private func cancelPressed() {
        let dirty = !(self.textView.text ?? "").isEmpty || !self.media.isEmpty || self.privacy.base != .everyone || !self.privacy.additionallyIncludePeers.isEmpty
        guard dirty else {
            self.navigationController?.popViewController(animated: true)
            return
        }
        let strings = self.presentationData.strings
        self.present(textAlertController(context: self.context, title: momentsText(strings, .draftTitle), text: momentsText(strings, .friendsHint), actions: [
            TextAlertAction(type: .defaultAction, title: momentsText(strings, .draftSave), action: { [weak self] in
                self?.saveDraft()
                self?.navigationController?.popViewController(animated: true)
            }),
            TextAlertAction(type: .destructiveAction, title: momentsText(strings, .draftDiscard), action: { [weak self] in
                self?.context.engine.moments.storeDraft(nil)
                self?.navigationController?.popViewController(animated: true)
            }),
            TextAlertAction(type: .genericAction, title: momentsText(strings, .draftContinue), action: {})
        ], actionLayout: .vertical), in: .window(.root))
    }

    @objc private func publishPressed() {
        let audience = momentsAudience(from: self.privacy)
        let text = self.textView.text ?? ""
        let scan = momentsScanText(text)
        let send = { [weak self] in
            guard let self else { return }
            var audienceBody: [String: Any] = ["kind": audience.kind.rawValue]
            if !audience.exclude.isEmpty {
                audienceBody["exclude"] = audience.exclude
            }
            if !audience.include.isEmpty {
                audienceBody["include"] = audience.include
            }
            var body: [String: Any] = [
                "text": text,
                "audience": audienceBody,
                "comment_policy": MomentsCommentPolicy.everyoneWhoCanView.rawValue,
                "client_nonce": UUID().uuidString
            ]
            if !self.media.isEmpty {
                body["media"] = self.media.map { item in
                    [
                        "type": item.type.rawValue,
                        "key": item.key,
                        "w": item.width,
                        "h": item.height,
                        "duration_ms": item.durationMs,
                        "order": item.order
                    ]
                }
            }
            if self.allowNearby && audience.kind == .everyone {
                body["location"] = ["allow_nearby": true]
            }
            if let quoteId = self.quoteId {
                body["quote_of"] = quoteId
            }
            if let url = scan.firstURL, !self.linkRemoved, momentsShowsLinkPreview(MomentsComposerAttachmentState(imageCount: self.imageCount, videoCount: self.videoCount, hasPoll: self.hasPoll, hasLinkPreview: true)) {
                body["link_preview"] = ["url": url]
            }
            let _ = (self.context.engine.moments.publish(body) |> deliverOnMainQueue).start(next: { [weak self] _ in
                self?.context.engine.moments.storeDraft(nil)
                self?.navigationController?.popViewController(animated: true)
            }, error: { [weak self] _ in
                guard let self else { return }
                self.present(textAlertController(context: self.context, title: nil, text: momentsText(self.presentationData.strings, .failedRetry), actions: [TextAlertAction(type: .defaultAction, title: momentsText(self.presentationData.strings, .retry), action: { [weak self] in self?.publishPressed() })]), in: .window(.root))
            })
        }
        if !scan.mentions.isEmpty && audience.kind != .everyone {
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
        if textView.text.count > self.limits.textLimit {
            textView.text = String(textView.text.prefix(self.limits.textLimit))
        }
        self.refresh()
    }
}
