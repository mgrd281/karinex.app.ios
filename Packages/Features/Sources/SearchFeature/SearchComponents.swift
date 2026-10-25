import CommerceUI
import DesignSystem
import Observation
import ShopifyKit
import SwiftUI

// MARK: - SearchCategoryGrid

/// The category shortcuts in the style of fashion retail apps: two columns of light grey tiles,
/// each with the bold category name on the leading side and the photo of a product of that
/// collection on the trailing side (the collection's symbol until the photo has loaded, or when
/// the collection has no product).
struct SearchCategoryGrid: View {
    /// A product photo per collection handle, from ``SearchCategoryImages``.
    let images: [String: ShopifyImage]
    let onSelect: @MainActor (SearchCategoryShortcut) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title3) private var photoSize: CGFloat = 64
    @ScaledMetric(relativeTo: .title3) private var tileHeight: CGFloat = 84

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: KXSpacing.xs) {
            ForEach(SearchCategoryShortcut.allCases) { shortcut in
                Button {
                    onSelect(shortcut)
                } label: {
                    tile(shortcut)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(shortcut.title))
                .accessibilityIdentifier("search.category.\(shortcut.handle)")
            }
        }
    }

    private func tile(_ shortcut: SearchCategoryShortcut) -> some View {
        let shape = RoundedRectangle(cornerRadius: KXRadius.card, style: .continuous)
        return HStack(alignment: .center, spacing: KXSpacing.xs) {
            Text(shortcut.title)
                .kxFont(.title3)
                .foregroundStyle(KXColor.textPrimary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            photo(shortcut)
                .frame(width: min(photoSize, 96), height: min(photoSize, 96))
                .clipShape(RoundedRectangle(cornerRadius: KXRadius.small, style: .continuous))
                .accessibilityHidden(true)
        }
        .padding(.leading, KXSpacing.m)
        .padding(.trailing, KXSpacing.s)
        .padding(.vertical, KXSpacing.s)
        .frame(maxWidth: .infinity, minHeight: tileHeight, alignment: .leading)
        .background(KXColor.surface, in: shape)
        .contentShape(shape)
    }

    @ViewBuilder
    private func photo(_ shortcut: SearchCategoryShortcut) -> some View {
        if let image = images[shortcut.handle] {
            ProductImage(image, isDecorative: true)
                .kxPhotoTile()
        } else {
            Image(systemName: shortcut.systemImage)
                .kxFont(.title2)
                .foregroundStyle(KXColor.iconSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var columns: [GridItem] {
        let count = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        return Array(repeating: GridItem(.flexible(), spacing: KXSpacing.xs, alignment: .top), count: count)
    }
}

// MARK: - SearchCategoryImages

/// Loads one product photo per category shortcut (the first product of each collection), so the
/// category tiles can show real store photos. A failing or empty collection keeps its symbol.
@MainActor
@Observable
final class SearchCategoryImages {
    /// The photo per collection handle; collections without a photo are missing.
    private(set) var images: [String: ShopifyImage] = [:]

    /// Loads the photos once; later calls do nothing.
    func loadIfNeeded(from catalog: any CatalogRepository) async {
        guard images.isEmpty else { return }
        let handles = SearchCategoryShortcut.allCases.map(\.handle)
        let loaded = await withTaskGroup(of: (String, ShopifyImage?).self) { group in
            for handle in handles {
                group.addTask {
                    let page = try? await catalog.collection(handle: handle, first: 1)
                    return (handle, page?.products.first?.featuredImage)
                }
            }
            var result: [String: ShopifyImage] = [:]
            for await (handle, image) in group {
                if let image {
                    result[handle] = image
                }
            }
            return result
        }
        images = loaded
    }
}

// MARK: - SearchChip

/// A grey capsule with a query, used for suggested searches. With `onRemove` it also shows an
/// "x" that removes the query (recent searches).
struct SearchChip: View {
    let title: String
    var onRemove: (@MainActor () -> Void)?
    let action: @MainActor () -> Void

    var body: some View {
        HStack(spacing: KXSpacing.xs) {
            Button {
                action()
            } label: {
                Text(title)
                    .kxFont(.callout)
                    .foregroundStyle(KXColor.textPrimary)
                    .lineLimit(1)
                    .frame(minHeight: KXSpacing.minimumTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if let onRemove {
                Button {
                    onRemove()
                } label: {
                    Image(systemName: "xmark")
                        .kxFont(.subheadline)
                        .foregroundStyle(KXColor.textPrimary)
                        .frame(minWidth: KXSpacing.l, minHeight: KXSpacing.minimumTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("search.recent.remove", bundle: .module))
            }
        }
        .padding(.leading, KXSpacing.m)
        .padding(.trailing, onRemove == nil ? KXSpacing.m : KXSpacing.xs)
        .background(KXColor.surface, in: Capsule(style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

// MARK: - SearchChipRow

/// A horizontally scrolling row of chips, edge to edge with the gutter as content margins.
struct SearchChipRow<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: KXSpacing.xs) {
                content
            }
        }
        .scrollIndicators(.hidden)
        .contentMargins(.horizontal, KXSpacing.gutter, for: .scrollContent)
    }
}

// MARK: - SearchSectionBand

/// The light grey band between the sections of the search screen, edge to edge.
struct SearchSectionBand: View {
    var body: some View {
        KXColor.surface
            .frame(height: KXSpacing.xs)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
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

/// The section title of the search screen: an optional line icon and an uppercase bold title,
/// with an optional trailing text action such as "Löschen".
struct SearchSectionTitle: View {
    let title: String
    var systemImage: String?
    var actionTitle: String?
    var action: (@MainActor () -> Void)?

    var body: some View {
        HStack(alignment: .center, spacing: KXSpacing.s) {
            if let systemImage {
                Image(systemName: systemImage)
                    .kxFont(.title3)
                    .fontWeight(.regular)
                    .foregroundStyle(KXColor.textPrimary)
                    .accessibilityHidden(true)
            }
            Text(title)
                .textCase(.uppercase)
                .fontWeight(.semibold)
                .kxFont(.subheadline)
                .foregroundStyle(KXColor.textPrimary)
                .accessibilityAddTraits(.isHeader)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let actionTitle, let action {
                Button {
                    action()
                } label: {
                    Text(actionTitle)
                        .kxFont(.footnote)
                        .foregroundStyle(KXColor.textSecondary)
                        .frame(minHeight: KXSpacing.minimumTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
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
        let spacing = KXSpacing.xs * CGFloat(columnCount - 1)
        return max((width - spacing) / CGFloat(columnCount), 0)
    }

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: KXSpacing.xs, alignment: .top), count: columnCount),
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
                columns: [GridItem(.flexible(), spacing: KXSpacing.xs), GridItem(.flexible(), spacing: KXSpacing.xs)],
                spacing: KXSpacing.l
            ) {
                ForEach(0..<4, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: KXSpacing.xs) {
                        KXSkeleton(cornerRadius: KXRadius.image)
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
