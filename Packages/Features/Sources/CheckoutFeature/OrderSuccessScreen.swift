import DesignSystem
import SwiftUI

// MARK: - OrderSuccessScreen

/// The confirmation after a completed checkout (PROMPT.md section 6.6): "Bestellung
/// eingegangen", the delivery expectation ("Ihr Lizenzschlüssel wird per E-Mail zugestellt."),
/// the order total as Shopify reported it and "Weiter einkaufen".
///
/// The orders button arrives with the accounts in Phase 2.
public struct OrderSuccessScreen: View {
    private let order: CompletedOrder
    private let onContinue: @MainActor () -> Void

    @ScaledMetric(relativeTo: .largeTitle) private var symbolSize: CGFloat = 44
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isShown = false

    /// Creates the screen.
    ///
    /// - Parameters:
    ///   - order: The completed order.
    ///   - onContinue: Called by "Weiter einkaufen".
    public init(order: CompletedOrder, onContinue: @escaping @MainActor () -> Void) {
        self.order = order
        self.onContinue = onContinue
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: KXSpacing.xl) {
                seal
                VStack(spacing: KXSpacing.s) {
                    Text("checkout.success.eyebrow", bundle: .module)
                        .kxFont(.eyebrow)
                        .foregroundStyle(KXColor.accentText)
                    Text("checkout.success.title", bundle: .module)
                        .kxFont(.title1)
                        .foregroundStyle(KXColor.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("orderSuccess.title")
                    Text("checkout.success.message", bundle: .module)
                        .kxFont(.body)
                        .foregroundStyle(KXColor.textSecondary)
                }
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                if let total = order.formattedTotal {
                    KXCard {
                        KXSpecRow(String(localized: "checkout.success.total", bundle: .module), value: total)
                    }
                    .accessibilityIdentifier("orderSuccess.total")
                }
                KXButton(String(localized: "checkout.success.continue", bundle: .module), isFullWidth: true) {
                    onContinue()
                }
                .accessibilityIdentifier("orderSuccess.continue")
            }
            .padding(.horizontal, KXSpacing.gutter)
            .padding(.vertical, KXSpacing.xxl)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .kxScreenBackground()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.orderSuccess")
        .onAppear {
            isShown = true
        }
    }

    /// The checkmark in a gold ring, scaling in once (a fade with Reduce Motion). Ring and
    /// symbol grow with Dynamic Type up to 120 pt and 48 pt.
    private var seal: some View {
        let symbol = min(symbolSize, 48)
        let diameter = min(symbolSize * 2.2, 120)
        return Image(systemName: "checkmark")
            .font(.system(size: symbol, weight: .semibold))
            .foregroundStyle(KXColor.brand)
            .frame(width: diameter, height: diameter)
            .background {
                Circle()
                    .fill(KXColor.surface)
            }
            .overlay {
                Circle()
                    .strokeBorder(KXColor.accent, lineWidth: KXBorder.regular)
            }
            .scaleEffect(isShown || reduceMotion ? 1 : 0.8)
            .opacity(isShown ? 1 : 0)
            .animation(KXMotion.animation(.gentle, reduceMotion: reduceMotion), value: isShown)
            .accessibilityHidden(true)
    }
}

// MARK: - Previews

#Preview("OrderSuccessScreen") {
    OrderSuccessScreen(
        order: CompletedOrder(id: "gid://shopify/OrderIdentity/1", hasEmail: true, formattedTotal: "29,90 €"),
        onContinue: {}
    )
}

#Preview("OrderSuccessScreen, dark, accessibility size") {
    OrderSuccessScreen(
        order: CompletedOrder(id: "gid://shopify/OrderIdentity/1", hasEmail: true, formattedTotal: "29,90 €"),
        onContinue: {}
    )
    .preferredColorScheme(.dark)
    .dynamicTypeSize(.accessibility2)
}
