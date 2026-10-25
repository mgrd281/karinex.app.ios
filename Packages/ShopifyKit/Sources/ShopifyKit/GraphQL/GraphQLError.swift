import Foundation

// MARK: - GraphQLPathComponent

/// One element of a GraphQL error `path`: a field name or a list index.
public enum GraphQLPathComponent: Sendable, Hashable, Codable, CustomStringConvertible {
    /// A response key, e.g. `product`.
    case key(String)
    /// A position in a list, e.g. `0`.
    case index(Int)

    /// Decodes a string as `.key` and an integer as `.index`.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let index = try? container.decode(Int.self) {
            self = .index(index)
        } else {
            self = try .key(container.decode(String.self))
        }
    }

    /// Encodes `.key` as a string and `.index` as an integer.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .key(key): try container.encode(key)
        case let .index(index): try container.encode(index)
        }
    }

    /// The key, or the index as a decimal string.
    public var description: String {
        switch self {
        case let .key(key): key
        case let .index(index): String(index)
        }
    }
}

// MARK: - GraphQLErrorDetail

/// One entry of the top-level `errors` array of a GraphQL response.
///
/// ```json
/// {"message": "Access denied for metafield field. ...", "path": ["product", "metafields"],
///  "extensions": {"code": "ACCESS_DENIED", "requiredAccess": "`unauthenticated_read_metafields` access scope."}}
/// ```
///
/// Decoding is lenient: a missing message decodes as an empty string and unknown extension
/// fields are ignored, so an unexpected error shape never hides the fact that there was an error.
public struct GraphQLErrorDetail: Sendable, Equatable, Hashable, Codable {
    /// Well-known values of `extensions.code`.
    public enum Code {
        /// The request lacks an access scope (`requiredAccess` names it).
        public static let accessDenied = "ACCESS_DENIED"
        /// The client exceeded the rate limit; retry later.
        public static let throttled = "THROTTLED"
        /// The shop is not active.
        public static let shopInactive = "SHOP_INACTIVE"
        /// Shopify failed internally; usually transient.
        public static let internalServerError = "INTERNAL_SERVER_ERROR"
        /// The query exceeded the maximum cost.
        public static let maxCostExceeded = "MAX_COST_EXCEEDED"
    }

    /// The server's (English) message. Meant for developers, never shown to customers.
    public let message: String
    /// The response path the error refers to, empty for request-level errors.
    public let path: [GraphQLPathComponent]
    /// `extensions.code`, e.g. `ACCESS_DENIED` or `THROTTLED`.
    public let code: String?
    /// `extensions.requiredAccess` of `ACCESS_DENIED` errors, e.g.
    /// "`unauthenticated_read_metafields` access scope."
    public let requiredAccess: String?

    /// Creates an error detail, e.g. in tests.
    public init(message: String, path: [GraphQLPathComponent] = [], code: String? = nil, requiredAccess: String? = nil) {
        self.message = message
        self.path = path
        self.code = code
        self.requiredAccess = requiredAccess
    }

    /// The path joined with dots, e.g. `product.metafields` or `products.nodes.0.title`.
    public var pathDescription: String {
        path.map(\.description).joined(separator: ".")
    }

    // MARK: Codable

    private enum CodingKeys: String, CodingKey {
        case message
        case path
        case extensions
    }

    private enum ExtensionKeys: String, CodingKey {
        case code
        case requiredAccess
    }

    /// Decodes an entry of the `errors` array.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        message = (try? container.decodeIfPresent(String.self, forKey: .message)) ?? ""
        path = (try? container.decodeIfPresent([GraphQLPathComponent].self, forKey: .path)) ?? []
        if let extensions = try? container.nestedContainer(keyedBy: ExtensionKeys.self, forKey: .extensions) {
            code = try? extensions.decodeIfPresent(String.self, forKey: .code)
            requiredAccess = try? extensions.decodeIfPresent(String.self, forKey: .requiredAccess)
        } else {
            code = nil
            requiredAccess = nil
        }
    }

    /// Encodes the entry in the GraphQL response shape.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(message, forKey: .message)
        if !path.isEmpty {
            try container.encode(path, forKey: .path)
        }
        if code != nil || requiredAccess != nil {
            var extensions = container.nestedContainer(keyedBy: ExtensionKeys.self, forKey: .extensions)
            try extensions.encodeIfPresent(code, forKey: .code)
            try extensions.encodeIfPresent(requiredAccess, forKey: .requiredAccess)
        }
    }
}
