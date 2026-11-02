import Foundation
import UIKit
import AsyncDisplayKit
import Display
import TelegramCore
import SwiftSignalKit
import MtProtoKit
import MessageUI
import CoreTelephony
import TelegramPresentationData
import PresentationDataUtils
import TextFormat
import AccountContext
import CountrySelectionUI
import PhoneNumberFormat
import LegacyComponents
import LegacyMediaPickerUI
import PasswordSetupUI
import TelegramNotices
import AuthenticationServices
import Markdown
import AlertUI
import InAppPurchaseManager
import ObjectiveC
import AVFoundation

private var ObjCKey_Delegate: Int?

private enum InnerState: Equatable {
    case state(UnauthorizedAccountStateContents)
    case authorized
}

public final class AuthorizationSequenceController: NavigationController, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    static func navigationBarTheme(_ theme: PresentationTheme) -> NavigationBarTheme {
        return NavigationBarTheme(overallDarkAppearance: theme.overallDarkAppearance, buttonColor: theme.chat.inputPanel.panelControlColor, disabledButtonColor: theme.intro.disabledTextColor, primaryTextColor: theme.intro.primaryTextColor, badgeBackgroundColor: theme.rootController.navigationBar.badgeBackgroundColor, badgeTextColor: theme.rootController.navigationBar.badgeTextColor, edgeEffectColor: .clear, accentButtonColor: theme.list.itemCheckColors.fillColor, accentDisabledButtonColor: theme.chat.inputPanel.panelControlDisabledColor, accentForegroundColor: theme.list.itemCheckColors.foregroundColor)
    }
    
    private let sharedContext: SharedAccountContext
    private var account: UnauthorizedAccount
    private let otherAccountPhoneNumbers: ((String, AccountRecordId, Bool)?, [(String, AccountRecordId, Bool)])
    private let apiId: Int32
    private let apiHash: String
    public var presentationData: PresentationData
    private let openUrl: (String) -> Void
    private let authorizationCompleted: () -> Void
    
    private var stateDisposable: Disposable?
    private let actionDisposable = MetaDisposable()
    private var applicationStateDisposable: Disposable?
    private let tellomiLanguageDisposable = MetaDisposable()
    private let tellomiLanguageStringsDisposable = MetaDisposable()
    private let presentationDataDisposable = MetaDisposable()
    private var tellomiLanguageGate = 0
    private var tellomiLatestState: InnerState?
    private var tellomiDidAuthorize = false
    
    private var didPlayPresentationAnimation = false
    
    private let _ready = Promise<Bool>()
    override public var ready: Promise<Bool> {
        return self._ready
    }
    private var didSetReady = false
    
    fileprivate var engine: TelegramEngineUnauthorized {
        return TelegramEngineUnauthorized(account: self.account)
    }
    
    private var inAppPurchaseManager: InAppPurchaseManager!
    
    public init(sharedContext: SharedAccountContext, account: UnauthorizedAccount, otherAccountPhoneNumbers: ((String, AccountRecordId, Bool)?, [(String, AccountRecordId, Bool)]), presentationData: PresentationData, openUrl: @escaping (String) -> Void, apiId: Int32, apiHash: String, authorizationCompleted: @escaping () -> Void) {
        self.sharedContext = sharedContext
        self.account = account
        self.otherAccountPhoneNumbers = otherAccountPhoneNumbers
        self.apiId = apiId
        self.apiHash = apiHash
        self.presentationData = presentationData
        self.openUrl = openUrl
        self.authorizationCompleted = authorizationCompleted
        
        let navigationStatusBar: NavigationStatusBarStyle
        switch presentationData.theme.rootController.statusBarStyle {
        case .black:
            navigationStatusBar = .black
        case .white:
            navigationStatusBar = .white
        }
        
        super.init(mode: .single, theme: NavigationControllerTheme(statusBar: navigationStatusBar, navigationBar: AuthorizationSequenceController.navigationBarTheme(presentationData.theme), emptyAreaColor: .black, separatorColor: .clear, opaqueBackgroundColor: .clear), isFlat: true)
        
        self.inAppPurchaseManager = InAppPurchaseManager(engine: .unauthorized(self.engine))
        
        self.stateDisposable = (self.engine.auth.state()
        |> map { state -> InnerState in
            if case .authorized = state {
                return .authorized
            } else if case let .unauthorized(state) = state {
                return .state(state.contents)
            } else {
                return .state(.empty)
            }
        }
        |> distinctUntilChanged
        |> deliverOnMainQueue).startStrict(next: { [weak self] state in
            self?.updateState(state: state)
        }).strict()
        
        self.presentationDataDisposable.set((self.sharedContext.presentationData
        |> deliverOnMainQueue).start(next: { [weak self] presentationData in
            guard let self else {
                return
            }
            guard presentationData.theme !== self.presentationData.theme else {
                return
            }
            self.presentationData = self.presentationData.withTheme(presentationData.theme)
            if self.isViewLoaded {
                self.view.backgroundColor = presentationData.theme.list.plainBackgroundColor
            }
            for controller in self.viewControllers {
                if let controller = controller as? AuthorizationSequencePhoneEntryController {
                    controller.applyPresentationTheme(self.presentationData)
                } else if let controller = controller as? AuthorizationSequenceCodeEntryController {
                    controller.applyPresentationTheme(self.presentationData)
                } else if let controller = controller as? AuthorizationSequenceSplashController {
                    controller.applyPresentationTheme(presentationData.theme)
                }
            }
        }))

        self.applicationStateDisposable = (self.sharedContext.applicationBindings.applicationIsActive
        |> deliverOnMainQueue).start(next: { [weak self] isActive in
            guard let self else {
                return
            }
            for viewController in self.viewControllers {
                if let codeController = viewController as? AuthorizationSequenceCodeEntryController {
                    codeController.updateAppIsActive(isActive)
                }
            }
        })
    }
    
    required public init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        self.stateDisposable?.dispose()
        self.actionDisposable.dispose()
        self.applicationStateDisposable?.dispose()
        self.tellomiLanguageDisposable.dispose()
        self.tellomiLanguageStringsDisposable.dispose()
        self.presentationDataDisposable.dispose()
    }
    
    override public func loadView() {
        super.loadView()
        self.view.backgroundColor = self.presentationData.theme.list.plainBackgroundColor
    }
    
    private func splashController() -> AuthorizationSequenceSplashController {
        var currentController: AuthorizationSequenceSplashController?
        for c in self.viewControllers {
            if let c = c as? AuthorizationSequenceSplashController {
                currentController = c
                break
            }
        }
        let controller: AuthorizationSequenceSplashController
        if let currentController = currentController {
            controller = currentController
        } else {
            controller = AuthorizationSequenceSplashController(accountManager: self.sharedContext.accountManager, account: self.account, theme: self.presentationData.theme)
            controller.nextPressed = { [weak self] strings in
                if let strongSelf = self {
                    if let strings = strings {
                        strongSelf.presentationData = strongSelf.presentationData.withStrings(strings)
                    }
                    let masterDatacenterId = strongSelf.account.masterDatacenterId
                    let isTestingEnvironment = strongSelf.account.testingEnvironment
                    
                    let countryCode = AuthorizationSequenceCountrySelectionController.defaultCountryCode()
                    
                    let _ = strongSelf.engine.auth.setState(state: UnauthorizedAccountState(isTestingEnvironment: isTestingEnvironment, masterDatacenterId: masterDatacenterId, contents: .phoneEntry(countryCode: countryCode, number: ""))).startStandalone()
                }
            }
        }
        return controller
    }
    
    private func phoneEntryController(countryCode: Int32, number: String, splashController: AuthorizationSequenceSplashController?) -> AuthorizationSequencePhoneEntryController {
        var currentController: AuthorizationSequencePhoneEntryController?
        for c in self.viewControllers {
            if let c = c as? AuthorizationSequencePhoneEntryController {
                currentController = c
                break
            }
        }
        let controller: AuthorizationSequencePhoneEntryController
        if let currentController = currentController {
            controller = currentController
        } else {
            controller = AuthorizationSequencePhoneEntryController(sharedContext: self.sharedContext, account: self.account, apiId: self.apiId, apiHash: self.apiHash, isTestingEnvironment: self.account.testingEnvironment, otherAccountPhoneNumbers: self.otherAccountPhoneNumbers, network: self.account.network, presentationData: self.presentationData, openUrl: { [weak self] url in
                self?.openUrl(url)
            }, back: { [weak self] in
                guard let strongSelf = self else {
                    return
                }
                strongSelf.tellomiAbandonPendingLogin()
                if !strongSelf.otherAccountPhoneNumbers.1.isEmpty {
                    let _ = (strongSelf.sharedContext.accountManager.transaction { transaction -> Void in
                        transaction.removeAuth()
                    }).startStandalone()
                } else {
                    let _ = strongSelf.engine.auth.setState(state: UnauthorizedAccountState(isTestingEnvironment: strongSelf.account.testingEnvironment, masterDatacenterId: strongSelf.account.masterDatacenterId, contents: .empty)).startStandalone()
                }
            })
            if let splashController = splashController {
                controller.animateWithSplashController(splashController)
            }
            controller.accountUpdated = { [weak self] updatedAccount in
                guard let strongSelf = self else {
                    return
                }
                strongSelf.account = updatedAccount
                strongSelf.inAppPurchaseManager = InAppPurchaseManager(engine: .unauthorized(strongSelf.engine))
            }
            controller.loginWithNumber = { [weak self, weak controller] number, syncContacts in
                guard let self else {
                    return
                }
                let loginAttempt = self.tellomiBeginLoginAttempt(identifier: number)
                self.tellomiActiveLoginNumber = number
                controller?.inProgress = true
                
                let disableAuthTokens = self.sharedContext.immediateExperimentalUISettings.disableReloginTokens
                let authorizationPushConfiguration = self.sharedContext.authorizationPushConfiguration
                |> take(1)
                |> timeout(2.0, queue: .mainQueue(), alternate: .single(nil))
                self.actionDisposable.set((authorizationPushConfiguration
                |> deliverOnMainQueue).startStandalone(next: { [weak self] authorizationPushConfiguration in
                    if let strongSelf = self {
                        strongSelf.actionDisposable.set((sendAuthorizationCode(accountManager: strongSelf.sharedContext.accountManager, account: strongSelf.account, phoneNumber: number, apiId: strongSelf.apiId, apiHash: strongSelf.apiHash, pushNotificationConfiguration: authorizationPushConfiguration, firebaseSecretStream: strongSelf.sharedContext.firebaseSecretStream, syncContacts: syncContacts, disableAuthTokens: disableAuthTokens, attempt: loginAttempt, forcedPasswordSetupNotice: { value in
                            guard let entry = EngineCodableEntry(ApplicationSpecificCounterNotice(value: value)) else {
                                return nil
                            }
                            return (ApplicationSpecificNotice.forcedPasswordSetupKey(), entry)
                        }) |> deliverOnMainQueue).startStrict(next: { [weak self] result in
                            if let strongSelf = self {
                                switch result {
                                case let .sentCode(account):
                                    controller?.inProgress = false
                                    strongSelf.account = account
                                    strongSelf.inAppPurchaseManager = InAppPurchaseManager(engine: .unauthorized(strongSelf.engine))
                                case .loggedIn:
                                    break
                                }
                            }
                        }, error: { error in
                            if let strongSelf = self, let controller = controller {
                                controller.inProgress = false
                                
                                let emailLogin = tellomiIsLoginEmail(number)
                                let emailCopy = tellomiEmailLoginCopy(languageCode: tellomiInterfaceLanguageCode(strongSelf.presentationData.strings))
                                let text: String
                                var actions: [TextAlertAction] = []
                                switch error {
                                    case .limitExceeded:
                                        text = strongSelf.presentationData.strings.Login_CodeFloodError
                                        actions.append(TextAlertAction(type: .defaultAction, title: strongSelf.presentationData.strings.Common_OK, action: {}))
                                    case .invalidPhoneNumber where emailLogin:
                                        text = emailCopy.invalid
                                        actions.append(TextAlertAction(type: .defaultAction, title: strongSelf.presentationData.strings.Common_OK, action: {}))
                                    case .invalidPhoneNumber:
                                        text = strongSelf.presentationData.strings.Login_InvalidPhoneError
                                        actions.append(TextAlertAction(type: .genericAction, title: strongSelf.presentationData.strings.Common_OK, action: {}))
                                        actions.append(TextAlertAction(type: .defaultAction, title: strongSelf.presentationData.strings.Login_PhoneNumberHelp, action: {
                                            guard let strongSelf = self else {
                                                return
                                            }
                                            strongSelf.sharedContext.applicationBindings.openUrl(TellomiLoginChrome.helpURL)
                                        }))
                                    case .phoneLimitExceeded:
                                        text = strongSelf.presentationData.strings.Login_PhoneFloodError
                                        actions.append(TextAlertAction(type: .defaultAction, title: strongSelf.presentationData.strings.Common_OK, action: {}))
                                    case .appOutdated:
                                        text = strongSelf.presentationData.strings.Login_ErrorAppOutdated
                                        let updateUrl = strongSelf.presentationData.strings.InviteText_URL
                                        let sharedContext = strongSelf.sharedContext
                                        actions.append(TextAlertAction(type: .defaultAction, title: strongSelf.presentationData.strings.Common_OK, action: {
                                            sharedContext.applicationBindings.openUrl(updateUrl)
                                        }))
                                    case .phoneBanned where emailLogin:
                                        text = emailCopy.unavailable
                                        actions.append(TextAlertAction(type: .defaultAction, title: strongSelf.presentationData.strings.Common_OK, action: {}))
                                    case .phoneBanned:
                                        text = strongSelf.presentationData.strings.Login_PhoneBannedError
                                        actions.append(TextAlertAction(type: .genericAction, title: strongSelf.presentationData.strings.Common_OK, action: {}))
                                        actions.append(TextAlertAction(type: .defaultAction, title: strongSelf.presentationData.strings.Login_PhoneNumberHelp, action: {
                                            guard let strongSelf = self else {
                                                return
                                            }
                                            strongSelf.sharedContext.applicationBindings.openUrl(TellomiLoginChrome.helpURL)
                                        }))
                                    case .generic(_) where emailLogin:
                                        text = strongSelf.presentationData.strings.Login_UnknownError
                                        actions.append(TextAlertAction(type: .defaultAction, title: strongSelf.presentationData.strings.Common_OK, action: {}))
                                    case .generic(_):
                                        text = strongSelf.presentationData.strings.Login_UnknownError
                                        actions.append(TextAlertAction(type: .genericAction, title: strongSelf.presentationData.strings.Common_OK, action: {}))
                                        actions.append(TextAlertAction(type: .defaultAction, title: strongSelf.presentationData.strings.Login_PhoneNumberHelp, action: {
                                            guard let strongSelf = self else {
                                                return
                                            }
                                            strongSelf.sharedContext.applicationBindings.openUrl(TellomiLoginChrome.helpURL)
                                        }))
                                    case .timeout:
                                        text = strongSelf.presentationData.strings.Login_NetworkError
                                        actions.append(TextAlertAction(type: .defaultAction, title: strongSelf.presentationData.strings.Common_OK, action: {}))
                                        actions.append(TextAlertAction(type: .genericAction, title: strongSelf.presentationData.strings.ChatSettings_ConnectionType_UseProxy, action: { [weak controller] in
                                            guard let strongSelf = self, let controller = controller else {
                                                return
                                            }
                                            controller.present(strongSelf.sharedContext.makeProxySettingsController(sharedContext: strongSelf.sharedContext, account: strongSelf.account), in: .window(.root), with: ViewControllerPresentationArguments(presentationAnimation: .modalSheet))
                                        }))
                                }
                                (controller.navigationController as? NavigationController)?.presentOverlay(controller: textAlertController(sharedContext: strongSelf.sharedContext, title: nil, text: text, actions: actions), inGlobal: true, blockInteraction: true)
                                
                                controller.dismissConfirmation()
                            }
                        }))
                    }
                }))
            }
            controller.loginWithPasskey = { [weak self, weak controller] passkey, syncContacts in
                guard let self else {
                    return
                }
                
                self.actionDisposable.set((authorizeWithPasskey(
                    accountManager: self.sharedContext.accountManager,
                    account: self.account,
                    passkey: passkey,
                    foreignDatacenter: nil,
                    forcedPasswordSetupNotice: { value in
                        guard let entry = EngineCodableEntry(ApplicationSpecificCounterNotice(value: value)) else {
                            return nil
                        }
                        return (ApplicationSpecificNotice.forcedPasswordSetupKey(), entry)
                    },
                    syncContacts: syncContacts
                )
                |> deliverOnMainQueue).startStrict(next: { [weak self] result in
                    guard let self else {
                        return
                    }
                    if result.updatedAccount !== self.account {
                        self.account = result.updatedAccount
                        self.inAppPurchaseManager = InAppPurchaseManager(engine: .unauthorized(self.engine))
                    }
                }, error: { [weak self, weak controller] error in
                    Queue.mainQueue().async {
                        if let strongSelf = self, let controller {
                            let text: String
                            switch error {
                            case .limitExceeded:
                                text = strongSelf.presentationData.strings.Login_CodeFloodError
                            case .generic, .invalidEmailAddress, .codeExpired, .invalidEmailToken, .invalidCode:
                                text = strongSelf.presentationData.strings.Login_UnknownError
                            }
                            
                            controller.present(textAlertController(sharedContext: strongSelf.sharedContext, title: nil, text: text, actions: [TextAlertAction(type: .defaultAction, title: strongSelf.presentationData.strings.Common_OK, action: {})]), in: .window(.root))
                        }
                    }
                }))
            }
        }
        controller.updateData(countryCode: countryCode, countryName: nil, number: number)
        return controller
    }
    
    private func codeEntryController(number: String, phoneCodeHash: String, email: String?, type: SentAuthorizationCodeType, nextType: AuthorizationCodeNextType?, timeout: Int32?, previousCodeType: SentAuthorizationCodeType?, isPrevious: Bool, termsOfService: (UnauthorizedAccountTermsOfService, Bool)?) -> AuthorizationSequenceCodeEntryController {
        var currentController: AuthorizationSequenceCodeEntryController?
        for c in self.viewControllers {
            if let c = c as? AuthorizationSequenceCodeEntryController {
                if c.data?.2 == type {
                    currentController = c
                }
                break
            }
        }
        let controller: AuthorizationSequenceCodeEntryController
        if let currentController = currentController {
            controller = currentController
        } else {
            controller = AuthorizationSequenceCodeEntryController(sharedContext: self.sharedContext, presentationData: self.presentationData, back: { [weak self] in
                guard let strongSelf = self else {
                    return
                }
                strongSelf.returnToPhoneOrEmailEntry()
            })
            controller.retryResetEmail = { [weak self] in
                if let self {
                    self.actionDisposable.set(
                        resetLoginEmail(account: self.account, phoneNumber: number, phoneCodeHash: phoneCodeHash).startStandalone()
                    )
                }
            }
            controller.resetEmail = { [weak self, weak controller] in
                if let self, case let .email(pattern, _, resetAvailablePeriod, resetPendingDate, _, setup) = type, !setup {
                    let body = MarkdownAttributeSet(font: Font.regular(self.presentationData.listsFontSize.baseDisplaySize * 13.0 / 17.0), textColor: self.presentationData.theme.actionSheet.primaryTextColor)
                    let bold = MarkdownAttributeSet(font: Font.semibold(self.presentationData.listsFontSize.baseDisplaySize * 13.0 / 17.0), textColor: self.presentationData.theme.actionSheet.primaryTextColor)
                    if let _ = resetPendingDate {
                        self.actionDisposable.set(
                            (resetLoginEmail(account: self.account, phoneNumber: number, phoneCodeHash: phoneCodeHash)
                            |> deliverOnMainQueue).startStrict(error: { [weak self] error in
                                if let self, case .alreadyInProgress = error {
                                    let formattedNumber = formatPhoneNumber(number)
                                    let title = NSAttributedString(string: self.presentationData.strings.Login_Email_PremiumRequiredTitle, font: Font.semibold(self.presentationData.listsFontSize.baseDisplaySize), textColor: self.presentationData.theme.actionSheet.primaryTextColor, paragraphAlignment: .center)
                                    let text = parseMarkdownIntoAttributedString(self.presentationData.strings.Login_Email_PremiumRequiredText(formattedNumber).string, attributes: MarkdownAttributes(body: body, bold: bold, link: body, linkAttribute: { _ in nil }), textAlignment: .center).mutableCopy() as! NSMutableAttributedString
                                    
                                    let alertController = textWithEntitiesAlertController(theme: AlertControllerTheme(presentationData: self.presentationData), title: title, text: text, actions: [TextAlertAction(type: .genericAction, title: self.presentationData.strings.Common_OK, action: { })])
                                    controller?.present(alertController, in: .window(.root))
                                }
                            })
                        )
                    } else if let resetAvailablePeriod {
                        if resetAvailablePeriod == 0 {
                            self.actionDisposable.set(
                                resetLoginEmail(account: self.account, phoneNumber: number, phoneCodeHash: phoneCodeHash).startStrict()
                            )
                        } else {
                            let pattern = pattern.replacingOccurrences(of: "*", with: "#")
                            let title = NSAttributedString(string: self.presentationData.strings.Login_Email_ResetTitle, font: Font.semibold(self.presentationData.listsFontSize.baseDisplaySize), textColor: self.presentationData.theme.actionSheet.primaryTextColor)
                            let availableIn = unmuteIntervalString(strings: self.presentationData.strings, value: resetAvailablePeriod)
                            let text = parseMarkdownIntoAttributedString(self.presentationData.strings.Login_Email_ResetText(pattern, availableIn).string, attributes: MarkdownAttributes(body: body, bold: bold, link: body, linkAttribute: { _ in nil }), textAlignment: .center).mutableCopy() as! NSMutableAttributedString
                            if let regex = try? NSRegularExpression(pattern: "\\#", options: []) {
                                let matches = regex.matches(in: text.string, options: [], range: NSMakeRange(0, text.length))
                                if let first = matches.first {
                                    text.addAttribute(NSAttributedString.Key(rawValue: TelegramTextAttributes.Spoiler), value: true, range: NSRange(location: first.range.location, length: matches.count))
                                }
                            }
                            
                            let alertController = textWithEntitiesAlertController(theme: AlertControllerTheme(presentationData: self.presentationData), title: title, text: text, actions: [TextAlertAction(type: .genericAction, title: self.presentationData.strings.Common_Cancel, action: {}), TextAlertAction(type: .defaultAction, title: self.presentationData.strings.Login_Email_Reset, action: { [weak self] in
                                guard let self else {
                                    return
                                }
                                self.actionDisposable.set(
                                    (resetLoginEmail(account: self.account, phoneNumber: number, phoneCodeHash: phoneCodeHash)
                                     |> deliverOnMainQueue).startStrict(error: { [weak self] error in
                                         Queue.mainQueue().async {
                                             guard let self, let controller = controller else {
                                                 return
                                             }
                                             controller.inProgress = false
                                             
                                             let text: String
                                             switch error {
                                             case .limitExceeded:
                                                 text = self.presentationData.strings.Login_CodeFloodError
                                             case .generic, .alreadyInProgress:
                                                 text = self.presentationData.strings.Login_UnknownError
                                             case .codeExpired:
                                                 text = self.presentationData.strings.Login_CodeExpired
                                                 let account = self.account
                                                 let _ = self.engine.auth.setState(state: UnauthorizedAccountState(isTestingEnvironment: account.testingEnvironment, masterDatacenterId: account.masterDatacenterId, contents: .empty)).startStandalone()
                                             }
                                             
                                             controller.presentInGlobalOverlay(textAlertController(sharedContext: self.sharedContext, title: nil, text: text, actions: [TextAlertAction(type: .defaultAction, title: self.presentationData.strings.Common_OK, action: {})]))
                                         }
                                     })
                                )
                            })])
                            controller?.present(alertController, in: .window(.root))
                        }
                    }
                }
            }
            controller.loginWithCode = { [weak self, weak controller] code in
                if let strongSelf = self {
                    controller?.inProgress = true
                    
                    let authorizationCode: AuthorizationCode
                    switch type {
                        case .email:
                            authorizationCode = .emailVerification(.emailCode(code))
                        default:
                            authorizationCode = .phoneCode(code)
                    }
                    
                    if case let .email(_, _, _, _, _, setup) = type, setup, case let .emailVerification(emailCode) = authorizationCode {
                        strongSelf.actionDisposable.set(((verifyLoginEmailSetup(account: strongSelf.account, code: emailCode))
                        |> deliverOnMainQueue).startStrict(error: { error in
                            Queue.mainQueue().async {
                                if let strongSelf = self, let controller = controller {
                                    controller.inProgress = false
                                    
                                    if case .invalidCode = error {
                                        controller.animateError(text: strongSelf.presentationData.strings.Login_WrongCodeError)
                                    } else {
                                        var resetCode = false
                                        let text: String
                                        switch error {
                                            case .limitExceeded:
                                                resetCode = true
                                                text = strongSelf.presentationData.strings.Login_CodeFloodError
                                            case .invalidCode:
                                                resetCode = true
                                                text = strongSelf.presentationData.strings.Login_InvalidCodeError
                                            case .generic:
                                                text = strongSelf.presentationData.strings.Login_UnknownError
                                            case .codeExpired:
                                                text = strongSelf.presentationData.strings.Login_CodeExpired
                                                let account = strongSelf.account
                                                let _ = strongSelf.engine.auth.setState(state: UnauthorizedAccountState(isTestingEnvironment: account.testingEnvironment, masterDatacenterId: account.masterDatacenterId, contents: .empty)).startStandalone()
                                            case .timeout:
                                                text = strongSelf.presentationData.strings.Login_NetworkError
                                            case .invalidEmailToken:
                                                text = strongSelf.presentationData.strings.Login_InvalidEmailTokenError
                                            case .emailNotAllowed:
                                                text = strongSelf.presentationData.strings.Login_EmailNotAllowedError
                                        }
                                        
                                        if resetCode {
                                            controller.resetCode()
                                        }
                                        
                                        controller.present(textAlertController(sharedContext: strongSelf.sharedContext, title: nil, text: text, actions: [TextAlertAction(type: .defaultAction, title: strongSelf.presentationData.strings.Common_OK, action: {})]), in: .window(.root))
                                    }
                                }
                            }
                        }))
                    } else {
                        strongSelf.actionDisposable.set((authorizeWithCode(accountManager: strongSelf.sharedContext.accountManager, account: strongSelf.account, code: authorizationCode, termsOfService: termsOfService?.0, forcedPasswordSetupNotice: { value in
                            guard let entry = EngineCodableEntry(ApplicationSpecificCounterNotice(value: value)) else {
                                return nil
                            }
                            return (ApplicationSpecificNotice.forcedPasswordSetupKey(), entry)
                        })
                        |> deliverOnMainQueue).startStrict(next: { result in
                            guard let strongSelf = self else {
                                return
                            }
                            switch result {
                                case let .signUp(data):
                                    if let (termsOfService, explicit) = termsOfService, explicit {
                                        var presentAlertAgainImpl: (() -> Void)?
                                        let presentAlertImpl: () -> Void = {
                                            guard let strongSelf = self else {
                                                return
                                            }
                                            var dismissImpl: (() -> Void)?
                                            let alertTheme = AlertControllerTheme(presentationData: strongSelf.presentationData)
                                            let attributedText = stringWithAppliedEntities(termsOfService.text, entities: termsOfService.entities, baseColor: alertTheme.primaryColor, linkColor: alertTheme.accentColor, baseFont: Font.regular(13.0), linkFont: Font.regular(13.0), boldFont: Font.semibold(13.0), italicFont: Font.italic(13.0), boldItalicFont: Font.semiboldItalic(13.0), fixedFont: Font.regular(13.0), blockQuoteFont: Font.regular(13.0), message: nil)
                                            let contentNode = TextAlertContentNode(theme: alertTheme, title: NSAttributedString(string: strongSelf.presentationData.strings.Login_TermsOfServiceHeader, font: Font.medium(17.0), textColor: alertTheme.primaryColor, paragraphAlignment: .center), text: attributedText, actions: [
                                                TextAlertAction(type: .defaultAction, title: strongSelf.presentationData.strings.Login_TermsOfServiceAgree, action: {
                                                    dismissImpl?()
                                                    guard let strongSelf = self else {
                                                        return
                                                    }
                                                    let _ = beginSignUp(account: strongSelf.account, data: data).startStandalone()
                                                }), TextAlertAction(type: .genericAction, title: strongSelf.presentationData.strings.Login_TermsOfServiceDecline, action: {
                                                    dismissImpl?()
                                                    guard let strongSelf = self else {
                                                        return
                                                    }
                                                    strongSelf.currentWindow?.present(standardTextAlertController(theme: alertTheme, title: strongSelf.presentationData.strings.Login_TermsOfServiceDecline, text: strongSelf.presentationData.strings.Login_TermsOfServiceSignupDecline, actions: [TextAlertAction(type: .defaultAction, title: strongSelf.presentationData.strings.Common_Cancel, action: {
                                                        presentAlertAgainImpl?()
                                                    }), TextAlertAction(type: .genericAction, title: strongSelf.presentationData.strings.Login_TermsOfServiceDecline, action: {
                                                        guard let strongSelf = self else {
                                                            return
                                                        }
                                                        let account = strongSelf.account
                                                        let _ = strongSelf.engine.auth.setState(state: UnauthorizedAccountState(isTestingEnvironment: account.testingEnvironment, masterDatacenterId: account.masterDatacenterId, contents: .empty)).startStandalone()
                                                    })]), on: .root, blockInteraction: false, completion: {})
                                                })
                                            ], actionLayout: .vertical, dismissOnOutsideTap: true)
                                            contentNode.textAttributeAction = (NSAttributedString.Key(rawValue: TelegramTextAttributes.URL), { value in
                                                if let value = value as? String {
                                                    strongSelf.openUrl(value)
                                                }
                                            })
                                            let controller = AlertController(theme: alertTheme, contentNode: contentNode)
                                            dismissImpl = { [weak controller] in
                                                controller?.dismissAnimated()
                                            }
                                            strongSelf.view.endEditing(true)
                                            strongSelf.currentWindow?.present(controller, on: .root, blockInteraction: false, completion: {})
                                        }
                                        presentAlertAgainImpl = {
                                            presentAlertImpl()
                                        }
                                        presentAlertImpl()
                                    } else {
                                        let _ = beginSignUp(account: strongSelf.account, data: data).startStandalone()
                                    }
                                case .loggedIn:
                                    controller?.animateSuccess()
                            }
                        }, error: { error in
                            Queue.mainQueue().async {
                                if let strongSelf = self, let controller = controller {
                                    controller.inProgress = false
                                    
                                    if case .invalidCode = error {
                                        let text: String
                                        switch type {
                                        case .word, .phrase:
                                            text = strongSelf.presentationData.strings.Login_WrongPhraseError
                                            controller.selectIncorrectPart()
                                        default:
                                            text = strongSelf.presentationData.strings.Login_WrongCodeError
                                        }
                                        controller.animateError(text: text)
                                    } else {
                                        var resetCode = false
                                        let text: String
                                        switch error {
                                            case .limitExceeded:
                                                resetCode = true
                                                text = strongSelf.presentationData.strings.Login_CodeFloodError
                                            case .invalidCode:
                                                resetCode = true
                                                text = strongSelf.presentationData.strings.Login_InvalidCodeError
                                            case .generic:
                                                text = strongSelf.presentationData.strings.Login_UnknownError
                                            case .codeExpired:
                                                text = strongSelf.presentationData.strings.Login_CodeExpired
                                                let account = strongSelf.account
                                                let _ = strongSelf.engine.auth.setState(state: UnauthorizedAccountState(isTestingEnvironment: account.testingEnvironment, masterDatacenterId: account.masterDatacenterId, contents: .empty)).startStandalone()
                                            case .invalidEmailToken:
                                                text = strongSelf.presentationData.strings.Login_InvalidEmailTokenError
                                            case .invalidEmailAddress:
                                                text = strongSelf.presentationData.strings.Login_InvalidEmailAddressError
                                        }
                                        
                                        if resetCode {
                                            controller.resetCode()
                                        }
                                        
                                        controller.present(textAlertController(sharedContext: strongSelf.sharedContext, title: nil, text: text, actions: [TextAlertAction(type: .defaultAction, title: strongSelf.presentationData.strings.Common_OK, action: {})]), in: .window(.root))
                                    }
                                }
                            }
                        }))
                    }
                }
            }
        }
        controller.requestNextOption = { [weak self, weak controller] in
            if let strongSelf = self {
                if previousCodeType != nil && isPrevious {
                    strongSelf.actionDisposable.set(togglePreviousCodeEntry(account: strongSelf.account).start())
                    return
                }
                
                if nextType == nil {
                    if let controller {
                        let carrier = CTCarrier()
                        let mnc = carrier.mobileNetworkCode ?? "none"
                        let _ = strongSelf.engine.auth.reportMissingCode(phoneNumber: number, phoneCodeHash: phoneCodeHash, mnc: mnc).start()
                        
                        AuthorizationSequenceController.presentDidNotGetCodeUI(sharedContext: strongSelf.sharedContext, controller: controller, presentationData: strongSelf.presentationData, phoneNumber: number, mnc: mnc)
                    }
                } else {
                    controller?.inProgress = true
                    strongSelf.actionDisposable.set((resendAuthorizationCode(accountManager: strongSelf.sharedContext.accountManager, account: strongSelf.account, apiId: strongSelf.apiId, apiHash: strongSelf.apiHash, firebaseSecretStream: strongSelf.sharedContext.firebaseSecretStream, attempt: strongSelf.tellomiActiveLoginAttempt)
                    |> deliverOnMainQueue).startStrict(next: { result in
                        controller?.inProgress = false
                    }, error: { error in
                        if let strongSelf = self, let controller = controller {
                            controller.inProgress = false
                            
                            var actions: [TextAlertAction] = [TextAlertAction(type: .defaultAction, title: strongSelf.presentationData.strings.Common_OK, action: {})]
                            
                            let text: String
                            switch error {
                                case .limitExceeded:
                                    text = strongSelf.presentationData.strings.Login_CodeFloodError
                                case .invalidPhoneNumber:
                                    text = strongSelf.presentationData.strings.Login_InvalidPhoneError
                                case .phoneLimitExceeded:
                                    text = strongSelf.presentationData.strings.Login_PhoneFloodError
                                case .appOutdated:
                                    text = strongSelf.presentationData.strings.Login_ErrorAppOutdated
                                    let updateUrl = strongSelf.presentationData.strings.InviteText_URL
                                    let sharedContext = strongSelf.sharedContext
                                    actions = [TextAlertAction(type: .defaultAction, title: strongSelf.presentationData.strings.Common_OK, action: {
                                        sharedContext.applicationBindings.openUrl(updateUrl)
                                    })]
                                case .phoneBanned:
                                    text = strongSelf.presentationData.strings.Login_PhoneBannedError
                                case .generic:
                                    text = strongSelf.presentationData.strings.Login_UnknownError
                                case .timeout:
                                    text = strongSelf.presentationData.strings.Login_NetworkError
                            }
                            
                            controller.present(textAlertController(sharedContext: strongSelf.sharedContext, title: nil, text: text, actions: actions), in: .window(.root))
                        }
                    }))
                }
            }
        }
        controller.requestPreviousOption = { [weak self] in
            guard let self else {
                return
            }
            self.actionDisposable.set(togglePreviousCodeEntry(account: self.account).start())
        }
        controller.reset = { [weak self] in
            guard let self else {
                return
            }
            let _ = self.engine.auth.setState(state: UnauthorizedAccountState(isTestingEnvironment: self.account.testingEnvironment, masterDatacenterId: self.account.masterDatacenterId, contents: .empty)).startStandalone()
        }
        controller.signInWithApple = { [weak self] in
            guard let strongSelf = self else {
                return
            }
            
            strongSelf.signInWithAppleSetup = false
            
            if #available(iOS 13.0, *) {
                let appleIdProvider = ASAuthorizationAppleIDProvider()
                let request = appleIdProvider.createRequest()
                request.requestedScopes = [.email]
                request.user = number
                 
                let authorizationController = ASAuthorizationController(authorizationRequests: [request])
                authorizationController.delegate = strongSelf
                authorizationController.presentationContextProvider = strongSelf
                authorizationController.performRequests()
            }
        }
        controller.openFragment = { [weak self] url in
            if let strongSelf = self {
                strongSelf.sharedContext.applicationBindings.openUrl(url)
            }
        }
        let displayedNumber = tellomiIsLoginEmail(number) ? tellomiNormalizedLoginEmail(number) : formatPhoneNumber(number)
        let displayedEmail = email ?? (tellomiIsLoginEmail(number) ? tellomiNormalizedLoginEmail(number) : nil)
        controller.updateData(number: displayedNumber, email: displayedEmail, codeType: type, nextType: nextType, timeout: timeout, termsOfService: termsOfService, previousCodeType: previousCodeType, isPrevious: isPrevious)
        return controller
    }
    
    private var signInWithAppleSetup = false
    private var appleSignInAllowed = false
    private var currentEmail: String?
    /// The identifier of the login in progress. An email is put back into the phone-entry state on Back.
    private var tellomiActiveLoginNumber: String = ""
    /// Bumped on each send and on Back. A response whose id no longer matches does not write a code hash.
    private let tellomiLoginAttemptToken = Atomic<Int>(value: 0)
    private var tellomiLoginAttemptId: Int = 0
    private var tellomiPendingIdentifier: String?

    private func tellomiBeginLoginAttempt(identifier: String) -> TellomiLoginAttempt {
        let id = self.tellomiLoginAttemptToken.modify { $0 + 1 }
        self.tellomiLoginAttemptId = id
        self.tellomiPendingIdentifier = identifier
        return TellomiLoginAttempt(token: self.tellomiLoginAttemptToken, id: id)
    }

    private var tellomiActiveLoginAttempt: TellomiLoginAttempt {
        return TellomiLoginAttempt(token: self.tellomiLoginAttemptToken, id: self.tellomiLoginAttemptId)
    }

    /// Back, close, and a new number invalidate the in-flight `auth.sendCode`.
    private func tellomiAbandonPendingLogin() {
        let _ = self.tellomiLoginAttemptToken.modify { $0 + 1 }
        self.tellomiPendingIdentifier = nil
        self.actionDisposable.set(nil)
    }

    private func tellomiCodeEntryBelongsToThisAttempt(_ number: String) -> Bool {
        guard let pending = self.tellomiPendingIdentifier, tellomiLoginIdentifiersMatch(pending, number) else {
            return false
        }
        return self.tellomiActiveLoginAttempt.isCurrent()
    }

    /// Country calling code plus the national number, for the phone field after a dropped code screen.
    private func tellomiPhoneEntryParts(identifier: String) -> (countryCode: Int32, number: String) {
        if tellomiIsLoginEmail(identifier) {
            return (AuthorizationSequenceCountrySelectionController.defaultCountryCode(), tellomiNormalizedLoginEmail(identifier))
        }
        let digits = identifier.filter { $0 >= "0" && $0 <= "9" }
        if let (_, countryCode) = AuthorizationSequenceCountrySelectionController.lookupCountryIdByNumber(digits, preferredCountries: ["86": "CN"]), let code = Int32(countryCode.code), digits.hasPrefix(countryCode.code) {
            return (code, String(digits.dropFirst(countryCode.code.count)))
        }
        let fallback = AuthorizationSequenceCountrySelectionController.defaultCountryCode()
        let prefix = String(fallback)
        if digits.hasPrefix(prefix) {
            return (fallback, String(digits.dropFirst(prefix.count)))
        }
        return (fallback, digits)
    }

    /// A code screen saved by a previous launch, or a response for a number the user already left.
    /// The hash is dropped. The number stays in the phone field so they can send a new code.
    private func tellomiDropPersistedCodeEntry(identifier: String) {
        let parts = self.tellomiPhoneEntryParts(identifier: identifier)
        let _ = self.engine.auth.replaceConfirmationCodeEntryWithPhoneEntry(countryCode: parts.countryCode, number: parts.number).startStandalone()
    }

    private func returnToPhoneOrEmailEntry() {
        self.tellomiAbandonPendingLogin()
        let countryCode = AuthorizationSequenceCountrySelectionController.defaultCountryCode()
        let restored = tellomiIsLoginEmail(self.tellomiActiveLoginNumber) ? tellomiNormalizedLoginEmail(self.tellomiActiveLoginNumber) : ""
        let _ = self.engine.auth.setState(state: UnauthorizedAccountState(isTestingEnvironment: self.account.testingEnvironment, masterDatacenterId: self.account.masterDatacenterId, contents: .phoneEntry(countryCode: countryCode, number: restored))).startStandalone()
    }
    
    private func emailSetupController(number: String, appleSignInAllowed: Bool) -> AuthorizationSequenceEmailEntryController {
        var currentController: AuthorizationSequenceEmailEntryController?
        for c in self.viewControllers {
            if let c = c as? AuthorizationSequenceEmailEntryController {
                currentController = c
                break
            }
        }
        let controller: AuthorizationSequenceEmailEntryController
        if let currentController = currentController {
            controller = currentController
        } else {
            controller = AuthorizationSequenceEmailEntryController(presentationData: self.presentationData, mode: .setup, back: { [weak self] in
                guard let strongSelf = self else {
                    return
                }
                strongSelf.returnToPhoneOrEmailEntry()
            })
        }
        controller.proceedWithEmail = { [weak self, weak controller] email in
            guard let strongSelf = self else {
                return
            }
            
            controller?.inProgress = true
            
            strongSelf.currentEmail = email
            
            strongSelf.actionDisposable.set((sendLoginEmailCode(account: strongSelf.account, email: email)
            |> deliverOnMainQueue).startStrict(error: { error in
                if let strongSelf = self, let controller = controller {
                    controller.inProgress = false
                    
                    let text: String
                    switch error {
                        case .limitExceeded:
                            text = strongSelf.presentationData.strings.Login_CodeFloodError
                        case .generic, .codeExpired:
                            text = strongSelf.presentationData.strings.Login_UnknownError
                        case .timeout:
                            text = strongSelf.presentationData.strings.Login_NetworkError
                        case .invalidEmail:
                            text = strongSelf.presentationData.strings.Login_InvalidEmailError
                        case .emailNotAllowed:
                            text = strongSelf.presentationData.strings.Login_EmailNotAllowedError
                    }
                    
                    controller.present(textAlertController(sharedContext: strongSelf.sharedContext, title: nil, text: text, actions: [TextAlertAction(type: .defaultAction, title: strongSelf.presentationData.strings.Common_OK, action: {})]), in: .window(.root))
                }
            }, completed: {
                controller?.inProgress = false
            }))
        }
        controller.signInWithApple = { [weak self] in
            guard let strongSelf = self else {
                return
            }
            
            strongSelf.signInWithAppleSetup = true
            
            if #available(iOS 13.0, *) {
                let appleIdProvider = ASAuthorizationAppleIDProvider()
                let request = appleIdProvider.createRequest()
                request.requestedScopes = [.email]
                request.user = number
                 
                let authorizationController = ASAuthorizationController(authorizationRequests: [request])
                authorizationController.delegate = strongSelf
                authorizationController.presentationContextProvider = strongSelf
                authorizationController.performRequests()
            }
        }
        controller.updateData(appleSignInAllowed: appleSignInAllowed)
        return controller
    }
    
    private func paymentController(number: String, phoneCodeHash: String, storeProduct: String, premiumDays: Int32, supportEmailAddress: String, supportEmailSubject: String) -> AuthorizationSequencePaymentScreen {
        let controller = AuthorizationSequencePaymentScreen(sharedContext: self.sharedContext, engine: self.engine, presentationData: self.presentationData, inAppPurchaseManager: self.inAppPurchaseManager, phoneNumber: number, phoneCodeHash: phoneCodeHash, storeProduct: storeProduct, premiumDays: premiumDays, supportEmailAddress: supportEmailAddress, supportEmailSubject: supportEmailSubject, back: { [weak self] in
            guard let self else {
                return
            }
            self.returnToPhoneOrEmailEntry()
        })
        return controller
    }
    
    @available(iOS 13.0, *)
    public func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        let lastController = self.viewControllers.last as? ViewController
        
        switch authorization.credential {
            case let appleIdCredential as ASAuthorizationAppleIDCredential:
                guard let tokenData = appleIdCredential.identityToken, let token = String(data: tokenData, encoding: .utf8) else {
                    lastController?.present(textAlertController(sharedContext: self.sharedContext, title: nil, text: self.presentationData.strings.Login_UnknownError, actions: [TextAlertAction(type: .defaultAction, title: self.presentationData.strings.Common_OK, action: {})]), in: .window(.root))
                    return
                }
            
            if self.signInWithAppleSetup {
                self.actionDisposable.set((verifyLoginEmailSetup(account: self.account, code: .appleToken(token))
                |> deliverOnMainQueue).startStrict(error: { [weak self, weak lastController] error in
                    if let strongSelf = self, let lastController = lastController {
                        let text: String
                        switch error {
                            case .limitExceeded:
                                text = strongSelf.presentationData.strings.Login_CodeFloodError
                            case .generic, .codeExpired:
                                text = strongSelf.presentationData.strings.Login_UnknownError
                            case .invalidCode:
                                text = strongSelf.presentationData.strings.Login_InvalidCodeError
                            case .timeout:
                                text = strongSelf.presentationData.strings.Login_NetworkError
                            case .invalidEmailToken:
                                text = strongSelf.presentationData.strings.Login_InvalidEmailTokenError
                            case .emailNotAllowed:
                                text = strongSelf.presentationData.strings.Login_EmailNotAllowedError
                        }
                        lastController.present(textAlertController(sharedContext: strongSelf.sharedContext, title: nil, text: text, actions: [TextAlertAction(type: .genericAction, title: strongSelf.presentationData.strings.Common_OK, action: {})]), in: .window(.root))
                    }
                }))
            } else {
                self.actionDisposable.set(
                    authorizeWithCode(accountManager: self.sharedContext.accountManager, account: self.account, code: .emailVerification(.appleToken(token)), termsOfService: nil, forcedPasswordSetupNotice: { value in
                        guard let entry = EngineCodableEntry(ApplicationSpecificCounterNotice(value: value)) else {
                            return nil
                        }
                        return (ApplicationSpecificNotice.forcedPasswordSetupKey(), entry)
                    }).startStrict(next: { [weak self] result in
                        guard let strongSelf = self else {
                            return
                        }
                        switch result {
                            case let .signUp(data):
                                let _ = beginSignUp(account: strongSelf.account, data: data).startStandalone()
                            case .loggedIn:
                                break
                        }
                    }, error: { [weak self, weak lastController] error in
                        Queue.mainQueue().async {
                            if let strongSelf = self, let lastController = lastController {
                                let text: String
                                switch error {
                                    case .limitExceeded:
                                        text = strongSelf.presentationData.strings.Login_CodeFloodError
                                    case .invalidCode:
                                        text = strongSelf.presentationData.strings.Login_InvalidCodeError
                                    case .generic:
                                        text = strongSelf.presentationData.strings.Login_UnknownError
                                    case .codeExpired:
                                        text = strongSelf.presentationData.strings.Login_CodeExpired
                                        let account = strongSelf.account
                                        let _ = strongSelf.engine.auth.setState(state: UnauthorizedAccountState(isTestingEnvironment: account.testingEnvironment, masterDatacenterId: account.masterDatacenterId, contents: .empty)).startStandalone()
                                    case .invalidEmailToken:
                                        text = strongSelf.presentationData.strings.Login_InvalidEmailTokenError
                                    case .invalidEmailAddress:
                                        text = strongSelf.presentationData.strings.Login_InvalidEmailAddressError
                                }
                                
                                lastController.present(textAlertController(sharedContext: strongSelf.sharedContext, title: nil, text: text, actions: [TextAlertAction(type: .defaultAction, title: strongSelf.presentationData.strings.Common_OK, action: {})]), in: .window(.root))
                            }
                        }
                    })
                )
            }
            default:
                break
        }
    }
    
    @available(iOS 13.0, *)
    public func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        guard let lastController = self.viewControllers.last as? ViewController else {
            return
        }
        lastController.present(textAlertController(sharedContext: self.sharedContext, title: nil, text: error.localizedDescription, actions: [TextAlertAction(type: .defaultAction, title: self.presentationData.strings.Common_OK, action: {})]), in: .window(.root))
    }
    
    @available(iOS 13.0, *)
    public func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        return self.view.window!
    }
    
    private func passwordEntryController(hint: String, suggestReset: Bool, syncContacts: Bool) -> AuthorizationSequencePasswordEntryController {
        var currentController: AuthorizationSequencePasswordEntryController?
        for c in self.viewControllers {
            if let c = c as? AuthorizationSequencePasswordEntryController {
                currentController = c
                break
            }
        }
        let controller: AuthorizationSequencePasswordEntryController
        if let currentController = currentController {
            controller = currentController
        } else {
            controller = AuthorizationSequencePasswordEntryController(sharedContext: self.sharedContext, presentationData: self.presentationData, back: { [weak self] in
                guard let strongSelf = self else {
                    return
                }
                strongSelf.returnToPhoneOrEmailEntry()
            })
            controller.loginWithPassword = { [weak self, weak controller] password in
                if let strongSelf = self {
                    controller?.inProgress = true
                    
                    strongSelf.actionDisposable.set((authorizeWithPassword(accountManager: strongSelf.sharedContext.accountManager, account: strongSelf.account, password: password, syncContacts: syncContacts) |> deliverOnMainQueue).startStrict(error: { error in
                        Queue.mainQueue().async {
                            if let strongSelf = self, let controller = controller {
                                controller.inProgress = false
                                
                                let text: String
                                switch error {
                                    case .limitExceeded:
                                        text = strongSelf.presentationData.strings.LoginPassword_FloodError
                                    case .invalidPassword:
                                        text = strongSelf.presentationData.strings.LoginPassword_InvalidPasswordError
                                    case .generic:
                                        text = strongSelf.presentationData.strings.Login_UnknownError
                                }
                                
                                controller.present(textAlertController(sharedContext: strongSelf.sharedContext, title: nil, text: text, actions: [TextAlertAction(type: .defaultAction, title: strongSelf.presentationData.strings.Common_OK, action: {})]), in: .window(.root))
                                controller.passwordIsInvalid()
                            }
                        }
                    }))
                }
            }
        }
        controller.forgot = { [weak self, weak controller] in
            if let strongSelf = self, let strongController = controller {
                strongController.inProgress = true
                strongSelf.actionDisposable.set((strongSelf.engine.auth.requestTwoStepVerificationPasswordRecoveryCode()
                |> deliverOnMainQueue).startStrict(next: { pattern in
                    if let strongSelf = self, let strongController = controller {
                        strongController.inProgress = false

                        let _ = (strongSelf.engine.auth.state()
                        |> take(1)
                        |> deliverOnMainQueue).startStandalone(next: { state in
                            guard let strongSelf = self else {
                                return
                            }
                            if case let .unauthorized(state) = state, case let .passwordEntry(hint, number, code, _, syncContacts) = state.contents {
                                let _ = strongSelf.engine.auth.setState(state: UnauthorizedAccountState(isTestingEnvironment: strongSelf.account.testingEnvironment, masterDatacenterId: strongSelf.account.masterDatacenterId, contents: .passwordRecovery(hint: hint, number: number, code: code, emailPattern: pattern, syncContacts: syncContacts))).startStandalone()
                            }
                        })
                    }
                }, error: { error in
                    guard let strongController = controller else {
                        return
                    }

                    strongController.inProgress = false

                    strongController.present(textAlertController(sharedContext: strongSelf.sharedContext, title: nil, text: strongSelf.presentationData.strings.TwoStepAuth_RecoveryUnavailable, actions: [TextAlertAction(type: .defaultAction, title: strongSelf.presentationData.strings.Common_OK, action: {})]), in: .window(.root))
                    strongController.didForgotWithNoRecovery = true
                }))
            }
        }
        controller.reset = { [weak self, weak controller] in
            if let strongSelf = self, let strongController = controller {
                strongController.present(textAlertController(sharedContext: strongSelf.sharedContext, title: nil, text: suggestReset ? strongSelf.presentationData.strings.TwoStepAuth_RecoveryFailed : strongSelf.presentationData.strings.TwoStepAuth_RecoveryUnavailable, actions: [
                    TextAlertAction(type: .genericAction, title: strongSelf.presentationData.strings.Common_Cancel, action: {}),
                    TextAlertAction(type: .destructiveAction, title: strongSelf.presentationData.strings.Login_ResetAccountProtected_Reset, action: {
                        if let strongSelf = self, let strongController = controller {
                            strongController.inProgress = true
                            strongSelf.actionDisposable.set((performAccountReset(account: strongSelf.account)
                            |> deliverOnMainQueue).startStrict(next: {
                                if let strongController = controller {
                                    strongController.inProgress = false
                                }
                            }, error: { error in
                                if let strongSelf = self, let strongController = controller {
                                    strongController.inProgress = false
                                    let text: String
                                    switch error {
                                        case .generic:
                                            text = strongSelf.presentationData.strings.Login_UnknownError
                                        case .limitExceeded:
                                            text = strongSelf.presentationData.strings.Login_ResetAccountProtected_LimitExceeded
                                    }
                                    strongController.present(textAlertController(sharedContext: strongSelf.sharedContext, title: nil, text: text, actions: [TextAlertAction(type: .defaultAction, title: strongSelf.presentationData.strings.Common_OK, action: {})]), in: .window(.root))
                                }
                            }))
                        }
                    })]), in: .window(.root))
            }
        }
        controller.updateData(hint: hint, suggestReset: suggestReset)
        return controller
    }
    
    private func passwordRecoveryController(emailPattern: String, syncContacts: Bool) -> TwoFactorDataInputScreen {
        var currentController: TwoFactorDataInputScreen?
        for c in self.viewControllers {
            if let c = c as? TwoFactorDataInputScreen {
                currentController = c
                break
            }
        }
        let controller: TwoFactorDataInputScreen
        if let currentController = currentController {
            controller = currentController
        } else {
            controller = TwoFactorDataInputScreen(sharedContext: self.sharedContext, engine: .unauthorized(self.engine), mode: .passwordRecoveryEmail(emailPattern: emailPattern, mode: .notAuthorized(syncContacts: syncContacts), doneText: self.presentationData.strings.TwoFactorSetup_Done_Action), stateUpdated: { _ in
            }, presentation: .default)
        }
        controller.passwordRecoveryFailed = { [weak self] in
            guard let strongSelf = self else {
                return
            }

            let _ = (strongSelf.engine.auth.state()
            |> take(1)
            |> deliverOnMainQueue).startStandalone(next: { state in
                guard let strongSelf = self else {
                    return
                }
                if case let .unauthorized(state) = state, case let .passwordRecovery(hint, number, code, _, syncContacts) = state.contents {
                    let _ = strongSelf.engine.auth.setState(state: UnauthorizedAccountState(isTestingEnvironment: strongSelf.account.testingEnvironment, masterDatacenterId: strongSelf.account.masterDatacenterId, contents: .passwordEntry(hint: hint, number: number, code: code, suggestReset: true, syncContacts: syncContacts))).startStandalone()
                }
            })
        }
        return controller
    }
    
    private func awaitingAccountResetController(protectedUntil: Int32, number: String?) -> AuthorizationSequenceAwaitingAccountResetController {
        var currentController: AuthorizationSequenceAwaitingAccountResetController?
        for c in self.viewControllers {
            if let c = c as? AuthorizationSequenceAwaitingAccountResetController {
                currentController = c
                break
            }
        }
        let controller: AuthorizationSequenceAwaitingAccountResetController
        if let currentController = currentController {
            controller = currentController
        } else {
            controller = AuthorizationSequenceAwaitingAccountResetController(strings: self.presentationData.strings, theme: self.presentationData.theme, back: { [weak self] in
                guard let strongSelf = self else {
                    return
                }
                strongSelf.returnToPhoneOrEmailEntry()
            })
            controller.reset = { [weak self, weak controller] in
                if let strongSelf = self, let strongController = controller {
                    strongController.present(textAlertController(sharedContext: strongSelf.sharedContext, title: nil, text: strongSelf.presentationData.strings.TwoStepAuth_ResetAccountConfirmation, actions: [
                        TextAlertAction(type: .genericAction, title: strongSelf.presentationData.strings.Common_Cancel, action: {}),
                        TextAlertAction(type: .destructiveAction, title: strongSelf.presentationData.strings.Login_ResetAccountProtected_Reset, action: {
                            if let strongSelf = self, let strongController = controller {
                                strongController.inProgress = true
                                strongSelf.actionDisposable.set((performAccountReset(account: strongSelf.account)
                                    |> deliverOnMainQueue).startStrict(next: {
                                        if let strongController = controller {
                                            strongController.inProgress = false
                                        }
                                    }, error: { error in
                                        if let strongSelf = self, let strongController = controller {
                                            strongController.inProgress = false
                                            let text: String
                                            switch error {
                                                case .generic:
                                                    text = strongSelf.presentationData.strings.Login_UnknownError
                                                case .limitExceeded:
                                                    text = strongSelf.presentationData.strings.Login_ResetAccountProtected_LimitExceeded
                                            }
                                            strongController.present(textAlertController(sharedContext: strongSelf.sharedContext, title: nil, text: text, actions: [TextAlertAction(type: .defaultAction, title: strongSelf.presentationData.strings.Common_OK, action: {})]), in: .window(.root))
                                        }
                                    }))
                            }
                        })]), in: .window(.root))
                }
            }
            controller.logout = { [weak self] in
                if let strongSelf = self {
                    let account = strongSelf.account
                    let _ = strongSelf.engine.auth.setState(state: UnauthorizedAccountState(isTestingEnvironment: account.testingEnvironment, masterDatacenterId: account.masterDatacenterId, contents: .empty)).startStandalone()
                }
            }
        }
        controller.updateData(protectedUntil: protectedUntil, number: number ?? "")
        return controller
    }
    
    private func signUpController(firstName: String, lastName: String, termsOfService: UnauthorizedAccountTermsOfService?, displayCancel: Bool, loginNumber: String) -> AuthorizationSequenceSignUpController {
        var currentController: AuthorizationSequenceSignUpController?
        for c in self.viewControllers {
            if let c = c as? AuthorizationSequenceSignUpController {
                currentController = c
                break
            }
        }
        let controller: AuthorizationSequenceSignUpController
        if let currentController = currentController {
            controller = currentController
        } else {
            controller = AuthorizationSequenceSignUpController(sharedContext: self.sharedContext, presentationData: self.presentationData, back: { [weak self] in
                guard let strongSelf = self else {
                    return
                }
                strongSelf.returnToPhoneOrEmailEntry()
            }, displayCancel: displayCancel)
            controller.openUrl = { [weak self] url in
                guard let self else {
                    return
                }
                self.openUrl(url)
            }
            controller.signUpWithName = { [weak self, weak controller] firstName, lastName, avatarData, avatarAsset, avatarAdjustments, announceSignUp in
                if let strongSelf = self {
                    controller?.inProgress = true
                    
                    var videoStartTimestamp: Double? = nil
                    if let adjustments = avatarAdjustments, adjustments.videoStartValue > 0.0 {
                        videoStartTimestamp = adjustments.videoStartValue - adjustments.trimStartValue
                    }
                    
                    let avatarVideo: Signal<UploadedPeerPhotoData?, NoError>?
                    if let avatarAsset = avatarAsset as? AVAsset {
                        let engine = strongSelf.engine
                        avatarVideo = Signal<EngineMediaResource?, NoError> { subscriber in
                            let entityRenderer: LegacyPaintEntityRenderer? = avatarAdjustments.flatMap { adjustments in
                                if let paintingData = adjustments.paintingData, paintingData.hasAnimation {
                                    return LegacyPaintEntityRenderer(postbox: nil, adjustments: adjustments)
                                } else {
                                    return nil
                                }
                            }
                            
                            let tempFile = EngineTempBox.shared.tempFile(fileName: "video.mp4")
                            let signal = TGMediaVideoConverter.convert(avatarAsset, adjustments: avatarAdjustments, path: tempFile.path, watcher: nil, entityRenderer: entityRenderer)!
                            
                            let signalDisposable = signal.start(next: { next in
                                if let result = next as? TGMediaVideoConversionResult {
                                    var value = stat()
                                    if stat(result.fileURL.path, &value) == 0 {
                                        if let data = try? Data(contentsOf: result.fileURL) {
                                            let resource = LocalFileMediaResource(fileId: Int64.random(in: Int64.min ... Int64.max))
                                            engine.resources.storeResourceData(id: EngineMediaResource.Id(resource.id), data: data, synchronous: true)
                                            subscriber.putNext(EngineMediaResource(resource))
                                            
                                            EngineTempBox.shared.dispose(tempFile)
                                        }
                                    }
                                    subscriber.putCompletion()
                                }
                            }, error: { _ in
                            }, completed: nil)
                            
                            let disposable = ActionDisposable {
                                signalDisposable?.dispose()
                            }
                            
                            return ActionDisposable {
                                disposable.dispose()
                            }
                        }
                        |> mapToSignal { resource -> Signal<UploadedPeerPhotoData?, NoError> in
                            if let resource = resource {
                                return engine.auth.uploadedPeerVideo(resource: resource) |> map(Optional.init)
                            } else {
                                return .single(nil)
                            }
                        }
                    } else {
                        avatarVideo = nil
                    }
                    
                    strongSelf.actionDisposable.set((signUpWithName(accountManager: strongSelf.sharedContext.accountManager, account: strongSelf.account, firstName: firstName, lastName: lastName, avatarData: avatarData, avatarVideo: avatarVideo, videoStartTimestamp: videoStartTimestamp, disableJoinNotifications: !announceSignUp, forcedPasswordSetupNotice: { value in
                        guard let entry = EngineCodableEntry(ApplicationSpecificCounterNotice(value: value)) else {
                            return nil
                        }
                        return (ApplicationSpecificNotice.forcedPasswordSetupKey(), entry)
                    })
                    |> deliverOnMainQueue).startStrict(error: { error in
                        Queue.mainQueue().async {
                            if let strongSelf = self, let controller = controller {
                                controller.inProgress = false
                                
                                let text: String
                                switch error {
                                    case .limitExceeded:
                                        text = strongSelf.presentationData.strings.Login_CodeFloodError
                                    case .codeExpired:
                                        text = strongSelf.presentationData.strings.Login_CodeExpiredError
                                    case .invalidFirstName:
                                        text = strongSelf.presentationData.strings.Login_InvalidFirstNameError
                                    case .invalidLastName:
                                        text = strongSelf.presentationData.strings.Login_InvalidLastNameError
                                    case .generic:
                                        text = strongSelf.presentationData.strings.Login_UnknownError
                                }
                                
                                controller.present(textAlertController(sharedContext: strongSelf.sharedContext, title: nil, text: text, actions: [TextAlertAction(type: .defaultAction, title: strongSelf.presentationData.strings.Common_OK, action: {})]), in: .window(.root))
                            }
                        }
                    }))
                }
            }
        }
        controller.setTellomiNicknameOnly(tellomiIsLoginEmail(loginNumber))
        controller.updateData(firstName: firstName, lastName: lastName, termsOfService: termsOfService)
        return controller
    }
    
    private func updateState(state: InnerState) {
        if self.tellomiDidAuthorize {
            return
        }
        self.tellomiLatestState = state
        if case .authorized = state {
            self.tellomiDidAuthorize = true
            self.authorizationCompleted()
            return
        }
        // Download zh-hans / zh-hant before the login screens are built. The old Start
        // button stored English, and an update keeps that pack. The intro carousel
        // itself stays the bundled English strings.
        if self.tellomiLanguageGate == 1 {
            return
        } else if self.tellomiLanguageGate == 0, let code = tellomiLangPackCodePendingApplication(currentLanguageCode: self.presentationData.strings.primaryComponent.languageCode) {
            self.tellomiLanguageGate = 1
            let accountManager = self.sharedContext.accountManager
            let signal = TelegramEngineUnauthorized(account: self.account).localization.downloadAndApplyLocalization(accountManager: accountManager, languageCode: code)
            |> timeout(12.0, queue: .mainQueue(), alternate: .fail(.generic))
            self.tellomiLanguageDisposable.set(signal.start(error: { [weak self] _ in
                Queue.mainQueue().async {
                    guard let self else {
                        return
                    }
                    self.tellomiLanguageGate = 2
                    self.updateState(state: self.tellomiLatestState ?? state)
                }
            }, completed: { [weak self] in
                Queue.mainQueue().async {
                    guard let self else {
                        return
                    }
                    tellomiMarkSystemLangPackApplied()
                    self.tellomiLanguageStringsDisposable.set((accountManager.transaction { transaction -> PresentationStrings? in
                        guard let localizationSettings = transaction.getSharedData(SharedDataKeys.localizationSettings)?.get(LocalizationSettings.self) else {
                            return nil
                        }
                        return PresentationStrings(primaryComponent: PresentationStrings.Component(languageCode: localizationSettings.primaryComponent.languageCode, localizedName: localizationSettings.primaryComponent.localizedName, pluralizationRulesCode: localizationSettings.primaryComponent.customPluralizationCode, dict: dictFromLocalization(localizationSettings.primaryComponent.localization)), secondaryComponent: localizationSettings.secondaryComponent.flatMap({ PresentationStrings.Component(languageCode: $0.languageCode, localizedName: $0.localizedName, pluralizationRulesCode: $0.customPluralizationCode, dict: dictFromLocalization($0.localization)) }), groupingSeparator: "")
                    }
                    |> deliverOnMainQueue).start(next: { [weak self] strings in
                        guard let self else {
                            return
                        }
                        if let strings {
                            self.presentationData = self.presentationData.withStrings(strings)
                        }
                        self.tellomiLanguageGate = 2
                        self.updateState(state: self.tellomiLatestState ?? state)
                    }))
                }
            }))
            return
        }
        switch state {
        case .authorized:
            self.authorizationCompleted()
        case let .state(state):
            switch state {
                case .empty:
                    if let _ = self.viewControllers.last as? AuthorizationSequenceSplashController {
                    } else {
                        var controllers: [ViewController] = []
                        if self.otherAccountPhoneNumbers.1.isEmpty {
                            controllers.append(self.splashController())
                        } else {
                            controllers.append(self.phoneEntryController(countryCode: AuthorizationSequenceCountrySelectionController.defaultCountryCode(), number: "", splashController: nil))
                        }
                        self.setViewControllers(controllers, animated: !self.viewControllers.isEmpty)
                    }
                case let .phoneEntry(storedCountryCode, number):
                    // An update keeps the previous unauthorized state. An empty number is still
                    // the automatic default, so replace a stored +1 with China. A typed number
                    // keeps the code it was entered with.
                    let countryCode = number.isEmpty ? AuthorizationSequenceCountrySelectionController.defaultCountryCode() : storedCountryCode
                    var controllers: [ViewController] = []
                    var previousSplashController: AuthorizationSequenceSplashController?
                    for c in self.viewControllers {
                        if let c = c as? AuthorizationSequenceSplashController {
                            previousSplashController = c
                            break
                        }
                    }
                
                    if let validLayout = self.validLayout, case .tablet = validLayout.deviceMetrics.type {
                        previousSplashController = nil
                    }
                
                    controllers.append(self.phoneEntryController(countryCode: countryCode, number: number, splashController: previousSplashController))
                    self.setViewControllers(controllers, animated: !self.viewControllers.isEmpty && (previousSplashController == nil || self.viewControllers.count > 2))
                case let .confirmationCodeEntry(number, type, phoneCodeHash, timeout, nextType, _, previousCodeEntry, usePrevious):
                    // A previous launch, or a sendCode for a number the user already replaced, must not
                    // open the code screen. The hash belongs to that attempt.
                    if !self.tellomiCodeEntryBelongsToThisAttempt(number) {
                        self.tellomiDropPersistedCodeEntry(identifier: number)
                        return
                    }
                    self.tellomiActiveLoginNumber = number
                    let loginEmail = tellomiIsLoginEmail(number) ? tellomiNormalizedLoginEmail(number) : nil
                    var controllers: [ViewController] = []
                    controllers.append(self.phoneEntryController(countryCode: AuthorizationSequenceCountrySelectionController.defaultCountryCode(), number: loginEmail ?? "", splashController: nil))
                
                    var isGoingBack = false
                    if case let .emailSetupRequired(appleSignInAllowed) = type {
                        self.appleSignInAllowed = appleSignInAllowed
                        controllers.append(self.emailSetupController(number: number, appleSignInAllowed: appleSignInAllowed))
                    } else {
                        // currentEmail is the login-email setup screen. An address used as phone_number is the login itself.
                        if self.currentEmail != nil && loginEmail == nil {
                            controllers.append(self.emailSetupController(number: number, appleSignInAllowed: self.appleSignInAllowed))
                        }
                        let codeEmail = loginEmail ?? self.currentEmail
                        
                        if let previousCodeEntry, case let .confirmationCodeEntry(number, previousType, phoneCodeHash, timeout, nextType, _, _, _) = previousCodeEntry, usePrevious {
                            controllers.append(self.codeEntryController(number: number, phoneCodeHash: phoneCodeHash, email: codeEmail, type: previousType, nextType: nextType, timeout: timeout, previousCodeType: type, isPrevious: true, termsOfService: nil))
                            isGoingBack = true
                        } else {
                            var previousCodeType: SentAuthorizationCodeType?
                            if let previousCodeEntry, case let .confirmationCodeEntry(_, type, _, _, _, _, _, _) = previousCodeEntry {
                                previousCodeType = type
                            }
                            controllers.append(self.codeEntryController(number: number, phoneCodeHash: phoneCodeHash, email: codeEmail, type: type, nextType: nextType, timeout: timeout, previousCodeType: previousCodeType, isPrevious: false, termsOfService: nil))
                        }
                    }
                
                    if isGoingBack, let currentLastController = self.viewControllers.last as? AuthorizationSequenceCodeEntryController, !currentLastController.isPrevious {
                        var tempControllers = controllers
                        tempControllers.append(currentLastController)
                        self.setViewControllers(tempControllers, animated: false)
                        Queue.mainQueue().justDispatch {
                            self.setViewControllers(controllers, animated: true)
                        }
                    } else {
                        self.setViewControllers(controllers, animated: !self.viewControllers.isEmpty)
                    }
                case let .passwordEntry(hint, number, _, suggestReset, syncContacts):
                    if let number {
                        self.tellomiActiveLoginNumber = number
                    }
                    var controllers: [ViewController] = []
                    controllers.append(self.passwordEntryController(hint: hint, suggestReset: suggestReset, syncContacts: syncContacts))
                    self.setViewControllers(controllers, animated: !self.viewControllers.isEmpty)
                case let .passwordRecovery(_, _, _, emailPattern, syncContacts):
                    var controllers: [ViewController] = []
                    controllers.append(self.passwordRecoveryController(emailPattern: emailPattern, syncContacts: syncContacts))
                    self.setViewControllers(controllers, animated: !self.viewControllers.isEmpty)
                case let .awaitingAccountReset(protectedUntil, number, _):
                    var controllers: [ViewController] = []
                    controllers.append(self.awaitingAccountResetController(protectedUntil: protectedUntil, number: number))
                    self.setViewControllers(controllers, animated: !self.viewControllers.isEmpty)
                case let .signUp(number, _, firstName, lastName, termsOfService, _):
                    self.tellomiActiveLoginNumber = number
                    var controllers: [ViewController] = []
                    controllers.append(self.signUpController(firstName: firstName, lastName: lastName, termsOfService: termsOfService, displayCancel: true, loginNumber: number))
                    self.setViewControllers(controllers, animated: !self.viewControllers.isEmpty)
                case let .payment(number, codeHash, storeProduct, premiumDays, supportEmailAddress, supportEmailSubject, _):
                    var controllers: [ViewController] = []
                controllers.append(self.paymentController(number: number, phoneCodeHash: codeHash, storeProduct: storeProduct, premiumDays: premiumDays, supportEmailAddress: supportEmailAddress, supportEmailSubject: supportEmailSubject))
                    self.setViewControllers(controllers, animated: !self.viewControllers.isEmpty)
            }
        }
    }
    
    override public func setViewControllers(_ viewControllers: [UIViewController], animated: Bool) {
        let wasEmpty = self.viewControllers.isEmpty
        super.setViewControllers(viewControllers, animated: animated)
        if wasEmpty {
            if self.topViewController is AuthorizationSequenceSplashController {
            } else {
                self.topViewController?.view.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.3)
            }
        }
        if !self.didSetReady {
            self.didSetReady = true
            self._ready.set(.single(true))
        }
    }
    
    public func applyConfirmationCode(_ code: Int) {
        if let controller = self.viewControllers.last as? AuthorizationSequenceCodeEntryController {
            controller.applyConfirmationCode(code)
        }
    }
    
    static func presentEmailComposeController(sharedContext: SharedAccountContext, address: String, subject: String, body: String, from controller: ViewController, presentationData: PresentationData) {
        if MFMailComposeViewController.canSendMail() {
            final class ComposeDelegate: NSObject, MFMailComposeViewControllerDelegate {
                @objc func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
                    controller.dismiss(animated: true, completion: nil)
                }
            }
        
            let composeController = MFMailComposeViewController()
            composeController.setToRecipients([address])
            composeController.setSubject(subject)
            composeController.setMessageBody(body, isHTML: false)
            
            let composeDelegate = ComposeDelegate()
            objc_setAssociatedObject(composeDelegate, &ObjCKey_Delegate, composeDelegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            composeController.mailComposeDelegate = composeDelegate
            
            controller.view.window?.rootViewController?.present(composeController, animated: true, completion: nil)
        } else {
            controller.present(textAlertController(sharedContext: sharedContext, title: nil, text: presentationData.strings.Login_EmailNotConfiguredError, actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]), in: .window(.root))
        }
    }
    
    private func animateIn() {
        if !self.otherAccountPhoneNumbers.1.isEmpty {
            self.view.layer.animatePosition(from: CGPoint(x: self.view.layer.position.x, y: self.view.layer.position.y + self.view.layer.bounds.size.height), to: self.view.layer.position, duration: 0.5, timingFunction: kCAMediaTimingFunctionSpring)
        } else {
            if let splashController = self.topViewController as? AuthorizationSequenceSplashController {
                splashController.animateIn()
            }
        }
    }
    
    private func animateOut(completion: (() -> Void)? = nil) {
        self.view.layer.animatePosition(from: self.view.layer.position, to: CGPoint(x: self.view.layer.position.x, y: self.view.layer.position.y + self.view.layer.bounds.size.height), duration: 0.2, timingFunction: CAMediaTimingFunctionName.easeInEaseOut.rawValue, removeOnCompletion: false, completion: { _ in
            completion?()
        })
    }
    
    override public func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        if !self.didPlayPresentationAnimation {
            self.didPlayPresentationAnimation = true
            self.animateIn()
        }
    }
    
    public func dismiss() {
        self.animateOut(completion: { [weak self] in
            self?.presentingViewController?.dismiss(animated: false, completion: nil)
        })
    }
    
    public static func defaultCountryCode() -> Int32 {
        return AuthorizationSequenceCountrySelectionController.defaultCountryCode()
    }
    
    public static func presentDidNotGetCodeUI(
        sharedContext: SharedAccountContext,
        controller: ViewController,
        presentationData: PresentationData,
        phoneNumber: String,
        mnc: String
    ) {
        let _ = (sharedContext, controller, presentationData, phoneNumber, mnc)
        if let url = URL(string: TellomiLoginChrome.helpURL) {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }
}
