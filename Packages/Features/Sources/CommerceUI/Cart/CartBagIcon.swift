import DesignSystem
import SwiftUI

// MARK: - CartBagIcon

/// The shopping bag with the number of items beside it, as fashion retail apps draw their cart:
/// the outline tote with its tall handle (``CartBagShape``) and a small semibold figure to its
/// right, centered on the bag. An empty cart shows the bag alone. The bag is 22 points high and
/// scales with Dynamic Type. Decorative; the button or tab around it carries the label and the
/// count for VoiceOver.
///
/// ```swift
/// Button { onRoute(.cart) } label: { CartBagIcon(count: cartStore.itemCount) }
/// ```
public struct CartBagIcon: View {
    private let count: Int
    private let isCentered: Bool
    @ScaledMetric(relativeTo: .body) private var bagHeight = CartBagGrid.size.height

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
        HStack(alignment: .center, spacing: KXSpacing.xs) {
            if isCentered {
                figure
                    .hidden()
            }
            CartBagShape()
                .frame(width: bagHeight * CartBagShape.aspectRatio, height: bagHeight)
            figure
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder private var figure: some View {
        let text = Self.figure(for: count)
        if !text.isEmpty {
            Text(verbatim: text)
                .kxFont(.figure)
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
