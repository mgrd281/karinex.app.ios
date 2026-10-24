import Foundation

// MARK: - SearchRepository

/// Product search in the current buyer context.
public protocol SearchRepository: Sendable {
    /// As-you-type results for `query`: products, collections, articles and query suggestions.
    ///
    /// - Parameters:
    ///   - query: The text typed so far.
    ///   - limit: The number of results per type (1 to 10).
    /// - Returns: The results; `.empty` for a blank query, without a request.
    /// - Throws: `ShopifyError`.
    func predictive(query: String, limit: Int) async throws -> PredictiveSearchResult

    /// One page of full product search results.
    ///
    /// - Parameters:
    ///   - query: The search text.
    ///   - first: The page size (1 to 250).
    ///   - after: The cursor of the previous page, `nil` for the first page.
    ///   - sortKey: Relevance or price.
    ///   - reverse: Whether to reverse the sort order (price high to low).
    ///   - filters: The chosen filter values (from `SearchResultPage.filters`), empty for none.
    /// - Returns: The page; `.empty` for a blank query, without a request.
    /// - Throws: `ShopifyError`.
    func products(
        query: String,
        first: Int,
        after: String?,
        sortKey: SearchSortKey,
        reverse: Bool,
        filters: [ProductFilterInput]
    ) async throws -> SearchResultPage
}

// MARK: - StorefrontSearchRepository

/// `SearchRepository` backed by the Storefront `predictiveSearch` and `search` queries.
public final class StorefrontSearchRepository: SearchRepository {
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

    /// Loads predictive results in the current context.
    public func predictive(query: String, limit: Int) async throws -> PredictiveSearchResult {
        let operation = PredictiveSearchQuery(query: query, limit: limit)
        guard !operation.variables.query.isEmpty else { return .empty }
        let context = await contextProvider.currentContext()
        return try await client.execute(operation, context: context).predictiveSearch ?? .empty
    }

    /// Loads one page of search results in the current context.
    public func products(
        query: String,
        first: Int,
        after: String?,
        sortKey: SearchSortKey,
        reverse: Bool,
        filters: [ProductFilterInput]
    ) async throws -> SearchResultPage {
        let operation = SearchProductsQuery(query: query, first: first, after: after, sortKey: sortKey, reverse: reverse, filters: filters)
        guard !operation.variables.query.isEmpty else { return .empty }
        let context = await contextProvider.currentContext()
        return try await client.execute(operation, context: context).search.page
    }
}
