import Foundation

// MARK: - CollectionPage

/// One page of a collection: the collection itself, its products and pagination state.
public struct CollectionPage: Sendable, Hashable {
    /// The collection's identity, texts and image.
    public let collection: CollectionSummary
    /// The products of this page.
    public let products: [ProductSummary]
    /// Pagination state; pass `pageInfo.nextPageCursor` as `after` for the next page.
    public let pageInfo: PageInfo

    /// Creates a page.
    public init(collection: CollectionSummary, products: [ProductSummary], pageInfo: PageInfo) {
        self.collection = collection
        self.products = products
        self.pageInfo = pageInfo
    }

    /// Creates a page from a decoded collection. A missing `pageInfo` counts as a single page.
    public init(collection: ProductCollection) {
        self.init(
            collection: collection.summary,
            products: collection.products.nodes,
            pageInfo: collection.products.pageInfo ?? .singlePage
        )
    }
}

// MARK: - CatalogRepository

/// Read access to products and collections in the current buyer context.
public protocol CatalogRepository: Sendable {
    /// The product with `handle`, or `nil` when it does not exist in the current market.
    ///
    /// - Throws: `ShopifyError`.
    func product(handle: String) async throws -> Product?

    /// One page of the collection with `handle`, or `nil` when the collection does not exist.
    ///
    /// - Parameters:
    ///   - handle: The collection handle, e.g. `bestseller`.
    ///   - first: The page size (1 to 250).
    ///   - after: The cursor of the previous page, `nil` for the first page.
    ///   - sortKey: The sort order, `nil` for the collection default.
    ///   - reverse: Whether to reverse the sort order (e.g. price high to low).
    /// - Throws: `ShopifyError`.
    func collection(
        handle: String,
        first: Int,
        after: String?,
        sortKey: ProductCollectionSortKeys?,
        reverse: Bool
    ) async throws -> CollectionPage?
}

extension CatalogRepository {
    /// One page of the collection with `handle` in ascending sort order.
    public func collection(
        handle: String,
        first: Int,
        after: String? = nil,
        sortKey: ProductCollectionSortKeys? = nil
    ) async throws -> CollectionPage? {
        try await collection(handle: handle, first: first, after: after, sortKey: sortKey, reverse: false)
    }
}

// MARK: - StorefrontCatalogRepository

/// `CatalogRepository` backed by the Storefront API.
///
/// Every call uses the context provider's current context, so a market or language change
/// applies to the next request. Metafields are requested only when a Storefront token is
/// configured (tokenless access is denied them).
public final class StorefrontCatalogRepository: CatalogRepository {
    private let client: StorefrontClient
    private let contextProvider: any StorefrontContextProviding

    /// Creates a repository.
    ///
    /// - Parameters:
    ///   - client: The Storefront client.
    ///   - contextProvider: Supplies the buyer context of each call.
    public init(client: StorefrontClient, contextProvider: any StorefrontContextProviding) {
        self.client = client
        self.contextProvider = contextProvider
    }

    /// Loads the product with `handle` in the current context.
    public func product(handle: String) async throws -> Product? {
        let query = ProductByHandleQuery(handle: handle, includeMetafields: !client.isTokenless)
        let context = await contextProvider.currentContext()
        return try await client.execute(query, context: context).product
    }

    /// Loads one page of the collection with `handle` in the current context.
    public func collection(
        handle: String,
        first: Int,
        after: String?,
        sortKey: ProductCollectionSortKeys?,
        reverse: Bool
    ) async throws -> CollectionPage? {
        let query = CollectionProductsQuery(handle: handle, first: first, after: after, sortKey: sortKey, reverse: reverse)
        let context = await contextProvider.currentContext()
        return try await client.execute(query, context: context).collection.map(CollectionPage.init(collection:))
    }
}
