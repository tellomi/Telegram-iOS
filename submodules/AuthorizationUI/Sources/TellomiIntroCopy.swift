import Foundation

/// Welcome carousel copy. The stock intro reads only `en.lproj`, which is Telegram's
/// "Start Messaging" tour. Tellomi keeps the same six pages and follows the system language.
struct TellomiIntroCopy {
    let headlines: [String]
    let descriptions: [String]
    let startButton: String
}

func tellomiIntroCopy() -> TellomiIntroCopy {
    // Page order matches RMIntroViewController: 1, 2, 6, 3, 4, 5.
    // The OpenGL page turns stay. The words are a dating app, not the Telegram tour.
    let script: TellomiLoginScript
    if let preferred = UserDefaults.standard.string(forKey: tellomiPreferredInterfaceLanguageKey) {
        script = tellomiLoginScript(languageCode: preferred)
    } else if let code = tellomiSystemLangPackCode() {
        script = tellomiLoginScript(languageCode: code)
    } else {
        script = .english
    }
    switch script {
    case .hans:
        return TellomiIntroCopy(
            headlines: ["Tellomi", "附近", "随身", "消息", "照片", "私密"],
            descriptions: [
                "认识附近的人。\n真实，也**私密**。",
                "看看谁在身边，\n先打个招呼。",
                "换一台设备，\n接着聊。",
                "一段只属于你们的\n对话。",
                "准备好了，\n再分享一个瞬间。",
                "聊天内容\n只留给你们。"
            ],
            startButton: "开始认识"
        )
    case .hant:
        return TellomiIntroCopy(
            headlines: ["Tellomi", "附近", "隨身", "訊息", "照片", "私密"],
            descriptions: [
                "認識附近的人。\n真實，也**私密**。",
                "看看誰在身邊，\n先打個招呼。",
                "換一台裝置，\n接著聊。",
                "一段只屬於你們的\n對話。",
                "準備好了，\n再分享一個瞬間。",
                "聊天內容\n只留給你們。"
            ],
            startButton: "開始認識"
        )
    case .english:
        return TellomiIntroCopy(
            headlines: ["Tellomi", "Nearby", "Anywhere", "Messages", "Photos", "Private"],
            descriptions: [
                "Meet someone nearby.\nReal people, **private** chats.",
                "See who's around\nand say hello.",
                "Pick up the same chat\non every device.",
                "A conversation\nthat stays between you two.",
                "Share a moment\nwhen you're ready.",
                "Your chats\nstay yours."
            ],
            startButton: "Start meeting"
        )
    }
}
