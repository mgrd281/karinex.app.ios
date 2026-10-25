import DesignSystem
import Foundation
@preconcurrency import ShopifyCheckoutSheetKit
import UIKit

// MARK: - CheckoutConfiguration

/// The global Checkout Kit setup of the app: KARINEX branding, the color scheme following the
/// system, preloading on and confetti off.
///
/// Call ``configure()`` once at launch (the App target does it in its composition root) and
/// hand ``preloader`` to `CartStore.checkoutPreloader`, so the checkout of the current cart is
/// preloaded after every cart change. This file and the rest of `CheckoutFeature` are the only
/// places that import Checkout Kit.
@MainActor
public enum CheckoutConfiguration {
    /// Whether ``configure()`` already ran in this process.
    public private(set) static var isConfigured = false

    /// Sets `ShopifyCheckoutSheetKit.configuration`: color scheme `.automatic`, brand tint,
    /// KARINEX background, preloading enabled, confetti disabled and the localized sheet title
    /// ("Kasse"). Later calls do nothing.
    public static func configure() {
        guard !isConfigured else { return }
        isConfigured = true
        ShopifyCheckoutSheetKit.configure { configuration in
            configuration.colorScheme = .automatic
            configuration.tintColor = tintColor
            configuration.backgroundColor = backgroundColor
            configuration.closeButtonTintColor = tintColor
            configuration.preloading.enabled = true
            configuration.confetti.enabled = false
            configuration.title = title
        }
    }

    /// Preloads the checkout of `url` with Checkout Kit. Assign it to
    /// `CartStore.checkoutPreloader`; the store calls it debounced after every cart change.
    public static let preloader: @MainActor (URL) -> Void = { url in
        ShopifyCheckoutSheetKit.preload(checkout: url)
    }

    /// The localized title of the checkout sheet ("Kasse").
    static var title: String {
        String(localized: "checkout.title", bundle: .module)
    }

    /// The tint of checkout buttons and the progress bar: the brand color (black, white in dark
    /// mode through the token).
    static var tintColor: UIColor {
        KXColor.uiColor(.brand)
    }

    /// The background behind the checkout web view: the KARINEX page background.
    static var backgroundColor: UIColor {
        KXColor.uiColor(.background)
    }
}

// MARK: - Boundary conversions

extension CompletedOrder {
    /// Converts Checkout Kit's completion event at the module boundary. Only the order
    /// identifier, the presence of an e-mail address and the formatted total are kept.
    init(event: CheckoutCompletedEvent, locale: Locale) {
        let details = event.orderDetails
        self.init(
            id: details.id,
            email: details.email,
            totalAmount: details.cart.price.total?.amount,
            currencyCode: details.cart.price.total?.currencyCode,
            locale: locale
        )
    }
}

extension CheckoutFailure {
    /// Converts Checkout Kit's error at the module boundary. Shopify's messages are not kept:
    /// they are technical and may contain details of the cart.
    init(error: CheckoutError) {
        let kind: Kind = switch error {
        case .checkoutExpired:
            .expired
        case .checkoutUnavailable:
            .unavailable
        case .configurationError:
            .configuration
        case .sdkError:
            .sdk
        }
        self.init(kind: kind, isRecoverable: error.isRecoverable)
    }
}
