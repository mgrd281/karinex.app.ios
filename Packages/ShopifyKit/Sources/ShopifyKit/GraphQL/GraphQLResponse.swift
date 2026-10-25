import Foundation

// MARK: - GraphQLResponse

/// A decoded GraphQL response envelope: `{"data": ..., "errors": [...], "extensions": {...}}`.
///
/// `GraphQLClient` decodes `data` into the operation's `ResponseData` only when there are no
/// errors (see `GraphQLResponseEnvelope`). This type is the plain form for callers that want to
/// inspect a raw body themselves, such as tests or the fixture recorder: it always decodes
/// `data` as well.
public struct GraphQLResponse<ResponseData: Decodable & Sendable>: Sendable, Decodable {
    /// The `data` member, `nil` when absent or `null`.
    public let data: ResponseData?
    /// The top-level `errors`, empty when absent. A plain string (`"errors": "Not Found"`, as
    /// some Shopify endpoints send) becomes one error with that message.
    public let errors: [GraphQLErrorDetail]
    /// The `extensions` member (query cost, resolved context), if present.
    public let extensions: GraphQLResponseExtensions?

    /// Creates a response, e.g. in tests.
    public init(data: ResponseData?, errors: [GraphQLErrorDetail] = [], extensions: GraphQLResponseExtensions? = nil) {
        self.data = data
        self.errors = errors
        self.extensions = extensions
    }

    /// Decodes the envelope. A missing or `null` `errors` member decodes as an empty array.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: GraphQLResponseKeys.self)
        data = try container.decodeIfPresent(ResponseData.self, forKey: .data)
        errors = try GraphQLResponseKeys.decodeErrors(from: container)
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

/// The top-level members of a GraphQL response.
enum GraphQLResponseKeys: String, CodingKey {
    case data
    case errors
    case extensions

    /// Decodes `errors`: an array of error objects, or a plain message string, which some
    /// Shopify endpoints send (`"errors": "Not Found"`). Absent or `null` is no error.
    static func decodeErrors(from container: KeyedDecodingContainer<Self>) throws -> [GraphQLErrorDetail] {
        do {
            return try container.decodeIfPresent([GraphQLErrorDetail].self, forKey: .errors) ?? []
        } catch {
            guard let message = try? container.decode(String.self, forKey: .errors) else { throw error }
            return [GraphQLErrorDetail(message: message)]
        }
    }
}

/// The errors and extensions of a response, without `data`. Used where only the error codes
/// matter (retry decisions, HTTP 401 and 403 bodies).
struct GraphQLResponseHead: Decodable {
    let errors: [GraphQLErrorDetail]
    let extensions: GraphQLResponseExtensions?

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: GraphQLResponseKeys.self)
        errors = try GraphQLResponseKeys.decodeErrors(from: container)
        extensions = try? container.decodeIfPresent(GraphQLResponseExtensions.self, forKey: .extensions)
    }
}

/// A whole response decoded in one pass: `errors` and `extensions` first, then `data` only when
/// there are no errors, so a `data` member that does not fit `ResponseData` (for example the
/// partial data next to an error) never hides the error.
struct GraphQLResponseEnvelope<ResponseData: Decodable>: Decodable {
    /// Thrown when `data` does not decode, to tell it apart from a malformed envelope. The
    /// coding path of `underlying` starts at the `data` member.
    struct DataDecodingError: Error {
        let underlying: any Error
    }

    let errors: [GraphQLErrorDetail]
    let extensions: GraphQLResponseExtensions?
    /// `nil` when there are errors, or when `data` is absent or `null`.
    let data: ResponseData?

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: GraphQLResponseKeys.self)
        errors = try GraphQLResponseKeys.decodeErrors(from: container)
        extensions = try? container.decodeIfPresent(GraphQLResponseExtensions.self, forKey: .extensions)
        guard errors.isEmpty else {
            data = nil
            return
        }
        do {
            data = try container.decodeIfPresent(ResponseData.self, forKey: .data)
        } catch {
            throw DataDecodingError(underlying: error)
        }
    }
}
