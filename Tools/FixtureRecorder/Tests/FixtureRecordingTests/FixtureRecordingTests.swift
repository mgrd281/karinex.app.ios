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
    @Test("Masks cart tokens, checkout URLs and personal fields, keeps catalog data")
    func anonymizes() throws {
        let body = Data("""
            {"data": {"cartCreate": {"cart": {"id": "gid://shopify/Cart/c1-abc?key=def",
             "checkoutUrl": "https://www.karinex.de/cart/c/c1-abc?key=def", "totalQuantity": 1},
             "buyer": {"email": "someone@example.com"},
             "userErrors": [{"message": "Line gid://shopify/CartLine/xyz invalid", "field": null}]},
             "product": {"id": "gid://shopify/Product/10534352027915", "handle": "office-2024-professional-plus-key"}}}
            """.utf8)
        let (object, paths) = try FixtureAnonymizer.anonymize(JSONValue.parseObject(body))
        let printed = String(decoding: JSONValue.object(object).prettyPrintedData(), as: UTF8.self)

        #expect(printed.contains("\"gid://shopify/Cart/anonymized\""))
        #expect(printed.contains("\"https://www.karinex.de/cart/c/anonymized\""))
        #expect(printed.contains("Line gid://shopify/CartLine/anonymized invalid"))
        #expect(printed.contains("\"email\": \"anonymized\""))
        #expect(printed.contains("gid://shopify/Product/10534352027915"))
        #expect(!printed.contains("c1-abc"))
        #expect(!printed.contains("example.com"))
        #expect(paths.sorted() == [
            "data.cartCreate.buyer.email",
            "data.cartCreate.cart.checkoutUrl",
            "data.cartCreate.cart.id",
            "data.cartCreate.userErrors[0].message",
        ])
    }

    @Test("Leaves fixtures without customer data unchanged")
    func unchanged() throws {
        let object = try JSONValue.parseObject(Data(#"{"data":{"cartCreate":{"cart":null,"userErrors":[]}}}"#.utf8))
        let (result, paths) = FixtureAnonymizer.anonymize(object)
        #expect(result == object)
        #expect(paths.isEmpty)
    }
}

// MARK: - CommandLineOptions

@Suite("CommandLineOptions")
struct CommandLineOptionsTests {
    private let workingDirectory = URL(fileURLWithPath: "/work", isDirectory: true)

    @Test("Defaults to the live store, API 2026-07 and tokenless mode")
    func defaults() throws {
        let options = try CommandLineOptions.parse(["--output", "Fixtures"], currentDirectory: workingDirectory)
        #expect(options.shopDomain == "45dv93-bk.myshopify.com")
        #expect(options.apiVersion == "2026-07")
        #expect(options.token == nil)
        #expect(options.outputDirectory.path == "/work/Fixtures")
        #expect(options.storefrontConfiguration.endpoint.absoluteString == "https://45dv93-bk.myshopify.com/api/2026-07/graphql.json")
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
    @Test("Covers every required fixture and only one, harmless mutation")
    func plan() throws {
        let specs = try FixturePlan.liveFixtures(isTokenless: true)
        let names = Set(specs.map(\.fileName))
        #expect(names.isSuperset(of: [
            "localization_DE_DE.json",
            "product_office-2024-professional-plus-key_DE_DE.json",
            "product_office-2024-professional-plus-key_CH_FR.json",
            "collection_bestseller_DE_DE.json",
            "cart_create_invalid_merchandise_DE_DE.json",
            "product_metafields_access_denied_DE_DE.json",
        ]))

        let mutations = specs.filter { $0.kind == .mutation }
        #expect(mutations.map(\.operationName) == ["CartCreate"])
        let printedVariables = try String(decoding: #require(mutations.first).variables.prettyPrintedData(), as: UTF8.self)
        #expect(printedVariables.contains("gid://shopify/ProductVariant/1\""))

        let accessDenied = try #require(specs.first { $0.fileName == "product_metafields_access_denied_DE_DE.json" })
        #expect(accessDenied.requiresTokenlessClient)
        #expect(accessDenied.expectedOutcome == .accessDenied)
        #expect(SyntheticFixture.all.allSatisfy { $0.fileName.hasPrefix("synthetic_") })
    }
}

// MARK: - FixtureRecorder

/// Answers every request with a canned body chosen by operation name.
private final class CannedHTTPClient: HTTPClient {
    private let bodies: [String: String]
    private let requests = Locked<[HTTPRequest]>([])

    init(bodies: [String: String]) {
        self.bodies = bodies
    }

    var sentRequests: [HTTPRequest] {
        requests.value
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        requests.withLock { $0.append(request) }
        let object = try JSONSerialization.jsonObject(with: request.body ?? Data()) as? [String: Any]
        let operationName = object?["operationName"] as? String ?? ""
        let variables = object?["variables"] as? [String: Any]
        let key = operationName == "ProductByHandle" && variables?["includeMetafields"] as? Bool == true
            ? "ProductByHandleWithMetafields"
            : operationName == "ProductByHandle" && variables?["handle"] as? String == FixturePlan.missingProductHandle
                ? "ProductByHandleMissing"
                : operationName
        return HTTPResponse(statusCode: 200, headers: ["Content-Type": "application/json"], body: Data((bodies[key] ?? "{}").utf8))
    }
}

@Suite("FixtureRecorder")
struct FixtureRecorderTests {
    private static let money = #"{"amount":"29.9","currencyCode":"EUR"}"#
    private static let product = """
        {"data":{"product":{"id":"gid://shopify/Product/1","handle":"h","title":"T","vendor":"V","productType":"P",
        "tags":[],"availableForSale":true,"descriptionHtml":"","onlineStoreUrl":null,"featuredImage":null,
        "images":{"nodes":[]},"options":[],"variants":{"nodes":[{"id":"gid://shopify/ProductVariant/2","title":"Default Title",
        "sku":null,"availableForSale":true,"requiresShipping":false,"price":\(money),"compareAtPrice":null,
        "selectedOptions":[],"image":null}]},"seo":{"title":null,"description":null},"collections":{"nodes":[]},
        "priceRange":{"minVariantPrice":\(money),"maxVariantPrice":\(money)},
        "compareAtPriceRange":{"minVariantPrice":\(money),"maxVariantPrice":\(money)}}}}
        """
    private static let summary = """
        {"id":"gid://shopify/Product/1","handle":"h","title":"T","vendor":"V","availableForSale":true,"featuredImage":null,
        "priceRange":{"minVariantPrice":\(money),"maxVariantPrice":\(money)},
        "compareAtPriceRange":{"minVariantPrice":\(money),"maxVariantPrice":\(money)},"variants":{"nodes":[]}}
        """
    private static let bodies: [String: String] = [
        "Localization": """
            {"data":{"localization":{"country":{"isoCode":"DE","name":"Deutschland",
            "currency":{"isoCode":"EUR","name":"Euro","symbol":"€"},
            "availableLanguages":[]},"language":{"isoCode":"DE","name":"Deutsch","endonymName":"Deutsch"},
            "availableCountries":[{"isoCode":"DE","name":"Deutschland","currency":{"isoCode":"EUR","name":"Euro","symbol":"€"},
            "availableLanguages":[]}],"availableLanguages":[]}}}
            """,
        "ProductByHandle": product,
        "ProductByHandleMissing": #"{"data":{"product":null}}"#,
        "ProductByHandleWithMetafields": """
            {"errors":[{"message":"Access denied","path":["product","metafields"],
            "extensions":{"code":"ACCESS_DENIED","requiredAccess":"unauthenticated_read_metafields"}}],"data":{"product":null}}
            """,
        "CollectionProducts": """
            {"data":{"collection":{"id":"gid://shopify/Collection/1","handle":"bestseller","title":"B","description":"","image":null,
            "products":{"nodes":[\(Array(repeating: summary, count: 8).joined(separator: ","))],
            "pageInfo":{"hasNextPage":true,"hasPreviousPage":false,"startCursor":"a","endCursor":"b"}}}}}
            """,
        "CartCreate": """
            {"data":{"cartCreate":{"cart":null,"userErrors":[{"field":["input","lines","0","merchandiseId"],
            "message":"invalid","code":"INVALID"}],"warnings":[]}}}
            """,
    ]

    @Test("Writes every fixture, the synthetic envelope and the manifest")
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
        let transport = CannedHTTPClient(bodies: Self.bodies)
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
            #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent(file).path))
        }

        let manifest = try JSONValue.parseObject(Data(contentsOf: directory.appendingPathComponent("manifest.json")))
        #expect(manifest["apiVersion"] == .string("2026-07"))
        #expect(manifest["recordedAt"] == .string("2026-09-26T00:00:00Z"))
        guard case let .array(entries)? = manifest["fixtures"] else {
            Issue.record("manifest has no fixtures array")
            return
        }
        #expect(entries.count == written.count - 1)

        let throttled = try String(contentsOf: directory.appendingPathComponent("synthetic_throttled.json"), encoding: .utf8)
        #expect(throttled.contains("\"code\": \"THROTTLED\""))
        #expect(transport.sentRequests.allSatisfy { $0.value(forHeader: StorefrontConfiguration.accessTokenHeader) == nil })
    }
}
