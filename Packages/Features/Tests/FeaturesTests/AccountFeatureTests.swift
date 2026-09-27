@testable import AccountFeature
import Foundation
import Testing

// MARK: - Version

@Suite("Account app info")
struct AccountAppInfoTests {
    @Test("Version and build read as \"0.1.0 (1)\"")
    func summary() {
        #expect(AccountAppInfo(version: "0.1.0", build: "1").summary == "0.1.0 (1)")
    }

    @Test("Surrounding whitespace is removed")
    func trimming() {
        let info = AccountAppInfo(version: " 0.1.0\n", build: "\t42 ")

        #expect(info.version == "0.1.0")
        #expect(info.build == "42")
        #expect(info.summary == "0.1.0 (42)")
    }

    @Test("A missing part is left out")
    func missingParts() {
        #expect(AccountAppInfo(version: "0.1.0", build: "  ").summary == "0.1.0")
        #expect(AccountAppInfo(version: "", build: "7").summary == "7")
        #expect(AccountAppInfo(version: " ", build: "").summary.isEmpty)
    }
}

// MARK: - Benefits

@Suite("Account benefits")
struct AccountBenefitTests {
    @Test("The benefits are orders and invoices, license keys on this device and faster checkout")
    func order() {
        #expect(AccountBenefit.allCases == [.ordersAndInvoices, .licenseKeys, .fasterCheckout])
        #expect(AccountBenefit.allCases.map(\.systemImage) == ["doc.text", "key", "bolt"])
        #expect(Set(AccountBenefit.allCases.map(\.id)).count == AccountBenefit.allCases.count)
    }

    @Test("German benefit texts")
    func germanTexts() throws {
        let german = try LocalizedStrings(language: "de", in: AccountResources.bundle)

        #expect(AccountBenefit.allCases.map { $0.text(in: german.bundle) } == [
            "Bestellungen und Rechnungen jederzeit abrufen",
            "Lizenzschlüssel sicher auf diesem Gerät aufbewahren",
            "Schneller zur Kasse",
        ])
    }

    @Test("Texts resolve in the current language")
    func currentLanguage() {
        for benefit in AccountBenefit.allCases {
            #expect(!benefit.text.isEmpty)
            #expect(!benefit.text.hasPrefix("account."), "Unresolved key for \(benefit)")
        }
    }
}

// MARK: - Strings

@Suite("Account strings")
struct AccountStringTests {
    @Test("Every account text resolves without dashes", arguments: appLanguages)
    func allTexts(language: String) throws {
        let strings = try LocalizedStrings(language: language, in: AccountResources.bundle)
        let keys = [
            "account.title",
            "account.intro.eyebrow",
            "account.intro.title",
            "account.benefit.orders",
            "account.benefit.keys",
            "account.benefit.checkout",
            "account.signin.note",
            "account.about.title",
            "account.about.version",
        ]

        for key in keys {
            let text = strings(key)
            #expect(text != key, "\(key) has no \(language) value")
            #expect(!containsForbiddenDash(text), "Dash in \(key)")
        }
    }
}
