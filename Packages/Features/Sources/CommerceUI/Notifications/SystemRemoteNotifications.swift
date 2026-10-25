import UIKit
import UserNotifications

// MARK: - SystemRemoteNotifications

/// ``RemoteNotificationRegistering`` with `UNUserNotificationCenter` and `UIApplication`.
@MainActor
public final class SystemRemoteNotifications: RemoteNotificationRegistering {
    /// Creates the registrar.
    public init() {}

    public func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            return false
        }
    }

    public func isAuthorized() async -> Bool {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        return status == .authorized || status == .provisional || status == .ephemeral
    }

    public func register() {
        UIApplication.shared.registerForRemoteNotifications()
    }

    public func unregister() {
        UIApplication.shared.unregisterForRemoteNotifications()
    }
}
