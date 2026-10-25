import Core
import Foundation
import Observation
import SwiftUI

// MARK: - AppSettingsStore

/// The app's own settings, stored in the preferences (`UserDefaults`):
/// - the appearance (system, light or dark), applied by the App to every window,
/// - whether the license vault asks for Face ID, Touch ID or the device code.
///
/// The market lives in `MarketStore`, the privacy consents in `ConsentStoring`.
@MainActor
@Observable
public final class AppSettingsStore {
    /// The appearance choice.
    public enum Appearance: String, CaseIterable, Sendable, Identifiable {
        /// Follows the system setting.
        case system
        /// Always light.
        case light
        /// Always dark.
        case dark

        /// The raw value.
        public var id: String {
            rawValue
        }

        /// The color scheme to force, `nil` for the system setting.
        public var colorScheme: ColorScheme? {
            switch self {
            case .system: nil
            case .light: .light
            case .dark: .dark
            }
        }
    }

    /// Preferences key of the appearance.
    public static let appearanceKey = "settings.appearance.v1"
    /// Preferences key of the license lock.
    public static let licenseLockKey = "settings.licenseLock.v1"

    /// The appearance; saved on change.
    public var appearance: Appearance {
        didSet { store.set(appearance.rawValue, forKey: Self.appearanceKey) }
    }

    /// Whether the license vault is locked with Face ID, Touch ID or the device code; saved on change.
    public var locksLicenses: Bool {
        didSet { store.set(locksLicenses, forKey: Self.licenseLockKey) }
    }

    @ObservationIgnored private let store: any KeyValueStore

    /// Creates the store and reads the saved values.
    public init(store: any KeyValueStore) {
        self.store = store
        appearance = store.string(forKey: Self.appearanceKey).flatMap(Appearance.init(rawValue:)) ?? .system
        locksLicenses = store.bool(forKey: Self.licenseLockKey) ?? false
    }
}
