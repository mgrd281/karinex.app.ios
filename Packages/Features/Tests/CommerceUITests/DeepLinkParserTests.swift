@testable import CommerceUI
import Foundation
import Testing

@Suite("DeepLinkParser")
struct DeepLinkParserTests {
    private func route(_ string: String) throws -> CommerceRoute? {
        try DeepLinkParser.route(for: #require(URL(string: string)))
    }

    // MARK: Custom scheme

    @Test("Custom scheme links", arguments: [
        ("karinex://product/office-2024-professional-plus-key", CommerceRoute.product(handle: "office-2024-professional-plus-key")),
        ("karinex://collection/windows", .collection(handle: "windows", title: nil)),
        ("karinex://article/guides/office-2024-installieren", .article(blogHandle: "guides", articleHandle: "office-2024-installieren")),
        ("karinex://search?q=office%202024", .search(query: "office 2024")),
        ("karinex://search?q=", .search(query: "")),
        ("karinex://search", .search(query: "")),
        ("karinex://cart", .cart),
        ("KARINEX://Product/Windows-11-Pro", .product(handle: "windows-11-pro")),
        ("karinex://product/windows-11-pro/", .product(handle: "windows-11-pro")),
    ])
    func customScheme(url: String, expected: CommerceRoute) throws {
        #expect(try route(url) == expected)
    }

    @Test("Unknown or malformed custom scheme links", arguments: [
        "karinex://",
        "karinex://product",
        "karinex://product/a/b",
        "karinex://article/guides",
        "karinex://orders/123",
        "karinex://cart/extra",
        "karinex://product/%3Cscript%3E",
        "karinex://product/..",
    ])
    func customSchemeUnknown(url: String) throws {
        #expect(try route(url) == nil)
    }

    // MARK: Web

    @Test("Store web URLs", arguments: [
        ("https://www.karinex.de/products/windows-11-pro", CommerceRoute.product(handle: "windows-11-pro")),
        ("https://karinex.de/products/windows-11-pro?variant=1", .product(handle: "windows-11-pro")),
        ("http://www.karinex.de/fr/products/windows-11-pro", .product(handle: "windows-11-pro")),
        ("https://www.karinex.de/de-ch/products/windows-11-pro", .product(handle: "windows-11-pro")),
        ("https://www.karinex.de/collections/microsoft-office", .collection(handle: "microsoft-office", title: nil)),
        ("https://www.karinex.de/en/collections/sale/products/office-2024", .product(handle: "office-2024")),
        (
            "https://www.karinex.de/blogs/guides/office-2024-installieren",
            .article(blogHandle: "guides", articleHandle: "office-2024-installieren")
        ),
        ("https://www.karinex.de/pt-pt/blogs/news/neu", .article(blogHandle: "news", articleHandle: "neu")),
        ("https://www.karinex.de/cart", .cart),
        ("https://www.karinex.de/search?q=windows+server", .search(query: "windows server")),
        ("https://www.karinex.de/search?q=c%2B%2B", .search(query: "c++")),
        ("https://www.karinex.de/search?q=windows%20server&type=product", .search(query: "windows server")),
        ("HTTPS://WWW.KARINEX.DE/PRODUCTS/Office", .product(handle: "office")),
    ])
    func web(url: String, expected: CommerceRoute) throws {
        #expect(try route(url) == expected)
    }

    @Test("Other web URLs are not routes", arguments: [
        "https://www.karinex.de/",
        "https://www.karinex.de/pages/impressum",
        "https://www.karinex.de/blogs/guides",
        "https://www.karinex.de/products",
        "https://www.karinex.de/account/orders/1",
        "https://www.karinex.de/collections/a/b",
        "https://shop.karinex.de/products/windows-11-pro",
        "https://karinex.de.example.com/products/windows-11-pro",
        "https://example.com/products/windows-11-pro",
        "ftp://www.karinex.de/products/windows-11-pro",
        "mailto:kundenservice@karinex.de",
    ])
    func webUnknown(url: String) throws {
        #expect(try route(url) == nil)
    }

    // MARK: Helpers

    @Test("Locale prefixes")
    func localePrefixes() {
        #expect(DeepLinkParser.isLocalePrefix("fr"))
        #expect(DeepLinkParser.isLocalePrefix("de-ch"))
        #expect(DeepLinkParser.isLocalePrefix("PT-PT"))
        #expect(!DeepLinkParser.isLocalePrefix("products"))
        #expect(!DeepLinkParser.isLocalePrefix("f"))
        #expect(!DeepLinkParser.isLocalePrefix("de-"))
        #expect(!DeepLinkParser.isLocalePrefix("12"))
    }

    @Test("Handles are lowercased and restricted to letters, digits, hyphen and underscore")
    func handles() {
        #expect(DeepLinkParser.handle("Office_2024-Pro") == "office_2024-pro")
        #expect(DeepLinkParser.handle("für-mac") == "für-mac")
        #expect(DeepLinkParser.handle("") == nil)
        #expect(DeepLinkParser.handle("a b") == nil)
        #expect(DeepLinkParser.handle("a.b") == nil)
    }
}
