import AsyncDisplayKit
import Display
import Foundation
import TelegramPresentationData
import UIKit

final class TellomiFeedScreenNode: ASDisplayNode {
    private let titleNode = ImmediateTextNode()
    private let textNode = ImmediateTextNode()

    init(presentationData: PresentationData) {
        super.init()
        self.titleNode.maximumNumberOfLines = 2
        self.titleNode.textAlignment = .center
        self.textNode.maximumNumberOfLines = 4
        self.textNode.textAlignment = .center
        self.addSubnode(self.titleNode)
        self.addSubnode(self.textNode)
        self.update(presentationData: presentationData, postUnavailable: false)
    }

    func update(presentationData: PresentationData, postUnavailable: Bool) {
        let copy = TellomiTabCopy.resolve(languageCode: presentationData.strings.primaryComponent.languageCode)
        self.backgroundColor = presentationData.theme.list.plainBackgroundColor
        self.titleNode.attributedText = NSAttributedString(string: copy.feedEmptyTitle, font: Font.semibold(17.0), textColor: presentationData.theme.list.itemPrimaryTextColor, paragraphAlignment: .center)
        let body = postUnavailable ? copy.feedPostUnavailable : copy.feedEmptyText
        self.textNode.attributedText = NSAttributedString(string: body, font: Font.regular(15.0), textColor: presentationData.theme.list.itemSecondaryTextColor, paragraphAlignment: .center)
    }

    func updateLayout(size: CGSize, topInset: CGFloat, bottomInset: CGFloat, transition: ContainedViewLayoutTransition) {
        let width = min(280.0, max(1.0, size.width - 48.0))
        let titleSize = self.titleNode.updateLayout(CGSize(width: width, height: 120.0))
        let textSize = self.textNode.updateLayout(CGSize(width: width, height: 160.0))
        let gap: CGFloat = 8.0
        let contentHeight = titleSize.height + gap + textSize.height
        let availableTop = topInset
        let availableBottom = max(availableTop, size.height - bottomInset)
        let originY = availableTop + max(0.0, (availableBottom - availableTop - contentHeight) / 2.0)
        let titleFrame = CGRect(x: floor((size.width - titleSize.width) / 2.0), y: originY, width: titleSize.width, height: titleSize.height)
        let textFrame = CGRect(x: floor((size.width - textSize.width) / 2.0), y: titleFrame.maxY + gap, width: textSize.width, height: textSize.height)
        transition.updateFrame(node: self.titleNode, frame: titleFrame)
        transition.updateFrame(node: self.textNode, frame: textFrame)
    }
}
