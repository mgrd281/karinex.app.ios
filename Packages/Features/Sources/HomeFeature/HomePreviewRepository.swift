#if DEBUG
import Foundation
import ShopifyKit

// MARK: - HomePreviewRepository

/// Serves fixed sample content to the previews of this module, or fails every request.
///
/// The values are modelled on the live store (DE/DE); they exist for previews only and are
/// never shown in the app.
struct HomePreviewRepository: CatalogRepository, ContentRepository {
    /// Whether every request fails like a dropped connection.
    var fails = false

    func product(handle _: String) async throws -> Product? {
        nil
    }

    func collection(
        handle: String,
        first _: Int,
        after _: String?,
        sortKey _: ProductCollectionSortKeys,
        reverse _: Bool,
        filters _: [ProductFilterInput]
    ) async throws -> CollectionPage? {
        if fails {
            throw ShopifyError.network(.offline)
        }
        let collection = CollectionSummary(
            id: ShopifyID("gid://shopify/Collection/\(handle)"),
            handle: handle,
            title: handle,
            description: "",
            image: nil
        )
        return CollectionPage(collection: collection, products: Self.products, pageInfo: .singlePage)
    }

    func collections(first _: Int) async throws -> [CollectionSummary] {
        []
    }

    func recommendations(productID _: ShopifyID, intent _: ProductRecommendationIntent) async throws -> [ProductSummary] {
        []
    }

    func articles(blogHandle: String, first _: Int) async throws -> [ArticleSummary] {
        if fails {
            throw ShopifyError.network(.offline)
        }
        return [
            ArticleSummary(
                id: ShopifyID("gid://shopify/Article/1"),
                handle: "windows-11-kompatibilitaet-pruefen",
                blogHandle: blogHandle,
                title: "Windows 11 Kompatibilität prüfen",
                excerpt: "So prüfen Sie, ob Ihr PC die Voraussetzungen für Windows 11 erfüllt.",
                publishedAt: Date(timeIntervalSince1970: 1_780_000_000),
                image: nil,
                onlineStoreUrl: nil
            ),
        ]
    }

    func article(blogHandle _: String, handle _: String) async throws -> Article? {
        nil
    }

    private static let products: [ProductSummary] = [
        product(
            handle: "office-2024-professional-plus-key",
            title: "Microsoft Office 2024 Professional Plus Download kaufen",
            price: "29.90",
            compareAt: "149.99"
        ),
        product(
            handle: "windows-11-pro",
            title: "Windows 11 Pro kaufen \u{2013} Dauerlizenz 1 PC, Download",
            price: "12.90",
            compareAt: "79.99"
        ),
        product(
            handle: "office-2024-standard-mac",
            title: "Microsoft Office 2024 Standard für Mac Key \u{2013} Sofort Download",
            price: "13.90",
            compareAt: "13.90"
        ),
    ]

    private static func product(handle: String, title: String, price: String, compareAt: String) -> ProductSummary {
        let priceValue = MoneyV2(amount: Decimal(string: price) ?? 0, currencyCode: .eur)
        let compareAtValue = MoneyV2(amount: Decimal(string: compareAt) ?? 0, currencyCode: .eur)
        return ProductSummary(
            id: ShopifyID("gid://shopify/Product/\(handle)"),
            handle: handle,
            title: title,
            vendor: "Microsoft",
            availableForSale: true,
            featuredImage: nil,
            priceRange: PriceRange(minVariantPrice: priceValue, maxVariantPrice: priceValue),
            compareAtPriceRange: PriceRange(minVariantPrice: compareAtValue, maxVariantPrice: compareAtValue),
            requiresShipping: false
        )
    }
}
#endif
