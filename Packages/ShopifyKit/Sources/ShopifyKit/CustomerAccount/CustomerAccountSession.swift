import Core
import Foundation

// MARK: - CustomerAccountTokenClient

/// Talks to the token endpoint: exchanges an authorization code (with the PKCE verifier) and
/// refreshes access tokens. Requests are form-encoded POSTs and are never retried, because a
/// code or refresh token can only be used once.
public struct CustomerAccountTokenClient: Sendable {
    private let httpClient: any HTTPClient
    private let clientID: String
    private let now: @Sendable () -> Date

    /// Creates the client.
    ///
    /// - Parameters:
    ///   - httpClient: The transport.
    ///   - clientID: The public client ID.
    ///   - now: The clock used to compute expiry dates.
    public init(httpClient: any HTTPClient, clientID: String, now: @escaping @Sendable () -> Date = { Date() }) {
        self.httpClient = httpClient
        self.clientID = clientID
        self.now = now
    }

    /// Exchanges `code` for tokens.
    public func exchange(
        code: String,
        authorization: CustomerAccountAuthorization,
        tokenEndpoint: URL
    ) async throws -> CustomerAccountTokens {
        try await request(
            tokenEndpoint,
            fields: [
                ("grant_type", "authorization_code"),
                ("client_id", clientID),
                ("redirect_uri", authorization.redirectURI.absoluteString),
                ("code", code),
                ("code_verifier", authorization.pkce.verifier),
            ],
            previousRefreshToken: nil
        )
    }

    /// Exchanges `refreshToken` for a new access token. Shopify may rotate the refresh token;
    /// when the response carries none, the previous one is kept.
    public func refresh(_ refreshToken: String, idToken: String?, tokenEndpoint: URL) async throws -> CustomerAccountTokens {
        let tokens = try await request(
            tokenEndpoint,
            fields: [
                ("grant_type", "refresh_token"),
                ("client_id", clientID),
                ("refresh_token", refreshToken),
            ],
            previousRefreshToken: refreshToken
        )
        return CustomerAccountTokens(
            accessToken: tokens.accessToken,
            refreshToken: tokens.refreshToken,
            idToken: tokens.idToken ?? idToken,
            expiresAt: tokens.expiresAt
        )
    }

    // MARK: Private

    private struct TokenResponse: Decodable {
        let accessToken: String
        let refreshToken: String?
        let idToken: String?
        let expiresIn: Double?

        private enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case idToken = "id_token"
            case expiresIn = "expires_in"
        }
    }

    private struct ErrorResponse: Decodable {
        let error: String?
    }

    private func request(_ url: URL, fields: [(String, String)], previousRefreshToken: String?) async throws -> CustomerAccountTokens {
        let body = Data(Self.formEncoded(fields).utf8)
        let request = HTTPRequest(
            method: .post,
            url: url,
            headers: ["Content-Type": "application/x-www-form-urlencoded", "Accept": "application/json"],
            body: body
        )
        let response: HTTPResponse
        do {
            response = try await httpClient.send(request)
        } catch let error as NetworkError {
            throw CustomerAccountAuthError.network(error)
        }
        guard response.isSuccess else {
            let code = (try? JSONDecoder().decode(ErrorResponse.self, from: response.body))?.error
            if code == "invalid_grant" {
                throw CustomerAccountAuthError.invalidGrant
            }
            throw CustomerAccountAuthError.tokenEndpoint(statusCode: response.statusCode, code: code)
        }
        guard let decoded = try? JSONDecoder().decode(TokenResponse.self, from: response.body) else {
            throw CustomerAccountAuthError.decoding
        }
        // Shopify documents `expires_in`; one hour is its usual value and a safe fallback.
        let lifetime = max(decoded.expiresIn ?? 3600, 0)
        return CustomerAccountTokens(
            accessToken: decoded.accessToken,
            refreshToken: decoded.refreshToken ?? previousRefreshToken,
            idToken: decoded.idToken,
            expiresAt: now().addingTimeInterval(lifetime)
        )
    }

    /// `application/x-www-form-urlencoded` with RFC 3986 unreserved characters kept.
    static func formEncoded(_ fields: [(String, String)]) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        func encode(_ text: String) -> String {
            text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
        }
        return fields.map { "\(encode($0.0))=\(encode($0.1))" }.joined(separator: "&")
    }
}

// MARK: - CustomerAccountSessionEvent

/// A change of the signed-in state, delivered on `CustomerAccountSession.events`.
public enum CustomerAccountSessionEvent: Sendable, Equatable {
    /// Tokens were stored after a login.
    case signedIn
    /// The tokens were removed: by logout, or because Shopify rejected the refresh token.
    case signedOut
}

// MARK: - CustomerAccountSession

/// The customer's login: starts and completes the OAuth flow, keeps the tokens in the Keychain
/// and hands out valid access tokens.
///
/// - Tokens live in `SecureStore` under ``tokenStorageKey`` (device-only Keychain item).
/// - `accessToken()` refreshes about a minute before expiry. Concurrent callers share one
///   refresh. A rejected refresh token (`invalid_grant`) signs the customer out.
/// - Nothing here logs a token, code, verifier, nonce or state.
public actor CustomerAccountSession {
    /// The Keychain key of the tokens.
    public static let tokenStorageKey = "customerAccount.tokens.v1"

    /// Sign-in and sign-out events, for the account screen.
    public nonisolated let events: AsyncStream<CustomerAccountSessionEvent>

    private let clientID: String
    private let redirectURI: URL
    private let discovery: CustomerAccountDiscovery
    private let tokenClient: CustomerAccountTokenClient
    private let secureStore: any SecureStore
    private let now: @Sendable () -> Date
    private let logger: KXLogger
    private let continuation: AsyncStream<CustomerAccountSessionEvent>.Continuation
    private var tokens: CustomerAccountTokens?
    private var refreshing: Task<CustomerAccountTokens, any Error>?
    /// Increases with every `clear()`, so a refresh that finishes after a logout is dropped.
    private var generation = 0

    /// Creates the session and reads stored tokens.
    ///
    /// - Parameters:
    ///   - clientID: The public client ID.
    ///   - redirectURI: The registered redirect URI.
    ///   - discovery: The endpoint discovery.
    ///   - httpClient: The transport of the token endpoint.
    ///   - secureStore: The Keychain.
    ///   - now: The clock.
    ///   - logger: Logs outcomes, never secrets.
    public init(
        clientID: String,
        redirectURI: URL,
        discovery: CustomerAccountDiscovery,
        httpClient: any HTTPClient,
        secureStore: any SecureStore,
        now: @escaping @Sendable () -> Date = { Date() },
        logger: KXLogger = KXLogger(category: .auth)
    ) {
        self.clientID = clientID
        self.redirectURI = redirectURI
        self.discovery = discovery
        tokenClient = CustomerAccountTokenClient(httpClient: httpClient, clientID: clientID, now: now)
        self.secureStore = secureStore
        self.now = now
        self.logger = logger
        (events, continuation) = AsyncStream.makeStream(of: CustomerAccountSessionEvent.self)
        do {
            tokens = try secureStore.value(CustomerAccountTokens.self, for: Self.tokenStorageKey)
        } catch {
            logger.error("Stored customer tokens are unreadable and were ignored")
            tokens = nil
        }
    }

    /// Whether tokens are stored (the access token may still need a refresh).
    public var isSignedIn: Bool {
        tokens != nil
    }

    // MARK: Login

    /// Prepares a login: discovers the endpoints and builds the authorization URL.
    ///
    /// - Parameter locale: The login page language, e.g. `de`.
    public func beginSignIn(locale: String?) async throws -> CustomerAccountAuthorization {
        let endpoints = try await discovery.endpoints()
        return CustomerAccountAuthorization(endpoints: endpoints, clientID: clientID, redirectURI: redirectURI, locale: locale)
    }

    /// Completes a login with the redirect of `authorization`: checks `state`, exchanges the
    /// code, validates the ID token and stores the tokens.
    public func completeSignIn(_ authorization: CustomerAccountAuthorization, callbackURL: URL) async throws {
        let code = try authorization.code(fromCallback: callbackURL)
        let endpoints = try await discovery.endpoints()
        let received = try await tokenClient.exchange(code: code, authorization: authorization, tokenEndpoint: endpoints.tokenEndpoint)
        guard let idToken = received.idToken else {
            throw CustomerAccountAuthError.invalidIDToken(reason: "missing")
        }
        try IDTokenClaims(token: idToken).validate(nonce: authorization.nonce, clientID: clientID, issuer: endpoints.issuer, now: now())
        try store(received)
        logger.info("Customer signed in")
        continuation.yield(.signedIn)
    }

    // MARK: Tokens

    /// A valid access token, refreshed when it expires within a minute.
    ///
    /// - Throws: `.signedOut` without tokens or after a rejected refresh; network errors of a
    ///   refresh are passed on and keep the tokens.
    public func accessToken() async throws -> String {
        guard let current = tokens else { throw CustomerAccountAuthError.signedOut }
        if !current.needsRefresh(at: now()) {
            return current.accessToken
        }
        return try await refreshed().accessToken
    }

    /// Forces the next `accessToken()` to refresh, e.g. after the API answered 401.
    public func invalidateAccessToken() {
        guard let current = tokens else { return }
        tokens = CustomerAccountTokens(
            accessToken: current.accessToken,
            refreshToken: current.refreshToken,
            idToken: current.idToken,
            expiresAt: .distantPast
        )
    }

    // MARK: Logout

    /// Removes the tokens and returns the URL that ends the Shopify session, if the store
    /// advertises one. The app may open it in the background; the local logout does not wait.
    @discardableResult
    public func signOut() async -> URL? {
        let idToken = tokens?.idToken
        clear()
        guard let idToken, let endpoints = try? await discovery.endpoints(), let endSession = endpoints.endSessionEndpoint,
              var components = URLComponents(url: endSession, resolvingAgainstBaseURL: false)
        else { return nil }
        components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "id_token_hint", value: idToken)]
        return components.url
    }

    /// Removes the tokens without contacting Shopify (account deletion, reset).
    public func clear() {
        refreshing?.cancel()
        refreshing = nil
        generation += 1
        let wasSignedIn = tokens != nil
        tokens = nil
        do {
            try secureStore.removeValue(for: Self.tokenStorageKey)
        } catch {
            logger.error("Removing the customer tokens failed")
        }
        if wasSignedIn {
            logger.info("Customer signed out")
            continuation.yield(.signedOut)
        }
    }

    // MARK: Private

    private func refreshed() async throws -> CustomerAccountTokens {
        if let refreshing {
            return try await refreshing.value
        }
        guard let current = tokens, let refreshToken = current.refreshToken else {
            clear()
            throw CustomerAccountAuthError.signedOut
        }
        let task = Task { [discovery, tokenClient] in
            let endpoints = try await discovery.endpoints()
            return try await tokenClient.refresh(refreshToken, idToken: current.idToken, tokenEndpoint: endpoints.tokenEndpoint)
        }
        refreshing = task
        let startGeneration = generation
        do {
            let fresh = try await task.value
            guard generation == startGeneration else { throw CustomerAccountAuthError.signedOut }
            refreshing = nil
            try store(fresh)
            return fresh
        } catch CustomerAccountAuthError.invalidGrant {
            guard generation == startGeneration else { throw CustomerAccountAuthError.signedOut }
            refreshing = nil
            logger.notice("Refresh token rejected; signing out")
            clear()
            throw CustomerAccountAuthError.signedOut
        } catch {
            if generation == startGeneration {
                refreshing = nil
            }
            throw error
        }
    }

    private func store(_ fresh: CustomerAccountTokens) throws {
        try secureStore.setValue(fresh, for: Self.tokenStorageKey)
        tokens = fresh
    }
}
