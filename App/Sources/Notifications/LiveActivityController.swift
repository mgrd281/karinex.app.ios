import ActivityKit
import BackendKit
import Core
import Foundation

// MARK: - LiveActivityController

/// Starts and ends the "Lizenz wird zugestellt" Live Activity.
///
/// - It starts after a completed checkout, only when the customer turned on order updates in
///   the settings (`PrivacyConsent.orderUpdateNotifications`) and Live Activities are allowed.
///   It is a local activity: no push token is requested for it.
/// - It ends as "Zugestellt" when a `license.delivered` push arrives, or when the BFF reports the
///   order as delivered on the next return to the app. It goes stale after two hours.
@MainActor
final class LiveActivityController {
    /// How long the activity stays fresh without an update.
    static let staleInterval: TimeInterval = 2 * 60 * 60
    /// How long "Zugestellt" stays on the Lock Screen.
    static let deliveredDismissal: TimeInterval = 15 * 60

    private let consentStore: any ConsentStoring
    private let backend: any BackendClient
    private let logger: KXLogger

    init(consentStore: any ConsentStoring, backend: any BackendClient, logger: KXLogger = KXLogger(category: .ui)) {
        self.consentStore = consentStore
        self.backend = backend
        self.logger = logger
    }

    /// Starts the activity for the order with `reference` (from Shopify checkout).
    func startDelivery(orderReference reference: String) {
        guard consentStore.load().orderUpdateNotifications,
              ActivityAuthorizationInfo().areActivitiesEnabled,
              !Activity<LicenseDeliveryAttributes>.activities.contains(where: { $0.attributes.orderReference == reference })
        else { return }
        let content = ActivityContent(
            state: LicenseDeliveryAttributes.ContentState(phase: .preparing),
            staleDate: Date().addingTimeInterval(Self.staleInterval)
        )
        do {
            _ = try Activity.request(attributes: LicenseDeliveryAttributes(orderReference: reference), content: content)
            logger.info("License delivery activity started")
        } catch {
            logger.notice("License delivery activity not started: \(String(describing: type(of: error)))")
        }
    }

    /// Ends every running activity as delivered, e.g. after a `license.delivered` push.
    func markAllDelivered() async {
        for activity in Activity<LicenseDeliveryAttributes>.activities {
            await end(activity)
        }
    }

    /// Asks the BFF whether a running activity's order was delivered meanwhile.
    func refresh() async {
        let activities = Activity<LicenseDeliveryAttributes>.activities
        guard !activities.isEmpty, let orders = try? await backend.orders() else { return }
        let delivered = Set(orders.filter { $0.deliveryStatus == .delivered }.map(\.orderID))
        for activity in activities where Self.matches(activity.attributes.orderReference, delivered) {
            await end(activity)
        }
    }

    /// Whether `reference` (a numeric ID or a GID ending in it) is one of `orderIDs`.
    static func matches(_ reference: String, _ orderIDs: Set<String>) -> Bool {
        let last = reference.split(separator: "/").last.map(String.init) ?? reference
        let numeric = last.split(separator: "?").first.map(String.init) ?? last
        return orderIDs.contains(numeric)
    }

    private func end(_ activity: Activity<LicenseDeliveryAttributes>) async {
        let content = ActivityContent(state: LicenseDeliveryAttributes.ContentState(phase: .delivered), staleDate: nil)
        await activity.end(content, dismissalPolicy: .after(Date().addingTimeInterval(Self.deliveredDismissal)))
    }
}
