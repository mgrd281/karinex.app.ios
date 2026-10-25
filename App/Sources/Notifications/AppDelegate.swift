import CommerceUI
import UIKit
import UserNotifications

// MARK: - AppDelegate

/// Receives the APNs callbacks and notification taps and hands them to the
/// `PushRegistrationCoordinator`. It registers for nothing on its own: registration starts only
/// from the coordinator, after consent.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    /// Set by `KarinexApp` once the container exists.
    @MainActor var pushCoordinator: PushRegistrationCoordinator?

    func application(
        _: UIApplication,
        didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in
            await pushCoordinator?.didRegister(deviceToken: deviceToken)
        }
    }

    func application(_: UIApplication, didFailToRegisterForRemoteNotificationsWithError _: any Error) {
        Task { @MainActor in
            pushCoordinator?.didFailToRegister()
        }
    }

    // MARK: UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let payload = PushPayload(userInfo: response.notification.request.content.userInfo) else { return }
        await MainActor.run {
            pushCoordinator?.didOpen(payload)
        }
    }
}
