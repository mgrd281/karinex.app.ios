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
/// appear, as in the web shop. Rechnung and Vorkasse have no brand mark of their own; the app
/// ships its own marks for them (a document with a euro sign, a cheque with a pen), drawn like the others.
/// When Shopify reports nothing (previews, a failed request) the app shows Apple Pay, a neutral
/// card symbol and those fixed methods, without naming a card brand.
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
    /// Purchase on invoice ("Rechnung"): the app's own mark, a document with a euro sign.
    case invoice
    /// Payment in advance by bank transfer ("Vorkasse"): the app's own mark, a cheque with a pen.
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
        case .invoice: "payment-invoice"
        case .prepayment: "payment-prepayment"
        case .card: nil
        }
    }

    /// The SF Symbol on the plain card of a method without a mark (the neutral card), `nil` for
    /// the others.
    var plainCardSymbol: String? {
        self == .card ? "creditcard" : nil
    }

    /// The name VoiceOver reads. Brand names are never
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
/// centered below the title on one line (``PaymentMarksLine``, owner request 28.10.2026): the
/// marks keep their 38 by 24 shape and shrink together when the line would be wider than the
/// screen. They grow a little with Dynamic Type. VoiceOver reads the row as one element: the
/// title and the names of the methods.
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

    /// The widest a mark gets: 38 by 24 scaled with Dynamic Type, capped at a height of 40.
    private var maximumMarkWidth: CGFloat {
        min(scaledHeight, 40) * PaymentMarksLine.aspectRatio
    }

    public var body: some View {
        let heading = title ?? String(localized: "commerce.payment.title", bundle: .module)
        VStack(spacing: KXSpacing.xs) {
            Text(heading)
                .kxFont(.eyebrow)
                .foregroundStyle(KXColor.textSecondary)
                .multilineTextAlignment(.center)
            PaymentMarksLine(maximumMarkWidth: maximumMarkWidth, spacing: KXSpacing.xxs + 2) {
                ForEach(methods) { method in
                    PaymentMark(method: method)
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

// MARK: - PaymentMarksLine

/// Lays the payment marks out on one centered line. Every mark has the 38 by 24 shape of the
/// acceptance marks; it is `maximumMarkWidth` wide unless the line would not fit, then all marks
/// shrink by the same amount (``markWidth(available:count:maximum:spacing:)``).
struct PaymentMarksLine: Layout {
    /// Width divided by height of an acceptance mark.
    static let aspectRatio: CGFloat = 38 / 24

    let maximumMarkWidth: CGFloat
    let spacing: CGFloat

    /// The width of each mark for `count` marks in `available` points: the maximum, or less so
    /// that all of them fit on one line. An unknown width keeps the maximum.
    static func markWidth(available: CGFloat?, count: Int, maximum: CGFloat, spacing: CGFloat) -> CGFloat {
        guard count > 0 else { return 0 }
        guard let available, available.isFinite else { return maximum }
        let fitting = (available - spacing * CGFloat(count - 1)) / CGFloat(count)
        return max(0, min(maximum, fitting))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let width = Self.markWidth(available: proposal.width, count: subviews.count, maximum: maximumMarkWidth, spacing: spacing)
        return CGSize(width: lineWidth(markWidth: width, count: subviews.count), height: width / Self.aspectRatio)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        let width = Self.markWidth(available: bounds.width, count: subviews.count, maximum: maximumMarkWidth, spacing: spacing)
        let size = ProposedViewSize(width: width, height: width / Self.aspectRatio)
        var x = bounds.midX - lineWidth(markWidth: width, count: subviews.count) / 2
        for subview in subviews {
            subview.place(at: CGPoint(x: x, y: bounds.midY), anchor: .leading, proposal: size)
            x += width + spacing
        }
    }

    private func lineWidth(markWidth: CGFloat, count: Int) -> CGFloat {
        markWidth * CGFloat(count) + spacing * CGFloat(max(count - 1, 0))
    }
}

// MARK: - PaymentMark

/// One acceptance mark, filling the 38 by 24 size ``PaymentMarksLine`` gives it. The neutral
/// card (a brand Shopify did not name) is a plain white card with a card symbol; it stays white
/// in dark mode, like the brand marks.
private struct PaymentMark: View {
    let method: PaymentMethod

    var body: some View {
        Group {
            if let assetName = method.assetName {
                Image(assetName, bundle: .module)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                plainCard
            }
        }
        .accessibilityIdentifier("payment.method.\(method.id)")
    }

    private var plainCard: some View {
        let shape = RoundedRectangle(cornerRadius: 3, style: .continuous)
        return shape
            .fill(KXColor.background)
            .overlay {
                shape.strokeBorder(KXColor.divider, lineWidth: KXBorder.hairline)
            }
            .overlay {
                if let symbol = method.plainCardSymbol {
                    Image(systemName: symbol)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(KXColor.textSecondary)
                        .padding(.vertical, 5)
                }
            }
            .environment(\.colorScheme, .light)
    }
}
