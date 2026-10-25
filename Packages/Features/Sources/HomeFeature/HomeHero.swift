import DesignSystem
import SwiftUI

// MARK: - HomeHero

/// The editorial hero of the Start tab: the KARINEX wordmark, an eyebrow, a serif display
/// headline with a short gold rule, a short introduction and the primary call to action
/// "Zum Sortiment", on a cream panel.
///
/// A champagne-gold seal ornament in the top trailing corner drifts slightly while the page
/// scrolls (subtle parallax). With Reduce Motion it stays still.
struct HomeHero: View {
    /// Called by the call to action.
    let onBrowse: @MainActor () -> Void

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: KXRadius.large, style: .continuous)
        VStack(alignment: .leading, spacing: KXSpacing.l) {
            // Masthead size, so the display headline stays the dominant line of the hero.
            KXWordmark(size: .regular)
            VStack(alignment: .leading, spacing: KXSpacing.s) {
                Text("home.hero.eyebrow", bundle: .module)
                    .kxFont(.eyebrow)
                    .foregroundStyle(KXColor.accentText)
                Text("home.hero.title", bundle: .module)
                    .kxFont(.display)
                    .foregroundStyle(KXColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Rectangle()
                    .fill(KXColor.accent)
                    .frame(width: KXSpacing.xl, height: KXBorder.emphasis)
                    .accessibilityHidden(true)
                Text("home.hero.body", bundle: .module)
                    .kxFont(.body)
                    .foregroundStyle(KXColor.textSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            KXButton(
                String(localized: "home.hero.cta", bundle: .module),
                systemImage: "square.grid.2x2",
                isFullWidth: true
            ) {
                onBrowse()
            }
            .accessibilityIdentifier("home.hero.cta")
        }
        .padding(KXSpacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                KXColor.surface
                HomeHeroOrnament()
            }
        }
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(KXColor.hairline, lineWidth: 1 / max(displayScale, 1))
        }
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Ornament

/// Concentric champagne-gold rings, the certificate-seal motif of the brand, partly cut off by
/// the hero panel. Decorative: hidden from VoiceOver and not hit-testable.
///
/// The rings move by up to `KXMotion.heroParallax` (the brand's hero parallax distance) against
/// the scroll direction while the hero leaves the screen. Reduce Motion turns the movement off.
private struct HomeHeroOrnament: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Copied into a local constant so that the `@Sendable` transition closure captures a
        // plain value instead of the view.
        let parallaxDistance: CGFloat = reduceMotion ? 0 : KXMotion.heroParallax
        ZStack {
            ring(diameter: 200, opacity: 0.6, lineWidth: KXBorder.regular)
            ring(diameter: 150, opacity: 0.4, lineWidth: KXBorder.hairline)
            ring(diameter: 100, opacity: 0.3, lineWidth: KXBorder.hairline)
        }
        // Centers the seal on the top trailing corner, clear of the wordmark and headline.
        .offset(x: 96, y: -84)
        .scrollTransition(axis: .vertical) { content, phase in
            content.offset(y: CGFloat(-phase.value) * parallaxDistance)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func ring(diameter: CGFloat, opacity: Double, lineWidth: CGFloat) -> some View {
        Circle()
            .strokeBorder(KXColor.accent.opacity(opacity), lineWidth: lineWidth)
            .frame(width: diameter, height: diameter)
    }
}
