import CommerceUI
import DesignSystem
import ShopifyKit
import SwiftUI

// MARK: - ProductPurchaseBar

/// The sticky bar at the bottom of the product screen, as in fashion retail apps: the price of
/// the selected variant with its tax note on the leading side and the black "In den Warenkorb"
/// button on the trailing side. The compare-at price and the savings stay in the summary above,
/// so the bar stays calm.
///
/// The button is disabled while the variant cannot be bought or an add is running. When price
/// and button do not fit side by side (long translations, large text sizes) the button moves
/// below the price at full width, so nothing is cut off.
struct ProductPurchaseBar: View {
    let variant: ProductVariant
    let isAdding: Bool
    let onAddToCart: @MainActor () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: KXSpacing.m) {
                price
                    .fixedSize()
                addButton
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: KXSpacing.s) {
                price
                addButton
            }
        }
        .padding(.horizontal, KXSpacing.gutter)
        .padding(.top, KXSpacing.s)
        .padding(.bottom, KXSpacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            KXColor.surface
                .ignoresSafeArea(edges: .bottom)
        }
        .overlay(alignment: .top) {
            KXDivider()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("product.bar")
    }

    private var price: some View {
        PriceText(
            price: variant.price,
            requiresShipping: variant.requiresShipping,
            showsSavings: false
        )
        .accessibilityIdentifier("product.bar.price")
    }

    private var addButton: some View {
        KXButton(
            String(localized: "product.cart.add", bundle: .module),
            isFullWidth: true,
            isLoading: isAdding
        ) {
            onAddToCart()
        }
        .disabled(!variant.availableForSale || isAdding)
        .accessibilityIdentifier("product.addToCart")
    }
}
