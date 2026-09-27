import SwiftUI

// MARK: - KXCardStyle

/// Background treatment of a ``KXCard``.
public enum KXCardStyle: String, CaseIterable, Sendable {
    /// The cream panel (`surface`). Use for cards placed on the page background.
    case standard
    /// The lighter `surfaceElevated` panel. Use for cards nested in another panel or shown
    /// over imagery.
    case elevated
}

// MARK: - KXCard

/// The KARINEX panel: a cream (dark mode: deep forest) surface with an 18 pt continuous
/// corner radius, a one-pixel hairline border and an optional champagne-gold inset ring.
///
/// The card fills the available width and aligns its content to the leading edge. Content
/// is clipped to the rounded shape, so full-bleed images can be placed inside with
/// `padding: 0`.
///
/// ```swift
/// KXCard(showsInsetRing: true) {
///     VStack(alignment: .leading, spacing: KXSpacing.s) {
///         Text(title).kxFont(.title3).foregroundStyle(KXColor.textPrimary)
///         Text(message).kxFont(.body).foregroundStyle(KXColor.textSecondary)
///     }
/// }
/// ```
public struct KXCard<Content: View>: View {
    private let padding: CGFloat
    private let style: KXCardStyle
    private let showsInsetRing: Bool
    private let content: Content

    @Environment(\.displayScale) private var displayScale

    /// Creates a card.
    ///
    /// - Parameters:
    ///   - padding: Inner padding around the content. Defaults to 16 pt (`KXSpacing.m`).
    ///     With `showsInsetRing` keep it at 16 pt or more so the content clears the ring.
    ///   - style: Background treatment. Defaults to ``KXCardStyle/standard``.
    ///   - showsInsetRing: Draws a thin gold ring inset from the edge, the certificate-like
    ///     accent of the brand. Decorative and hidden from VoiceOver.
    ///   - content: The card content.
    public init(
        padding: CGFloat = KXSpacing.m,
        style: KXCardStyle = .standard,
        showsInsetRing: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.padding = padding
        self.style = style
        self.showsInsetRing = showsInsetRing
        self.content = content()
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: KXRadius.card, style: .continuous)
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(backgroundColor, in: shape)
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(KXColor.hairline, lineWidth: hairlineWidth)
            }
            .overlay {
                if showsInsetRing {
                    RoundedRectangle(cornerRadius: KXRadius.card - kxCardRingInset, style: .continuous)
                        .strokeBorder(KXColor.accent, lineWidth: KXBorder.regular)
                        .padding(kxCardRingInset)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityElement(children: .contain)
    }

    private var backgroundColor: Color {
        switch style {
        case .standard: KXColor.surface
        case .elevated: KXColor.surfaceElevated
        }
    }

    /// One physical pixel, the thinnest line the display can draw.
    private var hairlineWidth: CGFloat {
        1 / max(displayScale, 1)
    }
}

/// Distance of the gold inset ring from the card edge. A file-level constant because
/// generic types cannot have static stored properties.
private let kxCardRingInset: CGFloat = 6

// MARK: - Previews

private struct KXCardPreviewGallery: View {
    var body: some View {
        ScrollView {
            VStack(spacing: KXSpacing.m) {
                // Recorded from the live Storefront API on 2026-09-26 (collection "bestseller", DE/DE).
                KXCard {
                    VStack(alignment: .leading, spacing: KXSpacing.s) {
                        Text(verbatim: "Microsoft Office 2024 Professional Plus Download kaufen")
                            .kxFont(.title3)
                            .foregroundStyle(KXColor.textPrimary)
                        KXPriceTag(price: "29,90 €", compareAtPrice: "149,99 €", taxNote: "inkl. MwSt.")
                    }
                }
                KXCard(showsInsetRing: true) {
                    VStack(alignment: .leading, spacing: KXSpacing.s) {
                        Text(verbatim: "Support")
                            .kxFont(.title3)
                            .foregroundStyle(KXColor.textPrimary)
                        Text(verbatim: "WhatsApp, E-Mail und Live-Chat, Mo. bis So., 06:00 bis 23:00 Uhr deutscher Zeit")
                            .kxFont(.body)
                            .foregroundStyle(KXColor.textSecondary)
                    }
                    .padding(KXSpacing.xs)
                }
                KXCard(style: .elevated) {
                    // Store title rendered as-is; the dash is store content, written as an escape.
                    Text(verbatim: "Windows 11 Pro kaufen \u{2013} Dauerlizenz 1 PC, Download")
                        .kxFont(.body)
                        .foregroundStyle(KXColor.textPrimary)
                }
            }
            .padding(KXSpacing.gutter)
        }
        .kxScreenBackground()
    }
}

#Preview("KXCard, light") {
    KXCardPreviewGallery()
}

#Preview("KXCard, dark") {
    KXCardPreviewGallery()
        .preferredColorScheme(.dark)
}

#Preview("KXCard, accessibility size") {
    KXCardPreviewGallery()
        .dynamicTypeSize(.accessibility2)
}
