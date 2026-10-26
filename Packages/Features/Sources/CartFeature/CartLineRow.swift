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
/// price below it and the line total for more than one unit, and the quantity control. The
/// photo and the texts open the product.
///
/// Removing works like the About You app: swiping the row to the left uncovers a red
/// "Entfernen" behind it; a long swipe, a tap on "Entfernen" or on the "x" at the top right
/// turns the row red with "Produkt wird entfernt" and "Abbrechen", whose fill runs down until
/// the line leaves the cart (``CartViewModel/requestRemoval(of:after:)``).
struct CartLineRow: View {
    /// Width to height of the photo: a little taller than wide.
    static let photoAspectRatio: CGFloat = 5 / 6

    let line: CartLine
    let model: CartViewModel
    let onRoute: @MainActor (CommerceRoute) -> Void

    @Environment(\.locale) private var locale
    @Environment(\.commerceCountry) private var country
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var isVoiceOverEnabled
    @ScaledMetric(relativeTo: .body) private var scaledPhotoWidth: CGFloat = 112
    @ScaledMetric(relativeTo: .footnote) private var actionWidth: CGFloat = 96

    /// How far the row is pushed to the left by the finger or while "Entfernen" stays open.
    @State private var swipeOffset: CGFloat = 0
    /// Whether "Entfernen" stays uncovered after the finger let go.
    @State private var isActionOpen = false
    /// The direction of the current drag, decided by its first movement.
    @State private var dragAxis: Axis?
    @State private var rowWidth: CGFloat = 0

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
        let isRemoving = model.isRemoving(line)
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
        .background(KXColor.background)
        .offset(x: isRemoving ? 0 : swipeOffset)
        .accessibilityHidden(isRemoving)
        .background(alignment: .trailing) {
            if !isRemoving {
                swipeAction
            }
        }
        .overlay {
            if isRemoving {
                CartLineRemovalPanel(duration: removalDelay) {
                    model.cancelRemoval(of: line)
                }
                .padding(.horizontal, -KXSpacing.gutter)
                .padding(.vertical, -KXSpacing.xs)
                .transition(.opacity)
            }
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            rowWidth = width
        }
        .simultaneousGesture(swipe)
        .animation(KXMotion.animation(.snappy, reduceMotion: reduceMotion), value: isRemoving)
        .sensoryFeedback(.impact(weight: .medium), trigger: isRemoving) { _, startsRemoving in startsRemoving }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: Text("cart.line.swipe.remove", bundle: .module)) {
            requestRemoval()
        }
        .accessibilityIdentifier("cart.line.\(line.merchandise.product.handle)")
    }

    // MARK: Removal

    /// How long the row stays red before the line leaves the cart.
    private var removalDelay: TimeInterval {
        isVoiceOverEnabled ? CartViewModel.accessibleRemovalDelay : CartViewModel.removalDelay
    }

    private func requestRemoval() {
        isActionOpen = false
        swipeOffset = 0
        model.requestRemoval(of: line, after: removalDelay)
    }

    /// The red "Entfernen" that the row uncovers when it moves to the left, reaching to the
    /// screen edge. While it is narrower than the symbol and the word, their leading part is
    /// cut off. A tap removes the line like a long swipe.
    private var swipeAction: some View {
        let width = max(-swipeOffset, 0)
        let redWidth = width + KXSpacing.gutter
        return Button {
            requestRemoval()
        } label: {
            VStack(spacing: KXSpacing.xxs) {
                Image(systemName: "xmark")
                    .kxFont(.title3)
                Text("cart.line.swipe.remove", bundle: .module)
                    .kxFont(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(KXColor.textOnUrgency)
            .frame(width: max(redWidth, actionWidth))
            .frame(width: redWidth, alignment: .trailing)
            .frame(maxHeight: .infinity)
            .clipped()
            .background(KXColor.urgency)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.trailing, -KXSpacing.gutter)
        .padding(.vertical, -KXSpacing.xs)
        .opacity(width > 0 ? 1 : 0)
        .accessibilityHidden(true)
    }

    /// Moves the row with a horizontal drag to the left and decides on release: far enough
    /// removes the line, half of "Entfernen" keeps it open, less closes it again. Vertical drags
    /// are left to the scroll view.
    private var swipe: some Gesture {
        DragGesture(minimumDistance: KXSpacing.m)
            .onChanged { value in
                if dragAxis == nil {
                    dragAxis = abs(value.translation.width) > abs(value.translation.height) ? .horizontal : .vertical
                }
                guard dragAxis == .horizontal, !model.isRemoving(line) else { return }
                let start = isActionOpen ? -actionWidth : 0
                swipeOffset = min(0, start + value.translation.width)
            }
            .onEnded { value in
                defer { dragAxis = nil }
                guard dragAxis == .horizontal, !model.isRemoving(line) else { return }
                let start = isActionOpen ? -actionWidth : 0
                let travel = -(start + value.predictedEndTranslation.width)
                withAnimation(KXMotion.animation(.snappy, reduceMotion: reduceMotion)) {
                    if CartSwipe.removes(offset: swipeOffset, predictedTravel: travel, rowWidth: rowWidth) {
                        requestRemoval()
                    } else if -swipeOffset > actionWidth / 2 {
                        isActionOpen = true
                        swipeOffset = -actionWidth
                    } else {
                        isActionOpen = false
                        swipeOffset = 0
                    }
                }
            }
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

    /// The "x" at the top right that removes the line like a long swipe.
    private var removeButton: some View {
        Button {
            withAnimation(KXMotion.animation(.snappy, reduceMotion: reduceMotion)) {
                requestRemoval()
            }
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

// MARK: - CartSwipe

/// When a swipe to the left removes a line.
enum CartSwipe {
    /// The share of the row a finger has to cover, or a flick is predicted to cover, to remove
    /// the line.
    static let removalShare: CGFloat = 0.55

    /// Whether a swipe that moved the row to `offset` (negative to the left) and would travel
    /// `predictedTravel` points with its momentum removes the line.
    static func removes(offset: CGFloat, predictedTravel: CGFloat, rowWidth: CGFloat) -> Bool {
        guard rowWidth > 0 else { return false }
        return -offset > rowWidth * removalShare || predictedTravel > rowWidth
    }
}

// MARK: - CartLineRemovalPanel

/// The red panel over a line that is about to leave the cart: "Produkt wird entfernt" and an
/// outlined "Abbrechen" whose lighter fill runs across it in `duration` seconds, until the line
/// is gone.
struct CartLineRemovalPanel: View {
    let duration: TimeInterval
    let onCancel: @MainActor () -> Void

    @State private var progress: CGFloat = 0

    var body: some View {
        VStack(spacing: KXSpacing.s) {
            Text("cart.line.removing", bundle: .module)
                .fontWeight(.semibold)
                .kxFont(.subheadline)
                .multilineTextAlignment(.center)
            Button {
                onCancel()
            } label: {
                Label {
                    Text("cart.line.removing.cancel", bundle: .module)
                } icon: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .kxFont(.subheadline)
                .padding(.horizontal, KXSpacing.l)
                .padding(.vertical, KXSpacing.xs)
                .frame(minHeight: KXSpacing.minimumTapTarget)
                .background(alignment: .leading) {
                    Rectangle()
                        .fill(KXColor.textOnUrgency.opacity(0.22))
                        .scaleEffect(x: progress, y: 1, anchor: .leading)
                }
                .background(KXColor.textOnUrgency.opacity(0.12))
                .overlay {
                    RoundedRectangle(cornerRadius: KXRadius.small, style: .continuous)
                        .strokeBorder(KXColor.textOnUrgency, lineWidth: KXBorder.regular)
                }
                .clipShape(RoundedRectangle(cornerRadius: KXRadius.small, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("cart.removal.cancel")
        }
        .foregroundStyle(KXColor.textOnUrgency)
        .padding(KXSpacing.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(KXColor.urgency)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cart.removal")
        .onAppear {
            withAnimation(.linear(duration: duration)) {
                progress = 1
            }
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
