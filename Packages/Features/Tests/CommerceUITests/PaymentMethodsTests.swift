@testable import CommerceUI
import Foundation
import ShopifyKit
import Testing
import UIKit

@Suite("Payment methods")
struct PaymentMethodsTests {
    /// The methods that always follow, because Shopify's payment settings cannot report them.
    private static let fixed: [PaymentMethod] = [.klarna, .invoice, .prepayment]

    @Test("Without Shopify's settings the business facts show: Apple Pay, a neutral card, UnionPay, Klarna, Rechnung, Vorkasse")
    func fallback() {
        #expect(PaymentMethod.fallback == [.applePay, .card, .unionPay] + Self.fixed)
        #expect(PaymentMethod.methods(for: .empty) == PaymentMethod.fallback)
    }

    @Test("Visa, Mastercard and Amex with Apple Pay and Google Pay give the nine methods of the web shop")
    func liveStore() {
        let settings = PaymentSettings(
            acceptedCardBrands: [.visa, .mastercard, .americanExpress],
            supportedDigitalWallets: [.shopifyPay, .applePay, .googlePay]
        )
        #expect(PaymentMethod.methods(for: settings) == [
            .applePay, .visa, .mastercard, .americanExpress, .unionPay, .googlePay, .klarna, .invoice, .prepayment,
        ])
    }

    @Test("Shopify's card brands replace the neutral card, in Shopify's order, followed by UnionPay")
    func reportedBrands() {
        let settings = PaymentSettings(
            acceptedCardBrands: [.visa, .mastercard, .americanExpress],
            supportedDigitalWallets: [.applePay, .shopifyPay]
        )
        #expect(PaymentMethod.methods(for: settings) == [.applePay, .visa, .mastercard, .americanExpress, .unionPay] + Self.fixed)
    }

    @Test("Apple Pay and Google Pay show only when Shopify lists them; the fixed methods always show")
    func wallets() {
        let cardsOnly = PaymentSettings(acceptedCardBrands: [.visa], supportedDigitalWallets: [])
        #expect(PaymentMethod.methods(for: cardsOnly) == [.visa, .unionPay] + Self.fixed)
        let walletOnly = PaymentSettings(acceptedCardBrands: [], supportedDigitalWallets: [.applePay])
        #expect(PaymentMethod.methods(for: walletOnly) == [.applePay, .card, .unionPay] + Self.fixed)
        let otherWallets = PaymentSettings(acceptedCardBrands: [.jcb], supportedDigitalWallets: [.googlePay, .shopifyPay])
        #expect(PaymentMethod.methods(for: otherWallets) == [.jcb, .unionPay, .googlePay] + Self.fixed)
    }

    @Test("Every card brand has its own method", arguments: CardBrand.allCases)
    func cardBrands(brand: CardBrand) {
        let method = PaymentMethod(cardBrand: brand)
        #expect(method != .card)
        #expect(method.assetName != nil)
    }

    @Test("Every acceptance mark is in the module's asset catalog; the others have a plain card", arguments: PaymentMethod.allCases)
    func assets(method: PaymentMethod) {
        guard let assetName = method.assetName else {
            #expect(method == .card)
            #expect(method.plainCardSymbol != nil)
            return
        }
        #expect(method.plainCardSymbol == nil)
        #expect(UIImage(named: assetName, in: CommerceUIResources.bundle, with: nil) != nil, "\(assetName) is missing")
    }

    @Test("Rechnung and Vorkasse have their own marks")
    func ownMarks() {
        #expect(PaymentMethod.invoice.assetName == "payment-invoice")
        #expect(PaymentMethod.prepayment.assetName == "payment-prepayment")
    }

    @Test("All marks fit on one line: they keep their size when there is room and shrink together otherwise")
    func oneLine() {
        #expect(PaymentMarksLine.markWidth(available: 500, count: 9, maximum: 38, spacing: 6) == 38)
        let narrow = PaymentMarksLine.markWidth(available: 353, count: 9, maximum: 38, spacing: 6)
        #expect(abs(narrow * 9 + 6 * 8 - 353) < 0.001)
        #expect(PaymentMarksLine.markWidth(available: nil, count: 9, maximum: 38, spacing: 6) == 38)
        #expect(PaymentMarksLine.markWidth(available: 300, count: 0, maximum: 38, spacing: 6) == 0)
    }

    @Test("Brand names stay untranslated; the neutral card, Rechnung and Vorkasse have localized names")
    func spokenNames() {
        #expect(PaymentMethod.applePay.spokenName == "Apple Pay")
        #expect(PaymentMethod.googlePay.spokenName == "Google Pay")
        #expect(PaymentMethod.unionPay.spokenName == "UnionPay")
        #expect(PaymentMethod.klarna.spokenName == "Klarna")
        #expect(PaymentMethod.mastercard.spokenName == "Mastercard")
        let localized: [(PaymentMethod, String)] = [
            (.card, "commerce.payment.card"),
            (.invoice, "commerce.payment.invoice"),
            (.prepayment, "commerce.payment.prepayment"),
        ]
        for (method, key) in localized {
            #expect(!method.spokenName.isEmpty)
            #expect(method.spokenName != key)
        }
    }
}

@MainActor
@Suite("Payment methods store")
struct PaymentMethodsStoreTests {
    @Test("Loads Shopify's settings once")
    func loadsOnce() async {
        let catalog = PaymentStubCatalog(results: [
            .success(PaymentSettings(acceptedCardBrands: [.visa, .mastercard], supportedDigitalWallets: [.applePay])),
        ])
        let store = PaymentMethodsStore(catalog: catalog)
        #expect(store.methods == PaymentMethod.fallback)

        await store.loadIfNeeded()
        await store.loadIfNeeded()

        #expect(store.methods == [.applePay, .visa, .mastercard, .unionPay, .klarna, .invoice, .prepayment])
        #expect(await catalog.requestCount == 1)
    }

    @Test("A failure keeps the business facts and the next call tries again")
    func failureRetries() async {
        let catalog = PaymentStubCatalog(results: [
            .failure(ShopifyError.network(.offline)),
            .success(PaymentSettings(acceptedCardBrands: [.mastercard], supportedDigitalWallets: [.applePay])),
        ])
        let store = PaymentMethodsStore(catalog: catalog)

        await store.loadIfNeeded()
        #expect(store.methods == PaymentMethod.fallback)

        await store.loadIfNeeded()
        #expect(store.methods == [.applePay, .mastercard, .unionPay, .klarna, .invoice, .prepayment])
        #expect(await catalog.requestCount == 2)
    }
}

// MARK: - PaymentStubCatalog

/// A catalog that answers the payment settings from a queue and nothing else.
private actor PaymentStubCatalog: CatalogRepository {
    private var results: [Result<PaymentSettings, ShopifyError>]
    private(set) var requestCount = 0

    init(results: [Result<PaymentSettings, ShopifyError>]) {
        self.results = results
    }

    func paymentSettings() async throws -> PaymentSettings {
        requestCount += 1
        guard !results.isEmpty else { return .empty }
        return try results.removeFirst().get()
    }

    func product(handle _: String) async throws -> Product? {
        nil
    }

    func collection(
        handle _: String,
        first _: Int,
        after _: String?,
        sortKey _: ProductCollectionSortKeys,
        reverse _: Bool,
        filters _: [ProductFilterInput]
    ) async throws -> CollectionPage? {
        nil
    }

    func collections(first _: Int) async throws -> [CollectionSummary] {
        []
    }

    func recommendations(productID _: ShopifyID, intent _: ProductRecommendationIntent) async throws -> [ProductSummary] {
        []
    }
}
