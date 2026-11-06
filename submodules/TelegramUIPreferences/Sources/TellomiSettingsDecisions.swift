import Foundation
import TellomiLinks

/// Settings home (M1 / D-29). Tips and Apple Watch are not rows.
/// Saved messages, recent calls, chat folders, power saving, and open-source
/// licenses are the secondary page (`TellomiSettingsSecondaryRow`).
public enum TellomiSettingsHomeGroup: String, Equatable {
    case account
    case general
    case help
}

public enum TellomiSettingsHomeRow: String, Equatable {
    case profile
    case bindings
    case privacy
    case devices
    case notifications
    case appearance
    case chatStorage
    case language
    case navigation
    case more
    case helpCenter
    case support
    case legal
    case about
}

public enum TellomiSettingsSecondaryRow: String, CaseIterable, Equatable {
    case savedMessages
    case recentCalls
    case chatFolders
    case powerSaving
    case openSourceLicenses
}

public func tellomiSettingsHomeLayout(includeNavigation: Bool) -> [(TellomiSettingsHomeGroup, [TellomiSettingsHomeRow])] {
    var general: [TellomiSettingsHomeRow] = [.notifications, .appearance, .chatStorage, .language]
    if includeNavigation {
        general.append(.navigation)
    }
    general.append(.more)
    return [
        (.account, [.profile, .bindings, .privacy, .devices]),
        (.general, general),
        (.help, [.helpCenter, .support, .legal, .about])
    ]
}

/// D-39. Phone when there is one, otherwise the email, then `@username`.
/// The owner's settings card shows the address in full.
public func tellomiSettingsIdentityLine(formattedPhone: String?, email: String?, username: String?) -> String {
    var parts: [String] = []
    let phone = formattedPhone?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let address = email?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !phone.isEmpty {
        parts.append(phone)
    } else if !address.isEmpty {
        parts.append(address)
    }
    let rawName = username?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !rawName.isEmpty {
        parts.append(rawName.hasPrefix("@") ? rawName : "@\(rawName)")
    }
    return parts.joined(separator: " • ")
}

/// D-58. A missing record stays on. Only the recommend feed reads this.
public struct TellomiRecommendationChoice: Equatable {
    public var personalized: Bool

    public static var defaultChoice: TellomiRecommendationChoice {
        return TellomiRecommendationChoice(personalized: true)
    }

    public init(personalized: Bool) {
        self.personalized = personalized
    }
}

public func tellomiRecommendationChoice(storedPersonalized: Bool?) -> TellomiRecommendationChoice {
    guard let storedPersonalized else {
        return .defaultChoice
    }
    return TellomiRecommendationChoice(personalized: storedPersonalized)
}

public func tellomiRecommendFeedIsPersonalized(_ choice: TellomiRecommendationChoice) -> Bool {
    return choice.personalized
}

/// Privacy and Security always shows 「个性化推荐」.
/// `personalization_toggle_visible` is parsed on the feed config and is not a gate:
/// the parser stores false both when the key is omitted and when it is false, so
/// the configs this client already accepts would hide the only control that can
/// send `personalized=false`.
public func tellomiPersonalizedRecommendationRowVisible(personalizationToggleVisible _: Bool) -> Bool {
    return true
}

/// What happens to the cached Recommend page when the stored switch is read or moved.
/// The first read does not count as a change: nothing has been fetched under another value yet.
/// A later change drops that page. Recommend reloads immediately; another tab waits until it is opened.
public enum TellomiRecommendCacheUpdate: Equatable {
    case none
    case drop(reload: Bool)
}

public func tellomiRecommendCacheUpdate(preferenceKnown: Bool, wasPersonalized: Bool, isPersonalized: Bool, viewingRecommend: Bool) -> TellomiRecommendCacheUpdate {
    guard preferenceKnown, wasPersonalized != isPersonalized else {
        return .none
    }
    return .drop(reload: viewingRecommend)
}

/// D-50 / D-59. Shown only on About Tellomi.
/// `help.getAppConfig` may replace each field with a non-empty string.
public struct TellomiAboutFacts: Equatable {
    public var modelName: String
    public var generativeAIRegistrationNumber: String
    public var algorithmFilingNumber: String

    public init(modelName: String, generativeAIRegistrationNumber: String, algorithmFilingNumber: String) {
        self.modelName = modelName
        self.generativeAIRegistrationNumber = generativeAIRegistrationNumber
        self.algorithmFilingNumber = algorithmFilingNumber
    }
}

public enum TellomiAboutDisclosure {
    public static let modelConfigurationKey = "tellomi_ai_model_name"
    public static let generativeRegistrationConfigurationKey = "tellomi_generative_ai_registration_number"
    /// Key teamgram `pkg/about` puts on `help.getAppConfig`. The longer key wins when both are set.
    public static let publishedGenerativeRegistrationConfigurationKey = "tellomi_ai_registration_number"
    public static let algorithmFilingConfigurationKey = "tellomi_algorithm_filing_number"
    /// D-22. DeepSeek is the backup and is not listed here.
    public static let defaultModelName = "通义千问 Qwen"

    /// A missing key, a non-string, or a blank string keeps `fallback`.
    public static func facts(configuration: [String: Any]?, numberPlaceholder: String) -> TellomiAboutFacts {
        func string(_ key: String, fallback: String) -> String {
            guard let raw = configuration?[key] as? String else {
                return fallback
            }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? fallback : trimmed
        }
        let registration = string(
            Self.generativeRegistrationConfigurationKey,
            fallback: string(Self.publishedGenerativeRegistrationConfigurationKey, fallback: numberPlaceholder)
        )
        return TellomiAboutFacts(
            modelName: string(Self.modelConfigurationKey, fallback: Self.defaultModelName),
            generativeAIRegistrationNumber: registration,
            algorithmFilingNumber: string(Self.algorithmFilingConfigurationKey, fallback: numberPlaceholder)
        )
    }
}

public func tellomiAboutDisclosureText(modelLabel: String, registrationLabel: String, algorithmLabel: String, facts: TellomiAboutFacts) -> String {
    return "\(modelLabel)\n\(facts.modelName)\n\n\(registrationLabel)\n\(facts.generativeAIRegistrationNumber)\n\n\(algorithmLabel)\n\(facts.algorithmFilingNumber)"
}

public enum TellomiSettingsURLs {
    public static var helpCenter: String { TellomiLinks.siteURL("help") }
    public static var terms: String { TellomiLinks.siteURL("legal/terms/") }
    public static var privacy: String { TellomiLinks.siteURL("legal/privacy/") }
}

public struct TellomiSettingsCopy: Equatable {
    public var account: String
    public var general: String
    public var help: String
    public var profile: String
    public var bindings: String
    public var privacy: String
    public var devices: String
    public var notifications: String
    public var appearance: String
    public var chatStorage: String
    public var language: String
    public var more: String
    public var helpCenter: String
    public var support: String
    public var supportUnavailable: String
    public var legal: String
    public var about: String
    public var phone: String
    public var email: String
    public var username: String
    public var addAccount: String
    public var logout: String
    public var openSource: String
    public var personalizedRecommendationSection: String
    public var personalizedRecommendation: String
    public var personalizedRecommendationFooter: String
    public var modelLabel: String
    public var registrationLabel: String
    public var algorithmLabel: String
    public var numberPlaceholder: String
    public var terms: String
    public var privacyPolicy: String
    public var version: String
    public var aboutFooter: String
    public var premiumGraceTitle: String
    public var premiumGraceText: String
    public var premiumGraceAction: String

    public func title(for group: TellomiSettingsHomeGroup) -> String {
        switch group {
        case .account:
            return self.account
        case .general:
            return self.general
        case .help:
            return self.help
        }
    }

    public static func resolve(languageCode: String, pack: [String: String] = [:]) -> TellomiSettingsCopy {
        func text(_ key: String, _ english: String, _ simplified: String, _ traditional: String) -> String {
            return tellomiTabPackString(languageCode: languageCode, pack: pack, key: key, english: english, simplified: simplified, traditional: traditional)
        }
        return TellomiSettingsCopy(
            account: text("Tellomi.Settings.Account", "Account", "账号", "帳號"),
            general: text("Tellomi.Settings.General", "General", "通用", "通用"),
            help: text("Tellomi.Settings.Help", "Help & About", "帮助与关于", "幫助與關於"),
            profile: text("Tellomi.Settings.Profile", "Profile", "资料", "資料"),
            bindings: text("Tellomi.Settings.Bindings", "Account & Sign-In", "账号与绑定", "帳號與綁定"),
            privacy: text("Tellomi.Settings.Privacy", "Privacy and Security", "隐私与安全", "隱私與安全"),
            devices: text("Tellomi.Settings.Devices", "Devices", "设备", "裝置"),
            notifications: text("Tellomi.Settings.Notifications", "Notifications and Sounds", "通知与声音", "通知與聲音"),
            appearance: text("Tellomi.Settings.Appearance", "Appearance", "外观", "外觀"),
            chatStorage: text("Tellomi.Settings.ChatStorage", "Chat and Storage", "聊天与存储", "聊天與儲存"),
            language: text("Tellomi.Settings.Language", "Language", "语言", "語言"),
            more: text("Tellomi.Settings.More", "More", "更多", "更多"),
            helpCenter: text("Tellomi.Settings.HelpCenter", "Help Center", "帮助中心", "幫助中心"),
            support: text("Tellomi.Settings.Support", "Support", "客服", "客服"),
            supportUnavailable: text("Tellomi.Settings.SupportUnavailable", "Support isn't available right now. Try again later.", "暂时联系不上客服，请稍后再试。", "暫時聯絡不上客服，請稍後再試。"),
            legal: text("Tellomi.Settings.Legal", "Terms and Privacy", "协议与隐私", "協議與隱私"),
            about: text("Tellomi.Settings.About", "About Tellomi", "关于 Tellomi", "關於 Tellomi"),
            phone: text("Tellomi.Settings.Phone", "Phone", "手机号", "手機號碼"),
            email: text("Tellomi.Settings.Email", "Email", "邮箱", "電子郵件"),
            username: text("Tellomi.Settings.Username", "Username", "用户名", "使用者名稱"),
            addAccount: text("Tellomi.Settings.AddAccount", "Add Account", "添加账号", "新增帳號"),
            logout: text("Tellomi.Settings.Logout", "Log Out", "退出登录", "登出"),
            openSource: text("Tellomi.Settings.OpenSource", "Open Source Licenses", "开源许可", "開源許可"),
            personalizedRecommendationSection: text("Tellomi.Settings.PersonalizedRecommendationSection", "Discover", "发现", "發現"),
            personalizedRecommendation: text("Tellomi.Settings.PersonalizedRecommendation", "Personalized Recommendations", "个性化推荐", "個人化推薦"),
            personalizedRecommendationFooter: text("Tellomi.Settings.PersonalizedRecommendationFooter", "When this is off, For You is not ranked from your activity.", "关闭后，推荐不再根据你的浏览记录排序。", "關閉後，推薦不再根據你的瀏覽記錄排序。"),
            modelLabel: text("Tellomi.Settings.ModelLabel", "AI model", "AI 模型", "AI 模型"),
            registrationLabel: text("Tellomi.Settings.RegistrationLabel", "Generative AI registration number", "生成式人工智能服务登记编号", "生成式人工智慧服務登記編號"),
            algorithmLabel: text("Tellomi.Settings.AlgorithmLabel", "Algorithm filing number", "算法备案编号", "演算法備案編號"),
            numberPlaceholder: text("Tellomi.Settings.NumberPlaceholder", "Pending", "待公示", "待公示"),
            terms: text("Tellomi.Settings.Terms", "Terms of Service", "用户服务协议", "使用者服務協議"),
            privacyPolicy: text("Tellomi.Settings.PrivacyPolicy", "Privacy Policy", "隐私政策", "隱私權政策"),
            version: text("Tellomi.Settings.Version", "Version", "版本", "版本"),
            aboutFooter: text("Tellomi.Settings.AboutFooter", "This is the only page that shows this information.", "以上信息只在这个页面公示。", "以上資訊只在這個頁面公示。"),
            premiumGraceTitle: text("Tellomi.Settings.PremiumGraceTitle", "Your membership will expire soon.", "你的会员即将到期。", "你的會員即將到期。"),
            premiumGraceText: text("Tellomi.Settings.PremiumGraceText", "The latest payment did not go through. Renew to keep these features.", "最近一次付款没有成功。要继续使用这些功能，请续订。", "最近一次付款沒有成功。要繼續使用這些功能，請續訂。"),
            premiumGraceAction: text("Tellomi.Settings.PremiumGraceAction", "Restore Subscription", "恢复订阅", "恢復訂閱")
        )
    }
}
