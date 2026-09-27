import Foundation

// MARK: - GraphQLResponse

/// A decoded GraphQL response envelope: `{"data": ..., "errors": [...], "extensions": {...}}`.
///
/// `GraphQLClient` decodes the envelope in two steps: first `errors` and `extensions`, and only
/// when there are no errors the `data` member into the operation's `ResponseData`. This type is
/// the one-step form for callers that want to inspect a raw body themselves, such as tests or
/// the fixture recorder.
public struct GraphQLResponse<ResponseData: Decodable & Sendable>: Sendable, Decodable {
    /// The `data` member, `nil` when absent or `null`.
    public let data: ResponseData?
    /// The top-level `errors`, empty when absent.
    public let errors: [GraphQLErrorDetail]
    /// The `extensions` member (query cost, resolved context), if present.
    public let extensions: GraphQLResponseExtensions?

    /// Creates a response, e.g. in tests.
    public init(data: ResponseData?, errors: [GraphQLErrorDetail] = [], extensions: GraphQLResponseExtensions? = nil) {
        self.data = data
        self.errors = errors
        self.extensions = extensions
    }

    private enum CodingKeys: String, CodingKey {
        case data
        case errors
        case extensions
    }

    /// Decodes the envelope. A missing or `null` `errors` member decodes as an empty array.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        data = try container.decodeIfPresent(ResponseData.self, forKey: .data)
        errors = try container.decodeIfPresent([GraphQLErrorDetail].self, forKey: .errors) ?? []
        extensions = try? container.decodeIfPresent(GraphQLResponseExtensions.self, forKey: .extensions)
    }
}

// MARK: - GraphQLResponseExtensions

/// The `extensions` member of a Shopify GraphQL response.
public struct GraphQLResponseExtensions: Sendable, Equatable, Hashable, Codable {
    /// The query cost, if reported.
    public let cost: GraphQLQueryCost?
    /// The buyer context Shopify resolved for the request (from `@inContext`), if reported.
    public let context: GraphQLResponseContext?

    /// Creates the extensions, e.g. in tests.
    public init(cost: GraphQLQueryCost? = nil, context: GraphQLResponseContext? = nil) {
        self.cost = cost
        self.context = context
    }

    private enum CodingKeys: String, CodingKey {
        case cost
        case context
    }

    /// Decodes the extensions, ignoring members of unexpected shape.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cost = try? container.decodeIfPresent(GraphQLQueryCost.self, forKey: .cost)
        context = try? container.decodeIfPresent(GraphQLResponseContext.self, forKey: .context)
    }
}

// MARK: - GraphQLQueryCost

/// The `extensions.cost` member: how expensive the operation was.
///
/// The tokenless Storefront API reports only `requestedQueryCost`; other APIs also report
/// `actualQueryCost`. Values are decoded from integers or floating point numbers.
public struct GraphQLQueryCost: Sendable, Equatable, Hashable, Codable {
    /// The cost Shopify computed from the query before running it.
    public let requestedQueryCost: Int?
    /// The cost of the executed query, if reported.
    public let actualQueryCost: Int?

    /// Creates a cost value.
    public init(requestedQueryCost: Int?, actualQueryCost: Int? = nil) {
        self.requestedQueryCost = requestedQueryCost
        self.actualQueryCost = actualQueryCost
    }

    private enum CodingKeys: String, CodingKey {
        case requestedQueryCost
        case actualQueryCost
    }

    /// Decodes both members leniently from integer or floating point JSON numbers.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        requestedQueryCost = Self.decodeNumber(container, .requestedQueryCost)
        actualQueryCost = Self.decodeNumber(container, .actualQueryCost)
    }

    /// Encodes the members that are present.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(requestedQueryCost, forKey: .requestedQueryCost)
        try container.encodeIfPresent(actualQueryCost, forKey: .actualQueryCost)
    }

    private static func decodeNumber(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Int? {
        if let integer = try? container.decodeIfPresent(Int.self, forKey: key) {
            return integer
        }
        guard let double = try? container.decodeIfPresent(Double.self, forKey: key), double.isFinite,
              double >= Double(Int.min), double <= Double(Int.max)
        else { return nil }
        return Int(double.rounded())
    }
}

// MARK: - GraphQLResponseContext

/// The `extensions.context` member of a Storefront response: the country and language Shopify
/// actually used, e.g. `{"country": "DE", "language": "DE"}`.
public struct GraphQLResponseContext: Sendable, Equatable, Hashable, Codable {
    /// The resolved country.
    public let country: CountryCode?
    /// The resolved content language.
    public let language: LanguageCode?

    /// Creates a context value.
    public init(country: CountryCode?, language: LanguageCode?) {
        self.country = country
        self.language = language
    }
}

// MARK: - Internal envelopes

/// The part of a response that is decoded before `data`: errors and extensions.
struct GraphQLResponseHead: Decodable {
    let errors: [GraphQLErrorDetail]
    let extensions: GraphQLResponseExtensions?

    private enum CodingKeys: String, CodingKey {
        case errors
        case extensions
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        errors = try container.decodeIfPresent([GraphQLErrorDetail].self, forKey: .errors) ?? []
        extensions = try? container.decodeIfPresent(GraphQLResponseExtensions.self, forKey: .extensions)
    }
}

/// The `data` member alone, decoded only when the response has no errors.
struct GraphQLDataEnvelope<ResponseData: Decodable>: Decodable {
    let data: ResponseData?
}
