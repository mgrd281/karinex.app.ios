import DesignSystem
import SwiftUI
import Testing

extension DesignSystemSnapshotTests {
    /// Every `KXBadge` style with and without a symbol, and a long text that wraps.
    @MainActor
    @Suite("KXBadge")
    struct KXBadgeSnapshotTests {
        @Test("Styles, symbols and wrapping", arguments: SnapshotVariant.matrix)
        func variants(_ variant: SnapshotVariant) {
            let copy = SnapshotCopy.forLanguage(variant.language)
            assertComponentSnapshot(variant: variant) {
                VStack(alignment: .leading, spacing: KXSpacing.s) {
                    HStack(spacing: KXSpacing.xs) {
                        KXBadge(copy.bestsellerBadge)
                        KXBadge(copy.saleBadge, style: .urgency)
                    }
                    HStack(spacing: KXSpacing.xs) {
                        KXBadge(copy.digitalBadge, style: .neutral, systemImage: "envelope")
                        KXBadge(copy.deliveredBadge, style: .success, systemImage: "checkmark")
                    }
                    KXBadge(copy.deliveryFact, style: .neutral)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
