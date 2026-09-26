/// Semantic color tokens with light and dark values.
///
/// Every value is chosen so that the text/background pairs listed in
/// `ContrastRequirement.all` meet WCAG AA (4.5:1 for text, 3:1 for non-text UI) in both
/// appearances. `DesignTokensTests` enforces this, so changing a value that breaks
/// contrast fails the build.
public enum ColorToken: String, CaseIterable, Sendable {
    // Surfaces
    case background
    case surface
    case surfaceElevated
    case skeleton

    // Text
    case textPrimary
    case textSecondary
    case textTertiary

    // Brand and actions
    case brand
    case brandPressed
    case brandSoft
    case textOnBrand

    // Accent (champagne gold)
    case accent
    case accentDeep
    case accentText

    // Urgency (terracotta)
    case urgency
    case urgencyText
    case textOnUrgency

    // Lines and icons
    case hairline
    case divider
    case iconSecondary

    // Status
    case success
    case warning
    case error
    case info

    // License certificate card
    case keyCardBackground
    case keyCardText
    case keyCardMuted
    case keyCardAccent

    // Overlays
    case scrim

    /// Value used in the light appearance.
    public var light: RGBAColor {
        switch self {
        case .background: BrandPalette.cream
        case .surface: BrandPalette.creamPanel
        case .surfaceElevated: RGBAColor(hex: 0xFFFDF8)
        case .skeleton: RGBAColor(hex: 0xE9E4D8)
        case .textPrimary: BrandPalette.ink
        case .textSecondary: BrandPalette.graphite
        case .textTertiary: RGBAColor(hex: 0x6E6E73)
        case .brand: BrandPalette.forest
        case .brandPressed: BrandPalette.forestDeep
        case .brandSoft: BrandPalette.forestSoft
        case .textOnBrand: BrandPalette.cream
        case .accent: BrandPalette.gold
        case .accentDeep: BrandPalette.goldDeep
        case .accentText: RGBAColor(hex: 0x7A6534)
        case .urgency: BrandPalette.terracotta
        case .urgencyText: RGBAColor(hex: 0xA8461F)
        case .textOnUrgency: RGBAColor(hex: 0xFFFFFF)
        case .hairline: BrandPalette.hairlineCream
        case .divider: BrandPalette.hairline
        case .iconSecondary: BrandPalette.secondary
        case .success: RGBAColor(hex: 0x2E6B45)
        case .warning: RGBAColor(hex: 0x8A5A00)
        case .error: RGBAColor(hex: 0xB3261E)
        case .info: RGBAColor(hex: 0x1F5A8A)
        case .keyCardBackground: BrandPalette.ink
        case .keyCardText: BrandPalette.cream
        case .keyCardMuted: RGBAColor(hex: 0xA39E92)
        case .keyCardAccent: BrandPalette.terracotta
        case .scrim: RGBAColor(hex: 0x000000, alpha: 0.4)
        }
    }

    /// Value used in the dark appearance.
    public var dark: RGBAColor {
        switch self {
        case .background: BrandPalette.darkBackground
        case .surface: BrandPalette.forestDeep
        case .surfaceElevated: RGBAColor(hex: 0x1B4034)
        case .skeleton: RGBAColor(hex: 0x1F4538)
        case .textPrimary: BrandPalette.cream
        case .textSecondary: RGBAColor(hex: 0xC9C4B8)
        case .textTertiary: RGBAColor(hex: 0xADA89C)
        case .brand: BrandPalette.gold
        case .brandPressed: BrandPalette.goldDeep
        case .brandSoft: BrandPalette.forestSoft
        case .textOnBrand: BrandPalette.ink
        case .accent: BrandPalette.gold
        case .accentDeep: BrandPalette.goldDeep
        case .accentText: BrandPalette.gold
        case .urgency: BrandPalette.terracotta
        case .urgencyText: RGBAColor(hex: 0xE98F6B)
        case .textOnUrgency: RGBAColor(hex: 0xFFFFFF)
        case .hairline: BrandPalette.darkHairline
        case .divider: BrandPalette.darkHairline
        case .iconSecondary: RGBAColor(hex: 0xADA89C)
        case .success: RGBAColor(hex: 0x7CC596)
        case .warning: RGBAColor(hex: 0xE7B85C)
        case .error: RGBAColor(hex: 0xF2877E)
        case .info: RGBAColor(hex: 0x86B8E6)
        case .keyCardBackground: BrandPalette.ink
        case .keyCardText: BrandPalette.cream
        case .keyCardMuted: RGBAColor(hex: 0xA39E92)
        case .keyCardAccent: BrandPalette.terracotta
        case .scrim: RGBAColor(hex: 0x000000, alpha: 0.6)
        }
    }

    /// Returns the value for the given appearance.
    public func value(for appearance: Appearance) -> RGBAColor {
        switch appearance {
        case .light: light
        case .dark: dark
        }
    }
}

/// The two appearances every token defines.
public enum Appearance: String, CaseIterable, Sendable {
    case light
    case dark
}
