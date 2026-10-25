import BackendKit
import Core
import Foundation
import Observation
import ShopifyKit

// MARK: - RemoteNotificationRegistering

/// The system side of push registration, behind a protocol so the coordinator can be tested.
/// The App passes ``SystemRemoteNotifications``.
@MainActor
public protocol RemoteNotificationRegistering: AnyObject {
    /// Asks the user for permission to show alerts, badges and sounds. Returns whether it was
    /// granted (also when it had been granted before).
    func requestAuthorization() async -> Bool
    /// Whether the user has granted permission, without asking.
    func isAuthorized() async -> Bool
    /// Asks APNs for a device token; the answer arrives in the App delegate.
    func register()
    /// Stops receiving remote notifications.
    func unregister()
}

// MARK: - PushRegistrationCoordinator

/// Push notifications, strictly behind consent (PROMPT.md 3, CLAUDE.md):
///
/// - Nothing touches APNs or the permission prompt until the customer turns on
///   "Bestellstatus" or "Angebote" in the settings (`PrivacyConsent.allowsPushRegistration`).
///   The permission prompt appears only right after such a toggle, never at launch.
/// - The device token is sent to the BFF (`POST /v1/app/devices`) with the two consents, the UI
///   language and the market country. Turning both off unregisters the device locally and at
///   the BFF.
/// - A tapped notification becomes a deep link in ``pendingURL``, which the App opens.
/// - The token is never logged.
@MainActor
@Observable
public final class PushRegistrationCoordinator {
    /// A deep link from a tapped notification, waiting for the App to open it.
    public var pendingURL: URL?
    /// Whether iOS refused the permission; the settings then point to the iOS settings.
    public private(set) var isPermissionDenied = false

    @ObservationIgnored private let system: any RemoteNotificationRegistering
    @ObservationIgnored private let backend: any BackendClient
    @ObservationIgnored private let consentStore: any ConsentStoring
    @ObservationIgnored private let languageCode: @MainActor () -> String
    @ObservationIgnored private let countryCode: @MainActor () -> String
    @ObservationIgnored private let logger: KXLogger
    @ObservationIgnored private var deviceToken: String?

    /// Creates the coordinator.
    ///
    /// - Parameters:
    ///   - system: Permission prompt and APNs registration.
    ///   - backend: Receives the device registration.
    ///   - consentStore: The privacy consents.
    ///   - languageCode: The UI language, e.g. `de`.
    ///   - countryCode: The market country, e.g. `DE`.
    ///   - logger: Logs outcomes, never the token.
    public init(
        system: any RemoteNotificationRegistering,
        backend: any BackendClient,
        consentStore: any ConsentStoring,
        languageCode: @escaping @MainActor () -> String,
        countryCode: @escaping @MainActor () -> String,
        logger: KXLogger = KXLogger(category: .ui)
    ) {
        self.system = system
        self.backend = backend
        self.consentStore = consentStore
        self.languageCode = languageCode
        self.countryCode = countryCode
        self.logger = logger
    }

    // MARK: Lifecycle

    /// At launch: renews the APNs registration when the customer consented earlier and iOS
    /// still allows notifications (device tokens can change). Never shows the prompt.
    public func start() async {
        guard consentStore.load().allowsPushRegistration else { return }
        if await system.isAuthorized() {
            system.register()
        }
    }

    /// Applies a changed consent from the settings: asks for permission and registers when a
    /// push category was turned on, unregisters when both are off, and updates the BFF.
    public func consentDidChange(_ consent: PrivacyConsent) async {
        guard consent.allowsPushRegistration else {
            await unregister()
            return
        }
        let granted = await system.requestAuthorization()
        isPermissionDenied = !granted
        guard granted else {
            logger.notice("Notification permission denied")
            return
        }
        if deviceToken != nil {
            await sendRegistration(consent: consent)
        }
        system.register()
    }

    // MARK: App delegate

    /// Called with the APNs device token.
    public func didRegister(deviceToken data: Data) async {
        let token = data.map { String(format: "%02x", $0) }.joined()
        deviceToken = token
        let consent = consentStore.load()
        guard consent.allowsPushRegistration else {
            system.unregister()
            return
        }
        await sendRegistration(consent: consent)
    }

    /// Called when APNs registration failed.
    public func didFailToRegister() {
        logger.notice("APNs registration failed")
    }

    /// Called when the customer tapped a notification with a KARINEX payload.
    public func didOpen(_ payload: PushPayload) {
        pendingURL = payload.deepLink
    }

    // MARK: Private

    private func sendRegistration(consent: PrivacyConsent) async {
        guard let deviceToken else { return }
        let registration = DeviceRegistration(
            apnsToken: deviceToken,
            locale: languageCode(),
            country: countryCode(),
            consent: DeviceRegistration.Consent(
                orderUpdates: consent.orderUpdateNotifications,
                deals: consent.dealNotifications
            )
        )
        do {
            try await backend.registerDevice(registration)
            logger.info("Device registered for notifications")
        } catch {
            logger.notice("Device registration failed: \(Self.logName(error))")
        }
    }

    private func unregister() async {
        system.unregister()
        guard let token = deviceToken else { return }
        deviceToken = nil
        do {
            try await backend.unregisterDevice(apnsToken: token)
        } catch {
            logger.notice("Device unregistration failed: \(Self.logName(error))")
        }
    }

    private static func logName(_ error: any Error) -> String {
        (error as? BackendError)?.logDescription ?? String(describing: type(of: error))
    }
}

// MARK: - PushPayload

/// The custom part of a KARINEX push (docs/BFF_CONTRACT.md, "Push payloads").
public enum PushPayload: Equatable, Sendable {
    /// An order was paid.
    case orderPaid(orderID: String)
    /// The keys of an order were delivered.
    case licenseDelivered(orderID: String)
    /// A deal started in a collection.
    case dealStarted(collection: String)

    /// Reads `type` and its fields from the notification's `userInfo`; `nil` for anything else.
    public init?(userInfo: [AnyHashable: Any]) {
        guard let type = userInfo["type"] as? String else { return nil }
        switch type {
        case "order.paid":
            guard let id = Self.orderID(userInfo["orderId"]) else { return nil }
            self = .orderPaid(orderID: id)
        case "license.delivered":
            guard let id = Self.orderID(userInfo["orderId"]) else { return nil }
            self = .licenseDelivered(orderID: id)
        case "deal.started":
            guard let handle = (userInfo["collection"] as? String).flatMap(DeepLinkParser.handle) else { return nil }
            self = .dealStarted(collection: handle)
        default:
            return nil
        }
    }

    /// The `karinex://` link the tap opens.
    public var deepLink: URL? {
        switch self {
        case let .orderPaid(orderID):
            URL(string: "\(DeepLinkParser.scheme)://account/orders/\(orderID)")
        case .licenseDelivered:
            URL(string: "\(DeepLinkParser.scheme)://account/licenses")
        case let .dealStarted(collection):
            URL(string: "\(DeepLinkParser.scheme)://collection/\(collection)")
        }
    }

    private static func orderID(_ value: Any?) -> String? {
        guard let text = value as? String, DeepLinkParser.orderID(text) != nil else { return nil }
        return text
    }
}
