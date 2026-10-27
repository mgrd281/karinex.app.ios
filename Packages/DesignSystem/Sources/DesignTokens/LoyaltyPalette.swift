import Foundation

/// The membership levels as the design system knows them. The raw values match the backend's
/// level IDs (`BackendKit.LoyaltyTier`), so a feature maps one to the other by `rawValue`.
public enum LoyaltyTierStyle: String, CaseIterable, Sendable {
    case starter
    case silber
    case gold
    case platin
    case diamant
    case elite
}

/// The colors of the membership card: a calm gradient per level with light text, the same in
/// light and dark mode (like the store color panels of ``TintToken``).
///
/// Petrol is the brand level, silver is a graphite silver, gold a deep antique gold, platinum
/// a dark charcoal, diamond a deep ink blue and elite the store's darkest emerald. Every level
/// meets WCAG AA for text (4.5:1) on both ends of its gradient, which `LoyaltyPaletteTests` checks.
public struct LoyaltyPanelColors: Hashable, Sendable {
    /// The upper end of the gradient.
    public let top: RGBAColor
    /// The lower end of the gradient.
    public let bottom: RGBAColor
    /// The text color on the panel.
    public let text: RGBAColor
    /// The secondary text color: ``text`` at ``LoyaltyPalette/mutedOpacity``.
    public var mutedText: RGBAColor {
        RGBAColor(red: text.red, green: text.green, blue: text.blue, alpha: LoyaltyPalette.mutedOpacity)
    }

    /// The filled part of the progress ring.
    public var ring: RGBAColor {
        text
    }

    /// The empty part of the progress ring.
    public var ringTrack: RGBAColor {
        RGBAColor(red: text.red, green: text.green, blue: text.blue, alpha: LoyaltyPalette.trackOpacity)
    }

    /// The tint of the action tiles.
    public var tile: RGBAColor {
        RGBAColor(red: text.red, green: text.green, blue: text.blue, alpha: LoyaltyPalette.tileOpacity)
    }

    /// Whether ``text`` and the muted text meet 4.5:1 on both ends of the gradient.
    public var isReadable: Bool {
        [top, bottom].allSatisfy { background in
            text.contrastRatio(against: background) >= LoyaltyPalette.minimumContrast
                && mutedText.composited(over: background).contrastRatio(against: background) >= LoyaltyPalette.minimumContrast
        }
    }
}

/// The membership card palette.
public enum LoyaltyPalette {
    /// The contrast the text needs.
    public static let minimumContrast = 4.5
    /// The opacity of the secondary text.
    public static let mutedOpacity = 0.92
    /// The opacity of the empty ring.
    public static let trackOpacity = 0.28
    /// The opacity of the action tiles.
    public static let tileOpacity = 0.16

    /// The colors of a level.
    public static func colors(for tier: LoyaltyTierStyle) -> LoyaltyPanelColors {
        let white = RGBAColor(hex: 0xFFFFFF)
        switch tier {
        case .starter:
            return LoyaltyPanelColors(top: TintToken.store, bottom: TintToken.deepened(TintToken.store), text: white)
        case .silber:
            return LoyaltyPanelColors(top: RGBAColor(hex: 0x626C76), bottom: RGBAColor(hex: 0x474F58), text: white)
        case .gold:
            return LoyaltyPanelColors(top: RGBAColor(hex: 0x806440), bottom: RGBAColor(hex: 0x66502E), text: white)
        case .platin:
            return LoyaltyPanelColors(top: RGBAColor(hex: 0x2E343B), bottom: RGBAColor(hex: 0x1A1E23), text: white)
        case .diamant:
            return LoyaltyPanelColors(top: RGBAColor(hex: 0x23455E), bottom: RGBAColor(hex: 0x142C3E), text: white)
        case .elite:
            return LoyaltyPanelColors(top: RGBAColor(hex: 0x0D2E22), bottom: RGBAColor(hex: 0x061A13), text: white)
        }
    }
}
