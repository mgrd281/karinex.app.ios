import CommerceUI
import Core
import DesignSystem
import ShopifyKit
import SwiftUI

// MARK: - SearchView

/// The Suche tab, laid out like the search screen of a fashion retail app: the search field
/// with predictive results as you type (products, collections, articles and query suggestions);
/// while the field is empty the recent searches (the last 8) as removable chips, suggested
/// queries as chips and the category tiles with a real product photo each, separated by light
/// grey bands; and a "nothing found" state with the same tiles.
///
/// Submitting a search records it and asks for ``CommerceRoute/search(query:)``, which the App
/// maps to ``SearchResultsScreen``. Every other tap asks for a product, collection or article
/// route.
///
/// Place it inside a `NavigationStack`; it uses an inline title and the navigation bar search
/// field.
public struct SearchView: View {
    private let catalog: (any CatalogRepository)?
    private let fieldActivation: Int
    private let onRoute: @MainActor (CommerceRoute) -> Void

    @State private var model: SearchViewModel
    @State private var categoryImages = SearchCategoryImages()
    @State private var query = ""
    @State private var isFieldActive = false
    /// The last `fieldActivation` that put the cursor into the field.
    @State private var handledFieldActivation = 0

    /// Creates the search screen.
    ///
    /// - Parameters:
    ///   - search: Runs the predictive search.
    ///   - preferences: Stores the recent searches on the device.
    ///   - catalog: Loads one product photo per category tile; `nil` shows the symbols only.
    ///   - fieldActivation: Counts the requests to start typing, for example from the search
    ///     field of the Start tab. Every new value puts the cursor into the search field.
    ///   - onRoute: Called with the destination of a tap or a submitted search.
    public init(
        search: any SearchRepository,
        preferences: any KeyValueStore,
        catalog: (any CatalogRepository)? = nil,
        fieldActivation: Int = 0,
        onRoute: @escaping @MainActor (CommerceRoute) -> Void
    ) {
        _model = State(initialValue: SearchViewModel(search: search, preferences: preferences))
        self.catalog = catalog
        self.fieldActivation = fieldActivation
        self.onRoute = onRoute
    }

    public var body: some View {
        Group {
            if model.activeQuery.isEmpty {
                ScrollView {
                    SearchIdleContent(
                        recentSearches: model.recentSearches,
                        categoryImages: categoryImages.images,
                        onSearch: submit,
                        onRemoveRecent: { model.removeRecent($0) },
                        onClearRecent: { model.clearRecent() },
                        onCategory: openCategory
                    )
                }
                .scrollDismissesKeyboard(.immediately)
            } else {
                AsyncContentView(
                    model.predictive,
                    retry: { await model.retry() },
                    content: { result in
                        ScrollView {
                            SearchPredictiveContent(
                                query: model.activeQuery,
                                result: result,
                                categoryImages: categoryImages.images,
                                onSearch: submit,
                                onRoute: onRoute,
                                onCategory: openCategory
                            )
                        }
                        .scrollDismissesKeyboard(.immediately)
                    },
                    placeholder: {
                        SearchResultsSkeleton()
                    }
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.search")
        .kxScreenBackground()
        .navigationTitle(Text("search.title", bundle: .module))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $query,
            isPresented: $isFieldActive,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: Text("search.prompt", bundle: .module)
        )
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .onSubmit(of: .search) {
            submit(query)
        }
        .onChange(of: query) { _, newValue in
            model.queryChanged(newValue)
        }
        .task {
            if let catalog {
                await categoryImages.loadIfNeeded(from: catalog)
            }
        }
        .task(id: fieldActivation) {
            guard fieldActivation != handledFieldActivation else { return }
            handledFieldActivation = fieldActivation
            // Let the navigation bar with the field reach the screen first.
            await Task.yield()
            isFieldActive = true
        }
    }

    private func submit(_ text: String) {
        guard let submitted = model.submit(text) else { return }
        if query != submitted {
            query = submitted
        }
        onRoute(.search(query: submitted))
    }

    private func openCategory(_ shortcut: SearchCategoryShortcut) {
        onRoute(.collection(handle: shortcut.handle, title: shortcut.title))
    }
}

// MARK: - Idle content

/// What the search screen shows while the field is empty, in sections separated by light grey
/// bands: the recent searches as removable chips, the suggested queries as chips and the
/// category tiles.
private struct SearchIdleContent: View {
    let recentSearches: [String]
    let categoryImages: [String: ShopifyImage]
    let onSearch: @MainActor (String) -> Void
    let onRemoveRecent: @MainActor (String) -> Void
    let onClearRecent: @MainActor () -> Void
    let onCategory: @MainActor (SearchCategoryShortcut) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !recentSearches.isEmpty {
                recentSection
                SearchSectionBand()
            }
            VStack(alignment: .leading, spacing: KXSpacing.xs) {
                SearchSectionTitle(title: String(localized: "search.suggested.title", bundle: .module), systemImage: "sparkles")
                    .padding(.horizontal, KXSpacing.gutter)
                SearchChipRow {
                    ForEach(SearchSuggestion.allCases) { suggestion in
                        SearchChip(title: suggestion.query) {
                            onSearch(suggestion.query)
                        }
                        .accessibilityIdentifier("search.suggestion.\(suggestion.id)")
                    }
                }
            }
            .padding(.vertical, KXSpacing.l)
            SearchSectionBand()
            VStack(alignment: .leading, spacing: KXSpacing.s) {
                SearchSectionTitle(title: String(localized: "search.categories.title", bundle: .module), systemImage: "square.grid.2x2")
                SearchCategoryGrid(images: categoryImages, onSelect: onCategory)
            }
            .padding(.horizontal, KXSpacing.gutter)
            .padding(.top, KXSpacing.l)
            .padding(.bottom, KXSpacing.xl)
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: KXSpacing.xs) {
            SearchSectionTitle(
                title: String(localized: "search.recent.title", bundle: .module),
                systemImage: "clock",
                actionTitle: String(localized: "search.recent.clear", bundle: .module),
                action: onClearRecent
            )
            .padding(.horizontal, KXSpacing.gutter)
            .accessibilityIdentifier("search.recent")
            SearchChipRow {
                ForEach(recentSearches, id: \.self) { recent in
                    SearchChip(
                        title: recent,
                        onRemove: { onRemoveRecent(recent) },
                        action: { onSearch(recent) }
                    )
                }
            }
        }
        .padding(.vertical, KXSpacing.l)
    }
}

// MARK: - Predictive content

/// The predictive results for the typed text, in the order products, collections, articles and
/// query suggestions, or the "nothing found" state with category shortcuts.
private struct SearchPredictiveContent: View {
    let query: String
    let result: PredictiveSearchResult
    let categoryImages: [String: ShopifyImage]
    let onSearch: @MainActor (String) -> Void
    let onRoute: @MainActor (CommerceRoute) -> Void
    let onCategory: @MainActor (SearchCategoryShortcut) -> Void

    var body: some View {
        if result.isEmpty {
            noResults
        } else {
            VStack(alignment: .leading, spacing: KXSpacing.xl) {
                if !result.products.isEmpty {
                    VStack(alignment: .leading, spacing: KXSpacing.s) {
                        SearchSectionTitle(
                            title: String(localized: "search.section.products", bundle: .module),
                            actionTitle: String(localized: "search.show_all_results", bundle: .module),
                            action: { onSearch(query) }
                        )
                        .padding(.horizontal, KXSpacing.gutter)
                        ProductRow(products: result.products) { product in
                            onRoute(.product(handle: product.handle))
                        }
                    }
                }
                VStack(alignment: .leading, spacing: KXSpacing.xl) {
                    if !result.collections.isEmpty {
                        SearchListCard(
                            title: String(localized: "search.section.collections", bundle: .module),
                            items: result.collections
                        ) { collection in
                            SearchListRow(systemImage: "square.grid.2x2", title: collection.title, detail: nil) {
                                onRoute(.collection(handle: collection.handle, title: collection.title))
                            }
                            .accessibilityIdentifier("search.collection.\(collection.handle)")
                        }
                    }
                    if !result.articles.isEmpty {
                        SearchListCard(
                            title: String(localized: "search.section.articles", bundle: .module),
                            items: result.articles
                        ) { article in
                            SearchListRow(systemImage: "book.pages", title: article.title, detail: article.excerpt) {
                                onRoute(.article(blogHandle: article.blogHandle, articleHandle: article.handle))
                            }
                            .accessibilityIdentifier("search.article.\(article.handle)")
                        }
                    }
                    if !result.queries.isEmpty {
                        SearchListCard(
                            title: String(localized: "search.section.suggestions", bundle: .module),
                            items: result.queries
                        ) { suggestion in
                            SearchListRow(systemImage: "magnifyingglass", title: suggestion.text, detail: nil) {
                                onSearch(suggestion.text)
                            }
                        }
                    }
                }
                .padding(.horizontal, KXSpacing.gutter)
            }
            .padding(.top, KXSpacing.m)
            .padding(.bottom, KXSpacing.xl)
        }
    }

    private var noResults: some View {
        VStack(alignment: .leading, spacing: KXSpacing.l) {
            KXEmptyState(
                systemImage: "magnifyingglass",
                title: String(localized: "search.no_results.title", bundle: .module),
                message: String(localized: "search.no_results.message \(query)", bundle: .module)
            )
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("state.empty")
            VStack(alignment: .leading, spacing: KXSpacing.s) {
                SearchSectionTitle(title: String(localized: "search.categories.title", bundle: .module), systemImage: "square.grid.2x2")
                SearchCategoryGrid(images: categoryImages, onSelect: onCategory)
            }
            .padding(.horizontal, KXSpacing.gutter)
        }
        .padding(.bottom, KXSpacing.xl)
    }
}

// MARK: - SearchFlowLayout

/// Places its subviews in rows from leading to trailing and wraps to the next row when a row is
/// full, for chips of different widths.
struct SearchFlowLayout: Layout {
    /// The horizontal and vertical gap between subviews.
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let rows = arrange(subviews: subviews, maxWidth: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews: subviews, maxWidth: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
                subviews[index].place(
                    at: CGPoint(x: x, y: y),
                    proposal: ProposedViewSize(width: min(size.width, bounds.width), height: size.height)
                )
                x += min(size.width, bounds.width) + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
            let itemWidth = min(size.width, maxWidth)
            let proposedWidth = current.indices.isEmpty ? itemWidth : current.width + spacing + itemWidth
            if proposedWidth > maxWidth, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? itemWidth : current.width + spacing + itemWidth
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty {
            rows.append(current)
        }
        return rows
    }
}

// MARK: - Previews

#if DEBUG
#Preview("SearchView, light") {
    NavigationStack {
        SearchView(search: SearchPreviewRepository(), preferences: InMemoryKeyValueStore(), onRoute: { _ in })
    }
}

#Preview("SearchView, dark") {
    NavigationStack {
        SearchView(search: SearchPreviewRepository(), preferences: InMemoryKeyValueStore(), onRoute: { _ in })
    }
    .preferredColorScheme(.dark)
}

#Preview("SearchView, accessibility size") {
    NavigationStack {
        SearchView(search: SearchPreviewRepository(), preferences: InMemoryKeyValueStore(), onRoute: { _ in })
    }
    .dynamicTypeSize(.accessibility2)
}
#endif
