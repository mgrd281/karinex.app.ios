import Foundation

// MARK: - CollectionsQuery

/// Lists the store's collections by title (Storefront `collections`), for the catalog grid.
public struct CollectionsQuery: GraphQLOperation {
    /// The largest page size the Storefront API accepts.
    public static let maximumPageSize = 250

    /// The operation variables.
    public struct Variables: Encodable, Sendable, Equatable {
        /// The number of collections, 1 to 250.
        public let first: Int
    }

    /// The `data` of the response.
    public struct ResponseData: Decodable, Sendable, Equatable {
        /// The collections connection.
        public let collections: Connection<CollectionSummary>
    }

    /// `Collections`.
    public static let operationName = "Collections"
    /// A query.
    public static let kind = GraphQLOperationKind.query
    /// The operation followed by `CollectionSummaryFields` and `ImageFields`.
    public static let document = StorefrontFragments.document(
        """
        query Collections($first: Int!) {
          collections(first: $first, sortKey: TITLE) {
            nodes {
              ...CollectionSummaryFields
            }
          }
        }
        """,
        fragments: [StorefrontFragments.collectionSummary, StorefrontFragments.image]
    )

    /// The variables of this call.
    public let variables: Variables

    /// Creates the query; `first` is clamped to 1...250.
    public init(first: Int) {
        variables = Variables(first: min(max(first, 1), Self.maximumPageSize))
    }
}

// MARK: - ProductRecommendationsQuery

/// Loads Shopify's recommendations for a product (Storefront `productRecommendations`):
/// related products for comparisons, complementary products for cross-selling.
public struct ProductRecommendationsQuery: GraphQLOperation {
    /// The operation variables.
    public struct Variables: Encodable, Sendable, Equatable {
        /// The product GID.
        public let productId: ShopifyID
        /// The kind of recommendations.
        public let intent: ProductRecommendationIntent
    }

    /// The `data` of the response.
    public struct ResponseData: Decodable, Sendable, Equatable {
        /// The recommended products; `nil` when the product does not exist.
        public let productRecommendations: [ProductSummary]?
    }

    /// `ProductRecommendations`.
    public static let operationName = "ProductRecommendations"
    /// A query.
    public static let kind = GraphQLOperationKind.query
    /// The operation followed by `ProductSummaryFields`, `ImageFields` and `MoneyFields`.
    public static let document = StorefrontFragments.document(
        """
        query ProductRecommendations($productId: ID!, $intent: ProductRecommendationIntent!) {
          productRecommendations(productId: $productId, intent: $intent) {
            ...ProductSummaryFields
          }
        }
        """,
        fragments: [StorefrontFragments.productSummary, StorefrontFragments.image, StorefrontFragments.money]
    )

    /// The variables of this call.
    public let variables: Variables

    /// Creates the query.
    ///
    /// - Parameters:
    ///   - productID: The product GID.
    ///   - intent: `.related` (default) or `.complementary`.
    public init(productID: ShopifyID, intent: ProductRecommendationIntent = .related) {
        variables = Variables(productId: productID, intent: intent)
    }
}
