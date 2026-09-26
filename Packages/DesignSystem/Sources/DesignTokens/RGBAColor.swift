import Foundation

/// A platform-independent sRGB color value with helpers for WCAG 2.x contrast math.
///
/// Components are stored in the 0...1 range. The type deliberately has no UIKit or
/// SwiftUI dependency so that token values and accessibility checks can be unit tested
/// on every platform.
public struct RGBAColor: Hashable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = Self.clamp(red)
        self.green = Self.clamp(green)
        self.blue = Self.clamp(blue)
        self.alpha = Self.clamp(alpha)
    }

    /// Creates a color from a 24-bit `0xRRGGBB` literal.
    public init(hex: UInt32, alpha: Double = 1) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            alpha: alpha
        )
    }

    /// Parses `#RRGGBB`, `RRGGBB`, `#RRGGBBAA` or `RRGGBBAA`. Returns `nil` for anything else.
    public init?(hexString: String) {
        var value = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6 || value.count == 8,
              value.allSatisfy(\.isHexDigit),
              let raw = UInt64(value, radix: 16)
        else { return nil }
        if value.count == 6 {
            self.init(hex: UInt32(raw))
        } else {
            self.init(hex: UInt32(raw >> 8), alpha: Double(raw & 0xFF) / 255)
        }
    }

    /// Uppercase `#RRGGBB` representation (alpha is ignored).
    public var hexString: String {
        let red = Int((red * 255).rounded())
        let green = Int((green * 255).rounded())
        let blue = Int((blue * 255).rounded())
        return String(format: "#%02X%02X%02X", red, green, blue)
    }

    /// WCAG 2.x relative luminance of the opaque color.
    public var relativeLuminance: Double {
        0.2126 * Self.linearize(red) + 0.7152 * Self.linearize(green) + 0.0722 * Self.linearize(blue)
    }

    /// Returns this color alpha-composited over an opaque `background`.
    public func composited(over background: RGBAColor) -> RGBAColor {
        RGBAColor(
            red: red * alpha + background.red * (1 - alpha),
            green: green * alpha + background.green * (1 - alpha),
            blue: blue * alpha + background.blue * (1 - alpha),
            alpha: 1
        )
    }

    /// WCAG 2.x contrast ratio (1...21) between this color and `other`.
    /// Translucent foregrounds are composited over `other` first.
    public func contrastRatio(against other: RGBAColor) -> Double {
        let foreground = alpha < 1 ? composited(over: other) : self
        let lighter = max(foreground.relativeLuminance, other.relativeLuminance)
        let darker = min(foreground.relativeLuminance, other.relativeLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private static func linearize(_ component: Double) -> Double {
        component <= 0.040_45 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}
