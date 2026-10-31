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
    if tellomiSystemLangPackCode() != nil {
        return TellomiIntroCopy(
            headlines: ["Tellomi", "快速", "免费", "强大", "安全", "云端"],
            descriptions: [
                "认识新朋友、发送消息。\n**免费**且**私密**。",
                "**Tellomi** 发送消息\n比其他应用更快。",
                "**Tellomi** 为聊天和媒体\n提供免费且不限量的云存储。",
                "**Tellomi** 对媒体和聊天\n没有大小限制。",
                "**Tellomi** 保护你的消息\n免受黑客攻击。",
                "**Tellomi** 让你在多台设备上\n访问你的消息。"
            ],
            startButton: "开始使用"
        )
    }
    return TellomiIntroCopy(
        headlines: ["Tellomi", "Fast", "Free", "Powerful", "Secure", "Cloud"],
        descriptions: [
            "A place to meet and message.\n**Free** and **private**.",
            "**Tellomi** delivers messages\nfaster than any other app.",
            "**Tellomi** provides free unlimited\ncloud storage for chats and media.",
            "**Tellomi** has no limits on\nthe size of your media and chats.",
            "**Tellomi** keeps your messages\nsafe from hacker attacks.",
            "**Tellomi** lets you access your\nmessages from multiple devices."
        ],
        startButton: "Get Started"
    )
}
