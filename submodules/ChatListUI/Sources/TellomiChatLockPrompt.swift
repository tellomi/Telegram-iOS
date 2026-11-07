import UIKit
import LocalAuthentication
import AccountContext
import TelegramUIPreferences
import TelegramCore

func tellomiPresentChatLock(context: AccountContext, host: UIViewController, peerId: EnginePeer.Id) {
    let accountPeerId = context.account.peerId.toInt64()
    let chatPeerId = peerId.toInt64()
    let language = context.sharedContext.currentPresentationData.with { $0 }.strings.primaryComponent.languageCode
    let locked = TellomiChatLockDirectory.shared.isLocked(accountPeerId: accountPeerId, chatPeerId: chatPeerId)
    let title = tellomiChatLockMenuTitle(languageCode: language, isLocked: locked)
    let alert = UIAlertController(title: title, message: tellomiChatLockExplanation(languageCode: language, locked: locked), preferredStyle: .alert)
    if locked {
        alert.addAction(UIAlertAction(title: tellomiChatPrivacyUsesChinese(language) ? "修改密码" : "Change", style: .default, handler: { _ in
            tellomiPromptPin(host: host, language: language, title: tellomiChatPrivacyUsesChinese(language) ? "当前密码" : "Current password") { current in
                guard let record = TellomiChatLockDirectory.shared.record(accountPeerId: accountPeerId, chatPeerId: chatPeerId), tellomiChatLockMatches(pin: current, record: record) else {
                    tellomiChatLockNote(host: host, language: language, text: tellomiChatPrivacyUsesChinese(language) ? "密码不正确" : "Wrong password")
                    return
                }
                tellomiPromptNewPin(host: host, language: language) { pin, biometrics in
                    guard case let .success(updated) = tellomiMakeChatLockRecord(pin: pin, biometricsEnabled: biometrics) else {
                        return
                    }
                    TellomiChatLockKeychain.save(updated, accountPeerId: accountPeerId, chatPeerId: chatPeerId)
                }
            }
        }))
        alert.addAction(UIAlertAction(title: tellomiChatPrivacyUsesChinese(language) ? "移除密码" : "Remove", style: .destructive, handler: { _ in
            tellomiPromptPin(host: host, language: language, title: tellomiChatPrivacyUsesChinese(language) ? "当前密码" : "Current password") { current in
                guard let record = TellomiChatLockDirectory.shared.record(accountPeerId: accountPeerId, chatPeerId: chatPeerId), tellomiChatLockMatches(pin: current, record: record) else {
                    tellomiChatLockNote(host: host, language: language, text: tellomiChatPrivacyUsesChinese(language) ? "密码不正确" : "Wrong password")
                    return
                }
                TellomiChatLockKeychain.remove(accountPeerId: accountPeerId, chatPeerId: chatPeerId)
            }
        }))
    } else {
        alert.addAction(UIAlertAction(title: tellomiChatPrivacyUsesChinese(language) ? "设置" : "Set", style: .default, handler: { _ in
            tellomiPromptNewPin(host: host, language: language) { pin, biometrics in
                guard case let .success(record) = tellomiMakeChatLockRecord(pin: pin, biometricsEnabled: biometrics) else {
                    tellomiChatLockNote(host: host, language: language, text: tellomiChatPrivacyUsesChinese(language) ? "请使用 4 到 8 位数字" : "Use 4 to 8 digits")
                    return
                }
                TellomiChatLockKeychain.save(record, accountPeerId: accountPeerId, chatPeerId: chatPeerId)
            }
        }))
    }
    alert.addAction(UIAlertAction(title: tellomiChatPrivacyUsesChinese(language) ? "取消" : "Cancel", style: .cancel))
    host.present(alert, animated: true)
}

func tellomiUnlockChatIfNeeded(context: AccountContext, host: UIViewController, peerId: EnginePeer.Id, languageCode: String, proceed: @escaping () -> Void) {
    let accountPeerId = context.account.peerId.toInt64()
    let chatPeerId = peerId.toInt64()
    guard let record = TellomiChatLockDirectory.shared.record(accountPeerId: accountPeerId, chatPeerId: chatPeerId) else {
        proceed()
        return
    }
    let alert = UIAlertController(title: tellomiChatLockConcealedText(languageCode: languageCode), message: tellomiChatPrivacyUsesChinese(languageCode) ? "输入这个聊天的数字密码" : "Enter this chat's PIN", preferredStyle: .alert)
    alert.addTextField { field in
        field.keyboardType = .numberPad
        field.isSecureTextEntry = true
    }
    alert.addAction(UIAlertAction(title: tellomiChatPrivacyUsesChinese(languageCode) ? "打开" : "Open", style: .default, handler: { _ in
        let pin = alert.textFields?.first?.text ?? ""
        if tellomiChatLockMatches(pin: pin, record: record) {
            proceed()
        } else {
            tellomiChatLockNote(host: host, language: languageCode, text: tellomiChatPrivacyUsesChinese(languageCode) ? "密码不正确" : "Wrong password")
        }
    }))
    if record.biometricsEnabled {
        alert.addAction(UIAlertAction(title: tellomiChatPrivacyUsesChinese(languageCode) ? "面容 / 触控 ID" : "Face ID / Touch ID", style: .default, handler: { _ in
            let context = LAContext()
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: tellomiChatLockConcealedText(languageCode: languageCode)) { ok, _ in
                DispatchQueue.main.async {
                    if ok {
                        proceed()
                    }
                }
            }
        }))
    }
    alert.addAction(UIAlertAction(title: tellomiChatPrivacyUsesChinese(languageCode) ? "忘记密码" : "Forgot password", style: .default, handler: { _ in
        switch tellomiForgotChatLock(hasAppPasscode: TellomiAppPasscodeBridge.hasPasscode()) {
        case .staysLocked:
            tellomiChatLockNote(host: host, language: languageCode, text: tellomiChatPrivacyUsesChinese(languageCode) ? "没有应用锁时无法找回。聊天保持锁定，密码不会上传。" : "Without an app passcode this PIN cannot be recovered. The chat stays locked and nothing is uploaded.")
        case .resetAfterAppPasscode:
            tellomiPromptPin(host: host, language: languageCode, title: tellomiChatPrivacyUsesChinese(languageCode) ? "应用锁" : "App passcode") { code in
                guard TellomiAppPasscodeBridge.verify(code) else {
                    tellomiChatLockNote(host: host, language: languageCode, text: tellomiChatPrivacyUsesChinese(languageCode) ? "应用锁不正确。聊天仍锁定。" : "Wrong app passcode. The chat stays locked.")
                    return
                }
                tellomiPromptNewPin(host: host, language: languageCode) { pin, biometrics in
                    guard case let .success(updated) = tellomiMakeChatLockRecord(pin: pin, biometricsEnabled: biometrics) else {
                        return
                    }
                    TellomiChatLockKeychain.save(updated, accountPeerId: accountPeerId, chatPeerId: chatPeerId)
                    proceed()
                }
            }
        }
    }))
    alert.addAction(UIAlertAction(title: tellomiChatPrivacyUsesChinese(languageCode) ? "取消" : "Cancel", style: .cancel))
    host.present(alert, animated: true)
}

private func tellomiChatLockExplanation(languageCode: String, locked: Bool) -> String {
    if tellomiChatPrivacyUsesChinese(languageCode) {
        return locked ? "密码只保存在本机，可以修改或移除。忘记密码时，只有已开启的应用锁能重置。" : "为这个聊天设置 4 到 8 位数字密码。密码只保存在本机，不上传。"
    }
    return locked ? "The PIN stays on this device. You can change or remove it. If you forget it, only an existing app passcode can reset it." : "Set a 4 to 8 digit PIN for this chat. It stays on this device and is not uploaded."
}

private func tellomiPromptNewPin(host: UIViewController, language: String, done: @escaping (String, Bool) -> Void) {
    tellomiPromptPin(host: host, language: language, title: tellomiChatPrivacyUsesChinese(language) ? "新密码" : "New PIN") { pin in
        guard tellomiChatLockPinIsNumeric(pin) else {
            tellomiChatLockNote(host: host, language: language, text: tellomiChatPrivacyUsesChinese(language) ? "请使用 4 到 8 位数字" : "Use 4 to 8 digits")
            return
        }
        tellomiPromptPin(host: host, language: language, title: tellomiChatPrivacyUsesChinese(language) ? "再输入一次" : "Repeat PIN") { repeatPin in
            guard pin == repeatPin else {
                tellomiChatLockNote(host: host, language: language, text: tellomiChatPrivacyUsesChinese(language) ? "两次输入不一致" : "The PINs do not match")
                return
            }
            let biometrics = UIAlertController(title: tellomiChatPrivacyUsesChinese(language) ? "面容 / 触控 ID" : "Face ID / Touch ID", message: tellomiChatPrivacyUsesChinese(language) ? "可以用生物识别打开这个聊天。数字密码仍然有效。" : "Biometrics can open this chat. The PIN still works.", preferredStyle: .alert)
            biometrics.addAction(UIAlertAction(title: tellomiChatPrivacyUsesChinese(language) ? "开启" : "Turn on", style: .default, handler: { _ in
                done(pin, true)
            }))
            biometrics.addAction(UIAlertAction(title: tellomiChatPrivacyUsesChinese(language) ? "不用" : "Not now", style: .cancel, handler: { _ in
                done(pin, false)
            }))
            host.present(biometrics, animated: true)
        }
    }
}

private func tellomiPromptPin(host: UIViewController, language: String, title: String, done: @escaping (String) -> Void) {
    let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert)
    alert.addTextField { field in
        field.keyboardType = .numberPad
        field.isSecureTextEntry = true
    }
    alert.addAction(UIAlertAction(title: tellomiChatPrivacyUsesChinese(language) ? "继续" : "Continue", style: .default, handler: { _ in
        done(alert.textFields?.first?.text ?? "")
    }))
    alert.addAction(UIAlertAction(title: tellomiChatPrivacyUsesChinese(language) ? "取消" : "Cancel", style: .cancel))
    host.present(alert, animated: true)
}

private func tellomiChatLockNote(host: UIViewController, language: String, text: String) {
    let alert = UIAlertController(title: nil, message: text, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: tellomiChatPrivacyUsesChinese(language) ? "好" : "OK", style: .default))
    host.present(alert, animated: true)
}
