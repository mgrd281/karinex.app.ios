import Foundation

// MARK: - GraphQLOperationKind

/// Whether an operation reads (`query`) or writes (`mutation`).
///
/// The kind drives the retry rules of `GraphQLClient`: queries are idempotent and are retried
/// on transient failures, while a mutation that may already have executed is never replayed.
public enum GraphQLOperationKind: String, Sendable, Hashable, CaseIterable {
    /// A read-only operation. Retried on transient failures and de-duplicated while in flight.
    case query
    /// A write operation. Retried only when the server provably rejected it before execution
    /// (HTTP 429 or a GraphQL `THROTTLED` error), never de-duplicated.
    case mutation
}

// MARK: - GraphQLOperation

/// A typed GraphQL operation: its document, its variables and the shape of its `data`.
///
/// Conforming types are small value types that carry the variables; the document and the
/// operation name are static because they never change between calls.
///
/// ```swift
/// struct ShopNameQuery: GraphQLOperation {
///     struct ResponseData: Decodable, Sendable {
///         struct Shop: Decodable, Sendable { let name: String }
///         let shop: Shop
///     }
///
///     static let operationName = "ShopName"
///     static let kind = GraphQLOperationKind.query
///     static let document = "query ShopName { shop { name } }"
/// }
/// ```
///
/// Documents are complete GraphQL: the operation first, then every fragment it uses (and no
/// unused fragment, which the server rejects). They are written without `@inContext`; the
/// Storefront client injects the directive per call with `ContextInjector`, so the same
/// document also works against the Customer Account API, which has no such directive.
public protocol GraphQLOperation: Sendable {
    /// The variables sent with the operation. Defaults to `EmptyVariables`.
    associatedtype Variables: Encodable & Sendable = EmptyVariables
    /// The type the `data` member of the response decodes into.
    associatedtype ResponseData: Decodable & Sendable

    /// The operation name as written in `document`, sent as `operationName`.
    static var operationName: String { get }
    /// Whether the operation is a query or a mutation.
    static var kind: GraphQLOperationKind { get }
    /// The complete GraphQL document: the operation followed by the fragments it uses.
    static var document: String { get }
    /// The variables of this call.
    var variables: Variables { get }
}

// MARK: - EmptyVariables

/// The variables of an operation that declares none. Encodes as `{}`.
public struct EmptyVariables: Encodable, Sendable, Equatable, Hashable {
    /// Creates the empty variables value.
    public init() {}
}

extension GraphQLOperation where Variables == EmptyVariables {
    /// Operations without variables send `{}`.
    public var variables: EmptyVariables {
        EmptyVariables()
    }
}
