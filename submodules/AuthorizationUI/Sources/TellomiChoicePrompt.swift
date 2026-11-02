import Foundation
import UIKit
import AsyncDisplayKit
import Display

struct TellomiChoiceRow {
    enum Style {
        /// Language row. The bool is whether this row is the current language.
        case check(Bool)
        /// Help and resend rows.
        case link
    }

    let title: String
    let style: Style
    let action: () -> Void
}

/// Centered card used by the login language button and「收不到验证码？」.
/// Same dim, radius, and title weight as the agreement card.
final class TellomiChoicePromptController: ViewController {
    private let promptTitle: String
    private let rows: [TellomiChoiceRow]
    private let cancelTitle: String
    private let dark: Bool

    init(promptTitle: String, rows: [TellomiChoiceRow], cancelTitle: String, dark: Bool) {
        self.promptTitle = promptTitle
        self.rows = rows
        self.cancelTitle = cancelTitle
        self.dark = dark
        super.init(navigationBarPresentationData: nil)
        self.statusBar.statusBarStyle = .Ignore
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadDisplayNode() {
        self.displayNode = TellomiChoicePromptNode(title: self.promptTitle, rows: self.rows, cancelTitle: self.cancelTitle, dark: self.dark, dismiss: { [weak self] in
            self?.dismiss()
        })
        self.displayNodeDidLoad()
    }
}

private final class TellomiChoicePromptNode: ASDisplayNode {
    private let dimNode = ASDisplayNode()
    private let cardNode = ASDisplayNode()
    private let titleNode = ImmediateTextNode()
    private let rowNodes: [TellomiChoiceRowNode]
    private let cancelNode = HighlightableButtonNode()
    private let dismissPrompt: () -> Void

    init(title: String, rows: [TellomiChoiceRow], cancelTitle: String, dark: Bool, dismiss: @escaping () -> Void) {
        self.dismissPrompt = dismiss
        let palette = TellomiLoginChrome.palette(dark: dark)
        self.rowNodes = rows.map { TellomiChoiceRowNode(row: $0, dark: dark, dismiss: dismiss) }
        super.init()

        self.dimNode.backgroundColor = UIColor(white: 0.0, alpha: 0.45)
        self.cardNode.backgroundColor = palette.rowBackground
        self.cardNode.cornerRadius = 16.0
        self.cardNode.clipsToBounds = true

        self.titleNode.attributedText = NSAttributedString(string: title, font: Font.semibold(17.0), textColor: palette.rowText, paragraphAlignment: .center)
        self.titleNode.maximumNumberOfLines = 0
        self.titleNode.displaysAsynchronously = false

        self.cancelNode.setTitle(cancelTitle, with: Font.regular(16.0), with: palette.secondaryText, for: [])
        self.cancelNode.accessibilityLabel = cancelTitle
        self.cancelNode.accessibilityTraits = [.button]
        self.cancelNode.addTarget(self, action: #selector(self.cancelPressed), forControlEvents: .touchUpInside)

        self.addSubnode(self.dimNode)
        self.addSubnode(self.cardNode)
        self.cardNode.addSubnode(self.titleNode)
        for row in self.rowNodes {
            self.cardNode.addSubnode(row)
        }
        self.cardNode.addSubnode(self.cancelNode)
    }

    @objc private func cancelPressed() {
        self.dismissPrompt()
    }

    override func didLoad() {
        super.didLoad()
        self.dimNode.view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.cancelPressed)))
    }

    override func layout() {
        super.layout()
        self.dimNode.frame = self.bounds
        let cardWidth = min(320.0, self.bounds.width - 48.0)
        let inner = cardWidth - 8.0
        let titleSize = self.titleNode.updateLayout(CGSize(width: cardWidth - 40.0, height: 80.0))
        let rowHeight: CGFloat = 48.0
        let cardHeight = 18.0 + titleSize.height + 8.0 + rowHeight * CGFloat(self.rowNodes.count) + 4.0 + rowHeight + 8.0
        let cardFrame = CGRect(x: floor((self.bounds.width - cardWidth) / 2.0), y: floor((self.bounds.height - cardHeight) / 2.0), width: cardWidth, height: cardHeight)
        self.cardNode.frame = cardFrame
        var y: CGFloat = 18.0
        self.titleNode.frame = CGRect(x: 20.0, y: y, width: cardWidth - 40.0, height: titleSize.height)
        y += titleSize.height + 8.0
        for row in self.rowNodes {
            row.frame = CGRect(x: 4.0, y: y, width: inner, height: rowHeight)
            y += rowHeight
        }
        y += 4.0
        self.cancelNode.frame = CGRect(x: 4.0, y: y, width: inner, height: rowHeight)
    }
}

private final class TellomiChoiceRowNode: HighlightableButtonNode {
    private let labelNode = ImmediateTextNode()
    private let markNode = ImmediateTextNode()
    private let rowAction: () -> Void
    private let dismissPrompt: () -> Void
    private let centered: Bool

    init(row: TellomiChoiceRow, dark: Bool, dismiss: @escaping () -> Void) {
        self.rowAction = row.action
        self.dismissPrompt = dismiss
        let palette = TellomiLoginChrome.palette(dark: dark)
        let checked: Bool
        let color: UIColor
        let font: UIFont
        let alignment: NSTextAlignment
        switch row.style {
        case let .check(isChecked):
            checked = isChecked
            color = palette.rowText
            font = isChecked ? Font.semibold(16.0) : Font.regular(16.0)
            alignment = .left
        case .link:
            checked = false
            color = TellomiLoginChrome.link
            font = Font.regular(16.0)
            alignment = .center
        }
        self.centered = alignment == .center
        super.init()
        self.labelNode.attributedText = NSAttributedString(string: row.title, font: font, textColor: color, paragraphAlignment: alignment)
        self.labelNode.maximumNumberOfLines = 1
        self.labelNode.displaysAsynchronously = false
        self.labelNode.isUserInteractionEnabled = false
        self.markNode.attributedText = NSAttributedString(string: "\u{2713}", font: Font.semibold(18.0), textColor: palette.rowText)
        self.markNode.displaysAsynchronously = false
        self.markNode.isUserInteractionEnabled = false
        self.markNode.isHidden = !checked
        self.accessibilityLabel = row.title
        if checked {
            self.accessibilityTraits = [.button, .selected]
        } else {
            self.accessibilityTraits = [.button]
        }
        self.addSubnode(self.labelNode)
        self.addSubnode(self.markNode)
        self.addTarget(self, action: #selector(self.pressed), forControlEvents: .touchUpInside)
    }

    @objc private func pressed() {
        self.dismissPrompt()
        self.rowAction()
    }

    override func layout() {
        super.layout()
        let markSize = self.markNode.updateLayout(CGSize(width: 24.0, height: self.bounds.height))
        let labelWidth = self.markNode.isHidden ? self.bounds.width - 32.0 : self.bounds.width - 32.0 - markSize.width - 8.0
        let labelSize = self.labelNode.updateLayout(CGSize(width: max(0.0, labelWidth), height: self.bounds.height))
        let labelX: CGFloat
        if self.centered {
            labelX = floor((self.bounds.width - labelSize.width) / 2.0)
        } else {
            labelX = 16.0
        }
        self.labelNode.frame = CGRect(x: labelX, y: floor((self.bounds.height - labelSize.height) / 2.0), width: labelSize.width, height: labelSize.height)
        self.markNode.frame = CGRect(x: self.bounds.width - 16.0 - markSize.width, y: floor((self.bounds.height - markSize.height) / 2.0), width: markSize.width, height: markSize.height)
    }
}
