import ActivityKit
import Foundation

// MARK: - LicenseDeliveryAttributes

/// The "Lizenz wird zugestellt" Live Activity, shared by the app (which starts and ends it)
/// and the widget extension (which draws it). It carries no key, price or personal data:
/// only the order reference and the delivery phase.
struct LicenseDeliveryAttributes: ActivityAttributes {
    /// The changing part.
    struct ContentState: Codable, Hashable {
        /// Where the delivery stands.
        var phase: Phase
    }

    /// The delivery phases.
    enum Phase: String, Codable, Hashable {
        /// Paid; the fulfillment service is preparing the key.
        case preparing
        /// The key was delivered by e-mail and is in the license vault.
        case delivered
    }

    /// The order reference from Shopify checkout, used to match the delivery.
    let orderReference: String
}
