import SwiftUI

// MARK: - KXDivider

/// A one-pixel rule, horizontal or vertical.
///
/// Unlike SwiftUI's `Divider` it uses the design-system colors, and it can be drawn in
/// champagne gold for editorial separations. It is decorative and hidden from VoiceOver.
///
/// ```swift
/// VStack(spacing: KXSpacing.s) {
///     KXSpecRow(label, value: value)
///     KXDivider()
/// }
/// ```
public struct KXDivider: View {
    /// Color of a ``KXDivider``.
    public enum Style: String, CaseIterable, Sendable {
        /// Neutral divider color, for lists and forms.
        case standard
        /// Champagne gold, for editorial separations.
        case accent
    }

    private let style: Style
    private let axis: Axis

    @Environment(\.displayScale) private var displayScale

    /// Creates a divider.
    ///
    /// - Parameters:
    ///   - style: Color of the rule. Defaults to ``Style/standard``.
    ///   - axis: `.horizontal` (default) fills the available width, `.vertical` the height.
    public init(_ style: Style = .standard, axis: Axis = .horizontal) {
        self.style = style
        self.axis = axis
    }

    public var body: some View {
        let thickness = 1 / max(displayScale, 1)
        Rectangle()
            .fill(color)
            .frame(
                width: axis == .vertical ? thickness : nil,
                height: axis == .horizontal ? thickness : nil
            )
            .frame(
                maxWidth: axis == .horizontal ? .infinity : nil,
                maxHeight: axis == .vertical ? .infinity : nil
            )
            .accessibilityHidden(true)
    }

    private var color: Color {
        switch style {
        case .standard: KXColor.divider
        case .accent: KXColor.accent
        }
    }
}

// MARK: - Previews

private struct KXDividerPreviewGallery: View {
    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.m) {
            Text(verbatim: "Standard")
                .kxFont(.body)
                .foregroundStyle(KXColor.textPrimary)
            KXDivider()
            Text(verbatim: "Accent")
                .kxFont(.body)
                .foregroundStyle(KXColor.textPrimary)
            KXDivider(.accent)
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
        .padding(KXSpacing.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .kxScreenBackground()
    }
}

#Preview("KXDivider, light") {
    KXDividerPreviewGallery()
}

#Preview("KXDivider, dark") {
    KXDividerPreviewGallery()
        .preferredColorScheme(.dark)
}

#Preview("KXDivider, accessibility size") {
    KXDividerPreviewGallery()
        .dynamicTypeSize(.accessibility2)
}
