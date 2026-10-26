import CommerceUI
import Foundation
import Observation
import ShopifyKit

// MARK: - ProductCartConfirmation

/// A successful "In den Warenkorb": the screen shows a confirmation with "Zum Warenkorb" and
/// plays the success haptic. Every add has its own number, so two adds in a row are two
/// confirmations.
struct ProductCartConfirmation: Sendable, Hashable, Identifiable {
    /// The running number of the confirmation on this screen.
    let id: Int
}

// MARK: - ProductDetailViewModel

/// Loads a product by handle, keeps the selected variant and adds it to the cart.
///
/// - The product loads once; reloading (pull to refresh) keeps the shown content when it fails
///   and reports the failure through ``actionError`` instead.
/// - The comparison row loads Shopify's `RELATED` recommendations after the product, at most
///   ``comparisonLimit`` products, without the product itself. The "Passend dazu" row loads the
///   `COMPLEMENTARY` recommendations the merchant set up in Shopify at the same time, without
///   the product and its linked products. A failing row never blocks the screen.
/// - The linked products row shows the products the merchant linked to this one in the web shop
///   (``ShopifyKit/Product/linkedProducts``), see ``linkedProducts(of:)``.
/// - Adding goes through the shared ``CartStore``, which creates the cart on the first add.
@MainActor
@Observable
final class ProductDetailViewModel {
    /// The maximum number of products in the comparison and "Passend dazu" rows.
    static let comparisonLimit = 6
    /// The maximum number of thumbnails in the linked products row.
    static let linkedProductsLimit = 12

    /// The handle of the product.
    let handle: String

    /// The load state of the product.
    private(set) var state: LoadState<ProductDetailContent> = .idle
    /// The load state of the comparison row.
    private(set) var comparison: LoadState<[ProductSummary]> = .idle
    /// The load state of the "Passend dazu" row.
    private(set) var complementary: LoadState<[ProductSummary]> = .idle
    /// The variant the customer chose, `nil` until the product has loaded.
    private(set) var selectedVariantID: ShopifyID?
    /// Whether an add to the cart is running.
    private(set) var isAddingToCart = false
    /// The current add confirmation, `nil` when none is shown.
    private(set) var confirmation: ProductCartConfirmation?
    /// The number of successful adds on this screen; drives the success haptic.
    private(set) var successfulAddCount = 0
    /// The last failure of an action (adding, reloading), shown in a banner. Set it to `nil` to
    /// dismiss it.
    var actionError: UserFacingError?

    @ObservationIgnored private let catalog: any CatalogRepository
    @ObservationIgnored private let cartStore: CartStore

    /// Creates the view model.
    ///
    /// - Parameters:
    ///   - handle: The product handle, e.g. `office-2024-professional-plus-key`.
    ///   - catalog: The catalog repository.
    ///   - cartStore: The app's cart.
    init(handle: String, catalog: any CatalogRepository, cartStore: CartStore) {
        self.handle = handle
        self.catalog = catalog
        self.cartStore = cartStore
    }

    // MARK: Derived state

    /// The loaded content, if any.
    var content: ProductDetailContent? {
        state.value
    }

    /// The loaded product, if any.
    var product: Product? {
        content?.product
    }

    /// The selected variant, falling back to Shopify's preselection (the first available one).
    var selectedVariant: ProductVariant? {
        guard let product else { return nil }
        return product.variants.first { $0.id == selectedVariantID } ?? product.defaultVariant
    }

    /// Whether the screen offers a variant choice: only for more than one variant.
    var showsVariantPicker: Bool {
        (product?.variants.count ?? 0) > 1
    }

    /// How the selected variant is delivered.
    var fulfillment: ProductFulfillment {
        ProductFulfillment(variant: selectedVariant)
    }

    /// Whether the selected variant can be bought.
    var isPurchasable: Bool {
        selectedVariant?.availableForSale == true
    }

    /// The thumbnails of the linked products row; empty hides the row.
    var linkedProducts: [ProductSummary] {
        product.map(Self.linkedProducts(of:)) ?? []
    }

    /// The store's lowest price of the last 30 days for the selected variant. Only for products
    /// with one variant, because the store keeps one value per product.
    var lowestPrice: MoneyV2? {
        guard let product, product.variants.count == 1, let variant = selectedVariant else { return nil }
        return product.productMetafields.lowestPrice30Days(currency: variant.price.currencyCode)
    }

    /// The units the store reports as sold in the last days, or `nil` to hide the row.
    var recentSales: RecentSales? {
        product?.productMetafields.recentSales
    }

    // MARK: Loading

    /// Loads the product and then both recommendation rows. Keeps shown content while
    /// reloading.
    func load() async {
        if state.value == nil {
            state = .loading
        }
        do {
            guard let product = try await catalog.product(handle: handle) else {
                state = .empty
                comparison = .empty
                complementary = .empty
                return
            }
            let content = await ProductDetailContent.make(product)
            // The customer's choice survives a reload as long as the variant still exists.
            let keepsSelection = selectedVariantID.map { id in product.variants.contains { $0.id == id } } ?? false
            if !keepsSelection {
                selectedVariantID = product.defaultVariant?.id
            }
            state = .loaded(content)
        } catch {
            guard let failure = UserFacingError(error) else { return }
            if state.value == nil {
                state = .failed(failure)
            } else {
                actionError = failure
            }
            return
        }
        async let related: Void = loadComparison()
        async let complements: Void = loadComplementary()
        _ = await (related, complements)
    }

    /// Loads the comparison row for the loaded product. Keeps shown products while reloading.
    func loadComparison() async {
        guard let product else { return }
        if comparison.value == nil {
            comparison = .loading
        }
        do {
            let related = try await catalog.recommendations(productID: product.id, intent: .related)
            comparison = LoadState(collection: Self.comparisonProducts(related, excluding: product.id))
        } catch {
            guard let failure = UserFacingError(error), comparison.value == nil else { return }
            comparison = .failed(failure)
        }
    }

    /// Loads the "Passend dazu" row for the loaded product. Keeps shown products while
    /// reloading.
    func loadComplementary() async {
        guard let product else { return }
        if complementary.value == nil {
            complementary = .loading
        }
        do {
            let complements = try await catalog.recommendations(productID: product.id, intent: .complementary)
            let excluded = Set(product.linkedProducts.map(\.id))
            let products = Self.comparisonProducts(complements.filter { !excluded.contains($0.id) }, excluding: product.id)
            complementary = LoadState(collection: products)
        } catch {
            guard let failure = UserFacingError(error), complementary.value == nil else { return }
            complementary = .failed(failure)
        }
    }

    /// The products of the comparison row: `products` without the product itself and without
    /// repeats, at most ``comparisonLimit``.
    static func comparisonProducts(_ products: [ProductSummary], excluding productID: ShopifyID) -> [ProductSummary] {
        var seen: Set<ShopifyID> = [productID]
        return Array(products.filter { seen.insert($0.id).inserted }.prefix(comparisonLimit))
    }

    /// The thumbnails of the linked products row: the products the merchant linked to `product`
    /// without repeats, in the merchant's order, with `product` itself in its place, or first
    /// when the merchant's list leaves it out. At most ``linkedProductsLimit``. Empty unless at
    /// least one other product is linked.
    static func linkedProducts(of product: Product) -> [ProductSummary] {
        var seen: Set<ShopifyID> = []
        var products = product.linkedProducts.filter { seen.insert($0.id).inserted }
        guard products.contains(where: { $0.id != product.id }) else { return [] }
        if !seen.contains(product.id) {
            products.insert(ProductSummary(product), at: 0)
        }
        return Array(products.prefix(linkedProductsLimit))
    }

    // MARK: Variants

    /// Selects a variant of the loaded product. Unknown IDs are ignored.
    func selectVariant(_ variantID: ShopifyID) {
        guard product?.variants.contains(where: { $0.id == variantID }) == true else { return }
        selectedVariantID = variantID
    }

    // MARK: Cart

    /// Adds one unit of the selected variant to the cart and shows the confirmation.
    ///
    /// - Returns: Whether the variant was added. On failure ``actionError`` explains why.
    @discardableResult
    func addToCart() async -> Bool {
        await add(confirming: true)
    }

    /// "Jetzt kaufen": adds one unit of the selected variant without the confirmation, because
    /// the checkout opens right after.
    ///
    /// - Returns: Whether the variant was added; only then may the checkout open.
    func buyNow() async -> Bool {
        await add(confirming: false)
    }

    /// Hides the confirmation `id`, unless a newer one replaced it.
    func dismissConfirmation(_ id: ProductCartConfirmation.ID) {
        if confirmation?.id == id {
            confirmation = nil
        }
    }

    private func add(confirming: Bool) async -> Bool {
        guard let variant = selectedVariant, variant.availableForSale, !isAddingToCart else { return false }
        isAddingToCart = true
        actionError = nil
        let added = await cartStore.add(variantID: variant.id, quantity: 1)
        isAddingToCart = false
        if added {
            successfulAddCount += 1
            confirmation = confirming ? ProductCartConfirmation(id: successfulAddCount) : nil
        } else {
            confirmation = nil
            actionError = cartStore.lastError ?? UserFacingError(kind: .unknown)
        }
        return added
    }
}
