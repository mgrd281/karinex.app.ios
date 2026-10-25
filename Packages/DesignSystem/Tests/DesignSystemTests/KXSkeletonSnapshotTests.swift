import DesignSystem
import SwiftUI
import Testing

extension DesignSystemSnapshotTests {
    /// `KXSkeleton` blocks and the redacting `kxSkeleton(isActive:)` modifier. The canvas turns the
    /// time-based shimmer off, so the render does not depend on the clock.
    @MainActor
    @Suite("KXSkeleton")
    struct KXSkeletonSnapshotTests {
        @Test("Placeholders and redacted content", arguments: SnapshotVariant.matrix)
        func variants(_ variant: SnapshotVariant) {
            let copy = SnapshotCopy.forLanguage(variant.language)
            assertComponentSnapshot(variant: variant) {
                VStack(alignment: .leading, spacing: KXSpacing.l) {
                    HStack(alignment: .top, spacing: KXSpacing.m) {
                        ForEach(0..<2, id: \.self) { _ in
                            VStack(alignment: .leading, spacing: KXSpacing.xs) {
                                KXSkeleton(cornerRadius: KXRadius.card)
                                    .aspectRatio(1, contentMode: .fit)
                                KXSkeleton()
                                    .frame(width: 64, height: 10)
                                KXSkeleton()
                                    .frame(height: 16)
                                KXSkeleton()
                                    .frame(width: 80, height: 20)
                            }
                        }
                    }
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
                            KXButton(copy.addToCart, isFullWidth: true) {}
                        }
                    }
                    .kxSkeleton(isActive: true)
                }
            }
        }
    }
}
