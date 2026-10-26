import Foundation

// MARK: - CollectionPage

/// One page of a collection: the collection itself, its products, the available filters and
/// pagination state.
public struct CollectionPage: Sendable, Hashable {
    /// The collection's identity, texts and image.
    public let collection: CollectionSummary
    /// The products of this page.
    public let products: [ProductSummary]
    /// Pagination state; pass `pageInfo.nextPageCursor` as `after` for the next page.
    public let pageInfo: PageInfo
    /// The filters the store offers for the collection (Search & Discovery), with counts for
    /// the current selection.
    public let filters: [ProductFilter]

    /// Creates a page.
    public init(collection: CollectionSummary, products: [ProductSummary], pageInfo: PageInfo, filters: [ProductFilter] = []) {
        self.collection = collection
        self.products = products
        self.pageInfo = pageInfo
        self.filters = filters
    }

    /// Creates a page from a decoded collection. A missing `pageInfo` counts as a single page.
    public init(collection: ProductCollection) {
        self.init(
            collection: collection.summary,
            products: collection.products.nodes,
            pageInfo: collection.products.pageInfo ?? .singlePage,
            filters: collection.filters
        )
    }
}

// MARK: - CatalogRepository

/// Read access to products, collections, recommendations and the accepted payment methods in
/// the current buyer context.
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
    ///   - sortKey: The sort order, e.g. `.collectionDefault` or `.price`.
    ///   - reverse: Whether to reverse the sort order (e.g. price high to low).
    ///   - filters: The chosen filter values (from `CollectionPage.filters`), empty for none.
    /// - Throws: `ShopifyError`.
    func collection(
        handle: String,
        first: Int,
        after: String?,
        sortKey: ProductCollectionSortKeys,
        reverse: Bool,
        filters: [ProductFilterInput]
    ) async throws -> CollectionPage?

    /// The store's collections, sorted by title, each with the photo of its first product
    /// (``CollectionSummary/previewImage``).
    ///
    /// - Parameter first: The number of collections (1 to 250).
    /// - Throws: `ShopifyError`.
    func collections(first: Int) async throws -> [CollectionSummary]

    /// Shopify's recommendations for the product with `productID`; empty when there are none
    /// or the product does not exist.
    ///
    /// - Throws: `ShopifyError`.
    func recommendations(productID: ShopifyID, intent: ProductRecommendationIntent) async throws -> [ProductSummary]

    /// The card brands and digital wallets the store accepts in the current market (Storefront
    /// `shop.paymentSettings`).
    ///
    /// - Throws: `ShopifyError`.
    func paymentSettings() async throws -> PaymentSettings
}

extension CatalogRepository {
    /// No payment data, for catalogs that do not talk to Shopify (previews and tests). The app
    /// then shows its neutral card symbol next to the business facts.
    public func paymentSettings() async throws -> PaymentSettings {
        .empty
    }

    /// One page of the collection with `handle` without filters: 24 products in the
    /// collection's default order unless specified.
    ///
    /// - Parameters:
    ///   - handle: The collection handle.
    ///   - first: The page size, 24 by default.
    ///   - after: The cursor of the previous page, `nil` for the first page.
    ///   - sortKey: The sort order, `nil` (the default) for `COLLECTION_DEFAULT`.
    ///   - reverse: Whether to reverse the sort order, `false` by default.
    public func collection(
        handle: String,
        first: Int = 24,
        after: String? = nil,
        sortKey: ProductCollectionSortKeys? = nil,
        reverse: Bool = false
    ) async throws -> CollectionPage? {
        try await collection(
            handle: handle,
            first: first,
            after: after,
            sortKey: sortKey ?? .collectionDefault,
            reverse: reverse,
            filters: []
        )
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
        sortKey: ProductCollectionSortKeys,
        reverse: Bool,
        filters: [ProductFilterInput]
    ) async throws -> CollectionPage? {
        let query = CollectionProductsQuery(
            handle: handle,
            first: first,
            after: after,
            sortKey: sortKey,
            reverse: reverse,
            filters: filters
        )
        let context = await contextProvider.currentContext()
        return try await client.execute(query, context: context).collection.map(CollectionPage.init(collection:))
    }

    /// Loads the store's collections in the current context.
    public func collections(first: Int) async throws -> [CollectionSummary] {
        let context = await contextProvider.currentContext()
        return try await client.execute(CollectionsQuery(first: first), context: context).collections.nodes.map(\.collection)
    }

    /// Loads recommendations in the current context.
    public func recommendations(productID: ShopifyID, intent: ProductRecommendationIntent) async throws -> [ProductSummary] {
        let context = await contextProvider.currentContext()
        let query = ProductRecommendationsQuery(productID: productID, intent: intent)
        return try await client.execute(query, context: context).productRecommendations ?? []
    }

    /// Loads the accepted card brands and digital wallets in the current context.
    public func paymentSettings() async throws -> PaymentSettings {
        let context = await contextProvider.currentContext()
        return try await client.execute(PaymentSettingsQuery(), context: context).shop.paymentSettings
    }
}

// MARK: - ProductLookupRepository

/// Loads known products by GID, for lists the app keeps on the device (wishlist, recently
/// viewed). The device stores only the IDs; titles, prices and images always come fresh from
/// Shopify in the current market.
public protocol ProductLookupRepository: Sendable {
    /// The products with `ids` that exist in the current market, in the order of `ids`.
    ///
    /// - Throws: `ShopifyError`.
    func products(ids: [ShopifyID]) async throws -> [ProductSummary]
}

extension StorefrontCatalogRepository: ProductLookupRepository {
    /// Loads the products in the current context; an empty list makes no request.
    public func products(ids: [ShopifyID]) async throws -> [ProductSummary] {
        guard !ids.isEmpty else { return [] }
        let context = await contextProvider.currentContext()
        let products = try await client.execute(ProductsByIDQuery(ids: ids), context: context).products
        let order = Dictionary(ids.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return products.sorted { (order[$0.id] ?? .max) < (order[$1.id] ?? .max) }
    }
}
