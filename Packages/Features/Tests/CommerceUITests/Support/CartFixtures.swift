import Foundation
import ShopifyKit

// MARK: - CartFixtures

/// Builds cart values for tests in one place, so a change of the ShopifyKit model only touches
/// this file.
enum CartFixtures {
    /// A variant ID of the recorded store (Windows 11 Pro).
    static let windowsVariant = ShopifyID("gid://shopify/ProductVariant/50000000000001")
    /// A second variant ID (Office 2024 Professional Plus).
    static let officeVariant = ShopifyID("gid://shopify/ProductVariant/50000000000002")

    /// A cart with `lines` (line ID, variant ID, quantity), every unit at 12,90 €.
    static func cart(
        id: ShopifyID,
        lines: [(id: ShopifyID, variantID: ShopifyID, quantity: Int)],
        discountCodes: [CartDiscountCode] = [],
        country: CountryCode = .de,
        attributes: [AttributeInput] = []
    ) -> Cart {
        let unit = StubCartRepository.unitPrice
        let cartLines = lines.map { line in
            let total = MoneyV2(amount: unit.amount * Decimal(line.quantity), currencyCode: unit.currencyCode)
            return CartLine(
                id: line.id,
                quantity: line.quantity,
                merchandise: CartMerchandise(
                    id: line.variantID,
                    title: "Default Title",
                    requiresShipping: false,
                    availableForSale: true,
                    image: nil,
                    price: unit,
                    compareAtPrice: nil,
                    product: CartProductReference(
                        id: ShopifyID("gid://shopify/Product/1"),
                        handle: "windows-11-pro",
                        title: "Windows 11 Pro",
                        vendor: "karinex"
                    )
                ),
                cost: CartLineCost(amountPerQuantity: unit, compareAtAmountPerQuantity: nil, subtotalAmount: total, totalAmount: total)
            )
        }
        let total = MoneyV2(
            amount: cartLines.reduce(Decimal(0)) { $0 + $1.cost.totalAmount.amount },
            currencyCode: unit.currencyCode
        )
        return Cart(
            id: id,
            checkoutUrl: checkoutURL(for: id),
            totalQuantity: lines.reduce(0) { $0 + $1.quantity },
            lines: cartLines,
            cost: CartCost(subtotalAmount: total, totalAmount: total, totalTaxAmount: nil, checkoutChargeAmount: nil),
            discountCodes: discountCodes,
            buyerIdentity: CartBuyerIdentity(countryCode: country, email: nil),
            attributes: attributes
        )
    }

    /// The checkout URL the stub hands out for a cart (shape of the real one, token redacted).
    static func checkoutURL(for id: ShopifyID) -> URL {
        let token = id.rawValue.split(separator: "/").last.map(String.init) ?? "REDACTED"
        return URL(string: "https://www.karinex.de/cart/c/\(token)?key=REDACTED") ?? URL(fileURLWithPath: "/")
    }
}
