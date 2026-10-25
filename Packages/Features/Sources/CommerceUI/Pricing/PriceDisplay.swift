import DesignSystem
import Foundation
import ShopifyKit
import SwiftUI

// MARK: - PriceDisplay

/// The display strings of a price for ``KXPriceTag``: the formatted price and compare-at price,
/// the savings badge, the tax note of the market and the store's lowest price of the last 30
/// days.
///
/// Rules (PROMPT.md sections 3 and 7):
/// - Money is shown exactly as Shopify returns it for the market, formatted with the user's
///   locale. Nothing is computed, rounded or converted; tax is never calculated.
/// - The compare-at price is shown only when it is higher than the price in the same currency.
/// - The savings badge shows the reduction as a percentage rounded down ("-80 %"), only when
///   the compare-at price is higher and the reduction is at least 1 %.
/// - Tax note: "inkl. MwSt." in EU markets (`CountryCode.isEUMember`), where Shopify's prices
///   include VAT; nothing in Switzerland and other non-EU markets. "zzgl. Versand" is added only
///   when the item requires shipping, never for digital keys.
/// - The lowest price of the last 30 days is shown only with a reduced price and only in the
///   price's currency; it comes from the store (`karinex.lowest_price_30d`), never from the app.
public struct PriceDisplay: Sendable, Hashable {
    /// The tax and shipping note shown below a price.
    public enum TaxNote: Sendable, Hashable, CaseIterable {
        /// "inkl. MwSt." (EU market, digital item).
        case includingVAT
        /// "inkl. MwSt., zzgl. Versand" (EU market, physical item).
        case includingVATPlusShipping
        /// "zzgl. Versand" (non-EU market, physical item).
        case plusShipping

        /// The localized note.
        public var text: String {
            switch self {
            case .includingVAT:
                String(localized: "commerce.price.tax.included", bundle: .module)
            case .includingVATPlusShipping:
                String(localized: "commerce.price.tax.included_plus_shipping", bundle: .module)
            case .plusShipping:
                String(localized: "commerce.price.tax.plus_shipping", bundle: .module)
            }
        }
    }

    /// The formatted price, e.g. "12,90 €".
    public let price: String
    /// The formatted compare-at price, or `nil` when there is no higher compare-at price.
    public let compareAtPrice: String?
    /// The reduction in percent, rounded down, or `nil` when there is none.
    public let savingsPercent: Int?
    /// The tax note, or `nil` when the market shows none.
    public let taxNote: TaxNote?
    /// The formatted lowest price of the last 30 days, or `nil` when it is not shown.
    public let lowestPrice: String?

    /// Creates the display strings for a price.
    ///
    /// - Parameters:
    ///   - price: The price from Shopify.
    ///   - compareAtPrice: The compare-at price from Shopify, if any.
    ///   - country: The country of the active market.
    ///   - requiresShipping: Whether the item is shipped (physical) rather than delivered digitally.
    ///   - locale: The locale used for formatting, normally the user's (`Locale.current` or the
    ///     SwiftUI `locale` environment value).
    ///   - lowestPrice: The store's lowest price of the last 30 days, if known.
    public init(
        price: MoneyV2,
        compareAtPrice: MoneyV2?,
        country: CountryCode,
        requiresShipping: Bool,
        locale: Locale,
        lowestPrice: MoneyV2? = nil
    ) {
        self.price = price.formatted(locale: locale)
        let isReduced = Self.isReduced(price: price, compareAtPrice: compareAtPrice)
        self.compareAtPrice = isReduced ? compareAtPrice?.formatted(locale: locale) : nil
        savingsPercent = Self.savingsPercent(price: price, compareAtPrice: compareAtPrice)
        taxNote = Self.taxNote(country: country, requiresShipping: requiresShipping)
        self.lowestPrice = if isReduced, let lowestPrice, lowestPrice.currencyCode == price.currencyCode, lowestPrice.amount > 0 {
            lowestPrice.formatted(locale: locale)
        } else {
            nil
        }
    }

    /// Creates the display strings for the lowest price of a product summary. A product whose
    /// shipping requirement is unknown counts as digital.
    public init(product: ProductSummary, country: CountryCode, locale: Locale) {
        self.init(
            price: product.price,
            compareAtPrice: product.compareAtPrice,
            country: country,
            requiresShipping: product.requiresShipping ?? false,
            locale: locale
        )
    }

    /// Creates the display strings for a product variant.
    public init(variant: ProductVariant, country: CountryCode, locale: Locale) {
        self.init(
            price: variant.price,
            compareAtPrice: variant.compareAtPrice,
            country: country,
            requiresShipping: variant.requiresShipping,
            locale: locale
        )
    }

    // MARK: Derived text

    /// The localized savings badge, e.g. "-80 %", or `nil`.
    public var savingsText: String? {
        savingsPercent.map { String(localized: "commerce.price.savings \($0)", bundle: .module) }
    }

    /// The localized tax note, or `nil`.
    public var taxNoteText: String? {
        taxNote?.text
    }

    // MARK: Rules

    /// Whether `compareAtPrice` is higher than `price` in the same currency.
    public static func isReduced(price: MoneyV2, compareAtPrice: MoneyV2?) -> Bool {
        guard let compareAtPrice, compareAtPrice.currencyCode == price.currencyCode else { return false }
        return compareAtPrice.amount > price.amount
    }

    /// The reduction from `compareAtPrice` to `price` in percent, rounded down; `nil` when the
    /// price is not reduced or the reduction is below 1 %.
    public static func savingsPercent(price: MoneyV2, compareAtPrice: MoneyV2?) -> Int? {
        guard isReduced(price: price, compareAtPrice: compareAtPrice), let compareAtPrice,
              compareAtPrice.amount > 0
        else { return nil }
        var ratio = (compareAtPrice.amount - price.amount) / compareAtPrice.amount * 100
        var roundedDown = Decimal()
        NSDecimalRound(&roundedDown, &ratio, 0, .down)
        let percent = NSDecimalNumber(decimal: roundedDown).intValue
        return percent >= 1 ? percent : nil
    }

    /// The tax note for a market and an item: "inkl. MwSt." only in the EU, "zzgl. Versand" only
    /// for physical items.
    public static func taxNote(country: CountryCode, requiresShipping: Bool) -> TaxNote? {
        switch (country.isEUMember, requiresShipping) {
        case (true, false):
            .includingVAT
        case (true, true):
            .includingVATPlusShipping
        case (false, true):
            .plusShipping
        case (false, false):
            nil
        }
    }
}

// MARK: - PriceText

/// A ``KXPriceTag`` for Shopify money: formats with the SwiftUI `locale` and takes the tax note
/// from the market country in the environment (`EnvironmentValues.commerceCountry`). A reduced
/// price is drawn in sale red; the product page passes the store's lowest price of the last 30
/// days.
///
/// ```swift
/// PriceText(price: variant.price, compareAtPrice: variant.compareAtPrice, requiresShipping: variant.requiresShipping)
/// ```
public struct PriceText: View {
    private let price: MoneyV2
    private let compareAtPrice: MoneyV2?
    private let requiresShipping: Bool
    private let size: KXPriceTag.Size
    private let showsSavings: Bool
    private let lowestPrice: MoneyV2?

    @Environment(\.locale) private var locale
    @Environment(\.commerceCountry) private var country

    /// Creates a price text.
    ///
    /// - Parameters:
    ///   - price: The price from Shopify.
    ///   - compareAtPrice: The compare-at price from Shopify, if any.
    ///   - requiresShipping: Whether the item is shipped. Digital keys pass `false`.
    ///   - size: The type scale. Defaults to `.regular`.
    ///   - showsSavings: Whether to show the savings badge. Defaults to `true`.
    ///   - lowestPrice: The store's lowest price of the last 30 days, shown with a reduced price.
    public init(
        price: MoneyV2,
        compareAtPrice: MoneyV2? = nil,
        requiresShipping: Bool,
        size: KXPriceTag.Size = .regular,
        showsSavings: Bool = true,
        lowestPrice: MoneyV2? = nil
    ) {
        self.price = price
        self.compareAtPrice = compareAtPrice
        self.requiresShipping = requiresShipping
        self.size = size
        self.showsSavings = showsSavings
        self.lowestPrice = lowestPrice
    }

    public var body: some View {
        let display = PriceDisplay(
            price: price,
            compareAtPrice: compareAtPrice,
            country: country,
            requiresShipping: requiresShipping,
            locale: locale,
            lowestPrice: lowestPrice
        )
        KXPriceTag(
            price: display.price,
            compareAtPrice: display.compareAtPrice,
            savings: showsSavings ? display.savingsText : nil,
            taxNote: display.taxNoteText,
            lowestPrice: display.lowestPrice,
            size: size
        )
    }
}

// MARK: - Previews

// Recorded from the live Storefront API on 2026-09-26: Windows 11 Pro (DE/DE) and Microsoft
// Office 2024 Professional Plus (CH/FR).
#Preview("PriceText") {
    VStack(alignment: .leading, spacing: KXSpacing.l) {
        PriceText(
            price: MoneyV2(amount: Decimal(string: "12.90") ?? 0, currencyCode: .eur),
            compareAtPrice: MoneyV2(amount: Decimal(string: "79.99") ?? 0, currencyCode: .eur),
            requiresShipping: false
        )
        PriceText(price: MoneyV2(amount: Decimal(string: "29.00") ?? 0, currencyCode: .chf), requiresShipping: false)
            .commerceCountry(.ch)
    }
    .padding(KXSpacing.gutter)
    .frame(maxWidth: .infinity, alignment: .leading)
    .kxScreenBackground()
    .environment(\.locale, Locale(identifier: "de_DE"))
}
