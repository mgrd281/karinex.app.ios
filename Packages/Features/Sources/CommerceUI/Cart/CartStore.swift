import Core
import Foundation
import Observation
import ShopifyKit

// MARK: - CartStore

/// Owns the customer's Shopify cart for the whole app.
///
/// - The cart ID is persisted in the ``KeyValueStore`` under ``cartIDKey``; ``refresh()`` reads
///   the cart at launch and when the app returns to the foreground. An expired or completed cart
///   is forgotten and a new one is created lazily with the next ``add(variantID:quantity:)``.
/// - Mutations run one at a time in the order they were requested. Quantity taps on the same
///   line are coalesced: while an update is waiting, further taps only change the target, so the
///   latest intent wins and no intermediate value is sent.
/// - Mutations are never repeated after an ambiguous failure (timeout, dropped connection,
///   5xx): the store re-reads the cart instead (see docs/ARCHITECTURE.md, retry rules).
/// - A mutation refused because the cart no longer exists recreates the cart once and repeats
///   the intent there; Shopify's refusal guarantees the first attempt had no effect.
/// - ``checkoutURL()`` never recreates an expired or completed cart from its last known lines
///   (they may already belong to a placed order); it forgets the cart and reports it.
/// - After every change the ``checkoutPreloader`` is called with the fresh checkout URL,
///   debounced by ``preloadDelay``, so Checkout Kit can preload (CommerceUI does not import it).
/// - While a customer is signed in, the cart carries their access token
///   (``customerAccessToken``): from the launch refresh, from its creation and from the sign-in
///   on (``associateCustomer()``), so Shopify prices the cart for them and automatic discounts
///   of their customer segment (the loyalty level's permanent discount) show in the cart, not
///   only at checkout. ``checkoutURL()`` puts a fresh token on it again right before checkout,
///   so checkout opens signed in with their e-mail address, addresses and saved payment
///   methods, and the order belongs to their account (Shopify's "Authenticate checkouts" for
///   Checkout Kit). Such a cart is never preloaded, because its checkout URL expires. After a sign-out, ``signOutCustomer()``
///   moves the lines to a new cart without the token, so the next checkout on this device
///   never shows the previous customer's details.
///
/// No cart ID, line ID or checkout URL is ever logged.
@MainActor
@Observable
public final class CartStore {
    /// The key the cart ID is stored under.
    public static let cartIDKey = "cart.id.v1"
    /// The cart attribute that marks carts created by the app.
    public static let platformAttributeKey = "app_platform"
    /// The value of ``platformAttributeKey``.
    public static let platformAttributeValue = "ios"
    /// The cart attribute carrying the app version.
    public static let versionAttributeKey = "app_version"
    /// The key the ID of a cart that carries a customer access token is stored under.
    public static let signedInCartIDKey = "cart.signedIn.v1"
    /// The cart attribute carrying the customer's consent to immediate delivery of digital
    /// content (§ 356 Abs. 5 BGB), the same attribute and format as the web shop's checkbox:
    /// `Ja (<ISO 8601 time>)`. The order confirmation e-mail confirms it from there.
    public static let withdrawalConsentKey = "widerruf_consent"

    // MARK: State

    /// The current cart, or `nil` when there is none yet (or it expired).
    public private(set) var cart: Cart?
    /// Whether a mutation is running or waiting.
    public private(set) var isUpdating = false
    /// The last failure, for a banner or an inline message. Set it to `nil` to dismiss it.
    public var lastError: UserFacingError?
    /// Shopify's warnings from the last mutation (for example a discount code that is not
    /// applicable), with Shopify's localized messages.
    public private(set) var lastWarnings: [CartWarning] = []
    /// The line removed last, while ``undoRemove()`` can still restore it.
    public private(set) var lastRemovedLine: CartLine?

    /// The number of items in the cart (the tab badge).
    public var itemCount: Int {
        cart?.totalQuantity ?? 0
    }

    /// Whether ``undoRemove()`` has something to restore.
    public var canUndoRemove: Bool {
        lastRemovedLine != nil
    }

    /// Called with the cart's checkout URL after every change (debounced), so the App can let
    /// Checkout Kit preload the checkout. `nil` disables preloading.
    public var checkoutPreloader: (@MainActor (URL) -> Void)?

    /// The debounce interval of ``checkoutPreloader``.
    public let preloadDelay: Duration

    /// Returns a valid Customer Account API access token while a customer is signed in, `nil`
    /// otherwise. The cart carries it while the customer is signed in and ``checkoutURL()``
    /// refreshes it; `nil` (or no supplier) keeps every cart and checkout a guest one. The
    /// token is a secret and is never stored or logged here.
    public var customerAccessToken: (@MainActor () async -> String?)?

    /// Called when a checkout Checkout Kit may have preloaded no longer matches the cart,
    /// because the cart was signed in or replaced; the App drops Checkout Kit's cache with it.
    public var checkoutInvalidator: (@MainActor () -> Void)?

    // MARK: Dependencies

    @ObservationIgnored private let repository: any CartRepository
    @ObservationIgnored private let store: any KeyValueStore
    @ObservationIgnored private let appVersion: String
    @ObservationIgnored private let logger: KXLogger

    // MARK: Serialisation

    /// The last enqueued operation; every new operation waits for it.
    @ObservationIgnored private var queueTail: Task<Void, Never>?
    /// Operations enqueued and not yet finished.
    @ObservationIgnored private var pendingOperationCount = 0
    /// Target quantities of lines whose update is waiting in the queue.
    @ObservationIgnored private var pendingQuantities: [ShopifyID: Int] = [:]
    /// The debounced preload.
    @ObservationIgnored private var preloadTask: Task<Void, Never>?

    /// Creates the cart store.
    ///
    /// - Parameters:
    ///   - repository: The Storefront cart repository.
    ///   - store: Where the cart ID is persisted.
    ///   - appVersion: The app version, sent as the `app_version` cart attribute.
    ///   - preloadDelay: The debounce interval of ``checkoutPreloader``. Defaults to 0.5 s.
    ///   - logger: The logger. Defaults to the `cart` category.
    public init(
        repository: any CartRepository,
        store: any KeyValueStore,
        appVersion: String,
        preloadDelay: Duration = .milliseconds(500),
        logger: KXLogger = KXLogger(category: .cart)
    ) {
        self.repository = repository
        self.store = store
        self.appVersion = appVersion
        self.preloadDelay = preloadDelay
        self.logger = logger
    }

    // MARK: Reading

    /// The persisted cart ID, if any.
    public var storedCartID: ShopifyID? {
        store.string(forKey: Self.cartIDKey).map(ShopifyID.init(rawValue:))
    }

    /// The quantity to show for a line: a pending target from coalesced taps, otherwise the
    /// quantity Shopify returned.
    public func displayedQuantity(for lineID: ShopifyID) -> Int {
        pendingQuantities[lineID] ?? line(for: lineID)?.quantity ?? 0
    }

    /// The line with `lineID` in the current cart.
    public func line(for lineID: ShopifyID) -> CartLine? {
        cart?.lines.first { $0.id == lineID }
    }

    /// Reloads the persisted cart. An expired or completed cart is forgotten (a new one is
    /// created with the next add). Failures set ``lastError`` and keep the current cart.
    public func refresh() async {
        _ = await serialized { [self] in
            guard let cartID = storedCartID else {
                cart = nil
                return
            }
            if let fresh = try await repository.cart(id: cartID) {
                cart = fresh
                await attachCustomer()
                schedulePreload()
            } else {
                logger.info("Stored cart is no longer available; it will be recreated with the next add")
                forgetCart()
            }
        }
    }

    // MARK: Withdrawal consent

    /// Whether the cart contains digital content, i.e. a line without shipping. Only then the
    /// right of withdrawal can expire with delivery, so only then the consent is needed.
    public var needsWithdrawalConsent: Bool {
        cart?.lines.contains { !$0.merchandise.requiresShipping } ?? false
    }

    /// Whether the cart carries the consent to immediate delivery.
    public var hasWithdrawalConsent: Bool {
        cart?.attributes.contains { $0.key == Self.withdrawalConsentKey && !$0.value.isEmpty } ?? false
    }

    /// The attribute value for consent given at `date`, as the web shop writes it.
    public nonisolated static func withdrawalConsentValue(at date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return "Ja (\(formatter.string(from: date)))"
    }

    /// Records (`given`) or withdraws the consent on the cart, keeping all other attributes.
    ///
    /// - Returns: Whether Shopify stored the change. On failure ``lastError`` explains why.
    @discardableResult
    public func setWithdrawalConsent(_ given: Bool, at date: Date = Date()) async -> Bool {
        await serialized { [self] in
            guard let cart else { return }
            var attributes = cart.attributes.filter { $0.key != Self.withdrawalConsentKey }
            if given {
                attributes.append(AttributeInput(key: Self.withdrawalConsentKey, value: Self.withdrawalConsentValue(at: date)))
            }
            let result = try await repository.updateAttributes(cartID: cart.id, attributes: attributes)
            apply(result)
        }
    }

    // MARK: Mutations

    /// Adds `quantity` of the variant. Creates the cart on the first add, with the attributes
    /// `app_platform=ios` and `app_version`.
    ///
    /// - Returns: Whether the line was added. On failure ``lastError`` explains why.
    @discardableResult
    public func add(variantID: ShopifyID, quantity: Int = 1) async -> Bool {
        let lines = [CartLineInput(merchandiseId: variantID, quantity: quantity)]
        return await serialized { [self] in
            try await mutateCart(
                existing: { cartID in try await self.repository.addLines(cartID: cartID, lines: lines) },
                recreate: { try await self.createCart(lines: lines) }
            )
        }
    }

    /// Sets the quantity of a line; zero or less removes it. Taps arriving while an update of
    /// the same line waits only change its target, so the latest intent wins.
    public func setQuantity(lineID: ShopifyID, quantity: Int) async {
        guard quantity > 0 else {
            await remove(lineID: lineID)
            return
        }
        let isWaiting = pendingQuantities[lineID] != nil
        pendingQuantities[lineID] = quantity
        guard !isWaiting else { return }
        _ = await serialized { [self] in
            guard let target = pendingQuantities.removeValue(forKey: lineID) else { return }
            guard let cartID = cart?.id, let current = line(for: lineID), current.quantity != target else { return }
            let result = try await repository.updateLines(cartID: cartID, lines: [CartLineUpdateInput(id: lineID, quantity: target)])
            apply(result)
        }
    }

    /// Removes a line. ``undoRemove()`` restores it until the next removal or checkout.
    public func remove(lineID: ShopifyID) async {
        pendingQuantities[lineID] = nil
        _ = await serialized { [self] in
            guard let cartID = cart?.id, let removed = line(for: lineID) else { return }
            let result = try await repository.removeLines(cartID: cartID, lineIDs: [lineID])
            lastRemovedLine = removed
            apply(result)
        }
    }

    /// Adds the last removed line again, with its quantity.
    ///
    /// - Returns: Whether the line was restored.
    @discardableResult
    public func undoRemove() async -> Bool {
        guard let removed = lastRemovedLine else { return false }
        lastRemovedLine = nil
        let restored = await add(variantID: removed.merchandise.id, quantity: removed.quantity)
        if !restored {
            lastRemovedLine = removed
        }
        return restored
    }

    /// Clears the undo state, e.g. when the undo banner disappears.
    public func discardUndo() {
        lastRemovedLine = nil
    }

    /// The outcome of ``applyDiscountCode(_:)``.
    public enum DiscountOutcome: Sendable, Hashable {
        /// Shopify applies the code to the cart.
        case applied
        /// Shopify accepted the code but it does not apply to this cart; ``lastWarnings`` may
        /// carry Shopify's explanation.
        case notApplicable
        /// The request failed; ``lastError`` explains why.
        case failed
    }

    /// Adds a discount code to the cart (codes already in the cart are kept).
    public func applyDiscountCode(_ code: String) async -> DiscountOutcome {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .notApplicable }
        let succeeded = await serialized { [self] in
            guard let cartID = cart?.id else { throw ShopifyError.notFound }
            var codes = cart?.discountCodes.map(\.code) ?? []
            if !codes.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
                codes.append(trimmed)
            }
            try await apply(repository.updateDiscountCodes(cartID: cartID, codes: codes))
        }
        guard succeeded else { return .failed }
        let applied = cart?.discountCodes.contains { $0.code.caseInsensitiveCompare(trimmed) == .orderedSame && $0.applicable }
        return applied == true ? .applied : .notApplicable
    }

    /// Removes a discount code from the cart.
    @discardableResult
    public func removeDiscountCode(_ code: String) async -> Bool {
        await serialized { [self] in
            guard let cart else { return }
            let codes = cart.discountCodes.map(\.code).filter { $0.caseInsensitiveCompare(code) != .orderedSame }
            try await apply(repository.updateDiscountCodes(cartID: cart.id, codes: codes))
        }
    }

    /// Moves the cart to another market country (buyer identity), so prices and taxes follow
    /// the market. Does nothing without a cart or when the country is unchanged.
    public func updateCountry(_ country: CountryCode) async {
        _ = await serialized { [self] in
            guard let cart, cart.buyerIdentity.countryCode != country else { return }
            try await apply(repository.updateBuyerIdentity(cartID: cart.id, countryCode: country))
        }
    }

    /// Puts the signed-in customer's access token on the cart, so Shopify prices it for them
    /// (automatic discounts for their customer segment show in the cart). Call it after a
    /// sign-in. Does nothing without a cart, without a signed-in customer or when the cart
    /// already carries a token; a failure keeps the cart as it is, checkout tries again.
    public func associateCustomer() async {
        _ = await enqueue { [self] in await attachCustomer() }
    }

    // MARK: Checkout

    /// A fresh checkout URL: waits for pending mutations and re-reads the cart.
    ///
    /// An expired or completed cart is never recreated here: its lines may belong to an order
    /// that was already placed, so recreating it could buy the same items twice. The store
    /// forgets such a cart instead (``cart`` becomes `nil`) and throws ``expiredCartError``.
    ///
    /// - Throws: ``UserFacingError``: ``expiredCartError`` when the cart expired or was
    ///   completed, ``UserFacingError/Kind/notFound`` when there is nothing to check out, or
    ///   the mapped failure when the cart cannot be read.
    public func checkoutURL() async throws -> URL {
        let result = await enqueue { [self] in try await freshCheckoutURL() }
        switch result {
        case let .success(url):
            return url
        case let .failure(error):
            logger.error("Checkout URL unavailable: \(Self.logDescription(error))")
            throw UserFacingError(error) ?? UserFacingError(kind: .unknown)
        }
    }

    /// The error of ``checkoutURL()`` for a cart that expired or was completed in the meantime:
    /// Shopify refuses it, so the customer has to add the items again ("Ihr Warenkorb ist
    /// abgelaufen. Bitte legen Sie die Artikel erneut in den Warenkorb.").
    public nonisolated static var expiredCartError: UserFacingError {
        UserFacingError(kind: .rejected(messages: [String(localized: "commerce.cart.expired", bundle: .module)]))
    }

    /// Forgets the cart after a completed checkout: the order exists, the cart must not be
    /// used again.
    public func clearAfterCheckout() {
        pendingQuantities.removeAll()
        forgetCart()
    }

    /// Takes the signed-out customer off the cart: a cart that carried their access token is
    /// replaced by a new cart with the same lines and discount codes, and Checkout Kit's cache
    /// is dropped. When the new cart cannot be created, the cart is forgotten instead, so the
    /// previous customer's checkout can never open again. A cart that never carried a token
    /// stays as it is.
    public func signOutCustomer() async {
        _ = await enqueue { [self] in
            guard let cartID = storedCartID, isSignedInCart(cartID) else {
                store.removeValue(forKey: Self.signedInCartIDKey)
                return
            }
            invalidatePreloadedCheckout()
            do {
                if let signedInCart = try await repository.cart(id: cartID), !signedInCart.lines.isEmpty {
                    try await replaceSignedInCart(signedInCart)
                } else {
                    forgetCart()
                }
            } catch {
                logger.notice("Replacing the signed-in cart failed (\(Self.logDescription(error))); it is forgotten")
                forgetCart()
            }
        }
    }

    // MARK: Private: checkout

    private func freshCheckoutURL() async throws -> URL {
        guard let cartID = storedCartID else {
            forgetCart()
            throw UserFacingError(kind: .notFound)
        }
        guard let fresh = try await repository.cart(id: cartID) else {
            logger.info("Cart expired or completed before checkout; it is forgotten, not recreated")
            forgetCart()
            throw Self.expiredCartError
        }
        cart = fresh
        guard !fresh.lines.isEmpty else {
            throw UserFacingError(kind: .notFound)
        }
        guard let token = await customerAccessToken?() else {
            guard isSignedInCart(cartID) else { return fresh.checkoutUrl }
            // The customer signed out, but the cart still carries their token (the app ended
            // before the cart was replaced): never open their checkout for someone else.
            invalidatePreloadedCheckout()
            return try await replaceSignedInCart(fresh).checkoutUrl
        }
        // Marked before the request: if it fails ambiguously, the token may be on the cart.
        if !isSignedInCart(cartID) {
            store.set(cartID.rawValue, forKey: Self.signedInCartIDKey)
            invalidatePreloadedCheckout()
        }
        do {
            let result = try await repository.updateBuyerIdentity(cartID: cartID, customerAccessToken: token)
            cart = result.cart
            lastWarnings = result.warnings
            return result.cart.checkoutUrl
        } catch {
            logger.notice("Signing the checkout in failed (\(Self.logDescription(error))); it opens as a guest checkout")
            return fresh.checkoutUrl
        }
    }

    /// Puts the signed-in customer's token on the current cart unless it carries one already.
    /// A refusal takes the mark off again, so the next refresh or checkout retries; after an
    /// ambiguous failure the mark stays, because the token may be on the cart.
    private func attachCustomer() async {
        guard let cartID = cart?.id ?? storedCartID, !isSignedInCart(cartID) else { return }
        guard let token = await customerAccessToken?() else { return }
        store.set(cartID.rawValue, forKey: Self.signedInCartIDKey)
        invalidatePreloadedCheckout()
        do {
            let result = try await repository.updateBuyerIdentity(cartID: cartID, customerAccessToken: token)
            cart = result.cart
            lastWarnings = result.warnings
        } catch {
            logger.notice("Signing the cart in failed (\(Self.logDescription(error))); it stays a guest cart for now")
            if !Self.isAmbiguous(error) {
                store.removeValue(forKey: Self.signedInCartIDKey)
            }
        }
    }

    /// Makes a new cart with the lines and discount codes of `signedInCart`, without its buyer
    /// identity, the current cart. A discount code that cannot be carried over is left out.
    @discardableResult
    private func replaceSignedInCart(_ signedInCart: Cart) async throws -> Cart {
        let lines = signedInCart.lines.map { CartLineInput(merchandiseId: $0.merchandise.id, quantity: $0.quantity) }
        let created = try await createCart(lines: lines)
        store.removeValue(forKey: Self.signedInCartIDKey)
        apply(created)
        let codes = signedInCart.discountCodes.map(\.code)
        guard !codes.isEmpty else { return created.cart }
        do {
            let discounted = try await repository.updateDiscountCodes(cartID: created.cart.id, codes: codes)
            apply(discounted)
            return discounted.cart
        } catch {
            logger.notice("Carrying the discount codes to the new cart failed: \(Self.logDescription(error))")
            return created.cart
        }
    }

    /// Whether the cart with `cartID` carries a customer access token.
    private func isSignedInCart(_ cartID: ShopifyID) -> Bool {
        store.string(forKey: Self.signedInCartIDKey) == cartID.rawValue
    }

    /// Stops a pending preload and lets the App drop the checkout Checkout Kit preloaded.
    private func invalidatePreloadedCheckout() {
        preloadTask?.cancel()
        preloadTask = nil
        checkoutInvalidator?()
    }

    // MARK: Private: mutations

    /// Runs a mutation on the existing cart, or `recreate` when there is no cart. When Shopify
    /// refuses the mutation because the cart no longer exists, the cart is recreated once.
    private func mutateCart(
        existing: (ShopifyID) async throws -> CartMutationResult,
        recreate: () async throws -> CartMutationResult
    ) async throws {
        guard let cartID = cart?.id ?? storedCartID else {
            try await apply(recreate())
            await attachCustomer()
            return
        }
        do {
            try await apply(existing(cartID))
        } catch let error as ShopifyError {
            guard case .userErrors = error, try await repository.cart(id: cartID) == nil else { throw error }
            logger.info("Cart expired; recreating it for the requested change")
            forgetCart()
            try await apply(recreate())
            await attachCustomer()
        }
    }

    private func createCart(lines: [CartLineInput]) async throws -> CartMutationResult {
        try await repository.createCart(
            lines: lines,
            attributes: [
                AttributeInput(key: Self.platformAttributeKey, value: Self.platformAttributeValue),
                AttributeInput(key: Self.versionAttributeKey, value: appVersion),
            ]
        )
    }

    private func apply(_ result: CartMutationResult) {
        cart = result.cart
        lastWarnings = result.warnings
        lastError = nil
        store.set(result.cart.id.rawValue, forKey: Self.cartIDKey)
        schedulePreload()
    }

    private func forgetCart() {
        cart = nil
        lastWarnings = []
        lastRemovedLine = nil
        store.removeValue(forKey: Self.cartIDKey)
        store.removeValue(forKey: Self.signedInCartIDKey)
        preloadTask?.cancel()
        preloadTask = nil
    }

    // MARK: Private: queue

    /// Runs `operation` after every earlier operation finished.
    ///
    /// The operation runs in its own task, so a caller that goes away (a cancelled view task)
    /// never abandons a mutation halfway, and ``isUpdating`` stays `true` until the queue is
    /// empty.
    private func enqueue<Value: Sendable>(
        _ operation: @escaping @MainActor () async throws -> Value
    ) async -> Result<Value, any Error> {
        pendingOperationCount += 1
        isUpdating = true
        let previous = queueTail
        let task = Task { @MainActor () -> Result<Value, any Error> in
            await previous?.value
            do {
                return try await .success(operation())
            } catch {
                return .failure(error)
            }
        }
        queueTail = Task { _ = await task.value }
        let result = await task.value
        pendingOperationCount -= 1
        isUpdating = pendingOperationCount > 0
        return result
    }

    /// Runs a mutation through the queue and records its failure in ``lastError``.
    ///
    /// - Returns: Whether the operation succeeded.
    private func serialized(_ operation: @escaping @MainActor () async throws -> Void) async -> Bool {
        let result = await enqueue { [self] in
            do {
                try await operation()
                return true
            } catch {
                await handle(error)
                return false
            }
        }
        if case let .success(succeeded) = result {
            return succeeded
        }
        return false
    }

    /// Records a failure. After an ambiguous failure the cart is re-read, because the mutation
    /// may or may not have been executed; it is never repeated.
    private func handle(_ error: any Error) async {
        guard let failure = UserFacingError(error) else { return }
        logger.error("Cart operation failed: \(Self.logDescription(error))")
        lastError = failure
        guard Self.isAmbiguous(error), let cartID = storedCartID else { return }
        do {
            if let fresh = try await repository.cart(id: cartID) {
                cart = fresh
            } else {
                forgetCart()
            }
        } catch {
            logger.error("Cart re-read after a failed change failed: \(Self.logDescription(error))")
        }
    }

    /// Whether Shopify may have executed a mutation that failed with `error`.
    static func isAmbiguous(_ error: any Error) -> Bool {
        guard let error = error as? ShopifyError else { return false }
        switch error {
        case let .network(networkError):
            return networkError != .offline && networkError != .cancelled
        case let .http(statusCode):
            return statusCode >= 500
        case let .graphQL(errors):
            return errors.contains { $0.code == GraphQLErrorDetail.Code.internalServerError }
        case .accessDenied, .throttled, .userErrors, .notFound, .decoding:
            return false
        }
    }

    private static func logDescription(_ error: any Error) -> String {
        switch error {
        case let error as ShopifyError:
            error.logDescription
        case let error as UserFacingError:
            "userFacing(\(error.logName))"
        default:
            String(describing: type(of: error))
        }
    }

    // MARK: Private: preload

    private func schedulePreload() {
        preloadTask?.cancel()
        // A signed-in cart's checkout URL expires; ``checkoutURL()`` signs it in again instead.
        guard checkoutPreloader != nil, let cart, !cart.lines.isEmpty, !isSignedInCart(cart.id) else {
            preloadTask = nil
            return
        }
        let url = cart.checkoutUrl
        let delay = preloadDelay
        preloadTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.checkoutPreloader?(url)
        }
    }
}
