import Foundation

// MARK: - CollectionsQuery

/// Lists the store's collections by title (Storefront `collections`), for the Shop tab, each
/// with the image of its first product that has one as ``CollectionSummary/previewImage``.
///
/// The requested cost is about 6 per collection (the image and the connection of three products
/// with their images), so 100 collections stay below the tokenless limit of 1000.
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
        public let collections: Connection<Node>
    }

    /// One collection of the response: the summary fields and the images of its first products.
    public struct Node: Decodable, Sendable, Equatable {
        /// The collection, with ``CollectionSummary/previewImage`` taken from its first product
        /// that has an image.
        public let collection: CollectionSummary

        private enum CodingKeys: String, CodingKey {
            case products
        }

        /// The one field of a product the query asks for.
        private struct FirstProduct: Decodable {
            let featuredImage: ShopifyImage?
        }

        public init(from decoder: any Decoder) throws {
            let summary = try CollectionSummary(from: decoder)
            let products = try decoder.container(keyedBy: CodingKeys.self)
                .decodeIfPresent(Connection<FirstProduct>.self, forKey: .products)
            collection = CollectionSummary(
                id: summary.id,
                handle: summary.handle,
                title: summary.title,
                description: summary.description,
                image: summary.image,
                previewImage: products?.nodes.lazy.compactMap(\.featuredImage).first ?? summary.previewImage
            )
        }
    }

    /// The number of products per collection whose images are candidates for the preview.
    public static let previewProductCount = 3

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
              products(first: \(previewProductCount)) {
                nodes {
                  featuredImage {
                    ...ImageFields
                  }
                }
              }
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

// MARK: - ProductsByIDQuery

/// Loads several products by GID in one request (Storefront `nodes`), e.g. the wishlist and
/// the recently viewed products. Products that were deleted or are not published in the
/// current market come back as `null` and are left out.
public struct ProductsByIDQuery: GraphQLOperation {
    /// The most IDs the Storefront API accepts in one `nodes` call.
    public static let maximumIDs = 250

    /// The operation variables.
    public struct Variables: Encodable, Sendable, Equatable {
        /// The product GIDs.
        public let ids: [ShopifyID]
    }

    /// The `data` of the response.
    public struct ResponseData: Decodable, Sendable, Equatable {
        /// The products in the order of the IDs, without the missing ones.
        public let products: [ProductSummary]

        private enum CodingKeys: String, CodingKey {
            case nodes
        }

        /// A node that is decoded as a product, or `nil` for `null` and other types.
        private struct OptionalProduct: Decodable {
            let product: ProductSummary?

            init(from decoder: any Decoder) throws {
                product = try? ProductSummary(from: decoder)
            }
        }

        /// Creates the data, e.g. for previews and tests.
        public init(products: [ProductSummary]) {
            self.products = products
        }

        /// Decodes `nodes`, skipping `null` entries.
        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let nodes = try container.decode([OptionalProduct?].self, forKey: .nodes)
            products = nodes.compactMap { $0?.product }
        }
    }

    /// `ProductsByID`.
    public static let operationName = "ProductsByID"
    /// A query.
    public static let kind = GraphQLOperationKind.query
    /// The operation followed by `ProductSummaryFields`, `ImageFields` and `MoneyFields`.
    public static let document = StorefrontFragments.document(
        """
        query ProductsByID($ids: [ID!]!) {
          nodes(ids: $ids) {
            ... on Product {
              ...ProductSummaryFields
            }
          }
        }
        """,
        fragments: [StorefrontFragments.productSummary, StorefrontFragments.image, StorefrontFragments.money]
    )

    /// The variables of this call.
    public let variables: Variables

    /// Creates the query for at most 250 distinct IDs, in the given order.
    public init(ids: [ShopifyID]) {
        var seen = Set<ShopifyID>()
        let unique = ids.filter { seen.insert($0).inserted }
        variables = Variables(ids: Array(unique.prefix(Self.maximumIDs)))
    }
}
