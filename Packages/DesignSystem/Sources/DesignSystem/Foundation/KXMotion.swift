import DesignTokens
import SwiftUI

/// Brand animations. Always go through `KXMotion.animation(_:reduceMotion:)` (or the
/// `kxAnimation` modifier) so that Reduce Motion is respected everywhere.
public enum KXMotion {
    /// The animation curves the design system uses.
    public enum Curve: Sendable {
        /// Default spring for most state changes.
        case standard
        /// Quick spring for small controls (accordions, toggles, steppers).
        case snappy
        /// Soft spring for large surfaces (hero, sheets, matched geometry).
        case gentle
        /// Plain cross-fade.
        case fade
        /// Slow cross-fade for a large surface that swaps its content, e.g. a showcase moving
        /// on to its next item.
        case swap
    }

    /// How long a cycling showcase shows one item before it moves on to the next.
    public static let cycleDwell = Duration.seconds(MotionToken.cycleDwellDuration)

    /// How blurred content is at the start and the end of a ``Curve/swap``.
    public static let swapBlurRadius = CGFloat(MotionToken.swapBlurRadius)

    /// The steady fill of a cycling showcase's progress over ``cycleDwell``. Only run it while
    /// the showcase cycles, which it never does with Reduce Motion.
    public static var cycleProgress: Animation {
        .linear(duration: MotionToken.cycleDwellDuration)
    }

    /// How long the wishlist heart takes to fill when a product is saved.
    public static let heartFillDuration = MotionToken.heartFillDuration
    /// How long the filled heart takes to grow and settle again after filling.
    public static let heartPopDuration = MotionToken.heartPopDuration
    /// How far the filled heart grows before it settles.
    public static let heartPopScale = CGFloat(MotionToken.heartPopScale)
    /// How long the small hearts take to burst from the saved heart and fade.
    public static let heartBurstDuration = MotionToken.heartBurstDuration
    /// How long the membership ring takes to fill to its value.
    public static let ringFillDuration = MotionToken.ringFillDuration
    /// How long the trend line takes to draw itself.
    public static let trendDrawDuration = MotionToken.trendDrawDuration
    /// How long the arrow head takes to draw after the line.
    public static let trendArrowDuration = MotionToken.trendArrowDuration
    /// How long the drawn trend stays visible.
    public static let trendHoldDuration = MotionToken.trendHoldDuration
    /// How long the trend takes to erase itself again.
    public static let trendEraseDuration = MotionToken.trendEraseDuration
    /// How long the trend rests erased before it draws again.
    public static let trendRestDuration = MotionToken.trendRestDuration

    /// Returns the animation for `curve`, or a short cross-fade when Reduce Motion is on.
    public static func animation(_ curve: Curve, reduceMotion: Bool) -> Animation {
        if reduceMotion {
            return .easeInOut(duration: MotionToken.fadeDuration)
        }
        switch curve {
        case .standard:
            return .spring(response: MotionToken.springResponse, dampingFraction: MotionToken.springDamping)
        case .snappy:
            return .spring(response: MotionToken.snappyResponse, dampingFraction: MotionToken.springDamping)
        case .gentle:
            return .spring(response: MotionToken.gentleResponse, dampingFraction: MotionToken.springDamping)
        case .fade:
            return .easeInOut(duration: MotionToken.fadeDuration)
        case .swap:
            return .easeInOut(duration: MotionToken.swapDuration)
        }
    }
}

extension View {
    /// Animates changes of `value` with a brand curve, honoring Reduce Motion.
    public func kxAnimation(_ curve: KXMotion.Curve = .standard, value: some Equatable) -> some View {
        modifier(KXAnimationModifier(curve: curve, value: value))
    }
}

private struct KXAnimationModifier<Value: Equatable>: ViewModifier {
    let curve: KXMotion.Curve
    let value: Value
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(KXMotion.animation(curve, reduceMotion: reduceMotion), value: value)
    }
}
