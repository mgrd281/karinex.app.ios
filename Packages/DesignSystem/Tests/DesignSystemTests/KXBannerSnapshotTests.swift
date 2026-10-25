import DesignSystem
import SwiftUI
import Testing

extension DesignSystemSnapshotTests {
    /// `KXBanner` in every style: the catalog's default messages, the default retry action, a
    /// custom message with a close button, and a custom action.
    @MainActor
    @Suite("KXBanner")
    struct KXBannerSnapshotTests {
        @Test("Styles, actions and close button", arguments: SnapshotVariant.matrix)
        func variants(_ variant: SnapshotVariant) {
            let copy = SnapshotCopy.forLanguage(variant.language)
            assertComponentSnapshot(variant: variant) {
                VStack(spacing: KXSpacing.m) {
                    KXBanner(.offline)
                    KXBanner(.error, action: {})
                    KXBanner(.info, message: copy.deliveryInfo, onDismiss: {})
                    KXBanner(.success, message: copy.addedToCart, actionTitle: copy.showAll, action: {}, onDismiss: {})
                }
                .padding(.bottom, KXSpacing.m)
            }
        }
    }
}
