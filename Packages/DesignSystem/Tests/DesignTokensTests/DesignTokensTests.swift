@testable import DesignTokens
import Testing

@Suite("RGBAColor")
struct RGBAColorTests {
    @Test("Parses and prints hex strings")
    func hexRoundTrip() throws {
        let color = try #require(RGBAColor(hexString: "#1D4739"))
        #expect(color.hexString == "#1D4739")
        #expect(RGBAColor(hexString: "c9b486")?.hexString == "#C9B486")
        #expect(RGBAColor(hexString: "#00000080")?.alpha == 128.0 / 255.0)
    }

    @Test("Rejects malformed hex strings", arguments: ["", "#12345", "#GGGGGG", "1234567", "#1D4739FF00"])
    func rejectsMalformed(input: String) {
        #expect(RGBAColor(hexString: input) == nil)
    }

    @Test("Matches the WCAG reference ratios")
    func referenceRatios() {
        let black = RGBAColor(hex: 0x000000)
        let white = RGBAColor(hex: 0xFFFFFF)
        #expect(abs(black.contrastRatio(against: white) - 21) < 0.001)
        #expect(abs(white.contrastRatio(against: white) - 1) < 0.001)
        // Symmetric.
        let forest = BrandPalette.forest
        let cream = BrandPalette.cream
        #expect(abs(forest.contrastRatio(against: cream) - cream.contrastRatio(against: forest)) < 0.0001)
    }

    @Test("Composites translucent colors before measuring")
    func compositing() {
        let halfBlack = RGBAColor(hex: 0x000000, alpha: 0.5)
        let composited = halfBlack.composited(over: RGBAColor(hex: 0xFFFFFF))
        #expect(composited.hexString == "#808080")
        #expect(composited.alpha == 1)
    }
}

@Suite("Color tokens")
struct ColorTokenTests {
    @Test("Brand palette matches the brand spec")
    func brandPalette() {
        #expect(BrandPalette.forest.hexString == "#1D4739")
        #expect(BrandPalette.forestDeep.hexString == "#16382D")
        #expect(BrandPalette.forestSoft.hexString == "#2A5F4C")
        #expect(BrandPalette.cream.hexString == "#F5F2EC")
        #expect(BrandPalette.creamPanel.hexString == "#F7F4ED")
        #expect(BrandPalette.hairlineCream.hexString == "#E6E0D3")
        #expect(BrandPalette.ink.hexString == "#17161A")
        #expect(BrandPalette.graphite.hexString == "#424245")
        #expect(BrandPalette.secondary.hexString == "#86868B")
        #expect(BrandPalette.hairline.hexString == "#D2D2D7")
        #expect(BrandPalette.gold.hexString == "#C9B486")
        #expect(BrandPalette.goldDeep.hexString == "#B39B66")
        #expect(BrandPalette.terracotta.hexString == "#BC5127")
        #expect(BrandPalette.darkBackground.hexString == "#0F1C17")
        #expect(BrandPalette.darkHairline.hexString == "#2E4A3F")
    }

    @Test("Dark mode follows the brand spec")
    func darkModeMapping() {
        #expect(ColorToken.background.dark == BrandPalette.darkBackground)
        #expect(ColorToken.surface.dark == BrandPalette.forestDeep)
        #expect(ColorToken.textPrimary.dark == BrandPalette.cream)
        #expect(ColorToken.accent.dark == BrandPalette.gold)
        #expect(ColorToken.hairline.dark == BrandPalette.darkHairline)
    }

    @Test(
        "Every allowed pairing meets WCAG AA",
        arguments: ContrastRequirement.all, Appearance.allCases
    )
    func contrast(requirement: ContrastRequirement, appearance: Appearance) {
        let ratio = requirement.ratio(in: appearance)
        #expect(
            ratio >= requirement.minimumRatio,
            """
            \(requirement.foreground.rawValue) on \(requirement.background.rawValue) \
            (\(appearance.rawValue)) is \(ratio), needs \(requirement.minimumRatio)
            """
        )
    }

    @Test("Gold is never an allowed text color on light page surfaces")
    func goldIsDecorativeInLightMode() {
        let lightPageSurfaces: [ColorToken] = [.background, .surface, .surfaceElevated]
        for surface in lightPageSurfaces {
            #expect(ColorToken.accent.light.contrastRatio(against: surface.light) < 4.5)
            #expect(!ContrastRequirement.all.contains {
                $0.foreground == .accent && $0.background == surface && $0.kind == .text
            })
        }
    }
}

@Suite("Layout and type tokens")
struct LayoutTokenTests {
    @Test("Spacing sits on the 4 pt half-grid and grows monotonically")
    func spacingScale() {
        let scale = [
            SpacingToken.xxs, SpacingToken.xs, SpacingToken.s, SpacingToken.m,
            SpacingToken.l, SpacingToken.xl, SpacingToken.xxl, SpacingToken.xxxl,
        ]
        #expect(scale == scale.sorted())
        #expect(scale.allSatisfy { $0.truncatingRemainder(dividingBy: 4) == 0 })
        #expect(SpacingToken.gutter == 16)
        #expect(SpacingToken.minimumTapTarget >= 44)
    }

    @Test("Card radius follows the spec")
    func radii() {
        #expect(RadiusToken.card == 18)
    }

    @Test("Springs stay within the 0.25 to 0.35 s brand range")
    func motionRange() {
        for response in [MotionToken.springResponse, MotionToken.snappyResponse, MotionToken.gentleResponse] {
            #expect((0.25...0.35).contains(response))
        }
    }

    @Test("Headlines are serif, keys are monospaced, UI text is sans serif")
    func typographyDesigns() {
        #expect(TypographyToken.display.design == .serif)
        #expect(TypographyToken.title1.design == .serif)
        #expect(TypographyToken.licenseKey.design == .monospaced)
        #expect(TypographyToken.body.design == .sans)
        #expect(TypographyToken.allCases.allSatisfy { $0.baseSize >= 11 })
    }
}
