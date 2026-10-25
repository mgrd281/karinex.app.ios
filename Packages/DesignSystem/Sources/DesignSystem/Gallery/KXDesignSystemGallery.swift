#if DEBUG
import SwiftUI

// MARK: - KXDesignSystemGallery

/// A developer catalog of the KARINEX design system: the color tokens with their light and dark
/// values and contrast pairs, the type scale, spacing, radii, borders and motion curves, and one
/// page per component showing its variants and states.
///
/// The gallery is a DEBUG-only developer tool and is never shipped to customers. Its own labels
/// are plain English developer text (`Text(verbatim:)`); the sample content passed into the
/// components is German store data recorded from the live Storefront API, so the components
/// look exactly as they will in the app.
///
/// Push it inside an existing `NavigationStack`, for example from the Account tab:
///
/// ```swift
/// #if DEBUG
/// NavigationLink {
///     KXDesignSystemGallery()
/// } label: {
///     Text(verbatim: "Design System")
/// }
/// #endif
/// ```
///
/// The preview settings at the top override the appearance and the Dynamic Type size of the
/// pages pushed from the gallery, so every component can be checked in light and dark mode and
/// at accessibility text sizes without changing the device settings.
public struct KXDesignSystemGallery: View {
    @State private var appearance = KXGalleryAppearance.system
    @State private var textSize = KXGalleryTextSize.system

    /// Creates the gallery.
    public init() {}

    public var body: some View {
        List {
            Section {
                settingsRows
            } header: {
                KXGallerySectionTitle("Preview settings")
            } footer: {
                Text(verbatim: "Applied to the pages opened from this list.")
                    .kxFont(.footnote)
                    .foregroundStyle(KXColor.textSecondary)
            }

            Section {
                topicLinks(KXGalleryTopic.foundations)
            } header: {
                KXGallerySectionTitle("Foundations")
            }

            Section {
                topicLinks(KXGalleryTopic.components)
            } header: {
                KXGallerySectionTitle("Components")
            }
        }
        .scrollContentBackground(.hidden)
        .kxScreenBackground()
        .navigationTitle(Text(verbatim: "Design System"))
        .accessibilityIdentifier("screen.designSystemGallery")
    }

    // MARK: Rows

    @ViewBuilder private var settingsRows: some View {
        Picker(selection: $appearance) {
            ForEach(KXGalleryAppearance.allCases) { option in
                Text(verbatim: option.title).tag(option)
            }
        } label: {
            Text(verbatim: "Appearance")
                .kxFont(.body)
                .foregroundStyle(KXColor.textPrimary)
        }
        .listRowBackground(KXColor.surface)

        Picker(selection: $textSize) {
            ForEach(KXGalleryTextSize.allCases) { option in
                Text(verbatim: option.title).tag(option)
            }
        } label: {
            Text(verbatim: "Text size")
                .kxFont(.body)
                .foregroundStyle(KXColor.textPrimary)
        }
        .listRowBackground(KXColor.surface)
    }

    private func topicLinks(_ topics: [KXGalleryTopic]) -> some View {
        ForEach(topics) { topic in
            NavigationLink {
                KXGalleryTopicPage(topic: topic)
                    .modifier(KXGalleryPreviewEnvironment(appearance: appearance, textSize: textSize))
            } label: {
                KXGalleryTopicRow(topic: topic)
            }
            .listRowBackground(KXColor.surface)
            .accessibilityIdentifier("gallery.topic.\(topic.rawValue)")
        }
    }
}

// MARK: - Topics

/// One page of the gallery: a foundation (tokens) or a component.
enum KXGalleryTopic: String, CaseIterable, Identifiable, Sendable {
    // Foundations
    case colors
    case typography
    case layout
    // Components
    case button
    case card
    case badge
    case priceTag
    case sectionHeader
    case specRow
    case divider
    case wordmark
    case skeleton
    case emptyState
    case banner
    case stepTimeline
    case accordion
    case countdown
    case trustStrip
    case productCard
    case keyCard

    /// The foundation pages in display order.
    static let foundations: [Self] = allCases.filter(\.isFoundation)
    /// The component pages in display order.
    static let components: [Self] = allCases.filter { !$0.isFoundation }

    var id: String { rawValue }

    /// Whether the topic documents tokens rather than a component.
    var isFoundation: Bool {
        switch self {
        case .colors, .typography, .layout: true
        default: false
        }
    }

    /// The page title: the token group or the component type name.
    var title: String {
        switch self {
        case .colors: "Colors"
        case .typography: "Typography"
        case .layout: "Spacing, shape and motion"
        case .button: "KXButton"
        case .card: "KXCard"
        case .badge: "KXBadge"
        case .priceTag: "KXPriceTag"
        case .sectionHeader: "KXSectionHeader"
        case .specRow: "KXSpecRow"
        case .divider: "KXDivider"
        case .wordmark: "KXWordmark"
        case .skeleton: "KXSkeleton"
        case .emptyState: "KXEmptyState"
        case .banner: "KXBanner"
        case .stepTimeline: "KXStepTimeline"
        case .accordion: "KXAccordion"
        case .countdown: "KXCountdown"
        case .trustStrip: "KXTrustStrip"
        case .productCard: "KXProductCard"
        case .keyCard: "KXKeyCard"
        }
    }

    /// One line describing what the page shows.
    var summary: String {
        switch self {
        case .colors: "Semantic tokens with light and dark values, and every WCAG contrast pair."
        case .typography: "The type scale with size, design, weight and Dynamic Type anchor."
        case .layout: "Spacing scale, corner radii, stroke widths and the motion curves."
        case .button: "Primary, secondary and tertiary styles in both sizes, loading and disabled."
        case .card: "Standard and elevated panels, the gold inset ring and full-bleed content."
        case .badge: "Gold, urgency, neutral and success capsules, with and without symbols."
        case .priceTag: "Price, compare-at price, savings badge and tax note, regular and compact."
        case .sectionHeader: "Serif title with eyebrow, gold rule and the optional trailing action."
        case .specRow: "Label and value with a dotted leader that stacks when space runs out."
        case .divider: "Hairline rules in the neutral and gold styles, horizontal and vertical."
        case .wordmark: "The interim typographic logo in three sizes and on brand panels."
        case .skeleton: "Loading placeholders, the redacting modifier and the shimmer switch."
        case .emptyState: "Symbol in a gold ring, serif title, message and optional action."
        case .banner: "Offline, error, info and success banners and the top-edge presenter in both placements."
        case .stepTimeline: "Process explanations and progress timelines, vertical and horizontal."
        case .accordion: "Single and multiple expansion, custom content and external state."
        case .countdown: "Live and fixed-date countdowns, ink and brand tiles, expiry callback."
        case .trustStrip: "Trust facts as a two-column grid and as an edge-to-edge carousel."
        case .productCard: "Product tiles with remote, missing and local images and badges."
        case .keyCard: "The certificate-style license card, revealed and masked."
        }
    }

    /// SF Symbol shown in the gallery list.
    var systemImage: String {
        switch self {
        case .colors: "paintpalette"
        case .typography: "textformat"
        case .layout: "ruler"
        case .button: "rectangle.and.hand.point.up.left"
        case .card: "rectangle.on.rectangle"
        case .badge: "tag"
        case .priceTag: "eurosign"
        case .sectionHeader: "textformat.size"
        case .specRow: "list.bullet.rectangle"
        case .divider: "minus"
        case .wordmark: "character.cursor.ibeam"
        case .skeleton: "rectangle.dashed"
        case .emptyState: "tray"
        case .banner: "exclamationmark.bubble"
        case .stepTimeline: "list.number"
        case .accordion: "plus.circle"
        case .countdown: "timer"
        case .trustStrip: "checkmark.seal"
        case .productCard: "square.grid.2x2"
        case .keyCard: "key"
        }
    }
}

// MARK: - Preview settings

/// Appearance override for the gallery pages.
enum KXGalleryAppearance: String, CaseIterable, Identifiable, Sendable {
    /// Follow the device.
    case system
    /// Force the light appearance.
    case light
    /// Force the dark appearance.
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// The forced color scheme, or `nil` to follow the device.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// Dynamic Type override for the gallery pages. The sizes match the snapshot test matrix.
enum KXGalleryTextSize: String, CaseIterable, Identifiable, Sendable {
    /// Follow the device.
    case system
    /// The default size (Large).
    case large
    /// The largest non-accessibility size (xxxLarge).
    case xxxLarge
    /// Accessibility size AX3 (accessibilityExtraLarge).
    case accessibility3
    /// The largest accessibility size, AX5.
    case accessibility5

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .large: "Large (default)"
        case .xxxLarge: "xxxLarge"
        case .accessibility3: "AX3"
        case .accessibility5: "AX5"
        }
    }

    /// The forced Dynamic Type size, or `nil` to follow the device.
    var dynamicTypeSize: DynamicTypeSize? {
        switch self {
        case .system: nil
        case .large: .large
        case .xxxLarge: .xxxLarge
        case .accessibility3: .accessibility3
        case .accessibility5: .accessibility5
        }
    }
}

/// Applies the gallery's appearance and text size overrides. Without an override the values
/// of the surrounding environment are passed through unchanged.
struct KXGalleryPreviewEnvironment: ViewModifier {
    let appearance: KXGalleryAppearance
    let textSize: KXGalleryTextSize

    @Environment(\.colorScheme) private var inheritedColorScheme
    @Environment(\.dynamicTypeSize) private var inheritedDynamicTypeSize

    func body(content: Content) -> some View {
        content
            .environment(\.colorScheme, appearance.colorScheme ?? inheritedColorScheme)
            .dynamicTypeSize(textSize.dynamicTypeSize ?? inheritedDynamicTypeSize)
    }
}

// MARK: - List rows

/// A gallery list section title in the eyebrow style.
private struct KXGallerySectionTitle: View {
    private let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(verbatim: title)
            .kxFont(.eyebrow)
            .foregroundStyle(KXColor.accentText)
    }
}

/// A topic row: symbol, title and one-line summary.
private struct KXGalleryTopicRow: View {
    let topic: KXGalleryTopic

    @ScaledMetric(relativeTo: .headline) private var iconSize: CGFloat = 32

    var body: some View {
        HStack(alignment: .center, spacing: KXSpacing.s) {
            Image(systemName: topic.systemImage)
                .font(KXFont.font(.headline, size: Double(iconSize * 0.5)))
                .foregroundStyle(KXColor.brand)
                .frame(width: iconSize, height: iconSize)
                .overlay {
                    Circle().strokeBorder(KXColor.accent, lineWidth: KXBorder.regular)
                }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                Text(verbatim: topic.title)
                    .kxFont(.headline)
                    .foregroundStyle(KXColor.textPrimary)
                Text(verbatim: topic.summary)
                    .kxFont(.footnote)
                    .foregroundStyle(KXColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, KXSpacing.xxs)
    }
}

// MARK: - Router

/// Shows the page of one topic.
struct KXGalleryTopicPage: View {
    let topic: KXGalleryTopic

    var body: some View {
        switch topic {
        case .colors: KXGalleryColorsPage()
        case .typography: KXGalleryTypographyPage()
        case .layout: KXGalleryLayoutPage()
        case .button: KXGalleryButtonPage()
        case .card: KXGalleryCardPage()
        case .badge: KXGalleryBadgePage()
        case .priceTag: KXGalleryPriceTagPage()
        case .sectionHeader: KXGallerySectionHeaderPage()
        case .specRow: KXGallerySpecRowPage()
        case .divider: KXGalleryDividerPage()
        case .wordmark: KXGalleryWordmarkPage()
        case .skeleton: KXGallerySkeletonPage()
        case .emptyState: KXGalleryEmptyStatePage()
        case .banner: KXGalleryBannerPage()
        case .stepTimeline: KXGalleryStepTimelinePage()
        case .accordion: KXGalleryAccordionPage()
        case .countdown: KXGalleryCountdownPage()
        case .trustStrip: KXGalleryTrustStripPage()
        case .productCard: KXGalleryProductCardPage()
        case .keyCard: KXGalleryKeyCardPage()
        }
    }
}

// MARK: - Previews

#Preview("Gallery, light") {
    NavigationStack {
        KXDesignSystemGallery()
    }
}

#Preview("Gallery, dark") {
    NavigationStack {
        KXDesignSystemGallery()
    }
    .preferredColorScheme(.dark)
}

#Preview("Gallery, accessibility size") {
    NavigationStack {
        KXDesignSystemGallery()
    }
    .dynamicTypeSize(.accessibility2)
}
#endif
