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

/// Loads a collection and one page of its products (Storefront `collection(handle:)`).
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
    /// The operation followed by `ProductSummaryFields`, `ImageFields` and `MoneyFields`.
    public static let document = """
        query CollectionProducts(
          $handle: String!
          $first: Int!
          $after: String
          $sortKey: ProductCollectionSortKeys
          $reverse: Boolean
        ) {
          collection(handle: $handle) {
            id
            handle
            title
            description
            image {
              ...ImageFields
            }
            products(first: $first, after: $after, sortKey: $sortKey, reverse: $reverse) {
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

        """ + StorefrontFragments.productSummary + "\n\n" + StorefrontFragments.image + "\n\n" + StorefrontFragments.money + "\n"

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
    public init(
        handle: String,
        first: Int,
        after: String? = nil,
        sortKey: ProductCollectionSortKeys? = nil,
        reverse: Bool = false
    ) {
        variables = Variables(
            handle: handle,
            first: min(max(first, 1), Self.maximumPageSize),
            after: after,
            sortKey: sortKey,
            reverse: reverse
        )
    }
}
