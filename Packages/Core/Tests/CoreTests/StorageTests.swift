@testable import Core
import Foundation
import Testing

private struct StoredToken: Codable, Equatable {
    var accessToken: String
    var expiresAt: Date
}

@Suite("InMemorySecureStore")
struct InMemorySecureStoreTests {
    @Test("Stores, reads, overwrites and removes data")
    func dataRoundTrip() throws {
        let store = InMemorySecureStore()
        #expect(try store.data(for: "token") == nil)
        try store.set(Data([1, 2, 3]), for: "token")
        #expect(try store.data(for: "token") == Data([1, 2, 3]))
        try store.set(Data([4]), for: "token")
        #expect(try store.data(for: "token") == Data([4]))
        try store.removeValue(for: "token")
        #expect(try store.data(for: "token") == nil)
        try store.removeValue(for: "missing")
    }

    @Test("removeAll clears every value")
    func removeAll() throws {
        let store = InMemorySecureStore(values: ["a": Data([1]), "b": Data([2])])
        #expect(store.keys == ["a", "b"])
        try store.removeAll()
        #expect(store.keys.isEmpty)
    }

    @Test("Codable helpers round-trip values")
    func codableHelpers() throws {
        let store = InMemorySecureStore()
        let token = StoredToken(accessToken: "value", expiresAt: Date(timeIntervalSinceReferenceDate: 800_000_000.25))
        try store.setValue(token, for: "session")
        #expect(try store.value(StoredToken.self, for: "session") == token)
        #expect(try store.value(StoredToken.self, for: "missing") == nil)
    }

    @Test("Codable helpers report corrupt data as a decoding error")
    func decodingError() throws {
        let store = InMemorySecureStore(values: ["session": Data("not json".utf8)])
        #expect(throws: SecureStoreError.decoding) {
            try store.value(StoredToken.self, for: "session")
        }
    }

    @Test("String helpers round-trip UTF-8")
    func stringHelpers() throws {
        let store = InMemorySecureStore()
        try store.setString("Käyttöoikeusavain", for: "label")
        #expect(try store.string(for: "label") == "Käyttöoikeusavain")
        try store.set(Data([0xFF, 0xFE]), for: "binary")
        #expect(throws: SecureStoreError.decoding) {
            try store.string(for: "binary")
        }
    }
}

@Suite("KeyValueStore")
struct KeyValueStoreTests {
    @Test("In-memory store keeps values typed")
    func inMemoryTyped() {
        let store = InMemoryKeyValueStore()
        store.set("cart", forKey: "string")
        store.set(true, forKey: "bool")
        store.set(Data([7]), forKey: "data")

        #expect(store.string(forKey: "string") == "cart")
        #expect(store.bool(forKey: "bool") == true)
        #expect(store.data(forKey: "data") == Data([7]))

        #expect(store.bool(forKey: "string") == nil)
        #expect(store.string(forKey: "bool") == nil)
        #expect(store.data(forKey: "string") == nil)
        #expect(store.bool(forKey: "missing") == nil)
    }

    @Test("Setting nil or removing deletes the value")
    func inMemoryRemoval() {
        let store = InMemoryKeyValueStore()
        store.set("x", forKey: "a")
        store.set(false, forKey: "b")
        store.set(Data([1]), forKey: "c")
        store.set(String?.none, forKey: "a")
        store.set(Bool?.none, forKey: "b")
        store.removeValue(forKey: "c")
        #expect(store.keys.isEmpty)
    }

    @Test("Codable helpers round-trip and remove")
    func codableHelpers() throws {
        let store = InMemoryKeyValueStore()
        try store.setValue(["DE", "PT_PT"], forKey: "market")
        #expect(try store.value([String].self, forKey: "market") == ["DE", "PT_PT"])
        try store.setValue([String]?.none, forKey: "market")
        #expect(try store.value([String].self, forKey: "market") == nil)
    }

    @Test("Codable helpers surface decoding errors")
    func codableDecodingError() {
        let store = InMemoryKeyValueStore()
        store.set(Data("{".utf8), forKey: "broken")
        #expect(throws: DecodingError.self) {
            try store.value([String].self, forKey: "broken")
        }
    }

    @Test("UserDefaults store keeps values typed")
    func userDefaultsTyped() throws {
        let suiteName = "de.karinex.core-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsStore(defaults: defaults)

        store.set("cart", forKey: "string")
        store.set(true, forKey: "bool")
        store.set(Data([7]), forKey: "data")
        #expect(store.string(forKey: "string") == "cart")
        #expect(store.bool(forKey: "bool") == true)
        #expect(store.data(forKey: "data") == Data([7]))
        #expect(store.bool(forKey: "missing") == nil)
        #expect(store.data(forKey: "string") == nil)

        store.set(String?.none, forKey: "string")
        store.removeValue(forKey: "bool")
        #expect(store.string(forKey: "string") == nil)
        #expect(store.bool(forKey: "bool") == nil)
    }
}

@Suite("ConsentStore")
struct ConsentStoreTests {
    @Test("Defaults to undecided with everything off")
    func defaultsToUndecided() {
        let store = ConsentStore(store: InMemoryKeyValueStore())
        let consent = store.load()
        #expect(consent == .undecided)
        #expect(!consent.hasDecided)
        #expect(!consent.analytics)
        #expect(!consent.crashReports)
        #expect(!consent.orderUpdateNotifications)
        #expect(!consent.dealNotifications)
        #expect(!consent.allowsPushRegistration)
    }

    @Test("Round-trips a decision")
    func roundTrip() {
        let backing = InMemoryKeyValueStore()
        let store = ConsentStore(store: backing)
        let decision = PrivacyConsent(analytics: true, orderUpdateNotifications: true)
            .decided(at: Date(timeIntervalSinceReferenceDate: 812_345_678.123))
        store.save(decision)

        #expect(backing.data(forKey: ConsentStore.storageKey) != nil)
        #expect(ConsentStore.storageKey == "privacy.consent.v1")
        let loaded = ConsentStore(store: backing).load()
        #expect(loaded == decision)
        #expect(loaded.hasDecided)
        #expect(loaded.allowsPushRegistration)
    }

    @Test("Corrupt data falls back to undecided and is logged without content")
    func corruptData() {
        let backing = InMemoryKeyValueStore()
        backing.set(Data("garbage".utf8), forKey: ConsentStore.storageKey)
        let sink = RecordingLogSink()
        let store = ConsentStore(store: backing, logger: KXLogger(category: .consent, sink: sink))
        #expect(store.load() == .undecided)
        #expect(sink.entries.map(\.level) == [.error])
        #expect(!(sink.messages.first ?? "").contains("garbage"))
    }

    @Test("Older payloads without newer flags still decode")
    func tolerantDecoding() {
        let backing = InMemoryKeyValueStore()
        backing.set(Data(#"{"analytics":true}"#.utf8), forKey: ConsentStore.storageKey)
        let consent = ConsentStore(store: backing).load()
        #expect(consent.analytics)
        #expect(!consent.crashReports)
        #expect(consent.decidedAt == nil)
    }

    @Test("Reset removes the stored decision")
    func reset() {
        let backing = InMemoryKeyValueStore()
        let store = ConsentStore(store: backing)
        store.save(PrivacyConsent(crashReports: true).decided())
        store.reset()
        #expect(store.load() == .undecided)
    }
}
