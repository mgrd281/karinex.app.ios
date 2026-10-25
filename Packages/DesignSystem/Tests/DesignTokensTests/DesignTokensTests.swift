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
        let ink = BrandPalette.ink
        let fog = BrandPalette.fog
        #expect(abs(ink.contrastRatio(against: fog) - fog.contrastRatio(against: ink)) < 0.0001)
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
        #expect(BrandPalette.ink.hexString == "#111111")
        #expect(BrandPalette.inkPressed.hexString == "#3A3A3A")
        #expect(BrandPalette.graphite.hexString == "#4D4D4D")
        #expect(BrandPalette.slate.hexString == "#6B6B6B")
        #expect(BrandPalette.steel.hexString == "#8A8A8A")
        #expect(BrandPalette.silver.hexString == "#D9D9D9")
        #expect(BrandPalette.mist.hexString == "#E8E8E8")
        #expect(BrandPalette.cloud.hexString == "#F3F3F3")
        #expect(BrandPalette.fog.hexString == "#F5F5F5")
        #expect(BrandPalette.white.hexString == "#FFFFFF")
        #expect(BrandPalette.sale.hexString == "#C20E2B")
        #expect(BrandPalette.darkBackground.hexString == "#000000")
        #expect(BrandPalette.darkPanel.hexString == "#1C1C1C")
        #expect(BrandPalette.darkElevated.hexString == "#2C2C2C")
        #expect(BrandPalette.darkDivider.hexString == "#3A3A3A")
        #expect(BrandPalette.darkText.hexString == "#F5F5F5")
    }

    @Test("Dark mode follows the brand spec")
    func darkModeMapping() {
        #expect(ColorToken.background.dark == BrandPalette.darkBackground)
        #expect(ColorToken.surface.dark == BrandPalette.darkPanel)
        #expect(ColorToken.textPrimary.dark == BrandPalette.darkText)
        #expect(ColorToken.brand.dark == BrandPalette.white)
        #expect(ColorToken.textOnBrand.dark == BrandPalette.ink)
        #expect(ColorToken.divider.dark == BrandPalette.darkDivider)
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

    @Test("The interface is monochrome: only status colors and the sale red have a hue")
    func monochromeInterface() {
        let colored: Set<ColorToken> = [.urgency, .urgencyText, .success, .warning, .error, .info]
        for token in ColorToken.allCases where !colored.contains(token) {
            for appearance in Appearance.allCases {
                let value = token.value(for: appearance)
                #expect(
                    value.red == value.green && value.green == value.blue,
                    "\(token.rawValue) (\(appearance.rawValue)) is \(value.hexString), not a neutral grey"
                )
            }
        }
    }

    @Test("Product photos sit on a light grey in both appearances")
    func imageBackgroundStaysLight() {
        for appearance in Appearance.allCases {
            let background = ColorToken.imageBackground.value(for: appearance)
            #expect(background.contrastRatio(against: BrandPalette.white) < 1.3)
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

    @Test("Radii follow the spec: rounded panels, square product photos")
    func radii() {
        #expect(RadiusToken.card == 12)
        #expect(RadiusToken.image == 0)
        let scale = [RadiusToken.image, RadiusToken.small, RadiusToken.medium, RadiusToken.large]
        #expect(scale == scale.sorted())
    }

    @Test("Springs stay within the 0.25 to 0.35 s brand range")
    func motionRange() {
        for response in [MotionToken.springResponse, MotionToken.snappyResponse, MotionToken.gentleResponse] {
            #expect((0.25...0.35).contains(response))
        }
    }

    @Test("Every style is sans serif except the monospaced license keys")
    func typographyDesigns() {
        for style in TypographyToken.allCases {
            #expect(style.design == (style == .licenseKey ? .monospaced : .sans))
        }
        #expect(TypographyToken.display.weight == .bold)
        #expect(TypographyToken.allCases.allSatisfy { $0.baseSize >= 11 })
        #expect(TypographyToken.display.baseSize > TypographyToken.title1.baseSize)
        #expect(TypographyToken.title1.baseSize > TypographyToken.title2.baseSize)
    }
}
