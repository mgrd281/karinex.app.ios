import CommerceUI
import DesignSystem
import ShopifyKit
import SwiftUI

// MARK: - CartView

/// The Warenkorb tab (PROMPT.md section 6.5).
///
/// With lines: each line with image, title, variant, price and a quantity control (1 to 10),
/// a remove button with an undo bar, the discount code field (Shopify's message when a code
/// does not apply), subtotal, discount and total from Shopify's cart cost with the market's tax
/// note, the payment methods (Apple Pay, Kreditkarte, Klarna), the right of withdrawal notice
/// for digital content, a cross-sell row and a sticky "Zur Kasse" bar.
///
/// Without lines: the empty state ("Ihr Warenkorb ist leer", "Zum Sortiment") with the payment
/// methods and the notice. Shopify's warnings and failed changes appear as banners.
///
/// Every amount comes from Shopify; the screen never computes prices or taxes. Place it inside
/// a `NavigationStack`; it uses a large title.
///
/// ```swift
/// CartView(
///     cartStore: container.cartStore,
///     catalog: container.catalogRepository,
///     onRoute: { path.append($0) },
///     onBrowse: { selectedTab = .shop },
///     onCheckout: { isCheckoutPresented = true }
/// )
/// ```
public struct CartView: View {
    @State private var model: CartViewModel

    private let onRoute: @MainActor (CommerceRoute) -> Void
    private let onBrowse: @MainActor () -> Void
    private let onCheckout: @MainActor () -> Void

    @Environment(\.accessibilityVoiceOverEnabled) private var isVoiceOverEnabled

    /// Creates the cart screen.
    ///
    /// - Parameters:
    ///   - cartStore: The app's cart.
    ///   - catalog: Loads the cross-sell recommendations.
    ///   - onRoute: Opens a product (a line's title or a cross-sell card).
    ///   - onBrowse: Called by "Zum Sortiment" in the empty state, typically switching to the
    ///     Shop tab.
    ///   - onCheckout: Called by "Zur Kasse"; the App presents the checkout.
    public init(
        cartStore: CartStore,
        catalog: any CatalogRepository,
        onRoute: @escaping @MainActor (CommerceRoute) -> Void,
        onBrowse: @escaping @MainActor () -> Void,
        onCheckout: @escaping @MainActor () -> Void
    ) {
        _model = State(initialValue: CartViewModel(cartStore: cartStore, catalog: catalog))
        self.onRoute = onRoute
        self.onBrowse = onBrowse
        self.onCheckout = onCheckout
    }

    public var body: some View {
        AsyncContentView(
            model.state,
            retry: { await model.refresh() },
            content: { content in
                switch content {
                case .empty:
                    CartEmptyContent(onBrowse: onBrowse)
                case let .cart(cart):
                    CartContent(cart: cart, model: model, onRoute: onRoute)
                }
            },
            placeholder: {
                CartSkeleton()
            }
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.cart")
        .kxScreenBackground()
        .navigationTitle(Text("cart.title", bundle: .module))
        .navigationBarTitleDisplayMode(.large)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomBars
        }
        .kxBanner(isPresented: model.actionError != nil) {
            if let error = model.actionError {
                KXBanner(.error, message: error.message, onDismiss: { model.dismissError() })
                    .accessibilityIdentifier("cart.error")
            }
        }
        .task {
            await model.refresh()
        }
        .task(id: model.crossSellKey) {
            await model.loadCrossSell()
        }
        .task(id: model.removedLine?.id) {
            await discardUndoLater()
        }
    }

    // MARK: Bottom bars

    private var bottomBars: some View {
        VStack(spacing: 0) {
            if let removed = model.removedLine {
                CartUndoBar(
                    title: removed.merchandise.product.title,
                    onUndo: { Task { await model.undoRemove() } },
                    onDismiss: { model.discardUndo() }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if let cart = model.cart {
                CartCheckoutBar(cart: cart, onCheckout: onCheckout)
            }
        }
        .kxAnimation(.standard, value: model.removedLine?.id)
    }

    /// Hides the undo bar after a while; VoiceOver users get more time to reach "Rückgängig".
    private func discardUndoLater() async {
        guard let id = model.removedLine?.id else { return }
        try? await Task.sleep(for: .seconds(isVoiceOverEnabled ? 12 : 6))
        guard !Task.isCancelled, model.removedLine?.id == id else { return }
        model.discardUndo()
    }
}

// MARK: - CartContent

/// The scrolling content of a cart with lines.
private struct CartContent: View {
    let cart: Cart
    let model: CartViewModel
    let onRoute: @MainActor (CommerceRoute) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KXSpacing.xl) {
                VStack(alignment: .leading, spacing: KXSpacing.l) {
                    ForEach(model.generalWarnings, id: \.self) { warning in
                        KXBanner(.info, message: warning)
                            .accessibilityIdentifier("cart.warning")
                    }
                    CartLinesSection(cart: cart, model: model, onRoute: onRoute)
                    CartDiscountSection(cart: cart, model: model)
                    CartSummaryCard(cart: cart)
                    CartPaymentMethods()
                    CartDigitalNotice()
                }
                .padding(.horizontal, KXSpacing.gutter)
                ProductCarouselSection(
                    title: String(localized: "cart.crosssell.title", bundle: .module),
                    state: model.crossSell,
                    retry: { await model.reloadCrossSell() },
                    onSelect: { product in onRoute(.product(handle: product.handle)) }
                )
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("cart.crosssell")
            }
            .padding(.vertical, KXSpacing.m)
        }
        .scrollDismissesKeyboard(.interactively)
        .refreshable {
            await model.refresh()
        }
    }
}

// MARK: - CartEmptyContent

/// The empty cart: the way back into the range, the payment methods and the notice.
private struct CartEmptyContent: View {
    let onBrowse: @MainActor () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KXSpacing.xl) {
                KXEmptyState(
                    systemImage: "bag",
                    title: String(localized: "cart.empty.title", bundle: .module),
                    message: String(localized: "cart.empty.message", bundle: .module),
                    actionTitle: String(localized: "cart.empty.action", bundle: .module),
                    action: { onBrowse() }
                )
                .accessibilityIdentifier("cart.empty")
                CartPaymentMethods()
                CartDigitalNotice()
            }
            .padding(.horizontal, KXSpacing.gutter)
            .padding(.vertical, KXSpacing.m)
        }
    }
}

// MARK: - CartSkeleton

/// The placeholder while a stored cart loads: three line skeletons and a summary block.
private struct CartSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.l) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(alignment: .top, spacing: KXSpacing.m) {
                    KXSkeleton(cornerRadius: KXRadius.small)
                        .aspectRatio(CartLineRow.photoAspectRatio, contentMode: .fit)
                        .frame(width: KXSpacing.xxxl * 2)
                    VStack(alignment: .leading, spacing: KXSpacing.xs) {
                        KXSkeleton()
                            .frame(height: KXSpacing.m)
                        KXSkeleton()
                            .frame(height: KXSpacing.m)
                            .padding(.trailing, KXSpacing.xxl)
                        KXSkeleton()
                            .frame(width: KXSpacing.xxxl, height: KXSpacing.m)
                    }
                }
            }
            KXSkeleton(cornerRadius: KXRadius.card)
                .frame(height: KXSpacing.xxxl * 2)
        }
        .padding(KXSpacing.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("cart.loading", bundle: .module))
    }
}

// MARK: - Previews

#if DEBUG
#Preview("CartView, empty") {
    NavigationStack {
        CartView(
            cartStore: CartPreviewData.emptyStore(),
            catalog: CartPreviewCatalog(),
            onRoute: { _ in },
            onBrowse: {},
            onCheckout: {}
        )
    }
}

#Preview("CartView, lines") {
    NavigationStack {
        CartView(
            cartStore: CartPreviewData.filledStore(),
            catalog: CartPreviewCatalog(),
            onRoute: { _ in },
            onBrowse: {},
            onCheckout: {}
        )
    }
}

#Preview("CartView, dark") {
    NavigationStack {
        CartView(
            cartStore: CartPreviewData.filledStore(),
            catalog: CartPreviewCatalog(),
            onRoute: { _ in },
            onBrowse: {},
            onCheckout: {}
        )
    }
    .preferredColorScheme(.dark)
}

#Preview("CartView, accessibility size") {
    NavigationStack {
        CartView(
            cartStore: CartPreviewData.filledStore(),
            catalog: CartPreviewCatalog(),
            onRoute: { _ in },
            onBrowse: {},
            onCheckout: {}
        )
    }
    .dynamicTypeSize(.accessibility2)
}
#endif
