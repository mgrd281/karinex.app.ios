import Foundation

/// Loads one product with everything the product screen needs (Storefront `product(handle:)`).
///
/// Metafields require the `unauthenticated_read_metafields` scope, which tokenless access does
/// not have: selecting them without a token fails the whole request with `ACCESS_DENIED`. The
/// query therefore selects them only when `includeMetafields` is true, which repositories set
/// when a Storefront token is configured.
public struct ProductByHandleQuery: GraphQLOperation {
    /// The operation variables.
    public struct Variables: Encodable, Sendable, Equatable {
        /// The product handle.
        public let handle: String
        /// Whether metafields are selected.
        public let includeMetafields: Bool
        /// The metafields to select when `includeMetafields` is true.
        public let metafieldIdentifiers: [MetafieldIdentifier]
    }

    /// The `data` of the response.
    public struct ResponseData: Decodable, Sendable, Equatable {
        /// The product, or `nil` when no product has the handle in this context.
        public let product: Product?
    }

    /// `ProductByHandle`.
    public static let operationName = "ProductByHandle"
    /// A query.
    public static let kind = GraphQLOperationKind.query
    /// The operation followed by `ProductDetail`, `ImageFields` and `MoneyFields`.
    public static let document = """
        query ProductByHandle(
          $handle: String!
          $includeMetafields: Boolean!
          $metafieldIdentifiers: [HasMetafieldsIdentifier!]!
        ) {
          product(handle: $handle) {
            ...ProductDetail
          }
        }

        """ + StorefrontFragments.productDetail + "\n\n" + StorefrontFragments.image + "\n\n" + StorefrontFragments.money + "\n"

    /// The variables of this call.
    public let variables: Variables

    /// Creates the query.
    ///
    /// - Parameters:
    ///   - handle: The product handle, e.g. `office-2024-professional-plus-key`.
    ///   - includeMetafields: Whether to select metafields. Only pass `true` with a token.
    ///   - metafieldIdentifiers: The metafields to select, `ProductMetafields.allIdentifiers`
    ///     by default.
    public init(
        handle: String,
        includeMetafields: Bool,
        metafieldIdentifiers: [MetafieldIdentifier] = ProductMetafields.allIdentifiers
    ) {
        variables = Variables(handle: handle, includeMetafields: includeMetafields, metafieldIdentifiers: metafieldIdentifiers)
    }
}
