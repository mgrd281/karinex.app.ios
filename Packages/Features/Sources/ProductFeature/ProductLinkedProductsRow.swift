import CommerceUI
import DesignSystem
import ShopifyKit
import SwiftUI

// MARK: - ProductLinkedProductsRow

/// The products the merchant linked to this one in the web shop (for example the other editions
/// of a product), as a row of photo thumbnails below the price, the way fashion retail apps show
/// the other colors of an article.
///
/// The current product is outlined in ink and stays where the merchant put it; tapping another
/// thumbnail opens that product. A product that cannot be bought is dimmed and VoiceOver says
/// "Derzeit nicht verfügbar". The row scrolls sideways when the thumbnails do not fit.
struct ProductLinkedProductsRow: View {
    /// The thumbnails, from ``ProductDetailViewModel/linkedProducts(of:)``.
    let products: [ProductSummary]
    /// The product of the screen.
    let currentID: ShopifyID
    /// Opens a linked product.
    let onSelect: @MainActor (ProductSummary) -> Void

    @ScaledMetric(relativeTo: .body) private var scaledSide: CGFloat = 72

    /// The side of one square thumbnail, larger at large text sizes but capped.
    private var side: CGFloat {
        min(scaledSide, 120)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.s) {
            Text("product.linked.title", bundle: .module)
                .fontWeight(.semibold)
                .kxFont(.subheadline)
                .foregroundStyle(KXColor.textPrimary)
                .accessibilityAddTraits(.isHeader)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: KXSpacing.xs) {
                    ForEach(products) { product in
                        thumbnail(product)
                    }
                }
            }
            .scrollClipDisabled()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("product.linked")
    }

    private func thumbnail(_ product: ProductSummary) -> some View {
        let isCurrent = product.id == currentID
        let shape = RoundedRectangle(cornerRadius: KXRadius.small, style: .continuous)
        return Button {
            if !isCurrent {
                onSelect(product)
            }
        } label: {
            ProductImage(product.featuredImage, isDecorative: true)
                .padding(KXSpacing.xs)
                .kxPhotoTile()
                .frame(width: side, height: side)
                .clipShape(shape)
                .overlay {
                    shape.strokeBorder(
                        isCurrent ? KXColor.textPrimary : KXColor.hairline,
                        lineWidth: isCurrent ? KXBorder.emphasis : KXBorder.hairline
                    )
                }
                .opacity(product.availableForSale ? 1 : 0.45)
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(product.title))
        .accessibilityValue(
            product.availableForSale ? Text(verbatim: "") : Text("product.availability.unavailable", bundle: .module)
        )
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
        .accessibilityIdentifier("product.linked.\(product.handle)")
    }
}
