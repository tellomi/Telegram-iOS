import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import PresentationDataUtils
import ProgressNavigationButtonNode
import AccountContext
import CountrySelectionUI
import PhoneNumberFormat
import DebugSettingsUI
import MessageUI
import AuthenticationServices
import UIKitRuntimeUtils

public final class AuthorizationSequencePhoneEntryController: ViewController, MFMailComposeViewControllerDelegate, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var controllerNode: AuthorizationSequencePhoneEntryControllerNode {
        return self.displayNode as! AuthorizationSequencePhoneEntryControllerNode
    }
    
    private var validLayout: ContainerViewLayout?
    
    private let sharedContext: SharedAccountContext
    private var account: UnauthorizedAccount?
    private let apiId: Int32
    private let apiHash: String
    private let isTestingEnvironment: Bool
    private let otherAccountPhoneNumbers: ((String, AccountRecordId, Bool)?, [(String, AccountRecordId, Bool)])
    private let network: Network
    private var presentationData: PresentationData
    private let openUrl: (String) -> Void
    
    private let back: () -> Void
    
    private var currentData: (Int32, String?, String)?
    private var pendingEntry: (Int32, String?, String)?
        
    var codeNode: ASDisplayNode {
        return self.controllerNode.codeNode
    }
    
    var numberNode: ASDisplayNode {
        return self.controllerNode.numberNode
    }
    
    var buttonNode: ASDisplayNode {
        return self.controllerNode.buttonNode
    }
    
    public var inProgress: Bool = false {
        didSet {
            self.updateNavigationItems()
            self.controllerNode.inProgress = self.inProgress
            self.confirmationController?.inProgress = self.inProgress
        }
    }
    public var loginWithNumber: ((String, Bool) -> Void)?
    public var loginWithPasskey: ((AuthorizationPasskeyData, Bool) -> Void)?
    var accountUpdated: ((UnauthorizedAccount) -> Void)?
    
    weak var confirmationController: PhoneConfirmationController?
    
    private let termsDisposable = MetaDisposable()
    
    private let hapticFeedback = HapticFeedback()
    private var tellomiBindPhone = false
    
    public init(sharedContext: SharedAccountContext, account: UnauthorizedAccount?, countriesConfiguration: CountriesConfiguration? = nil, apiId: Int32, apiHash: String, isTestingEnvironment: Bool, otherAccountPhoneNumbers: ((String, AccountRecordId, Bool)?, [(String, AccountRecordId, Bool)]), network: Network, presentationData: PresentationData, openUrl: @escaping (String) -> Void, back: @escaping () -> Void) {
        self.sharedContext = sharedContext
        self.account = account
        self.apiId = apiId
        self.apiHash = apiHash
        self.isTestingEnvironment = isTestingEnvironment
        self.otherAccountPhoneNumbers = otherAccountPhoneNumbers
        self.network = network
        self.presentationData = presentationData
        self.openUrl = openUrl
        self.back = back
                
        super.init(navigationBarPresentationData: NavigationBarPresentationData(theme: AuthorizationSequenceController.navigationBarTheme(presentationData.theme), strings: NavigationBarStrings(presentationStrings: presentationData.strings)))
        
        self.supportedOrientations = ViewControllerSupportedOrientations(regularSize: .all, compactSize: .portrait)
        
        self.hasActiveInput = true
        
        self.statusBar.statusBarStyle = presentationData.theme.intro.statusBarStyle.style
        self.attemptNavigation = { _ in
            return false
        }
        self.navigationBar?.backPressed = {
            back()
        }
        
        if !otherAccountPhoneNumbers.1.isEmpty {
            self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: "___close", style: .plain, target: self, action: #selector(self.cancelPressed))
        }
        if account != nil {
            self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: tellomiLoginCopy(languageCode: tellomiInterfaceLanguageCode(presentationData.strings)).help, style: .plain, target: self, action: #selector(self.helpPressed))
        }
        
        if let countriesConfiguration {
            AuthorizationSequenceCountrySelectionController.setupCountryCodes(countries: countriesConfiguration.countries, codesByPrefix: countriesConfiguration.countriesByPrefix)
        }
    }
    
    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        self.termsDisposable.dispose()
    }
    
    @objc private func cancelPressed() {
        self.back()
    }
    
    @objc private func helpPressed() {
        self.openUrl(TellomiLoginChrome.helpURL)
    }

    public func setTellomiBindPhone(_ bind: Bool) {
        self.tellomiBindPhone = bind
        if self.isNodeLoaded {
            self.controllerNode.setTellomiBindPhone(bind)
            self.controllerNode.applyPresentationTheme(self.presentationData.theme)
        }
    }

    public func applyPresentationTheme(_ presentationData: PresentationData) {
        self.presentationData = presentationData
        if self.isNodeLoaded {
            self.controllerNode.applyPresentationTheme(presentationData.theme)
        }
    }

    @objc private func tellomiSurfaceBackPressed() {
        if !self.controllerNode.popTellomiSurface() {
            self.back()
        }
    }

    private func presentTellomiUnavailable() {
        let copy = tellomiLoginCopy(languageCode: tellomiInterfaceLanguageCode(self.presentationData.strings))
        self.present(textAlertController(sharedContext: self.sharedContext, title: copy.unavailableTitle, text: copy.unavailableBody, actions: [TextAlertAction(type: .defaultAction, title: copy.ok, action: {})]), in: .window(.root))
    }

    private func presentTellomiAgreementPrompt() {
        let kind: TellomiSignUpAgreement.Kind = self.controllerNode.tellomiSurface.showsCarrierAgreement ? .phone : .email
        let prompt = TellomiAgreementPromptController(kind: kind, chinese: tellomiLoginPrefersChinese(languageCode: tellomiInterfaceLanguageCode(self.presentationData.strings)), openUrl: { [weak self] url in
            self?.openUrl(url)
        })
        prompt.agreed = { [weak self] in
            guard let self else {
                return
            }
            self.controllerNode.setTellomiAgreed(true)
            self.nextPressed()
        }
        self.present(prompt, in: .window(.root))
    }

    func updateNavigationItems() {
        if self.account != nil {
            let copy = tellomiLoginCopy(languageCode: tellomiInterfaceLanguageCode(self.presentationData.strings))
            self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: copy.help, style: .plain, target: self, action: #selector(self.helpPressed))
            if self.isNodeLoaded, self.controllerNode.tellomiSurface != .phoneCode {
                let backTitle = tellomiLoginPrefersChinese(languageCode: tellomiInterfaceLanguageCode(self.presentationData.strings)) ? "返回" : "Back"
                self.navigationItem.leftBarButtonItem = UIBarButtonItem(backButtonAppearanceWithTitle: backTitle, target: self, action: #selector(self.tellomiSurfaceBackPressed))
            } else {
                self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: "___close", style: .plain, target: self, action: #selector(self.cancelPressed))
            }
            return
        }
        guard let layout = self.validLayout, layout.size.width < 360.0 else {
            return
        }
                
        if self.inProgress {
            let item = UIBarButtonItem(customDisplayNode: ProgressNavigationButtonNode(color: self.presentationData.theme.rootController.navigationBar.accentTextColor))
            self.navigationItem.rightBarButtonItem = item
        } else {
            self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: self.presentationData.strings.Common_Next, style: .done, target: self, action: #selector(self.nextPressed))
        }
    }
    
    public func updateData(countryCode: Int32, countryName: String?, number: String) {
        self.pendingEntry = (countryCode, countryName, number)
        // The country picker reads currentData. An email must not land in the phone field.
        if tellomiIsLoginEmail(number) {
            self.currentData = (countryCode, countryName, "")
        } else {
            self.currentData = (countryCode, countryName, number)
        }
        if self.isNodeLoaded {
            self.controllerNode.applyEntry(countryCode: countryCode, countryName: countryName, number: number)
        }
    }
    
    private var shouldAnimateIn = false
    private var transitionInArguments: (buttonFrame: CGRect, buttonTitle: String, animationSnapshot: UIView, textSnapshot: UIView)?
    
    func animateWithSplashController(_ controller: AuthorizationSequenceSplashController) {
        self.shouldAnimateIn = true
        
        if let animationSnapshot = controller.animationSnapshot, let textSnapshot = controller.textSnaphot {
            self.transitionInArguments = (controller.buttonFrame, controller.buttonTitle, animationSnapshot, textSnapshot)
        }
    }
    
    override public func loadDisplayNode() {
        self.displayNode = AuthorizationSequencePhoneEntryControllerNode(sharedContext: self.sharedContext, account: self.account, strings: self.presentationData.strings, theme: self.presentationData.theme, debugAction: { [weak self] in
            guard let strongSelf = self else {
                return
            }
            strongSelf.view.endEditing(true)
            self?.present(debugController(sharedContext: strongSelf.sharedContext, context: nil, modal: true), in: .window(.root), with: ViewControllerPresentationArguments(presentationAnimation: .modalSheet))
        }, hasOtherAccounts: self.otherAccountPhoneNumbers.0 != nil)
        self.controllerNode.setTellomiBindPhone(self.tellomiBindPhone)
        self.controllerNode.accountUpdated = { [weak self] account in
            guard let strongSelf = self else {
                return
            }
            strongSelf.account = account
            strongSelf.accountUpdated?(account)
        }
        self.controllerNode.retryPasskey = { [weak self] in
            guard let self else {
                return
            }
            self.loadAndPresentPasskey(force: true)
        }
        
        if let (code, name, number) = self.pendingEntry {
            self.controllerNode.applyEntry(countryCode: code, countryName: name, number: number)
        } else if let (code, name, number) = self.currentData {
            self.controllerNode.applyEntry(countryCode: code, countryName: name, number: number)
        }
        self.displayNodeDidLoad()
        
        self.controllerNode.view.disableAutomaticKeyboardHandling = [.forward, .backward]
        
        self.controllerNode.selectCountryCode = { [weak self] in
            if let strongSelf = self {
                let controller = AuthorizationSequenceCountrySelectionController(strings: strongSelf.presentationData.strings, theme: strongSelf.presentationData.theme, glass: true)
                controller.completeWithCountryCode = { code, name in
                    if let strongSelf = self, let currentData = strongSelf.currentData {
                        strongSelf.updateData(countryCode: Int32(code), countryName: name, number: currentData.2)
                        strongSelf.controllerNode.activateInput()
                    }
                }
                controller.dismissed = { 
                    self?.controllerNode.activateInput()
                }
                strongSelf.push(controller)
            }
        }
        self.controllerNode.checkPhone = { [weak self] in
            self?.nextPressed()
        }
        self.controllerNode.tellomiOpenUrl = { [weak self] url in
            self?.openUrl(url)
        }
        self.controllerNode.tellomiUnavailable = { [weak self] in
            self?.presentTellomiUnavailable()
        }
        self.controllerNode.tellomiSurfaceChanged = { [weak self] in
            self?.updateNavigationItems()
        }
        
        if let account = self.account {
            loadServerCountryCodes(accountManager: sharedContext.accountManager, engine: TelegramEngineUnauthorized(account: account), completion: { [weak self] in
                if let strongSelf = self {
                    strongSelf.controllerNode.updateCountryCode()
                }
            })
        } else {
            self.controllerNode.updateCountryCode()
        }
        
        self.loadAndPresentPasskey(force: false)
    }
    
    private func loadAndPresentPasskey(force: Bool) {
        if #available(iOS 16.0, *) {
            Task { @MainActor [weak self] in
                guard let self, let account = self.account else {
                    return
                }
                
                let decodeBase64: (String) -> Data? = { string in
                    var string = string.replacingOccurrences(of: "-", with: "+")
                        .replacingOccurrences(of: "_", with: "/")
                    while string.count % 4 != 0 {
                        string.append("=")
                    }
                    return Data(base64Encoded: string)
                }
                
                let engine = TelegramEngineUnauthorized(account: account)
                let passkeyDataString = await engine.auth.requestPasskeyLoginData(apiId: self.apiId, apiHash: self.apiHash).get()
                guard let passkeyDataString, let passkeyData = passkeyDataString.data(using: .utf8) else {
                    return
                }
                guard let params = try? JSONSerialization.jsonObject(with: passkeyData) as? [String: Any] else {
                    return
                }
                guard let pkDict = params["publicKey"] as? [String: Any] else {
                    return
                }
                guard let relyingPartyIdentifier = pkDict["rpId"] as? String else {
                    return
                }
                guard let challengeBase64 = pkDict["challenge"] as? String else {
                    return
                }
                guard let challengeData = decodeBase64(challengeBase64) else {
                    return
                }
                
                let platformProvider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: relyingPartyIdentifier)
                let platformKeyRequest = platformProvider.createCredentialAssertionRequest(challenge: challengeData)
                let authController = ASAuthorizationController(authorizationRequests: [platformKeyRequest])
                authController.delegate = self
                authController.presentationContextProvider = self
                if force {
                    authController.performRequests()
                } else {
                    authController.performRequests(options: [.preferImmediatelyAvailableCredentials])
                }
            }
        }
    }
    
    public func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        Task { @MainActor [weak self] in
            guard let self, let account = self.account else {
                return
            }
            
            let encodeBase64URL: (Data) -> String = { data in
                var string = data.base64EncodedString()
                string = string
                    .replacingOccurrences(of: "+", with: "-")
                    .replacingOccurrences(of: "/", with: "_")
                string = string.replacingOccurrences(of: "=", with: "")
                return string
            }
            
            if #available(iOS 17.0, *) {
                if let credential = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialAssertion {
                    guard let clientData = String(data: credential.rawClientDataJSON, encoding: .utf8) else {
                        return
                    }
                    guard let userHandle = String(data: credential.userID, encoding: .utf8) else {
                        return
                    }
                    let passkey = AuthorizationPasskeyData(
                        id: encodeBase64URL(credential.credentialID),
                        clientData: clientData,
                        authenticatorData: credential.rawAuthenticatorData,
                        signature: credential.signature,
                        userHandle: userHandle
                    )
                    self.loginWithPasskey?(passkey, self.controllerNode.syncContacts)
                    
                    /*if let clientData = String(data: credential.rawClientDataJSON, encoding: .utf8), let attestationObject = credential.rawAttestationObject {
                        let passkey = await component.context.engine.auth.requestCreatePasskey(id: encodeBase64URL(credential.credentialID), clientData: clientData, attestationObject: attestationObject).get()
                        if let passkey {
                            if self.passkeysData == nil {
                                self.passkeysData = []
                                self.passkeysData?.insert(passkey, at: 0)
                            }
                            self.state?.updated(transition: .immediate)
                        }
                    }*/
                    let _ = account
                    let _ = credential
                }
            }
        }
    }

    public func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: any Error) {
        if (error as NSError).domain == "com.apple.AuthenticationServices.AuthorizationError" && (error as NSError).code == 1001 {
            self.controllerNode.updateDisplayPasskeyLoginOption()
            if let validLayout = self.validLayout {
                self.containerLayoutUpdated(validLayout, transition: .immediate)
            }
        }
    }
    
    public func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        guard let windowScene = self.view.window?.windowScene else {
            preconditionFailure()
        }
        return ASPresentationAnchor(windowScene: windowScene)
    }
    
    public func updateCountryCode() {
        self.controllerNode.updateCountryCode()
    }
    
    private var animatingIn = false
    override public func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        if self.shouldAnimateIn {
            self.animatingIn = true
            if let (buttonFrame, buttonTitle, animationSnapshot, textSnapshot) = self.transitionInArguments {
                self.controllerNode.willAnimateIn(buttonFrame: buttonFrame, buttonTitle: buttonTitle, animationSnapshot: animationSnapshot, textSnapshot: textSnapshot)
            }
            Queue.mainQueue().justDispatch {
                self.controllerNode.activateInput()
            }
        } else {
            self.controllerNode.activateInput()
        }
    }
    
    override public func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        if !self.animatingIn {
            self.controllerNode.activateInput()
        }
    }
    
    override public func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        if let confirmationController = self.confirmationController {
            confirmationController.transitionOut()
        }
    }
    
    override public func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        
        let hadLayout = self.validLayout != nil
        self.validLayout = layout
        
        if !hadLayout {
            self.updateNavigationItems()
        }
    
        self.controllerNode.containerLayoutUpdated(layout, navigationBarHeight: self.navigationLayout(layout: layout).navigationFrame.maxY, transition: transition)
        
        if self.shouldAnimateIn, let inputHeight = layout.inputHeight, inputHeight > 0.0 {
            if let (buttonFrame, buttonTitle, animationSnapshot, textSnapshot) = self.transitionInArguments {
                self.shouldAnimateIn = false
                self.controllerNode.animateIn(buttonFrame: buttonFrame, buttonTitle: buttonTitle, animationSnapshot: animationSnapshot, textSnapshot: textSnapshot)
            }
        }
    }
    
    public func dismissConfirmation() {
        self.confirmationController?.dismissAnimated()
        self.confirmationController = nil
    }
    
    @objc func nextPressed() {
        guard self.confirmationController == nil else {
            return
        }
        if self.account != nil && !self.controllerNode.tellomiAgreement.agreed {
            self.hapticFeedback.error()
            self.controllerNode.animateAgreementError()
            self.presentTellomiAgreementPrompt()
            return
        }
        if self.account != nil && self.controllerNode.isPasswordLogin {
            // There is no password sign-in RPC. Same notice as Apple, Google, and 找回账号.
            self.presentTellomiUnavailable()
            return
        }
        if self.controllerNode.isEmailLogin {
            let email = self.controllerNode.emailAddress
            guard tellomiIsLoginEmail(email) else {
                self.hapticFeedback.error()
                self.controllerNode.animateError()
                return
            }
            if self.presentExistingAccountIfNeeded(identifier: email) {
                return
            }
            if self.account != nil {
                self.loginWithNumber?(email, self.controllerNode.syncContacts)
                return
            }
            let languageCode = tellomiInterfaceLanguageCode(self.presentationData.strings)
            let copy = tellomiEmailLoginCopy(languageCode: languageCode)
            let bundled = tellomiBundledChineseLoginCopy(self.presentationData.strings)
            let editTitle = bundled?.edit ?? self.presentationData.strings.Login_Edit
            let yesTitle = bundled?.yes ?? self.presentationData.strings.Login_Yes
            var actions: [TextAlertAction] = []
            actions.append(TextAlertAction(type: .genericAction, title: editTitle, action: {}))
            actions.append(TextAlertAction(type: .defaultAction, title: yesTitle, action: { [weak self] in
                guard let self else {
                    return
                }
                self.loginWithNumber?(email, self.controllerNode.syncContacts)
            }))
            self.present(textAlertController(sharedContext: self.sharedContext, title: email, text: copy.confirm, actions: actions), in: .window(.root))
            return
        }
        let (_, _, number) = self.controllerNode.codeAndNumber
        if !number.isEmpty {
            let logInNumber = cleanPhoneNumber(self.controllerNode.currentNumber, removePlus: true)
            if self.presentExistingAccountIfNeeded(identifier: self.controllerNode.currentNumber) {
                return
            } else if self.account != nil {
                self.loginWithNumber?(self.controllerNode.currentNumber, self.controllerNode.syncContacts)
            } else {
                if let validLayout = self.validLayout, validLayout.size.width > 320.0 {
                    let (code, formattedNumber) = self.controllerNode.formattedCodeAndNumber

                    let confirmationController = PhoneConfirmationController(theme: self.presentationData.theme, strings: self.presentationData.strings, code: code, number: formattedNumber, sourceController: self)
                    confirmationController.proceed = { [weak self] in
                        if let strongSelf = self {
                            strongSelf.loginWithNumber?(strongSelf.controllerNode.currentNumber, strongSelf.controllerNode.syncContacts)
                        }
                    }
                    (self.navigationController as? NavigationController)?.presentOverlay(controller: confirmationController, inGlobal: true, blockInteraction: true)
                    self.confirmationController = confirmationController
                } else {
                    let bundled = tellomiBundledChineseLoginCopy(self.presentationData.strings)
                    let editTitle = bundled?.edit ?? self.presentationData.strings.Login_Edit
                    let yesTitle = bundled?.yes ?? self.presentationData.strings.Login_Yes
                    let confirmText = bundled?.phoneConfirm ?? self.presentationData.strings.Login_PhoneNumberConfirmation
                    var actions: [TextAlertAction] = []
                    actions.append(TextAlertAction(type: .genericAction, title: editTitle, action: {}))
                    actions.append(TextAlertAction(type: .defaultAction, title: yesTitle, action: { [weak self] in
                        if let strongSelf = self {
                            strongSelf.loginWithNumber?(strongSelf.controllerNode.currentNumber, strongSelf.controllerNode.syncContacts)
                        }
                    }))
                    self.present(textAlertController(sharedContext: self.sharedContext, title: logInNumber, text: confirmText, actions: actions), in: .window(.root))
                }
            }
        } else {
            self.hapticFeedback.error()
            self.controllerNode.animateError()
        }
    }
    
    /// True when this number or address is already signed in on the device. The alert switches to it.
    private func presentExistingAccountIfNeeded(identifier: String) -> Bool {
        var existing: AccountRecordId?
        for (stored, id, isTestingEnvironment) in self.otherAccountPhoneNumbers.1 {
            if isTestingEnvironment == self.isTestingEnvironment && tellomiLoginIdentifiersMatch(stored, identifier) {
                existing = id
            }
        }
        guard let id = existing else {
            return false
        }
        let copy = tellomiLoginCopy(languageCode: tellomiInterfaceLanguageCode(self.presentationData.strings))
        let text = tellomiLoginPrefersChinese(languageCode: tellomiInterfaceLanguageCode(self.presentationData.strings)) ? copy.alreadyAuthorized : self.presentationData.strings.Login_PhoneNumberAlreadyAuthorized
        let switchTitle = tellomiLoginPrefersChinese(languageCode: tellomiInterfaceLanguageCode(self.presentationData.strings)) ? copy.switchToAccount : self.presentationData.strings.Login_PhoneNumberAlreadyAuthorizedSwitch
        let actions = [
            TextAlertAction(type: .genericAction, title: switchTitle, action: { [weak self] in
                self?.sharedContext.switchToAccount(id: id, fromSettingsController: nil, withChatListController: nil)
                self?.back()
            }),
            TextAlertAction(type: .defaultAction, title: self.presentationData.strings.Common_OK, action: {})
        ]
        self.present(textAlertController(sharedContext: self.sharedContext, title: nil, text: text, actions: actions), in: .window(.root))
        return true
    }

    public func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
        controller.dismiss(animated: true, completion: nil)
    }
}
