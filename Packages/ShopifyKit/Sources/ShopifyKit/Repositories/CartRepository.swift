import Foundation

// MARK: - CartRepository

/// Write access to the cart. Phase 0 only creates carts; line updates follow in Phase 1.
public protocol CartRepository: Sendable {
    /// Creates a cart with `lines` for the current buyer context.
    ///
    /// - Parameters:
    ///   - lines: The initial lines.
    ///   - attributes: Cart attributes such as `app_platform = ios`.
    /// - Returns: The new cart.
    /// - Throws: `ShopifyError.userErrors` when Shopify rejects the input (for example an
    ///   unknown variant), otherwise `ShopifyError`.
    func createCart(lines: [CartLineInput], attributes: [AttributeInput]) async throws -> Cart
}

// MARK: - StorefrontCartRepository

/// `CartRepository` backed by the Storefront cart mutations.
public final class StorefrontCartRepository: CartRepository {
    private let client: StorefrontClient
    private let contextProvider: any StorefrontContextProviding

    /// Creates a repository.
    ///
    /// - Parameters:
    ///   - client: The Storefront client.
    ///   - contextProvider: Supplies the buyer context; its country becomes the cart's buyer
    ///     identity so prices match the market.
    public init(client: StorefrontClient, contextProvider: any StorefrontContextProviding) {
        self.client = client
        self.contextProvider = contextProvider
    }

    /// Creates a cart and surfaces user errors as `ShopifyError.userErrors`.
    public func createCart(lines: [CartLineInput], attributes: [AttributeInput]) async throws -> Cart {
        let context = await contextProvider.currentContext()
        let mutation = CartCreateMutation(lines: lines, countryCode: context.country, attributes: attributes)
        let data = try await client.execute(mutation, context: context)
        guard let payload = data.cartCreate else {
            throw ShopifyError.decoding("CartCreateMutation.ResponseData: cartCreate")
        }
        try payload.throwingUserErrors()
        guard let cart = payload.cart else {
            throw ShopifyError.decoding("CartCreateMutation.Payload: cart")
        }
        return cart
    }
}
