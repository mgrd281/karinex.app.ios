import DesignTokens
import SwiftUI

// MARK: - KXPressButtonStyle

/// The button style of large tappable surfaces (cards, tiles, rows, chips): while pressed the
/// surface shrinks a little and springs back on release, as the cards of retail apps do. With
/// Reduce Motion it dims instead of moving.
///
/// ```swift
/// Button { open(collection) } label: { CategoryRow(collection) }
///     .buttonStyle(.kxPress)
/// ```
public struct KXPressButtonStyle: ButtonStyle {
    /// Creates the style.
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        KXPressBody(configuration: configuration)
    }
}

extension ButtonStyle where Self == KXPressButtonStyle {
    /// ``KXPressButtonStyle``: a card or tile that shrinks a little while pressed.
    public static var kxPress: KXPressButtonStyle {
        KXPressButtonStyle()
    }
}

/// The pressed state of ``KXPressButtonStyle``, which needs the Reduce Motion setting.
private struct KXPressBody: View {
    let configuration: ButtonStyleConfiguration

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let isPressed = configuration.isPressed
        configuration.label
            .scaleEffect(isPressed && !reduceMotion ? MotionToken.pressedScale : 1)
            .opacity(isPressed && reduceMotion ? MotionToken.pressedOpacity : 1)
            .animation(KXMotion.animation(.snappy, reduceMotion: reduceMotion), value: isPressed)
    }
}
