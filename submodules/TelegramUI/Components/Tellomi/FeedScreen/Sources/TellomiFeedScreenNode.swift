import AsyncDisplayKit
import Display
import Foundation
import TelegramPresentationData
import TellomiDiscover
import UIKit

enum TellomiFeedNodeMode {
    case legacy
    case feed
    case city
}

struct TellomiFeedNodeModel {
    var mode: TellomiFeedNodeMode
    var tabTitles: [String]
    var selectedTab: Int
    var posts: [TellomiDiscoverPost]
    var loading: Bool
    var failure: String?
    var legacyTitle: String
    var legacyBody: String
    var copy: TellomiDiscoverCopy
    var cities: [TellomiDiscoverCity] = []
}

final class TellomiFeedScreenNode: ASDisplayNode, UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate {
    var onSelectTab: ((Int) -> Void)?
    var onSelectPost: ((String) -> Void)?
    var onReportPost: ((String) -> Void)?
    var onRefresh: (() -> Void)?
    var onNearEnd: (() -> Void)?
    var onUseLocation: (() -> Void)?
    var onSubmitCity: ((String) -> Void)?
    var onSelectCity: ((String) -> Void)?

    private let titleNode = ImmediateTextNode()
    private let textNode = ImmediateTextNode()
    private let tabs = UISegmentedControl()
    private let table = UITableView(frame: .zero, style: .plain)
    private let refresh = UIRefreshControl()
    private let failureLabel = UILabel()
    private let cityPrompt = UILabel()
    private let cityHint = UILabel()
    private let cityField = UITextField()
    private let locationButton = UIButton(type: .system)
    private let cityButton = UIButton(type: .system)
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let sizingCell = TellomiDiscoverPostCell(style: .default, reuseIdentifier: nil)
    private var model = TellomiFeedNodeModel(mode: .legacy, tabTitles: [], selectedTab: 0, posts: [], loading: false, failure: nil, legacyTitle: "", legacyBody: "", copy: .resolve(languageCode: "en"))
    private var presentationData: PresentationData?
    private var layout: (size: CGSize, topInset: CGFloat, bottomInset: CGFloat)?
    private var suppressTab = false

    override init() {
        super.init()
        self.titleNode.maximumNumberOfLines = 2
        self.titleNode.textAlignment = .center
        self.textNode.maximumNumberOfLines = 5
        self.textNode.textAlignment = .center
        self.addSubnode(self.titleNode)
        self.addSubnode(self.textNode)
        self.tabs.addTarget(self, action: #selector(self.tabChanged), for: .valueChanged)
        self.table.dataSource = self
        self.table.delegate = self
        self.table.separatorInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 0)
        self.table.rowHeight = UITableView.automaticDimension
        self.table.estimatedRowHeight = 88
        self.table.register(TellomiDiscoverPostCell.self, forCellReuseIdentifier: "post")
        self.table.register(UITableViewCell.self, forCellReuseIdentifier: "city")
        self.refresh.addTarget(self, action: #selector(self.refreshChanged), for: .valueChanged)
        self.table.refreshControl = self.refresh
        self.failureLabel.numberOfLines = 2
        self.failureLabel.textAlignment = .center
        self.cityPrompt.numberOfLines = 2
        self.cityPrompt.textAlignment = .center
        self.cityHint.numberOfLines = 3
        self.cityHint.textAlignment = .center
        self.cityField.borderStyle = .roundedRect
        self.cityField.returnKeyType = .done
        self.cityField.autocorrectionType = .no
        self.cityField.delegate = self
        self.locationButton.addTarget(self, action: #selector(self.locationPressed), for: .touchUpInside)
        self.cityButton.addTarget(self, action: #selector(self.cityPressed), for: .touchUpInside)
        self.tabs.accessibilityIdentifier = "tellomi.discover.tabs"
        self.cityField.accessibilityIdentifier = "tellomi.discover.city"
    }

    override func didLoad() {
        super.didLoad()
        self.view.addSubview(self.tabs)
        self.view.addSubview(self.table)
        self.view.addSubview(self.failureLabel)
        self.view.addSubview(self.cityPrompt)
        self.view.addSubview(self.cityHint)
        self.view.addSubview(self.cityField)
        self.view.addSubview(self.locationButton)
        self.view.addSubview(self.cityButton)
        self.view.addSubview(self.spinner)
        self.apply()
    }

    func update(presentationData: PresentationData, model: TellomiFeedNodeModel) {
        self.presentationData = presentationData
        self.model = model
        self.apply()
    }

    func updateLayout(size: CGSize, topInset: CGFloat, bottomInset: CGFloat, transition: ContainedViewLayoutTransition) {
        let _ = transition
        self.layout = (size, topInset, bottomInset)
        self.applyFrames()
    }

    private func apply() {
        guard let presentationData = self.presentationData else {
            return
        }
        let copy = self.model.copy
        self.backgroundColor = presentationData.theme.list.plainBackgroundColor
        self.titleNode.attributedText = NSAttributedString(string: self.model.legacyTitle, font: Font.semibold(17.0), textColor: presentationData.theme.list.itemPrimaryTextColor, paragraphAlignment: .center)
        self.textNode.attributedText = NSAttributedString(string: self.model.legacyBody, font: Font.regular(15.0), textColor: presentationData.theme.list.itemSecondaryTextColor, paragraphAlignment: .center)
        let titles = self.model.tabTitles
        self.suppressTab = true
        if self.tabs.numberOfSegments != titles.count {
            self.tabs.removeAllSegments()
            for (index, title) in titles.enumerated() {
                self.tabs.insertSegment(withTitle: title, at: index, animated: false)
            }
        } else {
            for (index, title) in titles.enumerated() {
                self.tabs.setTitle(title, forSegmentAt: index)
            }
        }
        if !titles.isEmpty {
            self.tabs.selectedSegmentIndex = min(max(0, self.model.selectedTab), titles.count - 1)
        }
        self.suppressTab = false
        self.tabs.selectedSegmentTintColor = presentationData.theme.list.itemAccentColor
        self.failureLabel.text = self.model.failure
        self.failureLabel.textColor = presentationData.theme.list.itemDestructiveColor
        self.failureLabel.font = Font.regular(14.0)
        self.cityPrompt.text = copy.cityPrompt
        self.cityPrompt.textColor = presentationData.theme.list.itemPrimaryTextColor
        self.cityPrompt.font = Font.semibold(17.0)
        self.cityHint.text = copy.cityDenied
        self.cityHint.textColor = presentationData.theme.list.itemSecondaryTextColor
        self.cityHint.font = Font.regular(14.0)
        self.cityField.placeholder = copy.cityPlaceholder
        self.cityField.textColor = presentationData.theme.list.itemPrimaryTextColor
        self.locationButton.setTitle(copy.useLocation, for: .normal)
        self.cityButton.setTitle(copy.confirmCity, for: .normal)
        self.locationButton.setTitleColor(presentationData.theme.list.itemAccentColor, for: .normal)
        self.cityButton.setTitleColor(presentationData.theme.list.itemAccentColor, for: .normal)
        self.table.backgroundColor = presentationData.theme.list.plainBackgroundColor
        self.table.separatorColor = presentationData.theme.list.itemPlainSeparatorColor
        let live = self.model.mode != .legacy
        self.tabs.isHidden = !live
        self.table.isHidden = self.model.mode == .legacy
        self.failureLabel.isHidden = self.model.failure == nil || !live
        let city = self.model.mode == .city
        self.cityPrompt.isHidden = !city
        self.cityHint.isHidden = !city
        self.cityField.isHidden = true
        self.locationButton.isHidden = !city
        self.cityButton.isHidden = true
        let showLegacy = self.model.mode == .legacy || (self.model.mode == .feed && self.model.posts.isEmpty && !self.model.loading)
        self.titleNode.isHidden = !showLegacy
        self.textNode.isHidden = !showLegacy
        if self.model.loading {
            self.spinner.startAnimating()
        } else {
            self.spinner.stopAnimating()
            self.refresh.endRefreshing()
        }
        if self.isNodeLoaded {
            self.table.reloadData()
        }
        self.applyFrames()
    }

    private func applyFrames() {
        guard let layout = self.layout else {
            return
        }
        let size = layout.size
        let topInset = layout.topInset
        let bottomInset = layout.bottomInset
        let width = min(280.0, max(1.0, size.width - 48.0))
        let titleSize = self.titleNode.updateLayout(CGSize(width: width, height: 120.0))
        let textSize = self.textNode.updateLayout(CGSize(width: width, height: 180.0))
        let gap: CGFloat = 8.0
        let contentHeight = titleSize.height + gap + textSize.height
        let originY = topInset + max(0.0, (size.height - bottomInset - topInset - contentHeight) / 2.0)
        self.titleNode.frame = CGRect(x: floor((size.width - titleSize.width) / 2.0), y: originY, width: titleSize.width, height: titleSize.height)
        self.textNode.frame = CGRect(x: floor((size.width - textSize.width) / 2.0), y: self.titleNode.frame.maxY + gap, width: textSize.width, height: textSize.height)
        guard self.isNodeLoaded else {
            return
        }
        let side: CGFloat = 16.0
        let tabY = topInset + 8.0
        self.tabs.frame = CGRect(x: side, y: tabY, width: size.width - side * 2.0, height: 32.0)
        let bodyTop = self.tabs.frame.maxY + 8.0
        var cursor = bodyTop
        if self.model.failure != nil {
            self.failureLabel.frame = CGRect(x: side, y: cursor, width: size.width - side * 2.0, height: 36.0)
            cursor += 36.0
        } else {
            self.failureLabel.frame = .zero
        }
        self.cityPrompt.frame = CGRect(x: side, y: cursor, width: size.width - side * 2.0, height: 28.0)
        self.cityHint.frame = CGRect(x: side, y: self.cityPrompt.frame.maxY + 4.0, width: size.width - side * 2.0, height: 56.0)
        self.locationButton.frame = CGRect(x: side, y: self.cityHint.frame.maxY + 4.0, width: size.width - side * 2.0, height: 40.0)
        if self.model.mode == .city {
            cursor = self.locationButton.frame.maxY + 8.0
        }
        let bottom = max(cursor, size.height - bottomInset)
        self.table.frame = CGRect(x: 0, y: cursor, width: size.width, height: max(0, bottom - cursor))
        self.spinner.center = CGPoint(x: size.width / 2.0, y: cursor + 28.0)
    }

    @objc private func tabChanged() {
        guard !self.suppressTab else {
            return
        }
        self.onSelectTab?(self.tabs.selectedSegmentIndex)
    }

    @objc private func refreshChanged() {
        self.onRefresh?()
    }

    @objc private func locationPressed() {
        self.onUseLocation?()
    }

    @objc private func cityPressed() {
        self.onSubmitCity?(self.cityField.text ?? "")
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        self.onSubmitCity?(textField.text ?? "")
        textField.resignFirstResponder()
        return true
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let _ = (tableView, section)
        if self.model.mode == .city {
            return self.model.cities.count
        }
        guard self.model.mode == .feed else {
            return 0
        }
        return self.model.posts.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if self.model.mode == .city {
            let cell = tableView.dequeueReusableCell(withIdentifier: "city", for: indexPath)
            let city = self.model.cities[indexPath.row]
            var content = cell.defaultContentConfiguration()
            content.text = city.name
            content.textProperties.color = self.presentationData?.theme.list.itemPrimaryTextColor ?? .label
            cell.contentConfiguration = content
            cell.accessibilityIdentifier = "tellomi.discover.city.\(city.code)"
            cell.backgroundColor = self.presentationData?.theme.list.plainBackgroundColor
            return cell
        }
        let cell = tableView.dequeueReusableCell(withIdentifier: "post", for: indexPath) as! TellomiDiscoverPostCell
        let post = self.model.posts[indexPath.row]
        let summary = tellomiDiscoverPostSummary(post: post, copy: self.model.copy, list: true)
        let primary = self.presentationData?.theme.list.itemPrimaryTextColor ?? .label
        let secondary = self.presentationData?.theme.list.itemSecondaryTextColor ?? .secondaryLabel
        cell.apply(summary: summary, preview: post.linkPreview, primary: primary, secondary: secondary, accent: self.presentationData?.theme.list.itemAccentColor ?? .systemBlue, background: self.presentationData?.theme.list.itemHighlightedBackgroundColor ?? .secondarySystemBackground)
        cell.reportButton.accessibilityIdentifier = "tellomi.discover.report.\(post.id)"
        cell.onReport = { [weak self] in
            self?.onReportPost?(post.id)
        }
        cell.accessibilityIdentifier = "tellomi.discover.post.\(post.id)"
        cell.backgroundColor = self.presentationData?.theme.list.plainBackgroundColor
        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        if self.model.mode == .city {
            return 48
        }
        guard self.model.posts.indices.contains(indexPath.row) else {
            return 0
        }
        let post = self.model.posts[indexPath.row]
        let summary = tellomiDiscoverPostSummary(post: post, copy: self.model.copy, list: true)
        let primary = self.presentationData?.theme.list.itemPrimaryTextColor ?? .label
        let secondary = self.presentationData?.theme.list.itemSecondaryTextColor ?? .secondaryLabel
        self.sizingCell.apply(summary: summary, preview: post.linkPreview, primary: primary, secondary: secondary, accent: self.presentationData?.theme.list.itemAccentColor ?? .systemBlue, background: self.presentationData?.theme.list.itemHighlightedBackgroundColor ?? .secondarySystemBackground)
        return self.sizingCell.sizeThatFits(CGSize(width: tableView.bounds.width, height: 0)).height
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if self.model.mode == .city {
            guard self.model.cities.indices.contains(indexPath.row) else {
                return
            }
            self.onSelectCity?(self.model.cities[indexPath.row].code)
            return
        }
        guard self.model.posts.indices.contains(indexPath.row) else {
            return
        }
        self.onSelectPost?(self.model.posts[indexPath.row].id)
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        let _ = (tableView, cell)
        guard self.model.mode == .feed else {
            return
        }
        if indexPath.row == self.model.posts.count - 1, tableView.contentOffset.y > 1 {
            self.onNearEnd?()
        }
    }
}

private final class TellomiDiscoverPostCell: UITableViewCell {
    var onReport: (() -> Void)?
    let reportButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let bodyLabel = UILabel()
    private let metaLabel = UILabel()
    private let linkCard = TellomiDiscoverLinkCardView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        self.titleLabel.font = Font.semibold(16.0)
        self.titleLabel.numberOfLines = 1
        self.bodyLabel.font = Font.regular(15.0)
        self.bodyLabel.numberOfLines = 4
        self.metaLabel.font = Font.regular(13.0)
        self.metaLabel.numberOfLines = 2
        self.reportButton.setTitle("…", for: .normal)
        self.reportButton.addTarget(self, action: #selector(self.reportPressed), for: .touchUpInside)
        self.linkCard.isUserInteractionEnabled = false
        self.contentView.addSubview(self.titleLabel)
        self.contentView.addSubview(self.bodyLabel)
        self.contentView.addSubview(self.metaLabel)
        self.contentView.addSubview(self.linkCard)
        self.contentView.addSubview(self.reportButton)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(summary: TellomiDiscoverPostSummary, preview: TellomiDiscoverLink.Preview?, primary: UIColor, secondary: UIColor, accent: UIColor, background: UIColor) {
        self.titleLabel.text = summary.title
        self.titleLabel.textColor = primary
        self.bodyLabel.text = summary.body
        self.bodyLabel.textColor = primary
        self.metaLabel.text = summary.meta
        self.metaLabel.textColor = secondary
        self.reportButton.setTitleColor(secondary, for: .normal)
        self.linkCard.apply(primary: primary, secondary: secondary, accent: accent, background: background)
        if let preview {
            self.linkCard.show(preview, opens: false)
        } else {
            self.linkCard.hide()
        }
        self.setNeedsLayout()
    }

    @objc private func reportPressed() {
        self.onReport?()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let side: CGFloat = 16.0
        let buttonWidth: CGFloat = 44.0
        let width = max(1, self.contentView.bounds.width - side * 2.0 - buttonWidth)
        let titleSize = self.titleLabel.sizeThatFits(CGSize(width: width, height: 40))
        let bodySize = self.bodyLabel.sizeThatFits(CGSize(width: width, height: 120))
        let metaSize = self.metaLabel.sizeThatFits(CGSize(width: width, height: 40))
        self.titleLabel.frame = CGRect(x: side, y: 10, width: width, height: titleSize.height)
        self.bodyLabel.frame = CGRect(x: side, y: self.titleLabel.frame.maxY + 4, width: width, height: bodySize.height)
        self.metaLabel.frame = CGRect(x: side, y: self.bodyLabel.frame.maxY + 4, width: width, height: self.metaLabel.text?.isEmpty == false ? metaSize.height : 0)
        let metaBottom = self.metaLabel.frame.maxY
        if self.linkCard.isHidden {
            self.linkCard.frame = .zero
        } else {
            let cardHeight = self.linkCard.sizeThatFits(CGSize(width: width, height: 160)).height
            self.linkCard.frame = CGRect(x: side, y: metaBottom + 8, width: width, height: cardHeight)
        }
        self.reportButton.frame = CGRect(x: self.contentView.bounds.width - side - buttonWidth, y: 0, width: buttonWidth, height: self.contentView.bounds.height)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let side: CGFloat = 16.0
        let width = max(1, size.width - side * 2.0 - 44.0)
        let title = self.titleLabel.sizeThatFits(CGSize(width: width, height: 40)).height
        let body = self.bodyLabel.sizeThatFits(CGSize(width: width, height: 120)).height
        let meta = self.metaLabel.text?.isEmpty == false ? self.metaLabel.sizeThatFits(CGSize(width: width, height: 40)).height : 0
        let card = self.linkCard.isHidden ? 0 : self.linkCard.sizeThatFits(CGSize(width: width, height: 160)).height + 8
        return CGSize(width: size.width, height: 10 + title + 4 + body + 4 + meta + card + 10)
    }
}
