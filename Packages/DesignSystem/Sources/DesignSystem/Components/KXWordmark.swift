import SwiftUI

// MARK: - KXWordmark

/// The interim KARINEX logo: the brand name set in the serif display face with wide tracking.
///
/// It replaces the logo until the redesigned brand assets arrive. The brand name is never
/// translated, so it is not part of any String Catalog. The wordmark scales moderately with
/// Dynamic Type (capped, like a logo) and never wraps; on very narrow widths it shrinks.
///
/// ```swift
/// KXWordmark(size: .large)
/// KXWordmark(size: .small, color: KXColor.textOnBrand) // on a brand-colored panel
/// ```
public struct KXWordmark: View {
    /// Size of a ``KXWordmark``.
    public enum Size: String, CaseIterable, Sendable {
        /// 16 pt, for navigation bars and footers.
        case small
        /// 22 pt, for headers and cards.
        case regular
        /// 34 pt, for the hero and launch-like moments.
        case large

        /// Point size at the default Dynamic Type setting.
        var pointSize: CGFloat {
            switch self {
            case .small: 16
            case .regular: 22
            case .large: 34
            }
        }
    }

    /// The brand name as it is always written.
    private static let brandName = "KARINEX"
    /// Spoken form for VoiceOver, so the name is pronounced as a word and not spelled out.
    private static let spokenBrandName = "Karinex"
    /// Letter spacing as a fraction of the point size.
    private static let trackingFactor: CGFloat = 0.28

    private let size: Size
    private let color: Color

    @ScaledMetric(relativeTo: .title) private var dynamicTypeScale: CGFloat = 1

    /// Creates the wordmark.
    ///
    /// - Parameters:
    ///   - size: Size of the wordmark. Defaults to ``Size/regular``.
    ///   - color: Text color. Defaults to `KXColor.textPrimary`. Pass `KXColor.textOnBrand`
    ///     on brand-colored panels and `KXColor.keyCardText` on the key card.
    public init(size: Size = .regular, color: Color = KXColor.textPrimary) {
        self.size = size
        self.color = color
    }

    public var body: some View {
        let scale = min(max(dynamicTypeScale, 0.85), 1.35)
        let pointSize = size.pointSize * scale
        Text(verbatim: Self.brandName)
            .font(KXFont.font(.display, size: Double(pointSize)))
            .tracking(pointSize * Self.trackingFactor)
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .accessibilityLabel(Text(verbatim: Self.spokenBrandName))
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
