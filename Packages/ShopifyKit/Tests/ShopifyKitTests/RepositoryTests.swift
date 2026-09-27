import Core
import Foundation
@testable import ShopifyKit
import Testing

@Suite("Repositories")
struct RepositoryTests {
    @Test("Tokenless catalog repository does not request metafields and sends no token")
    func tokenlessProduct() async throws {
        let stub = try StubHTTPClient([.fixture(Fixture.productDE)])
        let repository = StorefrontCatalogRepository(
            client: makeStorefrontClient(stub),
            contextProvider: StaticStorefrontContextProvider(context: germanyContext)
        )

        let product = try #require(try await repository.product(handle: "office-2024-professional-plus-key"))

        #expect(product.title == "Microsoft Office 2024 Professional Plus Download kaufen")
        let request = try #require(stub.requests.first)
        #expect(request.value(forHeader: StorefrontConfiguration.accessTokenHeader) == nil)
        let body = try SentGraphQLBody(request)
        #expect(body.variables["includeMetafields"] == .bool(false))
        #expect(body.query.contains("@include(if: $includeMetafields)"))
        #expect(body.query.contains("@inContext(country: DE, language: DE"))
    }

    @Test("With a token the repository requests metafields and sends the token header")
    func tokenProduct() async throws {
        let stub = try StubHTTPClient([.fixture(Fixture.productDE)])
        let repository = StorefrontCatalogRepository(
            client: makeStorefrontClient(stub, token: "public-storefront-token"),
            contextProvider: StaticStorefrontContextProvider(context: germanyContext)
        )

        _ = try await repository.product(handle: "office-2024-professional-plus-key")

        let request = try #require(stub.requests.first)
        #expect(request.value(forHeader: "x-shopify-storefront-access-token") == "public-storefront-token")
        #expect(try SentGraphQLBody(request).variables["includeMetafields"] == .bool(true))
    }

    @Test("Unknown product handle returns nil")
    func missingProduct() async throws {
        let stub = try StubHTTPClient([.fixture(Fixture.productNotFound)])
        let repository = StorefrontCatalogRepository(client: makeStorefrontClient(stub), contextProvider: StaticStorefrontContextProvider())
        #expect(try await repository.product(handle: "kx-fixture-no-such-product") == nil)
    }

    @Test("Collection page with sort and cursor, in the provider's current context")
    func collectionPage() async throws {
        let stub = try StubHTTPClient([.fixture(Fixture.collectionBestseller), .json(#"{"data":{"collection":null}}"#)])
        let provider = MutableStorefrontContextProvider(context: germanyContext)
        let repository = StorefrontCatalogRepository(client: makeStorefrontClient(stub), contextProvider: provider)

        let page = try #require(try await repository.collection(handle: "bestseller", first: 8, after: nil, sortKey: .collectionDefault))
        #expect(page.collection.title == "Bestseller günstig kaufen")
        #expect(page.products.count == 8)
        #expect(page.pageInfo.hasNextPage)

        provider.update(to: switzerlandFrenchContext)
        let next = try await repository.collection(
            handle: "missing",
            first: 500,
            after: page.pageInfo.nextPageCursor,
            sortKey: .price,
            reverse: true
        )
        #expect(next == nil)

        let firstBody = try SentGraphQLBody(stub.requests[0])
        #expect(firstBody.variables["sortKey"] == .string("COLLECTION_DEFAULT"))
        #expect(firstBody.variables["reverse"] == .bool(false))
        #expect(firstBody.variables["after"] == nil)

        let secondBody = try SentGraphQLBody(stub.requests[1])
        #expect(secondBody.variables["first"] == .number(250))
        #expect(secondBody.variables["sortKey"] == .string("PRICE"))
        #expect(secondBody.variables["reverse"] == .bool(true))
        #expect(secondBody.variables["after"] == .string("eyJsYXN0X2lkIjoxMDY1MTQ4Mjc4NDAxMSwibGFzdF92YWx1ZSI6NjUsIm9mZnNldCI6N30="))
        #expect(secondBody.query.contains("@inContext(country: CH, language: FR,"))
    }

    @Test("Localization repository")
    func localizationRepository() async throws {
        let stub = try StubHTTPClient([.fixture(Fixture.localization)])
        let repository = StorefrontLocalizationRepository(
            client: makeStorefrontClient(stub),
            contextProvider: StaticStorefrontContextProvider(context: germanyContext)
        )
        let localization = try await repository.localization()
        #expect(localization.availableCountries.count == 28)
        #expect(try SentGraphQLBody(#require(stub.requests.first)).operationName == "Localization")
    }

    @Test("Cart repository surfaces user errors as ShopifyError.userErrors with code and field path")
    func cartUserErrors() async throws {
        let stub = try StubHTTPClient([.fixture(Fixture.cartCreateInvalidMerchandise)])
        let repository = StorefrontCartRepository(
            client: makeStorefrontClient(stub),
            contextProvider: StaticStorefrontContextProvider(context: germanyContext)
        )

        do {
            _ = try await repository.createCart(
                lines: [CartLineInput(merchandiseId: "gid://shopify/ProductVariant/1", quantity: 1)],
                attributes: [AttributeInput(key: "app_platform", value: "ios")]
            )
            Issue.record("Expected user errors")
        } catch let ShopifyError.userErrors(errors) {
            #expect(errors.count == 1)
            #expect(errors.first?.code == .invalid)
            #expect(errors.first?.field == ["input", "lines", "0", "merchandiseId"])
        }

        let body = try SentGraphQLBody(#require(stub.requests.first))
        #expect(body.operationName == "CartCreate")
        #expect(body.query.hasPrefix("mutation CartCreate($input: CartInput!) @inContext(country: DE, language: DE,"))
        let expectedInput: JSONAny = .object([
            "lines": .array([.object(["merchandiseId": .string("gid://shopify/ProductVariant/1"), "quantity": .number(1)])]),
            "buyerIdentity": .object(["countryCode": .string("DE")]),
            "attributes": .array([.object(["key": .string("app_platform"), "value": .string("ios")])]),
        ])
        #expect(body.variables["input"] == expectedInput)
    }

    @Test("Cart repository returns the created cart")
    func cartCreated() async throws {
        let body = """
            {"data": {"cartCreate": {"cart": {"id": "gid://shopify/Cart/test-token?key=test-key",
            "checkoutUrl": "https://www.karinex.de/cart/c/test-token?key=test-key", "totalQuantity": 2},
            "userErrors": [],
            "warnings": [{"code": "MERCHANDISE_NOT_ENOUGH_STOCK", "message": "m", "target": "gid://shopify/CartLine/1"}]}}}
            """
        let stub = StubHTTPClient([.json(body)])
        let repository = StorefrontCartRepository(client: makeStorefrontClient(stub), contextProvider: StaticStorefrontContextProvider())

        let line = CartLineInput(merchandiseId: "gid://shopify/ProductVariant/52710041846027", quantity: 2)
        let cart = try await repository.createCart(lines: [line], attributes: [])

        #expect(cart.id.resourceType == "Cart")
        #expect(cart.totalQuantity == 2)
        #expect(cart.checkoutUrl.host == "www.karinex.de")
        let sent = try SentGraphQLBody(#require(stub.requests.first))
        guard case let .object(input)? = sent.variables["input"] else {
            Issue.record("input missing")
            return
        }
        #expect(input["attributes"] == nil)
    }
}
