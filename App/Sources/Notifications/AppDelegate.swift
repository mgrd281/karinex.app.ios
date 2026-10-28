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
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        if let payload = PushPayload(userInfo: notification.request.content.userInfo) {
            await receive(payload, opened: false)
        }
        return [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let payload = PushPayload(userInfo: response.notification.request.content.userInfo) else { return }
        await receive(payload, opened: true)
    }

    @MainActor
    private func receive(_ payload: PushPayload, opened: Bool) async {
        if opened {
            await pushCoordinator?.didOpen(payload)
        } else {
            await pushCoordinator?.didReceive(payload)
        }
    }
}

// MARK: - PushAlertKeys

/// The keys the KARINEX backend sends as `title-loc-key` and `loc-key` in notifications of
/// "Neuigkeiten" (back in stock, order paid, keys delivered). iOS looks them up in the App's
/// String Catalog when the notification arrives, so the text appears in the customer's language;
/// `loc-args` fill the `%@` (product name or order number). The backend contract lists the same
/// keys (docs/BFF_CONTRACT.md, "Push payloads").
enum PushAlertKeys {
    /// Title and text of each notification kind, in the order title, text.
    static let all: [(title: String, body: String)] = [
        ("push.restock.title", "push.restock.body"),
        ("push.order.paid.title", "push.order.paid.body"),
        ("push.license.delivered.title", "push.license.delivered.body"),
    ]
}
