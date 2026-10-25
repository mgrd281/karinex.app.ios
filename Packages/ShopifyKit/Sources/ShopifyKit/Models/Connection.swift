import Foundation

// MARK: - PageInfo

/// Cursor pagination state of a connection (Storefront `PageInfo`).
public struct PageInfo: Sendable, Hashable, Codable {
    /// Whether more items follow `endCursor`.
    public let hasNextPage: Bool
    /// Whether items precede `startCursor`.
    public let hasPreviousPage: Bool
    /// The cursor of the first item, if any.
    public let startCursor: String?
    /// The cursor of the last item; pass it as `after` to load the next page.
    public let endCursor: String?

    /// Creates pagination state.
    public init(hasNextPage: Bool, hasPreviousPage: Bool, startCursor: String?, endCursor: String?) {
        self.hasNextPage = hasNextPage
        self.hasPreviousPage = hasPreviousPage
        self.startCursor = startCursor
        self.endCursor = endCursor
    }

    /// A single page with nothing before or after it.
    public static let singlePage = PageInfo(hasNextPage: false, hasPreviousPage: false, startCursor: nil, endCursor: nil)

    /// The cursor to request the next page with, or `nil` on the last page.
    public var nextPageCursor: String? {
        hasNextPage ? endCursor : nil
    }
}

// MARK: - Connection

/// A GraphQL connection decoded from its `nodes` and optional `pageInfo`:
/// `{"nodes": [...], "pageInfo": {...}}`.
public struct Connection<Node> {
    /// The items of this page.
    public let nodes: [Node]
    /// Pagination state, if the query requested it.
    public let pageInfo: PageInfo?

    /// Creates a connection.
    public init(nodes: [Node], pageInfo: PageInfo? = nil) {
        self.nodes = nodes
        self.pageInfo = pageInfo
    }
}

extension Connection: Sendable where Node: Sendable {}
extension Connection: Equatable where Node: Equatable {}
extension Connection: Hashable where Node: Hashable {}
extension Connection: Decodable where Node: Decodable {}
extension Connection: Encodable where Node: Encodable {}
