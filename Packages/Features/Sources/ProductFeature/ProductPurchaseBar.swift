import CommerceUI
import DesignSystem
import ShopifyKit
import SwiftUI

// MARK: - ProductPurchaseBar

/// The sticky bar at the bottom of the product screen, as in fashion retail apps: a small photo
/// of the product and the price of the selected variant with its tax note on the leading side,
/// the black "In den Warenkorb" button on the trailing side. The compare-at price and the
/// savings stay in the summary above, so the bar stays calm.
///
/// The button is disabled while the variant cannot be bought or an add is running. When photo,
/// price and button do not fit side by side (long translations, large text sizes) the button
/// moves below them at full width, so nothing is cut off.
struct ProductPurchaseBar: View {
    let variant: ProductVariant
    /// The photo of the selected variant, or the product's featured image.
    let image: ShopifyImage?
    let isAdding: Bool
    let onAddToCart: @MainActor () -> Void

    @ScaledMetric(relativeTo: .body) private var scaledThumbnailSide: CGFloat = 44

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: KXSpacing.m) {
                summary
                    .fixedSize()
                addButton
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: KXSpacing.s) {
                summary
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

    /// Photo and price, side by side.
    private var summary: some View {
        HStack(alignment: .center, spacing: KXSpacing.s) {
            if image != nil {
                ProductImage(image, isDecorative: true)
                    .padding(KXSpacing.xxs)
                    .kxPhotoTile()
                    .frame(width: thumbnailSide, height: thumbnailSide)
                    .clipShape(RoundedRectangle(cornerRadius: KXRadius.small, style: .continuous))
            }
            price
        }
    }

    /// The side of the square photo, larger at large text sizes but capped.
    private var thumbnailSide: CGFloat {
        min(scaledThumbnailSide, 64)
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
