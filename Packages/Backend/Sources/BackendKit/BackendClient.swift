import Core
import Foundation

// MARK: - BackendError

/// Why a backend call failed. Messages for the UI are chosen by the features; the backend's
/// own `message` is only logged as its `code`.
public enum BackendError: Error, Sendable, Equatable {
    /// No backend host is configured in this build.
    case notConfigured
    /// The customer is not signed in, or the backend rejected the token (401).
    case unauthorized
    /// The resource belongs to someone else (403).
    case forbidden
    /// The resource does not exist (404).
    case notFound
    /// Too many requests (429); retry after the given seconds, if known.
    case rateLimited(retryAfter: TimeInterval?)
    /// Another HTTP error with the contract's `code` and `requestId`.
    case server(statusCode: Int, code: String?, requestID: String?)
    /// The request did not reach the backend.
    case network(NetworkError)
    /// The response did not match the contract.
    case decoding

    /// Whether trying again later can help.
    public var isTransient: Bool {
        switch self {
        case .rateLimited, .network: true
        case let .server(statusCode, _, _): statusCode >= 500
        case .notConfigured, .unauthorized, .forbidden, .notFound, .decoding: false
        }
    }

    /// A log-safe description.
    public var logDescription: String {
        switch self {
        case .notConfigured: "notConfigured"
        case .unauthorized: "unauthorized"
        case .forbidden: "forbidden"
        case .notFound: "notFound"
        case .rateLimited: "rateLimited"
        case let .server(statusCode, code, requestID): "server(\(statusCode),\(code ?? "-"),\(requestID ?? "-"))"
        case let .network(error): "network(\(error))"
        case .decoding: "decoding"
        }
    }
}

// MARK: - BackendClient

/// The KARINEX backend (BFF) as the app uses it (PROMPT.md 12, docs/BFF_CONTRACT.md).
public protocol BackendClient: Sendable {
    /// `GET /v1/app/config`. Public, cached with ETag.
    func appConfig() async throws -> RemoteAppConfig
    /// `GET /v1/app/orders`.
    func orders() async throws -> [BackendOrderStatus]
    /// `GET /v1/app/orders/{orderId}/licenses`.
    func licenses(orderID: String) async throws -> LicenseDelivery
    /// `GET /v1/app/orders/{orderId}/invoice`.
    func invoice(orderID: String) async throws -> InvoiceLink
    /// `POST /v1/app/account/delete`. Returns the backend's request ID.
    func requestAccountDeletion() async throws -> String?
    /// `GET /v1/app/loyalty`: the customer's level, points and history.
    func loyalty() async throws -> LoyaltyStatus
    /// `POST /v1/app/loyalty/redeem`: exchanges reward points for a one-time discount code. The
    /// same `idempotencyKey` always returns the same code, so a double tap never spends twice.
    /// Throws ``LoyaltyRedeemError`` when the backend refuses (the points are not spent).
    func redeemLoyalty(points: Int, idempotencyKey: String) async throws -> LoyaltyRedeemCode
    /// `POST /v1/app/loyalty/referral`: the customer's referral code, created on the first call; the
    /// same customer always gets the same code. Throws ``LoyaltyReferralError`` when refused.
    func loyaltyReferral() async throws -> LoyaltyReferralCode
    /// `GET /v1/app/wallet-card`: the customer's KARINEX card for Apple Wallet as `.pkpass` data.
    /// `.notFound` when the account has no card or Apple Wallet is not set up on the backend.
    func walletPass() async throws -> Data
    /// `POST /v1/app/devices`.
    func registerDevice(_ registration: DeviceRegistration) async throws
    /// `DELETE /v1/app/devices/{token}`.
    func unregisterDevice(apnsToken: String) async throws
    /// `GET /v1/app/notifications`: the messages of "Neuigkeiten" for this installation, and for
    /// the signed-in customer when there is a session. Newest first.
    func notifications() async throws -> [InboxMessage]
    /// `POST /v1/app/restock`: "Benachrichtigen, wenn verfügbar" for a sold-out variant.
    func watchRestock(_ watch: RestockWatch) async throws
    /// `DELETE /v1/app/restock?variantId=`: cancels a restock watch.
    func unwatchRestock(variantID: String) async throws
}

extension BackendClient {
    public func notifications() async throws -> [InboxMessage] {
        throw BackendError.notConfigured
    }

    public func watchRestock(_: RestockWatch) async throws {
        throw BackendError.notConfigured
    }

    public func unwatchRestock(variantID _: String) async throws {
        throw BackendError.notConfigured
    }
}

// MARK: - HTTPBackendClient

/// `BackendClient` over HTTPS.
///
/// - Customer endpoints send `Authorization: Bearer <Customer Account API access token>`;
///   the backend validates the token with Shopify and checks order ownership itself.
/// - Every request carries `X-KX-App-Version` and `Accept-Language`.
/// - GET requests are retried on timeouts, transport errors, 429 and 5xx (see `RetryPolicy`);
///   POST and DELETE are never repeated.
/// - Bodies are never logged; license keys only exist in memory and in the Keychain cache.
public final class HTTPBackendClient: BackendClient {
    private let baseURL: URL
    private let httpClient: any HTTPClient
    private let accessToken: @Sendable () async throws -> String
    private let appVersion: String
    private let languageCode: @Sendable () -> String
    private let installationID: String?
    private let retryExecutor: RetryExecutor
    private let logger: KXLogger
    private let configCache = Locked<(etag: String, config: RemoteAppConfig)?>(nil)

    /// Creates the client.
    ///
    /// - Parameters:
    ///   - baseURL: `AppConfiguration.backendBaseURL`.
    ///   - httpClient: The transport.
    ///   - accessToken: The customer's current access token (`CustomerAccountSession.accessToken()`).
    ///   - appVersion: The marketing version, e.g. `0.2.0`.
    ///   - languageCode: The UI language for `Accept-Language`, e.g. `de`.
    ///   - installationID: The random ID of this app installation (`X-KX-Install`) for the
    ///     device endpoints (notifications, restock, push registration); `nil` disables them.
    ///   - retryPolicy: Bounds for GET retries.
    ///   - sleeper: Waits between retries.
    ///   - logger: Logs outcomes, never bodies.
    public init(
        baseURL: URL,
        httpClient: any HTTPClient,
        accessToken: @escaping @Sendable () async throws -> String,
        appVersion: String,
        languageCode: @escaping @Sendable () -> String,
        installationID: String? = nil,
        retryPolicy: RetryPolicy = .default,
        sleeper: any Sleeper = TaskSleeper(),
        logger: KXLogger = KXLogger(category: .networking)
    ) {
        self.baseURL = baseURL
        self.httpClient = httpClient
        self.accessToken = accessToken
        self.appVersion = appVersion
        self.languageCode = languageCode
        self.installationID = installationID
        retryExecutor = RetryExecutor(policy: retryPolicy, sleeper: sleeper)
        self.logger = logger
    }

    // MARK: Endpoints

    public func appConfig() async throws -> RemoteAppConfig {
        var headers: [String: String] = [:]
        let cached = configCache.value
        if let cached {
            headers["If-None-Match"] = cached.etag
        }
        let response = try await send(.get, path: "/v1/app/config", authenticated: false, headers: headers, acceptedStatus: [200, 304])
        if response.statusCode == 304, let cached {
            return cached.config
        }
        let config: RemoteAppConfig = try decode(response)
        if let etag = response.value(forHeader: "ETag") {
            configCache.withLock { $0 = (etag, config) }
        }
        return config
    }

    public func orders() async throws -> [BackendOrderStatus] {
        struct Envelope: Decodable {
            let orders: [BackendOrderStatus]
        }
        let response = try await send(.get, path: "/v1/app/orders", authenticated: true)
        let envelope: Envelope = try decode(response)
        return envelope.orders
    }

    public func licenses(orderID: String) async throws -> LicenseDelivery {
        struct Envelope: Decodable {
            let licenses: [LicenseKey]
        }
        let path = try "/v1/app/orders/\(Self.pathSegment(orderID))/licenses"
        let response = try await send(.get, path: path, authenticated: true, acceptedStatus: [200, 202])
        if response.statusCode == 202 {
            return .pending
        }
        let envelope: Envelope = try decode(response)
        return .delivered(envelope.licenses.map { $0.assigned(to: orderID) })
    }

    public func invoice(orderID: String) async throws -> InvoiceLink {
        let path = try "/v1/app/orders/\(Self.pathSegment(orderID))/invoice"
        return try await decode(send(.get, path: path, authenticated: true))
    }

    public func requestAccountDeletion() async throws -> String? {
        struct Envelope: Decodable {
            let requestId: String?
        }
        let body = Data(#"{"confirm":true}"#.utf8)
        let response = try await send(.post, path: "/v1/app/account/delete", authenticated: true, body: body, acceptedStatus: [200, 202])
        return (try? JSONDecoder().decode(Envelope.self, from: response.body))?.requestId
    }

    public func loyalty() async throws -> LoyaltyStatus {
        try await decode(send(.get, path: "/v1/app/loyalty", authenticated: true))
    }

    public func redeemLoyalty(points: Int, idempotencyKey: String) async throws -> LoyaltyRedeemCode {
        struct Request: Encodable {
            let points: Int
            let idempotencyKey: String
        }
        struct Rejection: Decodable {
            let reason: String?
        }
        let body: Data
        do {
            body = try JSONEncoder().encode(Request(points: points, idempotencyKey: idempotencyKey))
        } catch {
            throw BackendError.decoding
        }
        let response = try await send(.post, path: "/v1/app/loyalty/redeem", authenticated: true, body: body, acceptedStatus: [200, 409])
        if response.statusCode == 409 {
            throw LoyaltyRedeemError(reason: (try? JSONDecoder().decode(Rejection.self, from: response.body))?.reason)
        }
        return try decode(response)
    }

    public func loyaltyReferral() async throws -> LoyaltyReferralCode {
        struct Rejection: Decodable {
            let reason: String?
        }
        let response = try await send(.post, path: "/v1/app/loyalty/referral", authenticated: true, acceptedStatus: [200, 409])
        if response.statusCode == 409 {
            let reason = (try? JSONDecoder().decode(Rejection.self, from: response.body))?.reason
            throw reason == "in_progress" ? LoyaltyReferralError.inProgress : LoyaltyReferralError.disabled
        }
        return try decode(response)
    }

    public func walletPass() async throws -> Data {
        let response = try await send(
            .get,
            path: "/v1/app/wallet-card",
            authenticated: true,
            headers: ["Accept": "application/vnd.apple.pkpass"]
        )
        // A pass is a ZIP archive; anything else is not what the contract promises.
        guard response.body.starts(with: [0x50, 0x4B, 0x03, 0x04]) else {
            logger.error("Backend wallet card is not a pass archive")
            throw BackendError.decoding
        }
        return response.body
    }

    public func registerDevice(_ registration: DeviceRegistration) async throws {
        let body: Data
        do {
            body = try JSONEncoder().encode(registration)
        } catch {
            throw BackendError.decoding
        }
        _ = try await send(.post, path: "/v1/app/devices", authenticated: false, device: true, body: body, acceptedStatus: [200, 201, 204])
    }

    public func unregisterDevice(apnsToken: String) async throws {
        let path = try "/v1/app/devices/\(Self.pathSegment(apnsToken))"
        _ = try await send(.delete, path: path, authenticated: false, device: true, acceptedStatus: [200, 204, 404])
    }

    public func notifications() async throws -> [InboxMessage] {
        let page: InboxPage = try decode(send(.get, path: "/v1/app/notifications", authenticated: false, device: true))
        return page.items
    }

    public func watchRestock(_ watch: RestockWatch) async throws {
        let body: Data
        do {
            body = try JSONEncoder().encode(watch)
        } catch {
            throw BackendError.decoding
        }
        _ = try await send(.post, path: "/v1/app/restock", authenticated: false, device: true, body: body, acceptedStatus: [200, 204])
    }

    public func unwatchRestock(variantID: String) async throws {
        let number = String(variantID.split(separator: "/").last ?? "")
        let path = try "/v1/app/restock?variantId=\(Self.pathSegment(number))"
        _ = try await send(.delete, path: path, authenticated: false, device: true, acceptedStatus: [200, 204, 404])
    }

    // MARK: Transport

    private func send(
        _ method: HTTPMethod,
        path: String,
        authenticated: Bool,
        device: Bool = false,
        headers extraHeaders: [String: String] = [:],
        body: Data? = nil,
        acceptedStatus: Set<Int> = [200]
    ) async throws -> HTTPResponse {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else { throw BackendError.notFound }
        var headers = extraHeaders
        headers["Accept"] = extraHeaders["Accept"] ?? "application/json"
        headers["X-KX-App-Version"] = appVersion
        headers["Accept-Language"] = languageCode()
        if body != nil {
            headers["Content-Type"] = "application/json"
        }
        if authenticated {
            do {
                headers["Authorization"] = try await "Bearer \(accessToken())"
            } catch {
                throw BackendError.unauthorized
            }
        } else if device {
            // Device endpoints work for guests; a session only adds the customer's own messages.
            guard let installationID else { throw BackendError.notConfigured }
            headers["X-KX-Install"] = installationID
            if let token = try? await accessToken() {
                headers["Authorization"] = "Bearer \(token)"
            }
        }
        let request = HTTPRequest(method: method, url: url, headers: headers, body: body, timeout: 20)
        let clock = ContinuousClock()
        let start = clock.now
        let response: HTTPResponse
        do {
            response = try await perform(request, retrying: method == .get)
        } catch let error as NetworkError {
            logger.notice("Backend \(method.rawValue) \(path) failed error=\(error)")
            throw BackendError.network(error)
        }
        let elapsed = (clock.now - start).components
        let milliseconds = elapsed.seconds * 1000 + elapsed.attoseconds / 1_000_000_000_000_000
        logger.debug("Backend \(method.rawValue) \(path) status=\(response.statusCode) duration=\(milliseconds)ms")
        guard acceptedStatus.contains(response.statusCode) else {
            let error = Self.error(for: response)
            logger.error("Backend \(method.rawValue) \(path) error=\(error.logDescription)")
            throw error
        }
        return response
    }

    /// A response that a GET may repeat.
    private struct Retryable: Error {
        let response: HTTPResponse
    }

    private func perform(_ request: HTTPRequest, retrying: Bool) async throws -> HTTPResponse {
        guard retrying else { return try await httpClient.send(request) }
        let httpClient = httpClient
        do {
            return try await retryExecutor.run {
                let response = try await httpClient.send(request)
                if response.statusCode == 429 || (500...504).contains(response.statusCode) {
                    throw Retryable(response: response)
                }
                return response
            } decide: { error in
                switch error {
                case let retryable as Retryable:
                    .retry(after: retryable.response.retryAfter.map { Duration.milliseconds(Int64(min($0, 60) * 1000)) })
                case let networkError as NetworkError:
                    networkError == .timeout || networkError.isTransportFailure ? .retry(after: nil) : .doNotRetry
                default:
                    .doNotRetry
                }
            }
        } catch let retryable as Retryable {
            return retryable.response
        }
    }

    private func decode<Value: Decodable>(_ response: HTTPResponse) throws -> Value {
        do {
            return try JSONDecoder().decode(Value.self, from: response.body)
        } catch {
            logger.error("Backend response does not match the contract: \(Value.self)")
            throw BackendError.decoding
        }
    }

    /// The contract's error body `{ "code", "message", "requestId" }`.
    private struct ErrorBody: Decodable {
        let code: String?
        let requestId: String?
    }

    static func error(for response: HTTPResponse) -> BackendError {
        switch response.statusCode {
        case 401:
            return .unauthorized
        case 403:
            return .forbidden
        case 404:
            return .notFound
        case 429:
            return .rateLimited(retryAfter: response.retryAfter)
        default:
            let body = try? JSONDecoder().decode(ErrorBody.self, from: response.body)
            return .server(statusCode: response.statusCode, code: body?.code, requestID: body?.requestId)
        }
    }

    /// `value` as one path segment; IDs with `/`, `?` or `#` are rejected.
    static func pathSegment(_ value: String) throws -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#")
        guard !value.isEmpty, let encoded = value.addingPercentEncoding(withAllowedCharacters: allowed), encoded == value else {
            throw BackendError.notFound
        }
        return encoded
    }
}

extension NetworkError {
    /// Whether the error is a transport failure (connection lost, DNS, TLS).
    var isTransportFailure: Bool {
        if case .transport = self { return true }
        return false
    }
}

// MARK: - UnavailableBackendClient

/// The client while no backend host is configured: config falls back to
/// `RemoteAppConfig.fallback`, everything else throws `.notConfigured`, so the screens show
/// their "delivered by e-mail" fallback (PROMPT.md 12).
public struct UnavailableBackendClient: BackendClient {
    /// Creates the client.
    public init() {}

    public func appConfig() async throws -> RemoteAppConfig {
        .fallback
    }

    public func orders() async throws -> [BackendOrderStatus] {
        throw BackendError.notConfigured
    }

    public func licenses(orderID _: String) async throws -> LicenseDelivery {
        throw BackendError.notConfigured
    }

    public func invoice(orderID _: String) async throws -> InvoiceLink {
        throw BackendError.notConfigured
    }

    public func requestAccountDeletion() async throws -> String? {
        throw BackendError.notConfigured
    }

    public func loyalty() async throws -> LoyaltyStatus {
        throw BackendError.notConfigured
    }

    public func redeemLoyalty(points _: Int, idempotencyKey _: String) async throws -> LoyaltyRedeemCode {
        throw BackendError.notConfigured
    }

    public func loyaltyReferral() async throws -> LoyaltyReferralCode {
        throw BackendError.notConfigured
    }

    public func walletPass() async throws -> Data {
        throw BackendError.notConfigured
    }

    public func registerDevice(_: DeviceRegistration) async throws {
        throw BackendError.notConfigured
    }

    public func unregisterDevice(apnsToken _: String) async throws {
        throw BackendError.notConfigured
    }
}

// MARK: - LicenseKeyCache

/// Keeps delivered license keys in the Keychain (device-only) so the vault works offline.
/// Wiped on logout and on account deletion.
public final class LicenseKeyCache: Sendable {
    /// The Keychain key.
    public static let storageKey = "licenses.cache.v1"

    private let secureStore: any SecureStore
    private let logger: KXLogger

    /// Creates the cache on `store`.
    public init(store: any SecureStore, logger: KXLogger = KXLogger(category: .keychain)) {
        secureStore = store
        self.logger = logger
    }

    /// Every cached key, newest delivery first.
    public func all() -> [LicenseKey] {
        do {
            let keys = try secureStore.value([LicenseKey].self, for: Self.storageKey) ?? []
            return keys.sorted { ($0.deliveredAt ?? .distantPast) > ($1.deliveredAt ?? .distantPast) }
        } catch {
            logger.error("The license cache is unreadable and was ignored")
            return []
        }
    }

    /// The cached keys of `orderID`.
    public func keys(orderID: String) -> [LicenseKey] {
        all().filter { $0.orderID == orderID }
    }

    /// Replaces the cached keys of `orderID` with `keys`.
    public func store(_ keys: [LicenseKey], orderID: String) {
        let merged = all().filter { $0.orderID != orderID } + keys.map { $0.assigned(to: orderID) }
        do {
            try secureStore.setValue(merged, for: Self.storageKey)
        } catch {
            logger.error("Caching license keys failed")
        }
    }

    /// Removes every cached key.
    public func removeAll() {
        do {
            try secureStore.removeValue(for: Self.storageKey)
        } catch {
            logger.error("Removing the license cache failed")
        }
    }
}
