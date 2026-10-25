import SwiftUI

// MARK: - KXWordmark

/// The KARINEX logo: the store's wordmark (the logo of karinex.de, `KarinexLogo` in the
/// DesignSystem asset catalog), drawn as a template image so it takes the given color: ink on
/// light pages, white in dark mode or on dark panels.
///
/// The brand name is never translated, so it is not part of any String Catalog. The logo scales
/// moderately with Dynamic Type (capped, like a logo) and never wraps.
///
/// ```swift
/// KXWordmark(size: .large)
/// KXWordmark(size: .small, color: KXColor.textOnBrand) // on a brand-colored panel
/// ```
public struct KXWordmark: View {
    /// Size of a ``KXWordmark``.
    public enum Size: String, CaseIterable, Sendable {
        /// 16 pt tall, for navigation bars and footers.
        case small
        /// 22 pt tall, for headers and cards.
        case regular
        /// 34 pt tall, for the hero and launch-like moments.
        case large

        /// Logo height at the default Dynamic Type setting.
        var pointSize: CGFloat {
            switch self {
            case .small: 16
            case .regular: 22
            case .large: 34
            }
        }
    }

    /// Spoken form for VoiceOver, so the name is pronounced as a word and not spelled out.
    private static let spokenBrandName = "Karinex"

    private let size: Size
    private let color: Color

    @ScaledMetric(relativeTo: .title) private var dynamicTypeScale: CGFloat = 1

    /// Creates the wordmark.
    ///
    /// - Parameters:
    ///   - size: Size of the wordmark. Defaults to ``Size/regular``.
    ///   - color: Logo color. Defaults to `KXColor.textPrimary`. Pass `KXColor.textOnBrand`
    ///     on brand-colored panels and `KXColor.keyCardText` on the key card.
    public init(size: Size = .regular, color: Color = KXColor.textPrimary) {
        self.size = size
        self.color = color
    }

    public var body: some View {
        let scale = min(max(dynamicTypeScale, 0.85), 1.35)
        Image("KarinexLogo", bundle: .module)
            .renderingMode(.template)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(height: size.pointSize * scale)
            .foregroundStyle(color)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: Self.spokenBrandName))
            .accessibilityAddTraits(.isImage)
    }
}

// MARK: - Previews

private struct KXWordmarkPreviewGallery: View {
    var body: some View {
        VStack(spacing: KXSpacing.l) {
            KXWordmark(size: .small)
            KXWordmark()
            KXWordmark(size: .large)
            KXWordmark(size: .regular, color: KXColor.textOnBrand)
                .padding(KXSpacing.m)
                .frame(maxWidth: .infinity)
                .background(KXColor.brand, in: RoundedRectangle(cornerRadius: KXRadius.card, style: .continuous))
        }
        .padding(KXSpacing.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .kxScreenBackground()
    }
}

#Preview("KXWordmark, light") {
    KXWordmarkPreviewGallery()
}

#Preview("KXWordmark, dark") {
    KXWordmarkPreviewGallery()
        .preferredColorScheme(.dark)
}

#Preview("KXWordmark, accessibility size") {
    KXWordmarkPreviewGallery()
        .dynamicTypeSize(.accessibility2)
}
