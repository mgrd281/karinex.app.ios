import Foundation

// MARK: - CommerceRoute

/// A destination in the store that any feature may ask for. Features never push each other's
/// screens: they call their `onRoute` closure with a route, and the App target, which owns the
/// `NavigationStack`s, maps it to a screen (`navigationDestination(for: CommerceRoute.self)`).
/// Deep links become routes through ``DeepLinkParser``.
public enum CommerceRoute: Hashable, Sendable {
    /// A product detail screen.
    case product(handle: String)
    /// A collection with its products. `title` is shown until the collection has loaded; deep
    /// links have none.
    case collection(handle: String, title: String?)
    /// A blog article.
    case article(blogHandle: String, articleHandle: String)
    /// Search results for `query`; an empty query opens the search screen.
    case search(query: String)
    /// The cart tab.
    case cart
    /// A screen of the account area.
    case account(AccountDestination)
    /// "Neuigkeiten": the messages behind the bell of the Start tab.
    case notifications
}
