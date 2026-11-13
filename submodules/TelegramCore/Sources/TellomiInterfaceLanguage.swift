import Foundation
import Postbox
import SwiftSignalKit

/// Stores a language code with an empty pack. Do not use this to switch language.
/// An empty version-0 pack makes every missing key fall back to bundled English, and
/// `langpack.getDifference` is what fills it only after login. The login picker downloads
/// the pack with `downloadAndApplyLocalization` instead (`langpack.getLangPack`).
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
