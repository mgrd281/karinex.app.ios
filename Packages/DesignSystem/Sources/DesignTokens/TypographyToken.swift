/// The KARINEX type scale.
///
/// Display and title styles use a serif face (editorial headlines); UI and body text use
/// the system sans serif; license keys use a monospaced face. Every style scales with
/// Dynamic Type relative to the listed system text style.
public enum TypographyToken: String, CaseIterable, Sendable {
    /// Hero headline.
    case display
    /// Screen and product titles.
    case title1
    /// Section titles.
    case title2
    /// Card titles.
    case title3
    /// Emphasized UI labels.
    case headline
    /// Running text.
    case body
    /// Secondary running text.
    case callout
    /// Supporting labels.
    case subheadline
    /// Legal notes, footnotes.
    case footnote
    /// Captions and metadata.
    case caption
    /// Small uppercase label above a title ("eyebrow").
    case eyebrow
    /// Prices.
    case price
    /// Large numerals (countdown digits).
    case numeral
    /// License keys.
    case licenseKey

    /// Font family classification.
    public enum Design: String, Sendable {
        case serif
        case sans
        case monospaced
    }

    /// Weight names shared with the SwiftUI mapping.
    public enum Weight: String, Sendable {
        case regular
        case medium
        case semibold
        case bold
    }

    /// The system text style a token scales relative to under Dynamic Type.
    public enum RelativeStyle: String, Sendable {
        case largeTitle
        case title
        case title2
        case title3
        case headline
        case body
        case callout
        case subheadline
        case footnote
        case caption
        case caption2
    }

    /// Point size at the default Dynamic Type setting (Large).
    public var baseSize: Double {
        switch self {
        case .display: 38
        case .title1: 30
        case .title2: 24
        case .title3: 20
        case .headline: 17
        case .body: 17
        case .callout: 16
        case .subheadline: 15
        case .footnote: 13
        case .caption: 12
        case .eyebrow: 12
        case .price: 22
        case .numeral: 28
        case .licenseKey: 17
        }
    }

    public var design: Design {
        switch self {
        case .display, .title1, .title2, .title3, .numeral: .serif
        case .licenseKey: .monospaced
        case .headline, .body, .callout, .subheadline, .footnote, .caption, .eyebrow, .price: .sans
        }
    }

    public var weight: Weight {
        switch self {
        case .display, .title1, .title2: .medium
        case .title3, .headline, .eyebrow, .price, .numeral: .semibold
        case .licenseKey: .medium
        case .body, .callout, .subheadline, .footnote, .caption: .regular
        }
    }

    public var relativeStyle: RelativeStyle {
        switch self {
        case .display: .largeTitle
        case .title1: .title
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .body, .licenseKey: .body
        case .callout: .callout
        case .subheadline: .subheadline
        case .footnote: .footnote
        case .caption: .caption
        case .eyebrow: .caption2
        case .price: .title3
        case .numeral: .title
        }
    }

    /// Letter spacing in points at the base size.
    public var tracking: Double {
        switch self {
        case .display: -0.4
        case .title1: -0.2
        case .eyebrow: 1.4
        case .licenseKey: 1.2
        default: 0
        }
    }

    /// Whether the style is rendered in uppercase.
    public var isUppercased: Bool {
        self == .eyebrow
    }

    /// Whether digits are rendered with fixed width (prices, countdowns, keys).
    public var usesMonospacedDigits: Bool {
        switch self {
        case .price, .numeral, .licenseKey: true
        default: false
        }
    }
}
