@testable import DesignTokens
import Foundation
import Testing

@Suite("LoyaltyPalette")
struct LoyaltyPaletteTests {
    @Test("Text and muted text are readable on both ends of every level")
    func readable() {
        for tier in LoyaltyTierStyle.allCases {
            #expect(LoyaltyPalette.colors(for: tier).isReadable, "\(tier)")
        }
    }

    @Test("The levels look different and get darker toward the bottom")
    func distinct() {
        let colors = LoyaltyTierStyle.allCases.map { LoyaltyPalette.colors(for: $0) }
        #expect(Set(colors.map(\.top)).count == colors.count)
        for color in colors {
            #expect(color.bottom.relativeLuminance < color.top.relativeLuminance)
        }
    }

    @Test("The brand level is the store color")
    func starterIsStoreColor() {
        #expect(LoyaltyPalette.colors(for: .starter).top == TintToken.store)
    }

    @Test("The level IDs match the backend's")
    func rawValues() {
        #expect(LoyaltyTierStyle.allCases.map(\.rawValue) == ["starter", "silber", "gold", "platin", "diamant", "elite"])
    }

    @Test("The ring track and tiles are the text color at a low opacity")
    func derived() {
        let colors = LoyaltyPalette.colors(for: .gold)
        #expect(colors.ringTrack.alpha == LoyaltyPalette.trackOpacity)
        #expect(colors.tile.alpha == LoyaltyPalette.tileOpacity)
        #expect(colors.ring == colors.text)
    }
}
