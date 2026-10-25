import DesignSystem
import SwiftUI

// MARK: - HomeHero

/// The hero of the Start tab: the KARINEX wordmark, an eyebrow, a bold display headline, a short
/// introduction and the primary call to action "Zum Sortiment", on a flat light grey panel.
/// No ornaments: the type and the black button carry it.
struct HomeHero: View {
    /// Called by the call to action.
    let onBrowse: @MainActor () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.l) {
            // Masthead size, so the display headline stays the dominant line of the hero.
            KXWordmark(size: .regular)
            VStack(alignment: .leading, spacing: KXSpacing.s) {
                Text("home.hero.eyebrow", bundle: .module)
                    .kxFont(.eyebrow)
                    .foregroundStyle(KXColor.textSecondary)
                Text("home.hero.title", bundle: .module)
                    .kxFont(.display)
                    .foregroundStyle(KXColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text("home.hero.body", bundle: .module)
                    .kxFont(.body)
                    .foregroundStyle(KXColor.textSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            KXButton(
                String(localized: "home.hero.cta", bundle: .module),
                isFullWidth: true
            ) {
                onBrowse()
            }
            .accessibilityIdentifier("home.hero.cta")
        }
        .padding(KXSpacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KXColor.surface, in: RoundedRectangle(cornerRadius: KXRadius.large, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}
