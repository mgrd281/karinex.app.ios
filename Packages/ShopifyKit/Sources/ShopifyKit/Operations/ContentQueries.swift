import Foundation

// MARK: - BlogArticlesQuery

/// Loads the newest articles of a blog (Storefront `blog(handle:)` with `articles` sorted by
/// publication date, newest first).
public struct BlogArticlesQuery: GraphQLOperation {
    /// The largest page size the Storefront API accepts.
    public static let maximumPageSize = 250

    /// The operation variables.
    public struct Variables: Encodable, Sendable, Equatable {
        /// The blog handle, e.g. `guides`.
        public let blogHandle: String
        /// The number of articles, 1 to 250.
        public let first: Int
    }

    /// A blog with one page of articles.
    public struct Blog: Decodable, Sendable, Equatable {
        /// The articles.
        public let articles: Connection<ArticleSummary>
    }

    /// The `data` of the response.
    public struct ResponseData: Decodable, Sendable, Equatable {
        /// The blog, or `nil` when no blog has the handle.
        public let blog: Blog?
    }

    /// `BlogArticles`.
    public static let operationName = "BlogArticles"
    /// A query.
    public static let kind = GraphQLOperationKind.query
    /// The operation followed by `ArticleSummaryFields` and `ImageFields`.
    public static let document = StorefrontFragments.document(
        """
        query BlogArticles($blogHandle: String!, $first: Int!) {
          blog(handle: $blogHandle) {
            articles(first: $first, sortKey: PUBLISHED_AT, reverse: true) {
              nodes {
                ...ArticleSummaryFields
              }
            }
          }
        }
        """,
        fragments: [StorefrontFragments.articleSummary, StorefrontFragments.image]
    )

    /// The variables of this call.
    public let variables: Variables

    /// Creates the query; `first` is clamped to 1...250.
    public init(blogHandle: String, first: Int) {
        variables = Variables(blogHandle: blogHandle, first: min(max(first, 1), Self.maximumPageSize))
    }
}

// MARK: - ArticleQuery

/// Loads one article with its HTML body (Storefront `blog(handle:).articleByHandle`).
///
/// Only the author's name is selected, never the author's e-mail address.
public struct ArticleQuery: GraphQLOperation {
    /// The operation variables.
    public struct Variables: Encodable, Sendable, Equatable {
        /// The blog handle.
        public let blogHandle: String
        /// The article handle.
        public let articleHandle: String
    }

    /// A blog with the requested article.
    public struct Blog: Decodable, Sendable, Equatable {
        /// The article, or `nil` when the blog has no article with the handle.
        public let articleByHandle: Article?
    }

    /// The `data` of the response.
    public struct ResponseData: Decodable, Sendable, Equatable {
        /// The blog, or `nil` when no blog has the handle.
        public let blog: Blog?
    }

    /// `Article`.
    public static let operationName = "Article"
    /// A query.
    public static let kind = GraphQLOperationKind.query
    /// The operation followed by `ImageFields`.
    public static let document = StorefrontFragments.document(
        """
        query Article($blogHandle: String!, $articleHandle: String!) {
          blog(handle: $blogHandle) {
            articleByHandle(handle: $articleHandle) {
              id
              handle
              title
              publishedAt
              contentHtml
              onlineStoreUrl
              authorV2 {
                name
              }
              image {
                ...ImageFields
              }
              blog {
                handle
              }
            }
          }
        }
        """,
        fragments: [StorefrontFragments.image]
    )

    /// The variables of this call.
    public let variables: Variables

    /// Creates the query.
    public init(blogHandle: String, articleHandle: String) {
        variables = Variables(blogHandle: blogHandle, articleHandle: articleHandle)
    }
}
