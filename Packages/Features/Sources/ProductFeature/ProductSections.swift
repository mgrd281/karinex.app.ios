import CommerceUI
import DesignSystem
import ShopifyKit
import SwiftUI

// MARK: - ProductSummarySection

/// The top of the product: the bold title, the price of the selected variant with the market's
/// tax note, compare-at price and the store's lowest price of the last 30 days, the thumbnails
/// of the linked products, availability, the delivery form and the recent sales as icon rows,
/// and the variant
/// pills when there is more than one variant.
struct ProductSummarySection: View {
    let product: Product
    let variant: ProductVariant?
    /// The store's lowest price of the last 30 days, shown with a reduced price.
    let lowestPrice: MoneyV2?
    /// The thumbnails of the linked products row; empty hides the row.
    let linkedProducts: [ProductSummary]
    /// Opens a linked product.
    let onSelectLinkedProduct: @MainActor (ProductSummary) -> Void
    let fulfillment: ProductFulfillment
    /// The units the store reports as sold in the last days; `nil` hides the row.
    let recentSales: RecentSales?
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
                    requiresShipping: variant.requiresShipping,
                    lowestPrice: lowestPrice
                )
                .accessibilityIdentifier("product.price")
            }
            if !linkedProducts.isEmpty {
                ProductLinkedProductsRow(products: linkedProducts, currentID: product.id, onSelect: onSelectLinkedProduct)
            }
            ProductAvailabilityRow(
                isAvailable: variant?.availableForSale ?? product.availableForSale,
                fulfillment: fulfillment,
                recentSales: recentSales
            )
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

/// Availability of the selected variant ("Verfügbar" or "Derzeit nicht verfügbar"), how it is
/// delivered (by e-mail or shipped) and, when the store reports it, how often it sold in the
/// last days, as rows with a line icon each, read by VoiceOver as one element.
struct ProductAvailabilityRow: View {
    let isAvailable: Bool
    let fulfillment: ProductFulfillment
    var recentSales: RecentSales?

    @ScaledMetric(relativeTo: .callout) private var iconWidth: CGFloat = 28

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.s) {
            row(
                systemImage: isAvailable ? "checkmark.circle" : "clock",
                iconColor: isAvailable ? KXColor.success : KXColor.textSecondary,
                text: Text(isAvailable ? "product.availability.available" : "product.availability.unavailable", bundle: .module)
            )
            row(systemImage: fulfillment.systemImage, iconColor: KXColor.textPrimary, text: Text(fulfillment.deliveryNote))
            if let recentSales {
                HStack(alignment: .center, spacing: KXSpacing.s) {
                    ProductTrendIcon()
                        .frame(width: iconWidth, alignment: .leading)
                    Text("product.recent_sales \(recentSales.count) \(recentSales.days)", bundle: .module)
                        .foregroundStyle(KXColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .kxFont(.callout)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("product.availability")
    }

    private func row(systemImage: String, iconColor: Color, text: Text) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: KXSpacing.s) {
            Image(systemName: systemImage)
                .foregroundStyle(iconColor)
                .frame(width: iconWidth, alignment: .leading)
                .accessibilityHidden(true)
            text
                .foregroundStyle(KXColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .kxFont(.callout)
    }
}

// MARK: - ProductTrendIcon

/// The icon of the "recently sold" row, the same as in the web shop: a rising trend line with an
/// arrow head in green. It draws itself, then the arrow head, stays for a few seconds, erases and
/// starts again; with Reduce Motion it stays drawn.
struct ProductTrendIcon: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .callout) private var size: CGFloat = 20

    var body: some View {
        Group {
            if reduceMotion {
                trend(ProductTrendProgress.drawn)
            } else {
                KeyframeAnimator(initialValue: ProductTrendProgress.erased, repeating: true) { progress in
                    trend(progress)
                } keyframes: { _ in
                    KeyframeTrack(\.line) {
                        CubicKeyframe(1, duration: KXMotion.trendDrawDuration)
                        LinearKeyframe(1, duration: KXMotion.trendArrowDuration + KXMotion.trendHoldDuration)
                        CubicKeyframe(0, duration: KXMotion.trendEraseDuration)
                        LinearKeyframe(0, duration: KXMotion.trendRestDuration)
                    }
                    KeyframeTrack(\.arrow) {
                        LinearKeyframe(0, duration: KXMotion.trendDrawDuration)
                        CubicKeyframe(1, duration: KXMotion.trendArrowDuration)
                        LinearKeyframe(1, duration: KXMotion.trendHoldDuration)
                        CubicKeyframe(0, duration: KXMotion.trendEraseDuration)
                        LinearKeyframe(0, duration: KXMotion.trendRestDuration)
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func trend(_ progress: ProductTrendProgress) -> some View {
        let style = StrokeStyle(lineWidth: size / 12, lineCap: .round, lineJoin: .round)
        return ZStack {
            ProductTrendShape(points: ProductTrendShape.line)
                .trim(from: 0, to: progress.line)
                .stroke(KXColor.success, style: style)
            ProductTrendShape(points: ProductTrendShape.arrowHead)
                .trim(from: 0, to: progress.arrow)
                .stroke(KXColor.success, style: style)
        }
    }
}

/// How far the trend line and its arrow head are drawn, from 0 to 1.
struct ProductTrendProgress {
    var line: CGFloat
    var arrow: CGFloat

    static let erased = ProductTrendProgress(line: 0, arrow: 0)
    static let drawn = ProductTrendProgress(line: 1, arrow: 1)
}

/// A polyline in a 24 by 24 grid, scaled to the frame.
struct ProductTrendShape: Shape {
    /// The rising line: down, up, a small dip and up to the top right.
    static let line = [CGPoint(x: 1, y: 18), CGPoint(x: 8.5, y: 10.5), CGPoint(x: 13.5, y: 15.5), CGPoint(x: 23, y: 6)]
    /// The arrow head at the top right end.
    static let arrowHead = [CGPoint(x: 17, y: 6), CGPoint(x: 23, y: 6), CGPoint(x: 23, y: 12)]

    let points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let scale = min(rect.width, rect.height) / 24
        let placed = points.map { CGPoint(x: rect.minX + $0.x * scale, y: rect.minY + $0.y * scale) }
        path.addLines(placed)
        return path
    }
}

// MARK: - ProductVariantPicker

/// The variants as pills that wrap onto several lines. The selected pill is filled with ink;
/// unavailable variants stay selectable (to show their price) but are struck through.
struct ProductVariantPicker: View {
    let variants: [ProductVariant]
    let selectedVariantID: ShopifyID?
    let onSelect: @MainActor (ShopifyID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.s) {
            Text("product.variant.title", bundle: .module)
                .fontWeight(.semibold)
                .kxFont(.subheadline)
                .foregroundStyle(KXColor.textPrimary)
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

/// One variant pill.
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
                .padding(.horizontal, KXSpacing.l)
                .padding(.vertical, KXSpacing.xs)
                .frame(minWidth: KXSpacing.minimumTapTarget * 1.5, minHeight: KXSpacing.minimumTapTarget)
                .background(isSelected ? KXColor.brand : Color.clear, in: shape)
                .overlay {
                    shape.strokeBorder(isSelected ? KXColor.brand : KXColor.textPrimary, lineWidth: KXBorder.regular)
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

/// "Auf einen Blick": the key facts from the store's metafields as dot-leader rows separated by
/// hairlines. The caller hides the section when there are no facts.
struct ProductFactsSection: View {
    let facts: [ProductFact]

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.s) {
            KXSectionHeader(String(localized: "product.facts.title", bundle: .module))
            VStack(spacing: 0) {
                ForEach(facts) { fact in
                    KXSpecRow(fact.kind.label, value: fact.value)
                        .padding(.vertical, KXSpacing.xxs)
                    KXDivider()
                }
            }
        }
        .accessibilityIdentifier("product.facts")
    }
}

// MARK: - ProductMoreInformationSection

/// Collapsible rows in the style of fashion retail apps ("Produktdetails"): the full product
/// description from the store, "So läuft es ab" (order, pay and receive the key by e-mail, or
/// the shipping process for physical variants) and the activation instructions when the store
/// provides them. A row opens and closes with a tap on its title; an opened description also
/// ends with "Weniger anzeigen", so a long text can be closed without scrolling back up.
struct ProductMoreInformationSection: View {
    let description: HTMLDocument
    let fulfillment: ProductFulfillment
    let activation: HTMLDocument?

    @State private var expandedIDs: Set<String> = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        KXAccordion(items: rows, expandedIDs: $expandedIDs)
    }

    private var rows: [KXAccordionItem] {
        var rows: [KXAccordionItem] = []
        if !description.isEmpty {
            rows.append(
                KXAccordionItem(title: String(localized: "product.description.title", bundle: .module), id: "description") {
                    VStack(alignment: .leading, spacing: KXSpacing.l) {
                        RichTextView(document: description)
                            .accessibilityIdentifier("product.description")
                        KXButton(
                            String(localized: "product.description.less", bundle: .module),
                            systemImage: "chevron.up",
                            style: .secondary,
                            size: .compact,
                            isFullWidth: true
                        ) {
                            withAnimation(KXMotion.animation(.snappy, reduceMotion: reduceMotion)) {
                                _ = expandedIDs.remove("description")
                            }
                        }
                        .kxButtonCornerRadius(KXRadius.small)
                        .accessibilityIdentifier("product.description.close")
                    }
                    .padding(.top, KXSpacing.xs)
                }
            )
        }
        rows.append(
            KXAccordionItem(title: String(localized: "product.process.title", bundle: .module), id: "process") {
                KXStepTimeline(steps: fulfillment.steps.map { KXStepTimeline.Step(title: $0.title, detail: $0.detail) })
                    .padding(.top, KXSpacing.xs)
                    .accessibilityIdentifier("product.process")
            }
        )
        if let activation {
            rows.append(
                KXAccordionItem(title: String(localized: "product.activation.title", bundle: .module), id: "activation") {
                    RichTextView(document: activation)
                        .accessibilityIdentifier("product.activation")
                }
            )
        }
        return rows
    }
}

// MARK: - ProductFAQSection

/// "Häufige Fragen": the questions of `karinex.faq` in an accordion with chevron toggles.
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

/// The "14 Tage Geld-zurück" promise with its conditions right next to it (PROMPT.md section 2).
struct ProductRefundSection: View {
    var body: some View {
        KXCard(padding: KXSpacing.l, isOutlined: true) {
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
                KXDivider()
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

// MARK: - ProductDetailSkeleton

/// The placeholder while the product loads: the photo tile edge to edge, title, price and a few
/// text lines.
struct ProductDetailSkeleton: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KXSpacing.l) {
                KXColor.imageBackground
                    .aspectRatio(1, contentMode: .fit)
                VStack(alignment: .leading, spacing: KXSpacing.m) {
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
                .padding(.horizontal, KXSpacing.gutter)
            }
        }
        .scrollDisabled(true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("product.loading", bundle: .module))
    }
}
