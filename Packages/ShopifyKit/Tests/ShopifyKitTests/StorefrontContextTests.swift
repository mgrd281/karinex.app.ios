import Core
import Foundation
@testable import ShopifyKit
import Testing

@Suite("StorefrontContext and VisitorConsent")
struct StorefrontContextTests {
    @Test("Renders the full directive")
    func fullDirective() {
        let context = StorefrontContext(
            country: .de,
            language: .ptPT,
            visitorConsent: VisitorConsent(analytics: false, preferences: true, marketing: false, saleOfData: false)
        )
        let expected = "@inContext(country: DE, language: PT_PT, "
            + "visitorConsent: {analytics: false, preferences: true, marketing: false, saleOfData: false})"
        #expect(context.directive == expected)
    }

    @Test("Omits a missing or empty consent and nil consent fields")
    func omissions() {
        #expect(StorefrontContext(country: .ch, language: .fr).directive == "@inContext(country: CH, language: FR)")
        #expect(
            StorefrontContext(country: .ch, language: .fr, visitorConsent: VisitorConsent()).directive
                == "@inContext(country: CH, language: FR)"
        )
        #expect(
            StorefrontContext(country: .ch, language: .fr, visitorConsent: VisitorConsent(analytics: true)).directive
                == "@inContext(country: CH, language: FR, visitorConsent: {analytics: true})"
        )
    }

    @Test("Never writes values that are not GraphQL enum values into the document")
    func invalidCodesAreOmitted() {
        let context = StorefrontContext(country: CountryCode(rawValue: "DE) { evil }"), language: LanguageCode(rawValue: "1X"))
        #expect(context.directive == "@inContext")
        let partly = StorefrontContext(country: .at, language: LanguageCode(rawValue: "de de"))
        #expect(partly.directive == "@inContext(country: AT)")
    }

    @Test("Maps the app's privacy consent: analytics as chosen, preferences on, marketing and sale of data off")
    func consentMapping() {
        #expect(
            VisitorConsent(privacyConsent: .undecided)
                == VisitorConsent(analytics: false, preferences: true, marketing: false, saleOfData: false)
        )
        var consent = PrivacyConsent.undecided
        consent.analytics = true
        consent.dealNotifications = true
        #expect(
            VisitorConsent(privacyConsent: consent)
                == VisitorConsent(analytics: true, preferences: true, marketing: false, saleOfData: false)
        )
    }

    @Test("with(visitorConsent:) replaces only the consent")
    func withConsent() {
        let context = StorefrontContext.germany.with(visitorConsent: VisitorConsent(preferences: true))
        #expect(context.country == .de)
        #expect(context.language == .de)
        #expect(context.visitorConsent == VisitorConsent(preferences: true))
    }

    @Test("Context providers")
    func providers() async {
        #expect(await StaticStorefrontContextProvider().currentContext() == .germany)
        let provider = MutableStorefrontContextProvider(context: .germany)
        provider.update(to: switzerlandFrenchContext)
        #expect(await provider.currentContext() == switzerlandFrenchContext)
        #expect(provider.context.country == .ch)
    }
}

@Suite("StorefrontConfiguration")
struct StorefrontConfigurationTests {
    @Test("Built from the app configuration, tokenless without a token")
    func fromAppConfiguration() {
        let configuration = StorefrontConfiguration(appConfiguration: .preview)
        #expect(configuration.endpoint.absoluteString == "https://45dv93-bk.myshopify.com/api/2026-07/graphql.json")
        #expect(configuration.apiVersion == "2026-07")
        #expect(configuration.isTokenless)
        #expect(configuration.headers.isEmpty)
    }

    @Test("A token becomes the access token header; a blank token counts as none")
    func token() {
        let endpoint = AppConfiguration.preview.storefrontEndpoint
        let configuration = StorefrontConfiguration(endpoint: endpoint, accessToken: " public-token ", apiVersion: "2026-07")
        #expect(!configuration.isTokenless)
        #expect(configuration.headers == ["X-Shopify-Storefront-Access-Token": "public-token"])
        #expect(StorefrontConfiguration(endpoint: endpoint, accessToken: "  ", apiVersion: "2026-07").isTokenless)
    }

    @Test("Descriptions never contain the token")
    func maskedDescription() {
        let configuration = StorefrontConfiguration(
            endpoint: AppConfiguration.preview.storefrontEndpoint,
            accessToken: "public-token-value",
            apiVersion: "2026-07"
        )
        #expect(!configuration.description.contains("public-token-value"))
        #expect(!String(reflecting: configuration).contains("public-token-value"))
        var dumped = ""
        dump(configuration, to: &dumped)
        #expect(!dumped.contains("public-token-value"))
        #expect(configuration.description.contains("<redacted>"))
    }
}
