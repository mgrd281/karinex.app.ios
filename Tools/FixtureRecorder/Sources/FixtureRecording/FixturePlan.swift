import Core
import Foundation
import ShopifyKit

// MARK: - FixtureSession

/// State shared by the steps of one recording run: the product the recommendation fixtures
/// use, and the cart the recorder creates itself for the cart lifecycle fixtures.
///
/// Cart mutations only ever target `cartID`, which only the recorder's own `cartCreate` step
/// sets, so the recorder can never modify a cart it did not create.
public final class FixtureSession: Sendable {
    /// The mutable state.
    public struct State: Sendable, Equatable {
        /// The GID of the product fixture's product.
        public var productID: ShopifyID?
        /// The digital variants used for the cart lifecycle, cheapest first.
        public var variantIDs: [ShopifyID] = []
        /// The cart the recorder created.
        public var cartID: ShopifyID?
        /// The line GID per variant GID of that cart.
        public var lineIDs: [ShopifyID: ShopifyID] = [:]
    }

    private let storage = Locked(State())

    /// Creates an empty session.
    public init() {}

    /// The current state.
    public var state: State {
        storage.value
    }

    /// Changes the state.
    public func update(_ change: (inout State) -> Void) {
        storage.withLock { change(&$0) }
    }

    /// The recorder's cart, or a failure for `fileName` when no cart was created yet.
    func requireCartID(for fileName: String) throws -> ShopifyID {
        guard let cartID = state.cartID else {
            throw FixtureSpec.UnexpectedOutcome(fileName: fileName, detail: "no cart was created by the recorder")
        }
        return cartID
    }

    /// The line of `variant` in the recorder's cart.
    func requireLineID(variantIndex: Int, for fileName: String) throws -> ShopifyID {
        let current = state
        guard current.variantIDs.indices.contains(variantIndex), let line = current.lineIDs[current.variantIDs[variantIndex]] else {
            throw FixtureSpec.UnexpectedOutcome(fileName: fileName, detail: "no cart line for variant \(variantIndex)")
        }
        return line
    }

    /// Records the lines of `cart`.
    func remember(_ cart: Cart) {
        update { state in
            state.cartID = cart.id
            state.lineIDs = Dictionary(cart.lines.map { ($0.merchandise.id, $0.id) }, uniquingKeysWith: { first, _ in first })
        }
    }
}

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

        /// Creates a failure.
        public init(fileName: String, detail: String) {
            self.fileName = fileName
            self.detail = detail
        }

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
    /// The buyer context of the call.
    public let context: StorefrontContext
    /// Whether the call must be made without a token even when one is configured.
    public let requiresTokenlessClient: Bool
    /// The expected outcome.
    public let expectedOutcome: Outcome
    /// The variables when they are known before the run; `nil` when they depend on earlier
    /// steps (for example a cart ID).
    public let plannedVariables: JSONValue?
    /// Unrecorded preparation, e.g. looking up the variants for the cart. Its requests are
    /// validated but not stored.
    public let prepare: (@Sendable (StorefrontClient, FixtureSession) async throws -> Void)?
    /// Runs the operation through a real client, validates the outcome and returns the
    /// variables that were sent.
    public let execute: @Sendable (StorefrontClient, FixtureSession) async throws -> JSONValue

    /// Creates a spec for `operation`, whose variables are known up front.
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
        validate: @escaping @Sendable (O.ResponseData, FixtureSession) throws -> Void = { _, _ in }
    ) throws -> FixtureSpec {
        let variables = try JSONValue.encoding(operation.variables)
        return deferred(
            fileName: fileName,
            summary: summary,
            context: context,
            expectedOutcome: expectedOutcome,
            requiresTokenlessClient: requiresTokenlessClient,
            plannedVariables: variables,
            makeOperation: { _ in operation },
            validate: validate
        )
    }

    /// Creates a spec whose operation is built at run time from the session, e.g. a cart
    /// mutation on the cart created by an earlier step.
    ///
    /// - Parameters:
    ///   - fileName: The fixture file name.
    ///   - summary: What the fixture shows.
    ///   - context: The buyer context.
    ///   - expectedOutcome: The expected outcome.
    ///   - requiresTokenlessClient: Whether to use a tokenless client.
    ///   - plannedVariables: The variables if known up front, else `nil`.
    ///   - prepare: Unrecorded preparation that runs first.
    ///   - makeOperation: Builds the operation from the session.
    ///   - validate: Checks the decoded data, may update the session, and throws
    ///     `UnexpectedOutcome` if the data is not as expected.
    public static func deferred<O: GraphQLOperation>(
        fileName: String,
        summary: String,
        context: StorefrontContext,
        expectedOutcome: Outcome,
        requiresTokenlessClient: Bool = false,
        plannedVariables: JSONValue? = nil,
        prepare: (@Sendable (StorefrontClient, FixtureSession) async throws -> Void)? = nil,
        makeOperation: @escaping @Sendable (FixtureSession) throws -> O,
        validate: @escaping @Sendable (O.ResponseData, FixtureSession) throws -> Void
    ) -> FixtureSpec {
        FixtureSpec(
            fileName: fileName,
            summary: summary,
            operationName: O.operationName,
            kind: O.kind,
            context: context,
            requiresTokenlessClient: requiresTokenlessClient,
            expectedOutcome: expectedOutcome,
            plannedVariables: plannedVariables,
            prepare: prepare
        ) { client, session in
            let operation = try makeOperation(session)
            let variables = try JSONValue.encoding(operation.variables)
            let data: O.ResponseData
            do {
                data = try await client.execute(operation, context: context)
            } catch let error as ShopifyError {
                if expectedOutcome == .accessDenied, case .accessDenied = error {
                    return variables
                }
                throw UnexpectedOutcome(fileName: fileName, detail: "failed with \(error.logDescription)")
            }
            guard expectedOutcome != .accessDenied else {
                throw UnexpectedOutcome(fileName: fileName, detail: "succeeded, but ACCESS_DENIED was expected")
            }
            try validate(data, session)
            return variables
        }
    }
}

// MARK: - FixturePlan

/// The fixtures `fixture-recorder` writes and how to record them.
///
/// Mutations: one `cartCreate` with a merchandise ID that does not exist (creates nothing),
/// and one cart lifecycle on a cart the recorder creates itself with the cheapest digital
/// variants: create, add a line, change a quantity, enter a discount code that does not exist,
/// remove a line, read the cart. The checkout URL is never opened, so the cart never becomes an
/// order and expires on its own. No other mutation is ever sent.
public enum FixturePlan {
    /// The handle of the product fixtures.
    public static let productHandle = "office-2024-professional-plus-key"
    /// A handle no product has, for the not-found fixture.
    public static let missingProductHandle = "kx-fixture-no-such-product"
    /// The collection of the collection fixture.
    public static let collectionHandle = "bestseller"
    /// The page size of the collection fixtures.
    public static let collectionPageSize = 8
    /// The collection of the filtered collection fixture.
    public static let filteredCollectionHandle = "windows"
    /// The price filter of the filtered collection fixture, in EUR.
    public static let priceFilter = ProductFilterInput.price(minimum: 10, maximum: 30)
    /// The collection searched for the cheapest digital variants.
    public static let allProductsHandle = "all"
    /// The query of the search fixture.
    public static let searchQuery = "office 2024"
    /// The query of the predictive search fixture.
    public static let predictiveQuery = "win"
    /// The blog of the article fixtures.
    public static let blogHandle = "guides"
    /// The article of the article fixture: it has a style sheet, a script, an image, tables
    /// with `colgroup`, `details` and inline code, which exercises the HTML parser.
    public static let articleHandle = "windows-11-kompatibilitaet-pruefen"
    /// The number of articles of the blog fixture.
    public static let articleCount = 6
    /// The discount code of the invalid discount fixture. It does not exist in the store.
    public static let invalidDiscountCode = "KX-FIXTURE-NOT-A-CODE"
    /// The only merchandise ID the recorder sends to `cartCreate` besides the cheapest
    /// variants. No such variant exists, so `cartCreate` answers with a user error and
    /// creates nothing.
    public static let invalidMerchandiseID: ShopifyID = "gid://shopify/ProductVariant/1"
    /// The attributes of the recorder's cart; `kx_fixture_recording` lets the store owner
    /// recognize it among abandoned carts.
    public static let cartAttributes = [
        AttributeInput(key: "app_platform", value: "ios"),
        AttributeInput(key: "kx_fixture_recording", value: "true"),
    ]

    /// The consent the app sends before the user decided: analytics off, preferences on,
    /// marketing and sale of data off.
    public static let visitorConsent = VisitorConsent(privacyConsent: .undecided)
    /// Germany in German.
    public static let germanyContext = StorefrontContext(country: .de, language: .de, visitorConsent: visitorConsent)
    /// Switzerland in French (currency CHF).
    public static let switzerlandFrenchContext = StorefrontContext(country: .ch, language: .fr, visitorConsent: visitorConsent)

    /// The operation names the plan may send as mutations.
    public static let allowedMutations: Set<String> = [
        CartCreateMutation.operationName,
        CartLinesAddMutation.operationName,
        CartLinesUpdateMutation.operationName,
        CartDiscountCodesUpdateMutation.operationName,
        CartLinesRemoveMutation.operationName,
    ]

    /// The live fixtures in recording order.
    ///
    /// - Parameter isTokenless: Whether the main client has no token. With a token, the
    ///   product fixtures include metafields; the access-denied fixture is always recorded
    ///   without a token.
    public static func liveFixtures(isTokenless: Bool) throws -> [FixtureSpec] {
        try catalogFixtures(includeMetafields: !isTokenless) + collectionFixtures() + searchAndContentFixtures() + cartFixtures()
            + cartLifecycleFixtures() + [
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

    // MARK: Catalog

    private static func catalogFixtures(includeMetafields: Bool) throws -> [FixtureSpec] {
        try [
            .live(
                fileName: "localization_DE_DE.json",
                summary: "Store countries, currencies and languages in the DE/DE context.",
                operation: LocalizationQuery(),
                context: germanyContext,
                expectedOutcome: .success
            ) { data, _ in
                try require(!data.localization.availableCountries.isEmpty, "localization_DE_DE.json", "no countries")
            },
            .live(
                fileName: "product_\(productHandle)_DE_DE.json",
                summary: "Office 2024 Professional Plus with the ProductDetail fragment in the DE/DE context (EUR).",
                operation: ProductByHandleQuery(handle: productHandle, includeMetafields: includeMetafields),
                context: germanyContext,
                expectedOutcome: .success
            ) { data, session in
                let fileName = "product_\(productHandle)_DE_DE.json"
                guard let product = data.product, !product.variants.isEmpty else {
                    throw FixtureSpec.UnexpectedOutcome(fileName: fileName, detail: "product missing or without variants")
                }
                session.update { $0.productID = product.id }
            },
            .live(
                fileName: "product_\(productHandle)_CH_FR.json",
                summary: "The same product in the CH/FR context (French content, CHF prices).",
                operation: ProductByHandleQuery(handle: productHandle, includeMetafields: includeMetafields),
                context: switzerlandFrenchContext,
                expectedOutcome: .success
            ) { data, _ in
                try require(
                    data.product?.variants.isEmpty == false,
                    "product_\(productHandle)_CH_FR.json",
                    "product missing or without variants"
                )
            },
            .live(
                fileName: "product_not_found_DE_DE.json",
                summary: "product(handle:) for a handle that does not exist: data.product is null.",
                operation: ProductByHandleQuery(handle: missingProductHandle, includeMetafields: includeMetafields),
                context: germanyContext,
                expectedOutcome: .notFound
            ) { data, _ in
                try require(data.product == nil, "product_not_found_DE_DE.json", "product exists")
            },
        ]
    }

    private static func collectionFixtures() throws -> [FixtureSpec] {
        try [
            .live(
                fileName: "collection_\(collectionHandle)_DE_DE.json",
                summary: "The first 8 products of the bestseller collection in its default order, with the store's filters, DE/DE.",
                operation: CollectionProductsQuery(handle: collectionHandle, first: collectionPageSize, sortKey: .collectionDefault),
                context: germanyContext,
                expectedOutcome: .success
            ) { data, _ in
                try require(
                    data.collection?.products.nodes.count == collectionPageSize && data.collection?.filters.isEmpty == false,
                    "collection_\(collectionHandle)_DE_DE.json",
                    "collection missing, not \(collectionPageSize) products or no filters"
                )
            },
            .live(
                fileName: "collection_\(filteredCollectionHandle)_price_filtered_DE_DE.json",
                summary: "The windows collection sorted by price with the price filter 10 to 30 EUR, DE/DE.",
                operation: CollectionProductsQuery(
                    handle: filteredCollectionHandle,
                    first: collectionPageSize,
                    sortKey: .price,
                    filters: [priceFilter]
                ),
                context: germanyContext,
                expectedOutcome: .success
            ) { data, _ in
                let prices = data.collection?.products.nodes.map(\.price.amount) ?? []
                try require(
                    !prices.isEmpty && prices.allSatisfy { $0 >= 10 && $0 <= 30 } && prices == prices.sorted(),
                    "collection_\(filteredCollectionHandle)_price_filtered_DE_DE.json",
                    "no products, prices outside the filter or not ascending"
                )
            },
            .live(
                fileName: "collections_DE_DE.json",
                summary: "The store's collections by title (first 50), DE/DE.",
                operation: CollectionsQuery(first: 50),
                context: germanyContext,
                expectedOutcome: .success
            ) { data, _ in
                try require(
                    data.collections.nodes.contains { $0.collection.handle == collectionHandle },
                    "collections_DE_DE.json",
                    "bestseller missing"
                )
            },
            .deferred(
                fileName: "product_recommendations_related_DE_DE.json",
                summary: "RELATED recommendations for Office 2024 Professional Plus, DE/DE.",
                context: germanyContext,
                expectedOutcome: .success,
                makeOperation: { session in try ProductRecommendationsQuery(productID: requireProductID(session), intent: .related) },
                validate: { data, _ in
                    try require(
                        data.productRecommendations?.isEmpty == false,
                        "product_recommendations_related_DE_DE.json",
                        "no recommendations"
                    )
                }
            ),
            .deferred(
                fileName: "product_recommendations_complementary_DE_DE.json",
                summary: "COMPLEMENTARY recommendations for Office 2024 Professional Plus, DE/DE (the store configures none).",
                context: germanyContext,
                expectedOutcome: .success,
                makeOperation: { session in try ProductRecommendationsQuery(productID: requireProductID(session), intent: .complementary) },
                validate: { data, _ in
                    try require(data.productRecommendations != nil, "product_recommendations_complementary_DE_DE.json", "null result")
                }
            ),
        ]
    }

    // MARK: Search and content

    private static func searchAndContentFixtures() throws -> [FixtureSpec] {
        try [
            .live(
                fileName: "predictive_search_win_DE_DE.json",
                summary: "Predictive search for \"win\" (6 per type): products, collections, articles, query suggestions, DE/DE.",
                operation: PredictiveSearchQuery(query: predictiveQuery, limit: 6),
                context: germanyContext,
                expectedOutcome: .success
            ) { data, _ in
                try require(data.predictiveSearch?.products.isEmpty == false, "predictive_search_win_DE_DE.json", "no products")
            },
            .live(
                fileName: "search_office-2024_DE_DE.json",
                summary: "Product search for \"office 2024\" by relevance (first 8) with total count and filters, DE/DE.",
                operation: SearchProductsQuery(query: searchQuery, first: 8),
                context: germanyContext,
                expectedOutcome: .success
            ) { data, _ in
                try require(
                    data.search.totalCount > 0 && !data.search.products.isEmpty,
                    "search_office-2024_DE_DE.json",
                    "no results"
                )
            },
            .live(
                fileName: "blog_\(blogHandle)_articles_DE_DE.json",
                summary: "The 6 newest articles of the guides blog, DE/DE.",
                operation: BlogArticlesQuery(blogHandle: blogHandle, first: articleCount),
                context: germanyContext,
                expectedOutcome: .success
            ) { data, _ in
                try require(data.blog?.articles.nodes.isEmpty == false, "blog_\(blogHandle)_articles_DE_DE.json", "no articles")
            },
            .live(
                fileName: "article_\(blogHandle)_\(articleHandle)_DE_DE.json",
                summary: "One guide article with its contentHtml (style, script, image, tables, details, code), DE/DE.",
                operation: ArticleQuery(blogHandle: blogHandle, articleHandle: articleHandle),
                context: germanyContext,
                expectedOutcome: .success
            ) { data, _ in
                try require(
                    data.blog?.articleByHandle?.contentHtml.contains("<table") == true,
                    "article_\(blogHandle)_\(articleHandle)_DE_DE.json",
                    "article missing or without a table"
                )
            },
        ]
    }

    // MARK: Cart

    private static func cartFixtures() throws -> [FixtureSpec] {
        try [
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
            ) { data, _ in
                guard let payload = data.cartCreate, payload.cart == nil, !payload.userErrors.isEmpty else {
                    throw FixtureSpec.UnexpectedOutcome(
                        fileName: "cart_create_invalid_merchandise_DE_DE.json",
                        detail: "expected user errors and no cart"
                    )
                }
            },
            .deferred(
                fileName: "cart_create_DE_DE.json",
                summary: "cartCreate with 1x the cheapest digital variant, country DE and the recorder's attributes.",
                context: germanyContext,
                expectedOutcome: .success,
                prepare: { client, session in try await findCheapestDigitalVariants(client: client, session: session) },
                makeOperation: { session in
                    try CartCreateMutation(
                        lines: [CartLineInput(merchandiseId: variantID(0, session, "cart_create_DE_DE.json"), quantity: 1)],
                        countryCode: .de,
                        attributes: cartAttributes
                    )
                },
                validate: { data, session in
                    let cart = try requireCart(data.payload, lineCount: 1, "cart_create_DE_DE.json")
                    session.remember(cart)
                }
            ),
            .deferred(
                fileName: "cart_lines_add_DE_DE.json",
                summary: "cartLinesAdd with 1x the second cheapest digital variant: two lines.",
                context: germanyContext,
                expectedOutcome: .success,
                makeOperation: { session in
                    let fileName = "cart_lines_add_DE_DE.json"
                    return try CartLinesAddMutation(
                        cartID: session.requireCartID(for: fileName),
                        lines: [CartLineInput(merchandiseId: variantID(1, session, fileName), quantity: 1)]
                    )
                },
                validate: { data, session in
                    try session.remember(requireCart(data.payload, lineCount: 2, "cart_lines_add_DE_DE.json"))
                }
            ),
            .deferred(
                fileName: "cart_lines_update_DE_DE.json",
                summary: "cartLinesUpdate: the first line to quantity 2 (the store's automatic quantity discount applies).",
                context: germanyContext,
                expectedOutcome: .success,
                makeOperation: { session in
                    let fileName = "cart_lines_update_DE_DE.json"
                    return try CartLinesUpdateMutation(
                        cartID: session.requireCartID(for: fileName),
                        lines: [CartLineUpdateInput(id: session.requireLineID(variantIndex: 0, for: fileName), quantity: 2)]
                    )
                },
                validate: { data, session in
                    let cart = try requireCart(data.payload, lineCount: 2, "cart_lines_update_DE_DE.json")
                    try require(cart.totalQuantity == 3, "cart_lines_update_DE_DE.json", "total quantity is not 3")
                    session.remember(cart)
                }
            ),
        ]
    }

    private static func cartLifecycleFixtures() -> [FixtureSpec] {
        [
            .deferred(
                fileName: "cart_discount_codes_invalid_DE_DE.json",
                summary: "cartDiscountCodesUpdate with a code that does not exist: applicable false and a DISCOUNT_NOT_FOUND warning.",
                context: germanyContext,
                expectedOutcome: .success,
                makeOperation: { session in
                    try CartDiscountCodesUpdateMutation(
                        cartID: session.requireCartID(for: "cart_discount_codes_invalid_DE_DE.json"),
                        codes: [invalidDiscountCode]
                    )
                },
                validate: { data, _ in
                    let cart = try requireCart(data.payload, lineCount: 2, "cart_discount_codes_invalid_DE_DE.json")
                    try require(
                        cart.discountCodes == [CartDiscountCode(code: invalidDiscountCode, applicable: false)],
                        "cart_discount_codes_invalid_DE_DE.json",
                        "the code is missing or applicable"
                    )
                }
            ),
            .deferred(
                fileName: "cart_lines_remove_DE_DE.json",
                summary: "cartLinesRemove of the second line: one line left.",
                context: germanyContext,
                expectedOutcome: .success,
                makeOperation: { session in
                    let fileName = "cart_lines_remove_DE_DE.json"
                    return try CartLinesRemoveMutation(
                        cartID: session.requireCartID(for: fileName),
                        lineIDs: [session.requireLineID(variantIndex: 1, for: fileName)]
                    )
                },
                validate: { data, session in
                    try session.remember(requireCart(data.payload, lineCount: 1, "cart_lines_remove_DE_DE.json"))
                }
            ),
            .deferred(
                fileName: "cart_query_DE_DE.json",
                summary: "cart(id:) of the recorder's cart after the lifecycle: one line, quantity 2, the invalid code.",
                context: germanyContext,
                expectedOutcome: .success,
                makeOperation: { session in try CartQuery(id: session.requireCartID(for: "cart_query_DE_DE.json")) },
                validate: { data, _ in
                    try require(data.cart?.totalQuantity == 2, "cart_query_DE_DE.json", "cart missing or quantity not 2")
                }
            ),
        ]
    }

    /// Finds the two cheapest digital variants that are available for sale: the cheapest
    /// products of the `all` collection, then each product's default variant.
    static func findCheapestDigitalVariants(client: StorefrontClient, session: FixtureSession) async throws {
        let candidates = try await client.execute(
            CollectionProductsQuery(handle: allProductsHandle, first: 12, sortKey: .price),
            context: germanyContext
        ).collection?.products.nodes ?? []
        var variants: [ShopifyID] = []
        for summary in candidates where summary.availableForSale && summary.requiresShipping == false {
            let product = try await client.execute(
                ProductByHandleQuery(handle: summary.handle, includeMetafields: false),
                context: germanyContext
            ).product
            if let variant = product?.defaultVariant, variant.availableForSale, !variant.requiresShipping {
                variants.append(variant.id)
            }
            if variants.count == 2 {
                break
            }
        }
        guard variants.count == 2 else {
            throw FixtureSpec.UnexpectedOutcome(fileName: "cart_create_DE_DE.json", detail: "fewer than two digital variants found")
        }
        session.update { $0.variantIDs = variants }
    }

    // MARK: Helpers

    private static func require(_ condition: Bool, _ fileName: String, _ detail: String) throws {
        guard condition else {
            throw FixtureSpec.UnexpectedOutcome(fileName: fileName, detail: detail)
        }
    }

    private static func requireProductID(_ session: FixtureSession) throws -> ShopifyID {
        guard let productID = session.state.productID else {
            throw FixtureSpec.UnexpectedOutcome(fileName: "product_recommendations", detail: "the product fixture did not run")
        }
        return productID
    }

    private static func variantID(_ index: Int, _ session: FixtureSession, _ fileName: String) throws -> ShopifyID {
        let variants = session.state.variantIDs
        guard variants.indices.contains(index) else {
            throw FixtureSpec.UnexpectedOutcome(fileName: fileName, detail: "variant \(index) was not found")
        }
        return variants[index]
    }

    private static func requireCart(_ payload: CartMutationPayload?, lineCount: Int, _ fileName: String) throws -> Cart {
        guard let payload else {
            throw FixtureSpec.UnexpectedOutcome(fileName: fileName, detail: "no payload")
        }
        guard payload.userErrors.isEmpty else {
            throw FixtureSpec.UnexpectedOutcome(
                fileName: fileName,
                detail: "user errors \(ShopifyError.userErrors(payload.userErrors).logDescription)"
            )
        }
        guard let cart = payload.cart, cart.lines.count == lineCount else {
            throw FixtureSpec.UnexpectedOutcome(fileName: fileName, detail: "cart missing or not \(lineCount) line(s)")
        }
        return cart
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
        documentationURL: "https://shopify.dev/docs/api/storefront/2026-10#status-and-error-codes",
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
