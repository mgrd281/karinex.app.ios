import DesignSystem
import SwiftUI
import Testing

extension DesignSystemSnapshotTests {
    /// `KXCard` in both styles, with the gold inset ring and with full-bleed content.
    @MainActor
    @Suite("KXCard")
    struct KXCardSnapshotTests {
        @Test("Styles, inset ring and full-bleed content", arguments: SnapshotVariant.matrix)
        func variants(_ variant: SnapshotVariant) {
            let copy = SnapshotCopy.forLanguage(variant.language)
            assertComponentSnapshot(variant: variant) {
                VStack(spacing: KXSpacing.m) {
                    KXCard {
                        VStack(alignment: .leading, spacing: KXSpacing.s) {
                            Text(verbatim: SnapshotStoreData.officeProPlusTitle)
                                .kxFont(.title3)
                                .foregroundStyle(KXColor.textPrimary)
                            KXPriceTag(
                                price: SnapshotStoreData.officeProPlusPrice,
                                compareAtPrice: SnapshotStoreData.officeProPlusCompareAtPrice,
                                taxNote: copy.taxNote
                            )
                        }
                    }
                    KXCard(showsInsetRing: true) {
                        VStack(alignment: .leading, spacing: KXSpacing.s) {
                            Text(verbatim: copy.supportTitle)
                                .kxFont(.title3)
                                .foregroundStyle(KXColor.textPrimary)
                            Text(verbatim: copy.supportChannels)
                                .kxFont(.body)
                                .foregroundStyle(KXColor.textSecondary)
                        }
                        .padding(KXSpacing.xs)
                    }
                    KXCard(style: .elevated) {
                        Text(verbatim: SnapshotStoreData.windowsProTitle)
                            .kxFont(.body)
                            .foregroundStyle(KXColor.textPrimary)
                    }
                    KXCard(padding: 0) {
                        VStack(alignment: .leading, spacing: 0) {
                            SnapshotProductArtwork()
                                .frame(height: 96)
                            Text(verbatim: copy.deliveryFact)
                                .kxFont(.body)
                                .foregroundStyle(KXColor.textPrimary)
                                .padding(KXSpacing.m)
                        }
                    }
                }
            }
        }
    }
}
