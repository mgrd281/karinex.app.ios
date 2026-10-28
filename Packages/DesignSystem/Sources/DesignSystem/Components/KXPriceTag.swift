import SwiftUI

// MARK: - KXPriceTag

/// Displays a price exactly as formatted by the caller, with an optional struck-through
/// compare-at price, an optional savings badge, an optional tax note and an optional lowest
/// price of the last 30 days.
///
/// The component never formats, computes or rounds money: pass the strings produced from
/// Shopify's `MoneyV2` for the active market ("12,90 €", "CHF 29.00"). Pass the tax note
/// ("inkl. MwSt.") only for markets whose prices include tax.
///
/// Sale look, as in fashion retail apps: a reduced price (one with a compare-at price) is sale
/// red. In the ``Size/regular`` size of the product page a red "SALE" badge sits above the
/// price and the former price follows below as "Ursprünglich: 149,99 €", then the lowest price
/// of 30 days. In the ``Size/compact`` size of cards the compare-at price is struck through
/// next to the price, with the savings badge. Sale red is the one color accent of the otherwise
/// monochrome interface.
///
/// Layout: price and compare-at price (and the compact badge) sit on one baseline. When they
/// do not fit (narrow cards, large text sizes) the compare-at price moves below the price, and
/// at the largest sizes everything stacks. Tax note and lowest price follow below.
///
/// Empty strings count as missing, so optional Shopify values can be passed through unchanged.
///
/// VoiceOver reads the whole tag as one element, e.g. "Preis 12,90 €, statt 79,99 €,
/// inkl. MwSt.".
///
/// ```swift
/// KXPriceTag(price: "12,90 €", compareAtPrice: "79,99 €", taxNote: taxNote, size: .compact)
/// ```
public struct KXPriceTag: View {
    /// Type scale of a ``KXPriceTag``.
    public enum Size: String, CaseIterable, Sendable {
        /// Large price for product detail and cart totals.
        case regular
        /// Price in the regular weight of the card title, for product cards and list rows.
        case compact
    }

    private let price: String
    private let compareAtPrice: String?
    private let savings: String?
    private let taxNote: String?
    private let lowestPrice: String?
    private let size: Size

    /// Creates a price tag.
    ///
    /// - Parameters:
    ///   - price: The formatted current price.
    ///   - compareAtPrice: The formatted former price, shown struck through. Pass `nil` when
    ///     the store has no compare-at price or it is not higher than the price.
    ///   - savings: Already-localized savings text shown in a red badge, e.g. a value the
    ///     caller derived from Shopify prices. `nil` hides the badge.
    ///   - taxNote: Already-localized tax note shown below, e.g. "inkl. MwSt.".
    ///   - lowestPrice: The formatted lowest price of the last 30 days from the store, shown
    ///     below as "Niedrigster Preis der letzten 30 Tage: 24,90 €". `nil` hides the line.
    ///   - size: Type scale. Defaults to ``Size/regular``.
    public init(
        price: String,
        compareAtPrice: String? = nil,
        savings: String? = nil,
        taxNote: String? = nil,
        lowestPrice: String? = nil,
        size: Size = .regular
    ) {
        self.price = price
        self.compareAtPrice = kxNonEmpty(compareAtPrice)
        self.savings = kxNonEmpty(savings)
        self.taxNote = kxNonEmpty(taxNote)
        self.lowestPrice = kxNonEmpty(lowestPrice)
        self.size = size
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.xxs) {
            if showsSaleBadge {
                KXBadge(String(localized: "kx.price.sale", bundle: .module), style: .urgency)
                    .padding(.bottom, KXSpacing.xxs)
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: KXSpacing.xs) {
                    priceText
                    compareAtText
                    inlineSavingsBadge
                }
                VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                    priceText
                    HStack(alignment: .firstTextBaseline, spacing: KXSpacing.xs) {
                        compareAtText
                        inlineSavingsBadge
                    }
                }
                VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                    priceText
                    compareAtText
                    inlineSavingsBadge
                }
            }
            if let taxNote {
                Text(taxNote)
                    .kxFont(size == .regular ? .footnote : .caption)
                    .foregroundStyle(KXColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if size == .regular, let compareAtPrice {
                Text("kx.price.original \(compareAtPrice)", bundle: .module)
                    .monospacedDigit()
                    .kxFont(.footnote)
                    .foregroundStyle(KXColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let lowestPrice {
                Text("kx.price.lowest_30_days \(lowestPrice)", bundle: .module)
                    .monospacedDigit()
                    .kxFont(size == .regular ? .footnote : .caption)
                    .foregroundStyle(KXColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .kxAnimation(.standard, value: price)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    // MARK: Parts

    private var priceText: some View {
        Text(price)
            .monospacedDigit()
            .kxFont(size == .regular ? .price : .subheadline)
            .foregroundStyle(compareAtPrice == nil ? KXColor.textPrimary : KXColor.urgencyText)
            .contentTransition(.numericText())
    }

    /// The red "SALE" badge above the price in the regular size, as at About You: a reduced
    /// price shows the word, the former price follows below as "Ursprünglich: …".
    private var showsSaleBadge: Bool {
        size == .regular && compareAtPrice != nil
    }

    @ViewBuilder private var compareAtText: some View {
        if size == .compact, let compareAtPrice {
            Text(compareAtPrice)
                .strikethrough(true, color: KXColor.textTertiary)
                .monospacedDigit()
                .kxFont(size == .regular ? .subheadline : .footnote)
                .foregroundStyle(KXColor.textTertiary)
        }
    }

    /// The savings badge next to the price, only in the compact size.
    @ViewBuilder private var inlineSavingsBadge: some View {
        if size == .compact, let savings {
            KXBadge(savings, style: .urgency)
        }
    }

    /// The spoken "Niedrigster Preis der letzten 30 Tage: 24,90 €", or `nil`.
    private var lowestPriceText: String? {
        lowestPrice.map { String(localized: "kx.price.lowest_30_days \($0)", bundle: .module) }
    }

    // MARK: Accessibility

    /// "Preis 12,90 €, statt 79,99 €" plus the savings, tax note and lowest price, comma
    /// separated.
    private var accessibilityText: String {
        let priceDescription = Self.spokenPrice(price, compareAtPrice: compareAtPrice)
        return [priceDescription, savings, taxNote, lowestPriceText]
            .compactMap(\.self)
            .joined(separator: ", ")
    }

    /// The spoken form of a price, "Preis 12,90 €" or "Preis 12,90 €, statt 79,99 €" when there
    /// is a non-empty compare-at price. Shared with ``KXProductCard`` so that every component
    /// reads prices the same way.
    nonisolated static func spokenPrice(_ price: String, compareAtPrice: String?) -> String {
        if let compareAtPrice = kxNonEmpty(compareAtPrice) {
            String(localized: "kx.price.accessibility.compare \(price) \(compareAtPrice)", bundle: .module)
        } else {
            String(localized: "kx.price.accessibility.current \(price)", bundle: .module)
        }
    }
}

/// `string`, or `nil` when it is `nil` or empty.
private func kxNonEmpty(_ string: String?) -> String? {
    guard let string, !string.isEmpty else { return nil }
    return string
}

// MARK: - Previews

// Recorded from the live Storefront API on 2026-09-26 (Storefront API 2026-10). The German
// strings are the MoneyV2 amounts formatted for de_DE; the CHF string is the CH/FR market price
// formatted for de_CH. The savings text is derived from the recorded price and compare-at price.
private struct KXPriceTagPreviewGallery: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KXSpacing.l) {
                // Windows 11 Pro, DE/DE, with the store's lowest price of the last 30 days.
                KXPriceTag(
                    price: "12,90 €",
                    compareAtPrice: "79,99 €",
                    savings: "-83 %",
                    taxNote: "inkl. MwSt.",
                    lowestPrice: "12,90 €"
                )
                // Microsoft Office 2024 Professional Plus, DE/DE.
                KXPriceTag(price: "29,90 €", compareAtPrice: "149,99 €", taxNote: "inkl. MwSt.")
                // Microsoft Office 2024 Standard für Mac, DE/DE, compact as on a product card.
                KXPriceTag(price: "13,90 €", compareAtPrice: "39,99 €", taxNote: "inkl. MwSt.", size: .compact)
                    .frame(width: 160, alignment: .leading)
                // Microsoft Office 2024 Professional Plus, CH/FR: no tax note outside the EU.
                KXPriceTag(price: "CHF 29.00")
            }
            .padding(KXSpacing.gutter)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .kxScreenBackground()
    }
}

#Preview("KXPriceTag, light") {
    KXPriceTagPreviewGallery()
}

#Preview("KXPriceTag, dark") {
    KXPriceTagPreviewGallery()
        .preferredColorScheme(.dark)
}

#Preview("KXPriceTag, accessibility size") {
    KXPriceTagPreviewGallery()
        .dynamicTypeSize(.accessibility2)
}
