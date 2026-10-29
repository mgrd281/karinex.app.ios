import CommerceUI
import Foundation
import Observation
import ShopifyKit

// MARK: - CartScreenContent

/// What the cart screen shows once the cart is known: the empty state or the cart's lines.
enum CartScreenContent: Sendable, Hashable {
    /// No cart, or a cart without lines: "Ihr Warenkorb ist leer".
    case empty
    /// A cart with at least one line.
    case cart(Cart)
}

// MARK: - CartDiscountFeedback

/// The message below the discount code field after the customer applied a code.
enum CartDiscountFeedback: Sendable, Hashable {
    /// Shopify applies the code.
    case applied(code: String)
    /// Shopify knows the cart but the code does not apply; `message` is Shopify's own
    /// explanation when it sent one.
    case notApplicable(message: String?)
    /// The request failed.
    case failed(UserFacingError)
}

// MARK: - CartViewModel

/// The logic of the Warenkorb screen on top of the shared ``CartStore``.
///
/// - The screen state follows the store: a skeleton while a stored cart loads for the first
///   time, the error when that load failed, the empty state without lines, otherwise the cart.
/// - Quantities stay within ``quantityRange`` (1 to 10); a line leaves the cart through
///   ``requestRemoval(of:after:)``: its row shows "Produkt wird entfernt" with "Abbrechen"
///   until the delay has passed, as in the About You app.
/// - The discount code field applies and removes codes and shows Shopify's message when a code
///   does not apply.
/// - The cross-sell row shows Shopify's `COMPLEMENTARY` recommendations for the first line's
///   product, without products that are already in the cart.
@MainActor
@Observable
final class CartViewModel {
    /// The quantities the stepper allows.
    static let quantityRange = 1...10
    /// The maximum number of products in the cross-sell row.
    static let crossSellLimit = 8

    /// The text of the discount code field.
    var discountCode = ""
    /// The feedback of the last discount action, `nil` when there is none.
    private(set) var discountFeedback: CartDiscountFeedback?
    /// Whether a discount code is being applied.
    private(set) var isApplyingDiscount = false
    /// The cross-sell row.
    private(set) var crossSell: LoadState<[ProductSummary]> = .idle

    /// The shared cart.
    let cartStore: CartStore

    @ObservationIgnored private let catalog: any CatalogRepository
    /// The product the cross-sell row was loaded for.
    @ObservationIgnored private var crossSellProductID: ShopifyID?

    /// Creates the view model.
    ///
    /// - Parameters:
    ///   - cartStore: The app's cart.
    ///   - catalog: Loads the cross-sell recommendations.
    init(cartStore: CartStore, catalog: any CatalogRepository) {
        self.cartStore = cartStore
        self.catalog = catalog
    }

    // MARK: Screen state

    /// The state of the screen, derived from the cart store.
    var state: LoadState<CartScreenContent> {
        if let cart = cartStore.cart {
            return .loaded(cart.lines.isEmpty ? .empty : .cart(cart))
        }
        guard cartStore.storedCartID != nil else {
            return .loaded(.empty)
        }
        // A stored cart that has not been read yet: it is loading, unless the read failed.
        if !cartStore.isUpdating, let error = cartStore.lastError {
            return .failed(error)
        }
        return .loading
    }

    /// The cart with its lines, or `nil` when the cart is empty or unknown.
    var cart: Cart? {
        guard let cart = cartStore.cart, !cart.lines.isEmpty else { return nil }
        return cart
    }

    /// Reloads the cart from Shopify, e.g. when the screen appears or on pull to refresh.
    func refresh() async {
        await cartStore.refresh()
    }

    // MARK: Quantities

    /// The quantity shown for `line`, including taps that are still on their way to Shopify.
    func quantity(of line: CartLine) -> Int {
        let displayed = cartStore.displayedQuantity(for: line.id)
        return displayed > 0 ? displayed : line.quantity
    }

    /// Whether "+" is enabled for `line`.
    func canIncrease(_ line: CartLine) -> Bool {
        quantity(of: line) < Self.quantityRange.upperBound
    }

    /// Whether "-" is enabled for `line`. The last unit is removed with the remove button.
    func canDecrease(_ line: CartLine) -> Bool {
        quantity(of: line) > Self.quantityRange.lowerBound
    }

    /// Adds one unit to `line`, up to the maximum.
    func increase(_ line: CartLine) async {
        await setQuantity(quantity(of: line) + 1, of: line)
    }

    /// Removes one unit from `line`, down to one.
    func decrease(_ line: CartLine) async {
        await setQuantity(quantity(of: line) - 1, of: line)
    }

    /// Sets the quantity of `line`, clamped to ``quantityRange``.
    func setQuantity(_ quantity: Int, of line: CartLine) async {
        let clamped = Self.clampedQuantity(quantity)
        guard clamped != self.quantity(of: line) else { return }
        await cartStore.setQuantity(lineID: line.id, quantity: clamped)
    }

    /// `quantity` limited to ``quantityRange``.
    static func clampedQuantity(_ quantity: Int) -> Int {
        min(max(quantity, quantityRange.lowerBound), quantityRange.upperBound)
    }

    // MARK: Removal

    /// How long a line shows "Produkt wird entfernt" before it leaves the cart.
    static let removalDelay: TimeInterval = 3
    /// The same with VoiceOver, so there is time to reach "Abbrechen".
    static let accessibleRemovalDelay: TimeInterval = 10

    /// The lines on their way out of the cart.
    private(set) var removingLineIDs: Set<ShopifyID> = []
    @ObservationIgnored private var removalTasks: [ShopifyID: Task<Void, Never>] = [:]

    /// Whether `line` shows "Produkt wird entfernt".
    func isRemoving(_ line: CartLine) -> Bool {
        removingLineIDs.contains(line.id)
    }

    /// Starts removing `line`: after `delay` seconds it leaves the cart, unless
    /// ``cancelRemoval(of:)`` keeps it. A second request for the same line changes nothing.
    func requestRemoval(of line: CartLine, after delay: TimeInterval) {
        guard !removingLineIDs.contains(line.id) else { return }
        removingLineIDs.insert(line.id)
        removalTasks[line.id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await self?.remove(line)
        }
    }

    /// Keeps `line` in the cart ("Abbrechen").
    func cancelRemoval(of line: CartLine) {
        removalTasks.removeValue(forKey: line.id)?.cancel()
        removingLineIDs.remove(line.id)
    }

    /// The running removal of `line`, `nil` when there is none.
    func removal(of line: CartLine) -> Task<Void, Never>? {
        removalTasks[line.id]
    }

    /// Removes `line` now. The row already offered "Abbrechen", so no undo is kept. When the
    /// request fails, the line stays and the error banner explains why.
    func remove(_ line: CartLine) async {
        await cartStore.remove(lineID: line.id)
        cartStore.discardUndo()
        removalTasks[line.id] = nil
        removingLineIDs.remove(line.id)
    }

    // MARK: Discount codes

    /// The trimmed discount code field.
    var trimmedDiscountCode: String {
        discountCode.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether "Anwenden" is enabled.
    var canApplyDiscount: Bool {
        !trimmedDiscountCode.isEmpty && !isApplyingDiscount && cart != nil
    }

    /// Applies the code in the field. On success the field is cleared.
    func applyDiscount() async {
        let code = trimmedDiscountCode
        guard !code.isEmpty, !isApplyingDiscount else { return }
        isApplyingDiscount = true
        let outcome = await cartStore.applyDiscountCode(code)
        isApplyingDiscount = false
        switch outcome {
        case .applied:
            discountCode = ""
            discountFeedback = .applied(code: code)
        case .notApplicable:
            discountFeedback = .notApplicable(message: Self.discountMessage(in: cartStore.lastWarnings))
        case .failed:
            discountFeedback = .failed(cartStore.lastError ?? UserFacingError(kind: .unknown))
            cartStore.lastError = nil
        }
    }

    /// Removes `code` from the cart.
    func removeDiscount(_ code: String) async {
        discountFeedback = nil
        await cartStore.removeDiscountCode(code)
    }

    /// Hides the discount feedback, e.g. when the customer edits the field.
    func clearDiscountFeedback() {
        discountFeedback = nil
    }

    /// Shopify's message about a discount code, if one of `warnings` is about discounts.
    static func discountMessage(in warnings: [CartWarning]) -> String? {
        warnings
            .first { $0.isDiscountWarning }
            .map { $0.message.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 }
    }

    // MARK: Withdrawal consent

    /// Whether the checkout bar shows the consent checkbox: the cart contains digital content.
    var needsWithdrawalConsent: Bool {
        cartStore.needsWithdrawalConsent
    }

    /// Whether the consent is ticked: stored on the cart, or on its way there.
    var hasWithdrawalConsent: Bool {
        pendingConsent ?? cartStore.hasWithdrawalConsent
    }

    /// Whether "Zur Kasse" shows the hint below the checkbox because it was tapped without
    /// the consent.
    private(set) var showsConsentHint = false
    /// The consent the customer just ticked or unticked, until Shopify stored it.
    private(set) var pendingConsent: Bool?

    /// Ticks or unticks the consent and stores it on the cart, as the web shop does.
    func toggleWithdrawalConsent() async {
        let target = !hasWithdrawalConsent
        pendingConsent = target
        if target { showsConsentHint = false }
        await cartStore.setWithdrawalConsent(target)
        pendingConsent = nil
    }

    /// "Zur Kasse": opens the checkout only with the consent when the cart needs it, the same
    /// rule as the web shop's cart (AGB § 10 Abs. 3a). Without it the hint appears instead.
    ///
    /// - Returns: Whether the checkout may open.
    func requestCheckout() -> Bool {
        guard needsWithdrawalConsent else { return true }
        guard pendingConsent == nil, cartStore.hasWithdrawalConsent else {
            showsConsentHint = true
            return false
        }
        showsConsentHint = false
        return true
    }

    // MARK: Warnings and errors

    /// Shopify's warnings of the last change that are not about discount codes (those appear
    /// below the discount field).
    var generalWarnings: [String] {
        cartStore.lastWarnings
            .filter { !$0.isDiscountWarning }
            .map { $0.message.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// The failure of the last cart change while the cart is shown, for the error banner.
    var actionError: UserFacingError? {
        cart == nil ? nil : cartStore.lastError
    }

    /// Hides the error banner.
    func dismissError() {
        cartStore.lastError = nil
    }

    // MARK: Cross-sell

    /// Loads the cross-sell row for the first line's product, unless it is already loaded for
    /// that product. Without lines the row is empty.
    func loadCrossSell() async {
        guard let cart, let first = cart.lines.first else {
            crossSellProductID = nil
            crossSell = .empty
            return
        }
        let productID = first.merchandise.product.id
        if crossSellProductID == productID, crossSell.value != nil {
            crossSell = LoadState(collection: Self.crossSellProducts(crossSell.value ?? [], excluding: cart))
            return
        }
        crossSellProductID = productID
        crossSell = .loading
        do {
            let products = try await catalog.recommendations(productID: productID, intent: .complementary)
            guard crossSellProductID == productID else { return }
            crossSell = LoadState(collection: Self.crossSellProducts(products, excluding: cart))
        } catch {
            guard crossSellProductID == productID, let failure = UserFacingError(error) else { return }
            crossSell = .failed(failure)
        }
    }

    /// Forces the cross-sell row to load again (retry after a failure).
    func reloadCrossSell() async {
        crossSellProductID = nil
        await loadCrossSell()
    }

    /// The key that changes whenever the cross-sell row has to be reconsidered: the products
    /// in the cart, in order.
    var crossSellKey: [ShopifyID] {
        cart?.lines.map(\.merchandise.product.id) ?? []
    }

    /// `products` without the products already in `cart` and without repeats, at most
    /// ``crossSellLimit``.
    static func crossSellProducts(_ products: [ProductSummary], excluding cart: Cart) -> [ProductSummary] {
        var seen = Set(cart.lines.map(\.merchandise.product.id))
        return Array(products.filter { seen.insert($0.id).inserted }.prefix(crossSellLimit))
    }
}
