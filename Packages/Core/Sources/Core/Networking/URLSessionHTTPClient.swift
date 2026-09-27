import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - URLSessionHTTPClient

/// `HTTPClient` backed by `URLSession`.
///
/// Non-2xx responses are returned, not thrown: interpreting status codes is the job of the
/// API layer (for example the GraphQL client, which maps 401, 429 and 5xx differently).
/// Failures without a response are thrown as `NetworkError`.
public final class URLSessionHTTPClient: HTTPClient {
    private let session: URLSession

    /// Creates a client that sends requests through `session`.
    public init(session: URLSession) {
        self.session = session
    }

    /// Creates a client with its own `URLSession` built from `configuration`.
    ///
    /// - Parameter configuration: The session configuration, `.kxDefault` by default.
    public convenience init(configuration: URLSessionConfiguration = .kxDefault) {
        self.init(session: URLSession(configuration: configuration))
    }

    /// Sends `request` and returns the response, whatever its status code.
    ///
    /// - Throws: `NetworkError.cancelled` if the calling task is cancelled before or during the
    ///   request, `NetworkError.invalidResponse` for non-HTTP responses, and the mapping of
    ///   `NetworkError(urlError:)` for URL loading failures.
    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        if Task.isCancelled {
            throw NetworkError.cancelled
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: Self.urlRequest(for: request))
        } catch {
            throw Self.networkError(for: error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }
        return HTTPResponse(
            statusCode: httpResponse.statusCode,
            headers: Self.headers(of: httpResponse),
            body: data
        )
    }

    // MARK: - Mapping

    static func urlRequest(for request: HTTPRequest) -> URLRequest {
        var urlRequest = URLRequest(url: request.url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: request.timeout)
        urlRequest.httpMethod = request.method.rawValue
        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }
        urlRequest.httpBody = request.body
        return urlRequest
    }

    static func headers(of response: HTTPURLResponse) -> [String: String] {
        var headers: [String: String] = [:]
        for (key, value) in response.allHeaderFields {
            guard let name = key as? String else { continue }
            if let stringValue = value as? String {
                headers[name] = stringValue
            } else {
                headers[name] = String(describing: value)
            }
        }
        return headers
    }

    static func networkError(for error: any Error) -> NetworkError {
        switch error {
        case let networkError as NetworkError:
            return networkError
        case is CancellationError:
            return .cancelled
        case let urlError as URLError:
            return NetworkError(urlError: urlError)
        default:
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain {
                return NetworkError(urlErrorCode: nsError.code)
            }
            return Task.isCancelled ? .cancelled : .transport(code: URLError.Code.unknown.rawValue)
        }
    }
}

// MARK: - URLSessionConfiguration

extension URLSessionConfiguration {
    /// Maximum size of the in-memory HTTP cache of `kxDefault` (20 MB).
    public static let kxMemoryCacheCapacity = 20 * 1024 * 1024
    /// Maximum size of the on-disk HTTP cache of `kxDefault` (100 MB).
    public static let kxDiskCacheCapacity = 100 * 1024 * 1024

    /// The app's session configuration: a persistent (non-ephemeral) session that fails fast
    /// when offline (`waitsForConnectivity = false`), a 30 second request timeout, a dedicated
    /// `URLCache` of 20 MB in memory and 100 MB on disk, and no additional headers.
    ///
    /// Each access creates a new configuration with a new cache instance that uses the same
    /// directory, so create the session once (the app container does) and share it.
    public static var kxDefault: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.requestCachePolicy = .useProtocolCachePolicy
        configuration.httpAdditionalHeaders = nil
        #if canImport(FoundationNetworking)
        // swift-corelibs-foundation never waits for connectivity and exposes the property as
        // read-only; its URLCache still uses the path-based initializer.
        configuration.urlCache = URLCache(
            memoryCapacity: kxMemoryCacheCapacity,
            diskCapacity: kxDiskCacheCapacity,
            diskPath: "de.karinex.urlcache"
        )
        #else
        configuration.waitsForConnectivity = false
        configuration.urlCache = URLCache(
            memoryCapacity: kxMemoryCacheCapacity,
            diskCapacity: kxDiskCacheCapacity,
            directory: kxCacheDirectory
        )
        #endif
        return configuration
    }

    #if !canImport(FoundationNetworking)
    /// `Library/Caches/de.karinex.urlcache`, separate from `URLCache.shared`'s store.
    private static var kxCacheDirectory: URL? {
        FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first?
            .appending(path: "de.karinex.urlcache", directoryHint: .isDirectory)
    }
    #endif
}
