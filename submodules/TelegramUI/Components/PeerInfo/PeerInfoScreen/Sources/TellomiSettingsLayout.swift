import AccountContext
import Display
import Foundation
import PresentationDataUtils
import SettingsUI
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences
import UIKit

func tellomiSettingsHomeItems(data: PeerInfoScreenData?, context: AccountContext, presentationData: PresentationData, interaction: PeerInfoInteraction, isExpanded: Bool) -> [(AnyHashable, [PeerInfoScreenItem])] {
    let source = settingsItems(data: data, context: context, presentationData: presentationData, interaction: interaction, isExpanded: isExpanded)
    let copy = TellomiSettingsCopy.resolve(languageCode: presentationData.strings.primaryComponent.languageCode, pack: tellomiStringPack(primary: presentationData.strings.primaryComponent.dict, secondary: presentationData.strings.secondaryComponent?.dict))
    let includeNavigation = tellomiBottomNavigationEnabled(appConfiguration: context.currentAppConfiguration.with { $0 })
    var result: [(AnyHashable, [PeerInfoScreenItem])] = []
    let notices = tellomiSettingsSectionItems(source, .phone)
    if !notices.isEmpty {
        result.append((SettingsSection.phone, notices))
    }
    let accounts = tellomiSettingsSectionItems(source, .accounts)
    if !accounts.isEmpty {
        result.append((SettingsSection.accounts, accounts))
    }
    for (group, rows) in tellomiSettingsHomeLayout(includeNavigation: includeNavigation) {
        var items: [PeerInfoScreenItem] = [
            PeerInfoScreenHeaderItem(id: "tellomi.header.\(group.rawValue)", text: copy.title(for: group))
        ]
        for row in rows {
            items.append(tellomiSettingsHomeRow(row, source: source, context: context, presentationData: presentationData, interaction: interaction, copy: copy))
        }
        if group == .general, let proxy = tellomiSettingsDisclosure(source, .proxy, id: 0) {
            let proxyItem = tellomiRelocatedDisclosure(proxy, id: "tellomi.proxy")
            if let moreIndex = items.firstIndex(where: { $0.id == AnyHashable("tellomi.more") }) {
                items.insert(proxyItem, at: moreIndex)
            } else {
                items.append(proxyItem)
            }
        }
        result.append((group, items))
    }
    return result
}

private func tellomiSettingsSectionItems(_ sections: [(AnyHashable, [PeerInfoScreenItem])], _ section: SettingsSection) -> [PeerInfoScreenItem] {
    for (key, items) in sections {
        if let key = key as? SettingsSection, key == section {
            return items
        }
    }
    return []
}

private func tellomiSettingsDisclosure(_ sections: [(AnyHashable, [PeerInfoScreenItem])], _ section: SettingsSection, id: Int) -> PeerInfoScreenDisclosureItem? {
    for item in tellomiSettingsSectionItems(sections, section) {
        if let item = item as? PeerInfoScreenDisclosureItem, item.id == AnyHashable(id) {
            return item
        }
    }
    return nil
}

private func tellomiRelocatedDisclosure(_ item: PeerInfoScreenDisclosureItem, id: String, text: String? = nil) -> PeerInfoScreenDisclosureItem {
    return PeerInfoScreenDisclosureItem(id: id, label: item.label, additionalBadgeLabel: item.additionalBadgeLabel, additionalBadgeIcon: item.additionalBadgeIcon, text: text ?? item.text, icon: item.icon, iconSignal: item.iconSignal, hasArrow: item.hasArrow, action: item.action)
}

private func tellomiDisclosure(id: String, text: String, icon: UIImage?, label: PeerInfoScreenDisclosureItem.Label = .none, action: @escaping () -> Void) -> PeerInfoScreenDisclosureItem {
    return PeerInfoScreenDisclosureItem(id: id, label: label, text: text, icon: icon, action: action)
}

private func tellomiSettingsHomeRow(_ row: TellomiSettingsHomeRow, source: [(AnyHashable, [PeerInfoScreenItem])], context: AccountContext, presentationData: PresentationData, interaction: PeerInfoInteraction, copy: TellomiSettingsCopy) -> PeerInfoScreenItem {
    switch row {
    case .profile:
        if let item = tellomiSettingsDisclosure(source, .myProfile, id: 0) {
            return tellomiRelocatedDisclosure(item, id: "tellomi.profile", text: copy.profile)
        }
        return tellomiDisclosure(id: "tellomi.profile", text: copy.profile, icon: PresentationResourcesSettings.myProfile, action: {
            interaction.openSettings(.profile)
        })
    case .bindings:
        return tellomiDisclosure(id: "tellomi.bindings", text: copy.bindings, icon: PresentationResourcesSettings.email, action: {
            tellomiPresentBindings(source: source, context: context, interaction: interaction, copy: copy)
        })
    case .privacy:
        if let item = tellomiSettingsDisclosure(source, .advanced, id: 1) {
            return tellomiRelocatedDisclosure(item, id: "tellomi.privacy", text: copy.privacy)
        }
        return tellomiDisclosure(id: "tellomi.privacy", text: copy.privacy, icon: PresentationResourcesSettings.security, action: {
            interaction.openSettings(.privacyAndSecurity)
        })
    case .devices:
        if let item = tellomiSettingsDisclosure(source, .shortcuts, id: 3) {
            return tellomiRelocatedDisclosure(item, id: "tellomi.devices", text: copy.devices)
        }
        return tellomiDisclosure(id: "tellomi.devices", text: copy.devices, icon: PresentationResourcesSettings.devices, action: {
            interaction.openSettings(.devices)
        })
    case .notifications:
        if let item = tellomiSettingsDisclosure(source, .advanced, id: 0) {
            return tellomiRelocatedDisclosure(item, id: "tellomi.notifications", text: copy.notifications)
        }
        return tellomiDisclosure(id: "tellomi.notifications", text: copy.notifications, icon: PresentationResourcesSettings.notifications, action: {
            interaction.openSettings(.notificationsAndSounds)
        })
    case .appearance:
        if let item = tellomiSettingsDisclosure(source, .advanced, id: 3) {
            return tellomiRelocatedDisclosure(item, id: "tellomi.appearance", text: copy.appearance)
        }
        return tellomiDisclosure(id: "tellomi.appearance", text: copy.appearance, icon: PresentationResourcesSettings.appearance, action: {
            interaction.openSettings(.appearance)
        })
    case .chatStorage:
        if let item = tellomiSettingsDisclosure(source, .advanced, id: 2) {
            return tellomiRelocatedDisclosure(item, id: "tellomi.chatStorage", text: copy.chatStorage)
        }
        return tellomiDisclosure(id: "tellomi.chatStorage", text: copy.chatStorage, icon: PresentationResourcesSettings.dataAndStorage, action: {
            interaction.openSettings(.dataAndStorage)
        })
    case .language:
        if let item = tellomiSettingsDisclosure(source, .advanced, id: 4) {
            return tellomiRelocatedDisclosure(item, id: "tellomi.language", text: copy.language)
        }
        return tellomiDisclosure(id: "tellomi.language", text: copy.language, icon: PresentationResourcesSettings.language, action: {
            interaction.openSettings(.language)
        })
    case .navigation:
        if let item = tellomiSettingsDisclosure(source, .advanced, id: 7) {
            return tellomiRelocatedDisclosure(item, id: "tellomi.navigation")
        }
        let title = TellomiTabCopy.resolve(languageCode: presentationData.strings.primaryComponent.languageCode, pack: tellomiStringPack(primary: presentationData.strings.primaryComponent.dict, secondary: presentationData.strings.secondaryComponent?.dict)).navigationTitle
        return tellomiDisclosure(id: "tellomi.navigation", text: title, icon: PresentationResourcesSettings.appearance, action: {
            tellomiPushSettingsPage(interaction: interaction, controller: tellomiNavigationSettingsController(context: context))
        })
    case .more:
        return tellomiDisclosure(id: "tellomi.more", text: copy.more, icon: PresentationResourcesSettings.dataAndStorage, action: {
            tellomiPresentMore(source: source, context: context, presentationData: presentationData, interaction: interaction, copy: copy)
        })
    case .helpCenter:
        return tellomiDisclosure(id: "tellomi.help", text: copy.helpCenter, icon: PresentationResourcesSettings.faq, action: {
            tellomiOpenSettingsURL(context: context, interaction: interaction, url: TellomiSettingsURLs.helpCenter)
        })
    case .support:
        return tellomiDisclosure(id: "tellomi.support", text: copy.support, icon: PresentationResourcesSettings.support, action: {
            tellomiOpenSupportChat(context: context, interaction: interaction)
        })
    case .legal:
        return tellomiDisclosure(id: "tellomi.legal", text: copy.legal, icon: PresentationResourcesSettings.faq, action: {
            tellomiPresentLegal(context: context, interaction: interaction, copy: copy)
        })
    case .about:
        return tellomiDisclosure(id: "tellomi.about", text: copy.about, icon: PresentationResourcesSettings.faq, action: {
            tellomiPushSettingsPage(interaction: interaction, controller: tellomiAboutController(context: context))
        })
    }
}

private func tellomiPresentBindings(source: [(AnyHashable, [PeerInfoScreenItem])], context: AccountContext, interaction: PeerInfoInteraction, copy: TellomiSettingsCopy) {
    var links: [TellomiSettingsLink] = []
    var actions: [String: () -> Void] = [:]
    func add(_ id: String, _ title: String, label: String = "", destructive: Bool = false, _ action: @escaping () -> Void) {
        links.append(TellomiSettingsLink(id: id, title: title, label: label, destructive: destructive))
        actions[id] = action
    }
    for item in tellomiSettingsSectionItems(source, .edit) {
        if let item = item as? PeerInfoScreenActionItem, item.id != AnyHashable(3) {
            let id = "edit-\(item.id)"
            add(id, item.text) {
                item.action?()
            }
        }
    }
    add("phone", copy.phone) {
        interaction.openSettings(.phoneNumber)
    }
    add("email", copy.email) {
        interaction.openSettings(.loginEmail)
    }
    add("username", copy.username) {
        interaction.openSettings(.username)
    }
    add("addAccount", copy.addAccount) {
        interaction.openSettings(.addAccount)
    }
    add("logout", copy.logout, destructive: true) {
        interaction.openSettings(.logout)
    }
    tellomiPushSettingsPage(interaction: interaction, controller: tellomiSettingsLinksController(context: context, title: copy.bindings, links: links, open: { id in
        actions[id]?()
    }))
}

private func tellomiPresentMore(source: [(AnyHashable, [PeerInfoScreenItem])], context: AccountContext, presentationData: PresentationData, interaction: PeerInfoInteraction, copy: TellomiSettingsCopy) {
    var links: [TellomiSettingsLink] = []
    var actions: [String: () -> Void] = [:]
    func add(_ id: String, _ title: String, label: String = "", _ action: @escaping () -> Void) {
        links.append(TellomiSettingsLink(id: id, title: title, label: label))
        actions[id] = action
    }
    for row in TellomiSettingsSecondaryRow.allCases {
        switch row {
        case .savedMessages:
            add(row.rawValue, presentationData.strings.Settings_SavedMessages) {
                interaction.openSettings(.savedMessages)
            }
        case .recentCalls:
            add(row.rawValue, presentationData.strings.CallSettings_RecentCalls) {
                interaction.openSettings(.recentCalls)
            }
        case .chatFolders:
            add(row.rawValue, presentationData.strings.Settings_ChatFolders) {
                interaction.openSettings(.chatFolders)
            }
        case .powerSaving:
            let item = tellomiSettingsDisclosure(source, .advanced, id: 6)
            add(row.rawValue, item?.text ?? presentationData.strings.Settings_PowerSaving, label: item?.label.text ?? "") {
                interaction.openSettings(.powerSaving)
            }
        case .openSourceLicenses:
            let item = tellomiSettingsDisclosure(source, .support, id: 3)
            add(row.rawValue, item?.text ?? copy.openSource) {
                if let action = item?.action {
                    action()
                } else {
                    interaction.openSettings(.openSourceLicenses)
                }
            }
        }
    }
    if let passport = tellomiSettingsDisclosure(source, .extra, id: 0), passport.text == presentationData.strings.Settings_Passport {
        add("passport", passport.text) {
            passport.action?()
        }
    }
    for item in tellomiSettingsSectionItems(source, .payment) {
        if let item = item as? PeerInfoScreenDisclosureItem {
            let id = "payment-\(item.id)"
            add(id, item.text, label: item.label.text) {
                item.action?()
            }
        }
    }
    for item in tellomiSettingsSectionItems(source, .apps) {
        if let item = item as? PeerInfoScreenDisclosureItem {
            let id = "app-\(item.id)"
            add(id, item.text, label: item.label.text) {
                item.action?()
            }
        }
    }
    if let wallet = tellomiSettingsDisclosure(source, .wallet, id: 0) {
        add("wallet", wallet.text, label: wallet.label.text) {
            wallet.action?()
        }
    }
    tellomiPushSettingsPage(interaction: interaction, controller: tellomiSettingsLinksController(context: context, title: copy.more, links: links, open: { id in
        actions[id]?()
    }))
}

private func tellomiPresentLegal(context: AccountContext, interaction: PeerInfoInteraction, copy: TellomiSettingsCopy) {
    let links = [
        TellomiSettingsLink(id: "terms", title: copy.terms),
        TellomiSettingsLink(id: "privacy", title: copy.privacyPolicy)
    ]
    tellomiPushSettingsPage(interaction: interaction, controller: tellomiSettingsLinksController(context: context, title: copy.legal, links: links, open: { id in
        let url = id == "privacy" ? TellomiSettingsURLs.privacy : TellomiSettingsURLs.terms
        tellomiOpenSettingsURL(context: context, interaction: interaction, url: url)
    }))
}

private func tellomiOpenSettingsURL(context: AccountContext, interaction: PeerInfoInteraction, url: String) {
    guard let controller = interaction.getController() else {
        return
    }
    context.sharedContext.openExternalUrl(context: context, urlContext: .generic, url: url, forceExternal: true, presentationData: context.sharedContext.currentPresentationData.with { $0 }, navigationController: controller.navigationController as? NavigationController, dismissInput: {})
}

private func tellomiOpenSupportChat(context: AccountContext, interaction: PeerInfoInteraction) {
    guard let navigationController = interaction.getController()?.navigationController as? NavigationController else {
        return
    }
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let copy = TellomiSettingsCopy.resolve(languageCode: presentationData.strings.primaryComponent.languageCode, pack: tellomiStringPack(primary: presentationData.strings.primaryComponent.dict, secondary: presentationData.strings.secondaryComponent?.dict))
    let _ = (context.engine.peers.supportPeerId()
    |> take(1)
    |> deliverOnMainQueue).startStandalone(next: { peerId in
        if let peerId {
            navigationController.pushViewController(context.sharedContext.makeChatController(context: context, chatLocation: .peer(id: peerId), subject: nil, botStart: nil, mode: .standard(.default), params: nil))
            return
        }
        guard let controller = interaction.getController() else {
            return
        }
        controller.present(textAlertController(context: context, title: nil, text: copy.supportUnavailable, actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]), in: .window(.root))
    })
}
