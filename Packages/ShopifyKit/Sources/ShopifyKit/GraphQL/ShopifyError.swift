import Core
import Foundation

// MARK: - ShopifyError

/// The typed failure of every Shopify API call made through `GraphQLClient`.
///
/// Mapping rules:
/// - no HTTP response: `.network` (offline, timeout, cancellation, TLS and so on),
/// - HTTP 401 or 403: `.accessDenied(requiredAccess: nil)`,
/// - HTTP 429 once retries are exhausted: `.throttled`,
/// - any other non-2xx status: `.http(statusCode:)`,
/// - a top-level GraphQL error with code `ACCESS_DENIED`: `.accessDenied(requiredAccess:)`,
///   with `THROTTLED`: `.throttled`, anything else: `.graphQL(errors)`. Any top-level error
///   fails the whole call; partial data is never returned,
/// - a `data` member that does not decode: `.decoding("<Type>: <codingPath>")`, which never
///   contains payload content,
/// - `userErrors` of a mutation payload: `.userErrors` (see `UserErrorsPayload`),
/// - a resource that must exist but does not: `.notFound`.
public enum ShopifyError: Error, Sendable, Equatable {
    /// No HTTP response was received.
    case network(NetworkError)
    /// The request lacks permission. `requiredAccess` names the missing scope when Shopify
    /// reports it.
    case accessDenied(requiredAccess: String?)
    /// Shopify rate limited the request and retries did not help.
    case throttled
    /// Shopify reported GraphQL errors (for example a validation error).
    case graphQL([GraphQLErrorDetail])
    /// A mutation was rejected with user errors, for example an invalid cart line.
    case userErrors([UserError])
    /// The requested resource does not exist.
    case notFound
    /// The response could not be decoded. The associated value names the type and coding path.
    case decoding(String)
    /// Shopify answered with an unexpected HTTP status.
    case http(statusCode: Int)

    /// Whether the failure is caused by missing or poor connectivity, so the UI should show
    /// the offline state rather than an error.
    public var isConnectivityProblem: Bool {
        if case let .network(error) = self {
            return error.isConnectivityProblem
        }
        return false
    }

    /// Whether the call was cancelled by the caller (no error UI needed).
    public var isCancellation: Bool {
        self == .network(.cancelled)
    }

    /// Whether trying again later can reasonably succeed without changing the request.
    public var isTransient: Bool {
        switch self {
        case let .network(error):
            error != .cancelled && error != .invalidResponse
        case .throttled:
            true
        case let .http(statusCode):
            statusCode == 408 || statusCode >= 500
        case let .graphQL(errors):
            errors.contains { $0.code == GraphQLErrorDetail.Code.internalServerError }
        case .accessDenied, .userErrors, .notFound, .decoding:
            false
        }
    }

    /// A log-safe summary, e.g. `http(503)` or `userErrors(INVALID)`. Contains codes only,
    /// never messages or field values.
    public var logDescription: String {
        switch self {
        case let .network(error):
            "network(\(error))"
        case .accessDenied:
            "accessDenied"
        case .throttled:
            "throttled"
        case let .graphQL(errors):
            "graphQL(\(errors.map { $0.code ?? "unknown" }.joined(separator: ",")))"
        case let .userErrors(errors):
            "userErrors(\(errors.map { $0.code?.rawValue ?? "unknown" }.joined(separator: ",")))"
        case .notFound:
            "notFound"
        case .decoding:
            "decoding"
        case let .http(statusCode):
            "http(\(statusCode))"
        }
    }
}

// MARK: - UserError

/// A user error of a mutation payload (`CartUserError` and friends): `{field, message, code}`.
///
/// `message` is localized by Shopify for the context language and may be shown to customers.
public struct UserError: Sendable, Equatable, Hashable, Codable {
    /// The path to the input field that caused the error, e.g. `["input", "lines", "0", "merchandiseId"]`.
    public let field: [String]?
    /// The localized error message.
    public let message: String
    /// The error code, if Shopify sent one.
    public let code: UserErrorCode?

    /// Creates a user error, e.g. in tests.
    public init(field: [String]?, message: String, code: UserErrorCode?) {
        self.field = field
        self.message = message
        self.code = code
    }
}

// MARK: - UserErrorCode

/// Error codes of Storefront user errors (`CartErrorCode` in API 2026-07 plus a few cart
/// warning codes the app treats like errors). Unknown values decode as `.unknown(rawValue)`,
/// so a new code from Shopify never breaks decoding.
public enum UserErrorCode: Sendable, Hashable, Codable, RawRepresentable, CustomStringConvertible {
    /// The input value is invalid (for example a merchandise ID that does not exist).
    case invalid
    /// The input value must be greater (for example a quantity below 1).
    case lessThan
    /// The quantity exceeds the maximum allowed.
    case maximumExceeded
    /// The quantity is below the minimum.
    case minimumNotMet
    /// The quantity is not a multiple of the required increment.
    case invalidIncrement
    /// Not enough stock for the requested quantity.
    case merchandiseNotEnoughStock
    /// The merchandise is out of stock.
    case merchandiseOutOfStock
    /// The merchandise line is invalid.
    case invalidMerchandiseLine
    /// The merchandise cannot be combined with the cart.
    case merchandiseNotApplicable
    /// The discount code is missing.
    case missingDiscountCode
    /// The note is missing.
    case missingNote
    /// The note is too long.
    case noteTooLong
    /// The delivery group is invalid.
    case invalidDeliveryGroup
    /// The delivery option is invalid.
    case invalidDeliveryOption
    /// Delivery groups are still being computed.
    case pendingDeliveryGroups
    /// Cart metafields are invalid.
    case invalidMetafields
    /// A customer access token is required.
    case missingCustomerAccessToken
    /// The company location is invalid.
    case invalidCompanyLocation
    /// The variant can only be bought with a selling plan.
    case variantRequiresSellingPlan
    /// The selling plan does not apply.
    case sellingPlanNotApplicable
    /// The cart has too many lines.
    case cartTooLarge
    /// Shopify could not process the request right now.
    case serviceUnavailable
    /// A validation function rejected the cart.
    case validationCustom
    /// A code this version of the app does not know.
    case unknown(String)

    /// Every known case, used to map raw codes back to cases.
    private static let knownCases: [UserErrorCode] = [
        .invalid, .lessThan, .maximumExceeded, .minimumNotMet, .invalidIncrement, .merchandiseNotEnoughStock,
        .merchandiseOutOfStock, .invalidMerchandiseLine, .merchandiseNotApplicable, .missingDiscountCode, .missingNote,
        .noteTooLong, .invalidDeliveryGroup, .invalidDeliveryOption, .pendingDeliveryGroups, .invalidMetafields,
        .missingCustomerAccessToken, .invalidCompanyLocation, .variantRequiresSellingPlan, .sellingPlanNotApplicable,
        .cartTooLarge, .serviceUnavailable, .validationCustom,
    ]

    private static let casesByRawValue: [String: UserErrorCode] = Dictionary(
        uniqueKeysWithValues: knownCases.map { ($0.rawValue, $0) }
    )

    /// Maps a Shopify code such as `INVALID` to a case; unknown codes become `.unknown`.
    public init(rawValue: String) {
        self = Self.casesByRawValue[rawValue] ?? .unknown(rawValue)
    }

    /// The Shopify code, e.g. `INVALID`.
    public var rawValue: String {
        switch self {
        case .invalid: "INVALID"
        case .lessThan: "LESS_THAN"
        case .maximumExceeded: "MAXIMUM_EXCEEDED"
        case .minimumNotMet: "MINIMUM_NOT_MET"
        case .invalidIncrement: "INVALID_INCREMENT"
        case .merchandiseNotEnoughStock: "MERCHANDISE_NOT_ENOUGH_STOCK"
        case .merchandiseOutOfStock: "MERCHANDISE_OUT_OF_STOCK"
        case .invalidMerchandiseLine: "INVALID_MERCHANDISE_LINE"
        case .merchandiseNotApplicable: "MERCHANDISE_NOT_APPLICABLE"
        case .missingDiscountCode: "MISSING_DISCOUNT_CODE"
        case .missingNote: "MISSING_NOTE"
        case .noteTooLong: "NOTE_TOO_LONG"
        case .invalidDeliveryGroup: "INVALID_DELIVERY_GROUP"
        case .invalidDeliveryOption: "INVALID_DELIVERY_OPTION"
        case .pendingDeliveryGroups: "PENDING_DELIVERY_GROUPS"
        case .invalidMetafields: "INVALID_METAFIELDS"
        case .missingCustomerAccessToken: "MISSING_CUSTOMER_ACCESS_TOKEN"
        case .invalidCompanyLocation: "INVALID_COMPANY_LOCATION"
        case .variantRequiresSellingPlan: "VARIANT_REQUIRES_SELLING_PLAN"
        case .sellingPlanNotApplicable: "SELLING_PLAN_NOT_APPLICABLE"
        case .cartTooLarge: "CART_TOO_LARGE"
        case .serviceUnavailable: "SERVICE_UNAVAILABLE"
        case .validationCustom: "VALIDATION_CUSTOM"
        case let .unknown(value): value
        }
    }

    /// The Shopify code.
    public var description: String {
        rawValue
    }

    /// Decodes any string.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(rawValue: container.decode(String.self))
    }

    /// Encodes the Shopify code as a string.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

// MARK: - UserErrorsPayload

/// A mutation payload that reports `userErrors`.
public protocol UserErrorsPayload {
    /// The user errors of the mutation; empty on success.
    var userErrors: [UserError] { get }
}

extension UserErrorsPayload {
    /// Returns `self` when there are no user errors, otherwise throws
    /// `ShopifyError.userErrors` so repositories surface them as typed errors.
    @discardableResult
    public func throwingUserErrors() throws -> Self {
        guard userErrors.isEmpty else {
            throw ShopifyError.userErrors(userErrors)
        }
        return self
    }
}
