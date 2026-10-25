@testable import CartFeature
import CommerceUI
import Core
import Foundation
import ShopifyKit
import Testing

@Suite("Cart strings")
struct CartStringTests {
    @Test("The German notice states when the right of withdrawal for digital content expires")
    func germanDigitalContentNotice() throws {
        let german = try LocalizedStrings(language: "de", in: CartResources.bundle)

        let notice = german("cart.notice.digital")
        #expect(notice.contains("digitalen Inhalten"))
        #expect(notice.contains("Widerrufsrecht"))
        #expect(notice.contains("sobald die Lieferung mit Ihrer ausdrücklichen Zustimmung beginnt"))
        #expect(notice.contains("§ 356 Abs. 5 BGB"))
    }

    @Test("The English notice describes the rule without citing German law")
    func englishDigitalContentNotice() throws {
        let english = try LocalizedStrings(language: "en", in: CartResources.bundle)

        let notice = english("cart.notice.digital")
        #expect(notice.contains("right of withdrawal"))
        #expect(notice.contains("express consent"))
        #expect(!notice.contains("BGB"))
    }

    @Test(
        "Outside German the notice never cites German law (docs/LOCALIZATION.md rule 6)",
        arguments: appLanguages.filter { $0 != "de" }
    )
    func noticeCitesNoGermanLaw(language: String) throws {
        let strings = try LocalizedStrings(language: language, in: CartResources.bundle)

        let notice = strings("cart.notice.digital")
        #expect(!notice.isEmpty)
        #expect(!notice.contains("BGB"), "\(language): \(notice)")
        #expect(!notice.contains("§"), "\(language): \(notice)")
    }

    @Test("The empty cart state reads as in the brand copy")
    func emptyState() throws {
        let german = try LocalizedStrings(language: "de", in: CartResources.bundle)

        #expect(german("cart.empty.title") == "Ihr Warenkorb ist leer")
        #expect(german("cart.empty.action") == "Zum Sortiment")
    }

    @Test("Every cart text resolves without dashes", arguments: appLanguages)
    func allTexts(language: String) throws {
        let strings = try LocalizedStrings(language: language, in: CartResources.bundle)
        let keys = [
            "cart.title",
            "cart.empty.title",
            "cart.empty.message",
            "cart.empty.action",
            "cart.payment.title",
            "cart.notice.title",
            "cart.notice.digital",
        ]

        for key in keys {
            let text = strings(key)
            #expect(text != key, "\(key) has no \(language) value")
            #expect(!containsForbiddenDash(text), "Dash in \(key)")
        }
    }
}

// MARK: - Cart screen logic

@MainActor
@Suite("Cart view model")
struct CartViewModelTests {
    private let repository = CartFeatureStubRepository()
    private let preferences = InMemoryKeyValueStore()

    private func makeModel(catalog: CartFeatureStubCatalog = CartFeatureStubCatalog()) -> CartViewModel {
        let store = CartStore(repository: repository, store: preferences, appVersion: "1.0.0", preloadDelay: .milliseconds(1))
        return CartViewModel(cartStore: store, catalog: catalog)
    }

    private func firstLine(_ model: CartViewModel) throws -> CartLine {
        try #require(model.cart?.lines.first)
    }

    @Test("Without a cart the screen shows the empty state, with lines the cart")
    func screenState() async {
        let model = makeModel()
        #expect(model.state == .loaded(.empty))
        #expect(model.cart == nil)

        await model.cartStore.add(variantID: CartTestFixtures.variant("windows-11-pro"))

        guard case let .loaded(.cart(cart)) = model.state else {
            Issue.record("Expected the cart, got \(model.state)")
            return
        }
        #expect(cart.lines.count == 1)
    }

    @Test("A stored cart that has not been read yet shows the skeleton")
    func storedCartLoads() {
        preferences.set("gid://shopify/Cart/unread", forKey: CartStore.cartIDKey)
        let model = makeModel()

        #expect(model.state.isLoading)
    }

    @Test("A cart whose lines were all removed shows the empty state")
    func emptiedCart() async throws {
        let model = makeModel()
        await model.cartStore.add(variantID: CartTestFixtures.variant("windows-11-pro"))

        try await model.remove(firstLine(model))

        #expect(model.state == .loaded(.empty))
        #expect(model.removedLine?.merchandise.id == CartTestFixtures.variant("windows-11-pro"))
    }

    @Test("Quantities stay between 1 and 10")
    func quantityRange() async throws {
        let model = makeModel()
        await model.cartStore.add(variantID: CartTestFixtures.variant("office-2024"))
        let line = try firstLine(model)

        #expect(!model.canDecrease(line))
        #expect(model.canIncrease(line))

        await model.decrease(line)
        #expect(try firstLine(model).quantity == 1)

        try await model.setQuantity(15, of: firstLine(model))
        let atMaximum = try firstLine(model)
        #expect(atMaximum.quantity == 10)
        #expect(!model.canIncrease(atMaximum))
        #expect(model.canDecrease(atMaximum))

        await model.increase(atMaximum)
        #expect(try firstLine(model).quantity == 10)

        await model.decrease(atMaximum)
        #expect(try firstLine(model).quantity == 9)
    }

    @Test("Clamping keeps every quantity inside the stepper range")
    func clamping() {
        #expect(CartViewModel.clampedQuantity(-3) == 1)
        #expect(CartViewModel.clampedQuantity(0) == 1)
        #expect(CartViewModel.clampedQuantity(4) == 4)
        #expect(CartViewModel.clampedQuantity(11) == 10)
    }

    @Test("Remove offers undo, undo restores the line with its quantity")
    func removeAndUndo() async throws {
        let model = makeModel()
        await model.cartStore.add(variantID: CartTestFixtures.variant("office-2024"), quantity: 3)
        await model.cartStore.add(variantID: CartTestFixtures.variant("windows-11-pro"))

        try await model.remove(firstLine(model))
        #expect(model.removedLine?.quantity == 3)
        #expect(model.cart?.lines.count == 1)

        await model.undoRemove()

        #expect(model.removedLine == nil)
        let restored = model.cart?.lines.first { $0.merchandise.id == CartTestFixtures.variant("office-2024") }
        #expect(restored?.quantity == 3)
    }

    @Test("Discarding the undo bar keeps the line removed")
    func discardUndo() async throws {
        let model = makeModel()
        await model.cartStore.add(variantID: CartTestFixtures.variant("office-2024"))
        try await model.remove(firstLine(model))

        model.discardUndo()

        #expect(model.removedLine == nil)
        #expect(model.cart == nil)
    }

    @Test("An applied discount code clears the field and confirms the code")
    func discountApplied() async {
        let model = makeModel()
        await model.cartStore.add(variantID: CartTestFixtures.variant("office-2024"))
        model.discountCode = "  \(CartFeatureStubRepository.validDiscountCode) "
        #expect(model.canApplyDiscount)

        await model.applyDiscount()

        #expect(model.discountFeedback == .applied(code: CartFeatureStubRepository.validDiscountCode))
        #expect(model.discountCode.isEmpty)
        #expect(model.cart?.discountCodes == [CartDiscountCode(code: CartFeatureStubRepository.validDiscountCode, applicable: true)])
        #expect(model.cart?.discountTotal != nil)

        await model.removeDiscount(CartFeatureStubRepository.validDiscountCode)
        #expect(model.cart?.discountCodes.isEmpty == true)
        #expect(model.discountFeedback == nil)
    }

    @Test("A code that does not apply shows Shopify's own message")
    func discountNotApplicable() async {
        let model = makeModel()
        await model.cartStore.add(variantID: CartTestFixtures.variant("office-2024"))
        model.discountCode = "FALSCH"

        await model.applyDiscount()

        #expect(model.discountFeedback == .notApplicable(message: CartFeatureStubRepository.discountWarning))
        #expect(model.discountCode == "FALSCH")
        #expect(model.generalWarnings.isEmpty, "Discount warnings belong below the field, not in the general banner")
    }

    @Test("A failed discount request explains why and leaves no banner behind")
    func discountFailed() async {
        let model = makeModel()
        await model.cartStore.add(variantID: CartTestFixtures.variant("office-2024"))
        await repository.failNextMutation(with: ShopifyError.network(.offline))
        model.discountCode = "WILLKOMMEN"

        await model.applyDiscount()

        #expect(model.discountFeedback == .failed(UserFacingError(kind: .offline)))
        #expect(model.actionError == nil)
    }

    @Test("Without a cart or a code nothing can be applied")
    func discountNeedsCartAndCode() async {
        let model = makeModel()
        model.discountCode = "WILLKOMMEN"
        #expect(!model.canApplyDiscount)

        await model.cartStore.add(variantID: CartTestFixtures.variant("office-2024"))
        model.discountCode = "   "
        #expect(!model.canApplyDiscount)
    }

    @Test("Discount messages come only from discount warnings")
    func discountMessage() {
        let warnings = [
            CartWarning(code: "MERCHANDISE_NOT_ENOUGH_STOCK", message: "Nicht genug Bestand.", target: "line"),
            CartWarning(code: "DISCOUNT_NOT_FOUND", message: "  Code unbekannt.  ", target: "cart"),
        ]
        #expect(CartViewModel.discountMessage(in: warnings) == "Code unbekannt.")
        #expect(CartViewModel.discountMessage(in: [warnings[0]]) == nil)
        #expect(CartViewModel.discountMessage(in: [CartWarning(code: "DISCOUNT_X", message: " ", target: "")]) == nil)
    }

    @Test("Other warnings of Shopify are shown in the general banner")
    func generalWarnings() async {
        let model = makeModel()
        await repository.addWarnings([CartWarning(code: "MERCHANDISE_NOT_ENOUGH_STOCK", message: "Nicht genug Bestand.", target: "line")])

        await model.cartStore.add(variantID: CartTestFixtures.variant("office-2024"))

        #expect(model.generalWarnings == ["Nicht genug Bestand."])
    }

    @Test("A failed change while the cart is shown appears as a dismissable banner")
    func actionError() async throws {
        let model = makeModel()
        await model.cartStore.add(variantID: CartTestFixtures.variant("office-2024"))
        await repository.failNextMutation(with: ShopifyError.network(.offline))

        try await model.increase(firstLine(model))

        #expect(model.actionError == UserFacingError(kind: .offline))
        model.dismissError()
        #expect(model.actionError == nil)
    }

    @Test("The cross-sell row asks for complementary products of the first line, without products in the cart")
    func crossSell() async {
        let recommended = ["office-2024", "windows-11-pro"] + (1...10).map { "extra-\($0)" }
        let catalog = CartFeatureStubCatalog(recommendations: recommended.map(CartTestFixtures.summary))
        let model = makeModel(catalog: catalog)
        await model.cartStore.add(variantID: CartTestFixtures.variant("office-2024"))
        await model.cartStore.add(variantID: CartTestFixtures.variant("windows-11-pro"))

        await model.loadCrossSell()

        let handles = model.crossSell.value?.map(\.handle) ?? []
        #expect(handles == (1...8).map { "extra-\($0)" })
        let requests = await catalog.requests
        #expect(requests == [CartFeatureStubCatalog.Request(productID: CartTestFixtures.productID("office-2024"), intent: .complementary)])
        #expect(model.crossSellKey == [CartTestFixtures.productID("office-2024"), CartTestFixtures.productID("windows-11-pro")])

        await model.loadCrossSell()
        #expect(await catalog.requests.count == 1, "The row is not loaded again for the same first product")
    }

    @Test("A failing cross-sell row reports the failure and can be retried")
    func crossSellFailure() async {
        let catalog = CartFeatureStubCatalog(recommendations: [CartTestFixtures.summary("extra")])
        await catalog.failNext(with: ShopifyError.network(.offline))
        let model = makeModel(catalog: catalog)
        await model.cartStore.add(variantID: CartTestFixtures.variant("office-2024"))

        await model.loadCrossSell()
        #expect(model.crossSell.error == UserFacingError(kind: .offline))

        await model.reloadCrossSell()
        #expect(model.crossSell.value?.map(\.handle) == ["extra"])
    }

    @Test("Without lines the cross-sell row is empty and asks nothing")
    func crossSellWithoutCart() async {
        let catalog = CartFeatureStubCatalog(recommendations: [CartTestFixtures.summary("extra")])
        let model = makeModel(catalog: catalog)

        await model.loadCrossSell()

        #expect(model.crossSell == .empty)
        #expect(await catalog.requests.isEmpty)
    }

    @Test("The variant line hides Shopify's default title and repeats of the product title")
    func variantText() {
        #expect(CartLinePresentation.variantText(for: CartTestFixtures.merchandise("windows-11-pro")) == nil)
        #expect(CartLinePresentation
            .variantText(for: CartTestFixtures.merchandise("windows-11-pro", title: "Produkt windows-11-pro")) == nil)
        #expect(CartLinePresentation.variantText(for: CartTestFixtures.merchandise("office", title: "1 PC")) == "1 PC")
        let options = [SelectedOption(name: "Geräte", value: "1 PC"), SelectedOption(name: "Laufzeit", value: "Dauerhaft")]
        #expect(CartLinePresentation.variantText(for: CartTestFixtures.merchandise("office", title: "1 PC / Dauerhaft", options: options))
            == "1 PC, Dauerhaft")
    }
}

// MARK: - New cart strings

@Suite("Cart screen strings")
struct CartScreenStringTests {
    static let keys = [
        "cart.loading",
        "cart.crosssell.title",
        "cart.line.unavailable",
        "cart.line.remove",
        "cart.line.decrease",
        "cart.line.increase",
        "cart.discount.title",
        "cart.discount.placeholder",
        "cart.discount.apply",
        "cart.discount.not_applicable",
        "cart.discount.active",
        "cart.discount.inactive",
        "cart.summary.subtotal",
        "cart.summary.discount",
        "cart.summary.total",
        "cart.undo.action",
        "cart.undo.dismiss",
        "cart.checkout",
    ]

    @Test("The German checkout button reads \"Zur Kasse\"")
    func checkoutButton() throws {
        let german = try LocalizedStrings(language: "de", in: CartResources.bundle)
        #expect(german("cart.checkout") == "Zur Kasse")
        #expect(german("cart.undo.action") == "Rückgängig")
    }

    @Test("Every new cart text exists in German and English without dashes", arguments: ["de", "en"])
    func texts(language: String) throws {
        let strings = try LocalizedStrings(language: language, in: CartResources.bundle)
        for key in Self.keys {
            let text = strings(key)
            #expect(text != key, "\(key) has no \(language) value")
            #expect(!containsForbiddenDash(text), "Dash in \(key)")
        }
    }
}
