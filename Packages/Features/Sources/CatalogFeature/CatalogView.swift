import CommerceUI
import DesignSystem
import ShopifyKit
import SwiftUI

// MARK: - CatalogView

/// The Shop tab, laid out like the category pages of fashion retail apps: the bestsellers and
/// the sale as two large cards, the product families as rows with the photo of their first
/// product, the single versions as chips with a photo and every other collection as a list
/// (``CatalogDirectory``). The names come from ``CollectionNames``, so the store's search engine
/// titles never show. A tap asks for ``CommerceRoute/collection(handle:title:)``.
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

/// The loaded Shop tab, section by section.
private struct CatalogDirectoryContent: View {
    let sections: CatalogSections
    let onRoute: @MainActor (CommerceRoute) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.xxl) {
            if !sections.highlights.isEmpty {
                // Side by side with equal heights; stacked at the largest text sizes.
                highlightLayout {
                    ForEach(sections.highlights) { collection in
                        collectionButton(collection) {
                            CatalogHighlightCard(collection: collection)
                        }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            if !sections.categories.isEmpty {
                VStack(alignment: .leading, spacing: KXSpacing.m) {
                    KXSectionHeader(
                        String(localized: "catalog.featured.title", bundle: .module),
                        eyebrow: String(localized: "catalog.featured.eyebrow", bundle: .module)
                    )
                    VStack(spacing: KXSpacing.xs) {
                        ForEach(sections.categories) { collection in
                            collectionButton(collection) {
                                CatalogCategoryRow(collection: collection)
                            }
                        }
                    }
                }
            }
            if !sections.versions.isEmpty {
                VStack(alignment: .leading, spacing: KXSpacing.m) {
                    KXSectionHeader(
                        String(localized: "catalog.versions.title", bundle: .module),
                        eyebrow: String(localized: "catalog.versions.eyebrow", bundle: .module)
                    )
                    KXFlowLayout(spacing: KXSpacing.xs) {
                        ForEach(sections.versions) { collection in
                            collectionButton(collection) {
                                CatalogVersionChip(collection: collection)
                            }
                        }
                    }
                }
            }
            if !sections.more.isEmpty {
                moreCollections
            }
        }
        .padding(.horizontal, KXSpacing.gutter)
        .padding(.top, KXSpacing.s)
        .padding(.bottom, KXSpacing.xl)
    }

    /// Every other collection as a list in one card.
    private var moreCollections: some View {
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

    private var highlightLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: KXSpacing.s))
            : AnyLayout(HStackLayout(alignment: .top, spacing: KXSpacing.s))
    }

    /// A card, row or chip that opens `collection` and shrinks a little while pressed.
    private func collectionButton(_ collection: CollectionSummary, @ViewBuilder label: () -> some View) -> some View {
        Button {
            open(collection)
        } label: {
            label()
        }
        .buttonStyle(.kxPress)
        .accessibilityHint(Text("catalog.collection.hint", bundle: .module))
        .accessibilityIdentifier("catalog.collection.\(collection.handle)")
    }

    private func open(_ collection: CollectionSummary) {
        onRoute(.collection(handle: collection.handle, title: CollectionNames.title(for: collection)))
    }
}

// MARK: - Highlight card

/// A large card on top of the Shop tab: the photo of the collection's first product on its light
/// tile, the name and an invitation ("Jetzt entdecken") with an arrow. The bestsellers card is
/// ink, the sale card sale red with its name in capitals.
private struct CatalogHighlightCard: View {
    let collection: CollectionSummary

    private var isSale: Bool {
        CatalogDirectory.isSale(collection.handle)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: KXRadius.large, style: .continuous)
        VStack(alignment: .leading, spacing: KXSpacing.s) {
            ProductImage(collection.displayImage, isDecorative: true)
                .padding(KXSpacing.m)
                .kxPhotoTile()
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: KXRadius.medium, style: .continuous))
            VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                Text(CollectionNames.title(for: collection))
                    // Before kxFont, whose own text case would otherwise win.
                    .textCase(isSale ? .uppercase : nil)
                    .kxFont(.title2)
                    .lineLimit(2)
                if let action = CatalogDirectory.highlightAction(for: collection.handle) {
                    HStack(spacing: KXSpacing.xxs) {
                        Text(action)
                        Image(systemName: "arrow.right")
                            .accessibilityHidden(true)
                    }
                    .fontWeight(.medium)
                    .kxFont(.subheadline)
                }
            }
            .foregroundStyle(isSale ? KXColor.textOnUrgency : KXColor.textOnAccent)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, KXSpacing.xxs)
            .padding(.bottom, KXSpacing.xxs)
        }
        .padding(KXSpacing.s)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(isSale ? KXColor.urgency : KXColor.accent, in: shape)
        .contentShape(shape)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Category row

/// A product family: the bold name with its short line on the left, the photo of the
/// collection's first product on the right, on a light grey panel.
private struct CatalogCategoryRow: View {
    let collection: CollectionSummary

    @ScaledMetric(relativeTo: .title3) private var scaledPhotoSide: CGFloat = 76

    private var photoSide: CGFloat {
        min(scaledPhotoSide, 120)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: KXRadius.medium, style: .continuous)
        HStack(spacing: KXSpacing.m) {
            VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                Text(CollectionNames.title(for: collection))
                    .kxFont(.title3)
                    .foregroundStyle(KXColor.textPrimary)
                if let detail = CatalogDirectory.detail(for: collection.handle) {
                    Text(detail)
                        .kxFont(.subheadline)
                        .foregroundStyle(KXColor.textSecondary)
                }
            }
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            ProductImage(collection.displayImage, isDecorative: true)
                .padding(KXSpacing.xs)
                .kxPhotoTile()
                .frame(width: photoSide, height: photoSide)
                .clipShape(RoundedRectangle(cornerRadius: KXRadius.small, style: .continuous))
        }
        .padding(.leading, KXSpacing.m)
        .padding(.trailing, KXSpacing.s)
        .padding(.vertical, KXSpacing.s)
        .frame(maxWidth: .infinity)
        .background(KXColor.surface, in: shape)
        .contentShape(shape)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Version chip

/// A single version: the photo of its first product in a small circle and the name, in a light
/// grey capsule.
private struct CatalogVersionChip: View {
    let collection: CollectionSummary

    @ScaledMetric(relativeTo: .subheadline) private var photoDiameter: CGFloat = 32

    var body: some View {
        let shape = Capsule(style: .continuous)
        HStack(spacing: KXSpacing.xs) {
            ProductImage(collection.displayImage, isDecorative: true)
                .padding(KXSpacing.xxs)
                .kxPhotoTile()
                .frame(width: photoDiameter, height: photoDiameter)
                .clipShape(Circle())
            Text(CollectionNames.title(for: collection))
                .fontWeight(.semibold)
                .kxFont(.subheadline)
                .foregroundStyle(KXColor.textPrimary)
                .multilineTextAlignment(.leading)
        }
        .padding(.leading, KXSpacing.xxs)
        .padding(.trailing, KXSpacing.s)
        .padding(.vertical, KXSpacing.xxs)
        .frame(minHeight: KXSpacing.minimumTapTarget)
        .background(KXColor.surface, in: shape)
        .contentShape(shape)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Row

/// A further collection: the photo of its first product, the name and a chevron, at least 44 pt
/// high.
private struct CatalogCollectionRow: View {
    let collection: CollectionSummary

    @ScaledMetric(relativeTo: .body) private var photoSide: CGFloat = 40

    var body: some View {
        HStack(spacing: KXSpacing.s) {
            ProductImage(collection.displayImage, isDecorative: true)
                .padding(KXSpacing.xxs)
                .kxPhotoTile()
                .frame(width: photoSide, height: photoSide)
                .clipShape(RoundedRectangle(cornerRadius: KXRadius.small, style: .continuous))
            Text(CollectionNames.title(for: collection))
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
        .padding(.vertical, KXSpacing.xs)
        .frame(minHeight: KXSpacing.minimumTapTarget)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Skeleton

/// The loading placeholder of the Shop tab: the two cards, a header and four rows.
private struct CatalogSkeleton: View {
    @ScaledMetric(relativeTo: .title3) private var rowHeight: CGFloat = 100

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.xxl) {
            HStack(spacing: KXSpacing.s) {
                ForEach(0..<2, id: \.self) { _ in
                    KXSkeleton(cornerRadius: KXRadius.large)
                        .aspectRatio(0.78, contentMode: .fit)
                }
            }
            VStack(alignment: .leading, spacing: KXSpacing.m) {
                KXSkeleton()
                    .frame(width: 180, height: KXSpacing.l)
                VStack(spacing: KXSpacing.xs) {
                    ForEach(0..<4, id: \.self) { _ in
                        KXSkeleton(cornerRadius: KXRadius.medium)
                            .frame(height: rowHeight)
                    }
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
