import DesignTokens
import SwiftUI
import UIKit

// MARK: - KXBadge

/// A small capsule label in the eyebrow type style (uppercase, tracked), for states such as
/// "Sale", "Neu" or "Digital".
///
/// Styles and their color pairings (all meet WCAG AA text contrast):
/// - ``Style/gold``: champagne-gold fill with ink text.
/// - ``Style/urgency``: terracotta fill with white text. Use sparingly.
/// - ``Style/neutral``: hairline outline with `textSecondary` text.
/// - ``Style/success``: outline and text in the `success` color.
///
/// The badge is not interactive. Its text is read by VoiceOver as passed (the uppercase
/// rendering is visual only). Long texts wrap instead of being truncated.
///
/// ```swift
/// KXBadge(digitalBadgeText, style: .neutral, systemImage: "envelope")
/// ```
public struct KXBadge: View {
    /// Color treatment of a ``KXBadge``.
    public enum Style: String, CaseIterable, Sendable {
        /// Gold fill, ink text. The default, for highlights.
        case gold
        /// Terracotta fill, white text. For urgency (sale, ending deals).
        case urgency
        /// Hairline outline, secondary text. For neutral facts.
        case neutral
        /// Success-colored outline and text. For positive states.
        case success
    }

    private let text: String
    private let style: Style
    private let systemImage: String?

    /// Creates a badge.
    ///
    /// - Parameters:
    ///   - text: The already-localized badge text. Keep it to one or two words.
    ///   - style: Color treatment. Defaults to ``Style/gold``.
    ///   - systemImage: Optional decorative SF Symbol shown before the text.
    public init(_ text: String, style: Style = .gold, systemImage: String? = nil) {
        self.text = text
        self.style = style
        self.systemImage = systemImage
    }

    public var body: some View {
        HStack(spacing: KXSpacing.xxs) {
            if let systemImage {
                Image(systemName: systemImage)
                    .imageScale(.small)
                    .accessibilityHidden(true)
            }
            Text(text)
        }
        .kxFont(.eyebrow)
        .foregroundStyle(foregroundColor)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, KXSpacing.s)
        .padding(.vertical, KXSpacing.xxs)
        .background(fillColor, in: Capsule(style: .continuous))
        .overlay {
            if let strokeColor {
                Capsule(style: .continuous)
                    .strokeBorder(strokeColor, lineWidth: KXBorder.regular)
            }
        }
    }

    // MARK: Appearance

    private var foregroundColor: Color {
        switch style {
        case .gold: KXColor.textOnAccent
        case .urgency: KXColor.textOnUrgency
        case .neutral: KXColor.textSecondary
        case .success: KXColor.success
        }
    }

    private var fillColor: Color {
        switch style {
        case .gold: KXColor.accent
        case .urgency: KXColor.urgency
        case .neutral, .success: Color.clear
        }
    }

    private var strokeColor: Color? {
        switch style {
        case .gold, .urgency: nil
        case .neutral: KXColor.divider
        case .success: KXColor.success
        }
    }
}

// MARK: - Previews

private struct KXBadgePreviewGallery: View {
    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.m) {
            HStack(spacing: KXSpacing.xs) {
                KXBadge("Bestseller")
                KXBadge("Sale", style: .urgency)
            }
            HStack(spacing: KXSpacing.xs) {
                KXBadge("Digital", style: .neutral, systemImage: "envelope")
                KXBadge("Zugestellt", style: .success, systemImage: "checkmark")
            }
            KXBadge("Toimitus sähköpostitse minuuteissa", style: .neutral)
        }
        .padding(KXSpacing.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .kxScreenBackground()
    }
}

#Preview("KXBadge, light") {
    KXBadgePreviewGallery()
}

#Preview("KXBadge, dark") {
    KXBadgePreviewGallery()
        .preferredColorScheme(.dark)
}

#Preview("KXBadge, accessibility size") {
    KXBadgePreviewGallery()
        .dynamicTypeSize(.accessibility2)
}
