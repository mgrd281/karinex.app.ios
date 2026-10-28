import SwiftUI

// MARK: - KXCardStyle

/// Background treatment of a ``KXCard``.
public enum KXCardStyle: String, CaseIterable, Sendable {
    /// The light grey panel (`surface`). Use for cards placed on the page background.
    case standard
    /// The lighter `surfaceElevated` panel. Use for cards nested in another panel or shown
    /// over imagery.
    case elevated
}

// MARK: - KXCard

/// The KARINEX panel: a flat light grey (dark mode: graphite) surface with a 12 pt continuous
/// corner radius. No border and no shadow, so cards read as calm blocks on the white page.
///
/// An outlined card (`isOutlined: true`) is white with a thin ink outline instead. Use it for
/// the one card on a screen that carries a promise, such as the money-back conditions.
///
/// The card fills the available width and aligns its content to the leading edge. Content
/// is clipped to the rounded shape, so full-bleed images can be placed inside with
/// `padding: 0`.
///
/// ```swift
/// KXCard(isOutlined: true) {
///     VStack(alignment: .leading, spacing: KXSpacing.s) {
///         Text(title).kxFont(.title3).foregroundStyle(KXColor.textPrimary)
///         Text(message).kxFont(.body).foregroundStyle(KXColor.textSecondary)
///     }
/// }
/// ```
public struct KXCard<Content: View>: View {
    private let padding: CGFloat
    private let style: KXCardStyle
    private let isOutlined: Bool
    private let content: Content

    /// Creates a card.
    ///
    /// - Parameters:
    ///   - padding: Inner padding around the content. Defaults to 16 pt (`KXSpacing.m`).
    ///   - style: Background treatment. Defaults to ``KXCardStyle/standard``.
    ///   - isOutlined: Draws the card white with a thin ink outline, for emphasis. Defaults to
    ///     `false`.
    ///   - content: The card content.
    public init(
        padding: CGFloat = KXSpacing.m,
        style: KXCardStyle = .standard,
        isOutlined: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.padding = padding
        self.style = style
        self.isOutlined = isOutlined
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
                if isOutlined {
                    shape
                        .strokeBorder(KXColor.textPrimary, lineWidth: KXBorder.regular)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityElement(children: .contain)
    }

    private var backgroundColor: Color {
        if isOutlined {
            return KXColor.surfaceElevated
        }
        switch style {
        case .standard: return KXColor.surface
        case .elevated: return KXColor.surfaceElevated
        }
    }
}

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
                KXCard(isOutlined: true) {
                    VStack(alignment: .leading, spacing: KXSpacing.s) {
                        Text(verbatim: "Support")
                            .kxFont(.title3)
                            .foregroundStyle(KXColor.textPrimary)
                        Text(verbatim: "WhatsApp, E-Mail und Live-Chat, Mo. bis So., 08:00 bis 23:00 Uhr deutscher Zeit")
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
