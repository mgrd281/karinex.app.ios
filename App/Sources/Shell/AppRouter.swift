import CommerceUI
import Foundation
import Observation

// MARK: - AppRouter

/// The navigation state of the root view: the selected tab and one navigation path per tab.
///
/// Features never push each other's screens. They hand ``CommerceRoute`` values to their
/// `onRoute` closures, and the router decides what happens (``action(for:)``): most routes are
/// pushed onto the stack of the tab they came from, `.cart` switches to the Warenkorb tab and an
/// empty search switches to the Suche tab. Deep links and Universal Links select the tab that
/// owns the destination (``tab(forDeepLink:)``) and show the destination on top of its root.
@MainActor
@Observable
final class AppRouter {
    /// What a route does.
    enum Action: Equatable, Sendable {
        /// Push the route onto the current tab's navigation stack.
        case push(CommerceRoute)
        /// Switch to a tab and show its root screen.
        case selectTab(AppTab)
    }

    /// The selected tab.
    var selectedTab: AppTab
    /// The navigation path of every tab; tabs without an entry show their root screen.
    private(set) var paths: [AppTab: [CommerceRoute]] = [:]

    /// Creates the router with `selectedTab` selected and every tab at its root.
    init(selectedTab: AppTab = .home) {
        self.selectedTab = selectedTab
    }

    // MARK: Paths

    /// The navigation path of `tab`.
    func path(for tab: AppTab) -> [CommerceRoute] {
        paths[tab] ?? []
    }

    /// Replaces the navigation path of `tab`, e.g. when the navigation stack pops.
    func setPath(_ path: [CommerceRoute], for tab: AppTab) {
        paths[tab] = path
    }

    // MARK: Routes

    /// What `route` does when a screen asks for it.
    static func action(for route: CommerceRoute) -> Action {
        switch route {
        case .cart:
            .selectTab(.cart)
        case let .search(query) where query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty:
            .selectTab(.search)
        case .product, .collection, .article, .search:
            .push(route)
        }
    }

    /// Handles a route requested by a screen of `tab`.
    func open(_ route: CommerceRoute, from tab: AppTab) {
        switch Self.action(for: route) {
        case let .push(destination):
            paths[tab, default: []].append(destination)
        case let .selectTab(target):
            select(target, popToRoot: true)
        }
    }

    /// Switches to `tab`, optionally showing its root screen.
    func select(_ tab: AppTab, popToRoot: Bool = false) {
        if popToRoot {
            paths[tab] = []
        }
        selectedTab = tab
    }

    // MARK: Deep links

    /// The tab that shows a deep-linked destination: products and collections in Shop,
    /// articles in Start, searches in Suche, the cart in Warenkorb.
    static func tab(forDeepLink route: CommerceRoute) -> AppTab {
        switch route {
        case .product, .collection:
            .shop
        case .article:
            .home
        case .search:
            .search
        case .cart:
            .cart
        }
    }

    /// Opens a deep link or Universal Link: selects the tab that owns the destination and shows
    /// the destination on top of that tab's root screen.
    ///
    /// - Returns: Whether the app has a screen for `url` (``DeepLinkParser``); unknown links are
    ///   ignored.
    @discardableResult
    func openDeepLink(_ url: URL) -> Bool {
        guard let route = DeepLinkParser.route(for: url) else { return false }
        openDeepLink(route)
        return true
    }

    /// Shows `route` as a deep link destination.
    func openDeepLink(_ route: CommerceRoute) {
        let tab = Self.tab(forDeepLink: route)
        switch Self.action(for: route) {
        case let .push(destination):
            paths[tab] = [destination]
            selectedTab = tab
        case let .selectTab(target):
            select(target, popToRoot: true)
        }
    }

    // MARK: Checkout

    /// After the success screen of a checkout ("Weiter einkaufen"): back to the Start tab, with
    /// the cart tab at its root.
    func finishCheckout() {
        paths[.cart] = []
        select(.home, popToRoot: true)
    }
}
