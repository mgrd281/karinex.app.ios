import Foundation

// MARK: - LegalText

/// A legal text from Shopify: a shop policy (`ShopPolicy`) or an online store page (`Page`).
/// The body is HTML and is rendered natively by the app.
public struct LegalText: Sendable, Hashable, Decodable, Identifiable {
    /// The policy or page GID.
    public let id: ShopifyID
    /// The title in the context language.
    public let title: String
    /// The handle, e.g. `terms-of-service` or `rechtliche-hinweise`.
    public let handle: String
    /// The HTML body.
    public let body: String
    /// When the page was last changed; policies carry no date.
    public let updatedAt: Date?
    /// The web URL, if Shopify returns one.
    public let url: URL?

    /// Creates a legal text.
    public init(id: ShopifyID, title: String, handle: String, body: String, updatedAt: Date?, url: URL?) {
        self.id = id
        self.title = title
        self.handle = handle
        self.body = body
        self.updatedAt = updatedAt
        self.url = url
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, handle, body, updatedAt, url, onlineStoreUrl
    }

    /// Decodes both shapes: policies (`url`) and pages (`updatedAt`, `onlineStoreUrl`).
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(ShopifyID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        handle = try container.decode(String.self, forKey: .handle)
        body = try container.decodeIfPresent(String.self, forKey: .body) ?? ""
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt).flatMap(ArticleCoding.date(from:))
        url = try container.decodeIfPresent(URL.self, forKey: .url) ?? container.decodeIfPresent(URL.self, forKey: .onlineStoreUrl)
    }
}

// MARK: - ShopPolicies

/// The shop policies; `nil` for a policy the store has not written.
public struct ShopPolicies: Sendable, Hashable, Decodable {
    /// Impressum (`Shop.legalNotice`, Settings > Policies > Impressum in the Shopify admin).
    public let legalNotice: LegalText?
    /// Datenschutzerklärung.
    public let privacyPolicy: LegalText?
    /// Rückerstattung.
    public let refundPolicy: LegalText?
    /// Versand.
    public let shippingPolicy: LegalText?
    /// AGB.
    public let termsOfService: LegalText?

    /// Creates the policies.
    public init(
        privacyPolicy: LegalText?,
        refundPolicy: LegalText?,
        shippingPolicy: LegalText?,
        termsOfService: LegalText?,
        legalNotice: LegalText? = nil
    ) {
        self.legalNotice = legalNotice
        self.privacyPolicy = privacyPolicy
        self.refundPolicy = refundPolicy
        self.shippingPolicy = shippingPolicy
        self.termsOfService = termsOfService
    }
}

// MARK: - ShopPoliciesQuery

/// Loads the shop policies (Storefront `shop`).
public struct ShopPoliciesQuery: GraphQLOperation {
    /// The `data` of the response.
    public struct ResponseData: Decodable, Sendable, Equatable {
        /// The shop with its policies.
        public let shop: ShopPolicies
    }

    /// `ShopPolicies`.
    public static let operationName = "ShopPolicies"
    /// A query.
    public static let kind = GraphQLOperationKind.query
    /// The operation and `ShopPolicyFields`.
    public static let document = StorefrontFragments.document(
        """
        query ShopPolicies {
          shop {
            legalNotice {
              ...ShopPolicyFields
            }
            privacyPolicy {
              ...ShopPolicyFields
            }
            refundPolicy {
              ...ShopPolicyFields
            }
            shippingPolicy {
              ...ShopPolicyFields
            }
            termsOfService {
              ...ShopPolicyFields
            }
          }
        }
        """,
        fragments: [
            """
            fragment ShopPolicyFields on ShopPolicy {
              id
              title
              handle
              body
              url
            }
            """,
        ]
    )

    /// Creates the query.
    public init() {}
}

// MARK: - PageByHandleQuery

/// Loads an online store page (Storefront `page(handle:)`), e.g. the Impressum.
public struct PageByHandleQuery: GraphQLOperation {
    /// The operation variables.
    public struct Variables: Encodable, Sendable, Equatable {
        /// The page handle.
        public let handle: String
    }

    /// The `data` of the response.
    public struct ResponseData: Decodable, Sendable, Equatable {
        /// The page, `nil` when no page has the handle.
        public let page: LegalText?
    }

    /// `PageByHandle`.
    public static let operationName = "PageByHandle"
    /// A query.
    public static let kind = GraphQLOperationKind.query
    /// The operation.
    public static let document = """
        query PageByHandle($handle: String!) {
          page(handle: $handle) {
            id
            title
            handle
            body
            updatedAt
            onlineStoreUrl
          }
        }

        """

    /// The variables of this call.
    public let variables: Variables

    /// Creates the query.
    public init(handle: String) {
        variables = Variables(handle: handle)
    }
}

// MARK: - LegalContentRepository

/// Loads the legal texts in the buyer's language.
public protocol LegalContentRepository: Sendable {
    /// The shop policies.
    func policies() async throws -> ShopPolicies
    /// The page with `handle`, or `nil`.
    func page(handle: String) async throws -> LegalText?
}

/// `LegalContentRepository` on the Storefront API.
public final class StorefrontLegalContentRepository: LegalContentRepository {
    private let client: StorefrontClient
    private let contextProvider: any StorefrontContextProviding

    /// Creates the repository.
    public init(client: StorefrontClient, contextProvider: any StorefrontContextProviding) {
        self.client = client
        self.contextProvider = contextProvider
    }

    public func policies() async throws -> ShopPolicies {
        let context = await contextProvider.currentContext()
        return try await client.execute(ShopPoliciesQuery(), context: context).shop
    }

    public func page(handle: String) async throws -> LegalText? {
        let context = await contextProvider.currentContext()
        return try await client.execute(PageByHandleQuery(handle: handle), context: context).page
    }
}
