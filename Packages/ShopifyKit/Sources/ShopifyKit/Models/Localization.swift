import Foundation

// MARK: - Localization

/// The store's markets and languages (Storefront `Localization`).
///
/// `country` and `language` are the ones Shopify resolved for the request's `@inContext`;
/// `availableCountries` lists every country the store sells to with its currency and content
/// languages.
public struct Localization: Sendable, Hashable, Codable {
    /// The country of the request context.
    public let country: Country
    /// The language of the request context.
    public let language: Language
    /// Every country the store sells to.
    public let availableCountries: [Country]
    /// The content languages available for the request's country.
    public let availableLanguages: [Language]

    /// Creates a localization value.
    public init(country: Country, language: Language, availableCountries: [Country], availableLanguages: [Language]) {
        self.country = country
        self.language = language
        self.availableCountries = availableCountries
        self.availableLanguages = availableLanguages
    }

    /// The available country with `code`, or `nil` if the store does not sell there.
    public func country(for code: CountryCode) -> Country? {
        availableCountries.first { $0.isoCode == code }
    }

    /// Whether the store sells to `code`.
    public func sells(to code: CountryCode) -> Bool {
        country(for: code) != nil
    }
}

// MARK: - Country

/// A country the store sells to (Storefront `Country`).
public struct Country: Sendable, Hashable, Codable, Identifiable {
    /// The ISO code, e.g. `CH`.
    public let isoCode: CountryCode
    /// The name in the request's language, e.g. `Schweiz`.
    public let name: String
    /// The market currency.
    public let currency: Currency
    /// The content languages available in this country.
    public let availableLanguages: [Language]

    /// Creates a country.
    public init(isoCode: CountryCode, name: String, currency: Currency, availableLanguages: [Language]) {
        self.isoCode = isoCode
        self.name = name
        self.currency = currency
        self.availableLanguages = availableLanguages
    }

    /// The ISO code.
    public var id: CountryCode {
        isoCode
    }

    /// Whether `language` is available in this country.
    public func offers(_ language: LanguageCode) -> Bool {
        availableLanguages.contains { $0.isoCode == language }
    }
}

// MARK: - Currency

/// A market currency (Storefront `Currency`).
public struct Currency: Sendable, Hashable, Codable, Identifiable {
    /// The ISO code, e.g. `CHF`.
    public let isoCode: CurrencyCode
    /// The name in the request's language, e.g. `Schweizer Franken`.
    public let name: String
    /// The symbol, e.g. `CHF` or `€`.
    public let symbol: String

    /// Creates a currency.
    public init(isoCode: CurrencyCode, name: String, symbol: String) {
        self.isoCode = isoCode
        self.name = name
        self.symbol = symbol
    }

    /// The ISO code.
    public var id: CurrencyCode {
        isoCode
    }
}

// MARK: - Language

/// A content language (Storefront `Language`).
public struct Language: Sendable, Hashable, Codable, Identifiable {
    /// The Storefront code, e.g. `PT_PT`.
    public let isoCode: LanguageCode
    /// The name in the request's language, e.g. `Portugiesisch (Portugal)`.
    public let name: String
    /// The language's own name, e.g. `português (Portugal)`.
    public let endonymName: String

    /// Creates a language.
    public init(isoCode: LanguageCode, name: String, endonymName: String) {
        self.isoCode = isoCode
        self.name = name
        self.endonymName = endonymName
    }

    /// The Storefront code.
    public var id: LanguageCode {
        isoCode
    }
}
