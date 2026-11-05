import AccountContext
import Display
import Foundation
import TelegramPresentationData
import TellomiDiscover
import UIKit

func tellomiPresentDiscoverPostMenu(host: ViewController, context: AccountContext, loggedIn: Bool, configuration: TellomiDiscoverConfiguration, loader: TellomiDiscoverLoader, postId: String, post: TellomiDiscoverPost?, onReposted: @escaping (Bool) -> Void, onQuote: @escaping () -> Void) {
    guard loggedIn, let postId = tellomiDiscoverPostId(postId) else {
        return
    }
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let copy = TellomiDiscoverCopy.resolve(languageCode: presentationData.strings.primaryComponent.languageCode, pack: tellomiStringPack(primary: presentationData.strings.primaryComponent.dict, secondary: presentationData.strings.secondaryComponent?.dict))
    let sheet = ActionSheetController(presentationData: presentationData)
    var rows: [ActionSheetItem] = []
    for action in tellomiDiscoverShareActions(shareable: post?.shareable == true, reposted: post?.reposted == true) {
        let title: String
        switch action {
        case .repost:
            title = copy.repost
        case .unrepost:
            title = copy.unrepost
        case .quote:
            title = copy.quote
        case .shareInChat:
            title = copy.shareChat
        case .shareExternal:
            title = copy.shareExternal
        }
        rows.append(ActionSheetButtonItem(title: title, color: .accent, action: { [weak sheet, weak host] in
            sheet?.dismissAnimated()
            guard let host else {
                return
            }
            tellomiPerformDiscoverShare(action: action, host: host, context: context, configuration: configuration, loader: loader, postId: postId, reposted: post?.reposted == true, onReposted: onReposted, onQuote: onQuote)
        }))
    }
    rows.append(ActionSheetButtonItem(title: presentationData.strings.Report_Report, color: .accent, action: { [weak sheet, weak host] in
        sheet?.dismissAnimated()
        guard let host else {
            return
        }
        tellomiPresentDiscoverReportReasons(host: host, context: context, loggedIn: loggedIn, configuration: configuration, loader: loader, target: .post(postId))
    }))
    sheet.setItemGroups([
        ActionSheetItemGroup(items: rows),
        ActionSheetItemGroup(items: [
            ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, action: { [weak sheet] in
                sheet?.dismissAnimated()
            })
        ])
    ])
    host.present(sheet, in: .window(.root))
}

private func tellomiPerformDiscoverShare(action: TellomiDiscoverShareAction, host: ViewController, context: AccountContext, configuration: TellomiDiscoverConfiguration, loader: TellomiDiscoverLoader, postId: String, reposted: Bool, onReposted: @escaping (Bool) -> Void, onQuote: @escaping () -> Void) {
    switch action {
    case .repost, .unrepost:
        let operation: TellomiDiscoverOperation = reposted ? .unrepost(postId) : .repost(postId)
        loader.run(loggedIn: true, configuration: configuration, operation: operation) { result in
            guard case .success(.acknowledged) = result else {
                return
            }
            onReposted(!reposted)
        }
    case .quote:
        onQuote()
    case .shareInChat:
        guard let url = tellomiDiscoverShareURL(postId: postId) else {
            return
        }
        let controller = context.sharedContext.makeShareScreen(context: context, params: ShareControllerParams(subject: .url(url.absoluteString), externalShare: false, immediateExternalShare: false))
        host.present(controller, in: .window(.root))
    case .shareExternal:
        guard let url = tellomiDiscoverShareURL(postId: postId) else {
            return
        }
        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        context.sharedContext.applicationBindings.presentNativeController(activity)
    }
}
