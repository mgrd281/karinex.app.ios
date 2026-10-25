import CommerceUI
import Foundation
import Observation
import ShopifyKit

// MARK: - CollectionContent

/// The loaded part of a collection: the collection, every product loaded so far, the filters
/// of the current selection and the pagination state of the last page.
struct CollectionContent: Sendable, Hashable {
    /// The collection's identity, texts and image.
    let collection: CollectionSummary
    /// The products of every page loaded so far, without duplicates.
    let products: [ProductSummary]
    /// The filters the store offers, with counts for the current selection.
    let filters: [ProductFilter]
    /// The pagination state of the last loaded page.
    let pageInfo: PageInfo

    /// The content of a first page.
    init(page: CollectionPage) {
        collection = page.collection
        products = page.products
        filters = page.filters
        pageInfo = page.pageInfo
    }

    private init(collection: CollectionSummary, products: [ProductSummary], filters: [ProductFilter], pageInfo: PageInfo) {
        self.collection = collection
        self.products = products
        self.filters = filters
        self.pageInfo = pageInfo
    }

    /// The content with the products of `page` appended (products already shown are skipped)
    /// and the pagination state of `page`. The filters of the first page are kept.
    func appending(_ page: CollectionPage) -> CollectionContent {
        let known = Set(products.map(\.id))
        let added = page.products.filter { !known.contains($0.id) }
        return CollectionContent(collection: collection, products: products + added, filters: filters, pageInfo: page.pageInfo)
    }

    /// The content marked as complete (no further page).
    func completed() -> CollectionContent {
        CollectionContent(collection: collection, products: products, filters: filters, pageInfo: .singlePage)
    }

    /// Whether another page can be requested.
    var hasMore: Bool {
        pageInfo.nextPageCursor != nil
    }
}

// MARK: - CollectionViewModel

/// Loads a collection page by page with a sort order and filters.
///
/// Changing the sort order or the filters reloads the first page while the current products
/// stay visible; an answer that arrives after a newer request was started is dropped, so the
/// list always matches the latest choice. The next page is requested when the end of the list
/// comes into view (``loadMoreIfNeeded(after:)``).
@MainActor
@Observable
final class CollectionViewModel {
    /// The number of products per page.
    static let pageSize = 24
    /// How close to the end of the list (in products) the next page is requested.
    static let prefetchDistance = 6

    /// The collection handle.
    let handle: String

    /// The load state of the first page and everything appended to it.
    private(set) var state: LoadState<CollectionContent> = .idle
    /// The chosen sort order.
    private(set) var sort: CollectionSortOption = .recommended
    /// The chosen filters.
    private(set) var selection: CollectionFilterSelection = .none
    /// Whether the first page is reloading while content is shown.
    private(set) var isReloading = false
    /// Why the last reload failed while content was shown, if it did.
    private(set) var reloadError: UserFacingError?
    /// Whether the next page is loading.
    private(set) var isLoadingMore = false
    /// Why the next page failed, if it did.
    private(set) var loadMoreError: UserFacingError?

    @ObservationIgnored private let initialTitle: String?
    @ObservationIgnored private let catalog: any CatalogRepository
    @ObservationIgnored private var generation = 0

    /// Creates the model; nothing is requested before ``load()``.
    ///
    /// - Parameters:
    ///   - handle: The collection handle.
    ///   - title: The title to show until the collection has loaded.
    ///   - catalog: The catalog repository.
    init(handle: String, title: String?, catalog: any CatalogRepository) {
        self.handle = handle
        initialTitle = title
        self.catalog = catalog
    }

    /// The collection title: Shopify's once loaded, the given one before.
    var title: String? {
        state.value?.collection.title ?? initialTitle
    }

    // MARK: Loading

    /// Loads the first page with the current sort order and filters.
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
            let page = try await catalog.collection(
                handle: handle,
                first: Self.pageSize,
                after: nil,
                sortKey: sort.sortKey,
                reverse: sort.reverse,
                filters: selection.inputs
            )
            guard current == generation else { return }
            isReloading = false
            if let page {
                state = .loaded(CollectionContent(page: page))
            } else {
                state = .failed(UserFacingError(kind: .notFound))
            }
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
    func setSort(_ option: CollectionSortOption) async {
        guard option != sort else { return }
        sort = option
        await load()
    }

    /// Applies a filter selection and reloads; does nothing when it did not change.
    func apply(_ newSelection: CollectionFilterSelection) async {
        guard newSelection != selection else { return }
        selection = newSelection
        await load()
    }

    /// Removes every filter and reloads.
    func resetFilters() async {
        await apply(.none)
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
        guard let content = state.value, let cursor = content.pageInfo.nextPageCursor, !isLoadingMore, !isReloading else { return }
        let current = generation
        isLoadingMore = true
        loadMoreError = nil
        do {
            let page = try await catalog.collection(
                handle: handle,
                first: Self.pageSize,
                after: cursor,
                sortKey: sort.sortKey,
                reverse: sort.reverse,
                filters: selection.inputs
            )
            guard current == generation else { return }
            isLoadingMore = false
            guard let shown = state.value else { return }
            state = .loaded(page.map { shown.appending($0) } ?? shown.completed())
        } catch {
            guard current == generation else { return }
            isLoadingMore = false
            loadMoreError = UserFacingError(error)
        }
    }
}
