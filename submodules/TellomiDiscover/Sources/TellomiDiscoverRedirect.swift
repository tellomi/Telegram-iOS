import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum TellomiDiscoverRedirect: Equatable {
    case refuse
    /// Follow only this URL. `attachBearer` is true only when it is still on the original origin and prefix.
    case follow(URL, attachBearer: Bool)
}

/// The URLSession redirect delegate calls this and nothing else. A refused redirect is not followed.
/// Bearer is removed unless the target stays on the same https origin and under the original path prefix.
public func tellomiDiscoverRedirect(original: URL?, proposed: URL?, authorizes: Bool) -> TellomiDiscoverRedirect {
    guard let original, let proposed else {
        return .refuse
    }
    guard original.scheme?.lowercased() == "https", proposed.scheme?.lowercased() == "https" else {
        return .refuse
    }
    guard original.user == nil, original.password == nil, proposed.user == nil, proposed.password == nil else {
        return .refuse
    }
    guard let originalHost = original.host, let proposedHost = proposed.host, !originalHost.isEmpty, originalHost.caseInsensitiveCompare(proposedHost) == .orderedSame else {
        return .refuse
    }
    guard (original.port ?? 443) == (proposed.port ?? 443) else {
        return .refuse
    }
    let prefix = tellomiDiscoverRedirectPrefix(original.path)
    guard tellomiDiscoverRedirectPath(proposed.path, allowed: prefix) else {
        return .refuse
    }
    return .follow(proposed, attachBearer: authorizes)
}

func tellomiDiscoverRedirectPrefix(_ path: String) -> String {
    let uploads = TellomiDiscoverImageContract.uploadsPath
    if path == uploads || path.hasPrefix(uploads + "/") {
        return uploads
    }
    if path == "/v1/feed" || path.hasPrefix("/v1/feed/") {
        return "/v1/feed"
    }
    if path == "/v1/capabilities" {
        return "/v1/capabilities"
    }
    return path
}

private func tellomiDiscoverRedirectPath(_ path: String, allowed prefix: String) -> Bool {
    if path.contains("..") || path.contains("\\") || path.contains("%") {
        return false
    }
    if path == prefix {
        return true
    }
    return path.hasPrefix(prefix + "/")
}

public final class TellomiDiscoverRedirectGate: NSObject, URLSessionTaskDelegate {
    public func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        let _ = (session, response)
        let authorizes = task.originalRequest?.value(forHTTPHeaderField: "Authorization") != nil
        switch tellomiDiscoverRedirect(original: task.originalRequest?.url, proposed: request.url, authorizes: authorizes) {
        case .refuse:
            completionHandler(nil)
        case let .follow(url, attachBearer):
            var clean = request
            clean.url = url
            clean.setValue(nil, forHTTPHeaderField: "Authorization")
            if attachBearer, let header = task.originalRequest?.value(forHTTPHeaderField: "Authorization"), !header.isEmpty {
                clean.setValue(header, forHTTPHeaderField: "Authorization")
            }
            completionHandler(clean)
        }
    }
}
