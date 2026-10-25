import BackendKit
import CommerceUI
import Core
import Foundation
import Observation

// MARK: - LicenseVaultViewModel

/// The license vault: shows the keys cached in the Keychain at once, then asks the backend for
/// the keys of every order that has some and refreshes the cache.
///
/// - Without a backend (no host configured, or `/licenses` unavailable) the screen shows the
///   notice that keys are delivered by e-mail (PROMPT.md 12); cached keys stay visible.
/// - An order whose keys are not delivered yet (HTTP 202) is listed as pending.
/// - Keys are never logged; only counts are.
@MainActor
@Observable
final class LicenseVaultViewModel {
    /// What the refresh found out about the backend.
    enum BackendState: Equatable {
        /// Not asked yet.
        case idle
        /// Asking.
        case refreshing
        /// The backend answered.
        case available
        /// No backend in this build, or it cannot deliver keys: the e-mail notice applies.
        case unavailable
        /// The refresh failed; the cached keys are still shown.
        case failed(UserFacingError)
    }

    /// The most orders whose keys one refresh loads.
    static let orderLimit = 25

    /// Limits the vault to one order (numeric order ID), or shows every key.
    let orderID: String?
    /// The keys, newest delivery first.
    private(set) var keys: [LicenseKey] = []
    /// Orders whose keys are still being delivered, by name (e.g. `#1042`) or ID.
    private(set) var pendingOrders: [String] = []
    /// The refresh state.
    private(set) var backendState: BackendState = .idle
    /// The keys shown in clear text.
    var revealedKeyIDs: Set<String> = []

    @ObservationIgnored private let backend: any BackendClient
    @ObservationIgnored private let cache: LicenseKeyCache
    @ObservationIgnored private let logger: KXLogger
    @ObservationIgnored private var orderNames: [String: String] = [:]

    init(orderID: String?, backend: any BackendClient, cache: LicenseKeyCache, logger: KXLogger = KXLogger(category: .ui)) {
        self.orderID = orderID
        self.backend = backend
        self.cache = cache
        self.logger = logger
        keys = Self.filtered(cache.all(), orderID: orderID)
    }

    /// The order name for `key`, e.g. `#1042`, if the backend reported one.
    func orderName(for key: LicenseKey) -> String? {
        orderNames[key.orderID]
    }

    /// Whether `key` is shown in clear text.
    func isRevealed(_ key: LicenseKey) -> Bool {
        revealedKeyIDs.contains(key.id)
    }

    /// Shows or hides `key`.
    func setRevealed(_ isRevealed: Bool, for key: LicenseKey) {
        if isRevealed {
            revealedKeyIDs.insert(key.id)
        } else {
            revealedKeyIDs.remove(key.id)
        }
    }

    /// Hides every key, e.g. when the app goes to the background.
    func hideAll() {
        revealedKeyIDs.removeAll()
    }

    // MARK: Refresh

    /// Asks the backend for the keys and updates the cache.
    func refresh() async {
        backendState = .refreshing
        do {
            let orderIDs = try await ordersWithLicenses()
            var pending: [String] = []
            for id in orderIDs {
                switch try await backend.licenses(orderID: id) {
                case let .delivered(delivered):
                    cache.store(delivered, orderID: id)
                case .pending:
                    pending.append(orderNames[id] ?? id)
                }
            }
            keys = Self.filtered(cache.all(), orderID: orderID)
            pendingOrders = pending
            backendState = .available
            logger.info("License vault refreshed: \(keys.count) keys, \(pending.count) pending orders")
        } catch BackendError.notConfigured {
            backendState = .unavailable
        } catch BackendError.notFound {
            backendState = .unavailable
        } catch {
            if let failure = UserFacingError(error) {
                backendState = .failed(failure)
            } else {
                backendState = .idle
            }
        }
    }

    /// The orders to ask for keys: the given one, or every order the backend marks.
    private func ordersWithLicenses() async throws -> [String] {
        if let orderID {
            return [orderID]
        }
        let orders = try await backend.orders()
        for order in orders {
            if let name = order.name {
                orderNames[order.orderID] = name
            }
        }
        return Array(orders.filter(\.hasLicenses).map(\.orderID).prefix(Self.orderLimit))
    }

    static func filtered(_ keys: [LicenseKey], orderID: String?) -> [LicenseKey] {
        guard let orderID else { return keys }
        return keys.filter { $0.orderID == orderID }
    }
}
