import Core
import Foundation
@testable import ShopifyKit
import Testing

/// Uses the recorded store localization (28 countries; 13 languages everywhere except the
/// Netherlands, which only offer NL).
@Suite("MarketResolver")
struct MarketResolverTests {
    private let resolver = MarketResolver()

    private func localization() throws -> Localization {
        let response = try JSONDecoder().decode(
            GraphQLResponse<LocalizationQuery.ResponseData>.self,
            from: Fixture.data(Fixture.localization)
        )
        return try #require(response.data?.localization)
    }

    private func resolve(_ region: String?, _ languages: [String]) throws -> MarketResolution {
        try resolver.resolve(regionCode: region, preferredLanguages: languages, localization: localization())
    }

    @Test("Switzerland with French UI: CH/FR, not adjusted")
    func switzerlandFrench() throws {
        let resolution = try resolve("CH", ["fr-CH", "de-CH"])
        #expect(resolution.selection == MarketSelection(country: .ch, language: .fr))
        #expect(resolution.reason == .deviceMatch)
        #expect(!resolution.wasAdjusted)
    }

    @Test("Austria with de-AT: AT/DE, not adjusted")
    func austria() throws {
        let resolution = try resolve("AT", ["de-AT"])
        #expect(resolution.selection == MarketSelection(country: .at, language: .de))
        #expect(!resolution.wasAdjusted)
    }

    @Test("US region is not sold: DE with the preferred English, adjusted")
    func unitedStates() throws {
        let resolution = try resolve("US", ["en-US"])
        #expect(resolution.selection == MarketSelection(country: .de, language: .en))
        #expect(resolution.reason == .countryUnavailable)
        #expect(resolution.wasAdjusted)
    }

    @Test("Brazilian Portuguese maps to PT_PT")
    func brazilianPortuguese() throws {
        let resolution = try resolve("PT", ["pt-BR"])
        #expect(resolution.selection == MarketSelection(country: .pt, language: .ptPT))
        #expect(!resolution.wasAdjusted)
        #expect(try resolve("PT", ["pt"]).selection.language == .ptPT)
        #expect(try resolve("PT", ["pt_PT"]).selection.language == .ptPT)
    }

    @Test("Greek UI: EL is a store language but not an app language, so EN")
    func greek() throws {
        let resolution = try resolve("GR", ["el-GR"])
        #expect(resolution.selection == MarketSelection(country: .gr, language: .en))
        #expect(resolution.reason == .languageUnavailable)
        #expect(resolution.wasAdjusted)
    }

    @Test("The first usable preferred language wins")
    func preferenceOrder() throws {
        let resolution = try resolve("CH", ["el-GR", "ro-RO", "it-CH", "de-CH"])
        #expect(resolution.selection == MarketSelection(country: .ch, language: .it))
        #expect(!resolution.wasAdjusted)
    }

    @Test("Unknown region falls back to DE")
    func unknownRegion() throws {
        let resolution = try resolve(nil, ["de-DE"])
        #expect(resolution.selection == .germany)
        #expect(resolution.reason == .countryUnavailable)
        #expect(try resolve("150", ["de"]).selection.country == .de)
    }

    @Test("Region codes are case-insensitive")
    func lowercaseRegion() throws {
        #expect(try resolve("se", ["sv-SE"]).selection == MarketSelection(country: .se, language: .sv))
    }

    @Test("Neither region nor language usable: DE/EN")
    func nothingUsable() throws {
        let resolution = try resolve("US", ["el", "zh-Hans-US"])
        #expect(resolution.selection == MarketSelection(country: .de, language: .en))
        #expect(resolution.reason == .countryAndLanguageUnavailable)
    }

    @Test("The Netherlands only offer NL: an English device gets NL content")
    func netherlands() throws {
        let resolution = try resolve("NL", ["en-GB"])
        #expect(resolution.selection == MarketSelection(country: .nl, language: .nl))
        #expect(resolution.reason == .languageUnavailable)
        #expect(try resolve("NL", ["nl-NL"]).reason == .deviceMatch)
    }

    @Test("No preferred languages at all: EN")
    func noLanguages() throws {
        #expect(try resolve("FR", []).selection == MarketSelection(country: .fr, language: .en))
    }

    @Test("A custom default country and fallback order are honored")
    func customFallbacks() throws {
        let custom = MarketResolver(defaultCountry: .at, fallbackLanguages: [.de])
        let resolution = try custom.resolve(regionCode: "US", preferredLanguages: ["el"], localization: localization())
        #expect(resolution.selection == MarketSelection(country: .at, language: .de))
    }

    @Test("A default country the store does not sell to falls back to the first sold country")
    func defaultCountryNotSold() throws {
        let full = try localization()
        let withoutGermany = Localization(
            country: full.country,
            language: full.language,
            availableCountries: full.availableCountries.filter { $0.isoCode != .de },
            availableLanguages: full.availableLanguages
        )
        let resolution = resolver.resolve(regionCode: "US", preferredLanguages: ["de-DE"], localization: withoutGermany)
        #expect(resolution.selection == MarketSelection(country: .at, language: .de))
        #expect(resolution.reason == .countryUnavailable)
        #expect(withoutGermany.sells(to: resolution.selection.country))

        let nothingSold = Localization(country: full.country, language: full.language, availableCountries: [], availableLanguages: [])
        let fallback = resolver.resolve(regionCode: "DE", preferredLanguages: ["de"], localization: nothingSold)
        #expect(fallback.selection == MarketSelection(country: .de, language: .en))
        #expect(fallback.reason == .countryAndLanguageUnavailable)
    }

    @Test("A selection builds the Storefront context")
    func storefrontContext() {
        let selection = MarketSelection(country: .ch, language: .fr)
        let context = selection.storefrontContext(visitorConsent: VisitorConsent(privacyConsent: .undecided))
        #expect(context == switzerlandFrenchContext)
    }
}
