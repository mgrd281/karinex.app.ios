import CommerceUI
import DesignSystem
import ShopifyKit
import SwiftUI

// MARK: - HomeFeedBar

/// The chips at the bottom of the Start screen, above the tab bar, as in fashion retail apps:
/// "Für Sie" for the whole Start page and one chip per category, which switches the page to that
/// category's products. The chosen chip is outlined in ink.
struct HomeFeedBar: View {
    let categories: [HomeCategory]
    /// The handle of the chosen category, `nil` for "Für Sie".
    @Binding var selection: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: KXSpacing.xs) {
                HomeFeedChip(
                    title: String(localized: "home.feed.for_you", bundle: .module),
                    isSelected: selection == nil
                ) {
                    selection = nil
                }
                .accessibilityIdentifier("home.feed.forYou")
                ForEach(categories) { category in
                    HomeFeedChip(title: category.title.resolved, isSelected: selection == category.handle) {
                        selection = category.handle
                    }
                    .accessibilityIdentifier("home.feed.\(category.handle)")
                }
            }
            .padding(.horizontal, KXSpacing.gutter)
        }
        .frame(maxWidth: .infinity)
        .background(KXColor.background)
        .overlay(alignment: .top) {
            KXDivider()
        }
        .sensoryFeedback(.selection, trigger: selection)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.feed")
    }
}

// MARK: - HomeFeedChip

/// One chip of the feed bar: a light grey capsule, or white with an ink outline when chosen. The
/// tap area is the full height of the bar.
private struct HomeFeedChip: View {
    let title: String
    let isSelected: Bool
    let action: @MainActor () -> Void

    @ScaledMetric(relativeTo: .subheadline) private var chipHeight: CGFloat = 36

    var body: some View {
        let shape = Capsule(style: .continuous)
        Button {
            action()
        } label: {
            Text(title)
                .fontWeight(isSelected ? .semibold : .regular)
                .kxFont(.subheadline)
                .foregroundStyle(isSelected ? KXColor.textPrimary : KXColor.textSecondary)
                .lineLimit(1)
                .padding(.horizontal, KXSpacing.s)
                .frame(minHeight: chipHeight)
                .background(isSelected ? KXColor.background : KXColor.surface, in: shape)
                .overlay {
                    if isSelected {
                        shape.strokeBorder(KXColor.textPrimary, lineWidth: KXBorder.regular)
                    }
                }
                .padding(.vertical, KXSpacing.xxs)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - HomeCategoryFeed

/// The Start screen switched to one category by the feed bar: the category's name and its
/// products as a grid of cards, then "Alle Produkte anzeigen", which opens the whole collection.
struct HomeCategoryFeed: View {
    let category: HomeCategory
    let state: LoadState<[ProductSummary]>
    let retry: @MainActor () async -> Void
    let onShowAll: @MainActor () -> Void
    let onSelect: @MainActor (ProductSummary) -> Void

    @ScaledMetric(relativeTo: .body) private var minimumCardWidth: CGFloat = 150

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: min(minimumCardWidth, 280)), spacing: KXSpacing.s, alignment: .top)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.l) {
            KXSectionHeader(category.title.resolved, eyebrow: category.eyebrow?.resolved)
            content
            KXButton(String(localized: "home.feed.show_all", bundle: .module), style: .secondary, isFullWidth: true) {
                onShowAll()
            }
            .accessibilityIdentifier("home.feed.showAll")
        }
        .padding(.horizontal, KXSpacing.gutter)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.feed.category.\(category.handle)")
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .idle, .loading:
            LazyVGrid(columns: columns, alignment: .leading, spacing: KXSpacing.l) {
                ForEach(0..<4, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: KXSpacing.xs) {
                        KXSkeleton(cornerRadius: KXRadius.image)
                            .aspectRatio(1, contentMode: .fit)
                        KXSkeleton()
                            .frame(height: KXSpacing.m)
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("home.loading", bundle: .module))
        case let .loaded(products):
            LazyVGrid(columns: columns, alignment: .leading, spacing: KXSpacing.l) {
                ForEach(products) { product in
                    Button {
                        onSelect(product)
                    } label: {
                        ProductCardView(product)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("product.card.\(product.handle)")
                }
            }
        case let .failed(error):
            KXBanner(
                .error,
                message: error.message,
                action: error.isRetryable ? { Task { await retry() } } : nil
            )
        case .empty:
            EmptyView()
        }
    }
}
