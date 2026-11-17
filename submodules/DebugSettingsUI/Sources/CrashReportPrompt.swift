import Foundation

/// Whether the crash-log prompt is on screen, and whether the person has already
/// chosen. A pending report stays pending until Not Now, or until Send is
/// confirmed by the server. Leaving the foreground takes the prompt down without
/// that choice, and the next time the app can present it the prompt is shown
/// again. A send that fails leaves the report pending. Another update while the
/// prompt is already showing, or while a send is in flight, does not present a
/// second copy.
struct CrashReportPromptMachine: Equatable {
    enum Phase: Equatable {
        case waiting
        case showing
        case sending
        case done
    }

    private(set) var phase: Phase

    init(phase: Phase = .waiting) {
        self.phase = phase
    }

    mutating func environment(_ environment: CrashReportPromptEnvironment) -> [CrashReportPromptEffect] {
        if self.phase == .done || self.phase == .sending {
            return []
        }
        if !environment.canPresent {
            if self.phase == .showing {
                self.phase = .waiting
                return [.dismiss]
            }
            return []
        }
        if !environment.alertsEnabled || !environment.hasPending {
            return []
        }
        if self.phase == .waiting {
            self.phase = .showing
            return [.present]
        }
        return []
    }

    /// The person tapped Send. The report stays pending until the server confirms it.
    mutating func beginSend() -> [CrashReportPromptEffect] {
        if self.phase == .done {
            return []
        }
        self.phase = .sending
        return []
    }

    /// The server accepted the document. The report is no longer pending.
    mutating func sendConfirmed() -> [CrashReportPromptEffect] {
        if self.phase == .done {
            return []
        }
        self.phase = .done
        return [.markResolved]
    }

    /// The server did not accept the document. The report stays pending.
    mutating func sendFailed() -> [CrashReportPromptEffect] {
        if self.phase == .done {
            return []
        }
        self.phase = .waiting
        return []
    }

    /// The person chose Not Now. The report is no longer pending.
    mutating func decline() -> [CrashReportPromptEffect] {
        if self.phase == .done {
            return []
        }
        self.phase = .done
        return [.markResolved]
    }
}

struct CrashReportPromptEnvironment: Equatable {
    var canPresent: Bool
    var alertsEnabled: Bool
    var hasPending: Bool
}

enum CrashReportPromptEffect: Equatable {
    case present
    case dismiss
    case markResolved
}

/// What the outgoing message's flags mean for the crash log.
/// A transport acknowledgement still counts as waiting. Sent is the cleared
/// unsent flag after the server's reply. Failed leaves the log pending.
enum CrashReportDelivery: Equatable {
    case waiting
    case sent
    case failed
}

func crashReportDelivery(failed: Bool, stillSending: Bool) -> CrashReportDelivery {
    if failed {
        return .failed
    }
    if stillSending {
        return .waiting
    }
    return .sent
}

/// `help.getAppConfig` key `tellomi_crash_report_bot`. Empty or unusable values use the built-in name.
let crashReportBotConfigKey = "tellomi_crash_report_bot"
let crashReportBotFallbackUsername = "TellomiBot"

func crashReportBotUsername(configured: String?) -> String {
    let trimmed = configured?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let name = trimmed.hasPrefix("@") ? String(trimmed.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines) : trimmed
    if crashReportBotUsernameIsAcceptable(name) {
        return name
    }
    return crashReportBotFallbackUsername
}

/// A zip document plus the caption the collector reads (`app=` and `device=`).
struct CrashReportDocument: Equatable {
    var fileName: String
    var mimeType: String
    var caption: String
}

func crashReportDocument(applicationVersion: String, deviceType: String) -> CrashReportDocument {
    let version = crashReportDocumentToken(applicationVersion, fallback: "0")
    let device = crashReportDocumentToken(deviceType, fallback: "iOS")
    return CrashReportDocument(
        fileName: "Tellomi-iOS-\(version)-crash.zip",
        mimeType: "application/zip",
        caption: "app=\(version) device=\(device)"
    )
}

private func crashReportBotUsernameIsAcceptable(_ name: String) -> Bool {
    let characters = Array(name)
    if characters.count < 4 || characters.count > 32 || name.hasPrefix("_") || name.hasSuffix("_") {
        return false
    }
    for (index, character) in characters.enumerated() {
        guard let ascii = character.asciiValue else {
            return false
        }
        let isLetter = (ascii >= 65 && ascii <= 90) || (ascii >= 97 && ascii <= 122)
        let isDigit = ascii >= 48 && ascii <= 57
        if index == 0 {
            if !isLetter {
                return false
            }
        } else if !isLetter && !isDigit && character != "_" {
            return false
        }
    }
    return true
}

private func crashReportDocumentToken(_ raw: String, fallback: String) -> String {
    let trimmed = raw
        .replacingOccurrences(of: "\n", with: " ")
        .replacingOccurrences(of: "\r", with: " ")
        .replacingOccurrences(of: "/", with: "-")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
        return fallback
    }
    return trimmed
}
