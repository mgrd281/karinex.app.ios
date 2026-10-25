import Foundation

// MARK: - PrivacyConsent

/// The user's privacy choices. Everything is off until the user explicitly opts in.
///
/// Enforcement rule for the whole app: analytics, crash reporting and push registration must
/// not be initialized, not even lazily, unless the matching flag is `true`. Components that
/// need consent read it from `ConsentStoring` at the moment they would start, and must stop
/// (and delete what they collected, where possible) when the flag is revoked.
public struct PrivacyConsent: Codable, Sendable, Equatable {
    /// Anonymous usage analytics.
    public var analytics: Bool
    /// Crash and diagnostics reports sent to a third party.
    public var crashReports: Bool
    /// Push notifications about the user's orders and license delivery.
    public var orderUpdateNotifications: Bool
    /// Push notifications about deals.
    public var dealNotifications: Bool
    /// When the user last made a decision, `nil` if never.
    public var decidedAt: Date?

    /// Creates a consent value. All flags default to `false`.
    public init(
        analytics: Bool = false,
        crashReports: Bool = false,
        orderUpdateNotifications: Bool = false,
        dealNotifications: Bool = false,
        decidedAt: Date? = nil
    ) {
        self.analytics = analytics
        self.crashReports = crashReports
        self.orderUpdateNotifications = orderUpdateNotifications
        self.dealNotifications = dealNotifications
        self.decidedAt = decidedAt
    }

    /// No decision made yet: everything off.
    public static let undecided = PrivacyConsent()

    /// Whether the user has made a decision (even if everything was declined).
    public var hasDecided: Bool {
        decidedAt != nil
    }

    /// Whether any push notification category is allowed, i.e. whether the app may register
    /// for remote notifications at all.
    public var allowsPushRegistration: Bool {
        orderUpdateNotifications || dealNotifications
    }

    /// Returns a copy recording that the user decided at `date`.
    public func decided(at date: Date = Date()) -> PrivacyConsent {
        var copy = self
        copy.decidedAt = date
        return copy
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case analytics, crashReports, orderUpdateNotifications, dealNotifications, decidedAt
    }

    /// Decodes a stored value. Missing flags decode as `false`, so values written by older app
    /// versions stay readable when new flags are added.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        analytics = try container.decodeIfPresent(Bool.self, forKey: .analytics) ?? false
        crashReports = try container.decodeIfPresent(Bool.self, forKey: .crashReports) ?? false
        orderUpdateNotifications = try container.decodeIfPresent(Bool.self, forKey: .orderUpdateNotifications) ?? false
        dealNotifications = try container.decodeIfPresent(Bool.self, forKey: .dealNotifications) ?? false
        decidedAt = try container.decodeIfPresent(Date.self, forKey: .decidedAt)
    }
}

// MARK: - ConsentStoring

/// Loads and saves the user's privacy consent.
public protocol ConsentStoring: Sendable {
    /// The stored consent, or `.undecided` if there is none (or it cannot be read).
    func load() -> PrivacyConsent
    /// Persists `consent`.
    func save(_ consent: PrivacyConsent)
}

// MARK: - ConsentStore

/// `ConsentStoring` backed by a `KeyValueStore`, stored as JSON under `privacy.consent.v1`.
public final class ConsentStore: ConsentStoring {
    /// The key the consent is stored under.
    public static let storageKey = "privacy.consent.v1"

    private let store: any KeyValueStore
    private let logger: KXLogger

    /// Creates a consent store.
    ///
    /// - Parameters:
    ///   - store: The backing store, e.g. `UserDefaultsStore()`.
    ///   - logger: Logger for read and write failures.
    public init(store: any KeyValueStore, logger: KXLogger = KXLogger(category: .consent)) {
        self.store = store
        self.logger = logger
    }

    /// Returns the stored consent. Missing or unreadable data yields `.undecided`, which keeps
    /// every optional feature off and makes the app ask again.
    public func load() -> PrivacyConsent {
        do {
            return try store.value(PrivacyConsent.self, forKey: Self.storageKey) ?? .undecided
        } catch {
            logger.error("Stored privacy consent is unreadable, falling back to undecided")
            return .undecided
        }
    }

    /// Persists `consent`.
    public func save(_ consent: PrivacyConsent) {
        do {
            try store.setValue(consent, forKey: Self.storageKey)
        } catch {
            logger.fault("Privacy consent could not be encoded: \(String(describing: error))")
        }
    }

    /// Removes the stored consent, e.g. when the app is reset for UI tests.
    public func reset() {
        store.removeValue(forKey: Self.storageKey)
    }
}
