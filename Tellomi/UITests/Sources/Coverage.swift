import Foundation

/// Backlog ids each check reports. `tellomi_ui_results.py` reads these arrays.
/// An id is `pass` only when that check saw the element do what the row says.
enum Coverage {
    static let phoneEntry: [String] = [
        "I-LOGIN-191",
    ]

    static let phoneField: [String] = [
        "I-LOGIN-067",
        "I-LOGIN-068",
        "I-LOGIN-121",
        "I-LOGIN-155",
        "I-LOGIN-167",
    ]

    static let closedLoginMethods: [String] = [
        "I-LOGIN-114",
        "I-LOGIN-118",
        "I-LOGIN-119",
        "I-LOGIN-122",
        "I-LOGIN-123",
        "I-LOGIN-156",
        "I-LOGIN-163",
    ]

    static let codeFlow: [String] = [
        "I-LOGIN-004",
        "I-LOGIN-116",
        "I-LOGIN-173",
        "I-LOGIN-174",
        "I-LOGIN-212",
        "I-LOGIN-222",
    ]

    static let brand: [String] = [
        "I-IDX-BRAND-004",
    ]

    static let tabsAndSettings: [String] = [
        "I-IDX-SETTINGS-001",
        "I-SETTINGS-473",
        "I-SETTINGS-475",
        "I-SETTINGS-476",
        "I-SETTINGS-481",
        "I-SETTINGS-482",
        "I-SETTINGS-484",
        "I-SETTINGS-486",
        "I-SETTINGS-487",
        "I-SETTINGS-488",
        "I-SETTINGS-493",
        "I-SETTINGS-496",
        "I-SETTINGS-497",
        "I-SETTINGS-501",
        "I-SETTINGS-503",
        "I-SETTINGS-508",
    ]

    static let navigationToggles: [String] = [
        "I-SETTINGS-448",
        "I-SETTINGS-449",
        "I-SETTINGS-450",
    ]

    static let legalLinks: [String] = [
        "I-IDX-SETTINGS-016",
        "I-SETTINGS-502",
        "I-SETTINGS-507",
    ]

    static let premiumHidden: [String] = [
        "I-PREMIUM-280",
        "I-PREMIUM-281",
        "I-PREMIUM-282",
        "I-PREMIUM-284",
        "I-PREMIUM-285",
        "I-PREMIUM-286",
        "I-PREMIUM-287",
        "I-PREMIUM-288",
        "I-PREMIUM-289",
        "I-PREMIUM-290",
        "I-PREMIUM-291",
        "I-PREMIUM-292",
        "I-PREMIUM-293",
        "I-PREMIUM-295",
        "I-PREMIUM-307",
        "I-PREMIUM-308",
        "I-PREMIUM-309",
        "I-SETTINGS-500",
    ]

    static let discover: [String] = [
        "I-DISCOVER-044",
        "I-DISCOVER-070",
        "I-DISCOVER-071",
        "I-DISCOVER-072",
        "I-DISCOVER-073",
        "I-IDX-MOMENTS-034",
    ]

    static let deepLinks: [String] = [
        "I-DEEPLINKS-017",
    ]

    static let translationEntry: [String] = [
        "I-TRANSLATION-052",
        "I-TRANSLATION-057",
        "I-TRANSLATION-061",
        "I-TRANSLATION-062",
        "I-TRANSLATION-063",
        "I-TRANSLATION-066",
        "I-TRANSLATION-073",
    ]
}
