import Foundation
import Postbox
import SwiftSignalKit

/// Stores the pre-login language on the account manager, the same record Settings writes.
/// An existing pack for that code is kept. A different code is stored with an empty pack at
/// version 0 so the logged-in langpack sync can fill it. Missing keys fall back to the
/// bundled English strings until then. No network.
public func tellomiStoreInterfaceLanguage(accountManager: AccountManager<TelegramAccountManagerTypes>, languageCode: String, localizedName: String, pluralizationCode: String?) -> Signal<Void, NoError> {
    let normalized = languageCode.lowercased()
    return accountManager.transaction { transaction in
        if let existing = transaction.getSharedData(SharedDataKeys.localizationSettings)?.get(LocalizationSettings.self), existing.primaryComponent.languageCode.lowercased() == normalized {
            return
        }
        let primary = LocalizationComponent(languageCode: normalized, localizedName: localizedName, localization: Localization(version: 0, entries: []), customPluralizationCode: pluralizationCode)
        transaction.updateSharedData(SharedDataKeys.localizationSettings, { _ in
            return PreferencesEntry(LocalizationSettings(primaryComponent: primary, secondaryComponent: nil))
        })
    }
}
