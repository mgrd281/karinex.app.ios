import DesignTokens
import SwiftUI

extension View {
    /// Applies a KARINEX text style: font, Dynamic Type scaling, tracking, digit style and
    /// case. Prefer this over `.font(_:)` everywhere in the app.
    ///
    /// ```swift
    /// Text("Office 2024").kxFont(.title1)
    /// ```
    public func kxFont(_ style: TypographyToken) -> some View {
        modifier(KXFontModifier(style: style))
    }
}

/// Scales a token's base size with Dynamic Type relative to its system text style.
struct KXFontModifier: ViewModifier {
    let style: TypographyToken
    @ScaledMetric private var size: Double
    @ScaledMetric private var tracking: Double

    init(style: TypographyToken) {
        self.style = style
        _size = ScaledMetric(wrappedValue: style.baseSize, relativeTo: style.relativeStyle.swiftUI)
        _tracking = ScaledMetric(wrappedValue: style.tracking, relativeTo: style.relativeStyle.swiftUI)
    }

    func body(content: Content) -> some View {
        content
            .font(KXFont.font(style, size: size))
            .tracking(tracking)
            .textCase(style.isUppercased ? .uppercase : nil)
    }
}

/// Direct font access for places where a `View` modifier cannot be used (for example
/// `Text` concatenation or `AttributedString` runs). These fonts do not rescale on their
/// own, so pass a size from `@ScaledMetric` when Dynamic Type matters.
public enum KXFont {
    /// Returns the font for `style` at `size` points (defaults to the unscaled base size).
    public static func font(_ style: TypographyToken, size: Double? = nil) -> Font {
        let font = Font.system(
            size: size ?? style.baseSize,
            weight: style.weight.swiftUI,
            design: style.design.swiftUI
        )
        return style.usesMonospacedDigits ? font.monospacedDigit() : font
    }
}

extension TypographyToken.Design {
    var swiftUI: Font.Design {
        switch self {
        case .serif: .serif
        case .sans: .default
        case .monospaced: .monospaced
        }
    }
}

extension TypographyToken.Weight {
    var swiftUI: Font.Weight {
        switch self {
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        }
    }
}

extension TypographyToken.RelativeStyle {
    var swiftUI: Font.TextStyle {
        switch self {
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
