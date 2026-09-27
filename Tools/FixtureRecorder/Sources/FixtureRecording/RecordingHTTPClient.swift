import Core
import Foundation

/// An `HTTPClient` decorator that forwards every request to a base client and keeps the raw
/// responses, so the recorder can store the exact bytes Shopify returned while the real
/// `StorefrontClient` still decodes and validates them.
public final class RecordingHTTPClient: HTTPClient {
    /// One request and the response it received.
    public struct Exchange: Sendable {
        /// The request as sent (including headers).
        public let request: HTTPRequest
        /// The raw response.
        public let response: HTTPResponse
    }

    private let base: any HTTPClient
    private let storage = Locked<[Exchange]>([])

    /// Wraps `base`.
    public init(base: any HTTPClient) {
        self.base = base
    }

    /// Sends `request` through the base client and records the response.
    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let response = try await base.send(request)
        storage.withLock { $0.append(Exchange(request: request, response: response)) }
        return response
    }

    /// Every recorded exchange in order.
    public var exchanges: [Exchange] {
        storage.value
    }

    /// Returns the recorded exchanges and forgets them.
    @discardableResult
    public func takeExchanges() -> [Exchange] {
        storage.replace(with: [])
    }
}
