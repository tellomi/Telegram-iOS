import Foundation
import TelegramCore

public func momentsReportReasonCode(_ reason: ReportReason) -> String {
    switch reason {
    case .spam:
        return "spam"
    case .fake:
        return "fake"
    case .violence:
        return "violence"
    case .porno:
        return "pornography"
    case .childAbuse:
        return "child_abuse"
    case .copyright:
        return "copyright"
    case .illegalDrugs:
        return "illegal_drugs"
    case .personalDetails:
        return "personal_details"
    case .irrelevantLocation:
        return "irrelevant_location"
    case .custom:
        return "other"
    }
}
