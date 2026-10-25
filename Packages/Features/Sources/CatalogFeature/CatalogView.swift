import CommerceUI
import DesignSystem
import ShopifyKit
import SwiftUI

// MARK: - CatalogView

/// The Shop tab: the store's collections, the curated categories (Windows, Office, Server,
/// Entwicklung, Bestseller, Angebote and more) as large tiles first, every other collection as
/// a list below. A tap asks for ``CommerceRoute/collection(handle:title:)``.
///
/// Place it inside a `NavigationStack`; it uses a large title.
///
/// ```swift
/// NavigationStack(path: $path) {
///     CatalogView(catalog: container.catalogRepository, onRoute: { path.append($0) })
/// }
/// ```
public struct CatalogView: View {
    private let onRoute: @MainActor (CommerceRoute) -> Void

    @State private var model: CatalogViewModel

    /// Creates the Shop screen.
    ///
    /// - Parameters:
    ///   - catalog: Loads the collections.
    ///   - onRoute: Called with the collection the user opens.
    public init(catalog: any CatalogRepository, onRoute: @escaping @MainActor (CommerceRoute) -> Void) {
        _model = State(initialValue: CatalogViewModel(catalog: catalog))
        self.onRoute = onRoute
    }

    public var body: some View {
        AsyncContentView(
            model.state,
            empty: AsyncContentEmptyState(
                systemImage: "square.grid.2x2",
                title: String(localized: "catalog.collections.empty.title", bundle: .module),
                message: String(localized: "catalog.collections.empty.message", bundle: .module)
            ),
            retry: { await model.load() },
            content: { sections in
                ScrollView {
                    CatalogDirectoryContent(sections: sections, onRoute: onRoute)
                }
                .refreshable { await model.load() }
            },
            placeholder: {
                ScrollView {
                    CatalogSkeleton()
                }
                .scrollDisabled(true)
            }
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.catalog")
        .kxScreenBackground()
        .navigationTitle(Text("catalog.title", bundle: .module))
        .navigationBarTitleDisplayMode(.large)
        .task {
            if model.state.value == nil {
                await model.load()
            }
        }
    }
}

// MARK: - Content

/// The loaded Shop tab: the curated tiles and the list of further collections.
private struct CatalogDirectoryContent: View {
    let sections: CatalogSections
    let onRoute: @MainActor (CommerceRoute) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.xxl) {
            if !sections.featured.isEmpty {
                VStack(alignment: .leading, spacing: KXSpacing.m) {
                    KXSectionHeader(
                        String(localized: "catalog.featured.title", bundle: .module),
                        eyebrow: String(localized: "catalog.featured.eyebrow", bundle: .module)
                    )
                    LazyVGrid(columns: columns, alignment: .leading, spacing: KXSpacing.m) {
                        ForEach(sections.featured) { collection in
                            Button {
                                open(collection)
                            } label: {
                                CatalogCollectionTile(collection: collection)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint(Text("catalog.collection.hint", bundle: .module))
                            .accessibilityIdentifier("catalog.collection.\(collection.handle)")
                        }
                    }
                }
            }
            if !sections.more.isEmpty {
                VStack(alignment: .leading, spacing: KXSpacing.m) {
                    KXSectionHeader(
                        String(localized: "catalog.more.title", bundle: .module),
                        eyebrow: String(localized: "catalog.more.eyebrow", bundle: .module)
                    )
                    KXCard(padding: 0) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(sections.more) { collection in
                                Button {
                                    open(collection)
                                } label: {
                                    CatalogCollectionRow(collection: collection)
                                }
                                .buttonStyle(.plain)
                                .accessibilityHint(Text("catalog.collection.hint", bundle: .module))
                                .accessibilityIdentifier("catalog.collection.\(collection.handle)")
                                if collection.id != sections.more.last?.id {
                                    KXDivider()
                                        .padding(.leading, KXSpacing.m)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, KXSpacing.gutter)
        .padding(.top, KXSpacing.s)
        .padding(.bottom, KXSpacing.xl)
    }

    private var columns: [GridItem] {
        let count = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        return Array(repeating: GridItem(.flexible(), spacing: KXSpacing.m, alignment: .top), count: count)
    }

    private func open(_ collection: CollectionSummary) {
        onRoute(.collection(handle: collection.handle, title: collection.title))
    }
}

// MARK: - Tile

/// A curated collection: the collection image or a symbol on a white disc, and the bold title,
/// on a light grey panel. The sale collection's symbol, title and arrow are sale red, as fashion
/// retail apps mark their sale.
private struct CatalogCollectionTile: View {
    let collection: CollectionSummary

    /// The color of symbol, title and arrow.
    private var tint: Color {
        CatalogDirectory.isSale(collection.handle) ? KXColor.urgencyText : KXColor.textPrimary
    }

    @ScaledMetric(relativeTo: .title) private var ringDiameter: CGFloat = 48
    @ScaledMetric(relativeTo: .body) private var minimumHeight: CGFloat = 150

    var body: some View {
        KXCard {
            VStack(alignment: .leading, spacing: KXSpacing.m) {
                if let image = collection.image {
                    ProductImage(image, contentMode: .fill, isDecorative: true)
                        .aspectRatio(16 / 10, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: KXRadius.medium, style: .continuous))
                } else {
                    Image(systemName: CatalogDirectory.systemImage(for: collection.handle))
                        .kxFont(.title3)
                        .foregroundStyle(tint)
                        .frame(width: ringDiameter, height: ringDiameter)
                        .background(KXColor.surfaceElevated, in: Circle())
                        .accessibilityHidden(true)
                }
                Spacer(minLength: 0)
                HStack(alignment: .lastTextBaseline, spacing: KXSpacing.xs) {
                    Text(collection.title)
                        .kxFont(.title3)
                        .foregroundStyle(tint)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "arrow.right")
                        .kxFont(.footnote)
                        .foregroundStyle(CatalogDirectory.isSale(collection.handle) ? KXColor.urgencyText : KXColor.accentText)
                        .accessibilityHidden(true)
                }
            }
            .padding(KXSpacing.xxs)
            .frame(maxWidth: .infinity, minHeight: minimumHeight, alignment: .topLeading)
        }
        .contentShape(RoundedRectangle(cornerRadius: KXRadius.card, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Row

/// A further collection: symbol, title and a chevron, at least 44 pt high.
private struct CatalogCollectionRow: View {
    let collection: CollectionSummary

    var body: some View {
        HStack(spacing: KXSpacing.s) {
            Image(systemName: CatalogDirectory.systemImage(for: collection.handle))
                .kxFont(.body)
                .foregroundStyle(KXColor.brand)
                .frame(minWidth: KXSpacing.l)
                .accessibilityHidden(true)
            Text(collection.title)
                .kxFont(.body)
                .foregroundStyle(KXColor.textPrimary)
                .multilineTextAlignment(.leading)
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
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Skeleton

/// The loading placeholder of the Shop tab: a header and six tiles.
private struct CatalogSkeleton: View {
    @ScaledMetric(relativeTo: .body) private var tileHeight: CGFloat = 150

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.m) {
            KXSkeleton()
                .frame(width: 180, height: KXSpacing.l)
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: KXSpacing.m), GridItem(.flexible(), spacing: KXSpacing.m)],
                spacing: KXSpacing.m
            ) {
                ForEach(0..<6, id: \.self) { _ in
                    KXSkeleton(cornerRadius: KXRadius.card)
                        .frame(height: tileHeight)
                }
            }
        }
        .padding(.horizontal, KXSpacing.gutter)
        .padding(.top, KXSpacing.s)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("catalog.loading", bundle: .module))
    }
}

// MARK: - Previews

#if DEBUG
#Preview("CatalogView, light") {
    NavigationStack {
        CatalogView(catalog: CatalogPreviewRepository(), onRoute: { _ in })
    }
}

#Preview("CatalogView, dark") {
    NavigationStack {
        CatalogView(catalog: CatalogPreviewRepository(), onRoute: { _ in })
    }
    .preferredColorScheme(.dark)
}

#Preview("CatalogView, offline, accessibility size") {
    NavigationStack {
        CatalogView(catalog: CatalogPreviewRepository(fails: true), onRoute: { _ in })
    }
    .dynamicTypeSize(.accessibility2)
}
#endif
