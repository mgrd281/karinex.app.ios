import DesignSystem
import SwiftUI

// MARK: - HomeTrustSection

/// The trust strip of the Start tab with its section header and the money-back footnote.
///
/// The four facts come from ``HomeTrustFact``. The money-back tile carries the footnote marker
/// and presents the conditions on tap; the footnote below the strip repeats the condition in
/// short form and offers the same sheet, so the condition is always visible next to the promise
/// (PROMPT.md section 2).
struct HomeTrustSection: View {
    /// Controls the presentation of the money-back conditions sheet.
    @Binding var isConditionPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.m) {
            KXSectionHeader(
                String(localized: "home.trust.title", bundle: .module),
                eyebrow: String(localized: "home.trust.eyebrow", bundle: .module)
            )
            KXTrustStrip(items: HomeTrustFact.allCases.map { trustItem(for: $0) })
                .accessibilityIdentifier("home.trust")
            conditionFootnote
        }
    }

    // MARK: Parts

    private var conditionFootnote: some View {
        VStack(alignment: .leading, spacing: KXSpacing.xxs) {
            HStack(alignment: .firstTextBaseline, spacing: KXSpacing.xxs) {
                Text(verbatim: HomeTrustFact.conditionMarker)
                    .kxFont(.footnote)
                    .foregroundStyle(KXColor.textSecondary)
                    .accessibilityHidden(true)
                Text("home.trust.footnote", bundle: .module)
                    .kxFont(.footnote)
                    .foregroundStyle(KXColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            KXButton(
                String(localized: "home.trust.conditions", bundle: .module),
                style: .tertiary,
                size: .compact
            ) {
                isConditionPresented = true
            }
            // Tertiary buttons carry a small inner padding; this aligns the label with the text.
            .padding(.leading, -KXSpacing.xs)
            .accessibilityIdentifier("home.trust.conditions")
        }
    }

    // MARK: Items

    private func trustItem(for fact: HomeTrustFact) -> KXTrustItem {
        guard fact.revealsConditions else {
            return KXTrustItem(systemImage: fact.systemImage, text: fact.text, id: fact.id)
        }
        return KXTrustItem(
            systemImage: fact.systemImage,
            text: fact.text,
            footnoteMarker: fact.footnoteMarker,
            accessibilityHint: String(localized: "home.trust.moneyback.hint", bundle: .module),
            id: fact.id
        ) {
            isConditionPresented = true
        }
    }
}
