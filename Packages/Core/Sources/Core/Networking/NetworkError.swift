import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Transport-level failures, independent of any API on top of HTTP.
public enum NetworkError: Error, Sendable, Equatable {
    /// The device has no usable connection (or the host could not be reached at all).
    /// Never retried automatically: the UI shows the offline banner instead.
    case offline
    /// The request timed out.
    case timeout
    /// The request was cancelled, usually because the calling task was cancelled.
    case cancelled
    /// Another transport failure, identified by its `URLError.Code` raw value (for example a
    /// TLS error or a malformed response).
    case transport(code: Int)
    /// The server answered with a status code the caller treats as a failure. `retryAfter` is
    /// the parsed `Retry-After` header in seconds, if present. `HTTPClient` itself never throws
    /// this; higher layers use it to feed retry decisions.
    case httpStatus(code: Int, retryAfter: TimeInterval?)
    /// The response was not an HTTP response.
    case invalidResponse

    /// Maps a `URLError` to a `NetworkError`.
    ///
    /// Connectivity codes (`notConnectedToInternet`, `networkConnectionLost`, `dataNotAllowed`,
    /// `internationalRoamingOff`, `cannotFindHost`, `cannotConnectToHost`, `dnsLookupFailed`)
    /// become `.offline`: on a mobile device they almost always mean the network is gone or
    /// switching, and the store host itself is known to exist. `timedOut` becomes `.timeout`,
    /// `cancelled` becomes `.cancelled`, everything else `.transport(code:)`.
    public init(urlError: URLError) {
        self.init(urlErrorCode: urlError.code.rawValue)
    }

    /// Maps a raw `URLError.Code` value (the `code` of an `NSError` in `NSURLErrorDomain`) the
    /// same way as `init(urlError:)`.
    public init(urlErrorCode code: Int) {
        switch code {
        case URLError.Code.notConnectedToInternet.rawValue,
             URLError.Code.networkConnectionLost.rawValue,
             URLError.Code.dataNotAllowed.rawValue,
             URLError.Code.internationalRoamingOff.rawValue,
             URLError.Code.cannotFindHost.rawValue,
             URLError.Code.cannotConnectToHost.rawValue,
             URLError.Code.dnsLookupFailed.rawValue:
            self = .offline
        case URLError.Code.timedOut.rawValue:
            self = .timeout
        case URLError.Code.cancelled.rawValue:
            self = .cancelled
        default:
            self = .transport(code: code)
        }
    }

    /// Whether the failure is caused by missing or poor connectivity (`offline` or `timeout`),
    /// as opposed to a server, protocol or programming problem.
    public var isConnectivityProblem: Bool {
        switch self {
        case .offline, .timeout:
            true
        case .cancelled, .transport, .httpStatus, .invalidResponse:
            false
        }
    }
}
