import Core
import Foundation
import ShopifyKit

// MARK: - ProductFixtures

/// Builds products for the product screen tests in one place. Prices and the image follow the
/// recorded `office-2024-professional-plus-key` product (DE/DE).
enum ProductFixtures {
    /// The product ID of ``product(variants:metafields:images:)``.
    static let productID = ShopifyID("gid://shopify/Product/9001")
    /// The handle of ``product(variants:metafields:images:)``.
    static let handle = "office-2024-professional-plus-key"

    /// A recorded CDN image URL.
    static let imageURL = URL(string: "https://cdn.shopify.com/s/files/1/0917/5328/3851/files/Office_2024_Professional_Plus.webp")
        ?? URL(fileURLWithPath: "/")

    /// A variant at 29,90 € instead of 149,99 €.
    static func variant(
        _ number: Int,
        title: String = "Default Title",
        availableForSale: Bool = true,
        requiresShipping: Bool = false,
        image: ShopifyImage? = nil
    ) -> ProductVariant {
        ProductVariant(
            id: ShopifyID("gid://shopify/ProductVariant/\(number)"),
            title: title,
            sku: nil,
            availableForSale: availableForSale,
            requiresShipping: requiresShipping,
            price: money("29.90"),
            compareAtPrice: money("149.99"),
            selectedOptions: [SelectedOption(name: "Title", value: title)],
            image: image
        )
    }

    /// A product with `variants`, `metafields`, `images` and `linkedProducts`.
    static func product(
        variants: [ProductVariant] = [variant(1)],
        metafields: [Metafield] = [],
        images: [ShopifyImage] = [ShopifyImage(url: imageURL, altText: "Microsoft Office 2024 Professional Plus")],
        descriptionHtml: String = "<p>Microsoft Office 2024 Professional Plus als Vollversion.</p>",
        linkedProducts: [ProductSummary] = []
    ) -> Product {
        Product(
            id: productID,
            handle: handle,
            title: "Microsoft Office 2024 Professional Plus Download kaufen",
            vendor: "karinex",
            productType: "",
            tags: [],
            availableForSale: variants.contains(where: \.availableForSale),
            descriptionHtml: descriptionHtml,
            featuredImage: images.first,
            images: images,
            options: [],
            variants: variants,
            seo: SEO(title: nil, description: nil),
            collections: [],
            priceRange: PriceRange(minVariantPrice: money("29.90"), maxVariantPrice: money("29.90")),
            compareAtPriceRange: PriceRange(minVariantPrice: money("149.99"), maxVariantPrice: money("149.99")),
            onlineStoreUrl: URL(string: "https://www.karinex.de/products/\(handle)"),
            metafields: metafields,
            linkedProducts: linkedProducts
        )
    }

    /// A product summary with the given number, for recommendations.
    static func summary(_ number: Int, id: ShopifyID? = nil) -> ProductSummary {
        ProductSummary(
            id: id ?? ShopifyID("gid://shopify/Product/\(number)"),
            handle: "product-\(number)",
            title: "Product \(number)",
            vendor: "karinex",
            availableForSale: true,
            featuredImage: nil,
            priceRange: PriceRange(minVariantPrice: money("12.90"), maxVariantPrice: money("12.90")),
            compareAtPriceRange: PriceRange(minVariantPrice: money("79.99"), maxVariantPrice: money("79.99")),
            requiresShipping: false
        )
    }

    /// Euro money.
    static func money(_ amount: String) -> MoneyV2 {
        MoneyV2(amount: Decimal(string: amount) ?? 0, currencyCode: .eur)
    }
}

// MARK: - ProductStubCatalogRepository

/// A catalog that serves one product and its recommendations per intent, with queued failures.
actor ProductStubCatalogRepository: CatalogRepository {
    private var product: Product?
    private var recommendations: [ProductSummary]
    private var complementary: [ProductSummary]
    private var productFailures: [any Error] = []
    private var recommendationFailures: [ProductRecommendationIntent: [any Error]] = [:]

    /// The handles requested so far.
    private(set) var requestedHandles: [String] = []
    /// The recommendation requests so far.
    private(set) var recommendationRequests: [(productID: ShopifyID, intent: ProductRecommendationIntent)] = []

    /// Creates the catalog.
    ///
    /// - Parameters:
    ///   - product: The product, or `nil` for a product that does not exist.
    ///   - recommendations: The `RELATED` recommendations.
    ///   - complementary: The `COMPLEMENTARY` recommendations.
    init(product: Product?, recommendations: [ProductSummary] = [], complementary: [ProductSummary] = []) {
        self.product = product
        self.recommendations = recommendations
        self.complementary = complementary
    }

    /// Makes the next product request throw `error`.
    func failNextProduct(with error: any Error) {
        productFailures.append(error)
    }

    /// Makes the next recommendations request for `intent` throw `error`.
    func failNextRecommendations(with error: any Error, intent: ProductRecommendationIntent = .related) {
        recommendationFailures[intent, default: []].append(error)
    }

    func product(handle: String) async throws -> Product? {
        requestedHandles.append(handle)
        if !productFailures.isEmpty {
            throw productFailures.removeFirst()
        }
        return product?.handle == handle ? product : nil
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

    func recommendations(productID: ShopifyID, intent: ProductRecommendationIntent) async throws -> [ProductSummary] {
        recommendationRequests.append((productID, intent))
        if let failure = recommendationFailures[intent]?.first {
            recommendationFailures[intent]?.removeFirst()
            throw failure
        }
        return intent == .complementary ? complementary : recommendations
    }
}

// MARK: - ProductStubCartRepository

/// A cart service that records added variants and can fail the next add.
actor ProductStubCartRepository: CartRepository {
    /// The variants of every create and add call, in order.
    private(set) var addedVariantIDs: [ShopifyID] = []
    /// The number of carts created.
    private(set) var createCount = 0

    private var quantity = 0
    private var addFailures: [any Error] = []
    private let cartID = ShopifyID("gid://shopify/Cart/product-tests")

    /// Makes the next create or add throw `error`.
    func failNextAdd(with error: any Error) {
        addFailures.append(error)
    }

    func cart(id _: ShopifyID) async throws -> Cart? {
        createCount > 0 ? snapshot() : nil
    }

    func createCart(lines: [CartLineInput], attributes _: [AttributeInput]) async throws -> CartMutationResult {
        try throwQueuedFailure()
        createCount += 1
        return record(lines)
    }

    func addLines(cartID _: ShopifyID, lines: [CartLineInput]) async throws -> CartMutationResult {
        try throwQueuedFailure()
        return record(lines)
    }

    func updateLines(cartID _: ShopifyID, lines _: [CartLineUpdateInput]) async throws -> CartMutationResult {
        CartMutationResult(cart: snapshot(), warnings: [])
    }

    func removeLines(cartID _: ShopifyID, lineIDs _: [ShopifyID]) async throws -> CartMutationResult {
        CartMutationResult(cart: snapshot(), warnings: [])
    }

    func updateDiscountCodes(cartID _: ShopifyID, codes _: [String]) async throws -> CartMutationResult {
        CartMutationResult(cart: snapshot(), warnings: [])
    }

    func updateBuyerIdentity(cartID _: ShopifyID, countryCode _: CountryCode) async throws -> CartMutationResult {
        CartMutationResult(cart: snapshot(), warnings: [])
    }

    func updateAttributes(cartID _: ShopifyID, attributes _: [AttributeInput]) async throws -> CartMutationResult {
        CartMutationResult(cart: snapshot(), warnings: [])
    }

    private func throwQueuedFailure() throws {
        if !addFailures.isEmpty {
            throw addFailures.removeFirst()
        }
    }

    private func record(_ lines: [CartLineInput]) -> CartMutationResult {
        addedVariantIDs.append(contentsOf: lines.map(\.merchandiseId))
        quantity += lines.reduce(0) { $0 + $1.quantity }
        return CartMutationResult(cart: snapshot(), warnings: [])
    }

    private func snapshot() -> Cart {
        let total = ProductFixtures.money("29.90")
        return Cart(
            id: cartID,
            checkoutUrl: URL(string: "https://www.karinex.de/cart/c/REDACTED") ?? URL(fileURLWithPath: "/"),
            totalQuantity: quantity,
            lines: [],
            cost: CartCost(subtotalAmount: total, totalAmount: total, totalTaxAmount: nil, checkoutChargeAmount: nil),
            discountCodes: [],
            buyerIdentity: CartBuyerIdentity(countryCode: .de, email: nil),
            attributes: []
        )
    }
}
