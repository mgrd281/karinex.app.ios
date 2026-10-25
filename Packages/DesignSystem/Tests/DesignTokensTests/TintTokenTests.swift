@testable import DesignTokens
import Foundation
import Testing

@Suite("TintToken")
struct TintTokenTests {
    @Test("Every hue and saturation gives a panel on which the dark-mode text is readable")
    func readableEverywhere() {
        for hueStep in 0..<40 {
            for saturation in [0.0, 0.2, 0.45, 0.8, 1.0] {
                let panel = TintToken.panel(hue: Double(hueStep) / 40, saturation: saturation)
                #expect(TintToken.isReadable(panel), "hue \(hueStep) / 40, saturation \(saturation)")
                #expect(TintToken.isReadable(TintToken.deepened(panel)))
                #expect(panel.alpha == 1)
            }
        }
    }

    @Test("White packshots, greys and transparent pixels give no tint")
    func neutralPhotos() {
        let white = Array(repeating: RGBAColor(hex: 0xFFFFFF), count: 90)
        let greys = (0..<90).map { RGBAColor(red: Double($0) / 90, green: Double($0) / 90, blue: Double($0) / 90) }
        let clear = Array(repeating: RGBAColor(red: 0.9, green: 0.1, blue: 0.1, alpha: 0), count: 90)
        #expect(TintToken.panel(fromSamples: white) == nil)
        #expect(TintToken.panel(fromSamples: greys) == nil)
        #expect(TintToken.panel(fromSamples: clear) == nil)
        #expect(TintToken.panel(fromSamples: []) == nil)
    }

    @Test("A few colored pixels below the minimum share give no tint")
    func tooLittleColor() {
        let samples = Array(repeating: RGBAColor(hex: 0xFFFFFF), count: 99) + [RGBAColor(hex: 0x1532CB)]
        #expect(TintToken.panel(fromSamples: samples) == nil)
    }

    @Test("A blue box on white tints the panel blue")
    func bluePackshot() throws {
        let samples = Array(repeating: RGBAColor(hex: 0xFFFFFF), count: 70)
            + Array(repeating: RGBAColor(hex: 0x1532CB), count: 30)
        let panel = try #require(TintToken.panel(fromSamples: samples))
        #expect(panel.blue > panel.red)
        #expect(panel.blue > panel.green)
        #expect(TintToken.isReadable(panel))
    }

    @Test("Hues on both sides of red average to red, not to cyan")
    func hueWrapsAroundRed() throws {
        let samples = Array(repeating: RGBAColor(red: 0.9, green: 0.1, blue: 0.2), count: 50)
            + Array(repeating: RGBAColor(red: 0.9, green: 0.2, blue: 0.1), count: 50)
        let panel = try #require(TintToken.panel(fromSamples: samples))
        #expect(panel.red > panel.green)
        #expect(panel.red > panel.blue)
    }

    @Test("A yellow photo, the hardest hue for light text, is darkened until readable")
    func yellowPhoto() throws {
        let samples = Array(repeating: RGBAColor(hex: 0xF5D300), count: 40)
        let panel = try #require(TintToken.panel(fromSamples: samples))
        #expect(TintToken.isReadable(panel))
        #expect(panel.red > panel.blue)
    }
}
