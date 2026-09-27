@testable import CartFeature
import Foundation
import Testing

@Suite("Cart strings")
struct CartStringTests {
    @Test("The payment methods are exactly Apple Pay, Kreditkarte, Klarna")
    func paymentMethods() throws {
        let german = try LocalizedStrings(language: "de", in: CartResources.bundle)
        let english = try LocalizedStrings(language: "en", in: CartResources.bundle)

        #expect(german("cart.payment.methods") == "Apple Pay, Kreditkarte, Klarna")
        #expect(english("cart.payment.methods") == "Apple Pay, credit card, Klarna")
    }

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

    @Test("The empty cart state reads as in the brand copy")
    func emptyState() throws {
        let german = try LocalizedStrings(language: "de", in: CartResources.bundle)

        #expect(german("cart.empty.title") == "Ihr Warenkorb ist leer")
        #expect(german("cart.empty.action") == "Zum Sortiment")
    }

    @Test("Every cart text resolves without dashes", arguments: phaseZeroLanguages)
    func allTexts(language: String) throws {
        let strings = try LocalizedStrings(language: language, in: CartResources.bundle)
        let keys = [
            "cart.title",
            "cart.empty.title",
            "cart.empty.message",
            "cart.empty.action",
            "cart.payment.title",
            "cart.payment.methods",
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
