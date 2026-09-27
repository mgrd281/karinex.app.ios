import Core
import Foundation
@testable import ShopifyKit

// MARK: - Fixtures

/// Access to the recorded fixtures in `Fixtures/` (see `Fixtures/README.md`).
enum Fixture {
    static let localization = "localization_DE_DE.json"
    static let productDE = "product_office-2024-professional-plus-key_DE_DE.json"
    static let productCHFR = "product_office-2024-professional-plus-key_CH_FR.json"
    static let productNotFound = "product_not_found_DE_DE.json"
    static let collectionBestseller = "collection_bestseller_DE_DE.json"
    static let cartCreateInvalidMerchandise = "cart_create_invalid_merchandise_DE_DE.json"
    static let metafieldsAccessDenied = "product_metafields_access_denied_DE_DE.json"
    static let syntheticThrottled = "synthetic_throttled.json"
    static let manifest = "manifest.json"

    /// Every fixture file, including the manifest.
    static let all = [
        localization, productDE, productCHFR, productNotFound, collectionBestseller,
        cartCreateInvalidMerchandise, metafieldsAccessDenied, syntheticThrottled, manifest,
    ]

    struct Missing: Error, CustomStringConvertible {
        let name: String
        var description: String { "Fixture \(name) is missing from the test bundle." }
    }

    /// The raw bytes of fixture `name`.
    static func data(_ name: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures") else {
            throw Missing(name: name)
        }
        return try Data(contentsOf: url)
    }

    /// An HTTP 200 response whose body is fixture `name`.
    static func response(_ name: String) throws -> HTTPResponse {
        try HTTPResponse(statusCode: 200, headers: ["Content-Type": "application/json; charset=utf-8"], body: data(name))
    }
}

// MARK: - StubHTTPClient

/// An `HTTPClient` that records requests and answers with queued replies.
///
/// When a `Gate` is given, every `send` waits for it after recording the request, which lets
/// tests hold requests in flight (for de-duplication tests).
final class StubHTTPClient: HTTPClient {
    enum Reply: Sendable {
        case response(HTTPResponse)
        case failure(NetworkError)
    }

    struct Exhausted: Error {}

    private struct State {
        var requests: [HTTPRequest] = []
        var replies: [Reply]
    }

    private let state: Locked<State>
    private let gate: Gate?

    init(_ replies: [Reply] = [], gate: Gate? = nil) {
        state = Locked(State(replies: replies))
        self.gate = gate
    }

    /// Every request received so far.
    var requests: [HTTPRequest] {
        state.value.requests
    }

    /// Appends replies to the queue.
    func enqueue(_ replies: Reply...) {
        state.withLock { $0.replies.append(contentsOf: replies) }
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        state.withLock { $0.requests.append(request) }
        if let gate {
            await gate.wait()
        }
        let reply = state.withLock { state -> Reply? in
            state.replies.isEmpty ? nil : state.replies.removeFirst()
        }
        switch reply {
        case let .response(response)?:
            return response
        case let .failure(error)?:
            throw error
        case nil:
            throw Exhausted()
        }
    }
}

extension StubHTTPClient.Reply {
    /// An HTTP response with a JSON body.
    static func json(_ body: String, status: Int = 200, headers: [String: String] = [:]) -> Self {
        .response(HTTPResponse(statusCode: status, headers: headers, body: Data(body.utf8)))
    }

    /// An HTTP status without meaningful body.
    static func status(_ status: Int, headers: [String: String] = [:]) -> Self {
        .response(HTTPResponse(statusCode: status, headers: headers, body: Data("{}".utf8)))
    }

    /// HTTP 200 with fixture `name`.
    static func fixture(_ name: String) throws -> Self {
        try .response(Fixture.response(name))
    }
}

// MARK: - Concurrency helpers

/// A `Sleeper` that records durations and returns immediately.
final class RecordingSleeper: Sleeper {
    private let recorded = Locked<[Duration]>([])

    var durations: [Duration] {
        recorded.value
    }

    func sleep(for duration: Duration) async throws {
        recorded.withLock { $0.append(duration) }
        try Task.checkCancellation()
    }
}

/// A one-shot latch: tasks wait until it is opened.
actor Gate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func open() {
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending {
            waiter.resume()
        }
    }
}

/// Polls `condition` until it holds or `limit` yields have passed.
func eventually(limit: Int = 100_000, _ condition: () async -> Bool) async -> Bool {
    for _ in 0..<limit {
        if await condition() { return true }
        await Task.yield()
    }
    return await condition()
}

// MARK: - Request inspection

/// The decoded JSON body of a GraphQL request.
struct SentGraphQLBody: Decodable {
    let query: String
    let operationName: String
    let variables: [String: JSONAny]

    init(_ request: HTTPRequest) throws {
        self = try JSONDecoder().decode(SentGraphQLBody.self, from: request.body ?? Data())
    }
}

/// A minimal JSON value for inspecting request variables.
enum JSONAny: Decodable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONAny])
    case object([String: JSONAny])

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([JSONAny].self) {
            self = .array(array)
        } else {
            self = try .object(container.decode([String: JSONAny].self))
        }
    }
}

// MARK: - Factories

/// A Storefront client over `stub` with a recording sleeper, so retries never wait.
func makeStorefrontClient(
    _ stub: StubHTTPClient,
    token: String? = nil,
    retryPolicy: RetryPolicy = .default,
    sleeper: RecordingSleeper = RecordingSleeper(),
    logSink: RecordingLogSink = RecordingLogSink()
) -> StorefrontClient {
    StorefrontClient(
        configuration: StorefrontConfiguration(
            endpoint: AppConfiguration.preview.storefrontEndpoint,
            accessToken: token,
            apiVersion: AppConfiguration.preview.storefrontAPIVersion
        ),
        httpClient: stub,
        retryPolicy: retryPolicy,
        sleeper: sleeper,
        logger: KXLogger(category: .graphql, sink: logSink)
    )
}

/// A generic GraphQL client over `stub` with a recording sleeper.
func makeGraphQLClient(
    _ stub: StubHTTPClient,
    endpoint: GraphQLEndpoint = GraphQLEndpoint(url: AppConfiguration.preview.storefrontEndpoint),
    retryPolicy: RetryPolicy = .default,
    sleeper: RecordingSleeper = RecordingSleeper(),
    logSink: RecordingLogSink = RecordingLogSink()
) -> GraphQLClient {
    GraphQLClient(
        endpoint: endpoint,
        httpClient: stub,
        retryPolicy: retryPolicy,
        sleeper: sleeper,
        logger: KXLogger(category: .graphql, sink: logSink)
    )
}

/// The Germany context with the consent the app sends before the user decided.
let germanyContext = StorefrontContext(country: .de, language: .de, visitorConsent: VisitorConsent(privacyConsent: .undecided))
/// Switzerland in French.
let switzerlandFrenchContext = StorefrontContext(country: .ch, language: .fr, visitorConsent: VisitorConsent(privacyConsent: .undecided))

/// Exact decimal from a string literal.
func decimal(_ string: String) -> Decimal {
    Decimal(string: string, locale: Locale(identifier: "en_US_POSIX")) ?? .nan
}
