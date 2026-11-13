import Foundation
import UIKit
import Display

/// The direction a tab bar lays its items out in.
public enum TabBarAxis: Equatable {
    case horizontal
    case vertical
}

/// An item's length along the bar in every mode but horizontal regular, and a regular item's size across it.
public let tabBarItemLength: CGFloat = 56.0
/// The gap between the bar's edge and its items, at both ends and on both sides.
public let tabBarInnerInset: CGFloat = 4.0
/// A compact (icon-only) item's size across the bar.
public let tabBarCompactItemThickness: CGFloat = 40.0
/// A horizontal compact bar that would hug its items within this much of its available length takes the
/// whole length instead: a small leftover gap on each side reads as a mistake rather than a design.
private let tabBarCompactFillThreshold: CGFloat = 60.0

public struct TabBarItemsLayout: Equatable {
    /// The bar: its items plus the inner inset on every side.
    public var size: CGSize
    /// Each item's frame in the bar's coordinates, in item order.
    public var itemFrames: [CGRect]

    public init(size: CGSize, itemFrames: [CGRect]) {
        self.size = size
        self.itemFrames = itemFrames
    }
}

/// The item frames and the bar's size, one item per entry of `unboundItemWidths`.
///
/// Horizontal regular items share `availableLength` (the bar's length available along the axis, inner
/// insets included): equal lengths when every item's unconstrained width fits, else lengths weighted by
/// those widths. Every other mode gives each item `tabBarItemLength` and the bar hugs its items, except
/// that a horizontal compact bar hugging them within `tabBarCompactFillThreshold` of `availableLength`
/// (or beyond it) takes `availableLength`, its items sharing it equally. The widths are unused outside
/// horizontal regular, and `availableLength` on the vertical axis.
public func tabBarItemsLayout(axis: TabBarAxis, isCompact: Bool, unboundItemWidths: [CGFloat], availableLength: CGFloat) -> TabBarItemsLayout {
    let count = unboundItemWidths.count
    let thickness = isCompact ? tabBarCompactItemThickness : tabBarItemLength

    let lengths: [CGFloat]
    if axis == .horizontal && !isCompact && count != 0 {
        let availableItemsLength = availableLength - tabBarInnerInset * 2.0
        let equalLength = floorToScreenPixels(availableItemsLength / CGFloat(count))
        if unboundItemWidths.allSatisfy({ $0 <= equalLength }) {
            lengths = Array(repeating: equalLength, count: count)
        } else {
            let weight = availableItemsLength / unboundItemWidths.reduce(0.0, +)
            lengths = unboundItemWidths.map { floorToScreenPixels($0 * weight) }
        }
    } else if axis == .horizontal && isCompact && count != 0 && availableLength - (CGFloat(count) * tabBarItemLength + tabBarInnerInset * 2.0) < tabBarCompactFillThreshold {
        let equalLength = floorToScreenPixels((availableLength - tabBarInnerInset * 2.0) / CGFloat(count))
        lengths = Array(repeating: equalLength, count: count)
    } else {
        lengths = Array(repeating: tabBarItemLength, count: count)
    }

    var itemFrames: [CGRect] = []
    var position = tabBarInnerInset
    for length in lengths {
        switch axis {
        case .horizontal:
            itemFrames.append(CGRect(x: position, y: tabBarInnerInset, width: length, height: thickness))
        case .vertical:
            itemFrames.append(CGRect(x: tabBarInnerInset, y: position, width: thickness, height: length))
        }
        position += length
    }
    let barLength = position + tabBarInnerInset
    let barThickness = thickness + tabBarInnerInset * 2.0
    switch axis {
    case .horizontal:
        return TabBarItemsLayout(size: CGSize(width: barLength, height: barThickness), itemFrames: itemFrames)
    case .vertical:
        return TabBarItemsLayout(size: CGSize(width: barThickness, height: barLength), itemFrames: itemFrames)
    }
}

/// The lens's selection rect in the bar's coordinates: the dragged position, else the selected item grown
/// by the inner inset along the axis, else the first item's place; always the bar's full thickness across
/// it, and clamped to the bar along it. A horizontal item narrower than its height is widened to 1.2 times
/// its height first.
public func tabBarLensSelectionFrame(axis: TabBarAxis, barSize: CGSize, selectedItemFrame: CGRect?, drag: (origin: CGFloat, itemLength: CGFloat)?) -> CGRect {
    var origin: CGFloat
    let length: CGFloat
    if let drag {
        origin = drag.origin
        length = drag.itemLength + tabBarInnerInset * 2.0
    } else if var itemFrame = selectedItemFrame {
        switch axis {
        case .horizontal:
            if itemFrame.width < itemFrame.height {
                itemFrame = itemFrame.insetBy(dx: floor((itemFrame.height * 1.2 - itemFrame.width) * -0.5), dy: 0.0)
            }
            origin = itemFrame.minX - tabBarInnerInset
            length = itemFrame.width + tabBarInnerInset * 2.0
        case .vertical:
            origin = itemFrame.minY - tabBarInnerInset
            length = itemFrame.height + tabBarInnerInset * 2.0
        }
    } else {
        origin = 0.0
        length = tabBarItemLength
    }

    switch axis {
    case .horizontal:
        origin = max(0.0, min(origin, barSize.width - length))
        return CGRect(x: origin, y: 0.0, width: length, height: barSize.height)
    case .vertical:
        origin = max(0.0, min(origin, barSize.height - length))
        return CGRect(x: 0.0, y: origin, width: barSize.width, height: length)
    }
}

/// Upstream `TabBarNode` draws Contacts/Chats/Settings from a 30pt PDF in a 45pt block
/// whose top is 3pt below the bar. A larger bitmap is fitted into that 30pt box.
public let tabBarUpstreamIconPointSize: CGFloat = 30.0
public let tabBarUpstreamItemContentOriginY: CGFloat = 3.0
public let tabBarUpstreamItemContentHeight: CGFloat = 45.0
public let tabBarUpstreamTitlePointSize: CGFloat = 10.0
public let tabBarUpstreamTitleBottomInset: CGFloat = 1.0

public func tabBarUpstreamIconFrame(itemWidth: CGFloat, imageSize: CGSize) -> CGRect {
    let longest = max(imageSize.width, imageSize.height)
    let scale: CGFloat
    if longest > tabBarUpstreamIconPointSize && longest > 0 {
        scale = tabBarUpstreamIconPointSize / longest
    } else {
        scale = 1
    }
    let fitted = CGSize(width: floor(imageSize.width * scale), height: floor(imageSize.height * scale))
    return CGRect(x: floor((itemWidth - fitted.width) / 2.0), y: tabBarUpstreamItemContentOriginY, width: fitted.width, height: fitted.height)
}

public func tabBarUpstreamTitleFrame(itemWidth: CGFloat, titleSize: CGSize) -> CGRect {
    let y = tabBarUpstreamItemContentOriginY + tabBarUpstreamItemContentHeight - tabBarUpstreamTitleBottomInset - titleSize.height
    return CGRect(x: floor((itemWidth - titleSize.width) / 2.0), y: y, width: titleSize.width, height: titleSize.height)
}

/// Title frame inside one item. Same title height means the same baseline across items.
public func tabBarTitleFrame(itemSize: CGSize, titleSize: CGSize) -> CGRect {
    return CGRect(x: floor((itemSize.width - titleSize.width) * 0.5), y: itemSize.height - 8.0 - titleSize.height, width: titleSize.width, height: titleSize.height)
}

public let tabBarTitleBasePointSize: CGFloat = 10.0
/// The item is 56pt. Past this size the title covers the icon, so Dynamic Type stops here and then only shrinks.
public let tabBarTitleMaximumPointSize: CGFloat = 13.0
/// How far a shared title size may shrink so three labels still share one width.
public let tabBarTitleMinimumScale: CGFloat = 0.7

public func tabBarClampedTitlePointSize(dynamicPointSize: CGFloat) -> CGFloat {
    return min(tabBarTitleMaximumPointSize, dynamicPointSize)
}

/// Scale that keeps every measured title inside an equal slot, or nil when `minimumScale` still overflows.
/// One means they already fit. The caller then keeps one font so the baselines stay together.
public func tabBarEqualTitleScale(titleWidths: [CGFloat], equalSlotWidth: CGFloat, minimumScale: CGFloat = tabBarTitleMinimumScale) -> CGFloat? {
    guard equalSlotWidth > 0, !titleWidths.isEmpty else {
        return 1
    }
    let widest = titleWidths.max() ?? 0
    if widest <= equalSlotWidth + 0.5 {
        return 1
    }
    let scale = equalSlotWidth / widest
    if scale + 0.0001 < minimumScale {
        return nil
    }
    return scale
}

public func tabBarItemAccessibilityTraits(isSelected: Bool) -> UIAccessibilityTraits {
    var traits: UIAccessibilityTraits = [.button]
    if isSelected {
        traits.insert(.selected)
    }
    return traits
}

/// The item under `point`, or the nearest one by distance along the axis when it is outside every item.
/// Nil when there are no items.
public func tabBarItemIndex(at point: CGPoint, axis: TabBarAxis, itemFrames: [CGRect]) -> Int? {
    var closest: (index: Int, distance: CGFloat)?
    for (index, frame) in itemFrames.enumerated() {
        if frame.contains(point) {
            return index
        }
        let distance: CGFloat
        switch axis {
        case .horizontal:
            distance = abs(point.x - frame.midX)
        case .vertical:
            distance = abs(point.y - frame.midY)
        }
        if let closestValue = closest {
            if distance < closestValue.distance {
                closest = (index, distance)
            }
        } else {
            closest = (index, distance)
        }
    }
    return closest?.index
}
