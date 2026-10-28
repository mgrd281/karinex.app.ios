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

    @Test("An expired or completed cart is forgotten before checkout, never recreated from its lines")
    func checkoutForgetsExpiredCart() async throws {
        let store = makeStore()
        await store.add(variantID: CartFixtures.officeVariant, quantity: 2)
        let expiredID = try #require(store.cart?.id)
        await repository.expire(expiredID)

        await #expect(throws: CartStore.expiredCartError) {
            try await store.checkoutURL()
        }

        #expect(store.cart == nil)
        #expect(store.itemCount == 0)
        #expect(preferences.string(forKey: CartStore.cartIDKey) == nil)
        #expect(await repository.count(of: .create) == 1, "The cart must not be recreated with the old lines")
        #expect(await repository.calls.last == .cart)
    }

    @Test("The expired cart error explains what to do in German and English")
    func expiredCartErrorText() throws {
        let error = CartStore.expiredCartError
        #expect(!error.isRetryable)
        guard case let .rejected(messages) = error.kind else {
            Issue.record("Unexpected kind \(error.kind)")
            return
        }
        #expect(messages.count == 1)
        let bundle = CommerceUIResources.bundle
        let german = try #require(bundle.path(forResource: "de", ofType: "lproj").flatMap(Bundle.init(path:)))
        let english = try #require(bundle.path(forResource: "en", ofType: "lproj").flatMap(Bundle.init(path:)))
        #expect(german.localizedString(forKey: "commerce.cart.expired", value: nil, table: nil)
            == "Ihr Warenkorb ist abgelaufen. Bitte legen Sie die Artikel erneut in den Warenkorb.")
        #expect(english.localizedString(forKey: "commerce.cart.expired", value: nil, table: nil)
            == "Your basket has expired. Please add the items to your basket again.")
    }

    @Test("After an expired checkout the next add creates a new cart")
    func addAfterExpiredCheckoutCreatesCart() async throws {
        let store = makeStore()
        await store.add(variantID: CartFixtures.officeVariant)
        let expiredID = try #require(store.cart?.id)
        await repository.expire(expiredID)
        _ = try? await store.checkoutURL()

        await store.add(variantID: CartFixtures.windowsVariant)

        let newID = try #require(store.cart?.id)
        #expect(newID != expiredID)
        #expect(store.cart?.lines.map(\.merchandise.id) == [CartFixtures.windowsVariant])
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

    // MARK: Signed-in checkout

    /// A store whose customer is signed in with `token` (or nobody, for `nil`), recording
    /// preloads and dropped preloads in `recorder`.
    private func makeSignedInStore(token: String?, recorder: PreloadRecorder) -> CartStore {
        let store = makeStore(preloadDelay: .milliseconds(50))
        store.checkoutPreloader = { recorder.urls.append($0) }
        store.checkoutInvalidator = { recorder.invalidations += 1 }
        store.customerAccessToken = { token }
        return store
    }

    @Test("A signed-in checkout carries the customer's token, drops the preloaded checkout and is not preloaded again")
    func signedInCheckout() async throws {
        let recorder = PreloadRecorder()
        let store = makeSignedInStore(token: "shcat_test", recorder: recorder)
        await store.add(variantID: CartFixtures.windowsVariant)
        let cartID = try #require(store.cart?.id)

        let url = try await store.checkoutURL()

        #expect(url == CartFixtures.checkoutURL(for: cartID))
        #expect(await repository.customerAccessToken(of: cartID) == "shcat_test")
        #expect(await repository.calls.suffix(2) == [.cart, .customerAccessToken("shcat_test")])
        #expect(preferences.string(forKey: CartStore.signedInCartIDKey) == cartID.rawValue)
        #expect(recorder.invalidations == 1)

        recorder.urls.removeAll()
        await store.add(variantID: CartFixtures.officeVariant)
        try await Task.sleep(for: .milliseconds(300))
        #expect(recorder.urls.isEmpty, "A signed-in cart's checkout URL expires, so it is not preloaded")
    }

    @Test("A signed-in customer's new cart carries the token from its creation, so their discounts show in the cart")
    func signedInCartFromCreation() async throws {
        let recorder = PreloadRecorder()
        let store = makeSignedInStore(token: "shcat_test", recorder: recorder)

        await store.add(variantID: CartFixtures.windowsVariant)

        let cartID = try #require(store.cart?.id)
        #expect(await repository.customerAccessToken(of: cartID) == "shcat_test")
        #expect(await repository.count(of: .create) == 1)
        #expect(await repository.calls.last == .customerAccessToken("shcat_test"))
        #expect(preferences.string(forKey: CartStore.signedInCartIDKey) == cartID.rawValue)
        #expect(recorder.invalidations == 1)

        await store.add(variantID: CartFixtures.officeVariant)
        #expect(await repository.count(of: .customerAccessToken) == 1, "A cart that carries the token is not signed in again")
    }

    @Test("A guest cart is signed in by the launch refresh and after a sign-in, once")
    func guestCartSignedInLater() async throws {
        let store = makeSignedInStore(token: nil, recorder: PreloadRecorder())
        await store.add(variantID: CartFixtures.windowsVariant)
        let cartID = try #require(store.cart?.id)
        #expect(await repository.count(of: .customerAccessToken) == 0)

        store.customerAccessToken = { "shcat_test" }
        await store.associateCustomer()
        #expect(await repository.customerAccessToken(of: cartID) == "shcat_test")

        await store.refresh()
        await store.associateCustomer()
        #expect(await repository.count(of: .customerAccessToken) == 1)
    }

    @Test("The launch refresh signs in a stored guest cart")
    func refreshSignsInStoredCart() async throws {
        let guest = makeSignedInStore(token: nil, recorder: PreloadRecorder())
        await guest.add(variantID: CartFixtures.windowsVariant)
        let cartID = try #require(guest.cart?.id)

        let relaunched = makeSignedInStore(token: "shcat_test", recorder: PreloadRecorder())
        await relaunched.refresh()

        #expect(relaunched.cart?.id == cartID)
        #expect(await repository.customerAccessToken(of: cartID) == "shcat_test")
    }

    @Test("Without a signed-in customer the checkout stays a guest checkout")
    func guestCheckout() async throws {
        let recorder = PreloadRecorder()
        let store = makeSignedInStore(token: nil, recorder: recorder)
        await store.add(variantID: CartFixtures.windowsVariant)
        let cartID = try #require(store.cart?.id)

        let url = try await store.checkoutURL()

        #expect(url == CartFixtures.checkoutURL(for: cartID))
        #expect(await repository.count(of: .customerAccessToken) == 0)
        #expect(preferences.string(forKey: CartStore.signedInCartIDKey) == nil)
        #expect(recorder.invalidations == 0)
    }

    @Test("A token Shopify refuses keeps a guest cart and still opens the checkout, as a guest checkout")
    func refusedToken() async throws {
        let store = makeSignedInStore(token: "shcat_expired", recorder: PreloadRecorder())
        await repository.fail(.customerAccessToken, with: ShopifyError.userErrors([]))
        await repository.fail(.customerAccessToken, with: ShopifyError.userErrors([]))
        await store.add(variantID: CartFixtures.windowsVariant)
        let cartID = try #require(store.cart?.id)
        #expect(preferences.string(forKey: CartStore.signedInCartIDKey) == nil, "A refusal takes the mark off, so checkout retries")

        let url = try await store.checkoutURL()

        #expect(url == CartFixtures.checkoutURL(for: cartID))
        #expect(store.lastError == nil)
        #expect(await repository.customerAccessToken(of: cartID) == nil)
    }

    @Test("Signing out moves a signed-in cart's lines and codes to a new cart without the token")
    func signOutReplacesSignedInCart() async throws {
        let recorder = PreloadRecorder()
        let store = makeSignedInStore(token: "shcat_test", recorder: recorder)
        await store.add(variantID: CartFixtures.officeVariant, quantity: 2)
        _ = await store.applyDiscountCode(StubCartRepository.validDiscountCode)
        let signedInID = try #require(store.cart?.id)
        _ = try await store.checkoutURL()
        store.customerAccessToken = { nil }

        await store.signOutCustomer()

        let newID = try #require(store.cart?.id)
        #expect(newID != signedInID)
        #expect(store.cart?.lines.map(\.merchandise.id) == [CartFixtures.officeVariant])
        #expect(store.itemCount == 2)
        #expect(store.cart?.discountCodes.map(\.code) == [StubCartRepository.validDiscountCode])
        #expect(await repository.customerAccessToken(of: newID) == nil)
        #expect(preferences.string(forKey: CartStore.cartIDKey) == newID.rawValue)
        #expect(preferences.string(forKey: CartStore.signedInCartIDKey) == nil)
        #expect(recorder.invalidations == 2)
    }

    @Test("Signing out keeps a cart that never carried a token")
    func signOutKeepsGuestCart() async throws {
        let store = makeSignedInStore(token: nil, recorder: PreloadRecorder())
        await store.add(variantID: CartFixtures.windowsVariant)
        let cartID = try #require(store.cart?.id)

        await store.signOutCustomer()

        #expect(store.cart?.id == cartID)
        #expect(await repository.count(of: .create) == 1)
    }

    @Test("A cart still signed in after the customer left is replaced before checkout")
    func checkoutReplacesLeftoverSignedInCart() async throws {
        let store = makeSignedInStore(token: "shcat_test", recorder: PreloadRecorder())
        await store.add(variantID: CartFixtures.windowsVariant)
        let signedInID = try #require(store.cart?.id)
        _ = try await store.checkoutURL()
        store.customerAccessToken = { nil }

        let url = try await store.checkoutURL()

        let newID = try #require(store.cart?.id)
        #expect(newID != signedInID)
        #expect(url == CartFixtures.checkoutURL(for: newID))
        #expect(await repository.customerAccessToken(of: newID) == nil)
        #expect(preferences.string(forKey: CartStore.signedInCartIDKey) == nil)
    }

    @Test("When no new cart can be made, signing out forgets the signed-in cart")
    func signOutForgetsCartOnFailure() async throws {
        let store = makeSignedInStore(token: "shcat_test", recorder: PreloadRecorder())
        await store.add(variantID: CartFixtures.windowsVariant)
        _ = try await store.checkoutURL()
        store.customerAccessToken = { nil }
        await repository.fail(.create, with: ShopifyError.network(.offline))

        await store.signOutCustomer()

        #expect(store.cart == nil)
        #expect(preferences.string(forKey: CartStore.cartIDKey) == nil)
        #expect(preferences.string(forKey: CartStore.signedInCartIDKey) == nil)
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

/// Collects the URLs handed to the checkout preloader and counts the dropped preloads.
@MainActor
private final class PreloadRecorder {
    var urls: [URL] = []
    var invalidations = 0
}
