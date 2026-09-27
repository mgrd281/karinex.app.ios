import DesignSystem
import SwiftUI

// MARK: - CartView

/// The Warenkorb tab.
///
/// Phase 0 has no cart yet, so the screen shows the real empty state ("Ihr Warenkorb ist leer")
/// with the way back into the range, the payment methods the store offers (Apple Pay,
/// Kreditkarte, Klarna) and the notice on the right of withdrawal for digital content
/// (§ 356 Abs. 5 BGB), which the cart must always show (PROMPT.md section 2). Line items,
/// totals, discount codes and "Zur Kasse" arrive in Phase 1.
///
/// Place it inside a `NavigationStack`; it uses a large title.
public struct CartView: View {
    private let onBrowse: @MainActor () -> Void

    /// Creates the cart screen.
    ///
    /// - Parameter onBrowse: Called by "Zum Sortiment" in the empty state, typically switching
    ///   to the Shop tab.
    public init(onBrowse: @escaping @MainActor () -> Void) {
        self.onBrowse = onBrowse
    }

    public var body: some View {
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
                paymentMethodsCard
                digitalContentNotice
            }
            .padding(.horizontal, KXSpacing.gutter)
            .padding(.vertical, KXSpacing.m)
        }
        .accessibilityIdentifier("screen.cart")
        .kxScreenBackground()
        .navigationTitle(Text("cart.title", bundle: .module))
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: Parts

    /// The payment methods of the store, as text only.
    private var paymentMethodsCard: some View {
        KXCard {
            HStack(alignment: .firstTextBaseline, spacing: KXSpacing.s) {
                Image(systemName: "creditcard")
                    .fontWeight(.medium)
                    .kxFont(.body)
                    .foregroundStyle(KXColor.brand)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                    Text("cart.payment.title", bundle: .module)
                        .kxFont(.eyebrow)
                        .foregroundStyle(KXColor.accentText)
                    Text("cart.payment.methods", bundle: .module)
                        .kxFont(.body)
                        .foregroundStyle(KXColor.textPrimary)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .combine)
        }
        .accessibilityIdentifier("cart.payment")
    }

    /// The right-of-withdrawal notice for digital content, set as a footnote.
    private var digitalContentNotice: some View {
        VStack(alignment: .leading, spacing: KXSpacing.xxs) {
            Text("cart.notice.title", bundle: .module)
                .kxFont(.eyebrow)
                .foregroundStyle(KXColor.textSecondary)
            Text("cart.notice.digital", bundle: .module)
                .kxFont(.footnote)
                .foregroundStyle(KXColor.textSecondary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("cart.notice.digital")
    }
}

// MARK: - Previews

#Preview("CartView, light") {
    NavigationStack {
        CartView(onBrowse: {})
    }
}

#Preview("CartView, dark") {
    NavigationStack {
        CartView(onBrowse: {})
    }
    .preferredColorScheme(.dark)
}

#Preview("CartView, accessibility size") {
    NavigationStack {
        CartView(onBrowse: {})
    }
    .dynamicTypeSize(.accessibility2)
}
