import DesignSystem
import SwiftUI
import Testing

extension DesignSystemSnapshotTests {
    /// `KXWordmark` in every size and on the brand and key card panels. The wordmark is never
    /// translated; the Finnish variants only change the text size.
    @MainActor
    @Suite("KXWordmark")
    struct KXWordmarkSnapshotTests {
        @Test("Sizes and panels", arguments: SnapshotVariant.matrix)
        func variants(_ variant: SnapshotVariant) {
            assertComponentSnapshot(variant: variant) {
                VStack(spacing: KXSpacing.l) {
                    ForEach(KXWordmark.Size.allCases, id: \.self) { size in
                        KXWordmark(size: size)
                    }
                    KXWordmark(size: .regular, color: KXColor.textOnBrand)
                        .padding(KXSpacing.m)
                        .frame(maxWidth: .infinity)
                        .background(KXColor.brand, in: RoundedRectangle(cornerRadius: KXRadius.card, style: .continuous))
                    KXWordmark(size: .regular, color: KXColor.keyCardText)
                        .padding(KXSpacing.m)
                        .frame(maxWidth: .infinity)
                        .background(KXColor.keyCardBackground, in: RoundedRectangle(cornerRadius: KXRadius.card, style: .continuous))
                }
            }
        }
    }
}
