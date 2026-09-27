import SwiftUI

// MARK: - KXPriceTag

/// Displays a price exactly as formatted by the caller, with an optional struck-through
/// compare-at price, an optional savings badge and an optional tax note.
///
/// The component never formats, computes or rounds money: pass the strings produced from
/// Shopify's `MoneyV2` for the active market ("12,90 €", "CHF 29.00"). Pass the tax note
/// ("inkl. MwSt.") only for markets whose prices include tax.
///
/// Layout: price, compare-at price and badge sit on one baseline. When they do not fit (narrow
/// cards, large text sizes) the compare-at price and badge move below the price, and at the
/// largest sizes everything stacks. The savings badge is gold (PROMPT.md section 6.1); terracotta
/// stays reserved for urgency such as a running deal countdown.
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
        /// Smaller price for product cards and list rows.
        case compact
    }

    private let price: String
    private let compareAtPrice: String?
    private let savings: String?
    private let taxNote: String?
    private let size: Size

    /// Creates a price tag.
    ///
    /// - Parameters:
    ///   - price: The formatted current price.
    ///   - compareAtPrice: The formatted former price, shown struck through. Pass `nil` when
    ///     the store has no compare-at price or it is not higher than the price.
    ///   - savings: Already-localized savings text shown in a gold badge, e.g. a value the
    ///     caller derived from Shopify prices. `nil` hides the badge.
    ///   - taxNote: Already-localized tax note shown below, e.g. "inkl. MwSt.".
    ///   - size: Type scale. Defaults to ``Size/regular``.
    public init(
        price: String,
        compareAtPrice: String? = nil,
        savings: String? = nil,
        taxNote: String? = nil,
        size: Size = .regular
    ) {
        self.price = price
        self.compareAtPrice = kxNonEmpty(compareAtPrice)
        self.savings = kxNonEmpty(savings)
        self.taxNote = kxNonEmpty(taxNote)
        self.size = size
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.xxs) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: KXSpacing.xs) {
                    priceText
                    compareAtText
                    savingsBadge
                }
                VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                    priceText
                    HStack(alignment: .firstTextBaseline, spacing: KXSpacing.xs) {
                        compareAtText
                        savingsBadge
                    }
                }
                VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                    priceText
                    compareAtText
                    savingsBadge
                }
            }
            if let taxNote {
                Text(taxNote)
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
            .kxFont(size == .regular ? .price : .headline)
            .foregroundStyle(KXColor.textPrimary)
            .contentTransition(.numericText())
    }

    @ViewBuilder private var compareAtText: some View {
        if let compareAtPrice {
            Text(compareAtPrice)
                .strikethrough(true, color: KXColor.textTertiary)
                .monospacedDigit()
                .kxFont(size == .regular ? .subheadline : .footnote)
                .foregroundStyle(KXColor.textTertiary)
        }
    }

    @ViewBuilder private var savingsBadge: some View {
        if let savings {
            KXBadge(savings, style: .gold)
        }
    }

    // MARK: Accessibility

    /// "Preis 12,90 €, statt 79,99 €" plus the savings and tax note, comma separated.
    private var accessibilityText: String {
        let priceDescription = Self.spokenPrice(price, compareAtPrice: compareAtPrice)
        return [priceDescription, savings, taxNote]
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

// Recorded from the live Storefront API on 2026-09-26 (Storefront API 2026-07). The German
// strings are the MoneyV2 amounts formatted for de_DE; the CHF string is the CH/FR market price
// formatted for de_CH. The savings text is derived from the recorded price and compare-at price.
private struct KXPriceTagPreviewGallery: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KXSpacing.l) {
                // Windows 11 Pro, DE/DE.
                KXPriceTag(price: "12,90 €", compareAtPrice: "79,99 €", savings: "Sie sparen 67,09 €", taxNote: "inkl. MwSt.")
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
