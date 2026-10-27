@testable import CommerceUI
import Core
import Foundation
import Testing

// MARK: - Stubs

private final class CounterServer: HTTPClient, @unchecked Sendable {
    private let state = Locked((count: Int?.none, requests: [HTTPRequest]()))

    init(count: Int?) {
        state.withLock { $0.count = count }
    }

    var requests: [HTTPRequest] {
        state.value.requests
    }

    var stored: Int? {
        state.value.count
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        state.withLock { $0.requests.append(request) }
        if request.method == .put {
            let value = try JSONDecoder().decode([String: Int].self, from: request.body ?? Data())["count"]
            state.withLock { $0.count = value }
            return HTTPResponse(statusCode: 200, body: request.body ?? Data())
        }
        guard let count = state.value.count else {
            return HTTPResponse(statusCode: 200, body: Data("null".utf8))
        }
        return HTTPResponse(statusCode: 200, body: Data("{\"count\":\(count)}".utf8))
    }
}

private final class AnalyticsConsent: ConsentStoring, @unchecked Sendable {
    private let consent: PrivacyConsent

    init(analytics: Bool) {
        consent = PrivacyConsent(analytics: analytics)
    }

    func load() -> PrivacyConsent {
        consent
    }

    func save(_ consent: PrivacyConsent) {}
}

// MARK: - Tests

@Suite("Save counter")
@MainActor
struct SaveCountStoreTests {
    @Test("Without analytics consent nothing is requested")
    func noConsentNoRequest() async {
        let server = CounterServer(count: 7)
        let store = SaveCountStore(http: server, consentStore: AnalyticsConsent(analytics: false))
        await store.refresh(handle: "windows-11-pro")
        await store.didChange(handle: "windows-11-pro", isSaved: true)
        #expect(server.requests.isEmpty)
        #expect(store.displayCount(for: "windows-11-pro") == nil)
    }

    @Test("Reading shows the shared number and an empty counter shows none")
    func reads() async {
        let server = CounterServer(count: 12)
        let store = SaveCountStore(http: server, consentStore: AnalyticsConsent(analytics: true))
        await store.refresh(handle: "windows-11-pro")
        #expect(store.displayCount(for: "windows-11-pro") == 12)
        #expect(server.requests.first?.url.path == "/wishlist/windows-11-pro.json")

        let empty = SaveCountStore(http: CounterServer(count: nil), consentStore: AnalyticsConsent(analytics: true))
        await empty.refresh(handle: "windows-11-pro")
        #expect(empty.displayCount(for: "windows-11-pro") == nil)
    }

    @Test("Saving counts up, removing counts down and never below zero")
    func writes() async {
        let server = CounterServer(count: 4)
        let store = SaveCountStore(http: server, consentStore: AnalyticsConsent(analytics: true))
        await store.didChange(handle: "office", isSaved: true)
        #expect(server.stored == 5)
        #expect(store.displayCount(for: "office") == 5)
        await store.didChange(handle: "office", isSaved: false)
        #expect(server.stored == 4)

        let zero = CounterServer(count: 0)
        let low = SaveCountStore(http: zero, consentStore: AnalyticsConsent(analytics: true))
        await low.didChange(handle: "office", isSaved: false)
        #expect(zero.stored == 0)
    }
}
