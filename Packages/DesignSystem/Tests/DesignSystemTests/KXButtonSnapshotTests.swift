import DesignSystem
import SwiftUI
import Testing

extension DesignSystemSnapshotTests {
    /// Every `KXButton` style in both sizes, plus the loading, disabled and full-width states and
    /// the `KXButtonStyle` shorthand on a plain `Button`.
    @MainActor
    @Suite("KXButton")
    struct KXButtonSnapshotTests {
        @Test("Styles, sizes and states", arguments: SnapshotVariant.matrix)
        func variants(_ variant: SnapshotVariant) {
            let copy = SnapshotCopy.forLanguage(variant.language)
            assertComponentSnapshot(variant: variant) {
                VStack(alignment: .leading, spacing: KXSpacing.m) {
                    KXButton(copy.browse, systemImage: "square.grid.2x2", isFullWidth: true) {}
                    KXButton(copy.addToCart, isFullWidth: true, isLoading: true) {}
                    KXButton(copy.browse, isFullWidth: true) {}
                        .disabled(true)
                    HStack(spacing: KXSpacing.s) {
                        KXButton(copy.guide, style: .secondary) {}
                        KXButton(copy.guide, style: .secondary, size: .compact) {}
                    }
                    KXButton(copy.showAll, style: .tertiary, size: .compact) {}
                    Button(copy.addToCart) {}
                        .buttonStyle(.kx(.secondary, size: .compact, isFullWidth: true))
                }
            }
        }
    }
}
