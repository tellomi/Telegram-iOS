import Foundation
import LottieSettings
import UIKit
import AsyncDisplayKit
import Display
import TelegramCore
import TelegramPresentationData
import PhoneInputNode
import CountrySelectionUI
import QrCode
import SwiftSignalKit
import AccountContext
import AnimatedStickerNode
import TelegramAnimatedStickerNode
import SolidRoundedButtonNode
import AuthorizationUtils
import ManagedAnimationNode
import Markdown

private final class PhoneAndCountryNode: ASDisplayNode {
    let strings: PresentationStrings
    let theme: PresentationTheme
    
    let countryButton: CountryButtonNode
    let countryButtonArrow: ASImageNode
    let phoneBackground: ASImageNode
    let phoneInputNode: PhoneInputNode
    
    var selectCountryCode: (() -> Void)?
    var checkPhone: (() -> Void)?
    var hasNumberUpdated: ((Bool) -> Void)?
    var keyPressed: ((Int) -> Void)?
    
    var preferredCountryIdForCode: [String: String] = [:]
    
    var hasCountry = false
    private let tellomiBackground = ASDisplayNode()
    private let tellomiDivider = ASDisplayNode()
    private let tellomiChevron = ASImageNode()
    private var tellomiCompact = false
    private var tellomiPlaceholder = ""
    
    init(strings: PresentationStrings, theme: PresentationTheme) {
        self.strings = strings
        self.theme = theme
        
        let inset: CGFloat = 24.0
        
        let countryButtonBackground = generateImage(CGSize(width: 136.0, height: 67.0), rotatedContext: { size, context in
            let arrowSize: CGFloat = 10.0
            let lineWidth = UIScreenPixel
            context.clear(CGRect(origin: CGPoint(), size: size))
            context.setStrokeColor(theme.list.itemPlainSeparatorColor.cgColor)
            context.setLineWidth(lineWidth)
            context.move(to: CGPoint(x: inset, y: lineWidth / 2.0))
            context.addLine(to: CGPoint(x: size.width - inset, y: lineWidth / 2.0))
            context.strokePath()
            
            context.move(to: CGPoint(x: size.width - inset, y: size.height - arrowSize - lineWidth / 2.0))
            context.addLine(to: CGPoint(x: 69.0, y: size.height - arrowSize - lineWidth / 2.0))
            context.addLine(to: CGPoint(x: 69.0 - arrowSize, y: size.height - lineWidth / 2.0))
            context.addLine(to: CGPoint(x: 69.0 - arrowSize - arrowSize, y: size.height - arrowSize - lineWidth / 2.0))
            context.addLine(to: CGPoint(x: inset, y: size.height - arrowSize - lineWidth / 2.0))
            context.strokePath()
        })?.stretchableImage(withLeftCapWidth: 69, topCapHeight: 1)
        
        let countryButtonHighlightedBackground = generateImage(CGSize(width: 70.0, height: 67.0), rotatedContext: { size, context in
            let arrowSize: CGFloat = 10.0
            context.clear(CGRect(origin: CGPoint(), size: size))
            context.setFillColor(theme.list.itemHighlightedBackgroundColor.cgColor)
            context.fill(CGRect(origin: CGPoint(), size: CGSize(width: size.width, height: size.height - arrowSize)))
            context.move(to: CGPoint(x: size.width, y: size.height - arrowSize))
            context.addLine(to: CGPoint(x: size.width - 1.0, y: size.height - arrowSize))
            context.addLine(to: CGPoint(x: size.width - 1.0 - arrowSize, y: size.height))
            context.addLine(to: CGPoint(x: size.width - 1.0 - arrowSize - arrowSize, y: size.height - arrowSize))
            context.closePath()
            context.fillPath()
        })?.stretchableImage(withLeftCapWidth: 69, topCapHeight: 2)
        
        let phoneInputBackground = generateImage(CGSize(width: 96.0, height: 57.0), rotatedContext: { size, context in
            let lineWidth = UIScreenPixel
            context.clear(CGRect(origin: CGPoint(), size: size))
            context.setStrokeColor(theme.list.itemPlainSeparatorColor.cgColor)
            context.setLineWidth(lineWidth)
            context.move(to: CGPoint(x: inset, y: size.height - lineWidth / 2.0))
            context.addLine(to: CGPoint(x: size.width, y: size.height - lineWidth / 2.0))
            context.strokePath()
            context.move(to: CGPoint(x: size.width - 2.0 + lineWidth / 2.0, y: size.height - 9.0))
            context.addLine(to: CGPoint(x: size.width - 2.0 + lineWidth / 2.0, y: 8.0))
            context.strokePath()
        })?.stretchableImage(withLeftCapWidth: 95, topCapHeight: 2)
        
        self.countryButton = CountryButtonNode()
        self.countryButton.displaysAsynchronously = false
        self.countryButton.setBackgroundImage(countryButtonBackground, for: [])
        self.countryButton.titleNode.maximumNumberOfLines = 1
        self.countryButton.titleNode.truncationMode = .byTruncatingTail
        self.countryButton.setBackgroundImage(countryButtonHighlightedBackground, for: .highlighted)
        
        self.countryButtonArrow = ASImageNode()
        self.countryButtonArrow.image = generateTintedImage(image: UIImage(bundleImageName: "Item List/DisclosureArrow"), color: theme.list.disclosureArrowColor)
        
        self.phoneBackground = ASImageNode()
        self.phoneBackground.image = phoneInputBackground
        self.phoneBackground.displaysAsynchronously = false
        self.phoneBackground.displayWithoutProcessing = true
        self.phoneBackground.isLayerBacked = true
        
        self.phoneInputNode = PhoneInputNode()
        
        super.init()
        
        self.tellomiBackground.isHidden = true
        self.tellomiDivider.isHidden = true
        self.tellomiDivider.backgroundColor = UIColor(rgb: 0xE4E4E7)
        self.tellomiChevron.isHidden = true
        self.tellomiChevron.isUserInteractionEnabled = false
        self.tellomiChevron.image = generateImage(CGSize(width: 10.0, height: 6.0), rotatedContext: { size, context in
            context.clear(CGRect(origin: CGPoint(), size: size))
            context.setFillColor(UIColor(rgb: 0x8A8A8E).cgColor)
            context.move(to: CGPoint())
            context.addLine(to: CGPoint(x: size.width, y: 0.0))
            context.addLine(to: CGPoint(x: size.width / 2.0, y: size.height))
            context.closePath()
            context.fillPath()
        })

        self.addSubnode(self.phoneBackground)
        self.addSubnode(self.tellomiBackground)
        self.addSubnode(self.countryButton)
        self.countryButton.addSubnode(self.countryButtonArrow)
        self.addSubnode(self.phoneInputNode)
        self.addSubnode(self.tellomiDivider)
        self.addSubnode(self.tellomiChevron)
        
        self.phoneInputNode.countryCodeField.textField.keyboardAppearance = theme.rootController.keyboardColor.keyboardAppearance
        self.phoneInputNode.numberField.textField.keyboardAppearance = theme.rootController.keyboardColor.keyboardAppearance
        self.phoneInputNode.countryCodeField.textField.textColor = theme.list.itemPrimaryTextColor
        self.phoneInputNode.numberField.textField.textColor = theme.list.itemPrimaryTextColor
        self.phoneInputNode.countryCodeField.textField.tintColor = theme.list.itemAccentColor
        self.phoneInputNode.numberField.textField.tintColor = theme.list.itemAccentColor
        self.phoneInputNode.countryCodeField.accessibilityHint = strings.Login_VoiceOver_PhoneCountryCode
        self.phoneInputNode.numberField.accessibilityHint = strings.Login_VoiceOver_PhoneNumber
        self.phoneInputNode.countryCodeField.textField.accessibilityIdentifier = "Auth.PhoneEntry.CountryCodeField"
        self.phoneInputNode.numberField.textField.accessibilityIdentifier = "Auth.PhoneEntry.PhoneNumberField"

        self.phoneInputNode.countryCodeField.textField.tintColor = theme.list.itemAccentColor
        self.phoneInputNode.numberField.textField.tintColor = theme.list.itemAccentColor
        
        self.phoneInputNode.countryCodeField.textField.disableAutomaticKeyboardHandling = [.forward]
        self.phoneInputNode.numberField.textField.disableAutomaticKeyboardHandling = [.forward]
        
        self.countryButton.contentEdgeInsets = UIEdgeInsets(top: 0.0, left: 24.0 + 16.0, bottom: 10.0, right: 0.0)
        self.countryButton.contentHorizontalAlignment = .left
        
        self.countryButton.addTarget(self, action: #selector(self.countryPressed), forControlEvents: .touchUpInside)
                
        self.phoneInputNode.numberTextUpdated = { [weak self] number in
            if let strongSelf = self {
                let _ = strongSelf.processNumberChange(number: strongSelf.phoneInputNode.number)
                                
                let isServiceNumber = strongSelf.phoneInputNode.number.hasPrefix("+999")
                if strongSelf.hasCountry || isServiceNumber {
                    strongSelf.hasNumberUpdated?(!strongSelf.phoneInputNode.codeAndNumber.2.isEmpty || isServiceNumber)
                } else {
                    strongSelf.hasNumberUpdated?(false)
                }
            }
        }
        
        self.phoneInputNode.countryCodeUpdated = { [weak self] code, name in
            if let strongSelf = self {
                if let name = name {
                    strongSelf.preferredCountryIdForCode[code] = name
                }
                                
                if strongSelf.processNumberChange(number: strongSelf.phoneInputNode.number) {
                } else if let code = Int(code), let name = name, let countryName = countryCodeAndIdToName[CountryCodeAndId(code: code, id: name)] {
                    var localizedName: String = AuthorizationSequenceCountrySelectionController.lookupCountryNameById(name, strings: strongSelf.strings) ?? countryName
                    if name == "FT" {
                        localizedName = strongSelf.strings.Login_AnonymousNumbers
                    }
                    strongSelf.updateCountryButton(countryId: name, name: localizedName)
                    strongSelf.hasCountry = true
                    
                    if strongSelf.phoneInputNode.mask == nil {
                        strongSelf.phoneInputNode.numberField.textField.attributedPlaceholder = NSAttributedString(string: strings.Login_PhonePlaceholder, font: Font.regular(20.0), textColor: theme.list.itemPlaceholderTextColor)
                    }
                } else if let code = Int(code), let (countryId, countryName) = countryCodeToIdAndName[code] {
                    var localizedName: String = AuthorizationSequenceCountrySelectionController.lookupCountryNameById(countryId, strings: strongSelf.strings) ?? countryName
                    if countryId == "FT" {
                        localizedName = strongSelf.strings.Login_AnonymousNumbers
                    }
                    strongSelf.updateCountryButton(countryId: countryId, name: localizedName)
                    strongSelf.hasCountry = true
                    
                    if strongSelf.phoneInputNode.mask == nil {
                        strongSelf.phoneInputNode.numberField.textField.attributedPlaceholder = NSAttributedString(string: strings.Login_PhonePlaceholder, font: Font.regular(20.0), textColor: theme.list.itemPlaceholderTextColor)
                    }
                } else {
                    strongSelf.hasCountry = false
                    if strongSelf.tellomiCompact {
                        strongSelf.countryButton.setTitle("", with: Font.regular(17.0), with: .clear, for: [])
                    } else {
                        strongSelf.countryButton.setTitle(strings.Login_SelectCountry, with: Font.regular(20.0), with: theme.list.itemAccentColor, for: [])
                    }
                    strongSelf.phoneInputNode.mask = nil
                    strongSelf.phoneInputNode.numberField.textField.attributedPlaceholder = NSAttributedString(string: strings.Login_PhonePlaceholder, font: Font.regular(20.0), textColor: theme.list.itemPlaceholderTextColor)
                }
                
                if !strongSelf.tellomiCompact {
                    strongSelf.countryButton.accessibilityLabel = strongSelf.countryButton.attributedTitle(for: .normal)?.string ?? ""
                }
                strongSelf.countryButton.accessibilityTraits = [.button]
                strongSelf.applyTellomiPlaceholder()
                
                if strongSelf.hasCountry {
                    strongSelf.hasNumberUpdated?(!strongSelf.phoneInputNode.codeAndNumber.2.isEmpty)
                } else {
                    strongSelf.hasNumberUpdated?(false)
                }
            }
        }
        
        self.phoneInputNode.customFormatter = { number in
            if let (_, code) = AuthorizationSequenceCountrySelectionController.lookupCountryIdByNumber(number, preferredCountries: [:]) {
                return code.code
            } else {
                return nil
            }
        }
        
        self.phoneInputNode.number = "+1"
        self.phoneInputNode.returnAction = { [weak self] in
            self?.checkPhone?()
        }
        
        self.phoneInputNode.keyPressed = { [weak self] num in
            self?.keyPressed?(num)
        }
    }
    
    func processNumberChange(number: String) -> Bool {
        if let (country, _) = AuthorizationSequenceCountrySelectionController.lookupCountryIdByNumber(number, preferredCountries: self.preferredCountryIdForCode) {
            var localizedName: String = AuthorizationSequenceCountrySelectionController.lookupCountryNameById(country.id, strings: self.strings) ?? country.name
            if country.id == "FT" {
                localizedName = self.strings.Login_AnonymousNumbers
            }
            self.updateCountryButton(countryId: country.id, name: localizedName)
            self.hasCountry = true
            
            let maskFont = Font.with(size: 20.0, design: .regular, traits: [.monospacedNumbers])
            if self.tellomiCompact {
                self.applyTellomiPlaceholder()
            } else if let mask = AuthorizationSequenceCountrySelectionController.lookupPatternByNumber(number, preferredCountries: self.preferredCountryIdForCode).flatMap({ NSAttributedString(string: $0, font: maskFont, textColor: self.theme.list.itemPlaceholderTextColor) }) {
                self.phoneInputNode.numberField.textField.attributedPlaceholder = nil
                self.phoneInputNode.mask = mask
            } else {
                self.phoneInputNode.mask = nil
                self.phoneInputNode.numberField.textField.attributedPlaceholder = NSAttributedString(string: strings.Login_PhonePlaceholder, font: Font.regular(20.0), textColor: self.theme.list.itemPlaceholderTextColor)
            }
            return true
        } else {
            return false
        }
    }
    
    func setTellomiStyle(placeholder: String) {
        self.tellomiCompact = true
        self.tellomiPlaceholder = placeholder
        self.tellomiBackground.isHidden = false
        self.tellomiDivider.isHidden = false
        self.tellomiChevron.isHidden = false
        self.phoneBackground.isHidden = true
        self.countryButtonArrow.isHidden = true
        self.countryButton.setBackgroundImage(nil, for: [])
        self.countryButton.setBackgroundImage(nil, for: .highlighted)
        let palette = TellomiLoginChrome.palette(dark: self.theme.overallDarkAppearance)
        TellomiLoginChrome.applyField(self.tellomiBackground, dark: self.theme.overallDarkAppearance)
        self.phoneInputNode.countryCodeField.textField.textAlignment = .left
        self.phoneInputNode.countryCodeField.textField.textColor = palette.fieldText
        self.phoneInputNode.numberField.textField.textColor = palette.fieldText
        self.phoneInputNode.countryCodeField.textField.tintColor = palette.accent
        self.phoneInputNode.numberField.textField.tintColor = palette.accent
        let font = Font.regular(17.0)
        self.phoneInputNode.countryCodeField.textField.font = font
        self.phoneInputNode.numberField.textField.font = font
        // The code opens the country list. Typing digits into it was the broken picker.
        self.phoneInputNode.countryCodeField.textField.isEnabled = false
        self.phoneInputNode.countryCodeField.isUserInteractionEnabled = false
        self.applyTellomiPlaceholder()
        self.addSubnode(self.countryButton)
        self.addSubnode(self.tellomiChevron)
        self.setNeedsLayout()
    }

    private func applyTellomiPlaceholder() {
        guard self.tellomiCompact else {
            return
        }
        self.phoneInputNode.mask = nil
        self.phoneInputNode.numberField.textField.attributedPlaceholder = NSAttributedString(string: self.tellomiPlaceholder, font: Font.regular(17.0), textColor: TellomiLoginChrome.palette(dark: self.theme.overallDarkAppearance).placeholder)
    }

    private func updateCountryButton(countryId: String, name: String) {
        if self.tellomiCompact {
            self.countryButton.setTitle("", with: Font.regular(17.0), with: .clear, for: [])
            self.countryButton.accessibilityLabel = name
            return
        }
        self.countryButton.setCountryTitle(countryId: countryId, name: name, font: Font.regular(20.0), color: self.theme.list.itemAccentColor)
    }

    @objc func countryPressed() {
        self.selectCountryCode?()
    }

    private func layoutTellomi() {
        let size = self.bounds.size
        let inset: CGFloat = 24.0
        let fieldHeight: CGFloat = 52.0
        let fieldFrame = CGRect(x: inset, y: floor((size.height - fieldHeight) / 2.0), width: max(0.0, size.width - inset * 2.0), height: fieldHeight)
        self.tellomiBackground.frame = fieldFrame

        let codeWidth: CGFloat = 78.0
        self.tellomiDivider.frame = CGRect(x: fieldFrame.minX + codeWidth, y: fieldFrame.minY + 16.0, width: UIScreenPixel, height: fieldHeight - 32.0)
        let chevronSize = self.tellomiChevron.image?.size ?? CGSize(width: 10.0, height: 6.0)
        self.tellomiChevron.frame = CGRect(x: fieldFrame.minX + codeWidth - 14.0 - chevronSize.width, y: fieldFrame.midY - chevronSize.height / 2.0, width: chevronSize.width, height: chevronSize.height)

        self.countryButton.isHidden = false
        self.countryButton.frame = CGRect(x: fieldFrame.minX, y: fieldFrame.minY, width: codeWidth, height: fieldHeight)
        self.countryButton.backgroundColor = nil

        self.phoneInputNode.frame = fieldFrame
        self.phoneInputNode.countryCodeField.frame = CGRect(x: 14.0, y: 0.0, width: 46.0, height: fieldHeight)
        let numberFrame = CGRect(x: codeWidth + 12.0, y: 0.0, width: max(0.0, fieldFrame.width - codeWidth - 24.0), height: fieldHeight)
        self.phoneInputNode.numberField.frame = numberFrame
        self.phoneInputNode.placeholderNode.frame = numberFrame
    }
    
    override func layout() {
        super.layout()

        if self.tellomiCompact {
            self.layoutTellomi()
            return
        }
        
        let size = self.bounds.size
        let inset: CGFloat = 24.0
        
        self.countryButton.frame = CGRect(origin: CGPoint(), size: CGSize(width: size.width, height: 67.0))
        self.phoneBackground.frame = CGRect(origin: CGPoint(x: 0.0, y: size.height - 57.0), size: CGSize(width: size.width - inset, height: 57.0))
        
        if let image = self.countryButtonArrow.image {
            self.countryButtonArrow.frame = CGRect(origin: CGPoint(x: size.width - image.size.width - 24.0 - 3.0, y: 16.0 + UIScreenPixel), size: image.size)
        }
        
        let countryCodeFrame = CGRect(origin: CGPoint(x: 18.0, y: size.height - 58.0), size: CGSize(width: 71.0, height: 57.0))
        let numberFrame = CGRect(origin: CGPoint(x: 107.0, y: size.height - 58.0), size: CGSize(width: size.width - 96.0 - 8.0 - 24.0, height: 57.0))
        let placeholderFrame = numberFrame.offsetBy(dx: 0.0, dy: 17.0 - UIScreenPixel)
        
        let phoneInputFrame = countryCodeFrame.union(numberFrame)
        
        self.phoneInputNode.frame = phoneInputFrame
        self.phoneInputNode.countryCodeField.frame = countryCodeFrame.offsetBy(dx: -phoneInputFrame.minX, dy: -phoneInputFrame.minY)
        self.phoneInputNode.numberField.frame = numberFrame.offsetBy(dx: -phoneInputFrame.minX, dy: -phoneInputFrame.minY)
        self.phoneInputNode.placeholderNode.frame = placeholderFrame.offsetBy(dx: -phoneInputFrame.minX, dy: -phoneInputFrame.minY)
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if self.tellomiCompact, self.countryButton.frame.contains(point) {
            return self.countryButton.hitTest(self.view.convert(point, to: self.countryButton.view), with: event) ?? self.countryButton.view
        }
        return super.hitTest(point, with: event)
    }
}

private final class ContactSyncNode: ASDisplayNode {
    private let titleNode: ImmediateTextNode
    let switchNode: SwitchNode
    
    init(theme: PresentationTheme, strings: PresentationStrings) {
        self.titleNode = ImmediateTextNode()
        self.titleNode.maximumNumberOfLines = 1
        self.titleNode.attributedText = NSAttributedString(string: strings.Privacy_ContactsSync, font: Font.regular(17.0), textColor: theme.list.itemPrimaryTextColor)
        self.switchNode = SwitchNode()
        self.switchNode.frameColor = theme.list.itemSwitchColors.frameColor
        self.switchNode.contentColor = theme.list.itemSwitchColors.contentColor
        self.switchNode.handleColor = theme.list.itemSwitchColors.handleColor
        self.switchNode.isOn = true
        
        super.init()
        
        self.addSubnode(self.titleNode)
        self.addSubnode(self.switchNode)
    }
    
    func updateLayout(width: CGFloat) -> CGSize {
        var switchSize = CGSize(width: 51.0, height: 31.0)
        if let switchView = self.switchNode.view as? UISwitch {
            if self.switchNode.bounds.size.width.isZero {
                switchView.sizeToFit()
            }
            switchSize = switchView.bounds.size
        }
        
        let inset: CGFloat = 24.0
        let titleSize = self.titleNode.updateLayout(CGSize(width: width - switchSize.width - inset * 2.0 - 8.0, height: .greatestFiniteMagnitude))
        let height: CGFloat = 40.0
        self.titleNode.frame = CGRect(origin: CGPoint(x: inset, y: floor((height - titleSize.height) / 2.0)), size: titleSize)
        self.switchNode.frame = CGRect(origin: CGPoint(x: width - inset - switchSize.width, y: floor((height - switchSize.height) / 2.0)), size: switchSize)
        return CGSize(width: width, height: height)
    }
}

/// Gray rounded email row on the login home.
private final class TellomiEmailFieldNode: ASDisplayNode, UITextFieldDelegate {
    let textField: TextFieldNode
    private let backgroundNode: ASDisplayNode
    private let separatorNode: ASDisplayNode
    var textChanged: ((String) -> Void)?
    var returnPressed: (() -> Void)?

    var text: String {
        return self.textField.textField.text ?? ""
    }

    init(theme: PresentationTheme, placeholder: String) {
        self.textField = TextFieldNode()
        self.textField.textField.font = Font.regular(17.0)
        self.textField.textField.textColor = TellomiLoginChrome.palette(dark: theme.overallDarkAppearance).fieldText
        self.textField.textField.textAlignment = .natural
        self.textField.textField.autocorrectionType = .no
        self.textField.textField.autocapitalizationType = .none
        self.textField.textField.keyboardType = .emailAddress
        self.textField.textField.returnKeyType = .done
        self.textField.textField.keyboardAppearance = theme.rootController.keyboardColor.keyboardAppearance
        self.textField.textField.tintColor = TellomiLoginChrome.accent
        self.textField.textField.disableAutomaticKeyboardHandling = [.forward, .backward]
        self.textField.textField.attributedPlaceholder = NSAttributedString(string: placeholder, font: Font.regular(17.0), textColor: TellomiLoginChrome.placeholder)
        self.textField.textField.accessibilityIdentifier = "Auth.PhoneEntry.EmailField"
        if #available(iOSApplicationExtension 10.0, iOS 10.0, *) {
            self.textField.textField.textContentType = .emailAddress
        }

        self.backgroundNode = ASDisplayNode()
        TellomiLoginChrome.applyField(self.backgroundNode, dark: theme.overallDarkAppearance)

        self.separatorNode = ASDisplayNode()
        self.separatorNode.isHidden = true

        super.init()

        self.textField.textField.delegate = self
        self.addSubnode(self.backgroundNode)
        self.addSubnode(self.separatorNode)
        self.addSubnode(self.textField)
        self.textField.textField.addTarget(self, action: #selector(self.editingChanged), for: .editingChanged)
    }

    func setText(_ text: String) {
        self.textField.textField.text = text
    }

    func setPlaceholder(_ placeholder: String, theme: PresentationTheme) {
        let palette = TellomiLoginChrome.palette(dark: theme.overallDarkAppearance)
        self.textField.textField.textColor = palette.fieldText
        self.textField.textField.tintColor = palette.accent
        self.textField.textField.keyboardAppearance = theme.rootController.keyboardColor.keyboardAppearance
        TellomiLoginChrome.applyField(self.backgroundNode, dark: theme.overallDarkAppearance)
        self.textField.textField.attributedPlaceholder = NSAttributedString(string: placeholder, font: Font.regular(17.0), textColor: palette.placeholder)
    }

    @objc private func editingChanged() {
        self.textChanged?(self.text)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        self.returnPressed?()
        return false
    }

    override func layout() {
        super.layout()
        let inset: CGFloat = 24.0
        let size = self.bounds.size
        let fieldHeight: CGFloat = 52.0
        let fieldFrame = CGRect(x: inset, y: floor((size.height - fieldHeight) / 2.0), width: max(0.0, size.width - inset * 2.0), height: fieldHeight)
        self.backgroundNode.frame = fieldFrame
        self.textField.frame = fieldFrame.insetBy(dx: 16.0, dy: 0.0)
    }
}

final class AuthorizationSequencePhoneEntryControllerNode: ASDisplayNode {
    private let sharedContext: SharedAccountContext
    private var account: UnauthorizedAccount?
    private let strings: PresentationStrings
    private var theme: PresentationTheme
    private let hasOtherAccounts: Bool
    private var tellomiBindPhone = false
    
    private let animationNode: AnimatedStickerNode
    private let managedAnimationNode: ManagedPhoneAnimationNode
    private let titleNode: ASTextNode
    private let titleActivateAreaNode: AccessibilityAreaNode
    private let noticeNode: ImmediateTextNode
    private let noticeActivateAreaNode: AccessibilityAreaNode
    private let phoneAndCountryNode: PhoneAndCountryNode
    private let emailFieldNode: TellomiEmailFieldNode?
    private let emailSwitchNode: HighlightableButtonNode?
    private let contactSyncNode: ContactSyncNode
    private let agreementNode: ImmediateTextNode
    private let agreementRow: TellomiAgreementRow?
    let tellomiAgreement = TellomiSignUpAgreement()
    var tellomiOpenUrl: ((String) -> Void)?
    var tellomiUnavailable: (() -> Void)?
    var tellomiSurfaceChanged: (() -> Void)?
    private let proceedNode: SolidRoundedButtonNode
    private(set) var tellomiSurface: TellomiLoginSurface = .phoneCode
    private var emailLogin: Bool {
        return self.tellomiSurface.isEmail
    }
    private let passwordFieldNode: TellomiPasswordFieldNode?
    private let modeIconNode: ASImageNode?
    private let orDividerNode: TellomiOrDividerNode?
    private let appleRowNode: TellomiSocialRowNode?
    private let googleRowNode: TellomiSocialRowNode?
    private let emailRowNode: TellomiSocialRowNode?
    private let otherRowNode: TellomiSocialRowNode?
    private let recoverNode: HighlightableButtonNode?
    private let circleGoogleNode: TellomiCircleButtonNode?
    private let circleAppleNode: TellomiCircleButtonNode?
    private let circleEmailNode: TellomiCircleButtonNode?
    private let circleMoreNode: TellomiCircleButtonNode?
    private let passwordErrorNode: ImmediateTextNode?
    private var passkeyNotice = false
    private var layoutArguments: (ContainerViewLayout, CGFloat)?
    
    private var qrNode: ASImageNode?
    private let exportTokenDisposable = MetaDisposable()
    private let tokenEventsDisposable = MetaDisposable()
    var accountUpdated: ((UnauthorizedAccount) -> Void)?
    
    var retryPasskey: (() -> Void)?
    
    private let debugAction: () -> Void
    
    var currentNumber: String {
        return self.phoneAndCountryNode.phoneInputNode.number
    }

    var isEmailLogin: Bool {
        return self.emailLogin
    }

    var isPasswordLogin: Bool {
        return self.tellomiSurface.isPassword
    }

    var password: String {
        return self.passwordFieldNode?.text ?? ""
    }

    var emailAddress: String {
        return tellomiNormalizedLoginEmail(self.emailFieldNode?.text ?? "")
    }
    
    var codeAndNumber: (Int32?, String?, String) {
        get {
            return self.phoneAndCountryNode.phoneInputNode.codeAndNumber
        } set(value) {
            self.phoneAndCountryNode.phoneInputNode.codeAndNumber = value
        }
    }
    
    var formattedCodeAndNumber: (String, String) {
        return self.phoneAndCountryNode.phoneInputNode.formattedCodeAndNumber
    }
    
    var syncContacts: Bool {
        get {
            if self.hasOtherAccounts {
                return self.contactSyncNode.switchNode.isOn
            } else {
                return true
            }
        }
    }
    
    var selectCountryCode: (() -> Void)?
    var checkPhone: (() -> Void)?
    
    var inProgress: Bool = false {
        didSet {
            self.phoneAndCountryNode.phoneInputNode.enableEditing = !self.inProgress
            self.phoneAndCountryNode.phoneInputNode.alpha = self.inProgress ? 0.6 : 1.0
            self.phoneAndCountryNode.countryButton.isEnabled = !self.inProgress
            self.emailFieldNode?.textField.alpha = self.inProgress ? 0.6 : 1.0
            self.emailFieldNode?.textField.textField.isEnabled = !self.inProgress
            self.passwordFieldNode?.textField.alpha = self.inProgress ? 0.6 : 1.0
            self.passwordFieldNode?.textField.textField.isEnabled = !self.inProgress
            self.emailSwitchNode?.isUserInteractionEnabled = !self.inProgress
            self.emailSwitchNode?.alpha = self.inProgress ? 0.6 : 1.0
            
            if self.inProgress != oldValue {
                if self.inProgress {
                    self.proceedNode.transitionToProgress()
                } else {
                    self.proceedNode.transitionFromProgress()
                }
            }
        }
    }
    
    var codeNode: ASDisplayNode {
        return self.phoneAndCountryNode.phoneInputNode.countryCodeField
    }
    
    var numberNode: ASDisplayNode {
        return self.phoneAndCountryNode.phoneInputNode.numberField
    }
    
    var buttonNode: ASDisplayNode {
        return self.proceedNode
    }

    private var tellomiLoginHome: Bool {
        return self.account != nil
    }

    func setTellomiBindPhone(_ bind: Bool) {
        self.tellomiBindPhone = bind
    }

    func applyPresentationTheme(_ theme: PresentationTheme) {
        self.theme = theme
        let dark = theme.overallDarkAppearance
        let palette = TellomiLoginChrome.palette(dark: dark)
        self.backgroundColor = theme.list.plainBackgroundColor
        let phoneInputNode = self.phoneAndCountryNode.phoneInputNode
        phoneInputNode.countryCodeField.textField.textColor = palette.fieldText
        phoneInputNode.numberField.textField.textColor = palette.fieldText
        phoneInputNode.countryCodeField.textField.tintColor = palette.accent
        phoneInputNode.numberField.textField.tintColor = palette.accent
        phoneInputNode.countryCodeField.textField.keyboardAppearance = theme.rootController.keyboardColor.keyboardAppearance
        phoneInputNode.numberField.textField.keyboardAppearance = theme.rootController.keyboardColor.keyboardAppearance
        self.emailFieldNode?.setPlaceholder(self.emailFieldNode?.textField.textField.attributedPlaceholder?.string ?? "", theme: theme)
        self.passwordFieldNode?.applyPalette(dark: dark, theme: theme)
        self.agreementRow?.setDark(dark)
        self.appleRowNode?.applyPalette(dark: dark)
        self.googleRowNode?.applyPalette(dark: dark)
        self.emailRowNode?.applyPalette(dark: dark)
        self.otherRowNode?.applyPalette(dark: dark)
        if self.tellomiLoginHome || self.tellomiBindPhone {
            self.proceedNode.updateTheme(TellomiLoginChrome.buttonTheme(dark: dark))
        }
        if let layoutArguments = self.layoutArguments {
            self.containerLayoutUpdated(layoutArguments.0, navigationBarHeight: layoutArguments.1, transition: .immediate)
        }
    }
    
    init(sharedContext: SharedAccountContext, account: UnauthorizedAccount?, strings: PresentationStrings, theme: PresentationTheme, debugAction: @escaping () -> Void, hasOtherAccounts: Bool) {
        self.sharedContext = sharedContext
        self.account = account
        
        self.strings = strings
        self.theme = theme
        self.debugAction = debugAction
        self.hasOtherAccounts = hasOtherAccounts
        
        self.animationNode = DefaultAnimatedStickerNodeImpl(lottieSettings: .noAccountFallback)
        self.animationNode.setup(source: AnimatedStickerNodeLocalFileSource(name: "IntroPhone"), width: 256, height: 256, playbackMode: .once, mode: .direct(cachePathPrefix: nil))
        
        self.managedAnimationNode = ManagedPhoneAnimationNode(lottieSettings: .noAccountFallback)
        self.managedAnimationNode.isHidden = true
        
        self.titleNode = ASTextNode()
        self.titleNode.isUserInteractionEnabled = true
        self.titleNode.displaysAsynchronously = false
        self.titleNode.attributedText = NSAttributedString(string: account == nil ? strings.Login_NewNumber : strings.Login_PhoneTitle, font: Font.light(30.0), textColor: theme.list.itemPrimaryTextColor)
        
        self.titleActivateAreaNode = AccessibilityAreaNode()
        self.titleActivateAreaNode.accessibilityTraits = .staticText
        
        self.noticeNode = ImmediateTextNode()
        self.noticeNode.maximumNumberOfLines = 0
        self.noticeNode.isUserInteractionEnabled = true
        self.noticeNode.displaysAsynchronously = false
        self.noticeNode.lineSpacing = 0.1
        
        self.noticeActivateAreaNode = AccessibilityAreaNode()
        self.noticeActivateAreaNode.accessibilityTraits = .staticText
        
        self.noticeNode.attributedText = NSAttributedString(string: account == nil ? strings.ChangePhoneNumberNumber_Help : strings.Login_PhoneAndCountryHelp, font: Font.regular(17.0), textColor: theme.list.itemPrimaryTextColor, paragraphAlignment: .center)
        
        self.contactSyncNode = ContactSyncNode(theme: theme, strings: strings)
        
        self.phoneAndCountryNode = PhoneAndCountryNode(strings: strings, theme: theme)

        // Change Phone Number uses this screen with account == nil. The login home is the mockup set.
        if account != nil {
            let copy = tellomiEmailLoginCopy(languageCode: tellomiInterfaceLanguageCode(strings))
            let loginCopy = tellomiLoginCopy(languageCode: tellomiInterfaceLanguageCode(strings))
            let emailFieldNode = TellomiEmailFieldNode(theme: theme, placeholder: copy.placeholder)
            emailFieldNode.isHidden = true
            self.emailFieldNode = emailFieldNode
            let emailSwitchNode = HighlightableButtonNode()
            emailSwitchNode.displaysAsynchronously = false
            emailSwitchNode.setTitle(loginCopy.passwordLogin, with: Font.regular(15.0), with: TellomiLoginChrome.link, for: [])
            emailSwitchNode.accessibilityLabel = loginCopy.passwordLogin
            emailSwitchNode.accessibilityTraits = [.button]
            emailSwitchNode.contentHorizontalAlignment = .left
            emailSwitchNode.contentEdgeInsets = UIEdgeInsets(top: 0.0, left: 48.0, bottom: 0.0, right: 24.0)
            self.emailSwitchNode = emailSwitchNode
            self.phoneAndCountryNode.setTellomiStyle(placeholder: loginCopy.phonePlaceholder)

            let modeIconNode = ASImageNode()
            modeIconNode.image = tellomiSymbol("arrow.left.arrow.right", pointSize: 13.0, weight: .medium)?.withTintColor(TellomiLoginChrome.link, renderingMode: .alwaysOriginal)
            modeIconNode.isUserInteractionEnabled = false
            self.modeIconNode = modeIconNode

            self.passwordFieldNode = TellomiPasswordFieldNode(theme: theme, placeholder: loginCopy.passwordPlaceholder, eyeOnLeft: true)
            self.passwordFieldNode?.isHidden = true

            let orDividerNode = TellomiOrDividerNode()
            orDividerNode.setTitle(loginCopy.orDivider)
            self.orDividerNode = orDividerNode

            let appleIcon = tellomiSymbol("apple.logo", pointSize: 20.0)?.withTintColor(UIColor(rgb: 0x111111), renderingMode: .alwaysOriginal)
            let googleIcon = tellomiGoogleMark(side: 22.0)
            let mailIcon = tellomiSymbol("envelope", pointSize: 16.0)?.withTintColor(UIColor(rgb: 0x111111), renderingMode: .alwaysOriginal)
            let dotsIcon = tellomiDotsImage(side: 22.0)
            let rowDark = theme.overallDarkAppearance
            self.appleRowNode = TellomiSocialRowNode(title: loginCopy.appleLogin, icon: appleIcon, dark: rowDark)
            self.googleRowNode = TellomiSocialRowNode(title: loginCopy.googleLogin, icon: googleIcon, dark: rowDark)
            self.emailRowNode = TellomiSocialRowNode(title: loginCopy.emailLogin, icon: mailIcon, dark: rowDark)
            self.otherRowNode = TellomiSocialRowNode(title: loginCopy.otherLogin, icon: dotsIcon, dark: rowDark)

            let recoverNode = HighlightableButtonNode()
            recoverNode.setTitle(loginCopy.recoverAccount, with: Font.regular(16.0), with: TellomiLoginChrome.link, for: [])
            recoverNode.accessibilityLabel = loginCopy.recoverAccount
            recoverNode.accessibilityTraits = [.button]
            self.recoverNode = recoverNode

            self.circleGoogleNode = TellomiCircleButtonNode(icon: googleIcon, accessibilityLabel: loginCopy.googleLogin)
            self.circleAppleNode = TellomiCircleButtonNode(icon: appleIcon, accessibilityLabel: loginCopy.appleLogin)
            self.circleEmailNode = TellomiCircleButtonNode(icon: mailIcon, accessibilityLabel: loginCopy.emailLogin)
            self.circleMoreNode = TellomiCircleButtonNode(icon: dotsIcon, accessibilityLabel: loginCopy.otherLogin)
            self.circleGoogleNode?.isHidden = true
            self.circleAppleNode?.isHidden = true
            self.circleEmailNode?.isHidden = true
            self.circleMoreNode?.isHidden = true

            let passwordErrorNode = ImmediateTextNode()
            passwordErrorNode.maximumNumberOfLines = 0
            passwordErrorNode.displaysAsynchronously = false
            passwordErrorNode.isHidden = true
            self.passwordErrorNode = passwordErrorNode
        } else {
            self.emailFieldNode = nil
            self.emailSwitchNode = nil
            self.passwordFieldNode = nil
            self.modeIconNode = nil
            self.orDividerNode = nil
            self.appleRowNode = nil
            self.googleRowNode = nil
            self.emailRowNode = nil
            self.otherRowNode = nil
            self.recoverNode = nil
            self.circleGoogleNode = nil
            self.circleAppleNode = nil
            self.circleEmailNode = nil
            self.circleMoreNode = nil
            self.passwordErrorNode = nil
        }
        
        let loginCopy = tellomiLoginCopy(languageCode: tellomiInterfaceLanguageCode(strings))
        let buttonTitle = account != nil ? loginCopy.verifyAndLogin : self.strings.Login_Continue
        let buttonTheme = account != nil ? TellomiLoginChrome.buttonTheme(dark: theme.overallDarkAppearance) : SolidRoundedButtonTheme(theme: self.theme)
        self.proceedNode = SolidRoundedButtonNode(title: buttonTitle, theme: buttonTheme, glass: false, height: 50.0, cornerRadius: 25.0)
        self.proceedNode.progressType = .embedded
        self.proceedNode.isEnabled = false
        self.proceedNode.accessibilityIdentifier = "Auth.PhoneEntry.ContinueButton"

        self.agreementNode = ImmediateTextNode()
        self.agreementNode.maximumNumberOfLines = 0
        self.agreementNode.displaysAsynchronously = false
        self.agreementNode.isUserInteractionEnabled = true
        self.agreementNode.linkHighlightColor = TellomiLoginChrome.link.withAlphaComponent(0.2)
        self.agreementNode.isHidden = account == nil
        self.agreementRow = account != nil ? TellomiAgreementRow(textNode: self.agreementNode) : nil

        super.init()
        
        self.setViewBlock({
            return UITracingLayerView()
        })
        
        self.backgroundColor = theme.list.plainBackgroundColor
        
        self.addSubnode(self.titleNode)
        self.addSubnode(self.noticeNode)
        self.addSubnode(self.titleActivateAreaNode)
        self.addSubnode(self.noticeActivateAreaNode)
        self.addSubnode(self.phoneAndCountryNode)
        if let emailFieldNode = self.emailFieldNode {
            self.addSubnode(emailFieldNode)
        }
        if let emailSwitchNode = self.emailSwitchNode {
            self.addSubnode(emailSwitchNode)
        }
        self.addSubnode(self.contactSyncNode)
        if let agreementRow = self.agreementRow {
            self.addSubnode(agreementRow)
        } else {
            self.addSubnode(self.agreementNode)
        }
        if let passwordFieldNode = self.passwordFieldNode {
            self.addSubnode(passwordFieldNode)
        }
        if let modeIconNode = self.modeIconNode {
            self.addSubnode(modeIconNode)
        }
        if let orDividerNode = self.orDividerNode {
            self.addSubnode(orDividerNode)
        }
        for node in [self.appleRowNode, self.googleRowNode, self.emailRowNode, self.otherRowNode] {
            if let node {
                self.addSubnode(node)
            }
        }
        if let recoverNode = self.recoverNode {
            self.addSubnode(recoverNode)
        }
        for node in [self.circleGoogleNode, self.circleAppleNode, self.circleEmailNode, self.circleMoreNode] {
            if let node {
                self.addSubnode(node)
            }
        }
        if let passwordErrorNode = self.passwordErrorNode {
            self.addSubnode(passwordErrorNode)
        }
        self.addSubnode(self.proceedNode)
        self.addSubnode(self.animationNode)
        self.addSubnode(self.managedAnimationNode)
        self.contactSyncNode.isHidden = true
        
        self.noticeNode.highlightAttributeAction = { attributes in
            if let _ = attributes[NSAttributedString.Key(rawValue: "URL")] {
                return NSAttributedString.Key(rawValue: "URL")
            } else {
                return nil
            }
        }
        self.noticeNode.tapAttributeAction = { [weak self] attributes, _ in
            guard let self else {
                return
            }
            if let _ = attributes[NSAttributedString.Key(rawValue: "URL")] as? String {
                self.retryPasskey?()
            }
        }
        self.noticeNode.linkHighlightColor = theme.list.itemAccentColor.withAlphaComponent(0.2)
        
        self.phoneAndCountryNode.selectCountryCode = { [weak self] in
            self?.selectCountryCode?()
        }
        self.phoneAndCountryNode.checkPhone = { [weak self] in
            self?.checkPhone?()
        }
        self.phoneAndCountryNode.hasNumberUpdated = { [weak self] _ in
            self?.refreshProceedEnabled()
        }
        self.emailFieldNode?.textChanged = { [weak self] _ in
            self?.refreshProceedEnabled()
        }
        self.emailFieldNode?.returnPressed = { [weak self] in
            self?.checkPhone?()
        }
        self.emailSwitchNode?.addTarget(self, action: #selector(self.emailSwitchPressed), forControlEvents: .touchUpInside)
        self.passwordFieldNode?.textChanged = { [weak self] _ in
            self?.clearPasswordError()
            self?.refreshProceedEnabled()
        }
        self.passwordFieldNode?.returnPressed = { [weak self] in
            self?.checkPhone?()
        }
        self.appleRowNode?.addTarget(self, action: #selector(self.tellomiUnavailablePressed), forControlEvents: .touchUpInside)
        self.googleRowNode?.addTarget(self, action: #selector(self.tellomiUnavailablePressed), forControlEvents: .touchUpInside)
        self.otherRowNode?.addTarget(self, action: #selector(self.tellomiUnavailablePressed), forControlEvents: .touchUpInside)
        self.recoverNode?.addTarget(self, action: #selector(self.tellomiUnavailablePressed), forControlEvents: .touchUpInside)
        self.circleGoogleNode?.addTarget(self, action: #selector(self.tellomiUnavailablePressed), forControlEvents: .touchUpInside)
        self.circleAppleNode?.addTarget(self, action: #selector(self.tellomiUnavailablePressed), forControlEvents: .touchUpInside)
        self.circleMoreNode?.addTarget(self, action: #selector(self.tellomiUnavailablePressed), forControlEvents: .touchUpInside)
        self.emailRowNode?.addTarget(self, action: #selector(self.tellomiEmailRowPressed), forControlEvents: .touchUpInside)
        self.circleEmailNode?.addTarget(self, action: #selector(self.tellomiEmailRowPressed), forControlEvents: .touchUpInside)
        self.agreementRow?.onToggle = { [weak self] in
            guard let self else {
                return
            }
            self.tellomiAgreement.setAgreed(!self.tellomiAgreement.agreed)
        }
        self.phoneAndCountryNode.keyPressed = { [weak self] num in
            if let strongSelf = self, !strongSelf.managedAnimationNode.isHidden {
                strongSelf.managedAnimationNode.animate(num: num)
            }
        }
        
        if let account = account {
            self.tokenEventsDisposable.set((account.updateLoginTokenEvents
            |> deliverOnMainQueue).startStrict(next: { [weak self] _ in
                self?.refreshQrToken()
            }))
        }
        
        self.proceedNode.pressed = { [weak self] in
            self?.checkPhone?()
        }

        if account != nil {
            self.tellomiAgreement.install(on: self.agreementNode, theme: theme, kind: .phone, chinese: tellomiLoginPrefersChinese(languageCode: tellomiInterfaceLanguageCode(strings)), openUrl: { [weak self] url in
                self?.tellomiOpenUrl?(url)
            }, changed: { [weak self] agreed in
                self?.agreementRow?.setChecked(agreed)
            })
        }
        
        self.animationNode.completed = { [weak self] _ in
            guard let self else {
                return
            }
            self.animationNode.removeFromSupernode()
            if !self.emailLogin && !self.tellomiLoginHome {
                self.managedAnimationNode.isHidden = false
            }
        }
    }
    
    deinit {
        self.exportTokenDisposable.dispose()
        self.tokenEventsDisposable.dispose()
    }
    
    override func didLoad() {
        super.didLoad()
        
        self.emailSwitchNode?.view.accessibilityIdentifier = "Auth.PhoneEntry.EmailSwitch"
        self.titleNode.view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.debugTap(_:))))
        #if DEBUG && false
        self.noticeNode.view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.debugQrTap(_:))))
        #endif
    }
    
    private var animationSnapshotView: UIView?
    private var textSnapshotView: UIView?
    private var forcedButtonFrame: CGRect?
    
    func willAnimateIn(buttonFrame: CGRect, buttonTitle: String, animationSnapshot: UIView, textSnapshot: UIView) {
        self.proceedNode.frame = buttonFrame
        
        self.proceedNode.isEnabled = true
        self.proceedNode.title = buttonTitle
        
        self.animationSnapshotView = animationSnapshot
        self.view.insertSubview(animationSnapshot, at: 0)
        
        self.textSnapshotView = textSnapshot
        self.view.insertSubview(textSnapshot, at: 0)
        
        var nodes: [ASDisplayNode] = [
            self.animationNode,
            self.titleNode,
            self.noticeNode,
            self.phoneAndCountryNode,
            self.contactSyncNode
        ]
        if let emailFieldNode = self.emailFieldNode {
            nodes.append(emailFieldNode)
        }
        if let emailSwitchNode = self.emailSwitchNode {
            nodes.append(emailSwitchNode)
        }

        for node in nodes {
            node.alpha = 0.0
        }
    }
    
    func animateIn(buttonFrame: CGRect, buttonTitle: String, animationSnapshot: UIView, textSnapshot: UIView) {
        let continueTitle = self.tellomiLoginHome ? tellomiLoginCopy(languageCode: tellomiInterfaceLanguageCode(self.strings)).verifyAndLogin : self.strings.Login_Continue
        self.proceedNode.animateTitle(to: continueTitle)
                
        self.animationSnapshotView?.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2, removeOnCompletion: false, completion: { [weak self] _ in
            self?.animationSnapshotView?.removeFromSuperview()
            self?.animationSnapshotView = nil
        })
        self.animationSnapshotView?.layer.animatePosition(from: CGPoint(), to: CGPoint(x: 0.0, y: -100.0), duration: 0.3, timingFunction: kCAMediaTimingFunctionSpring, removeOnCompletion: false, additive: true)
        self.animationSnapshotView?.layer.animateScale(from: 1.0, to: 0.3, duration: 0.4)
       
        self.textSnapshotView?.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2, removeOnCompletion: false, completion: { [weak self] _ in
            self?.textSnapshotView?.removeFromSuperview()
            self?.textSnapshotView = nil
        })
        self.textSnapshotView?.layer.animatePosition(from: CGPoint(), to: CGPoint(x: 0.0, y: -140.0), duration: 0.3, timingFunction: kCAMediaTimingFunctionSpring, removeOnCompletion: false, additive: true)
    
        var nodes: [ASDisplayNode] = [
            self.animationNode,
            self.titleNode,
            self.noticeNode,
            self.phoneAndCountryNode,
            self.contactSyncNode
        ]
        if let emailFieldNode = self.emailFieldNode {
            nodes.append(emailFieldNode)
        }
        if let emailSwitchNode = self.emailSwitchNode {
            nodes.append(emailSwitchNode)
        }
        
        self.animationNode.layer.animateScale(from: 0.3, to: 1.0, duration: 0.3)

        for node in nodes {
            node.alpha = 1.0
            node.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.3)
        }
    }
    
    func updateCountryCode() {
        self.phoneAndCountryNode.phoneInputNode.codeAndNumber = self.codeAndNumber
        let _ = self.phoneAndCountryNode.processNumberChange(number: self.phoneAndCountryNode.phoneInputNode.number)
    }
    
    func updateDisplayPasskeyLoginOption() {
        if self.account == nil || self.tellomiLoginHome {
            return
        }
        self.passkeyNotice = true
        if self.emailLogin {
            return
        }
        let attributedText = NSMutableAttributedString(attributedString: parseMarkdownIntoAttributedString(self.strings.Login_PhoneWithPasskeySubtitle, attributes: MarkdownAttributes(
            body: MarkdownAttributeSet(font: Font.regular(17.0), textColor: self.theme.list.itemPrimaryTextColor),
            bold: MarkdownAttributeSet(font: Font.semibold(17.0), textColor: self.theme.list.itemPrimaryTextColor),
            link: MarkdownAttributeSet(font: Font.regular(17.0), textColor: self.theme.list.itemAccentColor),
            linkAttribute: { url in
                return ("URL", url)
            }
        )))
        let chevronImage = generateTintedImage(image: UIImage(bundleImageName: "Item List/InlineTextRightArrow"), color: self.theme.list.itemAccentColor)
        
        if let range = attributedText.string.range(of: ">"), let chevronImage {
            attributedText.addAttribute(.attachment, value: chevronImage, range: NSRange(range, in: attributedText.string))
        }
        
        self.noticeNode.attributedText = attributedText
    }
    
    func applyEntry(countryCode: Int32, countryName: String?, number: String) {
        if self.account != nil, tellomiIsLoginEmail(number) {
            self.setTellomiSurface(.emailCode, address: tellomiNormalizedLoginEmail(number))
            return
        }
        if self.emailLogin {
            self.setTellomiSurface(.phoneCode)
        }
        self.codeAndNumber = (countryCode, countryName, number)
    }

    func containerLayoutUpdated(_ layout: ContainerViewLayout, navigationBarHeight: CGFloat, transition: ContainedViewLayoutTransition) {
        self.layoutArguments = (layout, navigationBarHeight)
        var insets = layout.insets(options: [])
        insets.top = layout.statusBarHeight ?? 20.0
        if let inputHeight = layout.inputHeight, !inputHeight.isZero {
            insets.bottom = max(inputHeight, insets.bottom)
        }

        if self.tellomiLoginHome {
            self.layoutTellomiHome(layout, insets: insets, navigationBarHeight: navigationBarHeight, transition: transition)
            return
        }
        
        let titleInset: CGFloat = layout.size.width > 320.0 ? 18.0 : 0.0
        let additionalBottomInset: CGFloat = layout.size.width > 320.0 ? 80.0 : 10.0
        
        let emailCopy = tellomiEmailLoginCopy(languageCode: tellomiInterfaceLanguageCode(self.strings))
        let title: String
        if self.emailLogin {
            title = emailCopy.title
        } else if self.account == nil {
            let loginCopy = tellomiLoginCopy(languageCode: tellomiInterfaceLanguageCode(self.strings))
            title = self.tellomiBindPhone ? loginCopy.bindPhoneTitle : self.strings.Login_NewNumber
        } else {
            title = self.strings.Login_PhoneTitle
        }
        self.titleNode.attributedText = NSAttributedString(string: title, font: Font.bold(28.0), textColor: self.theme.list.itemPrimaryTextColor)
        if self.emailLogin {
            self.noticeNode.attributedText = NSAttributedString(string: emailCopy.notice, font: Font.regular(17.0), textColor: self.theme.list.itemPrimaryTextColor, paragraphAlignment: .center)
            self.emailFieldNode?.setPlaceholder(emailCopy.placeholder, theme: self.theme)
        } else if self.tellomiBindPhone {
            let loginCopy = tellomiLoginCopy(languageCode: tellomiInterfaceLanguageCode(self.strings))
            self.noticeNode.attributedText = NSAttributedString(string: loginCopy.bindPhoneNotice, font: Font.regular(17.0), textColor: TellomiLoginChrome.palette(dark: self.theme.overallDarkAppearance).secondaryText, paragraphAlignment: .center)
            self.proceedNode.title = loginCopy.bindPhoneAction
            self.proceedNode.updateTheme(TellomiLoginChrome.buttonTheme(dark: self.theme.overallDarkAppearance))
        }
        if let emailSwitchNode = self.emailSwitchNode {
            let switchTitle = self.emailLogin ? emailCopy.switchToPhone : emailCopy.switchToEmail
            emailSwitchNode.setTitle(switchTitle, with: Font.regular(17.0), with: self.theme.list.itemAccentColor, for: [])
            emailSwitchNode.accessibilityLabel = switchTitle
        }
        self.titleActivateAreaNode.accessibilityLabel = self.titleNode.attributedText?.string ?? ""
        
        // iPhone Duo: beside a side strip the content keeps to the band between the side insets. With equal
        // insets (every other phone) it keeps the full width.
        let insetsDiffer = layout.safeInsets.left != layout.safeInsets.right
        let bandMinX: CGFloat = insetsDiffer ? layout.safeInsets.left : 0.0
        let bandWidth: CGFloat = insetsDiffer ? layout.size.width - layout.safeInsets.left - layout.safeInsets.right : layout.size.width
        
        let inset: CGFloat = 24.0
        let maximumWidth: CGFloat = min(430.0, bandWidth)
        
        // The bottom button spans iPhone Duo's side strip; it keeps clear only of a corner block at the bottom.
        let bottomSideInsets = layout.bottomEdgeSideInsets()
        let bottomBandMinX: CGFloat = insetsDiffer ? bottomSideInsets.left : 0.0
        let bottomBandWidth: CGFloat = insetsDiffer ? layout.size.width - bottomSideInsets.left - bottomSideInsets.right : layout.size.width
        let bottomMaximumWidth: CGFloat = min(430.0, bottomBandWidth)
        
        let animationSize = CGSize(width: 100.0, height: 100.0)
        let titleSize = self.titleNode.measure(CGSize(width: maximumWidth, height: CGFloat.greatestFiniteMagnitude))
        
        let noticeInset: CGFloat = self.account == nil ? 32.0 : 0.0
        
        let noticeSize = self.noticeNode.updateLayout(CGSize(width: min(274.0 + noticeInset, maximumWidth - 28.0), height: CGFloat.greatestFiniteMagnitude))
        let proceedHeight = self.proceedNode.updateLayout(width: bottomMaximumWidth - inset * 2.0, transition: transition)
        let proceedSize = CGSize(width: bottomMaximumWidth - inset * 2.0, height: proceedHeight)
        
        var items: [AuthorizationLayoutItem] = [
            AuthorizationLayoutItem(node: self.titleNode, size: titleSize, spacingBefore: AuthorizationLayoutItemSpacing(weight: titleInset, maxValue: titleInset), spacingAfter: AuthorizationLayoutItemSpacing(weight: 0.0, maxValue: 0.0)),
            AuthorizationLayoutItem(node: self.noticeNode, size: noticeSize, spacingBefore: AuthorizationLayoutItemSpacing(weight: 18.0, maxValue: 18.0), spacingAfter: AuthorizationLayoutItemSpacing(weight: 0.0, maxValue: 0.0)),
        ]
        if self.emailLogin, let emailFieldNode = self.emailFieldNode {
            items.append(AuthorizationLayoutItem(node: emailFieldNode, size: CGSize(width: maximumWidth, height: 64.0), spacingBefore: AuthorizationLayoutItemSpacing(weight: 30.0, maxValue: 30.0), spacingAfter: AuthorizationLayoutItemSpacing(weight: 0.0, maxValue: 0.0)))
        } else {
            items.append(AuthorizationLayoutItem(node: self.phoneAndCountryNode, size: CGSize(width: maximumWidth, height: 115.0), spacingBefore: AuthorizationLayoutItemSpacing(weight: 30.0, maxValue: 30.0), spacingAfter: AuthorizationLayoutItemSpacing(weight: 0.0, maxValue: 0.0)))
        }
        if let emailSwitchNode = self.emailSwitchNode {
            let measured = emailSwitchNode.measure(CGSize(width: maximumWidth, height: CGFloat.greatestFiniteMagnitude))
            items.append(AuthorizationLayoutItem(node: emailSwitchNode, size: CGSize(width: maximumWidth, height: max(44.0, measured.height)), spacingBefore: AuthorizationLayoutItemSpacing(weight: 8.0, maxValue: 8.0), spacingAfter: AuthorizationLayoutItemSpacing(weight: 0.0, maxValue: 0.0)))
        }
        
        if layout.size.width > 320.0 {
            if !self.emailLogin {
                items.insert(AuthorizationLayoutItem(node: self.animationNode, size: animationSize, spacingBefore: AuthorizationLayoutItemSpacing(weight: 10.0, maxValue: 10.0), spacingAfter: AuthorizationLayoutItemSpacing(weight: 0.0, maxValue: 0.0)), at: 0)
            }
            self.proceedNode.isHidden = false
            self.animationNode.isHidden = self.emailLogin
            self.animationNode.visibility = !self.emailLogin
        } else {
            insets.top = navigationBarHeight
            self.proceedNode.isHidden = true
            self.animationNode.isHidden = true
            self.managedAnimationNode.isHidden = true
        }
        
        let contactSyncSize = self.contactSyncNode.updateLayout(width: maximumWidth)
        if self.hasOtherAccounts {
            self.contactSyncNode.isHidden = false
            items.append(AuthorizationLayoutItem(node: self.contactSyncNode, size: contactSyncSize, spacingBefore: AuthorizationLayoutItemSpacing(weight: 14.0, maxValue: 14.0), spacingAfter: AuthorizationLayoutItemSpacing(weight: 0.0, maxValue: 0.0)))
        } else {
            self.contactSyncNode.isHidden = true
        }
        
        let buttonFrame: CGRect
        if let forcedButtonFrame = self.forcedButtonFrame, (layout.inputHeight ?? 0.0).isZero {
            buttonFrame = forcedButtonFrame
        } else {
            buttonFrame = CGRect(origin: CGPoint(x: bottomBandMinX + floorToScreenPixels((bottomBandWidth - proceedSize.width) / 2.0), y: layout.size.height - insets.bottom - proceedSize.height - inset), size: proceedSize)
        }
        
        transition.updateFrame(node: self.proceedNode, frame: buttonFrame)
        
        self.animationNode.updateLayout(size: animationSize)
        
        let _ = layoutAuthorizationItems(bounds: CGRect(origin: CGPoint(x: bandMinX, y: insets.top), size: CGSize(width: bandWidth, height: layout.size.height - insets.top - insets.bottom - additionalBottomInset)), items: items, transition: transition, failIfDoesNotFit: false)
        
        transition.updateFrame(node: self.managedAnimationNode, frame: self.animationNode.frame)
        
        self.titleActivateAreaNode.frame = self.titleNode.frame
        self.noticeActivateAreaNode.accessibilityLabel = self.noticeNode.attributedText?.string ?? ""
        self.noticeActivateAreaNode.frame = self.noticeNode.frame
    }
    
    private func layoutTellomiHome(_ layout: ContainerViewLayout, insets: UIEdgeInsets, navigationBarHeight: CGFloat, transition: ContainedViewLayoutTransition) {
        let emailCopy = tellomiEmailLoginCopy(languageCode: tellomiInterfaceLanguageCode(self.strings))
        let loginCopy = tellomiLoginCopy(languageCode: tellomiInterfaceLanguageCode(self.strings))
        let surface = self.tellomiSurface
        let title: String
        let titleAlignment: NSTextAlignment
        switch surface {
        case .phoneCode:
            title = loginCopy.phoneTitle
            titleAlignment = .center
        case .phonePassword:
            title = loginCopy.phonePasswordTitle
            titleAlignment = .left
        case .emailCode:
            title = emailCopy.title
            titleAlignment = .left
        case .emailPassword:
            title = loginCopy.emailPasswordTitle
            titleAlignment = .left
        }
        let titleFont = surface == .phoneCode ? Font.bold(20.0) : Font.semibold(22.0)
        self.titleNode.attributedText = NSAttributedString(string: title, font: titleFont, textColor: self.theme.list.itemPrimaryTextColor, paragraphAlignment: titleAlignment)
        self.proceedNode.title = surface.isPassword ? loginCopy.login : loginCopy.verifyAndLogin
        self.proceedNode.updateTheme(TellomiLoginChrome.buttonTheme(dark: self.theme.overallDarkAppearance))
        let agreementKind: TellomiSignUpAgreement.Kind = surface.showsCarrierAgreement ? .phone : .email
        self.tellomiAgreement.setKind(agreementKind)
        if surface.isEmail {
            self.noticeNode.attributedText = NSAttributedString(string: emailCopy.notice, font: Font.regular(13.0), textColor: TellomiLoginChrome.secondaryText, paragraphAlignment: .left)
            self.emailFieldNode?.setPlaceholder(emailCopy.placeholder, theme: self.theme)
            self.noticeNode.isHidden = surface != .emailCode
        } else {
            self.noticeNode.attributedText = NSAttributedString(string: "", font: Font.regular(13.0), textColor: TellomiLoginChrome.secondaryText)
            self.noticeNode.isHidden = true
        }
        if let emailSwitchNode = self.emailSwitchNode {
            let switchTitle = surface.isPassword ? loginCopy.codeLogin : loginCopy.passwordLogin
            emailSwitchNode.setTitle(switchTitle, with: Font.regular(15.0), with: TellomiLoginChrome.link, for: [])
            emailSwitchNode.accessibilityLabel = switchTitle
        }
        self.passwordFieldNode?.setPlaceholder(loginCopy.passwordPlaceholder)
        self.titleActivateAreaNode.accessibilityLabel = title

        let insetsDiffer = layout.safeInsets.left != layout.safeInsets.right
        let bandMinX: CGFloat = insetsDiffer ? layout.safeInsets.left : 0.0
        let bandWidth: CGFloat = insetsDiffer ? layout.size.width - layout.safeInsets.left - layout.safeInsets.right : layout.size.width
        let columnWidth = min(430.0, bandWidth)
        let columnX = bandMinX + floor((bandWidth - columnWidth) / 2.0)
        let contentX = columnX + 24.0
        let contentWidth = columnWidth - 48.0

        self.animationNode.isHidden = true
        self.animationNode.visibility = false
        self.managedAnimationNode.isHidden = true
        self.contactSyncNode.isHidden = true
        self.agreementNode.isHidden = false
        self.agreementRow?.isHidden = false
        self.proceedNode.isHidden = false

        let showPhone = !surface.isEmail
        let showEmail = surface.isEmail
        let showPassword = surface.isPassword
        // Keep Apple / Google / Email / Other on the phone home while the keyboard is up.
        let showHomeRows = surface == .phoneCode
        let showCircles = surface != .phoneCode && (layout.inputHeight ?? 0.0) < 20.0
        self.phoneAndCountryNode.isHidden = !showPhone
        self.emailFieldNode?.isHidden = !showEmail
        self.passwordFieldNode?.isHidden = !showPassword
        self.passwordFieldNode?.setEyeOnLeft(!surface.isEmail)
        self.emailSwitchNode?.isHidden = false
        self.modeIconNode?.isHidden = false
        self.orDividerNode?.isHidden = !showHomeRows
        self.appleRowNode?.isHidden = !showHomeRows
        self.googleRowNode?.isHidden = !showHomeRows
        self.emailRowNode?.isHidden = !showHomeRows
        self.otherRowNode?.isHidden = !showHomeRows
        self.recoverNode?.isHidden = !showHomeRows
        let showEmailCircle = showCircles && !surface.isEmail
        self.circleGoogleNode?.isHidden = !showCircles
        self.circleAppleNode?.isHidden = !showCircles
        self.circleEmailNode?.isHidden = !showEmailCircle
        self.circleMoreNode?.isHidden = !showCircles

        let proceedHeight = self.proceedNode.updateLayout(width: contentWidth, transition: transition)
        let agreementCentered = !surface.showsCarrierAgreement
        let agreementSize = self.agreementRow?.updateLayout(width: contentWidth, centered: agreementCentered) ?? self.agreementNode.updateLayout(CGSize(width: contentWidth, height: 80.0))
        let titleSize = self.titleNode.measure(CGSize(width: contentWidth, height: 80.0))
        let noticeSize = self.noticeNode.isHidden ? CGSize() : self.noticeNode.updateLayout(CGSize(width: contentWidth, height: 60.0))

        var y = max(navigationBarHeight, insets.top) + (surface == .phoneCode ? 28.0 : 16.0)
        transition.updateFrame(node: self.titleNode, frame: CGRect(x: contentX, y: y, width: contentWidth, height: titleSize.height))
        y += titleSize.height + (self.noticeNode.isHidden ? 22.0 : 8.0)
        if !self.noticeNode.isHidden {
            transition.updateFrame(node: self.noticeNode, frame: CGRect(x: contentX, y: y, width: contentWidth, height: noticeSize.height))
            y += noticeSize.height + 16.0
        }

        let fieldHeight: CGFloat = 68.0
        if showPhone {
            transition.updateFrame(node: self.phoneAndCountryNode, frame: CGRect(x: columnX, y: y, width: columnWidth, height: fieldHeight))
            y += fieldHeight + 4.0
        }
        if showEmail, let emailFieldNode = self.emailFieldNode {
            transition.updateFrame(node: emailFieldNode, frame: CGRect(x: columnX, y: y, width: columnWidth, height: fieldHeight))
            y += fieldHeight + 4.0
        }
        if showPassword, let passwordFieldNode = self.passwordFieldNode {
            transition.updateFrame(node: passwordFieldNode, frame: CGRect(x: columnX, y: y, width: columnWidth, height: fieldHeight))
            y += fieldHeight
            if let passwordErrorNode = self.passwordErrorNode, !passwordErrorNode.isHidden {
                let errorSize = passwordErrorNode.updateLayout(CGSize(width: contentWidth, height: 40.0))
                transition.updateFrame(node: passwordErrorNode, frame: CGRect(x: contentX, y: y + 4.0, width: contentWidth, height: errorSize.height))
                y += errorSize.height + 8.0
            } else {
                y += 4.0
            }
        }

        if let emailSwitchNode = self.emailSwitchNode {
            let linkHeight: CGFloat = 32.0
            transition.updateFrame(node: emailSwitchNode, frame: CGRect(x: columnX, y: y, width: columnWidth, height: linkHeight))
            if let modeIconNode = self.modeIconNode {
                let iconSide: CGFloat = 16.0
                transition.updateFrame(node: modeIconNode, frame: CGRect(x: contentX, y: y + floor((linkHeight - iconSide) / 2.0), width: iconSide, height: iconSide))
            }
            y += linkHeight + 8.0
        }

        transition.updateFrame(node: self.proceedNode, frame: CGRect(x: contentX, y: y, width: contentWidth, height: proceedHeight))
        y += proceedHeight + 16.0

        if showHomeRows {
            if let orDividerNode = self.orDividerNode {
                transition.updateFrame(node: orDividerNode, frame: CGRect(x: contentX, y: y, width: contentWidth, height: 24.0))
                y += 36.0
            }
            let rowHeight: CGFloat = 48.0
            let rowGap: CGFloat = 12.0
            for row in [self.appleRowNode, self.googleRowNode, self.emailRowNode, self.otherRowNode] {
                if let row {
                    transition.updateFrame(node: row, frame: CGRect(x: contentX, y: y, width: contentWidth, height: rowHeight))
                    y += rowHeight + rowGap
                }
            }
            if let recoverNode = self.recoverNode {
                y += 4.0
                transition.updateFrame(node: recoverNode, frame: CGRect(x: contentX, y: y, width: contentWidth, height: 36.0))
            }
            let bottom = layout.size.height - max(insets.bottom, layout.intrinsicInsets.bottom) - agreementSize.height - 8.0
            if let agreementRow = self.agreementRow {
                transition.updateFrame(node: agreementRow, frame: CGRect(x: contentX, y: max(y + 12.0, bottom), width: contentWidth, height: agreementSize.height))
            }
        } else if let agreementRow = self.agreementRow {
            transition.updateFrame(node: agreementRow, frame: CGRect(x: contentX, y: y, width: contentWidth, height: agreementSize.height))
        }

        if showCircles {
            let circle: CGFloat = 52.0
            let bottomY = layout.size.height - max(layout.intrinsicInsets.bottom, 16.0) - circle - 12.0
            var icons: [ASDisplayNode] = []
            if let circleGoogleNode = self.circleGoogleNode {
                icons.append(circleGoogleNode)
            }
            if let circleAppleNode = self.circleAppleNode {
                icons.append(circleAppleNode)
            }
            if showEmailCircle, let circleEmailNode = self.circleEmailNode {
                icons.append(circleEmailNode)
            }
            if let circleMoreNode = self.circleMoreNode {
                icons.append(circleMoreNode)
            }
            let gap: CGFloat = 22.0
            let total = circle * CGFloat(icons.count) + gap * CGFloat(max(icons.count - 1, 0))
            var x = columnX + floor((columnWidth - total) / 2.0)
            for icon in icons {
                transition.updateFrame(node: icon, frame: CGRect(x: x, y: bottomY, width: circle, height: circle))
                x += circle + gap
            }
        }

        if let agreementRow = self.agreementRow {
            self.view.bringSubviewToFront(agreementRow.view)
        }
        self.titleActivateAreaNode.frame = self.titleNode.frame
        self.noticeActivateAreaNode.accessibilityLabel = self.noticeNode.attributedText?.string ?? ""
        self.noticeActivateAreaNode.frame = self.noticeNode.frame
    }

    func activateInput() {
        switch self.tellomiSurface {
        case .emailCode, .emailPassword:
            if self.tellomiSurface.isPassword, !self.emailAddress.isEmpty, self.password.isEmpty {
                self.passwordFieldNode?.textField.textField.becomeFirstResponder()
            } else {
                self.emailFieldNode?.textField.textField.becomeFirstResponder()
            }
        case .phonePassword:
            if !self.phoneAndCountryNode.phoneInputNode.number.isEmpty, self.password.isEmpty {
                self.passwordFieldNode?.textField.textField.becomeFirstResponder()
            } else {
                self.phoneAndCountryNode.phoneInputNode.numberField.textField.becomeFirstResponder()
            }
        case .phoneCode:
            self.phoneAndCountryNode.phoneInputNode.numberField.textField.becomeFirstResponder()
        }
    }
    
    func animateError() {
        if self.emailLogin, let emailFieldNode = self.emailFieldNode {
            emailFieldNode.layer.addShakeAnimation()
        } else {
            self.phoneAndCountryNode.phoneInputNode.countryCodeField.layer.addShakeAnimation()
            self.phoneAndCountryNode.phoneInputNode.numberField.layer.addShakeAnimation()
        }
    }

    private func clearPasswordError() {
        guard self.passwordErrorNode?.isHidden == false else {
            return
        }
        self.passwordErrorNode?.isHidden = true
        if let (layout, navigationBarHeight) = self.layoutArguments {
            self.containerLayoutUpdated(layout, navigationBarHeight: navigationBarHeight, transition: .immediate)
        }
    }

    func animateAgreementError() {
        self.agreementNode.layer.addShakeAnimation()
    }

    private func refreshProceedEnabled() {
        if self.emailLogin {
            self.proceedNode.isEnabled = tellomiIsLoginEmail(self.emailAddress)
            return
        }
        let isServiceNumber = self.phoneAndCountryNode.phoneInputNode.number.hasPrefix("+999")
        if self.phoneAndCountryNode.hasCountry || isServiceNumber {
            self.proceedNode.isEnabled = !self.phoneAndCountryNode.phoneInputNode.codeAndNumber.2.isEmpty || isServiceNumber
        } else {
            self.proceedNode.isEnabled = false
        }
    }

    func setTellomiSurface(_ surface: TellomiLoginSurface, address: String? = nil) {
        guard self.account != nil else {
            return
        }
        self.tellomiSurface = surface
        if let address, let emailFieldNode = self.emailFieldNode {
            emailFieldNode.setText(address)
        }
        self.clearPasswordError()
        self.refreshProceedEnabled()
        if let (layout, navigationBarHeight) = self.layoutArguments {
            self.containerLayoutUpdated(layout, navigationBarHeight: navigationBarHeight, transition: .immediate)
        }
        self.tellomiSurfaceChanged?()
    }

    func popTellomiSurface() -> Bool {
        switch self.tellomiSurface {
        case .phoneCode:
            return false
        case .phonePassword:
            self.setTellomiSurface(.phoneCode)
            return true
        case .emailPassword:
            self.setTellomiSurface(.emailCode)
            return true
        case .emailCode:
            self.setTellomiSurface(.phoneCode)
            return true
        }
    }

    func setTellomiAgreed(_ agreed: Bool) {
        self.tellomiAgreement.setAgreed(agreed)
        self.agreementRow?.setChecked(agreed)
    }

    @objc private func emailSwitchPressed() {
        if self.inProgress {
            return
        }
        switch self.tellomiSurface {
        case .phoneCode:
            self.setTellomiSurface(.phonePassword)
        case .phonePassword:
            self.setTellomiSurface(.phoneCode)
        case .emailCode:
            self.setTellomiSurface(.emailPassword)
        case .emailPassword:
            self.setTellomiSurface(.emailCode)
        }
        self.activateInput()
    }

    @objc private func tellomiEmailRowPressed() {
        if self.inProgress {
            return
        }
        self.setTellomiSurface(.emailCode)
        self.activateInput()
    }

    @objc private func tellomiUnavailablePressed() {
        self.tellomiUnavailable?()
    }
    
    private var debugTapCounter: (Double, Int) = (0.0, 0)
    @objc private func debugTap(_ recognizer: UITapGestureRecognizer) {
        if case .ended = recognizer.state {
            let timestamp = CACurrentMediaTime()
            if self.debugTapCounter.0 < timestamp - 0.4 {
                self.debugTapCounter.0 = timestamp
                self.debugTapCounter.1 = 0
            }
            
            if self.debugTapCounter.0 >= timestamp - 0.4 {
                self.debugTapCounter.0 = timestamp
                self.debugTapCounter.1 += 1
            }
            
            if self.debugTapCounter.1 >= 10 {
                self.debugTapCounter.1 = 0
                
                self.debugAction()
            }
        }
    }
    
    @objc private func debugQrTap(_ recognizer: UITapGestureRecognizer) {
        if self.qrNode == nil {
            let qrNode = ASImageNode()
            qrNode.frame = CGRect(origin: CGPoint(x: 16.0, y: 64.0 + 16.0), size: CGSize(width: 200.0, height: 200.0))
            self.qrNode = qrNode
            self.addSubnode(qrNode)
            
            self.refreshQrToken()
        }
    }
    
    private func refreshQrToken() {
        guard let account = self.account else {
            return
        }
        let sharedContext = self.sharedContext
        let tokenSignal = sharedContext.activeAccountContexts
        |> castError(ExportAuthTransferTokenError.self)
        |> take(1)
        |> mapToSignal { activeAccountsAndInfo -> Signal<ExportAuthTransferTokenResult, ExportAuthTransferTokenError> in
            let (_, activeAccounts, _) = activeAccountsAndInfo
            let activeProductionUserIds = activeAccounts.map({ $0.1.account }).filter({ !$0.testingEnvironment }).map({ $0.peerId.id })
            let activeTestingUserIds = activeAccounts.map({ $0.1.account }).filter({ $0.testingEnvironment }).map({ $0.peerId.id })
            
            let allProductionUserIds = activeProductionUserIds
            let allTestingUserIds = activeTestingUserIds
            
            return TelegramEngineUnauthorized(account: account).auth.exportAuthTransferToken(accountManager: sharedContext.accountManager, otherAccountUserIds: account.testingEnvironment ? allTestingUserIds : allProductionUserIds, syncContacts: true)
        }
        
        self.exportTokenDisposable.set((tokenSignal
        |> deliverOnMainQueue).startStrict(next: { [weak self] result in
            guard let strongSelf = self else {
                return
            }
            switch result {
            case let .displayToken(token):
                var tokenString = token.value.base64EncodedString()
                //print("export token \(tokenString)")
                tokenString = tokenString.replacingOccurrences(of: "+", with: "-")
                tokenString = tokenString.replacingOccurrences(of: "/", with: "_")
                let urlString = "tg://login?token=\(tokenString)"
                let _ = (qrCode(string: urlString, color: .black, backgroundColor: .white, icon: .none)
                |> deliverOnMainQueue).startStandalone(next: { _, generate in
                    guard let strongSelf = self else {
                        return
                    }
                    
                    let context = generate(TransformImageArguments(corners: ImageCorners(), imageSize: CGSize(width: 200.0, height: 200.0), boundingSize: CGSize(width: 200.0, height: 200.0), intrinsicInsets: UIEdgeInsets()))
                    if let image = context?.generateImage() {
                        strongSelf.qrNode?.image = image
                    }
                })
                
                let timestamp = Int32(Date().timeIntervalSince1970)
                let timeout = max(5, token.validUntil - timestamp)
                strongSelf.exportTokenDisposable.set((Signal<Never, NoError>.complete()
                |> delay(Double(timeout), queue: .mainQueue())).startStrict(completed: {
                    guard let strongSelf = self else {
                        return
                    }
                    strongSelf.refreshQrToken()
                }))
            case let .changeAccountAndRetry(account):
                strongSelf.exportTokenDisposable.set(nil)
                strongSelf.account = account
                strongSelf.accountUpdated?(account)
                strongSelf.tokenEventsDisposable.set((account.updateLoginTokenEvents
                |> deliverOnMainQueue).startStrict(next: { _ in
                    self?.refreshQrToken()
                }))
                strongSelf.refreshQrToken()
            case .loggedIn, .passwordRequested:
                strongSelf.exportTokenDisposable.set(nil)
            }
        }))
    }
}

final class PhoneConfirmationController: ViewController {
    private var controllerNode: Node {
        return self.displayNode as! Node
    }
    
    private let theme: PresentationTheme
    private let strings: PresentationStrings
    private let code: String
    private let number: String
    private weak var sourceController: AuthorizationSequencePhoneEntryController?
    
    var inProgress: Bool = false {
        didSet {
            if self.inProgress != oldValue {
                if self.inProgress {
                    self.controllerNode.proceedNode.transitionToProgress()
                } else {
                    self.controllerNode.proceedNode.transitionFromProgress()
                }
            }
        }
    }
    
    var proceed: () -> Void = {}
    
    class Node: ASDisplayNode {
        private let theme: PresentationTheme
        private let strings: PresentationStrings
        
        private let code: String
        private let number: String
        
        private let dimNode: ASDisplayNode
        private let backgroundNode: ASDisplayNode
        
        private let codeSourceNode: ImmediateTextNode
        private let phoneSourceNode: ImmediateTextNode
        
        private let codeTargetNode: ImmediateTextNode
        private let phoneTargetNode: ImmediateTextNode
        private let measureTargetNode: ImmediateTextNode
        
        private let textNode: ImmediateTextNode
        private let textActivateAreaNode: AccessibilityAreaNode
        
        private let cancelButton: HighlightableButtonNode
        fileprivate let proceedNode: SolidRoundedButtonNode
        
        var proceed: () -> Void = {}
        var cancel: () -> Void = {}
        
        private var validLayout: ContainerViewLayout?
        
        init(theme: PresentationTheme, strings: PresentationStrings, code: String, number: String) {
            self.theme = theme
            self.strings = strings
            
            self.code = code
            self.number = number
            
            self.dimNode = ASDisplayNode()
            self.dimNode.backgroundColor = UIColor(white: 0.0, alpha: 0.4)
            
            self.backgroundNode = ASDisplayNode()
            self.backgroundNode.backgroundColor = theme.list.itemBlocksBackgroundColor
            self.backgroundNode.cornerRadius = 42.0
            
            let bundled = tellomiBundledChineseLoginCopy(strings)
            let confirmText = bundled?.phoneConfirm ?? strings.Login_PhoneNumberConfirmation
            let editText = bundled?.edit ?? strings.Login_Edit
            let continueText = bundled?.continueAction ?? strings.Login_Continue
            self.textNode = ImmediateTextNode()
            self.textNode.displaysAsynchronously = false
            self.textNode.attributedText = NSAttributedString(string: confirmText, font: Font.regular(17.0), textColor: theme.list.itemPrimaryTextColor)
            self.textNode.textAlignment = .center
            
            self.textActivateAreaNode = AccessibilityAreaNode()
            self.textActivateAreaNode.accessibilityTraits = .staticText
            
            self.cancelButton = HighlightableButtonNode()
            self.cancelButton.setTitle(editText, with: Font.regular(19.0), with: theme.list.itemAccentColor, for: .normal)
            self.cancelButton.accessibilityTraits = [.button]
            self.cancelButton.accessibilityLabel = editText
            
            self.proceedNode = SolidRoundedButtonNode(title: continueText, theme: SolidRoundedButtonTheme(theme: theme), glass: false, height: 50.0, cornerRadius: 50.0 * 0.5)
            self.proceedNode.progressType = .embedded
            self.proceedNode.accessibilityIdentifier = "Auth.PhoneConfirm.ContinueButton"

            let font = Font.with(size: 20.0, design: .regular, traits: [.monospacedNumbers])
            let largeFont = Font.with(size: 34.0, design: .regular, weight: .bold, traits: [.monospacedNumbers])
            
            self.codeSourceNode = ImmediateTextNode()
            self.codeSourceNode.alpha = 0.0
            self.codeSourceNode.displaysAsynchronously = false
            self.codeSourceNode.attributedText = NSAttributedString(string: code, font: font, textColor: theme.list.itemPrimaryTextColor)
            
            self.phoneSourceNode = ImmediateTextNode()
            self.phoneSourceNode.alpha = 0.0
            self.phoneSourceNode.displaysAsynchronously = false
            
            let sourceString = NSMutableAttributedString(string: number, font: font, textColor: theme.list.itemPrimaryTextColor)
            sourceString.addAttribute(NSAttributedString.Key.kern, value: 1.6, range: NSRange(location: 0, length: sourceString.length))
            self.phoneSourceNode.attributedText = sourceString
            
            self.codeTargetNode = ImmediateTextNode()
            self.codeTargetNode.displaysAsynchronously = false
            self.codeTargetNode.attributedText = NSAttributedString(string: code, font: largeFont, textColor: theme.list.itemPrimaryTextColor)
            
            self.phoneTargetNode = ImmediateTextNode()
            self.phoneTargetNode.displaysAsynchronously = false
            
            self.measureTargetNode = ImmediateTextNode()
            self.measureTargetNode.displaysAsynchronously = false
            self.measureTargetNode.maximumNumberOfLines = 1
            
            let targetString = NSMutableAttributedString(string: number, font: largeFont, textColor: theme.list.itemPrimaryTextColor)
            targetString.addAttribute(NSAttributedString.Key.kern, value: 1.6, range: NSRange(location: 0, length: sourceString.length))
            self.phoneTargetNode.attributedText = targetString
            
            super.init()
            
            self.clipsToBounds = false
            
            self.addSubnode(self.dimNode)
            self.addSubnode(self.backgroundNode)
            
            self.addSubnode(self.codeSourceNode)
            self.addSubnode(self.phoneSourceNode)
            
            self.addSubnode(self.codeTargetNode)
            self.addSubnode(self.phoneTargetNode)
            
            self.addSubnode(self.textNode)
            self.addSubnode(self.textActivateAreaNode)
            
            self.addSubnode(self.cancelButton)
            self.addSubnode(self.proceedNode)
            
            self.cancelButton.addTarget(self, action: #selector(self.cancelPressed), forControlEvents: .touchUpInside)
            self.proceedNode.pressed = { [weak self] in
                self?.proceed()
            }
        }
        
        override func didLoad() {
            super.didLoad()
            
            self.dimNode.view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.dimTapped)))
        }
        
        @objc private func dimTapped() {
            self.cancelPressed()
        }
        
        @objc private func cancelPressed() {
            self.dimNode.isUserInteractionEnabled = false
            self.cancel()
        }
        
        func animateIn(codeNode: ASDisplayNode, numberNode: ASDisplayNode, buttonNode: ASDisplayNode) {
            guard let layout = self.validLayout else {
                return
            }
            let codeFrame = codeNode.convert(codeNode.bounds, to: nil)
            let numberFrame = numberNode.convert(numberNode.bounds, to: nil)
            let buttonFrame = buttonNode.convert(buttonNode.bounds, to: nil)
            
            codeNode.isHidden = true
            numberNode.isHidden = true
            buttonNode.isHidden = true
            
            self.dimNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.3)
            
            let duration: Double = 0.25
            
            let codeSize = self.codeSourceNode.updateLayout(layout.size)
            self.codeSourceNode.frame = CGRect(origin: CGPoint(x: codeFrame.midX - codeSize.width / 2.0, y: codeFrame.midY - codeSize.height / 2.0), size: codeSize)
            
            let numberSize = self.phoneSourceNode.updateLayout(layout.size)
            self.phoneSourceNode.frame = CGRect(origin: CGPoint(x: numberFrame.minX, y: numberFrame.midY - numberSize.height / 2.0), size: numberSize)
            
            let targetScale = codeSize.height / self.codeTargetNode.frame.height
            let sourceScale = self.codeTargetNode.frame.height / codeSize.height
            
            self.codeSourceNode.layer.animateScale(from: 1.0, to: sourceScale, duration: duration)
            self.codeSourceNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: duration)
            self.codeSourceNode.layer.animatePosition(from: self.codeSourceNode.position, to: self.codeTargetNode.position, duration: duration)
            
            self.phoneSourceNode.layer.animateScale(from: 1.0, to: sourceScale, duration: duration)
            self.phoneSourceNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: duration)
            self.phoneSourceNode.layer.animatePosition(from: self.phoneSourceNode.position, to: self.phoneTargetNode.position, duration: duration)
            
            self.codeTargetNode.layer.animateScale(from: targetScale, to: 1.0, duration: duration)
            self.codeTargetNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: duration)
            self.codeTargetNode.layer.animatePosition(from: self.codeSourceNode.position, to: self.codeTargetNode.position, duration: duration)
            
            self.phoneTargetNode.layer.animateScale(from: targetScale, to: 1.0, duration: duration)
            self.phoneTargetNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: duration)
            self.phoneTargetNode.layer.animatePosition(from: self.phoneSourceNode.position, to: self.phoneTargetNode.position, duration: duration)
            
            self.backgroundNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.1)
            
            self.backgroundNode.layer.animateFrame(from: CGRect(origin: CGPoint(x: self.backgroundNode.frame.origin.x + 6.0, y: codeFrame.minY), size: CGSize(width: self.backgroundNode.frame.width - 12.0, height: buttonFrame.maxY + 18.0 - codeFrame.minY)), to: self.backgroundNode.frame, duration: duration)
            
            self.textNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: duration)
            self.textNode.layer.animateScale(from: 0.5, to: 1.0, duration: duration)
            self.textNode.layer.animatePosition(from: CGPoint(x: -100.0, y: -45.0), to: CGPoint(), duration: duration, additive: true)
            
            self.cancelButton.layer.animateAlpha(from: 0.0, to: 1.0, duration: duration)
            self.cancelButton.layer.animateScale(from: 0.5, to: 1.0, duration: duration)
            self.cancelButton.layer.animatePosition(from: CGPoint(x: -100.0, y: -70.0), to: CGPoint(), duration: duration, additive: true)
            
            self.proceedNode.layer.animatePosition(from: buttonFrame.center, to: self.proceedNode.position, duration: duration)
        }
        
        func animateOut(codeNode: ASDisplayNode, numberNode: ASDisplayNode, buttonNode: ASDisplayNode, completion: @escaping () -> Void) {
            let codeFrame = codeNode.convert(codeNode.bounds, to: nil)
            let numberFrame = numberNode.convert(numberNode.bounds, to: nil)
            let buttonFrame = buttonNode.convert(buttonNode.bounds, to: nil)
            
            self.dimNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2, removeOnCompletion: false)
            
            let duration: Double = 0.25
            
            let codeSize = self.codeSourceNode.updateLayout(self.frame.size)
            self.codeSourceNode.frame = CGRect(origin: CGPoint(x: codeFrame.midX - codeSize.width / 2.0, y: codeFrame.midY - codeSize.height / 2.0), size: codeSize)
            
            let numberSize = self.phoneSourceNode.updateLayout(self.frame.size)
            self.phoneSourceNode.frame = CGRect(origin: CGPoint(x: numberFrame.minX, y: numberFrame.midY - numberSize.height / 2.0), size: numberSize)
            
            let targetScale = codeSize.height / self.codeTargetNode.frame.height
            let sourceScale = self.codeTargetNode.frame.height / codeSize.height
            
            self.codeSourceNode.layer.animateScale(from: sourceScale, to: 1.0, duration: duration)
            self.codeSourceNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: duration)
            self.codeSourceNode.layer.animatePosition(from: self.codeTargetNode.position, to: self.codeSourceNode.position, duration: duration)
            
            self.phoneSourceNode.layer.animateScale(from: sourceScale, to: 1.0, duration: duration)
            self.phoneSourceNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: duration)
            self.phoneSourceNode.layer.animatePosition(from: self.phoneTargetNode.position, to: self.phoneSourceNode.position, duration: duration)
            
            self.codeTargetNode.layer.animateScale(from: 1.0, to: targetScale, duration: duration)
            self.codeTargetNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: duration, removeOnCompletion: false)
            self.codeTargetNode.layer.animatePosition(from: self.codeTargetNode.position, to: self.codeSourceNode.position, duration: duration)
            
            Queue.mainQueue().after(0.2) {
                codeNode.isHidden = false
                numberNode.isHidden = false
                buttonNode.isHidden = false
            }
            
            self.phoneTargetNode.layer.animateScale(from: 1.0, to: targetScale, duration: duration)
            self.phoneTargetNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: duration, removeOnCompletion: false, completion: { _ in
                completion()
            })
            self.phoneTargetNode.layer.animatePosition(from: self.phoneTargetNode.position, to: self.phoneSourceNode.position, duration: duration)
            
            self.backgroundNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2, delay: 0.1, removeOnCompletion: false)
            self.backgroundNode.layer.animateFrame(from: self.backgroundNode.frame, to: CGRect(origin: CGPoint(x: self.backgroundNode.frame.origin.x + 6.0, y: codeFrame.minY), size: CGSize(width: self.backgroundNode.frame.width - 12.0, height: buttonFrame.maxY + 18.0 - codeFrame.minY)), duration: duration)
                        
            self.textNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2, removeOnCompletion: false)
            self.textNode.layer.animateScale(from: 1.0, to: 0.5, duration: duration, removeOnCompletion: false)
            self.textNode.layer.animatePosition(from: CGPoint(), to: CGPoint(x: -100.0, y: -45.0), duration: duration, removeOnCompletion: false, additive: true)
            
            self.cancelButton.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2, removeOnCompletion: false)
            self.cancelButton.layer.animateScale(from: 1.0, to: 0.5, duration: duration, removeOnCompletion: false)
            self.cancelButton.layer.animatePosition(from: CGPoint(), to: CGPoint(x: -100.0, y: -70.0), duration: duration, removeOnCompletion: false, additive: true)
            
            self.proceedNode.layer.animatePosition(from: self.proceedNode.position, to: buttonFrame.center, duration: duration, removeOnCompletion: false)
        }
        
        func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
            let hadLayout = self.validLayout != nil
            self.validLayout = layout
            
            let sideInset: CGFloat = 8.0
            let innerInset: CGFloat = 18.0
            
            // iPhone Duo: beside a side strip the card keeps to the band between the side insets. With equal
            // insets (every other phone) it is centered on the full width.
            let insetsDiffer = layout.safeInsets.left != layout.safeInsets.right
            let bandMinX: CGFloat = insetsDiffer ? layout.safeInsets.left : 0.0
            let bandWidth: CGFloat = insetsDiffer ? layout.size.width - layout.safeInsets.left - layout.safeInsets.right : layout.size.width
            
            let maximumWidth: CGFloat = min(430.0, bandWidth)
            
            transition.updateFrame(node: self.dimNode, frame: CGRect(origin: CGPoint(x: -layout.size.width, y: 0.0), size: CGSize(width: layout.size.width * 3.0, height: layout.size.height)))
            
            let backgroundSize = CGSize(width: maximumWidth - sideInset * 2.0, height: 243.0)
            
            let originY: CGFloat
            if case .regular = layout.metrics.widthClass {
                originY = floorToScreenPixels((layout.size.height - backgroundSize.height) / 2.0)
            } else {
                let hasOnScreenNavigation = layout.deviceMetrics.onScreenNavigationHeight(inLandscape: false, systemOnScreenNavigationHeight: nil) != nil
                if hasOnScreenNavigation || layout.deviceMetrics.hasTopNotch || layout.deviceMetrics.hasDynamicIsland {
                    originY = layout.size.height - backgroundSize.height - 260.0
                } else {
                    originY = floorToScreenPixels((layout.size.height - backgroundSize.height) / 2.0)
                }
            }
            
            let backgroundFrame = CGRect(origin: CGPoint(x: bandMinX + floorToScreenPixels((bandWidth - backgroundSize.width) / 2.0), y: originY), size: backgroundSize)
            transition.updateFrame(node: self.backgroundNode, frame: backgroundFrame)
              
            let maxWidth = bandWidth - 20.0
            if !hadLayout {
                var fontSize = 34.0
                if layout.size.width < 375.0 {
                    fontSize = 30.0
                }
              
                self.measureTargetNode.attributedText = NSAttributedString(string: self.code + " " + self.number, font: Font.with(size: fontSize, design: .regular, weight: .bold, traits: [.monospacedNumbers]), textColor: self.theme.list.itemPrimaryTextColor)
                let measuredSize = self.measureTargetNode.updateLayout(CGSize(width: 1000.0, height: .greatestFiniteMagnitude))
                if measuredSize.width > maxWidth {
                    fontSize = floor(0.8 * fontSize)
                }
                
                let largeFont = Font.with(size: fontSize, design: .regular, weight: .bold, traits: [.monospacedNumbers])
                
                self.codeTargetNode.attributedText = NSAttributedString(string: self.code, font: largeFont, textColor: self.theme.list.itemPrimaryTextColor)
                let targetString = NSMutableAttributedString(string: self.number, font: largeFont, textColor: self.theme.list.itemPrimaryTextColor)
                targetString.addAttribute(NSAttributedString.Key.kern, value: 1.6, range: NSRange(location: 0, length: targetString.length))
                self.phoneTargetNode.attributedText = targetString
            }
            
            let spacing: CGFloat = 10.0
            
            let codeSize = self.codeTargetNode.updateLayout(CGSize(width: maxWidth, height: .greatestFiniteMagnitude))
            let numberSize = self.phoneTargetNode.updateLayout(CGSize(width: maxWidth - codeSize.width - spacing, height: .greatestFiniteMagnitude))
            
            let totalWidth = codeSize.width + numberSize.width + spacing
            
            let codeFrame = CGRect(origin: CGPoint(x: floorToScreenPixels((backgroundSize.width - totalWidth) / 2.0), y: 30.0), size: codeSize)
            transition.updateFrame(node: self.codeTargetNode, frame: codeFrame.offsetBy(dx: backgroundFrame.minX, dy: backgroundFrame.minY))
            
            let numberFrame = CGRect(origin: CGPoint(x: codeFrame.maxX + spacing, y: 30.0), size: numberSize)
            transition.updateFrame(node: self.phoneTargetNode, frame: numberFrame.offsetBy(dx: backgroundFrame.minX, dy: backgroundFrame.minY))
            
            let textSize = self.textNode.updateLayout(backgroundSize)
            transition.updateFrame(node: self.textNode, frame: CGRect(origin: CGPoint(x: floorToScreenPixels((backgroundSize.width - textSize.width) / 2.0), y: 88.0), size: textSize).offsetBy(dx: backgroundFrame.minX, dy: backgroundFrame.minY))
            self.textActivateAreaNode.frame = self.textNode.frame
            let confirmText = tellomiBundledChineseLoginCopy(self.strings)?.phoneConfirm ?? self.strings.Login_PhoneNumberConfirmation
            self.textActivateAreaNode.accessibilityLabel = "\(self.code) \(self.number). \(confirmText)"
            
            let proceedWidth = backgroundSize.width - innerInset * 2.0
            let proceedHeight = self.proceedNode.updateLayout(width: proceedWidth, transition: transition)
            transition.updateFrame(node: self.proceedNode, frame: CGRect(origin: CGPoint(x: innerInset, y: backgroundSize.height - proceedHeight - innerInset), size: CGSize(width: proceedWidth, height: proceedHeight)).offsetBy(dx: backgroundFrame.minX, dy: backgroundFrame.minY))
            
            let cancelSize = self.cancelButton.measure(layout.size)
            transition.updateFrame(node: self.cancelButton, frame: CGRect(origin: CGPoint(x: floorToScreenPixels((backgroundSize.width - cancelSize.width) / 2.0), y: backgroundSize.height - proceedHeight - innerInset - cancelSize.height - 25.0), size: cancelSize).offsetBy(dx: backgroundFrame.minX, dy: backgroundFrame.minY))
        }
    }
    
    public init(theme: PresentationTheme, strings: PresentationStrings, code: String, number: String, sourceController: AuthorizationSequencePhoneEntryController) {
        self.theme = theme
        self.strings = strings
        self.code = code
        self.number = number
        self.sourceController = sourceController
        
        super.init(navigationBarPresentationData: nil)
        
        self.blocksBackgroundWhenInOverlay = true
        
        self.statusBar.statusBarStyle = .Ignore
    }
    
    required public init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private var isDismissed = false
    override public func loadDisplayNode() {
        self.displayNode = Node(theme: self.theme, strings: self.strings, code: self.code, number: self.number)
        self.displayNodeDidLoad()
        
        self.controllerNode.proceed = { [weak self] in
            self?.proceed()
        }
        self.controllerNode.cancel = { [weak self] in
            if let strongSelf = self, let sourceController = strongSelf.sourceController {
                strongSelf.controllerNode.animateOut(codeNode: sourceController.codeNode, numberNode: sourceController.numberNode, buttonNode: sourceController.buttonNode, completion: { [weak self] in
                    self?.dismiss()
                })
            }
        }
    }
    
    func dismissAnimated() {
        self.controllerNode.cancel()
    }
    
    func transitionOut() {
        self.controllerNode.cancel()
        
        let transition = ContainedViewLayoutTransition.animated(duration: 0.5, curve: .spring)
        transition.updatePosition(layer: self.view.layer, position: CGPoint(x: self.view.center.x - self.view.frame.width, y: self.view.center.y))
    }
    
    private var didPlayAppearanceAnimation = false
    override public func viewDidAppear(_ animated: Bool) {
        if !self.didPlayAppearanceAnimation {
            self.didPlayAppearanceAnimation = true
            if let sourceController = self.sourceController {
                self.controllerNode.animateIn(codeNode: sourceController.codeNode, numberNode: sourceController.numberNode, buttonNode: sourceController.buttonNode)
            }
        }
    }
    
    override public func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        
        self.controllerNode.containerLayoutUpdated(layout, transition: transition)
    }
}

private final class PhoneKeyNode: ASDisplayNode {
    private let imageNode: ASImageNode
    private var highlightedNode: ASImageNode?
    
    private let image: UIImage?
    private let highlightedImage: UIImage?
    
    init(offset: CGPoint, image: UIImage?, highlightedImage: UIImage?) {
        self.image = image
        self.highlightedImage = highlightedImage
        
        self.imageNode = ASImageNode()
        self.imageNode.displaysAsynchronously = false
        self.imageNode.image = image
        
        super.init()
        
        self.clipsToBounds = true
        
        if let imageSize = self.imageNode.image?.size {
            self.imageNode.frame = CGRect(origin: CGPoint(x: -offset.x, y: -offset.y), size: imageSize)
        }
        
        self.addSubnode(self.imageNode)
    }
    
    func animatePress() {
        guard self.highlightedNode == nil else {
            return
        }
        
        let highlightedNode = ASImageNode()
        highlightedNode.displaysAsynchronously = false
        highlightedNode.image = self.highlightedImage
        highlightedNode.frame = self.imageNode.frame
        self.addSubnode(highlightedNode)
        self.highlightedNode = highlightedNode
        
        highlightedNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.16, removeOnCompletion: false, completion: { [weak self] _ in
            self?.highlightedNode?.removeFromSupernode()
            self?.highlightedNode = nil
        })
        
        let values: [NSNumber] = [0.75, 0.5, 0.75, 1.0]
        self.layer.animateKeyframes(values: values, duration: 0.16, keyPath: "transform.scale")
    }
}

private final class ManagedPhoneAnimationNode: ManagedAnimationNode {
    private var timer: SwiftSignalKit.Timer?
    
    private let plateNode: ASDisplayNode
    private var nodes: [PhoneKeyNode]
    
    init(lottieSettings: LottieRenderingSettings) {
        self.plateNode = ASDisplayNode()
        self.plateNode.backgroundColor = UIColor(rgb: 0xc30023)
        self.plateNode.frame = CGRect(x: 27.0, y: 38.0, width: 46.0, height: 32.0)
        
        let image = UIImage(bundleImageName: "Settings/Keypad")
        let highlightedImage = generateTintedImage(image: image, color: UIColor(rgb: 0x000000, alpha: 0.4))
        
        var nodes: [PhoneKeyNode] = []
        for i in 0 ..< 9 {
            let offset: CGPoint
            switch i {
                case 1:
                    offset = CGPoint(x: 15.0, y: 0.0)
                case 2:
                    offset = CGPoint(x: 30.0, y: 0.0)
                case 3:
                    offset = CGPoint(x: 0.0, y: 10.0)
                case 4:
                    offset = CGPoint(x: 15.0, y: 10.0)
                case 5:
                    offset = CGPoint(x: 30.0, y: 10.0)
                case 6:
                    offset = CGPoint(x: 0.0, y: 21.0)
                case 7:
                    offset = CGPoint(x: 15.0, y: 21.0)
                case 8:
                    offset = CGPoint(x: 30.0, y: 21.0)
                default:
                    offset = CGPoint(x: 0.0, y: 0.0)
            }
            let node = PhoneKeyNode(offset: offset, image: image, highlightedImage: highlightedImage)
            node.frame = CGRect(origin: offset.offsetBy(dx: 28.0, dy: 38.0), size: CGSize(width: 15.0, height: 10.0))
            nodes.append(node)
        }
        self.nodes = nodes
        
        super.init(size: CGSize(width: 100.0, height: 100.0), lottieSettings: lottieSettings)
        
        self.trackTo(item: ManagedAnimationItem(source: .local("IntroPhone"), frames: .range(startFrame: 0, endFrame: 0), duration: 0.001))
        
        self.addSubnode(self.plateNode)
        
        for node in nodes {
            self.addSubnode(node)
        }
    }
    
    func animate(num: Int) {
        guard num != 0 else {
            return
        }
        let index = max(0, min(self.nodes.count - 1, num - 1))
        self.nodes[index].animatePress()
    }
}
