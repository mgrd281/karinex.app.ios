import BackendKit
@testable import CommerceUI
import Core
import Foundation
import Testing

private actor InboxBackend: BackendClient {
    var messages: [InboxMessage] = []
    var fails = false
    private(set) var watched: [RestockWatch] = []
    private(set) var unwatched: [String] = []

    func set(messages: [InboxMessage]) {
        self.messages = messages
    }

    func set(fails: Bool) {
        self.fails = fails
    }

    func notifications() async throws -> [InboxMessage] {
        if fails { throw BackendError.server(statusCode: 503, code: nil, requestID: nil) }
        return messages
    }

    func watchRestock(_ watch: RestockWatch) async throws {
        if fails { throw BackendError.server(statusCode: 503, code: nil, requestID: nil) }
        watched.append(watch)
    }

    func unwatchRestock(variantID: String) async throws {
        unwatched.append(variantID)
    }

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

    func loyalty() async throws -> LoyaltyStatus {
        throw BackendError.notConfigured
    }

    func redeemLoyalty(points _: Int, idempotencyKey _: String) async throws -> LoyaltyRedeemCode {
        throw BackendError.notConfigured
    }

    func loyaltyReferral() async throws -> LoyaltyReferralCode {
        throw BackendError.notConfigured
    }

    func walletPass() async throws -> Data {
        throw BackendError.notConfigured
    }

    func registerDevice(_: DeviceRegistration) async throws {}

    func unregisterDevice(apnsToken _: String) async throws {}
}

private let day: TimeInterval = 86400
private let base = Date(timeIntervalSince1970: 1_800_000_000)

@MainActor
@Suite("InboxStore")
struct InboxStoreTests {
    @Test("New messages count until Neuigkeiten was opened; the read state survives a restart")
    func unread() async {
        let backend = InboxBackend()
        let prefs = InMemoryKeyValueStore()
        await backend.set(messages: [
            InboxMessage(id: "a", kind: .broadcast, title: "A", body: "a", createdAt: base),
            InboxMessage(id: "b", kind: .unknown, createdAt: base.addingTimeInterval(day)),
        ])
        let store = InboxStore(backend: backend, store: prefs, now: { base })
        await store.refresh()
        #expect(store.messages.map(\.id) == ["a"])
        #expect(store.unreadCount == 1)
        store.markAllSeen()
        #expect(store.unreadCount == 0)

        await backend.set(messages: [
            InboxMessage(id: "c", kind: .restock, params: ["productTitle": "Office"], createdAt: base.addingTimeInterval(day)),
            InboxMessage(id: "a", kind: .broadcast, title: "A", body: "a", createdAt: base),
        ])
        let restarted = InboxStore(backend: backend, store: prefs, now: { base })
        await restarted.refresh()
        #expect(restarted.unreadCount == 1)
        #expect(restarted.isUnread(restarted.messages[0]))
    }

    @Test("A failed reload keeps the messages shown before; a first failure shows the error")
    func failure() async {
        let backend = InboxBackend()
        await backend.set(fails: true)
        let store = InboxStore(backend: backend, store: InMemoryKeyValueStore())
        await store.refresh()
        guard case .failed = store.state else {
            Issue.record("expected the error state")
            return
        }
        await backend.set(fails: false)
        await backend.set(messages: [InboxMessage(id: "a", kind: .broadcast, title: "A", body: "a", createdAt: base)])
        await store.refresh()
        await backend.set(fails: true)
        await store.refresh()
        #expect(store.messages.map(\.id) == ["a"])
    }

    @Test("Restock: watching is remembered only after the backend accepted it")
    func restock() async {
        let backend = InboxBackend()
        let prefs = InMemoryKeyValueStore()
        let store = InboxStore(backend: backend, store: prefs)
        await backend.set(fails: true)
        #expect(await store.setWatching(true, productHandle: "office", variantID: "v1", productTitle: "Office") == false)
        #expect(!store.isWatching(variantID: "v1"))

        await backend.set(fails: false)
        #expect(await store.setWatching(true, productHandle: "office", variantID: "v1", productTitle: "Office"))
        #expect(store.isWatching(variantID: "v1"))
        #expect(InboxStore(backend: backend, store: prefs).isWatching(variantID: "v1"))
        #expect(await backend.watched.map(\.variantId) == ["v1"])

        #expect(await store.setWatching(false, productHandle: "office", variantID: "v1", productTitle: "Office"))
        #expect(!store.isWatching(variantID: "v1"))
        #expect(await backend.unwatched == ["v1"])
    }

    @Test("Pushes about restock and inbox messages open the product or Neuigkeiten")
    func payloads() {
        let restock = PushPayload(userInfo: ["type": "restock", "handle": "office-2024"])
        #expect(restock?.deepLink?.absoluteString == "karinex://product/office-2024")
        #expect(PushPayload(userInfo: ["type": "inbox.message"])?.deepLink?.absoluteString == "karinex://notifications")
        #expect(PushPayload(userInfo: ["type": "inbox.message", "handle": "x"])?.deepLink?.absoluteString == "karinex://product/x")
        #expect(DeepLinkParser.route(for: URL(string: "karinex://notifications")!) == .notifications)
    }
}
