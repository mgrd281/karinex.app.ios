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
/// it cross-fades instead. The `kxBanner(isPresented:banner:)` modifier does all of this and
/// places the banner at the top of the modified view:
///
/// ```swift
/// RootView()
///     .kxBanner(isPresented: networkStatus == .offline) {
///         KXBanner(.offline)
///     }
/// ```
///
/// Without a `message` each style uses its design-system default text, e.g. for
/// ``Style/offline`` "Keine Internetverbindung. Bitte prüfen Sie Ihre Verbindung.".
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
                .font(.system(.body, weight: .semibold))
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
                        .font(.system(.footnote, weight: .semibold))
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
        .frame(minHeight: 56)
        .background {
            ZStack(alignment: .leading) {
                shape.fill(KXColor.surfaceElevated)
                Rectangle()
                    .fill(accentColor)
                    .frame(width: 3)
            }
            .clipShape(shape)
        }
        .overlay {
            shape.strokeBorder(KXColor.hairline, lineWidth: 1 / max(displayScale, 1))
        }
        .shadow(color: KXColor.scrim.opacity(0.25), radius: 16, x: 0, y: 6)
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

// MARK: - Presentation

extension View {
    /// Shows `banner` at the top of this view while `isPresented` is `true`.
    ///
    /// The banner slides in from the top with the standard KARINEX spring (a cross-fade with
    /// Reduce Motion), keeps the standard screen gutter and stays inside the safe area.
    /// The banner announces itself to VoiceOver when it appears.
    ///
    /// - Parameters:
    ///   - isPresented: Whether the banner is visible.
    ///   - banner: Builds the banner. Only called while `isPresented` is `true`.
    public func kxBanner(isPresented: Bool, banner: () -> KXBanner) -> some View {
        modifier(KXBannerPresenter(banner: isPresented ? banner() : nil))
    }
}

private struct KXBannerPresenter: ViewModifier {
    let banner: KXBanner?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                ZStack {
                    if let banner {
                        banner
                            .padding(.horizontal, KXSpacing.gutter)
                            .padding(.top, KXSpacing.xs)
                            .transition(kxBannerTransition(reduceMotion: reduceMotion))
                    }
                }
                .animation(KXMotion.animation(.standard, reduceMotion: reduceMotion), value: banner != nil)
            }
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
