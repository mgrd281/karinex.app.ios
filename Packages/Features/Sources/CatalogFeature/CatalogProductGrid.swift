import CommerceUI
import DesignSystem
import ShopifyKit
import SwiftUI

// MARK: - CatalogProductGrid

/// A lazy grid of ``ProductCardView``s: two columns on iPhone, more on iPad, one at
/// accessibility text sizes.
/// Each card is a button with the identifier `product.card.<handle>`.
///
/// The images of every loaded product are prefetched at the rendered card width as soon as a
/// page arrives, so scrolling down shows them without a skeleton.
struct CatalogProductGrid: View {
    let products: [ProductSummary]
    let onSelect: @MainActor (ProductSummary) -> Void
    let onAppear: @MainActor (ProductSummary) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.displayScale) private var displayScale
    @State private var prefetcher = ProductImagePrefetcher()
    @State private var width: CGFloat = 0

    /// One column at accessibility sizes, else two on iPhone and up to five on wide iPad
    /// layouts (one column per 200 points).
    private var columnCount: Int {
        guard !dynamicTypeSize.isAccessibilitySize else { return 1 }
        return min(max(Int(width / Self.minimumColumnWidth), 2), Self.maximumColumns)
    }

    static let minimumColumnWidth: CGFloat = 200
    static let maximumColumns = 5

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

// MARK: - CatalogProductGridSkeleton

/// The loading placeholder of a product grid: a title line and four card skeletons.
struct CatalogProductGridSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.l) {
            KXSkeleton()
                .frame(width: 220, height: KXSpacing.l)
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
        .accessibilityLabel(Text("catalog.loading", bundle: .module))
    }
}
