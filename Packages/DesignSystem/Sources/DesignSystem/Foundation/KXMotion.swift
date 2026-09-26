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
    }

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
