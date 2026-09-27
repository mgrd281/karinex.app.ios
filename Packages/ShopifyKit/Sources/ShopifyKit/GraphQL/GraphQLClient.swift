import Core
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - GraphQLEndpoint

/// Where and how to send GraphQL requests.
///
/// The endpoint is API-agnostic: the Storefront API uses static headers (the optional public
/// access token), while the Customer Account API (Phase 2) supplies a fresh bearer token per
/// request through `authorization`.
public struct GraphQLEndpoint: Sendable {
    /// The GraphQL endpoint URL.
    public var url: URL
    /// Headers sent with every request, e.g. `X-Shopify-Storefront-Access-Token`.
    public var headers: [String: String]
    /// Timeout of a single HTTP attempt in seconds.
    public var timeout: TimeInterval
    /// Returns headers that must be computed per request, e.g. `Authorization: Bearer ...`.
    /// Called once per execution (not per retry attempt). Errors it throws are rethrown by
    /// `GraphQLClient.execute(_:directive:)` unchanged.
    public var authorization: @Sendable () async throws -> [String: String]

    /// Creates an endpoint.
    ///
    /// - Parameters:
    ///   - url: The GraphQL endpoint URL.
    ///   - headers: Headers sent with every request.
    ///   - timeout: Timeout of a single attempt in seconds, 30 by default.
    ///   - authorization: Computes per-request headers; returns none by default.
    public init(
        url: URL,
        headers: [String: String] = [:],
        timeout: TimeInterval = 30,
        authorization: @escaping @Sendable () async throws -> [String: String] = { [:] }
    ) {
        self.url = url
        self.headers = headers
        self.timeout = timeout
        self.authorization = authorization
    }
}

// MARK: - GraphQLClient

/// A small, typed GraphQL client on top of `HTTPClient`.
///
/// `execute(_:directive:)`:
/// 1. injects an optional directive (e.g. `@inContext`) into the operation's document,
/// 2. POSTs `{"query", "operationName", "variables"}` as JSON with `Content-Type` and `Accept`
///    set to `application/json`,
/// 3. retries transient failures (see below), honoring `Retry-After`,
/// 4. shares one in-flight request among concurrent callers of an identical query (same body
///    bytes); mutations are never shared,
/// 5. decodes the response and maps failures to `ShopifyError`,
/// 6. logs operation name, HTTP status, duration, attempts and query cost at debug level.
///    Variables and bodies are never logged.
///
/// Retry rules:
/// - Queries retry on `NetworkError.timeout` and `.transport`, on HTTP 429, 500, 502, 503 and
///   504, and on a GraphQL `THROTTLED` error. They also retry on a GraphQL
///   `INTERNAL_SERVER_ERROR`, which Shopify documents as its HTTP 200 form of a 500.
/// - Mutations retry only on HTTP 429 and GraphQL `THROTTLED`, where Shopify rejected the
///   request before executing it. A mutation that may have executed is never replayed.
/// - `NetworkError.offline` and `.cancelled` are never retried: offline fails fast so the UI
///   can show the offline banner right away.
public final class GraphQLClient: Sendable {
    /// The endpoint requests are sent to.
    public let endpoint: GraphQLEndpoint

    private let httpClient: any HTTPClient
    private let retryExecutor: RetryExecutor
    private let logger: KXLogger
    /// Shares in-flight queries, keyed by the exact request body. Internal for tests.
    let deduplicator = RequestDeduplicator<Data, Exchange>()

    /// Creates a client.
    ///
    /// - Parameters:
    ///   - endpoint: Where to send requests.
    ///   - httpClient: The transport, e.g. `URLSessionHTTPClient`.
    ///   - retryPolicy: Attempt and backoff bounds, `.default` (3 attempts) by default.
    ///   - sleeper: Waits between attempts; inject a recording sleeper in tests.
    ///   - logger: Receives one line per call, `.graphql` category by default.
    public init(
        endpoint: GraphQLEndpoint,
        httpClient: any HTTPClient,
        retryPolicy: RetryPolicy = .default,
        sleeper: any Sleeper = TaskSleeper(),
        logger: KXLogger = KXLogger(category: .graphql)
    ) {
        self.endpoint = endpoint
        self.httpClient = httpClient
        retryExecutor = RetryExecutor(policy: retryPolicy, sleeper: sleeper)
        self.logger = logger
    }

    // MARK: - Executing operations

    /// Executes `operation` and returns its decoded `data`.
    ///
    /// - Parameters:
    ///   - operation: The operation with its variables.
    ///   - directive: A directive inserted before the operation's selection set, e.g.
    ///     `StorefrontContext.directive`, or `nil` to send the document unchanged.
    /// - Throws: `ShopifyError` for every network, HTTP, GraphQL and decoding failure.
    ///   Errors thrown by `endpoint.authorization` are rethrown unchanged. A malformed document
    ///   throws `ContextInjectionError` and unencodable variables throw `EncodingError`; both are
    ///   programming errors covered by the unit tests of every operation.
    public func execute<O: GraphQLOperation>(_ operation: O, directive: String? = nil) async throws -> O.ResponseData {
        if Task.isCancelled {
            throw ShopifyError.network(.cancelled)
        }
        let document = try directive.map { try ContextInjector.inject($0, into: O.document) } ?? O.document
        let body = try Self.encodeBody(query: document, operationName: O.operationName, variables: operation.variables)

        let clock = ContinuousClock()
        let start = clock.now
        let exchange: Exchange
        do {
            switch O.kind {
            case .query:
                exchange = try await deduplicator.value(for: body) { [self] in
                    try await send(body: body, kind: .query)
                }
            case .mutation:
                exchange = try await send(body: body, kind: .mutation)
            }
        } catch let failure as AuthorizationFailure {
            logger.error("\(O.operationName) authorization failed duration=\(Self.milliseconds(clock.now - start))ms")
            throw failure.underlying
        } catch {
            let mapped = Self.shopifyError(forTransportError: error)
            log(mapped, operationName: O.operationName, status: nil, attempts: nil, duration: clock.now - start)
            throw mapped
        }

        let duration = clock.now - start
        do {
            let (data, extensions) = try Self.decode(O.ResponseData.self, from: exchange.response)
            logger.debug(
                "\(O.operationName) status=\(exchange.response.statusCode) duration=\(Self.milliseconds(duration))ms "
                    + "attempts=\(exchange.attempts)\(Self.costDescription(extensions?.cost))"
            )
            return data
        } catch let error as ShopifyError {
            log(
                error,
                operationName: O.operationName,
                status: exchange.response.statusCode,
                attempts: exchange.attempts,
                duration: duration
            )
            throw error
        }
    }

    // MARK: - Transport

    /// The final HTTP response of an execution and the number of attempts it took.
    struct Exchange: Sendable {
        let response: HTTPResponse
        let attempts: Int
    }

    /// Wraps an error thrown by `endpoint.authorization`, so it is rethrown unchanged.
    private struct AuthorizationFailure: Error {
        let underlying: any Error
    }

    /// Sends `body` with retries and returns the last response.
    ///
    /// Responses that are candidates for a retry are thrown as `RetryableResponse` inside the
    /// retry loop. When the retry decision or the attempt budget ends the loop, the last such
    /// response is returned for regular error mapping.
    private func send(body: Data, kind: GraphQLOperationKind) async throws -> Exchange {
        let dynamicHeaders: [String: String]
        do {
            dynamicHeaders = try await endpoint.authorization()
        } catch {
            throw AuthorizationFailure(underlying: error)
        }

        var request = HTTPRequest(method: .post, url: endpoint.url, headers: endpoint.headers, body: body, timeout: endpoint.timeout)
        for (name, value) in dynamicHeaders {
            request.setValue(value, forHeader: name)
        }
        request.setValue("application/json", forHeader: "Content-Type")
        request.setValue("application/json", forHeader: "Accept")

        let attempts = Locked(0)
        let httpClient = httpClient
        let finalRequest = request
        do {
            let response = try await retryExecutor.run {
                attempts.withLock { $0 += 1 }
                let response = try await httpClient.send(finalRequest)
                if let reason = RetryableResponse.Reason(response: response) {
                    throw RetryableResponse(response: response, reason: reason)
                }
                return response
            } decide: { error in
                Self.retryDecision(for: error, kind: kind)
            }
            return Exchange(response: response, attempts: attempts.value)
        } catch let retryable as RetryableResponse {
            return Exchange(response: retryable.response, attempts: attempts.value)
        }
    }

    // MARK: - Retry rules

    /// A response that may deserve a retry, thrown inside the retry loop.
    struct RetryableResponse: Error {
        enum Reason: Equatable {
            /// HTTP 429.
            case rateLimited(retryAfter: Duration?)
            /// HTTP 500, 502, 503 or 504.
            case serverError(retryAfter: Duration?)
            /// HTTP 2xx with a GraphQL `THROTTLED` error.
            case throttled

            init?(response: HTTPResponse) {
                switch response.statusCode {
                case 429:
                    self = .rateLimited(retryAfter: GraphQLClient.duration(seconds: response.retryAfter))
                case 500, 502, 503, 504:
                    self = .serverError(retryAfter: GraphQLClient.duration(seconds: response.retryAfter))
                case 200..<300:
                    switch GraphQLClient.retryableErrorCode(in: response.body) {
                    case GraphQLErrorDetail.Code.throttled?:
                        self = .throttled
                    case GraphQLErrorDetail.Code.internalServerError?:
                        self = .serverError(retryAfter: nil)
                    default:
                        return nil
                    }
                default:
                    return nil
                }
            }
        }

        let response: HTTPResponse
        let reason: Reason
    }

    /// Applies the retry rules to an error thrown by one attempt.
    static func retryDecision(for error: any Error, kind: GraphQLOperationKind) -> RetryDecision {
        switch error {
        case let retryable as RetryableResponse:
            switch retryable.reason {
            case let .rateLimited(retryAfter):
                return .retry(after: retryAfter)
            case .throttled:
                return .retry(after: nil)
            case let .serverError(retryAfter):
                return kind == .query ? .retry(after: retryAfter) : .doNotRetry
            }
        case let networkError as NetworkError:
            guard kind == .query else { return .doNotRetry }
            switch networkError {
            case .timeout, .transport:
                return .retry(after: nil)
            case .offline, .cancelled, .httpStatus, .invalidResponse:
                return .doNotRetry
            }
        default:
            return .doNotRetry
        }
    }

    /// The retry-relevant GraphQL error code of a successful HTTP response: `THROTTLED` (checked
    /// first) or `INTERNAL_SERVER_ERROR`, or `nil`. The body is only parsed when it contains one
    /// of the codes as text at all, so ordinary responses cost one byte scan.
    static func retryableErrorCode(in body: Data) -> String? {
        let candidates = [GraphQLErrorDetail.Code.throttled, GraphQLErrorDetail.Code.internalServerError]
        guard candidates.contains(where: { body.contains(Data($0.utf8)) }),
              let head = try? JSONDecoder().decode(GraphQLResponseHead.self, from: body)
        else { return nil }
        return candidates.first { code in head.errors.contains { $0.code == code } }
    }

    /// Converts a `Retry-After` value in seconds to a `Duration`.
    static func duration(seconds: TimeInterval?) -> Duration? {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return nil }
        return .milliseconds(Int64(min(seconds, 86_400) * 1000))
    }

    // MARK: - Encoding

    /// The JSON body of a GraphQL request.
    private struct RequestBody<Variables: Encodable>: Encodable {
        let query: String
        let operationName: String
        let variables: Variables
    }

    /// Encodes the request body deterministically (sorted keys), so identical requests have
    /// identical bytes and can be de-duplicated.
    static func encodeBody(query: String, operationName: String, variables: some Encodable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(RequestBody(query: query, operationName: operationName, variables: variables))
    }

    // MARK: - Decoding and error mapping

    /// Maps the final HTTP response to decoded data or a `ShopifyError`.
    static func decode<ResponseData: Decodable>(
        _ type: ResponseData.Type,
        from response: HTTPResponse
    ) throws -> (ResponseData, GraphQLResponseExtensions?) {
        let decoder = JSONDecoder()
        switch response.statusCode {
        case 200..<300:
            break
        case 401, 403:
            let head = try? decoder.decode(GraphQLResponseHead.self, from: response.body)
            throw ShopifyError.accessDenied(requiredAccess: head?.errors.lazy.compactMap(\.requiredAccess).first)
        case 429:
            throw ShopifyError.throttled
        default:
            throw ShopifyError.http(statusCode: response.statusCode)
        }

        let head: GraphQLResponseHead
        do {
            head = try decoder.decode(GraphQLResponseHead.self, from: response.body)
        } catch {
            throw ShopifyError.decoding("GraphQLResponse: \(codingPathDescription(of: error))")
        }

        if !head.errors.isEmpty {
            if let denied = head.errors.first(where: { $0.code == GraphQLErrorDetail.Code.accessDenied }) {
                throw ShopifyError.accessDenied(requiredAccess: denied.requiredAccess)
            }
            if head.errors.contains(where: { $0.code == GraphQLErrorDetail.Code.throttled }) {
                throw ShopifyError.throttled
            }
            throw ShopifyError.graphQL(head.errors)
        }

        let envelope: GraphQLDataEnvelope<ResponseData>
        do {
            envelope = try decoder.decode(GraphQLDataEnvelope<ResponseData>.self, from: response.body)
        } catch {
            throw ShopifyError.decoding("\(typeName(ResponseData.self)): \(codingPathDescription(of: error))")
        }
        guard let data = envelope.data else {
            throw ShopifyError.decoding("\(typeName(ResponseData.self)): data")
        }
        return (data, head.extensions)
    }

    /// Maps an error thrown by the transport or the retry loop to a `ShopifyError`.
    static func shopifyError(forTransportError error: any Error) -> ShopifyError {
        switch error {
        case let shopifyError as ShopifyError:
            shopifyError
        case let networkError as NetworkError:
            .network(networkError)
        case is CancellationError:
            .network(.cancelled)
        default:
            .network(.transport(code: URLError.Code.unknown.rawValue))
        }
    }

    /// The type name without the module prefix, e.g. `ProductByHandleQuery.ResponseData`.
    static func typeName(_ type: (some Any).Type) -> String {
        let name = String(reflecting: type)
        let prefix = "ShopifyKit."
        return name.hasPrefix(prefix) ? String(name.dropFirst(prefix.count)) : name
    }

    /// The coding path of a decoding error relative to `data`, e.g. `product.variants.nodes[0].price`.
    /// Never includes values from the payload.
    static func codingPathDescription(of error: any Error) -> String {
        guard let decodingError = error as? DecodingError else { return "<root>" }
        var path: [any CodingKey] = switch decodingError {
        case let .keyNotFound(key, context):
            context.codingPath + [key]
        case let .typeMismatch(_, context), let .valueNotFound(_, context), let .dataCorrupted(context):
            context.codingPath
        @unknown default:
            []
        }
        if let first = path.first, first.intValue == nil, first.stringValue == "data" {
            path.removeFirst()
        }
        guard !path.isEmpty else { return "<root>" }

        var description = ""
        for key in path {
            if let index = key.intValue {
                description += "[\(index)]"
            } else {
                description += description.isEmpty ? key.stringValue : ".\(key.stringValue)"
            }
        }
        return description
    }

    // MARK: - Logging

    private func log(_ error: ShopifyError, operationName: String, status: Int?, attempts: Int?, duration: Duration) {
        var message = "\(operationName) failed error=\(error.logDescription)"
        if let status {
            message += " status=\(status)"
        }
        message += " duration=\(Self.milliseconds(duration))ms"
        if let attempts {
            message += " attempts=\(attempts)"
        }
        if error.isConnectivityProblem || error.isCancellation {
            logger.notice(message)
        } else {
            logger.error(message)
        }
    }

    static func milliseconds(_ duration: Duration) -> Int64 {
        let components = duration.components
        return components.seconds * 1000 + components.attoseconds / 1_000_000_000_000_000
    }

    static func costDescription(_ cost: GraphQLQueryCost?) -> String {
        guard let cost else { return "" }
        var description = ""
        if let requested = cost.requestedQueryCost {
            description += " cost=\(requested)"
        }
        if let actual = cost.actualQueryCost {
            description += " actualCost=\(actual)"
        }
        return description
    }
}
