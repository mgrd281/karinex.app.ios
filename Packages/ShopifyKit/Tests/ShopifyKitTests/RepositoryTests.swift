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

    @Test("Every nullable field of the API decodes through the real client when it is null")
    func nullableFieldsDecode() async throws {
        let money = #"{"amount":"12.9","currencyCode":"EUR"}"#
        let zero = #"{"amount":"0.0","currencyCode":"EUR"}"#
        let body = """
            {"data":{"product":{"id":"gid://shopify/Product/1","handle":"h","title":"T","vendor":"V","productType":"",
            "tags":[],"availableForSale":false,"descriptionHtml":"","onlineStoreUrl":null,"featuredImage":null,
            "images":{"nodes":[{"url":"https://cdn.shopify.com/a.webp","altText":null,"width":null,"height":null}]},
            "options":[{"id":"gid://shopify/ProductOption/1","name":"Title","optionValues":[{"id":null,"name":"Default Title"}]}],
            "variants":{"nodes":[{"id":"gid://shopify/ProductVariant/2","title":"Default Title","sku":null,
            "availableForSale":false,"requiresShipping":true,"price":\(money),"compareAtPrice":null,
            "selectedOptions":[{"name":"Title","value":"Default Title"}],"image":null}]},
            "seo":{"title":null,"description":null},"collections":{"nodes":[]},
            "priceRange":{"minVariantPrice":\(money),"maxVariantPrice":\(money)},
            "compareAtPriceRange":{"minVariantPrice":\(zero),"maxVariantPrice":\(zero)},
            "metafields":[null,null]}}}
            """
        let stub = StubHTTPClient([.json(body)])
        let repository = StorefrontCatalogRepository(
            client: makeStorefrontClient(stub, token: "public-storefront-token"),
            contextProvider: StaticStorefrontContextProvider(context: germanyContext)
        )

        let product = try #require(try await repository.product(handle: "h"))
        let variant = try #require(product.variants.first)
        #expect(product.featuredImage == nil)
        #expect(product.onlineStoreUrl == nil)
        #expect(product.seo == SEO(title: nil, description: nil))
        #expect(product.metafields.isEmpty)
        #expect(product.images.first?.altText == nil)
        #expect(product.images.first?.aspectRatio == nil)
        #expect(product.options.first?.optionValues.first?.id == nil)
        #expect(variant.sku == nil)
        #expect(variant.compareAtPrice == nil)
        #expect(!variant.isDiscounted)
        #expect(variant.image == nil)
        #expect(!product.isDigitalOnly)
        #expect(product.compareAtPriceRange.isZero)

        let collectionBody = """
            {"data":{"collection":{"id":"gid://shopify/Collection/1","handle":"c","title":"C","description":"","image":null,
            "products":{"nodes":[{"id":"gid://shopify/Product/1","handle":"h","title":"T","vendor":"V","availableForSale":true,
            "featuredImage":null,"priceRange":{"minVariantPrice":\(money),"maxVariantPrice":\(money)},
            "compareAtPriceRange":{"minVariantPrice":\(zero),"maxVariantPrice":\(zero)},"variants":{"nodes":[]}}],
            "pageInfo":{"hasNextPage":false,"hasPreviousPage":false,"startCursor":null,"endCursor":null}}}}}
            """
        stub.enqueue(.json(collectionBody))
        let page = try #require(try await repository.collection(handle: "c", first: 1))
        let summary = try #require(page.products.first)
        #expect(page.collection.image == nil)
        #expect(summary.featuredImage == nil)
        #expect(summary.requiresShipping == nil)
        #expect(summary.compareAtPrice == nil)
        #expect(page.pageInfo.nextPageCursor == nil)
    }

    @Test("Unknown user error and warning codes from Shopify decode and surface as typed errors")
    func unknownCodes() async throws {
        let body = """
            {"data":{"cartCreate":{"cart":null,"userErrors":[{"field":null,"message":"m","code":"SOME_FUTURE_CODE"},
            {"field":["input"],"message":"n","code":null}],
            "warnings":[{"code":"SOME_FUTURE_WARNING","message":"w","target":"gid://shopify/CartLine/1"}]}}}
            """
        let stub = StubHTTPClient([.json(body)])
        let repository = StorefrontCartRepository(client: makeStorefrontClient(stub), contextProvider: StaticStorefrontContextProvider())
        await #expect(
            throws: ShopifyError.userErrors([
                UserError(field: nil, message: "m", code: .unknown("SOME_FUTURE_CODE")),
                UserError(field: ["input"], message: "n", code: nil),
            ])
        ) {
            _ = try await repository.createCart(lines: [CartLineInput(merchandiseId: "gid://shopify/ProductVariant/1")], attributes: [])
        }
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
