@testable import CommerceUI
import DesignSystem
import Foundation
import ShopifyKit
import Testing

@Suite("PriceDisplay")
struct PriceDisplayTests {
    private let germany = Locale(identifier: "de_DE")

    private func euro(_ amount: String) -> MoneyV2 {
        MoneyV2(amount: Decimal(string: amount) ?? 0, currencyCode: .eur)
    }

    // MARK: Tax note

    @Test("EU markets include VAT; shipping is added only for physical items", arguments: [
        CountryCode.de, .at, .fr, .it, .nl, .pl, .se, .fi, .ie, .gr, .ro, .mt,
    ])
    func euMarkets(country: CountryCode) {
        #expect(PriceDisplay.taxNote(country: country, requiresShipping: false) == .includingVAT)
        #expect(PriceDisplay.taxNote(country: country, requiresShipping: true) == .includingVATPlusShipping)
    }

    @Test("Switzerland and other non-EU markets show no VAT note", arguments: [CountryCode.ch, .no, .us])
    func nonEUMarkets(country: CountryCode) {
        #expect(PriceDisplay.taxNote(country: country, requiresShipping: false) == nil)
        #expect(PriceDisplay.taxNote(country: country, requiresShipping: true) == .plusShipping)
    }

    @Test("Every store country outside Switzerland is an EU market")
    func storeCountries() {
        for country in CountryCode.recordedStoreCountries {
            let note = PriceDisplay.taxNote(country: country, requiresShipping: false)
            #expect(note == (country == .ch ? nil : .includingVAT), "\(country)")
        }
    }

    @Test("Tax notes are localized and free of dashes")
    func taxNoteTexts() {
        for note in PriceDisplay.TaxNote.allCases {
            #expect(!note.text.isEmpty)
            #expect(!note.text.contains("\u{2013}") && !note.text.contains("\u{2014}"))
        }
    }

    // MARK: Savings

    @Test("Savings are a percentage rounded down", arguments: [
        ("12.90", "79.99", 83), // Windows 11 Pro, recorded 2026-09-26
        ("29.90", "149.99", 80), // Office 2024 Professional Plus
        ("13.90", "39.99", 65), // Office 2024 Standard für Mac
        ("99.00", "100.00", 1),
    ])
    func savingsPercent(price: String, compareAt: String, expected: Int) {
        #expect(PriceDisplay.savingsPercent(price: euro(price), compareAtPrice: euro(compareAt)) == expected)
    }

    @Test("No savings without a higher compare-at price in the same currency")
    func noSavings() {
        #expect(PriceDisplay.savingsPercent(price: euro("12.90"), compareAtPrice: nil) == nil)
        #expect(PriceDisplay.savingsPercent(price: euro("12.90"), compareAtPrice: euro("12.90")) == nil)
        #expect(PriceDisplay.savingsPercent(price: euro("12.90"), compareAtPrice: euro("9.90")) == nil)
        #expect(PriceDisplay.savingsPercent(price: euro("99.99"), compareAtPrice: euro("100.00")) == nil)
        let francs = MoneyV2(amount: 80, currencyCode: .chf)
        #expect(PriceDisplay.savingsPercent(price: euro("12.90"), compareAtPrice: francs) == nil)
    }

    // MARK: Display strings

    @Test("Reduced price in Germany: formatted strings, savings badge and VAT note")
    func reducedGermanPrice() {
        let display = PriceDisplay(
            price: euro("12.90"),
            compareAtPrice: euro("79.99"),
            country: .de,
            requiresShipping: false,
            locale: germany
        )
        #expect(display.price == euro("12.90").formatted(locale: germany))
        #expect(display.price.contains("12,90"))
        #expect(display.compareAtPrice == euro("79.99").formatted(locale: germany))
        #expect(display.savingsPercent == 83)
        #expect(display.savingsText?.contains("83") == true)
        #expect(display.taxNote == .includingVAT)
    }

    @Test("A compare-at price that is not higher is hidden")
    func compareAtHidden() {
        let display = PriceDisplay(
            price: euro("29.90"),
            compareAtPrice: euro("29.90"),
            country: .de,
            requiresShipping: false,
            locale: germany
        )
        #expect(display.compareAtPrice == nil)
        #expect(display.savingsText == nil)
    }

    @Test("Switzerland: CHF price without tax note")
    func swissPrice() {
        let display = PriceDisplay(
            price: MoneyV2(amount: 29, currencyCode: .chf),
            compareAtPrice: nil,
            country: .ch,
            requiresShipping: false,
            locale: Locale(identifier: "fr_CH")
        )
        #expect(display.price.contains("29"))
        #expect(display.taxNoteText == nil)
    }

    // MARK: Product cards

    @MainActor
    @Test("Product cards show the sale badge only for reduced products")
    func productCardBadges() {
        let reduced = CommercePreviewData.products[0]
        let saleBadge = String(localized: "commerce.product.badge.sale", bundle: CommerceUIResources.bundle)
        let bestsellerBadge = String(localized: "commerce.product.badge.bestseller", bundle: CommerceUIResources.bundle)

        let saleModel = ProductCardView.model(for: reduced, highlight: .bestseller, country: .de, locale: germany)
        #expect(saleModel.badge == saleBadge)
        #expect(saleModel.compareAtPrice != nil)
        #expect(saleModel.taxNote == PriceDisplay.TaxNote.includingVAT.text)
        #expect(saleModel.vendor == nil)
        #expect(saleModel.availabilityNote == nil)

        let regular = ProductSummary(
            id: reduced.id,
            handle: reduced.handle,
            title: reduced.title,
            vendor: reduced.vendor,
            availableForSale: false,
            featuredImage: nil,
            priceRange: reduced.priceRange,
            compareAtPriceRange: reduced.priceRange,
            requiresShipping: false
        )
        #expect(ProductCardView.model(for: regular, highlight: .bestseller, country: .ch, locale: germany).badge == bestsellerBadge)
        let plain = ProductCardView.model(for: regular, highlight: .none, country: .ch, locale: germany)
        #expect(plain.badge == nil)
        #expect(plain.taxNote == nil)
        #expect(plain.availabilityNote != nil)
    }
}
