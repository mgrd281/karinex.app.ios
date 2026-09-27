import DesignSystem
import SwiftUI
import Testing

extension DesignSystemSnapshotTests {
    /// `KXSectionHeader` with eyebrow and the catalog's default action, title only, and a long
    /// title with a custom action.
    @MainActor
    @Suite("KXSectionHeader")
    struct KXSectionHeaderSnapshotTests {
        @Test("Eyebrow, actions and long titles", arguments: SnapshotVariant.matrix)
        func variants(_ variant: SnapshotVariant) {
            let copy = SnapshotCopy.forLanguage(variant.language)
            assertComponentSnapshot(variant: variant) {
                VStack(alignment: .leading, spacing: KXSpacing.xl) {
                    KXSectionHeader(copy.sectionTitle, eyebrow: copy.sectionEyebrow, action: {})
                    KXSectionHeader(copy.processTitle)
                    KXSectionHeader(
                        copy.longSectionTitle,
                        eyebrow: copy.sectionEyebrow,
                        actionTitle: copy.allProducts,
                        action: {}
                    )
                }
            }
        }
    }
}
