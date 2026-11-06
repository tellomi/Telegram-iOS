import Foundation

/// Vertical stack for a Discover post detail. The host puts this stack in a scroll view.
/// Ten images stay reachable when the stack is taller than the viewport. Text, link, poll,
/// and comments keep their order and do not share a frame with an image.
public enum TellomiDiscoverDetailPiece: Equatable {
    case text(Double)
    case image(Double)
    case link(Double)
    case poll(Double)
    case comment(Double)
}

public struct TellomiDiscoverDetailFrame: Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public var maxY: Double {
        return self.y + self.height
    }
}

public struct TellomiDiscoverDetailLayout: Equatable {
    public var frames: [TellomiDiscoverDetailFrame]
    public var contentHeight: Double
    public var viewportHeight: Double

    public init(frames: [TellomiDiscoverDetailFrame], contentHeight: Double, viewportHeight: Double) {
        self.frames = frames
        self.contentHeight = contentHeight
        self.viewportHeight = viewportHeight
    }

    /// A piece can be brought fully into view when it is no taller than the viewport.
    public func reachable(_ frame: TellomiDiscoverDetailFrame) -> Bool {
        guard frame.height > 0, frame.height <= self.viewportHeight, frame.y >= 0, frame.maxY <= self.contentHeight else {
            return false
        }
        let maxOffset = max(0, self.contentHeight - self.viewportHeight)
        let offset = min(max(0, frame.y), maxOffset)
        return frame.y < offset + self.viewportHeight && frame.maxY > offset
    }
}

public func tellomiDiscoverDetailLayout(contentWidth: Double, viewportHeight: Double, pieces: [TellomiDiscoverDetailPiece], inset: Double = 16, bottom: Double = 16) -> TellomiDiscoverDetailLayout {
    let width = max(1, contentWidth)
    let inner = max(1, width - inset * 2)
    let imageWidth = min(inner, 280)
    var frames: [TellomiDiscoverDetailFrame] = []
    var cursor = inset
    for piece in pieces {
        let height: Double
        let pieceWidth: Double
        let gap: Double
        switch piece {
        case let .text(value):
            height = max(0, value)
            pieceWidth = inner
            gap = 12
        case let .image(value):
            height = max(0, value)
            pieceWidth = imageWidth
            gap = 8
        case let .link(value):
            height = max(0, value)
            pieceWidth = inner
            gap = 12
        case let .poll(value):
            height = max(0, value)
            pieceWidth = inner
            gap = 8
        case let .comment(value):
            height = max(0, value)
            pieceWidth = inner
            gap = 8
        }
        frames.append(TellomiDiscoverDetailFrame(x: inset, y: cursor, width: pieceWidth, height: height))
        cursor += height + gap
    }
    let content = cursor + bottom
    return TellomiDiscoverDetailLayout(frames: frames, contentHeight: content, viewportHeight: max(1, viewportHeight))
}
