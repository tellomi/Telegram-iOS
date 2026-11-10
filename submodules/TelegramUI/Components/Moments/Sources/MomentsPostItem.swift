import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import AccountContext
import TelegramUniversalVideoContent

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
    public var likers: (MomentsCard) -> Void
    public var voters: (MomentsCard) -> Void

    public init(open: @escaping (MomentsCard) -> Void, author: @escaping (MomentsCard) -> Void, like: @escaping (MomentsCard) -> Void, comment: @escaping (MomentsCard) -> Void, repost: @escaping (MomentsCard) -> Void, share: @escaping (MomentsCard) -> Void, save: @escaping (MomentsCard) -> Void, more: @escaping (MomentsCard, UIView) -> Void, follow: @escaping (MomentsCard) -> Void, undo: @escaping (String) -> Void, fullText: @escaping (MomentsCard) -> Void, topic: @escaping (String) -> Void, link: @escaping (String) -> Void, likers: @escaping (MomentsCard) -> Void = { _ in }, voters: @escaping (MomentsCard) -> Void = { _ in }) {
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
        self.likers = likers
        self.voters = voters
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
    let context: AccountContext?
    let handlers: MomentsPostHandlers
    let neighborDescriptor: AnyEquatable = .noNeighborInfluence

    init(card: MomentsCard, strings: PresentationStrings, theme: PresentationTheme, fontSize: CGFloat, showFollow: Bool, expanded: Bool, hidden: Bool, albumIndex: Int, playing: Bool, context: AccountContext? = nil, handlers: MomentsPostHandlers) {
        self.card = card
        self.strings = strings
        self.theme = theme
        self.fontSize = fontSize
        self.showFollow = showFollow
        self.expanded = expanded
        self.hidden = hidden
        self.albumIndex = albumIndex
        self.playing = playing
        self.context = context
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

private let momentsAvatar: CGFloat = 40.0
private let momentsInset: CGFloat = 12.0

final class MomentsPostItemNode: ListViewItemNode {
    private let avatar = UIImageView()
    private let avatarLetter = UILabel()
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
    private var videoNode: UniversalVideoNode?
    private var videoURL: String?
    private let pollHost = UIView()

    init() {
        super.init(layerBacked: false)
        self.avatar.layer.cornerRadius = 20
        self.follow.layer.cornerRadius = 8
        self.follow.clipsToBounds = true
        self.follow.titleLabel?.font = Font.semibold(12)
        self.avatar.clipsToBounds = true
        self.avatar.contentMode = .scaleAspectFill
        self.avatarLetter.font = Font.semibold(15)
        self.avatarLetter.textAlignment = .center
        self.avatar.addSubview(self.avatarLetter)
        self.name.font = Font.semibold(15)
        self.meta.font = Font.regular(13)
        self.body.numberOfLines = 0
        self.quote.numberOfLines = 3
        self.quote.layer.cornerRadius = 12
        self.quote.clipsToBounds = true
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
        self.view.addSubview(self.avatar)
        self.view.addSubview(self.name)
        self.view.addSubview(self.meta)
        self.view.addSubview(self.follow)
        self.view.addSubview(self.more)
        self.view.addSubview(self.body)
        self.view.addSubview(self.full)
        self.view.addSubview(self.album)
        self.view.addSubview(self.pollHost)
        let likers = UILongPressGestureRecognizer(target: self, action: #selector(self.likersPressed(_:)))
        self.like.addGestureRecognizer(likers)
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
            var height: CGFloat = 12 + 22 + 8
            if item.hidden {
                height = 64
            } else {
                height += bodyHeight + 8
                if collapsed { height += 22 }
                let slides = item.card.images.count + item.card.videos.count
                if slides > 0 { height += slides > 1 ? 200 : 220 }
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
            self.videoNode?.canAttachContent = false
            self.videoNode?.removeFromSupernode()
            self.videoNode = nil
            self.videoURL = nil
            return
        }
        self.setChrome(hidden: false)
        self.avatar.frame = CGRect(x: side + momentsInset, y: 10, width: momentsAvatar, height: momentsAvatar)
        self.avatarLetter.frame = self.avatar.bounds
        self.avatar.backgroundColor = theme.list.itemHighlightedBackgroundColor
        self.avatarLetter.textColor = theme.list.itemPrimaryTextColor
        let displayName = item.card.author?.displayName ?? ""
        self.avatarLetter.text = displayName.isEmpty ? "" : String(displayName.prefix(1))
        if let avatarURL = item.card.author?.avatarKey, avatarURL.hasPrefix("https://") {
            self.avatarLetter.isHidden = true
            momentsLoadImage(avatarURL, into: self.avatar)
        } else {
            self.avatar.image = nil
            self.avatarLetter.isHidden = displayName.isEmpty
        }
        let secondary = theme.list.itemSecondaryTextColor
        let likedColor = UIColor(rgb: 0xFF3B30)
        for button in [self.like, self.comment, self.repost, self.share, self.save, self.more] {
            button.setTitleColor(secondary, for: .normal)
            button.tintColor = secondary
        }
        self.follow.setTitleColor(.white, for: .normal)
        self.follow.backgroundColor = theme.list.itemAccentColor
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
            let showBadge = item.showFollow && item.card.author?.followed != true
            self.follow.isHidden = !showBadge
            self.follow.setTitle("+", for: .normal)
            self.follow.accessibilityLabel = momentsText(strings, .follow)
        }
        let nameWidth = min((self.name.text as NSString?)?.size(withAttributes: [.font: self.name.font as Any]).width ?? 80, width * 0.55)
        self.name.frame = CGRect(x: x, y: 12, width: nameWidth, height: 20)
        self.meta.frame = CGRect(x: x + nameWidth + 6, y: 14, width: width - nameWidth - 46, height: 18)
        self.more.frame = CGRect(x: x + width - 32, y: 6, width: 32, height: 32)
        self.follow.frame = CGRect(x: self.avatar.frame.maxX - 16, y: self.avatar.frame.maxY - 16, width: 16, height: 16)
        self.body.frame = CGRect(x: x, y: 36, width: width, height: bodyHeight)
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
        self.layoutPoll(item, x: x, y: cursor, width: width)
        if item.card.poll != nil {
            cursor += 28 + CGFloat(item.card.poll?.options.count ?? 0) * 28
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
        let liked = item.card.viewer.liked
        self.like.tintColor = liked ? likedColor : secondary
        self.like.setImage(generateTintedImage(image: UIImage(bundleImageName: liked ? "Stories/InputLikeOn" : "Stories/InputLikeOff"), color: liked ? likedColor : secondary), for: .normal)
        self.like.setTitle(item.card.counts.likes > 0 ? " \(item.card.counts.likes)" : nil, for: .normal)
        self.comment.setImage(generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Reply"), color: secondary), for: .normal)
        self.comment.setTitle(item.card.counts.comments > 0 ? " \(item.card.counts.comments)" : nil, for: .normal)
        self.repost.setImage(generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Forward"), color: secondary), for: .normal)
        self.repost.setTitle(item.card.counts.reposts > 0 ? " \(item.card.counts.reposts)" : nil, for: .normal)
        self.share.setImage(generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Share"), color: secondary), for: .normal)
        self.share.setTitle(nil, for: .normal)
        self.save.isHidden = true
        self.more.setImage(generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/More"), color: secondary), for: .normal)
        self.more.setTitle(nil, for: .normal)
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
        self.avatar.isHidden = hidden
        self.name.isHidden = hidden
        self.meta.isHidden = hidden
        self.more.isHidden = hidden
        self.follow.isHidden = hidden
        self.full.isHidden = hidden
        self.album.isHidden = hidden
        self.pollHost.isHidden = hidden
        self.quote.isHidden = hidden
        self.place.isHidden = hidden
        self.actions.isHidden = hidden
    }

    private func layoutAlbum(_ item: MomentsPostItem, x: CGFloat, y: CGFloat, width: CGFloat) {
        let slides = item.card.media.filter { momentsPresentsAsImage($0.type) || momentsPresentsAsVideo($0.type) }
        let slideWidth = slides.count > 1 ? floor(width * 0.78) : width
        self.album.frame = CGRect(x: x, y: y, width: width, height: slides.isEmpty ? 0 : (slides.count > 1 ? 188 : 212))
        self.album.contentSize = CGSize(width: slideWidth * CGFloat(max(slides.count, 1)) + (slides.count > 1 ? 8 : 0), height: self.album.frame.height)
        self.album.subviews.forEach { $0.removeFromSuperview() }
        var playingURL: String?
        let albumHeight = self.album.frame.height
        for (index, media) in slides.enumerated() {
            let frame = CGRect(x: slideWidth * CGFloat(index), y: 0, width: slideWidth - (slides.count > 1 ? 8 : 0), height: albumHeight)
            let label = UILabel(frame: frame)
            label.layer.cornerRadius = 12
            label.clipsToBounds = true
            label.textAlignment = .center
            label.textColor = item.theme.list.itemSecondaryTextColor
            label.backgroundColor = item.theme.list.itemHighlightedBackgroundColor
            if momentsPresentsAsVideo(media.type) {
                let seconds = media.durationMs / 1000
                label.text = "\(seconds)s"
                label.accessibilityLabel = "\(seconds)s"
                if item.playing && index == item.albumIndex {
                    playingURL = media.remoteURL
                }
                label.accessibilityIdentifier = media.type.rawValue
            } else if let remoteURL = media.remoteURL {
                let imageView = UIImageView(frame: frame)
                imageView.layer.cornerRadius = 12
                imageView.contentMode = .scaleAspectFill
                imageView.clipsToBounds = true
                imageView.backgroundColor = item.theme.list.itemHighlightedBackgroundColor
                imageView.accessibilityLabel = "\(index + 1)/\(slides.count)"
                self.album.addSubview(imageView)
                momentsLoadImage(remoteURL, into: imageView)
                continue
            } else {
                label.text = "\(index + 1)/\(slides.count)"
                label.accessibilityLabel = "\(index + 1)/\(slides.count)"
            }
            self.album.addSubview(label)
        }
        let page = min(item.albumIndex, max(slides.count - 1, 0))
        self.albumIndex = page
        self.album.setContentOffset(CGPoint(x: slideWidth * CGFloat(page), y: 0), animated: false)
        let playingType = slides.indices.contains(page) ? slides[page].type : .video
        self.attachVideo(url: playingURL, type: playingType, item: item, frame: CGRect(x: x + slideWidth * CGFloat(page), y: y, width: slideWidth - (slides.count > 1 ? 8 : 0), height: albumHeight))
    }

    private func layoutPoll(_ item: MomentsPostItem, x: CGFloat, y: CGFloat, width: CGFloat) {
        self.pollHost.subviews.forEach { $0.removeFromSuperview() }
        guard let poll = item.card.poll else {
            self.pollHost.isHidden = true
            return
        }
        self.pollHost.isHidden = false
        self.pollHost.frame = CGRect(x: x, y: y, width: width, height: 28 + CGFloat(poll.options.count) * 28)
        for (index, option) in poll.options.enumerated() {
            let button = UIButton(type: .system)
            button.frame = CGRect(x: 0, y: 28 + CGFloat(index) * 28, width: width, height: 28)
            button.contentHorizontalAlignment = .left
            button.setTitle("\(option.text)  \(option.count)", for: .normal)
            button.tag = index
            button.addTarget(self, action: #selector(self.pollPressed(_:)), for: .touchUpInside)
            let voters = UILongPressGestureRecognizer(target: self, action: #selector(self.votersPressed(_:)))
            button.addGestureRecognizer(voters)
            self.pollHost.addSubview(button)
        }
    }

    private func attachVideo(url: String?, type: MomentsMediaType, item: MomentsPostItem, frame: CGRect) {
        guard let url, let context = item.context, url.hasPrefix("https://") else {
            self.videoNode?.canAttachContent = false
            self.videoNode?.removeFromSupernode()
            self.videoNode = nil
            self.videoURL = nil
            return
        }
        if self.videoURL == url, let videoNode = self.videoNode {
            videoNode.frame = frame
            videoNode.updateLayout(size: frame.size, transition: .immediate)
            return
        }
        self.videoNode?.canAttachContent = false
        self.videoNode?.removeFromSupernode()
        let node = momentsVideoNode(context: context, url: url, type: type, size: frame.size)
        node.frame = frame
        self.addSubnode(node)
        node.updateLayout(size: frame.size, transition: .immediate)
        node.canAttachContent = true
        self.videoNode = node
        self.videoURL = url
    }

    func autoplayTarget(listView: UIView) -> (String, Int)? {
        guard let item = self.item, !item.hidden, !self.album.isHidden else {
            return nil
        }
        let frame = self.album.convert(self.album.bounds, to: listView)
        let visible = listView.bounds.insetBy(dx: 0, dy: 80)
        guard frame.intersects(visible) else {
            return nil
        }
        let slides = item.card.media.filter { momentsPresentsAsImage($0.type) || momentsPresentsAsVideo($0.type) }
        guard self.albumIndex < slides.count, momentsPresentsAsVideo(slides[self.albumIndex].type), slides[self.albumIndex].remoteURL != nil else {
            return nil
        }
        return (item.card.id, self.albumIndex)
    }

    @objc private func likePressed() { if let item = self.item { item.handlers.like(item.card) } }
    @objc private func likersPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, let item = self.item else { return }
        item.handlers.likers(item.card)
    }
    @objc private func pollPressed(_ button: UIButton) {
        guard let item = self.item, let poll = item.card.poll, poll.options.indices.contains(button.tag) else { return }
        let _ = item.context?.engine.moments.vote(postId: item.card.id, options: [poll.options[button.tag].id]).start()
    }
    @objc private func votersPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, let item = self.item else { return }
        item.handlers.voters(item.card)
    }
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

private func momentsLoadImage(_ urlString: String, into imageView: UIImageView) {
    guard let url = URL(string: urlString) else { return }
    let task = URLSession.shared.dataTask(with: url) { data, _, _ in
        guard let data, let image = UIImage(data: data) else { return }
        Queue.mainQueue().async {
            imageView.image = image
        }
    }
    task.resume()
}

private func momentsVideoNode(context: AccountContext, url: String, type: MomentsMediaType, size: CGSize) -> UniversalVideoNode {
    let width = Int32(max(size.width, 1))
    let height = Int32(max(size.height, 1))
    let file = TelegramMediaFile(
        fileId: EngineMedia.Id(namespace: Namespaces.Media.LocalFile, id: Int64(url.hashValue)),
        partialReference: nil,
        resource: HttpReferenceMediaResource(url: url, size: nil),
        previewRepresentations: [],
        videoThumbnails: [],
        immediateThumbnailData: nil,
        mimeType: momentsPlaybackMimeType(type),
        size: nil,
        attributes: [
            .FileName(fileName: momentsPlaybackFileName(type)),
            .Video(duration: 0, size: PixelDimensions(width: width, height: height), flags: TelegramMediaVideoFlags(), preloadSize: nil, coverTime: nil, videoCodec: nil)
        ],
        alternativeRepresentations: []
    )
    let content = NativeVideoContent(
        id: .contextResult(Int64(url.hashValue), url),
        userLocation: .other,
        fileReference: .standalone(media: file),
        streamVideo: .conservative,
        loopVideo: true,
        enableSound: false,
        soundMuted: true,
        fetchAutomatically: true,
        storeAfterDownload: nil
    )
    let decoration = ChatBubbleVideoDecoration(corners: ImageCorners(radius: 12), nativeSize: size, contentMode: .aspectFill, backgroundColor: .clear)
    return UniversalVideoNode(
        context: context,
        postbox: context.account.postbox,
        audioSession: context.sharedContext.mediaManager.audioSession,
        manager: context.sharedContext.mediaManager.universalVideoManager,
        decoration: decoration,
        content: content,
        priority: .embedded,
        autoplay: true
    )
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

    init() {
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
