import Core
import Foundation
@testable import ShopifyKit
import Testing

// MARK: - Request format

@Suite("GraphQLClient requests")
struct GraphQLClientRequestTests {
    @Test("Sends a JSON POST with query, operationName and variables and the directive injected")
    func requestFormat() async throws {
        let stub = try StubHTTPClient([.fixture(Fixture.productDE)])
        let client = makeStorefrontClient(stub)

        let query = ProductByHandleQuery(handle: "office-2024-professional-plus-key", includeMetafields: false)
        _ = try await client.execute(query, context: germanyContext)

        let request = try #require(stub.requests.first)
        #expect(request.method == .post)
        #expect(request.url.absoluteString == "https://45dv93-bk.myshopify.com/api/2026-07/graphql.json")
        #expect(request.value(forHeader: "content-type") == "application/json")
        #expect(request.value(forHeader: "accept") == "application/json")

        let body = try SentGraphQLBody(request)
        #expect(body.operationName == "ProductByHandle")
        let consent = "visitorConsent: {analytics: false, preferences: true, marketing: false, saleOfData: false}"
        #expect(body.query.contains(") @inContext(country: DE, language: DE, \(consent)) {"))
        #expect(body.query.hasPrefix("query ProductByHandle("))
        #expect(body.variables["handle"] == .string("office-2024-professional-plus-key"))
        #expect(body.variables["includeMetafields"] == .bool(false))
        guard case let .array(identifiers)? = body.variables["metafieldIdentifiers"] else {
            Issue.record("metafieldIdentifiers missing")
            return
        }
        #expect(identifiers.count == ProductMetafields.allIdentifiers.count)
        #expect(identifiers.first == .object(["namespace": .string("karinex"), "key": .string("faq")]))
    }

    @Test("Omits nil variables and sends an empty object for operations without variables")
    func variablesEncoding() async throws {
        let stub = try StubHTTPClient([.fixture(Fixture.collectionBestseller), .fixture(Fixture.localization)])
        let client = makeStorefrontClient(stub)

        _ = try await client.execute(CollectionProductsQuery(handle: "bestseller", first: 8), context: germanyContext)
        _ = try await client.execute(LocalizationQuery(), context: germanyContext)

        let collectionBody = try SentGraphQLBody(stub.requests[0])
        #expect(collectionBody.variables == ["handle": .string("bestseller"), "first": .number(8), "reverse": .bool(false)])
        let localizationBody = try SentGraphQLBody(stub.requests[1])
        #expect(localizationBody.variables.isEmpty)
        #expect(try String(decoding: #require(stub.requests[1].body), as: UTF8.self).contains(#""variables":{}"#))
    }

    @Test("Identical operations encode to identical bytes")
    func deterministicBody() throws {
        let variables = CollectionProductsQuery(handle: "a", first: 2).variables
        let first = try GraphQLClient.encodeBody(query: "q", operationName: "Op", variables: variables)
        let sameVariables = CollectionProductsQuery(handle: "a", first: 2).variables
        let second = try GraphQLClient.encodeBody(query: "q", operationName: "Op", variables: sameVariables)
        #expect(first == second)
        #expect(String(decoding: first, as: UTF8.self).hasPrefix(#"{"operationName":"Op","query":"q","variables":"#))
    }

    @Test("Without a directive the document is sent unchanged, and dynamic authorization headers are added")
    func genericEndpoint() async throws {
        let stub = StubHTTPClient([.json(#"{"data":{"localization":null}}"#)])
        let endpoint = try GraphQLEndpoint(
            url: #require(URL(string: "https://shopify.com/91753283851/account/customer/api/2026-07/graphql")),
            headers: ["X-Static": "1"],
            authorization: { ["Authorization": "Bearer shcat_example"] }
        )
        let client = makeGraphQLClient(stub, endpoint: endpoint)

        await #expect(throws: ShopifyError.decoding("LocalizationQuery.ResponseData: localization")) {
            _ = try await client.execute(LocalizationQuery())
        }

        let request = try #require(stub.requests.first)
        #expect(request.value(forHeader: "authorization") == "Bearer shcat_example")
        #expect(request.value(forHeader: "x-static") == "1")
        #expect(request.value(forHeader: StorefrontConfiguration.accessTokenHeader) == nil)
        #expect(try SentGraphQLBody(request).query == LocalizationQuery.document)
    }

    @Test("Errors of the authorization provider are rethrown unchanged and nothing is sent")
    func authorizationFailure() async throws {
        struct LoginRequired: Error, Equatable {}
        let stub = StubHTTPClient()
        let endpoint = GraphQLEndpoint(url: AppConfiguration.preview.storefrontEndpoint, authorization: { throw LoginRequired() })
        let client = makeGraphQLClient(stub, endpoint: endpoint)

        await #expect(throws: LoginRequired()) {
            _ = try await client.execute(LocalizationQuery())
        }
        #expect(stub.requests.isEmpty)
    }

    @Test("A cancelled task fails fast with network(.cancelled)")
    func cancelledBeforeStart() async throws {
        let stub = try StubHTTPClient([.fixture(Fixture.localization)])
        let client = makeStorefrontClient(stub)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await client.execute(LocalizationQuery(), context: germanyContext)
        }
        await #expect(throws: ShopifyError.network(.cancelled)) {
            _ = try await task.value
        }
        #expect(stub.requests.isEmpty)
    }

    @Test("Logs operation, status, duration, attempts and cost, never variables")
    func logging() async throws {
        let sink = RecordingLogSink()
        let stub = try StubHTTPClient([.fixture(Fixture.cartCreateInvalidMerchandise)])
        let client = makeStorefrontClient(stub, logSink: sink)

        let mutation = CartCreateMutation(
            lines: [CartLineInput(merchandiseId: "gid://shopify/ProductVariant/1")],
            countryCode: .de,
            attributes: [AttributeInput(key: "app_platform", value: "ios-secret-attribute")]
        )
        _ = try await client.execute(mutation, context: germanyContext)

        let line = try #require(sink.messages.first)
        #expect(sink.messages.count == 1)
        #expect(sink.entries.first?.level == .debug)
        #expect(line.hasPrefix("CartCreate status=200 duration="))
        #expect(line.contains("attempts=1"))
        #expect(line.hasSuffix("cost=13"))
        #expect(!line.contains("ProductVariant"))
        #expect(!line.contains("ios-secret-attribute"))
    }
}

// MARK: - Retries

@Suite("GraphQLClient retries")
struct GraphQLClientRetryTests {
    @Test("A query is retried on 503 and then succeeds")
    func queryRetriedOn503() async throws {
        let sleeper = RecordingSleeper()
        let stub = try StubHTTPClient([.status(503), .fixture(Fixture.localization)])
        let client = makeStorefrontClient(stub, sleeper: sleeper)

        let data = try await client.execute(LocalizationQuery(), context: germanyContext)

        #expect(data.localization.country.isoCode == .de)
        #expect(stub.requests.count == 2)
        #expect(sleeper.durations.count <= 1)
    }

    @Test("A mutation is not retried on 503")
    func mutationNotRetriedOn503() async throws {
        let stub = try StubHTTPClient([.status(503), .fixture(Fixture.cartCreateInvalidMerchandise)])
        let client = makeStorefrontClient(stub)

        await #expect(throws: ShopifyError.http(statusCode: 503)) {
            _ = try await client.execute(Self.cartCreate, context: germanyContext)
        }
        #expect(stub.requests.count == 1)
    }

    @Test("A mutation is retried on 429 and honors Retry-After")
    func mutationRetriedOn429() async throws {
        let sleeper = RecordingSleeper()
        let stub = try StubHTTPClient([.status(429, headers: ["Retry-After": "2"]), .fixture(Fixture.cartCreateInvalidMerchandise)])
        let client = makeStorefrontClient(stub, sleeper: sleeper)

        let data = try await client.execute(Self.cartCreate, context: germanyContext)

        #expect(data.cartCreate?.userErrors.first?.code == .invalid)
        #expect(stub.requests.count == 2)
        let delay = try #require(sleeper.durations.first)
        #expect(delay >= .seconds(2))
        #expect(delay <= RetryPolicy.default.maxDelay * 2)
    }

    @Test("429 on every attempt ends as throttled after the attempt budget")
    func throttledAfterRetries() async throws {
        let stub = StubHTTPClient([.status(429), .status(429), .status(429), .status(429)])
        let client = makeStorefrontClient(stub)

        await #expect(throws: ShopifyError.throttled) {
            _ = try await client.execute(LocalizationQuery(), context: germanyContext)
        }
        #expect(stub.requests.count == RetryPolicy.default.maxAttempts)
    }

    @Test("Offline is never retried")
    func offlineNotRetried() async throws {
        let stub = try StubHTTPClient([.failure(.offline), .fixture(Fixture.localization)])
        let client = makeStorefrontClient(stub)

        await #expect(throws: ShopifyError.network(.offline)) {
            _ = try await client.execute(LocalizationQuery(), context: germanyContext)
        }
        #expect(stub.requests.count == 1)
    }

    @Test("Cancellation reported by the transport is never retried")
    func cancelledNotRetried() async throws {
        let stub = try StubHTTPClient([.failure(.cancelled), .fixture(Fixture.localization)])
        let client = makeStorefrontClient(stub)

        await #expect(throws: ShopifyError.network(.cancelled)) {
            _ = try await client.execute(LocalizationQuery(), context: germanyContext)
        }
        #expect(stub.requests.count == 1)
    }

    @Test("A query is retried on timeouts and transport errors, a mutation is not")
    func timeouts() async throws {
        let queryStub = try StubHTTPClient([.failure(.timeout), .failure(.transport(code: -1200)), .fixture(Fixture.localization)])
        let data = try await makeStorefrontClient(queryStub).execute(LocalizationQuery(), context: germanyContext)
        #expect(data.localization.availableCountries.count == 28)
        #expect(queryStub.requests.count == 3)

        let mutationStub = try StubHTTPClient([.failure(.timeout), .fixture(Fixture.cartCreateInvalidMerchandise)])
        await #expect(throws: ShopifyError.network(.timeout)) {
            _ = try await makeStorefrontClient(mutationStub).execute(Self.cartCreate, context: germanyContext)
        }
        #expect(mutationStub.requests.count == 1)
    }

    @Test("GraphQL THROTTLED is retried for queries and mutations")
    func graphQLThrottledRetried() async throws {
        let queryStub = try StubHTTPClient([.fixture(Fixture.syntheticThrottled), .fixture(Fixture.localization)])
        _ = try await makeStorefrontClient(queryStub).execute(LocalizationQuery(), context: germanyContext)
        #expect(queryStub.requests.count == 2)

        let mutationStub = try StubHTTPClient([.fixture(Fixture.syntheticThrottled), .fixture(Fixture.cartCreateInvalidMerchandise)])
        _ = try await makeStorefrontClient(mutationStub).execute(Self.cartCreate, context: germanyContext)
        #expect(mutationStub.requests.count == 2)
    }

    @Test("The synthetic THROTTLED fixture maps to throttled once retries are exhausted")
    func graphQLThrottledExhausted() async throws {
        let throttled = try StubHTTPClient.Reply.fixture(Fixture.syntheticThrottled)
        let stub = StubHTTPClient([throttled, throttled, throttled])
        await #expect(throws: ShopifyError.throttled) {
            _ = try await makeStorefrontClient(stub).execute(LocalizationQuery(), context: germanyContext)
        }
        #expect(stub.requests.count == 3)

        let single = StubHTTPClient([throttled])
        await #expect(throws: ShopifyError.throttled) {
            _ = try await makeStorefrontClient(single, retryPolicy: .none).execute(LocalizationQuery(), context: germanyContext)
        }
    }

    @Test("Server errors exhaust the budget for queries; client errors are not retried")
    func statusCodes() async throws {
        let serverErrors = StubHTTPClient([.status(500), .status(502), .status(504)])
        await #expect(throws: ShopifyError.http(statusCode: 504)) {
            _ = try await makeStorefrontClient(serverErrors).execute(LocalizationQuery(), context: germanyContext)
        }
        #expect(serverErrors.requests.count == 3)

        let notFound = StubHTTPClient([.status(404)])
        await #expect(throws: ShopifyError.http(statusCode: 404)) {
            _ = try await makeStorefrontClient(notFound).execute(LocalizationQuery(), context: germanyContext)
        }
        #expect(notFound.requests.count == 1)
    }

    @Test("GraphQL INTERNAL_SERVER_ERROR is retried for queries only")
    func graphQLInternalServerError() async throws {
        let body = #"{"errors":[{"message":"Internal error","extensions":{"code":"INTERNAL_SERVER_ERROR"}}]}"#
        let queryStub = try StubHTTPClient([.json(body), .fixture(Fixture.localization)])
        _ = try await makeStorefrontClient(queryStub).execute(LocalizationQuery(), context: germanyContext)
        #expect(queryStub.requests.count == 2)

        let mutationStub = try StubHTTPClient([.json(body), .fixture(Fixture.cartCreateInvalidMerchandise)])
        do {
            _ = try await makeStorefrontClient(mutationStub).execute(Self.cartCreate, context: germanyContext)
            Issue.record("Expected an error")
        } catch let error as ShopifyError {
            #expect(error == .graphQL([GraphQLErrorDetail(message: "Internal error", code: "INTERNAL_SERVER_ERROR")]))
            #expect(error.isTransient)
        }
        #expect(mutationStub.requests.count == 1)
    }

    static let cartCreate = CartCreateMutation(
        lines: [CartLineInput(merchandiseId: "gid://shopify/ProductVariant/1", quantity: 1)],
        countryCode: .de
    )
}

// MARK: - De-duplication

@Suite("GraphQLClient de-duplication")
struct GraphQLClientDeduplicationTests {
    @Test("Two concurrent identical queries share one request")
    func concurrentQueriesShareOneRequest() async throws {
        let gate = Gate()
        let stub = try StubHTTPClient([.fixture(Fixture.localization)], gate: gate)
        let client = makeGraphQLClient(stub)
        let directive = germanyContext.directive

        async let first = client.execute(LocalizationQuery(), directive: directive)
        async let second = client.execute(LocalizationQuery(), directive: directive)

        #expect(await eventually { stub.requests.count == 1 })
        let body = try #require(stub.requests.first?.body)
        #expect(await eventually { await client.deduplicator.waiterCount(for: body) == 2 })
        await gate.open()

        let (firstResult, secondResult) = try await (first, second)
        #expect(firstResult == secondResult)
        #expect(stub.requests.count == 1)
        #expect(await client.deduplicator.inFlightCount == 0)
    }

    @Test("Queries in different contexts are not shared")
    func differentContextsAreSeparate() async throws {
        let stub = try StubHTTPClient([.fixture(Fixture.localization), .fixture(Fixture.localization)])
        let client = makeGraphQLClient(stub)

        async let first = client.execute(LocalizationQuery(), directive: germanyContext.directive)
        async let second = client.execute(LocalizationQuery(), directive: switzerlandFrenchContext.directive)
        _ = try await (first, second)

        #expect(stub.requests.count == 2)
    }

    @Test("Concurrent identical mutations are never shared")
    func mutationsAreNotShared() async throws {
        let gate = Gate()
        let stub = try StubHTTPClient(
            [.fixture(Fixture.cartCreateInvalidMerchandise), .fixture(Fixture.cartCreateInvalidMerchandise)],
            gate: gate
        )
        let client = makeGraphQLClient(stub)
        let mutation = GraphQLClientRetryTests.cartCreate

        async let first = client.execute(mutation, directive: germanyContext.directive)
        async let second = client.execute(mutation, directive: germanyContext.directive)

        #expect(await eventually { stub.requests.count == 2 })
        await gate.open()
        _ = try await (first, second)
        #expect(stub.requests.count == 2)
    }

    @Test("Sequential identical queries send two requests")
    func sequentialQueries() async throws {
        let stub = try StubHTTPClient([.fixture(Fixture.localization), .fixture(Fixture.localization)])
        let client = makeGraphQLClient(stub)

        _ = try await client.execute(LocalizationQuery(), directive: germanyContext.directive)
        _ = try await client.execute(LocalizationQuery(), directive: germanyContext.directive)

        #expect(stub.requests.count == 2)
    }
}

// MARK: - Error mapping

@Suite("GraphQLClient error mapping")
struct GraphQLClientErrorMappingTests {
    @Test("The recorded ACCESS_DENIED response maps to accessDenied with the required scope")
    func accessDeniedFixture() async throws {
        let stub = try StubHTTPClient([.fixture(Fixture.metafieldsAccessDenied)])
        let client = makeStorefrontClient(stub)

        await #expect(throws: ShopifyError.accessDenied(requiredAccess: "`unauthenticated_read_metafields` access scope.")) {
            _ = try await client.execute(
                ProductByHandleQuery(handle: "office-2024-professional-plus-key", includeMetafields: true),
                context: germanyContext
            )
        }
        #expect(stub.requests.count == 1)
    }

    @Test("HTTP 401 and 403 map to accessDenied")
    func unauthorizedStatus() async throws {
        for status in [401, 403] {
            let stub = StubHTTPClient([.status(status)])
            await #expect(throws: ShopifyError.accessDenied(requiredAccess: nil)) {
                _ = try await makeStorefrontClient(stub).execute(LocalizationQuery(), context: germanyContext)
            }
            #expect(stub.requests.count == 1)
        }
    }

    @Test("Other GraphQL errors map to graphQL with all details, even with partial data")
    func otherGraphQLErrors() async throws {
        let body = """
            {"data": {"localization": null}, "errors": [
              {"message": "Field 'foo' doesn't exist", "locations": [{"line": 1, "column": 3}], "path": ["localization", 0, "foo"],
               "extensions": {"code": "undefinedField"}},
              {"message": "Second"}
            ]}
            """
        let stub = StubHTTPClient([.json(body)])
        do {
            _ = try await makeStorefrontClient(stub).execute(LocalizationQuery(), context: germanyContext)
            Issue.record("Expected an error")
        } catch let ShopifyError.graphQL(errors) {
            #expect(errors.count == 2)
            #expect(errors[0].code == "undefinedField")
            #expect(errors[0].path == [.key("localization"), .index(0), .key("foo")])
            #expect(errors[0].pathDescription == "localization.0.foo")
            #expect(errors[1] == GraphQLErrorDetail(message: "Second"))
        }
        #expect(stub.requests.count == 1)
    }

    @Test("Decoding failures name the type and coding path without payload content")
    func decodingFailures() async throws {
        let missingField = StubHTTPClient([.json(#"{"data":{"localization":{"country":{"isoCode":"DE"}}}}"#)])
        await #expect(throws: ShopifyError.decoding("LocalizationQuery.ResponseData: localization.country.name")) {
            _ = try await makeStorefrontClient(missingField).execute(LocalizationQuery(), context: germanyContext)
        }

        let badAmount = #"{"data":{"collection":{"id":"gid://shopify/Collection/1","handle":"h","title":"t","description":"d","#
            + #""products":{"nodes":[{"id":"gid://shopify/Product/1","handle":"p","title":"T","vendor":"V","availableForSale":true,"#
            + #""priceRange":{"minVariantPrice":{"amount":"12,90 secret","currencyCode":"EUR"}}}]}}}}"#
        let wrongType = StubHTTPClient([.json(badAmount)])
        do {
            _ = try await makeStorefrontClient(wrongType).execute(CollectionProductsQuery(handle: "h", first: 1), context: germanyContext)
            Issue.record("Expected an error")
        } catch let ShopifyError.decoding(description) {
            #expect(description == "CollectionProductsQuery.ResponseData: collection.products.nodes[0].priceRange.minVariantPrice.amount")
            #expect(!description.contains("secret"))
        }

        let notJSON = StubHTTPClient([.json("<html>Maintenance</html>")])
        await #expect(throws: ShopifyError.decoding("GraphQLResponse: <root>")) {
            _ = try await makeStorefrontClient(notJSON).execute(LocalizationQuery(), context: germanyContext)
        }

        let noData = StubHTTPClient([.json(#"{"data":null}"#)])
        await #expect(throws: ShopifyError.decoding("LocalizationQuery.ResponseData: data")) {
            _ = try await makeStorefrontClient(noData).execute(LocalizationQuery(), context: germanyContext)
        }
    }

    @Test("Failures are logged with the error code only")
    func failureLogging() async throws {
        let sink = RecordingLogSink()
        let stub = try StubHTTPClient([.fixture(Fixture.metafieldsAccessDenied)])
        await #expect(throws: ShopifyError.self) {
            _ = try await makeStorefrontClient(stub, logSink: sink).execute(
                ProductByHandleQuery(handle: "office-2024-professional-plus-key", includeMetafields: true),
                context: germanyContext
            )
        }
        let line = try #require(sink.messages.first)
        #expect(sink.entries.first?.level == .error)
        #expect(line.hasPrefix("ProductByHandle failed error=accessDenied status=200"))
        #expect(!line.contains("unauthenticated_read_metafields"))

        let offlineSink = RecordingLogSink()
        await #expect(throws: ShopifyError.network(.offline)) {
            _ = try await makeStorefrontClient(StubHTTPClient([.failure(.offline)]), logSink: offlineSink)
                .execute(LocalizationQuery(), context: germanyContext)
        }
        #expect(offlineSink.entries.first?.level == .notice)
    }

    @Test("ShopifyError classification helpers")
    func classification() {
        #expect(ShopifyError.network(.offline).isConnectivityProblem)
        #expect(ShopifyError.network(.timeout).isConnectivityProblem)
        #expect(!ShopifyError.throttled.isConnectivityProblem)
        #expect(ShopifyError.network(.cancelled).isCancellation)
        #expect(ShopifyError.throttled.isTransient)
        #expect(ShopifyError.http(statusCode: 503).isTransient)
        #expect(!ShopifyError.http(statusCode: 404).isTransient)
        #expect(!ShopifyError.userErrors([]).isTransient)
        #expect(ShopifyError.userErrors([UserError(field: nil, message: "m", code: .invalid)]).logDescription == "userErrors(INVALID)")
    }
}
