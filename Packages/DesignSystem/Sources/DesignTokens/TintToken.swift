import Foundation

/// The color of a dark panel derived from the colors of a product photo, the way fashion retail
/// apps tint a campaign card with the color of its picture.
///
/// The panel keeps the photo's dominant hue but is always dark enough for the dark-mode text
/// tokens: `textPrimary` and `textSecondary` (dark values) on the panel, and on its deepened
/// lower end, meet WCAG AA for text (4.5:1). A photo without a clear color (a white packshot,
/// greys) gives `nil`; the caller then uses the neutral dark panel.
public enum TintToken {
    /// The share of colored samples a photo needs before it tints a panel.
    public static let minimumColoredShare = 0.04
    /// The brightness a panel starts from before it is darkened for contrast.
    public static let startBrightness = 0.38
    /// The saturation range of a panel.
    public static let saturationRange = 0.3...0.6
    /// How much darker the lower end of a panel gradient is (brightness factor).
    public static let deepeningFactor = 0.7
    /// The contrast both dark-mode text tokens need on a panel.
    public static let minimumContrast = 4.5

    /// The panel color for the colors of a photo, or `nil` when the photo has no clear color.
    ///
    /// - Parameter samples: Colors sampled from the photo, for example the pixels of a small
    ///   thumbnail. Transparent, very light, very dark and grey samples are ignored.
    public static func panel(fromSamples samples: [RGBAColor]) -> RGBAColor? {
        guard !samples.isEmpty else { return nil }
        let colored = samples.compactMap(HSB.init(color:)).filter(\.isColored)
        guard Double(colored.count) / Double(samples.count) >= minimumColoredShare else { return nil }
        // The mean hue as an angle, weighted by saturation, so a few strong pixels win over many
        // pale ones and hues around red (0 and 1) average correctly.
        var sumX = 0.0
        var sumY = 0.0
        var sumSaturation = 0.0
        for sample in colored {
            let angle = sample.hue * 2 * .pi
            sumX += cos(angle) * sample.saturation
            sumY += sin(angle) * sample.saturation
            sumSaturation += sample.saturation
        }
        var hue = atan2(sumY, sumX) / (2 * .pi)
        if hue < 0 {
            hue += 1
        }
        return panel(hue: hue, saturation: sumSaturation / Double(colored.count))
    }

    /// The panel color for a hue (0 to 1) and saturation: the saturation clamped to
    /// ``saturationRange``, darkened from ``startBrightness`` until both dark-mode text tokens
    /// meet ``minimumContrast``.
    public static func panel(hue: Double, saturation: Double) -> RGBAColor {
        let clamped = min(max(saturation, saturationRange.lowerBound), saturationRange.upperBound)
        var brightness = startBrightness
        var color = HSB(hue: hue, saturation: clamped, brightness: brightness).color
        while !isReadable(color), brightness > 0.05 {
            brightness -= 0.02
            color = HSB(hue: hue, saturation: clamped, brightness: brightness).color
        }
        return color
    }

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

// MARK: - HSB

/// Hue, saturation and brightness of an opaque color, each from 0 to 1.
private struct HSB {
    let hue: Double
    let saturation: Double
    let brightness: Double

    init(hue: Double, saturation: Double, brightness: Double) {
        self.hue = hue
        self.saturation = saturation
        self.brightness = brightness
    }

    /// The HSB value of a color with enough opacity to count, else `nil`.
    init?(color: RGBAColor) {
        guard color.alpha >= 0.5 else { return nil }
        let maximum = max(color.red, color.green, color.blue)
        let minimum = min(color.red, color.green, color.blue)
        let delta = maximum - minimum
        brightness = maximum
        saturation = maximum > 0 ? delta / maximum : 0
        guard delta > 0 else {
            hue = 0
            return
        }
        let sector: Double = if maximum == color.red {
            (color.green - color.blue) / delta
        } else if maximum == color.green {
            (color.blue - color.red) / delta + 2
        } else {
            (color.red - color.green) / delta + 4
        }
        var normalized = sector / 6
        if normalized < 0 {
            normalized += 1
        }
        hue = normalized
    }

    /// Whether the sample carries a color: saturated, neither near white nor near black.
    var isColored: Bool {
        saturation >= 0.25 && brightness >= 0.18 && brightness <= 0.98
    }

    /// The opaque sRGB color.
    var color: RGBAColor {
        let scaled = (hue - floor(hue)) * 6
        let sector = Int(scaled) % 6
        let fraction = scaled - floor(scaled)
        let low = brightness * (1 - saturation)
        let falling = brightness * (1 - saturation * fraction)
        let rising = brightness * (1 - saturation * (1 - fraction))
        let (red, green, blue): (Double, Double, Double) = switch sector {
        case 0: (brightness, rising, low)
        case 1: (falling, brightness, low)
        case 2: (low, brightness, rising)
        case 3: (low, falling, brightness)
        case 4: (rising, low, brightness)
        default: (brightness, low, falling)
        }
        return RGBAColor(red: red, green: green, blue: blue)
    }
}
