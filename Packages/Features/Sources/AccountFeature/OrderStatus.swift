import BackendKit
import DesignSystem
import Foundation
import ShopifyKit

// MARK: - OrderStatusPill

/// The status shown on an order: one short word with a badge style, derived from Shopify's
/// payment and fulfillment state and, when the backend knows it, the delivery of the keys.
enum OrderStatusPill: String, CaseIterable, Sendable {
    case cancelled
    case refunded
    case delivered
    case shipped
    case paid
    case processing

    /// The pill for `order`; `delivery` comes from the backend and wins for paid orders.
    init(order: CustomerOrder, delivery: DeliveryStatus?) {
        if order.cancelledAt != nil {
            self = .cancelled
        } else if order.financialStatus == .refunded {
            self = .refunded
        } else if delivery == .delivered {
            self = .delivered
        } else if delivery == .shipped {
            self = .shipped
        } else if order.fulfillmentStatus == .fulfilled {
            self = .delivered
        } else if order.financialStatus?.isPaid == true {
            self = .paid
        } else {
            self = .processing
        }
    }

    /// The localized label.
    var title: String {
        switch self {
        case .cancelled: String(localized: "account.order.status.cancelled", bundle: .module)
        case .refunded: String(localized: "account.order.status.refunded", bundle: .module)
        case .delivered: String(localized: "account.order.status.delivered", bundle: .module)
        case .shipped: String(localized: "account.order.status.shipped", bundle: .module)
        case .paid: String(localized: "account.order.status.paid", bundle: .module)
        case .processing: String(localized: "account.order.status.processing", bundle: .module)
        }
    }

    /// The badge style.
    var style: KXBadge.Style {
        switch self {
        case .delivered, .shipped: .success
        case .paid: .accent
        case .cancelled, .refunded, .processing: .neutral
        }
    }
}

// MARK: - OrderTimeline

/// The vertical timeline of an order: Bestellt, Bezahlt, then "Lizenz versendet" for digital
/// orders or "Versendet" for shipped goods (PROMPT.md 6.7).
enum OrderTimeline {
    /// The steps for `order`.
    ///
    /// - Parameters:
    ///   - order: The order.
    ///   - delivery: The backend's delivery state, if known.
    ///   - locale: Formats the order date.
    static func steps(for order: CustomerOrder, delivery: DeliveryStatus?, locale: Locale) -> [KXStepTimeline.Step] {
        let date = order.processedAt.formatted(Date.FormatStyle(date: .long, time: .shortened).locale(locale))
        let ordered = KXStepTimeline.Step(
            title: String(localized: "account.order.timeline.ordered", bundle: .module),
            detail: date,
            state: .done
        )
        let isPaid = order.financialStatus?.isPaid == true
        let isShipment = delivery == .shipped
        let isFulfilled = delivery == .delivered || delivery == .shipped || order.fulfillmentStatus == .fulfilled
            || order.fulfillments.contains(where: \.isSuccessful)
        let paid = KXStepTimeline.Step(
            title: String(localized: "account.order.timeline.paid", bundle: .module),
            state: isPaid || isFulfilled ? .done : .current
        )
        let lastTitle = isShipment
            ? String(localized: "account.order.timeline.shipped", bundle: .module)
            : String(localized: "account.order.timeline.key_sent", bundle: .module)
        let lastDetail = isFulfilled || isShipment ? nil : String(localized: "account.order.timeline.key_sent.detail", bundle: .module)
        let last = KXStepTimeline.Step(
            title: lastTitle,
            detail: lastDetail,
            state: isFulfilled ? .done : (isPaid ? .current : .upcoming)
        )
        return [ordered, paid, last]
    }
}
