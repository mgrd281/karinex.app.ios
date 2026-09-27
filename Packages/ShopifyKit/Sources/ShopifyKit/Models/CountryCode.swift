import Core
import Foundation

// MARK: - CountryCode

/// An ISO 3166-1 alpha-2 country code as used by the Storefront API `CountryCode` enum,
/// e.g. `DE` or `CH`.
///
/// Modeled as an open string wrapper instead of a closed enum so that countries the store adds
/// later decode without an app update. Values are normalized to upper case.
public struct CountryCode: RawRepresentable, Sendable, Hashable, Codable, Comparable, ExpressibleByStringLiteral,
    CustomStringConvertible
{
    /// The upper-case ISO code, e.g. `DE`.
    public let rawValue: String

    /// Creates a code from `rawValue`, trimmed and upper-cased.
    public init(rawValue: String) {
        self.rawValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    /// Creates a code from a string literal, e.g. `"DE"`.
    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }

    /// Decodes the code from a single string value.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(rawValue: container.decode(String.self))
    }

    /// Encodes the code as a single string value.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    /// The ISO code.
    public var description: String {
        rawValue
    }

    /// Orders codes alphabetically.
    public static func < (lhs: CountryCode, rhs: CountryCode) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Whether the value can be written into a GraphQL document as an enum value
    /// (`[A-Z][A-Z0-9_]*`). Only such values are rendered into `@inContext`.
    public var isValidGraphQLEnumValue: Bool {
        GraphQLEnumValue.isValid(rawValue)
    }

    // MARK: - Store countries

    /// Austria.
    public static let at: CountryCode = "AT"
    /// Belgium.
    public static let be: CountryCode = "BE"
    /// Bulgaria.
    public static let bg: CountryCode = "BG"
    /// Switzerland (currency CHF).
    public static let ch: CountryCode = "CH"
    /// Cyprus.
    public static let cy: CountryCode = "CY"
    /// Czechia (currency CZK).
    public static let cz: CountryCode = "CZ"
    /// Germany, the home market and default country.
    public static let de: CountryCode = "DE"
    /// Denmark (currency DKK).
    public static let dk: CountryCode = "DK"
    /// Estonia.
    public static let ee: CountryCode = "EE"
    /// Spain.
    public static let es: CountryCode = "ES"
    /// Finland.
    public static let fi: CountryCode = "FI"
    /// France.
    public static let fr: CountryCode = "FR"
    /// Greece.
    public static let gr: CountryCode = "GR"
    /// Croatia.
    public static let hr: CountryCode = "HR"
    /// Hungary (currency HUF).
    public static let hu: CountryCode = "HU"
    /// Ireland.
    public static let ie: CountryCode = "IE"
    /// Italy.
    public static let it: CountryCode = "IT"
    /// Lithuania.
    public static let lt: CountryCode = "LT"
    /// Luxembourg.
    public static let lu: CountryCode = "LU"
    /// Latvia.
    public static let lv: CountryCode = "LV"
    /// Malta.
    public static let mt: CountryCode = "MT"
    /// The Netherlands.
    public static let nl: CountryCode = "NL"
    /// Norway.
    public static let no: CountryCode = "NO"
    /// Poland (currency PLN).
    public static let pl: CountryCode = "PL"
    /// Portugal.
    public static let pt: CountryCode = "PT"
    /// Romania (currency RON).
    public static let ro: CountryCode = "RO"
    /// Sweden (currency SEK).
    public static let se: CountryCode = "SE"
    /// Slovenia.
    public static let si: CountryCode = "SI"
    /// Slovakia.
    public static let sk: CountryCode = "SK"
    /// The United States.
    public static let us: CountryCode = "US"

    /// The 28 countries the store sold to when the Storefront `localization` was recorded on
    /// 2026-09-26. The live `Localization` is authoritative; this list is for previews and tests.
    public static let recordedStoreCountries: [CountryCode] = [
        .at, .be, .bg, .ch, .cy, .cz, .de, .dk, .ee, .es, .fi, .fr, .gr, .hr,
        .hu, .ie, .it, .lt, .lu, .lv, .mt, .nl, .pl, .pt, .ro, .se, .si, .sk,
    ]
}

// MARK: - LanguageCode

/// A Storefront API `LanguageCode` enum value, e.g. `DE` or `PT_PT`.
///
/// Values are normalized to upper case with `_` as separator, so `pt-PT` becomes `PT_PT`.
public struct LanguageCode: RawRepresentable, Sendable, Hashable, Codable, Comparable, ExpressibleByStringLiteral,
    CustomStringConvertible
{
    /// The Storefront enum value, e.g. `PT_PT`.
    public let rawValue: String

    /// Creates a code from `rawValue`, trimmed, upper-cased and with `-` replaced by `_`.
    public init(rawValue: String) {
        self.rawValue = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(of: "-", with: "_")
    }

    /// Creates a code from a string literal, e.g. `"PT_PT"`.
    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }

    /// The Storefront language of an app UI language: `de` becomes `DE`, `pt-PT` becomes `PT_PT`.
    public init(appLanguage: AppLanguage) {
        switch appLanguage {
        case .ptPT:
            self = .ptPT
        default:
            self.init(rawValue: appLanguage.rawValue)
        }
    }

    /// Decodes the code from a single string value.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(rawValue: container.decode(String.self))
    }

    /// Encodes the code as a single string value.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    /// The Storefront enum value.
    public var description: String {
        rawValue
    }

    /// Orders codes alphabetically.
    public static func < (lhs: LanguageCode, rhs: LanguageCode) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// The app UI language for this content language, or `nil` when the app is not localized
    /// into it (for example `EL` or `RO`). Every Portuguese variant maps to `.ptPT`.
    public var appLanguage: AppLanguage? {
        AppLanguage(bcp47: rawValue.replacingOccurrences(of: "_", with: "-"))
    }

    /// Whether the value can be written into a GraphQL document as an enum value
    /// (`[A-Z][A-Z0-9_]*`). Only such values are rendered into `@inContext`.
    public var isValidGraphQLEnumValue: Bool {
        GraphQLEnumValue.isValid(rawValue)
    }

    // MARK: - Store languages

    /// Danish.
    public static let da: LanguageCode = "DA"
    /// German, the store's primary language.
    public static let de: LanguageCode = "DE"
    /// Greek (a store content language, not an app UI language).
    public static let el: LanguageCode = "EL"
    /// English.
    public static let en: LanguageCode = "EN"
    /// Spanish.
    public static let es: LanguageCode = "ES"
    /// Finnish.
    public static let fi: LanguageCode = "FI"
    /// French.
    public static let fr: LanguageCode = "FR"
    /// Italian.
    public static let it: LanguageCode = "IT"
    /// Dutch.
    public static let nl: LanguageCode = "NL"
    /// Polish.
    public static let pl: LanguageCode = "PL"
    /// European Portuguese.
    public static let ptPT: LanguageCode = "PT_PT"
    /// Romanian (a store content language, not an app UI language).
    public static let ro: LanguageCode = "RO"
    /// Swedish.
    public static let sv: LanguageCode = "SV"

    /// The 13 content languages of the store when the Storefront `localization` was recorded
    /// on 2026-09-26. The live `Localization` is authoritative.
    public static let recordedStoreLanguages: [LanguageCode] = [
        .da, .de, .el, .en, .es, .fi, .fr, .it, .nl, .pl, .ptPT, .ro, .sv,
    ]
}

// MARK: - CurrencyCode

/// An ISO 4217 currency code as used by the Storefront API `CurrencyCode` enum, e.g. `EUR`.
public struct CurrencyCode: RawRepresentable, Sendable, Hashable, Codable, Comparable, ExpressibleByStringLiteral,
    CustomStringConvertible
{
    /// The upper-case ISO code, e.g. `EUR`.
    public let rawValue: String

    /// Creates a code from `rawValue`, trimmed and upper-cased.
    public init(rawValue: String) {
        self.rawValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    /// Creates a code from a string literal, e.g. `"EUR"`.
    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }

    /// Decodes the code from a single string value.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(rawValue: container.decode(String.self))
    }

    /// Encodes the code as a single string value.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    /// The ISO code.
    public var description: String {
        rawValue
    }

    /// Orders codes alphabetically.
    public static func < (lhs: CurrencyCode, rhs: CurrencyCode) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    // MARK: - Store currencies

    /// Swiss franc.
    public static let chf: CurrencyCode = "CHF"
    /// Czech koruna.
    public static let czk: CurrencyCode = "CZK"
    /// Danish krone.
    public static let dkk: CurrencyCode = "DKK"
    /// Euro, the store's base currency.
    public static let eur: CurrencyCode = "EUR"
    /// Hungarian forint.
    public static let huf: CurrencyCode = "HUF"
    /// Norwegian krone.
    public static let nok: CurrencyCode = "NOK"
    /// Polish zloty.
    public static let pln: CurrencyCode = "PLN"
    /// Romanian leu.
    public static let ron: CurrencyCode = "RON"
    /// Swedish krona.
    public static let sek: CurrencyCode = "SEK"
    /// US dollar.
    public static let usd: CurrencyCode = "USD"
}

// MARK: - GraphQL enum validation

/// Validation of GraphQL enum values that are rendered into documents.
enum GraphQLEnumValue {
    /// Whether `value` matches `[A-Z][A-Z0-9_]*`, the shape of every Storefront enum value.
    /// Anything else must never be written into a document.
    static func isValid(_ value: String) -> Bool {
        guard let first = value.utf8.first, (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(first) else {
            return false
        }
        return value.utf8.allSatisfy { byte in
            (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte)
                || (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
                || byte == UInt8(ascii: "_")
        }
    }
}
