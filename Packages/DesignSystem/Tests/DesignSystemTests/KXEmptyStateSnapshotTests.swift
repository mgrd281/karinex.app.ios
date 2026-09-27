import DesignSystem
import SwiftUI
import Testing

extension DesignSystemSnapshotTests {
    /// `KXEmptyState` with and without the primary action.
    @MainActor
    @Suite("KXEmptyState")
    struct KXEmptyStateSnapshotTests {
        @Test("With and without action", arguments: SnapshotVariant.matrix)
        func variants(_ variant: SnapshotVariant) {
            let copy = SnapshotCopy.forLanguage(variant.language)
            assertComponentSnapshot(variant: variant) {
                VStack(spacing: KXSpacing.l) {
                    KXEmptyState(
                        systemImage: "bag",
                        title: copy.emptyCartTitle,
                        message: copy.emptyCartMessage,
                        actionTitle: copy.browse,
                        action: {}
                    )
                    KXDivider()
                    KXEmptyState(
                        systemImage: "magnifyingglass",
                        title: copy.noResultsTitle,
                        message: copy.noResultsMessage
                    )
                }
            }
        }
    }
}
