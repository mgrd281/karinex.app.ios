@testable import CommerceUI
import Core
import Foundation
import Testing

// MARK: - Stubs

private final class CounterServer: HTTPClient, @unchecked Sendable {
    private let state = Locked((count: 0, requests: [HTTPRequest](), fails: false))

    init(count: Int, fails: Bool = false) {
        state.withLock {
            $0.count = count
            $0.fails = fails
        }
    }

    var requests: [HTTPRequest] {
        state.value.requests
    }

    var stored: Int {
        state.value.count
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        state.withLock { $0.requests.append(request) }
        if state.value.fails {
            return HTTPResponse(statusCode: 503)
        }
        if request.method == .post {
            let change = try JSONDecoder().decode([String: CodableValue].self, from: request.body ?? Data())
            state.withLock { $0.count = change["saved"] == .bool(true) ? $0.count + 1 : max(0, $0.count - 1) }
        }
        return HTTPResponse(statusCode: 200, body: Data("{\"count\":\(state.value.count)}".utf8))
    }
}

private enum CodableValue: Decodable, Equatable {
    case bool(Bool)
    case string(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else {
            self = try .string(container.decode(String.self))
        }
    }
}

private let backend = URL(string: "https://backend.example")

// MARK: - Tests

@Suite("Save counter")
@MainActor
struct SaveCountStoreTests {
    @Test("Without a backend nothing is requested")
    func noBackendNoRequest() async {
        let server = CounterServer(count: 7)
        let store = SaveCountStore(http: server, backendBaseURL: nil)
        await store.refresh(handle: "windows-11-pro")
        await store.didChange(handle: "windows-11-pro", isSaved: true)
        #expect(server.requests.isEmpty)
        #expect(store.displayCount(for: "windows-11-pro") == nil)
    }

    @Test("Reading asks the backend for the handle and shows the number")
    func reads() async {
        let server = CounterServer(count: 12)
        let store = SaveCountStore(http: server, backendBaseURL: backend)
        await store.refresh(handle: "windows-11-pro")
        #expect(store.displayCount(for: "windows-11-pro") == 12)
        let url = server.requests.first?.url
        #expect(url?.path == "/v1/app/save-counts")
        #expect(url?.query == "handle=windows-11-pro")

        let empty = SaveCountStore(http: CounterServer(count: 0), backendBaseURL: backend)
        await empty.refresh(handle: "windows-11-pro")
        #expect(empty.displayCount(for: "windows-11-pro") == nil)
    }

    @Test("Saving counts up, removing counts down, a failure shows no number")
    func writes() async {
        let server = CounterServer(count: 4)
        let store = SaveCountStore(http: server, backendBaseURL: backend)
        await store.didChange(handle: "office", isSaved: true)
        #expect(server.stored == 5)
        #expect(store.displayCount(for: "office") == 5)
        #expect(server.requests.first?.method == .post)
        await store.didChange(handle: "office", isSaved: false)
        #expect(server.stored == 4)

        let failing = SaveCountStore(http: CounterServer(count: 9, fails: true), backendBaseURL: backend)
        await failing.refresh(handle: "office")
        #expect(failing.displayCount(for: "office") == nil)
    }
}
