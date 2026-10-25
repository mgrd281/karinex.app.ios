import Foundation

// MARK: - CartRepository

/// Read and write access to a cart.
///
/// Every mutation returns the complete updated cart plus Shopify's non-blocking warnings.
/// User errors (for example an unknown variant) throw `ShopifyError.userErrors` with
/// Shopify's localized messages. Mutations are never retried after a failure that may have
/// reached Shopify (`GraphQLClient` rules); callers re-read the cart with `cart(id:)` instead
/// of repeating the mutation.
public protocol CartRepository: Sendable {
    /// The cart with `id`, or `nil` when it is unknown, expired or completed (became an order).
    ///
    /// - Throws: `ShopifyError`.
    func cart(id: ShopifyID) async throws -> Cart?

    /// Creates a cart with `lines` for the current buyer context; the context's country
    /// becomes the cart's buyer identity.
    ///
    /// - Parameters:
    ///   - lines: The initial lines.
    ///   - attributes: Cart attributes such as `app_platform = ios`.
    /// - Throws: `ShopifyError.userErrors` when Shopify rejects the input, otherwise `ShopifyError`.
    func createCart(lines: [CartLineInput], attributes: [AttributeInput]) async throws -> CartMutationResult

    /// Adds `lines` to the cart; a variant already in the cart gets a higher quantity.
    ///
    /// - Throws: `ShopifyError.userErrors` when Shopify rejects the input, otherwise `ShopifyError`.
    func addLines(cartID: ShopifyID, lines: [CartLineInput]) async throws -> CartMutationResult

    /// Changes line quantities; a quantity of zero removes the line.
    ///
    /// - Throws: `ShopifyError.userErrors` when Shopify rejects the input, otherwise `ShopifyError`.
    func updateLines(cartID: ShopifyID, lines: [CartLineUpdateInput]) async throws -> CartMutationResult

    /// Removes the lines with `lineIDs`.
    ///
    /// - Throws: `ShopifyError.userErrors` when Shopify rejects the input, otherwise `ShopifyError`.
    func removeLines(cartID: ShopifyID, lineIDs: [ShopifyID]) async throws -> CartMutationResult

    /// Replaces the cart's discount codes with `codes`; an empty list removes all codes. A code
    /// that does not apply stays on the cart with `applicable: false` and a `DISCOUNT_*` warning.
    ///
    /// - Throws: `ShopifyError.userErrors` when Shopify rejects the input, otherwise `ShopifyError`.
    func updateDiscountCodes(cartID: ShopifyID, codes: [String]) async throws -> CartMutationResult

    /// Sets the buyer's country, which reprices the cart in that market.
    ///
    /// - Throws: `ShopifyError.userErrors` when Shopify rejects the input, otherwise `ShopifyError`.
    func updateBuyerIdentity(cartID: ShopifyID, countryCode: CountryCode) async throws -> CartMutationResult

    /// Replaces the cart attributes with `attributes`.
    ///
    /// - Throws: `ShopifyError.userErrors` when Shopify rejects the input, otherwise `ShopifyError`.
    func updateAttributes(cartID: ShopifyID, attributes: [AttributeInput]) async throws -> CartMutationResult
}

// MARK: - StorefrontCartRepository

/// `CartRepository` backed by the Storefront cart query and mutations.
public final class StorefrontCartRepository: CartRepository {
    private let client: StorefrontClient
    private let contextProvider: any StorefrontContextProviding

    /// Creates a repository.
    ///
    /// - Parameters:
    ///   - client: The Storefront client.
    ///   - contextProvider: Supplies the buyer context of each call; its country becomes the
    ///     buyer identity of new carts so prices match the market.
    public init(client: StorefrontClient, contextProvider: any StorefrontContextProviding) {
        self.client = client
        self.contextProvider = contextProvider
    }

    /// Loads the cart, `nil` when it no longer exists.
    public func cart(id: ShopifyID) async throws -> Cart? {
        let context = await contextProvider.currentContext()
        return try await client.execute(CartQuery(id: id), context: context).cart
    }

    /// Creates a cart in the current context's country.
    public func createCart(lines: [CartLineInput], attributes: [AttributeInput]) async throws -> CartMutationResult {
        let context = await contextProvider.currentContext()
        return try await perform(CartCreateMutation(lines: lines, countryCode: context.country, attributes: attributes), context: context)
    }

    /// Adds lines.
    public func addLines(cartID: ShopifyID, lines: [CartLineInput]) async throws -> CartMutationResult {
        try await perform(CartLinesAddMutation(cartID: cartID, lines: lines), context: contextProvider.currentContext())
    }

    /// Updates line quantities.
    public func updateLines(cartID: ShopifyID, lines: [CartLineUpdateInput]) async throws -> CartMutationResult {
        try await perform(CartLinesUpdateMutation(cartID: cartID, lines: lines), context: contextProvider.currentContext())
    }

    /// Removes lines.
    public func removeLines(cartID: ShopifyID, lineIDs: [ShopifyID]) async throws -> CartMutationResult {
        try await perform(CartLinesRemoveMutation(cartID: cartID, lineIDs: lineIDs), context: contextProvider.currentContext())
    }

    /// Replaces the discount codes.
    public func updateDiscountCodes(cartID: ShopifyID, codes: [String]) async throws -> CartMutationResult {
        try await perform(CartDiscountCodesUpdateMutation(cartID: cartID, codes: codes), context: contextProvider.currentContext())
    }

    /// Sets the buyer's country.
    public func updateBuyerIdentity(cartID: ShopifyID, countryCode: CountryCode) async throws -> CartMutationResult {
        try await perform(
            CartBuyerIdentityUpdateMutation(cartID: cartID, countryCode: countryCode),
            context: contextProvider.currentContext()
        )
    }

    /// Replaces the cart attributes.
    public func updateAttributes(cartID: ShopifyID, attributes: [AttributeInput]) async throws -> CartMutationResult {
        try await perform(CartAttributesUpdateMutation(cartID: cartID, attributes: attributes), context: contextProvider.currentContext())
    }

    // MARK: - Private

    /// Runs `mutation` in `context` and maps the payload: user errors throw, a missing payload
    /// or cart is a decoding error.
    private func perform<M: CartMutation>(_ mutation: M, context: StorefrontContext) async throws -> CartMutationResult {
        let data = try await client.execute(mutation, context: context)
        guard let payload = data.payload else {
            throw ShopifyError.decoding("\(M.operationName): payload")
        }
        try payload.throwingUserErrors()
        guard let cart = payload.cart else {
            throw ShopifyError.decoding("\(M.operationName): cart")
        }
        return CartMutationResult(cart: cart, warnings: payload.warnings)
    }
}
