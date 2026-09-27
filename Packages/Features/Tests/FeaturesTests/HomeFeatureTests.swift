import Foundation
@testable import HomeFeature
import Testing

// MARK: - Trust facts

@Suite("Home trust facts")
struct HomeTrustFactTests {
    @Test("The trust strip shows the four facts of the Start tab in order")
    func order() {
        #expect(HomeTrustFact.allCases == [.emailDelivery, .paymentMethods, .moneyBack, .supportHours])
        #expect(HomeTrustFact.allCases.map(\.systemImage) == ["envelope", "creditcard", "arrow.uturn.backward", "clock"])
        #expect(Set(HomeTrustFact.allCases.map(\.id)).count == HomeTrustFact.allCases.count)
    }

    @Test("Only the money-back promise carries the marker and opens its conditions")
    func onlyMoneyBackRevealsConditions() {
        for fact in HomeTrustFact.allCases {
            let isMoneyBack = fact == .moneyBack
            #expect(fact.revealsConditions == isMoneyBack)
            #expect(fact.footnoteMarker == (isMoneyBack ? HomeTrustFact.conditionMarker : nil))
        }
        #expect(HomeTrustFact.conditionMarker == "*")
    }

    @Test("German trust texts are the brand facts")
    func germanTexts() throws {
        let german = try LocalizedStrings(language: "de", in: HomeResources.bundle)

        #expect(HomeTrustFact.allCases.map { $0.text(in: german.bundle) } == [
            "Lieferung per E-Mail in Minuten",
            "Apple Pay, Kreditkarte, Klarna",
            "100 Tage Geld-zurück",
            "Support Mo. bis So., 06:00 bis 23:00 Uhr",
        ])
    }

    @Test("English trust texts name the same facts")
    func englishTexts() throws {
        let english = try LocalizedStrings(language: "en", in: HomeResources.bundle)

        #expect(HomeTrustFact.paymentMethods.text(in: english.bundle) == "Apple Pay, credit card, Klarna")
        #expect(HomeTrustFact.moneyBack.text(in: english.bundle) == "100-day money-back")
    }

    @Test("Texts resolve in the current language")
    func currentLanguage() {
        for fact in HomeTrustFact.allCases {
            #expect(!fact.text.isEmpty)
            #expect(!fact.text.hasPrefix("home."), "Unresolved key for \(fact)")
        }
    }
}

// MARK: - Money-back conditions

@Suite("Home money-back conditions")
struct MoneyBackConditionTests {
    @Test("The conditions are scope, unactivated keys and statutory rights, in that order")
    func order() {
        #expect(MoneyBackClause.allCases == [.scope, .unactivatedKeys, .statutoryRights])
        #expect(Set(MoneyBackClause.allCases.map(\.id)).count == MoneyBackClause.allCases.count)
    }

    @Test("The German clauses state the business rule")
    func germanClauses() throws {
        let german = try LocalizedStrings(language: "de", in: HomeResources.bundle)

        let scope = MoneyBackClause.scope.text(in: german.bundle)
        #expect(scope.contains("nur für aktivierte Lizenzschlüssel"))
        #expect(scope.contains("physische Ware"))

        let unactivated = MoneyBackClause.unactivatedKeys.text(in: german.bundle)
        #expect(unactivated.contains("nicht aktivierte Lizenzschlüssel"))
        #expect(unactivated.contains("nicht freiwillig erstattet"))

        let statutory = MoneyBackClause.statutoryRights.text(in: german.bundle)
        #expect(statutory.contains("gesetzlichen Gewährleistungsrechte"))
        #expect(statutory.contains("unberührt"))
    }

    @Test("The footnote next to the promise repeats all three conditions")
    func footnote() throws {
        let german = try LocalizedStrings(language: "de", in: HomeResources.bundle)

        let footnote = german("home.trust.footnote")
        #expect(footnote.contains("nur für aktivierte Lizenzschlüssel und physische Ware"))
        #expect(footnote.contains("nicht freiwillig erstattet"))
        #expect(footnote.contains("Gewährleistungsrechte bleiben unberührt"))
    }
}

// MARK: - Support

@Suite("Home support card")
struct HomeSupportTests {
    @Test("The support channels are WhatsApp, e-mail and live chat")
    func channels() throws {
        #expect(SupportChannel.allCases == [.whatsApp, .email, .liveChat])
        #expect(SupportChannel.email.detail == "kundenservice@karinex.de")
        #expect(SupportChannel.whatsApp.detail == nil)
        #expect(SupportChannel.liveChat.detail == nil)

        let german = try LocalizedStrings(language: "de", in: HomeResources.bundle)
        #expect(SupportChannel.allCases.map { $0.name(in: german.bundle) } == ["WhatsApp", "E-Mail", "Live-Chat"])
    }

    @Test("The service hours are Monday to Sunday, 06:00 to 23:00")
    func hours() throws {
        let german = try LocalizedStrings(language: "de", in: HomeResources.bundle)

        #expect(german("home.support.hours.value") == "Mo. bis So., 06:00 bis 23:00 Uhr")
    }
}

// MARK: - Catalog completeness

@Suite("Home strings")
struct HomeStringTests {
    @Test("Every content text resolves without dashes", arguments: phaseZeroLanguages)
    func contentTexts(language: String) throws {
        let strings = try LocalizedStrings(language: language, in: HomeResources.bundle)
        let texts = HomeTrustFact.allCases.map { $0.text(in: strings.bundle) }
            + MoneyBackClause.allCases.map { $0.text(in: strings.bundle) }
            + SupportChannel.allCases.map { $0.name(in: strings.bundle) }

        for text in texts {
            #expect(!text.isEmpty)
            #expect(!text.hasPrefix("home."), "Unresolved key \(text)")
            #expect(!containsForbiddenDash(text), "Dash in \(text)")
        }
    }

    @Test("Screen texts resolve without dashes", arguments: phaseZeroLanguages)
    func screenTexts(language: String) throws {
        let strings = try LocalizedStrings(language: language, in: HomeResources.bundle)
        let keys = [
            "home.title",
            "home.hero.eyebrow",
            "home.hero.title",
            "home.hero.body",
            "home.hero.cta",
            "home.trust.eyebrow",
            "home.trust.title",
            "home.trust.moneyback.hint",
            "home.trust.footnote",
            "home.trust.conditions",
            "home.moneyback.title",
            "home.moneyback.intro",
            "home.moneyback.done",
            "home.support.eyebrow",
            "home.support.title",
            "home.support.message",
            "home.support.hours.label",
            "home.support.hours.value",
        ]

        for key in keys {
            let text = strings(key)
            #expect(text != key, "\(key) has no \(language) value")
            #expect(!containsForbiddenDash(text), "Dash in \(key)")
        }
    }
}
