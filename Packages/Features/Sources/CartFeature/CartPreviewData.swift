#if DEBUG
import CommerceUI
import Core
import Foundation
import ShopifyKit

// MARK: - CartPreviewData

/// Sample carts for the previews of this module, modelled on the live store (DE/DE). They exist
/// for previews only and are never shown in the app.
@MainActor
enum CartPreviewData {
    /// The ID of the sample cart.
    static let cartID = ShopifyID("gid://shopify/Cart/preview")

    /// A cart store without a cart.
    static func emptyStore() -> CartStore {
        CartStore(repository: CartPreviewRepository(cart: nil), store: InMemoryKeyValueStore(), appVersion: "preview")
    }

    /// A cart store whose stored cart holds Office 2024 Professional Plus and two Windows 11
    /// Pro keys with an applied discount code. The cart loads when the screen appears.
    static func filledStore() -> CartStore {
        let preferences = InMemoryKeyValueStore()
        preferences.set(cartID.rawValue, forKey: CartStore.cartIDKey)
        return CartStore(repository: CartPreviewRepository(cart: cart), store: preferences, appVersion: "preview")
    }

    /// The sample cart.
    static var cart: Cart {
        let office = line(
            number: 1,
            handle: "office-2024-professional-plus-key",
            title: "Microsoft Office 2024 Professional Plus Download kaufen",
            price: "29.90",
            compareAtPrice: "149.99",
            quantity: 1
        )
        let windows = line(
            number: 2,
            handle: "windows-11-pro",
            title: "Windows 11 Pro kaufen \u{2013} Dauerlizenz 1 PC, Download",
            price: "12.90",
            compareAtPrice: "79.99",
            quantity: 2
        )
        return Cart(
            id: cartID,
            checkoutUrl: URL(fileURLWithPath: "/preview/checkout"),
            totalQuantity: 3,
            lines: [office, windows],
            cost: CartCost(subtotalAmount: money("55.70"), totalAmount: money("50.13")),
            discountCodes: [CartDiscountCode(code: "WILLKOMMEN", applicable: true)],
            buyerIdentity: CartBuyerIdentity(countryCode: .de, email: nil),
            attributes: []
        )
    }

    private static func line(
        number: Int,
        handle: String,
        title: String,
        price: String,
        compareAtPrice: String,
        quantity: Int
    ) -> CartLine {
        let unit = money(price)
        let total = MoneyV2(amount: unit.amount * Decimal(quantity), currencyCode: unit.currencyCode)
        return CartLine(
            id: ShopifyID("gid://shopify/CartLine/preview-\(number)"),
            quantity: quantity,
            merchandise: CartMerchandise(
                id: ShopifyID("gid://shopify/ProductVariant/preview-\(number)"),
                title: "Default Title",
                requiresShipping: false,
                availableForSale: true,
                image: nil,
                price: unit,
                compareAtPrice: money(compareAtPrice),
                product: CartProductReference(
                    id: ShopifyID("gid://shopify/Product/preview-\(number)"),
                    handle: handle,
                    title: title,
                    vendor: "karinex"
                )
            ),
            cost: CartLineCost(
                amountPerQuantity: unit,
                compareAtAmountPerQuantity: money(compareAtPrice),
                subtotalAmount: total,
                totalAmount: total
            )
        )
    }

    private static func money(_ amount: String) -> MoneyV2 {
        MoneyV2(amount: Decimal(string: amount) ?? 0, currencyCode: .eur)
    }
}

// MARK: - CartPreviewRepository

/// Answers every cart call with a fixed cart, so previews never touch the network.
struct CartPreviewRepository: CartRepository {
    /// The cart every call returns; `nil` behaves like an expired cart.
    let cart: Cart?

    func cart(id _: ShopifyID) async throws -> Cart? {
        cart
    }

    func createCart(lines _: [CartLineInput], attributes _: [AttributeInput]) async throws -> CartMutationResult {
        try result()
    }

    func addLines(cartID _: ShopifyID, lines _: [CartLineInput]) async throws -> CartMutationResult {
        try result()
    }

    func updateLines(cartID _: ShopifyID, lines _: [CartLineUpdateInput]) async throws -> CartMutationResult {
        try result()
    }

    func removeLines(cartID _: ShopifyID, lineIDs _: [ShopifyID]) async throws -> CartMutationResult {
        try result()
    }

    func updateDiscountCodes(cartID _: ShopifyID, codes _: [String]) async throws -> CartMutationResult {
        try result()
    }

    func updateBuyerIdentity(cartID _: ShopifyID, countryCode _: CountryCode) async throws -> CartMutationResult {
        try result()
    }

    func updateBuyerIdentity(cartID _: ShopifyID, customerAccessToken _: String) async throws -> CartMutationResult {
        try result()
    }

    func updateAttributes(cartID _: ShopifyID, attributes _: [AttributeInput]) async throws -> CartMutationResult {
        try result()
    }

    private func result() throws -> CartMutationResult {
        guard let cart else { throw ShopifyError.notFound }
        return CartMutationResult(cart: cart, warnings: [])
    }
}

// MARK: - CartPreviewCatalog

/// A catalog for the previews that recommends nothing, so the cross-sell row stays hidden.
struct CartPreviewCatalog: CatalogRepository {
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

    func recommendations(productID _: ShopifyID, intent _: ProductRecommendationIntent) async throws -> [ProductSummary] {
        []
    }
}
#endif
