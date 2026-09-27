import DesignSystem
import SwiftUI
import Testing

extension DesignSystemSnapshotTests {
    /// `KXDivider` in both styles, horizontal and vertical.
    @MainActor
    @Suite("KXDivider")
    struct KXDividerSnapshotTests {
        @Test("Styles and axes", arguments: SnapshotVariant.matrix)
        func variants(_ variant: SnapshotVariant) {
            let copy = SnapshotCopy.forLanguage(variant.language)
            assertComponentSnapshot(variant: variant) {
                VStack(alignment: .leading, spacing: KXSpacing.m) {
                    Text(verbatim: copy.deliveryFact)
                    KXDivider()
                    Text(verbatim: copy.paymentFact)
                    KXDivider(.accent)
                    HStack(spacing: KXSpacing.m) {
                        Text(verbatim: "WhatsApp")
                        KXDivider(axis: .vertical)
                        Text(verbatim: copy.email)
                        KXDivider(.accent, axis: .vertical)
                        Text(verbatim: "Live-Chat")
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                .kxFont(.callout)
                .foregroundStyle(KXColor.textPrimary)
            }
        }
    }
}
