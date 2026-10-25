import CommerceUI
import DesignSystem
import ShopifyKit
import SwiftUI

// MARK: - CartLinesSection

/// The lines of the cart, separated by hairlines, in one card.
struct CartLinesSection: View {
    let cart: Cart
    let model: CartViewModel
    let onRoute: @MainActor (CommerceRoute) -> Void

    var body: some View {
        KXCard {
            VStack(alignment: .leading, spacing: KXSpacing.m) {
                ForEach(Array(cart.lines.enumerated()), id: \.element.id) { index, line in
                    if index > 0 {
                        KXDivider()
                    }
                    CartLineRow(line: line, model: model, onRoute: onRoute)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cart.lines")
    }
}

// MARK: - CartLineRow

/// One line: image, product title (opens the product), variant, unit price with the
/// compare-at price, the line total for more than one unit, the quantity control and the
/// remove button.
struct CartLineRow: View {
    /// The edge length of the line image.
    static let imageSize: CGFloat = 72

    let line: CartLine
    let model: CartViewModel
    let onRoute: @MainActor (CommerceRoute) -> Void

    @Environment(\.locale) private var locale
    @Environment(\.commerceCountry) private var country
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.s) {
            HStack(alignment: .top, spacing: KXSpacing.m) {
                if !dynamicTypeSize.isAccessibilitySize {
                    image
                }
                details
            }
            controls
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cart.line.\(line.merchandise.product.handle)")
    }

    // MARK: Parts

    private var image: some View {
        ProductImage(line.merchandise.image, contentMode: .fit, isDecorative: true)
            .kxPhotoTile()
            .frame(width: Self.imageSize, height: Self.imageSize)
            .clipShape(RoundedRectangle(cornerRadius: KXRadius.small, style: .continuous))
            .accessibilityHidden(true)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: KXSpacing.xxs) {
            Button {
                onRoute(.product(handle: line.merchandise.product.handle))
            } label: {
                Text(verbatim: line.merchandise.product.title)
                    .kxFont(.headline)
                    .foregroundStyle(KXColor.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: KXSpacing.minimumTapTarget, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isLink)
            if let variant = CartLinePresentation.variantText(for: line.merchandise) {
                Text(verbatim: variant)
                    .kxFont(.subheadline)
                    .foregroundStyle(KXColor.textSecondary)
            }
            price
            if !line.merchandise.availableForSale {
                Text("cart.line.unavailable", bundle: .module)
                    .kxFont(.footnote)
                    .foregroundStyle(KXColor.urgencyText)
            }
        }
    }

    private var price: some View {
        let display = PriceDisplay(
            price: line.cost.amountPerQuantity,
            compareAtPrice: line.cost.compareAtAmountPerQuantity ?? line.merchandise.compareAtPrice,
            country: country,
            requiresShipping: line.merchandise.requiresShipping,
            locale: locale
        )
        let quantity = model.quantity(of: line)
        return VStack(alignment: .leading, spacing: KXSpacing.xxs) {
            KXPriceTag(
                price: display.price,
                compareAtPrice: display.compareAtPrice,
                savings: display.savingsText,
                size: .compact
            )
            if quantity > 1 {
                Text("cart.line.total \(line.cost.totalAmount.formatted(locale: locale))", bundle: .module)
                    .kxFont(.footnote)
                    .foregroundStyle(KXColor.textSecondary)
                    .accessibilityIdentifier("cart.line.total")
            }
        }
    }

    private var controls: some View {
        HStack(spacing: KXSpacing.s) {
            CartQuantityControl(line: line, model: model)
            Spacer(minLength: KXSpacing.xs)
            Button {
                Task { await model.remove(line) }
            } label: {
                Label {
                    Text("cart.line.remove", bundle: .module)
                } icon: {
                    Image(systemName: "trash")
                }
                .kxFont(.subheadline)
                .foregroundStyle(KXColor.textSecondary)
                .frame(minWidth: KXSpacing.minimumTapTarget, minHeight: KXSpacing.minimumTapTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("cart.line.remove.label \(line.merchandise.product.title)", bundle: .module))
            .accessibilityIdentifier("cart.remove")
        }
    }
}

// MARK: - CartQuantityControl

/// "-", the quantity and "+" in a capsule. The quantity stays within 1 to 10; the last unit
/// leaves the cart with the remove button.
struct CartQuantityControl: View {
    let line: CartLine
    let model: CartViewModel

    var body: some View {
        let quantity = model.quantity(of: line)
        HStack(spacing: 0) {
            stepButton(
                systemImage: "minus",
                label: Text("cart.line.decrease", bundle: .module),
                identifier: "cart.quantity.decrease",
                isEnabled: model.canDecrease(line)
            ) {
                await model.decrease(line)
            }
            Text(quantity, format: .number)
                .kxFont(.headline)
                .monospacedDigit()
                .foregroundStyle(KXColor.textPrimary)
                .frame(minWidth: KXSpacing.xl)
                .contentTransition(.numericText())
                .accessibilityLabel(Text("cart.line.quantity \(quantity)", bundle: .module))
                .accessibilityIdentifier("cart.quantity.value")
            stepButton(
                systemImage: "plus",
                label: Text("cart.line.increase", bundle: .module),
                identifier: "cart.quantity.increase",
                isEnabled: model.canIncrease(line)
            ) {
                await model.increase(line)
            }
        }
        .background {
            Capsule()
                .strokeBorder(KXColor.hairline, lineWidth: KXBorder.regular)
        }
        .kxAnimation(.snappy, value: quantity)
        .sensoryFeedback(.selection, trigger: quantity)
    }

    private func stepButton(
        systemImage: String,
        label: Text,
        identifier: String,
        isEnabled: Bool,
        action: @escaping @MainActor () async -> Void
    ) -> some View {
        Button {
            Task { await action() }
        } label: {
            Image(systemName: systemImage)
                .fontWeight(.semibold)
                .kxFont(.body)
                .foregroundStyle(isEnabled ? KXColor.brand : KXColor.textTertiary)
                .frame(width: KXSpacing.minimumTapTarget, height: KXSpacing.minimumTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
}

// MARK: - CartLinePresentation

/// Text rules of a cart line.
enum CartLinePresentation {
    /// The variant shown below the product title: the selected option values (without
    /// Shopify's "Default Title"), or the variant title when it differs from the product's.
    /// `nil` for single-variant products.
    static func variantText(for merchandise: CartMerchandise) -> String? {
        let options = merchandise.visibleOptions.map(\.value).filter { !$0.isEmpty }
        if !options.isEmpty {
            return options.joined(separator: ", ")
        }
        let title = merchandise.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title != "Default Title", title != merchandise.product.title else { return nil }
        return title
    }
}
