import Foundation

// MARK: - Cart

/// The minimal cart of Phase 0 (Storefront `Cart`): enough to persist the cart and open
/// checkout. Lines, costs and buyer identity follow in Phase 1.
///
/// - Important: `id` and `checkoutUrl` contain the secret cart token. Persist them, never
///   log them.
public struct Cart: Sendable, Hashable, Codable, Identifiable {
    /// The cart GID, e.g. `gid://shopify/Cart/<token>?key=<key>`.
    public let id: ShopifyID
    /// The web checkout URL for Checkout Kit. Request a fresh one right before checkout.
    public let checkoutUrl: URL
    /// The total number of items in the cart.
    public let totalQuantity: Int

    /// Creates a cart.
    public init(id: ShopifyID, checkoutUrl: URL, totalQuantity: Int) {
        self.id = id
        self.checkoutUrl = checkoutUrl
        self.totalQuantity = totalQuantity
    }
}

// MARK: - CartLineInput

/// A line to add to a cart (Storefront `CartLineInput`).
public struct CartLineInput: Sendable, Hashable, Codable {
    /// The variant GID.
    public let merchandiseId: ShopifyID
    /// The quantity, at least 1.
    public let quantity: Int
    /// Line attributes, if any.
    public let attributes: [AttributeInput]?

    /// Creates a line. Quantities below 1 are raised to 1.
    public init(merchandiseId: ShopifyID, quantity: Int = 1, attributes: [AttributeInput]? = nil) {
        self.merchandiseId = merchandiseId
        self.quantity = max(quantity, 1)
        self.attributes = attributes
    }
}

// MARK: - AttributeInput

/// A custom key-value attribute of a cart or cart line (Storefront `AttributeInput`), e.g.
/// `app_platform = ios`.
public struct AttributeInput: Sendable, Hashable, Codable {
    /// The key.
    public let key: String
    /// The value.
    public let value: String

    /// Creates an attribute.
    public init(key: String, value: String) {
        self.key = key
        self.value = value
    }
}

// MARK: - CartWarning

/// A non-blocking cart warning (Storefront `CartWarning`), e.g. `MERCHANDISE_NOT_ENOUGH_STOCK`.
public struct CartWarning: Sendable, Hashable, Codable {
    /// The warning code. Kept as a string so new codes never break decoding.
    public let code: String
    /// The localized message.
    public let message: String
    /// The GID of the object the warning refers to.
    public let target: String

    /// Creates a warning.
    public init(code: String, message: String, target: String) {
        self.code = code
        self.message = message
        self.target = target
    }
}
