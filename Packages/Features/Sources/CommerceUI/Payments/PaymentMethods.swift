import DesignSystem
import Foundation
import Observation
import ShopifyKit
import SwiftUI

// MARK: - PaymentMethod

/// A payment method the app shows with its real acceptance mark (cart, product page).
///
/// Which methods appear follows PROMPT.md section 2 (all inside Shopify checkout) and Shopify's
/// own payment settings: Apple Pay and Google Pay when Shopify lists them as wallets, and the
/// card brands Shopify reports as accepted. UnionPay (not part of the card brands of Storefront
/// API 2026-10), Klarna, Rechnung and Vorkasse are not in Shopify's payment settings and always
/// appear, as in the web shop. When Shopify reports nothing (previews, a failed request) the
/// app shows Apple Pay, a neutral card symbol and those fixed methods, without naming a card
/// brand.
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
    /// UnionPay.
    case unionPay
    /// Google Pay.
    case googlePay
    /// Klarna.
    case klarna
    /// Purchase on invoice ("Rechnung"): no brand mark, the name on a plain card.
    case invoice
    /// Payment in advance by bank transfer ("Vorkasse"): no brand mark, the name on a plain
    /// card.
    case prepayment

    /// Stable identity, also used in accessibility identifiers (`payment.method.visa`).
    public var id: String {
        rawValue
    }

    /// The card brand Shopify's payment settings cannot report (it is no `CardBrand` of
    /// Storefront API 2026-10), shown after the reported brands: UnionPay.
    static let fixedCard = PaymentMethod.unionPay
    /// The methods outside Shopify's payment settings, shown after the wallets: Klarna,
    /// Rechnung and Vorkasse.
    static let fixedAfterWallets: [PaymentMethod] = [.klarna, .invoice, .prepayment]

    /// The methods to show for Shopify's `settings`, in display order: Apple Pay, the card
    /// brands in Shopify's order (or the neutral card) and UnionPay, Google Pay, then Klarna,
    /// Rechnung and Vorkasse.
    public static func methods(for settings: PaymentSettings) -> [PaymentMethod] {
        let wallets = settings.supportedDigitalWallets
        let isReported = !settings.acceptedCardBrands.isEmpty || !wallets.isEmpty
        var methods: [PaymentMethod] = []
        if !isReported || wallets.contains(.applePay) {
            methods.append(.applePay)
        }
        let brands = settings.acceptedCardBrands.map(PaymentMethod.init(cardBrand:))
        methods += brands.isEmpty ? [.card] : brands
        methods.append(fixedCard)
        if wallets.contains(.googlePay) {
            methods.append(.googlePay)
        }
        methods += fixedAfterWallets
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

    /// The asset of the acceptance mark in `PaymentMethods.xcassets`, or `nil` for the methods
    /// drawn on a plain card (``plainCardSymbol``).
    var assetName: String? {
        switch self {
        case .applePay: "payment-apple-pay"
        case .visa: "payment-visa"
        case .mastercard: "payment-mastercard"
        case .americanExpress: "payment-american-express"
        case .discover: "payment-discover"
        case .dinersClub: "payment-diners-club"
        case .jcb: "payment-jcb"
        case .unionPay: "payment-unionpay"
        case .googlePay: "payment-google-pay"
        case .klarna: "payment-klarna"
        case .card, .invoice, .prepayment: nil
        }
    }

    /// The SF Symbol on the plain card of a method without a brand mark, `nil` for the others.
    var plainCardSymbol: String? {
        switch self {
        case .card: "creditcard"
        case .invoice: "doc.text"
        case .prepayment: "building.columns"
        default: nil
        }
    }

    /// Whether the plain card also shows the method's name: Rechnung and Vorkasse, which no
    /// symbol names on its own.
    var showsNameOnPlainCard: Bool {
        self == .invoice || self == .prepayment
    }

    /// The name VoiceOver reads, also the label of Rechnung and Vorkasse. Brand names are never
    /// translated; the neutral card, Rechnung and Vorkasse are.
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
        case .unionPay: "UnionPay"
        case .googlePay: "Google Pay"
        case .klarna: "Klarna"
        case .invoice: String(localized: "commerce.payment.invoice", bundle: .module)
        case .prepayment: String(localized: "commerce.payment.prepayment", bundle: .module)
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

/// The acceptance marks of the store's payment methods (the real marks the web shop shows),
/// centered below the title in rows that wrap like a paragraph (``KXFlowLayout``), as below the
/// buy button of the web shop. The marks grow a little with Dynamic Type. VoiceOver reads the
/// row as one element: the title and the names of the methods.
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
        VStack(spacing: KXSpacing.xs) {
            Text(heading)
                .kxFont(.eyebrow)
                .foregroundStyle(KXColor.textSecondary)
                .multilineTextAlignment(.center)
            KXFlowLayout(alignment: .center, spacing: KXSpacing.xs, lineSpacing: KXSpacing.xs) {
                ForEach(methods) { method in
                    PaymentMark(method: method, height: markHeight)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(heading))
        .accessibilityValue(Text(verbatim: methods.map(\.spokenName).joined(separator: ", ")))
        .accessibilityIdentifier("payment.methods")
    }
}

// MARK: - PaymentMark

/// One acceptance mark on a 38 by 24 card. Methods without a brand mark get a plain white card
/// in the same size with their symbol, Rechnung and Vorkasse also with their name in capitals,
/// so the card grows wider. The plain cards stay white in dark mode, like the brand marks.
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
                    .frame(width: markWidth, height: height)
            } else {
                plainCard
            }
        }
        .accessibilityIdentifier("payment.method.\(method.id)")
    }

    /// The width of a brand mark.
    private var markWidth: CGFloat {
        height * 38 / 24
    }

    private var plainCard: some View {
        let shape = RoundedRectangle(cornerRadius: height / 8, style: .continuous)
        return HStack(spacing: height / 6) {
            if let symbol = method.plainCardSymbol {
                Image(systemName: symbol)
                    .resizable()
                    .scaledToFit()
                    .frame(width: height / 2, height: height / 2)
            }
            if method.showsNameOnPlainCard {
                Text(method.spokenName)
                    .kxFont(.eyebrow)
                    .lineLimit(1)
                    .fixedSize()
                    // Grows with the card, which stops growing at a height of 40 points.
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            }
        }
        .foregroundStyle(KXColor.textSecondary)
        .padding(.horizontal, method.showsNameOnPlainCard ? height / 3 : 0)
        .frame(minWidth: markWidth, minHeight: height, maxHeight: height)
        .background(KXColor.background, in: shape)
        .overlay {
            shape.strokeBorder(KXColor.divider, lineWidth: KXBorder.hairline)
        }
        .environment(\.colorScheme, .light)
    }
}
