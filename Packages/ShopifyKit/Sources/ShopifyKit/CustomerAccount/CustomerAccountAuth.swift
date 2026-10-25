import Core
import Foundation

// MARK: - CustomerAccountAuthError

/// Why signing in, refreshing or calling the Customer Account API failed.
public enum CustomerAccountAuthError: Error, Sendable, Equatable {
    /// No client ID or redirect URI is configured; login is unavailable in this build.
    case notConfigured
    /// The customer closed the login page.
    case cancelled
    /// The redirect did not carry a code, or it did not come back to the registered URI.
    case invalidCallback
    /// The `state` of the redirect does not match the request (possible CSRF); nothing was stored.
    case stateMismatch
    /// Shopify answered the authorization with an OAuth error, e.g. `access_denied`.
    case authorizationFailed(code: String)
    /// The ID token is malformed or its `nonce`, audience, issuer or expiry is wrong.
    case invalidIDToken(reason: String)
    /// The token endpoint rejected the code or the refresh token (`invalid_grant`).
    case invalidGrant
    /// The token endpoint answered with another error.
    case tokenEndpoint(statusCode: Int, code: String?)
    /// The discovery documents or the token response could not be read.
    case decoding
    /// The request did not reach Shopify (offline, timeout, transport).
    case network(NetworkError)
    /// The customer is not signed in (anymore); the stored tokens were removed.
    case signedOut

    /// A short, log-safe description without any token or code.
    public var logDescription: String {
        switch self {
        case .notConfigured: "notConfigured"
        case .cancelled: "cancelled"
        case .invalidCallback: "invalidCallback"
        case .stateMismatch: "stateMismatch"
        case let .authorizationFailed(code): "authorizationFailed(\(code))"
        case let .invalidIDToken(reason): "invalidIDToken(\(reason))"
        case .invalidGrant: "invalidGrant"
        case let .tokenEndpoint(statusCode, code): "tokenEndpoint(\(statusCode),\(code ?? "-"))"
        case .decoding: "decoding"
        case let .network(error): "network(\(error))"
        case .signedOut: "signedOut"
        }
    }
}

// MARK: - CustomerAccountEndpoints

/// The OAuth and GraphQL endpoints of the store's Customer Account API, read from the discovery
/// documents `/.well-known/openid-configuration` and `/.well-known/customer-account-api`
/// (PROMPT.md 5.4). They are never hardcoded.
public struct CustomerAccountEndpoints: Sendable, Hashable, Codable {
    /// The OpenID issuer, e.g. `https://shopify.com/authentication/91753283851`.
    public let issuer: String
    /// Where the login page is opened.
    public let authorizationEndpoint: URL
    /// Where codes and refresh tokens are exchanged.
    public let tokenEndpoint: URL
    /// Where a session is ended, `nil` when the store does not advertise one.
    public let endSessionEndpoint: URL?
    /// The GraphQL endpoint of the pinned API version.
    public let graphQLEndpoint: URL

    /// Creates the endpoints.
    public init(issuer: String, authorizationEndpoint: URL, tokenEndpoint: URL, endSessionEndpoint: URL?, graphQLEndpoint: URL) {
        self.issuer = issuer
        self.authorizationEndpoint = authorizationEndpoint
        self.tokenEndpoint = tokenEndpoint
        self.endSessionEndpoint = endSessionEndpoint
        self.graphQLEndpoint = graphQLEndpoint
    }
}

/// The fields of `/.well-known/openid-configuration` the app uses.
struct OpenIDConfigurationDocument: Decodable, Sendable, Equatable {
    let issuer: String
    let authorizationEndpoint: URL
    let tokenEndpoint: URL
    let endSessionEndpoint: URL?

    private enum CodingKeys: String, CodingKey {
        case issuer
        case authorizationEndpoint = "authorization_endpoint"
        case tokenEndpoint = "token_endpoint"
        case endSessionEndpoint = "end_session_endpoint"
    }
}

/// The fields of `/.well-known/customer-account-api` the app uses.
struct CustomerAccountAPIDocument: Decodable, Sendable, Equatable {
    let graphQLAPI: URL

    private enum CodingKeys: String, CodingKey {
        case graphQLAPI = "graphql_api"
    }
}

// MARK: - CustomerAccountDiscovery

/// Loads and caches the Customer Account endpoints.
///
/// The GraphQL URL of the discovery document carries the API version Shopify considers current
/// (`.../customer/api/2026-07/graphql`); the app replaces that version segment with its pinned
/// `customerAccountAPIVersion`, so an API upgrade stays a deliberate change in
/// `Config/Base.xcconfig`. Concurrent callers share one load; a failed load is not cached.
public actor CustomerAccountDiscovery {
    private let openIDConfigurationURL: URL
    private let customerAccountAPIURL: URL
    private let apiVersion: String
    private let httpClient: any HTTPClient
    private var cached: CustomerAccountEndpoints?
    private var loading: Task<CustomerAccountEndpoints, any Error>?

    /// Creates the discovery.
    ///
    /// - Parameters:
    ///   - openIDConfigurationURL: `AppConfiguration.openIDConfigurationURL`.
    ///   - customerAccountAPIURL: `AppConfiguration.customerAccountDiscoveryURL`.
    ///   - apiVersion: The pinned Customer Account API version, e.g. `2026-10`.
    ///   - httpClient: The transport.
    public init(openIDConfigurationURL: URL, customerAccountAPIURL: URL, apiVersion: String, httpClient: any HTTPClient) {
        self.openIDConfigurationURL = openIDConfigurationURL
        self.customerAccountAPIURL = customerAccountAPIURL
        self.apiVersion = apiVersion
        self.httpClient = httpClient
    }

    /// The endpoints, loaded on first use.
    ///
    /// - Throws: `CustomerAccountAuthError.network`, `.tokenEndpoint` (non-2xx) or `.decoding`.
    public func endpoints() async throws -> CustomerAccountEndpoints {
        if let cached { return cached }
        if let loading { return try await loading.value }
        let task = Task { [openIDConfigurationURL, customerAccountAPIURL, apiVersion, httpClient] in
            async let openID: OpenIDConfigurationDocument = Self.fetch(openIDConfigurationURL, with: httpClient)
            async let api: CustomerAccountAPIDocument = Self.fetch(customerAccountAPIURL, with: httpClient)
            let (configuration, document) = try await (openID, api)
            return CustomerAccountEndpoints(
                issuer: configuration.issuer,
                authorizationEndpoint: configuration.authorizationEndpoint,
                tokenEndpoint: configuration.tokenEndpoint,
                endSessionEndpoint: configuration.endSessionEndpoint,
                graphQLEndpoint: Self.pinning(document.graphQLAPI, to: apiVersion)
            )
        }
        loading = task
        do {
            let endpoints = try await task.value
            cached = endpoints
            loading = nil
            return endpoints
        } catch {
            loading = nil
            throw error
        }
    }

    /// Replaces the version segment after `/api/` with `version`; other URLs stay unchanged.
    static func pinning(_ url: URL, to version: String) -> URL {
        var components = url.pathComponents
        guard let index = components.firstIndex(of: "api"), components.index(after: index) < components.endIndex,
              AppConfiguration.isValidAPIVersion(components[components.index(after: index)]),
              var urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return url }
        components[components.index(after: index)] = version
        urlComponents.path = "/" + components.dropFirst().joined(separator: "/")
        return urlComponents.url ?? url
    }

    private static func fetch<Document: Decodable>(_ url: URL, with httpClient: any HTTPClient) async throws -> Document {
        let response: HTTPResponse
        do {
            response = try await httpClient.send(HTTPRequest(method: .get, url: url, headers: ["Accept": "application/json"]))
        } catch let error as NetworkError {
            throw CustomerAccountAuthError.network(error)
        }
        guard response.isSuccess else {
            throw CustomerAccountAuthError.tokenEndpoint(statusCode: response.statusCode, code: nil)
        }
        do {
            return try JSONDecoder().decode(Document.self, from: response.body)
        } catch {
            throw CustomerAccountAuthError.decoding
        }
    }
}

// MARK: - PKCE

/// A PKCE pair (RFC 7636): a 43-character random verifier and its S256 challenge.
public struct PKCE: Sendable, Hashable {
    /// The secret `code_verifier`, sent only to the token endpoint.
    public let verifier: String
    /// `BASE64URL(SHA256(verifier))`, sent with the authorization request.
    public let challenge: String

    /// Creates the pair for `verifier`.
    public init(verifier: String) {
        self.verifier = verifier
        challenge = Base64URL.encode(SHA256.hash(verifier))
    }

    /// A fresh pair from 32 random bytes.
    public static func make() -> PKCE {
        PKCE(verifier: SecureRandom.token(byteCount: 32))
    }
}

// MARK: - CustomerAccountAuthorization

/// One login attempt: the URL to open and the secrets to check the redirect against.
public struct CustomerAccountAuthorization: Sendable, Hashable {
    /// The scopes PROMPT.md 4 requires.
    public static let scope = "openid email customer-account-api:full"

    /// The authorization URL to open in `ASWebAuthenticationSession`.
    public let url: URL
    /// The anti-CSRF value the redirect must return.
    public let state: String
    /// The value the ID token must carry.
    public let nonce: String
    /// The PKCE pair of this attempt.
    public let pkce: PKCE
    /// The registered redirect URI.
    public let redirectURI: URL

    /// Builds the authorization request.
    ///
    /// - Parameters:
    ///   - endpoints: The discovered endpoints.
    ///   - clientID: The public client ID.
    ///   - redirectURI: `shop.{shop_id}.app://callback`.
    ///   - locale: The login page language (`de`, `fr`, `pt-PT`, ...), or `nil` for Shopify's choice.
    ///   - pkce: The PKCE pair, fresh by default.
    ///   - state: The CSRF value, random by default.
    ///   - nonce: The replay protection value, random by default.
    public init(
        endpoints: CustomerAccountEndpoints,
        clientID: String,
        redirectURI: URL,
        locale: String?,
        pkce: PKCE = .make(),
        state: String = SecureRandom.token(),
        nonce: String = SecureRandom.token()
    ) {
        self.state = state
        self.nonce = nonce
        self.pkce = pkce
        self.redirectURI = redirectURI
        var components = URLComponents(url: endpoints.authorizationEndpoint, resolvingAgainstBaseURL: false)
        var items = components?.queryItems ?? []
        items += [
            URLQueryItem(name: "scope", value: Self.scope),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI.absoluteString),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "nonce", value: nonce),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        if let locale, !locale.isEmpty {
            items.append(URLQueryItem(name: "locale", value: locale))
        }
        components?.queryItems = items
        url = components?.url ?? endpoints.authorizationEndpoint
    }

    /// Reads the authorization code from the redirect.
    ///
    /// - Throws: `.invalidCallback` for another URI or no code, `.stateMismatch` for a wrong or
    ///   missing `state` (checked before the code is used), `.authorizationFailed` for an OAuth
    ///   `error` parameter.
    public func code(fromCallback callbackURL: URL) throws -> String {
        guard callbackURL.scheme?.lowercased() == redirectURI.scheme?.lowercased(),
              callbackURL.host == redirectURI.host,
              let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)
        else { throw CustomerAccountAuthError.invalidCallback }
        let items = components.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value
        }
        guard value("state") == state else {
            throw CustomerAccountAuthError.stateMismatch
        }
        if let error = value("error") {
            throw CustomerAccountAuthError.authorizationFailed(code: error)
        }
        guard let code = value("code"), !code.isEmpty else {
            throw CustomerAccountAuthError.invalidCallback
        }
        return code
    }
}

// MARK: - IDTokenClaims

/// The claims of an ID token the app checks. The token comes straight from the token endpoint
/// over TLS, so its signature is not verified (OpenID Connect Core 3.1.3.7, item 6); the
/// `nonce`, audience, issuer and expiry are.
public struct IDTokenClaims: Sendable, Hashable {
    /// `iss`.
    public let issuer: String
    /// `aud`, one or more client IDs.
    public let audiences: [String]
    /// `exp`.
    public let expiresAt: Date
    /// `nonce`, if present.
    public let nonce: String?

    /// Decodes the payload of `token` (header.payload.signature).
    ///
    /// - Throws: `.invalidIDToken` when it is not a JWT or lacks a claim.
    public init(token: String) throws {
        let segments = token.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 3, let data = Base64URL.decode(segments[1]),
              let payload = try? JSONDecoder().decode(Payload.self, from: data)
        else { throw CustomerAccountAuthError.invalidIDToken(reason: "format") }
        guard let issuer = payload.iss else {
            throw CustomerAccountAuthError.invalidIDToken(reason: "iss")
        }
        guard let expiry = payload.exp else {
            throw CustomerAccountAuthError.invalidIDToken(reason: "exp")
        }
        self.issuer = issuer
        audiences = payload.aud?.values ?? []
        expiresAt = Date(timeIntervalSince1970: expiry)
        nonce = payload.nonce
    }

    /// The JSON payload; `aud` is a string or an array of strings.
    private struct Payload: Decodable {
        let iss: String?
        let aud: Audience?
        let exp: Double?
        let nonce: String?
    }

    private struct Audience: Decodable {
        let values: [String]

        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let single = try? container.decode(String.self) {
                values = [single]
            } else {
                values = try container.decode([String].self)
            }
        }
    }

    /// Checks the claims of a token issued for `authorization`.
    ///
    /// - Parameters:
    ///   - nonce: The nonce of the authorization request.
    ///   - clientID: The client ID that must be among the audiences.
    ///   - issuer: The discovered issuer; an empty issuer is not compared.
    ///   - now: The current time; one minute of clock skew is tolerated.
    public func validate(nonce expectedNonce: String, clientID: String, issuer expectedIssuer: String, now: Date) throws {
        guard nonce == expectedNonce else {
            throw CustomerAccountAuthError.invalidIDToken(reason: "nonce")
        }
        guard audiences.contains(clientID) else {
            throw CustomerAccountAuthError.invalidIDToken(reason: "aud")
        }
        guard expectedIssuer.isEmpty || issuer == expectedIssuer else {
            throw CustomerAccountAuthError.invalidIDToken(reason: "iss")
        }
        guard expiresAt.addingTimeInterval(60) > now else {
            throw CustomerAccountAuthError.invalidIDToken(reason: "exp")
        }
    }
}

// MARK: - CustomerAccountTokens

/// The tokens of a signed-in customer, stored in the Keychain (device only).
///
/// `description` never prints a token.
public struct CustomerAccountTokens: Sendable, Hashable, Codable, CustomStringConvertible, CustomReflectable {
    /// The access token sent as the `Authorization` header of Customer Account API calls.
    public let accessToken: String
    /// The refresh token, `nil` when Shopify issued none.
    public let refreshToken: String?
    /// The ID token, used as `id_token_hint` when signing out.
    public let idToken: String?
    /// When the access token expires.
    public let expiresAt: Date

    /// Creates the tokens.
    public init(accessToken: String, refreshToken: String?, idToken: String?, expiresAt: Date) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.idToken = idToken
        self.expiresAt = expiresAt
    }

    /// Whether the access token is expired or expires within `leeway` seconds of `date`.
    public func needsRefresh(at date: Date, leeway: TimeInterval = 60) -> Bool {
        expiresAt.timeIntervalSince(date) <= leeway
    }

    /// A log-safe description.
    public var description: String {
        "CustomerAccountTokens(accessToken: \(Redactor.replacement), refreshToken: \(refreshToken == nil ? "nil" : Redactor.replacement), "
            + "expiresAt: \(expiresAt.formatted(Date.ISO8601FormatStyle())))"
    }

    /// A mirror without tokens.
    public var customMirror: Mirror {
        Mirror(self, children: ["description": description], displayStyle: .struct)
    }
}
