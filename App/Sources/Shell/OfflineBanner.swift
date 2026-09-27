import Core
import DesignSystem
import SwiftUI

// MARK: - OfflineBannerPolicy

/// Decides when the offline banner is shown.
enum OfflineBannerPolicy {
    /// Whether the banner is shown for `status`: only when the device is known to be offline.
    /// While the first measurement is pending (`nil`) nothing is shown, so a normal launch never
    /// flashes the banner.
    static func isBannerPresented(for status: NetworkStatus?) -> Bool {
        status == .offline
    }
}

// MARK: - OfflineBannerModifier

/// Shows the design-system offline banner at the top of the modified view while the device has
/// no network path, and hides it again as soon as a path is back.
///
/// The modifier subscribes to `NetworkMonitoring.statusUpdates()` for as long as the view is on
/// screen. The banner slides in with the brand spring (a cross-fade with Reduce Motion) and
/// announces itself to VoiceOver.
struct OfflineBannerModifier: ViewModifier {
    /// The reachability source.
    let monitor: any NetworkMonitoring

    @State private var status: NetworkStatus?

    func body(content: Content) -> some View {
        content
            .kxBanner(isPresented: OfflineBannerPolicy.isBannerPresented(for: status)) {
                KXBanner(.offline)
            }
            .task {
                await observeStatus()
            }
    }

    /// Follows the monitor until the view disappears (the task is then cancelled and the stream
    /// ends) or the monitor finishes its stream.
    private func observeStatus() async {
        for await update in monitor.statusUpdates() {
            status = update
        }
    }
}

extension View {
    /// Overlays the offline banner driven by `monitor`. See ``OfflineBannerModifier``.
    func offlineBanner(monitor: any NetworkMonitoring) -> some View {
        modifier(OfflineBannerModifier(monitor: monitor))
    }
}
