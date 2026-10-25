import Foundation

// MARK: - ContentRepository

/// Read access to blog articles in the current buyer context.
public protocol ContentRepository: Sendable {
    /// The newest articles of the blog with `blogHandle`; empty when the blog does not exist.
    ///
    /// - Parameters:
    ///   - blogHandle: The blog handle, e.g. `guides`.
    ///   - first: The number of articles (1 to 250).
    /// - Throws: `ShopifyError`.
    func articles(blogHandle: String, first: Int) async throws -> [ArticleSummary]

    /// The article with `handle` in the blog with `blogHandle`, or `nil` when either does not
    /// exist.
    ///
    /// - Throws: `ShopifyError`.
    func article(blogHandle: String, handle: String) async throws -> Article?
}

// MARK: - StorefrontContentRepository

/// `ContentRepository` backed by the Storefront `blog` queries.
public final class StorefrontContentRepository: ContentRepository {
    private let client: StorefrontClient
    private let contextProvider: any StorefrontContextProviding

    /// Creates a repository.
    ///
    /// - Parameters:
    ///   - client: The Storefront client.
    ///   - contextProvider: Supplies the buyer context (content language) of each call.
    public init(client: StorefrontClient, contextProvider: any StorefrontContextProviding) {
        self.client = client
        self.contextProvider = contextProvider
    }

    /// Loads the newest articles in the current context.
    public func articles(blogHandle: String, first: Int) async throws -> [ArticleSummary] {
        let context = await contextProvider.currentContext()
        let query = BlogArticlesQuery(blogHandle: blogHandle, first: first)
        return try await client.execute(query, context: context).blog?.articles.nodes ?? []
    }

    /// Loads one article in the current context.
    public func article(blogHandle: String, handle: String) async throws -> Article? {
        let context = await contextProvider.currentContext()
        let query = ArticleQuery(blogHandle: blogHandle, articleHandle: handle)
        return try await client.execute(query, context: context).blog?.articleByHandle
    }
}
