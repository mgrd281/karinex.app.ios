import DesignSystem
import SnapshotTesting
import SwiftUI
import Testing
import UIKit

// MARK: - Parent suite

/// The parent of every snapshot suite in this target.
///
/// `.serialized` is recursive: every nested suite, test and argument case runs one after the
/// other. Rendering goes through UIKit on the main thread and `assertSnapshot` waits by spinning
/// the main run loop, so running renders side by side would let them interleave.
///
/// Record mode is not set here. The library reads its own `SNAPSHOT_TESTING_RECORD` environment
/// variable (`all`, `failed`, `missing`, `never`; the default is `missing`). CI passes it to the
/// simulator as `TEST_RUNNER_SNAPSHOT_TESTING_RECORD`. References live in `__Snapshots__` next to
/// the test files, one folder per test file, named `<test>.<variant>.png`.
@Suite("DesignSystem snapshots", .serialized)
struct DesignSystemSnapshotTests {}

// MARK: - Matrix

/// Appearance of a snapshot.
enum SnapshotAppearance: String, Sendable {
    case light
    case dark
}

/// Dynamic Type size of a snapshot.
enum SnapshotTextSize: String, Sendable {
    /// The default size.
    case large
    /// The largest non-accessibility size.
    case extraExtraExtraLarge
    /// Accessibility size AX3.
    case accessibilityExtraLarge

    /// Short form used in snapshot names.
    var nameComponent: String {
        switch self {
        case .large: "large"
        case .extraExtraExtraLarge: "xxxl"
        case .accessibilityExtraLarge: "axxl"
        }
    }

    /// Whether this is one of the accessibility sizes.
    var isAccessibilitySize: Bool {
        self == .accessibilityExtraLarge
    }
}

/// Language of the caller-provided sample strings of a snapshot.
enum SnapshotLanguage: String, Sendable {
    /// German, the source language.
    case de
    /// Finnish, one of the longest app languages (long compound words).
    case fi
}

/// One cell of the snapshot matrix: appearance, Dynamic Type size and sample language.
///
/// Every component is rendered in light and dark at the default size with German samples, and
/// in light at xxxLarge and at accessibilityExtraLarge (AX3) with Finnish samples.
struct SnapshotVariant: Hashable, Sendable, CustomTestStringConvertible {
    let appearance: SnapshotAppearance
    let textSize: SnapshotTextSize
    let language: SnapshotLanguage

    /// The matrix every component is rendered in.
    static let matrix: [SnapshotVariant] = [
        SnapshotVariant(appearance: .light, textSize: .large, language: .de),
        SnapshotVariant(appearance: .dark, textSize: .large, language: .de),
        SnapshotVariant(appearance: .light, textSize: .extraExtraExtraLarge, language: .fi),
        SnapshotVariant(appearance: .light, textSize: .accessibilityExtraLarge, language: .fi),
    ]

    /// The snapshot name, e.g. `light-large-de`.
    var name: String {
        "\(appearance.rawValue)-\(textSize.nameComponent)-\(language.rawValue)"
    }

    var testDescription: String { name }

    /// The SwiftUI color scheme of the variant.
    var colorScheme: ColorScheme {
        switch appearance {
        case .light: .light
        case .dark: .dark
        }
    }

    /// The SwiftUI Dynamic Type size of the variant.
    var dynamicTypeSize: DynamicTypeSize {
        switch textSize {
        case .large: .large
        case .extraExtraExtraLarge: .xxxLarge
        case .accessibilityExtraLarge: .accessibility3
        }
    }

    /// The locale of the sample strings.
    var locale: Locale {
        switch language {
        case .de: Locale(identifier: "de_DE")
        case .fi: Locale(identifier: "fi_FI")
        }
    }

    /// The trait collection the snapshot is rendered with: appearance, content size, a fixed
    /// display scale of 2 and a fixed iPhone layout (compact width, left to right).
    @MainActor var traits: UITraitCollection {
        let style: UIUserInterfaceStyle = appearance == .dark ? .dark : .light
        let contentSize: UIContentSizeCategory = switch textSize {
        case .large: .large
        case .extraExtraExtraLarge: .extraExtraExtraLarge
        case .accessibilityExtraLarge: .accessibilityExtraLarge
        }
        return UITraitCollection { traits in
            traits.userInterfaceStyle = style
            traits.preferredContentSizeCategory = contentSize
            traits.displayScale = SnapshotLayout.displayScale
            traits.userInterfaceIdiom = .phone
            traits.horizontalSizeClass = .compact
            traits.verticalSizeClass = .regular
            traits.layoutDirection = .leftToRight
        }
    }
}

// MARK: - Layout

/// Fixed geometry of every snapshot.
enum SnapshotLayout {
    /// Canvas width in points (the width of a 6.1" iPhone).
    static let width: CGFloat = 390
    /// Render scale. Fixed so references do not depend on the simulator model.
    static let displayScale: CGFloat = 2
    /// Share of pixels that must match.
    static let precision: Float = 0.995
    /// How closely a pixel must match to count as matching (98 % mimics the human eye).
    static let perceptualPrecision: Float = 0.98
}

/// The canvas a component is rendered on: the page background, a fixed width of 390 pt, the
/// height the content needs, and the variant's environment.
///
/// The environment (color scheme, Dynamic Type size, locale, display scale) is set explicitly in
/// addition to the traits, because the snapshot library measures `.sizeThatFits` layouts before
/// it applies the trait overrides. The skeleton shimmer is switched off: it is time-based.
struct SnapshotCanvas<Content: View>: View {
    let variant: SnapshotVariant
    let horizontalPadding: CGFloat
    let content: Content

    init(variant: SnapshotVariant, horizontalPadding: CGFloat, @ViewBuilder content: () -> Content) {
        self.variant = variant
        self.horizontalPadding = horizontalPadding
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, KXSpacing.l)
            .frame(width: SnapshotLayout.width, alignment: .topLeading)
            .fixedSize(horizontal: false, vertical: true)
            .kxScreenBackground()
            .kxSkeletonShimmer(false)
            .environment(\.colorScheme, variant.colorScheme)
            .dynamicTypeSize(variant.dynamicTypeSize)
            .environment(\.locale, variant.locale)
            .environment(\.displayScale, SnapshotLayout.displayScale)
            .environment(\.layoutDirection, .leftToRight)
    }
}

// MARK: - Assertion

/// Renders `content` on a ``SnapshotCanvas`` for `variant` and compares it with the reference
/// image `__Snapshots__/<calling file>/<test>.<variant name>.png`.
///
/// - Parameters:
///   - variant: The matrix cell to render.
///   - horizontalPadding: Inset from the canvas edges. Defaults to the 16 pt screen gutter; pass
///     0 for components that manage their own margins (the trust strip carousel).
///   - fileID: Forwarded so failures point at the calling test.
///   - filePath: Forwarded so the reference folder is named after the calling test file.
///   - testName: Forwarded so the reference file is named after the calling test.
///   - line: Forwarded so failures point at the calling test.
///   - column: Forwarded so failures point at the calling test.
///   - content: The component configuration to render.
@MainActor
func assertComponentSnapshot<Content: View>(
    variant: SnapshotVariant,
    horizontalPadding: CGFloat = KXSpacing.gutter,
    fileID: StaticString = #fileID,
    filePath: StaticString = #filePath,
    testName: String = #function,
    line: UInt = #line,
    column: UInt = #column,
    @ViewBuilder content: () -> Content
) {
    let canvas = SnapshotCanvas(variant: variant, horizontalPadding: horizontalPadding, content: content)
    let strategy: Snapshotting<SnapshotCanvas<Content>, UIImage> = .image(
        precision: SnapshotLayout.precision,
        perceptualPrecision: SnapshotLayout.perceptualPrecision,
        layout: .sizeThatFits,
        traits: variant.traits
    )
    assertSnapshot(
        of: canvas,
        as: strategy,
        named: variant.name,
        fileID: fileID,
        file: filePath,
        testName: testName,
        line: line,
        column: column
    )
}

// MARK: - Local artwork

/// A deterministic stand-in for a product photo, built from shapes only, so product card
/// snapshots never load an image from the network.
struct SnapshotProductArtwork: View {
    var body: some View {
        ZStack {
            KXColor.brandSoft
            Circle()
                .strokeBorder(KXColor.accent, lineWidth: KXBorder.emphasis)
                .padding(KXSpacing.l)
            RoundedRectangle(cornerRadius: KXRadius.small, style: .continuous)
                .fill(KXColor.accent)
                .frame(width: KXSpacing.xl, height: KXSpacing.xl)
        }
    }
}
