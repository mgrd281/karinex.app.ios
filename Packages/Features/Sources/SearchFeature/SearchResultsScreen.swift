import CommerceUI
import DesignSystem
import ShopifyKit
import SwiftUI

// MARK: - SearchResultsScreen

/// The full product results for a query: the number of hits, a two-column grid of
/// ``ProductCardView``s with infinite scroll, a sort menu (Relevanz, Preis aufsteigend, Preis
/// absteigend) and pull to refresh. Nothing found shows category shortcuts.
///
/// Push it from a ``CommerceRoute/search(query:)`` route with a non-empty query. A product tap
/// asks for ``CommerceRoute/product(handle:)``, a shortcut for
/// ``CommerceRoute/collection(handle:title:)``.
public struct SearchResultsScreen: View {
    private let onRoute: @MainActor (CommerceRoute) -> Void

    @State private var model: SearchResultsViewModel

    /// Creates the screen.
    ///
    /// - Parameters:
    ///   - query: The search text.
    ///   - search: The search repository.
    ///   - onRoute: Called with the product or collection the user opens.
    public init(query: String, search: any SearchRepository, onRoute: @escaping @MainActor (CommerceRoute) -> Void) {
        _model = State(initialValue: SearchResultsViewModel(query: query, search: search))
        self.onRoute = onRoute
    }

    public var body: some View {
        AsyncContentView(
            model.state,
            retry: { await model.load() },
            content: { results in
                ScrollView {
                    if results.products.isEmpty {
                        noResults
                    } else {
                        loadedContent(results)
                    }
                }
                .refreshable { await model.load() }
            },
            placeholder: {
                SearchResultsSkeleton()
            }
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.searchResults")
        .kxScreenBackground()
        .navigationTitle(Text(verbatim: model.query))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if model.state.value?.products.isEmpty == false {
                ToolbarItem(placement: .primaryAction) {
                    sortMenu
                }
            }
        }
        .task {
            if model.state.value == nil {
                await model.load()
            }
        }
    }

    // MARK: Content

    private func loadedContent(_ results: SearchResults) -> some View {
        VStack(alignment: .leading, spacing: KXSpacing.l) {
            VStack(alignment: .leading, spacing: KXSpacing.s) {
                Text("search.results.count \(results.totalCount)", bundle: .module)
                    .kxFont(.eyebrow)
                    .foregroundStyle(KXColor.textSecondary)
                Text(verbatim: model.query)
                    .kxFont(.title1)
                    .foregroundStyle(KXColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, KXSpacing.gutter)
            if model.isReloading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(Text("search.loading", bundle: .module))
            }
            if let error = model.reloadError {
                KXBanner(.error, message: error.message, action: error.isRetryable ? { Task { await model.load() } } : nil)
                    .padding(.horizontal, KXSpacing.gutter)
            }
            SearchProductGrid(
                products: results.products,
                onSelect: { product in onRoute(.product(handle: product.handle)) },
                onAppear: { product in
                    Task { await model.loadMoreIfNeeded(after: product) }
                }
            )
            .padding(.horizontal, KXSpacing.gutter)
            .opacity(model.isReloading ? 0.5 : 1)
            footer(results)
        }
        .padding(.top, KXSpacing.s)
        .padding(.bottom, KXSpacing.xl)
    }

    @ViewBuilder
    private func footer(_ results: SearchResults) -> some View {
        if model.isLoadingMore {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: KXSpacing.minimumTapTarget)
                .accessibilityLabel(Text("search.loading_more", bundle: .module))
        } else if let error = model.loadMoreError {
            KXBanner(
                .error,
                message: String(localized: "search.load_more.error", bundle: .module),
                action: error.isRetryable ? { Task { await model.loadMore() } } : nil
            )
            .padding(.horizontal, KXSpacing.gutter)
        } else if results.hasMore {
            // The last cards trigger the next page; this keeps the end reachable when a page is
            // shorter than the screen.
            Color.clear
                .frame(height: 1)
                .onAppear {
                    Task { await model.loadMore() }
                }
                .accessibilityHidden(true)
        }
    }

    private var noResults: some View {
        VStack(alignment: .leading, spacing: KXSpacing.l) {
            KXEmptyState(
                systemImage: "magnifyingglass",
                title: String(localized: "search.no_results.title", bundle: .module),
                message: String(localized: "search.no_results.message \(model.query)", bundle: .module)
            )
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("state.empty")
            VStack(alignment: .leading, spacing: KXSpacing.s) {
                SearchSectionTitle(title: String(localized: "search.categories.title", bundle: .module))
                SearchCategoryGrid(images: [:]) { shortcut in
                    onRoute(.collection(handle: shortcut.handle, title: shortcut.title))
                }
            }
            .padding(.horizontal, KXSpacing.gutter)
        }
        .padding(.bottom, KXSpacing.xl)
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
                ForEach(SearchResultSortOption.allCases) { option in
                    Text(option.title)
                        .tag(option)
                }
            } label: {
                Text("search.sort.title", bundle: .module)
            }
            .pickerStyle(.inline)
        } label: {
            Label {
                Text("search.sort.title", bundle: .module)
            } icon: {
                Image(systemName: "arrow.up.arrow.down")
            }
        }
        .accessibilityValue(Text(model.sort.title))
        .accessibilityIdentifier("searchResults.sort")
    }
}

// MARK: - Previews

#if DEBUG
#Preview("SearchResultsScreen, light") {
    NavigationStack {
        SearchResultsScreen(query: "Office", search: SearchPreviewRepository(), onRoute: { _ in })
    }
}

#Preview("SearchResultsScreen, dark") {
    NavigationStack {
        SearchResultsScreen(query: "Office", search: SearchPreviewRepository(), onRoute: { _ in })
    }
    .preferredColorScheme(.dark)
}

#Preview("SearchResultsScreen, nothing found, accessibility size") {
    NavigationStack {
        SearchResultsScreen(query: "Zzz", search: SearchPreviewRepository(), onRoute: { _ in })
    }
    .dynamicTypeSize(.accessibility2)
}
#endif
