import Foundation

// MARK: - FeatureFlag

/// Features that ship dark and are switched on per phase, per build or remotely.
public enum FeatureFlag: String, CaseIterable, Sendable, Codable {
    /// In-app license key retrieval (Phase 2, needs the backend).
    case licenseVault
    /// Wishlist (Phase 3).
    case wishlist
    /// Push notifications (Phase 3, always also gated by `PrivacyConsent`).
    case pushNotifications
    /// "Lizenz wird zugestellt" Live Activity (Phase 3).
    case liveActivity
    /// Home screen widget (Phase 3).
    case homeWidget
    /// Flags and support info from the backend's `/v1/app/config` (Phase 2).
    case remoteConfig

    /// The launch argument that overrides this flag, e.g. `-kx.flag.wishlist`.
    public var launchArgument: String {
        "\(FeatureFlags.launchArgumentPrefix)\(rawValue)"
    }
}

// MARK: - FeatureFlags

/// An immutable set of feature flag values. Flags that are not enabled are off.
///
/// Encoded as a JSON object mapping every flag name to a Boolean. Decoding ignores unknown
/// names and treats missing ones as off, so remote configurations can be shared between app
/// versions with different flag sets.
public struct FeatureFlags: Sendable, Equatable, Codable {
    /// The prefix of flag launch arguments: `-kx.flag.<name> YES|NO`.
    public static let launchArgumentPrefix = "-kx.flag."

    /// The flags that are on.
    public private(set) var enabledFlags: Set<FeatureFlag>

    /// Creates flags with exactly `enabledFlags` switched on.
    public init(enabledFlags: Set<FeatureFlag> = []) {
        self.enabledFlags = enabledFlags
    }

    /// The defaults of the current release phase: everything off.
    public static let phaseDefaults = FeatureFlags()

    /// Whether `flag` is on.
    public func isEnabled(_ flag: FeatureFlag) -> Bool {
        enabledFlags.contains(flag)
    }

    /// Returns a copy with `flag` switched to `isEnabled`.
    public func setting(_ flag: FeatureFlag, to isEnabled: Bool) -> FeatureFlags {
        var copy = self
        if isEnabled {
            copy.enabledFlags.insert(flag)
        } else {
            copy.enabledFlags.remove(flag)
        }
        return copy
    }

    /// Returns a copy with the overrides from `-kx.flag.<name> YES|NO` argument pairs applied.
    ///
    /// Unknown flag names and values other than `YES`/`NO`, `true`/`false` or `1`/`0` are
    /// ignored. When a flag appears several times, the last occurrence wins.
    public func applyingLaunchArguments(_ arguments: [String]) -> FeatureFlags {
        var result = self
        for (index, argument) in arguments.enumerated() where argument.hasPrefix(Self.launchArgumentPrefix) {
            let name = String(argument.dropFirst(Self.launchArgumentPrefix.count))
            let valueIndex = index + 1
            guard let flag = FeatureFlag(rawValue: name),
                  valueIndex < arguments.count,
                  let isEnabled = LaunchArguments.parseBool(arguments[valueIndex])
            else { continue }
            result = result.setting(flag, to: isEnabled)
        }
        return result
    }

    // MARK: - Codable

    /// Decodes a `{ "flagName": Bool }` object, ignoring unknown names.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let values = try container.decode([String: Bool].self)
        enabledFlags = Set(values.compactMap { name, isEnabled in
            isEnabled ? FeatureFlag(rawValue: name) : nil
        })
    }

    /// Encodes every known flag as `{ "flagName": Bool }`.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        let values = Dictionary(uniqueKeysWithValues: FeatureFlag.allCases.map { ($0.rawValue, isEnabled($0)) })
        try container.encode(values)
    }
}

// MARK: - FeatureFlagProviding

/// Answers whether a feature is on. Inject it instead of reading flags globally.
public protocol FeatureFlagProviding: Sendable {
    /// Whether `flag` is on.
    func isEnabled(_ flag: FeatureFlag) -> Bool
}

// MARK: - StaticFeatureFlagProvider

/// A provider with fixed flag values, optionally overridden by launch arguments (UI tests,
/// Xcode schemes).
public struct StaticFeatureFlagProvider: FeatureFlagProviding {
    /// The effective flag values.
    public let flags: FeatureFlags

    /// Creates a provider with `flags`, the phase defaults by default.
    public init(flags: FeatureFlags = .phaseDefaults) {
        self.flags = flags
    }

    /// Creates a provider from `base` with `-kx.flag.<name> YES|NO` overrides from
    /// `launchArguments` applied, e.g. `ProcessInfo.processInfo.arguments`.
    public init(launchArguments: [String], base: FeatureFlags = .phaseDefaults) {
        flags = base.applyingLaunchArguments(launchArguments)
    }

    /// Whether `flag` is on.
    public func isEnabled(_ flag: FeatureFlag) -> Bool {
        flags.isEnabled(flag)
    }
}
