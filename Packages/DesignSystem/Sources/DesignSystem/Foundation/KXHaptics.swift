import SwiftUI
import UIKit

/// Haptic feedback for the moments the brand spec calls out: add to cart, copy key and
/// successful checkout. In SwiftUI views prefer `.sensoryFeedback(_:trigger:)`; use this
/// type from imperative code paths (view model callbacks, UIKit delegates).
@MainActor
public enum KXHaptics {
    /// Light confirmation, e.g. an item was added to the cart.
    public static func confirm() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    /// Success notification, e.g. a license key was copied or checkout completed.
    public static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// Warning notification, e.g. a recoverable error was shown.
    public static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    /// Selection tick, e.g. a variant chip or stepper value changed.
    public static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
}
