#if DEBUG
import Foundation
import ShopifyKit

// MARK: - SearchPreviewRepository

/// Serves fixed sample results to the previews of this module. Queries starting with "zzz"
/// find nothing.
///
/// The values are modelled on the live store (DE/DE); they exist for previews only and are
/// never shown in the app.
struct SearchPreviewRepository: SearchRepository {
    func predictive(query: String, limit _: Int) async throws -> PredictiveSearchResult {
        guard !query.lowercased().hasPrefix("zzz") else { return .empty }
        return PredictiveSearchResult(
            products: Self.products,
            collections: [
                CollectionSummary(
                    id: ShopifyID("gid://shopify/Collection/microsoft-office"),
                    handle: "microsoft-office",
                    title: "Microsoft Office",
                    description: "",
                    image: nil
                ),
            ],
            articles: [],
            queries: [SearchQuerySuggestion(text: "office 2024")]
        )
    }

    func products(
        query: String,
        first _: Int,
        after _: String?,
        sortKey _: SearchSortKey,
        reverse _: Bool,
        filters _: [ProductFilterInput]
    ) async throws -> SearchResultPage {
        guard !query.lowercased().hasPrefix("zzz") else { return .empty }
        return SearchResultPage(totalCount: Self.products.count, products: Self.products, filters: [], pageInfo: .singlePage)
    }

    private static let products: [ProductSummary] = [
        product(
            handle: "office-2024-professional-plus-key",
            title: "Microsoft Office 2024 Professional Plus Download kaufen",
            price: "29.90"
        ),
        product(
            handle: "office-2024-standard-mac",
            title: "Microsoft Office 2024 Standard für Mac Key \u{2013} Sofort Download",
            price: "13.90"
        ),
    ]

    private static func product(handle: String, title: String, price: String) -> ProductSummary {
        let priceValue = MoneyV2(amount: Decimal(string: price) ?? 0, currencyCode: .eur)
        return ProductSummary(
            id: ShopifyID("gid://shopify/Product/\(handle)"),
            handle: handle,
            title: title,
            vendor: "Microsoft",
            availableForSale: true,
            featuredImage: nil,
            priceRange: PriceRange(minVariantPrice: priceValue, maxVariantPrice: priceValue),
            compareAtPriceRange: PriceRange(minVariantPrice: priceValue, maxVariantPrice: priceValue),
            requiresShipping: false
        )
    }
}
#endif
