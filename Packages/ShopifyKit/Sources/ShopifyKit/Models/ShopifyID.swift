import Foundation

/// A Shopify global ID such as `gid://shopify/Product/10534352027915`.
///
/// Treat IDs as opaque: compare and send them back, never build them from parts except in
/// tests. Cart IDs carry a secret cart token (`gid://shopify/Cart/<token>?key=...`); they must
/// never be logged, which `KXLogger`'s redaction also enforces.
public struct ShopifyID: RawRepresentable, Sendable, Hashable, Codable, ExpressibleByStringLiteral, CustomStringConvertible {
    /// The complete GID string.
    public let rawValue: String

    /// Wraps a GID string.
    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// Wraps a GID string.
    public init(_ rawValue: String) {
        self.init(rawValue: rawValue)
    }

    /// Wraps a GID string literal, e.g. in tests.
    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }

    /// Decodes the GID from a single string value.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(rawValue: container.decode(String.self))
    }

    /// Encodes the GID as a single string value.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    /// The GID string.
    public var description: String {
        rawValue
    }

    /// The resource type, e.g. `Product` for `gid://shopify/Product/123`, or `nil` when the
    /// value is not a Shopify GID.
    public var resourceType: String? {
        pathComponents?.type
    }

    /// The resource's own identifier without query, e.g. `123` for `gid://shopify/Product/123`,
    /// or `nil` when the value is not a Shopify GID.
    public var resourceID: String? {
        pathComponents?.id
    }

    /// Whether the value has the form `gid://shopify/<Type>/<id>`.
    public var isShopifyGID: Bool {
        pathComponents != nil
    }

    private var pathComponents: (type: String, id: String)? {
        let prefix = "gid://shopify/"
        guard rawValue.hasPrefix(prefix) else { return nil }
        var remainder = rawValue.dropFirst(prefix.count)
        if let queryStart = remainder.firstIndex(of: "?") {
            remainder = remainder[..<queryStart]
        }
        guard let slash = remainder.firstIndex(of: "/") else { return nil }
        let type = remainder[..<slash]
        let id = remainder[remainder.index(after: slash)...]
        guard !type.isEmpty, !id.isEmpty, !id.contains("/") else { return nil }
        return (String(type), String(id))
    }
}
