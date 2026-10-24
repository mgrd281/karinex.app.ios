@testable import CommerceUI
import Core
import Foundation
import ShopifyKit
import Testing

@MainActor
@Suite("CartStore")
struct CartStoreTests {
    private let repository = StubCartRepository()
    private let preferences = InMemoryKeyValueStore()

    private func makeStore(preloadDelay: Duration = .milliseconds(500)) -> CartStore {
        CartStore(repository: repository, store: preferences, appVersion: "1.2.3", preloadDelay: preloadDelay)
    }

    // MARK: Creation

    @Test("The first add creates the cart with the app attributes and persists its ID")
    func firstAddCreatesCart() async throws {
        let store = makeStore()
        let added = await store.add(variantID: CartFixtures.windowsVariant)

        #expect(added)
        #expect(store.itemCount == 1)
        let calls = await repository.calls
        #expect(calls == [
            .create(
                lines: [CartLineInput(merchandiseId: CartFixtures.windowsVariant, quantity: 1)],
                attributes: [AttributeInput(key: "app_platform", value: "ios"), AttributeInput(key: "app_version", value: "1.2.3")]
            ),
        ])
        let cartID = try #require(store.cart?.id)
        #expect(preferences.string(forKey: CartStore.cartIDKey) == cartID.rawValue)
        #expect(!store.isUpdating)
    }

    @Test("Later adds go to the existing cart")
    func laterAddsUseExistingCart() async {
        let store = makeStore()
        await store.add(variantID: CartFixtures.windowsVariant)
        await store.add(variantID: CartFixtures.officeVariant, quantity: 2)
        await store.add(variantID: CartFixtures.windowsVariant)

        #expect(await repository.count(of: .create) == 1)
        #expect(await repository.count(of: .add) == 2)
        #expect(store.itemCount == 4)
        #expect(store.cart?.lines.count == 2)
    }

    // MARK: Refresh and expiry

    @Test("Refresh loads the stored cart in a new session")
    func refreshLoadsStoredCart() async {
        let first = makeStore()
        await first.add(variantID: CartFixtures.windowsVariant, quantity: 3)

        let relaunched = makeStore()
        #expect(relaunched.cart == nil)
        await relaunched.refresh()
        #expect(relaunched.itemCount == 3)
    }

    @Test("Refresh forgets an expired cart; the next add creates a new one")
    func refreshForgetsExpiredCart() async throws {
        let store = makeStore()
        await store.add(variantID: CartFixtures.windowsVariant)
        let expiredID = try #require(store.cart?.id)
        await repository.expire(expiredID)

        await store.refresh()
        #expect(store.cart == nil)
        #expect(preferences.string(forKey: CartStore.cartIDKey) == nil)

        await store.add(variantID: CartFixtures.officeVariant)
        #expect(await repository.count(of: .create) == 2)
        #expect(store.cart?.id != expiredID)
        #expect(store.itemCount == 1)
    }

    @Test("An add refused because the cart expired recreates the cart once")
    func addRecreatesExpiredCart() async throws {
        let store = makeStore()
        await store.add(variantID: CartFixtures.windowsVariant)
        let expiredID = try #require(store.cart?.id)
        await repository.expire(expiredID)

        let added = await store.add(variantID: CartFixtures.officeVariant)

        #expect(added)
        #expect(store.lastError == nil)
        #expect(store.cart?.id != expiredID)
        #expect(store.cart?.lines.map(\.merchandise.id) == [CartFixtures.officeVariant])
        #expect(preferences.string(forKey: CartStore.cartIDKey) == store.cart?.id.rawValue)
    }

    // MARK: Quantity

    @Test("Quantity taps during an update coalesce: the latest intent wins")
    func quantityTapsCoalesce() async throws {
        let store = makeStore()
        await store.add(variantID: CartFixtures.windowsVariant)
        let lineID = try #require(store.cart?.lines.first?.id)
        await repository.holdUpdates()

        let first = Task { await store.setQuantity(lineID: lineID, quantity: 2) }
        while await repository.heldUpdateCount == 0 {
            await Task.yield()
        }
        let second = Task { await store.setQuantity(lineID: lineID, quantity: 3) }
        while store.displayedQuantity(for: lineID) != 3 {
            await Task.yield()
        }
        // An update for the line is waiting now, so these only change its target and return.
        await store.setQuantity(lineID: lineID, quantity: 4)
        await store.setQuantity(lineID: lineID, quantity: 5)
        #expect(store.displayedQuantity(for: lineID) == 5)
        #expect(store.isUpdating)

        await repository.releaseUpdates()
        await first.value
        await second.value

        let updates = await repository.updateCalls
        #expect(updates == [[CartLineUpdateInput(id: lineID, quantity: 2)], [CartLineUpdateInput(id: lineID, quantity: 5)]])
        #expect(store.line(for: lineID)?.quantity == 5)
        #expect(store.displayedQuantity(for: lineID) == 5)
        #expect(!store.isUpdating)
    }

    @Test("Setting a quantity of zero removes the line")
    func zeroQuantityRemoves() async throws {
        let store = makeStore()
        await store.add(variantID: CartFixtures.windowsVariant)
        let lineID = try #require(store.cart?.lines.first?.id)

        await store.setQuantity(lineID: lineID, quantity: 0)

        #expect(store.cart?.lines.isEmpty == true)
        #expect(await repository.count(of: .remove) == 1)
    }

    // MARK: Remove and undo

    @Test("Undo restores the removed line with its quantity")
    func undoRestoresRemovedLine() async throws {
        let store = makeStore()
        await store.add(variantID: CartFixtures.officeVariant, quantity: 2)
        let lineID = try #require(store.cart?.lines.first?.id)

        await store.remove(lineID: lineID)
        #expect(store.itemCount == 0)
        #expect(store.canUndoRemove)
        #expect(store.lastRemovedLine?.merchandise.id == CartFixtures.officeVariant)

        let restored = await store.undoRemove()
        #expect(restored)
        #expect(!store.canUndoRemove)
        #expect(store.itemCount == 2)
        let lastCall = await repository.calls.last
        #expect(lastCall == .add(lines: [CartLineInput(merchandiseId: CartFixtures.officeVariant, quantity: 2)]))
    }

    // MARK: Discount codes

    @Test("Discount codes: applicable, not applicable with Shopify's warning, and removal")
    func discountCodes() async {
        let store = makeStore()
        await store.add(variantID: CartFixtures.windowsVariant)

        #expect(await store.applyDiscountCode("  \(StubCartRepository.validDiscountCode) ") == .applied)
        #expect(await store.applyDiscountCode("FALSCH") == .notApplicable)
        #expect(store.lastWarnings.count == 1)
        #expect(store.cart?.discountCodes.map(\.code) == [StubCartRepository.validDiscountCode, "FALSCH"])

        await store.removeDiscountCode("falsch")
        #expect(store.cart?.discountCodes.map(\.code) == [StubCartRepository.validDiscountCode])
        #expect(store.lastWarnings.isEmpty)
    }

    @Test("A discount code without a cart fails without a request")
    func discountWithoutCart() async {
        let store = makeStore()
        #expect(await store.applyDiscountCode("WILLKOMMEN") == .failed)
        #expect(store.lastError?.kind == .notFound)
        #expect(await repository.calls.isEmpty)
    }

    // MARK: Errors

    @Test("An offline failure maps to the offline error and is not repeated")
    func offlineFailure() async {
        let store = makeStore()
        await repository.fail(.create, with: ShopifyError.network(.offline))

        let added = await store.add(variantID: CartFixtures.windowsVariant)

        #expect(!added)
        #expect(store.lastError?.kind == .offline)
        #expect(await repository.calls.count == 1)
        #expect(store.cart == nil)
    }

    @Test("After an ambiguous failure the cart is re-read, never written again")
    func ambiguousFailureRereads() async {
        let store = makeStore()
        await store.add(variantID: CartFixtures.windowsVariant)
        await repository.fail(.add, with: ShopifyError.network(.timeout))

        let added = await store.add(variantID: CartFixtures.officeVariant)

        #expect(!added)
        #expect(store.lastError?.kind == .timeout)
        let calls = await repository.calls
        #expect(calls.suffix(2) == [.add(lines: [CartLineInput(merchandiseId: CartFixtures.officeVariant)]), .cart])
        #expect(store.itemCount == 1)
    }

    @Test("Shopify's user errors keep their messages")
    func userErrorsKeepMessages() async {
        let store = makeStore()
        await repository.fail(
            .create,
            with: ShopifyError.userErrors([UserError(field: ["input"], message: "Nicht genug Bestand.", code: .merchandiseNotEnoughStock)])
        )

        await store.add(variantID: CartFixtures.windowsVariant)

        #expect(store.lastError?.kind == .rejected(messages: ["Nicht genug Bestand."]))
        #expect(store.lastError?.message == "Nicht genug Bestand.")
        #expect(store.lastError?.isRetryable == false)
    }

    // MARK: Country

    @Test("A market change moves the cart to the new country once")
    func updateCountry() async {
        let store = makeStore()
        await store.updateCountry(.at)
        #expect(await repository.calls.isEmpty)

        await store.add(variantID: CartFixtures.windowsVariant)
        await store.updateCountry(.de)
        await store.updateCountry(.at)

        #expect(await repository.count(of: .buyerIdentity) == 1)
        #expect(store.cart?.buyerIdentity.countryCode == .at)
    }

    // MARK: Checkout

    @Test("The checkout URL comes from a fresh read of the cart")
    func checkoutURLRereadsCart() async throws {
        let store = makeStore()
        await store.add(variantID: CartFixtures.windowsVariant)
        let cartID = try #require(store.cart?.id)

        let url = try await store.checkoutURL()

        #expect(url == CartFixtures.checkoutURL(for: cartID))
        #expect(await repository.calls.last == .cart)
    }

    @Test("An expired cart is recreated with its lines before checkout")
    func checkoutRecreatesExpiredCart() async throws {
        let store = makeStore()
        await store.add(variantID: CartFixtures.officeVariant, quantity: 2)
        let expiredID = try #require(store.cart?.id)
        await repository.expire(expiredID)

        let url = try await store.checkoutURL()

        let newID = try #require(store.cart?.id)
        #expect(newID != expiredID)
        #expect(url == CartFixtures.checkoutURL(for: newID))
        let lastCall = await repository.calls.last
        #expect(lastCall == .create(
            lines: [CartLineInput(merchandiseId: CartFixtures.officeVariant, quantity: 2)],
            attributes: [AttributeInput(key: "app_platform", value: "ios"), AttributeInput(key: "app_version", value: "1.2.3")]
        ))
    }

    @Test("Without a cart there is no checkout")
    func checkoutWithoutCart() async {
        let store = makeStore()
        await #expect(throws: UserFacingError(kind: .notFound)) {
            try await store.checkoutURL()
        }
    }

    @Test("Clearing after checkout forgets the cart")
    func clearAfterCheckout() async {
        let store = makeStore()
        await store.add(variantID: CartFixtures.windowsVariant)

        store.clearAfterCheckout()

        #expect(store.cart == nil)
        #expect(store.itemCount == 0)
        #expect(preferences.string(forKey: CartStore.cartIDKey) == nil)
    }

    // MARK: Preload

    @Test("The checkout preloader runs once, debounced, after a burst of changes")
    func preloadIsDebounced() async throws {
        let store = makeStore(preloadDelay: .milliseconds(300))
        let recorder = PreloadRecorder()
        store.checkoutPreloader = { recorder.urls.append($0) }

        await store.add(variantID: CartFixtures.windowsVariant)
        await store.add(variantID: CartFixtures.officeVariant)
        #expect(recorder.urls.isEmpty)

        try await Task.sleep(for: .milliseconds(900))
        let cartID = try #require(store.cart?.id)
        #expect(recorder.urls == [CartFixtures.checkoutURL(for: cartID)])
    }

    @Test("Ambiguity: only failures that may have executed count as ambiguous")
    func ambiguity() {
        #expect(CartStore.isAmbiguous(ShopifyError.network(.timeout)))
        #expect(CartStore.isAmbiguous(ShopifyError.http(statusCode: 502)))
        #expect(!CartStore.isAmbiguous(ShopifyError.network(.offline)))
        #expect(!CartStore.isAmbiguous(ShopifyError.throttled))
        #expect(!CartStore.isAmbiguous(ShopifyError.userErrors([])))
        #expect(!CartStore.isAmbiguous(CancellationError()))
    }
}

/// Collects the URLs handed to the checkout preloader.
@MainActor
private final class PreloadRecorder {
    var urls: [URL] = []
}
