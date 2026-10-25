import Accessibility
import SwiftUI

// MARK: - KXBanner

/// A status banner for offline, error, info and success messages: an SF Symbol, the message,
/// an optional action (by default "Erneut versuchen") and an optional close button, on an
/// elevated panel with a colored leading edge.
///
/// When the banner appears, and whenever its message changes, it posts a VoiceOver
/// announcement so users of assistive technologies learn about the state change without
/// having to find the banner.
///
/// Insert and remove it inside an animation to slide it in from the top; with Reduce Motion
/// it cross-fades instead. The `kxBanner(isPresented:placement:banner:)` modifier does all of
/// this and places the banner at the top of the modified view. Around navigation containers use
/// the ``KXBannerPlacement/inset`` placement, which pushes the content down instead of covering
/// the navigation bar:
///
/// ```swift
/// TabView { ... }
///     .kxBanner(isPresented: networkStatus == .offline, placement: .inset) {
///         KXBanner(.offline)
///     }
/// ```
///
/// Without a `message` each style uses its design-system default text, e.g. for
/// ``Style/offline`` "Sie sind offline. Bitte prüfen Sie Ihre Internetverbindung.".
public struct KXBanner: View {
    /// The kind of message a ``KXBanner`` shows. Determines icon, accent color and default text.
    public enum Style: String, CaseIterable, Sendable {
        /// No network connection.
        case offline
        /// A request or action failed.
        case error
        /// Neutral information.
        case info
        /// An action completed.
        case success
    }

    private let style: Style
    private let message: String?
    private let actionTitle: String?
    private let action: (() -> Void)?
    private let onDismiss: (() -> Void)?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Creates a banner.
    ///
    /// - Parameters:
    ///   - style: Kind of message.
    ///   - message: The already-localized message. `nil` uses the style's default text.
    ///   - actionTitle: Label of the action button. `nil` uses "Erneut versuchen".
    ///   - action: Optional action, typically a retry. The button is shown only when an action
    ///     is given.
    ///   - onDismiss: Optional close handler. When given, a close button is shown; the caller
    ///     removes the banner in response.
    public init(
        _ style: Style,
        message: String? = nil,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.style = style
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
        self.onDismiss = onDismiss
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: KXRadius.medium, style: .continuous)
        HStack(alignment: .center, spacing: KXSpacing.s) {
            Image(systemName: systemImage)
                .kxFont(.headline)
                .foregroundStyle(iconColor)
                .accessibilityHidden(true)
            contentLayout {
                Text(resolvedMessage)
                    .kxFont(.subheadline)
                    .foregroundStyle(KXColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let action {
                    KXButton(resolvedActionTitle, style: .tertiary, size: .compact, action: action)
                }
            }
            if let onDismiss {
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .fontWeight(.semibold)
                        .kxFont(.footnote)
                        .foregroundStyle(KXColor.textSecondary)
                        .frame(width: KXSpacing.minimumTapTarget, height: KXSpacing.minimumTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("kx.banner.dismiss", bundle: .module))
            }
        }
        .padding(.leading, KXSpacing.m)
        .padding(.trailing, onDismiss == nil ? KXSpacing.s : KXSpacing.xxs)
        .padding(.vertical, KXSpacing.xxs)
        .frame(minHeight: KXBannerMetrics.minimumHeight)
        .background {
            ZStack(alignment: .leading) {
                shape.fill(KXColor.surfaceElevated)
                Rectangle()
                    .fill(accentColor)
                    .frame(width: KXBannerMetrics.accentEdgeWidth)
            }
            .clipShape(shape)
        }
        .overlay {
            shape.strokeBorder(KXColor.hairline, lineWidth: 1 / max(displayScale, 1))
        }
        .shadow(color: KXColor.scrim.opacity(0.25), radius: KXBannerMetrics.shadowRadius, x: 0, y: KXBannerMetrics.shadowOffset)
        .accessibilityElement(children: .contain)
        .onChange(of: resolvedMessage, initial: true) {
            AccessibilityNotification.Announcement(resolvedMessage).post()
        }
        .transition(kxBannerTransition(reduceMotion: reduceMotion))
    }

    // MARK: Layout

    /// Message and action side by side, or stacked at accessibility text sizes.
    private var contentLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: KXSpacing.xxs))
            : AnyLayout(HStackLayout(alignment: .center, spacing: KXSpacing.xs))
    }

    // MARK: Content

    private var resolvedMessage: String {
        if let message { return message }
        switch style {
        case .offline: return String(localized: "kx.banner.offline.message", bundle: .module)
        case .error: return String(localized: "kx.banner.error.message", bundle: .module)
        case .info: return String(localized: "kx.banner.info.message", bundle: .module)
        case .success: return String(localized: "kx.banner.success.message", bundle: .module)
        }
    }

    private var resolvedActionTitle: String {
        actionTitle ?? String(localized: "kx.banner.retry", bundle: .module)
    }

    // MARK: Appearance

    private var systemImage: String {
        switch style {
        case .offline: "wifi.slash"
        case .error: "exclamationmark.triangle.fill"
        case .info: "info.circle.fill"
        case .success: "checkmark.circle.fill"
        }
    }

    private var iconColor: Color {
        switch style {
        case .offline: KXColor.textSecondary
        case .error: KXColor.error
        case .info: KXColor.info
        case .success: KXColor.success
        }
    }

    private var accentColor: Color {
        switch style {
        case .offline: KXColor.accent
        case .error: KXColor.error
        case .info: KXColor.info
        case .success: KXColor.success
        }
    }
}

// MARK: - Metrics

/// Fixed metrics of ``KXBanner`` that have no general design token.
private enum KXBannerMetrics {
    /// Minimum height: a 44 pt action plus the vertical padding, so one-line banners keep a
    /// calm, consistent height.
    static let minimumHeight: CGFloat = KXSpacing.xxl + KXSpacing.xs
    /// Width of the colored leading edge that carries the style's accent color.
    static let accentEdgeWidth: CGFloat = 3
    /// Blur radius of the soft shadow that lifts the banner off the content.
    static let shadowRadius: CGFloat = KXSpacing.m
    /// Downward offset of the shadow.
    static let shadowOffset: CGFloat = 6
}

// MARK: - Presentation

/// Where the `kxBanner(isPresented:placement:banner:)` modifier shows its banner.
public enum KXBannerPlacement: String, CaseIterable, Sendable {
    /// The banner floats over the top of the modified view and covers what is underneath while it
    /// is visible. Use it for screen content below the navigation bar.
    case overlay
    /// The banner is stacked above the modified view and pushes it down, so nothing underneath is
    /// covered. Use it around navigation containers (`TabView`, `NavigationStack`), whose bars and
    /// buttons must stay reachable while the banner is shown. The strip behind the banner uses the
    /// page background.
    case inset
}

extension View {
    /// Shows `banner` at the top of this view while `isPresented` is `true`.
    ///
    /// The banner slides in from the top with the standard KARINEX spring (a cross-fade with
    /// Reduce Motion), keeps the standard screen gutter and stays inside the safe area.
    /// A ``KXBanner`` announces itself to VoiceOver when it appears.
    ///
    /// - Parameters:
    ///   - isPresented: Whether the banner is visible.
    ///   - placement: Whether the banner covers the top of the view (``KXBannerPlacement/overlay``,
    ///     the default) or pushes the view down (``KXBannerPlacement/inset``).
    ///   - banner: Builds the banner, typically a ``KXBanner`` (modifiers such as an
    ///     accessibility identifier may be applied). Only called while `isPresented` is `true`.
    public func kxBanner(
        isPresented: Bool,
        placement: KXBannerPlacement = .overlay,
        @ViewBuilder banner: () -> some View
    ) -> some View {
        modifier(KXBannerPresenter(banner: isPresented ? banner() : nil, placement: placement))
    }
}

private struct KXBannerPresenter<Banner: View>: ViewModifier {
    let banner: Banner?
    let placement: KXBannerPlacement

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        switch placement {
        case .overlay:
            content
                .overlay(alignment: .top) {
                    ZStack {
                        presentedBanner(bottomPadding: 0)
                    }
                    .animation(animation, value: banner != nil)
                }
        case .inset:
            // The animation covers the whole stack, so the content moves down together with the
            // banner instead of jumping.
            VStack(spacing: 0) {
                presentedBanner(bottomPadding: KXSpacing.xs)
                content
            }
            .background(KXColor.background.ignoresSafeArea())
            .animation(animation, value: banner != nil)
        }
    }

    @ViewBuilder
    private func presentedBanner(bottomPadding: CGFloat) -> some View {
        if let banner {
            banner
                .padding(.horizontal, KXSpacing.gutter)
                .padding(.top, KXSpacing.xs)
                .padding(.bottom, bottomPadding)
                .transition(kxBannerTransition(reduceMotion: reduceMotion))
        }
    }

    private var animation: Animation {
        KXMotion.animation(.standard, reduceMotion: reduceMotion)
    }
}

/// Slide in from the top edge combined with a fade, or a plain fade with Reduce Motion.
@MainActor
private func kxBannerTransition(reduceMotion: Bool) -> AnyTransition {
    reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity)
}

// MARK: - Previews

private struct KXBannerPreviewGallery: View {
    @State private var isOfflineBannerPresented = true

    var body: some View {
        ScrollView {
            VStack(spacing: KXSpacing.m) {
                KXBanner(.offline)
                KXBanner(.error, action: {})
                KXBanner(.info, message: "Die Lieferung erfolgt per E-Mail.", onDismiss: {})
                KXBanner(.success, message: "In den Warenkorb gelegt.")
                KXButton("Offline-Hinweis umschalten", style: .secondary) {
                    isOfflineBannerPresented.toggle()
                }
            }
            .padding(KXSpacing.gutter)
            .padding(.top, 96)
        }
        .kxScreenBackground()
        .kxBanner(isPresented: isOfflineBannerPresented) {
            KXBanner(.offline, onDismiss: { isOfflineBannerPresented = false })
        }
    }
}

#Preview("KXBanner, light") {
    KXBannerPreviewGallery()
}

#Preview("KXBanner, dark") {
    KXBannerPreviewGallery()
        .preferredColorScheme(.dark)
}

#Preview("KXBanner, accessibility size") {
    KXBannerPreviewGallery()
        .dynamicTypeSize(.accessibility2)
}
