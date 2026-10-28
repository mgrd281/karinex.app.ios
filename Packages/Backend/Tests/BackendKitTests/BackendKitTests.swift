@testable import BackendKit
import Core
import Foundation
import Testing

// MARK: - Support

/// Records requests and answers with queued responses.
private final class QueueHTTPClient: HTTPClient {
    private let state: Locked<(requests: [HTTPRequest], replies: [Result<HTTPResponse, NetworkError>])>

    init(_ replies: [Result<HTTPResponse, NetworkError>]) {
        state = Locked(([], replies))
    }

    var requests: [HTTPRequest] {
        state.value.requests
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let reply = state.withLock { state -> Result<HTTPResponse, NetworkError>? in
            state.requests.append(request)
            return state.replies.isEmpty ? nil : state.replies.removeFirst()
        }
        guard let reply else { throw NetworkError.invalidResponse }
        return try reply.get()
    }
}

private struct ImmediateSleeper: Sleeper {
    func sleep(for _: Duration) async throws {}
}

private func json(_ body: String, status: Int = 200, headers: [String: String] = [:]) -> Result<HTTPResponse, NetworkError> {
    .success(HTTPResponse(statusCode: status, headers: headers, body: Data(body.utf8)))
}

private func makeClient(_ http: QueueHTTPClient, token: String? = "shcat_token") -> HTTPBackendClient {
    HTTPBackendClient(
        baseURL: URL(string: "https://app-api.karinex.de")!,
        httpClient: http,
        accessToken: {
            guard let token else { throw BackendError.unauthorized }
            return token
        },
        appVersion: "0.2.0",
        languageCode: { "fr" },
        sleeper: ImmediateSleeper(),
        logger: KXLogger(category: .networking, sink: RecordingLogSink())
    )
}

private let configJSON = """
    {"supportHours": {"timeZone": "Europe/Berlin", "weekdays": [1, 2, 3, 4, 5, 6, 7], "opensAt": "08:00", "closesAt": "23:00"},
     "whatsappNumber": "+49 40 1234567", "liveChatUrl": "https://www.karinex.de/pages/live-chat",
     "supportEmail": "kundenservice@karinex.de", "featureFlags": {"licenseVault": true}, "homeBanners": [],
     "minSupportedAppVersion": "0.2.0"}
    """

// MARK: - Config and support hours

@Suite("Backend config and support hours")
struct BackendConfigTests {
    @Test("The config decodes and is cached with its ETag")
    func configWithETag() async throws {
        let http = QueueHTTPClient([json(configJSON, headers: ["ETag": "\"v1\""]), .success(HTTPResponse(statusCode: 304))])
        let client = makeClient(http)
        let first = try await client.appConfig()
        #expect(first.whatsappNumber == "49401234567")
        #expect(first.liveChatURL?.host == "www.karinex.de")
        #expect(first.featureFlags["licenseVault"] == true)
        #expect(first.supportHours == .standard)

        let second = try await client.appConfig()
        #expect(second == first)
        #expect(http.requests[1].value(forHeader: "If-None-Match") == "\"v1\"")
        #expect(http.requests[0].value(forHeader: "Authorization") == nil)
        #expect(http.requests[0].value(forHeader: "X-KX-App-Version") == "0.2.0")
        #expect(http.requests[0].value(forHeader: "Accept-Language") == "fr")
        #expect(http.requests[0].url.absoluteString == "https://app-api.karinex.de/v1/app/config")
    }

    @Test("Missing values fall back; a live chat link that is not https is dropped")
    func partialConfig() throws {
        let config = try JSONDecoder().decode(RemoteAppConfig.self, from: Data(#"{"liveChatUrl": "http://chat.example"}"#.utf8))
        #expect(config.supportHours == .standard)
        #expect(config.liveChatURL == nil)
        #expect(config.whatsappNumber == nil)
        #expect(config.supportEmail == "kundenservice@karinex.de")
    }

    @Test("The WhatsApp link is wa.me with the prefilled text")
    func whatsAppLink() throws {
        let config = try JSONDecoder().decode(RemoteAppConfig.self, from: Data(configJSON.utf8))
        let url = try #require(config.whatsAppURL(message: "Bestellung #1042"))
        #expect(url.absoluteString == "https://wa.me/49401234567?text=Bestellung%20%231042")
        #expect(RemoteAppConfig.fallback.whatsAppURL(message: nil) == nil)
    }

    @Test("An app older than the minimum version must update")
    func minimumVersion() throws {
        let config = try JSONDecoder().decode(RemoteAppConfig.self, from: Data(configJSON.utf8))
        #expect(config.requiresUpdate(appVersion: "0.1.9"))
        #expect(!config.requiresUpdate(appVersion: "0.2.0"))
        #expect(!config.requiresUpdate(appVersion: "0.10.0"))
        #expect(!RemoteAppConfig.fallback.requiresUpdate(appVersion: "0.0.1"))
    }

    @Test("Support is open Monday to Sunday from 08:00 to 23:00 Berlin time")
    func openingHours() throws {
        let hours = SupportHours.standard
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Berlin"))
        func date(_ day: Int, _ hour: Int, _ minute: Int) throws -> Date {
            try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute)))
        }
        #expect(try hours.isOpen(at: date(25, 8, 0)))
        #expect(try hours.isOpen(at: date(25, 22, 59)))
        #expect(try !hours.isOpen(at: date(25, 23, 0)))
        #expect(try !hours.isOpen(at: date(26, 7, 59)))
        #expect(try hours.isOpen(at: date(26, 12, 0)))
        #expect(hours.isEveryDay)
        let interval = try #require(try hours.interval(on: date(26, 12, 0)))
        #expect(interval.closes.timeIntervalSince(interval.opens) == 15 * 3600)
    }

    @Test("Weekday-only hours are closed on Sunday")
    func weekdaysOnly() throws {
        let hours = try JSONDecoder().decode(
            SupportHours.self,
            from: Data(#"{"timeZone": "Europe/Berlin", "weekdays": [1, 2, 3, 4, 5], "opensAt": "09:00", "closesAt": "17:30"}"#.utf8)
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Berlin"))
        let sunday = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 12)))
        let monday = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 17, minute: 29)))
        #expect(!hours.isOpen(at: sunday))
        #expect(hours.isOpen(at: monday))
        #expect(!hours.isEveryDay)
        #expect(SupportHours.text(hours.closesAtMinute) == "17:30")
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(SupportHours.self, from: Data(#"{"opensAt": "18:00", "closesAt": "09:00"}"#.utf8))
        }
    }
}

// MARK: - Customer endpoints

@Suite("Backend customer endpoints")
struct BackendCustomerTests {
    private static let licensesJSON = """
        {"licenses": [{"lineItemId": "11", "productTitle": "Office 2024 Professional Plus", "sku": "O24PP",
          "key": "ABCDE-FGHIJ-KLMNO-PQRST-UVWXY", "deliveredAt": "2026-10-20T09:20:00Z",
          "activationGuideUrl": "https://www.karinex.de/blogs/guides/office-2024"}]}
        """

    @Test("Orders are read with the bearer token")
    func orders() async throws {
        let http =
            QueueHTTPClient(
                [json(##"{"orders": [{"orderId": "5678", "name": "#1042", "deliveryStatus": "delivered", "hasLicenses": true}]}"##)]
            )
        let orders = try await makeClient(http).orders()
        let expected = BackendOrderStatus(orderID: "5678", name: "#1042", deliveryStatus: .delivered, hasLicenses: true, hasInvoice: true)
        #expect(orders == [expected])
        #expect(http.requests[0].value(forHeader: "Authorization") == "Bearer shcat_token")
    }

    @Test("Licenses decode with the order ID; 202 means pending")
    func licenses() async throws {
        let http = QueueHTTPClient([json(Self.licensesJSON), json(#"{"status": "pending"}"#, status: 202)])
        let client = makeClient(http)
        guard case let .delivered(keys) = try await client.licenses(orderID: "5678") else {
            Issue.record("Expected delivered keys")
            return
        }
        #expect(keys.count == 1)
        #expect(keys[0].orderID == "5678")
        #expect(keys[0].key == "ABCDE-FGHIJ-KLMNO-PQRST-UVWXY")
        #expect(keys[0].activationGuideURL?.host == "www.karinex.de")
        #expect(!keys[0].description.contains("ABCDE"))
        #expect(!keys[0].id.contains("ABCDE"))
        #expect(!String(reflecting: keys[0]).contains("ABCDE"))
        #expect(try await client.licenses(orderID: "5678") == .pending)
        #expect(http.requests[0].url.path == "/v1/app/orders/5678/licenses")
    }

    @Test("HTTP errors map to typed errors with the contract code")
    func errors() async throws {
        let http = QueueHTTPClient([
            json(#"{"code": "not_owner", "message": "x", "requestId": "r1"}"#, status: 403),
            json(#"{"code": "invoice_missing", "message": "x", "requestId": "r2"}"#, status: 422),
            json("{}", status: 503),
            json("{}", status: 503),
            json("{}", status: 503),
        ])
        let client = makeClient(http)
        await #expect(throws: BackendError.forbidden) {
            try await client.licenses(orderID: "1")
        }
        await #expect(throws: BackendError.server(statusCode: 422, code: "invoice_missing", requestID: "r2")) {
            try await client.invoice(orderID: "1")
        }
        await #expect(throws: BackendError.server(statusCode: 503, code: nil, requestID: nil)) {
            try await client.orders()
        }
        #expect(http.requests.count == 5)
    }

    @Test("POST is never repeated after an ambiguous failure")
    func postNotRetried() async throws {
        let http = QueueHTTPClient([json("{}", status: 503), json(#"{"requestId": "r9"}"#, status: 202)])
        let client = makeClient(http)
        await #expect(throws: BackendError.server(statusCode: 503, code: nil, requestID: nil)) {
            try await client.requestAccountDeletion()
        }
        #expect(http.requests.count == 1)
        #expect(try await client.requestAccountDeletion() == "r9")
        #expect(http.requests[1].method == .post)
        #expect(String(decoding: http.requests[1].body ?? Data(), as: UTF8.self) == #"{"confirm":true}"#)
    }

    @Test("Without a customer token nothing is sent")
    func signedOut() async throws {
        let http = QueueHTTPClient([])
        await #expect(throws: BackendError.unauthorized) {
            try await makeClient(http, token: nil).orders()
        }
        #expect(http.requests.isEmpty)
    }

    @Test("IDs that would change the path are rejected")
    func pathSegments() throws {
        #expect(try HTTPBackendClient.pathSegment("5678") == "5678")
        #expect(throws: BackendError.notFound) {
            try HTTPBackendClient.pathSegment("../admin")
        }
        #expect(throws: BackendError.notFound) {
            try HTTPBackendClient.pathSegment("1?x=2")
        }
    }

    @Test("Invoice links must be https")
    func invoice() async throws {
        let http = QueueHTTPClient([
            json(#"{"url": "https://files.karinex.de/i/1.pdf?sig=abc", "expiresAt": "2026-10-25T10:00:00Z"}"#),
            json(#"{"url": "http://files.karinex.de/i/1.pdf"}"#),
        ])
        let client = makeClient(http)
        #expect(try await client.invoice(orderID: "5678").url.host == "files.karinex.de")
        await #expect(throws: BackendError.decoding) {
            try await client.invoice(orderID: "5678")
        }
    }

    @Test("The unavailable client gives the fallback config and nothing else")
    func unavailable() async throws {
        let client = UnavailableBackendClient()
        #expect(try await client.appConfig() == .fallback)
        await #expect(throws: BackendError.notConfigured) {
            try await client.orders()
        }
    }
}

// MARK: - License cache

@Suite("License key cache")
struct LicenseKeyCacheTests {
    private static func key(_ line: String, delivered: TimeInterval) -> LicenseKey {
        LicenseKey(
            lineItemID: line,
            productTitle: "Windows 11 Pro",
            sku: nil,
            key: "AAAAA-BBBBB-CCCCC-DDDDD-\(line)0000",
            deliveredAt: Date(timeIntervalSince1970: delivered),
            activationGuideURL: nil,
            orderID: ""
        )
    }

    @Test("Keys are stored per order, newest first, and wiped together")
    func storeAndWipe() {
        let store = InMemorySecureStore()
        let cache = LicenseKeyCache(store: store, logger: KXLogger(category: .keychain, sink: RecordingLogSink()))
        cache.store([Self.key("1", delivered: 100)], orderID: "A")
        cache.store([Self.key("2", delivered: 200), Self.key("3", delivered: 50)], orderID: "B")
        #expect(cache.all().map(\.lineItemID) == ["2", "1", "3"])
        #expect(cache.keys(orderID: "A").map(\.orderID) == ["A"])

        cache.store([Self.key("4", delivered: 300)], orderID: "B")
        #expect(cache.keys(orderID: "B").map(\.lineItemID) == ["4"])

        let restored = LicenseKeyCache(store: store)
        #expect(restored.all().count == 2)

        cache.removeAll()
        #expect(cache.all().isEmpty)
    }
}
