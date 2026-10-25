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

    @Test("Deepening keeps the hue and the opacity")
    func deepening() {
        let deep = TintToken.deepened(RGBAColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 0.5))
        #expect(abs(deep.red - 0.14) < 0.0001)
        #expect(abs(deep.blue - 0.42) < 0.0001)
        #expect(deep.alpha == 0.5)
    }
}
