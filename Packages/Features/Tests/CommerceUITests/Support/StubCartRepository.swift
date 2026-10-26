import Foundation
import ShopifyKit

// MARK: - StubCartRepository

/// An in-memory Shopify cart service for `CartStore` tests.
///
/// It keeps carts like Shopify does: lines merge per variant, every mutation returns the full
/// cart, unknown or expired carts answer `cart(id:)` with `nil` and refuse mutations with a
/// `userErrors` payload. Every call is recorded. Failures can be queued per operation, and
/// `updateLines` can be held at a gate to observe what happens while a mutation is in flight.
actor StubCartRepository: CartRepository {
    /// One recorded call.
    enum Call: Equatable, Sendable {
        case cart
        case create(lines: [CartLineInput], attributes: [AttributeInput])
        case add(lines: [CartLineInput])
        case update(lines: [CartLineUpdateInput])
        case remove(lineIDs: [ShopifyID])
        case discountCodes([String])
        case buyerIdentity(CountryCode)
        case customerAccessToken(String)
        case attributes([AttributeInput])
    }

    /// The operations failures can be queued for.
    enum Operation: Hashable, Sendable {
        case cart, create, add, update, remove, discountCodes, buyerIdentity, customerAccessToken, attributes
    }

    /// The discount code the stub applies; every other code is not applicable.
    static let validDiscountCode = "WILLKOMMEN"
    /// The unit price of every variant.
    static let unitPrice = MoneyV2(amount: Decimal(string: "12.90") ?? 0, currencyCode: .eur)

    private struct StoredLine {
        let id: ShopifyID
        let variantID: ShopifyID
        var quantity: Int
    }

    private struct StoredCart {
        var lines: [StoredLine] = []
        var codes: [String] = []
        var country: CountryCode = .de
        var attributes: [AttributeInput] = []
        var customerAccessToken: String?
    }

    private(set) var calls: [Call] = []
    private var carts: [ShopifyID: StoredCart] = [:]
    private var nextCartNumber = 1
    private var nextLineNumber = 1
    private var failures: [Operation: [any Error]] = [:]
    private var isHoldingUpdates = false
    private var heldUpdates: [CheckedContinuation<Void, Never>] = []

    // MARK: Test control

    /// Makes the next call of `operation` throw `error`.
    func fail(_ operation: Operation, with error: any Error) {
        failures[operation, default: []].append(error)
    }

    /// Lets the cart expire: reads return `nil`, mutations are refused.
    func expire(_ cartID: ShopifyID) {
        carts[cartID] = nil
    }

    /// Holds every `updateLines` call until ``releaseUpdates()``.
    func holdUpdates() {
        isHoldingUpdates = true
    }

    /// Releases the held `updateLines` calls.
    func releaseUpdates() {
        isHoldingUpdates = false
        let held = heldUpdates
        heldUpdates.removeAll()
        held.forEach { $0.resume() }
    }

    /// The number of `updateLines` calls waiting at the gate.
    var heldUpdateCount: Int {
        heldUpdates.count
    }

    /// The `updateLines` calls received so far.
    var updateCalls: [[CartLineUpdateInput]] {
        calls.compactMap { call in
            if case let .update(lines) = call { return lines }
            return nil
        }
    }

    /// Whether a call of `kind` was recorded.
    func count(of kind: Operation) -> Int {
        calls.filter { Self.operation(of: $0) == kind }.count
    }

    // MARK: CartRepository

    func cart(id: ShopifyID) async throws -> Cart? {
        calls.append(.cart)
        try throwQueuedFailure(.cart)
        return carts[id].map { snapshot(id: id, $0) }
    }

    func createCart(lines: [CartLineInput], attributes: [AttributeInput]) async throws -> CartMutationResult {
        calls.append(.create(lines: lines, attributes: attributes))
        try throwQueuedFailure(.create)
        let id = ShopifyID("gid://shopify/Cart/stub-\(nextCartNumber)")
        nextCartNumber += 1
        carts[id] = StoredCart(attributes: attributes)
        try merge(lines, into: id)
        return try result(for: id)
    }

    func addLines(cartID: ShopifyID, lines: [CartLineInput]) async throws -> CartMutationResult {
        calls.append(.add(lines: lines))
        try throwQueuedFailure(.add)
        try requireCart(cartID)
        try merge(lines, into: cartID)
        return try result(for: cartID)
    }

    func updateLines(cartID: ShopifyID, lines: [CartLineUpdateInput]) async throws -> CartMutationResult {
        calls.append(.update(lines: lines))
        if isHoldingUpdates {
            await withCheckedContinuation { heldUpdates.append($0) }
        }
        try throwQueuedFailure(.update)
        try requireCart(cartID)
        for update in lines {
            guard let index = carts[cartID]?.lines.firstIndex(where: { $0.id == update.id }) else { continue }
            carts[cartID]?.lines[index].quantity = update.quantity
        }
        return try result(for: cartID)
    }

    func removeLines(cartID: ShopifyID, lineIDs: [ShopifyID]) async throws -> CartMutationResult {
        calls.append(.remove(lineIDs: lineIDs))
        try throwQueuedFailure(.remove)
        try requireCart(cartID)
        carts[cartID]?.lines.removeAll { lineIDs.contains($0.id) }
        return try result(for: cartID)
    }

    func updateDiscountCodes(cartID: ShopifyID, codes: [String]) async throws -> CartMutationResult {
        calls.append(.discountCodes(codes))
        try throwQueuedFailure(.discountCodes)
        try requireCart(cartID)
        carts[cartID]?.codes = codes
        let warnings = codes
            .filter { $0 != Self.validDiscountCode }
            .map { CartWarning(
                code: "DISCOUNT_CODE_NOT_HONOURED",
                message: "Der Rabattcode \($0) ist nicht gültig.",
                target: cartID.rawValue
            ) }
        return try CartMutationResult(cart: result(for: cartID).cart, warnings: warnings)
    }

    func updateBuyerIdentity(cartID: ShopifyID, countryCode: CountryCode) async throws -> CartMutationResult {
        calls.append(.buyerIdentity(countryCode))
        try throwQueuedFailure(.buyerIdentity)
        try requireCart(cartID)
        carts[cartID]?.country = countryCode
        return try result(for: cartID)
    }

    func updateBuyerIdentity(cartID: ShopifyID, customerAccessToken: String) async throws -> CartMutationResult {
        calls.append(.customerAccessToken(customerAccessToken))
        try throwQueuedFailure(.customerAccessToken)
        try requireCart(cartID)
        carts[cartID]?.customerAccessToken = customerAccessToken
        return try result(for: cartID)
    }

    /// The customer access token on the cart with `cartID`, if any.
    func customerAccessToken(of cartID: ShopifyID) -> String? {
        carts[cartID]?.customerAccessToken
    }

    func updateAttributes(cartID: ShopifyID, attributes: [AttributeInput]) async throws -> CartMutationResult {
        calls.append(.attributes(attributes))
        try throwQueuedFailure(.attributes)
        try requireCart(cartID)
        carts[cartID]?.attributes = attributes
        return try result(for: cartID)
    }

    // MARK: Private

    private static func operation(of call: Call) -> Operation {
        switch call {
        case .cart: .cart
        case .create: .create
        case .add: .add
        case .update: .update
        case .remove: .remove
        case .discountCodes: .discountCodes
        case .buyerIdentity: .buyerIdentity
        case .customerAccessToken: .customerAccessToken
        case .attributes: .attributes
        }
    }

    private func throwQueuedFailure(_ operation: Operation) throws {
        guard var queued = failures[operation], !queued.isEmpty else { return }
        let error = queued.removeFirst()
        failures[operation] = queued
        throw error
    }

    private func requireCart(_ cartID: ShopifyID) throws {
        guard carts[cartID] != nil else {
            throw ShopifyError.userErrors([
                UserError(field: ["cartId"], message: "Der angegebene Warenkorb existiert nicht.", code: .invalid),
            ])
        }
    }

    private func merge(_ inputs: [CartLineInput], into cartID: ShopifyID) throws {
        for input in inputs {
            if let index = carts[cartID]?.lines.firstIndex(where: { $0.variantID == input.merchandiseId }) {
                carts[cartID]?.lines[index].quantity += input.quantity
            } else {
                let line = StoredLine(
                    id: ShopifyID("gid://shopify/CartLine/stub-\(nextLineNumber)"),
                    variantID: input.merchandiseId,
                    quantity: input.quantity
                )
                nextLineNumber += 1
                carts[cartID]?.lines.append(line)
            }
        }
    }

    private func result(for cartID: ShopifyID) throws -> CartMutationResult {
        guard let stored = carts[cartID] else { throw ShopifyError.notFound }
        return CartMutationResult(cart: snapshot(id: cartID, stored), warnings: [])
    }

    private func snapshot(id: ShopifyID, _ stored: StoredCart) -> Cart {
        CartFixtures.cart(
            id: id,
            lines: stored.lines.map { (id: $0.id, variantID: $0.variantID, quantity: $0.quantity) },
            discountCodes: stored.codes.map { CartDiscountCode(code: $0, applicable: $0 == Self.validDiscountCode) },
            country: stored.country,
            attributes: stored.attributes
        )
    }
}
