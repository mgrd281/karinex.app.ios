import SwiftUI

// MARK: - KXSpecRow

/// A specification line: the label in grey on the leading side and the value on the trailing
/// side, with open space between them. There is deliberately no dotted leader (owner decision of
/// 2026-10-26: dots between label and value look dated).
///
/// When label and value do not fit on one line (long values, long translations, large text
/// sizes) the row stacks the value below the label instead of truncating either.
///
/// VoiceOver reads the row as one element: the label, then the value.
///
/// ```swift
/// VStack(spacing: 0) {
///     ForEach(specs) { spec in
///         KXSpecRow(spec.label, value: spec.value)
///     }
/// }
/// ```
public struct KXSpecRow: View {
    private let label: String
    private let value: String

    /// Creates a specification row.
    ///
    /// - Parameters:
    ///   - label: The already-localized label, e.g. "Lizenz".
    ///   - value: The value as provided by the store, e.g. "Dauerlizenz, 1 PC".
    public init(_ label: String, value: String) {
        self.label = label
        self.value = value
    }

    public var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: KXSpacing.m) {
                labelText
                    .lineLimit(1)
                Spacer(minLength: KXSpacing.m)
                valueText
                    .lineLimit(1)
            }
            VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                labelText
                    .fixedSize(horizontal: false, vertical: true)
                valueText
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, KXSpacing.xs)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }

    // MARK: Parts

    private var labelText: some View {
        Text(label)
            .kxFont(.callout)
            .foregroundStyle(KXColor.textSecondary)
    }

    private var valueText: some View {
        Text(value)
            .fontWeight(.medium)
            .kxFont(.callout)
            .foregroundStyle(KXColor.textPrimary)
    }
}

// MARK: - Previews

// Values derived from the Windows 11 Pro product recorded from the live Storefront API on
// 2026-09-26 (API 2026-10): its title names "Dauerlizenz 1 PC" and "Download".
private struct KXSpecRowPreviewGallery: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                KXSpecRow("Produkt", value: "Windows 11 Pro")
                KXSpecRow("Lizenz", value: "Dauerlizenz, 1 PC")
                KXSpecRow("Lieferung", value: "Download")
                KXSpecRow("Käyttöoikeusavain", value: "Toimitus sähköpostitse minuuteissa")
            }
            .padding(KXSpacing.gutter)
        }
        .kxScreenBackground()
    }
}

#Preview("KXSpecRow, light") {
    KXSpecRowPreviewGallery()
}

#Preview("KXSpecRow, dark") {
    KXSpecRowPreviewGallery()
        .preferredColorScheme(.dark)
}

#Preview("KXSpecRow, accessibility size") {
    KXSpecRowPreviewGallery()
        .dynamicTypeSize(.accessibility2)
}
