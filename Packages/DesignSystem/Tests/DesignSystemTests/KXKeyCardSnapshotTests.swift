import DesignSystem
import SwiftUI
import Testing

extension DesignSystemSnapshotTests {
    /// `KXKeyCard` revealed with the guide and support actions, and masked without them. The key
    /// is an obviously fake placeholder.
    @MainActor
    @Suite("KXKeyCard")
    struct KXKeyCardSnapshotTests {
        @Test("Revealed with actions", arguments: SnapshotVariant.matrix)
        func revealed(_ variant: SnapshotVariant) {
            let copy = SnapshotCopy.forLanguage(variant.language)
            assertComponentSnapshot(variant: variant) {
                KXKeyCard(
                    productName: SnapshotStoreData.windowsProTitle,
                    licenseKey: SnapshotStoreData.placeholderLicenseKey,
                    isRevealed: .constant(true),
                    subtitle: copy.licenseValue,
                    onShowGuide: {},
                    onContactSupport: {}
                )
            }
        }

        @Test("Masked without actions", arguments: SnapshotVariant.matrix)
        func masked(_ variant: SnapshotVariant) {
            assertComponentSnapshot(variant: variant) {
                KXKeyCard(
                    productName: SnapshotStoreData.officeProPlusTitle,
                    licenseKey: SnapshotStoreData.placeholderLicenseKey,
                    isRevealed: .constant(false)
                )
            }
        }
    }
}
