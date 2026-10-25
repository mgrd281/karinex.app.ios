import CommerceUI
import Core
import DesignSystem
import ShopifyKit
import SwiftUI

// MARK: - SearchView

/// The Suche tab: a search field with predictive results as you type (products, collections,
/// articles and query suggestions), the recent searches (the last 8, clearable), suggested
/// queries and category shortcuts while the field is empty, and a "nothing found" state with the
/// same shortcuts.
///
/// Submitting a search records it and asks for ``CommerceRoute/search(query:)``, which the App
/// maps to ``SearchResultsScreen``. Every other tap asks for a product, collection or article
/// route.
///
/// Place it inside a `NavigationStack`; it uses a large title and the navigation bar search
/// field.
public struct SearchView: View {
    private let onRoute: @MainActor (CommerceRoute) -> Void

    @State private var model: SearchViewModel
    @State private var query = ""

    /// Creates the search screen.
    ///
    /// - Parameters:
    ///   - search: Runs the predictive search.
    ///   - preferences: Stores the recent searches on the device.
    ///   - onRoute: Called with the destination of a tap or a submitted search.
    public init(
        search: any SearchRepository,
        preferences: any KeyValueStore,
        onRoute: @escaping @MainActor (CommerceRoute) -> Void
    ) {
        _model = State(initialValue: SearchViewModel(search: search, preferences: preferences))
        self.onRoute = onRoute
    }

    public var body: some View {
        Group {
            if model.activeQuery.isEmpty {
                ScrollView {
                    SearchIdleContent(
                        recentSearches: model.recentSearches,
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
        .navigationBarTitleDisplayMode(.large)
        .searchable(
            text: $query,
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

/// What the search screen shows while the field is empty: recent searches, suggested queries
/// and category shortcuts.
private struct SearchIdleContent: View {
    let recentSearches: [String]
    let onSearch: @MainActor (String) -> Void
    let onRemoveRecent: @MainActor (String) -> Void
    let onClearRecent: @MainActor () -> Void
    let onCategory: @MainActor (SearchCategoryShortcut) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.xl) {
            if !recentSearches.isEmpty {
                recentSection
            }
            VStack(alignment: .leading, spacing: KXSpacing.s) {
                SearchSectionTitle(title: String(localized: "search.suggested.title", bundle: .module))
                SearchFlowLayout(spacing: KXSpacing.xs) {
                    ForEach(SearchSuggestion.allCases) { suggestion in
                        SearchChip(title: suggestion.query, systemImage: "magnifyingglass") {
                            onSearch(suggestion.query)
                        }
                        .accessibilityIdentifier("search.suggestion.\(suggestion.id)")
                    }
                }
            }
            VStack(alignment: .leading, spacing: KXSpacing.s) {
                SearchSectionTitle(title: String(localized: "search.categories.title", bundle: .module))
                SearchCategoryGrid(onSelect: onCategory)
            }
        }
        .padding(.horizontal, KXSpacing.gutter)
        .padding(.top, KXSpacing.m)
        .padding(.bottom, KXSpacing.xl)
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: KXSpacing.s) {
            SearchSectionTitle(
                title: String(localized: "search.recent.title", bundle: .module),
                actionTitle: String(localized: "search.recent.clear", bundle: .module),
                action: onClearRecent
            )
            .accessibilityIdentifier("search.recent")
            KXCard(padding: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(recentSearches, id: \.self) { recent in
                        SearchListRow(systemImage: "clock.arrow.circlepath", title: recent, detail: nil) {
                            onSearch(recent)
                        }
                        .accessibilityAction(named: Text("search.recent.remove", bundle: .module)) {
                            onRemoveRecent(recent)
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                onRemoveRecent(recent)
                            } label: {
                                Label {
                                    Text("search.recent.remove", bundle: .module)
                                } icon: {
                                    Image(systemName: "trash")
                                }
                            }
                        }
                        if recent != recentSearches.last {
                            KXDivider()
                                .padding(.leading, KXSpacing.m)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Predictive content

/// The predictive results for the typed text, in the order products, collections, articles and
/// query suggestions, or the "nothing found" state with category shortcuts.
private struct SearchPredictiveContent: View {
    let query: String
    let result: PredictiveSearchResult
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
                SearchSectionTitle(title: String(localized: "search.categories.title", bundle: .module))
                SearchCategoryGrid(onSelect: onCategory)
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
