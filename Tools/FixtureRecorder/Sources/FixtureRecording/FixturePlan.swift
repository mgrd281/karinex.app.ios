import Core
import Foundation
import ShopifyKit

// MARK: - FixtureSpec

/// One live fixture: which operation to run in which context, and what outcome to expect.
public struct FixtureSpec: Sendable {
    /// The expected result of running the operation.
    public enum Outcome: String, Sendable {
        /// The operation returns data.
        case success
        /// The operation returns data whose resource is `null` (not found).
        case notFound
        /// The mutation returns `userErrors` and no result.
        case userErrors
        /// The request fails with `ACCESS_DENIED`.
        case accessDenied
    }

    /// Why a recording did not match its expectation.
    public struct UnexpectedOutcome: Error, CustomStringConvertible {
        /// The fixture file.
        public let fileName: String
        /// What happened instead.
        public let detail: String

        /// A one-line English message.
        public var description: String {
            "\(fileName): \(detail)"
        }
    }

    /// The fixture file name, e.g. `localization_DE_DE.json`.
    public let fileName: String
    /// What the fixture shows, for the manifest.
    public let summary: String
    /// The GraphQL operation name.
    public let operationName: String
    /// Query or mutation.
    public let kind: GraphQLOperationKind
    /// The variables as JSON, for the manifest.
    public let variables: JSONValue
    /// The buyer context of the call.
    public let context: StorefrontContext
    /// Whether the call must be made without a token even when one is configured.
    public let requiresTokenlessClient: Bool
    /// The expected outcome.
    public let expectedOutcome: Outcome
    /// Runs the operation through a real client and validates the outcome.
    public let execute: @Sendable (StorefrontClient) async throws -> Void

    /// Creates a spec for `operation`.
    ///
    /// - Parameters:
    ///   - fileName: The fixture file name.
    ///   - summary: What the fixture shows.
    ///   - operation: The operation to run.
    ///   - context: The buyer context.
    ///   - expectedOutcome: The expected outcome; `.accessDenied` expects a thrown error,
    ///     every other outcome expects data that `validate` accepts.
    ///   - requiresTokenlessClient: Whether to use a tokenless client.
    ///   - validate: Checks the decoded data and throws `UnexpectedOutcome` if it is not as expected.
    public static func live<O: GraphQLOperation>(
        fileName: String,
        summary: String,
        operation: O,
        context: StorefrontContext,
        expectedOutcome: Outcome,
        requiresTokenlessClient: Bool = false,
        validate: @escaping @Sendable (O.ResponseData) throws -> Void = { _ in }
    ) throws -> FixtureSpec {
        let variables = try JSONValue.encoding(operation.variables)

        return FixtureSpec(
            fileName: fileName,
            summary: summary,
            operationName: O.operationName,
            kind: O.kind,
            variables: variables,
            context: context,
            requiresTokenlessClient: requiresTokenlessClient,
            expectedOutcome: expectedOutcome
        ) { client in
            let data: O.ResponseData
            do {
                data = try await client.execute(operation, context: context)
            } catch let error as ShopifyError {
                if expectedOutcome == .accessDenied, case .accessDenied = error {
                    return
                }
                throw UnexpectedOutcome(fileName: fileName, detail: "failed with \(error.logDescription)")
            }
            guard expectedOutcome != .accessDenied else {
                throw UnexpectedOutcome(fileName: fileName, detail: "succeeded, but ACCESS_DENIED was expected")
            }
            try validate(data)
        }
    }
}

// MARK: - FixturePlan

/// The fixtures `fixture-recorder` writes (contract section 3.2) and how to record them.
public enum FixturePlan {
    /// The handle of the product fixtures.
    public static let productHandle = "office-2024-professional-plus-key"
    /// A handle no product has, for the not-found fixture.
    public static let missingProductHandle = "kx-fixture-no-such-product"
    /// The collection of the collection fixture.
    public static let collectionHandle = "bestseller"
    /// The page size of the collection fixture.
    public static let collectionPageSize = 8
    /// The only merchandise ID the recorder ever sends to a mutation. No such variant exists,
    /// so `cartCreate` answers with a user error and creates nothing.
    public static let invalidMerchandiseID: ShopifyID = "gid://shopify/ProductVariant/1"

    /// The consent the app sends before the user decided: analytics off, preferences on,
    /// marketing and sale of data off.
    public static let visitorConsent = VisitorConsent(privacyConsent: .undecided)
    /// Germany in German.
    public static let germanyContext = StorefrontContext(country: .de, language: .de, visitorConsent: visitorConsent)
    /// Switzerland in French (currency CHF).
    public static let switzerlandFrenchContext = StorefrontContext(country: .ch, language: .fr, visitorConsent: visitorConsent)

    /// The live fixtures in recording order.
    ///
    /// - Parameter isTokenless: Whether the main client has no token. With a token, the
    ///   product fixtures include metafields; the access-denied fixture is always recorded
    ///   without a token.
    public static func liveFixtures(isTokenless: Bool) throws -> [FixtureSpec] {
        let includeMetafields = !isTokenless
        return try [
            .live(
                fileName: "localization_DE_DE.json",
                summary: "Store countries, currencies and languages in the DE/DE context.",
                operation: LocalizationQuery(),
                context: germanyContext,
                expectedOutcome: .success
            ) { data in
                guard !data.localization.availableCountries.isEmpty else {
                    throw FixtureSpec.UnexpectedOutcome(fileName: "localization_DE_DE.json", detail: "no countries")
                }
            },
            .live(
                fileName: "product_\(productHandle)_DE_DE.json",
                summary: "Office 2024 Professional Plus with the ProductDetail fragment in the DE/DE context (EUR).",
                operation: ProductByHandleQuery(handle: productHandle, includeMetafields: includeMetafields),
                context: germanyContext,
                expectedOutcome: .success,
                validate: requireProduct("product_\(productHandle)_DE_DE.json")
            ),
            .live(
                fileName: "product_\(productHandle)_CH_FR.json",
                summary: "The same product in the CH/FR context (French content, CHF prices).",
                operation: ProductByHandleQuery(handle: productHandle, includeMetafields: includeMetafields),
                context: switzerlandFrenchContext,
                expectedOutcome: .success,
                validate: requireProduct("product_\(productHandle)_CH_FR.json")
            ),
            .live(
                fileName: "product_not_found_DE_DE.json",
                summary: "product(handle:) for a handle that does not exist: data.product is null.",
                operation: ProductByHandleQuery(handle: missingProductHandle, includeMetafields: includeMetafields),
                context: germanyContext,
                expectedOutcome: .notFound
            ) { data in
                guard data.product == nil else {
                    throw FixtureSpec.UnexpectedOutcome(fileName: "product_not_found_DE_DE.json", detail: "product exists")
                }
            },
            .live(
                fileName: "collection_\(collectionHandle)_DE_DE.json",
                summary: "The first 8 products of the bestseller collection in its default order, DE/DE.",
                operation: CollectionProductsQuery(
                    handle: collectionHandle,
                    first: collectionPageSize,
                    sortKey: .collectionDefault
                ),
                context: germanyContext,
                expectedOutcome: .success
            ) { data in
                guard let collection = data.collection, collection.products.nodes.count == collectionPageSize else {
                    throw FixtureSpec.UnexpectedOutcome(
                        fileName: "collection_\(collectionHandle)_DE_DE.json",
                        detail: "collection missing or not \(collectionPageSize) products"
                    )
                }
            },
            .live(
                fileName: "cart_create_invalid_merchandise_DE_DE.json",
                summary: "cartCreate with a merchandise ID that does not exist: a userError (code INVALID), no cart.",
                operation: CartCreateMutation(
                    lines: [CartLineInput(merchandiseId: invalidMerchandiseID, quantity: 1)],
                    countryCode: .de,
                    attributes: [AttributeInput(key: "app_platform", value: "ios")]
                ),
                context: germanyContext,
                expectedOutcome: .userErrors
            ) { data in
                guard let payload = data.cartCreate, payload.cart == nil, !payload.userErrors.isEmpty else {
                    throw FixtureSpec.UnexpectedOutcome(
                        fileName: "cart_create_invalid_merchandise_DE_DE.json",
                        detail: "expected user errors and no cart"
                    )
                }
            },
            .live(
                fileName: "product_metafields_access_denied_DE_DE.json",
                summary: "The product query with metafields but without a token: ACCESS_DENIED "
                    + "(requiredAccess unauthenticated_read_metafields), data.product null.",
                operation: ProductByHandleQuery(handle: productHandle, includeMetafields: true),
                context: germanyContext,
                expectedOutcome: .accessDenied,
                requiresTokenlessClient: true
            ),
        ]
    }

    private static func requireProduct(_ fileName: String) -> @Sendable (ProductByHandleQuery.ResponseData) throws -> Void {
        { data in
            guard let product = data.product, !product.variants.isEmpty else {
                throw FixtureSpec.UnexpectedOutcome(fileName: fileName, detail: "product missing or without variants")
            }
        }
    }
}

// MARK: - Synthetic fixtures

/// A hand-written error envelope for a situation that cannot be provoked safely against the
/// production store. It follows the format documented by Shopify.
public struct SyntheticFixture: Sendable {
    /// The file name; always starts with `synthetic_`.
    public let fileName: String
    /// What the fixture shows.
    public let summary: String
    /// Where Shopify documents the format.
    public let documentationURL: String
    /// The fixture body as JSON.
    public let json: String

    /// The documented Storefront/Customer Account API throttling error (HTTP 200 with a
    /// top-level `THROTTLED` error), see "Status and error codes" on shopify.dev.
    public static let throttled = SyntheticFixture(
        fileName: "synthetic_throttled.json",
        summary: "Documented GraphQL THROTTLED error envelope (HTTP 200, top-level errors, no data).",
        documentationURL: "https://shopify.dev/docs/api/storefront/2026-07#status-and-error-codes",
        json: """
            {
              "errors": [
                {
                  "message": "Throttled",
                  "extensions": {
                    "code": "THROTTLED",
                    "documentation": "https://shopify.dev/api/usage/rate-limits"
                  }
                }
              ]
            }
            """
    )

    /// Every synthetic fixture.
    public static let all: [SyntheticFixture] = [.throttled]
}
