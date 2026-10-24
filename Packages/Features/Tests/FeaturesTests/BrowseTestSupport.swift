import Foundation
import ShopifyKit

// MARK: - BrowseFixtures

/// Sample values for the Home, Catalog and Search tests.
enum BrowseFixtures {
    /// A product with `handle`, priced at 10 EUR.
    static func product(_ handle: String) -> ProductSummary {
        let price = MoneyV2(amount: 10, currencyCode: .eur)
        return ProductSummary(
            id: ShopifyID("gid://shopify/Product/\(handle)"),
            handle: handle,
            title: handle,
            vendor: "Microsoft",
            availableForSale: true,
            featuredImage: nil,
            priceRange: PriceRange(minVariantPrice: price, maxVariantPrice: price),
            compareAtPriceRange: PriceRange(minVariantPrice: price, maxVariantPrice: price),
            requiresShipping: false
        )
    }

    /// Products named `prefix-1` to `prefix-count`.
    static func products(_ prefix: String, count: Int) -> [ProductSummary] {
        (0..<count).map { product("\(prefix)-\($0 + 1)") }
    }

    /// A collection summary with `handle` and `title`.
    static func collection(_ handle: String, title: String? = nil) -> CollectionSummary {
        CollectionSummary(
            id: ShopifyID("gid://shopify/Collection/\(handle)"),
            handle: handle,
            title: title ?? handle,
            description: "",
            image: nil
        )
    }

    /// A collection page; `nextCursor` makes it a page with a successor.
    static func page(
        _ handle: String,
        products: [ProductSummary],
        nextCursor: String? = nil,
        filters: [ProductFilter] = []
    ) -> CollectionPage {
        CollectionPage(
            collection: collection(handle),
            products: products,
            pageInfo: PageInfo(hasNextPage: nextCursor != nil, hasPreviousPage: false, startCursor: nil, endCursor: nextCursor),
            filters: filters
        )
    }

    /// A search result page; `nextCursor` makes it a page with a successor.
    static func searchPage(products: [ProductSummary], totalCount: Int, nextCursor: String? = nil) -> SearchResultPage {
        SearchResultPage(
            totalCount: totalCount,
            products: products,
            filters: [],
            pageInfo: PageInfo(hasNextPage: nextCursor != nil, hasPreviousPage: false, startCursor: nil, endCursor: nextCursor)
        )
    }

    /// A guide article with `handle`.
    static func article(_ handle: String, blog: String = "guides") -> ArticleSummary {
        ArticleSummary(
            id: ShopifyID("gid://shopify/Article/\(handle)"),
            handle: handle,
            blogHandle: blog,
            title: handle,
            excerpt: nil,
            publishedAt: Date(timeIntervalSince1970: 1_780_000_000),
            image: nil,
            onlineStoreUrl: nil
        )
    }

    /// The availability filter of the live store with two values.
    static let availabilityFilter = ProductFilter(
        id: "filter.v.availability",
        label: "Verfügbarkeit",
        type: "LIST",
        values: [
            ProductFilterValue(id: "filter.v.availability.1", label: "Auf Lager", count: 12, input: .available(true)),
            ProductFilterValue(id: "filter.v.availability.0", label: "Nicht vorrätig", count: 0, input: .available(false)),
        ]
    )
}

// MARK: - BrowseCollectionRequest

/// One recorded `collection` call of ``BrowseStubCatalogRepository``.
struct BrowseCollectionRequest: Sendable, Hashable {
    let handle: String
    let first: Int
    let after: String?
    let sortKey: ProductCollectionSortKeys
    let reverse: Bool
    let filters: [ProductFilterInput]
}

// MARK: - BrowseStubCatalogRepository

/// A `CatalogRepository` that records every call and answers through closures.
actor BrowseStubCatalogRepository: CatalogRepository {
    typealias CollectionHandler = @Sendable (BrowseCollectionRequest) async throws -> CollectionPage?

    private(set) var collectionRequests: [BrowseCollectionRequest] = []
    private(set) var collectionsRequests: [Int] = []
    private var collectionHandler: CollectionHandler
    private var collectionsHandler: @Sendable () async throws -> [CollectionSummary]

    init(
        collection: @escaping CollectionHandler = { _ in nil },
        collections: @escaping @Sendable () async throws -> [CollectionSummary] = { [] }
    ) {
        collectionHandler = collection
        collectionsHandler = collections
    }

    /// Replaces the collection handler, e.g. to make a retry succeed.
    func setCollectionHandler(_ handler: @escaping CollectionHandler) {
        collectionHandler = handler
    }

    /// The handles requested so far, in request order.
    var requestedHandles: [String] {
        collectionRequests.map(\.handle)
    }

    func product(handle _: String) async throws -> Product? {
        nil
    }

    func collection(
        handle: String,
        first: Int,
        after: String?,
        sortKey: ProductCollectionSortKeys,
        reverse: Bool,
        filters: [ProductFilterInput]
    ) async throws -> CollectionPage? {
        let request = BrowseCollectionRequest(
            handle: handle,
            first: first,
            after: after,
            sortKey: sortKey,
            reverse: reverse,
            filters: filters
        )
        collectionRequests.append(request)
        return try await collectionHandler(request)
    }

    func collections(first: Int) async throws -> [CollectionSummary] {
        collectionsRequests.append(first)
        return try await collectionsHandler()
    }

    func recommendations(productID _: ShopifyID, intent _: ProductRecommendationIntent) async throws -> [ProductSummary] {
        []
    }
}

// MARK: - BrowseStubContentRepository

/// A `ContentRepository` that records the requested blogs and answers through a closure.
actor BrowseStubContentRepository: ContentRepository {
    private(set) var requests: [(blog: String, first: Int)] = []
    private var handler: @Sendable (String) async throws -> [ArticleSummary]

    init(handler: @escaping @Sendable (String) async throws -> [ArticleSummary] = { _ in [] }) {
        self.handler = handler
    }

    /// The requested blog handles and counts, formatted as `blog:first`.
    var requestDescriptions: [String] {
        requests.map { "\($0.blog):\($0.first)" }
    }

    func articles(blogHandle: String, first: Int) async throws -> [ArticleSummary] {
        requests.append((blogHandle, first))
        return try await handler(blogHandle)
    }

    func article(blogHandle _: String, handle _: String) async throws -> Article? {
        nil
    }
}

// MARK: - BrowseSearchRequest

/// One recorded `products` call of ``BrowseStubSearchRepository``.
struct BrowseSearchRequest: Sendable, Hashable {
    let query: String
    let first: Int
    let after: String?
    let sortKey: SearchSortKey
    let reverse: Bool
}

// MARK: - BrowseStubSearchRepository

/// A `SearchRepository` that records every call and answers through closures.
actor BrowseStubSearchRepository: SearchRepository {
    typealias PredictiveHandler = @Sendable (String) async throws -> PredictiveSearchResult
    typealias ProductsHandler = @Sendable (BrowseSearchRequest) async throws -> SearchResultPage

    private(set) var predictiveQueries: [String] = []
    private(set) var productRequests: [BrowseSearchRequest] = []
    private var predictiveHandler: PredictiveHandler
    private var productsHandler: ProductsHandler

    init(
        predictive: @escaping PredictiveHandler = { _ in .empty },
        products: @escaping ProductsHandler = { _ in .empty }
    ) {
        predictiveHandler = predictive
        productsHandler = products
    }

    /// Replaces the predictive handler, e.g. to make a retry succeed.
    func setPredictiveHandler(_ handler: @escaping PredictiveHandler) {
        predictiveHandler = handler
    }

    func predictive(query: String, limit _: Int) async throws -> PredictiveSearchResult {
        predictiveQueries.append(query)
        return try await predictiveHandler(query)
    }

    func products(
        query: String,
        first: Int,
        after: String?,
        sortKey: SearchSortKey,
        reverse: Bool,
        filters _: [ProductFilterInput]
    ) async throws -> SearchResultPage {
        let request = BrowseSearchRequest(query: query, first: first, after: after, sortKey: sortKey, reverse: reverse)
        productRequests.append(request)
        return try await productsHandler(request)
    }
}
