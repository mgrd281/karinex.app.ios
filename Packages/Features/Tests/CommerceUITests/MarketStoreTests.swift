@testable import CommerceUI
import Core
import Foundation
import ShopifyKit
import Testing

@MainActor
@Suite("MarketStore")
struct MarketStoreTests {
    private let preferences = InMemoryKeyValueStore()
    private let consentPreferences = InMemoryKeyValueStore()
    private let contextProvider = MutableStorefrontContextProvider(context: .germany)

    private func makeStore(
        region: String?,
        languages: [String],
        repository: any LocalizationRepository = FixedLocalizationRepository(result: .success(CommercePreviewData.localization))
    ) -> MarketStore {
        MarketStore(
            localizationRepository: repository,
            contextProvider: contextProvider,
            consentStore: ConsentStore(store: consentPreferences),
            store: preferences,
            regionCode: { region },
            preferredLanguages: { languages }
        )
    }

    @Test("First launch resolves the device market, persists it and asks for confirmation once")
    func firstLaunch() async throws {
        let store = makeStore(region: "CH", languages: ["fr-CH", "de-CH"])
        await store.start()

        let expected = MarketSelection(country: .ch, language: .fr)
        #expect(store.selection == expected)
        #expect(store.resolution?.reason == .deviceMatch)
        #expect(store.needsConfirmation)
        #expect(contextProvider.context.country == .ch)
        #expect(contextProvider.context.language == .fr)
        #expect(try preferences.value(MarketSelection.self, forKey: MarketStore.selectionKey) == expected)

        store.confirm()
        #expect(!store.needsConfirmation)

        let relaunched = makeStore(region: "DE", languages: ["de-DE"])
        #expect(relaunched.selection == expected)
        await relaunched.start()
        #expect(relaunched.selection == expected)
        #expect(!relaunched.needsConfirmation)
        #expect(relaunched.resolution == nil)
    }

    @Test("A region the store does not sell to falls back to Germany and explains why")
    func unsoldRegion() async {
        let store = makeStore(region: "US", languages: ["en-US"])
        await store.start()

        #expect(store.selection == MarketSelection(country: .de, language: .en))
        #expect(store.resolution?.reason == .countryUnavailable)
        #expect(store.needsConfirmation)
    }

    @Test("An unconfirmed selection asks again on the next launch")
    func unconfirmedAsksAgain() async {
        let first = makeStore(region: "AT", languages: ["de-AT"])
        await first.start()

        let relaunched = makeStore(region: "AT", languages: ["de-AT"])
        await relaunched.start()
        #expect(relaunched.needsConfirmation)
    }

    @Test("Selecting another country reports the change and pushes the context")
    func selectReportsCountryChange() async {
        let store = makeStore(region: "DE", languages: ["de-DE"])
        let recorder = CountryRecorder()
        store.onCountryChange = { recorder.countries.append($0) }
        await store.start()
        #expect(recorder.countries.isEmpty)

        await store.select(country: .at, language: .de)
        await store.select(country: .at, language: .en)

        #expect(recorder.countries == [.at])
        #expect(store.selection == MarketSelection(country: .at, language: .en))
        #expect(contextProvider.context.language == .en)
    }

    @Test("A language the country does not offer is replaced by an offered one")
    func unofferedLanguageIsReplaced() async {
        let store = makeStore(region: "DE", languages: ["de-DE"])
        await store.start()

        await store.select(country: .nl, language: .de)

        #expect(store.selection == MarketSelection(country: .nl, language: .nl))
    }

    @Test("A country the store does not sell to is ignored")
    func unsoldSelectionIsIgnored() async {
        let store = makeStore(region: "DE", languages: ["de-DE"])
        await store.start()

        await store.select(country: .us, language: .en)

        #expect(store.selection == MarketSelection(country: .de, language: .de))
    }

    @Test("The visitor consent travels with the context")
    func consentInContext() async {
        ConsentStore(store: consentPreferences).save(
            PrivacyConsent(analytics: true, decidedAt: Date(timeIntervalSince1970: 0))
        )
        let store = makeStore(region: "DE", languages: ["de-DE"])
        await store.start()

        #expect(contextProvider.context.visitorConsent?.analytics == true)
        #expect(contextProvider.context.visitorConsent?.marketing == false)
    }

    @Test("A failure to load the markets keeps the current selection and reports the error")
    func loadFailure() async {
        let store = makeStore(
            region: "CH",
            languages: ["fr-CH"],
            repository: FixedLocalizationRepository(result: .failure(ShopifyError.network(.offline)))
        )
        await store.start()

        #expect(store.selection == .germany)
        #expect(store.lastError?.kind == .offline)
        #expect(!store.needsConfirmation)
    }
}

/// Answers `localization()` with a fixed result.
private struct FixedLocalizationRepository: LocalizationRepository {
    let result: Result<Localization, ShopifyError>

    func localization() async throws -> Localization {
        try result.get()
    }
}

/// Collects the countries reported by `onCountryChange`.
@MainActor
private final class CountryRecorder {
    var countries: [CountryCode] = []
}
