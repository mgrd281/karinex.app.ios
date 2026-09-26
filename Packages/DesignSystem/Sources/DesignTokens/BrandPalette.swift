/// The raw KARINEX "Editorial Luxe" brand palette, exactly as defined by the brand spec.
///
/// Components never use these values directly. They use the semantic `ColorToken`s, which
/// map onto this palette and add dark-mode and accessibility-adjusted variants.
public enum BrandPalette {
    /// `kx.forest`, primary brand green.
    public static let forest = RGBAColor(hex: 0x1D4739)
    /// `kx.forestDeep`, pressed states and dark-mode panels.
    public static let forestDeep = RGBAColor(hex: 0x16382D)
    /// `kx.forestSoft`, secondary green fills.
    public static let forestSoft = RGBAColor(hex: 0x2A5F4C)
    /// `kx.cream`, page background.
    public static let cream = RGBAColor(hex: 0xF5F2EC)
    /// `kx.creamPanel`, cards and panels.
    public static let creamPanel = RGBAColor(hex: 0xF7F4ED)
    /// `kx.hairlineCream`, hairlines on cream.
    public static let hairlineCream = RGBAColor(hex: 0xE6E0D3)
    /// `kx.ink`, primary text and the license certificate card.
    public static let ink = RGBAColor(hex: 0x17161A)
    /// `kx.graphite`, secondary text.
    public static let graphite = RGBAColor(hex: 0x424245)
    /// `kx.secondary`. Contrast on cream is 3.2:1, so it is used for icons only, never for text.
    public static let secondary = RGBAColor(hex: 0x86868B)
    /// `kx.hairline`, neutral dividers.
    public static let hairline = RGBAColor(hex: 0xD2D2D7)
    /// `kx.gold`, champagne accents. Decorative on light backgrounds (1.8:1 on cream).
    public static let gold = RGBAColor(hex: 0xC9B486)
    /// `kx.goldDeep`, pressed gold.
    public static let goldDeep = RGBAColor(hex: 0xB39B66)
    /// `kx.terracotta`, urgency (countdown, sale badge). Use sparingly.
    public static let terracotta = RGBAColor(hex: 0xBC5127)

    /// Dark-mode page background.
    public static let darkBackground = RGBAColor(hex: 0x0F1C17)
    /// Dark-mode hairline.
    public static let darkHairline = RGBAColor(hex: 0x2E4A3F)
}
