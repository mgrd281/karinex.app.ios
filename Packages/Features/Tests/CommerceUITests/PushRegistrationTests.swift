import BackendKit
@testable import CommerceUI
import Core
import Foundation
import Testing

// MARK: - Stubs

@MainActor
private final class StubSystem: RemoteNotificationRegistering {
    var grants = true
    var authorized = false
    private(set) var prompts = 0
    private(set) var registrations = 0
    private(set) var unregistrations = 0

    func requestAuthorization() async -> Bool {
        prompts += 1
        return grants
    }

    func isAuthorized() async -> Bool {
        authorized
    }

    func register() {
        registrations += 1
    }

    func unregister() {
        unregistrations += 1
    }
}

private actor RecordingBackend: BackendClient {
    private(set) var registered: [DeviceRegistration] = []
    private(set) var unregistered: [String] = []

    func appConfig() async throws -> RemoteAppConfig {
        .fallback
    }

    func orders() async throws -> [BackendOrderStatus] {
        []
    }

    func licenses(orderID _: String) async throws -> LicenseDelivery {
        .pending
    }

    func invoice(orderID _: String) async throws -> InvoiceLink {
        throw BackendError.notConfigured
    }

    func requestAccountDeletion() async throws -> String? {
        nil
    }

    func registerDevice(_ registration: DeviceRegistration) async throws {
        registered.append(registration)
    }

    func unregisterDevice(apnsToken: String) async throws {
        unregistered.append(apnsToken)
    }
}

private final class MemoryConsentStore: ConsentStoring, @unchecked Sendable {
    private let consent = Locked(PrivacyConsent.undecided)

    func load() -> PrivacyConsent {
        consent.value
    }

    func save(_ value: PrivacyConsent) {
        consent.withLock { $0 = value }
    }
}

// MARK: - Tests

@Suite("Push registration")
@MainActor
struct PushRegistrationTests {
    private let system = StubSystem()
    private let backend = RecordingBackend()
    private let consentStore = MemoryConsentStore()

    private func makeCoordinator() -> PushRegistrationCoordinator {
        PushRegistrationCoordinator(
            system: system,
            backend: backend,
            consentStore: consentStore,
            languageCode: { "de" },
            countryCode: { "DE" }
        )
    }

    private func consent(orders: Bool, deals: Bool) -> PrivacyConsent {
        var consent = PrivacyConsent.undecided
        consent.orderUpdateNotifications = orders
        consent.dealNotifications = deals
        return consent.decided()
    }

    @Test("Without consent nothing is asked or registered at launch")
    func noConsent() async {
        system.authorized = true
        let coordinator = makeCoordinator()

        await coordinator.start()

        #expect(system.prompts == 0)
        #expect(system.registrations == 0)
    }

    @Test("With earlier consent the launch renews the registration silently")
    func launchWithConsent() async {
        system.authorized = true
        consentStore.save(consent(orders: true, deals: false))
        let coordinator = makeCoordinator()

        await coordinator.start()

        #expect(system.prompts == 0)
        #expect(system.registrations == 1)
    }

    @Test("Turning on order updates asks, registers and sends the consents")
    func optIn() async {
        let coordinator = makeCoordinator()
        let updated = consent(orders: true, deals: false)
        consentStore.save(updated)

        await coordinator.consentDidChange(updated)
        await coordinator.didRegister(deviceToken: Data([0xAB, 0x01]))

        #expect(system.prompts == 1)
        #expect(system.registrations == 1)
        let registration = await backend.registered.first
        #expect(registration?.apnsToken == "ab01")
        #expect(registration?.consent == DeviceRegistration.Consent(orderUpdates: true, deals: false))
        #expect(registration?.country == "DE")
        #expect(registration?.locale == "de")
    }

    @Test("A denied permission is remembered and nothing is registered")
    func denied() async {
        system.grants = false
        let coordinator = makeCoordinator()

        await coordinator.consentDidChange(consent(orders: false, deals: true))

        #expect(coordinator.isPermissionDenied)
        #expect(system.registrations == 0)
    }

    @Test("Turning both off unregisters at the backend")
    func optOut() async {
        let coordinator = makeCoordinator()
        consentStore.save(consent(orders: true, deals: true))
        await coordinator.didRegister(deviceToken: Data([0x0F]))

        let off = consent(orders: false, deals: false)
        consentStore.save(off)
        await coordinator.consentDidChange(off)

        #expect(system.unregistrations == 1)
        #expect(await backend.unregistered == ["0f"])
    }

    @Test("A token that arrives after consent was withdrawn is not sent")
    func lateToken() async {
        let coordinator = makeCoordinator()

        await coordinator.didRegister(deviceToken: Data([0x01]))

        #expect(await backend.registered.isEmpty)
        #expect(system.unregistrations == 1)
    }

    @Test("A tapped notification becomes a deep link")
    func tap() {
        let coordinator = makeCoordinator()

        coordinator.didOpen(.licenseDelivered(orderID: "5678"))

        #expect(coordinator.pendingURL?.absoluteString == "karinex://account/licenses")
    }
}

@Suite("Push payloads")
struct PushPayloadTests {
    @Test("Known payloads map to deep links")
    func known() {
        #expect(PushPayload(userInfo: ["type": "order.paid", "orderId": "5678"])?.deepLink?.absoluteString
            == "karinex://account/orders/5678")
        #expect(PushPayload(userInfo: ["type": "license.delivered", "orderId": "5678"]) == .licenseDelivered(orderID: "5678"))
        #expect(PushPayload(userInfo: ["type": "deal.started", "collection": "bestseller"])?.deepLink?.absoluteString
            == "karinex://collection/bestseller")
    }

    @Test("Unknown or malformed payloads are ignored", arguments: [
        ["type": "order.paid", "orderId": "../1"],
        ["type": "order.paid"],
        ["type": "deal.started", "collection": "a/b"],
        ["type": "marketing"],
        ["aps": "x"],
    ] as [[String: String]])
    func ignored(userInfo: [String: String]) {
        #expect(PushPayload(userInfo: userInfo) == nil)
    }
}
