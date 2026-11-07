import Foundation
import CoreGraphics

public enum ReactionIconKind: Equatable {
    case builtin
    case custom
    case stars
}

public struct ReactionIconMetrics: Equatable {
    public var size: CGSize
    public var origin: CGPoint
    public var clipsToBounds: Bool

    public init(size: CGSize, origin: CGPoint, clipsToBounds: Bool) {
        self.size = size
        self.origin = origin
        self.clipsToBounds = clipsToBounds
    }
}

/// The pill reserves a 20×20 slot. Telegram's builtin reaction files are padded,
/// so a 2× layer still looks about that size. A full-bleed file at 2× leaves the
/// pill and the bubble. Builtin icons are drawn in the slot and clipped. Custom
/// emoji stays 1.25× and clipped. Stars stays 1.25×. The 24pt reactor avatar is
/// not this layer.
public func reactionIconMetrics(slot: CGSize, kind: ReactionIconKind) -> ReactionIconMetrics {
    let scale: CGFloat
    let clipsToBounds: Bool
    switch kind {
    case .builtin:
        scale = 1.0
        clipsToBounds = true
    case .custom:
        scale = 1.25
        clipsToBounds = true
    case .stars:
        scale = 1.25
        clipsToBounds = false
    }
    let size = CGSize(width: floor(slot.width * scale), height: floor(slot.height * scale))
    return ReactionIconMetrics(
        size: size,
        origin: CGPoint(x: floor((slot.width - size.width) / 2.0), y: floor((slot.height - size.height) / 2.0)),
        clipsToBounds: clipsToBounds
    )
}
