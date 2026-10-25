import DesignSystem
import SwiftUI

// MARK: - CartBagIcon

/// The shopping bag with the number of items as a small figure beside it, as the cart buttons
/// of fashion retail apps show it (and as the Warenkorb tab does). An empty cart shows the bag
/// alone. Decorative; the button around it carries the label and the count for VoiceOver.
///
/// ```swift
/// Button { onRoute(.cart) } label: { CartBagIcon(count: cartStore.itemCount) }
/// ```
public struct CartBagIcon: View {
    private let count: Int

    /// Creates the icon.
    ///
    /// - Parameter count: The number of items in the cart.
    public init(count: Int) {
        self.count = count
    }

    public var body: some View {
        HStack(alignment: .top, spacing: KXSpacing.xxs / 2) {
            Image(systemName: "bag")
            let figure = Self.figure(for: count)
            if !figure.isEmpty {
                Text(verbatim: figure)
                    .fontWeight(.semibold)
                    .kxFont(.caption)
                    .monospacedDigit()
            }
        }
        .accessibilityHidden(true)
    }

    /// The figure beside the bag: the count up to 99, then "99+"; empty for an empty cart.
    public static func figure(for count: Int) -> String {
        switch count {
        case ..<1: ""
        case 1...99: String(count)
        default: "99+"
        }
    }
}
