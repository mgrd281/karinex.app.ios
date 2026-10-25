import DesignTokens
import SwiftUI

// MARK: - KXLaunchIntro

/// The opening of the app, the way fashion retail apps open: the logo of the launch screen stays
/// a moment on the page background, then zooms towards the viewer while the cover fades and
/// reveals the app underneath. With Reduce Motion the cover only fades.
///
/// Pass the logo image the launch screen shows (`UILaunchScreen` `UIImageName`), unscaled, so
/// the hand-over from the launch screen has no visible jump: both center it on the whole screen
/// at its natural size. The intro is decorative, hidden from VoiceOver and transparent to
/// touches, so it never blocks the app.
///
/// ```swift
/// .overlay {
///     if showsIntro {
///         KXLaunchIntro(logo: Image("LaunchLogo")) { showsIntro = false }
///     }
/// }
/// ```
public struct KXLaunchIntro: View {
    private let logo: Image
    private let onFinish: @MainActor () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isZoomed = false
    @State private var isFaded = false

    /// Creates the intro.
    ///
    /// - Parameters:
    ///   - logo: The logo of the launch screen.
    ///   - onFinish: Called when the intro has faded out; remove the intro then.
    public init(logo: Image, onFinish: @escaping @MainActor () -> Void) {
        self.logo = logo
        self.onFinish = onFinish
    }

    public var body: some View {
        ZStack {
            KXColor.background
            logo
                .scaleEffect(isZoomed ? CGFloat(MotionToken.launchZoomScale) : 1)
        }
        .ignoresSafeArea()
        .opacity(isFaded ? 0 : 1)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task {
            await play()
        }
    }

    /// Holds, then zooms and fades (or only fades with Reduce Motion), then reports the end.
    private func play() async {
        try? await Task.sleep(for: .seconds(MotionToken.launchHoldDuration))
        if reduceMotion {
            withAnimation(KXMotion.animation(.fade, reduceMotion: true)) {
                isFaded = true
            }
            try? await Task.sleep(for: .seconds(MotionToken.fadeDuration))
        } else {
            let zoom = MotionToken.launchZoomDuration
            withAnimation(.easeIn(duration: zoom)) {
                isZoomed = true
            }
            // The cover fades during the second half of the zoom, when the logo fills the screen.
            withAnimation(.easeIn(duration: zoom / 2).delay(zoom / 2)) {
                isFaded = true
            }
            try? await Task.sleep(for: .seconds(zoom))
        }
        onFinish()
    }
}
