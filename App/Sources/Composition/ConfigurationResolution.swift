import Core
import Foundation

// MARK: - ConfigurationResolution

/// The configuration the app runs with, and why it differs from `Info.plist` when it does.
///
/// A broken build configuration (for example an unresolved `$(KX_SHOP_DOMAIN)` or a malformed
/// API version) must not crash the app. The app then falls back to the built-in values of the
/// live store in tokenless mode (`AppConfiguration.preview`), keeps the real version and build
/// number when they are readable, and records the validation failure so the container can log
/// it.
struct ConfigurationResolution: Equatable, Sendable {
    /// The configuration to use.
    let configuration: AppConfiguration
    /// A log-safe description of the validation error, or `nil` when `Info.plist` was valid.
    let failureDescription: String?

    /// Whether the built-in fallback is in use.
    var usesFallback: Bool {
        failureDescription != nil
    }

    /// Wraps an already valid configuration (previews and tests).
    init(configuration: AppConfiguration, failureDescription: String? = nil) {
        self.configuration = configuration
        self.failureDescription = failureDescription
    }

    /// Reads and validates `infoDictionary`, falling back to the built-in configuration when the
    /// values are unusable.
    init(infoDictionary: [String: Any]) {
        do {
            configuration = try AppConfiguration(infoDictionary: infoDictionary)
            failureDescription = nil
        } catch {
            configuration = ConfigurationResolution.fallbackConfiguration(infoDictionary: infoDictionary)
            failureDescription = String(describing: error)
        }
    }

    // MARK: - Fallback

    /// `AppConfiguration.preview` (the live store, tokenless) with the version and build number
    /// taken from `infoDictionary` when they are present and resolved.
    static func fallbackConfiguration(infoDictionary: [String: Any]) -> AppConfiguration {
        let preview = AppConfiguration.preview
        return AppConfiguration(
            shopDomain: preview.shopDomain,
            storeWebDomain: preview.storeWebDomain,
            storefrontAPIVersion: preview.storefrontAPIVersion,
            storefrontAccessToken: nil,
            customerAccountAPIVersion: preview.customerAccountAPIVersion,
            customerAccountClientID: nil,
            appVersion: resolvedValue(for: AppConfiguration.InfoKey.appVersion, in: infoDictionary) ?? preview.appVersion,
            buildNumber: resolvedValue(for: AppConfiguration.InfoKey.buildNumber, in: infoDictionary) ?? preview.buildNumber
        )
    }

    /// The trimmed string for `key`, or `nil` when it is absent, not a string, empty or an
    /// unresolved build setting such as `$(MARKETING_VERSION)`.
    private static func resolvedValue(for key: String, in infoDictionary: [String: Any]) -> String? {
        guard let raw = infoDictionary[key] as? String else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.contains("$("), !value.contains("${") else { return nil }
        return value
    }
}
