import Core
import Foundation

// MARK: - AppServices

/// The platform services the container composes: persistence, connectivity and the HTTP
/// transport. The app uses `live(launchEnvironment:arguments:bundleIdentifier:)`; previews and
/// tests use `inMemory(networkStatus:)`, which touches neither the Keychain nor `UserDefaults`
/// and reports a fixed network status.
struct AppServices: Sendable {
    /// Launch argument that makes a UI test run report the device as offline, so the offline
    /// banner can be checked without changing the simulator's network. Only honored together
    /// with `-kx.uitesting`.
    static let offlineArgument = "-kx.offline"

    /// Storage for secrets (license keys, tokens): the Keychain in the app.
    var secureStore: any SecureStore
    /// Storage for small preferences (consent, market choice): `UserDefaults` in the app.
    var preferences: any KeyValueStore
    /// Wipes every value of `preferences`. Called for `-kx.reset` before anything is read.
    var resetPreferences: @Sendable () -> Void
    /// Reachability, which drives the offline banner.
    var networkMonitor: any NetworkMonitoring
    /// The HTTP transport shared by every API client. Build it once: it owns the URL cache.
    var httpClient: any HTTPClient

    // MARK: - Factories

    /// The services of the running app.
    ///
    /// - Parameters:
    ///   - launchEnvironment: Launch switches. Under UI tests the network status is fixed
    ///     (online, or offline with `-kx.offline`) so runs do not depend on the host network.
    ///   - arguments: The process arguments, e.g. `ProcessInfo.processInfo.arguments`.
    ///   - bundleIdentifier: The app's bundle identifier, whose `UserDefaults` domain
    ///     `resetPreferences` removes.
    static func live(launchEnvironment: LaunchEnvironment, arguments: [String], bundleIdentifier: String?) -> AppServices {
        let networkMonitor: any NetworkMonitoring = if launchEnvironment.isUITesting {
            StaticNetworkMonitor(status: uiTestingNetworkStatus(arguments: arguments))
        } else {
            NWPathNetworkMonitor()
        }
        return AppServices(
            secureStore: KeychainStore(),
            preferences: UserDefaultsStore(),
            resetPreferences: {
                guard let bundleIdentifier else { return }
                UserDefaults.standard.removePersistentDomain(forName: bundleIdentifier)
            },
            networkMonitor: networkMonitor,
            httpClient: URLSessionHTTPClient()
        )
    }

    /// In-memory services for previews and tests. The HTTP client uses an ephemeral session;
    /// nothing in the shell sends requests on its own.
    static func inMemory(
        networkStatus: NetworkStatus = .online(isExpensive: false, isConstrained: false)
    ) -> AppServices {
        let preferences = InMemoryKeyValueStore()
        return AppServices(
            secureStore: InMemorySecureStore(),
            preferences: preferences,
            resetPreferences: { preferences.removeAll() },
            networkMonitor: StaticNetworkMonitor(status: networkStatus),
            httpClient: URLSessionHTTPClient(configuration: .ephemeral)
        )
    }

    /// The fixed network status of a UI test run: offline when `-kx.offline` is passed, online
    /// otherwise.
    static func uiTestingNetworkStatus(arguments: [String]) -> NetworkStatus {
        arguments.contains(offlineArgument) ? .offline : .online(isExpensive: false, isConstrained: false)
    }
}
