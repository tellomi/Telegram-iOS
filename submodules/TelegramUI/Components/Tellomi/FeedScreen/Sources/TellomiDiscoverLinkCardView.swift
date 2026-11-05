import Display
import Foundation
import TellomiDiscover
import UIKit

/// Title, description, and cover for one stored or just-fetched preview.
/// The cover is the stored `image` URL. This view does not read HTML.
final class TellomiDiscoverLinkCardView: UIControl {
    private let titleLabel = UILabel()
    private let siteLabel = UILabel()
    private let bodyLabel = UILabel()
    private let imageView = UIImageView()
    private var imageURL: String?
    private var openURL: String?
    private var showsImage = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.layer.cornerRadius = 10
        self.clipsToBounds = true
        self.titleLabel.font = Font.semibold(15)
        self.titleLabel.numberOfLines = 2
        self.siteLabel.font = Font.regular(12)
        self.siteLabel.numberOfLines = 1
        self.bodyLabel.font = Font.regular(13)
        self.bodyLabel.numberOfLines = 3
        self.imageView.contentMode = .scaleAspectFill
        self.imageView.clipsToBounds = true
        self.imageView.isHidden = true
        self.addSubview(self.imageView)
        self.addSubview(self.titleLabel)
        self.addSubview(self.siteLabel)
        self.addSubview(self.bodyLabel)
        self.addTarget(self, action: #selector(self.pressed), for: .touchUpInside)
        self.accessibilityIdentifier = "tellomi.discover.link"
        self.isHidden = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(primary: UIColor, secondary: UIColor, accent: UIColor, background: UIColor) {
        self.titleLabel.textColor = primary
        self.siteLabel.textColor = secondary
        self.bodyLabel.textColor = secondary
        self.backgroundColor = background
        self.tintColor = accent
    }

    func showLoading(_ text: String) {
        self.openURL = nil
        self.imageURL = nil
        self.showsImage = false
        self.imageView.image = nil
        self.imageView.isHidden = true
        self.titleLabel.text = text
        self.siteLabel.text = nil
        self.siteLabel.isHidden = true
        self.bodyLabel.text = nil
        self.bodyLabel.isHidden = true
        self.isHidden = false
        self.isUserInteractionEnabled = false
        self.setNeedsLayout()
    }

    func show(_ preview: TellomiDiscoverLink.Preview, opens: Bool) {
        guard TellomiDiscoverLink.fetchable(preview.url) else {
            self.hide()
            return
        }
        self.openURL = opens ? preview.url : nil
        self.titleLabel.text = preview.titleLine()
        if let site = preview.siteLine() {
            self.siteLabel.text = site
            self.siteLabel.isHidden = false
        } else {
            self.siteLabel.text = nil
            self.siteLabel.isHidden = true
        }
        if let description = preview.description, !description.isEmpty {
            self.bodyLabel.text = description
            self.bodyLabel.isHidden = false
        } else {
            self.bodyLabel.text = nil
            self.bodyLabel.isHidden = true
        }
        let image = preview.image.flatMap { TellomiDiscoverLink.fetchable($0) ? $0 : nil }
        self.showsImage = image != nil
        self.imageView.isHidden = image == nil
        if self.imageURL != image {
            self.imageURL = image
            self.imageView.image = nil
            if let image {
                TellomiDiscoverLinkClient.loadImage(image) { [weak self] picture in
                    guard let self, self.imageURL == image else {
                        return
                    }
                    self.imageView.image = picture
                }
            }
        }
        self.isHidden = false
        self.isUserInteractionEnabled = opens && self.openURL != nil
        self.setNeedsLayout()
    }

    func hide() {
        self.openURL = nil
        self.imageURL = nil
        self.showsImage = false
        self.imageView.image = nil
        self.isHidden = true
        self.isUserInteractionEnabled = false
    }

    @objc private func pressed() {
        guard let openURL = self.openURL, let url = URL(string: openURL), TellomiDiscoverLink.fetchable(openURL) else {
            return
        }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        guard !self.isHidden else {
            return CGSize(width: size.width, height: 0)
        }
        let measured = self.measured(width: size.width)
        return CGSize(width: size.width, height: measured.height)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let measured = self.measured(width: self.bounds.width)
        self.imageView.frame = measured.image
        self.titleLabel.frame = measured.title
        self.siteLabel.frame = measured.site
        self.bodyLabel.frame = measured.body
    }

    private func measured(width: CGFloat) -> (height: CGFloat, image: CGRect, title: CGRect, site: CGRect, body: CGRect) {
        let pad: CGFloat = 10
        let imageSide: CGFloat = self.showsImage ? 72 : 0
        let gap: CGFloat = self.showsImage ? 10 : 0
        let textX = pad + imageSide + gap
        let textWidth = max(1, width - textX - pad)
        let titleSize = self.titleLabel.sizeThatFits(CGSize(width: textWidth, height: 48))
        let siteSize = self.siteLabel.isHidden ? .zero : self.siteLabel.sizeThatFits(CGSize(width: textWidth, height: 18))
        let bodySize = self.bodyLabel.isHidden ? .zero : self.bodyLabel.sizeThatFits(CGSize(width: textWidth, height: 60))
        var y = pad
        let title = CGRect(x: textX, y: y, width: textWidth, height: titleSize.height)
        y = title.maxY
        let site = self.siteLabel.isHidden ? CGRect.zero : CGRect(x: textX, y: y + 2, width: textWidth, height: siteSize.height)
        if !self.siteLabel.isHidden {
            y = site.maxY
        }
        let body = self.bodyLabel.isHidden ? CGRect.zero : CGRect(x: textX, y: y + 2, width: textWidth, height: bodySize.height)
        if !self.bodyLabel.isHidden {
            y = body.maxY
        }
        let textHeight = y + pad
        let imageHeight = self.showsImage ? imageSide + pad * 2 : 0
        let height = max(textHeight, imageHeight)
        let image = self.showsImage ? CGRect(x: pad, y: pad, width: imageSide, height: imageSide) : .zero
        return (height, image, title, site, body)
    }
}
