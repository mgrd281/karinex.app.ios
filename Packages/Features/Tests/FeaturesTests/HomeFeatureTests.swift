import CommerceUI
import Foundation
@testable import HomeFeature
import ShopifyKit
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
            "Support Mo. bis So., 06:00 bis 23:00 Uhr deutscher Zeit",
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

    @Test("The service hours are Monday to Sunday, 06:00 to 23:00 German time")
    func hours() throws {
        let german = try LocalizedStrings(language: "de", in: HomeResources.bundle)

        #expect(german("home.support.hours.value") == "Mo. bis So., 06:00 bis 23:00 Uhr deutscher Zeit")
    }

    @Test("Every mention of the service hours says they are German time", arguments: appLanguages)
    func hoursNameTheTimeZone(language: String) throws {
        let strings = try LocalizedStrings(language: language, in: HomeResources.bundle)
        let timeZoneNames = [
            "de": "deutscher Zeit", "en": "German time", "pl": "czasu niemieckiego", "nl": "Duitse tijd",
            "pt-PT": "hora da Alemanha", "sv": "tysk tid", "da": "tysk tid", "es": "hora alemana",
            "fr": "heure allemande", "it": "ora tedesca", "fi": "Saksan aikaa",
        ]
        let timeZoneName = try #require(timeZoneNames[language])

        for text in [strings("home.support.hours.value"), HomeTrustFact.supportHours.text(in: strings.bundle)] {
            #expect(text.contains("06:00"), "\(text)")
            #expect(text.contains("23:00"), "\(text)")
            #expect(text.contains(timeZoneName), "\(text) does not say that the hours are German time")
        }
    }
}

// MARK: - Catalog completeness

@Suite("Home strings")
struct HomeStringTests {
    @Test("Every content text resolves without dashes", arguments: appLanguages)
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

    @Test("Screen texts resolve without dashes", arguments: appLanguages)
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

// MARK: - Layout

@Suite("Home layout")
struct HomeLayoutTests {
    @Test("The standard layout lists the live rows in order with the store handles")
    func standardOrder() {
        let sections = HomeLayout.standard.sections
        #expect(sections.map(\.id) == [
            "sale",
            "windows",
            "microsoft-office",
            "windows-server",
            "visual-studio-entwicklungstools",
            "bestseller",
            "guides",
        ])
        #expect(sections.map(\.accessibilityIdentifier).first == "home.row.sale")
        #expect(sections.map(\.accessibilityIdentifier).last == "home.row.guides")
    }

    @Test("Only the bestseller row carries the bestseller badge, the guides row loads 6 articles")
    func contentDetails() {
        for section in HomeLayout.standard.sections {
            switch section.content {
            case let .collection(handle, limit, highlight):
                #expect(highlight == (handle == "bestseller" ? .bestseller : ProductCardHighlight.none), "\(handle)")
                #expect(limit == HomeLayout.productsPerRow)
            case let .blog(handle, limit):
                #expect(handle == "guides")
                #expect(limit == 6)
            }
        }
    }

    @Test("The German row titles are the categories of the Start tab")
    func germanTitles() throws {
        let german = try LocalizedStrings(language: "de", in: HomeResources.bundle)

        #expect(HomeLayout.standard.sections.map { $0.title.resolved(in: german.bundle) } == [
            "Angebote", "Windows", "Office", "Server", "Entwicklung", "Bestseller", "Ratgeber",
        ])
    }

    @Test("A layout keeps the first section of a repeated handle")
    func uniqueHandles() {
        let layout = HomeLayout(sections: [
            HomeSection(title: .verbatim("A"), content: .collection(handle: "windows", limit: 4, highlight: .none)),
            HomeSection(title: .verbatim("B"), content: .collection(handle: "windows", limit: 8, highlight: .none)),
            HomeSection(title: .verbatim("C"), content: .blog(handle: "guides", limit: 3)),
        ])

        #expect(layout.sections.map(\.id) == ["windows", "guides"])
        #expect(layout.sections.first?.title == .verbatim("A"))
        #expect(HomeText.verbatim("Office").resolved == "Office")
    }
}

// MARK: - View model

@Suite("Home view model")
@MainActor
struct HomeViewModelTests {
    private let layout = HomeLayout(sections: [
        HomeSection(title: .verbatim("Angebote"), content: .collection(handle: "sale", limit: 8, highlight: .none)),
        HomeSection(title: .verbatim("Windows"), content: .collection(handle: "windows", limit: 8, highlight: .none)),
        HomeSection(title: .verbatim("Ratgeber"), content: .blog(handle: "guides", limit: 6)),
    ])

    @Test("Every row is requested with its handle, size and the collection order")
    func loadsEveryRow() async {
        let catalog = BrowseStubCatalogRepository { request in
            BrowseFixtures.page(request.handle, products: BrowseFixtures.products(request.handle, count: 3))
        }
        let content = BrowseStubContentRepository { blog in [BrowseFixtures.article("a", blog: blog)] }
        let model = HomeViewModel(catalog: catalog, content: content, layout: layout)

        await model.loadIfNeeded()

        let requests = await catalog.collectionRequests
        #expect(Set(requests.map(\.handle)) == ["sale", "windows"])
        #expect(requests
            .allSatisfy { $0.first == 8 && $0.after == nil && $0.sortKey == .collectionDefault && !$0.reverse && $0.filters.isEmpty })
        #expect(await content.requestDescriptions == ["guides:6"])
        #expect(model.productState(for: layout.sections[0]).value?.map(\.handle) == ["sale-1", "sale-2", "sale-3"])
        #expect(model.productState(for: layout.sections[1]).value?.count == 3)
        #expect(model.articleState(for: layout.sections[2]).value?.map(\.handle) == ["a"])
    }

    @Test("Loading happens once; pull to refresh loads again")
    func loadsOnce() async {
        let catalog = BrowseStubCatalogRepository { request in
            BrowseFixtures.page(request.handle, products: [BrowseFixtures.product("p")])
        }
        let model = HomeViewModel(catalog: catalog, content: BrowseStubContentRepository(), layout: layout)

        await model.loadIfNeeded()
        await model.loadIfNeeded()
        #expect(await catalog.collectionRequests.count == 2)

        await model.reload()
        #expect(await catalog.collectionRequests.count == 4)
    }

    @Test("A failing row fails alone and a retry reloads only that row")
    func failingRow() async {
        let catalog = BrowseStubCatalogRepository { request in
            if request.handle == "windows" {
                throw ShopifyError.network(.offline)
            }
            return BrowseFixtures.page(request.handle, products: [BrowseFixtures.product("deal")])
        }
        let model = HomeViewModel(catalog: catalog, content: BrowseStubContentRepository(), layout: layout)

        await model.reload()

        #expect(model.productState(for: layout.sections[0]).value?.count == 1)
        #expect(model.productState(for: layout.sections[1]).error == UserFacingError(kind: .offline))

        await catalog.setCollectionHandler { request in
            BrowseFixtures.page(request.handle, products: [BrowseFixtures.product("win")])
        }
        await model.reload(layout.sections[1])

        #expect(model.productState(for: layout.sections[1]).value?.map(\.handle) == ["win"])
        #expect(await catalog.requestedHandles.filter { $0 == "sale" }.count == 1)
    }

    @Test("Empty or missing collections and blogs hide their rows")
    func emptyRows() async {
        let catalog = BrowseStubCatalogRepository { request in
            request.handle == "sale" ? nil : BrowseFixtures.page(request.handle, products: [])
        }
        let model = HomeViewModel(catalog: catalog, content: BrowseStubContentRepository(), layout: layout)

        await model.reload()

        #expect(model.productState(for: layout.sections[0]) == .empty)
        #expect(model.productState(for: layout.sections[1]) == .empty)
        #expect(model.articleState(for: layout.sections[2]) == .empty)
    }

    @Test("A failed refresh keeps the rows on screen")
    func refreshKeepsContent() async {
        let catalog = BrowseStubCatalogRepository { request in
            BrowseFixtures.page(request.handle, products: [BrowseFixtures.product("kept")])
        }
        let content = BrowseStubContentRepository { _ in [BrowseFixtures.article("kept")] }
        let model = HomeViewModel(catalog: catalog, content: content, layout: layout)
        await model.reload()

        await catalog.setCollectionHandler { _ in throw ShopifyError.throttled }
        await model.reload()

        #expect(model.productState(for: layout.sections[0]).value?.map(\.handle) == ["kept"])
        #expect(model.articleState(for: layout.sections[2]).value?.map(\.handle) == ["kept"])
    }

    @Test("Rows start idle before the first load")
    func idleBeforeLoad() {
        let model = HomeViewModel(catalog: BrowseStubCatalogRepository(), content: BrowseStubContentRepository(), layout: layout)

        #expect(model.productState(for: layout.sections[0]) == .idle)
        #expect(model.articleState(for: layout.sections[2]) == .idle)
    }
}

// MARK: - Phase 1 strings

@Suite("Home live row strings")
struct HomeLiveRowStringTests {
    @Test("The row texts resolve without dashes", arguments: ["de", "en"])
    func rowTexts(language: String) throws {
        let strings = try LocalizedStrings(language: language, in: HomeResources.bundle)
        let keys = [
            "home.section.deals.title", "home.section.deals.eyebrow",
            "home.section.windows.title", "home.section.windows.eyebrow",
            "home.section.office.title", "home.section.office.eyebrow",
            "home.section.server.title", "home.section.server.eyebrow",
            "home.section.development.title", "home.section.development.eyebrow",
            "home.section.bestseller.title", "home.section.bestseller.eyebrow",
            "home.section.guides.title", "home.section.guides.eyebrow",
            "home.article.hint", "home.loading",
        ]

        for key in keys {
            let text = strings(key)
            #expect(text != key, "\(key) has no \(language) value")
            #expect(!containsForbiddenDash(text), "Dash in \(key)")
        }
    }
}
