import Foundation

// MARK: - HomeTrustFact

/// The four facts of the trust strip on the Start tab (PROMPT.md section 6.1), in display order.
///
/// The texts are fixed business facts (PROMPT.md section 2), not product data. The money-back
/// promise carries a footnote marker and opens its conditions on tap, so the condition is always
/// visible next to the promise.
enum HomeTrustFact: String, CaseIterable, Identifiable, Sendable {
    /// "Lieferung per E-Mail in Minuten".
    case emailDelivery
    /// "Apple Pay, Kreditkarte, Klarna". These are the only payment methods of the store.
    case paymentMethods
    /// "100 Tage Geld-zurück*". Tapping it presents the conditions.
    case moneyBack
    /// "Support Mo. bis So., 06:00 bis 23:00 Uhr".
    case supportHours

    /// The marker that links the money-back promise to its condition, in the tile and in the
    /// footnote below the strip.
    static let conditionMarker = "*"

    /// Stable identity, also used as the `KXTrustItem` id.
    var id: String {
        rawValue
    }

    /// SF Symbol shown in the tile's gold ring.
    var systemImage: String {
        switch self {
        case .emailDelivery: "envelope"
        case .paymentMethods: "creditcard"
        case .moneyBack: "arrow.uturn.backward"
        case .supportHours: "clock"
        }
    }

    /// Whether tapping the fact presents the money-back conditions.
    var revealsConditions: Bool {
        self == .moneyBack
    }

    /// The marker appended to the text of a fact with a condition, `nil` for the others.
    var footnoteMarker: String? {
        revealsConditions ? Self.conditionMarker : nil
    }

    /// The text in the user's language.
    var text: String {
        text(in: HomeResources.bundle)
    }

    /// The text resolved against `bundle`: the module bundle, or one of its `.lproj` folders.
    func text(in bundle: Bundle) -> String {
        String(localized: textKey, bundle: bundle)
    }

    private var textKey: String.LocalizationValue {
        switch self {
        case .emailDelivery: "home.trust.delivery"
        case .paymentMethods: "home.trust.payment"
        case .moneyBack: "home.trust.moneyback"
        case .supportHours: "home.trust.support"
        }
    }
}

// MARK: - MoneyBackClause

/// The conditions of the "100 Tage Geld-zurück" promise, exactly as defined by the business
/// (PROMPT.md section 2), in the order they are shown.
enum MoneyBackClause: String, CaseIterable, Identifiable, Sendable {
    /// The promise applies only to activated license keys and to physical goods.
    case scope
    /// Delivered but not activated keys are not refunded voluntarily (the key could still be used).
    case unactivatedKeys
    /// Statutory warranty rights, for example for a defective key, remain untouched.
    case statutoryRights

    /// Stable identity for `ForEach`.
    var id: String {
        rawValue
    }

    /// Decorative SF Symbol leading the clause.
    var systemImage: String {
        switch self {
        case .scope: "checkmark.circle"
        case .unactivatedKeys: "exclamationmark.circle"
        case .statutoryRights: "building.columns"
        }
    }

    /// The clause in the user's language.
    var text: String {
        text(in: HomeResources.bundle)
    }

    /// The clause resolved against `bundle`: the module bundle, or one of its `.lproj` folders.
    func text(in bundle: Bundle) -> String {
        String(localized: textKey, bundle: bundle)
    }

    private var textKey: String.LocalizationValue {
        switch self {
        case .scope: "home.moneyback.clause.scope"
        case .unactivatedKeys: "home.moneyback.clause.unactivated"
        case .statutoryRights: "home.moneyback.clause.statutory"
        }
    }
}

// MARK: - SupportChannel

/// The support channels of KARINEX (PROMPT.md section 2): WhatsApp, e-mail and live chat.
/// There is no phone support.
///
/// In Phase 0 the channels are presented as information only. The actions (WhatsApp deep link,
/// mail composer, chat link) arrive with the support hub in Phase 2, when the WhatsApp number and
/// the chat link are served by the backend configuration.
enum SupportChannel: String, CaseIterable, Identifiable, Sendable {
    /// WhatsApp messages.
    case whatsApp
    /// E-mail to the customer service address.
    case email
    /// Live chat on the store.
    case liveChat

    /// The customer service address (PROMPT.md section 2). An address, not copy, so it is not
    /// part of the String Catalog.
    static let emailAddress = "kundenservice@karinex.de"

    /// Stable identity for `ForEach`.
    var id: String {
        rawValue
    }

    /// Decorative SF Symbol shown in the channel's gold ring.
    var systemImage: String {
        switch self {
        case .whatsApp: "message"
        case .email: "envelope"
        case .liveChat: "bubble.left.and.bubble.right"
        }
    }

    /// Extra information shown below the channel name: the address for e-mail, `nil` otherwise.
    var detail: String? {
        switch self {
        case .email: Self.emailAddress
        case .whatsApp, .liveChat: nil
        }
    }

    /// The channel name in the user's language.
    var name: String {
        name(in: HomeResources.bundle)
    }

    /// The channel name resolved against `bundle`: the module bundle, or one of its `.lproj`
    /// folders.
    func name(in bundle: Bundle) -> String {
        String(localized: nameKey, bundle: bundle)
    }

    private var nameKey: String.LocalizationValue {
        switch self {
        case .whatsApp: "home.support.channel.whatsapp"
        case .email: "home.support.channel.email"
        case .liveChat: "home.support.channel.livechat"
        }
    }
}
