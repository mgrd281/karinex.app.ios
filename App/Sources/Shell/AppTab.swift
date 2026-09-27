import Foundation

// MARK: - AppTab

/// The tabs of the root tab bar, in display order: Start, Shop, Suche, Warenkorb, Konto
/// (PROMPT.md section 6).
///
/// The selection is state of the root view, so screens can switch tabs through closures they
/// receive, for example the hero call to action and the empty cart open ``shop``.
enum AppTab: String, CaseIterable, Hashable, Identifiable, Sendable {
    /// Start: the editorial home screen.
    case home
    /// Shop: the catalog.
    case shop
    /// Suche: search.
    case search
    /// Warenkorb: the cart.
    case cart
    /// Konto: the account.
    case account

    /// Stable identity for `ForEach`.
    var id: String {
        rawValue
    }

    /// SF Symbol of the tab bar item.
    var systemImage: String {
        switch self {
        case .home: "house"
        case .shop: "square.grid.2x2"
        case .search: "magnifyingglass"
        case .cart: "bag"
        case .account: "person.crop.circle"
        }
    }

    /// Accessibility identifier of the tab bar item for UI tests, e.g. `tab.home`.
    var accessibilityIdentifier: String {
        "tab.\(rawValue)"
    }

    /// The tab title in the user's language, from the app's String Catalog.
    var title: String {
        String(localized: titleKey)
    }

    /// The tab title resolved against `bundle`, one of the app's `.lproj` folders. Tests use it
    /// to check a specific language independent of the simulator language.
    func title(in bundle: Bundle) -> String {
        String(localized: titleKey, bundle: bundle)
    }

    private var titleKey: String.LocalizationValue {
        switch self {
        case .home: "tab.home"
        case .shop: "tab.shop"
        case .search: "tab.search"
        case .cart: "tab.cart"
        case .account: "tab.account"
        }
    }
}
