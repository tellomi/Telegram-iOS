import Foundation
import Postbox
import SwiftSignalKit
internal import TelegramApi

/// In-memory bearer token from `discover.getEngineCredential`. The host is not stored here:
/// `region` is only `cn` or `global`, and the https origin comes from `help.getAppConfig`.
final class MomentsCredentialStore {
    static let shared = MomentsCredentialStore()

    private let lock = NSLock()
    private var values: [Int64: MomentsCredential] = [:]

    func set(_ credential: MomentsCredential, accountPeerId: Int64) {
        self.lock.lock()
        self.values[accountPeerId] = credential
        self.lock.unlock()
    }

    func get(accountPeerId: Int64, now: Int64, baseURL: String) -> MomentsCredential? {
        self.lock.lock()
        let value = self.values[accountPeerId]
        self.lock.unlock()
        guard let value, value.baseURL == baseURL, !value.needsRefresh(now: now) else {
            return nil
        }
        return value
    }
}

private final class MomentsHTTP {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func send(credential: MomentsCredential, method: String, path: String, query: [String: String] = [:], body: Data? = nil, contentType: String = "application/json") -> Signal<Data, MomentsAPIError> {
        return Signal { [session] subscriber in
            guard var components = URLComponents(string: credential.baseURL + path) else {
                subscriber.putError(.invalid("bad url"))
                return EmptyDisposable
            }
            if !query.isEmpty {
                components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
            }
            guard let url = components.url else {
                subscriber.putError(.invalid("bad url"))
                return EmptyDisposable
            }
            var request = URLRequest(url: url)
            request.httpMethod = method
            request.setValue("Bearer \(credential.token)", forHTTPHeaderField: "Authorization")
            if let body {
                request.httpBody = body
                request.setValue(contentType, forHTTPHeaderField: "Content-Type")
            }
            let task = session.dataTask(with: request) { data, response, error in
                if let error = error as NSError?, error.code == NSURLErrorCancelled {
                    subscriber.putError(.cancelled)
                    return
                }
                if let error {
                    subscriber.putError(.transport(error.localizedDescription))
                    return
                }
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                let payload = data ?? Data()
                if !(200..<300).contains(status) {
                    subscriber.putError(momentsError(data: payload, status: status))
                    return
                }
                subscriber.putNext(payload)
                subscriber.putCompletion()
            }
            task.resume()
            return ActionDisposable {
                task.cancel()
            }
        }
    }

    func upload(credential: MomentsCredential, file: MomentsUploadFile) -> Signal<MomentsMedia, MomentsAPIError> {
        return Signal { [session] subscriber in
            let fileURL = URL(fileURLWithPath: file.path)
            let length = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.int64Value ?? 0
            guard length > 0, let createURL = URL(string: credential.baseURL + "/v1/feed/media/uploads") else {
                subscriber.putError(.invalid("upload"))
                return EmptyDisposable
            }
            var create = URLRequest(url: createURL)
            create.httpMethod = "POST"
            create.setValue("Bearer \(credential.token)", forHTTPHeaderField: "Authorization")
            create.setValue("1.0.0", forHTTPHeaderField: "Tus-Resumable")
            create.setValue(String(length), forHTTPHeaderField: "Upload-Length")
            create.setValue(momentsTusUploadMetadata(filename: file.filename, mimeType: file.mimeType), forHTTPHeaderField: "Upload-Metadata")
            let createTask = session.dataTask(with: create) { data, response, error in
                if let error {
                    subscriber.putError(.transport(error.localizedDescription))
                    return
                }
                let http = response as? HTTPURLResponse
                let status = http?.statusCode ?? 0
                let payload = data ?? Data()
                guard (200..<300).contains(status), let locationHeader = http?.value(forHTTPHeaderField: "Location"), let location = momentsResolvedUploadLocation(base: credential.baseURL, location: locationHeader), let patchURL = URL(string: location) else {
                    subscriber.putError(momentsError(data: payload, status: status))
                    return
                }
                var patch = URLRequest(url: patchURL)
                patch.httpMethod = "PATCH"
                patch.setValue("Bearer \(credential.token)", forHTTPHeaderField: "Authorization")
                patch.setValue("1.0.0", forHTTPHeaderField: "Tus-Resumable")
                patch.setValue("0", forHTTPHeaderField: "Upload-Offset")
                patch.setValue("application/offset+octet-stream", forHTTPHeaderField: "Content-Type")
                let patchTask = session.uploadTask(with: patch, fromFile: fileURL) { patchData, patchResponse, patchError in
                    if let patchError {
                        subscriber.putError(.transport(patchError.localizedDescription))
                        return
                    }
                    let patchHTTP = patchResponse as? HTTPURLResponse
                    let patchStatus = patchHTTP?.statusCode ?? 0
                    let patchPayload = patchData ?? Data()
                    guard (200..<300).contains(patchStatus) else {
                        subscriber.putError(momentsError(data: patchPayload, status: patchStatus))
                        return
                    }
                    let headers = patchHTTP?.allHeaderFields ?? http?.allHeaderFields ?? [:]
                    guard let key = momentsMediaUploadKey(body: patchPayload.isEmpty ? payload : patchPayload, headerFields: headers, location: location) else {
                        subscriber.putError(.invalid("upload-key"))
                        return
                    }
                    subscriber.putNext(MomentsMedia(type: file.type, key: key, width: file.width, height: file.height, durationMs: file.durationMs, order: file.order))
                    subscriber.putCompletion()
                }
                patchTask.resume()
            }
            createTask.resume()
            return ActionDisposable {
                createTask.cancel()
            }
        }
    }
}

public extension TelegramEngine {
    final class Moments {
        private let account: Account
        private let http = MomentsHTTP()
        private let mediaBaseURL = Atomic<String?>(value: nil)
        private let didLoadMediaBase = Atomic<Bool>(value: false)

        init(account: Account) {
            self.account = account
        }

        public var accountPeerId: Int64 {
            return self.account.peerId.toInt64()
        }

        private func endpoint() -> Signal<String, MomentsAPIError> {
            return self.account.postbox.transaction { transaction -> String? in
                return momentsFeedEndpoint(appConfiguration: currentAppConfiguration(transaction: transaction))?.baseURL
            }
            |> castError(MomentsAPIError.self)
            |> mapToSignal { base -> Signal<String, MomentsAPIError> in
                guard let base else {
                    return .fail(.credentialUnavailable)
                }
                return .single(base)
            }
        }

        /// Bearer from `discover.getEngineCredential`. Refreshed before `expires`. `region` is checked and never used as a host.
        private func credential() -> Signal<MomentsCredential, MomentsAPIError> {
            return self.endpoint()
            |> mapToSignal { base in
                let now = Int64(Date().timeIntervalSince1970)
                if let credential = MomentsCredentialStore.shared.get(accountPeerId: self.accountPeerId, now: now, baseURL: base) {
                    return .single(credential)
                }
                return self.account.network.request(Api.functions.discover.getEngineCredential())
                |> mapError { _ -> MomentsAPIError in
                    return .credentialUnavailable
                }
                |> mapToSignal { result -> Signal<MomentsCredential, MomentsAPIError> in
                    switch result {
                    case let .engineCredential(value):
                        guard value.region == "cn" || value.region == "global", !value.token.isEmpty else {
                            return .fail(.credentialUnavailable)
                        }
                        let credential = MomentsCredential(token: value.token, baseURL: base, expiresAt: Int64(value.expires), region: value.region)
                        MomentsCredentialStore.shared.set(credential, accountPeerId: self.accountPeerId)
                        return .single(credential)
                    }
                }
            }
        }

        private func call(method: String, path: String, query: [String: String] = [:], body: [String: Any]? = nil) -> Signal<Data, MomentsAPIError> {
            let bodyData = body.flatMap { momentsJSONData($0) }
            return self.credential()
            |> mapToSignal { credential in
                self.http.send(credential: credential, method: method, path: path, query: query, body: bodyData)
            }
        }

        public func cachedPage(_ kind: MomentsFeedKind) -> Signal<MomentsPage?, NoError> {
            return self.account.postbox.transaction { transaction -> MomentsPage? in
                guard let payload = momentsReadBlob(transaction: transaction, id: momentsFeedCacheId(kind)), let data = payload.data(using: .utf8) else {
                    return nil
                }
                return momentsPage(data: data, mediaBaseURL: self.mediaBaseURL.with { $0 })
            }
        }

        public func storePage(_ kind: MomentsFeedKind, data: Data) {
            guard let payload = String(data: data, encoding: .utf8) else {
                return
            }
            let _ = self.account.postbox.transaction { transaction in
                momentsWriteBlob(transaction: transaction, id: momentsFeedCacheId(kind), payload: payload)
            }.start()
        }

        public func loadFeed(_ kind: MomentsFeedKind, cursor: String?, city: String?, sort: String?) -> Signal<MomentsPage, MomentsAPIError> {
            var query: [String: String] = ["limit": "\(MomentsLimits.standard.pageSize)"]
            if let cursor, !cursor.isEmpty {
                query["cursor"] = cursor
            }
            if kind == .nearby {
                if let city {
                    query["city"] = city
                }
                query["sort"] = sort ?? "latest"
            }
            return self.prepareMediaBase()
            |> mapToSignal { _ in
                return self.call(method: "GET", path: "/v1/feed/\(kind.rawValue)", query: query)
            }
            |> mapToSignal { data in
                return self.hydrateFeedPage(data)
            }
        }

        public func feedStatus() -> Signal<MomentsFeedStatus, MomentsAPIError> {
            return self.call(method: "GET", path: "/v1/feed/status")
            |> map { data in
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    return MomentsFeedStatus(visible: true)
                }
                if json["visible"] == nil {
                    return MomentsFeedStatus(visible: true)
                }
                return MomentsFeedStatus(visible: momentsBool(json, "visible"))
            }
        }

        /// Tab ids from `GET /v1/capabilities`, then `GET /v1/feed/config`. `friends` is not an endpoint.
        public func feedTabs() -> Signal<[String], MomentsAPIError> {
            let fromConfig = self.remoteConfig()
            |> map { config -> [String] in
                return config.tabs.filter { $0 != "friends" && !$0.isEmpty }
            }
            return self.call(method: "GET", path: "/v1/capabilities")
            |> map { data -> [String] in
                return momentsCapabilityTabs(data)
            }
            |> mapToSignal { tabs -> Signal<[String], MomentsAPIError> in
                if tabs.isEmpty {
                    return fromConfig
                }
                return .single(tabs)
            }
            |> `catch` { _ -> Signal<[String], MomentsAPIError> in
                return fromConfig
            }
        }

        public func setLiked(_ postId: String, liked: Bool) -> Signal<Never, MomentsAPIError> {
            return self.call(method: liked ? "PUT" : "DELETE", path: "/v1/feed/posts/\(postId)/like")
            |> ignoreValues
        }

        public func setSaved(_ postId: String, saved: Bool) -> Signal<Never, MomentsAPIError> {
            return self.call(method: saved ? "PUT" : "DELETE", path: "/v1/feed/posts/\(postId)/save")
            |> ignoreValues
        }

        public func setRepost(_ postId: String, repost: Bool) -> Signal<Never, MomentsAPIError> {
            return self.call(method: repost ? "PUT" : "DELETE", path: "/v1/feed/posts/\(postId)/repost")
            |> ignoreValues
        }

        public func setFollow(authorId: String, follow: Bool) -> Signal<Never, MomentsAPIError> {
            return self.call(method: follow ? "PUT" : "DELETE", path: "/v1/feed/follow/author/\(authorId)")
            |> ignoreValues
        }

        public func hide(postId: String, undo: Bool) -> Signal<Never, MomentsAPIError> {
            if undo {
                return self.call(method: "DELETE", path: "/v1/feed/posts/\(postId)/hide") |> ignoreValues
            }
            return self.call(method: "POST", path: "/v1/feed/posts/\(postId)/hide") |> ignoreValues
        }

        public func notInterested(postId: String) -> Signal<Never, MomentsAPIError> {
            return self.call(method: "POST", path: "/v1/feed/not-interested", body: ["content_id": postId])
            |> ignoreValues
        }

        public func setMuted(profileId: String, muted: Bool) -> Signal<Never, MomentsAPIError> {
            return self.call(method: muted ? "PUT" : "DELETE", path: "/v1/feed/me/feed-mutes/\(profileId)")
            |> ignoreValues
        }

        public func report(targetType: String, targetId: String, reason: String, detail: String?) -> Signal<Never, MomentsAPIError> {
            var body: [String: Any] = ["target_type": targetType, "target_id": targetId, "reason": reason]
            if let detail, !detail.isEmpty {
                body["detail"] = detail
            }
            return self.call(method: "POST", path: "/v1/feed/reports", body: body) |> ignoreValues
        }

        public func comments(postId: String, sort: String, cursor: String?, thread: Bool = true) -> Signal<MomentsCommentPage, MomentsAPIError> {
            var query = ["sort": sort]
            if thread {
                query["thread"] = "1"
            }
            if let cursor {
                query["cursor"] = cursor
            }
            return self.prepareMediaBase()
            |> mapToSignal { _ in
                return self.call(method: "GET", path: "/v1/feed/posts/\(postId)/comments", query: query)
            }
            |> map { data in
                return momentsCommentPage(data: data, mediaBaseURL: self.mediaBaseURL.with { $0 })
            }
        }

        public func replies(rootId: String, cursor: String?) -> Signal<MomentsReplyPage, MomentsAPIError> {
            var query: [String: String] = [:]
            if let cursor {
                query["cursor"] = cursor
            }
            return self.prepareMediaBase()
            |> mapToSignal { _ in
                return self.call(method: "GET", path: "/v1/feed/comments/\(rootId)/replies", query: query)
            }
            |> map { data in
                return momentsReplyPage(data: data, rootId: rootId, mediaBaseURL: self.mediaBaseURL.with { $0 })
            }
        }

        public func addComment(postId: String, text: String, parentId: String?, attachment: [String: Any]? = nil) -> Signal<Never, MomentsAPIError> {
            var body: [String: Any] = ["text": text]
            if let parentId {
                body["parent_id"] = parentId
            }
            if let attachment, let key = momentsString(attachment, "key"), !key.isEmpty {
                body["media_keys"] = [key]
                if momentsString(attachment, "type") == "sticker" || momentsBool(attachment, "sticker") {
                    body["sticker"] = true
                }
            }
            return self.call(method: "POST", path: "/v1/feed/posts/\(postId)/comments", body: body) |> ignoreValues
        }

        public func setCommentLiked(id: String, liked: Bool) -> Signal<Never, MomentsAPIError> {
            return self.call(method: liked ? "PUT" : "DELETE", path: "/v1/feed/comments/\(id)/like") |> ignoreValues
        }

        public func setCommentDisliked(id: String, disliked: Bool) -> Signal<Never, MomentsAPIError> {
            return self.call(method: disliked ? "PUT" : "DELETE", path: "/v1/feed/comments/\(id)/dislike") |> ignoreValues
        }

        public func deleteComment(id: String) -> Signal<Never, MomentsAPIError> {
            return self.call(method: "DELETE", path: "/v1/feed/posts/\(id)") |> ignoreValues
        }

        public func storedAudience() -> Signal<EngineStoryPrivacy?, NoError> {
            return self.account.postbox.transaction { transaction -> EngineStoryPrivacy? in
                guard let payload = momentsReadBlob(transaction: transaction, id: momentsAudienceCacheId()), let data = payload.data(using: .utf8), let stored = try? JSONDecoder().decode(MomentsStoredAudience.self, from: data), let base = EngineStoryPrivacy.Base(rawValue: stored.base) else {
                    return nil
                }
                let peers = stored.peers.map { PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value($0)) }
                return EngineStoryPrivacy(base: base, additionallyIncludePeers: peers)
            }
        }

        public func storedDraft() -> Signal<MomentsComposerDraft?, NoError> {
            return self.account.postbox.transaction { transaction -> MomentsComposerDraft? in
                guard let payload = momentsReadBlob(transaction: transaction, id: momentsDraftsCacheId()), let data = payload.data(using: .utf8) else {
                    return nil
                }
                return try? JSONDecoder().decode(MomentsComposerDraft.self, from: data)
            }
        }

        public func storeDraft(_ draft: MomentsComposerDraft?) {
            let payload: String?
            if let draft, let data = try? JSONEncoder().encode(draft) {
                payload = String(data: data, encoding: .utf8)
            } else {
                payload = nil
            }
            let _ = self.account.postbox.transaction { transaction in
                momentsWriteBlob(transaction: transaction, id: momentsDraftsCacheId(), payload: payload)
            }.start()
        }

        public func storeAudience(_ privacy: EngineStoryPrivacy) {
            let stored = MomentsStoredAudience(base: privacy.base.rawValue, peers: privacy.additionallyIncludePeers.map { $0.toInt64() })
            guard let data = try? JSONEncoder().encode(stored), let payload = String(data: data, encoding: .utf8) else {
                return
            }
            let _ = self.account.postbox.transaction { transaction in
                momentsWriteBlob(transaction: transaction, id: momentsAudienceCacheId(), payload: payload)
            }.start()
        }

        public func uploadFile(_ file: MomentsUploadFile) -> Signal<MomentsMedia, MomentsAPIError> {
            return self.credential()
            |> mapToSignal { credential in
                self.http.upload(credential: credential, file: file)
            }
        }

        public func likers(postId: String) -> Signal<[MomentsAuthor], MomentsAPIError> {
            return self.call(method: "GET", path: "/v1/feed/posts/\(postId)/likers")
            |> map { data in
                guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    return []
                }
                return momentsArray(root["items"] ?? root["likers"] ?? root["users"]).compactMap { momentsAuthor($0) }
            }
        }

        public func pollVoters(postId: String) -> Signal<[MomentsPollOptionVoters], MomentsAPIError> {
            return self.call(method: "GET", path: "/v1/feed/posts/\(postId)/poll/voters")
            |> map { data in
                guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    return []
                }
                return momentsArray(root["options"] ?? root["items"]).compactMap { item in
                    guard let id = momentsString(item, "id", "option_id") else {
                        return nil
                    }
                    return MomentsPollOptionVoters(id: id, text: momentsString(item, "text", "option") ?? id, voters: momentsArray(item["voters"] ?? item["users"]).compactMap { momentsAuthor($0) })
                }
            }
        }

        public func publish(_ body: [String: Any]) -> Signal<String, MomentsAPIError> {
            return self.call(method: "POST", path: "/v1/feed/posts", body: body)
            |> mapToSignal { data in
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let id = momentsString(json, "id") else {
                    return .fail(.invalid("post"))
                }
                return .single(id)
            }
        }

        public func editPost(id: String, body: [String: Any]) -> Signal<Never, MomentsAPIError> {
            return self.call(method: "PATCH", path: "/v1/feed/posts/\(id)", body: body) |> ignoreValues
        }

        public func setAudience(id: String, kind: String) -> Signal<Never, MomentsAPIError> {
            return self.call(method: "PUT", path: "/v1/feed/posts/\(id)/audience", body: ["kind": kind]) |> ignoreValues
        }

        public func setPostSettings(id: String, body: [String: Any]) -> Signal<Never, MomentsAPIError> {
            return self.call(method: "PATCH", path: "/v1/feed/posts/\(id)/settings", body: body) |> ignoreValues
        }

        public func deletePost(id: String) -> Signal<Never, MomentsAPIError> {
            return self.call(method: "DELETE", path: "/v1/feed/posts/\(id)") |> ignoreValues
        }

        public func vote(postId: String, options: [String]) -> Signal<Never, MomentsAPIError> {
            return self.call(method: "PUT", path: "/v1/feed/posts/\(postId)/vote", body: ["options": options]) |> ignoreValues
        }

        public func clearVote(postId: String) -> Signal<Never, MomentsAPIError> {
            return self.call(method: "DELETE", path: "/v1/feed/posts/\(postId)/vote") |> ignoreValues
        }

        public func closePoll(postId: String) -> Signal<Never, MomentsAPIError> {
            return self.call(method: "POST", path: "/v1/feed/posts/\(postId)/poll/close") |> ignoreValues
        }

        public func profilePosts(id: String, filter: String, cursor: String?) -> Signal<MomentsPage, MomentsAPIError> {
            var query = ["filter": filter]
            if let cursor {
                query["cursor"] = cursor
            }
            return self.prepareMediaBase()
            |> mapToSignal { _ in
                return self.call(method: "GET", path: "/v1/feed/profiles/\(id)/posts", query: query)
            }
            |> mapToSignal { data in
                return self.hydrateFeedPage(data)
            }
        }

        public func saved(cursor: String?) -> Signal<MomentsPage, MomentsAPIError> {
            return self.listPage("/v1/feed/me/saved", cursor: cursor)
        }

        public func liked(cursor: String?) -> Signal<MomentsPage, MomentsAPIError> {
            return self.listPage("/v1/feed/me/liked", cursor: cursor)
        }

        public func search(query text: String, scope: String, sort: String, cursor: String?) -> Signal<MomentsSearchResult, MomentsAPIError> {
            var query = ["q": text, "scope": scope, "sort": sort]
            if let cursor {
                query["cursor"] = cursor
            }
            return self.prepareMediaBase()
            |> mapToSignal { _ in
                return self.call(method: "GET", path: "/v1/feed/search", query: query)
            }
            |> map { data in
                momentsSearchResult(data: data, mediaBaseURL: self.mediaBaseURL.with { $0 })
            }
        }

        public func topic(name: String, sort: String, cursor: String?) -> Signal<MomentsTopicPage, MomentsAPIError> {
            var query = ["sort": sort]
            if let cursor {
                query["cursor"] = cursor
            }
            let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
            return self.prepareMediaBase()
            |> mapToSignal { _ in
                return self.call(method: "GET", path: "/v1/feed/topics/\(encoded)", query: query)
            }
            |> map { data in
                momentsTopicPage(data: data, name: name, mediaBaseURL: self.mediaBaseURL.with { $0 })
            }
        }

        public func notifications(tab: String) -> Signal<[MomentsNotification], MomentsAPIError> {
            let normalized: String
            switch tab {
            case "follows", "system":
                normalized = tab
            default:
                normalized = "interactions"
            }
            return self.call(method: "GET", path: "/v1/feed/me/notifications", query: ["tab": normalized])
            |> map { data in
                guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    return []
                }
                return momentsArray(root["items"] ?? root["notifications"]).compactMap(momentsNotification)
            }
        }

        public func markNotificationsRead() -> Signal<Never, MomentsAPIError> {
            return self.call(method: "POST", path: "/v1/feed/me/notifications/read") |> ignoreValues
        }

        public func notificationSettings() -> Signal<MomentsNotificationSettings, MomentsAPIError> {
            return self.call(method: "GET", path: "/v1/feed/me/notification-settings")
            |> map { data in
                momentsNotificationSettings(data: data)
            }
        }

        public func updateNotificationSettings(_ settings: MomentsNotificationSettings) -> Signal<Never, MomentsAPIError> {
            let body: [String: Any] = [
                "comments": settings.comments,
                "replies": settings.replies,
                "mentions": settings.mentions,
                "follows": settings.follows,
                "likes": settings.likes,
                "reposts": settings.reposts,
                "new_posts": settings.newPosts
            ]
            return self.call(method: "PUT", path: "/v1/feed/me/notification-settings", body: body) |> ignoreValues
        }

        public func listVisibility() -> Signal<MomentsListVisibilitySettings, MomentsAPIError> {
            return self.call(method: "GET", path: "/v1/feed/me/list-visibility")
            |> map { data in
                momentsListVisibility(data: data)
            }
        }

        public func updateListVisibility(_ settings: MomentsListVisibilitySettings) -> Signal<Never, MomentsAPIError> {
            return self.call(method: "PUT", path: "/v1/feed/me/list-visibility", body: [
                "following_list": settings.followingList.rawValue,
                "followers_list": settings.followersList.rawValue
            ]) |> ignoreValues
        }

        public func remoteConfig() -> Signal<MomentsRemoteConfig, MomentsAPIError> {
            return self.call(method: "GET", path: "/v1/feed/config")
            |> map { data in
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    return MomentsRemoteConfig()
                }
                let config = MomentsRemoteConfig(
                    textLimit: json["text_limit"] == nil ? nil : momentsInt(json, "text_limit"),
                    imageLimit: json["image_limit"] == nil ? nil : momentsInt(json, "image_limit"),
                    videoLimit: json["video_limit"] == nil ? nil : momentsInt(json, "video_limit"),
                    videoMaxDuration: json["video_max_seconds"] == nil ? nil : Double(momentsInt(json, "video_max_seconds")),
                    voiceMaxDuration: json["voice_max_seconds"] == nil ? nil : Double(momentsInt(json, "voice_max_seconds")),
                    commentTextLimit: json["comment_text_limit"] == nil ? nil : momentsInt(json, "comment_text_limit"),
                    pageSize: json["page_size"] == nil ? nil : momentsInt(json, "page_size"),
                    tabs: json["tabs"] as? [String] ?? [],
                    mediaBaseURL: momentsConfigMediaBase(data)
                )
                if let mediaBaseURL = config.mediaBaseURL {
                    let _ = self.mediaBaseURL.swap(mediaBaseURL)
                }
                return config
            }
        }

        /// Emits once, after `media_base_url` is known. A `Signal<Never, _>` here would complete
        /// without a value and every `mapToSignal` chained after it would never run.
        private func prepareMediaBase() -> Signal<Void, MomentsAPIError> {
            if self.didLoadMediaBase.with({ $0 }) {
                return .single(Void())
            }
            return self.remoteConfig()
            |> map { _ -> Void in
                let _ = self.didLoadMediaBase.swap(true)
                return Void()
            }
        }

        public func cachedHides() -> Signal<MomentsLocalHides, NoError> {
            return self.account.postbox.transaction { transaction -> MomentsLocalHides in
                guard let payload = momentsReadBlob(transaction: transaction, id: momentsHidesCacheId()), let data = payload.data(using: .utf8), let hides = try? JSONDecoder().decode(MomentsLocalHides.self, from: data) else {
                    return MomentsLocalHides()
                }
                return hides
            }
        }

        public func storeHides(_ hides: MomentsLocalHides) {
            guard let data = try? JSONEncoder().encode(hides), let payload = String(data: data, encoding: .utf8) else {
                return
            }
            let _ = self.account.postbox.transaction { transaction in
                momentsWriteBlob(transaction: transaction, id: momentsHidesCacheId(), payload: payload)
            }.start()
        }

        private func listPage(_ path: String, cursor: String?) -> Signal<MomentsPage, MomentsAPIError> {
            var query: [String: String] = [:]
            if let cursor {
                query["cursor"] = cursor
            }
            return self.prepareMediaBase()
            |> mapToSignal { _ in
                return self.call(method: "GET", path: path, query: query)
            }
            |> mapToSignal { data in
                return self.hydrateFeedPage(data)
            }
        }

        private func hydrateFeedPage(_ data: Data) -> Signal<MomentsPage, MomentsAPIError> {
            let refs = momentsFeedRefPage(data: data) ?? MomentsFeedRefPage(ids: [], cursor: nil)
            if refs.ids.isEmpty {
                return .single(MomentsPage(items: [], nextCursor: refs.cursor))
            }
            return self.call(method: "POST", path: "/v1/feed/cards", body: ["ids": refs.ids])
            |> map { cardData in
                let items = momentsHydratedCards(ids: refs.ids, cardsData: cardData, mediaBaseURL: self.mediaBaseURL.with { $0 })
                return MomentsPage(items: items, nextCursor: refs.cursor)
            }
        }
    }
}

public struct MomentsSearchResult: Equatable {
    public var posts: [MomentsCard]
    public var topics: [MomentsTopicHit]
    public var users: [MomentsAuthor]
    public var nextCursor: String?

    public init(posts: [MomentsCard] = [], topics: [MomentsTopicHit] = [], users: [MomentsAuthor] = [], nextCursor: String? = nil) {
        self.posts = posts
        self.topics = topics
        self.users = users
        self.nextCursor = nextCursor
    }
}

public struct MomentsTopicHit: Equatable {
    public var name: String
    public var visibleCount: Int

    public init(name: String, visibleCount: Int) {
        self.name = name
        self.visibleCount = visibleCount
    }
}

public struct MomentsTopicPage: Equatable {
    public var name: String
    public var visibleCount: Int
    public var items: [MomentsCard]
    public var nextCursor: String?

    public init(name: String, visibleCount: Int, items: [MomentsCard], nextCursor: String?) {
        self.name = name
        self.visibleCount = visibleCount
        self.items = items
        self.nextCursor = nextCursor
    }
}

func momentsCommentCardBody(_ json: [String: Any]) -> [String: Any] {
    return momentsObject(json["card"]) ?? json
}

func momentsComment(_ json: [String: Any], mediaBaseURL: String? = nil) -> MomentsComment? {
    guard let id = momentsString(json, "id") else {
        return nil
    }
    let card = momentsCommentCardBody(json)
    let stats = momentsObject(json["stats"]) ?? momentsObject(card["stats"]) ?? json
    let me = momentsObject(json["me"]) ?? [:]
    let replies = momentsArray(json["replies"]).compactMap { momentsReply($0, rootId: id, mediaBaseURL: mediaBaseURL) }
    let media = momentsArray(card["media"]).first ?? momentsObject(json["attachment"])
    let created = momentsInt64(card, "created_at") != 0 ? momentsInt64(card, "created_at") : momentsInt64(json, "created_at")
    return MomentsComment(
        id: id,
        postId: momentsString(card, "root_id", "post_id") ?? momentsString(json, "post_id") ?? "",
        author: momentsAuthor(momentsObject(card["author"]) ?? momentsObject(json["author"]), mediaBaseURL: mediaBaseURL),
        text: momentsString(card, "text") ?? momentsString(json, "text") ?? "",
        attachment: media.flatMap { momentsMedia($0, mediaBaseURL: mediaBaseURL) },
        createdAt: created,
        likeCount: momentsInt(stats, "likes", "like_count"),
        liked: momentsBool(me, "liked") || momentsBool(json, "liked"),
        replies: replies,
        replyCount: max(momentsInt(json, "reply_count"), replies.count),
        isAuthor: momentsBool(json, "is_author"),
        ipRegionLabel: momentsString(card, "ip_region_label") ?? momentsString(json, "ip_region_label"),
        disliked: momentsBool(me, "disliked")
    )
}

func momentsReply(_ json: [String: Any], rootId: String, mediaBaseURL: String? = nil) -> MomentsReply? {
    guard let id = momentsString(json, "id") else {
        return nil
    }
    let card = momentsCommentCardBody(json)
    let stats = momentsObject(json["stats"]) ?? json
    let me = momentsObject(json["me"]) ?? [:]
    let replyTo = momentsObject(card["reply_to"]) ?? momentsObject(json["reply_to"])
    let media = momentsArray(card["media"]).first ?? momentsObject(json["attachment"])
    let created = momentsInt64(card, "created_at") != 0 ? momentsInt64(card, "created_at") : momentsInt64(json, "created_at")
    return MomentsReply(
        id: id,
        postId: momentsString(card, "root_id", "post_id") ?? "",
        rootId: momentsString(card, "root_id") ?? rootId,
        replyToName: momentsString(replyTo ?? [:], "display_name", "handle") ?? momentsString(json, "reply_to_name", "reply_to_user"),
        author: momentsAuthor(momentsObject(card["author"]) ?? momentsObject(json["author"]), mediaBaseURL: mediaBaseURL),
        text: momentsString(card, "text") ?? momentsString(json, "text") ?? "",
        attachment: media.flatMap { momentsMedia($0, mediaBaseURL: mediaBaseURL) },
        createdAt: created,
        likeCount: momentsInt(stats, "likes", "like_count"),
        liked: momentsBool(me, "liked") || momentsBool(json, "liked"),
        isAuthor: momentsBool(json, "is_author"),
        ipRegionLabel: momentsString(card, "ip_region_label"),
        disliked: momentsBool(me, "disliked")
    )
}

public func momentsCommentPage(data: Data, mediaBaseURL: String? = nil) -> MomentsCommentPage {
    guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return MomentsCommentPage(comments: [], total: 0, cursor: nil)
    }
    let comments = momentsArray(root["comments"] ?? root["items"]).compactMap { momentsComment($0, mediaBaseURL: mediaBaseURL) }
    let total = root["total"] == nil ? comments.count : momentsInt(root, "total")
    return MomentsCommentPage(comments: comments, total: total, cursor: momentsString(root, "cursor", "next_cursor"))
}

public func momentsReplyPage(data: Data, rootId: String, mediaBaseURL: String? = nil) -> MomentsReplyPage {
    guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return MomentsReplyPage(replies: [], total: 0, cursor: nil)
    }
    let replies = momentsArray(root["replies"] ?? root["items"]).compactMap { momentsReply($0, rootId: rootId, mediaBaseURL: mediaBaseURL) }
    let total = root["total"] == nil ? replies.count : momentsInt(root, "total")
    return MomentsReplyPage(replies: replies, total: total, cursor: momentsString(root, "cursor", "next_cursor"))
}

func momentsNotification(_ json: [String: Any]) -> MomentsNotification? {
    guard let id = momentsString(json, "id") else {
        return nil
    }
    let kind = MomentsNotificationKind(rawValue: momentsString(json, "kind") ?? "") ?? .system
    var actors = momentsArray(json["actors"]).compactMap { momentsAuthor($0) }
    if actors.isEmpty, let actor = momentsAuthor(momentsObject(json["actor"])) {
        actors = [actor]
    }
    return MomentsNotification(
        id: id,
        kind: kind,
        actors: actors,
        extraActorCount: momentsInt(json, "extra_actor_count"),
        postId: momentsString(json, "post_id"),
        commentId: momentsString(json, "comment_id"),
        text: momentsString(json, "text"),
        createdAt: momentsInt64(json, "created_at"),
        read: momentsBool(json, "read"),
        unavailable: momentsBool(json, "unavailable") || momentsString(json, "state") == "unavailable"
    )
}

func momentsSearchResult(data: Data, mediaBaseURL: String? = nil) -> MomentsSearchResult {
    guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return MomentsSearchResult()
    }
    let topics = momentsArray(root["topics"]).compactMap { item -> MomentsTopicHit? in
        guard let name = momentsString(item, "name") else {
            return nil
        }
        return MomentsTopicHit(name: name, visibleCount: momentsInt(item, "visible_count", "count"))
    }
    let users = momentsArray(root["users"]).compactMap { momentsAuthor($0) }
    return MomentsSearchResult(
        posts: momentsArray(root["posts"] ?? root["items"]).compactMap { momentsCard(json: $0, mediaBaseURL: mediaBaseURL) },
        topics: topics,
        users: users,
        nextCursor: momentsString(root, "next_cursor")
    )
}

func momentsTopicPage(data: Data, name: String, mediaBaseURL: String? = nil) -> MomentsTopicPage {
    guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return MomentsTopicPage(name: name, visibleCount: 0, items: [], nextCursor: nil)
    }
    return MomentsTopicPage(
        name: momentsString(root, "name") ?? name,
        visibleCount: momentsInt(root, "visible_count"),
        items: momentsArray(root["items"] ?? root["posts"]).compactMap { momentsCard(json: $0, mediaBaseURL: mediaBaseURL) },
        nextCursor: momentsString(root, "next_cursor")
    )
}

func momentsNotificationSettings(data: Data) -> MomentsNotificationSettings {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return .defaults
    }
    var settings = MomentsNotificationSettings.defaults
    if json["comments"] != nil { settings.comments = momentsBool(json, "comments") }
    if json["replies"] != nil { settings.replies = momentsBool(json, "replies") }
    if json["mentions"] != nil { settings.mentions = momentsBool(json, "mentions") }
    if json["follows"] != nil { settings.follows = momentsBool(json, "follows") }
    if json["likes"] != nil { settings.likes = momentsBool(json, "likes") }
    if json["reposts"] != nil { settings.reposts = momentsBool(json, "reposts") }
    if json["new_posts"] != nil { settings.newPosts = momentsBool(json, "new_posts") }
    return settings
}

func momentsListVisibility(data: Data) -> MomentsListVisibilitySettings {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return .defaults
    }
    let following = MomentsListVisibility(rawValue: momentsString(json, "following_list") ?? "") ?? .everyone
    let followers = MomentsListVisibility(rawValue: momentsString(json, "followers_list") ?? "") ?? .everyone
    return MomentsListVisibilitySettings(followingList: following, followersList: followers)
}
