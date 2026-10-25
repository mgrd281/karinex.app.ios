#if DEBUG
import SwiftUI

// MARK: - KXButton

/// Every button style in both sizes, with switches for the loading and disabled states.
struct KXGalleryButtonPage: View {
    @State private var isLoading = false
    @State private var isDisabled = false
    @State private var tapCount = 0

    var body: some View {
        KXGalleryPage(topic: .button) {
            KXGalleryDemo("States", note: "The switches apply to every button on this page.") {
                VStack(alignment: .leading, spacing: KXSpacing.s) {
                    Toggle(isOn: $isLoading) {
                        Text(verbatim: "isLoading")
                    }
                    Toggle(isOn: $isDisabled) {
                        Text(verbatim: ".disabled(true)")
                    }
                    KXGalleryEventLabel(tapCount == 0 ? nil : "Actions received: \(tapCount)")
                }
                .kxFont(.body)
                .foregroundStyle(KXColor.textPrimary)
                .tint(KXColor.brand)
            }
            ForEach(KXButton.Style.allCases, id: \.self) { style in
                KXGalleryDemo("Style .\(style.rawValue)") {
                    VStack(alignment: .leading, spacing: KXSpacing.s) {
                        ForEach(KXButton.Size.allCases, id: \.self) { size in
                            KXButton(
                                "Zum Sortiment",
                                systemImage: "square.grid.2x2",
                                style: style,
                                size: size,
                                isLoading: isLoading
                            ) {
                                tapCount += 1
                            }
                        }
                        KXButton("In den Warenkorb", style: style, isFullWidth: true, isLoading: isLoading) {
                            tapCount += 1
                        }
                    }
                    .disabled(isDisabled)
                }
            }
            KXGalleryDemo("Long label", note: "Labels wrap instead of truncating.") {
                KXButton(KXGallerySamples.finnishDelivery, style: .secondary, isFullWidth: true, isLoading: isLoading) {
                    tapCount += 1
                }
                .disabled(isDisabled)
            }
            KXGalleryDemo("KXButtonStyle", note: "The shorthand .buttonStyle(.kx(...)) on a NavigationLink.") {
                NavigationLink {
                    KXGalleryPage(topic: .button) {
                        KXGalleryDemo("Destination") {
                            Text(verbatim: "Pushed with a NavigationLink styled as KXButton.")
                                .kxFont(.body)
                                .foregroundStyle(KXColor.textPrimary)
                        }
                    }
                } label: {
                    Text(verbatim: "Open a detail page")
                }
                .buttonStyle(.kx(.secondary, isFullWidth: true))
                .disabled(isDisabled)
            }
        }
    }
}

// MARK: - KXCard

/// Card styles, the inset ring and full-bleed content.
struct KXGalleryCardPage: View {
    var body: some View {
        KXGalleryPage(topic: .card) {
            KXGalleryDemo("KXCardStyle.standard") {
                KXCard {
                    VStack(alignment: .leading, spacing: KXSpacing.s) {
                        Text(verbatim: KXGallerySamples.officeProPlusTitle)
                            .kxFont(.title3)
                            .foregroundStyle(KXColor.textPrimary)
                        KXPriceTag(
                            price: KXGallerySamples.officeProPlusPrice,
                            compareAtPrice: KXGallerySamples.officeProPlusCompareAtPrice,
                            taxNote: KXGallerySamples.taxNote
                        )
                    }
                }
            }
            KXGalleryDemo("showsInsetRing: true") {
                KXCard(showsInsetRing: true) {
                    VStack(alignment: .leading, spacing: KXSpacing.s) {
                        Text(verbatim: "Support")
                            .kxFont(.title3)
                            .foregroundStyle(KXColor.textPrimary)
                        Text(verbatim: KXGallerySamples.supportChannels)
                            .kxFont(.body)
                            .foregroundStyle(KXColor.textSecondary)
                    }
                    .padding(KXSpacing.xs)
                }
            }
            KXGalleryDemo("KXCardStyle.elevated") {
                KXCard(style: .elevated) {
                    Text(verbatim: KXGallerySamples.windowsProTitle)
                        .kxFont(.body)
                        .foregroundStyle(KXColor.textPrimary)
                }
            }
            KXGalleryDemo("padding: 0", note: "Content is clipped to the 18 pt radius, so it can run full bleed.") {
                KXCard(padding: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        KXColor.brand
                            .frame(height: 96)
                            .overlay {
                                KXWordmark(color: KXColor.textOnBrand)
                            }
                        Text(verbatim: KXGallerySamples.deliveryFact)
                            .kxFont(.body)
                            .foregroundStyle(KXColor.textPrimary)
                            .padding(KXSpacing.m)
                    }
                }
            }
        }
    }
}

// MARK: - KXBadge

/// Every badge style with and without a symbol, and a long text that wraps.
struct KXGalleryBadgePage: View {
    var body: some View {
        KXGalleryPage(topic: .badge) {
            ForEach(KXBadge.Style.allCases, id: \.self) { style in
                KXGalleryDemo("Style .\(style.rawValue)") {
                    HStack(spacing: KXSpacing.xs) {
                        KXBadge(Self.text(for: style), style: style)
                        KXBadge(Self.text(for: style), style: style, systemImage: Self.symbol(for: style))
                    }
                }
            }
            KXGalleryDemo("Long text", note: "Badges wrap instead of truncating.") {
                KXBadge(KXGallerySamples.finnishDelivery, style: .neutral, systemImage: "envelope")
            }
        }
    }

    private static func text(for style: KXBadge.Style) -> String {
        switch style {
        case .gold: "Bestseller"
        case .urgency: "Sale"
        case .neutral: "Digital"
        case .success: "Zugestellt"
        }
    }

    private static func symbol(for style: KXBadge.Style) -> String {
        switch style {
        case .gold: "star"
        case .urgency: "flame"
        case .neutral: "envelope"
        case .success: "checkmark"
        }
    }
}

// MARK: - KXPriceTag

/// Price tags with every optional part, in both sizes and for a market without tax note.
struct KXGalleryPriceTagPage: View {
    var body: some View {
        KXGalleryPage(topic: .priceTag) {
            KXGalleryDemo("Compare-at price, savings and tax note", note: "Windows 11 Pro, DE/DE.") {
                KXPriceTag(
                    price: KXGallerySamples.windowsProPrice,
                    compareAtPrice: KXGallerySamples.windowsProCompareAtPrice,
                    savings: KXGallerySamples.windowsProSavings,
                    taxNote: KXGallerySamples.taxNote
                )
            }
            KXGalleryDemo("Compare-at price and tax note", note: "Office 2024 Professional Plus, DE/DE.") {
                KXPriceTag(
                    price: KXGallerySamples.officeProPlusPrice,
                    compareAtPrice: KXGallerySamples.officeProPlusCompareAtPrice,
                    taxNote: KXGallerySamples.taxNote
                )
            }
            KXGalleryDemo("Size .compact in a 160 pt column", note: "Office 2024 Standard für Mac, as on a product card.") {
                KXPriceTag(
                    price: KXGallerySamples.officeMacPrice,
                    compareAtPrice: KXGallerySamples.officeMacCompareAtPrice,
                    taxNote: KXGallerySamples.taxNote,
                    size: .compact
                )
                .frame(width: 160, alignment: .leading)
            }
            KXGalleryDemo("Price only", note: "Office 2024 Professional Plus, CH/FR: no tax note outside the EU.") {
                KXPriceTag(price: KXGallerySamples.officeProPlusPriceCHF)
            }
        }
    }
}

// MARK: - KXSectionHeader

/// Section headers with and without eyebrow and action.
struct KXGallerySectionHeaderPage: View {
    @State private var lastEvent: String?

    var body: some View {
        KXGalleryPage(topic: .sectionHeader) {
            KXGalleryDemo("Eyebrow and default action") {
                KXSectionHeader("Bestseller", eyebrow: "Sortiment") {
                    lastEvent = "Default action tapped"
                }
            }
            KXGalleryDemo("Title only") {
                KXSectionHeader("So läuft es ab")
            }
            KXGalleryDemo("Custom action title and long words") {
                KXSectionHeader(
                    "Käyttöoikeusavaimet ja toimitus sähköpostitse",
                    eyebrow: "Valikoima",
                    actionTitle: "Näytä kaikki"
                ) {
                    lastEvent = "Custom action tapped"
                }
            }
            KXGalleryDemo("Callbacks") {
                KXGalleryEventLabel(lastEvent)
            }
        }
    }
}

// MARK: - KXSpecRow

/// Specification rows with dotted leaders, separated by dividers inside a card.
struct KXGallerySpecRowPage: View {
    private let rows: [(label: String, value: String)] = [
        (label: "Produkt", value: "Windows 11 Pro"),
        (label: "Lizenz", value: "Dauerlizenz, 1 PC"),
        (label: "Lieferung", value: "Download"),
        (label: KXGallerySamples.finnishLicenseKey, value: KXGallerySamples.finnishDelivery),
    ]

    var body: some View {
        KXGalleryPage(topic: .specRow) {
            KXGalleryDemo(
                "Rows in a card",
                note: "Values derived from the recorded Windows 11 Pro title. The last row stacks when it does not fit."
            ) {
                KXCard {
                    VStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                            if index > 0 {
                                KXDivider()
                            }
                            KXSpecRow(row.label, value: row.value)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - KXDivider

/// Divider styles on both axes.
struct KXGalleryDividerPage: View {
    var body: some View {
        KXGalleryPage(topic: .divider) {
            ForEach(KXDivider.Style.allCases, id: \.self) { style in
                KXGalleryDemo("Style .\(style.rawValue), horizontal") {
                    VStack(alignment: .leading, spacing: KXSpacing.s) {
                        Text(verbatim: KXGallerySamples.deliveryFact)
                        KXDivider(style)
                        Text(verbatim: KXGallerySamples.paymentFact)
                    }
                    .kxFont(.body)
                    .foregroundStyle(KXColor.textPrimary)
                }
            }
            KXGalleryDemo("Vertical") {
                HStack(spacing: KXSpacing.m) {
                    Text(verbatim: "WhatsApp")
                    KXDivider(axis: .vertical)
                    Text(verbatim: "E-Mail")
                    KXDivider(.accent, axis: .vertical)
                    Text(verbatim: "Live-Chat")
                }
                .kxFont(.callout)
                .foregroundStyle(KXColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - KXWordmark

/// The interim logo in every size and on the brand and key card panels.
struct KXGalleryWordmarkPage: View {
    var body: some View {
        KXGalleryPage(topic: .wordmark) {
            ForEach(KXWordmark.Size.allCases, id: \.self) { size in
                KXGalleryDemo("Size .\(size.rawValue)") {
                    KXWordmark(size: size)
                }
            }
            KXGalleryDemo("On a brand panel", note: "color: KXColor.textOnBrand") {
                KXWordmark(size: .regular, color: KXColor.textOnBrand)
                    .padding(KXSpacing.l)
                    .frame(maxWidth: .infinity)
                    .background(KXColor.brand, in: RoundedRectangle(cornerRadius: KXRadius.card, style: .continuous))
            }
            KXGalleryDemo("On the key card", note: "color: KXColor.keyCardText") {
                KXWordmark(size: .large, color: KXColor.keyCardText)
                    .padding(KXSpacing.l)
                    .frame(maxWidth: .infinity)
                    .background(KXColor.keyCardBackground, in: RoundedRectangle(cornerRadius: KXRadius.card, style: .continuous))
            }
        }
    }
}

// MARK: - Previews

#Preview("Content components, light") {
    NavigationStack {
        KXGalleryButtonPage()
    }
}

#Preview("Content components, dark") {
    NavigationStack {
        KXGalleryPriceTagPage()
    }
    .preferredColorScheme(.dark)
}

#Preview("Content components, accessibility size") {
    NavigationStack {
        KXGallerySpecRowPage()
    }
    .dynamicTypeSize(.accessibility2)
}
#endif
