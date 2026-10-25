import CommerceUI
import Foundation

// MARK: - CheckoutFailure

/// A failure reported by Shopify checkout, in the app's own `Sendable` form.
public struct CheckoutFailure: Sendable, Hashable {
    /// What failed.
    public enum Kind: Sendable, Hashable {
        /// The checkout URL expired or the cart was completed; a fresh URL is needed.
        case expired
        /// Checkout is unavailable (a server or client error of checkout).
        case unavailable
        /// The store's checkout configuration does not allow the checkout sheet.
        case configuration
        /// An internal error of Checkout Kit.
        case sdk
    }

    /// What failed.
    public let kind: Kind
    /// Whether Shopify marks the failure as recoverable, i.e. trying again may succeed.
    public let isRecoverable: Bool

    /// Creates a failure.
    public init(kind: Kind, isRecoverable: Bool) {
        self.kind = kind
        self.isRecoverable = isRecoverable
    }

    /// Whether the customer is offered "Erneut versuchen", which fetches a fresh checkout URL:
    /// for recoverable failures and for expired checkouts.
    public var canRetry: Bool {
        isRecoverable || kind == .expired
    }
}

// MARK: - CheckoutAlert

/// The error shown after the checkout could not be opened or failed, with "Erneut versuchen"
/// when trying again makes sense.
struct CheckoutAlert: Sendable, Hashable, Identifiable {
    /// A running number, so two alerts in a row are two alerts.
    let id: Int
    /// The localized title.
    let title: String
    /// The localized explanation.
    let message: String
    /// Whether "Erneut versuchen" is offered.
    let canRetry: Bool

    /// The alert for a failure of Shopify checkout.
    init(id: Int, failure: CheckoutFailure) {
        self.id = id
        title = String(localized: "checkout.error.title", bundle: .module)
        message = failure.kind == .expired
            ? String(localized: "checkout.error.expired", bundle: .module)
            : String(localized: "checkout.error.message", bundle: .module)
        canRetry = failure.canRetry
    }

    /// The alert for a failure while preparing the checkout (reading the cart).
    init(id: Int, error: UserFacingError) {
        self.id = id
        title = error.title
        message = error.message
        canRetry = error.isRetryable
    }
}
