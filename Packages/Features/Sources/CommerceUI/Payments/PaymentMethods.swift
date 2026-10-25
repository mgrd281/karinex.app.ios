import DesignSystem
import Foundation
import Observation
import ShopifyKit
import SwiftUI

// MARK: - PaymentMethod

/// A payment method the app shows with its real acceptance mark (cart, product page).
///
/// Which methods appear follows PROMPT.md section 2 (Apple Pay, credit and debit cards, Klarna,
/// all inside Shopify checkout) and Shopify's own payment settings: Apple Pay when Shopify lists
/// it as a wallet, and the card brands Shopify reports as accepted. When Shopify reports
/// nothing (previews, a failed request) the app shows Apple Pay, a neutral card symbol and
/// Klarna, the business facts without naming a card brand. Klarna is not part of Shopify's
/// payment settings and always appears.
public enum PaymentMethod: String, CaseIterable, Sendable, Hashable, Identifiable {
    /// Apple Pay.
    case applePay
    /// Visa.
    case visa
    /// Mastercard.
    case mastercard
    /// American Express.
    case americanExpress
    /// Discover.
    case discover
    /// Diners Club.
    case dinersClub
    /// JCB.
    case jcb
    /// A credit or debit card of a brand Shopify did not name: a neutral card symbol.
    case card
    /// Klarna.
    case klarna

    /// Stable identity, also used in accessibility identifiers (`payment.method.visa`).
    public var id: String {
        rawValue
    }

    /// The methods to show for Shopify's `settings`, in display order: Apple Pay, the card
    /// brands in Shopify's order (or the neutral card), Klarna.
    public static func methods(for settings: PaymentSettings) -> [PaymentMethod] {
        let isReported = !settings.acceptedCardBrands.isEmpty || !settings.supportedDigitalWallets.isEmpty
        var methods: [PaymentMethod] = []
        if !isReported || settings.supportedDigitalWallets.contains(.applePay) {
            methods.append(.applePay)
        }
        let brands = settings.acceptedCardBrands.map(PaymentMethod.init(cardBrand:))
        methods += brands.isEmpty ? [.card] : brands
        methods.append(.klarna)
        return methods
    }

    /// The methods shown before Shopify answered: the business facts.
    public static let fallback = methods(for: .empty)

    /// The method of a card brand.
    init(cardBrand: CardBrand) {
        switch cardBrand {
        case .visa: self = .visa
        case .mastercard: self = .mastercard
        case .americanExpress: self = .americanExpress
        case .discover: self = .discover
        case .dinersClub: self = .dinersClub
        case .jcb: self = .jcb
        }
    }

    /// The asset of the acceptance mark in `PaymentMethods.xcassets`, or `nil` for the
    /// neutral card symbol.
    var assetName: String? {
        switch self {
        case .applePay: "payment-apple-pay"
        case .visa: "payment-visa"
        case .mastercard: "payment-mastercard"
        case .americanExpress: "payment-american-express"
        case .discover: "payment-discover"
        case .dinersClub: "payment-diners-club"
        case .jcb: "payment-jcb"
        case .card: nil
        case .klarna: "payment-klarna"
        }
    }

    /// The name VoiceOver reads. Brand names are never translated; the neutral card is.
    public var spokenName: String {
        switch self {
        case .applePay: "Apple Pay"
        case .visa: "Visa"
        case .mastercard: "Mastercard"
        case .americanExpress: "American Express"
        case .discover: "Discover"
        case .dinersClub: "Diners Club"
        case .jcb: "JCB"
        case .card: String(localized: "commerce.payment.card", bundle: .module)
        case .klarna: "Klarna"
        }
    }
}

// MARK: - PaymentMethodsStore

/// The payment methods of the store, loaded from Shopify once per launch and shared by the cart
/// and the product page. Until Shopify answers, and when it cannot, ``methods`` holds the
/// business facts (``PaymentMethod/fallback``).
@MainActor
@Observable
public final class PaymentMethodsStore {
    /// The methods to show, in display order.
    public private(set) var methods: [PaymentMethod] = PaymentMethod.fallback

    @ObservationIgnored private let catalog: any CatalogRepository
    @ObservationIgnored private var hasLoaded = false

    /// Creates the store.
    ///
    /// - Parameter catalog: Loads Shopify's payment settings.
    public init(catalog: any CatalogRepository) {
        self.catalog = catalog
    }

    /// Loads the methods from Shopify unless that already succeeded. A failure keeps the
    /// current methods and is retried on the next call.
    public func loadIfNeeded() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        do {
            methods = try await PaymentMethod.methods(for: catalog.paymentSettings())
        } catch {
            hasLoaded = false
        }
    }
}

// MARK: - PaymentMethodsRow

/// The acceptance marks of the store's payment methods (the real Apple Pay, card and Klarna
/// marks the web shop shows), in one row, or two rows when one does not fit. The marks grow a
/// little with Dynamic Type. VoiceOver reads the row as one element: the title and the names
/// of the methods.
///
/// ```swift
/// PaymentMethodsRow(methods: paymentMethods?.methods ?? PaymentMethod.fallback)
/// ```
public struct PaymentMethodsRow: View {
    private let methods: [PaymentMethod]
    private let title: String?

    @ScaledMetric(relativeTo: .body) private var scaledHeight: CGFloat = 24

    /// Creates the row.
    ///
    /// - Parameters:
    ///   - methods: The methods, in display order.
    ///   - title: An already-localized title above the marks, e.g. "Zahlungsarten"; `nil`
    ///     shows "Zahlungsarten".
    public init(methods: [PaymentMethod], title: String? = nil) {
        self.methods = methods
        self.title = title
    }

    /// The height of one mark, capped so the marks stay a row of small cards.
    private var markHeight: CGFloat {
        min(scaledHeight, 40)
    }

    public var body: some View {
        let heading = title ?? String(localized: "commerce.payment.title", bundle: .module)
        VStack(alignment: .leading, spacing: KXSpacing.xs) {
            Text(heading)
                .kxFont(.eyebrow)
                .foregroundStyle(KXColor.textSecondary)
            ViewThatFits(in: .horizontal) {
                marks(methods)
                VStack(alignment: .leading, spacing: KXSpacing.xs) {
                    let split = (methods.count + 1) / 2
                    marks(Array(methods.prefix(split)))
                    marks(Array(methods.dropFirst(split)))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(heading))
        .accessibilityValue(Text(verbatim: methods.map(\.spokenName).joined(separator: ", ")))
        .accessibilityIdentifier("payment.methods")
    }

    private func marks(_ methods: [PaymentMethod]) -> some View {
        HStack(spacing: KXSpacing.xs) {
            ForEach(methods) { method in
                PaymentMark(method: method, height: markHeight)
            }
        }
    }
}

// MARK: - PaymentMark

/// One acceptance mark on a 38 by 24 card, or the neutral card symbol for ``PaymentMethod/card``.
private struct PaymentMark: View {
    let method: PaymentMethod
    let height: CGFloat

    var body: some View {
        Group {
            if let assetName = method.assetName {
                Image(assetName, bundle: .module)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                let shape = RoundedRectangle(cornerRadius: height / 8, style: .continuous)
                shape
                    .fill(KXColor.background)
                    .overlay {
                        shape.strokeBorder(KXColor.divider, lineWidth: KXBorder.hairline)
                    }
                    .overlay {
                        Image(systemName: "creditcard")
                            .resizable()
                            .scaledToFit()
                            .foregroundStyle(KXColor.iconSecondary)
                            .padding(height / 5)
                    }
            }
        }
        .frame(width: height * 38 / 24, height: height)
        .accessibilityIdentifier("payment.method.\(method.id)")
    }
}
