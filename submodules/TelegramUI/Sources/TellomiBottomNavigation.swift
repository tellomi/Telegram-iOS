import AccountContext
import CallListUI
import ContactListUI
import Display
import Foundation
import NewsScreen
import ObjectiveC
import SwiftSignalKit
import TellomiFeedScreen
import TelegramCore
import TelegramUIPreferences
import UIKit

private var tellomiFeedScreenKey: UInt8 = 0
private var tellomiTabObservationKey: UInt8 = 0

private final class TellomiTabObservationBox: NSObject {
    let disposable: Disposable

    init(_ disposable: Disposable) {
        self.disposable = disposable
    }
}

func tellomiFeedScreen(root: TelegramRootController, context: AccountContext) -> TellomiFeedScreen {
    if let existing = objc_getAssociatedObject(root, &tellomiFeedScreenKey) as? TellomiFeedScreen {
        return existing
    }
    let screen = TellomiFeedScreen(context: context)
    objc_setAssociatedObject(root, &tellomiFeedScreenKey, screen, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    return screen
}

/// Fills the bar in product order, without Settings. The caller appends Settings last.
/// Returns false when the kill switch is on so the upstream appends run.
func tellomiAppendRootTabs(_ controllers: inout [ViewController], root: TelegramRootController, context: AccountContext, contacts: ContactsController, calls: CallListController, chats: ChatListController, news: NewsScreen?, showCallsTab: Bool, showNewsTab: Bool) -> Bool {
    guard tellomiBottomNavigationEnabled(appConfiguration: context.currentAppConfiguration.with { $0 }) else {
        return false
    }
    let visibility = tellomiEffectiveTabVisibility()
    let order = tellomiRootTabOrder(showFeedTab: visibility.showFeedTab, showCallsTab: showCallsTab, showContactsTab: visibility.showContactsTab, showNewsTab: showNewsTab && news != nil)
    let feed = tellomiFeedScreen(root: root, context: context)
    for tab in order {
        switch tab {
        case .feed:
            controllers.append(feed)
        case .chats:
            controllers.append(chats)
        case .calls:
            controllers.append(calls)
        case .contacts:
            controllers.append(contacts)
        case .news:
            if let news {
                controllers.append(news)
            }
        case .settings:
            break
        }
    }
    return true
}

func tellomiStartTabObservation(context: AccountContext, rootController: TelegramRootController, showCallsTab: @escaping () -> Bool, showNewsTab: @escaping () -> Bool) {
    guard tellomiBottomNavigationEnabled(appConfiguration: context.currentAppConfiguration.with { $0 }) else {
        return
    }
    let signal = context.sharedContext.accountManager.sharedData(keys: [ApplicationSpecificSharedDataKeys.tellomiTabSettings])
    |> map { sharedData -> (Bool, Bool) in
        let settings = sharedData.entries[ApplicationSpecificSharedDataKeys.tellomiTabSettings]?.get(TellomiTabSettings.self) ?? .defaultSettings
        return (settings.showFeedTab, settings.showContactsTab)
    }
    |> distinctUntilChanged
    |> deliverOnMainQueue
    let disposable = signal.start(next: { [weak rootController] visibility in
        guard let rootController else {
            return
        }
        tellomiRememberTabVisibility(TellomiTabSettings(showFeedTab: visibility.0, showContactsTab: visibility.1))
        rootController.updateRootControllers(showCallsTab: showCallsTab(), showNewsTab: showNewsTab())
    })
    objc_setAssociatedObject(rootController, &tellomiTabObservationKey, TellomiTabObservationBox(disposable), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
}

func tellomiStopTabObservation(rootController: TelegramRootController) {
    if let box = objc_getAssociatedObject(rootController, &tellomiTabObservationKey) as? TellomiTabObservationBox {
        box.disposable.dispose()
    }
    objc_setAssociatedObject(rootController, &tellomiTabObservationKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
}

/// Hidden Contacts tab: other entry points push a contacts page (M2). The tab instance stays off the bar.
func tellomiResolvedContactsController(root: TelegramRootController, context: AccountContext, tabContacts: ContactsController?) -> ViewController? {
    guard tellomiBottomNavigationEnabled(appConfiguration: context.currentAppConfiguration.with { $0 }) else {
        return nil
    }
    guard let tabs = root.rootTabController else {
        return tabContacts
    }
    if let tabContacts, tabs.controllers.contains(where: { $0 === tabContacts }) {
        return tabContacts
    }
    if let existing = root.viewControllers.compactMap({ $0 as? ContactsController }).first(where: { $0 !== tabContacts }) {
        return existing
    }
    let controller = ContactsController(context: context)
    root.pushViewController(controller, animated: true)
    return controller
}

func tellomiOpenContacts(root: TelegramRootController, context: AccountContext) -> Bool {
    guard tellomiBottomNavigationEnabled(appConfiguration: context.currentAppConfiguration.with { $0 }) else {
        return false
    }
    guard let tabs = root.rootTabController else {
        return false
    }
    root.popToRoot(animated: false)
    if let tabContacts = root.contactsController, let index = tabs.controllers.firstIndex(where: { $0 === tabContacts }) {
        tabs.selectedIndex = index
        return true
    }
    if root.viewControllers.contains(where: { ($0 as? ContactsController) != nil && $0 !== root.contactsController }) {
        return true
    }
    root.pushViewController(ContactsController(context: context), animated: true)
    return true
}

func tellomiRevealFeedPost(root: TelegramRootController, context: AccountContext, postId: String) {
    tellomiSetShowFeedTab(true)
    let _ = updateTellomiTabSettingsInteractively(accountManager: context.sharedContext.accountManager, { settings in
        return settings.withUpdatedShowFeedTab(true)
    }).start()
    let showCallsTab = root.rootTabController?.controllers.contains(where: { $0 is CallListController }) ?? false
    let showNewsTab = root.rootTabController?.controllers.contains(where: { $0 is NewsScreen }) ?? false
    root.updateRootControllers(showCallsTab: showCallsTab, showNewsTab: showNewsTab)
    root.popToRoot(animated: false)
    guard let tabs = root.rootTabController, let index = tabs.controllers.firstIndex(where: { $0 is TellomiFeedScreen }) else {
        return
    }
    tabs.selectedIndex = index
    (tabs.controllers[index] as? TellomiFeedScreen)?.openPost(id: postId)
}

func tellomiHandleFeedPostLink(url: URL, context: AccountContext, navigationController: NavigationController?) -> Bool {
    guard let postId = tellomiFeedPostId(in: url) else {
        return false
    }
    guard tellomiBottomNavigationEnabled(appConfiguration: context.currentAppConfiguration.with { $0 }) else {
        return true
    }
    let root = (context.sharedContext.mainWindow?.viewController as? TelegramRootController) ?? (navigationController as? TelegramRootController)
    guard let root else {
        return true
    }
    tellomiRevealFeedPost(root: root, context: context, postId: postId)
    return true
}
