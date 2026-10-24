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
/// - After every change the ``checkoutPreloader`` is called with the fresh checkout URL,
///   debounced by ``preloadDelay``, so Checkout Kit can preload (CommerceUI does not import it).
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
                schedulePreload()
            } else {
                logger.info("Stored cart is no longer available; it will be recreated with the next add")
                forgetCart()
            }
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

    // MARK: Checkout

    /// A fresh checkout URL: waits for pending mutations, re-reads the cart and, when it
    /// expired, recreates it with the last known lines.
    ///
    /// - Throws: ``UserFacingError`` when the cart cannot be read or recreated, or when there
    ///   is nothing to check out (``UserFacingError/Kind/notFound``).
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

    /// Forgets the cart after a completed checkout: the order exists, the cart must not be
    /// used again.
    public func clearAfterCheckout() {
        pendingQuantities.removeAll()
        forgetCart()
    }

    // MARK: Private: checkout

    private func freshCheckoutURL() async throws -> URL {
        let knownLines = cart?.lines ?? []
        if let cartID = storedCartID, let fresh = try await repository.cart(id: cartID) {
            if fresh.lines.isEmpty {
                cart = fresh
                throw UserFacingError(kind: .notFound)
            }
            cart = fresh
            return fresh.checkoutUrl
        }
        guard !knownLines.isEmpty else {
            forgetCart()
            throw UserFacingError(kind: .notFound)
        }
        logger.info("Cart expired before checkout; recreating it with the known lines")
        let inputs = knownLines.map { CartLineInput(merchandiseId: $0.merchandise.id, quantity: $0.quantity) }
        let result = try await createCart(lines: inputs)
        apply(result)
        return result.cart.checkoutUrl
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
            return
        }
        do {
            try await apply(existing(cartID))
        } catch let error as ShopifyError {
            guard case .userErrors = error, try await repository.cart(id: cartID) == nil else { throw error }
            logger.info("Cart expired; recreating it for the requested change")
            forgetCart()
            try await apply(recreate())
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
        guard checkoutPreloader != nil, let cart, !cart.lines.isEmpty else {
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
