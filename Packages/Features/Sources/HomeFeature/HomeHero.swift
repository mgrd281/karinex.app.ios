import CommerceUI
import DesignSystem
import ShopifyKit
import SwiftUI

// MARK: - HomeHero

/// The hero of the Start tab, laid out like the campaign banner of a fashion retail app: the
/// KARINEX wordmark centered on top, the photo of the store's top bestseller edge to edge on the
/// light grey photo tile, then an eyebrow, a bold display headline, a short introduction and the
/// black call to action "Zum Sortiment".
///
/// The photo comes from the bestseller row of the store (Shopify is the only source of product
/// images); tapping it opens that product. While the row loads the plain tile holds the space;
/// when the row is empty or fails the hero shows its text only.
struct HomeHero: View {
    /// The load state of the bestseller row; its first product provides the photo.
    let bestsellers: LoadState<[ProductSummary]>
    /// Called by the call to action.
    let onBrowse: @MainActor () -> Void
    /// Opens the product of the photo.
    let onSelect: @MainActor (ProductSummary) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.l) {
            KXWordmark(size: .regular)
                .frame(maxWidth: .infinity)
                .padding(.top, KXSpacing.xs)
                .accessibilityAddTraits(.isHeader)
            photo
            VStack(alignment: .leading, spacing: KXSpacing.l) {
                VStack(alignment: .leading, spacing: KXSpacing.s) {
                    Text("home.hero.eyebrow", bundle: .module)
                        .kxFont(.eyebrow)
                        .foregroundStyle(KXColor.textSecondary)
                    Text("home.hero.title", bundle: .module)
                        .kxFont(.display)
                        .foregroundStyle(KXColor.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Text("home.hero.body", bundle: .module)
                        .kxFont(.body)
                        .foregroundStyle(KXColor.textSecondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                KXButton(
                    String(localized: "home.hero.cta", bundle: .module),
                    isFullWidth: true
                ) {
                    onBrowse()
                }
                .accessibilityIdentifier("home.hero.cta")
            }
            .padding(.horizontal, KXSpacing.gutter)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    // MARK: Photo

    @ViewBuilder private var photo: some View {
        switch bestsellers {
        case .idle, .loading:
            KXColor.imageBackground
                .aspectRatio(Self.photoAspectRatio, contentMode: .fit)
                .accessibilityHidden(true)
        case let .loaded(products):
            if let product = products.first {
                Button {
                    onSelect(product)
                } label: {
                    ProductImage(product.featuredImage, isDecorative: true)
                        .padding(KXSpacing.l)
                        .kxPhotoTile()
                        .aspectRatio(Self.photoAspectRatio, contentMode: .fit)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(product.title))
                .accessibilityAddTraits(.isImage)
                .accessibilityIdentifier("home.hero.product")
            }
        case .empty, .failed:
            EmptyView()
        }
    }

    /// Width to height of the photo: a little wider than square, like a campaign image.
    private static let photoAspectRatio: CGFloat = 4 / 3
}
