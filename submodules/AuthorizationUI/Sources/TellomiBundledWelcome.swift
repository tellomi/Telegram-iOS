import Foundation
import TelegramCore
import TelegramPresentationData

func tellomiBundledStringTable(languageCode: String) -> [String: String]? {
    let code = tellomiCanonicalBuiltinLanguage(languageCode)
    guard code != "en" else {
        return nil
    }
    guard let path = Bundle.main.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: code),
          let table = NSDictionary(contentsOfFile: path) as? [String: String],
          !table.isEmpty else {
        return nil
    }
    return table
}

func tellomiBundledPresentationStrings(languageCode: String) -> PresentationStrings {
    let code = tellomiCanonicalBuiltinLanguage(languageCode)
    guard let table = tellomiBundledStringTable(languageCode: code) else {
        return defaultPresentationStrings
    }
    let name = code == "zh-Hant" ? "繁體中文" : "简体中文"
    return PresentationStrings(primaryComponent: PresentationStrings.Component(languageCode: code, localizedName: name, pluralizationRulesCode: "zh", dict: table), secondaryComponent: defaultPresentationStrings.primaryComponent, groupingSeparator: "")
}

struct TellomiWelcomeCopy {
    var headlines: [String]
    var descriptions: [String]
    var startButton: String
}

/// Welcome pages from the bundled `Localizable.strings`, in the order RMIntro draws them.
/// No server langpack is required. Missing keys use the English bundle.
func tellomiWelcomeCopy(languageCode: String) -> TellomiWelcomeCopy {
    let localized = tellomiBundledStringTable(languageCode: languageCode) ?? [:]
    let englishPath = Bundle.main.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: "en")
    let english = (englishPath.flatMap { NSDictionary(contentsOfFile: $0) as? [String: String] }) ?? [:]
    func value(_ key: String) -> String {
        if let text = localized[key], !text.isEmpty {
            return text
        }
        if let text = english[key], !text.isEmpty {
            return text
        }
        return key
    }
    let order = [1, 2, 6, 3, 4, 5]
    return TellomiWelcomeCopy(
        headlines: order.map { value("Tour.Title\($0)") },
        descriptions: order.map { value("Tour.Text\($0)") },
        startButton: value("Tour.StartButton")
    )
}
