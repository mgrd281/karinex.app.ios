/// The raw KARINEX "Clean" brand palette: black, white and neutral greys, with one red for
/// sale prices and urgency.
///
/// The owner chose this monochrome direction on 2026-10-25 (it replaces the earlier green,
/// cream and gold "Editorial Luxe" palette). The product photography carries the color; the
/// interface stays neutral.
///
/// Components never use these values directly. They use the semantic `ColorToken`s, which
/// map onto this palette and add dark-mode and accessibility-adjusted variants.
public enum BrandPalette {
    /// `kx.ink`, primary text and filled buttons.
    public static let ink = RGBAColor(hex: 0x111111)
    /// `kx.inkPressed`, pressed filled buttons.
    public static let inkPressed = RGBAColor(hex: 0x3A3A3A)
    /// `kx.graphite`, secondary text.
    public static let graphite = RGBAColor(hex: 0x4D4D4D)
    /// `kx.slate`, tertiary text such as struck-through prices.
    public static let slate = RGBAColor(hex: 0x6B6B6B)
    /// `kx.steel`, secondary icons. 3.2:1 on `fog`, so it is used for icons only, never for text.
    public static let steel = RGBAColor(hex: 0x8A8A8A)
    /// `kx.silver`, dividers and inactive page dots.
    public static let silver = RGBAColor(hex: 0xD9D9D9)
    /// `kx.mist`, hairlines and the skeleton.
    public static let mist = RGBAColor(hex: 0xE8E8E8)
    /// `kx.cloud`, the light grey behind product photos.
    public static let cloud = RGBAColor(hex: 0xF3F3F3)
    /// `kx.fog`, panels and cards on the white page.
    public static let fog = RGBAColor(hex: 0xF5F5F5)
    /// `kx.white`, the page background.
    public static let white = RGBAColor(hex: 0xFFFFFF)
    /// `kx.sale`, sale prices, savings badges and running deals. Use sparingly.
    public static let sale = RGBAColor(hex: 0xC20E2B)

    /// Dark-mode page background.
    public static let darkBackground = RGBAColor(hex: 0x000000)
    /// Dark-mode panels and cards.
    public static let darkPanel = RGBAColor(hex: 0x1C1C1C)
    /// Dark-mode elevated panels (bars, nested cards).
    public static let darkElevated = RGBAColor(hex: 0x2C2C2C)
    /// Dark-mode dividers.
    public static let darkDivider = RGBAColor(hex: 0x3A3A3A)
    /// Dark-mode primary text.
    public static let darkText = RGBAColor(hex: 0xF5F5F5)
}
