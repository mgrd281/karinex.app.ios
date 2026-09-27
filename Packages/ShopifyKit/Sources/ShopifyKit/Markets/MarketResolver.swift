import Core
import Foundation

// MARK: - MarketSelection

/// The market (country) and content language the app uses for Storefront calls. Persisted
/// after the first-launch confirmation and changeable in Settings.
public struct MarketSelection: Sendable, Hashable, Codable {
    /// The buyer's country.
    public var country: CountryCode
    /// The content language.
    public var language: LanguageCode

    /// Creates a selection.
    public init(country: CountryCode, language: LanguageCode) {
        self.country = country
        self.language = language
    }

    /// The home market: Germany in German.
    public static let germany = MarketSelection(country: .de, language: .de)

    /// The Storefront context of this selection with the given consent.
    public func storefrontContext(visitorConsent: VisitorConsent? = nil) -> StorefrontContext {
        StorefrontContext(country: country, language: language, visitorConsent: visitorConsent)
    }
}

// MARK: - MarketResolution

/// The outcome of `MarketResolver.resolve(regionCode:preferredLanguages:localization:)`.
public struct MarketResolution: Sendable, Equatable {
    /// Why the resolver picked the selection.
    public enum Reason: Sendable, Hashable {
        /// The device region is sold and one of the preferred languages is available there.
        case deviceMatch
        /// The device region is unknown or not sold, so the default country was chosen. A
        /// preferred language was available in it.
        case countryUnavailable
        /// The device region is sold, but none of the preferred languages is both an app
        /// language and available there, so a fallback language was chosen.
        case languageUnavailable
        /// Neither the region nor any preferred language could be used.
        case countryAndLanguageUnavailable
    }

    /// The market and language to use.
    public let selection: MarketSelection
    /// Why this selection was chosen.
    public let reason: Reason

    /// Creates a resolution.
    public init(selection: MarketSelection, reason: Reason) {
        self.selection = selection
        self.reason = reason
    }

    /// Whether the device combination was not supported and a fallback was chosen. The
    /// first-launch confirmation sheet explains the adjustment once.
    public var wasAdjusted: Bool {
        reason != .deviceMatch
    }
}

// MARK: - MarketResolver

/// Maps the device region and preferred languages to a market and language the store supports.
///
/// Rules:
/// - Country: the device region when the store sells there, else `defaultCountry` (`DE`).
/// - Language: the first preferred language that is one of the 11 app languages and available
///   for that country in the store (`pt` and `pt-BR` count as `PT_PT`, `de-AT` as `DE`).
///   Otherwise the first of `fallbackLanguages` (`EN`, then `DE`) available in the country,
///   then the first app language the country offers, then the country's first language. A
///   country without any listed language keeps the first fallback language.
///
/// ```swift
/// let resolution = MarketResolver().resolve(
///     regionCode: Locale.current.region?.identifier,
///     preferredLanguages: Locale.preferredLanguages,
///     localization: localization
/// )
/// ```
public struct MarketResolver: Sendable {
    /// The country used when the device region is unknown or not sold.
    public let defaultCountry: CountryCode
    /// The languages tried, in order, when no preferred language is available.
    public let fallbackLanguages: [LanguageCode]

    /// Creates a resolver.
    ///
    /// - Parameters:
    ///   - defaultCountry: The fallback country, `DE` by default.
    ///   - fallbackLanguages: The fallback languages in order, `[EN, DE]` by default.
    public init(defaultCountry: CountryCode = .de, fallbackLanguages: [LanguageCode] = [.en, .de]) {
        self.defaultCountry = defaultCountry
        self.fallbackLanguages = fallbackLanguages
    }

    /// Resolves the market and language.
    ///
    /// - Parameters:
    ///   - regionCode: The device region, e.g. `Locale.current.region?.identifier` (`CH`), or `nil`.
    ///   - preferredLanguages: BCP 47 identifiers in preference order, e.g.
    ///     `Locale.preferredLanguages` (`["fr-CH", "de-CH"]`).
    ///   - localization: The store localization from `LocalizationRepository`.
    public func resolve(regionCode: String?, preferredLanguages: [String], localization: Localization) -> MarketResolution {
        let requestedCountry = regionCode.map(CountryCode.init(rawValue:))
        let soldCountry = requestedCountry.flatMap { localization.country(for: $0) }
        let country = soldCountry ?? localization.country(for: defaultCountry)
        let countryCode = soldCountry?.isoCode ?? defaultCountry
        let countryAdjusted = soldCountry == nil

        let availableLanguages = country?.availableLanguages.map(\.isoCode) ?? []
        let preferred = preferredLanguages
            .compactMap(AppLanguage.init(bcp47:))
            .map(LanguageCode.init(appLanguage:))
            .first { availableLanguages.contains($0) }

        let language = preferred ?? fallbackLanguage(availableLanguages: availableLanguages)
        let languageAdjusted = preferred == nil

        let reason: MarketResolution.Reason = switch (countryAdjusted, languageAdjusted) {
        case (false, false): .deviceMatch
        case (true, false): .countryUnavailable
        case (false, true): .languageUnavailable
        case (true, true): .countryAndLanguageUnavailable
        }
        return MarketResolution(selection: MarketSelection(country: countryCode, language: language), reason: reason)
    }

    /// Picks the fallback language for a country offering `availableLanguages`.
    private func fallbackLanguage(availableLanguages: [LanguageCode]) -> LanguageCode {
        if let fallback = fallbackLanguages.first(where: availableLanguages.contains) {
            return fallback
        }
        if let appLanguage = availableLanguages.first(where: { $0.appLanguage != nil }) {
            return appLanguage
        }
        return availableLanguages.first ?? fallbackLanguages.first ?? .de
    }
}
