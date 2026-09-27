import DesignSystem
import SwiftUI
import Testing

extension DesignSystemSnapshotTests {
    /// `KXSpecRow` with dotted leaders, including a row that stacks because it does not fit.
    @MainActor
    @Suite("KXSpecRow")
    struct KXSpecRowSnapshotTests {
        @Test("Leaders and stacking", arguments: SnapshotVariant.matrix)
        func variants(_ variant: SnapshotVariant) {
            let copy = SnapshotCopy.forLanguage(variant.language)
            assertComponentSnapshot(variant: variant) {
                KXCard {
                    VStack(spacing: 0) {
                        KXSpecRow(copy.productLabel, value: "Windows 11 Pro")
                        KXDivider()
                        KXSpecRow(copy.licenseLabel, value: copy.licenseValue)
                        KXDivider()
                        KXSpecRow(copy.deliveryLabel, value: copy.deliveryValue)
                        KXDivider()
                        KXSpecRow(copy.licenseKeyLabel, value: copy.deliveryFact)
                    }
                }
            }
        }
    }
}
