import CommerceUI
import DesignSystem
import ShopifyKit
import SwiftUI

// MARK: - ProductDetailScreen

/// The product detail screen (PROMPT.md section 6.3), the most important screen of the app, laid
/// out like a fashion retail app.
///
/// From top to bottom: the photos edge to edge on the light grey photo tile with page dots and
/// the wishlist heart (tap for the full-screen zoom viewer), the bold title, the price of the
/// selected variant with the market's tax note, availability and delivery as icon rows, the
/// variant pills when there is more than one variant, "Jetzt kaufen", the description, the key
/// facts from the store's metafields (hidden when there are none), "So läuft es ab" and the
/// activation instructions (when the store provides them) as collapsible rows, the money-back
/// conditions and, for digital variants, the right of withdrawal notice, similar products and
/// the FAQ (when present). A sticky bar keeps the price and "In den Warenkorb" in reach; the
/// toolbar shares the product page of the web shop.
///
/// Every product fact comes from Shopify. The screen adds no ratings and no claims.
///
/// Push it from a ``CommerceUI/CommerceRoute/product(handle:)`` route:
///
/// ```swift
/// ProductDetailScreen(
///     handle: handle,
///     catalog: catalogRepository,
///     cartStore: cartStore,
///     onRoute: { path.append($0) },
///     onBuyNow: { isCheckoutPresented = true }
/// )
/// ```
public struct ProductDetailScreen: View {
    @State private var model: ProductDetailViewModel
    @State private var isTitleVisible = true

    private let onRoute: @MainActor (CommerceRoute) -> Void
    private let onBuyNow: @MainActor () -> Void

    @Environment(\.accessibilityVoiceOverEnabled) private var isVoiceOverEnabled
    @Environment(SavedProductsStore.self) private var savedProducts: SavedProductsStore?

    /// Creates the screen.
    ///
    /// - Parameters:
    ///   - handle: The product handle, e.g. `office-2024-professional-plus-key`.
    ///   - catalog: Loads the product and the similar products.
    ///   - cartStore: The app's cart; "In den Warenkorb" and "Jetzt kaufen" add to it.
    ///   - onRoute: Opens another destination: a similar product (``CommerceRoute/product(handle:)``)
    ///     or the cart (``CommerceRoute/cart``, from the confirmation after adding).
    ///   - onBuyNow: Called after "Jetzt kaufen" added the variant to the cart; the App opens the
    ///     checkout.
    public init(
        handle: String,
        catalog: any CatalogRepository,
        cartStore: CartStore,
        onRoute: @escaping @MainActor (CommerceRoute) -> Void,
        onBuyNow: @escaping @MainActor () -> Void
    ) {
        _model = State(initialValue: ProductDetailViewModel(handle: handle, catalog: catalog, cartStore: cartStore))
        self.onRoute = onRoute
        self.onBuyNow = onBuyNow
    }

    public var body: some View {
        AsyncContentView(
            model.state,
            empty: AsyncContentEmptyState(
                systemImage: "shippingbox",
                title: String(localized: "product.empty.title", bundle: .module),
                message: String(localized: "product.empty.message", bundle: .module)
            ),
            retry: { await model.load() },
            content: { content in
                ProductDetailBody(
                    content: content,
                    model: model,
                    isSaved: savedProducts.map { $0.isSaved(content.product.id) },
                    onToggleSaved: { savedProducts?.toggle(content.product.id) },
                    onRoute: onRoute,
                    onBuyNow: buyNow,
                    onTitleVisibilityChange: { isTitleVisible = $0 }
                )
            },
            placeholder: {
                ProductDetailSkeleton()
            }
        )
        .kxScreenBackground()
        .navigationTitle(Text(verbatim: model.product?.title ?? String()))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(verbatim: model.product?.title ?? String())
                    .kxFont(.headline)
                    .foregroundStyle(KXColor.textPrimary)
                    .lineLimit(1)
                    .opacity(isTitleVisible ? 0 : 1)
                    .accessibilityHidden(isTitleVisible)
                    .kxAnimation(.fade, value: isTitleVisible)
            }
            if let url = model.product?.onlineStoreUrl {
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: url, subject: Text(verbatim: model.product?.title ?? String())) {
                        Label {
                            Text("product.share", bundle: .module)
                        } icon: {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                    .accessibilityIdentifier("product.share")
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let variant = model.selectedVariant {
                ProductPurchaseBar(
                    variant: variant,
                    image: variant.image ?? model.product?.featuredImage,
                    isAdding: model.isAddingToCart,
                    onAddToCart: addToCart
                )
            }
        }
        .kxBanner(isPresented: model.actionError != nil || model.confirmation != nil) {
            banner
        }
        .sensoryFeedback(.success, trigger: model.successfulAddCount)
        .task(id: model.confirmation) {
            await dismissConfirmationLater()
        }
        .task {
            if model.state.value == nil {
                await model.load()
            }
        }
        .onChange(of: model.product?.id, initial: true) { _, id in
            if let id {
                savedProducts?.recordView(id)
            }
        }
        .accessibilityIdentifier("screen.product")
    }

    // MARK: Banner

    @ViewBuilder private var banner: some View {
        if let error = model.actionError {
            KXBanner(.error, message: error.message, onDismiss: { model.actionError = nil })
                .accessibilityIdentifier("product.error")
        } else if let confirmation = model.confirmation {
            KXBanner(
                .success,
                message: String(localized: "product.cart.added", bundle: .module),
                actionTitle: String(localized: "product.cart.show", bundle: .module),
                action: {
                    model.dismissConfirmation(confirmation.id)
                    onRoute(.cart)
                },
                onDismiss: { model.dismissConfirmation(confirmation.id) }
            )
            .accessibilityIdentifier("product.confirmation")
        }
    }

    /// Hides the confirmation after a few seconds; VoiceOver users get more time to reach
    /// "Zum Warenkorb".
    private func dismissConfirmationLater() async {
        guard let id = model.confirmation?.id else { return }
        try? await Task.sleep(for: .seconds(isVoiceOverEnabled ? 10 : 4))
        guard !Task.isCancelled else { return }
        model.dismissConfirmation(id)
    }

    // MARK: Actions

    private func addToCart() {
        Task {
            await model.addToCart()
        }
    }

    private func buyNow() {
        Task {
            if await model.buyNow() {
                onBuyNow()
            }
        }
    }
}

// MARK: - ProductDetailBody

/// The scrolling content of a loaded product.
private struct ProductDetailBody: View {
    let content: ProductDetailContent
    let model: ProductDetailViewModel
    /// Whether the product is on the wishlist, or `nil` when the app offers no wishlist.
    let isSaved: Bool?
    let onToggleSaved: @MainActor () -> Void
    let onRoute: @MainActor (CommerceRoute) -> Void
    let onBuyNow: @MainActor () -> Void
    let onTitleVisibilityChange: @MainActor (Bool) -> Void

    @State private var galleryIndex = 0
    @State private var viewer: ProductViewerRequest?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KXSpacing.xl) {
                VStack(alignment: .leading, spacing: KXSpacing.l) {
                    ProductGallery(
                        images: content.images,
                        selection: $galleryIndex,
                        isSaved: isSaved,
                        onToggleSaved: onToggleSaved
                    ) { index in
                        viewer = ProductViewerRequest(index: index)
                    }
                    VStack(alignment: .leading, spacing: KXSpacing.l) {
                        ProductSummarySection(
                            product: content.product,
                            variant: model.selectedVariant,
                            lowestPrice: model.lowestPrice,
                            linkedProducts: model.linkedProducts,
                            onSelectLinkedProduct: { onRoute(.product(handle: $0.handle)) },
                            fulfillment: model.fulfillment,
                            showsVariantPicker: model.showsVariantPicker,
                            selectedVariantID: model.selectedVariantID,
                            onSelectVariant: { model.selectVariant($0) },
                            onTitleVisibilityChange: onTitleVisibilityChange
                        )
                        if let variant = model.selectedVariant {
                            KXButton(
                                String(localized: "product.cart.buy_now", bundle: .module),
                                style: .secondary,
                                isFullWidth: true
                            ) {
                                onBuyNow()
                            }
                            .disabled(!variant.availableForSale || model.isAddingToCart)
                            .accessibilityIdentifier("product.buyNow")
                        }
                        ProductPaymentMethods()
                    }
                    .padding(.horizontal, KXSpacing.gutter)
                }

                Group {
                    if !content.facts.isEmpty {
                        ProductFactsSection(facts: content.facts)
                    }
                    ProductMoreInformationSection(
                        description: content.description,
                        fulfillment: model.fulfillment,
                        activation: content.activation
                    )
                    VStack(alignment: .leading, spacing: KXSpacing.l) {
                        ProductRefundSection()
                        if model.fulfillment.showsDigitalContentNotice {
                            ProductDigitalNoticeSection()
                        }
                    }
                }
                .padding(.horizontal, KXSpacing.gutter)

                recommendationRows

                if !content.faq.isEmpty {
                    ProductFAQSection(items: content.faq)
                        .padding(.horizontal, KXSpacing.gutter)
                }
            }
            .padding(.bottom, KXSpacing.xl)
        }
        .refreshable {
            await model.load()
        }
        .onChange(of: model.selectedVariantID) {
            if let index = content.imageIndex(of: model.selectedVariant?.image) {
                galleryIndex = index
            }
        }
        .fullScreenCover(item: $viewer) { request in
            ProductImageViewer(images: content.images, initialIndex: request.index)
        }
    }
}

extension ProductDetailBody {
    /// "Passend dazu" (Shopify's `COMPLEMENTARY` recommendations) and "Ähnliche Produkte"
    /// (`RELATED`); each row hides itself when it is empty.
    @ViewBuilder private var recommendationRows: some View {
        ProductCarouselSection(
            title: String(localized: "product.complementary.title", bundle: .module),
            eyebrow: String(localized: "product.complementary.eyebrow", bundle: .module),
            state: model.complementary,
            retry: { await model.loadComplementary() },
            onSelect: { onRoute(.product(handle: $0.handle)) }
        )
        .accessibilityIdentifier("product.complementary")

        ProductCarouselSection(
            title: String(localized: "product.comparison.title", bundle: .module),
            eyebrow: String(localized: "product.comparison.eyebrow", bundle: .module),
            state: model.comparison,
            retry: { await model.loadComparison() },
            onSelect: { onRoute(.product(handle: $0.handle)) }
        )
        .accessibilityIdentifier("product.comparison")
    }
}

// MARK: - ProductViewerRequest

/// A request to open the image viewer at an index.
private struct ProductViewerRequest: Identifiable, Hashable {
    let index: Int

    var id: Int {
        index
    }
}
