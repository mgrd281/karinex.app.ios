import SwiftUI

// MARK: - KXButton

/// The KARINEX call-to-action button.
///
/// Three styles share one shape, type style and sizing system:
/// - ``Style/primary``: brand fill with a `textOnBrand` label. In light mode this is forest
///   green with a cream label; in dark mode the tokens invert to gold with an ink label.
/// - ``Style/secondary``: transparent with a gold outline and a `textPrimary` label.
/// - ``Style/tertiary``: text only, in `accentText`.
///
/// While `isLoading` is `true` the label is replaced by a spinner (the button keeps its size)
/// and taps are ignored, so an action can never be submitted twice. Disable the button with
/// the standard `.disabled(_:)` modifier; the style dims it accordingly.
///
/// Every button is at least 44 x 44 pt, grows with Dynamic Type and wraps long labels instead
/// of truncating them.
///
/// ```swift
/// KXButton(browseTitle, systemImage: "square.grid.2x2", isFullWidth: true) {
///     onBrowse()
/// }
/// ```
public struct KXButton: View {
    /// Visual emphasis of a ``KXButton``.
    public enum Style: String, CaseIterable, Sendable {
        /// Filled with the brand color. One per screen area, for the main action.
        case primary
        /// Gold outline on a transparent background, for alternative actions.
        case secondary
        /// Text only, for low-emphasis actions such as "Alle anzeigen".
        case tertiary
    }

    /// Height class of a ``KXButton``.
    public enum Size: String, CaseIterable, Sendable {
        /// Minimum height 50 pt, for prominent calls to action.
        case regular
        /// Minimum height 44 pt, for inline, banner and section header actions.
        case compact
    }

    private let title: String
    private let systemImage: String?
    private let style: Style
    private let size: Size
    private let isFullWidth: Bool
    private let isLoading: Bool
    private let action: () -> Void

    /// Creates a button.
    ///
    /// - Parameters:
    ///   - title: The already-localized label.
    ///   - systemImage: Optional SF Symbol name shown before the label. It is decorative and
    ///     hidden from VoiceOver.
    ///   - style: Visual emphasis. Defaults to ``Style/primary``.
    ///   - size: Height class. Defaults to ``Size/regular``.
    ///   - isFullWidth: When `true` the button fills the available width.
    ///   - isLoading: When `true` a spinner replaces the label and taps are ignored.
    ///   - action: Called on tap (never while loading).
    public init(
        _ title: String,
        systemImage: String? = nil,
        style: Style = .primary,
        size: Size = .regular,
        isFullWidth: Bool = false,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.style = style
        self.size = size
        self.isFullWidth = isFullWidth
        self.isLoading = isLoading
        self.action = action
    }

    public var body: some View {
        Button {
            guard !isLoading else { return }
            action()
        } label: {
            HStack(spacing: KXSpacing.xs) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .accessibilityHidden(true)
                }
                Text(title)
            }
        }
        .buttonStyle(KXButtonStyle(style, size: size, isFullWidth: isFullWidth, isLoading: isLoading))
        .accessibilityLabel(title)
        .accessibilityValue(isLoading ? String(localized: "kx.button.loading", bundle: .module) : "")
    }
}

// MARK: - KXButtonStyle

/// The `ButtonStyle` behind ``KXButton``.
///
/// Use it directly when a control needs the KARINEX button look but is not a plain `Button`,
/// for example a `NavigationLink` or a `ShareLink`:
///
/// ```swift
/// NavigationLink(value: route) { Text(title) }
///     .buttonStyle(.kx(.secondary, isFullWidth: true))
/// ```
///
/// The pressed state darkens the primary fill to `brandPressed`, tints the secondary
/// background with gold and fades the tertiary label. Presses scale the button slightly
/// unless Reduce Motion is on.
///
/// When you pass `isLoading: true` to a custom label, give the control an explicit
/// `accessibilityLabel`, because the hidden label may no longer be read by VoiceOver.
public struct KXButtonStyle: ButtonStyle {
    private let style: KXButton.Style
    private let size: KXButton.Size
    private let isFullWidth: Bool
    private let isLoading: Bool

    /// Creates the style.
    ///
    /// - Parameters:
    ///   - style: Visual emphasis. Defaults to ``KXButton/Style/primary``.
    ///   - size: Height class. Defaults to ``KXButton/Size/regular``.
    ///   - isFullWidth: When `true` the control fills the available width.
    ///   - isLoading: When `true` a spinner replaces the label. The style does not block
    ///     taps; the action is responsible for ignoring them (``KXButton`` does this).
    public init(
        _ style: KXButton.Style = .primary,
        size: KXButton.Size = .regular,
        isFullWidth: Bool = false,
        isLoading: Bool = false
    ) {
        self.style = style
        self.size = size
        self.isFullWidth = isFullWidth
        self.isLoading = isLoading
    }

    public func makeBody(configuration: Configuration) -> some View {
        KXButtonStyleBody(
            label: configuration.label,
            isPressed: configuration.isPressed,
            style: style,
            size: size,
            isFullWidth: isFullWidth,
            isLoading: isLoading
        )
    }
}

extension ButtonStyle where Self == KXButtonStyle {
    /// The KARINEX button style, e.g. `.buttonStyle(.kx(.secondary))`.
    ///
    /// - Parameters:
    ///   - style: Visual emphasis. Defaults to ``KXButton/Style/primary``.
    ///   - size: Height class. Defaults to ``KXButton/Size/regular``.
    ///   - isFullWidth: When `true` the control fills the available width.
    @MainActor
    public static func kx(
        _ style: KXButton.Style = .primary,
        size: KXButton.Size = .regular,
        isFullWidth: Bool = false
    ) -> KXButtonStyle {
        KXButtonStyle(style, size: size, isFullWidth: isFullWidth)
    }
}

// MARK: - Style body

/// Renders a button label for ``KXButtonStyle``. It is a separate view so that environment
/// values such as `isEnabled` and Reduce Motion update reliably.
private struct KXButtonStyleBody: View {
    let label: ButtonStyleConfiguration.Label
    let isPressed: Bool
    let style: KXButton.Style
    let size: KXButton.Size
    let isFullWidth: Bool
    let isLoading: Bool

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: KXRadius.medium, style: .continuous)
        label
            .kxFont(.headline)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(foregroundColor)
            .opacity(labelOpacity)
            .overlay {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(foregroundColor)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .frame(
                minWidth: KXSpacing.minimumTapTarget,
                maxWidth: isFullWidth ? .infinity : nil,
                minHeight: minimumHeight
            )
            .background(backgroundColor, in: shape)
            .overlay {
                if style == .secondary {
                    shape.strokeBorder(KXColor.accent, lineWidth: KXBorder.regular)
                }
            }
            .contentShape(shape)
            .scaleEffect(pressedScale)
            .opacity(isEnabled ? 1 : 0.45)
            .animation(KXMotion.animation(.snappy, reduceMotion: reduceMotion), value: isPressed)
    }

    // MARK: Appearance

    private var foregroundColor: Color {
        switch style {
        case .primary: KXColor.textOnBrand
        case .secondary: KXColor.textPrimary
        case .tertiary: KXColor.accentText
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .primary: isPressed ? KXColor.brandPressed : KXColor.brand
        case .secondary: isPressed ? KXColor.accent.opacity(0.16) : Color.clear
        case .tertiary: Color.clear
        }
    }

    private var labelOpacity: Double {
        if isLoading { return 0 }
        return style == .tertiary && isPressed ? 0.55 : 1
    }

    private var pressedScale: CGFloat {
        guard isPressed, !reduceMotion, style != .tertiary else { return 1 }
        return 0.98
    }

    // MARK: Metrics

    private var minimumHeight: CGFloat {
        switch size {
        case .regular: 50
        case .compact: KXSpacing.minimumTapTarget
        }
    }

    private var horizontalPadding: CGFloat {
        if style == .tertiary { return KXSpacing.xs }
        switch size {
        case .regular: return KXSpacing.l
        case .compact: return KXSpacing.m
        }
    }

    private var verticalPadding: CGFloat {
        switch size {
        case .regular: KXSpacing.s
        case .compact: KXSpacing.xs
        }
    }
}

// MARK: - Previews

private struct KXButtonPreviewGallery: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KXSpacing.m) {
                KXButton("Zum Sortiment", systemImage: "square.grid.2x2", isFullWidth: true) {}
                KXButton("In den Warenkorb", isFullWidth: true, isLoading: true) {}
                KXButton("Zum Sortiment", isFullWidth: true) {}
                    .disabled(true)
                KXButton("Anleitung", style: .secondary) {}
                KXButton("Anleitung", style: .secondary, size: .compact) {}
                KXButton("Alle anzeigen", style: .tertiary, size: .compact) {}
                NavigationLink {
                    Text(verbatim: "Ziel")
                } label: {
                    Text(verbatim: "NavigationLink mit .kx(.secondary)")
                }
                .buttonStyle(.kx(.secondary, isFullWidth: true))
            }
            .padding(KXSpacing.gutter)
        }
        .kxScreenBackground()
    }
}

#Preview("KXButton, light") {
    NavigationStack {
        KXButtonPreviewGallery()
    }
}

#Preview("KXButton, dark") {
    NavigationStack {
        KXButtonPreviewGallery()
    }
    .preferredColorScheme(.dark)
}

#Preview("KXButton, accessibility size") {
    NavigationStack {
        KXButtonPreviewGallery()
    }
    .dynamicTypeSize(.accessibility2)
}
