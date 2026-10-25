@testable import CatalogFeature
import CommerceUI
import Core
import Foundation
@testable import SearchFeature
import ShopifyKit
import Testing

// MARK: - Catalog directory

@Suite("Catalog directory")
struct CatalogDirectoryTests {
    @Test("Highlights, families and versions come in curated order, every other collection in store order")
    func arrangement() {
        let store = [
            "bestseller", "all", "digital-goods-vat-tax", "microsoft-project", "sale", "windows", "windows-11",
            "microsoft-office", "windows-7", "windows-server-2016",
        ]
        .map { BrowseFixtures.collection($0) }

        let sections = CatalogDirectory.arrange(store)

        #expect(sections.highlights.map(\.handle) == ["bestseller", "sale"])
        #expect(sections.categories.map(\.handle) == ["windows", "microsoft-office"])
        #expect(sections.versions.map(\.handle) == ["windows-11", "microsoft-project"])
        #expect(sections.more.map(\.handle) == ["windows-7", "windows-server-2016"])
    }

    @Test("All products and the tax helper collection are never listed")
    func exclusions() {
        let sections = CatalogDirectory.arrange([BrowseFixtures.collection("all"), BrowseFixtures.collection("digital-goods-vat-tax")])

        #expect(sections.isEmpty)
    }

    @Test("A repeated handle is listed once")
    func duplicates() {
        let sections = CatalogDirectory.arrange([
            BrowseFixtures.collection("windows"),
            BrowseFixtures.collection("windows", title: "Again"),
        ])

        #expect(sections.categories.map(\.title) == ["windows"])
        #expect(sections.more.isEmpty)
    }

    @Test("No handle sits in two sections")
    func disjointSections() {
        let handles = CatalogDirectory.highlightHandles + CatalogDirectory.categoryHandles + CatalogDirectory.versionHandles
        #expect(Set(handles).count == handles.count)
        #expect(Set(handles).isDisjoint(with: CatalogDirectory.excludedHandles))
        #expect(CatalogDirectory.isSale("sale"))
        #expect(!CatalogDirectory.isSale("bestseller"))
    }

    @Test("Every family has its short line and every highlight its invitation, without dashes", arguments: appLanguages)
    func texts(language: String) throws {
        let strings = try LocalizedStrings(language: language, in: CatalogResources.bundle)
        let lines = try CatalogDirectory.categoryHandles.map { try #require(CatalogDirectory.detail(for: $0, in: strings.bundle)) }
            + CatalogDirectory.highlightHandles.map { try #require(CatalogDirectory.highlightAction(for: $0, in: strings.bundle)) }

        for line in lines {
            #expect(!line.isEmpty)
            #expect(!line.hasPrefix("catalog."), "Unresolved key \(line) in \(language)")
            #expect(!containsForbiddenDash(line), "Dash in \(line)")
        }
        #expect(CatalogDirectory.detail(for: "windows-11", in: strings.bundle) == nil)
        #expect(CatalogDirectory.highlightAction(for: "windows", in: strings.bundle) == nil)
        for key in ["catalog.versions.eyebrow", "catalog.versions.title", "catalog.featured.title", "catalog.more.title"] {
            #expect(strings(key) != key, "\(key) has no \(language) value")
        }
    }

    @Test("The German lines describe the families")
    func germanLines() throws {
        let german = try LocalizedStrings(language: "de", in: CatalogResources.bundle)

        #expect(CatalogDirectory.categoryHandles.compactMap { CatalogDirectory.detail(for: $0, in: german.bundle) } == [
            "Betriebssysteme für Ihren PC",
            "Word, Excel, PowerPoint und mehr",
            "Office für macOS",
            "Im Abonnement",
            "Für Unternehmen",
            "Entwicklungstools",
            "Project, Visio und SQL Server",
        ])
        #expect(CatalogDirectory.highlightAction(for: "sale", in: german.bundle) == "Reduzierte Preise")
    }
}

// MARK: - Collection names

@Suite("Collection names")
struct CollectionNameTests {
    @Test("Search engine titles of the store give way to short names, clean titles stay")
    func shortNames() throws {
        let german = try LocalizedStrings(language: "de", in: CommerceUIResources.bundle)
        func name(_ handle: String, _ storeTitle: String) -> String {
            CollectionNames.title(handle: handle, storeTitle: storeTitle, in: german.bundle)
        }

        #expect(name("bestseller", "Bestseller günstig kaufen") == "Bestseller")
        #expect(name("sale", "SALE \u{2013} Stark reduzierte Angebote") == "Sale")
        #expect(name("visual-studio-entwicklungstools", "Visual Studio \u{2013} Entwicklungstools") == "Visual Studio")
        #expect(name("microsoft-tools", "Microsoft Tools \u{2013} Visual Studio, SQL, Project, Visio") == "Microsoft Tools")
        #expect(name("microsoft-365-abonnement", "Microsoft 365 Abonnement") == "Microsoft 365")
        #expect(name("windows-server", "Windows Server") == "Windows Server")
        #expect(name("microsoft-office-2024-fur-mac", "Microsoft Office 2024 für Mac") == "Microsoft Office 2024 für Mac")
        #expect(CollectionNames.title(for: BrowseFixtures.collection("windows", title: "Windows")) == "Windows")
    }

    @Test("The short names exist in every language, without dashes", arguments: appLanguages)
    func everyLanguage(language: String) throws {
        let strings = try LocalizedStrings(language: language, in: CommerceUIResources.bundle)
        for handle in ["bestseller", "sale"] {
            let name = CollectionNames.title(handle: handle, storeTitle: "x", in: strings.bundle)
            #expect(name != "x")
            #expect(!name.hasPrefix("commerce."), "Unresolved key \(name) in \(language)")
            #expect(!containsForbiddenDash(name), "Dash in \(name)")
        }
    }
}

// MARK: - Catalog view model

@Suite("Catalog view model")
@MainActor
struct CatalogViewModelTests {
    @Test("The collections are requested once and arranged")
    func load() async {
        let catalog = BrowseStubCatalogRepository(collections: {
            ["windows", "all", "sale", "windows-10", "windows-7"].map { BrowseFixtures.collection($0) }
        })
        let model = CatalogViewModel(catalog: catalog)

        await model.load()

        #expect(await catalog.collectionsRequests == [CatalogDirectory.requestLimit])
        #expect(CatalogDirectory.requestLimit >= 30)
        #expect(model.state.value?.highlights.map(\.handle) == ["sale"])
        #expect(model.state.value?.categories.map(\.handle) == ["windows"])
        #expect(model.state.value?.versions.map(\.handle) == ["windows-10"])
        #expect(model.state.value?.more.map(\.handle) == ["windows-7"])
    }

    @Test("No listable collection is the empty state, a failure the error state")
    func emptyAndFailure() async {
        let empty = CatalogViewModel(catalog: BrowseStubCatalogRepository(collections: { [BrowseFixtures.collection("all")] }))
        await empty.load()
        #expect(empty.state == .empty)

        let failing = CatalogViewModel(catalog: BrowseStubCatalogRepository(collections: { throw ShopifyError.network(.offline) }))
        await failing.load()
        #expect(failing.state.error == UserFacingError(kind: .offline))
    }
}

// MARK: - Sort and filters

@Suite("Collection sort and filters")
struct CollectionSortAndFilterTests {
    @Test("The sort options map to the Storefront sort keys")
    func sortMapping() {
        #expect(CollectionSortOption.allCases == [.recommended, .bestSelling, .priceAscending, .priceDescending, .newest])
        #expect(CollectionSortOption.allCases.map(\.sortKey) == [.collectionDefault, .bestSelling, .price, .price, .created])
        #expect(CollectionSortOption.allCases.map(\.reverse) == [false, false, false, true, true])
    }

    @Test("The German sort titles match the shop")
    func sortTitles() throws {
        let german = try LocalizedStrings(language: "de", in: CatalogResources.bundle)

        #expect(CollectionSortOption.allCases.map { $0.title(in: german.bundle) } == [
            "Empfohlen", "Bestseller", "Preis aufsteigend", "Preis absteigend", "Neueste",
        ])
    }

    @Test("Filter values toggle on and off")
    func toggle() throws {
        var selection = CollectionFilterSelection.none
        let inStock = try #require(BrowseFixtures.availabilityFilter.values.first)

        selection.toggle(inStock)
        #expect(selection.contains(inStock))
        #expect(selection.inputs == [.available(true)])
        #expect(selection.count == 1)

        selection.toggle(inStock)
        #expect(selection.isEmpty)
    }

    @Test("A price range replaces the previous one and keeps its bounds in order")
    func priceRange() throws {
        var selection = CollectionFilterSelection(inputs: [.available(true)])

        selection.setPriceRange(minimum: 30, maximum: 10)
        let range = try #require(selection.priceRange)
        #expect(range.minimum == 10)
        #expect(range.maximum == 30)

        selection.setPriceRange(minimum: nil, maximum: 20)
        #expect(selection.inputs == [.available(true), .price(minimum: nil, maximum: 20)])

        selection.setPriceRange(minimum: nil, maximum: nil)
        #expect(selection.inputs == [.available(true)])

        selection.removeAll()
        #expect(selection == .none)
    }

    @Test("A selection keeps every input once")
    func uniqueInputs() {
        let selection = CollectionFilterSelection(inputs: [.available(true), .available(true)])

        #expect(selection.count == 1)
    }
}

// MARK: - Collection view model

@Suite("Collection view model")
@MainActor
struct CollectionViewModelTests {
    @Test("The first page loads with the default order and no filters")
    func firstPage() async {
        let catalog = BrowseStubCatalogRepository { request in
            BrowseFixtures.page(
                request.handle,
                products: BrowseFixtures.products("p", count: 2),
                filters: [BrowseFixtures.availabilityFilter]
            )
        }
        let model = CollectionViewModel(handle: "windows", title: "Windows", catalog: catalog)
        #expect(model.title == "Windows")

        await model.load()

        let request = await catalog.collectionRequests.first
        #expect(request == BrowseCollectionRequest(
            handle: "windows",
            first: CollectionViewModel.pageSize,
            after: nil,
            sortKey: .collectionDefault,
            reverse: false,
            filters: []
        ))
        #expect(model.state.value?.products.count == 2)
        #expect(model.state.value?.filters == [BrowseFixtures.availabilityFilter])
        #expect(model.title == "windows")
    }

    @Test("Further pages are requested with the cursor and appended without duplicates")
    func pagination() async throws {
        let catalog = BrowseStubCatalogRepository { request in
            switch request.after {
            case nil:
                BrowseFixtures.page(request.handle, products: BrowseFixtures.products("p", count: 3), nextCursor: "c1")
            case "c1":
                BrowseFixtures.page(request.handle, products: [BrowseFixtures.product("p-3"), BrowseFixtures.product("p-4")])
            default:
                nil
            }
        }
        let model = CollectionViewModel(handle: "windows", title: nil, catalog: catalog)
        await model.load()
        #expect(model.state.value?.hasMore == true)

        let last = try #require(model.state.value?.products.last)
        await model.loadMoreIfNeeded(after: last)

        #expect(model.state.value?.products.map(\.handle) == ["p-1", "p-2", "p-3", "p-4"])
        #expect(model.state.value?.hasMore == false)
        #expect(await catalog.collectionRequests.map(\.after) == [nil, "c1"])

        await model.loadMore()
        #expect(await catalog.collectionRequests.count == 2)
    }

    @Test("Only products near the end request the next page")
    func prefetchDistance() async throws {
        let catalog = BrowseStubCatalogRepository { request in
            BrowseFixtures.page(
                request.handle,
                products: BrowseFixtures.products("p", count: 20),
                nextCursor: request.after == nil
                    ? "c1"
                    : nil
            )
        }
        let model = CollectionViewModel(handle: "windows", title: nil, catalog: catalog)
        await model.load()

        let first = try #require(model.state.value?.products.first)
        await model.loadMoreIfNeeded(after: first)

        #expect(await catalog.collectionRequests.count == 1)
    }

    @Test("Changing the sort order reloads the first page with the new sort key")
    func sorting() async {
        let catalog = BrowseStubCatalogRepository { request in
            BrowseFixtures.page(request.handle, products: [BrowseFixtures.product(request.sortKey.rawValue)])
        }
        let model = CollectionViewModel(handle: "office", title: nil, catalog: catalog)
        await model.load()

        await model.setSort(.priceDescending)
        await model.setSort(.priceDescending)

        let requests = await catalog.collectionRequests
        #expect(requests.count == 2)
        #expect(requests.last?.sortKey == .price)
        #expect(requests.last?.reverse == true)
        #expect(requests.last?.after == nil)
        #expect(model.sort == .priceDescending)
        #expect(model.state.value?.products.map(\.handle) == ["PRICE"])
    }

    @Test("Applied filters are sent back to Shopify unchanged and can be reset")
    func filters() async {
        let catalog = BrowseStubCatalogRepository { request in
            BrowseFixtures.page(request.handle, products: request.filters.isEmpty ? [BrowseFixtures.product("all")] : [])
        }
        let model = CollectionViewModel(handle: "windows", title: nil, catalog: catalog)
        await model.load()

        await model.apply(CollectionFilterSelection(inputs: [.available(true)]))
        #expect(await catalog.collectionRequests.last?.filters == [.available(true)])
        #expect(model.selection.count == 1)
        #expect(model.state.value?.products.isEmpty == true)

        await model.resetFilters()
        #expect(await catalog.collectionRequests.last?.filters == [])
        #expect(model.state.value?.products.map(\.handle) == ["all"])
    }

    @Test("A missing collection is reported as not found")
    func notFound() async {
        let model = CollectionViewModel(handle: "gone", title: nil, catalog: BrowseStubCatalogRepository())

        await model.load()

        #expect(model.state.error == UserFacingError(kind: .notFound))
    }

    @Test("A failing next page keeps the products and reports the error")
    func loadMoreFailure() async {
        let catalog = BrowseStubCatalogRepository { request in
            if request.after != nil {
                throw ShopifyError.network(.timeout)
            }
            return BrowseFixtures.page(request.handle, products: [BrowseFixtures.product("p")], nextCursor: "c1")
        }
        let model = CollectionViewModel(handle: "windows", title: nil, catalog: catalog)
        await model.load()

        await model.loadMore()

        #expect(model.state.value?.products.count == 1)
        #expect(model.loadMoreError == UserFacingError(kind: .timeout))
        #expect(model.isLoadingMore == false)
    }

    @Test("A failing reload keeps the products and reports the error")
    func reloadFailure() async {
        let catalog = BrowseStubCatalogRepository { request in
            BrowseFixtures.page(request.handle, products: [BrowseFixtures.product("p")])
        }
        let model = CollectionViewModel(handle: "windows", title: nil, catalog: catalog)
        await model.load()

        await catalog.setCollectionHandler { _ in throw ShopifyError.http(statusCode: 503) }
        await model.setSort(.newest)

        #expect(model.state.value?.products.count == 1)
        #expect(model.reloadError == UserFacingError(kind: .server))
        #expect(model.isReloading == false)
    }

    @Test("An answer for an outdated sort order is dropped")
    func staleAnswer() async {
        let catalog = BrowseStubCatalogRepository { request in
            if request.sortKey == .bestSelling {
                try? await Task.sleep(for: .milliseconds(200))
            }
            return BrowseFixtures.page(request.handle, products: [BrowseFixtures.product(request.sortKey.rawValue)])
        }
        let model = CollectionViewModel(handle: "windows", title: nil, catalog: catalog)
        await model.load()

        let slow = Task { await model.setSort(.bestSelling) }
        try? await Task.sleep(for: .milliseconds(50))
        await model.setSort(.newest)
        await slow.value

        #expect(model.sort == .newest)
        #expect(model.state.value?.products.map(\.handle) == ["CREATED"])
    }
}

// MARK: - Recent searches

@Suite("Recent searches")
struct RecentSearchesTests {
    @Test("The newest search comes first and a repeated search moves to the front")
    func ordering() {
        let recents = RecentSearches(store: InMemoryKeyValueStore())

        recents.add("Office")
        recents.add("Windows")
        let entries = recents.add("  office ")

        #expect(entries == ["office", "Windows"])
        #expect(recents.load() == ["office", "Windows"])
    }

    @Test("At most 8 searches are kept")
    func limit() {
        let recents = RecentSearches(store: InMemoryKeyValueStore())

        for index in 1...10 {
            recents.add("query \(index)")
        }

        #expect(recents.load().count == 8)
        #expect(recents.load().first == "query 10")
        #expect(recents.load().last == "query 3")
    }

    @Test("Blank searches are ignored, entries can be removed and cleared")
    func removal() {
        let store = InMemoryKeyValueStore()
        let recents = RecentSearches(store: store)

        recents.add("   ")
        #expect(recents.load().isEmpty)

        recents.add("Office")
        recents.add("Visio")
        #expect(recents.remove("Office") == ["Visio"])

        recents.clear()
        #expect(recents.load().isEmpty)
        #expect(store.data(forKey: RecentSearches.key) == nil)
    }

    @Test("Unreadable stored data counts as no searches")
    func corruptData() {
        let store = InMemoryKeyValueStore()
        store.set(Data("not json".utf8), forKey: RecentSearches.key)

        #expect(RecentSearches(store: store).load().isEmpty)
    }
}

// MARK: - Search view model

@Suite("Search view model")
@MainActor
struct SearchViewModelTests {
    private nonisolated static let result = PredictiveSearchResult(
        products: [BrowseFixtures.product("office-2024")],
        collections: [BrowseFixtures.collection("microsoft-office")],
        articles: [BrowseFixtures.article("aktivierung")],
        queries: [SearchQuerySuggestion(text: "office 2024")]
    )

    @Test("Typing waits for a pause and only requests the last text")
    func debounce() async {
        let search = BrowseStubSearchRepository(predictive: { _ in Self.result })
        let model = SearchViewModel(search: search, preferences: InMemoryKeyValueStore(), debounce: .milliseconds(50))

        model.queryChanged("o")
        model.queryChanged("of")
        model.queryChanged("off ")
        #expect(model.predictive.isLoading)
        await model.waitForPredictive()

        #expect(await search.predictiveQueries == ["off"])
        #expect(model.activeQuery == "off")
        #expect(model.predictive.value == Self.result)
    }

    @Test("The standard pause is 250 ms")
    func standardDebounce() {
        #expect(SearchViewModel.standardDebounce == .milliseconds(250))
    }

    @Test("An answer for an outdated text is dropped")
    func outdatedAnswer() async {
        let search = BrowseStubSearchRepository(predictive: { _ in
            try? await Task.sleep(for: .milliseconds(150))
            return Self.result
        })
        let model = SearchViewModel(search: search, preferences: InMemoryKeyValueStore(), debounce: .zero)

        model.queryChanged("office")
        while await search.predictiveQueries.isEmpty {
            await Task.yield()
        }
        model.queryChanged("")
        await model.waitForPredictive()
        try? await Task.sleep(for: .milliseconds(200))

        #expect(model.predictive == .idle)
        #expect(model.activeQuery.isEmpty)
    }

    @Test("A blank text clears the results without a request")
    func blankText() async {
        let search = BrowseStubSearchRepository(predictive: { _ in Self.result })
        let model = SearchViewModel(search: search, preferences: InMemoryKeyValueStore(), debounce: .zero)

        model.queryChanged("   ")
        await model.waitForPredictive()

        #expect(model.predictive == .idle)
        #expect(await search.predictiveQueries.isEmpty)
    }

    @Test("A failed request shows the error and a retry repeats it")
    func failureAndRetry() async {
        let search = BrowseStubSearchRepository(predictive: { _ in throw ShopifyError.network(.offline) })
        let model = SearchViewModel(search: search, preferences: InMemoryKeyValueStore(), debounce: .zero)

        model.queryChanged("windows")
        await model.waitForPredictive()
        #expect(model.predictive.error == UserFacingError(kind: .offline))

        await search.setPredictiveHandler { _ in .empty }
        await model.retry()

        #expect(model.predictive == .loaded(.empty))
        #expect(await search.predictiveQueries == ["windows", "windows"])
    }

    @Test("Submitting records the trimmed search; recent searches persist and can be cleared")
    func submitAndRecents() {
        let preferences = InMemoryKeyValueStore()
        let model = SearchViewModel(search: BrowseStubSearchRepository(), preferences: preferences)

        #expect(model.submit("  Windows 11 Pro ") == "Windows 11 Pro")
        #expect(model.submit("   ") == nil)
        #expect(model.recentSearches == ["Windows 11 Pro"])

        let reopened = SearchViewModel(search: BrowseStubSearchRepository(), preferences: preferences)
        #expect(reopened.recentSearches == ["Windows 11 Pro"])

        reopened.removeRecent("Windows 11 Pro")
        #expect(reopened.recentSearches.isEmpty)

        model.submit("Office")
        model.clearRecent()
        #expect(model.recentSearches.isEmpty)
        #expect(RecentSearches(store: preferences).load().isEmpty)
    }
}

// MARK: - Search results view model

@Suite("Search results view model")
@MainActor
struct SearchResultsViewModelTests {
    @Test("Results load by relevance and further pages are appended")
    func pagination() async {
        let search = BrowseStubSearchRepository(products: { request in
            if request.after == nil {
                BrowseFixtures.searchPage(products: BrowseFixtures.products("r", count: 2), totalCount: 3, nextCursor: "c1")
            } else {
                BrowseFixtures.searchPage(products: [BrowseFixtures.product("r-3")], totalCount: 3)
            }
        })
        let model = SearchResultsViewModel(query: " office ", search: search)

        await model.load()
        #expect(model.query == "office")
        #expect(model.state.value?.totalCount == 3)

        await model.loadMore()

        #expect(model.state.value?.products.map(\.handle) == ["r-1", "r-2", "r-3"])
        #expect(model.state.value?.hasMore == false)
        let requests = await search.productRequests
        #expect(requests.map(\.after) == [nil, "c1"])
        #expect(requests.allSatisfy { $0.query == "office" && $0.sortKey == .relevance && !$0.reverse })
    }

    @Test("The sort options map to the Storefront search sort keys")
    func sorting() async {
        #expect(SearchResultSortOption.allCases.map(\.sortKey) == [.relevance, .price, .price])
        #expect(SearchResultSortOption.allCases.map(\.reverse) == [false, false, true])

        let search = BrowseStubSearchRepository(products: { _ in
            BrowseFixtures.searchPage(products: [BrowseFixtures.product("r")], totalCount: 1)
        })
        let model = SearchResultsViewModel(query: "office", search: search)
        await model.load()
        await model.setSort(.priceAscending)

        let last = await search.productRequests.last
        #expect(last?.sortKey == .price)
        #expect(last?.reverse == false)
        #expect(model.sort == .priceAscending)
    }

    @Test("Nothing found is a loaded result without products, a failure the error state")
    func emptyAndFailure() async {
        let empty = SearchResultsViewModel(query: "zzz", search: BrowseStubSearchRepository())
        await empty.load()
        #expect(empty.state.value?.products.isEmpty == true)
        #expect(empty.state.value?.totalCount == 0)

        let failing = SearchResultsViewModel(
            query: "office",
            search: BrowseStubSearchRepository(products: { _ in throw ShopifyError.throttled })
        )
        await failing.load()
        #expect(failing.state.error == UserFacingError(kind: .throttled))
    }
}

// MARK: - Search content

@Suite("Search content")
struct SearchContentTests {
    @Test("The suggested queries are the four product families of PROMPT.md")
    func suggestions() throws {
        let german = try LocalizedStrings(language: "de", in: SearchResources.bundle)

        #expect(SearchSuggestion.allCases.map { $0.query(in: german.bundle) } == [
            "Office 2024", "Windows 11 Pro", "Windows Server", "Visual Studio",
        ])
    }

    @Test("The category shortcuts open the live collections")
    func categories() throws {
        let german = try LocalizedStrings(language: "de", in: SearchResources.bundle)

        #expect(SearchCategoryShortcut.allCases.map(\.handle) == [
            "windows", "microsoft-office", "windows-server", "visual-studio-entwicklungstools", "sale",
        ])
        #expect(SearchCategoryShortcut.allCases.map { $0.title(in: german.bundle) } == [
            "Windows", "Office", "Server", "Entwicklung", "Angebote",
        ])
    }
}

// MARK: - Strings

@Suite("Catalog and search strings")
struct CatalogAndSearchStringTests {
    @Test("The tab titles resolve in every language without dashes", arguments: appLanguages)
    func tabTitles(language: String) throws {
        let catalog = try LocalizedStrings(language: language, in: CatalogResources.bundle)
        let search = try LocalizedStrings(language: language, in: SearchResources.bundle)

        for (key, text) in [("catalog.title", catalog("catalog.title")), ("search.title", search("search.title"))] {
            #expect(text != key, "\(key) has no \(language) value")
            #expect(!containsForbiddenDash(text), "Dash in \(key)")
        }
    }

    @Test("The German tab titles are Shop and Suche")
    func germanTitles() throws {
        #expect(try LocalizedStrings(language: "de", in: CatalogResources.bundle)("catalog.title") == "Shop")
        #expect(try LocalizedStrings(language: "de", in: SearchResources.bundle)("search.title") == "Suche")
    }

    @Test("The browse texts resolve without dashes", arguments: ["de", "en"])
    func browseTexts(language: String) throws {
        let catalog = try LocalizedStrings(language: language, in: CatalogResources.bundle)
        let search = try LocalizedStrings(language: language, in: SearchResources.bundle)
        let catalogKeys = [
            "catalog.collections.empty.title", "catalog.collections.empty.message",
            "catalog.featured.eyebrow", "catalog.featured.title", "catalog.more.eyebrow", "catalog.more.title",
            "catalog.collection.hint", "catalog.loading", "catalog.loading_more", "catalog.load_more.error",
            "catalog.sort.title", "catalog.filter.title", "catalog.filter.cancel", "catalog.filter.reset",
            "catalog.filter.reset_all", "catalog.filter.apply", "catalog.filter.unavailable",
            "catalog.filter.price.minimum", "catalog.filter.price.maximum",
            "catalog.collection.empty.title", "catalog.collection.empty.message",
            "catalog.collection.filtered_empty.title", "catalog.collection.filtered_empty.message",
        ]
        let searchKeys = [
            "search.prompt", "search.recent.title", "search.recent.clear", "search.recent.remove",
            "search.suggested.title", "search.categories.title", "search.section.products",
            "search.section.collections", "search.section.articles", "search.section.suggestions",
            "search.show_all_results", "search.no_results.title", "search.sort.title", "search.loading",
            "search.loading_more", "search.load_more.error",
        ]

        for (key, text) in catalogKeys.map({ ($0, catalog($0)) }) + searchKeys.map({ ($0, search($0)) }) {
            #expect(text != key, "\(key) has no \(language) value")
            #expect(!containsForbiddenDash(text), "Dash in \(key)")
        }
    }
}
