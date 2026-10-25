import Foundation

// MARK: - Cart

/// A Storefront cart with its lines, costs, discounts and buyer identity (Storefront `Cart`
/// via the `CartFields` fragment).
///
/// Every amount is shown exactly as Shopify returns it for the cart's market; the app never
/// computes prices or tax.
///
/// - Important: `id` and `checkoutUrl` contain the secret cart token, and line IDs contain it
///   as well. Persist the ID, never log any of them.
public struct Cart: Sendable, Hashable, Codable, Identifiable {
    /// The cart GID, e.g. `gid://shopify/Cart/<token>?key=<key>`.
    public let id: ShopifyID
    /// The web checkout URL for Checkout Kit. Request a fresh one right before checkout.
    public let checkoutUrl: URL
    /// The total number of items in the cart.
    public let totalQuantity: Int
    /// The cart lines in the order Shopify returns them (up to 100).
    public let lines: [CartLine]
    /// The cart totals.
    public let cost: CartCost
    /// The discount codes entered on the cart, applicable or not.
    public let discountCodes: [CartDiscountCode]
    /// The buyer's country and e-mail address as known to the cart.
    public let buyerIdentity: CartBuyerIdentity
    /// The custom cart attributes, e.g. `app_platform = ios`. Attributes without a value are
    /// left out.
    public let attributes: [AttributeInput]
    /// The discounts applied to the cart (codes, automatic and custom discounts), Storefront
    /// `discountApplications` of API 2026-10.
    public let discountApplications: [CartDiscountApplication]
    /// The buyer's note, if any. Shopify returns an empty string when none was set.
    public let note: String?

    /// Creates a cart.
    public init(
        id: ShopifyID,
        checkoutUrl: URL,
        totalQuantity: Int,
        lines: [CartLine],
        cost: CartCost,
        discountCodes: [CartDiscountCode],
        buyerIdentity: CartBuyerIdentity,
        attributes: [AttributeInput],
        discountApplications: [CartDiscountApplication] = [],
        note: String? = nil
    ) {
        self.id = id
        self.checkoutUrl = checkoutUrl
        self.totalQuantity = totalQuantity
        self.lines = lines
        self.cost = cost
        self.discountCodes = discountCodes
        self.buyerIdentity = buyerIdentity
        self.attributes = attributes
        self.discountApplications = discountApplications
        self.note = note
    }

    // MARK: Derived values

    /// Whether the cart has no lines.
    public var isEmpty: Bool {
        lines.isEmpty
    }

    /// Whether any line needs shipping. License keys (ESD) do not.
    public var requiresShipping: Bool {
        lines.contains { $0.merchandise.requiresShipping }
    }

    /// The total reduction of the cart: `subtotalAmount - totalAmount` when that is positive
    /// and both amounts have the same currency, otherwise `nil`.
    public var discountTotal: MoneyV2? {
        let subtotal = cost.subtotalAmount
        let total = cost.totalAmount
        guard subtotal.currencyCode == total.currencyCode, subtotal.amount > total.amount else { return nil }
        return MoneyV2(amount: subtotal.amount - total.amount, currencyCode: subtotal.currencyCode)
    }

    /// The line with `id`, if the cart has one.
    public func line(id: ShopifyID) -> CartLine? {
        lines.first { $0.id == id }
    }

    /// The value of the cart attribute `key`, if set.
    public func attribute(_ key: String) -> String? {
        attributes.first { $0.key == key }?.value
    }

    // MARK: Codable

    private enum CodingKeys: String, CodingKey {
        case id, checkoutUrl, totalQuantity, lines, cost, discountCodes, buyerIdentity, attributes, discountApplications, note
    }

    /// An attribute as Shopify returns it: the value may be `null`.
    private struct NullableAttribute: Codable {
        let key: String
        let value: String?
    }

    /// Decodes the Storefront shape: `lines` as `{nodes: [...]}` and attributes whose `null`
    /// values are dropped.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(ShopifyID.self, forKey: .id)
        checkoutUrl = try container.decode(URL.self, forKey: .checkoutUrl)
        totalQuantity = try container.decode(Int.self, forKey: .totalQuantity)
        lines = try container.decode(Connection<CartLine>.self, forKey: .lines).nodes
        cost = try container.decode(CartCost.self, forKey: .cost)
        discountCodes = try container.decodeIfPresent([CartDiscountCode].self, forKey: .discountCodes) ?? []
        buyerIdentity = try container.decodeIfPresent(CartBuyerIdentity.self, forKey: .buyerIdentity)
            ?? CartBuyerIdentity(countryCode: nil, email: nil)
        attributes = try (container.decodeIfPresent([NullableAttribute].self, forKey: .attributes) ?? [])
            .compactMap { attribute in attribute.value.map { AttributeInput(key: attribute.key, value: $0) } }
        discountApplications = try container.decodeIfPresent([CartDiscountApplication].self, forKey: .discountApplications) ?? []
        note = try container.decodeIfPresent(String.self, forKey: .note)
    }

    /// Encodes the same shape `init(from:)` reads.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(checkoutUrl, forKey: .checkoutUrl)
        try container.encode(totalQuantity, forKey: .totalQuantity)
        try container.encode(Connection(nodes: lines), forKey: .lines)
        try container.encode(cost, forKey: .cost)
        try container.encode(discountCodes, forKey: .discountCodes)
        try container.encode(buyerIdentity, forKey: .buyerIdentity)
        try container.encode(attributes, forKey: .attributes)
        try container.encode(discountApplications, forKey: .discountApplications)
        try container.encodeIfPresent(note, forKey: .note)
    }
}

// MARK: - CartLine

/// One line of a cart (Storefront `BaseCartLine`).
public struct CartLine: Sendable, Hashable, Codable, Identifiable {
    /// The line GID. Contains the cart token; never log it.
    public let id: ShopifyID
    /// The quantity.
    public let quantity: Int
    /// The variant in the line.
    public let merchandise: CartMerchandise
    /// The line amounts.
    public let cost: CartLineCost
    /// Line-level discounts allocated to this line. Cart-level discounts (for example an
    /// automatic order discount) are reported in `Cart.discountApplications`.
    public let discountAllocations: [CartDiscountAllocation]

    /// Creates a cart line.
    public init(
        id: ShopifyID,
        quantity: Int,
        merchandise: CartMerchandise,
        cost: CartLineCost,
        discountAllocations: [CartDiscountAllocation] = []
    ) {
        self.id = id
        self.quantity = quantity
        self.merchandise = merchandise
        self.cost = cost
        self.discountAllocations = discountAllocations
    }

    private enum CodingKeys: String, CodingKey {
        case id, quantity, merchandise, cost, discountAllocations
    }

    /// Decodes a line; a missing `discountAllocations` member counts as none.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(ShopifyID.self, forKey: .id)
        quantity = try container.decode(Int.self, forKey: .quantity)
        merchandise = try container.decode(CartMerchandise.self, forKey: .merchandise)
        cost = try container.decode(CartLineCost.self, forKey: .cost)
        discountAllocations = try container.decodeIfPresent([CartDiscountAllocation].self, forKey: .discountAllocations) ?? []
    }
}

// MARK: - CartMerchandise

/// The variant of a cart line (Storefront `ProductVariant` as `Merchandise`).
public struct CartMerchandise: Sendable, Hashable, Codable, Identifiable {
    /// The variant GID.
    public let id: ShopifyID
    /// The variant title, `Default Title` for single-variant products.
    public let title: String
    /// Whether the variant is a physical good. License keys (ESD) are `false`.
    public let requiresShipping: Bool
    /// Whether the variant can currently be bought.
    public let availableForSale: Bool
    /// The variant image, if any.
    public let image: ShopifyImage?
    /// The unit price in the cart's market.
    public let price: MoneyV2
    /// The compare-at unit price, if the merchant set one.
    public let compareAtPrice: MoneyV2?
    /// The product the variant belongs to.
    public let product: CartProductReference
    /// The SKU, if set.
    public let sku: String?
    /// The option values of the variant.
    public let selectedOptions: [SelectedOption]

    /// Creates a cart merchandise value.
    public init(
        id: ShopifyID,
        title: String,
        requiresShipping: Bool,
        availableForSale: Bool,
        image: ShopifyImage?,
        price: MoneyV2,
        compareAtPrice: MoneyV2?,
        product: CartProductReference,
        sku: String? = nil,
        selectedOptions: [SelectedOption] = []
    ) {
        self.id = id
        self.title = title
        self.requiresShipping = requiresShipping
        self.availableForSale = availableForSale
        self.image = image
        self.price = price
        self.compareAtPrice = compareAtPrice
        self.product = product
        self.sku = sku
        self.selectedOptions = selectedOptions
    }

    /// The option values a customer chose, without Shopify's `Default Title` placeholder.
    public var visibleOptions: [SelectedOption] {
        selectedOptions.filter { !($0.name == "Title" && $0.value == "Default Title") }
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, requiresShipping, availableForSale, image, price, compareAtPrice, product, sku, selectedOptions
    }

    /// Decodes a variant; missing optional members count as absent.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(ShopifyID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        requiresShipping = try container.decode(Bool.self, forKey: .requiresShipping)
        availableForSale = try container.decode(Bool.self, forKey: .availableForSale)
        image = try container.decodeIfPresent(ShopifyImage.self, forKey: .image)
        price = try container.decode(MoneyV2.self, forKey: .price)
        compareAtPrice = try container.decodeIfPresent(MoneyV2.self, forKey: .compareAtPrice)
        product = try container.decode(CartProductReference.self, forKey: .product)
        sku = try container.decodeIfPresent(String.self, forKey: .sku)
        selectedOptions = try container.decodeIfPresent([SelectedOption].self, forKey: .selectedOptions) ?? []
    }
}

// MARK: - CartProductReference

/// The product of a cart line, enough to open the product screen.
public struct CartProductReference: Sendable, Hashable, Codable, Identifiable {
    /// The product GID.
    public let id: ShopifyID
    /// The URL handle.
    public let handle: String
    /// The title in the context language.
    public let title: String
    /// The vendor.
    public let vendor: String

    /// Creates a product reference.
    public init(id: ShopifyID, handle: String, title: String, vendor: String) {
        self.id = id
        self.handle = handle
        self.title = title
        self.vendor = vendor
    }
}

// MARK: - Costs

/// The amounts of one cart line (Storefront `CartLineCost`).
public struct CartLineCost: Sendable, Hashable, Codable {
    /// The price of one unit.
    public let amountPerQuantity: MoneyV2
    /// The compare-at price of one unit, if any.
    public let compareAtAmountPerQuantity: MoneyV2?
    /// The line amount before line-level discounts.
    public let subtotalAmount: MoneyV2
    /// The line amount after line-level discounts.
    public let totalAmount: MoneyV2

    /// Creates line costs.
    public init(amountPerQuantity: MoneyV2, compareAtAmountPerQuantity: MoneyV2? = nil, subtotalAmount: MoneyV2, totalAmount: MoneyV2) {
        self.amountPerQuantity = amountPerQuantity
        self.compareAtAmountPerQuantity = compareAtAmountPerQuantity
        self.subtotalAmount = subtotalAmount
        self.totalAmount = totalAmount
    }
}

/// The totals of a cart (Storefront `CartCost`).
public struct CartCost: Sendable, Hashable, Codable {
    /// The amount before cart-level discounts (and before shipping at checkout).
    public let subtotalAmount: MoneyV2
    /// The amount the buyer pays, after discounts.
    public let totalAmount: MoneyV2
    /// The tax amount. Shopify deprecated tax amounts in the Storefront cart API (they are no
    /// longer computed), so `CartFields` does not request it and the value is `nil` unless a
    /// cached or hand-made cart carries one. Never compute tax from other amounts.
    public let totalTaxAmount: MoneyV2?
    /// The amount charged at checkout (without deferred payments), if reported.
    public let checkoutChargeAmount: MoneyV2?

    /// Creates cart costs.
    public init(subtotalAmount: MoneyV2, totalAmount: MoneyV2, totalTaxAmount: MoneyV2? = nil, checkoutChargeAmount: MoneyV2? = nil) {
        self.subtotalAmount = subtotalAmount
        self.totalAmount = totalAmount
        self.totalTaxAmount = totalTaxAmount
        self.checkoutChargeAmount = checkoutChargeAmount
    }
}

// MARK: - Discounts

/// A discount code entered on the cart (Storefront `CartDiscountCode`).
public struct CartDiscountCode: Sendable, Hashable, Codable {
    /// The code as entered.
    public let code: String
    /// Whether the code applies to the cart. Unknown or ineligible codes stay on the cart with
    /// `false`, and Shopify adds a `DISCOUNT_*` warning.
    public let applicable: Bool

    /// Creates a discount code value.
    public init(code: String, applicable: Bool) {
        self.code = code
        self.applicable = applicable
    }
}

/// A line-level discount allocated to a cart line (Storefront `CartDiscountAllocation`).
public struct CartDiscountAllocation: Sendable, Hashable, Codable {
    /// The amount the line is reduced by.
    public let discountedAmount: MoneyV2

    /// Creates an allocation.
    public init(discountedAmount: MoneyV2) {
        self.discountedAmount = discountedAmount
    }
}

/// A discount applied to the cart (Storefront `BaseCartDiscountApplication`, 2026-10).
public struct CartDiscountApplication: Sendable, Hashable, Codable {
    /// Where the discount comes from.
    public enum Source: Sendable, Hashable {
        /// A discount code entered by the buyer.
        case code(String)
        /// An automatic discount with its merchant title, e.g. a quantity discount.
        case automatic(title: String)
        /// A discount applied by an app or script, with its title.
        case custom(title: String)
    }

    /// The size of the discount.
    public enum Value: Sendable, Hashable {
        /// A fixed amount.
        case money(MoneyV2)
        /// A percentage, e.g. `10` for 10 %.
        case percentage(Double)
    }

    /// Where the discount comes from.
    public let source: Source
    /// The size of the discount.
    public let value: Value
    /// The total amount the discount takes off the cart.
    public let totalAllocatedAmount: MoneyV2
    /// What the discount applies to: `LINE_ITEM` or `SHIPPING_LINE`.
    public let targetType: String
    /// How the value is distributed: `ACROSS` or `EACH`.
    public let allocationMethod: String

    /// Creates a discount application.
    public init(source: Source, value: Value, totalAllocatedAmount: MoneyV2, targetType: String, allocationMethod: String) {
        self.source = source
        self.value = value
        self.totalAllocatedAmount = totalAllocatedAmount
        self.targetType = targetType
        self.allocationMethod = allocationMethod
    }

    /// The text to show for the discount: the code or the merchant's title.
    public var title: String {
        switch source {
        case let .code(code): code
        case let .automatic(title), let .custom(title): title
        }
    }

    // MARK: Codable

    private enum CodingKeys: String, CodingKey {
        case typename = "__typename"
        case code, title, value, totalAllocatedAmount, targetType, allocationMethod
    }

    private enum ValueKeys: String, CodingKey {
        case typename = "__typename"
        case percentage
    }

    /// Decodes the `CartDiscountApplicationFields` shape: the concrete type from `__typename`,
    /// the value from `MoneyV2` or `PricingPercentageValue`.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let typename = try container.decodeIfPresent(String.self, forKey: .typename)
        if let code = try container.decodeIfPresent(String.self, forKey: .code) {
            source = .code(code)
        } else {
            let title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
            source = typename == "CartCustomDiscountApplication" ? .custom(title: title) : .automatic(title: title)
        }
        let valueContainer = try container.nestedContainer(keyedBy: ValueKeys.self, forKey: .value)
        if let percentage = try valueContainer.decodeIfPresent(Double.self, forKey: .percentage) {
            value = .percentage(percentage)
        } else {
            value = try .money(container.decode(MoneyV2.self, forKey: .value))
        }
        totalAllocatedAmount = try container.decode(MoneyV2.self, forKey: .totalAllocatedAmount)
        targetType = try container.decode(String.self, forKey: .targetType)
        allocationMethod = try container.decode(String.self, forKey: .allocationMethod)
    }

    /// Encodes the same shape `init(from:)` reads.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch source {
        case let .code(code):
            try container.encode("CartCodeDiscountApplication", forKey: .typename)
            try container.encode(code, forKey: .code)
        case let .automatic(title):
            try container.encode("CartAutomaticDiscountApplication", forKey: .typename)
            try container.encode(title, forKey: .title)
        case let .custom(title):
            try container.encode("CartCustomDiscountApplication", forKey: .typename)
            try container.encode(title, forKey: .title)
        }
        switch value {
        case let .money(money):
            try container.encode(money, forKey: .value)
        case let .percentage(percentage):
            var valueContainer = container.nestedContainer(keyedBy: ValueKeys.self, forKey: .value)
            try valueContainer.encode("PricingPercentageValue", forKey: .typename)
            try valueContainer.encode(percentage, forKey: .percentage)
        }
        try container.encode(totalAllocatedAmount, forKey: .totalAllocatedAmount)
        try container.encode(targetType, forKey: .targetType)
        try container.encode(allocationMethod, forKey: .allocationMethod)
    }
}

// MARK: - CartBuyerIdentity

/// The buyer as known to the cart (Storefront `CartBuyerIdentity`).
///
/// - Important: `email` is personal data. Never log or persist it outside the cart.
public struct CartBuyerIdentity: Sendable, Hashable, Codable {
    /// The buyer's country, which determines the market prices.
    public let countryCode: CountryCode?
    /// The buyer's e-mail address, once known (Phase 2 accounts).
    public let email: String?

    /// Creates a buyer identity.
    public init(countryCode: CountryCode?, email: String?) {
        self.countryCode = countryCode
        self.email = email
    }
}

// MARK: - CartMutationResult

/// The result of every cart mutation: the updated cart and Shopify's non-blocking warnings
/// (for example `DISCOUNT_NOT_FOUND` after an unknown discount code).
public struct CartMutationResult: Sendable, Hashable {
    /// The cart after the mutation.
    public let cart: Cart
    /// Non-blocking warnings with Shopify's localized messages.
    public let warnings: [CartWarning]

    /// Creates a result.
    public init(cart: Cart, warnings: [CartWarning]) {
        self.cart = cart
        self.warnings = warnings
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

// MARK: - CartLineUpdateInput

/// A quantity change of an existing cart line (Storefront `CartLineUpdateInput`).
public struct CartLineUpdateInput: Sendable, Hashable, Codable {
    /// The line GID.
    public let id: ShopifyID
    /// The new quantity. Zero removes the line; negative values are raised to zero.
    public let quantity: Int

    /// Creates an update.
    public init(id: ShopifyID, quantity: Int) {
        self.id = id
        self.quantity = max(quantity, 0)
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

/// A non-blocking cart warning (Storefront `CartWarning`), e.g. `MERCHANDISE_NOT_ENOUGH_STOCK`
/// or `DISCOUNT_NOT_FOUND`.
public struct CartWarning: Sendable, Hashable, Codable {
    /// The warning code. Kept as a string so new codes never break decoding.
    public let code: String
    /// The localized message, which may be shown to the buyer.
    public let message: String
    /// The GID of the object the warning refers to (a cart or a cart line). Never log it.
    public let target: String

    /// Creates a warning.
    public init(code: String, message: String, target: String) {
        self.code = code
        self.message = message
        self.target = target
    }

    /// Whether the warning is about a discount code (`DISCOUNT_*`).
    public var isDiscountWarning: Bool {
        code.hasPrefix("DISCOUNT_")
    }
}
