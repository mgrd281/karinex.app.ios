import CommerceUI
import DesignSystem
import SwiftUI

// MARK: - ProductToolbar

/// The navigation bar of the product page, as on the product pages of fashion retail apps: the
/// product title once it has scrolled away, then the share arrow and the shopping bag with the
/// number of items, which opens the cart.
///
/// On iOS 26 the share arrow and the bag are plain symbols without the glass circle of the
/// system bar items (`sharedBackgroundVisibility(.hidden)`); earlier versions draw plain bar
/// buttons anyway.
struct ProductToolbar: ViewModifier {
    /// The product title, shown in the bar once the title on the page scrolled away.
    let title: String
    /// Whether the title on the page is still on screen.
    let isTitleVisible: Bool
    /// The product page of the web shop, `nil` when the product has none (no share arrow).
    let shareURL: URL?
    /// The number of items in the cart.
    let cartCount: Int
    /// Opens the cart.
    let onCart: @MainActor () -> Void

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.toolbar {
                titleItem
                if let shareURL {
                    ToolbarItem(placement: .topBarTrailing) {
                        shareButton(shareURL)
                    }
                    .sharedBackgroundVisibility(.hidden)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    cartButton
                }
                .sharedBackgroundVisibility(.hidden)
            }
        } else {
            content.toolbar {
                titleItem
                if let shareURL {
                    ToolbarItem(placement: .topBarTrailing) {
                        shareButton(shareURL)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    cartButton
                }
            }
        }
    }

    // MARK: Items

    private var titleItem: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Text(verbatim: title)
                .kxFont(.headline)
                .foregroundStyle(KXColor.textPrimary)
                .lineLimit(1)
                .opacity(isTitleVisible ? 0 : 1)
                .accessibilityHidden(isTitleVisible)
                .kxAnimation(.fade, value: isTitleVisible)
        }
    }

    private func shareButton(_ url: URL) -> some View {
        ShareLink(item: url, subject: Text(verbatim: title)) {
            Label {
                Text("product.share", bundle: .module)
            } icon: {
                Image(systemName: "square.and.arrow.up")
            }
        }
        .foregroundStyle(KXColor.textPrimary)
        .accessibilityIdentifier("product.share")
    }

    private var cartButton: some View {
        let figure = CartBagIcon.figure(for: cartCount)
        return Button {
            onCart()
        } label: {
            CartBagIcon(count: cartCount)
                .foregroundStyle(KXColor.textPrimary)
                .frame(minWidth: KXSpacing.minimumTapTarget, minHeight: KXSpacing.minimumTapTarget)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(Text("product.toolbar.cart", bundle: .module))
        .accessibilityValue(figure)
        .accessibilityIdentifier("product.cart")
    }
}
