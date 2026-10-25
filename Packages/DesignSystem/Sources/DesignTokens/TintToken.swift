import Foundation

/// The color of the large dark panels of the Start tab (the story carousel, the category
/// showcase, the sale panel): the KARINEX store color `#0E4343`, with a deepened lower end for
/// the gradient.
///
/// The dark-mode text tokens `textPrimary` and `textSecondary` meet WCAG AA for text (4.5:1) on
/// both ends, which `TintTokenTests` checks.
public enum TintToken {
    /// The store color of the web shop.
    public static let store = RGBAColor(hex: 0x0E4343)
    /// How much darker the lower end of a panel gradient is (brightness factor).
    public static let deepeningFactor = 0.7
    /// The contrast both dark-mode text tokens need on a panel.
    public static let minimumContrast = 4.5

    /// The lower end of a panel gradient: the same hue, darker by ``deepeningFactor``.
    public static func deepened(_ color: RGBAColor) -> RGBAColor {
        RGBAColor(
            red: color.red * deepeningFactor,
            green: color.green * deepeningFactor,
            blue: color.blue * deepeningFactor,
            alpha: color.alpha
        )
    }

    /// Whether both dark-mode text tokens meet ``minimumContrast`` on `color`.
    public static func isReadable(_ color: RGBAColor) -> Bool {
        ColorToken.textPrimary.dark.contrastRatio(against: color) >= minimumContrast
            && ColorToken.textSecondary.dark.contrastRatio(against: color) >= minimumContrast
    }
}
