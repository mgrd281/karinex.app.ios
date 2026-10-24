import Foundation

// MARK: - ProductCollectionSortKeys

/// The Storefront `ProductCollectionSortKeys` enum: how products in a collection are sorted.
public enum ProductCollectionSortKeys: String, Sendable, Hashable, Codable, CaseIterable {
    /// By sales.
    case bestSelling = "BEST_SELLING"
    /// The order configured for the collection in the admin.
    case collectionDefault = "COLLECTION_DEFAULT"
    /// By creation date.
    case created = "CREATED"
    /// By price.
    case price = "PRICE"
    /// By search relevance.
    case relevance = "RELEVANCE"
    /// By title.
    case title = "TITLE"
    /// The manual order of the collection.
    case manual = "MANUAL"
    /// By ID.
    case id = "ID"
}

// MARK: - CollectionProductsQuery

/// Loads a collection, one page of its products and the filters the store offers for them
/// (Storefront `collection(handle:)` with `products(filters:)` and `products.filters`).
public struct CollectionProductsQuery: GraphQLOperation {
    /// The largest page size the Storefront API accepts.
    public static let maximumPageSize = 250

    /// The operation variables. `nil` members are omitted, which GraphQL treats as `null`.
    public struct Variables: Encodable, Sendable, Equatable {
        /// The collection handle.
        public let handle: String
        /// The page size, 1 to 250.
        public let first: Int
        /// The cursor to continue after, `nil` for the first page.
        public let after: String?
        /// The sort order, `nil` for the collection default.
        public let sortKey: ProductCollectionSortKeys?
        /// Whether to reverse the sort order.
        public let reverse: Bool?
        /// The chosen filter values, `nil` when none is chosen.
        public let filters: [ProductFilterInput]?
    }

    /// The `data` of the response.
    public struct ResponseData: Decodable, Sendable, Equatable {
        /// The collection, or `nil` when no collection has the handle.
        public let collection: ProductCollection?
    }

    /// `CollectionProducts`.
    public static let operationName = "CollectionProducts"
    /// A query.
    public static let kind = GraphQLOperationKind.query
    /// The operation followed by `FilterFields`, `ProductSummaryFields`, `ImageFields` and
    /// `MoneyFields`.
    public static let document = StorefrontFragments.document(
        """
        query CollectionProducts(
          $handle: String!
          $first: Int!
          $after: String
          $sortKey: ProductCollectionSortKeys
          $reverse: Boolean
          $filters: [ProductFilter!]
        ) {
          collection(handle: $handle) {
            id
            handle
            title
            description
            image {
              ...ImageFields
            }
            products(first: $first, after: $after, sortKey: $sortKey, reverse: $reverse, filters: $filters) {
              filters {
                ...FilterFields
              }
              nodes {
                ...ProductSummaryFields
              }
              pageInfo {
                hasNextPage
                hasPreviousPage
                startCursor
                endCursor
              }
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
    ///   - handle: The collection handle, e.g. `bestseller`.
    ///   - first: The page size, clamped to 1...250.
    ///   - after: The `endCursor` of the previous page, `nil` for the first page.
    ///   - sortKey: The sort order, `nil` for the collection default.
    ///   - reverse: Whether to reverse the sort order, `false` by default.
    ///   - filters: The chosen filter values (from `ProductFilterValue.input`); an empty list
    ///     is not sent.
    public init(
        handle: String,
        first: Int,
        after: String? = nil,
        sortKey: ProductCollectionSortKeys? = nil,
        reverse: Bool = false,
        filters: [ProductFilterInput] = []
    ) {
        variables = Variables(
            handle: handle,
            first: min(max(first, 1), Self.maximumPageSize),
            after: after,
            sortKey: sortKey,
            reverse: reverse,
            filters: filters.isEmpty ? nil : filters
        )
    }
}
