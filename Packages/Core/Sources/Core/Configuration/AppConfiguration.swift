import Foundation

/// Build-time configuration of the app: Shopify endpoints, API versions and bundle versions.
///
/// In the app the values come from `Info.plist` keys that are filled from the `.xcconfig`
/// files (`KXShopDomain = $(KX_SHOP_DOMAIN)` and so on), see `init(infoDictionary:)`.
/// Previews and tests use `AppConfiguration.preview`.
///
/// The Storefront access token is the *public* token of the headless channel. It is not a
/// secret in the cryptographic sense (it ships inside the binary), but it is still kept out
/// of logs: `description` and `debugDescription` only say whether a token is configured.
public struct AppConfiguration: Sendable, Equatable {
    // MARK: - Info.plist keys

    /// The `Info.plist` keys read by `init(infoDictionary:)`.
    public enum InfoKey {
        /// myshopify domain of the store, e.g. `45dv93-bk.myshopify.com`. Required.
        public static let shopDomain = "KXShopDomain"
        /// Public web domain of the store, e.g. `www.karinex.de`. Required.
        public static let storeWebDomain = "KXStoreWebDomain"
        /// Storefront API version, e.g. `2026-07`. Required.
        public static let storefrontAPIVersion = "KXStorefrontAPIVersion"
        /// Public Storefront API token. Optional: empty means tokenless mode.
        public static let storefrontAccessToken = "KXStorefrontAccessToken"
        /// Customer Account API version, e.g. `2026-07`. Required.
        public static let customerAccountAPIVersion = "KXCustomerAccountAPIVersion"
        /// Customer Account API public client ID. Optional until login ships.
        public static let customerAccountClientID = "KXCustomerAccountClientID"
        /// Marketing version (`MARKETING_VERSION`). Required.
        public static let appVersion = "CFBundleShortVersionString"
        /// Build number (`CURRENT_PROJECT_VERSION`). Required.
        public static let buildNumber = "CFBundleVersion"
    }

    // MARK: - Properties

    /// myshopify domain used for the Storefront API, e.g. `45dv93-bk.myshopify.com`.
    public let shopDomain: String
    /// Public web domain of the store, e.g. `www.karinex.de`. Used for web links and for the
    /// Customer Account API discovery documents.
    public let storeWebDomain: String
    /// Pinned Storefront API version, e.g. `2026-07`.
    public let storefrontAPIVersion: String
    /// Public Storefront API token, or `nil` to use Shopify's tokenless access.
    public let storefrontAccessToken: String?
    /// Pinned Customer Account API version, e.g. `2026-07`.
    public let customerAccountAPIVersion: String
    /// Customer Account API public client ID, or `nil` when login is not configured.
    public let customerAccountClientID: String?
    /// Marketing version of the app, e.g. `0.1.0`.
    public let appVersion: String
    /// Build number of the app, e.g. `42`.
    public let buildNumber: String

    // MARK: - Init

    /// Creates a configuration from already validated values.
    ///
    /// The values are taken as they are. Use `init(infoDictionary:)` for values from outside
    /// the code base: it trims, normalizes and validates them. Domains must be bare host names
    /// (`isValidHost(_:)`) and API versions must satisfy `isValidAPIVersion(_:)`, otherwise
    /// the computed URLs cannot be formed.
    public init(
        shopDomain: String,
        storeWebDomain: String,
        storefrontAPIVersion: String,
        storefrontAccessToken: String?,
        customerAccountAPIVersion: String,
        customerAccountClientID: String?,
        appVersion: String,
        buildNumber: String
    ) {
        self.shopDomain = shopDomain
        self.storeWebDomain = storeWebDomain
        self.storefrontAPIVersion = storefrontAPIVersion
        self.storefrontAccessToken = storefrontAccessToken
        self.customerAccountAPIVersion = customerAccountAPIVersion
        self.customerAccountClientID = customerAccountClientID
        self.appVersion = appVersion
        self.buildNumber = buildNumber
    }

    /// Reads and validates the configuration from an `Info.plist` dictionary.
    ///
    /// - Values are trimmed. Empty strings and unresolved build settings (`$(VAR)` or
    ///   `${VAR}`) count as absent.
    /// - Absent required keys throw `ConfigurationError.missingValue(key:)`; absent optional
    ///   keys (`KXStorefrontAccessToken`, `KXCustomerAccountClientID`) become `nil`.
    /// - Domains must be bare host names without scheme, path, port or spaces; they are
    ///   lowercased. API versions must look like `YYYY-MM` with a quarterly month (`01`, `04`,
    ///   `07`, `10`) or be `unstable`. Violations throw `ConfigurationError.invalidValue`.
    public init(infoDictionary: [String: Any]) throws {
        let reader = InfoReader(dictionary: infoDictionary)

        let shopDomain = try reader.required(InfoKey.shopDomain).lowercased()
        guard Self.isValidHost(shopDomain) else {
            throw ConfigurationError.invalidValue(key: InfoKey.shopDomain, value: shopDomain)
        }
        let storeWebDomain = try reader.required(InfoKey.storeWebDomain).lowercased()
        guard Self.isValidHost(storeWebDomain) else {
            throw ConfigurationError.invalidValue(key: InfoKey.storeWebDomain, value: storeWebDomain)
        }
        let storefrontAPIVersion = try reader.required(InfoKey.storefrontAPIVersion)
        guard Self.isValidAPIVersion(storefrontAPIVersion) else {
            throw ConfigurationError.invalidValue(key: InfoKey.storefrontAPIVersion, value: storefrontAPIVersion)
        }
        let customerAccountAPIVersion = try reader.required(InfoKey.customerAccountAPIVersion)
        guard Self.isValidAPIVersion(customerAccountAPIVersion) else {
            throw ConfigurationError.invalidValue(
                key: InfoKey.customerAccountAPIVersion,
                value: customerAccountAPIVersion
            )
        }

        try self.init(
            shopDomain: shopDomain,
            storeWebDomain: storeWebDomain,
            storefrontAPIVersion: storefrontAPIVersion,
            storefrontAccessToken: reader.optional(InfoKey.storefrontAccessToken),
            customerAccountAPIVersion: customerAccountAPIVersion,
            customerAccountClientID: reader.optional(InfoKey.customerAccountClientID),
            appVersion: reader.required(InfoKey.appVersion),
            buildNumber: reader.required(InfoKey.buildNumber)
        )
    }

    /// Reads and validates the configuration from a bundle's `Info.plist`.
    ///
    /// - Parameter bundle: The bundle to read, `Bundle.main` by default.
    public init(bundle: Bundle = .main) throws {
        try self.init(infoDictionary: bundle.infoDictionary ?? [:])
    }

    // MARK: - Preview

    /// The real, non-secret values of the live store in tokenless mode, for previews and tests.
    ///
    /// Storefront and Customer Account API versions are pinned to `2026-07`, which was
    /// verified against the live store on 2026-09-26.
    public static let preview = AppConfiguration(
        shopDomain: "45dv93-bk.myshopify.com",
        storeWebDomain: "www.karinex.de",
        storefrontAPIVersion: "2026-07",
        storefrontAccessToken: nil,
        customerAccountAPIVersion: "2026-07",
        customerAccountClientID: nil,
        appVersion: "0.1.0",
        buildNumber: "1"
    )

    // MARK: - Derived values

    /// The Storefront API GraphQL endpoint: `https://{shopDomain}/api/{version}/graphql.json`.
    public var storefrontEndpoint: URL {
        Self.httpsURL(host: shopDomain, path: "/api/\(storefrontAPIVersion)/graphql.json")
    }

    /// Whether a Storefront access token is configured. Without one the app runs in Shopify's
    /// tokenless mode, in which metafields are not readable.
    public var isStorefrontTokenConfigured: Bool {
        storefrontAccessToken != nil
    }

    /// Whether a Customer Account API client ID is configured.
    public var isCustomerAccountConfigured: Bool {
        customerAccountClientID != nil
    }

    /// The public store website, e.g. `https://www.karinex.de`.
    public var storeWebURL: URL {
        Self.httpsURL(host: storeWebDomain, path: "")
    }

    /// Discovery document of the Customer Account API:
    /// `https://{storeWebDomain}/.well-known/customer-account-api`.
    public var customerAccountDiscoveryURL: URL {
        Self.httpsURL(host: storeWebDomain, path: "/.well-known/customer-account-api")
    }

    /// OpenID Connect discovery document of the store:
    /// `https://{storeWebDomain}/.well-known/openid-configuration`.
    public var openIDConfigurationURL: URL {
        Self.httpsURL(host: storeWebDomain, path: "/.well-known/openid-configuration")
    }

    // MARK: - Validation

    /// Returns whether `host` is a bare DNS host name such as `www.karinex.de`: at least two
    /// dot-separated labels of ASCII letters, digits and inner hyphens, no scheme, path, port,
    /// user info or whitespace, and a non-numeric top-level label.
    public static func isValidHost(_ host: String) -> Bool {
        guard !host.isEmpty, host.utf8.count <= 253 else { return false }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2 else { return false }
        for label in labels {
            guard (1...63).contains(label.utf8.count),
                  label.utf8.allSatisfy({ isASCIIAlphanumeric($0) || $0 == UInt8(ascii: "-") }),
                  label.first != "-",
                  label.last != "-"
            else { return false }
        }
        guard let topLevel = labels.last, !topLevel.utf8.allSatisfy({ isASCIIDigit($0) }) else { return false }
        return true
    }

    /// Returns whether `version` is a Shopify API version: `YYYY-MM` with a quarterly release
    /// month (`01`, `04`, `07` or `10`), or the literal `unstable`.
    public static func isValidAPIVersion(_ version: String) -> Bool {
        if version == "unstable" { return true }
        let parts = version.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2,
              parts[0].utf8.count == 4,
              parts[0].utf8.allSatisfy(isASCIIDigit)
        else { return false }
        return ["01", "04", "07", "10"].contains(parts[1])
    }

    // MARK: - Private

    private static func httpsURL(host: String, path: String) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = path
        guard let url = components.url else {
            // Unreachable for configurations created by `init(infoDictionary:)` or `preview`,
            // whose hosts are validated. Only a programming error in a memberwise call gets here.
            preconditionFailure("AppConfiguration: \(host) is not a valid host name")
        }
        return url
    }

    private static func isASCIIDigit(_ byte: UInt8) -> Bool {
        (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
    }

    private static func isASCIIAlphanumeric(_ byte: UInt8) -> Bool {
        isASCIIDigit(byte)
            || (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(byte)
            || (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte)
    }
}

// MARK: - Info dictionary reading

private struct InfoReader {
    let dictionary: [String: Any]

    /// Returns the trimmed value for `key`, or `nil` when it is absent, empty or unresolved.
    func optional(_ key: String) throws -> String? {
        guard let raw = dictionary[key] else { return nil }
        guard let string = raw as? String else {
            throw ConfigurationError.invalidValue(key: key, value: String(describing: raw))
        }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.contains("$(") || trimmed.contains("${") {
            return nil
        }
        return trimmed
    }

    /// Returns the trimmed value for `key` or throws `ConfigurationError.missingValue`.
    func required(_ key: String) throws -> String {
        guard let value = try optional(key) else {
            throw ConfigurationError.missingValue(key: key)
        }
        return value
    }
}

// MARK: - Logging-safe descriptions

extension AppConfiguration: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// A log-safe summary. The Storefront token and client ID are reported as configured or
    /// not, never printed.
    public var description: String {
        """
        AppConfiguration(shopDomain: \(shopDomain), storeWebDomain: \(storeWebDomain), \
        storefrontAPIVersion: \(storefrontAPIVersion), storefrontAccessToken: \(Self.mask(storefrontAccessToken)), \
        customerAccountAPIVersion: \(customerAccountAPIVersion), \
        customerAccountClientID: \(Self.mask(customerAccountClientID)), \
        appVersion: \(appVersion), buildNumber: \(buildNumber))
        """
    }

    /// Same as `description`.
    public var debugDescription: String {
        description
    }

    /// A mirror that masks the Storefront token and client ID, so `dump(_:)` and test failure
    /// output never print them.
    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "shopDomain": shopDomain,
                "storeWebDomain": storeWebDomain,
                "storefrontAPIVersion": storefrontAPIVersion,
                "storefrontAccessToken": Self.mask(storefrontAccessToken),
                "customerAccountAPIVersion": customerAccountAPIVersion,
                "customerAccountClientID": Self.mask(customerAccountClientID),
                "appVersion": appVersion,
                "buildNumber": buildNumber,
            ],
            displayStyle: .struct
        )
    }

    private static func mask(_ secret: String?) -> String {
        secret == nil ? "nil" : Redactor.replacement
    }
}
