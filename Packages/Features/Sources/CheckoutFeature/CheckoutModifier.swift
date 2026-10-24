import CommerceUI
import DesignSystem
@preconcurrency import ShopifyCheckoutSheetKit
import SwiftUI

// MARK: - kxCheckout

extension View {
    /// Presents Shopify checkout for the cart of `cartStore` while `isPresented` is `true`
    /// (PROMPT.md sections 5.3 and 6.6).
    ///
    /// - Setting `isPresented` to `true` fetches a fresh checkout URL from
    ///   `CartStore.checkoutURL()` ("Kasse wird vorbereitet" meanwhile) and presents Checkout
    ///   Kit's sheet with the KARINEX branding.
    /// - On completion the order is converted to ``CompletedOrder``, the cart is cleared, a
    ///   success haptic plays and the sheet shows ``OrderSuccessScreen``. "Weiter einkaufen"
    ///   closes it and calls `onCompleted`.
    /// - On cancel the sheet closes and the cart stays as it is.
    /// - On failure the sheet closes. An expired checkout is retried once with a fresh URL;
    ///   otherwise an error explains what happened and offers "Erneut versuchen" when trying
    ///   again makes sense.
    /// - Links that leave checkout (for example to Klarna) open with `openURL`.
    ///
    /// `isPresented` returns to `false` when the flow ends.
    ///
    /// ```swift
    /// RootView()
    ///     .kxCheckout(isPresented: $isCheckoutPresented, cartStore: cartStore) { _ in
    ///         selectedTab = .home
    ///     }
    /// ```
    ///
    /// - Parameters:
    ///   - isPresented: Whether the checkout flow runs.
    ///   - cartStore: The app's cart.
    ///   - onCompleted: Called with the order after the success screen was closed.
    public func kxCheckout(
        isPresented: Binding<Bool>,
        cartStore: CartStore,
        onCompleted: @escaping @MainActor (CompletedOrder) -> Void
    ) -> some View {
        modifier(CheckoutModifier(isPresented: isPresented, cartStore: cartStore, onCompleted: onCompleted))
    }
}

// MARK: - CheckoutModifier

/// The view side of ``CheckoutCoordinator``: the preparing overlay, the sheet and the error.
private struct CheckoutModifier: ViewModifier {
    @Binding var isPresented: Bool
    @State private var coordinator: CheckoutCoordinator

    init(isPresented: Binding<Bool>, cartStore: CartStore, onCompleted: @escaping @MainActor (CompletedOrder) -> Void) {
        _isPresented = isPresented
        _coordinator = State(initialValue: CheckoutCoordinator(
            urlProvider: { try await cartStore.checkoutURL() },
            onOrderCompleted: { _ in cartStore.clearAfterCheckout() },
            onSuccessFinished: onCompleted
        ))
    }

    func body(content: Content) -> some View {
        content
            .overlay {
                if coordinator.isPreparing {
                    CheckoutPreparingOverlay()
                        .transition(.opacity)
                }
            }
            .kxAnimation(.fade, value: coordinator.isPreparing)
            .sheet(
                item: $coordinator.presentation,
                onDismiss: { coordinator.sheetDidDismiss() },
                content: { presentation in
                    CheckoutSheetContent(presentation: presentation, coordinator: coordinator)
                }
            )
            .alert(
                coordinator.alert?.title ?? String(),
                isPresented: Binding(
                    get: { coordinator.alert != nil },
                    set: { isShown in
                        if !isShown {
                            coordinator.dismissAlert()
                        }
                    }
                ),
                presenting: coordinator.alert
            ) { alert in
                if alert.canRetry {
                    Button {
                        coordinator.retryFromAlert()
                    } label: {
                        Text("checkout.error.retry", bundle: .module)
                    }
                }
                Button(role: .cancel) {
                    coordinator.dismissAlert()
                } label: {
                    Text("checkout.error.close", bundle: .module)
                }
            } message: { alert in
                Text(verbatim: alert.message)
            }
            .onChange(of: isPresented, initial: true) { _, presented in
                if presented {
                    coordinator.start()
                }
            }
            .onChange(of: coordinator.isActive) { _, active in
                if !active, isPresented {
                    isPresented = false
                }
            }
    }
}

// MARK: - CheckoutSheetContent

/// The content of the checkout sheet: Checkout Kit's checkout, then the success screen.
private struct CheckoutSheetContent: View {
    let presentation: CheckoutPresentation
    let coordinator: CheckoutCoordinator

    @Environment(\.locale) private var locale
    @Environment(\.openURL) private var openURL

    var body: some View {
        Group {
            if let order = coordinator.completedOrder {
                OrderSuccessScreen(order: order, onContinue: { coordinator.finishSuccess() })
            } else {
                checkout
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("checkout.sheet")
        .sensoryFeedback(.success, trigger: coordinator.completedOrder)
    }

    private var checkout: some View {
        CheckoutSheet(checkout: presentation.url)
            .title(CheckoutConfiguration.title)
            .colorScheme(.automatic)
            .tintColor(CheckoutConfiguration.tintColor)
            .backgroundColor(CheckoutConfiguration.backgroundColor)
            .closeButtonTintColor(CheckoutConfiguration.tintColor)
            .onComplete { event in
                coordinator.handleCompletion(CompletedOrder(event: event, locale: locale))
            }
            .onCancel {
                coordinator.handleCancel()
            }
            .onFail { error in
                coordinator.handleFailure(CheckoutFailure(error: error))
            }
            .onLinkClick { url in
                openURL(url)
            }
            .ignoresSafeArea(edges: .bottom)
    }
}

// MARK: - CheckoutPreparingOverlay

/// "Kasse wird vorbereitet" over a dimmed screen while the fresh checkout URL loads. It blocks
/// taps, so the cart cannot change underneath.
private struct CheckoutPreparingOverlay: View {
    var body: some View {
        ZStack {
            KXColor.scrim
                .opacity(0.35)
                .ignoresSafeArea()
            KXCard(style: .elevated) {
                HStack(spacing: KXSpacing.s) {
                    ProgressView()
                        .tint(KXColor.brand)
                    Text("checkout.preparing", bundle: .module)
                        .kxFont(.callout)
                        .foregroundStyle(KXColor.textPrimary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(KXSpacing.xl)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
        .accessibilityIdentifier("checkout.preparing")
    }
}
