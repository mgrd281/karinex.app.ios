import CommerceUI
import DesignSystem
import ShopifyKit
import SwiftUI

// MARK: - CollectionScreen

/// The products of one collection in a two-column grid of ``ProductCardView``s, with a sort
/// menu (Empfohlen, Bestseller, Preis aufsteigend, Preis absteigend, Neueste), a filter sheet
/// built from the store's filters with counts, infinite scroll and pull to refresh.
///
/// Push it from a ``CommerceRoute/collection(handle:title:)`` route. A product tap asks for
/// ``CommerceRoute/product(handle:)``.
public struct CollectionScreen: View {
    private let onRoute: @MainActor (CommerceRoute) -> Void

    @State private var model: CollectionViewModel
    @State private var isFilterSheetPresented = false

    /// Creates the screen.
    ///
    /// - Parameters:
    ///   - handle: The collection handle, e.g. `windows`.
    ///   - title: The title to show until the collection has loaded; deep links have none.
    ///   - catalog: The catalog repository.
    ///   - onRoute: Called with the product the user opens.
    public init(
        handle: String,
        title: String?,
        catalog: any CatalogRepository,
        onRoute: @escaping @MainActor (CommerceRoute) -> Void
    ) {
        _model = State(initialValue: CollectionViewModel(handle: handle, title: title, catalog: catalog))
        self.onRoute = onRoute
    }

    public var body: some View {
        AsyncContentView(
            model.state,
            retry: { await model.load() },
            content: { content in
                ScrollView {
                    loadedContent(content)
                }
                .refreshable { await model.load() }
            },
            placeholder: {
                CatalogProductGridSkeleton()
            }
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.collection")
        .kxScreenBackground()
        .navigationTitle(model.title.map { Text($0) } ?? Text(verbatim: ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if model.state.value != nil {
                ToolbarItemGroup(placement: .primaryAction) {
                    sortMenu
                    filterButton
                }
            }
        }
        .sheet(isPresented: $isFilterSheetPresented) {
            CollectionFilterSheet(
                filters: model.state.value?.filters ?? [],
                selection: model.selection,
                onApply: { selection in
                    Task { await model.apply(selection) }
                }
            )
        }
        .task {
            if model.state.value == nil {
                await model.load()
            }
        }
    }

    // MARK: Content

    private func loadedContent(_ content: CollectionContent) -> some View {
        VStack(alignment: .leading, spacing: KXSpacing.l) {
            CollectionHeader(collection: content.collection, sort: model.sort, filterCount: model.selection.count)
                .padding(.horizontal, KXSpacing.gutter)
            if model.isReloading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(Text("catalog.loading", bundle: .module))
            }
            if let error = model.reloadError {
                KXBanner(.error, message: error.message, action: error.isRetryable ? { Task { await model.load() } } : nil)
                    .padding(.horizontal, KXSpacing.gutter)
            }
            if content.products.isEmpty {
                emptyProducts
            } else {
                CatalogProductGrid(
                    products: content.products,
                    onSelect: { product in onRoute(.product(handle: product.handle)) },
                    onAppear: { product in
                        Task { await model.loadMoreIfNeeded(after: product) }
                    }
                )
                .padding(.horizontal, KXSpacing.gutter)
                .opacity(model.isReloading ? 0.5 : 1)
                footer(content)
            }
        }
        .padding(.top, KXSpacing.s)
        .padding(.bottom, KXSpacing.xl)
    }

    @ViewBuilder
    private func footer(_ content: CollectionContent) -> some View {
        if model.isLoadingMore {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: KXSpacing.minimumTapTarget)
                .accessibilityLabel(Text("catalog.loading_more", bundle: .module))
                .accessibilityIdentifier("collection.loading_more")
        } else if let error = model.loadMoreError {
            KXBanner(
                .error,
                message: String(localized: "catalog.load_more.error", bundle: .module),
                action: error.isRetryable ? { Task { await model.loadMore() } } : nil
            )
            .padding(.horizontal, KXSpacing.gutter)
        } else if content.hasMore {
            // The last cards trigger the next page; this keeps the grid's end reachable when
            // a page is shorter than the screen.
            Color.clear
                .frame(height: 1)
                .onAppear {
                    Task { await model.loadMore() }
                }
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder private var emptyProducts: some View {
        if model.selection.isEmpty {
            KXEmptyState(
                systemImage: "shippingbox",
                title: String(localized: "catalog.collection.empty.title", bundle: .module),
                message: String(localized: "catalog.collection.empty.message", bundle: .module)
            )
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("state.empty")
        } else {
            KXEmptyState(
                systemImage: "line.3.horizontal.decrease.circle",
                title: String(localized: "catalog.collection.filtered_empty.title", bundle: .module),
                message: String(localized: "catalog.collection.filtered_empty.message", bundle: .module),
                actionTitle: String(localized: "catalog.filter.reset_all", bundle: .module),
                action: { Task { await model.resetFilters() } }
            )
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("state.empty")
        }
    }

    // MARK: Toolbar

    private var sortMenu: some View {
        Menu {
            Picker(
                selection: Binding(
                    get: { model.sort },
                    set: { option in Task { await model.setSort(option) } }
                )
            ) {
                ForEach(CollectionSortOption.allCases) { option in
                    Text(option.title)
                        .tag(option)
                }
            } label: {
                Text("catalog.sort.title", bundle: .module)
            }
            .pickerStyle(.inline)
        } label: {
            Label {
                Text("catalog.sort.title", bundle: .module)
            } icon: {
                Image(systemName: "arrow.up.arrow.down")
            }
        }
        .accessibilityValue(Text(model.sort.title))
        .accessibilityIdentifier("collection.sort")
    }

    private var filterButton: some View {
        let count = model.selection.count
        return Button {
            isFilterSheetPresented = true
        } label: {
            Label {
                Text("catalog.filter.title", bundle: .module)
            } icon: {
                Image(systemName: count > 0 ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
            }
        }
        .disabled(model.state.value?.filters.isEmpty ?? true)
        .accessibilityValue(count > 0 ? Text("catalog.filter.active \(count)", bundle: .module) : Text(verbatim: ""))
        .accessibilityIdentifier("collection.filter")
    }
}

// MARK: - CollectionHeader

/// The head of a collection: eyebrow with the sort order and active filters, the bold name
/// (``CollectionNames``) and Shopify's description.
private struct CollectionHeader: View {
    let collection: CollectionSummary
    let sort: CollectionSortOption
    let filterCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.s) {
            Group {
                if filterCount > 0 {
                    Text("catalog.collection.eyebrow.filtered \(sort.title) \(filterCount)", bundle: .module)
                } else {
                    Text(sort.title)
                }
            }
            .kxFont(.eyebrow)
            .foregroundStyle(KXColor.textSecondary)
            Text(CollectionNames.title(for: collection))
                .kxFont(.title1)
                .foregroundStyle(KXColor.textPrimary)
                .accessibilityAddTraits(.isHeader)
            let description = collection.description.trimmingCharacters(in: .whitespacesAndNewlines)
            if !description.isEmpty {
                Text(description)
                    .kxFont(.subheadline)
                    .foregroundStyle(KXColor.textSecondary)
                    .lineLimit(4)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Previews

#if DEBUG
#Preview("CollectionScreen, light") {
    NavigationStack {
        CollectionScreen(handle: "windows", title: "Windows", catalog: CatalogPreviewRepository(), onRoute: { _ in })
    }
}

#Preview("CollectionScreen, dark") {
    NavigationStack {
        CollectionScreen(handle: "windows", title: "Windows", catalog: CatalogPreviewRepository(), onRoute: { _ in })
    }
    .preferredColorScheme(.dark)
}

#Preview("CollectionScreen, offline, accessibility size") {
    NavigationStack {
        CollectionScreen(handle: "windows", title: "Windows", catalog: CatalogPreviewRepository(fails: true), onRoute: { _ in })
    }
    .dynamicTypeSize(.accessibility2)
}
#endif
