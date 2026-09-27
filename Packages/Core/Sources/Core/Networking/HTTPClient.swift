import Foundation

// MARK: - HTTPMethod

/// HTTP request methods used by the app.
public enum HTTPMethod: String, Sendable, CaseIterable {
    /// `GET`
    case get = "GET"
    /// `POST`
    case post = "POST"
    /// `PUT`
    case put = "PUT"
    /// `PATCH`
    case patch = "PATCH"
    /// `DELETE`
    case delete = "DELETE"
}

// MARK: - HTTPRequest

/// A transport-independent HTTP request.
public struct HTTPRequest: Sendable, Hashable {
    /// The request method.
    public var method: HTTPMethod
    /// The absolute request URL.
    public var url: URL
    /// Request header fields. Look values up with `value(forHeader:)`, which ignores case.
    public var headers: [String: String]
    /// The request body, if any.
    public var body: Data?
    /// Timeout of the request in seconds.
    public var timeout: TimeInterval

    /// Creates a request.
    ///
    /// - Parameters:
    ///   - method: The request method, `GET` by default.
    ///   - url: The absolute request URL.
    ///   - headers: Header fields.
    ///   - body: The body, if any.
    ///   - timeout: Timeout in seconds, 30 by default.
    public init(
        method: HTTPMethod = .get,
        url: URL,
        headers: [String: String] = [:],
        body: Data? = nil,
        timeout: TimeInterval = 30
    ) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
        self.timeout = timeout
    }

    /// Returns the value of the header `name`, compared case-insensitively.
    public func value(forHeader name: String) -> String? {
        HTTPHeaderLookup.value(for: name, in: headers)
    }

    /// Sets (or, with `nil`, removes) the header `name`, replacing any existing field whose
    /// name differs only in case.
    public mutating func setValue(_ value: String?, forHeader name: String) {
        let existingKeys = headers.keys.filter { $0.caseInsensitiveCompare(name) == .orderedSame }
        for key in existingKeys {
            headers.removeValue(forKey: key)
        }
        if let value {
            headers[name] = value
        }
    }
}

// MARK: - HTTPResponse

/// A transport-independent HTTP response.
public struct HTTPResponse: Sendable, Equatable {
    /// The HTTP status code.
    public var statusCode: Int
    /// Response header fields. Look values up with `value(forHeader:)`, which ignores case.
    public var headers: [String: String]
    /// The response body (empty when there is none).
    public var body: Data

    /// Creates a response.
    public init(statusCode: Int, headers: [String: String] = [:], body: Data = Data()) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
    }

    /// Whether the status code is in the 2xx range.
    public var isSuccess: Bool {
        (200..<300).contains(statusCode)
    }

    /// Returns the value of the header `name`, compared case-insensitively.
    public func value(forHeader name: String) -> String? {
        HTTPHeaderLookup.value(for: name, in: headers)
    }

    /// The delay requested by a `Retry-After` header, in seconds from now.
    ///
    /// Both forms of RFC 9110 are understood: delay seconds (`Retry-After: 120`) and an
    /// HTTP-date (`Retry-After: Wed, 21 Oct 2026 07:28:00 GMT`). Dates in the past yield `0`.
    /// Returns `nil` when the header is absent or malformed.
    public var retryAfter: TimeInterval? {
        retryAfter(relativeTo: Date())
    }

    /// The delay requested by a `Retry-After` header, measured from `now`. See `retryAfter`.
    public func retryAfter(relativeTo now: Date) -> TimeInterval? {
        guard let rawValue = value(forHeader: "Retry-After") else { return nil }
        return RetryAfterParser.delay(from: rawValue, now: now)
    }
}

// MARK: - HTTPClient

/// Sends HTTP requests. Implementations return every response, including non-2xx ones, and
/// throw `NetworkError` only when no HTTP response was received.
public protocol HTTPClient: Sendable {
    /// Sends `request` and returns the response.
    ///
    /// - Throws: `NetworkError` for transport failures (offline, timeout, cancellation, TLS).
    func send(_ request: HTTPRequest) async throws -> HTTPResponse
}

// MARK: - Helpers

enum HTTPHeaderLookup {
    static func value(for name: String, in headers: [String: String]) -> String? {
        if let exact = headers[name] {
            return exact
        }
        return headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

enum RetryAfterParser {
    /// Parses a `Retry-After` value into a non-negative delay in seconds, or `nil`.
    static func delay(from rawValue: String, now: Date) -> TimeInterval? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        if let seconds = TimeInterval(value) {
            return seconds.isFinite && seconds >= 0 ? seconds : nil
        }
        guard let date = httpDate(from: value) else { return nil }
        return max(date.timeIntervalSince(now), 0)
    }

    /// Parses the three HTTP-date formats of RFC 9110 section 5.6.7.
    static func httpDate(from value: String) -> Date? {
        // Collapse the double space that asctime uses before single-digit days.
        let normalized = value.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        let formats = [
            "EEE, dd MMM yyyy HH:mm:ss zzz", // IMF-fixdate: Sun, 06 Nov 1994 08:49:37 GMT
            "EEEE, dd-MMM-yy HH:mm:ss zzz", // RFC 850: Sunday, 06-Nov-94 08:49:37 GMT
            "EEE MMM d HH:mm:ss yyyy", // asctime: Sun Nov 6 08:49:37 1994
        ]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.isLenient = false
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: normalized) {
                return date
            }
        }
        return nil
    }
}
