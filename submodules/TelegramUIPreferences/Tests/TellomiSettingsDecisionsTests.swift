import XCTest

final class TellomiSettingsDecisionsTests: XCTestCase {
    func testHomeGroupsAndSecondaryPage() {
        let layout = tellomiSettingsHomeLayout(includeNavigation: true)
        XCTAssertEqual(layout.map { $0.0 }, [.account, .general, .help])
        XCTAssertEqual(layout[0].1, [.profile, .bindings, .privacy, .devices])
        XCTAssertEqual(layout[1].1, [.notifications, .appearance, .chatStorage, .language, .navigation, .more])
        XCTAssertEqual(layout[2].1, [.helpCenter, .support, .legal, .about])

        let withoutNavigation = tellomiSettingsHomeLayout(includeNavigation: false)
        XCTAssertFalse(withoutNavigation[1].1.contains(.navigation))
        XCTAssertTrue(withoutNavigation[1].1.contains(.more))

        XCTAssertEqual(TellomiSettingsSecondaryRow.allCases, [.savedMessages, .recentCalls, .chatFolders, .powerSaving, .openSourceLicenses])
        let homeIds = layout.flatMap { $0.1.map { $0.rawValue } }
        XCTAssertFalse(homeIds.contains("savedMessages"))
        XCTAssertFalse(homeIds.contains("chatFolders"))
        XCTAssertFalse(homeIds.contains("tips"))
        XCTAssertFalse(homeIds.contains("watch"))
        XCTAssertFalse(TellomiSettingsSecondaryRow.allCases.map { $0.rawValue }.contains("tips"))
        XCTAssertFalse(TellomiSettingsSecondaryRow.allCases.map { $0.rawValue }.contains("watch"))
    }

    func testCopyFollowsLanguageAndPack() {
        XCTAssertEqual(TellomiSettingsCopy.resolve(languageCode: "zh-Hans").account, "账号")
        XCTAssertEqual(TellomiSettingsCopy.resolve(languageCode: "zh-Hans-TW").help, "帮助与关于")
        XCTAssertEqual(TellomiSettingsCopy.resolve(languageCode: "zh-Hant").account, "帳號")
        XCTAssertEqual(TellomiSettingsCopy.resolve(languageCode: "zh-TW").bindings, "帳號與綁定")
        XCTAssertEqual(TellomiSettingsCopy.resolve(languageCode: "en").helpCenter, "Help Center")
        XCTAssertEqual(TellomiSettingsCopy.resolve(languageCode: "en").personalizedRecommendation, "Personalized Recommendations")
        XCTAssertEqual(TellomiSettingsCopy.resolve(languageCode: "zh-Hans").personalizedRecommendation, "个性化推荐")
        XCTAssertEqual(TellomiSettingsCopy.resolve(languageCode: "zh-Hans").personalizedRecommendationFooter, "关闭后，发现里的推荐不再针对你个人。")
        XCTAssertEqual(TellomiSettingsCopy.resolve(languageCode: "zh-Hant").personalizedRecommendation, "個人化推薦")
        let packed = TellomiSettingsCopy.resolve(languageCode: "en", pack: ["Tellomi.Settings.Account": "Compte"])
        XCTAssertEqual(packed.account, "Compte")
        XCTAssertEqual(packed.general, "General")
    }

    func testIdentityLine() {
        XCTAssertEqual(tellomiSettingsIdentityLine(formattedPhone: "+86 138 0013 8000", email: "owner@tellomi.cn", username: "tellomi"), "+86 138 0013 8000 • @tellomi")
        XCTAssertEqual(tellomiSettingsIdentityLine(formattedPhone: nil, email: "owner@tellomi.cn", username: "@tellomi"), "owner@tellomi.cn • @tellomi")
        XCTAssertEqual(tellomiSettingsIdentityLine(formattedPhone: "  ", email: "owner@tellomi.cn", username: "  "), "owner@tellomi.cn")
        XCTAssertEqual(tellomiSettingsIdentityLine(formattedPhone: nil, email: nil, username: nil), "")
    }

    func testRecommendationDefaultsOnTurnsOffAndRestores() {
        let initial = tellomiRecommendationChoice(storedPersonalized: nil)
        XCTAssertTrue(initial.personalized)
        XCTAssertTrue(tellomiRecommendFeedIsPersonalized(initial))
        XCTAssertEqual(tellomiRecommendCacheUpdate(preferenceKnown: false, wasPersonalized: true, isPersonalized: false, viewingRecommend: true), .none)

        let off = tellomiRecommendationChoice(storedPersonalized: false)
        XCTAssertFalse(off.personalized)
        XCTAssertFalse(tellomiRecommendFeedIsPersonalized(off))
        XCTAssertEqual(tellomiRecommendCacheUpdate(preferenceKnown: true, wasPersonalized: true, isPersonalized: false, viewingRecommend: true), .drop(reload: true))
        XCTAssertEqual(tellomiRecommendCacheUpdate(preferenceKnown: true, wasPersonalized: true, isPersonalized: false, viewingRecommend: false), .drop(reload: false))

        let restored = tellomiRecommendationChoice(storedPersonalized: true)
        XCTAssertTrue(restored.personalized)
        XCTAssertTrue(tellomiRecommendFeedIsPersonalized(restored))
        XCTAssertEqual(tellomiRecommendCacheUpdate(preferenceKnown: true, wasPersonalized: false, isPersonalized: true, viewingRecommend: true), .drop(reload: true))
        XCTAssertEqual(tellomiRecommendCacheUpdate(preferenceKnown: true, wasPersonalized: true, isPersonalized: true, viewingRecommend: true), .none)
    }

    func testAboutFactsStayReplaceable() {
        let placeholder = TellomiSettingsCopy.resolve(languageCode: "zh-Hans").numberPlaceholder
        let facts = TellomiAboutDisclosure.facts(configuration: nil, numberPlaceholder: placeholder)
        XCTAssertEqual(facts.modelName, "通义千问 Qwen")
        XCTAssertEqual(facts.generativeAIRegistrationNumber, "待公示")
        XCTAssertEqual(facts.algorithmFilingNumber, "待公示")
        let replaced = TellomiAboutDisclosure.facts(configuration: [
            TellomiAboutDisclosure.generativeRegistrationConfigurationKey: " 网信算备示例 ",
            TellomiAboutDisclosure.algorithmFilingConfigurationKey: "",
            TellomiAboutDisclosure.modelConfigurationKey: "Qwen"
        ], numberPlaceholder: placeholder)
        XCTAssertEqual(replaced.modelName, "Qwen")
        XCTAssertEqual(replaced.generativeAIRegistrationNumber, "网信算备示例")
        XCTAssertEqual(replaced.algorithmFilingNumber, "待公示")
        let blankConfig: [String: Any] = [
            TellomiAboutDisclosure.modelConfigurationKey: "  \n",
            TellomiAboutDisclosure.generativeRegistrationConfigurationKey: " ",
            TellomiAboutDisclosure.algorithmFilingConfigurationKey: 12,
            TellomiAboutDisclosure.publishedGenerativeRegistrationConfigurationKey: false
        ]
        let blank = TellomiAboutDisclosure.facts(configuration: blankConfig, numberPlaceholder: placeholder)
        XCTAssertEqual(blank.modelName, "通义千问 Qwen")
        XCTAssertEqual(blank.generativeAIRegistrationNumber, "待公示")
        XCTAssertEqual(blank.algorithmFilingNumber, "待公示")
        let published = TellomiAboutDisclosure.facts(configuration: [
            TellomiAboutDisclosure.publishedGenerativeRegistrationConfigurationKey: " 示例登记 ",
            TellomiAboutDisclosure.modelConfigurationKey: "通义千问",
            TellomiAboutDisclosure.algorithmFilingConfigurationKey: "网信算备示例"
        ], numberPlaceholder: placeholder)
        XCTAssertEqual(published.modelName, "通义千问")
        XCTAssertEqual(published.generativeAIRegistrationNumber, "示例登记")
        XCTAssertEqual(published.algorithmFilingNumber, "网信算备示例")
        let preferred = TellomiAboutDisclosure.facts(configuration: [
            TellomiAboutDisclosure.generativeRegistrationConfigurationKey: "登记甲",
            TellomiAboutDisclosure.publishedGenerativeRegistrationConfigurationKey: "登记乙"
        ], numberPlaceholder: placeholder)
        XCTAssertEqual(preferred.generativeAIRegistrationNumber, "登记甲")
        let fallbackKey = TellomiAboutDisclosure.facts(configuration: [
            TellomiAboutDisclosure.generativeRegistrationConfigurationKey: " ",
            TellomiAboutDisclosure.publishedGenerativeRegistrationConfigurationKey: "登记乙"
        ], numberPlaceholder: placeholder)
        XCTAssertEqual(fallbackKey.generativeAIRegistrationNumber, "登记乙")
        let text = tellomiAboutDisclosureText(modelLabel: "AI 模型", registrationLabel: "生成式人工智能服务登记编号", algorithmLabel: "算法备案编号", facts: facts)
        XCTAssertTrue(text.contains("通义千问 Qwen"))
        XCTAssertTrue(text.contains("待公示"))
        XCTAssertEqual(TellomiSettingsURLs.helpCenter, "https://tellomi.cn/help")
        XCTAssertEqual(TellomiSettingsURLs.terms, "https://tellomi.cn/legal/terms/")
        XCTAssertEqual(TellomiSettingsURLs.privacy, "https://tellomi.cn/legal/privacy/")
    }

    func testHeaderCardPutsAvatarLeftAndEditRight() {
        let metrics = tellomiSettingsHeaderCardMetrics(width: 402, navigationHeight: 118, sectionLeft: 0, sectionRight: 0, editWidth: 36)
        XCTAssertEqual(metrics.avatarSide, 64)
        XCTAssertLessThan(metrics.avatarX, metrics.textX)
        XCTAssertGreaterThan(metrics.editX, metrics.textX)
        XCTAssertGreaterThan(metrics.avatarX, metrics.cardX)
        XCTAssertLessThan(metrics.editX + metrics.editWidth, metrics.cardX + metrics.cardWidth + 0.1)
        XCTAssertGreaterThan(metrics.panelHeight, metrics.cardHeight)
        let text = tellomiSettingsHeaderCardTextFrames(metrics: metrics, titleWidth: 80, titleHeight: 24, subtitleWidth: 140, subtitleHeight: 18)
        XCTAssertEqual(text.titleX, metrics.textX)
        XCTAssertEqual(text.subtitleX, metrics.textX)
        XCTAssertGreaterThan(text.subtitleY, text.titleY)
        XCTAssertLessThan(text.titleY, metrics.cardY + metrics.cardHeight)
        XCTAssertGreaterThan(text.subtitleY + text.subtitleHeight, metrics.cardY)
    }
}
