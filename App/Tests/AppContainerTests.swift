import Core
import Foundation
@testable import KARINEX
import ShopifyKit
import Testing

// MARK: - Fixtures

/// `Info.plist` values as the build injects them from `Config/Base.xcconfig` (no secrets set).
private func validInfoDictionary(
    storefrontAccessToken: String = "",
    appVersion: String = "0.1.0",
    buildNumber: String = "42"
) -> [String: Any] {
    [
        AppConfiguration.InfoKey.shopDomain: "45dv93-bk.myshopify.com",
        AppConfiguration.InfoKey.storeWebDomain: "www.karinex.de",
        AppConfiguration.InfoKey.storefrontAPIVersion: "2026-07",
        AppConfiguration.InfoKey.storefrontAccessToken: storefrontAccessToken,
        AppConfiguration.InfoKey.customerAccountAPIVersion: "2026-07",
        AppConfiguration.InfoKey.customerAccountClientID: "$(KX_CUSTOMER_ACCOUNT_CLIENT_ID)",
        AppConfiguration.InfoKey.appVersion: appVersion,
        AppConfiguration.InfoKey.buildNumber: buildNumber,
    ]
}

// MARK: - AppContainer

@MainActor
@Suite("AppContainer")
struct AppContainerTests {
    private func makeContainer(
        infoDictionary: [String: Any] = validInfoDictionary(),
        launchEnvironment: LaunchEnvironment = LaunchEnvironment(),
        launchArguments: [String] = [],
        services: AppServices = .inMemory(),
        sink: RecordingLogSink = RecordingLogSink()
    ) -> AppContainer {
        AppContainer(
            configuration: ConfigurationResolution(infoDictionary: infoDictionary),
            launchEnvironment: launchEnvironment,
            launchArguments: launchArguments,
            services: services,
            logger: KXLogger(category: .app, sink: sink)
        )
    }

    @Test("Builds from a valid info dictionary")
    func buildsFromValidInfoDictionary() throws {
        let sink = RecordingLogSink()
        let container = makeContainer(sink: sink)

        #expect(container.configurationFailure == nil)
        #expect(container.configuration.shopDomain == "45dv93-bk.myshopify.com")
        #expect(container.configuration.storeWebDomain == "www.karinex.de")
        #expect(container.configuration.storefrontAPIVersion == "2026-07")
        #expect(container.configuration.storefrontAccessToken == nil)
        #expect(container.configuration.customerAccountClientID == nil)
        #expect(container.configuration.appVersion == "0.1.0")
        #expect(container.configuration.buildNumber == "42")

        let endpoint = try #require(URL(string: "https://45dv93-bk.myshopify.com/api/2026-07/graphql.json"))
        #expect(container.storefrontClient.configuration.endpoint == endpoint)
        #expect(container.storefrontClient.isTokenless)
        #expect(!sink.entries.contains { $0.level >= .error })
    }

    @Test("A configured Storefront token switches off tokenless mode")
    func configuredTokenIsUsed() {
        let container = makeContainer(infoDictionary: validInfoDictionary(storefrontAccessToken: "test-storefront-token"))

        #expect(container.configurationFailure == nil)
        #expect(container.configuration.isStorefrontTokenConfigured)
        #expect(!container.storefrontClient.isTokenless)
    }

    @Test("An invalid info dictionary falls back to the built-in configuration and logs an error")
    func invalidConfigurationFallsBack() {
        var info = validInfoDictionary(appVersion: "0.2.0", buildNumber: "7")
        info.removeValue(forKey: AppConfiguration.InfoKey.shopDomain)
        let sink = RecordingLogSink()

        let container = makeContainer(infoDictionary: info, sink: sink)

        let expectedFailure = String(describing: ConfigurationError.missingValue(key: AppConfiguration.InfoKey.shopDomain))
        #expect(container.configurationFailure == expectedFailure)
        #expect(container.configuration.shopDomain == AppConfiguration.preview.shopDomain)
        #expect(container.configuration.storeWebDomain == AppConfiguration.preview.storeWebDomain)
        #expect(container.configuration.storefrontAPIVersion == AppConfiguration.preview.storefrontAPIVersion)
        #expect(container.configuration.storefrontAccessToken == nil)
        // The real version and build stay visible in the account screen.
        #expect(container.configuration.appVersion == "0.2.0")
        #expect(container.configuration.buildNumber == "7")
        #expect(sink.entries.contains { $0.level == .error && $0.category == .app })
    }

    @Test("Unresolved build settings count as missing and fall back")
    func unresolvedBuildSettingFallsBack() {
        var info = validInfoDictionary()
        info[AppConfiguration.InfoKey.shopDomain] = "$(KX_SHOP_DOMAIN)"
        info[AppConfiguration.InfoKey.appVersion] = "$(MARKETING_VERSION)"

        let resolution = ConfigurationResolution(infoDictionary: info)

        #expect(resolution.usesFallback)
        #expect(resolution.configuration.shopDomain == AppConfiguration.preview.shopDomain)
        #expect(resolution.configuration.appVersion == AppConfiguration.preview.appVersion)
        #expect(resolution.configuration.buildNumber == "42")
    }

    @Test("Feature flags are off by default and follow launch-argument overrides")
    func featureFlags() {
        let defaults = makeContainer()
        for flag in FeatureFlag.allCases {
            #expect(!defaults.featureFlags.isEnabled(flag))
        }

        let overridden = makeContainer(launchArguments: ["KARINEX", FeatureFlag.wishlist.launchArgument, "YES"])
        #expect(overridden.featureFlags.isEnabled(.wishlist))
        #expect(!overridden.featureFlags.isEnabled(.licenseVault))
    }

    @Test("The buyer context is Germany in German with the stored visitor consent")
    func storefrontContextUsesStoredConsent() {
        let services = AppServices.inMemory()
        let consent = PrivacyConsent(analytics: true).decided(at: Date(timeIntervalSince1970: 1_800_000_000))
        ConsentStore(store: services.preferences).save(consent)

        let container = makeContainer(services: services)

        let expected = MarketSelection.germany.storefrontContext(visitorConsent: VisitorConsent(privacyConsent: consent))
        #expect(container.storefrontContextProvider.context == expected)
        #expect(container.consentStore.load() == consent)
    }

    @Test("A reset launch wipes preferences, consent and Keychain items before reading them")
    func resetLaunchWipesPersistedState() throws {
        let services = AppServices.inMemory()
        let consent = PrivacyConsent(crashReports: true).decided(at: Date(timeIntervalSince1970: 1_800_000_000))
        ConsentStore(store: services.preferences).save(consent)
        services.preferences.set("DE", forKey: "market.selection")
        try services.secureStore.setString("stored-secret", for: "customer.token")

        let container = makeContainer(launchEnvironment: LaunchEnvironment(resetState: true), services: services)

        #expect(container.consentStore.load() == .undecided)
        #expect(services.preferences.string(forKey: "market.selection") == nil)
        #expect(try services.secureStore.data(for: "customer.token") == nil)
        let undecided = MarketSelection.germany.storefrontContext(visitorConsent: VisitorConsent(privacyConsent: .undecided))
        #expect(container.storefrontContextProvider.context == undecided)
    }

    @Test("Without a reset launch, persisted state is kept")
    func normalLaunchKeepsPersistedState() throws {
        let services = AppServices.inMemory()
        try services.secureStore.setString("stored-secret", for: "customer.token")

        _ = makeContainer(services: services)

        #expect(try services.secureStore.string(for: "customer.token") == "stored-secret")
    }

    @Test("The container hands out the network monitor it was built with")
    func networkMonitorIsInjected() async {
        let container = makeContainer(services: .inMemory(networkStatus: .offline))

        #expect(await container.networkMonitor.currentStatus == .offline)
        #expect(container.launchEnvironment == LaunchEnvironment())
    }
}
