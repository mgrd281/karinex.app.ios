@testable import DesignTokens
import Foundation
import Testing

@Suite("TintToken")
struct TintTokenTests {
    @Test("The store color is #0E4343 and the light text is readable on both ends of the panel")
    func storePanel() {
        #expect(TintToken.store == RGBAColor(hex: 0x0E4343))
        #expect(TintToken.isReadable(TintToken.store))
        #expect(TintToken.isReadable(TintToken.deepened(TintToken.store)))
    }

    @Test("Large sale red titles stay legible on the store color (3:1 for large text)")
    func saleTitle() {
        #expect(ColorToken.urgencyText.dark.contrastRatio(against: TintToken.store) >= 3)
    }

    @Test("White text stays readable on the lifted store color of the chosen category tile")
    func liftedStoreColor() {
        let lifted = TintToken.lifted(TintToken.store)
        #expect(ColorToken.textPrimary.dark.contrastRatio(against: lifted) >= TintToken.minimumContrast)
        #expect(lifted.relativeLuminance > TintToken.store.relativeLuminance)
    }

    @Test("Lifting mixes in white and keeps the opacity")
    func lifting() {
        let lifted = TintToken.lifted(RGBAColor(red: 0, green: 0.5, blue: 1, alpha: 0.5))
        #expect(abs(lifted.red - TintToken.liftFactor) < 0.0001)
        #expect(abs(lifted.green - (0.5 + 0.5 * TintToken.liftFactor)) < 0.0001)
        #expect(lifted.blue == 1)
        #expect(lifted.alpha == 0.5)
    }

    @Test("Deepening keeps the hue and the opacity")
    func deepening() {
        let deep = TintToken.deepened(RGBAColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 0.5))
        #expect(abs(deep.red - 0.14) < 0.0001)
        #expect(abs(deep.blue - 0.42) < 0.0001)
        #expect(deep.alpha == 0.5)
    }
}
