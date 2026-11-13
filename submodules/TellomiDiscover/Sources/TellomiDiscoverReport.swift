import Foundation

/// A Discover report. Official option ids are the ones Telegram's report sheet uses:
/// `spam`, `violence`, `pornography`, `child`, `drugs`, `personal`, `other`.
/// The comment collected for Other is `detail`. The request is `POST /v1/feed/reports`.
public enum TellomiDiscoverReportTarget: Equatable {
    case post(String)
    case comment(postId: String, commentId: String)
}

public func tellomiDiscoverReportOptionId(_ raw: String) -> String? {
    switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "spam":
        return "spam"
    case "violence":
        return "violence"
    case "pornography", "porno":
        return "pornography"
    case "child", "childabuse", "child_abuse":
        return "child"
    case "drugs", "illegaldrugs", "illegal_drugs":
        return "drugs"
    case "personal", "personaldetails", "personal_details":
        return "personal"
    case "other", "custom":
        return "other"
    default:
        return nil
    }
}

public func tellomiDiscoverReportBody(target: TellomiDiscoverReportTarget, option: String, detail: String) -> Data? {
    guard let option = tellomiDiscoverReportOptionId(option) else {
        return nil
    }
    let postId: String
    let commentId: String?
    switch target {
    case let .post(id):
        guard let id = tellomiDiscoverPostId(id) else {
            return nil
        }
        postId = id
        commentId = nil
    case let .comment(postId: rawPost, commentId: rawComment):
        guard let post = tellomiDiscoverPostId(rawPost), let comment = tellomiDiscoverPostId(rawComment) else {
            return nil
        }
        postId = post
        commentId = comment
    }
    var object: [String: Any] = [
        "target_type": "content",
        "post_id": postId,
        "option": option,
        "reason": option,
        "detail": detail
    ]
    if let commentId {
        object["comment_id"] = commentId
    }
    return try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
}

/// Nil when the account is logged out, so no URL is built and no request is sent.
public func tellomiDiscoverReportCall(loggedIn: Bool, base: URL, token: String, target: TellomiDiscoverReportTarget, option: String, detail: String) -> TellomiDiscoverHTTPCall? {
    guard loggedIn else {
        return nil
    }
    return tellomiDiscoverHTTPCall(base: base, operation: .report(target: target, option: option, detail: detail), token: token)
}
