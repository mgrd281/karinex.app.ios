import CommerceUI
import DesignSystem
import ShopifyKit
import SwiftUI

// MARK: - ProductPurchaseBar

/// The sticky bar at the bottom of the product screen, as at About You: the price of the
/// selected variant with its tax note on the leading side and the black "In den Warenkorb"
/// button with small rounded corners on the trailing side, on a white bar. The compare-at price
/// and the savings stay in the summary above, so the bar stays calm.
///
/// A sold-out variant gets "Benachrichtigen" instead (owner request 2026-10-28): the backend
/// sends a message to "Neuigkeiten" and, with consent, a notification once the variant is
/// available again; a second tap cancels the request.
///
/// The button is disabled while the variant cannot be bought or an add is running. When price
/// and button do not fit side by side (long translations, large text sizes) the button moves
/// below the price at full width, so nothing is cut off.
struct ProductPurchaseBar: View {
    let variant: ProductVariant
    let productHandle: String
    let productTitle: String
    let isAdding: Bool
    let onAddToCart: @MainActor () -> Void

    @Environment(InboxStore.self) private var inbox: InboxStore?
    @State private var isUpdatingWatch = false
    @State private var watchFailed = false

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: KXSpacing.l) {
                price
                    .fixedSize()
                addButton
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: KXSpacing.s) {
                price
                addButton
            }
        }
        .kxButtonCornerRadius(KXRadius.small)
        .padding(.horizontal, KXSpacing.gutter)
        .padding(.top, KXSpacing.s)
        .padding(.bottom, KXSpacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            KXColor.background
                .ignoresSafeArea(edges: .bottom)
        }
        .overlay(alignment: .top) {
            KXDivider()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("product.bar")
    }

    private var price: some View {
        PriceText(
            price: variant.price,
            requiresShipping: variant.requiresShipping,
            showsSavings: false
        )
        .accessibilityIdentifier("product.bar.price")
    }

    @ViewBuilder
    private var addButton: some View {
        if !variant.availableForSale, let inbox {
            restockButton(inbox)
        } else {
            cartButton
        }
    }

    private func restockButton(_ inbox: InboxStore) -> some View {
        let watching = inbox.isWatching(variantID: variant.id.rawValue)
        return KXButton(
            String(localized: watching ? "product.restock.watching" : "product.restock.notify", bundle: .module),
            systemImage: watching ? "bell.fill" : "bell",
            style: watching ? .secondary : .primary,
            isFullWidth: true,
            isLoading: isUpdatingWatch
        ) {
            Task {
                isUpdatingWatch = true
                let ok = await inbox.setWatching(
                    !watching,
                    productHandle: productHandle,
                    variantID: variant.id.rawValue,
                    productTitle: productTitle
                )
                isUpdatingWatch = false
                watchFailed = !ok
            }
        }
        .sensoryFeedback(.success, trigger: inbox.isWatching(variantID: variant.id.rawValue))
        .alert(Text("product.restock.failed", bundle: .module), isPresented: $watchFailed) {
            Button(String(localized: "product.restock.ok", bundle: .module), role: .cancel) {}
        }
        .accessibilityIdentifier("product.restock")
    }

    private var cartButton: some View {
        KXButton(
            String(localized: "product.cart.add", bundle: .module),
            isFullWidth: true,
            isLoading: isAdding
        ) {
            onAddToCart()
        }
        .disabled(!variant.availableForSale || isAdding)
        .accessibilityIdentifier("product.addToCart")
    }
}
