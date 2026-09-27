import Foundation
import UIKit
import UniformTypeIdentifiers

// MARK: - KXClipboard

/// Copies sensitive text, such as license keys, to the pasteboard so that it stays on this
/// device and disappears on its own.
///
/// Items are written with `UIPasteboard.OptionsKey.localOnly` (never synced to other devices
/// through Universal Clipboard) and `UIPasteboard.OptionsKey.expirationDate` (removed by the
/// system after the lifetime, two minutes by default). The copied value is never logged.
///
/// ```swift
/// KXClipboard.copySensitive(licenseKey)
/// ```
@MainActor
public enum KXClipboard {
    /// The default lifetime of copied sensitive text: two minutes.
    public nonisolated static let defaultExpiration: TimeInterval = 120

    /// Writes `string` as plain text to the general pasteboard, local to this device and
    /// expiring after `expiresAfter` seconds.
    ///
    /// - Parameters:
    ///   - string: The sensitive text, e.g. a license key.
    ///   - expiresAfter: Lifetime in seconds. Defaults to 120 (``defaultExpiration``). Values
    ///     below one second are raised to one second; non-finite values use the default.
    public static func copySensitive(_ string: String, expiresAfter: TimeInterval = 120) {
        copySensitive(string, expiresAfter: expiresAfter, to: UIPasteboard.general)
    }

    /// Writes `string` as plain text to `pasteboard`, local to this device and expiring after
    /// `expiresAfter` seconds. Use a named pasteboard in tests.
    ///
    /// - Parameters:
    ///   - string: The sensitive text, e.g. a license key.
    ///   - expiresAfter: Lifetime in seconds. Defaults to 120 (``defaultExpiration``).
    ///   - pasteboard: The pasteboard to write to.
    public static func copySensitive(_ string: String, expiresAfter: TimeInterval = 120, to pasteboard: UIPasteboard) {
        pasteboard.setItems(
            [[UTType.plainText.identifier: string]],
            options: sensitiveOptions(expiresAfter: expiresAfter, now: Date())
        )
    }

    /// The pasteboard options used for sensitive items: local only, expiring at
    /// `now + effectiveLifetime(expiresAfter)`.
    ///
    /// - Parameters:
    ///   - expiresAfter: Requested lifetime in seconds.
    ///   - now: The reference date the lifetime starts from.
    public static func sensitiveOptions(expiresAfter: TimeInterval, now: Date) -> [UIPasteboard.OptionsKey: Any] {
        [
            .localOnly: true,
            .expirationDate: now.addingTimeInterval(effectiveLifetime(expiresAfter)),
        ]
    }

    /// The lifetime actually applied for a requested one: at least one second, and
    /// ``defaultExpiration`` for NaN or infinite values.
    public nonisolated static func effectiveLifetime(_ requested: TimeInterval) -> TimeInterval {
        guard requested.isFinite else { return defaultExpiration }
        return max(1, requested)
    }
}
