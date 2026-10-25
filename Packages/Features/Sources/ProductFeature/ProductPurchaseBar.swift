import CommerceUI
import DesignSystem
import ShopifyKit
import SwiftUI

// MARK: - ProductPurchaseBar

/// The sticky bar at the bottom of the product screen: the price of the selected variant with
/// its tax note, "In den Warenkorb" and "Jetzt kaufen".
///
/// Both buttons are disabled while the variant cannot be bought or an add is running. The
/// buttons sit side by side and stack at large text sizes, so nothing is cut off.
struct ProductPurchaseBar: View {
    let variant: ProductVariant
    let isAdding: Bool
    let onAddToCart: @MainActor () -> Void
    let onBuyNow: @MainActor () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.s) {
            PriceText(
                price: variant.price,
                compareAtPrice: variant.compareAtPrice,
                requiresShipping: variant.requiresShipping,
                size: .compact
            )
            .accessibilityIdentifier("product.bar.price")
            buttons
        }
        .padding(.horizontal, KXSpacing.gutter)
        .padding(.top, KXSpacing.s)
        .padding(.bottom, KXSpacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            KXColor.surfaceElevated
                .ignoresSafeArea(edges: .bottom)
                .shadow(color: KXColor.scrim.opacity(0.12), radius: KXSpacing.s, x: 0, y: -2)
        }
        .overlay(alignment: .top) {
            KXDivider()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("product.bar")
    }

    private var buttons: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: KXSpacing.xs))
            : AnyLayout(HStackLayout(spacing: KXSpacing.s))
        return layout {
            KXButton(
                String(localized: "product.cart.buy_now", bundle: .module),
                style: .secondary,
                isFullWidth: true
            ) {
                onBuyNow()
            }
            .accessibilityIdentifier("product.buyNow")
            KXButton(
                String(localized: "product.cart.add", bundle: .module),
                systemImage: "bag",
                isFullWidth: true,
                isLoading: isAdding
            ) {
                onAddToCart()
            }
            .accessibilityIdentifier("product.addToCart")
        }
        .disabled(!variant.availableForSale || isAdding)
    }
}
