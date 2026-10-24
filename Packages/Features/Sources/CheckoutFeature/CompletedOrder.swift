import Foundation
import ShopifyKit

// MARK: - CompletedOrder

/// The summary of an order that Shopify checkout reported as completed, in the app's own
/// `Sendable` form.
///
/// It keeps only what the success screen needs: Shopify's order identifier, the formatted
/// total and whether the buyer gave an e-mail address. The address itself and every other
/// personal or payment detail of the checkout event are never copied, stored or logged.
public struct CompletedOrder: Sendable, Hashable, Identifiable {
    /// Shopify's identifier of the order, as reported by checkout.
    public let id: String
    /// Whether the buyer entered an e-mail address in checkout (the license key is sent there).
    public let hasEmail: Bool
    /// The order total formatted for the user's locale, e.g. "29,90 €", or `nil` when checkout
    /// did not report one.
    public let formattedTotal: String?

    /// Creates a summary from values that are already prepared.
    public init(id: String, hasEmail: Bool, formattedTotal: String?) {
        self.id = id
        self.hasEmail = hasEmail
        self.formattedTotal = formattedTotal
    }

    /// Creates a summary from the raw values of a checkout completion.
    ///
    /// - Parameters:
    ///   - id: Shopify's order identifier.
    ///   - email: The buyer's e-mail address. Only its presence is kept.
    ///   - totalAmount: The order total as reported by checkout.
    ///   - currencyCode: The ISO 4217 code of the total, e.g. `EUR`.
    ///   - locale: The locale the total is formatted with.
    public init(id: String, email: String?, totalAmount: Double?, currencyCode: String?, locale: Locale) {
        let trimmedEmail = email?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.init(
            id: id,
            hasEmail: !trimmedEmail.isEmpty,
            formattedTotal: Self.formattedTotal(amount: totalAmount, currencyCode: currencyCode, locale: locale)
        )
    }

    /// The total as Shopify money formatted for `locale`, or `nil` when the amount or the
    /// currency is missing or unusable. Nothing is rounded or converted.
    static func formattedTotal(amount: Double?, currencyCode: String?, locale: Locale) -> String? {
        guard let amount, amount.isFinite, amount >= 0,
              let code = currencyCode?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
              code.count == 3, code.unicodeScalars.allSatisfy({ ("A"..."Z").contains($0) }),
              let decimal = Decimal(string: String(amount), locale: Locale(identifier: "en_US_POSIX"))
        else { return nil }
        return MoneyV2(amount: decimal, currencyCode: CurrencyCode(rawValue: code)).formatted(locale: locale)
    }
}
