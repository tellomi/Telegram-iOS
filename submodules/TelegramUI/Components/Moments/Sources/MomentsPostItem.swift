import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData

public struct MomentsPostHandlers {
    public var open: (MomentsCard) -> Void
    public var author: (MomentsCard) -> Void
    public var like: (MomentsCard) -> Void
    public var comment: (MomentsCard) -> Void
    public var repost: (MomentsCard) -> Void
    public var share: (MomentsCard) -> Void
    public var save: (MomentsCard) -> Void
    public var more: (MomentsCard, UIView) -> Void
    public var follow: (MomentsCard) -> Void
    public var undo: (String) -> Void
    public var fullText: (MomentsCard) -> Void
    public var topic: (String) -> Void
    public var link: (String) -> Void

    public init(open: @escaping (MomentsCard) -> Void, author: @escaping (MomentsCard) -> Void, like: @escaping (MomentsCard) -> Void, comment: @escaping (MomentsCard) -> Void, repost: @escaping (MomentsCard) -> Void, share: @escaping (MomentsCard) -> Void, save: @escaping (MomentsCard) -> Void, more: @escaping (MomentsCard, UIView) -> Void, follow: @escaping (MomentsCard) -> Void, undo: @escaping (String) -> Void, fullText: @escaping (MomentsCard) -> Void, topic: @escaping (String) -> Void, link: @escaping (String) -> Void) {
        self.open = open
        self.author = author
        self.like = like
        self.comment = comment
        self.repost = repost
        self.share = share
        self.save = save
        self.more = more
        self.follow = follow
        self.undo = undo
        self.fullText = fullText
        self.topic = topic
        self.link = link
    }
}

final class MomentsPostItem: ListViewItem {
    let card: MomentsCard
    let strings: PresentationStrings
    let theme: PresentationTheme
    let fontSize: CGFloat
    let showFollow: Bool
    let expanded: Bool
    let hidden: Bool
    let albumIndex: Int
    let playing: Bool
    let handlers: MomentsPostHandlers
    let neighborDescriptor: AnyEquatable = .noNeighborInfluence

    init(card: MomentsCard, strings: PresentationStrings, theme: PresentationTheme, fontSize: CGFloat, showFollow: Bool, expanded: Bool, hidden: Bool, albumIndex: Int, playing: Bool, handlers: MomentsPostHandlers) {
        self.card = card
        self.strings = strings
        self.theme = theme
        self.fontSize = fontSize
        self.showFollow = showFollow
        self.expanded = expanded
        self.hidden = hidden
        self.albumIndex = albumIndex
        self.playing = playing
        self.handlers = handlers
    }

    func nodeConfiguredForParams(async: @escaping (@escaping () -> Void) -> Void, params: ListViewItemLayoutParams, synchronousLoads: Bool, neighbors: ListViewItemNeighbors, completion: @escaping (ListViewItemNode, @escaping () -> (Signal<Void, NoError>?, (ListViewItemApply) -> Void)) -> Void) {
        async {
            let node = MomentsPostItemNode()
            let (layout, apply) = node.asyncLayout()(self, params)
            node.contentSize = layout.contentSize
            node.insets = layout.insets
            Queue.mainQueue().async {
                completion(node, {
                    return (nil, { _ in apply() })
                })
            }
        }
    }

    func updateNode(async: @escaping (@escaping () -> Void) -> Void, node: @escaping () -> ListViewItemNode, params: ListViewItemLayoutParams, neighbors: ListViewItemNeighbors, animation: ListViewItemUpdateAnimation, completion: @escaping (ListViewItemNodeLayout, @escaping (ListViewItemApply) -> Void) -> Void) {
        Queue.mainQueue().async {
            guard let node = node() as? MomentsPostItemNode else {
                return
            }
            let (layout, apply) = node.asyncLayout()(self, params)
            completion(layout, { _ in apply() })
        }
    }

    func selected(listView: ListView) {
        if !self.hidden && !self.card.isUnavailable {
            self.handlers.open(self.card)
        }
    }
}

private let momentsAvatar: CGFloat = 36.0
private let momentsInset: CGFloat = 16.0

final class MomentsPostItemNode: ListViewItemNode {
    private let name = UILabel()
    private let meta = UILabel()
    private let body = UILabel()
    private let full = UIButton(type: .system)
    private let quote = UILabel()
    private let place = UILabel()
    private let actions = UIStackView()
    private let like = UIButton(type: .system)
    private let comment = UIButton(type: .system)
    private let repost = UIButton(type: .system)
    private let share = UIButton(type: .system)
    private let save = UIButton(type: .system)
    private let more = UIButton(type: .system)
    private let follow = UIButton(type: .system)
    private let album = UIScrollView()
    private let separator = UIView()
    private var item: MomentsPostItem?
    private var albumIndex = 0

    override init() {
        super.init(layerBacked: false)
        self.name.font = Font.semibold(15)
        self.meta.font = Font.regular(13)
        self.body.numberOfLines = 0
        self.quote.numberOfLines = 3
        self.place.font = Font.regular(13)
        self.actions.axis = .horizontal
        self.actions.distribution = .fillEqually
        for button in [self.like, self.comment, self.repost, self.share, self.save] {
            button.titleLabel?.font = Font.regular(13)
            self.actions.addArrangedSubview(button)
        }
        self.album.isPagingEnabled = true
        self.album.showsHorizontalScrollIndicator = false
        self.album.layer.cornerRadius = 12
        self.album.clipsToBounds = true
        self.view.addSubview(self.name)
        self.view.addSubview(self.meta)
        self.view.addSubview(self.follow)
        self.view.addSubview(self.more)
        self.view.addSubview(self.body)
        self.view.addSubview(self.full)
        self.view.addSubview(self.album)
        self.view.addSubview(self.quote)
        self.view.addSubview(self.place)
        self.view.addSubview(self.actions)
        self.view.addSubview(self.separator)
        self.like.addTarget(self, action: #selector(self.likePressed), for: .touchUpInside)
        self.comment.addTarget(self, action: #selector(self.commentPressed), for: .touchUpInside)
        self.repost.addTarget(self, action: #selector(self.repostPressed), for: .touchUpInside)
        self.share.addTarget(self, action: #selector(self.sharePressed), for: .touchUpInside)
        self.save.addTarget(self, action: #selector(self.savePressed), for: .touchUpInside)
        self.more.addTarget(self, action: #selector(self.morePressed), for: .touchUpInside)
        self.follow.addTarget(self, action: #selector(self.followPressed), for: .touchUpInside)
        self.full.addTarget(self, action: #selector(self.fullPressed), for: .touchUpInside)
        let nameTap = UITapGestureRecognizer(target: self, action: #selector(self.authorPressed))
        self.name.addGestureRecognizer(nameTap)
        self.name.isUserInteractionEnabled = true
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(self.likePressed))
        doubleTap.numberOfTapsRequired = 2
        self.album.addGestureRecognizer(doubleTap)
    }

    func asyncLayout() -> (MomentsPostItem, ListViewItemLayoutParams) -> (ListViewItemNodeLayout, () -> Void) {
        return { [weak self] item, params in
            let width = params.width
            let contentWidth = min(width, MomentsLimits.standard.maxContentWidth)
            let side = floor((width - contentWidth) / 2.0)
            let textWidth = contentWidth - momentsInset * 2.0 - momentsAvatar - 10.0
            let font = Font.regular(item.fontSize)
            let text = item.card.isUnavailable ? momentsText(item.strings, .unavailable) : item.card.text
            let fullHeight = (text as NSString).boundingRect(with: CGSize(width: textWidth, height: 10000), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font], context: nil).height
            let collapsed = !item.expanded && momentsTextExceedsLineLimit(fullHeight: fullHeight, lineHeight: font.lineHeight, limit: MomentsLimits.standard.collapsedLineCount)
            let bodyHeight = collapsed ? font.lineHeight * CGFloat(MomentsLimits.standard.collapsedLineCount) : fullHeight
            var height: CGFloat = 12 + 20 + 4 + 16
            if item.hidden {
                height = 64
            } else {
                height += bodyHeight + 8
                if collapsed { height += 22 }
                let slides = item.card.images.count + item.card.videos.count
                if slides > 0 { height += 220 }
                if item.card.voice != nil { height += 36 }
                if item.card.poll != nil { height += 28 + CGFloat(item.card.poll?.options.count ?? 0) * 28 }
                if item.card.quote != nil { height += 64 }
                if item.card.visibleLinkPreview != nil { height += 56 }
                if item.card.location?.cityName != nil || item.card.location?.place != nil { height += 22 }
                height += 40
            }
            let layout = ListViewItemNodeLayout(contentSize: CGSize(width: width, height: ceil(height)), insets: UIEdgeInsets())
            return (layout, {
                self?.apply(item, textWidth: textWidth, side: side, collapsed: collapsed, bodyHeight: bodyHeight)
            })
        }
    }

    private func apply(_ item: MomentsPostItem, textWidth: CGFloat, side: CGFloat, collapsed: Bool, bodyHeight: CGFloat) {
        self.item = item
        let theme = item.theme
        let strings = item.strings
        self.backgroundColor = theme.list.plainBackgroundColor
        self.name.textColor = theme.list.itemPrimaryTextColor
        self.meta.textColor = theme.list.itemSecondaryTextColor
        self.body.textColor = theme.list.itemPrimaryTextColor
        self.quote.textColor = theme.list.itemSecondaryTextColor
        self.place.textColor = theme.list.itemSecondaryTextColor
        self.separator.backgroundColor = theme.list.itemPlainSeparatorColor
        self.body.font = Font.regular(item.fontSize)
        let x = side + momentsInset + momentsAvatar + 10
        let width = textWidth
        if item.hidden {
            self.body.text = "\(momentsText(strings, .hidden)) · \(momentsText(strings, .undo))"
            self.body.frame = CGRect(x: side + momentsInset, y: 20, width: width + momentsAvatar, height: 24)
            self.setChrome(hidden: true)
            return
        }
        self.setChrome(hidden: false)
        if item.card.isUnavailable {
            self.name.text = momentsText(strings, .unavailable)
            self.meta.text = ""
            self.body.text = ""
            self.follow.isHidden = true
        } else {
            self.name.text = item.card.author?.displayName ?? ""
            var meta = momentsRelativeTime(item.card.createdAt)
            if item.card.showsEditedMark {
                meta += " · \(momentsText(strings, .edited))"
            }
            if let audience = item.card.audience, audience.kind != .everyone {
                meta += " · \(momentsAudienceTitle(strings, audience.kind))"
            }
            if let reposted = item.card.repostedBy?.displayName {
                meta = "\(reposted) \(momentsText(strings, .repostHeader)) · " + meta
            }
            self.meta.text = meta
            self.body.text = item.card.text
            self.follow.isHidden = !item.showFollow
            self.follow.setTitle(item.card.author?.followed == true ? momentsText(strings, .followingState) : momentsText(strings, .follow), for: .normal)
        }
        self.name.frame = CGRect(x: x, y: 10, width: width - 88, height: 18)
        self.meta.frame = CGRect(x: x, y: 28, width: width - 88, height: 16)
        self.more.frame = CGRect(x: x + width - 32, y: 8, width: 32, height: 32)
        self.follow.frame = CGRect(x: x + width - 88, y: 8, width: 52, height: 28)
        self.body.frame = CGRect(x: x, y: 50, width: width, height: bodyHeight)
        self.full.isHidden = !collapsed
        self.full.setTitle(momentsText(strings, .fullText), for: .normal)
        self.full.frame = CGRect(x: x, y: self.body.frame.maxY, width: 80, height: 20)
        var cursor = (collapsed ? self.full.frame.maxY : self.body.frame.maxY) + 8
        self.layoutAlbum(item, x: x, y: cursor, width: width)
        if item.card.images.isEmpty && item.card.videos.isEmpty {
            self.album.isHidden = true
        } else {
            self.album.isHidden = false
            cursor += 220
        }
        if let quote = item.card.quote {
            self.quote.isHidden = false
            if quote.unavailable {
                self.quote.text = momentsText(strings, .unavailable)
            } else {
                self.quote.text = [quote.authorName, quote.text].compactMap { $0 }.joined(separator: "\n")
            }
            self.quote.frame = CGRect(x: x, y: cursor, width: width, height: 56)
            cursor += 64
        } else {
            self.quote.isHidden = true
        }
        if let band = item.card.visibleDistanceBand, let place = item.card.location?.place?.name {
            self.place.isHidden = false
            self.place.text = "\(place) · \(band)"
        } else if let city = item.card.location?.cityName ?? item.card.location?.city {
            self.place.isHidden = false
            self.place.text = city
        } else {
            self.place.isHidden = true
        }
        if !self.place.isHidden {
            self.place.frame = CGRect(x: x, y: cursor, width: width, height: 18)
            cursor += 22
        }
        self.actions.frame = CGRect(x: x, y: cursor, width: width, height: 32)
        self.like.setTitle("\(momentsText(strings, .like)) \(item.card.counts.likes)", for: .normal)
        self.comment.setTitle("\(momentsText(strings, .comment)) \(item.card.counts.comments)", for: .normal)
        self.repost.setTitle(momentsText(strings, .repost), for: .normal)
        self.share.setTitle(momentsText(strings, .share), for: .normal)
        self.save.setTitle(item.card.viewer.saved ? momentsText(strings, .saved) : momentsText(strings, .save), for: .normal)
        self.like.accessibilityLabel = "\(momentsText(strings, .like)), \(item.card.counts.likes)"
        self.comment.accessibilityLabel = "\(momentsText(strings, .comment)), \(item.card.counts.comments)"
        self.repost.accessibilityLabel = momentsText(strings, .repost)
        self.share.accessibilityLabel = momentsText(strings, .share)
        self.save.accessibilityLabel = item.card.viewer.saved ? momentsText(strings, .saved) : momentsText(strings, .save)
        self.more.accessibilityLabel = momentsText(strings, .more)
        let slides = item.card.images.count + item.card.videos.count
        if slides > 0 {
            self.album.accessibilityLabel = "\(min(self.albumIndex + 1, slides))/\(slides)"
        }
        self.separator.frame = CGRect(x: side + momentsInset, y: self.bounds.height - UIScreenPixel, width: width + momentsAvatar + 10, height: UIScreenPixel)
        let _ = item.playing
    }

    private func setChrome(hidden: Bool) {
        self.name.isHidden = hidden
        self.meta.isHidden = hidden
        self.more.isHidden = hidden
        self.follow.isHidden = hidden
        self.full.isHidden = hidden
        self.album.isHidden = hidden
        self.quote.isHidden = hidden
        self.place.isHidden = hidden
        self.actions.isHidden = hidden
    }

    private func layoutAlbum(_ item: MomentsPostItem, x: CGFloat, y: CGFloat, width: CGFloat) {
        let slides = item.card.images + item.card.videos
        self.album.frame = CGRect(x: x, y: y, width: width, height: slides.isEmpty ? 0 : 212)
        self.album.contentSize = CGSize(width: width * CGFloat(max(slides.count, 1)), height: 212)
        self.album.subviews.forEach { $0.removeFromSuperview() }
        for (index, media) in slides.enumerated() {
            let label = UILabel(frame: CGRect(x: width * CGFloat(index), y: 0, width: width, height: 212))
            label.textAlignment = .center
            label.textColor = item.theme.list.itemSecondaryTextColor
            label.backgroundColor = item.theme.list.itemHighlightedBackgroundColor
            if media.type == .video {
                let seconds = media.durationMs / 1000
                label.text = item.playing && index == item.albumIndex ? "▶ \(seconds)s" : "\(seconds)s"
                label.accessibilityLabel = "\(seconds)s"
            } else {
                label.text = "\(index + 1)/\(slides.count)"
                label.accessibilityLabel = "\(index + 1)/\(slides.count)"
            }
            self.album.addSubview(label)
        }
        let page = min(item.albumIndex, max(slides.count - 1, 0))
        self.albumIndex = page
        self.album.setContentOffset(CGPoint(x: width * CGFloat(page), y: 0), animated: false)
    }

    @objc private func likePressed() { if let item = self.item { item.handlers.like(item.card) } }
    @objc private func commentPressed() { if let item = self.item { item.handlers.comment(item.card) } }
    @objc private func repostPressed() { if let item = self.item { item.handlers.repost(item.card) } }
    @objc private func sharePressed() { if let item = self.item { item.handlers.share(item.card) } }
    @objc private func savePressed() { if let item = self.item { item.handlers.save(item.card) } }
    @objc private func morePressed() { if let item = self.item { item.handlers.more(item.card, self.more) } }
    @objc private func followPressed() { if let item = self.item { item.handlers.follow(item.card) } }
    @objc private func fullPressed() { if let item = self.item { item.handlers.fullText(item.card) } }
    @objc private func authorPressed() { if let item = self.item { item.handlers.author(item.card) } }

    func albumContains(_ point: CGPoint) -> Bool {
        return !self.album.isHidden && self.album.frame.contains(self.view.convert(point, from: nil))
    }
}

func momentsAudienceTitle(_ strings: PresentationStrings, _ kind: MomentsAudienceKind) -> String {
    switch kind {
    case .everyone:
        return momentsText(strings, .audienceEveryone)
    case .contacts:
        return momentsText(strings, .audienceContacts)
    case .closeFriends:
        return momentsText(strings, .audienceCloseFriends)
    case .selected:
        return momentsText(strings, .audienceSelected)
    case .mutualFollowers:
        return momentsText(strings, .audienceMutual)
    }
}

func momentsRelativeTime(_ timestamp: Int64) -> String {
    guard timestamp > 0 else {
        return ""
    }
    let delta = max(0, Int(Date().timeIntervalSince1970) - Int(timestamp))
    if delta < 60 { return "\(delta)s" }
    if delta < 3600 { return "\(delta / 60)m" }
    if delta < 86400 { return "\(delta / 3600)h" }
    return "\(delta / 86400)d"
}

final class MomentsStatusItem: ListViewItem {
    let text: String
    let theme: PresentationTheme
    let action: () -> Void
    let neighborDescriptor: AnyEquatable = .noNeighborInfluence

    init(text: String, theme: PresentationTheme, action: @escaping () -> Void) {
        self.text = text
        self.theme = theme
        self.action = action
    }

    func nodeConfiguredForParams(async: @escaping (@escaping () -> Void) -> Void, params: ListViewItemLayoutParams, synchronousLoads: Bool, neighbors: ListViewItemNeighbors, completion: @escaping (ListViewItemNode, @escaping () -> (Signal<Void, NoError>?, (ListViewItemApply) -> Void)) -> Void) {
        async {
            let node = MomentsStatusItemNode()
            let layout = ListViewItemNodeLayout(contentSize: CGSize(width: params.width, height: 160), insets: UIEdgeInsets())
            node.contentSize = layout.contentSize
            node.insets = layout.insets
            Queue.mainQueue().async {
                completion(node, { return (nil, { _ in node.apply(self) }) })
            }
        }
    }

    func updateNode(async: @escaping (@escaping () -> Void) -> Void, node: @escaping () -> ListViewItemNode, params: ListViewItemLayoutParams, neighbors: ListViewItemNeighbors, animation: ListViewItemUpdateAnimation, completion: @escaping (ListViewItemNodeLayout, @escaping (ListViewItemApply) -> Void) -> Void) {
        Queue.mainQueue().async {
            guard let node = node() as? MomentsStatusItemNode else { return }
            let layout = ListViewItemNodeLayout(contentSize: CGSize(width: params.width, height: 160), insets: UIEdgeInsets())
            completion(layout, { _ in node.apply(self) })
        }
    }
}

private final class MomentsStatusItemNode: ListViewItemNode {
    private let label = UILabel()
    private var action: (() -> Void)?

    override init() {
        super.init(layerBacked: false)
        self.label.numberOfLines = 0
        self.label.textAlignment = .center
        self.label.font = Font.regular(16)
        self.label.isUserInteractionEnabled = true
        self.label.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.pressed)))
        self.view.addSubview(self.label)
    }

    func apply(_ item: MomentsStatusItem) {
        self.backgroundColor = item.theme.list.plainBackgroundColor
        self.label.textColor = item.theme.list.itemSecondaryTextColor
        self.label.text = item.text
        self.label.frame = self.bounds.insetBy(dx: 24, dy: 24)
        self.action = item.action
    }

    @objc private func pressed() { self.action?() }
}
