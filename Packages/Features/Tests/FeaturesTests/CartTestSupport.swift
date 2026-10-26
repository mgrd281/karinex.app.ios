import Foundation
import ShopifyKit

// MARK: - CartTestFixtures

/// Sample values for the Cart and Checkout tests.
enum CartTestFixtures {
    /// The unit price of every variant: 12,90 €.
    static let unitPrice = MoneyV2(amount: Decimal(string: "12.90") ?? 0, currencyCode: .eur)

    /// The variant ID of the product with `handle`.
    static func variant(_ handle: String) -> ShopifyID {
        ShopifyID("gid://shopify/ProductVariant/\(handle)")
    }

    /// The product ID of the product with `handle`.
    static func productID(_ handle: String) -> ShopifyID {
        ShopifyID("gid://shopify/Product/\(handle)")
    }

    /// The handle encoded in a variant ID built by ``variant(_:)``.
    static func handle(of variantID: ShopifyID) -> String {
        variantID.rawValue.components(separatedBy: "/").last ?? variantID.rawValue
    }

    /// A product summary with `handle`, as the catalog returns it.
    static func summary(_ handle: String) -> ProductSummary {
        ProductSummary(
            id: productID(handle),
            handle: handle,
            title: handle,
            vendor: "Microsoft",
            availableForSale: true,
            featuredImage: nil,
            priceRange: PriceRange(minVariantPrice: unitPrice, maxVariantPrice: unitPrice),
            compareAtPriceRange: PriceRange(minVariantPrice: unitPrice, maxVariantPrice: unitPrice),
            requiresShipping: false
        )
    }

    /// A merchandise reference for `handle` with the given options and title.
    static func merchandise(
        _ handle: String,
        title: String = "Default Title",
        options: [SelectedOption] = [],
        requiresShipping: Bool = false
    ) -> CartMerchandise {
        CartMerchandise(
            id: variant(handle),
            title: title,
            requiresShipping: requiresShipping,
            availableForSale: true,
            image: nil,
            price: unitPrice,
            compareAtPrice: nil,
            product: CartProductReference(id: productID(handle), handle: handle, title: "Produkt \(handle)", vendor: "Microsoft"),
            selectedOptions: options
        )
    }
}

// MARK: - CartFeatureStubRepository

/// An in-memory Shopify cart for the cart screen tests: lines merge per variant, every
/// mutation returns the whole cart, unknown carts answer `nil` and refuse mutations, and only
/// ``validDiscountCode`` applies (other codes come back with Shopify's warning).
actor CartFeatureStubRepository: CartRepository {
    /// The only discount code that applies.
    static let validDiscountCode = "WILLKOMMEN"
    /// Shopify's message for a code that does not apply.
    static let discountWarning = "Der Rabattcode ist für diesen Warenkorb nicht gültig."

    private struct StoredLine {
        let id: ShopifyID
        let variantID: ShopifyID
        var quantity: Int
    }

    private var lines: [StoredLine] = []
    private var codes: [String] = []
    private var exists = false
    private var nextLineNumber = 1
    private var pendingFailure: (any Error)?
    private var extraWarnings: [CartWarning] = []

    /// The ID of the one cart this stub keeps.
    static let cartID = ShopifyID("gid://shopify/Cart/feature-stub")

    /// Makes the next mutation throw `error`.
    func failNextMutation(with error: any Error) {
        pendingFailure = error
    }

    /// Adds `warnings` to the result of every following mutation.
    func addWarnings(_ warnings: [CartWarning]) {
        extraWarnings = warnings
    }

    // MARK: CartRepository

    func cart(id _: ShopifyID) async throws -> Cart? {
        exists ? snapshot() : nil
    }

    func createCart(lines inputs: [CartLineInput], attributes _: [AttributeInput]) async throws -> CartMutationResult {
        try throwPendingFailure()
        exists = true
        lines = []
        codes = []
        merge(inputs)
        return result()
    }

    func addLines(cartID _: ShopifyID, lines inputs: [CartLineInput]) async throws -> CartMutationResult {
        try throwPendingFailure()
        try requireCart()
        merge(inputs)
        return result()
    }

    func updateLines(cartID _: ShopifyID, lines updates: [CartLineUpdateInput]) async throws -> CartMutationResult {
        try throwPendingFailure()
        try requireCart()
        for update in updates {
            guard let index = lines.firstIndex(where: { $0.id == update.id }) else { continue }
            lines[index].quantity = update.quantity
        }
        lines.removeAll { $0.quantity <= 0 }
        return result()
    }

    func removeLines(cartID _: ShopifyID, lineIDs: [ShopifyID]) async throws -> CartMutationResult {
        try throwPendingFailure()
        try requireCart()
        lines.removeAll { lineIDs.contains($0.id) }
        return result()
    }

    func updateDiscountCodes(cartID _: ShopifyID, codes newCodes: [String]) async throws -> CartMutationResult {
        try throwPendingFailure()
        try requireCart()
        codes = newCodes
        let warnings = newCodes
            .filter { $0 != Self.validDiscountCode }
            .map { _ in CartWarning(code: "DISCOUNT_CODE_NOT_HONOURED", message: Self.discountWarning, target: Self.cartID.rawValue) }
        return CartMutationResult(cart: snapshot(), warnings: warnings + extraWarnings)
    }

    func updateBuyerIdentity(cartID _: ShopifyID, countryCode _: CountryCode) async throws -> CartMutationResult {
        try throwPendingFailure()
        try requireCart()
        return result()
    }

    func updateBuyerIdentity(cartID _: ShopifyID, customerAccessToken _: String) async throws -> CartMutationResult {
        try throwPendingFailure()
        try requireCart()
        return result()
    }

    func updateAttributes(cartID _: ShopifyID, attributes _: [AttributeInput]) async throws -> CartMutationResult {
        try throwPendingFailure()
        try requireCart()
        return result()
    }

    // MARK: Private

    private func throwPendingFailure() throws {
        guard let failure = pendingFailure else { return }
        pendingFailure = nil
        throw failure
    }

    private func requireCart() throws {
        guard exists else {
            throw ShopifyError.userErrors([UserError(field: ["cartId"], message: "Der Warenkorb existiert nicht.", code: .invalid)])
        }
    }

    private func merge(_ inputs: [CartLineInput]) {
        for input in inputs {
            if let index = lines.firstIndex(where: { $0.variantID == input.merchandiseId }) {
                lines[index].quantity += input.quantity
            } else {
                lines.append(StoredLine(
                    id: ShopifyID("gid://shopify/CartLine/feature-\(nextLineNumber)"),
                    variantID: input.merchandiseId,
                    quantity: input.quantity
                ))
                nextLineNumber += 1
            }
        }
    }

    private func result() -> CartMutationResult {
        CartMutationResult(cart: snapshot(), warnings: extraWarnings)
    }

    private func snapshot() -> Cart {
        let unit = CartTestFixtures.unitPrice
        let cartLines = lines.map { stored in
            let total = MoneyV2(amount: unit.amount * Decimal(stored.quantity), currencyCode: unit.currencyCode)
            return CartLine(
                id: stored.id,
                quantity: stored.quantity,
                merchandise: CartTestFixtures.merchandise(CartTestFixtures.handle(of: stored.variantID)),
                cost: CartLineCost(amountPerQuantity: unit, subtotalAmount: total, totalAmount: total)
            )
        }
        let subtotal = cartLines.reduce(Decimal(0)) { $0 + $1.cost.totalAmount.amount }
        let isDiscounted = codes.contains(Self.validDiscountCode)
        let total = isDiscounted ? subtotal - 1 : subtotal
        return Cart(
            id: Self.cartID,
            checkoutUrl: URL(fileURLWithPath: "/checkout/feature-stub"),
            totalQuantity: lines.reduce(0) { $0 + $1.quantity },
            lines: cartLines,
            cost: CartCost(
                subtotalAmount: MoneyV2(amount: subtotal, currencyCode: unit.currencyCode),
                totalAmount: MoneyV2(amount: total, currencyCode: unit.currencyCode)
            ),
            discountCodes: codes.map { CartDiscountCode(code: $0, applicable: $0 == Self.validDiscountCode) },
            buyerIdentity: CartBuyerIdentity(countryCode: .de, email: nil),
            attributes: []
        )
    }
}

// MARK: - CartFeatureStubCatalog

/// A catalog that answers recommendations from a fixed list (or fails) and records the
/// requests; everything else is empty.
actor CartFeatureStubCatalog: CatalogRepository {
    /// One recorded recommendations request.
    struct Request: Sendable, Hashable {
        let productID: ShopifyID
        let intent: ProductRecommendationIntent
    }

    private let recommendations: [ProductSummary]
    private var failure: (any Error)?
    private(set) var requests: [Request] = []

    /// Creates the catalog with the recommendations it returns.
    init(recommendations: [ProductSummary] = []) {
        self.recommendations = recommendations
    }

    /// Makes the next recommendations request throw `error`.
    func failNext(with error: any Error) {
        failure = error
    }

    func product(handle _: String) async throws -> Product? {
        nil
    }

    func collection(
        handle _: String,
        first _: Int,
        after _: String?,
        sortKey _: ProductCollectionSortKeys,
        reverse _: Bool,
        filters _: [ProductFilterInput]
    ) async throws -> CollectionPage? {
        nil
    }

    func collections(first _: Int) async throws -> [CollectionSummary] {
        []
    }

    func recommendations(productID: ShopifyID, intent: ProductRecommendationIntent) async throws -> [ProductSummary] {
        requests.append(Request(productID: productID, intent: intent))
        if let failure {
            self.failure = nil
            throw failure
        }
        return recommendations
    }
}
