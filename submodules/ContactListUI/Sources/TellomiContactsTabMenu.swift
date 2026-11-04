import AccountContext
import AppBundle
import ContextUI
import Display
import Foundation
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences
import UIKit

/// Long-press on the Contacts tab icon. Same menu shape as Calls (D-38).
func tellomiAppendHideContactsTabItem(_ items: inout [ContextMenuItem], context: AccountContext, presentationData: PresentationData) {
    guard tellomiBottomNavigationEnabled(appConfiguration: context.currentAppConfiguration.with { $0 }) else {
        return
    }
    let title = TellomiTabCopy.resolve(languageCode: presentationData.strings.primaryComponent.languageCode, pack: tellomiStringPack(primary: presentationData.strings.primaryComponent.dict, secondary: presentationData.strings.secondaryComponent?.dict)).hideContacts
    items.append(.action(ContextMenuActionItem(text: title, icon: { theme in
        return generateTintedImage(image: UIImage(bundleImageName: "Peer Info/HideIcon"), color: theme.contextMenu.primaryColor)
    }, action: { controller, _ in
        controller?.dismiss(completion: {
            let _ = updateTellomiTabSettingsInteractively(accountManager: context.sharedContext.accountManager, { settings in
                return settings.withUpdatedShowContactsTab(false)
            }).start()
        })
    })))
}
