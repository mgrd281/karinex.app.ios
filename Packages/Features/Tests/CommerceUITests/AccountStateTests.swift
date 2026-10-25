import BackendKit
@testable import CommerceUI
import Core
import Foundation
import ShopifyKit
import Testing

// MARK: - CallCounter

/// Counts calls of a `@MainActor` callback.
@MainActor
final class CallCounter {
    var calls = 0
}

// MARK: - Deep links

@Suite("Account deep links")
struct AccountDeepLinkTests {
    private func route(_ string: String) throws -> CommerceRoute? {
        try DeepLinkParser.route(for: #require(URL(string: string)))
    }

    @Test("Account links open the account screens", arguments: [
        ("karinex://account", CommerceRoute.account(.overview)),
        ("karinex://account/orders", .account(.orders)),
        ("karinex://account/orders/5678", .account(.order(id: "gid://shopify/Order/5678"))),
        ("karinex://account/licenses", .account(.licenses(orderID: nil))),
        ("https://karinex.de/account", .account(.overview)),
        ("https://www.karinex.de/account/orders/5678", .account(.order(id: "gid://shopify/Order/5678"))),
    ])
    func accountRoutes(url: String, expected: CommerceRoute) throws {
        #expect(try route(url) == expected)
    }

    @Test("Malformed account links are ignored", arguments: [
        "karinex://account/orders/abc",
        "karinex://account/orders/123/extra",
        "karinex://account/unknown",
        "karinex://account/orders/123456789012345678901",
    ])
    func malformed(url: String) throws {
        #expect(try route(url) == nil)
    }

    @Test("Order IDs are digits only")
    func orderIDs() {
        #expect(DeepLinkParser.orderID("1042") == "gid://shopify/Order/1042")
        #expect(DeepLinkParser.orderID("") == nil)
        #expect(DeepLinkParser.orderID("10a2") == nil)
        #expect(DeepLinkParser.orderID("../1") == nil)
    }
}

// MARK: - Settings

@Suite("App settings")
@MainActor
struct AppSettingsStoreTests {
    @Test("Defaults are the system appearance and an unlocked vault")
    func defaults() {
        let settings = AppSettingsStore(store: InMemoryKeyValueStore())

        #expect(settings.appearance == .system)
        #expect(settings.appearance.colorScheme == nil)
        #expect(!settings.locksLicenses)
    }

    @Test("Changes are saved and read again")
    func persistence() {
        let store = InMemoryKeyValueStore()
        let settings = AppSettingsStore(store: store)

        settings.appearance = .dark
        settings.locksLicenses = true
        let reloaded = AppSettingsStore(store: store)

        #expect(reloaded.appearance == .dark)
        #expect(reloaded.appearance.colorScheme == .dark)
        #expect(reloaded.locksLicenses)
    }

    @Test("An unknown saved appearance falls back to the system")
    func unknownAppearance() {
        let store = InMemoryKeyValueStore()
        store.set("sepia", forKey: AppSettingsStore.appearanceKey)

        #expect(AppSettingsStore(store: store).appearance == .system)
    }
}

// MARK: - Session

@Suite("Customer session store")
@MainActor
struct CustomerSessionStoreTests {
    @Test("Without a client ID login is unavailable")
    func unavailable() async {
        let store = CustomerSessionStore(session: nil, repository: nil, callbackScheme: nil, hasStoredTokens: true)
        let signedOutCalls = CallCounter()
        store.onSignedOut = { signedOutCalls.calls += 1 }

        #expect(store.status == .unavailable)
        #expect(!store.isAvailable)
        #expect(!store.isSignedIn)
        await store.signIn(locale: "de") { _, _ in
            Issue.record("The login page must not open")
            return URL(fileURLWithPath: "/")
        }
        #expect(store.status == .unavailable)
        #expect(await store.signOut() == nil)
        #expect(signedOutCalls.calls == 0)
    }
}

// MARK: - Errors

@Suite("Account errors")
struct AccountErrorTests {
    @Test("Login and backend errors map to customer-facing kinds", arguments: [
        (CustomerAccountAuthError.signedOut as any Error, UserFacingError.Kind.signedOut),
        (CustomerAccountAuthError.invalidGrant, .signedOut),
        (BackendError.unauthorized, .signedOut),
        (BackendError.rateLimited(retryAfter: nil), .throttled),
        (BackendError.server(statusCode: 502, code: nil, requestID: nil), .server),
        (BackendError.notFound, .notFound),
        (BackendError.network(.offline), .offline),
        (BackendError.decoding, .unknown),
    ])
    func mapping(error: any Error, expected: UserFacingError.Kind) throws {
        let mapped = try #require(UserFacingError(error))

        #expect(mapped.kind == expected)
    }

    @Test("A closed login page is no error")
    func cancelledLogin() {
        #expect(UserFacingError(CustomerAccountAuthError.cancelled) == nil)
    }
}
