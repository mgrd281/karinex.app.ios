import Core
import Foundation
import ShopifyKit

// MARK: - UserFacingError

/// A failure translated for the customer: a kind that decides title, message, symbol and
/// whether "Erneut versuchen" makes sense.
///
/// Build it from any error thrown by a repository with ``init(_:)``. Cancellations (the view
/// went away) produce `nil`, because they are not failures the customer should see:
///
/// ```swift
/// do {
///     state = .loaded(try await repository.product(handle: handle))
/// } catch {
///     if let failure = UserFacingError(error) { state = .failed(failure) }
/// }
/// ```
///
/// The texts never contain technical details. Only ``Kind/rejected(messages:)`` shows text
/// from Shopify: the localized `userErrors` messages of a cart mutation, which are written for
/// customers.
public struct UserFacingError: Error, Sendable, Hashable {
    /// What went wrong, from the customer's point of view.
    public enum Kind: Sendable, Hashable {
        /// The device has no usable connection.
        case offline
        /// The store did not answer in time.
        case timeout
        /// The store asked the app to slow down (HTTP 429 or `THROTTLED`).
        case throttled
        /// The store failed or could not be reached (5xx, internal errors, transport errors).
        case server
        /// Shopify refused the action and explained why, e.g. a cart `userErrors` message.
        case rejected(messages: [String])
        /// The requested content does not exist (any more).
        case notFound
        /// Anything else, e.g. a decoding problem or missing access.
        case unknown
    }

    /// What went wrong.
    public let kind: Kind

    /// Creates an error of `kind`.
    public init(kind: Kind) {
        self.kind = kind
    }

    /// Maps `error` to a customer-facing error, or returns `nil` for a cancellation.
    ///
    /// Understands `ShopifyError`, `NetworkError`, `URLError`, `CancellationError` and
    /// `UserFacingError` itself; everything else becomes ``Kind/unknown``.
    public init?(_ error: any Error) {
        guard let kind = Self.kind(for: error) else { return nil }
        self.init(kind: kind)
    }

    /// Whether `error` only reports a cancellation (a task or request that was abandoned).
    public static func isCancellation(_ error: any Error) -> Bool {
        kind(for: error) == nil
    }

    // MARK: Presentation

    /// Whether repeating the same action may succeed. `false` for refusals and missing content.
    public var isRetryable: Bool {
        switch kind {
        case .offline, .timeout, .throttled, .server, .unknown:
            true
        case .rejected, .notFound:
            false
        }
    }

    /// The SF Symbol of the error state.
    public var systemImage: String {
        switch kind {
        case .offline:
            "wifi.slash"
        case .timeout:
            "clock.arrow.circlepath"
        case .throttled, .server:
            "exclamationmark.icloud"
        case .rejected:
            "exclamationmark.circle"
        case .notFound:
            "magnifyingglass"
        case .unknown:
            "exclamationmark.triangle"
        }
    }

    /// The localized, short title.
    public var title: String {
        switch kind {
        case .offline:
            String(localized: "commerce.error.offline.title", bundle: .module)
        case .timeout:
            String(localized: "commerce.error.timeout.title", bundle: .module)
        case .throttled:
            String(localized: "commerce.error.throttled.title", bundle: .module)
        case .server:
            String(localized: "commerce.error.server.title", bundle: .module)
        case .rejected:
            String(localized: "commerce.error.rejected.title", bundle: .module)
        case .notFound:
            String(localized: "commerce.error.not_found.title", bundle: .module)
        case .unknown:
            String(localized: "commerce.error.unknown.title", bundle: .module)
        }
    }

    /// The localized explanation. For ``Kind/rejected(messages:)`` these are Shopify's own
    /// messages, one per line.
    public var message: String {
        switch kind {
        case .offline:
            return String(localized: "commerce.error.offline.message", bundle: .module)
        case .timeout:
            return String(localized: "commerce.error.timeout.message", bundle: .module)
        case .throttled:
            return String(localized: "commerce.error.throttled.message", bundle: .module)
        case .server:
            return String(localized: "commerce.error.server.message", bundle: .module)
        case let .rejected(messages):
            let joined = messages
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            return joined.isEmpty ? String(localized: "commerce.error.unknown.message", bundle: .module) : joined
        case .notFound:
            return String(localized: "commerce.error.not_found.message", bundle: .module)
        case .unknown:
            return String(localized: "commerce.error.unknown.message", bundle: .module)
        }
    }

    /// The localized label of the retry action ("Erneut versuchen").
    public static var retryTitle: String {
        String(localized: "commerce.error.retry", bundle: .module)
    }

    /// The name of the kind for logs, without Shopify's messages.
    var logName: String {
        switch kind {
        case .offline: "offline"
        case .timeout: "timeout"
        case .throttled: "throttled"
        case .server: "server"
        case .rejected: "rejected"
        case .notFound: "notFound"
        case .unknown: "unknown"
        }
    }

    // MARK: Mapping

    /// The kind for `error`, or `nil` for a cancellation.
    static func kind(for error: any Error) -> Kind? {
        switch error {
        case let error as UserFacingError:
            error.kind
        case let error as ShopifyError:
            kind(for: error)
        case let error as NetworkError:
            kind(for: error)
        case let error as URLError:
            kind(for: NetworkError(urlError: error))
        case is CancellationError:
            nil
        default:
            .unknown
        }
    }

    private static func kind(for error: ShopifyError) -> Kind? {
        switch error {
        case let .network(networkError):
            kind(for: networkError)
        case .throttled:
            .throttled
        case let .http(statusCode):
            if statusCode == 408 {
                .timeout
            } else if statusCode == 429 {
                .throttled
            } else if statusCode >= 500 {
                .server
            } else {
                .unknown
            }
        case let .graphQL(errors):
            errors.contains { $0.code == GraphQLErrorDetail.Code.internalServerError } ? .server : .unknown
        case let .userErrors(errors):
            .rejected(messages: errors.map(\.message))
        case .notFound:
            .notFound
        case .accessDenied, .decoding:
            .unknown
        }
    }

    private static func kind(for error: NetworkError) -> Kind? {
        switch error {
        case .offline:
            .offline
        case .timeout:
            .timeout
        case .cancelled:
            nil
        case let .httpStatus(code, _):
            code == 429 ? .throttled : (code >= 500 ? .server : .unknown)
        case .transport, .invalidResponse:
            .server
        }
    }
}

// MARK: - Identifiable

extension UserFacingError: Identifiable {
    /// A stable identity for alerts and banners: equal errors share it.
    public var id: Int {
        hashValue
    }
}
