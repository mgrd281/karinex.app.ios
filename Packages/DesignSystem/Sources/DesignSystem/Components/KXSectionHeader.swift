import SwiftUI

// MARK: - KXSectionHeader

/// The section header: an optional small eyebrow, a bold sans serif title and an optional
/// trailing text action such as "Alle anzeigen". No rules or ornaments; the type carries the
/// hierarchy.
///
/// The title carries the header trait for VoiceOver rotor navigation; the eyebrow is read
/// together with the title. At accessibility text sizes the action moves below the title so
/// that neither is truncated.
///
/// ```swift
/// KXSectionHeader(title, eyebrow: eyebrow, action: { selectedTab = .shop })
/// ```
public struct KXSectionHeader: View {
    private let title: String
    private let eyebrow: String?
    private let actionTitle: String?
    private let action: (() -> Void)?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Creates a section header.
    ///
    /// - Parameters:
    ///   - title: The already-localized section title.
    ///   - eyebrow: Optional already-localized small label above the title.
    ///   - actionTitle: Label of the trailing action. When `nil` and an `action` is given,
    ///     the design-system text "Alle anzeigen" is used.
    ///   - action: Optional trailing action. When `nil` no button is shown.
    public init(
        _ title: String,
        eyebrow: String? = nil,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.eyebrow = eyebrow
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.xs) {
            if let eyebrow {
                Text(eyebrow)
                    .kxFont(.eyebrow)
                    .foregroundStyle(KXColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
            }
            if dynamicTypeSize.isAccessibilitySize {
                titleText
                actionButton
            } else {
                HStack(alignment: .firstTextBaseline, spacing: KXSpacing.m) {
                    titleText
                        .frame(maxWidth: .infinity, alignment: .leading)
                    actionButton
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Parts

    private var titleText: some View {
        Text(title)
            .kxFont(.title2)
            .foregroundStyle(KXColor.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(accessibilityTitle)
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder private var actionButton: some View {
        if let action {
            KXButton(
                actionTitle ?? String(localized: "kx.section.show_all", bundle: .module),
                style: .tertiary,
                size: .compact,
                action: action
            )
        }
    }

    /// The title, prefixed with the eyebrow when there is one, so VoiceOver reads both at once.
    private var accessibilityTitle: String {
        guard let eyebrow else { return title }
        return "\(eyebrow), \(title)"
    }
}

// MARK: - Previews

private struct KXSectionHeaderPreviewGallery: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KXSpacing.xl) {
                KXSectionHeader("Bestseller", eyebrow: "Sortiment", action: {})
                KXSectionHeader("So läuft es ab")
                KXSectionHeader(
                    "Käyttöoikeusavaimet ja toimitus sähköpostitse",
                    eyebrow: "Valikoima",
                    actionTitle: "Näytä kaikki",
                    action: {}
                )
            }
            .padding(KXSpacing.gutter)
        }
        .kxScreenBackground()
    }
}

#Preview("KXSectionHeader, light") {
    KXSectionHeaderPreviewGallery()
}

#Preview("KXSectionHeader, dark") {
    KXSectionHeaderPreviewGallery()
        .preferredColorScheme(.dark)
}

#Preview("KXSectionHeader, accessibility size") {
    KXSectionHeaderPreviewGallery()
        .dynamicTypeSize(.accessibility2)
}
