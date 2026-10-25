import CommerceUI
import DesignSystem
import ShopifyKit
import SwiftUI

// MARK: - CartLinesSection

/// The lines of the cart as a list separated by hairlines, like the lists of fashion retail
/// apps.
struct CartLinesSection: View {
    let cart: Cart
    let model: CartViewModel
    let onRoute: @MainActor (CommerceRoute) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.m) {
            ForEach(Array(cart.lines.enumerated()), id: \.element.id) { index, line in
                if index > 0 {
                    KXDivider()
                }
                CartLineRow(line: line, model: model, onRoute: onRoute)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cart.lines")
    }
}

// MARK: - CartLineRow

/// One line, laid out like the product lists of fashion retail apps: the photo on its light
/// tile with the reduction ("-80 %") in sale red at its lower edge; beside it the vendor in
/// capitals, the product title, the variant, the price (sale red when reduced) with the former
/// price below it and the line total for more than one unit, and the quantity control; an "x"
/// at the top right removes the line. The photo and the texts open the product.
struct CartLineRow: View {
    /// Width to height of the photo: a little taller than wide.
    static let photoAspectRatio: CGFloat = 5 / 6

    let line: CartLine
    let model: CartViewModel
    let onRoute: @MainActor (CommerceRoute) -> Void

    @Environment(\.locale) private var locale
    @Environment(\.commerceCountry) private var country
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var scaledPhotoWidth: CGFloat = 112

    private var photoWidth: CGFloat {
        min(scaledPhotoWidth, 160)
    }

    var body: some View {
        let display = PriceDisplay(
            price: line.cost.amountPerQuantity,
            compareAtPrice: line.cost.compareAtAmountPerQuantity ?? line.merchandise.compareAtPrice,
            country: country,
            requiresShipping: line.merchandise.requiresShipping,
            locale: locale
        )
        HStack(alignment: .top, spacing: KXSpacing.m) {
            if !dynamicTypeSize.isAccessibilitySize {
                photo(savings: display.savingsText)
            }
            VStack(alignment: .leading, spacing: KXSpacing.s) {
                HStack(alignment: .top, spacing: KXSpacing.xs) {
                    details(display)
                    removeButton
                }
                CartQuantityControl(line: line, model: model)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cart.line.\(line.merchandise.product.handle)")
    }

    // MARK: Parts

    /// The photo with the reduction; opens the product like the texts beside it.
    private func photo(savings: String?) -> some View {
        Button {
            openProduct()
        } label: {
            ProductImage(line.merchandise.image, isDecorative: true)
                .padding(KXSpacing.xs)
                .kxPhotoTile()
                .frame(width: photoWidth, height: photoWidth / Self.photoAspectRatio)
                .overlay(alignment: .bottomLeading) {
                    if let savings {
                        Text(verbatim: savings)
                            .fontWeight(.semibold)
                            .kxFont(.caption)
                            .foregroundStyle(KXColor.textOnUrgency)
                            .padding(.horizontal, KXSpacing.xs)
                            .padding(.vertical, KXSpacing.xxs)
                            .background(KXColor.urgency)
                            .padding(.bottom, KXSpacing.s)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: KXRadius.small, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // The texts beside it open the same product and carry the label for VoiceOver.
        .accessibilityHidden(true)
    }

    /// Vendor, title, variant and price; opens the product.
    private func details(_ display: PriceDisplay) -> some View {
        let vendor = line.merchandise.product.vendor.trimmingCharacters(in: .whitespacesAndNewlines)
        return Button {
            openProduct()
        } label: {
            VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                if !vendor.isEmpty {
                    Text(verbatim: vendor)
                        .kxFont(.eyebrow)
                        .foregroundStyle(KXColor.textPrimary)
                }
                Text(verbatim: line.merchandise.product.title)
                    .kxFont(.subheadline)
                    .foregroundStyle(KXColor.textPrimary)
                    .lineLimit(3)
                if let variant = CartLinePresentation.variantText(for: line.merchandise) {
                    Text(verbatim: variant)
                        .kxFont(.footnote)
                        .foregroundStyle(KXColor.textSecondary)
                }
                price(display)
                    .padding(.top, KXSpacing.xxs)
                if !line.merchandise.availableForSale {
                    Text("cart.line.unavailable", bundle: .module)
                        .kxFont(.footnote)
                        .foregroundStyle(KXColor.urgencyText)
                }
            }
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("cart.line.open.hint", bundle: .module))
        .accessibilityIdentifier("cart.line.open")
    }

    /// The price, sale red when reduced, the former price below it and the line total for more
    /// than one unit.
    private func price(_ display: PriceDisplay) -> some View {
        let quantity = model.quantity(of: line)
        return VStack(alignment: .leading, spacing: KXSpacing.xxs / 2) {
            Text(verbatim: display.price)
                .kxFont(.price)
                .foregroundStyle(display.compareAtPrice == nil ? KXColor.textPrimary : KXColor.urgencyText)
            if let compareAtPrice = display.compareAtPrice {
                Text("cart.line.original \(compareAtPrice)", bundle: .module)
                    .kxFont(.footnote)
                    .foregroundStyle(KXColor.textSecondary)
            }
            if quantity > 1 {
                Text("cart.line.total \(line.cost.totalAmount.formatted(locale: locale))", bundle: .module)
                    .kxFont(.footnote)
                    .foregroundStyle(KXColor.textSecondary)
                    .accessibilityIdentifier("cart.line.total")
            }
        }
    }

    /// The "x" at the top right that removes the line (with undo).
    private var removeButton: some View {
        Button {
            Task { await model.remove(line) }
        } label: {
            Image(systemName: "xmark")
                .kxFont(.body)
                .foregroundStyle(KXColor.textPrimary)
                .frame(width: KXSpacing.minimumTapTarget, height: KXSpacing.minimumTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // The symbol lines up with the vendor line and the trailing edge; the tap area stays 44 pt.
        .padding(.top, -KXSpacing.s)
        .padding(.trailing, -KXSpacing.s)
        .accessibilityLabel(Text("cart.line.remove.label \(line.merchandise.product.title)", bundle: .module))
        .accessibilityIdentifier("cart.remove")
    }

    private func openProduct() {
        onRoute(.product(handle: line.merchandise.product.handle))
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
