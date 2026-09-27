import Foundation

/// Creates a cart (Storefront `cartCreate`).
///
/// The app creates the cart on the first "add to cart", persists `cart.id` and sends the
/// buyer's country so prices match the market. `userErrors` (for example an unknown variant)
/// are part of the payload; call `throwingUserErrors()` to turn them into
/// `ShopifyError.userErrors`.
public struct CartCreateMutation: GraphQLOperation {
    /// The operation variables: `{ "input": CartInput }`.
    public struct Variables: Encodable, Sendable, Equatable {
        /// The `CartInput`.
        public let input: CartInput
    }

    /// The Storefront `CartInput` subset the app sends.
    public struct CartInput: Encodable, Sendable, Equatable {
        /// The initial lines.
        public let lines: [CartLineInput]
        /// The buyer identity (country), if known.
        public let buyerIdentity: BuyerIdentity?
        /// Cart attributes such as `app_platform`, if any.
        public let attributes: [AttributeInput]?
    }

    /// The Storefront `CartBuyerIdentityInput` subset the app sends.
    public struct BuyerIdentity: Encodable, Sendable, Equatable {
        /// The buyer's country.
        public let countryCode: CountryCode
    }

    /// The `cartCreate` payload.
    public struct Payload: Decodable, Sendable, Equatable, UserErrorsPayload {
        /// The new cart, `nil` when user errors prevented its creation.
        public let cart: Cart?
        /// Reasons the input was rejected.
        public let userErrors: [UserError]
        /// Non-blocking warnings.
        public let warnings: [CartWarning]
    }

    /// The `data` of the response.
    public struct ResponseData: Decodable, Sendable, Equatable {
        /// The payload; `nil` only if Shopify could not run the mutation at all.
        public let cartCreate: Payload?
    }

    /// `CartCreate`.
    public static let operationName = "CartCreate"
    /// A mutation.
    public static let kind = GraphQLOperationKind.mutation
    /// The mutation document.
    public static let document = """
        mutation CartCreate($input: CartInput!) {
          cartCreate(input: $input) {
            cart {
              id
              checkoutUrl
              totalQuantity
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
          }
        }

        """

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
                buyerIdentity: countryCode.map(BuyerIdentity.init(countryCode:)),
                attributes: attributes.isEmpty ? nil : attributes
            )
        )
    }
}
