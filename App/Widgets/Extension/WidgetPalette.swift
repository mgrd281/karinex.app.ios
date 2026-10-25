import DesignTokens
import SwiftUI
import UIKit

// MARK: - WidgetPalette

/// The design-system colors for the widget extension. The extension links only
/// `DesignTokens` (pure Swift, extension-safe), so the semantic tokens are turned into
/// dynamic colors here, with the same light and dark values as `KXColor` in the app.
enum WidgetPalette {
    /// The color of `token`, following the system appearance.
    static func color(_ token: ColorToken) -> Color {
        Color(uiColor: UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? token.dark : token.light
            return UIColor(red: value.red, green: value.green, blue: value.blue, alpha: value.alpha)
        })
    }
}

// MARK: - Fonts

extension WidgetPalette {
    /// The font of `token`: the same design, weight and Dynamic Type style as `.kxFont(_:)`.
    static func font(_ token: TypographyToken) -> Font {
        Font.system(textStyle(token.relativeStyle), design: design(token.design), weight: weight(token.weight))
    }

    private static func design(_ design: TypographyToken.Design) -> Font.Design {
        switch design {
        case .sans: .default
        case .monospaced: .monospaced
        }
    }

    private static func weight(_ weight: TypographyToken.Weight) -> Font.Weight {
        switch weight {
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        }
    }

    private static func textStyle(_ style: TypographyToken.RelativeStyle) -> Font.TextStyle {
        switch style {
        case .largeTitle: .largeTitle
        case .title: .title
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .body: .body
        case .callout: .callout
        case .subheadline: .subheadline
        case .footnote: .footnote
        case .caption: .caption
        case .caption2: .caption2
        }
    }
}
