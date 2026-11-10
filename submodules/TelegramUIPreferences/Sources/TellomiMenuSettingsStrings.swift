import Foundation

/// Built-in languages from `Telegram/BUILD` `empty_languages`, plus English and the two Chinese scripts.
public let tellomiBuiltinMenuLanguages: [String] = [
    "ar", "be", "ca", "de", "en", "es", "fa", "fr", "id", "it", "ko", "ms", "nl", "pl", "pt", "ru", "tr", "uk", "uz", "zh-Hans", "zh-Hant"
]

public enum TellomiMenuSettingsStringKey: String, CaseIterable {
    case tools = "Tellomi.MenuSettings.Tools"
    case title = "Tellomi.MenuSettings.Title"
    case hideButtonTitles = "Tellomi.MenuSettings.HideButtonTitles"
    case navigationButtons = "Tellomi.MenuSettings.NavigationButtons"
}

/// Fills keys the active language pack does not have yet. A pack value wins.
public func tellomiMergeMenuSettingsStrings(_ dict: inout [String: String], languageCode: String) {
    let language = tellomiCanonicalMenuLanguage(languageCode)
    for key in TellomiMenuSettingsStringKey.allCases {
        if let existing = dict[key.rawValue], !existing.isEmpty {
            continue
        }
        dict[key.rawValue] = tellomiMenuSettingsString(languageCode: language, key: key)
    }
}

public func tellomiCanonicalMenuLanguage(_ raw: String) -> String {
    let lower = raw.replacingOccurrences(of: "_", with: "-").lowercased()
    if lower == "zh-hant" || lower.hasPrefix("zh-hant-") || lower == "zh-tw" || lower.hasPrefix("zh-tw-") || lower == "zh-hk" || lower.hasPrefix("zh-hk-") || lower == "zh-mo" || lower.hasPrefix("zh-mo-") {
        return "zh-Hant"
    }
    if lower == "zh" || lower.hasPrefix("zh-") {
        return "zh-Hans"
    }
    let base = lower.split(separator: "-").first.map(String.init) ?? lower
    if let match = tellomiBuiltinMenuLanguages.first(where: { $0.lowercased() == base }) {
        return match
    }
    return "en"
}

public func tellomiMenuSettingsCatalogHasCompleteTable(_ languageCode: String) -> Bool {
    guard let table = tellomiMenuSettingsCatalog[languageCode] else {
        return false
    }
    return TellomiMenuSettingsStringKey.allCases.allSatisfy { key in
        if let value = table[key] {
            return !value.isEmpty
        }
        return false
    }
}

public func tellomiMenuSettingsString(languageCode: String, key: TellomiMenuSettingsStringKey) -> String {
    let language = tellomiCanonicalMenuLanguage(languageCode)
    guard let table = tellomiMenuSettingsCatalog[language] ?? tellomiMenuSettingsCatalog["en"], let value = table[key], !value.isEmpty else {
        return ""
    }
    return value
}

private let tellomiMenuSettingsCatalog: [String: [TellomiMenuSettingsStringKey: String]] = [
    "en": [
        .tools: "Tools",
        .title: "Menu settings",
        .hideButtonTitles: "Hide button titles",
        .navigationButtons: "Navigation bar buttons"
    ],
    "zh-Hans": [
        .tools: "工具",
        .title: "选单设定",
        .hideButtonTitles: "隐藏按钮文字",
        .navigationButtons: "导航栏按钮"
    ],
    "zh-Hant": [
        .tools: "工具",
        .title: "選單設定",
        .hideButtonTitles: "隱藏按鈕文字",
        .navigationButtons: "導覽列按鈕"
    ],
    "ar": [
        .tools: "الأدوات",
        .title: "إعدادات القائمة",
        .hideButtonTitles: "إخفاء نص الأزرار",
        .navigationButtons: "أزرار شريط التنقل"
    ],
    "be": [
        .tools: "Інструменты",
        .title: "Налады меню",
        .hideButtonTitles: "Схаваць подпісы кнопак",
        .navigationButtons: "Кнопкі панэлі навігацыі"
    ],
    "ca": [
        .tools: "Eines",
        .title: "Configuració del menú",
        .hideButtonTitles: "Amaga el text dels botons",
        .navigationButtons: "Botons de la barra de navegació"
    ],
    "de": [
        .tools: "Werkzeuge",
        .title: "Menüeinstellungen",
        .hideButtonTitles: "Schaltflächentext ausblenden",
        .navigationButtons: "Navigationsleistenschaltflächen"
    ],
    "es": [
        .tools: "Herramientas",
        .title: "Ajustes del menú",
        .hideButtonTitles: "Ocultar texto de los botones",
        .navigationButtons: "Botones de la barra de navegación"
    ],
    "fa": [
        .tools: "ابزارها",
        .title: "تنظیمات منو",
        .hideButtonTitles: "پنهان کردن متن دکمه‌ها",
        .navigationButtons: "دکمه‌های نوار ناوبری"
    ],
    "fr": [
        .tools: "Outils",
        .title: "Réglages du menu",
        .hideButtonTitles: "Masquer le texte des boutons",
        .navigationButtons: "Boutons de la barre de navigation"
    ],
    "id": [
        .tools: "Alat",
        .title: "Pengaturan menu",
        .hideButtonTitles: "Sembunyikan teks tombol",
        .navigationButtons: "Tombol bilah navigasi"
    ],
    "it": [
        .tools: "Strumenti",
        .title: "Impostazioni menu",
        .hideButtonTitles: "Nascondi testo pulsanti",
        .navigationButtons: "Pulsanti della barra di navigazione"
    ],
    "ko": [
        .tools: "도구",
        .title: "메뉴 설정",
        .hideButtonTitles: "버튼 텍스트 숨기기",
        .navigationButtons: "탐색 막대 버튼"
    ],
    "ms": [
        .tools: "Alat",
        .title: "Tetapan menu",
        .hideButtonTitles: "Sembunyikan teks butang",
        .navigationButtons: "Butang bar navigasi"
    ],
    "nl": [
        .tools: "Hulpmiddelen",
        .title: "Menu-instellingen",
        .hideButtonTitles: "Knoptekst verbergen",
        .navigationButtons: "Navigatiebalkknoppen"
    ],
    "pl": [
        .tools: "Narzędzia",
        .title: "Ustawienia menu",
        .hideButtonTitles: "Ukryj tekst przycisków",
        .navigationButtons: "Przyciski paska nawigacji"
    ],
    "pt": [
        .tools: "Ferramentas",
        .title: "Definições do menu",
        .hideButtonTitles: "Ocultar texto dos botões",
        .navigationButtons: "Botões da barra de navegação"
    ],
    "ru": [
        .tools: "Инструменты",
        .title: "Настройки меню",
        .hideButtonTitles: "Скрыть подписи кнопок",
        .navigationButtons: "Кнопки панели навигации"
    ],
    "tr": [
        .tools: "Araçlar",
        .title: "Menü ayarları",
        .hideButtonTitles: "Düğme yazısını gizle",
        .navigationButtons: "Gezinme çubuğu düğmeleri"
    ],
    "uk": [
        .tools: "Інструменти",
        .title: "Налаштування меню",
        .hideButtonTitles: "Сховати підписи кнопок",
        .navigationButtons: "Кнопки панелі навігації"
    ],
    "uz": [
        .tools: "Asboblar",
        .title: "Menyu sozlamalari",
        .hideButtonTitles: "Tugma matnini yashirish",
        .navigationButtons: "Navigatsiya paneli tugmalari"
    ]
]
