import AsyncDisplayKit
import Display
import Foundation
import TelegramPresentationData
import UIKit

func tellomiSettingsCGRect(x: Double, y: Double, width: Double, height: Double) -> CGRect {
    return CGRect(x: CGFloat(x), y: CGFloat(y), width: CGFloat(width), height: CGFloat(height))
}

/// Settings header card (D-30). The header node owns the frames; this view only draws them.
final class TellomiSettingsHeaderCard: NSObject {
    let backgroundNode = ASDisplayNode()
    let editButton = HighlightTrackingButtonNode()
    let editText = ImmediateTextNode()
    var onEdit: (() -> Void)?

    override init() {
        super.init()
        self.backgroundNode.cornerRadius = 10.0
        self.backgroundNode.clipsToBounds = true
        self.backgroundNode.isUserInteractionEnabled = false
        self.backgroundNode.isHidden = true
        self.editButton.isHidden = true
        self.editText.displaysAsynchronously = false
        self.editText.isUserInteractionEnabled = false
        self.editText.maximumNumberOfLines = 1
        self.editButton.addSubnode(self.editText)
    }

    func install(in content: ASDisplayNode) {
        content.insertSubnode(self.backgroundNode, at: 0)
        content.addSubnode(self.editButton)
        self.editButton.addTarget(self, action: #selector(self.editPressed), forControlEvents: .touchUpInside)
    }

    func update(visible: Bool, backgroundFrame: CGRect, editFrame: CGRect, editTitle: String, accent: UIColor, background: UIColor, transition: ContainedViewLayoutTransition) {
        self.backgroundNode.backgroundColor = background
        self.backgroundNode.isHidden = !visible
        self.editButton.isHidden = !visible
        self.editButton.isUserInteractionEnabled = visible
        self.editButton.accessibilityLabel = editTitle
        self.editText.attributedText = NSAttributedString(string: editTitle, font: Font.semibold(17.0), textColor: accent)
        let textSize = self.editText.updateLayout(CGSize(width: max(0.0, editFrame.width), height: editFrame.height))
        let textFrame = CGRect(origin: CGPoint(x: floor((editFrame.width - textSize.width) / 2.0), y: floor((editFrame.height - textSize.height) / 2.0)), size: textSize)
        transition.updateFrame(node: self.backgroundNode, frame: backgroundFrame)
        transition.updateFrame(node: self.editButton, frame: editFrame)
        transition.updateFrame(node: self.editText, frame: textFrame)
    }

    @objc func editPressed() {
        self.onEdit?()
    }
}
