import DesignSystem
import SwiftUI
import Testing

extension DesignSystemSnapshotTests {
    /// `KXPriceTag` with every optional part, in both sizes, and without a tax note.
    @MainActor
    @Suite("KXPriceTag")
    struct KXPriceTagSnapshotTests {
        @Test("Compare-at price, savings, tax note and sizes", arguments: SnapshotVariant.matrix)
        func variants(_ variant: SnapshotVariant) {
            let copy = SnapshotCopy.forLanguage(variant.language)
            assertComponentSnapshot(variant: variant) {
                VStack(alignment: .leading, spacing: KXSpacing.l) {
                    KXPriceTag(
                        price: SnapshotStoreData.windowsProPrice,
                        compareAtPrice: SnapshotStoreData.windowsProCompareAtPrice,
                        savings: copy.windowsProSavings,
                        taxNote: copy.taxNote
                    )
                    KXPriceTag(
                        price: SnapshotStoreData.officeProPlusPrice,
                        compareAtPrice: SnapshotStoreData.officeProPlusCompareAtPrice,
                        taxNote: copy.taxNote
                    )
                    KXPriceTag(
                        price: SnapshotStoreData.officeMacPrice,
                        compareAtPrice: SnapshotStoreData.officeMacCompareAtPrice,
                        taxNote: copy.taxNote,
                        size: .compact
                    )
                    .frame(width: 160, alignment: .leading)
                    KXPriceTag(price: SnapshotStoreData.officeProPlusPriceCHF)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
