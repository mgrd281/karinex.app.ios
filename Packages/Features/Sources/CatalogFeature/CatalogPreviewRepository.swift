#if DEBUG
import Foundation
import ShopifyKit

// MARK: - CatalogPreviewRepository

/// Serves fixed sample content to the previews of this module, or fails every request.
///
/// The values are modelled on the live store (DE/DE); they exist for previews only and are
/// never shown in the app.
struct CatalogPreviewRepository: CatalogRepository {
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
        return CollectionPage(
            collection: Self.collection(handle: handle, title: "Windows"),
            products: Self.products,
            pageInfo: .singlePage,
            filters: Self.filters
        )
    }

    func collections(first _: Int) async throws -> [CollectionSummary] {
        if fails {
            throw ShopifyError.network(.offline)
        }
        return [
            ("bestseller", "Bestseller günstig kaufen"),
            ("microsoft-office", "Microsoft Office"),
            ("microsoft-office-2024", "Microsoft Office 2024"),
            ("microsoft-project", "Microsoft Project"),
            ("all", "Microsoft Software & Lizenzen"),
            ("sale", "SALE \u{2013} Stark reduzierte Angebote"),
            ("visual-studio-entwicklungstools", "Visual Studio \u{2013} Entwicklungstools"),
            ("windows", "Windows"),
            ("windows-11", "Windows 11"),
            ("windows-server", "Windows Server"),
        ].map { Self.collection(handle: $0.0, title: $0.1) }
    }

    func recommendations(productID _: ShopifyID, intent _: ProductRecommendationIntent) async throws -> [ProductSummary] {
        []
    }

    private static func collection(handle: String, title: String) -> CollectionSummary {
        CollectionSummary(id: ShopifyID("gid://shopify/Collection/\(handle)"), handle: handle, title: title, description: "", image: nil)
    }

    private static let filters = [
        ProductFilter(
            id: "filter.v.availability",
            label: "Verfügbarkeit",
            type: "LIST",
            values: [
                ProductFilterValue(id: "filter.v.availability.1", label: "Auf Lager", count: 12, input: .available(true)),
                ProductFilterValue(id: "filter.v.availability.0", label: "Nicht vorrätig", count: 0, input: .available(false)),
            ]
        ),
        ProductFilter(
            id: "filter.v.price",
            label: "Preis",
            type: ProductFilter.priceRangeType,
            values: [ProductFilterValue(id: "filter.v.price", label: "Preis", count: 0, input: .price(minimum: 0, maximum: 239.9))]
        ),
    ]

    private static let products: [ProductSummary] = [
        product(
            handle: "windows-11-pro",
            title: "Windows 11 Pro kaufen \u{2013} Dauerlizenz 1 PC, Download",
            price: "12.90",
            compareAt: "79.99"
        ),
        product(
            handle: "windows-10-professional-lizenz",
            title: "Windows 10 Pro kaufen, 32/64-Bit, Sofort-Download",
            price: "11.90",
            compareAt: "79.99"
        ),
        product(handle: "windows-11-home", title: "Windows 11 Home Download", price: "10.90", compareAt: "10.90"),
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
