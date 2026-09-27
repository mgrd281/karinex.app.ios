import Core
import Foundation
import Observation
import ShopifyKit

// MARK: - AppContainer

/// The composition root of the app: a lightweight dependency container that builds every
/// long-lived service once and hands them out through protocol-typed properties.
///
/// It is injected into SwiftUI with `.environment(container)` and read with
/// `@Environment(AppContainer.self)`. Screens receive only what they need from it through their
/// initializers; feature modules never see the container itself.
///
/// Composition:
/// - `AppConfiguration` from `Info.plist` (see `ConfigurationResolution` for the fallback),
/// - Keychain (`SecureStore`), `UserDefaults` (`KeyValueStore`) and the privacy consent on top,
/// - feature flags with `-kx.flag.<name> YES|NO` launch overrides,
/// - reachability (`NWPathNetworkMonitor`, fixed under UI tests),
/// - one `URLSessionHTTPClient`, the `StorefrontClient` and the Storefront repositories, all
///   sharing one buyer context (market and consent).
///
/// Phase 0 uses Germany in German as the buyer context. Phase 1 resolves the market from the
/// device with `MarketResolver`, persists it and updates `storefrontContextProvider`.
@MainActor
@Observable
final class AppContainer {
    // MARK: - Environment

    /// The launch switches of this process (UI testing, reset, forced appearance).
    let launchEnvironment: LaunchEnvironment
    /// The configuration the app runs with.
    let configuration: AppConfiguration
    /// Why `configuration` is the built-in fallback, or `nil` when `Info.plist` was valid.
    let configurationFailure: String?

    // MARK: - Storage and privacy

    /// Storage for secrets: license keys and tokens (Keychain, this device only).
    let secureStore: any SecureStore
    /// Storage for small preferences (`UserDefaults`).
    let preferences: any KeyValueStore
    /// The user's privacy choices. Nothing may start analytics, crash reporting or push
    /// registration unless the matching flag is set.
    let consentStore: any ConsentStoring

    // MARK: - Flags and connectivity

    /// Feature flags of the current phase, with launch-argument overrides applied.
    let featureFlags: any FeatureFlagProviding
    /// Reachability; drives the offline banner of the root view.
    let networkMonitor: any NetworkMonitoring

    // MARK: - Shopify

    /// The HTTP transport shared by every API client.
    let httpClient: any HTTPClient
    /// The Storefront API client (tokenless unless a token is configured).
    let storefrontClient: StorefrontClient
    /// The buyer context (market, language, visitor consent) of every Storefront call. Update it
    /// when the market or the consent changes.
    let storefrontContextProvider: MutableStorefrontContextProvider
    /// Products and collections.
    let catalogRepository: any CatalogRepository
    /// The countries, currencies and languages the store sells in.
    let localizationRepository: any LocalizationRepository

    // MARK: - Init

    /// Composes the container.
    ///
    /// - Parameters:
    ///   - resolution: The configuration and, when it is the fallback, the validation failure,
    ///     which is logged as an error.
    ///   - launchEnvironment: Launch switches. With `resetState` the preferences and the
    ///     Keychain items are wiped before anything is read.
    ///   - launchArguments: The process arguments, for feature flag overrides.
    ///   - services: Persistence, connectivity and transport.
    ///   - logger: Receives configuration and reset diagnostics.
    init(
        configuration resolution: ConfigurationResolution,
        launchEnvironment: LaunchEnvironment,
        launchArguments: [String],
        services: AppServices,
        logger: KXLogger = KXLogger(category: .app)
    ) {
        if let failure = resolution.failureDescription {
            logger.error("Info.plist configuration is invalid (\(failure)). Using the built-in store configuration.")
        }
        if launchEnvironment.resetState {
            // An explicit type name: `Self` in a class initializer would need `self`.
            AppContainer.resetPersistedState(of: services, logger: logger)
        }

        let consentStore = ConsentStore(store: services.preferences)
        let storefrontClient = StorefrontClient(
            configuration: StorefrontConfiguration(appConfiguration: resolution.configuration),
            httpClient: services.httpClient
        )
        let contextProvider = MutableStorefrontContextProvider(
            context: MarketSelection.germany.storefrontContext(
                visitorConsent: VisitorConsent(privacyConsent: consentStore.load())
            )
        )

        self.launchEnvironment = launchEnvironment
        configuration = resolution.configuration
        configurationFailure = resolution.failureDescription
        secureStore = services.secureStore
        preferences = services.preferences
        self.consentStore = consentStore
        featureFlags = StaticFeatureFlagProvider(launchArguments: launchArguments)
        networkMonitor = services.networkMonitor
        httpClient = services.httpClient
        self.storefrontClient = storefrontClient
        storefrontContextProvider = contextProvider
        catalogRepository = StorefrontCatalogRepository(client: storefrontClient, contextProvider: contextProvider)
        localizationRepository = StorefrontLocalizationRepository(client: storefrontClient, contextProvider: contextProvider)

        let access = storefrontClient.isTokenless ? "tokenless" : "token"
        logger.info("App container ready: Storefront API \(resolution.configuration.storefrontAPIVersion), \(access)")
    }

    // MARK: - Factories

    /// The container of the running app, built from the main bundle and the process.
    static func live(bundle: Bundle = .main, processInfo: ProcessInfo = .processInfo) -> AppContainer {
        let launchEnvironment = LaunchEnvironment(processInfo: processInfo)
        let arguments = processInfo.arguments
        return AppContainer(
            configuration: ConfigurationResolution(infoDictionary: bundle.infoDictionary ?? [:]),
            launchEnvironment: launchEnvironment,
            launchArguments: arguments,
            services: .live(
                launchEnvironment: launchEnvironment,
                arguments: arguments,
                bundleIdentifier: bundle.bundleIdentifier
            )
        )
    }

    /// A container for SwiftUI previews: the live store configuration in tokenless mode,
    /// in-memory storage and a fixed network status.
    static func preview(
        networkStatus: NetworkStatus = .online(isExpensive: false, isConstrained: false)
    ) -> AppContainer {
        AppContainer(
            configuration: ConfigurationResolution(configuration: .preview),
            launchEnvironment: LaunchEnvironment(),
            launchArguments: [],
            services: .inMemory(networkStatus: networkStatus)
        )
    }

    // MARK: - Reset

    /// Wipes preferences (including the privacy consent) and this app's Keychain items, for
    /// `-kx.reset` launches.
    private static func resetPersistedState(of services: AppServices, logger: KXLogger) {
        services.resetPreferences()
        do {
            try services.secureStore.removeAll()
        } catch {
            logger.error("Removing the Keychain items at launch failed: \(error)")
        }
        logger.notice("Persisted state was reset at launch (\(LaunchEnvironment.resetArgument)).")
    }
}
