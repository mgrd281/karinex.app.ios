import Core
@testable import FixtureRecording
import Foundation
import ShopifyKit
import Testing

// MARK: - JSONValue

@Suite("JSONValue")
struct JSONValueTests {
    @Test("Pretty prints deterministically with sorted keys and compact empty containers")
    func prettyPrinting() throws {
        let object = try JSONValue.parseObject(Data(#"{"b":[],"a":{"z":null,"y":true,"x":1.5,"w":46},"c":{},"d":"ü/\"x\"\n"}"#.utf8))
        let printed = String(decoding: JSONValue.object(object).prettyPrintedData(), as: UTF8.self)
        #expect(printed == """
            {
              "a": {
                "w": 46,
                "x": 1.5,
                "y": true,
                "z": null
              },
              "b": [],
              "c": {},
              "d": "ü/\\"x\\"\\n"
            }

            """)
    }

    @Test("Round trips through the pretty printer")
    func roundTrip() throws {
        let source = Data(#"{"data":{"amount":"29.9","flags":[true,false],"count":0,"nested":[{"k":"v"}]}}"#.utf8)
        let object = try JSONValue.parseObject(source)
        let reparsed = try JSONValue.parseObject(JSONValue.object(object).prettyPrintedData())
        #expect(reparsed == object)
    }

    @Test("Rejects bodies that are not JSON objects")
    func rejectsNonObjects() {
        #expect(throws: JSONValue.Failure.notAJSONObject) {
            try JSONValue.parseObject(Data("[1,2]".utf8))
        }
    }
}

// MARK: - FixtureAnonymizer

@Suite("FixtureAnonymizer")
struct FixtureAnonymizerTests {
    @Test("Replaces cart tokens and personal fields with REDACTED, keeps the shape and catalog data")
    func anonymizes() throws {
        let body = Data("""
            {"data": {"cartCreate": {"cart": {"id": "gid://shopify/Cart/c1-abcdefgh?key=keyvalue123",
             "checkoutUrl": "https://www.karinex.de/cart/c/c1-abcdefgh?key=other-key-456&_cs=3am",
             "lines": {"nodes": [{"id": "gid://shopify/CartLine/0f3c-line?cart=c1-abcdefgh"}]},
             "note": "", "totalQuantity": 1},
             "buyer": {"email": "someone@example.com"},
             "warnings": [{"target": "gid://shopify/Cart/c1-abcdefgh", "message": "Cart c1-abcdefgh changed"}],
             "userErrors": [{"message": "Line gid://shopify/CartLine/xyz?cart=c1-abcdefgh invalid", "field": null}]},
             "product": {"id": "gid://shopify/Product/10534352027915", "handle": "office-2024-professional-plus-key"}}}
            """.utf8)
        let (object, paths) = try FixtureAnonymizer.anonymize(JSONValue.parseObject(body))
        let printed = String(decoding: JSONValue.object(object).prettyPrintedData(), as: UTF8.self)

        #expect(printed.contains("\"gid://shopify/Cart/REDACTED?key=REDACTED\""))
        #expect(printed.contains("\"https://www.karinex.de/cart/c/REDACTED?key=REDACTED&_cs=REDACTED\""))
        #expect(printed.contains("\"gid://shopify/CartLine/0f3c-line?cart=REDACTED\""))
        #expect(printed.contains("Line gid://shopify/CartLine/xyz?cart=REDACTED invalid"))
        #expect(printed.contains("\"target\": \"gid://shopify/Cart/REDACTED\""))
        #expect(printed.contains("Cart REDACTED changed"))
        #expect(printed.contains("\"email\": \"REDACTED\""))
        #expect(printed.contains("\"note\": \"\""))
        #expect(printed.contains("gid://shopify/Product/10534352027915"))
        #expect(!printed.contains("abcdefgh"))
        #expect(!printed.contains("keyvalue123"))
        #expect(!printed.contains("other-key-456"))
        #expect(!printed.contains("3am"))
        #expect(!printed.contains("example.com"))
        #expect(paths.sorted() == [
            "data.cartCreate.buyer.email",
            "data.cartCreate.cart.checkoutUrl",
            "data.cartCreate.cart.id",
            "data.cartCreate.cart.lines.nodes[0].id",
            "data.cartCreate.userErrors[0].message",
            "data.cartCreate.warnings[0].message",
            "data.cartCreate.warnings[0].target",
        ])
    }

    @Test("Anonymizes request variables the same way")
    func variables() {
        let variables: [String: JSONValue] = [
            "variables": .object([
                "cartId": .string("gid://shopify/Cart/token-123456?key=secret-key-1"),
                "lineIds": .array([.string("gid://shopify/CartLine/line-1?cart=token-123456")]),
                "discountCodes": .array([.string("KX-FIXTURE-NOT-A-CODE")]),
            ]),
        ]
        let (object, paths) = FixtureAnonymizer.anonymize(variables)
        #expect(object["variables"] == .object([
            "cartId": .string("gid://shopify/Cart/REDACTED?key=REDACTED"),
            "lineIds": .array([.string("gid://shopify/CartLine/line-1?cart=REDACTED")]),
            "discountCodes": .array([.string("KX-FIXTURE-NOT-A-CODE")]),
        ]))
        #expect(paths.sorted() == ["variables.cartId", "variables.lineIds[0]"])
    }

    @Test("Leaves fixtures without customer data unchanged")
    func unchanged() throws {
        let object = try JSONValue.parseObject(Data(#"{"data":{"cartCreate":{"cart":null,"userErrors":[]}},"x":"short?key=v"}"#.utf8))
        let (result, paths) = FixtureAnonymizer.anonymize(object)
        #expect(result == object)
        #expect(paths.isEmpty)
    }
}

// MARK: - CommandLineOptions

@Suite("CommandLineOptions")
struct CommandLineOptionsTests {
    private let workingDirectory = URL(fileURLWithPath: "/work", isDirectory: true)

    @Test("Defaults to the live store, API 2026-10 and tokenless mode")
    func defaults() throws {
        let options = try CommandLineOptions.parse(["--output", "Fixtures"], currentDirectory: workingDirectory)
        #expect(options.shopDomain == "45dv93-bk.myshopify.com")
        #expect(options.apiVersion == "2026-10")
        #expect(options.token == nil)
        #expect(options.outputDirectory.path == "/work/Fixtures")
        #expect(options.storefrontConfiguration.endpoint.absoluteString == "https://45dv93-bk.myshopify.com/api/2026-10/graphql.json")
        #expect(options.storefrontConfiguration.isTokenless)
    }

    @Test("Reads every option and the token from the environment")
    func allOptions() throws {
        let options = try CommandLineOptions.parse(
            ["--shop-domain", "Example.myshopify.com", "--api-version", "2026-10", "--output", "/tmp/out"],
            environment: ["KX_STOREFRONT_TOKEN": " public-token "],
            currentDirectory: workingDirectory
        )
        #expect(options.shopDomain == "example.myshopify.com")
        #expect(options.apiVersion == "2026-10")
        #expect(options.token == "public-token")
        #expect(options.outputDirectory.path == "/tmp/out")
        #expect(options.storefrontConfiguration.isTokenless == false)
    }

    @Test("Descriptions and dumps never contain the token")
    func maskedToken() throws {
        let options = try CommandLineOptions.parse(
            ["--token", "0123456789abcdef-public-token", "--output", "out"],
            currentDirectory: workingDirectory
        )
        #expect(options.token == "0123456789abcdef-public-token")
        #expect(!options.description.contains("public-token"))
        #expect(!String(reflecting: options).contains("public-token"))
        #expect(options.description.contains("token: <redacted>"))
        var dumped = ""
        dump(options, to: &dumped)
        #expect(!dumped.contains("public-token"))
        #expect(dumped.contains("45dv93-bk.myshopify.com"))
        #expect(try CommandLineOptions.parse(["--output", "out"], currentDirectory: workingDirectory).description.contains("token: nil"))
    }

    @Test("Rejects invalid command lines")
    func errors() {
        #expect(throws: CommandLineOptions.ParseError.missingOutput) {
            try CommandLineOptions.parse([], currentDirectory: workingDirectory)
        }
        #expect(throws: CommandLineOptions.ParseError.missingValue(option: "--output")) {
            try CommandLineOptions.parse(["--output"], currentDirectory: workingDirectory)
        }
        #expect(throws: CommandLineOptions.ParseError.unknownOption("--verbose")) {
            try CommandLineOptions.parse(["--verbose"], currentDirectory: workingDirectory)
        }
        #expect(throws: CommandLineOptions.ParseError.invalidValue(option: "--api-version", value: "2026-08")) {
            try CommandLineOptions.parse(["--api-version", "2026-08", "--output", "x"], currentDirectory: workingDirectory)
        }
        #expect(throws: CommandLineOptions.ParseError.invalidValue(option: "--shop-domain", value: "https://shop")) {
            try CommandLineOptions.parse(["--shop-domain", "https://shop", "--output", "x"], currentDirectory: workingDirectory)
        }
        #expect(throws: CommandLineOptions.ParseError.helpRequested) {
            try CommandLineOptions.parse(["--help"], currentDirectory: workingDirectory)
        }
    }
}

// MARK: - FixturePlan

@Suite("FixturePlan")
struct FixturePlanTests {
    @Test("Covers every required fixture and only cart mutations on the recorder's own cart")
    func plan() throws {
        let specs = try FixturePlan.liveFixtures(isTokenless: true)
        let names = specs.map(\.fileName)
        #expect(Set(names).count == names.count)
        #expect(Set(names).isSuperset(of: [
            "localization_DE_DE.json",
            "product_office-2024-professional-plus-key_DE_DE.json",
            "product_office-2024-professional-plus-key_CH_FR.json",
            "collection_bestseller_DE_DE.json",
            "collection_windows_price_filtered_DE_DE.json",
            "collections_DE_DE.json",
            "product_recommendations_related_DE_DE.json",
            "product_recommendations_complementary_DE_DE.json",
            "predictive_search_win_DE_DE.json",
            "search_office-2024_DE_DE.json",
            "blog_guides_articles_DE_DE.json",
            "article_guides_windows-11-kompatibilitaet-pruefen_DE_DE.json",
            "cart_create_invalid_merchandise_DE_DE.json",
            "cart_create_DE_DE.json",
            "cart_lines_add_DE_DE.json",
            "cart_lines_update_DE_DE.json",
            "cart_discount_codes_invalid_DE_DE.json",
            "cart_lines_remove_DE_DE.json",
            "cart_query_DE_DE.json",
            "product_metafields_access_denied_DE_DE.json",
        ]))

        let mutations = specs.filter { $0.kind == .mutation }
        #expect(Set(mutations.map(\.operationName)).isSubset(of: FixturePlan.allowedMutations))
        #expect(mutations.map(\.fileName) == [
            "cart_create_invalid_merchandise_DE_DE.json",
            "cart_create_DE_DE.json",
            "cart_lines_add_DE_DE.json",
            "cart_lines_update_DE_DE.json",
            "cart_discount_codes_invalid_DE_DE.json",
            "cart_lines_remove_DE_DE.json",
        ])
        let invalid = try #require(mutations.first)
        let printedVariables = try String(decoding: #require(invalid.plannedVariables).prettyPrintedData(), as: UTF8.self)
        #expect(printedVariables.contains("gid://shopify/ProductVariant/1\""))
        #expect(mutations.dropFirst().allSatisfy { $0.plannedVariables == nil })
        #expect(specs.first { $0.fileName == "cart_create_DE_DE.json" }?.prepare != nil)

        let accessDenied = try #require(specs.first { $0.fileName == "product_metafields_access_denied_DE_DE.json" })
        #expect(accessDenied.requiresTokenlessClient)
        #expect(accessDenied.expectedOutcome == .accessDenied)
        #expect(SyntheticFixture.all.allSatisfy { $0.fileName.hasPrefix("synthetic_") })
    }

    @Test("Cart mutations refuse to run before the recorder created its own cart")
    func cartMutationsNeedTheRecordersCart() async throws {
        let specs = try FixturePlan.liveFixtures(isTokenless: true)
        let addLines = try #require(specs.first { $0.fileName == "cart_lines_add_DE_DE.json" })
        let transport = CannedHTTPClient { _, _ in "{}" }
        let client = StorefrontClient(configuration: CommandLineOptions.recorderTestConfiguration, httpClient: transport)
        await #expect(throws: FixtureSpec.UnexpectedOutcome.self) {
            _ = try await addLines.execute(client, FixtureSession())
        }
        #expect(transport.sentRequests.isEmpty)
    }
}

// MARK: - FixtureRecorder

/// Answers every request with a body chosen from the operation name and variables.
private final class CannedHTTPClient: HTTPClient {
    private let respond: @Sendable (String, [String: Any]) -> String
    private let requests = Locked<[HTTPRequest]>([])

    init(respond: @escaping @Sendable (String, [String: Any]) -> String) {
        self.respond = respond
    }

    var sentRequests: [HTTPRequest] {
        requests.value
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        requests.withLock { $0.append(request) }
        let object = try JSONSerialization.jsonObject(with: request.body ?? Data()) as? [String: Any]
        let body = respond(object?["operationName"] as? String ?? "", object?["variables"] as? [String: Any] ?? [:])
        return HTTPResponse(statusCode: 200, headers: ["Content-Type": "application/json"], body: Data(body.utf8))
    }
}

extension CommandLineOptions {
    /// A tokenless configuration of the live store for offline tests.
    static var recorderTestConfiguration: StorefrontConfiguration {
        CommandLineOptions(
            shopDomain: defaultShopDomain,
            apiVersion: defaultAPIVersion,
            token: nil,
            outputDirectory: URL(fileURLWithPath: "/tmp")
        ).storefrontConfiguration
    }
}

/// Canned Storefront bodies that satisfy every validation of the plan.
private enum CannedStore {
    static let money = #"{"amount":"29.9","currencyCode":"EUR"}"#
    static let image = #"{"url":"https://cdn.shopify.com/a.webp","altText":null,"width":1,"height":1}"#
    static let cartToken = "c1-secret-cart-token"

    static func summary(_ handle: String) -> String {
        """
        {"id":"gid://shopify/Product/\(handle)","handle":"\(handle)","title":"T","vendor":"V","availableForSale":true,"featuredImage":null,
        "priceRange":{"minVariantPrice":\(money),"maxVariantPrice":\(money)},
        "compareAtPriceRange":{"minVariantPrice":\(money),"maxVariantPrice":\(money)},"variants":{"nodes":[{"requiresShipping":false}]}}
        """
    }

    static func product(_ handle: String) -> String {
        """
        {"data":{"product":{"id":"gid://shopify/Product/\(handle)","handle":"\(handle)","title":"T","vendor":"V","productType":"P",
        "tags":[],"availableForSale":true,"descriptionHtml":"","onlineStoreUrl":null,"featuredImage":null,
        "images":{"nodes":[]},"options":[],"variants":{"nodes":[{"id":"gid://shopify/ProductVariant/\(handle)","title":"Default Title",
        "sku":null,"availableForSale":true,"requiresShipping":false,"price":\(money),"compareAtPrice":null,
        "selectedOptions":[],"image":null}]},"seo":{"title":null,"description":null},"collections":{"nodes":[]},
        "priceRange":{"minVariantPrice":\(money),"maxVariantPrice":\(money)},
        "compareAtPriceRange":{"minVariantPrice":\(money),"maxVariantPrice":\(money)}}}}
        """
    }

    static let filters = """
        [{"id":"filter.v.availability","label":"Verfügbarkeit","type":"LIST",
        "values":[{"id":"filter.v.availability.1","label":"Auf Lager","count":1,"input":"{\\"available\\":true}"}]}]
        """

    static func collection(_ handle: String, products: [String]) -> String {
        """
        {"data":{"collection":{"id":"gid://shopify/Collection/1","handle":"\(handle)","title":"B","description":"","image":null,
        "products":{"filters":\(filters),"nodes":[\(products.map(summary).joined(separator: ","))],
        "pageInfo":{"hasNextPage":true,"hasPreviousPage":false,"startCursor":"a","endCursor":"b"}}}}}
        """
    }

    static func cart(field: String?, lines: [(variant: String, quantity: Int)], codes: String = "[]", warnings: String = "[]") -> String {
        let lineJSON = lines.enumerated().map { index, line in
            """
            {"id":"gid://shopify/CartLine/line-\(index)?cart=\(cartToken)","quantity":\(line.quantity),
            "merchandise":{"id":"gid://shopify/ProductVariant/\(line.variant)","title":"Default Title","sku":null,"requiresShipping":false,
            "availableForSale":true,"image":\(image),"price":\(money),"compareAtPrice":null,"selectedOptions":[],
            "product":{"id":"gid://shopify/Product/\(line.variant)","handle":"\(line.variant)","title":"T","vendor":"V"}},
            "cost":{"amountPerQuantity":\(money),"compareAtAmountPerQuantity":null,"subtotalAmount":\(money),"totalAmount":\(money)},
            "discountAllocations":[]}
            """
        }.joined(separator: ",")
        let cart = """
            {"id":"gid://shopify/Cart/\(cartToken)?key=secret-key-value","checkoutUrl":"https://www.karinex.de/cart/c/\(cartToken)?key=k-secret-value",
            "totalQuantity":\(lines.map(\.quantity).reduce(0, +)),"note":"","buyerIdentity":{"countryCode":"DE","email":null},
            "attributes":[{"key":"app_platform","value":"ios"}],"discountCodes":\(codes),"discountApplications":[],
            "cost":{"subtotalAmount":\(money),"totalAmount":\(money),"checkoutChargeAmount":\(money)},"lines":{"nodes":[\(lineJSON)]}}
            """
        guard let field else { return #"{"data":{"cart":"# + cart + "}}" }
        return #"{"data":{""# + field + #"":{"cart":"# + cart + #","userErrors":[],"warnings":"# + warnings + "}}}"
    }

    static let invalidCode = #"[{"code":"KX-FIXTURE-NOT-A-CODE","applicable":false}]"#

    static func respond(operation: String, variables: [String: Any]) -> String {
        switch operation {
        case "Localization":
            return """
                {"data":{"localization":{"country":{"isoCode":"DE","name":"Deutschland",
                "currency":{"isoCode":"EUR","name":"Euro","symbol":"€"},
                "availableLanguages":[]},"language":{"isoCode":"DE","name":"Deutsch","endonymName":"Deutsch"},
                "availableCountries":[{"isoCode":"DE","name":"Deutschland","currency":{"isoCode":"EUR","name":"Euro","symbol":"€"},
                "availableLanguages":[]}],"availableLanguages":[]}}}
                """
        case "ProductByHandle":
            if variables["includeMetafields"] as? Bool == true {
                return """
                    {"errors":[{"message":"Access denied","path":["product","metafields"],
                    "extensions":{"code":"ACCESS_DENIED","requiredAccess":"unauthenticated_read_metafields"}}],"data":{"product":null}}
                    """
            }
            let handle = variables["handle"] as? String ?? ""
            return handle == FixturePlan.missingProductHandle ? #"{"data":{"product":null}}"# : product(handle)
        case "CollectionProducts":
            let handle = variables["handle"] as? String ?? ""
            return handle == FixturePlan.allProductsHandle
                ? collection(handle, products: ["cheap-a", "cheap-b"])
                : collection(handle, products: (1...8).map { "p\($0)" })
        case "Collections":
            return #"{"data":{"collections":{"nodes":[{"id":"gid://shopify/Collection/1","handle":"bestseller","title":"B","description":"","image":null}]}}}"#
        case "ProductRecommendations":
            return #"{"data":{"productRecommendations":["# + summary("r") + "]}}"
        case "PredictiveSearch":
            return #"{"data":{"predictiveSearch":{"products":["# + summary("w") + #"],"collections":[],"articles":[],"queries":[]}}}"#
        case "SearchProducts":
            let pageInfo = #""pageInfo":{"hasNextPage":false,"hasPreviousPage":false,"startCursor":null,"endCursor":null}"#
            return #"{"data":{"search":{"totalCount":1,"productFilters":[],"nodes":[{"__typename":"Product","#
                + summary("o").dropFirst() + "]," + pageInfo + "}}}"
        case "BlogArticles":
            return #"{"data":{"blog":{"articles":{"nodes":[{"id":"gid://shopify/Article/1","handle":"a","title":"A","excerpt":null,"#
                + #""publishedAt":"2026-08-29T15:33:05Z","onlineStoreUrl":null,"image":null,"blog":{"handle":"guides"}}]}}}}"#
        case "Article":
            return #"{"data":{"blog":{"articleByHandle":{"id":"gid://shopify/Article/1","handle":"a","title":"A","#
                + #""publishedAt":"2026-08-29T15:33:05Z","contentHtml":"<table><tr><td>x</td></tr></table>","onlineStoreUrl":null,"#
                + #""authorV2":{"name":"KARINEX"},"image":null,"blog":{"handle":"guides"}}}}}"#
        case "CartCreate":
            let input = variables["input"] as? [String: Any]
            let lines = input?["lines"] as? [[String: Any]]
            if lines?.first?["merchandiseId"] as? String == FixturePlan.invalidMerchandiseID.rawValue {
                return """
                    {"data":{"cartCreate":{"cart":null,"userErrors":[{"field":["input","lines","0","merchandiseId"],
                    "message":"invalid","code":"INVALID"}],"warnings":[]}}}
                    """
            }
            return cart(field: "cartCreate", lines: [("cheap-a", 1)])
        case "CartLinesAdd":
            return cart(field: "cartLinesAdd", lines: [("cheap-a", 1), ("cheap-b", 1)])
        case "CartLinesUpdate":
            return cart(field: "cartLinesUpdate", lines: [("cheap-a", 2), ("cheap-b", 1)])
        case "CartDiscountCodesUpdate":
            let warning = #"[{"code":"DISCOUNT_NOT_FOUND","message":"m","target":"gid://shopify/Cart/"# + cartToken + #""}]"#
            return cart(field: "cartDiscountCodesUpdate", lines: [("cheap-a", 2), ("cheap-b", 1)], codes: invalidCode, warnings: warning)
        case "CartLinesRemove":
            return cart(field: "cartLinesRemove", lines: [("cheap-a", 2)], codes: invalidCode)
        case "Cart":
            return cart(field: nil, lines: [("cheap-a", 2)], codes: invalidCode)
        default:
            return "{}"
        }
    }
}

@Suite("FixtureRecorder")
struct FixtureRecorderTests {
    @Test("Writes every fixture, the synthetic envelope and the manifest, with cart tokens redacted")
    func recordsEverything() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("fixture-recorder-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let options = CommandLineOptions(
            shopDomain: CommandLineOptions.defaultShopDomain,
            apiVersion: CommandLineOptions.defaultAPIVersion,
            token: nil,
            outputDirectory: directory
        )
        let transport = CannedHTTPClient { operation, variables in CannedStore.respond(operation: operation, variables: variables) }
        let recorder = FixtureRecorder(
            options: options,
            httpClient: transport,
            progress: { _ in },
            logSink: RecordingLogSink(),
            now: { Date(timeIntervalSince1970: 1_790_380_800) }
        )

        let written = try await recorder.run()

        let expected = try FixturePlan.liveFixtures(isTokenless: true).map(\.fileName)
            + SyntheticFixture.all.map(\.fileName) + [FixtureRecorder.manifestFileName]
        #expect(written == expected)
        for file in written {
            let contents = try String(contentsOf: directory.appendingPathComponent(file), encoding: .utf8)
            #expect(!contents.contains(CannedStore.cartToken))
            #expect(!contents.contains("secret-key-value"))
            #expect(!contents.contains("k-secret-value"))
        }

        let cart = try String(contentsOf: directory.appendingPathComponent("cart_lines_update_DE_DE.json"), encoding: .utf8)
        #expect(cart.contains("\"gid://shopify/Cart/REDACTED?key=REDACTED\""))
        #expect(cart.contains("\"gid://shopify/CartLine/line-0?cart=REDACTED\""))

        let manifest = try JSONValue.parseObject(Data(contentsOf: directory.appendingPathComponent("manifest.json")))
        #expect(manifest["apiVersion"] == .string("2026-10"))
        #expect(manifest["recordedAt"] == .string("2026-09-26T00:00:00Z"))
        guard case let .array(entries)? = manifest["fixtures"] else {
            Issue.record("manifest has no fixtures array")
            return
        }
        #expect(entries.count == written.count - 1)
        let update = entries.first { $0.objectValue?["file"] == .string("cart_lines_update_DE_DE.json") }?.objectValue
        guard case let .object(variables)? = update?["variables"] else {
            Issue.record("cart_lines_update has no variables")
            return
        }
        #expect(variables["cartId"] == .string("gid://shopify/Cart/REDACTED?key=REDACTED"))
        let updatedLine: JSONValue = .object(["id": .string("gid://shopify/CartLine/line-0?cart=REDACTED"), "quantity": .integer(2)])
        #expect(variables["lines"] == .array([updatedLine]))

        let throttled = try String(contentsOf: directory.appendingPathComponent("synthetic_throttled.json"), encoding: .utf8)
        #expect(throttled.contains("\"code\": \"THROTTLED\""))
        #expect(transport.sentRequests.allSatisfy { $0.value(forHeader: StorefrontConfiguration.accessTokenHeader) == nil })
        let mutationNames = try transport.sentRequests.compactMap { request -> String? in
            let object = try JSONSerialization.jsonObject(with: request.body ?? Data()) as? [String: Any]
            let query = object?["query"] as? String ?? ""
            return query.hasPrefix("mutation") ? object?["operationName"] as? String : nil
        }
        #expect(Set(mutationNames).isSubset(of: FixturePlan.allowedMutations))
        #expect(mutationNames.count == 6)
    }
}

extension JSONValue {
    fileprivate var objectValue: [String: JSONValue]? {
        if case let .object(object) = self {
            return object
        }
        return nil
    }
}
