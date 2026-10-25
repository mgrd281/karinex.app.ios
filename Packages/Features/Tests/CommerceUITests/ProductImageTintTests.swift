@testable import CommerceUI
import DesignTokens
import Foundation
import Testing
import UIKit

@Suite("Product image tint")
struct ProductImageTintTests {
    @Test("A photo is sampled pixel by pixel in its own colors")
    func solidSamples() {
        let samples = ProductImageTint.samples(of: Self.photo(red: 0.1, green: 0.4, blue: 0.8), side: 8)

        #expect(samples.count == 64)
        for sample in samples {
            #expect(abs(sample.red - 0.1) < 0.02)
            #expect(abs(sample.green - 0.4) < 0.02)
            #expect(abs(sample.blue - 0.8) < 0.02)
            #expect(abs(sample.alpha - 1) < 0.01)
        }
    }

    @Test("A blue packshot gives a readable blue panel, a white one the neutral panel")
    func panels() throws {
        let blue = ProductImageTint.samples(of: Self.photo(red: 0.1, green: 0.35, blue: 0.75), side: 8)
        let panel = try #require(TintToken.panel(fromSamples: blue))
        #expect(panel.blue > panel.red)
        #expect(TintToken.isReadable(panel))

        let white = ProductImageTint.samples(of: Self.photo(red: 1, green: 1, blue: 1), side: 8)
        #expect(TintToken.panel(fromSamples: white) == nil)
    }

    @Test("Without a photo nothing is loaded and the panel stays neutral")
    func missingPhoto() async {
        #expect(await ProductImageTint().panelColor(for: nil) == nil)
    }

    /// A 16 by 16 point photo of one sRGB color at scale 1.
    private static func photo(red: Double, green: Double, blue: Double) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.preferredRange = .standard
        let size = CGSize(width: 16, height: 16)
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor(red: red, green: green, blue: blue, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
}
