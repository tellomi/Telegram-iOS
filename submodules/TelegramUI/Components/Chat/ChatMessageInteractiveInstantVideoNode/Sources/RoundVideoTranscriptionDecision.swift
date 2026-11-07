import Foundation

/// What the chat already knows about a round video's transcript. Empty and failed
/// are not text: they must not replace the video.
public enum RoundVideoTranscriptFact: Equatable {
    case none
    case pending
    case text(String)
    case failure
}

public enum RoundVideoTranscriptPhase: Equatable {
    case collapsed
    case inProgress
    case expanded
    case locked
}

public struct RoundVideoTranscriptLayout: Equatable {
    public var phase: RoundVideoTranscriptPhase
    /// The round video stays on screen, with its duration, mute, time, and button.
    public var keepsRoundVideo: Bool
    /// Hand the circle off to the file row. Only when there is real text to show.
    public var replaceVideo: Bool
    public var showsText: Bool

    public init(phase: RoundVideoTranscriptPhase, keepsRoundVideo: Bool, replaceVideo: Bool, showsText: Bool) {
        self.phase = phase
        self.keepsRoundVideo = keepsRoundVideo
        self.replaceVideo = replaceVideo
        self.showsText = showsText
    }
}

public func roundVideoTranscriptFact(nonEmptyText: String?, isPending: Bool, failed: Bool) -> RoundVideoTranscriptFact {
    if failed {
        return .failure
    }
    if let nonEmptyText, !nonEmptyText.isEmpty {
        return isPending ? .pending : .text(nonEmptyText)
    }
    if isPending {
        return .pending
    }
    return .none
}

/// Pending, failure, empty, and cancel leave the round video in place.
/// A non-empty transcript is the only reason to replace it with the text row.
public func roundVideoTranscriptLayout(phase: RoundVideoTranscriptPhase, fact: RoundVideoTranscriptFact) -> RoundVideoTranscriptLayout {
    switch phase {
    case .locked:
        return RoundVideoTranscriptLayout(phase: .locked, keepsRoundVideo: true, replaceVideo: false, showsText: false)
    case .collapsed:
        return RoundVideoTranscriptLayout(phase: .collapsed, keepsRoundVideo: true, replaceVideo: false, showsText: false)
    case .inProgress:
        switch fact {
        case let .text(text):
            return RoundVideoTranscriptLayout(phase: .expanded, keepsRoundVideo: false, replaceVideo: true, showsText: !text.isEmpty)
        case .pending, .none:
            return RoundVideoTranscriptLayout(phase: .inProgress, keepsRoundVideo: true, replaceVideo: false, showsText: false)
        case .failure:
            return RoundVideoTranscriptLayout(phase: .collapsed, keepsRoundVideo: true, replaceVideo: false, showsText: false)
        }
    case .expanded:
        switch fact {
        case let .text(text) where !text.isEmpty:
            return RoundVideoTranscriptLayout(phase: .expanded, keepsRoundVideo: false, replaceVideo: true, showsText: true)
        case .text, .pending, .none, .failure:
            return RoundVideoTranscriptLayout(phase: .collapsed, keepsRoundVideo: true, replaceVideo: false, showsText: false)
        }
    }
}

public enum RoundVideoTranscriptSignalEvent: Equatable {
    case reportedSuccess
    case reportedFailure
    case finished
    case userCancelled
}

public struct RoundVideoTranscriptSession: Equatable {
    public var waiting: Bool
    public var sawSuccess: Bool
    public var automaticRetryCount: Int

    public static var waiting: RoundVideoTranscriptSession {
        return RoundVideoTranscriptSession(waiting: true, sawSuccess: false, automaticRetryCount: 0)
    }
}

public enum RoundVideoTranscriptSignalEffect: Equatable {
    case keepWaiting
    case restoreVideo
    case none
}

/// A failure or a finish with no success restores the video. Success waits for the
/// message update. Nothing here starts another request.
public func roundVideoTranscriptReduce(_ session: inout RoundVideoTranscriptSession, _ event: RoundVideoTranscriptSignalEvent) -> RoundVideoTranscriptSignalEffect {
    switch event {
    case .reportedSuccess:
        guard session.waiting else {
            return .none
        }
        session.sawSuccess = true
        return .keepWaiting
    case .reportedFailure, .userCancelled:
        guard session.waiting else {
            return .none
        }
        session.waiting = false
        return .restoreVideo
    case .finished:
        guard session.waiting else {
            return .none
        }
        session.waiting = false
        if session.sawSuccess {
            return .none
        }
        return .restoreVideo
    }
}
