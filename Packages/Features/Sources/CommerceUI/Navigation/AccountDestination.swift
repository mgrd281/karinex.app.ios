import Foundation
import ShopifyKit

// MARK: - AccountDestination

/// A screen of the Konto tab or one reachable from it. The account features (orders, licenses,
/// support, legal texts, settings) do not import each other; they ask for these destinations
/// through `CommerceRoute.account(_:)` and the App maps them to screens.
public enum AccountDestination: Hashable, Sendable {
    /// The Konto tab itself.
    case overview
    /// The order list.
    case orders
    /// One order.
    case order(id: ShopifyID)
    /// "Rechnungen": every invoice of the customer as a PDF.
    case invoices
    /// The license vault, optionally limited to one order (numeric Shopify order ID).
    case licenses(orderID: String?)
    /// "Treueprogramm": the membership card, reward points and discount codes.
    case loyalty
    /// "Persönliche Daten": the customer's name, e-mail address and addresses, and the way to
    /// delete the account.
    case profile
    /// The wishlist kept on this device (no login needed).
    case wishlist
    /// Help and support, optionally about an order (its name, e.g. `#1042`).
    case support(orderName: String?)
    /// The list of legal texts.
    case legal
    /// One legal text.
    case legalDocument(LegalDocumentKind)
    /// The settings.
    case settings
    /// The account deletion flow.
    case deleteAccount
}

// MARK: - LegalDocumentKind

/// The legal texts the app shows, all loaded from Shopify (PROMPT.md 6.9).
public enum LegalDocumentKind: String, CaseIterable, Hashable, Sendable, Identifiable {
    /// Impressum: the online store page `rechtliche-hinweise` (docs/STORE_AUDIT.md).
    case imprint
    /// AGB: the shop policy `termsOfService`.
    case terms
    /// Datenschutzerklärung: the shop policy `privacyPolicy`.
    case privacy
    /// Widerrufsbelehrung: the online store page `widerrufsrecht`, else the refund policy.
    case withdrawal
    /// Versand und Lieferung: the shop policy `shippingPolicy`.
    case shipping

    /// The raw value.
    public var id: String {
        rawValue
    }

    /// The online store page that holds the text, if it is a page.
    public var pageHandle: String? {
        switch self {
        case .imprint: "rechtliche-hinweise"
        case .withdrawal: "widerrufsrecht"
        case .terms, .privacy, .shipping: nil
        }
    }

    /// The localized title shown in lists and as the screen title until the text has loaded.
    public var title: String {
        switch self {
        case .imprint: String(localized: "commerce.legal.imprint", bundle: .module)
        case .terms: String(localized: "commerce.legal.terms", bundle: .module)
        case .privacy: String(localized: "commerce.legal.privacy", bundle: .module)
        case .withdrawal: String(localized: "commerce.legal.withdrawal", bundle: .module)
        case .shipping: String(localized: "commerce.legal.shipping", bundle: .module)
        }
    }

    /// A decorative SF Symbol.
    public var systemImage: String {
        switch self {
        case .imprint: "building.2"
        case .terms: "doc.text"
        case .privacy: "hand.raised"
        case .withdrawal: "arrow.uturn.backward.circle"
        case .shipping: "shippingbox"
        }
    }
}
