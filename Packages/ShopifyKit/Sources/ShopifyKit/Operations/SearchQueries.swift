import Foundation

// MARK: - PredictiveSearchQuery

/// As-you-type search for products, collections, articles and query suggestions (Storefront
/// `predictiveSearch`). Sold-out products are listed last.
public struct PredictiveSearchQuery: GraphQLOperation {
    /// The largest number of results per type the Storefront API accepts.
    public static let maximumLimit = 10

    /// The operation variables.
    public struct Variables: Encodable, Sendable, Equatable {
        /// The search text.
        public let query: String
        /// The number of results per type, 1 to 10.
        public let limit: Int
    }

    /// The `data` of the response.
    public struct ResponseData: Decodable, Sendable, Equatable {
        /// The results; `nil` when Shopify returned none at all.
        public let predictiveSearch: PredictiveSearchResult?
    }

    /// `PredictiveSearch`.
    public static let operationName = "PredictiveSearch"
    /// A query.
    public static let kind = GraphQLOperationKind.query
    /// The operation followed by the summary fragments of every result type.
    public static let document = StorefrontFragments.document(
        """
        query PredictiveSearch($query: String!, $limit: Int!) {
          predictiveSearch(
            query: $query
            limit: $limit
            limitScope: EACH
            types: [PRODUCT, COLLECTION, ARTICLE, QUERY]
            unavailableProducts: LAST
          ) {
            products {
              ...ProductSummaryFields
            }
            collections {
              ...CollectionSummaryFields
            }
            articles {
              ...ArticleSummaryFields
            }
            queries {
              text
              styledText
            }
          }
        }
        """,
        fragments: [
            StorefrontFragments.productSummary,
            StorefrontFragments.collectionSummary,
            StorefrontFragments.articleSummary,
            StorefrontFragments.image,
            StorefrontFragments.money,
        ]
    )

    /// The variables of this call.
    public let variables: Variables

    /// Creates the query.
    ///
    /// - Parameters:
    ///   - query: The search text, trimmed.
    ///   - limit: The number of results per type, clamped to 1...10.
    public init(query: String, limit: Int) {
        variables = Variables(
            query: query.trimmingCharacters(in: .whitespacesAndNewlines),
            limit: min(max(limit, 1), Self.maximumLimit)
        )
    }
}

// MARK: - SearchProductsQuery

/// Full product search with sorting, filters and cursor pagination (Storefront `search` with
/// `types: [PRODUCT]`). Sold-out products are listed last.
public struct SearchProductsQuery: GraphQLOperation {
    /// The largest page size the Storefront API accepts.
    public static let maximumPageSize = 250

    /// The operation variables. `nil` members are omitted.
    public struct Variables: Encodable, Sendable, Equatable {
        /// The search text.
        public let query: String
        /// The page size, 1 to 250.
        public let first: Int
        /// The cursor to continue after, `nil` for the first page.
        public let after: String?
        /// The sort order.
        public let sortKey: SearchSortKey
        /// Whether to reverse the sort order.
        public let reverse: Bool
        /// The chosen filter values, `nil` when none is chosen.
        public let filters: [ProductFilterInput]?
    }

    /// The `search` connection.
    public struct SearchConnection: Decodable, Sendable, Equatable {
        /// The number of matches over all pages.
        public let totalCount: Int
        /// The filters the store offers for the result.
        public let productFilters: [ProductFilter]
        /// The products of this page. Results of other types are skipped.
        public let products: [ProductSummary]
        /// Pagination state.
        public let pageInfo: PageInfo

        private enum CodingKeys: String, CodingKey {
            case totalCount, productFilters, nodes, pageInfo
        }

        /// Decodes the connection, keeping only `Product` nodes.
        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            totalCount = try container.decode(Int.self, forKey: .totalCount)
            productFilters = try container.decodeIfPresent([ProductFilter].self, forKey: .productFilters) ?? []
            products = try container.decode([SearchResultNode].self, forKey: .nodes).compactMap(\.product)
            pageInfo = try container.decode(PageInfo.self, forKey: .pageInfo)
        }

        /// The connection as a `SearchResultPage`.
        public var page: SearchResultPage {
            SearchResultPage(totalCount: totalCount, products: products, filters: productFilters, pageInfo: pageInfo)
        }
    }

    /// The `data` of the response.
    public struct ResponseData: Decodable, Sendable, Equatable {
        /// The search results.
        public let search: SearchConnection
    }

    /// `SearchProducts`.
    public static let operationName = "SearchProducts"
    /// A query.
    public static let kind = GraphQLOperationKind.query
    /// The operation followed by `FilterFields`, `ProductSummaryFields`, `ImageFields` and
    /// `MoneyFields`.
    public static let document = StorefrontFragments.document(
        """
        query SearchProducts(
          $query: String!
          $first: Int!
          $after: String
          $sortKey: SearchSortKeys!
          $reverse: Boolean!
          $filters: [ProductFilter!]
        ) {
          search(
            query: $query
            first: $first
            after: $after
            sortKey: $sortKey
            reverse: $reverse
            productFilters: $filters
            types: [PRODUCT]
            unavailableProducts: LAST
          ) {
            totalCount
            productFilters {
              ...FilterFields
            }
            nodes {
              __typename
              ... on Product {
                ...ProductSummaryFields
              }
            }
            pageInfo {
              hasNextPage
              hasPreviousPage
              startCursor
              endCursor
            }
          }
        }
        """,
        fragments: [StorefrontFragments.filter, StorefrontFragments.productSummary, StorefrontFragments.image, StorefrontFragments.money]
    )

    /// The variables of this call.
    public let variables: Variables

    /// Creates the query.
    ///
    /// - Parameters:
    ///   - query: The search text, trimmed.
    ///   - first: The page size, clamped to 1...250.
    ///   - after: The `endCursor` of the previous page, `nil` for the first page.
    ///   - sortKey: The sort order, relevance by default.
    ///   - reverse: Whether to reverse the sort order (price high to low).
    ///   - filters: The chosen filter values; an empty list is not sent.
    public init(
        query: String,
        first: Int,
        after: String? = nil,
        sortKey: SearchSortKey = .relevance,
        reverse: Bool = false,
        filters: [ProductFilterInput] = []
    ) {
        variables = Variables(
            query: query.trimmingCharacters(in: .whitespacesAndNewlines),
            first: min(max(first, 1), Self.maximumPageSize),
            after: after,
            sortKey: sortKey,
            reverse: reverse,
            filters: filters.isEmpty ? nil : filters
        )
    }
}

// MARK: - SearchResultNode

/// One `SearchResultItem` of a search connection: a product, or another type that is skipped.
private struct SearchResultNode: Decodable {
    let product: ProductSummary?

    private enum CodingKeys: String, CodingKey {
        case typename = "__typename"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let typename = try container.decodeIfPresent(String.self, forKey: .typename)
        product = try typename == "Product" ? ProductSummary(from: decoder) : nil
    }
}
