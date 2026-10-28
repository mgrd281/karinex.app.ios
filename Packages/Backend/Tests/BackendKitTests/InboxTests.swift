@testable import BackendKit
import Core
import Foundation
import Testing

private final class InboxHTTPClient: HTTPClient {
    private let state: Locked<(requests: [HTTPRequest], replies: [HTTPResponse])>

    init(_ replies: [HTTPResponse]) {
        state = Locked(([], replies))
    }

    var requests: [HTTPRequest] {
        state.value.requests
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let reply = state.withLock { state -> HTTPResponse? in
            state.requests.append(request)
            return state.replies.isEmpty ? nil : state.replies.removeFirst()
        }
        guard let reply else { throw NetworkError.invalidResponse }
        return reply
    }
}

private struct NoSleep: Sleeper {
    func sleep(for _: Duration) async throws {}
}

private let installID = "3f2a9c1e-0b4d-4e6f-8a7b-1c2d3e4f5a6b"

private func client(_ http: InboxHTTPClient, token: String? = nil, installation: String? = installID) -> HTTPBackendClient {
    HTTPBackendClient(
        baseURL: URL(string: "https://app-api.karinex.de")!,
        httpClient: http,
        accessToken: {
            guard let token else { throw BackendError.unauthorized }
            return token
        },
        appVersion: "0.2.0",
        languageCode: { "de" },
        installationID: installation,
        sleeper: NoSleep(),
        logger: KXLogger(category: .networking, sink: RecordingLogSink())
    )
}

private let inboxJSON = """
    {"items": [
      {"id": "m1", "kind": "broadcast", "label": "Neu im Shop", "title": "Office 2024", "body": "Jetzt da.",
       "imageUrl": "https://cdn.shopify.com/a.png", "productHandle": "office-2024", "params": {}, "createdAt": "2026-10-28T10:00:00.000Z"},
      {"id": "m2", "kind": "restock", "label": null, "title": "", "body": "", "imageUrl": "http://insecure/b.png",
       "productHandle": "windows-11-pro", "params": {"productTitle": "Windows 11 Pro"}, "createdAt": "2026-10-27T09:00:00Z"},
      {"id": "m3", "kind": "something_new", "title": "", "body": "", "params": {}, "createdAt": "2026-10-26T09:00:00Z"}
    ]}
    """

@Suite("Neuigkeiten and restock")
struct InboxBackendTests {
    @Test("Notifications decode; only https images; unknown kinds are kept as unknown")
    func decode() async throws {
        let http = InboxHTTPClient([HTTPResponse(statusCode: 200, headers: [:], body: Data(inboxJSON.utf8))])
        let messages = try await client(http).notifications()
        #expect(messages.map(\.kind) == [.broadcast, .restock, .unknown])
        #expect(messages[0].imageURL?.host == "cdn.shopify.com")
        #expect(messages[1].imageURL == nil)
        #expect(messages[1].params["productTitle"] == "Windows 11 Pro")
        #expect(http.requests.first?.url.path == "/v1/app/notifications")
    }

    @Test("Guests send the installation ID without a token; signed in customers add their token")
    func headers() async throws {
        let empty = HTTPResponse(statusCode: 200, headers: [:], body: Data(#"{"items": []}"#.utf8))
        let guest = InboxHTTPClient([empty])
        _ = try await client(guest).notifications()
        #expect(guest.requests[0].value(forHeader: "X-KX-Install") == installID)
        #expect(guest.requests[0].value(forHeader: "Authorization") == nil)

        let signedIn = InboxHTTPClient([empty])
        _ = try await client(signedIn, token: "shcat_token").notifications()
        #expect(signedIn.requests[0].value(forHeader: "Authorization") == "Bearer shcat_token")
    }

    @Test("Without an installation ID the device endpoints are not available")
    func noInstallation() async {
        let http = InboxHTTPClient([])
        await #expect(throws: BackendError.notConfigured) { try await client(http, installation: nil).notifications() }
        #expect(http.requests.isEmpty)
    }

    @Test("Restock posts the product; cancelling deletes by variant number")
    func restock() async throws {
        let http = InboxHTTPClient([HTTPResponse(statusCode: 204), HTTPResponse(statusCode: 204)])
        let backend = client(http)
        let watch = RestockWatch(productHandle: "office-2024", variantID: "gid://shopify/ProductVariant/42", productTitle: "Office")
        try await backend.watchRestock(watch)
        try await backend.unwatchRestock(variantID: "gid://shopify/ProductVariant/42")
        let body = try #require(http.requests[0].body)
        let sent = try #require(try JSONSerialization.jsonObject(with: body) as? [String: String])
        #expect(sent == ["productHandle": "office-2024", "variantId": "gid://shopify/ProductVariant/42", "productTitle": "Office"])
        #expect(http.requests[1].method == .delete)
        #expect(http.requests[1].url.absoluteString == "https://app-api.karinex.de/v1/app/restock?variantId=42")
    }
}
