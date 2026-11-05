import AccountContext
import Display
import Foundation
import SettingsUI
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences
import UIKit

func tellomiAppendNavigationSettingsEntry(items: inout [SettingsSection: [PeerInfoScreenItem]], context: AccountContext, presentationData: PresentationData, interaction: PeerInfoInteraction) {
    guard tellomiBottomNavigationEnabled(appConfiguration: context.currentAppConfiguration.with { $0 }) else {
        return
    }
    let title = TellomiTabCopy.resolve(languageCode: presentationData.strings.primaryComponent.languageCode, pack: tellomiStringPack(primary: presentationData.strings.primaryComponent.dict, secondary: presentationData.strings.secondaryComponent?.dict)).navigationTitle
    items[.advanced, default: []].append(PeerInfoScreenDisclosureItem(id: 7, text: title, icon: PresentationResourcesSettings.appearance, action: {
        tellomiPushSettingsPage(interaction: interaction, controller: tellomiNavigationSettingsController(context: context))
    }))
}

func tellomiPushSettingsPage(interaction: PeerInfoInteraction, controller: ViewController) {
    guard let host = interaction.getController(), let navigationController = host.navigationController as? NavigationController else {
        return
    }
    var updated = navigationController.viewControllers
    for existing in navigationController.viewControllers.reversed() {
        if existing !== host && !(existing is TabBarController) {
            updated.removeLast()
        } else {
            break
        }
    }
    updated.append(controller)
    navigationController.setViewControllers(updated, animated: true)
}
