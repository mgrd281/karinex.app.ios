import Foundation

// MARK: - AppTab

/// The tabs of the root tab bar, in display order: Shop, Suche, Start (the KARINEX wordmark in
/// the middle), Warenkorb, Konto (PROMPT.md section 6). The bar shows icons only, in the style
/// of fashion retail apps; the titles are the VoiceOver labels.
///
/// The selection is state of the root view, so screens can switch tabs through closures they
/// receive, for example the hero call to action and the empty cart open ``shop``.
enum AppTab: String, CaseIterable, Hashable, Identifiable, Sendable {
    /// Shop: the catalog.
    case shop
    /// Suche: search.
    case search
    /// Start: the home screen, shown as the wordmark in the middle of the bar.
    case home
    /// Warenkorb: the cart.
    case cart
    /// Konto: the account.
    case account

    /// Stable identity for `ForEach`.
    var id: String {
        rawValue
    }

    /// SF Symbol of the tab bar item, a thin line icon. Start shows the wordmark instead; its
    /// symbol is used where a symbol is needed (for example in previews of the bar).
    var systemImage: String {
        switch self {
        case .shop: "line.3.horizontal"
        case .search: "magnifyingglass"
        case .home: "house"
        case .cart: "basket"
        case .account: "person"
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

    /// The VoiceOver value of the Warenkorb tab: the number of items in the cart, e.g.
    /// "2 Artikel"; empty for an empty cart.
    static func cartBadgeAccessibilityValue(count: Int, bundle: Bundle = .main) -> String {
        guard count > 0 else { return "" }
        return String(localized: "tab.cart.badge \(count)", bundle: bundle)
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
