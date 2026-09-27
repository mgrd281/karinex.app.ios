/// A foreground/background token pair that must meet a minimum WCAG contrast ratio
/// in every appearance.
public struct ContrastRequirement: Hashable, Sendable {
    public enum Kind: String, Sendable {
        /// Body and UI text: WCAG 1.4.3, at least 4.5:1.
        case text
        /// Icons, focus rings and control boundaries: WCAG 1.4.11, at least 3:1.
        case nonText
    }

    public let foreground: ColorToken
    public let background: ColorToken
    public let kind: Kind

    public init(foreground: ColorToken, background: ColorToken, kind: Kind) {
        self.foreground = foreground
        self.background = background
        self.kind = kind
    }

    public var minimumRatio: Double {
        switch kind {
        case .text: 4.5
        case .nonText: 3.0
        }
    }

    /// Contrast ratio of this pair in the given appearance.
    public func ratio(in appearance: Appearance) -> Double {
        foreground.value(for: appearance).contrastRatio(against: background.value(for: appearance))
    }

    /// Every pairing the components are allowed to use. A component that renders text in
    /// a combination not listed here is a design-system bug.
    public static let all: [ContrastRequirement] = {
        let pageSurfaces: [ColorToken] = [.background, .surface, .surfaceElevated]
        let readableText: [ColorToken] = [
            .textPrimary, .textSecondary, .textTertiary,
            .accentText, .urgencyText,
            .success, .warning, .error, .info,
        ]
        var requirements: [ContrastRequirement] = []
        for background in pageSurfaces {
            for foreground in readableText {
                requirements.append(.init(foreground: foreground, background: background, kind: .text))
            }
            requirements.append(.init(foreground: .iconSecondary, background: background, kind: .nonText))
            requirements.append(.init(foreground: .brand, background: background, kind: .nonText))
        }
        requirements += [
            .init(foreground: .textOnBrand, background: .brand, kind: .text),
            .init(foreground: .textOnBrand, background: .brandPressed, kind: .text),
            .init(foreground: .textOnAccent, background: .accent, kind: .text),
            .init(foreground: .textOnAccent, background: .accentDeep, kind: .text),
            .init(foreground: .textOnUrgency, background: .urgency, kind: .text),
            .init(foreground: .keyCardText, background: .keyCardBackground, kind: .text),
            .init(foreground: .keyCardMuted, background: .keyCardBackground, kind: .text),
            .init(foreground: .accent, background: .keyCardBackground, kind: .text),
            .init(foreground: .keyCardAccent, background: .keyCardBackground, kind: .nonText),
        ]
        return requirements
    }()
}
