import DesignSystem
import SwiftUI

// MARK: - CartBagIcon

/// The shopping bag with the number of items beside it, as fashion retail apps draw their cart:
/// a thin outline bag with a small figure to its right, at half its height. An empty cart shows
/// the bag alone. Decorative; the button or tab around it carries the label and the count for
/// VoiceOver.
///
/// ```swift
/// Button { onRoute(.cart) } label: { CartBagIcon(count: cartStore.itemCount) }
/// ```
public struct CartBagIcon: View {
    private let count: Int
    private let isCentered: Bool

    /// Creates the icon.
    ///
    /// - Parameters:
    ///   - count: The number of items in the cart.
    ///   - isCentered: Whether an invisible copy of the figure on the leading side keeps the
    ///     bag itself centered, for example above the title of a tab.
    public init(count: Int, isCentered: Bool = false) {
        self.count = count
        self.isCentered = isCentered
    }

    public var body: some View {
        HStack(alignment: .center, spacing: KXSpacing.xxs) {
            if isCentered {
                figure
                    .hidden()
            }
            Image(systemName: "bag")
                .fontWeight(.light)
            figure
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder private var figure: some View {
        let text = Self.figure(for: count)
        if !text.isEmpty {
            Text(verbatim: text)
                .fontWeight(.medium)
                .kxFont(.caption)
                .monospacedDigit()
        }
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
