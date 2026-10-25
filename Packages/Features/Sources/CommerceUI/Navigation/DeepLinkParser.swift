import Foundation
import ShopifyKit

// MARK: - DeepLinkParser

/// Turns custom-scheme links and store web URLs into ``CommerceRoute``s. Pure and stateless.
///
/// Custom scheme `karinex`:
///
/// | URL | Route |
/// | --- | --- |
/// | `karinex://product/<handle>` | `.product(handle:)` |
/// | `karinex://collection/<handle>` | `.collection(handle:title: nil)` |
/// | `karinex://article/<blog>/<article>` | `.article(blogHandle:articleHandle:)` |
/// | `karinex://search?q=<query>` | `.search(query:)` |
/// | `karinex://cart` | `.cart` |
/// | `karinex://account` | `.account(.overview)` |
/// | `karinex://account/orders` | `.account(.orders)` |
/// | `karinex://account/orders/<number>` | `.account(.order(id:))` |
/// | `karinex://account/licenses` | `.account(.licenses(orderID: nil))` |
///
/// Web URLs on `karinex.de` and `www.karinex.de` (http or https), with an optional Shopify
/// locale prefix such as `/fr` or `/de-ch`:
/// `/products/<handle>`, `/collections/<handle>`, `/collections/<collection>/products/<handle>`,
/// `/blogs/<blog>/<article>`, `/cart`, `/search?q=<query>`, `/account` and
/// `/account/orders/<number>`.
///
/// Everything else returns `nil`, so the caller can open the URL in the browser or ignore it.
/// Handles are lowercased and must consist of letters, digits, `-` and `_`.
public enum DeepLinkParser {
    /// The custom URL scheme of the app.
    public static let scheme = "karinex"
    /// The store web hosts whose links the app opens.
    public static let webHosts: Set<String> = ["karinex.de", "www.karinex.de"]

    /// The route for `url`, or `nil` when the app has no screen for it.
    public static func route(for url: URL) -> CommerceRoute? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased()
        else { return nil }
        switch scheme {
        case Self.scheme:
            return customSchemeRoute(components)
        case "http", "https":
            guard let host = components.host?.lowercased(), webHosts.contains(host) else { return nil }
            return webRoute(components)
        default:
            return nil
        }
    }

    // MARK: Custom scheme

    private static func customSchemeRoute(_ components: URLComponents) -> CommerceRoute? {
        guard let host = components.host?.lowercased() else { return nil }
        let path = pathSegments(components)
        switch (host, path.count) {
        case ("product", 1):
            return handle(path[0]).map { .product(handle: $0) }
        case ("collection", 1):
            return handle(path[0]).map { .collection(handle: $0, title: nil) }
        case ("article", 2):
            guard let blog = handle(path[0]), let article = handle(path[1]) else { return nil }
            return .article(blogHandle: blog, articleHandle: article)
        case ("search", 0):
            return .search(query: searchQuery(components))
        case ("cart", 0):
            return .cart
        case ("account", _):
            return accountRoute(Array(path))
        default:
            return nil
        }
    }

    /// `account`, `account/orders`, `account/orders/<number>` and `account/licenses` (the path
    /// after `account`).
    private static func accountRoute(_ path: [String]) -> CommerceRoute? {
        switch path.map({ $0.lowercased() }) {
        case []:
            .account(.overview)
        case ["orders"]:
            .account(.orders)
        case let segments where segments.count == 2 && segments[0] == "orders":
            orderID(segments[1]).map { .account(.order(id: $0)) }
        case ["licenses"]:
            .account(.licenses(orderID: nil))
        default:
            nil
        }
    }

    /// The order GID for a numeric order ID, e.g. `5678`.
    static func orderID(_ segment: String) -> ShopifyID? {
        guard !segment.isEmpty, segment.count <= 20, segment.unicodeScalars.allSatisfy({ ("0"..."9").contains($0) }) else {
            return nil
        }
        return ShopifyID("gid://shopify/Order/\(segment)")
    }

    // MARK: Web

    private static func webRoute(_ components: URLComponents) -> CommerceRoute? {
        var path = pathSegments(components)
        if let first = path.first, isLocalePrefix(first) {
            path.removeFirst()
        }
        guard let first = path.first?.lowercased() else { return nil }
        switch (first, path.count) {
        case ("products", 2):
            return handle(path[1]).map { .product(handle: $0) }
        case ("collections", 2):
            return handle(path[1]).map { .collection(handle: $0, title: nil) }
        case ("collections", 4) where path[2].lowercased() == "products":
            guard handle(path[1]) != nil else { return nil }
            return handle(path[3]).map { .product(handle: $0) }
        case ("blogs", 3):
            guard let blog = handle(path[1]), let article = handle(path[2]) else { return nil }
            return .article(blogHandle: blog, articleHandle: article)
        case ("cart", 1):
            return .cart
        case ("search", 1):
            return .search(query: searchQuery(components))
        case ("account", _):
            return accountRoute(Array(path.dropFirst()))
        default:
            return nil
        }
    }

    // MARK: Helpers

    /// The non-empty, percent-decoded path segments.
    private static func pathSegments(_ components: URLComponents) -> [String] {
        components.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
    }

    /// The trimmed `q` query item, or an empty string. A `+` counts as a space, as in web forms.
    private static func searchQuery(_ components: URLComponents) -> String {
        let encoded = components.percentEncodedQueryItems?.first { $0.name == "q" }?.value ?? ""
        let value = encoded.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? ""
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether `segment` is a Shopify locale prefix: a two-letter language, optionally followed
    /// by a hyphen and a two-letter region (`fr`, `en`, `de-ch`, `pt-pt`).
    static func isLocalePrefix(_ segment: String) -> Bool {
        let parts = segment.lowercased().split(separator: "-", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count) else { return false }
        return parts.allSatisfy { part in
            part.count == 2 && part.unicodeScalars.allSatisfy { ("a"..."z").contains($0) }
        }
    }

    /// `segment` lowercased when it is a valid handle (letters, digits, `-`, `_`), else `nil`.
    static func handle(_ segment: String) -> String? {
        let candidate = segment.lowercased()
        guard !candidate.isEmpty, candidate.count <= 255 else { return nil }
        let isValid = candidate.unicodeScalars.allSatisfy { scalar in
            CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_"
        }
        return isValid ? candidate : nil
    }
}
