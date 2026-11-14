import Foundation
import UIKit
import Display

/// Length of one titled phone tab along the bar.
///
/// A two-tab capsule is 188pt: `2 * 90 + tabBarInnerInset * 2`. Short titles stay in that slot.
/// A title wider than the slot keeps its own measured width.
public let tellomiTitledTabItemLength: CGFloat = 90.0

/// A phone bar whose hug would leave less than this much free takes the whole available length instead.
/// The same gap the compact bar treats as a mistake rather than a margin.
public let tellomiPhoneTabBarFillThreshold: CGFloat = 60.0

/// The phone tab bar (horizontal, titles on or off) hugged to the visible tabs.
///
/// Nil when that hug would come within `tellomiPhoneTabBarFillThreshold` of `availableLength`, or past it.
/// The caller then keeps the full-length layout. No items still returns the inset-only bar.
public func tellomiPhoneTabBarHugLayout(showsItemTitles: Bool, unboundItemWidths: [CGFloat], availableLength: CGFloat) -> TabBarItemsLayout? {
    let count = unboundItemWidths.count
    let thickness = showsItemTitles ? tabBarItemLength : tabBarCompactItemThickness
    let lengths: [CGFloat]
    if showsItemTitles {
        lengths = unboundItemWidths.map { floorToScreenPixels(max(tellomiTitledTabItemLength, $0)) }
    } else {
        lengths = Array(repeating: tabBarItemLength, count: count)
    }
    let natural = lengths.reduce(0.0, +) + tabBarInnerInset * 2.0
    if count != 0 && availableLength - natural < tellomiPhoneTabBarFillThreshold {
        return nil
    }

    var itemFrames: [CGRect] = []
    var position = tabBarInnerInset
    for length in lengths {
        itemFrames.append(CGRect(x: position, y: tabBarInnerInset, width: length, height: thickness))
        position += length
    }
    let barLength = position + tabBarInnerInset
    let barThickness = thickness + tabBarInnerInset * 2.0
    return TabBarItemsLayout(size: CGSize(width: barLength, height: barThickness), itemFrames: itemFrames)
}
