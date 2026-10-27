import DesignSystem
import SwiftUI
import Testing

extension DesignSystemSnapshotTests {
    /// `KXList`: values with every accessory and a footer, and a row with a switch.
    @MainActor
    @Suite("KXList")
    struct KXListSnapshotTests {
        @Test("Values, accessories and a switch", arguments: SnapshotVariant.matrix)
        func variants(_ variant: SnapshotVariant) {
            let copy = SnapshotCopy.forLanguage(variant.language)
            assertComponentSnapshot(variant: variant) {
                VStack(spacing: KXSpacing.l) {
                    KXListGroup(Text(verbatim: copy.productLabel)) {
                        KXListRow(
                            systemImage: "shippingbox",
                            title: Text(verbatim: copy.productLabel),
                            value: "Windows 11 Pro",
                            accessory: .menu
                        )
                        KXListDivider()
                        KXListRow(
                            systemImage: "key",
                            title: Text(verbatim: copy.licenseLabel),
                            value: copy.licenseValue,
                            accessory: .chevron
                        )
                        KXListDivider()
                        KXListRow(systemImage: "arrow.down.circle", title: Text(verbatim: copy.deliveryLabel), value: copy.deliveryValue)
                        KXListDivider()
                        KXListRow(systemImage: "checkmark.seal", title: Text(verbatim: copy.licenseKeyLabel), accessory: .checkmark)
                    } footer: {
                        Text(verbatim: copy.deliveryFact)
                    }
                    KXListGroup {
                        KXListToggleRow(
                            systemImage: "faceid",
                            title: Text(verbatim: copy.licenseKeyLabel),
                            detail: Text(verbatim: copy.deliveryFact),
                            isOn: .constant(true)
                        )
                    }
                }
            }
        }
    }
}
