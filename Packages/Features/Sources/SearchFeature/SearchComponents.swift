import CommerceUI
import DesignSystem
import ShopifyKit
import SwiftUI

// MARK: - SearchCategoryGrid

/// The category shortcuts: a tile per main collection with its symbol in a gold ring.
struct SearchCategoryGrid: View {
    let onSelect: @MainActor (SearchCategoryShortcut) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var ringDiameter: CGFloat = 36

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: KXSpacing.s) {
            ForEach(SearchCategoryShortcut.allCases) { shortcut in
                Button {
                    onSelect(shortcut)
                } label: {
                    HStack(spacing: KXSpacing.s) {
                        Image(systemName: shortcut.systemImage)
                            .kxFont(.callout)
                            .foregroundStyle(KXColor.brand)
                            .frame(width: ringDiameter, height: ringDiameter)
                            .overlay {
                                Circle().strokeBorder(KXColor.accent, lineWidth: KXBorder.regular)
                            }
                            .accessibilityHidden(true)
                        Text(shortcut.title)
                            .kxFont(.headline)
                            .foregroundStyle(KXColor.textPrimary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(KXSpacing.s)
                    .frame(maxWidth: .infinity, minHeight: KXSpacing.minimumTapTarget, alignment: .leading)
                    .background(KXColor.surface, in: RoundedRectangle(cornerRadius: KXRadius.medium, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: KXRadius.medium, style: .continuous)
                            .strokeBorder(KXColor.hairline, lineWidth: KXBorder.hairline)
                    }
                    .contentShape(RoundedRectangle(cornerRadius: KXRadius.medium, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("search.category.\(shortcut.handle)")
            }
        }
    }

    private var columns: [GridItem] {
        let count = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        return Array(repeating: GridItem(.flexible(), spacing: KXSpacing.s, alignment: .top), count: count)
    }
}

// MARK: - SearchChip

/// A capsule button with a query, used for suggested searches.
struct SearchChip: View {
    let title: String
    let systemImage: String
    let action: @MainActor () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            Label {
                Text(title)
                    .kxFont(.subheadline)
            } icon: {
                Image(systemName: systemImage)
                    .kxFont(.footnote)
                    .foregroundStyle(KXColor.accentText)
            }
            .foregroundStyle(KXColor.textPrimary)
            .padding(.horizontal, KXSpacing.m)
            .frame(minHeight: KXSpacing.minimumTapTarget)
            .background(KXColor.surface, in: Capsule())
            .overlay {
                Capsule().strokeBorder(KXColor.accent.opacity(0.6), lineWidth: KXBorder.regular)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - SearchListRow

/// A tappable row of a result list: symbol, title, optional detail and a chevron.
struct SearchListRow: View {
    let systemImage: String
    let title: String
    let detail: String?
    let action: @MainActor () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            HStack(spacing: KXSpacing.s) {
                Image(systemName: systemImage)
                    .kxFont(.body)
                    .foregroundStyle(KXColor.brand)
                    .frame(minWidth: KXSpacing.l)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                    Text(title)
                        .kxFont(.body)
                        .foregroundStyle(KXColor.textPrimary)
                        .multilineTextAlignment(.leading)
                    if let detail {
                        Text(detail)
                            .kxFont(.footnote)
                            .foregroundStyle(KXColor.textSecondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .kxFont(.footnote)
                    .foregroundStyle(KXColor.iconSecondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, KXSpacing.m)
            .padding(.vertical, KXSpacing.s)
            .frame(minHeight: KXSpacing.minimumTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - SearchListCard

/// A titled card that stacks ``SearchListRow``s with hairline dividers.
struct SearchListCard<Item: Identifiable, Row: View>: View {
    let title: String
    let items: [Item]
    @ViewBuilder let row: (Item) -> Row

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.s) {
            SearchSectionTitle(title: title)
            KXCard(padding: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(items) { item in
                        row(item)
                        if item.id != items.last?.id {
                            KXDivider()
                                .padding(.leading, KXSpacing.m)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - SearchSectionTitle

/// The small section title of the search screen: an uppercase eyebrow in gold text color.
struct SearchSectionTitle: View {
    let title: String
    var actionTitle: String?
    var action: (@MainActor () -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: KXSpacing.s) {
            Text(title)
                .kxFont(.eyebrow)
                .foregroundStyle(KXColor.accentText)
                .accessibilityAddTraits(.isHeader)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let actionTitle, let action {
                KXButton(actionTitle, style: .tertiary, size: .compact) {
                    action()
                }
            }
        }
    }
}

// MARK: - SearchProductGrid

/// A lazy two-column grid of ``ProductCardView``s (one column at accessibility text sizes),
/// each a button with the identifier `product.card.<handle>`, with image prefetching.
struct SearchProductGrid: View {
    let products: [ProductSummary]
    let onSelect: @MainActor (ProductSummary) -> Void
    let onAppear: @MainActor (ProductSummary) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.displayScale) private var displayScale
    @State private var prefetcher = ProductImagePrefetcher()
    @State private var width: CGFloat = 0

    private var columnCount: Int {
        dynamicTypeSize.isAccessibilitySize ? 1 : 2
    }

    private var columnWidth: CGFloat {
        let spacing = KXSpacing.m * CGFloat(columnCount - 1)
        return max((width - spacing) / CGFloat(columnCount), 0)
    }

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: KXSpacing.m, alignment: .top), count: columnCount),
            alignment: .leading,
            spacing: KXSpacing.l
        ) {
            ForEach(products) { product in
                Button {
                    onSelect(product)
                } label: {
                    ProductCardView(product)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("product.card.\(product.handle)")
                .onAppear {
                    onAppear(product)
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { newWidth in
            width = newWidth
        }
        .task(id: PrefetchKey(count: products.count, width: columnWidth)) {
            guard columnWidth > 0 else { return }
            prefetcher.prefetch(products.map(\.featuredImage), pointWidth: columnWidth, scale: displayScale)
        }
    }

    /// Restarts the prefetch when a page arrives or the column width changes.
    private struct PrefetchKey: Hashable {
        let count: Int
        let width: CGFloat
    }
}

// MARK: - SearchResultsSkeleton

/// The loading placeholder of the result screens: a line and four card skeletons.
struct SearchResultsSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.l) {
            KXSkeleton()
                .frame(width: 160, height: KXSpacing.m)
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: KXSpacing.m), GridItem(.flexible(), spacing: KXSpacing.m)],
                spacing: KXSpacing.l
            ) {
                ForEach(0..<4, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: KXSpacing.xs) {
                        KXSkeleton(cornerRadius: KXRadius.card)
                            .aspectRatio(1, contentMode: .fit)
                        KXSkeleton()
                            .frame(height: KXSpacing.m)
                        KXSkeleton()
                            .frame(height: KXSpacing.m)
                            .padding(.trailing, KXSpacing.xl)
                    }
                }
            }
        }
        .padding(.horizontal, KXSpacing.gutter)
        .padding(.top, KXSpacing.s)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("search.loading", bundle: .module))
    }
}
