import Core
import Foundation

// MARK: - StorefrontConfiguration

/// Endpoint and credentials of the Storefront API.
public struct StorefrontConfiguration: Sendable, Equatable {
    /// The request header that carries the public Storefront access token.
    public static let accessTokenHeader = "X-Shopify-Storefront-Access-Token"

    /// The GraphQL endpoint, e.g. `https://45dv93-bk.myshopify.com/api/2026-07/graphql.json`.
    public let endpoint: URL
    /// The public Storefront access token, or `nil` for Shopify's tokenless access.
    public let accessToken: String?
    /// The pinned API version, e.g. `2026-07`.
    public let apiVersion: String

    /// Creates a configuration. A blank token counts as no token.
    public init(endpoint: URL, accessToken: String?, apiVersion: String) {
        self.endpoint = endpoint
        let trimmedToken = accessToken?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.accessToken = (trimmedToken?.isEmpty ?? true) ? nil : trimmedToken
        self.apiVersion = apiVersion
    }

    /// The Storefront endpoint, token and API version of the app configuration.
    public init(appConfiguration: AppConfiguration) {
        self.init(
            endpoint: appConfiguration.storefrontEndpoint,
            accessToken: appConfiguration.storefrontAccessToken,
            apiVersion: appConfiguration.storefrontAPIVersion
        )
    }

    /// Whether requests are sent without a token. Tokenless access covers products,
    /// collections, localization, search, content and cart, but not metafields.
    public var isTokenless: Bool {
        accessToken == nil
    }

    /// The static request headers: the access token header when a token is configured.
    public var headers: [String: String] {
        guard let accessToken else { return [:] }
        return [Self.accessTokenHeader: accessToken]
    }
}

extension StorefrontConfiguration: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// A log-safe summary that never contains the token.
    public var description: String {
        "StorefrontConfiguration(endpoint: \(endpoint.absoluteString), apiVersion: \(apiVersion), "
            + "accessToken: \(accessToken == nil ? "nil" : Redactor.replacement))"
    }

    /// Same as `description`.
    public var debugDescription: String {
        description
    }

    /// A mirror that masks the token, so `dump(_:)` and test output never print it.
    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "endpoint": endpoint,
                "accessToken": accessToken == nil ? "nil" : Redactor.replacement,
                "apiVersion": apiVersion,
            ],
            displayStyle: .struct
        )
    }
}

// MARK: - StorefrontClient

/// Executes Storefront API operations in a buyer context.
///
/// Wraps a `GraphQLClient` configured with the Storefront endpoint and, when a token is
/// configured, the `X-Shopify-Storefront-Access-Token` header. Every call carries an
/// `@inContext` directive built from a `StorefrontContext`.
///
/// ```swift
/// let client = StorefrontClient(configuration: StorefrontConfiguration(appConfiguration: .preview),
///                               httpClient: URLSessionHTTPClient())
/// let data = try await client.execute(LocalizationQuery(), context: .germany)
/// ```
public final class StorefrontClient: Sendable {
    /// The endpoint and credentials in use.
    public let configuration: StorefrontConfiguration
    private let graphQLClient: GraphQLClient

    /// Creates a client.
    ///
    /// - Parameters:
    ///   - configuration: Endpoint and optional token.
    ///   - httpClient: The transport, e.g. a shared `URLSessionHTTPClient`.
    ///   - retryPolicy: Attempt and backoff bounds, `.default` by default.
    ///   - sleeper: Waits between attempts; inject a recording sleeper in tests.
    ///   - logger: Receives one line per call, `.graphql` category by default.
    public init(
        configuration: StorefrontConfiguration,
        httpClient: any HTTPClient,
        retryPolicy: RetryPolicy = .default,
        sleeper: any Sleeper = TaskSleeper(),
        logger: KXLogger = KXLogger(category: .graphql)
    ) {
        self.configuration = configuration
        graphQLClient = GraphQLClient(
            endpoint: GraphQLEndpoint(url: configuration.endpoint, headers: configuration.headers),
            httpClient: httpClient,
            retryPolicy: retryPolicy,
            sleeper: sleeper,
            logger: logger
        )
    }

    /// Whether the client runs without an access token (metafields are not readable then).
    public var isTokenless: Bool {
        configuration.isTokenless
    }

    /// Executes `operation` with `@inContext` built from `context` and returns its data.
    ///
    /// - Throws: `ShopifyError`, or `ContextInjectionError` if the operation's document is
    ///   malformed (a programming error covered by unit tests).
    public func execute<O: GraphQLOperation>(_ operation: O, context: StorefrontContext) async throws -> O.ResponseData {
        try await graphQLClient.execute(operation, directive: context.directive)
    }
}

// MARK: - Context providers

/// Supplies the buyer context (market, language, consent) for Storefront calls.
///
/// The app implements it on top of the persisted market selection and the privacy consent,
/// so repositories always use the current values.
public protocol StorefrontContextProviding: Sendable {
    /// The context for the next Storefront call.
    func currentContext() async -> StorefrontContext
}

/// A context provider that always returns the same context. For previews, tests and tools.
public struct StaticStorefrontContextProvider: StorefrontContextProviding {
    /// The context returned by `currentContext()`.
    public let context: StorefrontContext

    /// Creates a provider for `context`, Germany in German by default.
    public init(context: StorefrontContext = .germany) {
        self.context = context
    }

    /// Returns `context`.
    public func currentContext() async -> StorefrontContext {
        context
    }
}

/// A thread-safe context provider whose context can be replaced, e.g. when the user picks a
/// different market or changes the privacy consent.
public final class MutableStorefrontContextProvider: StorefrontContextProviding {
    private let storage: Locked<StorefrontContext>

    /// Creates a provider starting with `context`.
    public init(context: StorefrontContext) {
        storage = Locked(context)
    }

    /// The current context.
    public var context: StorefrontContext {
        storage.value
    }

    /// Replaces the context used by subsequent calls.
    public func update(to context: StorefrontContext) {
        storage.replace(with: context)
    }

    /// Returns the current context.
    public func currentContext() async -> StorefrontContext {
        storage.value
    }
}
