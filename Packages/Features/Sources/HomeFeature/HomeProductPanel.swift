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

    @ScaledMetric(relativeTo: .body) private var skeletonCardWidth: CGFloat = 164

    var body: some View {
        if case .empty = state {
            EmptyView()
        } else {
            let shape = RoundedRectangle(cornerRadius: KXRadius.large, style: .continuous)
            VStack(alignment: .leading, spacing: KXSpacing.m) {
                header
                content
            }
            .padding(.vertical, KXSpacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                LinearGradient(
                    colors: [KXColor.storePanel, KXColor.storePanelDeep],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .clipShape(shape)
            .environment(\.colorScheme, .dark)
        }
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
            skeleton
        case let .loaded(products):
            ProductRow(products: products, onSelect: onSelect)
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

    private var skeleton: some View {
        HStack(alignment: .top, spacing: KXSpacing.xs) {
            ForEach(0..<3, id: \.self) { _ in
                VStack(alignment: .leading, spacing: KXSpacing.xs) {
                    KXSkeleton(cornerRadius: KXRadius.image)
                        .aspectRatio(1, contentMode: .fit)
                    KXSkeleton()
                        .frame(height: KXSpacing.m)
                    KXSkeleton()
                        .frame(width: skeletonCardWidth * 0.5, height: KXSpacing.m)
                }
                .frame(width: skeletonCardWidth)
            }
        }
        .padding(.horizontal, KXSpacing.gutter)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("home.loading", bundle: .module))
    }
}

// MARK: - HomeCategoryShowcase

/// "Unsere Kategorien": a row of category tiles, the chosen one filled in ink, above the dark
/// product panel of the chosen category, as the brand strip of fashion retail apps. The last tile
/// leads to the whole range in the Shop tab.
struct HomeCategoryShowcase: View {
    let categories: [HomeCategory]
    let state: @MainActor (HomeCategory) -> LoadState<[ProductSummary]>
    let retry: @MainActor (HomeCategory) async -> Void
    let onOpen: @MainActor (HomeCategory) -> Void
    let onBrowseAll: @MainActor () -> Void
    let onSelect: @MainActor (ProductSummary) -> Void

    @State private var selectedHandle: String?

    /// The chosen category, the first one until the customer picks another.
    private var selected: HomeCategory? {
        categories.first { $0.handle == selectedHandle } ?? categories.first
    }

    var body: some View {
        if let selected {
            VStack(alignment: .leading, spacing: KXSpacing.m) {
                KXSectionHeader(
                    String(localized: "home.showcase.title", bundle: .module),
                    eyebrow: String(localized: "home.showcase.eyebrow", bundle: .module)
                )
                .padding(.horizontal, KXSpacing.gutter)
                tiles(selected: selected)
                HomeProductPanel(
                    eyebrow: selected.eyebrow?.resolved,
                    title: selected.title.resolved,
                    isSale: false,
                    state: state(selected),
                    retry: { await retry(selected) },
                    onShowAll: { onOpen(selected) },
                    onSelect: onSelect
                )
                .padding(.horizontal, KXSpacing.gutter)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("home.panel.\(selected.handle)")
                // A new identity per category, so its product row starts at the first card.
                .id(selected.handle)
            }
            .sensoryFeedback(.selection, trigger: selectedHandle)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("home.showcase")
        }
    }

    private func tiles(selected: HomeCategory) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: KXSpacing.xs) {
                ForEach(categories) { category in
                    HomeCategoryTile(
                        title: category.title.resolved,
                        systemImage: category.systemImage,
                        isSelected: category == selected
                    ) {
                        selectedHandle = category.handle
                    }
                    .accessibilityIdentifier("home.category.\(category.handle)")
                }
                HomeCategoryTile(
                    title: String(localized: "home.showcase.all", bundle: .module),
                    systemImage: "square.grid.2x2",
                    isSelected: false,
                    action: onBrowseAll
                )
                .accessibilityIdentifier("home.categories.all")
            }
            .padding(.horizontal, KXSpacing.gutter)
        }
    }
}

// MARK: - HomeCategoryTile

/// One category tile: the symbol above the short name, filled in ink when chosen.
struct HomeCategoryTile: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: @MainActor () -> Void

    @ScaledMetric(relativeTo: .caption) private var scaledWidth: CGFloat = 92
    @ScaledMetric(relativeTo: .caption) private var scaledHeight: CGFloat = 72

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: KXRadius.small, style: .continuous)
        Button {
            action()
        } label: {
            VStack(spacing: KXSpacing.xxs) {
                Image(systemName: systemImage)
                    .kxFont(.title3)
                Text(title)
                    .fontWeight(.medium)
                    .kxFont(.caption)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(isSelected ? KXColor.textOnAccent : KXColor.textPrimary)
            .padding(KXSpacing.xxs)
            .frame(width: min(scaledWidth, 150), height: min(scaledHeight, 120))
            .background(isSelected ? KXColor.accent : KXColor.background, in: shape)
            .overlay {
                shape.strokeBorder(isSelected ? KXColor.accent : KXColor.divider, lineWidth: KXBorder.regular)
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
