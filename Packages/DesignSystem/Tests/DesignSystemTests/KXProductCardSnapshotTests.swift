import DesignSystem
import SwiftUI
import Testing

extension DesignSystemSnapshotTests {
    /// `KXProductCard` with recorded store data and a local image (never `AsyncImage`), with gold
    /// and urgency badges. Two columns as in the catalog grid, one column at accessibility sizes.
    @MainActor
    @Suite("KXProductCard")
    struct KXProductCardSnapshotTests {
        @Test("Grid of cards", arguments: SnapshotVariant.matrix)
        func variants(_ variant: SnapshotVariant) {
            let copy = SnapshotCopy.forLanguage(variant.language)
            let models = [
                KXProductCardModel(
                    id: "office-2024-professional-plus",
                    title: SnapshotStoreData.officeProPlusTitle,
                    price: SnapshotStoreData.officeProPlusPrice,
                    compareAtPrice: SnapshotStoreData.officeProPlusCompareAtPrice,
                    taxNote: copy.taxNote,
                    badge: copy.bestsellerBadge
                ),
                KXProductCardModel(
                    id: "windows-11-pro",
                    title: SnapshotStoreData.windowsProTitle,
                    price: SnapshotStoreData.windowsProPrice,
                    compareAtPrice: SnapshotStoreData.windowsProCompareAtPrice,
                    taxNote: copy.taxNote,
                    badge: copy.saleBadge,
                    badgeTone: .urgency
                ),
            ]
            // Eager stacks instead of a lazy grid: lazy containers may not have created their
            // children yet when the snapshot measures the layout.
            let layout = variant.textSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: KXSpacing.l))
                : AnyLayout(HStackLayout(alignment: .top, spacing: KXSpacing.m))
            assertComponentSnapshot(variant: variant) {
                layout {
                    ForEach(models) { model in
                        KXProductCard(model) {
                            SnapshotProductArtwork()
                        }
                    }
                }
            }
        }
    }
}
