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
    private var audienceChosen = false
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
    /// One UUID for this draft. Retries send the same value; a new composer mints a new one.
    private let clientNonce = UUID().uuidString
    private var publishing = false
    private var audienceGrant: (kind: String, userIds: [Int64], grant: MomentsAudienceGrant)?

    public init(context: AccountContext, quoteId: String?) {
        self.context = context
        self.quoteId = quoteId
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }
        super.init(navigationBarPresentationData: NavigationBarPresentationData(presentationData: self.presentationData))
        self.title = self.presentationData.strings.Moments_Composer_Title
        self.navigationItem.setLeftBarButton(UIBarButtonItem(title: self.presentationData.strings.Common_Cancel, style: .plain, target: self, action: #selector(self.cancelPressed)), animated: false)
        self.navigationItem.setRightBarButton(UIBarButtonItem(title: self.presentationData.strings.Moments_Publish, style: .done, target: self, action: #selector(self.publishPressed)), animated: false)
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
        self.nearbySwitch.addTarget(self, action: #selector(self.nearbyChanged), for: .valueChanged)
        self.textView.font = Font.regular(self.presentationData.listsFontSize.baseDisplaySize)
        self.textView.backgroundColor = .clear
        self.textView.delegate = self
        self.audienceButton.addTarget(self, action: #selector(self.chooseAudience), for: .touchUpInside)
        self.publishButton.addTarget(self, action: #selector(self.publishPressed), for: .touchUpInside)
        let photos = UIButton(type: .system)
        photos.setTitle(self.presentationData.strings.Moments_Publish, for: .normal)
        photos.addTarget(self, action: #selector(self.pickImages), for: .touchUpInside)
        photos.accessibilityLabel = self.presentationData.strings.Moments_Publish
        self.displayNode.view.addSubview(photos)
        photos.tag = 41
        let voice = UIButton(type: .system)
        voice.tag = 42
        voice.setTitle(self.presentationData.strings.Moments_Voice, for: .normal)
        voice.addTarget(self, action: #selector(self.voicePressed), for: .touchUpInside)
        voice.accessibilityLabel = self.presentationData.strings.Moments_Voice
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
                self.audienceChosen = true
            }
            self.refresh()
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
        if self.audienceChosen {
            self.audienceButton.setTitle(momentsAudienceTitle(strings, audience.kind), for: .normal)
        } else {
            self.audienceButton.setTitle(strings.Moments_Audience_Choose, for: .normal)
        }
        let state = MomentsComposerAttachmentState(imageCount: self.imageCount, videoCount: self.videoCount, hasVoice: self.hasVoice, hasPoll: self.hasPoll, hasLinkPreview: !self.linkRemoved && momentsScanText(self.textView.text ?? "", limits: self.limits).firstURL != nil)
        let hasBody = !(self.textView.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !state.isEmpty || !self.media.isEmpty
        let canPublish = hasBody && !self.isRecordingVoice && self.audienceChosen && !self.publishing
        self.navigationItem.rightBarButtonItem?.isEnabled = canPublish
        self.publishButton.isEnabled = canPublish
        self.nearbySwitch.isHidden = !self.audienceChosen || audience.kind != .everyone
        self.nearbySwitch.isOn = self.allowNearby
    }

    @objc private func chooseAudience() {
        let privacy = self.audienceChosen ? self.privacy : EngineStoryPrivacy(base: .nobody, additionallyIncludePeers: [])
        let stateContext = ShareWithPeersScreen.StateContext(
            context: self.context,
            subject: .stories(editing: false, count: 1),
            momentsAudience: true,
            initialSelectedPeers: self.audienceChosen ? [self.privacy.base: self.privacy.additionallyIncludePeers] : [:],
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
                    self.audienceChosen = true
                    if result.base != .everyone {
                        self.allowNearby = false
                    }
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
        if let rejection = momentsCanAdd(kind: .voice, to: state, limits: self.limits, voiceComment: false) {
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
            (self.displayNode.view.viewWithTag(42) as? UIButton)?.setTitle(self.presentationData.strings.Moments_VoiceStop, for: .normal)
            recorder.start()
            self.voiceStateDisposable?.dispose()
            self.voiceStateDisposable = (recorder.recordingState |> deliverOnMainQueue).start(next: { [weak self, weak recorder] state in
                guard let self, let recorder else { return }
                if case let .recording(duration, _) = state, duration >= momentsVoiceMaxDuration(self.limits, comment: false) {
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
        (self.displayNode.view.viewWithTag(42) as? UIButton)?.setTitle(self.presentationData.strings.Moments_Voice, for: .normal)
        self.refresh()
        self.voiceStateDisposable?.dispose()
        self.voiceStateDisposable = (recorder.takenRecordedData() |> deliverOnMainQueue).start(next: { [weak self] data in
            guard let self else { return }
            self.isFinishingVoice = false
            guard let data, data.duration >= 0.5, !data.compressedData.isEmpty else {
                self.presentVoiceFailure()
                return
            }
            let duration = min(data.duration, momentsVoiceMaxDuration(self.limits, comment: false))
            let state = MomentsComposerAttachmentState(imageCount: self.imageCount, videoCount: self.videoCount, hasVoice: self.hasVoice, hasPoll: self.hasPoll)
            if let rejection = momentsCanAdd(kind: .voice, to: state, limits: self.limits, duration: duration, voiceComment: false) {
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
        momentsPresentErrorToast(controller: self, presentationData: self.presentationData, text: self.presentationData.strings.Moments_VoiceFailed)
    }

    private func presentRejection(_ rejection: MomentsAttachmentRejection) {
        let text: String
        switch rejection {
        case .imageLimit, .videoLimit:
            text = self.presentationData.strings.Moments_LoadFailed
        case .videoTooLong, .voiceTooLong:
            text = self.presentationData.strings.Moments_LoadFailed
        default:
            text = self.presentationData.strings.Moments_LoadFailed
        }
        self.present(textAlertController(context: self.context, title: nil, text: text, actions: [TextAlertAction(type: .defaultAction, title: self.presentationData.strings.Common_Cancel, action: {})]), in: .window(.root))
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
        let dirty = !(self.textView.text ?? "").isEmpty || !self.media.isEmpty || self.audienceChosen
        guard dirty else {
            self.navigationController?.popViewController(animated: true)
            return
        }
        let strings = self.presentationData.strings
        self.present(textAlertController(context: self.context, title: strings.Moments_Draft_Title, text: strings.Moments_FriendsHint, actions: [
            TextAlertAction(type: .defaultAction, title: strings.Moments_Draft_Save, action: { [weak self] in
                self?.saveDraft()
                self?.navigationController?.popViewController(animated: true)
            }),
            TextAlertAction(type: .destructiveAction, title: strings.Moments_Draft_Discard, action: { [weak self] in
                self?.context.engine.moments.storeDraft(nil)
                self?.navigationController?.popViewController(animated: true)
            }),
            TextAlertAction(type: .genericAction, title: strings.Moments_Draft_Continue, action: {})
        ], actionLayout: .vertical), in: .window(.root))
    }

    @objc private func nearbyChanged() {
        self.allowNearby = self.nearbySwitch.isOn
    }

    @objc private func publishPressed() {
        guard self.audienceChosen, !self.publishing else { return }
        let audience = momentsAudience(from: self.privacy)
        let text = self.textView.text ?? ""
        let scan = momentsScanText(text, limits: self.limits)
        let submit: () -> Void = { [weak self] in
            self?.submitPost()
        }
        if !scan.mentions.isEmpty && audience.kind != .everyone {
            self.present(textAlertController(context: self.context, title: nil, text: self.presentationData.strings.Moments_MentionWarning + "\n" + scan.mentions.joined(separator: ", "), actions: [
                TextAlertAction(type: .genericAction, title: self.presentationData.strings.Common_Cancel, action: {}),
                TextAlertAction(type: .defaultAction, title: self.presentationData.strings.Moments_Publish, action: submit)
            ]), in: .window(.root))
        } else {
            submit()
        }
    }

    private func currentDraft() -> MomentsPostDraft {
        let audience = momentsAudience(from: self.privacy)
        let nearby = self.allowNearby && audience.kind == .everyone && audience.exclude.isEmpty && audience.include.isEmpty
        return MomentsPostDraft(
            text: (self.textView.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            audience: audience,
            mediaKeys: self.media.sorted { $0.order < $1.order }.map(\.key).filter { !$0.isEmpty },
            allowNearby: nearby,
            quoteOf: self.quoteId,
            clientNonce: self.clientNonce
        )
    }

    private func reusableAudienceToken(kind: String, userIds: [Int64]) -> String? {
        guard let stored = self.audienceGrant, stored.kind == kind, stored.userIds == userIds else {
            return nil
        }
        let now = Int64(Date().timeIntervalSince1970)
        if stored.grant.needsRefresh(now: now) || stored.grant.token.isEmpty {
            return nil
        }
        return stored.grant.token
    }

    private func submitPost() {
        guard self.audienceChosen, !self.publishing else { return }
        let draft = self.currentDraft()
        let tokenKind = momentsEncodePost(draft, audienceToken: nil)
        let token: String?
        if case let .success(.needsAudienceToken(kind, userIds)) = tokenKind {
            token = self.reusableAudienceToken(kind: kind, userIds: userIds)
        } else {
            token = nil
        }
        switch momentsEncodePost(draft, audienceToken: token) {
        case let .success(.needsAudienceToken(kind, userIds)):
            self.fetchAudienceToken(kind: kind, userIds: userIds, draft: draft)
        case .failure(.audienceTokenRequired), .failure(.audienceNotRepresentable):
            self.presentAudienceKept()
        case .failure(.invalidClientNonce):
            self.presentPublishError()
        case let .success(.ready(body)):
            self.sendPost(body)
        }
    }

    private func fetchAudienceToken(kind: String, userIds: [Int64], draft: MomentsPostDraft) {
        self.publishing = true
        self.refresh()
        let _ = (self.context.engine.moments.audienceToken(kind: kind, userIds: userIds) |> deliverOnMainQueue).start(next: { [weak self] grant in
            guard let self else { return }
            self.publishing = false
            self.refresh()
            self.audienceGrant = (kind: kind, userIds: userIds, grant: grant)
            switch momentsEncodePost(draft, audienceToken: grant.token) {
            case let .success(.ready(body)):
                self.sendPost(body)
            case .success(.needsAudienceToken(_, _)), .failure(_):
                self.presentAudienceKept()
            }
        }, error: { [weak self] _ in
            guard let self else { return }
            self.publishing = false
            self.refresh()
            self.presentAudienceKept()
        })
    }

    private func sendPost(_ body: [String: Any]) {
        guard !self.publishing else { return }
        self.publishing = true
        self.refresh()
        let _ = (self.context.engine.moments.publish(body) |> deliverOnMainQueue).start(next: { [weak self] _ in
            guard let self else { return }
            self.publishing = false
            self.context.engine.moments.storeDraft(nil)
            self.navigationController?.popViewController(animated: true)
        }, error: { [weak self] _ in
            guard let self else { return }
            self.publishing = false
            self.refresh()
            self.presentPublishError()
        })
    }

    private func presentPublishError() {
        self.presentFailure(self.presentationData.strings.Moments_FailedRetry)
    }

    private func presentAudienceKept() {
        self.presentFailure(self.presentationData.strings.Moments_Audience_Kept)
    }

    private func presentFailure(_ text: String) {
        self.present(textAlertController(context: self.context, title: nil, text: text, actions: [TextAlertAction(type: .defaultAction, title: self.presentationData.strings.Moments_Retry, action: { [weak self] in
            self?.submitPost()
        })]), in: .window(.root))
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
