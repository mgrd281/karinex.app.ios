import CommerceUI
import Core
import DesignSystem
import Foundation
import ShopifyKit
import SwiftUI

// MARK: - ProductPreviewData

/// Sample values for the previews of this module.
///
/// Recorded from the live Storefront API (product `office-2024-professional-plus-key`, DE/DE,
/// fixture `product_office-2024-professional-plus-key_DE_DE.json`). The description is shortened
/// to its heading and first paragraph; store dashes are written as \u{2013} escapes. Tokenless
/// access returns no metafields, so the key facts and the FAQ are hidden, exactly as in the app.
enum ProductPreviewData {
    /// Microsoft Office 2024 Professional Plus, one digital variant.
    static let product: Product = {
        let price = MoneyV2(amount: Decimal(string: "29.90") ?? 0, currencyCode: .eur)
        let compareAt = MoneyV2(amount: Decimal(string: "149.99") ?? 0, currencyCode: .eur)
        let image = URL(string: "https://cdn.shopify.com/s/files/1/0917/5328/3851/files/Office_2024_Professional_Plus.webp?v=1787443066")
            .map { ShopifyImage(url: $0, altText: "Microsoft Office 2024 Professional Plus") }
        return Product(
            id: ShopifyID("gid://shopify/Product/1"),
            handle: "office-2024-professional-plus-key",
            title: "Microsoft Office 2024 Professional Plus Download kaufen",
            vendor: "karinex",
            productType: "",
            tags: [],
            availableForSale: true,
            descriptionHtml: """
                <h1>Office 2024 Professional Plus kaufen \u{2013} Vollversion mit Dauerlizenz, kein Abo</h1>
                <p>Microsoft Office 2024 Professional Plus als günstige Vollversion mit Dauerlizenz für Unternehmen, \
                Selbstständige und anspruchsvolle Privatanwender. Die aktuellste Office-Suite mit Word, Excel, PowerPoint, \
                Outlook, Access, Publisher und OneNote \u{2013} einmalig kaufen statt monatlich abonnieren.</p>
                """,
            featuredImage: image,
            images: image.map { [$0] } ?? [],
            options: [
                ProductOption(id: nil, name: "Title", optionValues: [ProductOptionValue(id: nil, name: "Default Title")]),
            ],
            variants: [
                ProductVariant(
                    id: ShopifyID("gid://shopify/ProductVariant/1"),
                    title: "Default Title",
                    sku: nil,
                    availableForSale: true,
                    requiresShipping: false,
                    price: price,
                    compareAtPrice: compareAt,
                    selectedOptions: [SelectedOption(name: "Title", value: "Default Title")],
                    image: image
                ),
            ],
            seo: SEO(title: nil, description: nil),
            collections: [],
            priceRange: PriceRange(minVariantPrice: price, maxVariantPrice: price),
            compareAtPriceRange: PriceRange(minVariantPrice: compareAt, maxVariantPrice: compareAt),
            onlineStoreUrl: URL(string: "https://www.karinex.de/products/office-2024-professional-plus-key"),
            metafields: []
        )
    }()

    /// A cart store on in-memory storage whose adds always succeed.
    @MainActor
    static func cartStore() -> CartStore {
        CartStore(repository: PreviewCartRepository(), store: InMemoryKeyValueStore(), appVersion: "0.1.0")
    }
}

// MARK: - Preview repositories

/// Serves ``ProductPreviewData/product`` and no recommendations.
struct PreviewCatalogRepository: CatalogRepository {
    func product(handle _: String) async throws -> Product? {
        ProductPreviewData.product
    }

    func collection(
        handle _: String,
        first _: Int,
        after _: String?,
        sortKey _: ProductCollectionSortKeys,
        reverse _: Bool,
        filters _: [ProductFilterInput]
    ) async throws -> CollectionPage? {
        nil
    }

    func collections(first _: Int) async throws -> [CollectionSummary] {
        []
    }

    func recommendations(productID _: ShopifyID, intent _: ProductRecommendationIntent) async throws -> [ProductSummary] {
        []
    }
}

/// A cart service that accepts every change and answers with an empty cart of one item.
struct PreviewCartRepository: CartRepository {
    private static let cart: Cart = {
        let total = MoneyV2(amount: Decimal(string: "29.90") ?? 0, currencyCode: .eur)
        return Cart(
            id: ShopifyID("gid://shopify/Cart/preview"),
            checkoutUrl: URL(fileURLWithPath: "/"),
            totalQuantity: 1,
            lines: [],
            cost: CartCost(subtotalAmount: total, totalAmount: total, totalTaxAmount: nil, checkoutChargeAmount: nil),
            discountCodes: [],
            buyerIdentity: CartBuyerIdentity(countryCode: .de, email: nil),
            attributes: []
        )
    }()

    private var result: CartMutationResult {
        CartMutationResult(cart: Self.cart, warnings: [])
    }

    func cart(id _: ShopifyID) async throws -> Cart? {
        Self.cart
    }

    func createCart(lines _: [CartLineInput], attributes _: [AttributeInput]) async throws -> CartMutationResult {
        result
    }

    func addLines(cartID _: ShopifyID, lines _: [CartLineInput]) async throws -> CartMutationResult {
        result
    }

    func updateLines(cartID _: ShopifyID, lines _: [CartLineUpdateInput]) async throws -> CartMutationResult {
        result
    }

    func removeLines(cartID _: ShopifyID, lineIDs _: [ShopifyID]) async throws -> CartMutationResult {
        result
    }

    func updateDiscountCodes(cartID _: ShopifyID, codes _: [String]) async throws -> CartMutationResult {
        result
    }

    func updateBuyerIdentity(cartID _: ShopifyID, countryCode _: CountryCode) async throws -> CartMutationResult {
        result
    }

    func updateAttributes(cartID _: ShopifyID, attributes _: [AttributeInput]) async throws -> CartMutationResult {
        result
    }
}

// MARK: - Previews

#Preview("Product, light") {
    NavigationStack {
        ProductDetailScreen(
            handle: ProductPreviewData.product.handle,
            catalog: PreviewCatalogRepository(),
            cartStore: ProductPreviewData.cartStore(),
            onRoute: { _ in },
            onBuyNow: {}
        )
    }
    .environment(\.locale, Locale(identifier: "de_DE"))
}

#Preview("Product, dark") {
    NavigationStack {
        ProductDetailScreen(
            handle: ProductPreviewData.product.handle,
            catalog: PreviewCatalogRepository(),
            cartStore: ProductPreviewData.cartStore(),
            onRoute: { _ in },
            onBuyNow: {}
        )
    }
    .preferredColorScheme(.dark)
}

#Preview("Product, accessibility size") {
    NavigationStack {
        ProductDetailScreen(
            handle: ProductPreviewData.product.handle,
            catalog: PreviewCatalogRepository(),
            cartStore: ProductPreviewData.cartStore(),
            onRoute: { _ in },
            onBuyNow: {}
        )
    }
    .dynamicTypeSize(.accessibility2)
}

#Preview("Sections") {
    ScrollView {
        VStack(alignment: .leading, spacing: KXSpacing.xl) {
            ProductMoreInformationSection(
                description: HTMLDocument(html: ProductPreviewData.product.descriptionHtml),
                fulfillment: .digital,
                activation: nil
            )
            ProductMoreInformationSection(description: HTMLDocument(blocks: []), fulfillment: .physical, activation: nil)
            ProductPaymentMethods()
            ProductRefundSection()
            ProductDigitalNoticeSection()
        }
        .padding(KXSpacing.gutter)
    }
    .kxScreenBackground()
}

#Preview("Image viewer") {
    ProductImageViewer(images: ProductPreviewData.product.images, initialIndex: 0)
}
