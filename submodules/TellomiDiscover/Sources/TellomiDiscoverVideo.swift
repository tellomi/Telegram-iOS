import Foundation

/// Discover video cap (D-41). A clip longer than 60 seconds is not kept and is
/// not uploaded. Exactly 60 seconds is allowed. Nothing here trims a file.
///
/// `POST /v1/feed/posts` has no media field, and this client has no media route.
/// `beforeUpload` therefore returns `notUploaded` for a clip that is already
/// within the cap, so a text post is not sent in its place.
///
/// A gallery row that stores duration as whole seconds (milliseconds / 1000)
/// is a coarser check. The compose picker reads milliseconds and does not use
/// `selectPhotoEntrySeconds`.
public enum TellomiDiscoverVideo {
    /// Inclusive. 60_000 is allowed. 60_001 is not.
    public static let maxDurationMs: Int64 = 60_000
    public static let maxSeconds = 60

    public enum Decision: Equatable {
        case none
        case accept
        case tooLong
        case unknown
        case notUploaded
    }

    public enum PublishGate: Equatable {
        /// No clip is attached. The text post may be sent.
        case sendText
        /// A length read is in flight. Do not send.
        case wait
        /// A clip is attached. Do not send, and do not add media fields.
        case hold(Decision)
    }

    public struct StatusText: Equatable {
        public var text: String
        public var isError: Bool

        public init(text: String, isError: Bool) {
            self.text = text
            self.isError = isError
        }
    }

    /// Selection gate. `durationMs <= 0` means the length could not be read.
    public static func select(durationMs: Int64) -> Decision {
        if durationMs <= 0 {
            return .unknown
        }
        if durationMs > self.maxDurationMs {
            return .tooLong
        }
        return .accept
    }

    /// Hard limit immediately before upload. Over 60 seconds or an unknown
    /// length is rejected. A length inside the cap is `notUploaded` until the
    /// engine accepts video bytes.
    public static func beforeUpload(durationMs: Int64) -> Decision {
        let selected = self.select(durationMs: durationMs)
        if selected != .accept {
            return selected
        }
        return .notUploaded
    }

    /// What a publish tap does. An attached clip never falls through to a text post.
    public static func publishGate(hasVideo: Bool, busy: Bool, durationMs: Int64) -> PublishGate {
        if busy {
            return .wait
        }
        guard hasVideo else {
            return .sendText
        }
        return .hold(self.beforeUpload(durationMs: durationMs))
    }

    /// A fresh read wins. A failed re-read keeps the length already accepted.
    public static func measuredDuration(freshMs: Int64, storedMs: Int64) -> Int64 {
        return freshMs > 0 ? freshMs : storedMs
    }

    /// Whole seconds, as a gallery row stores them. 60 is inside the cap. 61 is
    /// not. Zero is unknown. Coarser than `select`: the remainder under one
    /// second is already gone. The compose picker does not call this.
    public static func selectPhotoEntrySeconds(_ seconds: Int) -> Decision {
        if seconds <= 0 {
            return .unknown
        }
        if seconds > self.maxSeconds {
            return .tooLong
        }
        return self.select(durationMs: Int64(seconds) * 1000)
    }

    /// Metadata duration string, in milliseconds. Blank or non-positive is 0.
    /// A fractional string truncates toward zero (`60000.9` is `60000`).
    public static func parseMillis(_ raw: String?) -> Int64 {
        guard let raw else {
            return 0
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return 0
        }
        if trimmed.contains(".") {
            guard let value = Double(trimmed), value > 0, value <= Double(Int64.max) else {
                return 0
            }
            return Int64(value)
        }
        guard let value = Int64(trimmed), value > 0 else {
            return 0
        }
        return value
    }

    /// CMTime-shaped length, in milliseconds, truncated toward zero. An invalid,
    /// non-numeric, or non-positive time is 0. A value that does not fit is
    /// treated as longer than the cap.
    public static func milliseconds(timeValue: Int64, timescale: Int32, numeric: Bool) -> Int64 {
        guard numeric, timescale > 0, timeValue > 0 else {
            return 0
        }
        let (product, overflow) = timeValue.multipliedReportingOverflow(by: 1000)
        if overflow {
            return self.maxDurationMs + 1
        }
        return product / Int64(timescale)
    }

    /// `m:ss` for a selected clip. A positive length under one second is `0:01`.
    public static func clock(_ durationMs: Int64) -> String {
        var total = durationMs / 1000
        if durationMs > 0 && total == 0 {
            total = 1
        }
        if total < 0 {
            total = 0
        }
        let minutes = total / 60
        let seconds = total % 60
        if seconds < 10 {
            return "\(minutes):0\(seconds)"
        }
        return "\(minutes):\(seconds)"
    }

    /// The bundled templates use `%s`, matching the shared pack. `%@` is accepted
    /// so an iOS-shaped override still substitutes. `%s` is not passed to
    /// `String(format:)`.
    public static func selectedLabel(template: String, clock: String) -> String {
        if let range = template.range(of: "%s") {
            return template.replacingCharacters(in: range, with: clock)
        }
        if template.contains("%@") {
            return String(format: template, clock)
        }
        return template + clock
    }

    /// The line under the picker. A kept clip always includes the not-uploaded
    /// explanation. Too-long and unreadable lengths are errors. Nothing is trimmed.
    public static func statusText(busy: Bool, decision: Decision, hasVideo: Bool, durationMs: Int64, copy: TellomiDiscoverCopy) -> StatusText? {
        if busy {
            return StatusText(text: copy.videoReading, isError: false)
        }
        switch decision {
        case .tooLong:
            return StatusText(text: copy.videoTooLong, isError: true)
        case .unknown:
            return StatusText(text: copy.videoUnknown, isError: true)
        case .accept, .notUploaded:
            guard hasVideo else {
                return nil
            }
            let selected = self.selectedLabel(template: copy.videoSelected, clock: self.clock(durationMs))
            return StatusText(text: selected + "\n" + copy.videoNotUploaded, isError: false)
        case .none:
            return nil
        }
    }
}
