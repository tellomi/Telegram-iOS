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
import TabBarUI
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
    let screen: TellomiFeedScreen
    if let existing = objc_getAssociatedObject(root, &tellomiFeedScreenKey) as? TellomiFeedScreen {
        screen = existing
    } else {
        screen = TellomiFeedScreen(context: context)
        objc_setAssociatedObject(root, &tellomiFeedScreenKey, screen, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
    screen.onRootNavigationVisible = { [weak root] visible, animated in
        guard let tabs = root?.rootTabController as? TabBarController else {
            return
        }
        let transition: ContainedViewLayoutTransition = animated ? .animated(duration: 0.25, curve: .easeInOut) : .immediate
        tabs.updateIsTabBarHidden(!visible, transition: transition)
    }
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
    |> map { sharedData -> TellomiTabSettings in
        return sharedData.entries[ApplicationSpecificSharedDataKeys.tellomiTabSettings]?.get(TellomiTabSettings.self) ?? .defaultSettings
    }
    |> distinctUntilChanged
    |> deliverOnMainQueue
    let disposable = signal.start(next: { [weak rootController] settings in
        guard let rootController else {
            return
        }
        tellomiRememberTabVisibility(settings)
        (rootController.rootTabController as? TabBarControllerImpl)?.tellomiHidesTabTitles = settings.hideTabTitles
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

/// Hidden Contacts tab: `openContacts` pushes a page (M2). This lookup is what
/// `getContactsController` calls, so it never creates or pushes a controller.
func tellomiResolvedContactsController(root: TelegramRootController, context: AccountContext, tabContacts: ContactsController?) -> ViewController? {
    let tabs = root.rootTabController
    let pushed = root.viewControllers.compactMap { $0 as? ContactsController }.first { $0 !== tabContacts }
    let tabVisible: Bool
    if let tabs, let tabContacts {
        tabVisible = tabs.controllers.contains(where: { $0 === tabContacts })
    } else {
        tabVisible = false
    }
    switch tellomiContactsControllerRead(
        navigationEnabled: tellomiBottomNavigationEnabled(appConfiguration: context.currentAppConfiguration.with { $0 }),
        tabBarReady: tabs != nil,
        tabVisible: tabVisible,
        pushedPageExists: pushed != nil
    ) {
    case .owned, .none:
        return nil
    case .tab:
        return tabContacts
    case .pushed:
        return pushed
    }
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
    let navigationEnabled = tellomiBottomNavigationEnabled(appConfiguration: context.currentAppConfiguration.with { $0 })
    guard let postId = tellomiFeedPostIdIfHandled(in: url, navigationEnabled: navigationEnabled) else {
        return false
    }
    let root = (context.sharedContext.mainWindow?.viewController as? TelegramRootController) ?? (navigationController as? TelegramRootController)
    guard let root else {
        return true
    }
    tellomiRevealFeedPost(root: root, context: context, postId: postId)
    return true
}
