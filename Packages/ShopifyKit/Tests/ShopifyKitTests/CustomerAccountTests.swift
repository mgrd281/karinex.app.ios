import Core
import Foundation
@testable import ShopifyKit
import Testing

// MARK: - Support

/// Answers by URL path, so concurrent requests (the two discovery documents) get the right
/// reply. Replies for a path are used in order; the last one repeats.
private final class RoutingHTTPClient: HTTPClient {
    private let routes: Locked<[String: [StubHTTPClient.Reply]]>
    private let recorded = Locked<[HTTPRequest]>([])

    init(_ routes: [String: [StubHTTPClient.Reply]]) {
        self.routes = Locked(routes)
    }

    var requests: [HTTPRequest] {
        recorded.value
    }

    func requests(to path: String) -> [HTTPRequest] {
        requests.filter { $0.url.path == path }
    }

    func setReplies(_ replies: [StubHTTPClient.Reply], for path: String) {
        routes.withLock { $0[path] = replies }
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        recorded.withLock { $0.append(request) }
        let reply = routes.withLock { routes -> StubHTTPClient.Reply? in
            guard var replies = routes[request.url.path], let first = replies.first else { return nil }
            if replies.count > 1 {
                replies.removeFirst()
                routes[request.url.path] = replies
            }
            return first
        }
        switch reply {
        case let .response(response)?:
            return response
        case let .failure(error)?:
            throw error
        case nil:
            throw StubHTTPClient.Exhausted()
        }
    }
}

private enum AuthFixture {
    static let clientID = "shp_test-client"
    static let issuer = "https://shopify.com/authentication/91753283851"
    static let redirectURI = URL(string: "shop.91753283851.app://callback")!
    static let openIDURL = URL(string: "https://www.karinex.de/.well-known/openid-configuration")!
    static let apiURL = URL(string: "https://www.karinex.de/.well-known/customer-account-api")!

    static let openIDDocument = """
        {"issuer": "\(issuer)",
         "authorization_endpoint": "https://account.karinex.de/authentication/oauth/authorize",
         "token_endpoint": "https://account.karinex.de/authentication/oauth/token",
         "end_session_endpoint": "https://account.karinex.de/authentication/logout"}
        """
    static let apiDocument = """
        {"graphql_api": "https://account.karinex.de/customer/api/2026-07/graphql", "mcp_api": "https://account.karinex.de/customer/api/mcp"}
        """

    static func routes(token: [StubHTTPClient.Reply] = [], graphQL: [StubHTTPClient.Reply] = []) -> [String: [StubHTTPClient.Reply]] {
        [
            "/.well-known/openid-configuration": [.json(openIDDocument)],
            "/.well-known/customer-account-api": [.json(apiDocument)],
            "/authentication/oauth/token": token,
            "/customer/api/2026-10/graphql": graphQL,
        ]
    }

    static func discovery(_ http: some HTTPClient) -> CustomerAccountDiscovery {
        CustomerAccountDiscovery(openIDConfigurationURL: openIDURL, customerAccountAPIURL: apiURL, apiVersion: "2026-10", httpClient: http)
    }

    static func jwt(_ claims: [String: Any]) -> String {
        let header = Base64URL.encode(Array(#"{"alg":"RS256","typ":"JWT"}"#.utf8))
        let payload = (try? JSONSerialization.data(withJSONObject: claims)) ?? Data()
        return "\(header).\(Base64URL.encode(payload)).c2lnbmF0dXJl"
    }

    static func tokenResponse(
        nonce: String,
        refresh: String? = "shcrt_refresh1",
        access: String = "shcat_access1",
        expiresIn: Int = 3600
    ) -> String {
        let idToken = jwt(["iss": issuer, "aud": clientID, "exp": 4_102_444_800, "nonce": nonce, "sub": "gid://shopify/Customer/1"])
        var fields = [#""access_token": "\#(access)""#, #""expires_in": \#(expiresIn)"#, #""id_token": "\#(idToken)""#]
        if let refresh {
            fields.append(#""refresh_token": "\#(refresh)""#)
        }
        return "{\(fields.joined(separator: ", "))}"
    }

    static let endpoints = CustomerAccountEndpoints(
        issuer: issuer,
        authorizationEndpoint: URL(string: "https://account.karinex.de/authentication/oauth/authorize")!,
        tokenEndpoint: URL(string: "https://account.karinex.de/authentication/oauth/token")!,
        endSessionEndpoint: URL(string: "https://account.karinex.de/authentication/logout")!,
        graphQLEndpoint: URL(string: "https://account.karinex.de/customer/api/2026-10/graphql")!
    )
}

private func formFields(_ request: HTTPRequest) -> [String: String] {
    let body = String(decoding: request.body ?? Data(), as: UTF8.self)
    var fields: [String: String] = [:]
    for pair in body.split(separator: "&") {
        let parts = pair.split(separator: "=", maxSplits: 1).map { String($0).removingPercentEncoding ?? String($0) }
        fields[parts[0]] = parts.count > 1 ? parts[1] : ""
    }
    return fields
}

private final class MutableClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ date: Date) {
        current = date
    }

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    func advance(by interval: TimeInterval) {
        lock.lock()
        current = current.addingTimeInterval(interval)
        lock.unlock()
    }
}

// MARK: - Discovery and authorization

@Suite("Customer Account login")
struct CustomerAccountLoginTests {
    @Test("Discovery reads both documents once and pins the API version")
    func discovery() async throws {
        let http = RoutingHTTPClient(AuthFixture.routes())
        let discovery = AuthFixture.discovery(http)
        async let first = discovery.endpoints()
        async let second = discovery.endpoints()
        let (endpoints, again) = try await (first, second)
        #expect(endpoints == again)
        #expect(endpoints.issuer == AuthFixture.issuer)
        #expect(endpoints.tokenEndpoint.absoluteString == "https://account.karinex.de/authentication/oauth/token")
        #expect(endpoints.endSessionEndpoint?.absoluteString == "https://account.karinex.de/authentication/logout")
        #expect(endpoints.graphQLEndpoint.absoluteString == "https://account.karinex.de/customer/api/2026-10/graphql")
        #expect(http.requests.count == 2)
        _ = try await discovery.endpoints()
        #expect(http.requests.count == 2)
    }

    @Test("A failed discovery is not cached")
    func failedDiscovery() async throws {
        let http = RoutingHTTPClient(AuthFixture.routes())
        http.setReplies([.failure(.offline), .json(AuthFixture.openIDDocument)], for: "/.well-known/openid-configuration")
        let discovery = AuthFixture.discovery(http)
        await #expect(throws: CustomerAccountAuthError.network(.offline)) {
            try await discovery.endpoints()
        }
        #expect(try await discovery.endpoints().issuer == AuthFixture.issuer)
    }

    @Test("Only a version segment after /api/ is replaced")
    func pinning() {
        let url = URL(string: "https://account.karinex.de/customer/api/2026-07/graphql")!
        #expect(CustomerAccountDiscovery.pinning(url, to: "2026-10")
            .absoluteString == "https://account.karinex.de/customer/api/2026-10/graphql")
        let other = URL(string: "https://account.karinex.de/customer/graphql")!
        #expect(CustomerAccountDiscovery.pinning(other, to: "2026-10") == other)
    }

    @Test("The authorization URL carries PKCE S256, state, nonce, scopes and the locale")
    func authorizationURL() throws {
        let pkce = PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        let authorization = CustomerAccountAuthorization(
            endpoints: AuthFixture.endpoints,
            clientID: AuthFixture.clientID,
            redirectURI: AuthFixture.redirectURI,
            locale: "de",
            pkce: pkce,
            state: "state-1",
            nonce: "nonce-1"
        )
        let components = try #require(URLComponents(url: authorization.url, resolvingAgainstBaseURL: false))
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(components.host == "account.karinex.de")
        #expect(items["client_id"] == AuthFixture.clientID)
        #expect(items["scope"] == "openid email customer-account-api:full")
        #expect(items["response_type"] == "code")
        #expect(items["redirect_uri"] == "shop.91753283851.app://callback")
        #expect(items["state"] == "state-1")
        #expect(items["nonce"] == "nonce-1")
        #expect(items["code_challenge"] == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        #expect(items["code_challenge_method"] == "S256")
        #expect(items["locale"] == "de")
        #expect(!authorization.url.absoluteString.contains(pkce.verifier))
    }

    @Test("Fresh PKCE pairs have 43 character verifiers and differ")
    func freshPKCE() {
        let first = PKCE.make()
        let second = PKCE.make()
        #expect(first.verifier.count == 43)
        #expect(first != second)
        #expect(first.challenge == Base64URL.encode(SHA256.hash(first.verifier)))
    }

    @Test("The callback is checked: scheme, state, OAuth error and code")
    func callbackParsing() throws {
        let authorization = CustomerAccountAuthorization(
            endpoints: AuthFixture.endpoints,
            clientID: AuthFixture.clientID,
            redirectURI: AuthFixture.redirectURI,
            locale: nil,
            state: "good",
            nonce: "n"
        )
        #expect(try authorization.code(fromCallback: URL(string: "shop.91753283851.app://callback?code=abc&state=good")!) == "abc")
        #expect(throws: CustomerAccountAuthError.stateMismatch) {
            try authorization.code(fromCallback: URL(string: "shop.91753283851.app://callback?code=abc&state=bad")!)
        }
        #expect(throws: CustomerAccountAuthError.stateMismatch) {
            try authorization.code(fromCallback: URL(string: "shop.91753283851.app://callback?code=abc")!)
        }
        #expect(throws: CustomerAccountAuthError.authorizationFailed(code: "access_denied")) {
            try authorization.code(fromCallback: URL(string: "shop.91753283851.app://callback?error=access_denied&state=good")!)
        }
        #expect(throws: CustomerAccountAuthError.invalidCallback) {
            try authorization.code(fromCallback: URL(string: "karinex://callback?code=abc&state=good")!)
        }
        #expect(throws: CustomerAccountAuthError.invalidCallback) {
            try authorization.code(fromCallback: URL(string: "shop.91753283851.app://callback?state=good")!)
        }
    }

    @Test("ID tokens are checked for nonce, audience, issuer and expiry")
    func idTokenValidation() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let token = AuthFixture.jwt([
            "iss": AuthFixture.issuer,
            "aud": [AuthFixture.clientID, "other"],
            "exp": 1_800_000_600,
            "nonce": "n1",
        ])
        let claims = try IDTokenClaims(token: token)
        #expect(claims.audiences == [AuthFixture.clientID, "other"])
        try claims.validate(nonce: "n1", clientID: AuthFixture.clientID, issuer: AuthFixture.issuer, now: now)
        #expect(throws: CustomerAccountAuthError.invalidIDToken(reason: "nonce")) {
            try claims.validate(nonce: "n2", clientID: AuthFixture.clientID, issuer: AuthFixture.issuer, now: now)
        }
        #expect(throws: CustomerAccountAuthError.invalidIDToken(reason: "aud")) {
            try claims.validate(nonce: "n1", clientID: "someone-else", issuer: AuthFixture.issuer, now: now)
        }
        #expect(throws: CustomerAccountAuthError.invalidIDToken(reason: "iss")) {
            try claims.validate(nonce: "n1", clientID: AuthFixture.clientID, issuer: "https://evil.example", now: now)
        }
        #expect(throws: CustomerAccountAuthError.invalidIDToken(reason: "exp")) {
            try claims.validate(nonce: "n1", clientID: AuthFixture.clientID, issuer: AuthFixture.issuer, now: now.addingTimeInterval(3600))
        }
        #expect(throws: CustomerAccountAuthError.invalidIDToken(reason: "format")) {
            try IDTokenClaims(token: "not-a-jwt")
        }
    }

    @Test("Token descriptions never contain a token")
    func tokenDescription() {
        let tokens = CustomerAccountTokens(accessToken: "shcat_secret", refreshToken: "shcrt_secret", idToken: "eyJ.x.y", expiresAt: Date())
        #expect(!tokens.description.contains("secret"))
        #expect(!String(reflecting: tokens).contains("secret"))
        #expect(!CustomerAccountAuthError.tokenEndpoint(statusCode: 400, code: "invalid_request").logDescription.contains("secret"))
    }

    @Test("Form encoding keeps unreserved characters and encodes everything else")
    func formEncoding() {
        let encoded = CustomerAccountTokenClient.formEncoded([("redirect_uri", "shop.1.app://callback"), ("x", "a b+c")])
        #expect(encoded == "redirect_uri=shop.1.app%3A%2F%2Fcallback&x=a%20b%2Bc")
    }
}

// MARK: - Session

@Suite("Customer Account session")
struct CustomerAccountSessionTests {
    private static func makeSession(
        http: RoutingHTTPClient,
        store: InMemorySecureStore = InMemorySecureStore(),
        clock: MutableClock = MutableClock(Date(timeIntervalSince1970: 1_800_000_000))
    ) -> CustomerAccountSession {
        CustomerAccountSession(
            clientID: AuthFixture.clientID,
            redirectURI: AuthFixture.redirectURI,
            discovery: AuthFixture.discovery(http),
            httpClient: http,
            secureStore: store,
            now: { clock.now },
            logger: KXLogger(category: .auth, sink: RecordingLogSink())
        )
    }

    private static func signIn(
        _ session: CustomerAccountSession,
        http: RoutingHTTPClient,
        refresh: String? = "shcrt_refresh1"
    ) async throws {
        let authorization = try await session.beginSignIn(locale: "de")
        http.setReplies(
            [.json(AuthFixture.tokenResponse(nonce: authorization.nonce, refresh: refresh))],
            for: "/authentication/oauth/token"
        )
        let callback = URL(string: "shop.91753283851.app://callback?code=code123&state=\(authorization.state)")!
        try await session.completeSignIn(authorization, callbackURL: callback)
    }

    @Test("Signing in exchanges the code with the verifier and stores the tokens in the Keychain")
    func signIn() async throws {
        let http = RoutingHTTPClient(AuthFixture.routes())
        let store = InMemorySecureStore()
        let session = Self.makeSession(http: http, store: store)
        #expect(await !session.isSignedIn)

        let authorization = try await session.beginSignIn(locale: "de")
        http.setReplies([.json(AuthFixture.tokenResponse(nonce: authorization.nonce))], for: "/authentication/oauth/token")
        try await session.completeSignIn(
            authorization,
            callbackURL: URL(string: "shop.91753283851.app://callback?code=code123&state=\(authorization.state)")!
        )

        let request = try #require(http.requests(to: "/authentication/oauth/token").first)
        #expect(request.method == .post)
        #expect(request.value(forHeader: "Content-Type") == "application/x-www-form-urlencoded")
        let fields = formFields(request)
        #expect(fields["grant_type"] == "authorization_code")
        #expect(fields["client_id"] == AuthFixture.clientID)
        #expect(fields["code"] == "code123")
        #expect(fields["code_verifier"] == authorization.pkce.verifier)
        #expect(fields["redirect_uri"] == "shop.91753283851.app://callback")

        #expect(await session.isSignedIn)
        #expect(try await session.accessToken() == "shcat_access1")
        let stored = try #require(try store.value(CustomerAccountTokens.self, for: CustomerAccountSession.tokenStorageKey))
        #expect(stored.refreshToken == "shcrt_refresh1")

        // A new session on the same store is signed in without logging in again.
        let restored = Self.makeSession(http: http, store: store)
        #expect(await restored.isSignedIn)
    }

    @Test("A wrong nonce in the ID token stores nothing")
    func wrongNonce() async throws {
        let http = RoutingHTTPClient(AuthFixture.routes())
        let session = Self.makeSession(http: http)
        let authorization = try await session.beginSignIn(locale: nil)
        http.setReplies([.json(AuthFixture.tokenResponse(nonce: "replayed"))], for: "/authentication/oauth/token")
        await #expect(throws: CustomerAccountAuthError.invalidIDToken(reason: "nonce")) {
            try await session.completeSignIn(
                authorization,
                callbackURL: URL(string: "shop.91753283851.app://callback?code=c&state=\(authorization.state)")!
            )
        }
        #expect(await !session.isSignedIn)
    }

    @Test("An expiring access token is refreshed once for concurrent callers")
    func refreshSingleFlight() async throws {
        let http = RoutingHTTPClient(AuthFixture.routes())
        let clock = MutableClock(Date(timeIntervalSince1970: 1_800_000_000))
        let session = Self.makeSession(http: http, clock: clock)
        try await Self.signIn(session, http: http)
        http.setReplies(
            [.json(#"{"access_token": "shcat_access2", "expires_in": 3600, "refresh_token": "shcrt_refresh2"}"#)],
            for: "/authentication/oauth/token"
        )
        clock.advance(by: 3590)

        async let first = session.accessToken()
        async let second = session.accessToken()
        let tokens = try await [first, second]
        #expect(tokens == ["shcat_access2", "shcat_access2"])
        let refreshes = http.requests(to: "/authentication/oauth/token").filter { formFields($0)["grant_type"] == "refresh_token" }
        #expect(refreshes.count == 1)
        #expect(try formFields(#require(refreshes.first))["refresh_token"] == "shcrt_refresh1")
    }

    @Test("A rejected refresh token signs the customer out")
    func invalidGrantSignsOut() async throws {
        let http = RoutingHTTPClient(AuthFixture.routes())
        let store = InMemorySecureStore()
        let session = Self.makeSession(http: http, store: store)
        try await Self.signIn(session, http: http)
        http.setReplies([.json(#"{"error": "invalid_grant"}"#, status: 400)], for: "/authentication/oauth/token")
        await session.invalidateAccessToken()

        await #expect(throws: CustomerAccountAuthError.signedOut) {
            try await session.accessToken()
        }
        #expect(await !session.isSignedIn)
        #expect(try store.data(for: CustomerAccountSession.tokenStorageKey) == nil)
    }

    @Test("A refresh that fails offline keeps the tokens")
    func offlineRefreshKeepsTokens() async throws {
        let http = RoutingHTTPClient(AuthFixture.routes())
        let session = Self.makeSession(http: http)
        try await Self.signIn(session, http: http)
        http.setReplies([.failure(.offline)], for: "/authentication/oauth/token")
        await session.invalidateAccessToken()
        await #expect(throws: CustomerAccountAuthError.network(.offline)) {
            try await session.accessToken()
        }
        #expect(await session.isSignedIn)
    }

    @Test("Signing out removes the tokens and returns the end-session URL with the ID token hint")
    func signOut() async throws {
        let http = RoutingHTTPClient(AuthFixture.routes())
        let store = InMemorySecureStore()
        let session = Self.makeSession(http: http, store: store)
        try await Self.signIn(session, http: http)

        let url = try #require(await session.signOut())
        #expect(url.host == "account.karinex.de")
        #expect(url.query?.contains("id_token_hint=") == true)
        #expect(await !session.isSignedIn)
        #expect(try store.data(for: CustomerAccountSession.tokenStorageKey) == nil)
        await #expect(throws: CustomerAccountAuthError.signedOut) {
            try await session.accessToken()
        }
    }

    @Test("Sign-in and sign-out are announced on the event stream")
    func events() async throws {
        let http = RoutingHTTPClient(AuthFixture.routes())
        let session = Self.makeSession(http: http)
        var iterator = session.events.makeAsyncIterator()
        try await Self.signIn(session, http: http)
        await session.clear()
        #expect(await iterator.next() == .signedIn)
        #expect(await iterator.next() == .signedOut)
    }

    @Test("Without a refresh token an expired session signs out")
    func noRefreshToken() async throws {
        let http = RoutingHTTPClient(AuthFixture.routes())
        let session = Self.makeSession(http: http)
        try await Self.signIn(session, http: http, refresh: nil)
        await session.invalidateAccessToken()
        await #expect(throws: CustomerAccountAuthError.signedOut) {
            try await session.accessToken()
        }
    }
}

// MARK: - API and repository

@Suite("Customer Account API")
struct CustomerAccountAPITests {
    private static let customerJSON = """
        {"data": {"customer": {"id": "gid://shopify/Customer/1", "displayName": "Anna Schmidt", "firstName": "Anna",
          "lastName": "Schmidt", "emailAddress": {"emailAddress": "anna@example.com"},
          "defaultAddress": {"id": "gid://shopify/CustomerAddress/9", "firstName": "Anna", "lastName": "Schmidt",
            "company": null, "address1": "Hauptstraße 1", "address2": "", "zip": "22115", "city": "Hamburg",
            "province": null, "zoneCode": null, "country": "Deutschland", "territoryCode": "DE"}}}}
        """

    private static let ordersJSON = """
        {"data": {"customer": {"orders": {"nodes": [
          {"id": "gid://shopify/Order/5678", "name": "#1042", "confirmationNumber": "ABC123",
           "processedAt": "2026-10-20T09:15:00Z", "cancelledAt": null, "financialStatus": "PAID",
           "fulfillmentStatus": "FULFILLED", "totalPrice": {"amount": "119.9", "currencyCode": "EUR"}},
          {"id": "gid://shopify/Order/5677", "name": "#1041", "confirmationNumber": null,
           "processedAt": "2026-10-01T09:15:00.123Z", "cancelledAt": "2026-10-02T09:15:00Z", "financialStatus": "REFUNDED",
           "fulfillmentStatus": "SOMETHING_NEW", "totalPrice": {"amount": "11.90", "currencyCode": "EUR"}}],
          "pageInfo": {"hasNextPage": true, "hasPreviousPage": false, "startCursor": "a", "endCursor": "b"}}}}}
        """

    private static let orderJSON = """
        {"data": {"order": {"id": "gid://shopify/Order/5678", "name": "#1042", "confirmationNumber": "ABC123",
          "processedAt": "2026-10-20T09:15:00Z", "cancelledAt": null, "financialStatus": "PAID", "fulfillmentStatus": "FULFILLED",
          "totalPrice": {"amount": "119.9", "currencyCode": "EUR"}, "subtotal": {"amount": "100.76", "currencyCode": "EUR"},
          "totalTax": {"amount": "19.14", "currencyCode": "EUR"}, "totalShipping": {"amount": "0.0", "currencyCode": "EUR"},
          "lineItems": {"nodes": [{"id": "gid://shopify/LineItem/1", "name": "Office 2024 Professional Plus",
            "presentmentTitle": "Default Title", "quantity": 1, "price": {"amount": "119.9", "currencyCode": "EUR"},
            "currentTotalPrice": {"amount": "119.9", "currencyCode": "EUR"}, "image": null}]},
          "fulfillments": {"nodes": [{"id": "gid://shopify/Fulfillment/3", "status": "SUCCESS", "latestShipmentStatus": null,
            "updatedAt": "2026-10-20T09:20:00Z"}]}}}}
        """

    private static func makeRepository(graphQL: [StubHTTPClient.Reply]) async throws
        -> (ShopifyCustomerAccountRepository, RoutingHTTPClient, CustomerAccountSession)
    {
        let http = RoutingHTTPClient(AuthFixture.routes(graphQL: graphQL))
        let discovery = AuthFixture.discovery(http)
        let session = CustomerAccountSession(
            clientID: AuthFixture.clientID,
            redirectURI: AuthFixture.redirectURI,
            discovery: discovery,
            httpClient: http,
            secureStore: InMemorySecureStore(),
            logger: KXLogger(category: .auth, sink: RecordingLogSink())
        )
        let authorization = try await session.beginSignIn(locale: nil)
        http.setReplies([.json(AuthFixture.tokenResponse(nonce: authorization.nonce))], for: "/authentication/oauth/token")
        try await session.completeSignIn(
            authorization,
            callbackURL: URL(string: "shop.91753283851.app://callback?code=c&state=\(authorization.state)")!
        )
        let client = CustomerAccountAPIClient(
            discovery: discovery,
            session: session,
            httpClient: http,
            logger: KXLogger(category: .customerAccount, sink: RecordingLogSink())
        )
        return (ShopifyCustomerAccountRepository(client: client), http, session)
    }

    @Test("Requests go to the pinned GraphQL URL with the raw access token")
    func customer() async throws {
        let (repository, http, _) = try await Self.makeRepository(graphQL: [.json(Self.customerJSON)])
        let customer = try await repository.customer()
        #expect(customer.displayName == "Anna Schmidt")
        #expect(customer.emailAddress == "anna@example.com")
        #expect(customer.defaultAddress?.lines == ["Anna Schmidt", "Hauptstraße 1", "22115 Hamburg", "Deutschland"])

        let request = try #require(http.requests(to: "/customer/api/2026-10/graphql").first)
        #expect(request.value(forHeader: "Authorization") == "shcat_access1")
        #expect(try SentGraphQLBody(request).operationName == "Customer")
    }

    @Test("Orders decode statuses, dates and the next cursor; unknown statuses are kept")
    func orders() async throws {
        let (repository, http, _) = try await Self.makeRepository(graphQL: [.json(Self.ordersJSON)])
        let page = try await repository.orders(first: 20, after: nil)
        #expect(page.orders.count == 2)
        #expect(page.nextCursor == "b")
        let first = page.orders[0]
        #expect(first.name == "#1042")
        #expect(first.financialStatus == .paid)
        #expect(first.financialStatus?.isPaid == true)
        #expect(first.fulfillmentStatus == .fulfilled)
        #expect(first.totalPrice == MoneyV2(amount: decimal("119.9"), currencyCode: .eur))
        #expect(first.numericID == "5678")
        #expect(page.orders[1].cancelledAt != nil)
        #expect(page.orders[1].fulfillmentStatus == .unknown("SOMETHING_NEW"))

        let body = try SentGraphQLBody(#require(http.requests(to: "/customer/api/2026-10/graphql").first))
        #expect(body.variables["first"] == .number(20))
        #expect(body.query.contains("sortKey: PROCESSED_AT, reverse: true"))
    }

    @Test("An order detail has line items and fulfillments; the default variant title is hidden")
    func orderDetail() async throws {
        let (repository, _, _) = try await Self.makeRepository(graphQL: [.json(Self.orderJSON)])
        let order = try #require(try await repository.order(id: "gid://shopify/Order/5678"))
        #expect(order.lineItems.count == 1)
        #expect(order.lineItems[0].variantTitle == nil)
        #expect(order.lineItems[0].quantity == 1)
        #expect(order.fulfillments.first?.isSuccessful == true)
        #expect(order.totalTax?.amount == decimal("19.14"))
    }

    @Test("A 401 refreshes the token and repeats the request once")
    func unauthorizedRetry() async throws {
        let (repository, http, _) = try await Self.makeRepository(graphQL: [.status(401), .json(Self.customerJSON)])
        http.setReplies(
            [.json(#"{"access_token": "shcat_access2", "expires_in": 3600}"#)],
            for: "/authentication/oauth/token"
        )
        let customer = try await repository.customer()
        #expect(customer.firstName == "Anna")
        let calls = http.requests(to: "/customer/api/2026-10/graphql")
        #expect(calls.map { $0.value(forHeader: "Authorization") } == ["shcat_access1", "shcat_access2"])
    }

    @Test("Without tokens the API is not called")
    func signedOut() async throws {
        let (repository, http, session) = try await Self.makeRepository(graphQL: [.json(Self.customerJSON)])
        await session.clear()
        await #expect(throws: CustomerAccountAuthError.signedOut) {
            try await repository.customer()
        }
        #expect(http.requests(to: "/customer/api/2026-10/graphql").isEmpty)
    }

    @Test("Address mutations surface Shopify's user errors")
    func addressUserErrors() async throws {
        let errors = """
            {"data": {"customerAddressCreate": {"customerAddress": null,
              "userErrors": [{"field": ["address", "zip"], "message": "Postleitzahl ist ungültig", "code": "INVALID"}]}}}
            """
        let (repository, http, _) = try await Self.makeRepository(graphQL: [.json(errors)])
        await #expect(throws: ShopifyError.userErrors([UserError(
            field: ["address", "zip"],
            message: "Postleitzahl ist ungültig",
            code: .invalid
        )])) {
            try await repository.createAddress(CustomerAddressInput(zip: "x", territoryCode: "DE"), makeDefault: false)
        }
        let body = try SentGraphQLBody(#require(http.requests(to: "/customer/api/2026-10/graphql").first))
        #expect(body.operationName == "CustomerAddressCreate")
        #expect(body.variables["address"] == .object(["zip": .string("x"), "territoryCode": .string("DE")]))
        #expect(body.variables["defaultAddress"] == .bool(false))
    }

    @Test("Every Customer Account document is a single named operation with its fragments")
    func documents() {
        let documents = [
            (CustomerQuery.operationName, CustomerQuery.document),
            (CustomerOrdersQuery.operationName, CustomerOrdersQuery.document),
            (CustomerOrderQuery.operationName, CustomerOrderQuery.document),
            (CustomerAddressesQuery.operationName, CustomerAddressesQuery.document),
            (CustomerAddressCreateMutation.operationName, CustomerAddressCreateMutation.document),
            (CustomerAddressUpdateMutation.operationName, CustomerAddressUpdateMutation.document),
            (CustomerAddressDeleteMutation.operationName, CustomerAddressDeleteMutation.document),
        ]
        for (name, document) in documents {
            #expect(document.contains(" \(name)"))
            for spread in document.matches(of: /\.\.\.([A-Za-z]+)/) {
                #expect(document.contains("fragment \(spread.1) on"), "\(name) uses \(spread.1) without defining it")
            }
        }
    }
}
