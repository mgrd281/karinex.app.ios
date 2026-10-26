import CommerceUI
import DesignSystem
import ShopifyKit
import SwiftUI

// MARK: - HomeProductPanel

/// A dark panel with a row of product cards, like the brand panels of fashion retail apps: the
/// small label and the name on top with "Alle anzeigen", then the products with light text on
/// the dark panel. The photos stay on their light tiles. The sale panel shows its name in sale
/// red. The panel is the KARINEX store color (``KXColor/storePanel``).
///
/// Like ``ProductCarouselSection`` it shows a skeleton while loading, a compact error with
/// "Erneut versuchen" when the request failed, and nothing at all when the collection is empty.
struct HomeProductPanel: View {
    let eyebrow: String?
    let title: String
    /// Whether the name is drawn in sale red.
    let isSale: Bool
    let state: LoadState<[ProductSummary]>
    let retry: @MainActor () async -> Void
    let onShowAll: @MainActor () -> Void
    let onSelect: @MainActor (ProductSummary) -> Void

    var body: some View {
        if case .empty = state {
            EmptyView()
        } else {
            HomePanelContent(
                eyebrow: eyebrow,
                title: title,
                isSale: isSale,
                state: state,
                cardSize: .regular,
                retry: retry,
                onShowAll: onShowAll,
                onSelect: onSelect
            )
            .homeStorePanel()
        }
    }
}

// MARK: - HomePanelContent

/// The inside of a store color panel: the small label and the name with "Alle anzeigen", then
/// the product row, its skeleton while loading, or a compact error with "Erneut versuchen".
struct HomePanelContent: View {
    let eyebrow: String?
    let title: String
    /// Whether the name is drawn in sale red.
    let isSale: Bool
    let state: LoadState<[ProductSummary]>
    /// The size of the product cards.
    let cardSize: ProductRowCardSize
    let retry: @MainActor () async -> Void
    let onShowAll: @MainActor () -> Void
    let onSelect: @MainActor (ProductSummary) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.m) {
            header
            content
        }
        .padding(.vertical, KXSpacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Parts

    private var header: some View {
        HStack(alignment: .lastTextBaseline, spacing: KXSpacing.m) {
            VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                if let eyebrow {
                    Text(eyebrow)
                        .kxFont(.eyebrow)
                        .foregroundStyle(KXColor.textSecondary)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .kxFont(.title1)
                    .foregroundStyle(isSale ? KXColor.urgencyText : KXColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                onShowAll()
            } label: {
                HStack(spacing: KXSpacing.xxs) {
                    Text("home.panel.show_all", bundle: .module)
                    Image(systemName: "arrow.right")
                        .accessibilityHidden(true)
                }
                .fontWeight(.semibold)
                .kxFont(.subheadline)
                .foregroundStyle(KXColor.textPrimary)
                .frame(minHeight: KXSpacing.minimumTapTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("home.panel.showAll")
        }
        .padding(.horizontal, KXSpacing.gutter)
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .idle, .loading:
            ProductRowSkeleton(cardSize: cardSize)
        case let .loaded(products):
            ProductRow(products: products, cardSize: cardSize, onSelect: onSelect)
        case let .failed(error):
            KXBanner(
                .error,
                message: error.message,
                action: error.isRetryable ? { Task { await retry() } } : nil
            )
            .padding(.horizontal, KXSpacing.gutter)
        case .empty:
            EmptyView()
        }
    }
}

// MARK: - Store panel

extension View {
    /// Draws the view on a large panel in the store color: the gradient from
    /// ``KXColor/storePanel`` to ``KXColor/storePanelDeep`` with large rounded corners, and the
    /// content in the dark color scheme, so its text is light.
    func homeStorePanel() -> some View {
        background {
            LinearGradient(
                colors: [KXColor.storePanel, KXColor.storePanelDeep],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: KXRadius.large, style: .continuous))
        .environment(\.colorScheme, .dark)
    }
}
