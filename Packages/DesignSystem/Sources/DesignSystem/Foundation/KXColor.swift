import DesignTokens
import SwiftUI
import UIKit

/// SwiftUI colors for every semantic `ColorToken`. Each color resolves its light or dark
/// value from the current trait collection, so it adapts automatically to appearance
/// changes, sheets and previews.
///
/// Usage: `.foregroundStyle(KXColor.textPrimary)`, `.background(KXColor.background)`.
public enum KXColor {
    public static let background = color(.background)
    public static let surface = color(.surface)
    public static let surfaceElevated = color(.surfaceElevated)
    public static let skeleton = color(.skeleton)

    public static let textPrimary = color(.textPrimary)
    public static let textSecondary = color(.textSecondary)
    public static let textTertiary = color(.textTertiary)

    public static let brand = color(.brand)
    public static let brandPressed = color(.brandPressed)
    public static let brandSoft = color(.brandSoft)
    public static let textOnBrand = color(.textOnBrand)

    public static let accent = color(.accent)
    public static let accentDeep = color(.accentDeep)
    public static let accentText = color(.accentText)
    /// Ink text on gold (`accent`) fills such as badges and numerals, in both appearances.
    public static let textOnAccent = color(.textOnAccent)

    public static let urgency = color(.urgency)
    public static let urgencyText = color(.urgencyText)
    public static let textOnUrgency = color(.textOnUrgency)

    public static let hairline = color(.hairline)
    public static let divider = color(.divider)
    public static let iconSecondary = color(.iconSecondary)

    public static let success = color(.success)
    public static let warning = color(.warning)
    public static let error = color(.error)
    public static let info = color(.info)

    public static let keyCardBackground = color(.keyCardBackground)
    public static let keyCardText = color(.keyCardText)
    public static let keyCardMuted = color(.keyCardMuted)
    public static let keyCardAccent = color(.keyCardAccent)

    public static let scrim = color(.scrim)

    /// The dynamic SwiftUI color for a token.
    public static func color(_ token: ColorToken) -> Color {
        Color(uiColor: uiColor(token))
    }

    /// The dynamic UIKit color for a token (used for UIKit appearance APIs such as the
    /// Checkout Kit configuration).
    public static func uiColor(_ token: ColorToken) -> UIColor {
        UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? token.dark : token.light
            return UIColor(rgba: value)
        }
    }
}

extension UIColor {
    /// Creates a static sRGB `UIColor` from a token value.
    public convenience init(rgba value: RGBAColor) {
        self.init(
            red: CGFloat(value.red),
            green: CGFloat(value.green),
            blue: CGFloat(value.blue),
            alpha: CGFloat(value.alpha)
        )
    }
}
