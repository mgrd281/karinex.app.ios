import Foundation

// MARK: - SearchSortKey

/// The Storefront `SearchSortKeys` enum: how full search results are sorted.
public enum SearchSortKey: String, Sendable, Hashable, Codable, CaseIterable {
    /// By search relevance (the default).
    case relevance = "RELEVANCE"
    /// By price; combine with `reverse` for high to low.
    case price = "PRICE"
}

// MARK: - ProductRecommendationIntent

/// The Storefront `ProductRecommendationIntent` enum: which kind of recommendations to load.
public enum ProductRecommendationIntent: String, Sendable, Hashable, Codable, CaseIterable {
    /// Similar products, e.g. for a comparison row on the product screen.
    case related = "RELATED"
    /// Products bought together, e.g. for the cross-sell row in the cart.
    case complementary = "COMPLEMENTARY"
}

// MARK: - SearchQuerySuggestion

/// A completed search query suggested while typing (Storefront `SearchQuerySuggestion`).
public struct SearchQuerySuggestion: Sendable, Hashable, Codable, Identifiable {
    /// The suggested query, e.g. `windows 11`.
    public let text: String
    /// The suggestion as HTML with the typed part unstyled and the completion in `<mark>`,
    /// e.g. `win<mark>dows 11</mark>`. Equal to `text` when Shopify sent no markup.
    public let styledText: String

    /// Creates a suggestion. `styledText` defaults to `text`.
    public init(text: String, styledText: String? = nil) {
        self.text = text
        self.styledText = styledText ?? text
    }

    /// The query text, unique within one result.
    public var id: String {
        text
    }

    private enum CodingKeys: String, CodingKey {
        case text, styledText
    }

    /// Decodes a suggestion; a missing `styledText` falls back to `text`.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let text = try container.decode(String.self, forKey: .text)
        try self.init(text: text, styledText: container.decodeIfPresent(String.self, forKey: .styledText))
    }
}

// MARK: - PredictiveSearchResult

/// The as-you-type results of a search (Storefront `PredictiveSearchResult`).
public struct PredictiveSearchResult: Sendable, Hashable, Codable {
    /// Matching products.
    public let products: [ProductSummary]
    /// Matching collections.
    public let collections: [CollectionSummary]
    /// Matching blog articles.
    public let articles: [ArticleSummary]
    /// Suggested complete queries.
    public let queries: [SearchQuerySuggestion]

    /// Creates a result.
    public init(
        products: [ProductSummary] = [],
        collections: [CollectionSummary] = [],
        articles: [ArticleSummary] = [],
        queries: [SearchQuerySuggestion] = []
    ) {
        self.products = products
        self.collections = collections
        self.articles = articles
        self.queries = queries
    }

    /// A result without any match.
    public static let empty = PredictiveSearchResult()

    /// Whether nothing matched.
    public var isEmpty: Bool {
        products.isEmpty && collections.isEmpty && articles.isEmpty && queries.isEmpty
    }
}

// MARK: - SearchResultPage

/// One page of full product search results (Storefront `search` with `types: [PRODUCT]`).
public struct SearchResultPage: Sendable, Hashable, Codable {
    /// The number of matching products over all pages.
    public let totalCount: Int
    /// The products of this page.
    public let products: [ProductSummary]
    /// The filters the store offers for the result, with counts.
    public let filters: [ProductFilter]
    /// Pagination state; pass `pageInfo.nextPageCursor` as `after` for the next page.
    public let pageInfo: PageInfo

    /// Creates a page.
    public init(totalCount: Int, products: [ProductSummary], filters: [ProductFilter], pageInfo: PageInfo) {
        self.totalCount = totalCount
        self.products = products
        self.filters = filters
        self.pageInfo = pageInfo
    }

    /// A page without results.
    public static let empty = SearchResultPage(totalCount: 0, products: [], filters: [], pageInfo: .singlePage)
}
