import Foundation

/// An amount of money in a currency, as returned by the Storefront API (`MoneyV2`).
///
/// Shopify sends the amount as a decimal string (`"29.9"`), which is parsed exactly into a
/// `Decimal` with a POSIX parser, never through `Double`. Amounts are shown exactly as returned
/// for the active market; the app never computes tax.
public struct MoneyV2: Sendable, Hashable, Codable, CustomStringConvertible {
    /// The amount, e.g. `29.9`.
    public let amount: Decimal
    /// The currency, e.g. `EUR`.
    public let currencyCode: CurrencyCode

    /// Creates a money value.
    public init(amount: Decimal, currencyCode: CurrencyCode) {
        self.amount = amount
        self.currencyCode = currencyCode
    }

    /// Parses a decimal string such as `"29.90"` or `"-3.5"` into a money value.
    ///
    /// - Returns: `nil` unless `amount` is a plain decimal number with `.` as separator.
    public init?(amount: String, currencyCode: CurrencyCode) {
        guard let decimal = Self.parseAmount(amount) else { return nil }
        self.init(amount: decimal, currencyCode: currencyCode)
    }

    // MARK: - Formatting

    /// The amount formatted as currency for `locale`, e.g. `29,90 €` for `de_DE` or
    /// `CHF 29.00` for `de_CH`.
    public func formatted(locale: Locale) -> String {
        amount.formatted(Decimal.FormatStyle.Currency(code: currencyCode.rawValue, locale: locale))
    }

    /// Whether the amount is zero, as Shopify reports for a missing compare-at price range.
    public var isZero: Bool {
        amount.isZero
    }

    /// A POSIX rendering for logs and debugging, e.g. `29.9 EUR`.
    public var description: String {
        "\(Self.posixString(amount)) \(currencyCode.rawValue)"
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case amount
        case currencyCode
    }

    /// Decodes `{"amount": "29.9", "currencyCode": "EUR"}`. A JSON number is accepted too.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        currencyCode = try container.decode(CurrencyCode.self, forKey: .currencyCode)
        if let string = try? container.decode(String.self, forKey: .amount) {
            guard let decimal = Self.parseAmount(string) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .amount,
                    in: container,
                    debugDescription: "The amount is not a decimal number."
                )
            }
            amount = decimal
        } else {
            amount = try container.decode(Decimal.self, forKey: .amount)
        }
    }

    /// Encodes the amount as a POSIX decimal string, like Shopify does.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.posixString(amount), forKey: .amount)
        try container.encode(currencyCode, forKey: .currencyCode)
    }

    // MARK: - Parsing

    private static let posixLocale = Locale(identifier: "en_US_POSIX")

    /// Parses `-?[0-9]+(\.[0-9]+)?` (surrounding white space allowed) with a POSIX locale.
    static func parseAmount(_ string: String) -> Decimal? {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        var digits = Substring(trimmed)
        if digits.first == "-" {
            digits = digits.dropFirst()
        }
        let parts = digits.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count),
              parts.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (UInt8(ascii: "0")...UInt8(ascii: "9")).contains($0) } })
        else { return nil }
        return Decimal(string: trimmed, locale: posixLocale)
    }

    /// `Decimal.description` is locale-independent and uses `.` as separator.
    static func posixString(_ decimal: Decimal) -> String {
        decimal.description
    }
}
