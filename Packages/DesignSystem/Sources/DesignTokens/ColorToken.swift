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
    /// The light grey behind product photos. It stays light in dark mode, because the store's
    /// photos are shot on white.
    case imageBackground
    /// The placeholder symbol on `imageBackground` when a photo is missing.
    case imageIcon

    // Text
    case textPrimary
    case textSecondary
    case textTertiary

    // Brand and actions
    case brand
    case brandPressed
    case brandSoft
    case textOnBrand

    // Accent (ink: eyebrows, selection rings, active page dots)
    case accent
    case accentDeep
    case accentText
    case textOnAccent

    // Sale and urgency (red: savings badges, sale prices, running deals)
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

    // Overlays
    case scrim

    /// Value used in the light appearance.
    public var light: RGBAColor {
        switch self {
        case .background: BrandPalette.white
        case .surface: BrandPalette.fog
        case .surfaceElevated: BrandPalette.white
        case .skeleton: BrandPalette.mist
        case .imageBackground: BrandPalette.cloud
        case .imageIcon: BrandPalette.steel
        case .textPrimary: BrandPalette.ink
        case .textSecondary: BrandPalette.graphite
        case .textTertiary: BrandPalette.slate
        case .brand: BrandPalette.ink
        case .brandPressed: BrandPalette.inkPressed
        case .brandSoft: RGBAColor(hex: 0x2B2B2B)
        case .textOnBrand: BrandPalette.white
        case .accent: BrandPalette.ink
        case .accentDeep: BrandPalette.inkPressed
        case .accentText: BrandPalette.ink
        case .textOnAccent: BrandPalette.white
        case .urgency: BrandPalette.sale
        case .urgencyText: BrandPalette.sale
        case .textOnUrgency: BrandPalette.white
        case .hairline: BrandPalette.mist
        case .divider: BrandPalette.silver
        case .iconSecondary: BrandPalette.steel
        case .success: RGBAColor(hex: 0x1B7A3D)
        case .warning: RGBAColor(hex: 0x8A5A00)
        case .error: RGBAColor(hex: 0xB3261E)
        case .info: RGBAColor(hex: 0x1F5A8A)
        case .keyCardBackground: BrandPalette.ink
        case .keyCardText: BrandPalette.white
        case .keyCardMuted: RGBAColor(hex: 0xA3A3A3)
        case .scrim: RGBAColor(hex: 0x000000, alpha: 0.4)
        }
    }

    /// Value used in the dark appearance.
    public var dark: RGBAColor {
        switch self {
        case .background: BrandPalette.darkBackground
        case .surface: BrandPalette.darkPanel
        case .surfaceElevated: BrandPalette.darkElevated
        case .skeleton: RGBAColor(hex: 0x2A2A2A)
        case .imageBackground: RGBAColor(hex: 0xE6E6E6)
        case .imageIcon: RGBAColor(hex: 0x7C7C7C)
        case .textPrimary: BrandPalette.darkText
        case .textSecondary: RGBAColor(hex: 0xB8B8B8)
        case .textTertiary: RGBAColor(hex: 0x9E9E9E)
        case .brand: BrandPalette.white
        case .brandPressed: BrandPalette.silver
        case .brandSoft: BrandPalette.darkDivider
        case .textOnBrand: BrandPalette.ink
        case .accent: BrandPalette.white
        case .accentDeep: BrandPalette.silver
        case .accentText: BrandPalette.darkText
        case .textOnAccent: BrandPalette.ink
        case .urgency: BrandPalette.sale
        case .urgencyText: RGBAColor(hex: 0xFF7A85)
        case .textOnUrgency: BrandPalette.white
        case .hairline: BrandPalette.darkElevated
        case .divider: BrandPalette.darkDivider
        case .iconSecondary: RGBAColor(hex: 0x8E8E8E)
        case .success: RGBAColor(hex: 0x5FC58A)
        case .warning: RGBAColor(hex: 0xE7B85C)
        case .error: RGBAColor(hex: 0xF2877E)
        case .info: RGBAColor(hex: 0x86B8E6)
        case .keyCardBackground: BrandPalette.darkPanel
        case .keyCardText: BrandPalette.white
        case .keyCardMuted: RGBAColor(hex: 0xA3A3A3)
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
