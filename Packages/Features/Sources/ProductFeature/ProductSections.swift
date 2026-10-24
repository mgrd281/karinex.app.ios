import CommerceUI
import DesignSystem
import ShopifyKit
import SwiftUI

// MARK: - ProductSummarySection

/// The top of the product: serif title, the price of the selected variant with the market's tax
/// note and compare-at price, availability with the delivery form, and the variant chips when
/// there is more than one variant.
struct ProductSummarySection: View {
    let product: Product
    let variant: ProductVariant?
    let fulfillment: ProductFulfillment
    let showsVariantPicker: Bool
    let selectedVariantID: ShopifyID?
    let onSelectVariant: @MainActor (ShopifyID) -> Void
    /// Reports whether the title is still on screen, so the navigation bar can show it once it
    /// scrolled away.
    let onTitleVisibilityChange: @MainActor (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.m) {
            Text(product.title)
                .kxFont(.title1)
                .foregroundStyle(KXColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("product.title")
                .onGeometryChange(for: Bool.self) { proxy in
                    proxy.frame(in: .scrollView).maxY > 0
                } action: { isVisible in
                    onTitleVisibilityChange(isVisible)
                }
            if let variant {
                PriceText(
                    price: variant.price,
                    compareAtPrice: variant.compareAtPrice,
                    requiresShipping: variant.requiresShipping
                )
                .accessibilityIdentifier("product.price")
            }
            ProductAvailabilityRow(isAvailable: variant?.availableForSale ?? product.availableForSale, fulfillment: fulfillment)
            if showsVariantPicker {
                ProductVariantPicker(
                    variants: product.variants,
                    selectedVariantID: selectedVariantID ?? variant?.id,
                    onSelect: onSelectVariant
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - ProductAvailabilityRow

/// Availability of the selected variant ("Verfügbar" or "Derzeit nicht verfügbar") and how it is
/// delivered (by e-mail or shipped), read by VoiceOver as one element.
struct ProductAvailabilityRow: View {
    let isAvailable: Bool
    let fulfillment: ProductFulfillment

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: KXSpacing.m) {
                availability
                KXDivider(axis: .vertical)
                    .frame(height: KXSpacing.m)
                delivery
            }
            .fixedSize(horizontal: true, vertical: false)
            VStack(alignment: .leading, spacing: KXSpacing.xs) {
                availability
                delivery
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("product.availability")
    }

    private var availability: some View {
        Label {
            Text(isAvailable ? "product.availability.available" : "product.availability.unavailable", bundle: .module)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: isAvailable ? "checkmark.circle.fill" : "clock")
                .foregroundStyle(isAvailable ? KXColor.success : KXColor.textSecondary)
                .accessibilityHidden(true)
        }
        .kxFont(.subheadline)
        .foregroundStyle(KXColor.textPrimary)
    }

    private var delivery: some View {
        Label {
            Text(fulfillment.deliveryNote)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: fulfillment.systemImage)
                .foregroundStyle(KXColor.accentText)
                .accessibilityHidden(true)
        }
        .kxFont(.subheadline)
        .foregroundStyle(KXColor.textSecondary)
    }
}

// MARK: - ProductVariantPicker

/// The variants as chips that wrap onto several lines. The selected chip is forest green;
/// unavailable variants stay selectable (to show their price) but are marked.
struct ProductVariantPicker: View {
    let variants: [ProductVariant]
    let selectedVariantID: ShopifyID?
    let onSelect: @MainActor (ShopifyID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.s) {
            Text("product.variant.title", bundle: .module)
                .kxFont(.eyebrow)
                .foregroundStyle(KXColor.accentText)
                .accessibilityAddTraits(.isHeader)
            ProductFlowLayout(spacing: KXSpacing.xs) {
                ForEach(Array(variants.enumerated()), id: \.element.id) { index, variant in
                    ProductVariantChip(variant: variant, isSelected: variant.id == selectedVariantID) {
                        onSelect(variant.id)
                    }
                    .accessibilityIdentifier("product.variant.\(index)")
                }
            }
        }
        .sensoryFeedback(.selection, trigger: selectedVariantID)
    }
}

/// One variant chip.
private struct ProductVariantChip: View {
    let variant: ProductVariant
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = Capsule(style: .continuous)
        Button(action: action) {
            Text(variant.title)
                .kxFont(.callout)
                .strikethrough(!variant.availableForSale, color: KXColor.textTertiary)
                .foregroundStyle(foreground)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, KXSpacing.m)
                .padding(.vertical, KXSpacing.xs)
                .frame(minWidth: KXSpacing.minimumTapTarget, minHeight: KXSpacing.minimumTapTarget)
                .background(isSelected ? KXColor.brand : KXColor.surface, in: shape)
                .overlay {
                    shape.strokeBorder(isSelected ? KXColor.accent : KXColor.hairline, lineWidth: KXBorder.regular)
                }
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .animation(KXMotion.animation(.snappy, reduceMotion: reduceMotion), value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityValue(variant.availableForSale ? Text(verbatim: "") : Text("product.availability.unavailable", bundle: .module))
    }

    private var foreground: Color {
        if isSelected {
            return KXColor.textOnBrand
        }
        return variant.availableForSale ? KXColor.textPrimary : KXColor.textTertiary
    }
}

// MARK: - ProductFlowLayout

/// Places its subviews in rows from the leading edge and wraps to the next row when a row is
/// full. A subview wider than the row gets the full row width (its text wraps).
struct ProductFlowLayout: Layout {
    /// The space between subviews in a row and between rows.
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let rows = arrange(subviews: subviews, width: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews: subviews, width: bounds.width) {
            var x = bounds.minX
            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: item.size.width, height: item.size.height)
                )
                x += item.size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Item {
        let index: Int
        let size: CGSize
    }

    private struct Row {
        var items: [Item] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(subviews: Subviews, width maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let ideal = subviews[index].sizeThatFits(.unspecified)
            let itemWidth = min(ideal.width, maxWidth)
            let size = itemWidth < ideal.width
                ? subviews[index].sizeThatFits(ProposedViewSize(width: itemWidth, height: nil))
                : ideal
            let proposedWidth = current.items.isEmpty ? size.width : current.width + spacing + size.width
            if !current.items.isEmpty, proposedWidth > maxWidth {
                rows.append(current)
                current = Row()
            }
            current.width = current.items.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.items.append(Item(index: index, size: size))
        }
        if !current.items.isEmpty {
            rows.append(current)
        }
        return rows
    }
}

// MARK: - ProductFactsSection

/// "Auf einen Blick": the key facts from the store's metafields as dot-leader rows. The caller
/// hides the section when there are no facts.
struct ProductFactsSection: View {
    let facts: [ProductFact]

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.m) {
            KXSectionHeader(String(localized: "product.facts.title", bundle: .module))
            KXCard {
                VStack(spacing: 0) {
                    ForEach(facts) { fact in
                        KXSpecRow(fact.kind.label, value: fact.value)
                    }
                }
            }
        }
        .accessibilityIdentifier("product.facts")
    }
}

// MARK: - ProductProcessSection

/// "So läuft es ab": order, pay and receive the key by e-mail, or the shipping process for
/// physical variants.
struct ProductProcessSection: View {
    let fulfillment: ProductFulfillment

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.m) {
            KXSectionHeader(String(localized: "product.process.title", bundle: .module))
            KXCard(padding: KXSpacing.l) {
                KXStepTimeline(steps: fulfillment.steps.map { KXStepTimeline.Step(title: $0.title, detail: $0.detail) })
            }
        }
        .accessibilityIdentifier("product.process")
    }
}

// MARK: - ProductRichTextSection

/// A titled section with store rich text: the description or the activation instructions.
struct ProductRichTextSection: View {
    let title: String
    let document: HTMLDocument
    let isCard: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.m) {
            KXSectionHeader(title)
            if isCard {
                KXCard(padding: KXSpacing.l) {
                    RichTextView(document: document)
                }
            } else {
                RichTextView(document: document)
            }
        }
    }
}

// MARK: - ProductFAQSection

/// "Häufige Fragen": the questions of `karinex.faq` in an accordion with gold plus toggles.
struct ProductFAQSection: View {
    let items: [ProductFAQItem]

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.m) {
            KXSectionHeader(String(localized: "product.faq.title", bundle: .module))
            KXAccordion(
                items: items.map { item in
                    KXAccordionItem(title: item.question, id: item.id) {
                        RichTextView(document: item.answer)
                    }
                },
                expansion: .single
            )
        }
        .accessibilityIdentifier("product.faq")
    }
}

// MARK: - ProductRefundSection

/// The "100 Tage Geld-zurück" promise with its conditions right next to it (PROMPT.md section 2).
struct ProductRefundSection: View {
    var body: some View {
        KXCard(padding: KXSpacing.l, showsInsetRing: true) {
            VStack(alignment: .leading, spacing: KXSpacing.m) {
                HStack(alignment: .firstTextBaseline, spacing: KXSpacing.s) {
                    Image(systemName: "arrow.uturn.backward.circle")
                        .kxFont(.title3)
                        .foregroundStyle(KXColor.accentText)
                        .accessibilityHidden(true)
                    Text("product.refund.title", bundle: .module)
                        .kxFont(.title3)
                        .foregroundStyle(KXColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                }
                KXDivider(.accent)
                ForEach(ProductRefundClause.allCases) { clause in
                    HStack(alignment: .firstTextBaseline, spacing: KXSpacing.s) {
                        Image(systemName: clause.systemImage)
                            .fontWeight(.medium)
                            .kxFont(.callout)
                            .foregroundStyle(KXColor.brand)
                            .accessibilityHidden(true)
                        Text(clause.text)
                            .kxFont(.callout)
                            .foregroundStyle(KXColor.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(KXSpacing.xxs)
        }
        .accessibilityIdentifier("product.refund")
    }
}

// MARK: - ProductDigitalNoticeSection

/// The right of withdrawal notice for digital content. The German text cites § 356 Abs. 5 BGB;
/// the other languages describe the rule neutrally (docs/LOCALIZATION.md rule 6).
struct ProductDigitalNoticeSection: View {
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: KXSpacing.s) {
            Image(systemName: "info.circle")
                .kxFont(.callout)
                .foregroundStyle(KXColor.info)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                Text("product.notice.title", bundle: .module)
                    .kxFont(.headline)
                    .foregroundStyle(KXColor.textPrimary)
                Text("product.notice.digital", bundle: .module)
                    .kxFont(.footnote)
                    .foregroundStyle(KXColor.textSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("product.notice.digital")
    }
}

// MARK: - ProductDetailSkeleton

/// The placeholder while the product loads: gallery, title, price and a few text lines.
struct ProductDetailSkeleton: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KXSpacing.m) {
                KXSkeleton(cornerRadius: KXRadius.large)
                    .aspectRatio(1, contentMode: .fit)
                KXSkeleton()
                    .frame(height: KXSpacing.l)
                KXSkeleton()
                    .frame(height: KXSpacing.l)
                    .padding(.trailing, KXSpacing.xxxl)
                KXSkeleton()
                    .frame(width: KXSpacing.xxxl * 2, height: KXSpacing.l)
                    .padding(.top, KXSpacing.xs)
                ForEach(0..<4, id: \.self) { _ in
                    KXSkeleton()
                        .frame(height: KXSpacing.s)
                }
            }
            .padding(KXSpacing.gutter)
        }
        .scrollDisabled(true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("product.loading", bundle: .module))
    }
}
