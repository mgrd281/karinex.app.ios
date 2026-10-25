@testable import CommerceUI
import Foundation
import ShopifyKit
import Testing
import UIKit

@Suite("Payment methods")
struct PaymentMethodsTests {
    @Test("Without Shopify's settings the business facts show: Apple Pay, a neutral card, Klarna")
    func fallback() {
        #expect(PaymentMethod.fallback == [.applePay, .card, .klarna])
        #expect(PaymentMethod.methods(for: .empty) == PaymentMethod.fallback)
    }

    @Test("Shopify's card brands replace the neutral card, in Shopify's order")
    func reportedBrands() {
        let settings = PaymentSettings(
            acceptedCardBrands: [.visa, .mastercard, .americanExpress],
            supportedDigitalWallets: [.applePay, .shopifyPay]
        )
        #expect(PaymentMethod.methods(for: settings) == [.applePay, .visa, .mastercard, .americanExpress, .klarna])
    }

    @Test("Apple Pay shows only when Shopify lists it; Klarna always shows")
    func wallets() {
        let cardsOnly = PaymentSettings(acceptedCardBrands: [.visa], supportedDigitalWallets: [])
        #expect(PaymentMethod.methods(for: cardsOnly) == [.visa, .klarna])
        let walletOnly = PaymentSettings(acceptedCardBrands: [], supportedDigitalWallets: [.applePay])
        #expect(PaymentMethod.methods(for: walletOnly) == [.applePay, .card, .klarna])
        let otherWallets = PaymentSettings(acceptedCardBrands: [.jcb], supportedDigitalWallets: [.googlePay, .shopifyPay])
        #expect(PaymentMethod.methods(for: otherWallets) == [.jcb, .klarna])
    }

    @Test("Every card brand has its own method", arguments: CardBrand.allCases)
    func cardBrands(brand: CardBrand) {
        let method = PaymentMethod(cardBrand: brand)
        #expect(method != .card)
        #expect(method.assetName != nil)
    }

    @Test("Every acceptance mark is in the module's asset catalog", arguments: PaymentMethod.allCases)
    func assets(method: PaymentMethod) {
        guard let assetName = method.assetName else {
            #expect(method == .card)
            return
        }
        #expect(UIImage(named: assetName, in: CommerceUIResources.bundle, with: nil) != nil, "\(assetName) is missing")
    }

    @Test("Brand names stay untranslated; the neutral card has a localized name")
    func spokenNames() {
        #expect(PaymentMethod.applePay.spokenName == "Apple Pay")
        #expect(PaymentMethod.klarna.spokenName == "Klarna")
        #expect(PaymentMethod.mastercard.spokenName == "Mastercard")
        #expect(!PaymentMethod.card.spokenName.isEmpty)
        #expect(PaymentMethod.card.spokenName != "commerce.payment.card")
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

        #expect(store.methods == [.applePay, .visa, .mastercard, .klarna])
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
        #expect(store.methods == [.applePay, .mastercard, .klarna])
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
