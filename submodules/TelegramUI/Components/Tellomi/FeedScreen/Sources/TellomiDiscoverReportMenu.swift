import AccountContext
import Display
import Foundation
import PeerReportScreen
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import TellomiDiscover
import UIKit
import UndoUI

func tellomiDiscoverReportReasonToken(_ reason: ReportReason) -> String {
    switch reason {
    case .spam:
        return "spam"
    case .violence:
        return "violence"
    case .porno:
        return "pornography"
    case .childAbuse:
        return "childAbuse"
    case .illegalDrugs:
        return "illegalDrugs"
    case .personalDetails:
        return "personalDetails"
    case .custom:
        return "other"
    default:
        return ""
    }
}

/// The "…" menu. Report opens Telegram's reason sheet. The chosen id is posted to
/// `POST /v1/feed/reports`. A logged-out session does not build that request.
func tellomiPresentDiscoverReport(host: ViewController, context: AccountContext, loggedIn: Bool, configuration: TellomiDiscoverConfiguration, loader: TellomiDiscoverLoader, target: TellomiDiscoverReportTarget) {
    guard loggedIn else {
        return
    }
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let sheet = ActionSheetController(presentationData: presentationData)
    sheet.setItemGroups([
        ActionSheetItemGroup(items: [
            ActionSheetButtonItem(title: presentationData.strings.Report_Report, color: .accent, action: { [weak sheet, weak host] in
                sheet?.dismissAnimated()
                guard let host else {
                    return
                }
                tellomiPresentDiscoverReportReasons(host: host, context: context, loggedIn: loggedIn, configuration: configuration, loader: loader, target: target)
            })
        ]),
        ActionSheetItemGroup(items: [
            ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, action: { [weak sheet] in
                sheet?.dismissAnimated()
            })
        ])
    ])
    host.present(sheet, in: .window(.root))
}

private func tellomiPresentDiscoverReportReasons(host: ViewController, context: AccountContext, loggedIn: Bool, configuration: TellomiDiscoverConfiguration, loader: TellomiDiscoverLoader, target: TellomiDiscoverReportTarget) {
    guard loggedIn else {
        return
    }
    let options: [PeerReportOption] = [.spam, .violence, .pornography, .childAbuse, .illegalDrugs, .personalDetails, .other]
    let controller = peerReportOptionsController(context: context, subject: .peer(context.account.peerId), options: options, passthrough: true, present: { [weak host] controller, arguments in
        host?.present(controller, in: .window(.root), with: arguments)
    }, push: { [weak host] controller in
        host?.push(controller)
    }, completion: { _, _ in
    }, submitLocally: { reason, detail in
        guard loggedIn else {
            return
        }
        let option = tellomiDiscoverReportReasonToken(reason)
        guard tellomiDiscoverReportOptionId(option) != nil else {
            return
        }
        loader.run(loggedIn: true, configuration: configuration, operation: .report(target: target, option: option, detail: detail)) { result in
            Queue.mainQueue().async {
                guard case .success(.reported) = result else {
                    return
                }
                let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                host.present(UndoOverlayController(presentationData: presentationData, content: .emoji(name: "PoliceCar", text: presentationData.strings.Report_Succeed), elevatedLayout: false, action: { _ in return false }), in: .current)
            }
        }
    })
    host.present(controller, in: .window(.root))
}
