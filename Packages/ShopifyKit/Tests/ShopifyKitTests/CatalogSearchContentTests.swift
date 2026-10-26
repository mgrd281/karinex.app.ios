import Core
import Foundation
@testable import ShopifyKit
import Testing

/// Collections, filters, recommendations, search and blog content: recorded fixtures
/// (2026-10-24, DE/DE) through the real client, and the repositories against a stub transport.
@Suite("Catalog, search and content")
struct CatalogSearchContentTests {
    private func context() -> StaticStorefrontContextProvider {
        StaticStorefrontContextProvider(context: germanyContext)
    }

    // MARK: - Collections and filters

    @Test("The bestseller page carries the store's availability and price filters")
    func collectionFilters() async throws {
        let stub = try StubHTTPClient([.fixture(Fixture.collectionBestseller)])
        let repository = StorefrontCatalogRepository(client: makeStorefrontClient(stub), contextProvider: context())

        let page = try #require(try await repository.collection(handle: "bestseller", first: 8))
        #expect(page.filters.map(\.id) == ["filter.v.availability", "filter.v.price"])

        let availability = try #require(page.filters.first)
        #expect(availability.label == "Verfügbarkeit")
        #expect(availability.type == "LIST")
        #expect(!availability.isPriceRange)
        let inStock = try #require(availability.values.first)
        #expect(inStock.id == "filter.v.availability.1")
        #expect(inStock.label == "Auf Lager")
        #expect(inStock.count == 22)
        #expect(inStock.input == .available(true))
        #expect(inStock.input.rawJSON == #"{"available":true}"#)

        let price = try #require(page.filters.last)
        #expect(price.isPriceRange)
        let bounds = try #require(price.values.first?.input.priceBounds)
        #expect(bounds.minimum == 0)
        #expect(bounds.maximum == decimal("239.9"))

        let body = try SentGraphQLBody(#require(stub.requests.first))
        #expect(body.variables["filters"] == nil)
        #expect(body.variables["sortKey"] == .string("COLLECTION_DEFAULT"))
        #expect(body.variables["first"] == .number(8))
    }

    @Test("Filters are sent back as JSON objects, and the filtered page is sorted by price")
    func filteredCollection() async throws {
        let stub = try StubHTTPClient([.fixture(Fixture.collectionWindowsPriceFiltered)])
        let repository = StorefrontCatalogRepository(client: makeStorefrontClient(stub), contextProvider: context())
        let filters = [ProductFilterInput(rawJSON: #"{"price":{"min":10,"max":30}}"#), .available(true)]

        let page = try #require(
            try await repository.collection(handle: "windows", first: 8, after: nil, sortKey: .price, reverse: false, filters: filters)
        )
        let prices = page.products.map(\.price.amount)
        #expect(page.products.count == 8)
        #expect(prices == prices.sorted())
        #expect(prices.allSatisfy { $0 >= 10 && $0 <= 30 })
        #expect(page.products.first?.handle == "windows-10-professional-lizenz")
        // Shopify echoes the applied price range in the price filter value.
        #expect(page.filters.last?.values.first?.input == .price(minimum: 10, maximum: 30))

        let body = try SentGraphQLBody(#require(stub.requests.first))
        #expect(body.variables["sortKey"] == .string("PRICE"))
        #expect(body.variables["filters"] == .array([
            .object(["price": .object(["min": .number(10), "max": .number(30)])]),
            .object(["available": .bool(true)]),
        ]))
    }

    @Test("Collections list and recommendations")
    func collectionsAndRecommendations() async throws {
        let stub = try StubHTTPClient([
            .fixture(Fixture.collections),
            .fixture(Fixture.recommendationsRelated),
            .fixture(Fixture.recommendationsComplementary),
            .json(#"{"data":{"productRecommendations":null}}"#),
        ])
        let repository = StorefrontCatalogRepository(client: makeStorefrontClient(stub), contextProvider: context())
        let productID: ShopifyID = "gid://shopify/Product/10534352027915"

        let collections = try await repository.collections(first: 500)
        #expect(collections.count == 29)
        #expect(collections.first?.handle == "bestseller")
        #expect(collections.map(\.handle).contains("visual-studio-entwicklungstools"))
        #expect(collections.map(\.handle).contains("all"))

        let related = try await repository.recommendations(productID: productID, intent: .related)
        #expect(related.count == 10)
        #expect(related.first?.handle == "windows-11-pro-key-kaufen-download")
        #expect(!related.contains { $0.id == productID })
        #expect(try await repository.recommendations(productID: productID, intent: .complementary).isEmpty)
        #expect(try await repository.recommendations(productID: "gid://shopify/Product/1", intent: .related).isEmpty)

        let bodies = try stub.requests.map(SentGraphQLBody.init)
        #expect(bodies[0].variables["first"] == .number(250))
        #expect(bodies[1].variables["productId"] == .string(productID.rawValue))
        #expect(bodies[1].variables["intent"] == .string("RELATED"))
        #expect(bodies[2].variables["intent"] == .string("COMPLEMENTARY"))
    }

    @Test("Each listed collection carries the photo of its first product that has one")
    func collectionPreviewImages() async throws {
        let stub = StubHTTPClient([
            .json(#"""
                {"data":{"collections":{"nodes":[
                  {"id":"gid://shopify/Collection/1","handle":"windows","title":"Windows","description":"","image":null,
                   "products":{"nodes":[{"featuredImage":{
                     "url":"https://cdn.shopify.com/s/files/w.png","altText":"Windows 11 Pro","width":800,"height":800
                   }}]}},
                  {"id":"gid://shopify/Collection/3","handle":"windows-server-2022","title":"Windows Server 2022","description":"",
                   "image":null,"products":{"nodes":[{"featuredImage":null},{"featuredImage":{
                     "url":"https://cdn.shopify.com/s/files/s.png","altText":null,"width":800,"height":800
                   }}]}},
                  {"id":"gid://shopify/Collection/2","handle":"leer","title":"Leer","description":"","image":null,"products":{"nodes":[]}}
                ]}}}
                """#),
        ])
        let repository = StorefrontCatalogRepository(client: makeStorefrontClient(stub), contextProvider: context())

        let collections = try await repository.collections(first: 60)

        #expect(collections.map(\.handle) == ["windows", "windows-server-2022", "leer"])
        let windows = try #require(collections.first)
        #expect(windows.image == nil)
        #expect(windows.previewImage?.url.absoluteString == "https://cdn.shopify.com/s/files/w.png")
        #expect(windows.previewImage?.altText == "Windows 11 Pro")
        #expect(windows.displayImage == windows.previewImage)
        #expect(collections[1].previewImage?.url.absoluteString == "https://cdn.shopify.com/s/files/s.png")
        #expect(collections.last?.previewImage == nil)
        #expect(collections.last?.displayImage == nil)
        #expect(try JSONDecoder().decode([CollectionSummary].self, from: JSONEncoder().encode(collections)) == collections)

        let body = try SentGraphQLBody(#require(stub.requests.first))
        #expect(body.query.contains("products(first: \(CollectionsQuery.previewProductCount))"))
        #expect(CollectionsQuery.previewProductCount == 3)
        #expect(body.variables["first"] == .number(60))
    }

    @Test("Collections with filters encode back into the shape they decode from")
    func collectionRoundTrip() throws {
        let collection = try #require(try Fixture.decode(CollectionProductsQuery.ResponseData.self, from: Fixture.collectionBestseller)
            .collection)
        #expect(!collection.filters.isEmpty)
        #expect(try JSONDecoder().decode(ProductCollection.self, from: JSONEncoder().encode(collection)) == collection)
        #expect(CollectionPage(collection: collection).filters == collection.filters)
    }

    // MARK: - Search

    @Test("Predictive search for win: products, collections and articles of both blogs")
    func predictive() async throws {
        let stub = try StubHTTPClient([.fixture(Fixture.predictiveSearchWin)])
        let repository = StorefrontSearchRepository(client: makeStorefrontClient(stub), contextProvider: context())

        let result = try await repository.predictive(query: "  win ", limit: 50)
        #expect(!result.isEmpty)
        #expect(result.products.count == 6)
        #expect(result.products.first?.handle == "windows-11-pro-key-kaufen-download")
        #expect(result.collections.map(\.handle).prefix(2) == ["windows", "windows-8"])
        #expect(result.articles.count == 6)
        #expect(Set(result.articles.map(\.blogHandle)) == ["news", "guides"])
        #expect(result.queries.isEmpty)

        let body = try SentGraphQLBody(#require(stub.requests.first))
        #expect(body.variables["query"] == .string("win"))
        #expect(body.variables["limit"] == .number(10))
    }

    @Test("A blank query returns empty results without a request")
    func blankQueries() async throws {
        let stub = StubHTTPClient()
        let repository = StorefrontSearchRepository(client: makeStorefrontClient(stub), contextProvider: context())
        #expect(try await repository.predictive(query: " \n", limit: 5) == .empty)
        #expect(try await repository.products(query: "", first: 10, after: nil, sortKey: .relevance, reverse: false, filters: []) == .empty)
        #expect(stub.requests.isEmpty)
    }

    @Test("Query suggestions decode their styled text")
    func suggestions() throws {
        let json = #"{"products":[],"collections":[],"articles":[],"#
            + #""queries":[{"text":"windows 11","styledText":"win<mark>dows 11</mark>"}]}"#
        let result = try JSONDecoder().decode(PredictiveSearchResult.self, from: Data(json.utf8))
        let suggestion = try #require(result.queries.first)
        #expect(suggestion.id == "windows 11")
        #expect(suggestion.styledText == "win<mark>dows 11</mark>")
        #expect(SearchQuerySuggestion(text: "office").styledText == "office")
    }

    @Test("Full search for office 2024: total count, filters, products and pagination")
    func search() async throws {
        let stub = try StubHTTPClient([.fixture(Fixture.searchOffice2024)])
        let repository = StorefrontSearchRepository(client: makeStorefrontClient(stub), contextProvider: context())

        let page = try await repository.products(
            query: "office 2024",
            first: 8,
            after: "cursor",
            sortKey: .price,
            reverse: true,
            filters: [.available(true)]
        )
        #expect(page.totalCount == 15)
        #expect(page.products.count == 8)
        #expect(page.products.first?.handle == "microsoft-office-2024-standard-vollversion-fur-windows")
        #expect(page.filters.map(\.id) == ["filter.v.availability", "filter.v.price"])
        #expect(page.pageInfo.hasNextPage)
        #expect(page.pageInfo.nextPageCursor != nil)

        let body = try SentGraphQLBody(#require(stub.requests.first))
        #expect(body.operationName == "SearchProducts")
        #expect(body.variables["query"] == .string("office 2024"))
        #expect(body.variables["sortKey"] == .string("PRICE"))
        #expect(body.variables["reverse"] == .bool(true))
        #expect(body.variables["after"] == .string("cursor"))
        #expect(body.variables["filters"] == .array([.object(["available": .bool(true)])]))
        #expect(body.query.contains("types: [PRODUCT]"))
    }

    @Test("Search results of other types are skipped")
    func searchSkipsOtherTypes() throws {
        let money = #"{"amount":"1.0","currencyCode":"EUR"}"#
        let json = """
            {"totalCount":2,"productFilters":[],
            "pageInfo":{"hasNextPage":false,"hasPreviousPage":false,"startCursor":null,"endCursor":null},
            "nodes":[{"__typename":"Page"},{"__typename":"Product","id":"gid://shopify/Product/1","handle":"h","title":"T","vendor":"V",
            "availableForSale":true,"featuredImage":null,"priceRange":{"minVariantPrice":\(money),"maxVariantPrice":\(money)},
            "compareAtPriceRange":{"minVariantPrice":\(money),"maxVariantPrice":\(money)},"variants":{"nodes":[]}}]}
            """
        let connection = try JSONDecoder().decode(SearchProductsQuery.SearchConnection.self, from: Data(json.utf8))
        #expect(connection.products.map(\.handle) == ["h"])
        #expect(connection.page.totalCount == 2)
    }

    // MARK: - Content

    @Test("Guides blog: the newest articles with excerpt, date, image and web URL")
    func articles() async throws {
        let stub = try StubHTTPClient([.fixture(Fixture.blogGuidesArticles), .json(#"{"data":{"blog":null}}"#)])
        let repository = StorefrontContentRepository(client: makeStorefrontClient(stub), contextProvider: context())

        let articles = try await repository.articles(blogHandle: "guides", first: 6)
        #expect(articles.count == 6)
        let newest = try #require(articles.first)
        #expect(newest.handle == "windows-testgeraet-systeminformationen-dokumentieren")
        #expect(newest.blogHandle == "guides")
        #expect(newest.id.resourceType == "Article")
        #expect(newest.excerpt?.isEmpty == false)
        #expect(newest.image == nil)
        #expect(newest.publishedAt == Date(timeIntervalSince1970: 1_788_038_195))
        #expect(newest.onlineStoreUrl?
            .absoluteString == "https://www.karinex.de/blogs/guides/windows-testgeraet-systeminformationen-dokumentieren")
        #expect(articles.map(\.publishedAt) == articles.map(\.publishedAt).sorted(by: >))
        #expect(articles[1].image?.width == 1248)
        #expect(try JSONDecoder().decode([ArticleSummary].self, from: JSONEncoder().encode(articles)) == articles)

        #expect(try await repository.articles(blogHandle: "missing", first: 3).isEmpty)
        let body = try SentGraphQLBody(stub.requests[0])
        #expect(body.variables["blogHandle"] == .string("guides"))
        #expect(body.variables["first"] == .number(6))
    }

    @Test("One article with author name, image and HTML body; missing articles are nil")
    func article() async throws {
        let stub = try StubHTTPClient([
            .fixture(Fixture.articleGuide),
            .json(#"{"data":{"blog":{"articleByHandle":null}}}"#),
            .json(#"{"data":{"blog":null}}"#),
        ])
        let repository = StorefrontContentRepository(client: makeStorefrontClient(stub), contextProvider: context())

        let article = try #require(try await repository.article(blogHandle: "guides", handle: "windows-11-kompatibilitaet-pruefen"))
        #expect(article.title == "Windows 11 Kompatibilität prüfen: Ist Ihr PC bereit?")
        #expect(article.authorName == "KARINEX Redaktion")
        #expect(article.blogHandle == "guides")
        #expect(article.image?.height == 832)
        #expect(article.contentHtml.contains("<table"))
        #expect(article.publishedAt == Date(timeIntervalSince1970: 1_788_017_585))
        #expect(!article.document.isEmpty)
        #expect(try JSONDecoder().decode(Article.self, from: JSONEncoder().encode(article)) == article)

        #expect(try await repository.article(blogHandle: "guides", handle: "missing") == nil)
        #expect(try await repository.article(blogHandle: "missing", handle: "missing") == nil)
        let body = try SentGraphQLBody(stub.requests[0])
        #expect(body.variables["articleHandle"] == .string("windows-11-kompatibilitaet-pruefen"))
    }

    @Test("Article dates accept fractional seconds; malformed dates fail decoding")
    func articleDates() throws {
        #expect(ArticleCoding.date(from: "2026-08-29T15:33:05Z") == Date(timeIntervalSince1970: 1_788_017_585))
        #expect(ArticleCoding.date(from: "2026-08-29T15:33:05.500Z") == Date(timeIntervalSince1970: 1_788_017_585.5))
        #expect(ArticleCoding.date(from: "29.08.2026") == nil)
        let json = #"{"id":"gid://shopify/Article/1","handle":"a","title":"T","excerpt":" ","publishedAt":"yesterday","#
            + #""image":null,"onlineStoreUrl":null,"blog":{"handle":"b"}}"#
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ArticleSummary.self, from: Data(json.utf8))
        }
        let valid = json.replacingOccurrences(of: "yesterday", with: "2026-01-01T00:00:00Z")
        #expect(try JSONDecoder().decode(ArticleSummary.self, from: Data(valid.utf8)).excerpt == nil)
    }
}

// MARK: - Model additions

@Suite("Filter inputs and markets")
struct FilterInputAndMarketTests {
    @Test("Filter inputs compare by JSON value and encode as objects")
    func filterInputs() throws {
        let fromShopify = ProductFilterInput(rawJSON: #"{"price":{"min":10.00,"max":30.00}}"#)
        let built = ProductFilterInput.price(minimum: 10, maximum: 30)
        #expect(fromShopify == built)
        #expect(fromShopify.hashValue == built.hashValue)
        #expect(fromShopify.rawJSON == #"{"price":{"min":10.00,"max":30.00}}"#)
        #expect(ProductFilterInput.available(true) != ProductFilterInput.available(false))
        #expect(ProductFilterInput.price(minimum: nil, maximum: 5).priceBounds?.minimum == nil)
        #expect(ProductFilterInput.available(true).priceBounds == nil)

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let encoded = try String(decoding: encoder.encode([fromShopify]), as: UTF8.self)
        #expect(encoded == #"[{"price":{"max":30,"min":10}}]"#)
        #expect(try JSONDecoder().decode([ProductFilterInput].self, from: Data(encoded.utf8)) == [fromShopify])
        let fractional = try String(decoding: encoder.encode(ProductFilterInput(rawJSON: #"{"price":{"max":239.9}}"#)), as: UTF8.self)
        #expect(fractional == #"{"price":{"max":239.9}}"#)
    }

    @Test("Invalid filter input JSON is kept but cannot be sent")
    func invalidFilterInput() {
        let invalid = ProductFilterInput(rawJSON: "not json")
        #expect(invalid.rawJSON == "not json")
        #expect(throws: EncodingError.self) {
            try JSONEncoder().encode([invalid])
        }
        #expect(throws: EncodingError.self) {
            try JSONEncoder().encode([ProductFilterInput(rawJSON: "[1,2]")])
        }
    }

    @Test("Filter values decode Shopify's JSON text and every scalar kind")
    func filterValueDecoding() throws {
        let json = #"{"id":"v","label":"L","count":3,"input":"{\"tag\":\"x\",\"n\":null,\"list\":[1,true]}"}"#
        let value = try JSONDecoder().decode(ProductFilterValue.self, from: Data(json.utf8))
        #expect(value.input == ProductFilterInput(rawJSON: #"{"list":[1,true],"n":null,"tag":"x"}"#))
        #expect(try JSONDecoder().decode(ProductFilterValue.self, from: JSONEncoder().encode(value)) == value)
    }

    @Test("EU membership drives the tax wording: 27 states, Switzerland and Norway are not members")
    func euMembers() {
        #expect(CountryCode.euMemberStates.count == 27)
        #expect(CountryCode.de.isEUMember)
        #expect(CountryCode.gr.isEUMember)
        #expect(CountryCode("at").isEUMember)
        #expect(!CountryCode.ch.isEUMember)
        #expect(!CountryCode.no.isEUMember)
        #expect(!CountryCode.us.isEUMember)
        #expect(!CountryCode("GB").isEUMember)
        let storeCountries = CountryCode.recordedStoreCountries
        #expect(storeCountries.filter { !$0.isEUMember } == [.ch])
    }
}
