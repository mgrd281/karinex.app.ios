import Foundation

// MARK: - CartMutationPayload

/// The payload every cart mutation returns: `cart`, `userErrors` and `warnings`.
///
/// Call `throwingUserErrors()` to turn `userErrors` into `ShopifyError.userErrors`.
public struct CartMutationPayload: Decodable, Sendable, Equatable, UserErrorsPayload {
    /// The cart after the mutation, `nil` when user errors prevented it.
    public let cart: Cart?
    /// Reasons the input was rejected; empty on success.
    public let userErrors: [UserError]
    /// Non-blocking warnings, e.g. `DISCOUNT_NOT_FOUND`.
    public let warnings: [CartWarning]

    /// Creates a payload, e.g. in tests.
    public init(cart: Cart?, userErrors: [UserError], warnings: [CartWarning]) {
        self.cart = cart
        self.userErrors = userErrors
        self.warnings = warnings
    }
}

// MARK: - CartMutation

/// A cart mutation whose response carries one `CartMutationPayload`.
///
/// Every cart mutation document selects `cart { ...CartFields }`, `userErrors {field message
/// code}` and `warnings {code message target}`.
public protocol CartMutation: GraphQLOperation where ResponseData: CartMutationResponse {}

/// The `data` of a cart mutation response.
public protocol CartMutationResponse: Decodable, Sendable {
    /// The mutation payload; `nil` only if Shopify could not run the mutation at all.
    var payload: CartMutationPayload? { get }
}

extension CartMutation {
    /// The selection of every cart mutation payload, indented for the mutation documents.
    static var payloadSelection: String {
        """
            cart {
              ...CartFields
            }
            userErrors {
              field
              message
              code
            }
            warnings {
              code
              message
              target
            }
        """
    }

    /// The complete document of a cart mutation: `mutation <name>(<signature>) { <field> {
    /// payload } }` followed by `CartFields` and its dependencies.
    static func mutationDocument(name: String, signature: String, field: String) -> String {
        StorefrontFragments.document(
            "mutation \(name)(\(signature)) {\n  \(field) {\n\(payloadSelection)\n  }\n}",
            fragments: StorefrontFragments.cartDependencies
        )
    }
}

// MARK: - CartQuery

/// Loads a cart by its ID (Storefront `cart(id:)`).
///
/// `cart` is `null` when the ID is unknown, the cart expired or it was completed (converted
/// into an order), so the app creates a new cart lazily.
public struct CartQuery: GraphQLOperation {
    /// The operation variables.
    public struct Variables: Encodable, Sendable, Equatable {
        /// The cart GID.
        public let id: ShopifyID
    }

    /// The `data` of the response.
    public struct ResponseData: Decodable, Sendable, Equatable {
        /// The cart, or `nil` when it no longer exists.
        public let cart: Cart?
    }

    /// `Cart`.
    public static let operationName = "Cart"
    /// A query.
    public static let kind = GraphQLOperationKind.query
    /// The operation followed by `CartFields` and its dependencies.
    public static let document = StorefrontFragments.document(
        """
        query Cart($id: ID!) {
          cart(id: $id) {
            ...CartFields
          }
        }
        """,
        fragments: StorefrontFragments.cartDependencies
    )

    /// The variables of this call.
    public let variables: Variables

    /// Creates the query for the cart `id`.
    public init(id: ShopifyID) {
        variables = Variables(id: id)
    }
}

// MARK: - CartBuyerIdentityInput

/// The Storefront `CartBuyerIdentityInput` subset the app sends. `nil` members are omitted.
public struct CartBuyerIdentityInput: Encodable, Sendable, Equatable {
    /// The buyer's country, which determines the market prices.
    public let countryCode: CountryCode?
    /// The buyer's e-mail address (Phase 2 accounts). Personal data: never log it.
    public let email: String?
    /// A customer access token that associates the cart with a signed-in customer (Phase 2).
    /// A secret: never log it.
    public let customerAccessToken: String?

    /// Creates a buyer identity input.
    public init(countryCode: CountryCode?, email: String? = nil, customerAccessToken: String? = nil) {
        self.countryCode = countryCode
        self.email = email
        self.customerAccessToken = customerAccessToken
    }
}

// MARK: - CartCreateMutation

/// Creates a cart (Storefront `cartCreate`) with its first lines, the buyer's country and the
/// app's cart attributes.
public struct CartCreateMutation: CartMutation {
    /// The operation variables: `{ "input": CartInput }`.
    public struct Variables: Encodable, Sendable, Equatable {
        /// The `CartInput`.
        public let input: CartInput
    }

    /// The Storefront `CartInput` subset the app sends. `nil` members are omitted.
    public struct CartInput: Encodable, Sendable, Equatable {
        /// The initial lines.
        public let lines: [CartLineInput]
        /// The buyer identity (country), if known.
        public let buyerIdentity: CartBuyerIdentityInput?
        /// Cart attributes such as `app_platform`, if any.
        public let attributes: [AttributeInput]?
    }

    /// The `cartCreate` payload.
    public typealias Payload = CartMutationPayload

    /// The `data` of the response.
    public struct ResponseData: CartMutationResponse, Equatable {
        /// The payload; `nil` only if Shopify could not run the mutation at all.
        public let cartCreate: CartMutationPayload?

        /// The payload.
        public var payload: CartMutationPayload? {
            cartCreate
        }
    }

    /// `CartCreate`.
    public static let operationName = "CartCreate"
    /// A mutation.
    public static let kind = GraphQLOperationKind.mutation
    /// The mutation followed by `CartFields` and its dependencies.
    public static let document = mutationDocument(name: operationName, signature: "$input: CartInput!", field: "cartCreate(input: $input)")

    /// The variables of this call.
    public let variables: Variables

    /// Creates the mutation.
    ///
    /// - Parameters:
    ///   - lines: The initial cart lines.
    ///   - countryCode: The buyer's country, sent as `buyerIdentity.countryCode`, or `nil`.
    ///   - attributes: Cart attributes; an empty list is not sent.
    public init(lines: [CartLineInput], countryCode: CountryCode?, attributes: [AttributeInput] = []) {
        variables = Variables(
            input: CartInput(
                lines: lines,
                buyerIdentity: countryCode.map { CartBuyerIdentityInput(countryCode: $0) },
                attributes: attributes.isEmpty ? nil : attributes
            )
        )
    }
}

// MARK: - CartLinesAddMutation

/// Adds lines to a cart (Storefront `cartLinesAdd`). Adding a variant that is already in the
/// cart increases that line's quantity.
public struct CartLinesAddMutation: CartMutation {
    /// The operation variables.
    public struct Variables: Encodable, Sendable, Equatable {
        /// The cart GID.
        public let cartId: ShopifyID
        /// The lines to add.
        public let lines: [CartLineInput]
    }

    /// The `data` of the response.
    public struct ResponseData: CartMutationResponse, Equatable {
        /// The payload.
        public let cartLinesAdd: CartMutationPayload?

        /// The payload.
        public var payload: CartMutationPayload? {
            cartLinesAdd
        }
    }

    /// `CartLinesAdd`.
    public static let operationName = "CartLinesAdd"
    /// A mutation.
    public static let kind = GraphQLOperationKind.mutation
    /// The mutation followed by `CartFields` and its dependencies.
    public static let document = mutationDocument(
        name: operationName,
        signature: "$cartId: ID!, $lines: [CartLineInput!]!",
        field: "cartLinesAdd(cartId: $cartId, lines: $lines)"
    )

    /// The variables of this call.
    public let variables: Variables

    /// Creates the mutation.
    public init(cartID: ShopifyID, lines: [CartLineInput]) {
        variables = Variables(cartId: cartID, lines: lines)
    }
}

// MARK: - CartLinesUpdateMutation

/// Changes the quantities of cart lines (Storefront `cartLinesUpdate`). A quantity of zero
/// removes the line.
public struct CartLinesUpdateMutation: CartMutation {
    /// The operation variables.
    public struct Variables: Encodable, Sendable, Equatable {
        /// The cart GID.
        public let cartId: ShopifyID
        /// The line updates.
        public let lines: [CartLineUpdateInput]
    }

    /// The `data` of the response.
    public struct ResponseData: CartMutationResponse, Equatable {
        /// The payload.
        public let cartLinesUpdate: CartMutationPayload?

        /// The payload.
        public var payload: CartMutationPayload? {
            cartLinesUpdate
        }
    }

    /// `CartLinesUpdate`.
    public static let operationName = "CartLinesUpdate"
    /// A mutation.
    public static let kind = GraphQLOperationKind.mutation
    /// The mutation followed by `CartFields` and its dependencies.
    public static let document = mutationDocument(
        name: operationName,
        signature: "$cartId: ID!, $lines: [CartLineUpdateInput!]!",
        field: "cartLinesUpdate(cartId: $cartId, lines: $lines)"
    )

    /// The variables of this call.
    public let variables: Variables

    /// Creates the mutation.
    public init(cartID: ShopifyID, lines: [CartLineUpdateInput]) {
        variables = Variables(cartId: cartID, lines: lines)
    }
}

// MARK: - CartLinesRemoveMutation

/// Removes lines from a cart (Storefront `cartLinesRemove`).
public struct CartLinesRemoveMutation: CartMutation {
    /// The operation variables.
    public struct Variables: Encodable, Sendable, Equatable {
        /// The cart GID.
        public let cartId: ShopifyID
        /// The GIDs of the lines to remove.
        public let lineIds: [ShopifyID]
    }

    /// The `data` of the response.
    public struct ResponseData: CartMutationResponse, Equatable {
        /// The payload.
        public let cartLinesRemove: CartMutationPayload?

        /// The payload.
        public var payload: CartMutationPayload? {
            cartLinesRemove
        }
    }

    /// `CartLinesRemove`.
    public static let operationName = "CartLinesRemove"
    /// A mutation.
    public static let kind = GraphQLOperationKind.mutation
    /// The mutation followed by `CartFields` and its dependencies.
    public static let document = mutationDocument(
        name: operationName,
        signature: "$cartId: ID!, $lineIds: [ID!]!",
        field: "cartLinesRemove(cartId: $cartId, lineIds: $lineIds)"
    )

    /// The variables of this call.
    public let variables: Variables

    /// Creates the mutation.
    public init(cartID: ShopifyID, lineIDs: [ShopifyID]) {
        variables = Variables(cartId: cartID, lineIds: lineIDs)
    }
}

// MARK: - CartDiscountCodesUpdateMutation

/// Replaces the discount codes of a cart (Storefront `cartDiscountCodesUpdate`). An empty
/// list removes every code. Unknown codes stay on the cart with `applicable: false` and a
/// `DISCOUNT_*` warning.
public struct CartDiscountCodesUpdateMutation: CartMutation {
    /// The operation variables.
    public struct Variables: Encodable, Sendable, Equatable {
        /// The cart GID.
        public let cartId: ShopifyID
        /// The complete list of codes.
        public let discountCodes: [String]
    }

    /// The `data` of the response.
    public struct ResponseData: CartMutationResponse, Equatable {
        /// The payload.
        public let cartDiscountCodesUpdate: CartMutationPayload?

        /// The payload.
        public var payload: CartMutationPayload? {
            cartDiscountCodesUpdate
        }
    }

    /// `CartDiscountCodesUpdate`.
    public static let operationName = "CartDiscountCodesUpdate"
    /// A mutation.
    public static let kind = GraphQLOperationKind.mutation
    /// The mutation followed by `CartFields` and its dependencies.
    public static let document = mutationDocument(
        name: operationName,
        signature: "$cartId: ID!, $discountCodes: [String!]!",
        field: "cartDiscountCodesUpdate(cartId: $cartId, discountCodes: $discountCodes)"
    )

    /// The variables of this call.
    public let variables: Variables

    /// Creates the mutation. Codes are trimmed; blank and duplicate codes are dropped.
    public init(cartID: ShopifyID, codes: [String]) {
        var seen = Set<String>()
        let cleaned = codes
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.uppercased()).inserted }
        variables = Variables(cartId: cartID, discountCodes: cleaned)
    }
}

// MARK: - CartBuyerIdentityUpdateMutation

/// Updates the buyer of a cart (Storefront `cartBuyerIdentityUpdate`), e.g. the country after
/// a market change, which reprices the cart in the new market's currency.
public struct CartBuyerIdentityUpdateMutation: CartMutation {
    /// The operation variables.
    public struct Variables: Encodable, Sendable, Equatable {
        /// The cart GID.
        public let cartId: ShopifyID
        /// The new buyer identity.
        public let buyerIdentity: CartBuyerIdentityInput
    }

    /// The `data` of the response.
    public struct ResponseData: CartMutationResponse, Equatable {
        /// The payload.
        public let cartBuyerIdentityUpdate: CartMutationPayload?

        /// The payload.
        public var payload: CartMutationPayload? {
            cartBuyerIdentityUpdate
        }
    }

    /// `CartBuyerIdentityUpdate`.
    public static let operationName = "CartBuyerIdentityUpdate"
    /// A mutation.
    public static let kind = GraphQLOperationKind.mutation
    /// The mutation followed by `CartFields` and its dependencies.
    public static let document = mutationDocument(
        name: operationName,
        signature: "$cartId: ID!, $buyerIdentity: CartBuyerIdentityInput!",
        field: "cartBuyerIdentityUpdate(cartId: $cartId, buyerIdentity: $buyerIdentity)"
    )

    /// The variables of this call.
    public let variables: Variables

    /// Creates the mutation.
    ///
    /// - Parameters:
    ///   - cartID: The cart GID.
    ///   - countryCode: The buyer's country.
    ///   - email: The buyer's e-mail address, Phase 2; `nil` leaves it unchanged.
    ///   - customerAccessToken: A customer access token, Phase 2; `nil` leaves it unchanged.
    public init(cartID: ShopifyID, countryCode: CountryCode?, email: String? = nil, customerAccessToken: String? = nil) {
        variables = Variables(
            cartId: cartID,
            buyerIdentity: CartBuyerIdentityInput(countryCode: countryCode, email: email, customerAccessToken: customerAccessToken)
        )
    }
}

// MARK: - CartAttributesUpdateMutation

/// Replaces the custom attributes of a cart (Storefront `cartAttributesUpdate`). Attributes
/// that are not in the new list are removed.
public struct CartAttributesUpdateMutation: CartMutation {
    /// The operation variables.
    public struct Variables: Encodable, Sendable, Equatable {
        /// The cart GID.
        public let cartId: ShopifyID
        /// The complete list of attributes.
        public let attributes: [AttributeInput]
    }

    /// The `data` of the response.
    public struct ResponseData: CartMutationResponse, Equatable {
        /// The payload.
        public let cartAttributesUpdate: CartMutationPayload?

        /// The payload.
        public var payload: CartMutationPayload? {
            cartAttributesUpdate
        }
    }

    /// `CartAttributesUpdate`.
    public static let operationName = "CartAttributesUpdate"
    /// A mutation.
    public static let kind = GraphQLOperationKind.mutation
    /// The mutation followed by `CartFields` and its dependencies.
    public static let document = mutationDocument(
        name: operationName,
        signature: "$cartId: ID!, $attributes: [AttributeInput!]!",
        field: "cartAttributesUpdate(cartId: $cartId, attributes: $attributes)"
    )

    /// The variables of this call.
    public let variables: Variables

    /// Creates the mutation.
    public init(cartID: ShopifyID, attributes: [AttributeInput]) {
        variables = Variables(cartId: cartID, attributes: attributes)
    }
}
