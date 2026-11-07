import Foundation

/// What the sticker upload signal told the editor. One user retry is a new event.
/// Nothing here starts another upload by itself.
public struct StickerUploadSession: Equatable {
    public var sawSuccess: Bool
    public var cancelled: Bool
    public var loading: Bool
    public var automaticRetryCount: Int

    public static var started: StickerUploadSession {
        return StickerUploadSession(sawSuccess: false, cancelled: false, loading: true, automaticRetryCount: 0)
    }
}

public enum StickerUploadEvent: Equatable {
    case progress(Float)
    case succeeded
    case failed
    case completedWithoutValue
    case userCancelled
    case userRetried
}

public enum StickerUploadEffect: Equatable {
    case updateProgress(Float)
    case commitSuccess
    case stopLoadingAndOfferRetry
    case restart
    case none
}

public func stickerUploadReduce(_ session: inout StickerUploadSession, _ event: StickerUploadEvent) -> StickerUploadEffect {
    switch event {
    case let .progress(value):
        guard session.loading, !session.cancelled, !session.sawSuccess else {
            return .none
        }
        return .updateProgress(value)
    case .succeeded:
        guard session.loading, !session.cancelled, !session.sawSuccess else {
            return .none
        }
        session.sawSuccess = true
        session.loading = false
        return .commitSuccess
    case .failed, .completedWithoutValue:
        guard session.loading, !session.cancelled, !session.sawSuccess else {
            return .none
        }
        session.loading = false
        return .stopLoadingAndOfferRetry
    case .userCancelled:
        guard session.loading, !session.cancelled, !session.sawSuccess else {
            return .none
        }
        session.cancelled = true
        session.loading = false
        return .none
    case .userRetried:
        guard !session.loading, !session.sawSuccess, !session.cancelled else {
            return .none
        }
        session = .started
        return .restart
    }
}
