import DesignSystem
import SwiftUI
import Testing

extension DesignSystemSnapshotTests {
    /// `KXTrustStrip` with the four facts of the Start tab, as a grid inside the gutters and as an
    /// edge-to-edge carousel. The money-back item carries its footnote marker and a tap action.
    @MainActor
    @Suite("KXTrustStrip")
    struct KXTrustStripSnapshotTests {
        @Test("Grid", arguments: SnapshotVariant.matrix)
        func grid(_ variant: SnapshotVariant) {
            let items = Self.items(SnapshotCopy.forLanguage(variant.language))
            assertComponentSnapshot(variant: variant) {
                KXTrustStrip(items: items)
            }
        }

        @Test("Carousel", arguments: SnapshotVariant.matrix)
        func carousel(_ variant: SnapshotVariant) {
            let items = Self.items(SnapshotCopy.forLanguage(variant.language))
            assertComponentSnapshot(variant: variant, horizontalPadding: 0) {
                KXTrustStrip(items: items, arrangement: .carousel)
            }
        }

        private static func items(_ copy: SnapshotCopy) -> [KXTrustItem] {
            [
                KXTrustItem(systemImage: "envelope", text: copy.deliveryFact),
                KXTrustItem(systemImage: "creditcard", text: copy.paymentFact),
                KXTrustItem(systemImage: "arrow.uturn.backward", text: copy.refundFact, footnoteMarker: "*", onTap: {}),
                KXTrustItem(systemImage: "bubble.left.and.bubble.right", text: copy.supportFact),
            ]
        }
    }
}
