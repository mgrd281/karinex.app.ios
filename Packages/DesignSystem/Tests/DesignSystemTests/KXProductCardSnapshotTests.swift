import DesignSystem
import SwiftUI
import Testing

extension DesignSystemSnapshotTests {
    /// `KXProductCard` with recorded store data and a local image (never a download), with gold
    /// and urgency badges. Two columns as in the catalog grid, one column at accessibility sizes.
    /// A second test renders the convenience initializer without an image URL, which shows the
    /// local fallback symbol and makes no request.
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

        @Test("Without an image", arguments: SnapshotVariant.matrix)
        func missingImage(_ variant: SnapshotVariant) {
            let copy = SnapshotCopy.forLanguage(variant.language)
            let model = KXProductCardModel(
                id: "office-2024-standard-mac",
                title: SnapshotStoreData.officeMacTitle,
                price: SnapshotStoreData.officeMacPrice,
                compareAtPrice: SnapshotStoreData.officeMacCompareAtPrice,
                taxNote: copy.taxNote
            )
            // Half the canvas as in the two-column grid; the full width at accessibility sizes.
            let columnWidth: CGFloat? = variant.textSize.isAccessibilitySize
                ? nil
                : (SnapshotLayout.width - 2 * KXSpacing.gutter - KXSpacing.m) / 2
            assertComponentSnapshot(variant: variant) {
                KXProductCard(model)
                    .frame(width: columnWidth)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
