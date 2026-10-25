import CommerceUI
import Foundation
import Observation
import ShopifyKit

// MARK: - SearchResults

/// Every product found so far for a query, with the total count and the pagination state of
/// the last page.
struct SearchResults: Sendable, Hashable {
    /// The number of matching products over all pages, as reported by Shopify.
    let totalCount: Int
    /// The products of every page loaded so far, without duplicates.
    let products: [ProductSummary]
    /// The pagination state of the last loaded page.
    let pageInfo: PageInfo

    /// The results of a first page.
    init(page: SearchResultPage) {
        totalCount = page.totalCount
        products = page.products
        pageInfo = page.pageInfo
    }

    private init(totalCount: Int, products: [ProductSummary], pageInfo: PageInfo) {
        self.totalCount = totalCount
        self.products = products
        self.pageInfo = pageInfo
    }

    /// The results with the products of `page` appended (products already shown are skipped).
    func appending(_ page: SearchResultPage) -> SearchResults {
        let known = Set(products.map(\.id))
        let added = page.products.filter { !known.contains($0.id) }
        return SearchResults(totalCount: totalCount, products: products + added, pageInfo: page.pageInfo)
    }

    /// Whether another page can be requested.
    var hasMore: Bool {
        pageInfo.nextPageCursor != nil
    }
}

// MARK: - SearchResultsViewModel

/// Loads the full search results for one query page by page, with a sort order.
///
/// Changing the sort order reloads the first page while the current products stay visible; an
/// answer that arrives after a newer request was started is dropped.
@MainActor
@Observable
final class SearchResultsViewModel {
    /// The number of products per page.
    static let pageSize = 24
    /// How close to the end of the list (in products) the next page is requested.
    static let prefetchDistance = 6

    /// The search text.
    let query: String

    /// The load state. Nothing found is a loaded value without products, so the screen can
    /// offer category shortcuts.
    private(set) var state: LoadState<SearchResults> = .idle
    /// The chosen sort order.
    private(set) var sort: SearchResultSortOption = .relevance
    /// Whether the first page is reloading while results are shown.
    private(set) var isReloading = false
    /// Why the last reload failed while results were shown, if it did.
    private(set) var reloadError: UserFacingError?
    /// Whether the next page is loading.
    private(set) var isLoadingMore = false
    /// Why the next page failed, if it did.
    private(set) var loadMoreError: UserFacingError?

    @ObservationIgnored private let search: any SearchRepository
    @ObservationIgnored private var generation = 0

    /// Creates the model; nothing is requested before ``load()``.
    init(query: String, search: any SearchRepository) {
        self.query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        self.search = search
    }

    /// Loads the first page with the current sort order.
    func load() async {
        generation += 1
        let current = generation
        if state.value == nil {
            state = .loading
        } else {
            isReloading = true
        }
        isLoadingMore = false
        loadMoreError = nil
        reloadError = nil
        do {
            let page = try await search.products(
                query: query,
                first: Self.pageSize,
                after: nil,
                sortKey: sort.sortKey,
                reverse: sort.reverse,
                filters: []
            )
            guard current == generation else { return }
            isReloading = false
            state = .loaded(SearchResults(page: page))
        } catch {
            guard current == generation else { return }
            isReloading = false
            guard let failure = UserFacingError(error) else {
                if state.isLoading {
                    state = .idle
                }
                return
            }
            if state.value == nil {
                state = .failed(failure)
            } else {
                reloadError = failure
            }
        }
    }

    /// Chooses a sort order and reloads; does nothing when it is already chosen.
    func setSort(_ option: SearchResultSortOption) async {
        guard option != sort else { return }
        sort = option
        await load()
    }

    /// Loads the next page when `product` is one of the last ``prefetchDistance`` products.
    func loadMoreIfNeeded(after product: ProductSummary) async {
        guard let products = state.value?.products,
              let index = products.lastIndex(where: { $0.id == product.id }),
              index >= products.count - Self.prefetchDistance
        else { return }
        await loadMore()
    }

    /// Appends the next page, if there is one and no other request is running.
    func loadMore() async {
        guard let results = state.value, let cursor = results.pageInfo.nextPageCursor, !isLoadingMore, !isReloading else { return }
        let current = generation
        isLoadingMore = true
        loadMoreError = nil
        do {
            let page = try await search.products(
                query: query,
                first: Self.pageSize,
                after: cursor,
                sortKey: sort.sortKey,
                reverse: sort.reverse,
                filters: []
            )
            guard current == generation else { return }
            isLoadingMore = false
            guard let shown = state.value else { return }
            state = .loaded(shown.appending(page))
        } catch {
            guard current == generation else { return }
            isLoadingMore = false
            loadMoreError = UserFacingError(error)
        }
    }
}
