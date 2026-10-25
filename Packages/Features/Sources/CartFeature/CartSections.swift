import CommerceUI
import DesignSystem
import ShopifyKit
import SwiftUI

// MARK: - CartDiscountSection

/// The discount code field with "Anwenden", the codes in the cart (each removable) and the
/// feedback of the last attempt, including Shopify's own message when a code does not apply.
struct CartDiscountSection: View {
    let cart: Cart
    let model: CartViewModel

    @FocusState private var isFieldFocused: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        @Bindable var model = model
        KXCard {
            VStack(alignment: .leading, spacing: KXSpacing.s) {
                Text("cart.discount.title", bundle: .module)
                    .kxFont(.eyebrow)
                    .foregroundStyle(KXColor.accentText)
                    .accessibilityAddTraits(.isHeader)
                fieldRow(code: $model.discountCode)
                if let feedback = model.discountFeedback {
                    feedbackText(feedback)
                }
                ForEach(cart.discountCodes, id: \.code) { code in
                    codeRow(code)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cart.discount")
    }

    // MARK: Parts

    private func fieldRow(code: Binding<String>) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: KXSpacing.xs))
            : AnyLayout(HStackLayout(spacing: KXSpacing.s))
        return layout {
            TextField(text: code) {
                Text("cart.discount.placeholder", bundle: .module)
            }
            .kxFont(.body)
            .foregroundStyle(KXColor.textPrimary)
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
            .submitLabel(.done)
            .focused($isFieldFocused)
            .onSubmit(apply)
            .onChange(of: code.wrappedValue) {
                if model.discountFeedback != nil {
                    model.clearDiscountFeedback()
                }
            }
            .padding(.horizontal, KXSpacing.s)
            .frame(minHeight: KXSpacing.minimumTapTarget)
            .background {
                RoundedRectangle(cornerRadius: KXRadius.small, style: .continuous)
                    .fill(KXColor.background)
            }
            .overlay {
                RoundedRectangle(cornerRadius: KXRadius.small, style: .continuous)
                    .strokeBorder(isFieldFocused ? KXColor.brand : KXColor.hairline, lineWidth: KXBorder.regular)
            }
            .accessibilityLabel(Text("cart.discount.title", bundle: .module))
            .accessibilityIdentifier("cart.discount.field")
            KXButton(
                String(localized: "cart.discount.apply", bundle: .module),
                style: .secondary,
                size: .compact,
                isLoading: model.isApplyingDiscount,
                action: apply
            )
            .disabled(!model.canApplyDiscount)
            .accessibilityIdentifier("cart.discount.apply")
        }
    }

    private func feedbackText(_ feedback: CartDiscountFeedback) -> some View {
        Group {
            switch feedback {
            case let .applied(code):
                Label {
                    Text("cart.discount.applied \(code)", bundle: .module)
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(KXColor.success)
                }
                .foregroundStyle(KXColor.textPrimary)
            case let .notApplicable(message):
                Label {
                    if let message {
                        Text(verbatim: message)
                    } else {
                        Text("cart.discount.not_applicable", bundle: .module)
                    }
                } icon: {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(KXColor.info)
                }
                .foregroundStyle(KXColor.textPrimary)
            case let .failed(error):
                Label {
                    Text(verbatim: error.message)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(KXColor.error)
                }
                .foregroundStyle(KXColor.textPrimary)
            }
        }
        .kxFont(.footnote)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("cart.discount.message")
    }

    private func codeRow(_ code: CartDiscountCode) -> some View {
        HStack(spacing: KXSpacing.s) {
            Image(systemName: "tag")
                .foregroundStyle(KXColor.brand)
                .accessibilityHidden(true)
            Text(verbatim: code.code)
                .kxFont(.callout)
                .foregroundStyle(KXColor.textPrimary)
            if code.applicable {
                KXBadge(String(localized: "cart.discount.active", bundle: .module), style: .success)
            } else {
                KXBadge(String(localized: "cart.discount.inactive", bundle: .module), style: .neutral)
            }
            Spacer(minLength: KXSpacing.xs)
            Button {
                Task { await model.removeDiscount(code.code) }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .kxFont(.body)
                    .foregroundStyle(KXColor.iconSecondary)
                    .frame(width: KXSpacing.minimumTapTarget, height: KXSpacing.minimumTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("cart.discount.remove \(code.code)", bundle: .module))
            .accessibilityIdentifier("cart.discount.remove")
        }
        .accessibilityElement(children: .contain)
    }

    private func apply() {
        guard model.canApplyDiscount else { return }
        isFieldFocused = false
        Task { await model.applyDiscount() }
    }
}

// MARK: - CartSummaryCard

/// Subtotal, discount and total exactly as Shopify returns them for the market, with the tax
/// note ("inkl. MwSt." in EU markets, "zzgl. Versand" only for physical items).
struct CartSummaryCard: View {
    let cart: Cart

    @Environment(\.locale) private var locale
    @Environment(\.commerceCountry) private var country

    var body: some View {
        KXCard(style: .elevated) {
            VStack(alignment: .leading, spacing: KXSpacing.s) {
                row(
                    title: Text("cart.summary.subtotal", bundle: .module),
                    value: Text(verbatim: cart.cost.subtotalAmount.formatted(locale: locale))
                )
                .accessibilityIdentifier("cart.subtotal")
                if let discount = cart.discountTotal {
                    row(
                        title: Text("cart.summary.discount", bundle: .module),
                        value: Text("cart.summary.discount.value \(discount.formatted(locale: locale))", bundle: .module)
                    )
                    .accessibilityIdentifier("cart.discountTotal")
                }
                KXDivider()
                totalRow
                if let note = PriceDisplay.taxNote(country: country, requiresShipping: cart.requiresShipping) {
                    Text(verbatim: note.text)
                        .kxFont(.footnote)
                        .foregroundStyle(KXColor.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cart.summary")
    }

    private var totalRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                totalTitle
                Spacer(minLength: KXSpacing.s)
                totalValue
            }
            VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                totalTitle
                totalValue
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("cart.total")
    }

    private var totalTitle: some View {
        Text("cart.summary.total", bundle: .module)
            .kxFont(.headline)
            .foregroundStyle(KXColor.textPrimary)
    }

    private var totalValue: some View {
        Text(verbatim: cart.cost.totalAmount.formatted(locale: locale))
            .kxFont(.price)
            .foregroundStyle(KXColor.textPrimary)
    }

    private func row(title: Text, value: Text) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                title
                Spacer(minLength: KXSpacing.s)
                value
            }
            VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                title
                value
            }
        }
        .kxFont(.body)
        .foregroundStyle(KXColor.textPrimary)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - CartPaymentMethods

/// The store's payment methods with their real acceptance marks (Apple Pay, the card brands
/// Shopify reports, Klarna), from the app's ``PaymentMethodsStore``; the business facts while it
/// loads and in previews.
struct CartPaymentMethods: View {
    @Environment(PaymentMethodsStore.self) private var paymentMethods: PaymentMethodsStore?

    var body: some View {
        PaymentMethodsRow(
            methods: paymentMethods?.methods ?? PaymentMethod.fallback,
            title: String(localized: "cart.payment.title", bundle: .module)
        )
        .accessibilityIdentifier("cart.payment")
        .task {
            await paymentMethods?.loadIfNeeded()
        }
    }
}

// MARK: - CartDigitalNotice

/// The right-of-withdrawal notice for digital content, set as a footnote.
struct CartDigitalNotice: View {
    var body: some View {
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

// MARK: - CartUndoBar

/// The bar after removing a line: "<Produkt> wurde entfernt." with "Rückgängig".
struct CartUndoBar: View {
    let title: String
    let onUndo: @MainActor () -> Void
    let onDismiss: @MainActor () -> Void

    var body: some View {
        HStack(spacing: KXSpacing.s) {
            Text("cart.undo.message \(title)", bundle: .module)
                .kxFont(.subheadline)
                .foregroundStyle(KXColor.textPrimary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
            KXButton(String(localized: "cart.undo.action", bundle: .module), style: .tertiary, size: .compact) {
                onUndo()
            }
            .accessibilityIdentifier("cart.undo")
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .fontWeight(.semibold)
                    .kxFont(.footnote)
                    .foregroundStyle(KXColor.textSecondary)
                    .frame(width: KXSpacing.minimumTapTarget, height: KXSpacing.minimumTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("cart.undo.dismiss", bundle: .module))
        }
        .padding(.leading, KXSpacing.m)
        .padding(.vertical, KXSpacing.xxs)
        .background {
            RoundedRectangle(cornerRadius: KXRadius.medium, style: .continuous)
                .fill(KXColor.surfaceElevated)
                .shadow(color: KXColor.scrim.opacity(0.16), radius: KXSpacing.s, x: 0, y: 2)
        }
        .padding(.horizontal, KXSpacing.gutter)
        .padding(.bottom, KXSpacing.s)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cart.undoBar")
    }
}

// MARK: - CartCheckoutBar

/// The sticky bar at the bottom: the total from Shopify and "Zur Kasse".
struct CartCheckoutBar: View {
    let cart: Cart
    let onCheckout: @MainActor () -> Void

    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.s) {
            HStack(alignment: .firstTextBaseline) {
                Text("cart.summary.total", bundle: .module)
                    .kxFont(.subheadline)
                    .foregroundStyle(KXColor.textSecondary)
                Spacer(minLength: KXSpacing.s)
                Text(verbatim: cart.cost.totalAmount.formatted(locale: locale))
                    .kxFont(.headline)
                    .foregroundStyle(KXColor.textPrimary)
            }
            .accessibilityElement(children: .combine)
            KXButton(
                String(localized: "cart.checkout", bundle: .module),
                systemImage: "lock",
                isFullWidth: true
            ) {
                onCheckout()
            }
            .accessibilityIdentifier("cart.checkout")
        }
        .padding(.horizontal, KXSpacing.gutter)
        .padding(.top, KXSpacing.s)
        .padding(.bottom, KXSpacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            KXColor.surfaceElevated
                .ignoresSafeArea(edges: .bottom)
                .shadow(color: KXColor.scrim.opacity(0.12), radius: KXSpacing.s, x: 0, y: -2)
        }
        .overlay(alignment: .top) {
            KXDivider()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cart.checkoutBar")
    }
}
