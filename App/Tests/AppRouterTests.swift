import CommerceUI
import Core
import Foundation
@testable import KARINEX
import Testing

// MARK: - AppRouter

@MainActor
@Suite("AppRouter")
struct AppRouterTests {
    @Test("Store destinations are pushed, the cart and an empty search switch tabs")
    func actions() {
        #expect(AppRouter.action(for: .product(handle: "windows-11-pro")) == .push(.product(handle: "windows-11-pro")))
        #expect(AppRouter.action(for: .collection(handle: "sale", title: "Angebote"))
            == .push(.collection(handle: "sale", title: "Angebote")))
        #expect(AppRouter.action(for: .article(blogHandle: "guides", articleHandle: "office"))
            == .push(.article(blogHandle: "guides", articleHandle: "office")))
        #expect(AppRouter.action(for: .search(query: "Office")) == .push(.search(query: "Office")))
        #expect(AppRouter.action(for: .search(query: "  ")) == .selectTab(.search))
        #expect(AppRouter.action(for: .cart) == .selectTab(.cart))
    }

    @Test("A route is pushed onto the stack of the tab it came from")
    func pushesOntoOwnTab() {
        let router = AppRouter()

        router.open(.collection(handle: "windows", title: "Windows"), from: .home)
        router.open(.product(handle: "windows-11-pro"), from: .home)
        router.open(.product(handle: "office-2024"), from: .shop)

        #expect(router.selectedTab == .home)
        #expect(router.path(for: .home) == [.collection(handle: "windows", title: "Windows"), .product(handle: "windows-11-pro")])
        #expect(router.path(for: .shop) == [.product(handle: "office-2024")])
        #expect(router.path(for: .search).isEmpty)
    }

    @Test("The cart route switches to the Warenkorb tab at its root")
    func cartSwitchesTab() {
        let router = AppRouter()
        router.setPath([.product(handle: "x")], for: .cart)
        router.open(.product(handle: "windows-11-pro"), from: .home)

        router.open(.cart, from: .home)

        #expect(router.selectedTab == .cart)
        #expect(router.path(for: .cart).isEmpty)
        #expect(router.path(for: .home) == [.product(handle: "windows-11-pro")], "The previous tab keeps its stack")
    }

    @Test("The search field of Start opens Suche at its root and asks for the cursor in the field")
    func searchFieldRequest() {
        let router = AppRouter()
        router.setPath([.search(query: "Office")], for: .search)

        router.open(.search(query: ""), from: .home)

        #expect(router.selectedTab == .search)
        #expect(router.path(for: .search).isEmpty)
        #expect(router.searchFieldRequests == 1)

        router.open(.product(handle: "windows-11-pro"), from: .search)
        router.open(.cart, from: .search)
        #expect(router.searchFieldRequests == 1, "Only the empty search asks for the field")
    }

    @Test("The navigation stack writes its path back when it pops")
    func setPath() {
        let router = AppRouter()
        router.open(.product(handle: "a"), from: .shop)
        router.open(.product(handle: "b"), from: .shop)

        router.setPath([.product(handle: "a")], for: .shop)

        #expect(router.path(for: .shop) == [.product(handle: "a")])
    }

    @Test("Deep links open in the tab that owns the destination")
    func deepLinkTabs() {
        #expect(AppRouter.tab(forDeepLink: .product(handle: "x")) == .shop)
        #expect(AppRouter.tab(forDeepLink: .collection(handle: "x", title: nil)) == .shop)
        #expect(AppRouter.tab(forDeepLink: .article(blogHandle: "b", articleHandle: "a")) == .home)
        #expect(AppRouter.tab(forDeepLink: .search(query: "x")) == .search)
        #expect(AppRouter.tab(forDeepLink: .cart) == .cart)
    }

    @Test("A product deep link selects Shop and shows the product on top of its root")
    func productDeepLink() throws {
        let router = AppRouter()
        router.open(.collection(handle: "windows", title: nil), from: .shop)
        let url = try #require(URL(string: "karinex://product/office-2024-professional-plus-key"))

        #expect(router.openDeepLink(url))

        #expect(router.selectedTab == .shop)
        #expect(router.path(for: .shop) == [.product(handle: "office-2024-professional-plus-key")])
    }

    @Test("Universal Links with a locale prefix are understood")
    func universalLink() throws {
        let router = AppRouter()
        let url = try #require(URL(string: "https://www.karinex.de/fr/blogs/guides/office-aktivieren"))

        #expect(router.openDeepLink(url))

        #expect(router.selectedTab == .home)
        #expect(router.path(for: .home) == [.article(blogHandle: "guides", articleHandle: "office-aktivieren")])
    }

    @Test("Search and cart deep links switch to their tabs")
    func searchAndCartDeepLinks() throws {
        let router = AppRouter()
        let search = try #require(URL(string: "karinex://search?q=Office+2024"))
        let emptySearch = try #require(URL(string: "karinex://search"))
        let cart = try #require(URL(string: "https://karinex.de/cart"))

        #expect(router.openDeepLink(search))
        #expect(router.selectedTab == .search)
        #expect(router.path(for: .search) == [.search(query: "Office 2024")])

        #expect(router.openDeepLink(emptySearch))
        #expect(router.selectedTab == .search)
        #expect(router.path(for: .search).isEmpty)

        #expect(router.openDeepLink(cart))
        #expect(router.selectedTab == .cart)
    }

    @Test("Unknown links are ignored")
    func unknownLinks() throws {
        let router = AppRouter()
        let foreign = try #require(URL(string: "https://example.com/products/x"))
        let unknown = try #require(URL(string: "karinex://unknown/x"))

        #expect(!router.openDeepLink(foreign))
        #expect(!router.openDeepLink(unknown))

        #expect(router.selectedTab == .home)
        #expect(router.paths.isEmpty)
    }

    @Test("After a completed checkout the Start tab is shown and the cart tab is at its root")
    func finishCheckout() {
        let router = AppRouter(selectedTab: .shop)
        router.open(.product(handle: "a"), from: .home)
        router.setPath([.product(handle: "b")], for: .cart)

        router.finishCheckout()

        #expect(router.selectedTab == .home)
        #expect(router.path(for: .home).isEmpty)
        #expect(router.path(for: .cart).isEmpty)
    }
}

// MARK: - MarketConfirmationPolicy

@Suite("Market confirmation policy")
struct MarketConfirmationPolicyTests {
    @Test("Normal launches may show the sheet")
    func normalLaunch() {
        #expect(MarketConfirmationPolicy.isEnabled(launchEnvironment: LaunchEnvironment(), arguments: ["KARINEX"]))
    }

    @Test("UI test launches show it only when asked to", arguments: [
        (["KARINEX", "-kx.uitesting"], false),
        (["KARINEX", "-kx.uitesting", "-kx.market.confirm", "YES"], true),
        (["KARINEX", "-kx.uitesting", "-kx.market.confirm", "true"], true),
        (["KARINEX", "-kx.uitesting", "-kx.market.confirm", "NO"], false),
        (["KARINEX", "-kx.uitesting", "-kx.market.confirm"], true),
        (["KARINEX", "-kx.market.confirm", "-kx.uitesting"], true),
    ])
    func uiTestLaunch(arguments: [String], expected: Bool) {
        let environment = LaunchEnvironment(arguments: arguments)
        #expect(environment.isUITesting)
        #expect(MarketConfirmationPolicy.isEnabled(launchEnvironment: environment, arguments: arguments) == expected)
    }
}

// MARK: - Cart badge

@Suite("Cart tab badge")
struct CartBadgeTests {
    @Test("VoiceOver hears the number of items in German and English")
    func accessibilityValue() throws {
        let german = try localizationBundle("de")
        let english = try localizationBundle("en")

        #expect(AppTab.cartBadgeAccessibilityValue(count: 0, bundle: german).isEmpty)
        #expect(AppTab.cartBadgeAccessibilityValue(count: 1, bundle: german) == "1 Artikel")
        #expect(AppTab.cartBadgeAccessibilityValue(count: 3, bundle: german) == "3 Artikel")
        #expect(AppTab.cartBadgeAccessibilityValue(count: 1, bundle: english) == "1 item")
        #expect(AppTab.cartBadgeAccessibilityValue(count: 2, bundle: english) == "2 items")
    }

    /// The `.lproj` folder of `language` inside the app bundle (the test host).
    private func localizationBundle(_ language: String) throws -> Bundle {
        let path = try #require(Bundle.main.path(forResource: language, ofType: "lproj"))
        return try #require(Bundle(path: path))
    }
}
