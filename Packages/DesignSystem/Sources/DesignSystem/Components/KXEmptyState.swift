import SwiftUI

// MARK: - KXEmptyState

/// The editorial empty state: an SF Symbol inside a double champagne-gold ring, a serif title,
/// a short message and an optional primary action.
///
/// Use it for empty lists and screens whose content is not available yet (empty cart, no
/// search results, catalog placeholder). The content is centered and limited to a readable
/// width, and everything wraps at large text sizes.
///
/// ```swift
/// KXEmptyState(
///     systemImage: "bag",
///     title: emptyTitle,
///     message: emptyMessage,
///     actionTitle: browseTitle,
///     action: onBrowse
/// )
/// ```
public struct KXEmptyState: View {
    private let systemImage: String
    private let title: String
    private let message: String
    private let actionTitle: String?
    private let action: (() -> Void)?

    @ScaledMetric(relativeTo: .title) private var ringDiameter: CGFloat = 88
    @ScaledMetric(relativeTo: .title) private var symbolSize: CGFloat = 30

    /// Creates an empty state.
    ///
    /// - Parameters:
    ///   - systemImage: SF Symbol shown in the gold ring. Decorative, hidden from VoiceOver.
    ///   - title: The already-localized title. It carries the header trait.
    ///   - message: The already-localized explanation, one or two sentences.
    ///   - actionTitle: Label of the optional primary button.
    ///   - action: Called when the button is tapped. The button is shown only when both
    ///     `actionTitle` and `action` are given.
    public init(
        systemImage: String,
        title: String,
        message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        VStack(spacing: KXSpacing.l) {
            symbolRing
            VStack(spacing: KXSpacing.s) {
                Text(title)
                    .kxFont(.title2)
                    .foregroundStyle(KXColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(message)
                    .kxFont(.body)
                    .foregroundStyle(KXColor.textSecondary)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                KXButton(actionTitle, action: action)
                    .padding(.top, KXSpacing.xs)
            }
        }
        .frame(maxWidth: 480)
        .padding(.horizontal, KXSpacing.l)
        .padding(.vertical, KXSpacing.xl)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    // MARK: Parts

    private var symbolRing: some View {
        let diameter = min(ringDiameter, 144)
        return ZStack {
            Circle()
                .fill(KXColor.surface)
            Circle()
                .strokeBorder(KXColor.accent, lineWidth: KXBorder.regular)
            Circle()
                .strokeBorder(KXColor.accent.opacity(0.45), lineWidth: KXBorder.hairline)
                .padding(KXSpacing.xs - KXSpacing.xxs / 2)
            Image(systemName: systemImage)
                .font(.system(size: min(symbolSize, 48), weight: .light))
                .foregroundStyle(KXColor.brand)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }
}

// MARK: - Previews

private struct KXEmptyStatePreviewGallery: View {
    var body: some View {
        ScrollView {
            VStack(spacing: KXSpacing.xl) {
                KXEmptyState(
                    systemImage: "bag",
                    title: "Ihr Warenkorb ist leer",
                    message: "Legen Sie Produkte in den Warenkorb, um sie hier zu sehen.",
                    actionTitle: "Zum Sortiment",
                    action: {}
                )
                KXEmptyState(
                    systemImage: "bag",
                    title: "Ostoskorisi on tyhjä",
                    message: "Käyttöoikeusavaimet toimitetaan sähköpostitse minuuteissa."
                )
            }
        }
        .kxScreenBackground()
    }
}

#Preview("KXEmptyState, light") {
    KXEmptyStatePreviewGallery()
}

#Preview("KXEmptyState, dark") {
    KXEmptyStatePreviewGallery()
        .preferredColorScheme(.dark)
}

#Preview("KXEmptyState, accessibility size") {
    KXEmptyStatePreviewGallery()
        .dynamicTypeSize(.accessibility2)
}
