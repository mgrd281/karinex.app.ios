#if DEBUG
import DesignTokens
import SwiftUI
import UIKit

// MARK: - Colors

/// A named group of color tokens for the colors page.
struct KXGalleryColorGroup: Identifiable, Sendable {
    let title: String
    let tokens: [ColorToken]

    var id: String { title }

    /// Every token grouped by role, in the order of `ColorToken`. Each token appears exactly once.
    static let all: [KXGalleryColorGroup] = [
        KXGalleryColorGroup(title: "Surfaces", tokens: [.background, .surface, .surfaceElevated, .skeleton]),
        KXGalleryColorGroup(title: "Text", tokens: [.textPrimary, .textSecondary, .textTertiary]),
        KXGalleryColorGroup(title: "Brand and actions", tokens: [.brand, .brandPressed, .brandSoft, .textOnBrand]),
        KXGalleryColorGroup(title: "Accent", tokens: [.accent, .accentDeep, .accentText, .textOnAccent]),
        KXGalleryColorGroup(title: "Urgency", tokens: [.urgency, .urgencyText, .textOnUrgency]),
        KXGalleryColorGroup(title: "Lines and icons", tokens: [.hairline, .divider, .iconSecondary]),
        KXGalleryColorGroup(title: "Status", tokens: [.success, .warning, .error, .info]),
        KXGalleryColorGroup(
            title: "License key card",
            tokens: [.keyCardBackground, .keyCardText, .keyCardMuted, .keyCardAccent]
        ),
        KXGalleryColorGroup(title: "Overlays", tokens: [.scrim]),
    ]
}

/// Every semantic color token with a live swatch, its light and dark values, and the WCAG
/// contrast of every allowed text/background pairing.
struct KXGalleryColorsPage: View {
    var body: some View {
        KXGalleryPage(topic: .colors) {
            ForEach(KXGalleryColorGroup.all) { group in
                KXGalleryDemo(group.title) {
                    VStack(alignment: .leading, spacing: KXSpacing.s) {
                        ForEach(group.tokens, id: \.self) { token in
                            KXGalleryColorRow(token: token)
                        }
                    }
                }
            }
            KXGalleryDemo(
                "Contrast pairs",
                note: "ContrastRequirement.all: light and dark ratio against the minimum (4.5 text, 3.0 non-text)."
            ) {
                VStack(alignment: .leading, spacing: KXSpacing.xs) {
                    ForEach(ContrastRequirement.all, id: \.self) { requirement in
                        KXGalleryContrastRow(requirement: requirement)
                    }
                }
            }
        }
    }
}

/// One token: a split swatch with the fixed light and dark values, a dot with the live
/// (appearance-dependent) color, the token name and its hex values.
private struct KXGalleryColorRow: View {
    let token: ColorToken

    var body: some View {
        HStack(alignment: .center, spacing: KXSpacing.s) {
            swatch
            VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                Text(verbatim: token.rawValue)
                    .kxFont(.headline)
                    .foregroundStyle(KXColor.textPrimary)
                Text(verbatim: "Light \(Self.describe(token.light)), dark \(Self.describe(token.dark))")
                    .kxFont(.caption)
                    .foregroundStyle(KXColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var swatch: some View {
        let shape = RoundedRectangle(cornerRadius: KXRadius.small, style: .continuous)
        return HStack(spacing: 0) {
            Color(uiColor: UIColor(rgba: token.light))
            Color(uiColor: UIColor(rgba: token.dark))
        }
        .frame(width: 64, height: 44)
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(KXColor.divider, lineWidth: KXBorder.hairline)
        }
        .overlay(alignment: .bottomTrailing) {
            Circle()
                .fill(KXColor.color(token))
                .frame(width: 16, height: 16)
                .overlay {
                    Circle().strokeBorder(KXColor.divider, lineWidth: KXBorder.regular)
                }
                .offset(x: KXSpacing.xxs, y: KXSpacing.xxs)
        }
        .accessibilityHidden(true)
    }

    /// `#RRGGBB`, plus the opacity in percent for translucent values.
    private static func describe(_ color: RGBAColor) -> String {
        guard color.alpha < 1 else { return color.hexString }
        return "\(color.hexString) at \(Int((color.alpha * 100).rounded())) %"
    }
}

/// One contrast pairing with its ratios in both appearances.
private struct KXGalleryContrastRow: View {
    let requirement: ContrastRequirement

    var body: some View {
        let lightRatio = requirement.ratio(in: .light)
        let darkRatio = requirement.ratio(in: .dark)
        let passes = lightRatio >= requirement.minimumRatio && darkRatio >= requirement.minimumRatio
        HStack(alignment: .firstTextBaseline, spacing: KXSpacing.xs) {
            Image(systemName: passes ? "checkmark.circle.fill" : "xmark.octagon.fill")
                .foregroundStyle(passes ? KXColor.success : KXColor.error)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: "\(requirement.foreground.rawValue) on \(requirement.background.rawValue)")
                    .kxFont(.subheadline)
                    .foregroundStyle(KXColor.textPrimary)
                Text(verbatim: Self.ratios(light: lightRatio, dark: darkRatio, minimum: requirement.minimumRatio))
                    .kxFont(.caption)
                    .foregroundStyle(KXColor.textSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    /// "Light 15.2, dark 14.1, minimum 4.5".
    private static func ratios(light: Double, dark: Double, minimum: Double) -> String {
        "Light \(format(light)), dark \(format(dark)), minimum \(format(minimum))"
    }

    private static func format(_ ratio: Double) -> String {
        ratio.formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "en_US_POSIX")))
    }
}

// MARK: - Typography

/// The type scale: every `TypographyToken` rendered with `kxFont(_:)` and its metrics.
struct KXGalleryTypographyPage: View {
    var body: some View {
        KXGalleryPage(topic: .typography) {
            KXGalleryDemo(
                "Type scale",
                note: "Sizes scale with Dynamic Type relative to the listed text style. Use the text size setting to compare."
            ) {
                VStack(alignment: .leading, spacing: KXSpacing.l) {
                    ForEach(TypographyToken.allCases, id: \.self) { token in
                        VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                            Text(verbatim: Self.sample(for: token))
                                .kxFont(token)
                                .foregroundStyle(KXColor.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(verbatim: Self.metrics(of: token))
                                .kxFont(.caption)
                                .foregroundStyle(KXColor.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    /// Representative content for each style, taken from the recorded store samples.
    private static func sample(for token: TypographyToken) -> String {
        switch token {
        case .display: "KARINEX Editorial"
        case .title1, .title2, .title3: KXGallerySamples.officeProPlusTitle
        case .headline, .body, .callout, .subheadline: KXGallerySamples.supportChannels
        case .footnote, .caption: KXGallerySamples.taxNote
        case .eyebrow: "Lizenzschlüssel"
        case .price: KXGallerySamples.officeProPlusPrice
        case .numeral: "02 03 04"
        case .licenseKey: KXGallerySamples.placeholderLicenseKey
        }
    }

    /// "title2: 24 pt, serif, medium, relative to title2, tracking -0.2".
    private static func metrics(of token: TypographyToken) -> String {
        var parts = [
            "\(token.rawValue): \(token.baseSize.formatted()) pt",
            token.design.rawValue,
            token.weight.rawValue,
            "relative to \(token.relativeStyle.rawValue)",
        ]
        if token.tracking != 0 {
            parts.append("tracking \(token.tracking.formatted())")
        }
        if token.isUppercased {
            parts.append("uppercase")
        }
        if token.usesMonospacedDigits {
            parts.append("monospaced digits")
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Spacing, shape and motion

/// A named numeric token value.
private struct KXGalleryMetric: Identifiable {
    let name: String
    let value: CGFloat

    var id: String { name }
}

/// Spacing scale, corner radii, stroke widths and an interactive comparison of the motion
/// curves.
struct KXGalleryLayoutPage: View {
    private let spacing: [KXGalleryMetric] = [
        KXGalleryMetric(name: "xxs", value: KXSpacing.xxs),
        KXGalleryMetric(name: "xs", value: KXSpacing.xs),
        KXGalleryMetric(name: "s", value: KXSpacing.s),
        KXGalleryMetric(name: "m, gutter", value: KXSpacing.m),
        KXGalleryMetric(name: "l", value: KXSpacing.l),
        KXGalleryMetric(name: "xl", value: KXSpacing.xl),
        KXGalleryMetric(name: "minimumTapTarget", value: KXSpacing.minimumTapTarget),
        KXGalleryMetric(name: "xxl", value: KXSpacing.xxl),
        KXGalleryMetric(name: "xxxl", value: KXSpacing.xxxl),
    ]

    private let radii: [KXGalleryMetric] = [
        KXGalleryMetric(name: "small", value: KXRadius.small),
        KXGalleryMetric(name: "medium", value: KXRadius.medium),
        KXGalleryMetric(name: "card", value: KXRadius.card),
        KXGalleryMetric(name: "large", value: KXRadius.large),
    ]

    private let borders: [KXGalleryMetric] = [
        KXGalleryMetric(name: "hairline", value: KXBorder.hairline),
        KXGalleryMetric(name: "regular", value: KXBorder.regular),
        KXGalleryMetric(name: "emphasis", value: KXBorder.emphasis),
    ]

    var body: some View {
        KXGalleryPage(topic: .layout) {
            KXGalleryDemo("Spacing", note: "KXSpacing on the 8 pt grid, drawn as gold bars.") {
                VStack(alignment: .leading, spacing: KXSpacing.xs) {
                    ForEach(spacing) { metric in
                        HStack(spacing: KXSpacing.s) {
                            KXColor.accent
                                .frame(width: metric.value, height: KXSpacing.s)
                                .accessibilityHidden(true)
                            metricLabel(metric)
                        }
                    }
                }
            }
            KXGalleryDemo("Corner radii", note: "KXRadius, continuous corners.") {
                VStack(alignment: .leading, spacing: KXSpacing.s) {
                    ForEach(radii) { metric in
                        HStack(spacing: KXSpacing.s) {
                            RoundedRectangle(cornerRadius: metric.value, style: .continuous)
                                .fill(KXColor.surface)
                                .overlay {
                                    RoundedRectangle(cornerRadius: metric.value, style: .continuous)
                                        .strokeBorder(KXColor.accent, lineWidth: KXBorder.regular)
                                }
                                .frame(width: 96, height: 56)
                                .accessibilityHidden(true)
                            metricLabel(metric)
                        }
                    }
                }
            }
            KXGalleryDemo("Stroke widths", note: "KXBorder. Components draw hairlines as one physical pixel.") {
                VStack(alignment: .leading, spacing: KXSpacing.s) {
                    ForEach(borders) { metric in
                        HStack(spacing: KXSpacing.s) {
                            KXColor.textPrimary
                                .frame(width: 96, height: metric.value)
                                .accessibilityHidden(true)
                            metricLabel(metric)
                        }
                    }
                }
            }
            KXGalleryDemo(
                "Motion",
                note: "KXMotion curves. With Reduce Motion every curve becomes a short cross-fade."
            ) {
                KXGalleryMotionDemo()
            }
        }
    }

    private func metricLabel(_ metric: KXGalleryMetric) -> some View {
        Text(verbatim: "\(metric.name): \(Double(metric.value).formatted()) pt")
            .kxFont(.footnote)
            .foregroundStyle(KXColor.textSecondary)
    }
}

/// The four brand curves side by side: each row moves a gold dot across its track.
private struct KXGalleryMotionDemo: View {
    /// A motion curve with its developer label.
    private struct MotionSample: Identifiable {
        let name: String
        let curve: KXMotion.Curve

        var id: String { name }
    }

    private let curves = [
        MotionSample(name: "standard", curve: .standard),
        MotionSample(name: "snappy", curve: .snappy),
        MotionSample(name: "gentle", curve: .gentle),
        MotionSample(name: "fade", curve: .fade),
    ]

    @State private var isAtEnd = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.m) {
            ForEach(curves) { item in
                VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                    Text(verbatim: item.name)
                        .kxFont(.footnote)
                        .foregroundStyle(KXColor.textSecondary)
                    Circle()
                        .fill(KXColor.accent)
                        .frame(width: KXSpacing.l, height: KXSpacing.l)
                        .opacity(item.curve == .fade && isAtEnd ? 0.35 : 1)
                        .frame(maxWidth: .infinity, alignment: isAtEnd ? .trailing : .leading)
                        .padding(KXSpacing.xxs)
                        .background(KXColor.surface, in: Capsule(style: .continuous))
                        .animation(KXMotion.animation(item.curve, reduceMotion: reduceMotion), value: isAtEnd)
                        .accessibilityHidden(true)
                }
            }
            KXButton("Play", systemImage: "play.fill", style: .secondary, size: .compact) {
                isAtEnd.toggle()
            }
        }
    }
}

// MARK: - Previews

#Preview("Foundations, light") {
    NavigationStack {
        KXGalleryColorsPage()
    }
}

#Preview("Foundations, dark") {
    NavigationStack {
        KXGalleryTypographyPage()
    }
    .preferredColorScheme(.dark)
}

#Preview("Foundations, accessibility size") {
    NavigationStack {
        KXGalleryLayoutPage()
    }
    .dynamicTypeSize(.accessibility2)
}
#endif
