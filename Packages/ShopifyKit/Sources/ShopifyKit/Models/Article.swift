import Foundation

// MARK: - ArticleSummary

/// A blog article in lists, cards and search results (Storefront `Article` via the
/// `ArticleSummaryFields` fragment).
public struct ArticleSummary: Sendable, Hashable, Codable, Identifiable {
    /// The article GID.
    public let id: ShopifyID
    /// The URL handle of the article.
    public let handle: String
    /// The handle of the blog the article belongs to, e.g. `guides`.
    public let blogHandle: String
    /// The title in the context language.
    public let title: String
    /// The plain text excerpt, `nil` when the article has none.
    public let excerpt: String?
    /// When the article was published.
    public let publishedAt: Date
    /// The article image, if any.
    public let image: ShopifyImage?
    /// The article page on the web shop, if published there.
    public let onlineStoreUrl: URL?

    /// Creates an article summary.
    public init(
        id: ShopifyID,
        handle: String,
        blogHandle: String,
        title: String,
        excerpt: String?,
        publishedAt: Date,
        image: ShopifyImage?,
        onlineStoreUrl: URL?
    ) {
        self.id = id
        self.handle = handle
        self.blogHandle = blogHandle
        self.title = title
        self.excerpt = excerpt
        self.publishedAt = publishedAt
        self.image = image
        self.onlineStoreUrl = onlineStoreUrl
    }

    // MARK: Codable

    private enum CodingKeys: String, CodingKey {
        case id, handle, title, excerpt, publishedAt, image, onlineStoreUrl, blog
    }

    /// Decodes the Storefront shape: `blog { handle }`, an ISO 8601 `publishedAt` and an
    /// excerpt that is empty or `null` when there is none.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(ShopifyID.self, forKey: .id)
        handle = try container.decode(String.self, forKey: .handle)
        blogHandle = try container.decode(BlogReference.self, forKey: .blog).handle
        title = try container.decode(String.self, forKey: .title)
        excerpt = try container.decodeIfPresent(String.self, forKey: .excerpt).flatMap(ArticleCoding.nonBlank)
        publishedAt = try ArticleCoding.decodeDate(from: container, forKey: .publishedAt)
        image = try container.decodeIfPresent(ShopifyImage.self, forKey: .image)
        onlineStoreUrl = try container.decodeIfPresent(URL.self, forKey: .onlineStoreUrl)
    }

    /// Encodes the same shape `init(from:)` reads.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(handle, forKey: .handle)
        try container.encode(BlogReference(handle: blogHandle), forKey: .blog)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(excerpt, forKey: .excerpt)
        try container.encode(ArticleCoding.string(from: publishedAt), forKey: .publishedAt)
        try container.encodeIfPresent(image, forKey: .image)
        try container.encodeIfPresent(onlineStoreUrl, forKey: .onlineStoreUrl)
    }
}

// MARK: - Article

/// A complete blog article for the article screen (Storefront `Article`).
public struct Article: Sendable, Hashable, Codable, Identifiable {
    /// The article GID.
    public let id: ShopifyID
    /// The URL handle of the article.
    public let handle: String
    /// The handle of the blog the article belongs to.
    public let blogHandle: String
    /// The title in the context language.
    public let title: String
    /// When the article was published.
    public let publishedAt: Date
    /// The author's display name, if set.
    public let authorName: String?
    /// The article image, if any.
    public let image: ShopifyImage?
    /// The article body as HTML, rendered natively through `HTMLDocument`.
    public let contentHtml: String
    /// The article page on the web shop, if published there.
    public let onlineStoreUrl: URL?

    /// Creates an article.
    public init(
        id: ShopifyID,
        handle: String,
        blogHandle: String,
        title: String,
        publishedAt: Date,
        authorName: String?,
        image: ShopifyImage?,
        contentHtml: String,
        onlineStoreUrl: URL?
    ) {
        self.id = id
        self.handle = handle
        self.blogHandle = blogHandle
        self.title = title
        self.publishedAt = publishedAt
        self.authorName = authorName
        self.image = image
        self.contentHtml = contentHtml
        self.onlineStoreUrl = onlineStoreUrl
    }

    /// The article's body parsed into native blocks.
    public var document: HTMLDocument {
        HTMLDocument(html: contentHtml, baseURL: onlineStoreUrl)
    }

    // MARK: Codable

    private enum CodingKeys: String, CodingKey {
        case id, handle, title, publishedAt, authorV2, image, contentHtml, onlineStoreUrl, blog
    }

    /// The `authorV2 { name }` selection. Only the name is requested; the author's e-mail
    /// address is never selected.
    private struct Author: Codable {
        let name: String
    }

    /// Decodes the Storefront shape: `blog { handle }`, `authorV2 { name }` and an ISO 8601
    /// `publishedAt`.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(ShopifyID.self, forKey: .id)
        handle = try container.decode(String.self, forKey: .handle)
        blogHandle = try container.decode(BlogReference.self, forKey: .blog).handle
        title = try container.decode(String.self, forKey: .title)
        publishedAt = try ArticleCoding.decodeDate(from: container, forKey: .publishedAt)
        authorName = try container.decodeIfPresent(Author.self, forKey: .authorV2).map(\.name).flatMap(ArticleCoding.nonBlank)
        image = try container.decodeIfPresent(ShopifyImage.self, forKey: .image)
        contentHtml = try container.decode(String.self, forKey: .contentHtml)
        onlineStoreUrl = try container.decodeIfPresent(URL.self, forKey: .onlineStoreUrl)
    }

    /// Encodes the same shape `init(from:)` reads.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(handle, forKey: .handle)
        try container.encode(BlogReference(handle: blogHandle), forKey: .blog)
        try container.encode(title, forKey: .title)
        try container.encode(ArticleCoding.string(from: publishedAt), forKey: .publishedAt)
        try container.encodeIfPresent(authorName.map(Author.init(name:)), forKey: .authorV2)
        try container.encodeIfPresent(image, forKey: .image)
        try container.encode(contentHtml, forKey: .contentHtml)
        try container.encodeIfPresent(onlineStoreUrl, forKey: .onlineStoreUrl)
    }
}

// MARK: - Coding helpers

/// The `blog { handle }` selection of an article.
private struct BlogReference: Codable {
    let handle: String
}

/// Shared decoding rules of the article types.
enum ArticleCoding {
    /// Parses a Storefront `DateTime` (ISO 8601, with or without fractional seconds).
    static func date(from string: String) -> Date? {
        if let date = try? Date(string, strategy: Date.ISO8601FormatStyle()) {
            return date
        }
        return try? Date(string, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true))
    }

    /// Formats a date as a Storefront `DateTime`, e.g. `2026-08-29T21:16:35Z`.
    static func string(from date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle())
    }

    /// Decodes a `DateTime` member.
    static func decodeDate<Key: CodingKey>(from container: KeyedDecodingContainer<Key>, forKey key: Key) throws -> Date {
        let string = try container.decode(String.self, forKey: key)
        guard let date = date(from: string) else {
            throw DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: "The date is not ISO 8601.")
        }
        return date
    }

    /// `nil` for empty or blank text.
    static func nonBlank(_ text: String) -> String? {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
    }
}
