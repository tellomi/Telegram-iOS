import CoreGraphics
import Foundation

/// Scroll position of the root tab bar while a Discover list is on screen.
public struct TellomiFeedNavigationScrollState: Equatable {
    public var visible: Bool
    public var pending: CGFloat

    public init(visible: Bool = true, pending: CGFloat = 0) {
        self.visible = visible
        self.pending = pending
    }

    public static let resting = TellomiFeedNavigationScrollState()
}

public enum TellomiFeedNavigationChange: Equatable {
    case unchanged
    case shown
    case hidden
}

/// Hides the bottom bar after a downward drag and shows it after an upward one.
/// An empty list and the top of the list keep the bar visible. Small reversals
/// do not accumulate, so a jittering finger does not flicker the bar.
public enum TellomiFeedNavigationScroll {
    public static let threshold: CGFloat = 24
    public static let topReset: CGFloat = 2
    public static let noise: CGFloat = 1

    public static func step(state: TellomiFeedNavigationScrollState, offsetY: CGFloat, delta: CGFloat, hasPosts: Bool) -> (state: TellomiFeedNavigationScrollState, change: TellomiFeedNavigationChange) {
        if !hasPosts || offsetY <= self.topReset {
            let change: TellomiFeedNavigationChange = state.visible ? .unchanged : .shown
            return (.resting, change)
        }
        if abs(delta) < self.noise {
            return (state, .unchanged)
        }
        var pending = state.pending
        if pending != 0, (pending > 0) != (delta > 0) {
            pending = 0
        }
        pending += delta
        if pending >= self.threshold, state.visible {
            return (TellomiFeedNavigationScrollState(visible: false, pending: 0), .hidden)
        }
        if pending <= -self.threshold, !state.visible {
            return (TellomiFeedNavigationScrollState(visible: true, pending: 0), .shown)
        }
        return (TellomiFeedNavigationScrollState(visible: state.visible, pending: pending), .unchanged)
    }
}

/// Reduce Motion keeps the same show/hide decision and drops the animation.
public func tellomiFeedNavigationTransitionAnimated(reduceMotion: Bool) -> Bool {
    return !reduceMotion
}

/// Bottom-right compose control. `bottomInset` is the tab bar and safe area.
/// `keyboardOverlap` lifts it above the keyboard when that is taller.
public func tellomiDiscoverComposeButtonFrame(containerWidth: CGFloat, containerHeight: CGFloat, bottomInset: CGFloat, keyboardOverlap: CGFloat, side: CGFloat = 56, margin: CGFloat = 16) -> CGRect {
    let lift = max(bottomInset, keyboardOverlap, 0)
    let width = min(side, max(0, containerWidth - margin * 2))
    let x = containerWidth - margin - width
    let y = containerHeight - lift - margin - width
    return CGRect(x: max(margin, x), y: max(margin, y), width: width, height: width)
}

public func tellomiDiscoverComposeButtonVisible(showsCompose: Bool, engineVisible: Bool) -> Bool {
    return showsCompose && engineVisible
}
